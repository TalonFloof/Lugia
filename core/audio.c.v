module core

import sync
import sokol.audio

#include "@VROOT/core/blip_buf.c"

[heap]
struct C.blip_t {}

fn C.blip_new(int) &C.blip_t

fn C.blip_add_delta(&C.blip_t, u32, int)

fn C.blip_read_samples(&C.blip_t, &i16, int, bool) int

fn C.blip_end_frame(&C.blip_t, u32)

fn C.blip_samples_avail(&C.blip_t) int

fn C.blip_clear(&C.blip_t)

fn C.blip_set_rates(&C.blip_t, f64, f64)

const (
	wave_pattern = [[i32(-1),-1,-1,-1,1,-1,-1,-1]!,[i32(-1),-1,-1,-1,1,1,-1,-1]!,[i32(-1),-1,1,1,1,1,-1,-1]!,[i32(1),1,1,1,-1,-1,1,1]!]!
	clocks_per_second  = u32(clock_frequency)
	clocks_per_frame = u32(clocks_per_second / 512)
	sweep_delay_zero_period = u8(8)

	wave_initial_delay = u32(4)
)

struct VolumeEnvelope {
pub mut:
	period u8
    goes_up bool
    delay u8
    initial_volume u8
    volume u8
}

pub fn new_volume_envelope() &VolumeEnvelope {
	return &VolumeEnvelope {
        period: 0
        goes_up: false
        delay: 0
        initial_volume: 0
        volume: 0
    }
}

pub fn (self &VolumeEnvelope) get(a u16) u8 {
	if (a == 0xFF12) || (a == 0xFF17) || (a == 0xFF2) {
		return u8(((self.initial_volume & 0xF) << 4) | (if self.goes_up { 0x08 } else { 0 }) | (self.period & 0x7))
	} else {
		return 0
	}
}

pub fn (mut self VolumeEnvelope) set(a u16, v u8) {
	if (a == 0xFF12) || (a == 0xFF17) || (a == 0xFF21) {
		self.period = v & 0x7
        self.goes_up = v & 0x8 == 0x8
        self.initial_volume = v >> 4
        self.volume = self.initial_volume
	} else if ((a == 0xFF14) || (a == 0xFF19) || (a == 0xFF23)) && (v & 0x80 == 0x80) {
		self.delay = self.period
        self.volume = self.initial_volume
	}
}

pub fn (mut self VolumeEnvelope) tick() {
	if self.delay > 1 {
		self.delay -= 1
	} else if self.delay == 1 {
		self.delay = self.period
		if self.goes_up && self.volume < 15 {
			self.volume += 1
		} else if !self.goes_up && self.volume > 0 {
			self.volume -= 1
		}
	}
}

struct LengthCounter {
pub mut:
    enabled bool
    value u16
    max u16
}

pub fn new_length_counter(max u16) &LengthCounter {
	return &LengthCounter {
        enabled: false
        value: 0
        max: max
    }
}

fn (self &LengthCounter) is_active() bool {
	return self.value > 0
}

fn (self &LengthCounter) extra_step(frame_step u8) bool {
	return frame_step % 2 == 1
}

fn (mut self LengthCounter) enable(enable bool, frame_step u8) {
	was_enabled := self.enabled
	self.enabled = enable
	if !was_enabled && self.extra_step(frame_step) {
		self.step()
	}
}

fn (mut self LengthCounter) set(minus_value u8) {
	self.value = self.max - minus_value as u16
}

fn (mut self LengthCounter) trigger(frame_step u8) {
	if self.value == 0 {
		self.value = self.max
		if self.extra_step(frame_step) {
			self.step()
		}
	}
}

fn (mut self LengthCounter) step() {
	if self.enabled && self.value > 0 {
		self.value -= 1
	}
}

