module core

[heap]
pub struct Intf {
mut:
	a u8
}

pub fn (mut self Intf) hi(flag u8) {
	self.a |= 1 << flag
}