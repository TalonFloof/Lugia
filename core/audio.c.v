module core

import sdl

#include "@VROOT/core/blip_buf.c"

[heap]
struct C.blip_t {}

fn C.blip_new(int) &C.blip_t

fn C.blip_add_delta(&C.blip_t, u32, int)

fn C.blip_end_frame(&C.blip_t, u32)

fn C.blip_samples_avail(&C.blip_t) int

fn C.blip_read_samples(&C.blip_t, &i16, int, bool) int

fn C.blip_set_rates(&C.blip_t, f64, f64)

fn C.blip_clear(&C.blip_t)

enum Channel {
    square1
    square2
    wave
    noise
    mixer
}

[heap]
struct Register {
pub mut:
    channel Channel
    nrx0 u8
    nrx1 u8
    nrx2 u8
    nrx3 u8
    nrx4 u8
}

fn (self &Register) get_sweep_period() u8 {
	return (self.nrx0 >> 4) & 0x07
}

fn (self &Register) get_negate() bool {
	return self.nrx0 & 0x08 != 0x00
}

fn (self &Register) get_shift() u8 {
	return self.nrx0 & 0x07
}

fn (self &Register) get_dac_power() bool {
	return self.nrx0 & 0x80 != 0x00
}

fn (self &Register) get_duty() u8 {
	return self.nrx1 >> 6
}

fn (self &Register) get_length_load() u16 {
	if self.channel == Channel.wave {
		return (1 << 8) - u16(self.nrx1)
	} else {
		return (1 << 6) - u16(self.nrx1 & 0x3f)
	}
}

fn (self &Register) get_starting_volume() u8 {
	return self.nrx2 >> 4
}

fn (self &Register) get_volume_code() u8 {
	return (self.nrx2 >> 5) & 0x03
}

fn (self &Register) get_envelope_add_mode() bool {
	return self.nrx2 & 0x08 != 0x00
}

fn (self &Register) get_period() u8 {
	return self.nrx2 & 0x07
}

fn (self &Register) get_frequency() u16 {
	return u16(self.nrx4 & 0x07) << 8 | u16(self.nrx3)
}

fn (mut self Register) set_frequency(f u16) {
	h := u8((f >> 8) & 0x07)
	l := u8(f)
	self.nrx4 = (self.nrx4 & 0xf8) | h
	self.nrx3 = l
}

fn (self &Register) get_clock_shift() u8 {
	return self.nrx3 >> 4
}

fn (self &Register) get_width_mode_of_lfsr() bool {
	return self.nrx3 & 0x08 != 0x00
}

fn (self &Register) get_dividor_code() u8 {
	return self.nrx3 & 0x07
}

fn (self &Register) get_trigger() bool {
	return self.nrx4 & 0x80 != 0x00
}

fn (mut self Register) set_trigger(b bool) {
	if b {
		self.nrx4 |= 0x80
	} else {
		self.nrx4 &= 0x7f
	}
}

fn (self &Register) get_length_enable() bool {
	return self.nrx4 & 0x40 != 0x00
}

fn (self &Register) get_l_vol() u8 {
	return (self.nrx0 >> 4) & 0x07
}

fn (self &Register) get_r_vol() u8 {
	return self.nrx0 & 0x07
}

fn (self &Register) get_power() bool {
	return self.nrx2 & 0x80 != 0x00
}

fn new_register(channel Channel) &Register {
	nrx1 := if (channel == Channel.square1) || (channel == Channel.square2) { 0x40 } else { 0x00 }
	return &Register {
		channel: channel
		nrx0: 0x00
		nrx1: u8(nrx1)
		nrx2: 0x00
		nrx3: 0x00
		nrx4: 0x00
	}
}

struct FrameSequencer {
pub mut:
    step u8
}

fn new_frame_sequencer() FrameSequencer {
    return FrameSequencer { step: 0x00 }
}

fn (mut self FrameSequencer) next() u8 {
    self.step += 1
    self.step %= 8
    return self.step
}

struct LengthCounter {
pub mut:
    reg &Register
    n u16
}

fn new_length_counter(reg &Register) LengthCounter {
	return LengthCounter { reg: reg, n: 0x0000 }
}

