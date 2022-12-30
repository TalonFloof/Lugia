module core

import os
import time

fn C.show_alert(msg string)

pub interface GameBoyROM {
    get(a u16) u8
mut:
    set(a u16, v u8)
    save()
}

pub struct SimpleROM {
    data []u8
}

pub fn (x &SimpleROM) get(a u16) u8 {
    return x.data[a]
}

pub fn (mut x SimpleROM) set(a u16, v u8) {}

pub fn (mut x SimpleROM) save() {}

pub struct MBC1ROM {
    rom []u8
mut:
    ram []u8
    bank_mode bool
    ram_enabled bool
    bank u8
    save_path string
}

pub fn new_mbc1rom(rom []u8, ram []u8, sav string) &MBC1ROM {
    return &MBC1ROM {
        rom: rom
        ram: ram
        bank_mode: false
        bank: 0x01
        ram_enabled: false
        save_path: sav
    }
}

fn (x &MBC1ROM) rom_bank() usize {
    return if x.bank_mode { x.bank & 0x1f } else { x.bank & 0x7f }
}

fn (x &MBC1ROM) ram_bank() usize {
    return if x.bank_mode { (x.bank & 0x60) >> 5 } else { 0x00 }
}

pub fn (x &MBC1ROM) get(a u16) u8 {
    return match true {
        a <= 0x3fff { x.rom[a] }
        a >= 0x4000 && a <= 0x7fff {
			if (x.rom_bank() * 0x4000 + usize(a) - 0x4000) < x.rom.len {
				x.rom[x.rom_bank() * 0x4000 + usize(a) - 0x4000]
			} else {
				0x00
			}
		}
        a >= 0xa000 && a <= 0xbfff { if x.ram_enabled { x.ram[x.ram_bank() * 0x2000 + usize(a) - 0xa000] } else { 0x00 } }
        else { 0x00 }
    }
}

pub fn (mut x MBC1ROM) set(a u16, v u8) {
    match true {
        a >= 0xa000 && a <= 0xbfff {
            if x.ram_enabled {
                x.ram[x.ram_bank() * 0x2000 + usize(a) - 0xa000] = v
            }
        }
        a <= 0x1fff {
            x.ram_enabled = (v & 0x0f) == 0x0a
        }
        a >= 0x2000 && a <= 0x3fff {
            x.bank = u8((x.bank & 0x60) | (if (v & 0x1f) == 0x00 { 0x01 } else { v & 0x1f }))
        }
        a >= 0x4000 && a <= 0x5fff {
            x.bank = (x.bank & 0x9f) | ((v & 0x03) << 5)
        }
        a >= 0x6000 && a <= 0x7fff {
            match v {
                0x00 { x.bank_mode = false }
                0x01 { x.bank_mode = true }
                else { C.show_alert("Invalid Cartridge Type 0x${v:02x}") }
            }
        }
        else {}
    }
}

pub fn (mut x MBC1ROM) save() {
    if x.save_path.len == 0 {
        return
    }
    eprintln("Saving!")
    mut f := os.create(x.save_path) or { C.show_alert("Failed to write save data: ${err}") panic("") }
    f.write(x.ram) or { C.show_alert("Failed to write save data: ${err}") panic("") }
    f.close()
}

/*
Unlike the rest of the MBC controllers, the MBC3 can contain a Real Time Clock
Games like Pokemon Gold/Silver utilized this to allow for a day-night cycle.
This feature is unique to the MBC3 controller, and no other controller that I'm aware of
has this feature.
*/
pub struct RTC {
mut:
    s u8
    m u8
    h u8
    dl u8
    dh u8
    epoch i64
    save_path string
}

pub fn new_rtc(save_path string) &RTC {
    data := os.read_bytes(save_path) or { []u8{len: 0} }
    return &RTC {
        epoch: if data.len == 0 { time.now().unix_time() } else { *(&i64(data.data)) }
        save_path: save_path
    }
}

pub fn (mut rtc RTC) tick() {
    d := time.now().unix_time() - rtc.epoch

    rtc.s = u8(d % 60)
    rtc.m = u8(d / 60 % 60)
    rtc.h = u8(d / 3600 % 24)
    days := u16(d / 3600 / 24)
    rtc.dl = u8(days % 256)
    match true {
        days >= 0x0000 && days <= 0x00ff {}
        days >= 0x0100 && days <= 0x01ff {
            rtc.dh |= 0x01
        }
        else {
            rtc.dh |= 0x01
            rtc.dh |= 0x80
        }
    }
}

