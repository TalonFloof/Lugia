module core

pub enum JoypadKey as u8 {
    right   = 0b0000_0001
    left    = 0b0000_0010
    up      = 0b0000_0100
    down    = 0b0000_1000
    a       = 0b0001_0000
    b       = 0b0010_0000
    select_ = 0b0100_0000
    start   = 0b1000_0000
}

pub struct Joypad {
mut:
	intf &&Intf
	matrix u8
	select_ u8
}

pub fn new_joypad(intf &&Intf) &Joypad {
	return &Joypad {
		intf: intf
		matrix: 0xff
		select_: 0x00
	}
}

pub fn (mut self Joypad) keydown(key JoypadKey) {
	self.matrix &= ~u8(key)
    self.intf.hi(4)
}

pub fn (mut self Joypad) keyup(key JoypadKey) {
	self.matrix |= u8(key)
}

pub fn (self &Joypad) get(a u16) u8 {
	if (self.select_ & 0b0001_0000) == 0x00 {
        return self.select_ | (self.matrix & 0x0f)
    }
	if (self.select_ & 0b0010_0000) == 0x00 {
        return self.select_ | (self.matrix >> 4)
    }
	return self.select_
}

pub fn (mut self Joypad) set(a u16, v u8) {
	self.select_ = v
}