fn (mut self LengthCounter) next() {
	if self.reg.get_length_enable() && self.n != 0 {
		self.n -= 1
		if self.n == 0 {
			self.reg.set_trigger(false)
		}
	}
}

fn (mut self LengthCounter) reload() {
	if self.n == 0x0000 {
		self.n = u16(if self.reg.channel == Channel.wave {
			1 << 8
		} else {
			1 << 6
		})
	}
}

struct VolumeEnvelope {
pub mut:
    reg &Register
    timer Clock
    volume u8
}

fn new_volume_envelope(reg &Register) VolumeEnvelope {
	return VolumeEnvelope {
		reg: reg
		timer: new_clock(8)
		volume: 0x00
	}
}

fn (mut self VolumeEnvelope) reload() {
	p := self.reg.get_period()
	// The volume envelope and sweep timers treat a period of 0 as 8.
	self.timer.period = if p == 0 { u32(8) } else { u32(p) }
	self.volume = self.reg.get_starting_volume()
}

fn (mut self VolumeEnvelope) next() {
	if self.reg.get_period() == 0 {
		return
	}
	if self.timer.next(1) == 0x00 {
		return
	}
	// If this new volume within the 0 to 15 range, the volume is updated
	v := u8(if self.reg.get_envelope_add_mode() {
		self.volume + 1
	} else {
		self.volume - 1
	})
	if v <= 15 {
		self.volume = v
	}
}

struct FrequencySweep {
pub mut:
    reg &Register
    timer Clock
    enable bool
    shadow u16
    newfeq u16
}

fn new_frequency_sweep(reg &Register) FrequencySweep {
	return FrequencySweep {
		reg: reg
		timer: new_clock(8)
		enable: false
		shadow: 0x0000
		newfeq: 0x0000
	}
}

fn (mut self FrequencySweep) reload() {
	self.shadow = self.reg.get_frequency()
	p := self.reg.get_sweep_period()

	self.timer.period = u32(if p == 0 { 8 } else { p })
	self.enable = p != 0x00 || self.reg.get_shift() != 0x00
	if self.reg.get_shift() != 0x00 {
		self.frequency_calculation()
		self.overflow_check()
	}
}

fn (mut self FrequencySweep) frequency_calculation() {
	offset := self.shadow >> self.reg.get_shift()
	if self.reg.get_negate() {
		self.newfeq = u16(self.shadow - offset)
	} else {
		self.newfeq = u16(self.shadow + offset)
	}
}

fn (mut self FrequencySweep) overflow_check() {
	if self.newfeq >= 2048 {
		self.reg.set_trigger(false)
	}
}

fn (mut self FrequencySweep) next() {
	if !self.enable || self.reg.get_sweep_period() == 0 {
		return
	}
	if self.timer.next(1) == 0x00 {
		return
	}
	self.frequency_calculation()
	self.overflow_check()

	if self.newfeq < 2048 && self.reg.get_shift() != 0 {
		self.reg.set_frequency(self.newfeq)
		self.shadow = self.newfeq
		self.frequency_calculation()
		self.overflow_check()
	}
}

struct Blip {
pub mut:
    data &C.blip_t
    from u32
    ampl i32
}

fn new_blip(data &C.blip_t) Blip {
	return Blip {
		data: data
		from: 0x0000_0000
		ampl: 0x0000_0000
	}
}

fn (mut self Blip) set(time u32, ampl i32) {
	self.from = time
	d := ampl - self.ampl
	self.ampl = ampl
	C.blip_add_delta(self.data, time, d)
}

struct ChannelSquare {
pub mut:
    reg &Register
    timer Clock
    lc LengthCounter
    ve VolumeEnvelope
    fs FrequencySweep
    blip Blip
    idx u8
}

fn new_channel_square(blip &C.blip_t, mode Channel) &ChannelSquare {
	reg := new_register(mode)
	return &ChannelSquare {
		reg: reg
		timer: new_clock(8192)
		lc: new_length_counter(reg)
		ve: new_volume_envelope(reg)
		fs: new_frequency_sweep(reg)
		blip: new_blip(blip)
		idx: 1
	}
}