struct SquareChannel {
pub mut:
    active bool
    dac_enabled bool
    duty u8
    phase u8
    length &LengthCounter
    frequency u16
    period u32
    last_amp i32
    delay u32
    has_sweep bool
    sweep_enabled bool
    sweep_frequency u16
    sweep_delay u8
    sweep_period u8
    sweep_shift u8
    sweep_negate bool
    sweep_did_negate bool
    volume_envelope &VolumeEnvelope
    blip &C.blip_t
}

fn new_square_channel(blip &C.blip_t, with_sweep bool) &SquareChannel {
	return &SquareChannel {
		active: false
		dac_enabled: false
		duty: 1
		phase: 1
		length: new_length_counter(64)
		frequency: 0
		period: 2048
		last_amp: 0
		delay: 0
		has_sweep: with_sweep
		sweep_enabled: false
		sweep_frequency: 0
		sweep_delay: 0
		sweep_period: 0
		sweep_shift: 0
		sweep_negate: false
		sweep_did_negate: false
		volume_envelope: new_volume_envelope()
		blip: blip
	}
}

fn (self &SquareChannel) on() bool {
    return self.active
}

fn (self &SquareChannel) get(a u16) u8 {
    match true {
		a == 0xFF10 {
			return u8(0x80 | ((self.sweep_period & 0x7) << 4) | (if self.sweep_negate { 0x8 } else { 0 }) | (self.sweep_shift & 0x7))
		}
		a == 0xFF11 || a == 0xFF16 {
			return ((self.duty & 3) << 6) | 0x3F
		}
		a == 0xFF12 || a == 0xFF17 {
			return self.volume_envelope.get(a)
		}
		a == 0xFF13 || a == 0xFF18 {
			return 0xff
		}
		a == 0xFF14 || a == 0xFF19 {
			return u8(0x80 | (if self.length.enabled { 0x40 } else { 0 }) | 0x3F)
		}
		else {
			return 0
		}
	}
}

fn (mut self SquareChannel) set(a u16, v u8, frame_step u8) {
	match true {
		a == 0xFF10 {
			self.sweep_period = (v >> 4) & 0x7
			self.sweep_shift = v & 0x7
			old_sweep_negate := self.sweep_negate
			self.sweep_negate = v & 0x8 == 0x8
			if old_sweep_negate && !self.sweep_negate && self.sweep_did_negate {
				self.active = false
			}
			self.sweep_did_negate = false
		}
		a == 0xFF11 || a == 0xFF16 {
			self.duty = v >> 6
			self.length.set(v & 0x3F)
		}
		a == 0xFF12 || a == 0xFF17 {
			self.dac_enabled = v & 0xF8 != 0
			self.active = self.active && self.dac_enabled
		}
		a == 0xFF13 || a == 0xFF18 {
			self.frequency = (self.frequency & 0x0700) | u16(v)
			self.calculate_period()
		}
		a == 0xFF14 || a == 0xFF19 {
			self.frequency = (self.frequency & 0x00FF) | (u16(v & 0b0000_0111) << 8)
			self.calculate_period()

			self.length.enable(v & 0x40 == 0x40, frame_step)
			self.active = self.active && self.length.is_active()

			if v & 0x80 == 0x80 {
				if self.dac_enabled {
					self.active = true
				}

				self.length.trigger(frame_step)

				if self.has_sweep {
					self.sweep_frequency = self.frequency
					self.sweep_delay = if self.sweep_period != 0 { self.sweep_period } else { sweep_delay_zero_period }

					self.sweep_enabled = self.sweep_period > 0 || self.sweep_shift > 0
					if self.sweep_shift > 0 {
						self.sweep_calculate_frequency()
					}
				}
			}
		}
		else {}
	}
	self.volume_envelope.set(a, v)
}

fn (mut self SquareChannel) calculate_period() {
	if self.frequency > 2047 { self.period = 0 } else { self.period = (2048 - u32(self.frequency)) * 4 }
}

