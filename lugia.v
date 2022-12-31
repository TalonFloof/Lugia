module main

import core

import gg
import gx
import os
import sokol.audio

[heap]
pub struct Lugia {
mut:
  gg &gg.Context = unsafe { nil }
  fb int
  fb_dat []u8
  cpu &core.RealTimePerfCPU = unsafe { nil }
  first_run bool = true
}

fn (mut l Lugia) run() {
  l.gg.run()
}

fn (mut l Lugia) is_frame_ready() bool {
  result := l.cpu.cpu.mem.gpu.v_blank
  l.cpu.cpu.mem.gpu.v_blank = false
  return result
}

fn lugia_frame(mut lugia Lugia) {
  if lugia.first_run {
    lugia.gg.begin()
    lugia.gg.end()
    if os.args.len == 1 {
      lugia.cpu = core.new_rtpcpu(open_file())
    } else {
      lugia.cpu = core.new_rtpcpu(os.args[1])
    }
    audio.setup(&C.saudio_desc {
      sample_rate: 44100
      num_channels: 2
      buffer_frames: 2048
      stream_userdata_cb: stream_audio
      user_data: lugia
    })
    if audio.channels() == 1 {
      show_alert("Sokol doesn't allow for stereo audio!")
    }
    lugia.fb = lugia.gg.new_streaming_image(160,144,4,gg.StreamingImageConfig { min_filter: .nearest, mag_filter: .nearest })
    spawn cpu_loop(mut lugia)

    lugia.first_run = false
  } else {
    lugia.gg.begin()
    lugia.gg.update_pixel_data(lugia.fb,lugia.fb_dat.data)
    lugia.gg.draw_image(0,0,160*4,144*4,lugia.gg.get_cached_image_by_idx(lugia.fb))
    lugia.gg.end()
  }
}

fn lugia_keydown(c gg.KeyCode, m gg.Modifier, mut lugia Lugia) {
  match c {
    .up {
      lugia.cpu.cpu.mem.joypad.keydown(.up)
    }
    .down {
      lugia.cpu.cpu.mem.joypad.keydown(.down)
    }
    .left {
      lugia.cpu.cpu.mem.joypad.keydown(.left)
    }
    .right {
      lugia.cpu.cpu.mem.joypad.keydown(.right)
    }
    .z {
      lugia.cpu.cpu.mem.joypad.keydown(.b)
    }
    .x {
      lugia.cpu.cpu.mem.joypad.keydown(.a)
    }
    .enter {
      lugia.cpu.cpu.mem.joypad.keydown(.start)
    }
    .right_shift {
      lugia.cpu.cpu.mem.joypad.keydown(.select_)
    }
    .left_shift {
      lugia.cpu.turbo = !lugia.cpu.turbo
      lugia.cpu.cpu.mem.apu.buffer.tail = lugia.cpu.cpu.mem.apu.buffer.head
    }
    else {}
  }
}

fn lugia_keyup(c gg.KeyCode, m gg.Modifier, mut lugia Lugia) {
  match c {
    .up {
      lugia.cpu.cpu.mem.joypad.keyup(.up)
    }
    .down {
      lugia.cpu.cpu.mem.joypad.keyup(.down)
    }
    .left {
      lugia.cpu.cpu.mem.joypad.keyup(.left)
    }
    .right {
      lugia.cpu.cpu.mem.joypad.keyup(.right)
    }
    .z {
      lugia.cpu.cpu.mem.joypad.keyup(.b)
    }
    .x {
      lugia.cpu.cpu.mem.joypad.keyup(.a)
    }
    .enter {
      lugia.cpu.cpu.mem.joypad.keyup(.start)
    }
    .right_shift {
      lugia.cpu.cpu.mem.joypad.keyup(.select_)
    }
    else {}
  }
}

fn cpu_loop(mut lugia &Lugia) {
  for {
    if lugia.cpu.cpu.pc == 0x10 {
      lugia.cpu.cpu.mem.switch_speed()
    }
    cycles := lugia.cpu.next()
    lugia.cpu.cpu.mem.next(cycles)

    if lugia.is_frame_ready() {
      mut i := usize(0)
      for l in lugia.cpu.cpu.mem.gpu.data {
        for w in l {
          lugia.fb_dat[(i*4)+0] = w[0]
          lugia.fb_dat[(i*4)+1] = w[1]
          lugia.fb_dat[(i*4)+2] = w[2]
          lugia.fb_dat[(i*4)+3] = 0xff
          i += 1
        }
      }
    }

    if !lugia.cpu.flip() {
      continue
    }
  }
}

fn stream_audio(mut buffer &f32, num_frames int, num_channels int, mut lugia Lugia) {
  if lugia.cpu != unsafe { nil } {
    unsafe { vmemset(buffer, 0, u32(num_frames*num_channels)*sizeof(f32)) }
    for i := 0; i < num_frames*num_channels; i += 2 {
	    if lugia.cpu.cpu.mem.apu.buffer.tail == lugia.cpu.cpu.mem.apu.buffer.head {
    	  break
  	  }
	    buffer[i] = lugia.cpu.cpu.mem.apu.buffer.data_l[lugia.cpu.cpu.mem.apu.buffer.tail]
      buffer[i+1] = lugia.cpu.cpu.mem.apu.buffer.data_r[lugia.cpu.cpu.mem.apu.buffer.tail]
	    lugia.cpu.cpu.mem.apu.buffer.tail = (lugia.cpu.cpu.mem.apu.buffer.tail + 1) % 44100
	  }
  }
}

fn lugia_exit(mut lugia Lugia) {
  lugia.cpu.cpu.mem.cart.save()
}

fn main() {
  mut lugia := &Lugia {
    fb_dat: []u8{len: 160*144*4, init: 0xff}
  }
  lugia.gg = gg.new_context(
    bg_color: gx.rgb(0,0,0)
    width: 160*4
    height: 144*4
    user_data: lugia
    frame_fn: lugia_frame
    keydown_fn: lugia_keydown
    keyup_fn: lugia_keyup
    cleanup_fn: lugia_exit
    window_title: "Lugia"
    create_window: true
  )

  lugia.run()
}