// This assumes no volume or sweep adjustments need to be done in the meantime
fn (mut self ChannelSquare) next(cycles u32) {
	pat := match self.reg.get_duty() {
		0 { 0b0000_0001 }
		1 { 0b1000_0001 }
		2 { 0b1000_0111 }
		3 { 0b0111_1110 }
		else { panic("BOI") }
	}
	vol := i32(self.ve.volume)
	for _ in 0..self.timer.next(cycles) {
		ampl := if !self.reg.get_trigger() || self.ve.volume == 0 {
			0x00
		} else if (pat >> self.idx) & 0x01 != 0x00 {
			vol
		} else {
			vol * -1
		}
		self.blip.set(self.blip.from + self.timer.period, ampl)
		self.idx = (self.idx + 1) % 8
	}
}

fn (self &ChannelSquare) get(a u16) u8 {
	return match true {
		a == 0xff10 || a == 0xff15 { self.reg.nrx0 }
		a == 0xff11 || a == 0xff16 { self.reg.nrx1 }
		a == 0xff12 || a == 0xff17 { self.reg.nrx2 }
		a == 0xff13 || a == 0xff18 { self.reg.nrx3 }
		a == 0xff14 || a == 0xff19 { self.reg.nrx4 }
		else { panic("BOI") }
	}
}

fn (mut self ChannelSquare) set(a u16, v u8) {
	match true {
		a == 0xff10 || a == 0xff15 { self.reg.nrx0 = v }
		a == 0xff11 || a == 0xff16 {
			self.reg.nrx1 = v
			self.lc.n = self.reg.get_length_load()
		}
		a == 0xff12 || a == 0xff17 { self.reg.nrx2 = v }
		a == 0xff13 || a == 0xff18 {
			self.reg.nrx3 = v
			self.timer.period = period(self.reg)
		}
		a == 0xff14 || a == 0xff19 {
			self.reg.nrx4 = v
			self.timer.period = period(self.reg)
			if self.reg.get_trigger() {
				self.lc.reload()
				self.ve.reload()
				if self.reg.channel == Channel.square1 {
					self.fs.reload()
				}
			}
		}
		else {}
	}
}

struct ChannelWave {
pub mut:
    reg &Register
    timer Clock
    lc LengthCounter
    blip Blip
    waveram [16]u8
    waveidx usize
}

fn new_channel_wave(blip &C.blip_t) &ChannelWave {
	reg := new_register(Channel.wave)
	return &ChannelWave {
		reg: reg
		timer: new_clock(8192)
		lc: new_length_counter(reg)
		blip: new_blip(blip)
		waveram: [16]u8{init: 0}
		waveidx: 0x00
	}
}

fn (mut self ChannelWave) next(cycles u32) {
	s := match self.reg.get_volume_code() {
		0 { 4 }
		1 { 0 }
		2 { 1 }
		3 { 2 }
		else { panic("BOI") }
	}
	for _ in 0..self.timer.next(cycles) {
		sample := if self.waveidx & 0x01 == 0x00 {
			self.waveram[self.waveidx / 2] & 0x0f
		} else {
			self.waveram[self.waveidx / 2] >> 4
		}
		ampl := if !self.reg.get_trigger() || !self.reg.get_dac_power() {
			0x00
		} else {
			i32(sample >> s)
		}
		self.blip.set(self.blip.from + self.timer.period, ampl)
		self.waveidx = (self.waveidx + 1) % 32
	}
}

fn (self &ChannelWave) get(a u16) u8 {
	return match true {
		a == 0xff1a { self.reg.nrx0 }
		a == 0xff1b { self.reg.nrx1 }
		a == 0xff1c { self.reg.nrx2 }
		a == 0xff1d { self.reg.nrx3 }
		a == 0xff1e { self.reg.nrx4 }
		a >= 0xff30 && a <= 0xff3f { self.waveram[a - 0xff30] }
		else { panic("BOI") }
	}
}

fn (mut self ChannelWave) set(a u16, v u8) {
	match true {
		a == 0xff1a { self.reg.nrx0 = v }
		a == 0xff1b {
			self.reg.nrx1 = v
			self.lc.n = self.reg.get_length_load()
		}
		a == 0xff1c { self.reg.nrx2 = v }
		a == 0xff1d {
			self.reg.nrx3 = v
			self.timer.period = period(self.reg)
		}
		a == 0xff1e {
			self.reg.nrx4 = v
			self.timer.period = period(self.reg)
			if self.reg.get_trigger() {
				self.lc.reload()
				self.waveidx = 0x00
			}
		}
		a >= 0xff30 && a <= 0xff3f { self.waveram[a - 0xff30] = v }
		else {}
	}
}