fn (mut self SquareChannel) run(start_time u32, end_time u32) {
	if !self.active || self.period == 0 {
		if self.last_amp != 0 {
			C.blip_add_delta(self.blip, start_time, -self.last_amp)
			self.last_amp = 0
			self.delay = 0
		}
	}
	else {
		mut time := start_time + self.delay
		pattern := wave_pattern[self.duty]
		vol := i32(self.volume_envelope.volume)

		for time < end_time {
			amp := vol * pattern[self.phase]
			if amp != self.last_amp {
				C.blip_add_delta(self.blip, time, amp - self.last_amp)
				self.last_amp = amp
			}
			time += self.period
			self.phase = (self.phase + 1) % 8
		}

		self.delay = time - end_time
	}
}

fn (mut self SquareChannel) step_length() {
	self.length.step()
	self.active = self.active && self.length.is_active()
}

fn (mut self SquareChannel) sweep_calculate_frequency() u16 {
	offset := self.sweep_frequency >> self.sweep_shift

	newfreq := if self.sweep_negate {
		self.sweep_did_negate = true
		u16(self.sweep_frequency - offset)
	}
	else {
		u16(self.sweep_frequency + offset)
	}

	if newfreq > 2047 {
		self.active = false
	}
	return newfreq
}

fn (mut self SquareChannel) step_sweep() {
	if self.sweep_delay > 1 {
		self.sweep_delay -= 1
	}
	else {
		if self.sweep_period == 0 {
			self.sweep_delay = sweep_delay_zero_period
		}
		else {
			self.sweep_delay = self.sweep_period
			if self.sweep_enabled {
				newfreq := self.sweep_calculate_frequency()
				if newfreq <= 2047 {
					if self.sweep_shift != 0 {
						self.sweep_frequency = newfreq
						self.frequency = newfreq
						self.calculate_period()
					}
					self.sweep_calculate_frequency()
				}
			}
		}
	}
}

struct WaveChannel {
pub mut:
    active bool
    dac_enabled bool
    length &LengthCounter
    frequency u16
    period u32
    last_amp i32
    delay u32
    volume_shift u8
    waveram [16]u8
    current_wave u8
    dmg_mode bool
    sample_recently_accessed bool
    blip &C.blip_t
}

fn new_wave_channel(blip &C.blip_t, dmg_mode bool) &WaveChannel {
	return &WaveChannel {
		active: false
		dac_enabled: false
		length: new_length_counter(256)
		frequency: 0
		period: 2048
		last_amp: 0
		delay: 0
		volume_shift: 0
		waveram: [16]u8{init: 0}
		current_wave: 0
		dmg_mode: dmg_mode
		sample_recently_accessed: false
		blip: blip
	}
}

fn (self &WaveChannel) get(a u16) u8 {
	match a {
		0xFF1A {
			return u8((if self.dac_enabled { 0x80 } else { 0 }) | 0x7F)
		}
		0xFF1B { return 0xFF }
		0xFF1C {
			return u8(0x80 | ((self.volume_shift & 0b11) << 5) | 0x1F)
		}
		0xFF1D { return 0xFF }
		0xFF1E {
			return u8(0x80 | if self.length.enabled { 0x40 } else { 0 } | 0x3F)
		}
		else {
			if a >= 0xff30 && a <= 0xff3f {
				if !self.active {
					return self.waveram[a - 0xFF30]
				} else {
					if !self.dmg_mode || self.sample_recently_accessed {
						return self.waveram[usize(self.current_wave) >> 1]
					} else {
						return 0xFF
					}
				}
			}
			return 0
		}
	}
}

