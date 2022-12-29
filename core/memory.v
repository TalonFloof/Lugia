module core

[heap]
pub struct Memory {
mut:
    wram []u8
    inte u8
    wram_bank usize
    hram []u8
pub mut:
    speed u32
    shift bool
    cart &GameBoyROM
    is_gbc bool
    intf &Intf
    gpu &GPU
    hdma &HDMA
    timer &Timer
    joypad &Joypad
	apu &APU

    serial_data u8
    serial_control u8
}

pub fn new_memory(path string, audio &AudioPlayer) &Memory {
    mut r := &Memory {
        wram: []u8{len: 0x8000, init: 0, cap: 0x8000}
        inte: 0x00
        wram_bank: 0x01
        hram: []u8{len: 0x7f, init: 0, cap: 0x7f}
        speed: 0,
        shift: false
        cart: new_cart(path)
        intf: &Intf {a: 0x00}
        gpu: unsafe { nil }
        hdma: new_hdma()
        timer: unsafe { nil }
        joypad: unsafe { nil }
		apu: unsafe { nil }
    }
    r.is_gbc = (r.cart.get(0x0143) & 0x80) == 0x80
    r.gpu = new_gpu(r.is_gbc,&r.intf)
    r.timer = new_timer(&r.intf)
    r.joypad = new_joypad(&r.intf)
	r.apu = new_apu(audio, !r.is_gbc)
    r.set(0xff05, 0x00)
    r.set(0xff06, 0x00)
    r.set(0xff07, 0x00)
    r.set(0xff10, 0x80)
    r.set(0xff11, 0xbf)
    r.set(0xff12, 0xf3)
    r.set(0xff14, 0xbf)
    r.set(0xff16, 0x3f)
    r.set(0xff16, 0x3f)
    r.set(0xff17, 0x00)
    r.set(0xff19, 0xbf)
    r.set(0xff1a, 0x7f)
    r.set(0xff1b, 0xff)
    r.set(0xff1c, 0x9f)
    r.set(0xff1e, 0xff)
    r.set(0xff20, 0xff)
    r.set(0xff21, 0x00)
    r.set(0xff22, 0x00)
    r.set(0xff23, 0xbf)
    r.set(0xff24, 0x77)
    r.set(0xff25, 0xf3)
    r.set(0xff26, 0xf1)
    r.set(0xff40, 0x91)
    r.set(0xff42, 0x00)
    r.set(0xff43, 0x00)
    r.set(0xff45, 0x00)
    r.set(0xff47, 0xfc)
    r.set(0xff48, 0xff)
    r.set(0xff49, 0xff)
    r.set(0xff4a, 0x00)
    r.set(0xff4b, 0x00)
    return r
}

pub fn (mut mem Memory) switch_speed() {
    if mem.shift {
        if mem.speed == 1 {
            mem.speed = 0
        } else {
            mem.speed = 1
        }
    }
    mem.shift = false
}

pub fn (mem &Memory) get(a u16) u8 {
    match true {
        a >= 0x0000 && a <= 0x7fff { // ROM
            return mem.cart.get(a)
        }
        a >= 0x8000 && a <= 0x9FFF { // VRAM (Switchable in CGB mode)
            return mem.gpu.get(a)
        }
        a >= 0xa000 && a <= 0xbfff { // External RAM
            return mem.cart.get(a)
        }
        a >= 0xc000 && a <= 0xcfff { // 4 KiB Working RAM Bank 0
            return mem.wram[usize(a) - 0xc000]
        }
        a >= 0xd000 && a <= 0xdfff { // 4 KiB Working RAM Bank 1 (Switchable between 1-7 in CGB Mode)
            return mem.wram[usize(a) - 0xd000 + 0x1000 * mem.wram_bank]
        }
        a >= 0xe000 && a <= 0xefff { // Echo of 0xC000-0xCFFF (Rarely Used)
            return mem.wram[usize(a) - 0xe000]
        }
        a >= 0xf000 && a <= 0xfdff { // Echo of 0xC000-0xDDFF (Rarely Used)
            return mem.wram[usize(a) - 0xf000 + 0x1000 * mem.wram_bank]
        }
        a >= 0xfe00 && a <= 0xfe9f { // Object Attribute Table
            return mem.gpu.get(a)
        }
        a >= 0xfea0 && a <= 0xfeff { // Unusable Space
            return 0
        }
        a == 0xff00 {
            return mem.joypad.get(a)
        }
        a == 0xff01 {
            return mem.serial_data
        }
        a == 0xff02 {
            return mem.serial_control
        }
        a >= 0xff04 && a <= 0xff07 { // Timer
            return mem.timer.get(a)
        }
        a == 0xff0f { // Intf
            return mem.intf.a
        }
		a >= 0xff10 && a <= 0xff3f {
			return mem.apu.get(a)
        }
        a == 0xff4d { // RAM Speed? (I have no idea)
            b := if mem.speed == 1 { 0x80 } else { 0x00 }
            c := if mem.shift { 0x01 } else { 0x00 }
            b | c
        }
        ((a >= 0xff40 && a <= 0xff45) || (a >= 0xff47 && a <= 0xff4b) || (a == 0xff4f)) { // GPU
            return mem.gpu.get(a)
        }
        a >= 0xff51 && a <= 0xff55 { return mem.hdma.get(a) } // HDMA
        a >= 0xff68 && a <= 0xff6b { return mem.gpu.get(a) } // More GPU
        a == 0xff70 { return u8(mem.wram_bank) } // Working RAM Bank (GameBoy Color Only)
        a >= 0xff80 && a <= 0xfffe { // High RAM
            return mem.hram[usize(a) - 0xff80]
        }
        a == 0xffff { // Interrupt Enable Register
            return mem.inte
        }
        else {
            return 0
        }
    }
    return 0
}