// The linear feedback shift register (LFSR) generates a pseudo-random bit sequence. It has a 15-bit shift register
// with feedback. When clocked by the frequency timer, the low two bits (0 and 1) are XORed, all bits are shifted right
// by one, and the result of the XOR is put into the now-empty high bit. If width mode is 1 (NR43), the XOR result is
// ALSO put into bit 6 AFTER the shift, resulting in a 7-bit LFSR. The waveform output is bit 0 of the LFSR, INVERTED.
struct Lfsr {
pub mut:
    reg &Register
    n u16
}

fn new_lfsr(reg &Register) Lfsr {
	return Lfsr { reg: reg, n: 0x0001 }
}

fn (mut self Lfsr) next() bool {
	s := if self.reg.get_width_mode_of_lfsr() {
		0x06
	} else {
		0x0e
	}
	src := self.n
	self.n <<= 1
	bit := ((src >> s) ^ (self.n >> s)) & 0x0001
	self.n |= bit
	return (src >> s) & 0x0001 != 0x0000
}

fn (mut self Lfsr) reload() {
	self.n = 0x0001
}

struct ChannelNoise {
pub mut:
    reg &Register
    timer Clock
    lc LengthCounter
    ve VolumeEnvelope
    lfsr Lfsr
    blip Blip
}

fn new_channel_noise(blip &C.blip_t) &ChannelNoise {
	reg := new_register(Channel.noise)
	return &ChannelNoise {
		reg: reg
		timer: new_clock(4096)
		lc: new_length_counter(reg)
		ve: new_volume_envelope(reg)
		lfsr: new_lfsr(reg)
		blip: new_blip(blip)
	}
}

fn (mut self ChannelNoise) next(cycles u32) {
	for _ in 0..self.timer.next(cycles) {
		ampl := if !self.reg.get_trigger() || self.ve.volume == 0 {
			0x00
		} else if self.lfsr.next() {
			i32(self.ve.volume)
		} else {
			i32(self.ve.volume) * -1
		}
		self.blip.set(self.blip.from + self.timer.period, ampl)
	}
}

fn (self &ChannelNoise) get(a u16) u8 {
	return match a {
		0xff1f { self.reg.nrx0 }
		0xff20 { self.reg.nrx1 }
		0xff21 { self.reg.nrx2 }
		0xff22 { self.reg.nrx3 }
		0xff23 { self.reg.nrx4 }
		else { panic("BOI") }
	}
}

fn (mut self ChannelNoise) set(a u16, v u8) {
	match a {
		0xff1f { self.reg.nrx0 = v }
		0xff20 {
			self.reg.nrx1 = v
			self.lc.n = self.reg.get_length_load()
		}
		0xff21 { self.reg.nrx2 = v }
		0xff22 {
			self.reg.nrx3 = v
			self.timer.period = period(self.reg)
		}
		0xff23 {
			self.reg.nrx4 = v
			if self.reg.get_trigger() {
				self.lc.reload()
				self.ve.reload()
				self.lfsr.reload()
			}
		}
		else { panic("BOI") }
	}
}

pub struct APU {
pub mut:
    reg &Register
    timer Clock
    fs FrameSequencer
    channel1 &ChannelSquare
    channel2 &ChannelSquare
    channel3 &ChannelWave
    channel4 &ChannelNoise
    sample_rate u32
}

pub fn new_apu(sample_rate u32) &APU {
	blipbuf1 := create_blipbuf(sample_rate)
	blipbuf2 := create_blipbuf(sample_rate)
	blipbuf3 := create_blipbuf(sample_rate)
	blipbuf4 := create_blipbuf(sample_rate)

	return &APU {
		reg: new_register(Channel.mixer)
		timer: new_clock(clock_frequency / 512)
		fs: new_frame_sequencer()
		channel1: new_channel_square(blipbuf1, Channel.square1)
		channel2: new_channel_square(blipbuf2, Channel.square2)
		channel3: new_channel_wave(blipbuf3)
		channel4: new_channel_noise(blipbuf4)
		sample_rate: sample_rate
	}
}