fn (mut self WaveChannel) set(a u16, v u8, frame_step u8) {
	match a {
		0xFF1A {
			self.dac_enabled = (v & 0x80) == 0x80
            self.active = self.active && self.dac_enabled
		}
		0xFF1B { self.length.set(v) }
		0xFF1C {
			self.volume_shift = (v >> 5) & 0b11
		}
		0xFF1D {
			self.frequency = (self.frequency & 0x0700) | u16(v)
            self.calculate_period()
		}
		0xFF1E {
			self.frequency = (self.frequency & 0x00FF) | (u16(v & 0b111) << 8)
			self.calculate_period()

			self.length.enable(v & 0x40 == 0x40, frame_step)
			self.active = self.active && self.length.is_active()

			if v & 0x80 == 0x80 {
				self.dmg_maybe_corrupt_waveram()

				self.length.trigger(frame_step)

				self.current_wave = 0
				self.delay = self.period + wave_initial_delay

				if self.dac_enabled {
					self.active = true
				}
			}
		}
		else {
			if a >= 0xff30 && a <= 0xff3f {
				if !self.active {
                    self.waveram[usize(a) - 0xFF30] = v
                } else {
                    if !self.dmg_mode || self.sample_recently_accessed {
                        self.waveram[usize(self.current_wave) >> 1] = v
                    }
                }
			}
		}
	}
}

fn (mut self WaveChannel) calculate_period() {
	if self.frequency > 2048 { self.period = 0 } else { self.period = (2048 - u32(self.frequency)) * 2 }
}

fn (self &WaveChannel) on() bool {
    return self.active
}

fn (mut self WaveChannel) run(start_time u32, end_time u32) {
	self.sample_recently_accessed = false
	if !self.active || self.period == 0 {
		if self.last_amp != 0 {
			C.blip_add_delta(self.blip, start_time, -self.last_amp)
			self.last_amp = 0
			self.delay = 0
		}
	} else {
		mut time := start_time + self.delay
		volshift := match self.volume_shift {
			0 { 4 + 2 }
			1 { 0 }
			2 { 1 }
			3 { 2 }
			else {panic("")}
		}

		for time < end_time {
			wavebyte := self.waveram[usize(self.current_wave) >> 1]
			sample := if self.current_wave % 2 == 0 { wavebyte >> 4 } else { wavebyte & 0xF }

			 amp := i32((sample << 2) >> volshift)

			if amp != self.last_amp {
				C.blip_add_delta(self.blip, time, amp - self.last_amp)
				self.last_amp = amp
			}

			if time >= end_time - 2 {
				self.sample_recently_accessed = true
			}
			time += self.period
			self.current_wave = (self.current_wave + 1) % 32
		}

		self.delay = time - end_time
	}
}

fn (mut self WaveChannel) step_length() {
	self.length.step()
	self.active = self.active && self.length.is_active()
}

fn (mut self WaveChannel) dmg_maybe_corrupt_waveram() {
	if !self.dmg_mode || !self.active || self.delay != 0 {
		return
	}

	byteindex := usize((self.current_wave + 1) % 32) >> 1

	if byteindex < 4 {
		self.waveram[0] = self.waveram[byteindex]
	}
	else {
		blockstart := byteindex & 0b1100
		self.waveram[0] = self.waveram[blockstart]
		self.waveram[1] = self.waveram[blockstart + 1]
		self.waveram[2] = self.waveram[blockstart + 2]
		self.waveram[3] = self.waveram[blockstart + 3]
	}	
}

struct NoiseChannel {
pub mut:
    active bool
    dac_enabled bool
    reg_ff22 u8
    length &LengthCounter
    volume_envelope &VolumeEnvelope
    period u32
    shift_width u8
    state u16
    delay u32
    last_amp i32
    blip &C.blip_t
}

pub fn new_noise_channel(blip &C.blip_t) &NoiseChannel {
	return &NoiseChannel {
		active: false
		dac_enabled: false
		reg_ff22: 0
		length: new_length_counter(64)
		volume_envelope: new_volume_envelope()
		period: 2048
		shift_width: 14
		state: 1
		delay: 0
		last_amp: 0
		blip: blip
	}
}

