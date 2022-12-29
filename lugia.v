module main

import core

import gg
import gx
import os
import sdl

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
    lugia.fb = lugia.gg.new_streaming_image(160,144,4,gg.StreamingImageConfig { min_filter: .nearest, mag_filter: .nearest })
    spawn cpu_loop(mut lugia)
    lugia.first_run = false
  } else {
    lugia.gg.begin()
    lugia.gg.update_pixel_data(lugia.fb,lugia.fb_dat.data)
    lugia.gg.draw_image(0,0,160*3,144*3,lugia.gg.get_cached_image_by_idx(lugia.fb))
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
  .escape {
    lugia.cpu.cpu.mem.cart.save()
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

fn main() {
  mut lugia := &Lugia {
    fb_dat: []u8{len: 160*144*4, init: 0xff}
  }
  lugia.gg = gg.new_context(
    bg_color: gx.rgb(0,0,0)
    width: 160*3
    height: 144*3
    user_data: lugia
    frame_fn: lugia_frame
    keydown_fn: lugia_keydown
    keyup_fn: lugia_keyup
    window_title: "Lugia"
    create_window: true
  )
  if sdl.init(sdl.init_audio) < 0 {
    error_msg := unsafe { cstring_to_vstring(sdl.get_error()) }
    show_alert("Couldn't initialize SDL: ${error_msg}")
  }

  desired := sdl.AudioSpec {
    freq: 44100
    format: sdl.audio_f32sys
    samples: 44100
    channels: 1
    silence: 0
    callback: unsafe { nil }
    userdata: unsafe { nil }
  }
  mut optained := sdl.AudioSpec {}

  if sdl.open_audio(&desired, &optained) < 0 {
    error_msg := unsafe { cstring_to_vstring(sdl.get_error()) }
    show_alert("Couldn't initialize SDL audio device: ${error_msg}")
  }
  if optained.format != sdl.audio_f32sys {
    show_alert("SDL doesn't allow for f32 audio samples!")
  }
  if optained.freq != 44100 {
    show_alert("SDL doesn't allow for a 44100Hz Sample Rate!")
  }
  if optained.samples != 44100 {
    show_alert("SDL doesn't allow for 44100 Samples!")
  }

  sdl.pause_audio(1)
  sdl.pause_audio_device(1,1)

  lugia.run()
  lugia.cpu.cpu.mem.cart.save()
}