fn (self &APU) play(l []f32, r []f32) {
	if sdl.queue_audio(1,l.data,u32(l.len*l.element_size)) < 0 {
		sdl.pause_audio(0)
		sdl.pause_audio_device(1,0)
	}
}

pub fn (mut self APU) next(cycles u32) {
	if !self.reg.get_power() {
		return
	}

	for _ in 0..self.timer.next(cycles) {
		self.channel1.next(self.timer.period)
		self.channel2.next(self.timer.period)
		self.channel3.next(self.timer.period)
		self.channel4.next(self.timer.period)

		step := self.fs.next()
		if step == 0 || step == 2 || step == 4 || step == 6 {
			self.channel1.lc.next()
			self.channel2.lc.next()
			self.channel3.lc.next()
			self.channel4.lc.next()
		}
		if step == 7 {
			self.channel1.ve.next()
			self.channel2.ve.next()
			self.channel4.ve.next()
		}
		if step == 2 || step == 6 {
			self.channel1.fs.next()
			self.channel1.timer.period = period(self.channel1.reg)
		}

		C.blip_end_frame(self.channel1.blip.data,self.timer.period)
		C.blip_end_frame(self.channel2.blip.data,self.timer.period)
		C.blip_end_frame(self.channel3.blip.data,self.timer.period)
		C.blip_end_frame(self.channel4.blip.data,self.timer.period)
		self.channel1.blip.from -= self.timer.period
		self.channel2.blip.from -= self.timer.period
		self.channel3.blip.from -= self.timer.period
		self.channel4.blip.from -= self.timer.period
		self.mix()
	}
}

fn (mut self APU) mix() {
	sc1 := C.blip_samples_avail(self.channel1.blip.data)

	sample_count := usize(sc1)
	mut sum := 0

	l_vol := (f32(self.reg.get_l_vol()) / 7.0) * (1.0 / 15.0) * 0.25
	r_vol := (f32(self.reg.get_r_vol()) / 7.0) * (1.0 / 15.0) * 0.25

	for sum < sample_count {
		mut buf_l := [2048]f32{init: 0}
		mut buf_r := [2048]f32{init: 0}
		mut buf := [2048]i16{init: 0}

		count1 := C.blip_read_samples(self.channel1.blip.data, unsafe {&i16(&buf)}, 2048, false)
		for i, v in buf[..count1] {
			if self.reg.nrx1 & 0x01 == 0x01 {
				buf_l[i] += f32(v) * l_vol
			}
			if self.reg.nrx1 & 0x10 == 0x10 {
				buf_r[i] += f32(v) * r_vol
			}
		}

		count2 := C.blip_read_samples(self.channel2.blip.data, unsafe {&i16(&buf)}, 2048, false)
		for i, v in buf[..count2] {
			if self.reg.nrx1 & 0x02 == 0x02 {
				buf_l[i] += f32(v) * l_vol
			}
			if self.reg.nrx1 & 0x20 == 0x20 {
				buf_r[i] += f32(v) * r_vol
			}
		}

		count3 := C.blip_read_samples(self.channel3.blip.data, unsafe {&i16(&buf)}, 2048, false)
		for i, v in buf[..count3] {
			if self.reg.nrx1 & 0x04 == 0x04 {
				buf_l[i] += f32(v) * l_vol
			}
			if self.reg.nrx1 & 0x40 == 0x40 {
				buf_r[i] += f32(v) * r_vol
			}
		}

		count4 := C.blip_read_samples(self.channel4.blip.data, unsafe {&i16(&buf)}, 2048, false)
		for i, v in buf[..count4] {
			if self.reg.nrx1 & 0x08 == 0x08 {
				buf_l[i] += f32(v) * l_vol
			}
			if self.reg.nrx1 & 0x80 == 0x80 {
				buf_r[i] += f32(v) * r_vol
			}
		}

		self.play(buf_l[..count1], buf_r[..count1])
		sum += count1
	}
}