pub fn (rtc &RTC) get(a u16) u8 {
   return match a {
        0x08 { rtc.s }
        0x09 { rtc.m }
        0x0a { rtc.h }
        0x0b { rtc.dl }
        0x0c { rtc.dh }
        else { C.show_alert("Unknown RTC Register was accessed!") panic("") }
    }
}

pub fn (mut rtc RTC) set(a u16, v u8) {
   match a {
        0x08 { rtc.s = v }
        0x09 { rtc.m = v }
        0x0a { rtc.h = v }
        0x0b { rtc.dl = v }
        0x0c { rtc.dh = v }
        else { C.show_alert("Unknown RTC Register was accessed!") panic("") }
    }
}

pub fn (mut rtc RTC) save() {
    if rtc.save_path.len == 0 {
        return
    }
    mut f := os.create(rtc.save_path) or { C.show_alert("Failed to write RTC data: ${err}") panic("") }
    unsafe { f.write_ptr(&(rtc.epoch),8) }
    f.close()
}

pub struct MBC3ROM { 
    rom []u8
mut:
    ram []u8
    ram_enabled bool
    rom_bank usize
    ram_bank usize
    rtc &RTC
    save_path string
}

pub fn new_mbc3rom(rom []u8, ram []u8, sav string, rtc string) &MBC3ROM {
    return &MBC3ROM {
        rom: rom
        ram: ram
        rom_bank: 0x01
        ram_bank: 0x00
        ram_enabled: false
        rtc: if rtc.len > 0 { new_rtc(rtc) } else { new_rtc("") }
        save_path: sav
    }
}

pub fn (x &MBC3ROM) get(a u16) u8 {
    return match true {
        a <= 0x3fff { x.rom[a] }
        a >= 0x4000 && a <= 0x7fff { x.rom[x.rom_bank * 0x4000 + usize(a) - 0x4000] }
        a >= 0xa000 && a <= 0xbfff {
            if x.ram_enabled {
                if x.ram_bank <= 0x03 {
                    x.ram[x.ram_bank * 0x2000 + usize(a) - 0xa000]
                } else {
                    x.rtc.get(u16(x.ram_bank))
                }
            } else {
                0x00
            }
        }
        else { 0x00 }
    }
}

pub fn (mut x MBC3ROM) set(a u16, v u8) {
    match true {
        a >= 0xa000 && a <= 0xbfff {
            if x.ram_enabled {
                if x.ram_bank <= 0x03 {
                    x.ram[x.ram_bank * 0x2000 + usize(a) - 0xa000] = v
                } else {
                    x.rtc.set(u16(x.ram_bank), v)
                }
            }
        }
        a <= 0x1fff {
            x.ram_enabled = (v & 0x0f) == 0x0a
        }
        a >= 0x2000 && a <= 0x3fff {
            x.rom_bank = usize(if (v & 0x7f) == 0 {0x01} else {(v & 0x7f)})
        }
        a >= 0x4000 && a <= 0x5fff {
            x.ram_bank = usize(v & 0x0f)
        }
        a >= 0x6000 && a <= 0x7fff {
            if v & 0x01 != 0 {
                x.rtc.tick()
            }
        }
        else {}
    }
}

pub fn (mut x MBC3ROM) save() {
    if x.save_path.len == 0 {
        return
    }
    eprintln("Saving!")
    mut f := os.create(x.save_path) or { C.show_alert("Failed to write save data: ${err}") panic("") }
    f.write(x.ram) or { C.show_alert("Failed to write save data: ${err}") panic("") }
    f.close()
    if x.rtc != unsafe { nil } {
        x.rtc.save()
    }
}

pub struct MBC5ROM {
    rom []u8
mut:
    ram []u8
    ram_enabled bool
    rom_bank usize
    ram_bank usize
	save_path string
}

pub fn new_mbc5rom(rom []u8, ram []u8, sav string) &MBC5ROM {
    return &MBC5ROM {
        rom: rom
        ram: ram
        rom_bank: 0x01
        ram_bank: 0x00
        ram_enabled: false
		save_path: sav
    }
}

pub fn (x &MBC5ROM) get(a u16) u8 {
    return match true {
        a <= 0x3fff { x.rom[a] }
        a >= 0x4000 && a <= 0x7fff { x.rom[x.rom_bank * 0x4000 + usize(a) - 0x4000] }
        a >= 0xa000 && a <= 0xbfff { if x.ram_enabled { x.ram[x.ram_bank * 0x2000 + usize(a) - 0xa000] } else { 0x00 } }
        else { 0x00 }
    }
}