fn (self &NoiseChannel) get(a u16) u8 {
	match a {
		0xFF20 { return 0xFF }
		0xFF21 { return self.volume_envelope.get(a) }
		0xFF22 {
			return self.reg_ff22
		}
		0xFF23 {
			return u8(0x80 | if self.length.enabled { 0x40 } else { 0 } | 0x3F)
		}
		else { return 0 }
	}
}

fn (mut self NoiseChannel) set(a u16, v u8, frame_step u8) {
	match a {
		0xFF20 { self.length.set(v & 0x3F) }
		0xFF21 {
			self.dac_enabled = v & 0xF8 != 0
			self.active = self.active && self.dac_enabled
		}
		0xFF22 {
			self.reg_ff22 = v
			self.shift_width = u8(if v & 8 == 8 { 6 } else { 14 })
			freq_div := match v & 7 {
				0 { 8 }
				else { (u32(v & 7) + 1) * 16 }
			}
			self.period = u32(freq_div) << (v >> 4)
		}
		0xFF23 {
			self.length.enable(v & 0x40 == 0x40, frame_step)
			self.active = self.length.is_active()

			if v & 0x80 == 0x80 {
				self.length.trigger(frame_step)

				self.state = 0xFF
				self.delay = 0

				if self.dac_enabled {
					self.active = true
				}
			}
		}
		else {}
	}
	self.volume_envelope.set(a, v)
}

fn (self &NoiseChannel) on() bool {
    return self.active
}

fn (mut self NoiseChannel) run(start_time u32, end_time u32) {
	if !self.active {
		if self.last_amp != 0 {
			C.blip_add_delta(self.blip, start_time, -self.last_amp)
			self.last_amp = 0
			self.delay = 0
		}
	} else {
		mut time := start_time + self.delay
		for time < end_time {
			oldstate := self.state
			self.state <<= 1
			bit := ((oldstate >> self.shift_width) ^ (self.state >> self.shift_width)) & 1
			self.state |= bit

			amp := match (oldstate >> self.shift_width) & 1 {
				0 { -i32(self.volume_envelope.volume) }
				else { i32(self.volume_envelope.volume) }
			}

			if self.last_amp != amp {
				C.blip_add_delta(self.blip, time, amp - self.last_amp)
				self.last_amp = amp
			}

			time += self.period
		}
		self.delay = time - end_time
	}
}

fn (mut self NoiseChannel) step_length() {
	self.length.step()
	self.active = self.active && self.length.is_active()
}

pub struct FIFOQueue {
pub mut:
	head int
	tail int
	data_l [44100]f32
	data_r [44100]f32
}

pub struct APU {
pub mut:
	buffer FIFOQueue
    on bool
    time u32
    prev_time u32
    next_time u32
    frame_step u8
    output_period u32
    channel1 &SquareChannel
    channel2 &SquareChannel
    channel3 &WaveChannel
    channel4 &NoiseChannel
    volume_left u8
    volume_right u8
    reg_vin_to_so u8
    reg_ff25 u8
    need_sync bool
    dmg_mode bool
}

pub fn new_apu(dmg_mode bool) &APU {
	blipbuf1 := create_blipbuf(44100)
	blipbuf2 := create_blipbuf(44100)
	blipbuf3 := create_blipbuf(44100)
	blipbuf4 := create_blipbuf(44100)

	output_period := (u64(1024) * u64(clock_frequency)) / u64(44100)

	return &APU {
		buffer: FIFOQueue {
			head: 0
			tail: 0
			data_l: [44100]f32{init: 0}
			data_r: [44100]f32{init: 0}
		}
		on: false
		time: 0
		prev_time: 0
		next_time: clocks_per_frame
		frame_step: 0
		output_period: u32(output_period)
		channel1: new_square_channel(blipbuf1, true)
		channel2: new_square_channel(blipbuf2, false)
		channel3: new_wave_channel(blipbuf3, dmg_mode)
		channel4: new_noise_channel(blipbuf4)
		volume_left: 7
		volume_right: 7
		reg_vin_to_so: 0x00
		reg_ff25: 0x00
		dmg_mode: dmg_mode
	}
}