const rd_mask = [
    u8(0x80), 0x3f, 0x00, 0xff, 0xbf, 0xff, 0x3f, 0x00, 0xff, 0xbf, 0x7f, 0xff, 0x9f, 0xff, 0xbf, 0xff, 0xff, 0x00, 0x00,
    0xbf, 0x00, 0x00, 0x70, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
]!

pub fn (self &APU) get(a u16) u8 {
	r := match a {
		0xff10...0xff14 { self.channel1.get(a) }
		0xff15...0xff19 { self.channel2.get(a) }
		0xff1a...0xff1e { self.channel3.get(a) }
		0xff1f...0xff23 { self.channel4.get(a) }
		0xff24 { self.reg.nrx0 }
		0xff25 { self.reg.nrx1 }
		0xff26 {
			a_ := self.reg.nrx2 & 0xf0
			b := if self.channel1.reg.get_trigger() { 1 } else { 0 }
			c := if self.channel2.reg.get_trigger() { 2 } else { 0 }
			d := if self.channel3.reg.get_trigger() && self.channel3.reg.get_dac_power() {
				4
			} else {
				0
			}
			e := if self.channel4.reg.get_trigger() { 8 } else { 0 }
			a_ | b | c | d | e
		}
		0xff27...0xff2f { 0x00 }
		0xff30...0xff3f { self.channel3.get(a) }
		else { 0x00 }
	}
	return r | rd_mask[a - 0xff10]
}

pub fn (mut self APU) set(a u16, v u8) {
	if a != 0xff26 && !self.reg.get_power() {
		return
	}
	match a {
		0xff10...0xff14 { self.channel1.set(a, v) }
		0xff15...0xff19 { self.channel2.set(a, v) }
		0xff1a...0xff1e { self.channel3.set(a, v) }
		0xff1f...0xff23 { self.channel4.set(a, v) }
		0xff24 { self.reg.nrx0 = v }
		0xff25 { self.reg.nrx1 = v }
		0xff26 {
			self.reg.nrx2 = v
			if !self.reg.get_power() {
				self.channel1.reg.nrx0 = 0x00
				self.channel1.reg.nrx1 = 0x00
				self.channel1.reg.nrx2 = 0x00
				self.channel1.reg.nrx3 = 0x00
				self.channel1.reg.nrx4 = 0x00
				self.channel2.reg.nrx0 = 0x00
				self.channel2.reg.nrx1 = 0x00
				self.channel2.reg.nrx2 = 0x00
				self.channel2.reg.nrx3 = 0x00
				self.channel2.reg.nrx4 = 0x00
				self.channel3.reg.nrx0 = 0x00
				self.channel3.reg.nrx1 = 0x00
				self.channel3.reg.nrx2 = 0x00
				self.channel3.reg.nrx3 = 0x00
				self.channel3.reg.nrx4 = 0x00
				self.channel4.reg.nrx0 = 0x00
				self.channel4.reg.nrx1 = 0x00
				self.channel4.reg.nrx2 = 0x00
				self.channel4.reg.nrx3 = 0x00
				self.channel4.reg.nrx4 = 0x00
				self.reg.nrx0 = 0x00
				self.reg.nrx1 = 0x00
				self.reg.nrx2 = 0x00
				self.reg.nrx3 = 0x00
				self.reg.nrx4 = 0x00
			}
		}
		0xff27...0xff2f {}
		0xff30...0xff3f { self.channel3.set(a, v) }
		else {}
	}
}

fn create_blipbuf(sample_rate u32) &C.blip_t {
    mut blipbuf := C.blip_new(sample_rate)
    C.blip_set_rates(blipbuf, f64(clock_frequency), f64(sample_rate))
    return blipbuf
}

fn period(reg &Register) u32 {
	return match true {
        reg.channel == Channel.square1 || reg.channel == Channel.square2 { 4 * (2048 - u32(reg.get_frequency())) }
        reg.channel == Channel.wave { 2 * (2048 - u32(reg.get_frequency())) }
        reg.channel == Channel.noise {
            d := match reg.get_dividor_code() {
                0 { 8 }
                else { (u32(reg.get_dividor_code()) + 1) * 16 }
            }
            u32(d) << reg.get_clock_shift()
        }
        reg.channel == Channel.mixer { clock_frequency / 512 }
		else { panic("") }
    }
}