pub fn (mut x MBC5ROM) set(a u16, v u8) {
    match true {
        a >= 0xa000 && a <= 0xbfff {
            if x.ram_enabled {
                x.ram[x.ram_bank * 0x2000 + usize(a) - 0xa000] = v
            }
        }
        a <= 0x1fff {
            x.ram_enabled = (v & 0x0f) == 0x0a
        }
        a >= 0x2000 && a <= 0x2fff {
            x.rom_bank = (x.rom_bank & 0x100) | usize(v)
        }
        a >= 0x3000 && a <= 0x3fff {
            x.rom_bank = (x.rom_bank & 0x0ff) | (usize(v & 0x01) << 8)
        }
        a >= 0x4000 && a <= 0x5fff {
            x.ram_bank = usize(v & 0x0f)
        }
        else {}
    }
}

pub fn (mut x MBC5ROM) save() {
	if x.save_path.len == 0 {
        return
    }
    eprintln("Saving!")
    mut f := os.create(x.save_path) or { C.show_alert("Failed to write save data: ${err}") panic("") }
    f.write(x.ram) or { C.show_alert("Failed to write save data: ${err}") panic("") }
    f.close()
}

fn cart_size(num u8) u32 {
    bank := u32(16384)
    return match num {
        0x00 { bank * 2 }
        0x01 { bank * 4 }
        0x02 { bank * 8 }
        0x03 { bank * 16 }
        0x04 { bank * 32 }
        0x05 { bank * 64 }
        0x06 { bank * 128 }
        0x07 { bank * 256 }
        0x08 { bank * 512 }
        0x52 { bank * 72 }
        0x53 { bank * 80 }
        0x54 { bank * 96 }
        else { C.show_alert("Lugia doesn't support the Bank Sizing: 0x{num:02x}") panic("") }
    }
}

fn ram_size(num u8) u32 {
    return match num {
        0x00 { 0 }
        0x01 { 1024 * 2 }
        0x02 { 1024 * 8 }
        0x03 { 1024 * 32 }
        0x04 { 1024 * 128 }
        0x05 { 1024 * 64 }
        else { C.show_alert("Lugia doesn't support the RAM Sizing: 0x{num:02x}") panic("") }
    }
}

fn read_ram(path string, size int) []u8 {
    data := os.read_bytes(path) or { []u8{len: size, init: 0} }
    return data
}

pub fn new_cart(path string) &GameBoyROM {
    data := os.read_bytes(path) or { C.show_alert("Couldn't read file!") panic("") }
    save_path_base := if path.last_index_u8(`.`) != -1 { path.substr(0,path.last_index_u8(`.`)) } else { path }
    if data.len < 0x150 {
        C.show_alert("ROM isn't large enough to contain the required information struct found at 0x0100-0x014f")
    }
    max_size := cart_size(data[0x148])
    if data.len > max_size {
        C.show_alert("ROM Size exceeds reported bank count")
    }
    return match data[0x147] {
        0x00 { &GameBoyROM(&SimpleROM {data: data}) }
        0x01 { &GameBoyROM(new_mbc1rom(data,[]u8{len: 0},"")) }
        0x02 { &GameBoyROM(new_mbc1rom(data,[]u8{len: int(ram_size(data[0x149])), init: 0},"")) }
        0x03 { &GameBoyROM(new_mbc1rom(data,read_ram(save_path_base + ".sav",int(ram_size(data[0x149]))),save_path_base + ".sav")) } // SAVEDATA!
        0x0f { &GameBoyROM(new_mbc3rom(data,[]u8{len: 0, init: 0},"",save_path_base + ".rtc")) } // TIMER!
        0x10 { &GameBoyROM(new_mbc3rom(data,read_ram(save_path_base + ".sav",int(ram_size(data[0x149]))),save_path_base + ".sav",save_path_base + ".rtc")) } // TIMER & SAVEDATA!
        0x12 { &GameBoyROM(new_mbc3rom(data,[]u8{len: int(ram_size(data[0x149])), init: 0},"","")) }
		0x13 { &GameBoyROM(new_mbc3rom(data,read_ram(save_path_base + ".sav",int(ram_size(data[0x149]))),save_path_base + ".sav","")) } // SAVEDATA!
        0x19 { &GameBoyROM(new_mbc5rom(data,[]u8{len: 0, init: 0},"")) }
		0x1a { &GameBoyROM(new_mbc5rom(data,[]u8{len: int(ram_size(data[0x149])), init: 0},"")) }
		0x1b { &GameBoyROM(new_mbc5rom(data,read_ram(save_path_base + ".sav",int(ram_size(data[0x149]))),save_path_base + ".sav")) }
        else { C.show_alert("ROM Type 0x${data[0x147]:02x} is not supported by Lugia") panic("") }
    }
}