pub fn (self &APU) get(a u16) u8 {
	v := match a {
		0xFF10...0xFF14 { self.channel1.get(a) }
		0xFF16...0xFF19 { self.channel2.get(a) }
		0xFF1A...0xFF1E { self.channel3.get(a) }
		0xFF20...0xFF23 { self.channel4.get(a) }
		0xFF24 { ((self.volume_right & 7) << 4) | (self.volume_left & 7) | self.reg_vin_to_so }
		0xFF25 { self.reg_ff25 }
		0xFF26 {
			is_on := if self.on { 0x80 } else { 0x00 }
			(is_on | 0x70 | (if self.channel4.on() { 0x8 } else { 0x0 }) | (if self.channel3.on() { 0x4 } else { 0x0 }) | (if self.channel2.on() { 0x2 } else { 0x0 }) | (if self.channel1.on() { 0x1 } else { 0x0 }))
		}
		0xFF30...0xFF3F { self.channel3.get(a) }
		else { 0xFF }
	}
	return v
}

pub fn (mut self APU) set(a u16, v u8) {
	if !self.on {
		if self.dmg_mode {
			match a {
				0xFF11 { self.channel1.set(a, v & 0x3F, self.frame_step) }
				0xFF16 { self.channel2.set(a, v & 0x3F, self.frame_step) }
				0xFF1B { self.channel3.set(a, v, self.frame_step) }
				0xFF20 { self.channel4.set(a, v & 0x3F, self.frame_step) }
				else {}
			}
		}
		if a != 0xFF26 {
			return
		}
	}
	self.run()
	match a {
		0xFF10 ... 0xFF14 { self.channel1.set(a, v, self.frame_step) }
		0xFF16 ... 0xFF19 { self.channel2.set(a, v, self.frame_step) }
		0xFF1A ... 0xFF1E { self.channel3.set(a, v, self.frame_step) }
		0xFF20 ... 0xFF23 { self.channel4.set(a, v, self.frame_step) }
		0xFF24 {
			self.volume_left = v & 0x7
			self.volume_right = (v >> 4) & 0x7
			self.reg_vin_to_so = v & 0x88
		}
		0xFF25 { self.reg_ff25 = v }
		0xFF26 {
			turn_on := v & 0x80 == 0x80
			if self.on && turn_on == false {
				for i in 0xFF10..0xFF26 {
					self.set(i, 0)
				}
			}
			if !self.on && turn_on {
				self.frame_step = 0
			}
			self.on = turn_on
		}
		0xFF30 ... 0xFF3F { self.channel3.set(a, v, self.frame_step) }
		else {}
	}
}

pub fn (mut self APU) next(cycles u32) {
	if !self.on { return }

	self.time += cycles

	if self.time >= self.output_period {
		self.do_output()
	}
}

pub fn (mut self APU) sync() {
	self.need_sync = true
}

fn (mut self APU) do_output() {
	self.run()
	C.blip_end_frame(self.channel1.blip,self.time)
	C.blip_end_frame(self.channel2.blip,self.time)
	C.blip_end_frame(self.channel3.blip,self.time)
	C.blip_end_frame(self.channel4.blip,self.time)
	self.next_time -= self.time
	self.time = 0
	self.prev_time = 0

	if !self.need_sync {
		self.need_sync = false
		self.mix_buffers()
	} else {
		self.clear_buffers()
	}
}

