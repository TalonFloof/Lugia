module core

pub struct Clock {
pub mut:
	period u32
    n u32
}

pub fn new_clock(period u32) Clock {
	return Clock { period: period, n: 0x00 }
}

pub fn (mut clock Clock) next(cycles u32) u32 {
	clock.n += cycles
    rs := u32(clock.n / clock.period)
    clock.n = u32(clock.n % clock.period)
    return rs
}

pub struct Timer {
mut:
	intf &&Intf
    div u8
	tima u8
	tma u8
	tac u8
    div_clock Clock
    tma_clock Clock
}

pub fn new_timer(intf &&Intf) &Timer {
	return &Timer {
		intf: intf
		div_clock: new_clock(256)
		tma_clock: new_clock(1024)
	}
}

pub fn (self &Timer) get(a u16) u8 {
	return match a {
		0xff04 { self.div }
		0xff05 { self.tima }
		0xff06 { self.tma }
		0xff07 { self.tac }
		else { panic("Unsupported Timer Address") }
	}
}

pub fn (mut self Timer) set(a u16, v u8) {
	match a {
		0xff04 {
			self.div = 0x00
			self.div_clock.n = 0x00
		}
		0xff05 { self.tima = v }
		0xff06 { self.tma = v }
		0xff07 {
			if (self.tac & 0x03) != (v & 0x03) {
				self.tma_clock.n = 0x00
				self.tma_clock.period = match v & 0x03 {
					0x00 { 1024 }
					0x01 { 16 }
					0x02 { 64 }
					0x03 { 256 }
					else { panic("") }
				}
				self.tima = self.tma
			}
			self.tac = v
		}
		else { panic("Unsupported Timer Address") }
	}
}

pub fn (mut self Timer) next(cycles u32) {
	self.div += u8(self.div_clock.next(cycles))

	if (self.tac & 0x04) != 0x00 {
		n := self.tma_clock.next(cycles)
		for _ in 0..n {
			self.tima = self.tima + 1
			if self.tima == 0x00 {
				self.tima = self.tma
				self.intf.hi(2)
			}
		}
	}
}