pub fn (mut mem Memory) set(a u16, v u8) {
    match true {
        a >= 0x0000 && a <= 0x7fff { // ROM
            mem.cart.set(a,v)
        }
        a >= 0x8000 && a <= 0x9FFF { // VRAM (Switchable in CGB mode)
            mem.gpu.set(a, v)
        }
        a >= 0xa000 && a <= 0xbfff { // External RAM
            mem.cart.set(a,v)
        }
        a >= 0xc000 && a <= 0xcfff { // 4 KiB Working RAM Bank 0
            mem.wram[usize(a) - 0xc000] = v
        }
        a >= 0xd000 && a <= 0xdfff { // 4 KiB Working RAM Bank 1 (Switchable between 1-7 in CGB Mode)
            mem.wram[usize(a) - 0xd000 + 0x1000 * mem.wram_bank] = v		
        }
        a >= 0xe000 && a <= 0xefff { // Echo of 0xC000-0xCFFF (Rarely Used)
            mem.wram[usize(a) - 0xe000] = v
        }
        a >= 0xf000 && a <= 0xfdff { // Echo of 0xD000-0xDDFF (Rarely Used)
            mem.wram[usize(a) - 0xf000 + 0x1000 * mem.wram_bank] = v
        }
        a >= 0xfe00 && a <= 0xfe9f { // Object Attribute Table
            mem.gpu.set(a, v)
        }
        a >= 0xfea0 && a <= 0xfeff { // Unusable Space
            return
        }
        a == 0xff00 {
            mem.joypad.set(a,v)
        }
        a == 0xff01 {
            mem.serial_data = v
        }
        a == 0xff02 {
            mem.serial_control = v
        }
        a >= 0xff04 && a <= 0xff07 { // Timer
            mem.timer.set(a, v)
        }
        a == 0xff0f { // Intf
            mem.intf.a = v
        }
		a >= 0xff10 && a <= 0xff3f {
			mem.apu.set(a,v)
        }
        a == 0xff46 { // Execute DMA Transfer to OAM
            if v > 0xf1 { panic("v is not less than or equal to 0xf1") }
            base := u16(v) << 8
            for i in 0..0xa0 {
                b := mem.get(base + i)
                mem.gpu.set(0xfe00 + i, b)
            }
        }
        a == 0xff4d { // RAM Speed? (I have no idea)
            mem.shift = (v & 0x01) == 0x01
        }
        (a >= 0xff40 && a <= 0xff45) || (a >= 0xff47 && a <= 0xff4b) || (a == 0xff4f) { // GPU
            mem.gpu.set(a, v)
        }
        a >= 0xff51 && a <= 0xff55 { // HDMA
            mem.hdma.set(a, v)
        }
        a >= 0xff68 && a <= 0xff6b { // More GPU
            mem.gpu.set(a, v)
        }
        a == 0xff70 {  // Working RAM Bank (GameBoy Color Only)
            mem.wram_bank = match v & 0x7 {
                0 { 1 }
                else { usize(v) }
            }
        }
        a >= 0xff80 && a <= 0xfffe { // High RAM
            mem.hram[usize(a) - 0xff80] = v
        }
        a == 0xffff { // Interrupt Enable Register
            mem.inte = v
        }
        else {
            return
        }
    }
}

pub fn (mem &Memory) get_word(a u16) u16 {
    return u16(mem.get(a)) | (u16(mem.get(a+1)) << 8)
}

pub fn (mut mem Memory) set_word(a u16, v u16) {
    mem.set(a,u8(v & 0xFF))
    mem.set(a+1,u8(v >> 8))
}

pub fn (mut mem Memory) next(cycles u32) u32 {
    cpu_divider := mem.speed + 1
    vram_cycles := mem.run_dma()
    gpu_cycles := cycles / cpu_divider + vram_cycles
    cpu_cycles := cycles + vram_cycles * cpu_divider
    mem.timer.next(cpu_cycles)
    mem.gpu.next(gpu_cycles)
	mem.apu.next(gpu_cycles)
    return gpu_cycles
}

pub fn (mut mem Memory) run_dma() u32 {
    if !mem.hdma.active {
        return 0
    }
    match mem.hdma.mode {
        0 {
            len := u32(mem.hdma.remain) + 1
            for _ in 0..len {
                mem.run_dma_hrampart()
            }
            mem.hdma.active = false
            return len * 8
        }
        1 {
            if !mem.gpu.h_blank {
                return 0
            }
            mem.run_dma_hrampart()
            if mem.hdma.remain == 0x7f {
                mem.hdma.active = false
            }
            return 8
        }
        else {}
    }
    panic("You shouldn't be seeing this...")
}

pub fn (mut mem Memory) run_dma_hrampart() {
    mmu_src := mem.hdma.src
    for i in 0..0x10 {
        b := u8(mem.get(mmu_src + i))
        mem.gpu.set(mem.hdma.dst + i, b)
    }
    mem.hdma.src += 0x10
    mem.hdma.dst += 0x10
    if mem.hdma.remain == 0 {
        mem.hdma.remain = 0x7f
    } else {
        mem.hdma.remain -= 1
    }
}