fn (mut self APU) run() {
	for self.next_time <= self.time {
		self.channel1.run(self.prev_time, self.next_time)
		self.channel2.run(self.prev_time, self.next_time)
		self.channel3.run(self.prev_time, self.next_time)
		self.channel4.run(self.prev_time, self.next_time)

		if self.frame_step % 2 == 0 {
			self.channel1.step_length()
			self.channel2.step_length()
			self.channel3.step_length()
			self.channel4.step_length()
		}
		if self.frame_step % 4 == 2 {
			self.channel1.step_sweep()
		}
		if self.frame_step == 7 {
			self.channel1.volume_envelope.tick()
			self.channel2.volume_envelope.tick()
			self.channel4.volume_envelope.tick()
		}

		self.frame_step = (self.frame_step + 1) % 8

		self.prev_time = self.next_time
		self.next_time += clocks_per_frame
	}

	if self.prev_time != self.time {
		self.channel1.run(self.prev_time, self.time)
		self.channel2.run(self.prev_time, self.time)
		self.channel3.run(self.prev_time, self.time)
		self.channel4.run(self.prev_time, self.time)

		self.prev_time = self.time
	}
}

fn (mut self APU) mix_buffers() {
	sample_count := C.blip_samples_avail(self.channel1.blip)

	mut outputted := 0

	left_vol := (f32(self.volume_left) / 7.0) * (1.0 / 15.0) * 0.25
	right_vol := (f32(self.volume_right) / 7.0) * (1.0 / 15.0) * 0.25

	for outputted < sample_count {
		mut buf_l := []f32{len: 1024, init: 0}
		mut buf_r := []f32{len: 1024, init: 0}
		mut buf := []i16{len: 1024, init: 0}

		count1 := C.blip_read_samples(self.channel1.blip, buf.data, buf.len, false)
		for i, v in buf[..count1] {
			if self.reg_ff25 & 0x01 == 0x01 {
				buf_l[i] += f32(v) * left_vol
			}
			if self.reg_ff25 & 0x10 == 0x10 {
				buf_r[i] += f32(v) * right_vol
			}
		}

		count2 := C.blip_read_samples(self.channel2.blip, buf.data, buf.len, false)
		for i, v in buf[..count2] {
			if self.reg_ff25 & 0x02 == 0x02 {
				buf_l[i] += f32(v) * left_vol
			}
			if self.reg_ff25 & 0x20 == 0x20 {
				buf_r[i] += f32(v) * right_vol
			}
		}

		count3 := C.blip_read_samples(self.channel3.blip, buf.data, buf.len, false)
		for i, v in buf[..count3] {
			if self.reg_ff25 & 0x04 == 0x04 {
				buf_l[i] += f32(v / 4) * left_vol
			}
			if self.reg_ff25 & 0x40 == 0x40 {
				buf_r[i] += f32(v / 4) * right_vol
			}
		}

		count4 := C.blip_read_samples(self.channel4.blip, buf.data, buf.len, false)
		for i, v in buf[..count4] {
			if self.reg_ff25 & 0x08 == 0x08 {
				buf_l[i] += f32(v) * left_vol
			}
			if self.reg_ff25 & 0x80 == 0x80 {
				buf_r[i] += f32(v) * right_vol
			}
		}

		for i in 0..count1 {
			if ((self.buffer.head + 1) % 44100) != self.buffer.tail {
				self.buffer.data_l[self.buffer.head] = buf_l[i]
				self.buffer.data_r[self.buffer.head] = buf_r[i]
				self.buffer.head = (self.buffer.head + 1) % 44100
			} else {
				break
			}
		}

		outputted += count1
	}
}

fn (mut self APU) clear_buffers() {
	C.blip_clear(self.channel1.blip)
	C.blip_clear(self.channel2.blip)
	C.blip_clear(self.channel3.blip)
	C.blip_clear(self.channel4.blip)
}

fn create_blipbuf(samples_rate u32) &C.blip_t {
    mut blipbuf := C.blip_new(samples_rate)
    C.blip_set_rates(blipbuf, f64(clocks_per_second), f64(samples_rate))
    return blipbuf
}