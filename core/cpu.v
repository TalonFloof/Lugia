module core

import time
import math

fn C.show_alert(msg string)

pub struct CPU {
pub mut:
    a u8
    f u8
    b u8
    c u8
    d u8
    e u8
    h u8
    l u8
    sp u16
    pc u16

    mem &Memory
    halted bool
    ei bool
}

const (
    clock_frequency = u32(4194304)
    step_time = u32(16)
    step_cycle_total = u32((f64(step_time) / (f64(f64(1000) / clock_frequency))))

    gbn_cycle_timings = [
        u32(1), 3, 2, 2, 1, 1, 2, 1, 5, 2, 2, 2, 1, 1, 2, 1, // 0
        0, 3, 2, 2, 1, 1, 2, 1, 3, 2, 2, 2, 1, 1, 2, 1, // 1
        2, 3, 2, 2, 1, 1, 2, 1, 2, 2, 2, 2, 1, 1, 2, 1, // 2
        2, 3, 2, 2, 3, 3, 3, 1, 2, 2, 2, 2, 1, 1, 2, 1, // 3
        1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, // 4
        1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, // 5
        1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, // 6
        2, 2, 2, 2, 2, 2, 0, 2, 1, 1, 1, 1, 1, 1, 2, 1, // 7
        1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, // 8
        1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, // 9
        1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, // a
        1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, // b
        2, 3, 3, 4, 3, 4, 2, 4, 2, 4, 3, 0, 3, 6, 2, 4, // c
        2, 3, 3, 0, 3, 4, 2, 4, 2, 4, 3, 0, 3, 0, 2, 4, // d
        3, 3, 2, 0, 0, 4, 2, 4, 4, 1, 4, 0, 0, 0, 2, 4, // e
        3, 3, 2, 1, 0, 4, 2, 4, 3, 2, 4, 1, 0, 0, 2, 4, // f
    ]!

    cb_cycle_timings = [
        u32(2), 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // 0
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // 1
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // 2
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // 3
        2, 2, 2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 3, 2, // 4
        2, 2, 2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 3, 2, // 5
        2, 2, 2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 3, 2, // 6
        2, 2, 2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 3, 2, // 7
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // 8
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // 9
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // a
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // b
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // c
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // d
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // e
        2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 2, 4, 2, // f
    ]!
)

pub enum Flags as u8 {
    z = 0b10000000
    n = 0b01000000
    h = 0b00100000
    c = 0b00010000
}

pub fn new_cpu(path string, audio &AudioPlayer) &CPU {
    mut cpu := &CPU {
        mem: new_memory(path,audio)
        halted: false
        ei: false
    }
    cpu.power_up()
    return cpu
}

pub fn (mut cpu CPU) immediate() u8 {
    v := cpu.mem.get(cpu.pc)
    cpu.pc += 1
    return v
}

pub fn (mut cpu CPU) immediate_word() u16 {
    v := cpu.mem.get_word(cpu.pc)
    cpu.pc += 2
    return v
}

pub fn (mut cpu CPU) push_stack(v u16) {
    cpu.sp -= 2
    cpu.mem.set_word(cpu.sp,v)
}

pub fn (mut cpu CPU) pop_stack() u16 {
    v := cpu.mem.get_word(cpu.sp)
    cpu.sp += 2
    return v
}

pub fn (mut cpu CPU) set_flag(f Flags, v bool) {
    if v {
        cpu.f |= u8(f)
    } else {
        cpu.f &= (~u8(f))
    }
}

pub fn (cpu &CPU) get_af() u16 {
    return (u16(cpu.a) << 8) | u16(cpu.f)
}

pub fn (cpu &CPU) get_bc() u16 {
    return (u16(cpu.b) << 8) | u16(cpu.c)
}

pub fn (cpu &CPU) get_de() u16 {
    return (u16(cpu.d) << 8) | u16(cpu.e)
}

pub fn (cpu &CPU) get_hl() u16 {
    return (u16(cpu.h) << 8) | u16(cpu.l)
}

pub fn (mut cpu CPU) set_af(v u16) {
    cpu.a = u8(v >> 8)
    cpu.f = u8(v & 0x00f0)
}

pub fn (mut cpu CPU) set_bc(v u16) {
    cpu.b = u8(v >> 8)
    cpu.c = u8(v & 0x00ff)
}

pub fn (mut cpu CPU) set_de(v u16) {
    cpu.d = u8(v >> 8)
    cpu.e = u8(v & 0x00ff)
}

pub fn (mut cpu CPU) set_hl(v u16) {
    cpu.h = u8(v >> 8)
    cpu.l = u8(v & 0x00ff)
}

pub fn (mut cpu CPU) add(n u8) {
    a := cpu.a
    r := a + n
    cpu.set_flag(Flags.c, u16(a) + u16(n) > 0xff)
    cpu.set_flag(Flags.h, (a & 0x0f) + (n & 0x0f) > 0x0f)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    cpu.a = r
}

pub fn (mut cpu CPU) adc(n u8) {
    a := cpu.a
    c := u8(if (cpu.f & u8(Flags.c)) != 0 { 1 } else { 0 })
    r := a + n + c
    cpu.set_flag(Flags.c, u16(a) + u16(n) + u16(c) > 0xff)
    cpu.set_flag(Flags.h, (a & 0x0f) + (n & 0x0f) + (c & 0x0f) > 0x0f)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    cpu.a = r
}

pub fn (mut cpu CPU) sub(n u8) {
    a := cpu.a
    r := a - n
    cpu.set_flag(Flags.c, u16(a) < u16(n))
    cpu.set_flag(Flags.h, (a & 0x0f) < (n & 0x0f))
    cpu.set_flag(Flags.n, true)
    cpu.set_flag(Flags.z, r == 0x00)
    cpu.a = r
}

pub fn (mut cpu CPU) sbc(n u8) {
    a := cpu.a
    c := u8(if (cpu.f & u8(Flags.c)) != 0 { 1 } else { 0 })
    r := a - n - c
    cpu.set_flag(Flags.c, u16(a) < u16(n) + u16(c))
    cpu.set_flag(Flags.h, (a & 0x0f) < (n & 0x0f) + c)
    cpu.set_flag(Flags.n, true)
    cpu.set_flag(Flags.z, r == 0x00)
    cpu.a = r
}

pub fn (mut cpu CPU) and(n u8) {
    r := cpu.a & n
    cpu.set_flag(Flags.c, false)
    cpu.set_flag(Flags.h, true)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    cpu.a = r
}

pub fn (mut cpu CPU) or_(n u8) {
    r := cpu.a | n
    cpu.set_flag(Flags.c, false)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    cpu.a = r
}

pub fn (mut cpu CPU) xor(n u8) {
    r := cpu.a ^ n
    cpu.set_flag(Flags.c, false)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    cpu.a = r
}

pub fn (mut cpu CPU) cp(n u8) {
    r := cpu.a
    cpu.sub(n)
    cpu.a = r
}

pub fn (mut cpu CPU) inc(a u8) u8 {
    r := a + 1
    cpu.set_flag(Flags.h, (a & 0x0f) + 0x01 > 0x0f)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    return r
}

fn trailing_zeroes(n usize) usize { // https://stackoverflow.com/questions/45221914/number-of-trailing-zeroes
    mut bits := usize(0)
    mut x := n

    if x != 0 {
        for (x & 1) == 0 {
            bits++
            x >>= 1
        }
    }
    return bits
}

pub fn (mut cpu CPU) dec(a u8) u8 {
    r := a - 1
    cpu.set_flag(Flags.h, (a & 0x0f) == 0x0)
    cpu.set_flag(Flags.n, true)
    cpu.set_flag(Flags.z, r == 0)
    return r
}

pub fn (mut cpu CPU) add_hl(n u16) {
    a := cpu.get_hl()
    r := a + n
    cpu.set_flag(Flags.c, a > 0xffff - n)
    cpu.set_flag(Flags.h, (a & 0x0fff) + (n & 0x0fff) > 0x0fff)
    cpu.set_flag(Flags.n, false)
    cpu.set_hl(r)
}

pub fn (mut cpu CPU) add_sp() {
    a := cpu.sp
    b := u16(i16(i8(cpu.immediate())))
    cpu.set_flag(Flags.c, (a & 0x00ff) + (b & 0x00ff) > 0x00ff)
    cpu.set_flag(Flags.h, (a & 0x000f) + (b & 0x000f) > 0x000f)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, false)
    cpu.sp = a + b
}

pub fn (mut cpu CPU) swap(a u8) u8 {
    cpu.set_flag(Flags.c, false)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, a == 0x00)
    return (a >> 4) | (a << 4)
}

pub fn (mut cpu CPU) daa() {
    mut a := cpu.a
    mut adjust := u8(if (cpu.f & u8(Flags.c)) != 0 { u8(0x60) } else { u8(0) })
    if (cpu.f & u8(Flags.h)) != 0 {
        adjust |= 0x06
    }
    if (cpu.f & u8(Flags.n)) == 0 {
        if (a & 0x0f) > 0x09 {
            adjust |= 0x06
        }
        if a > 0x99 {
            adjust |= 0x60
        }
        a = u8(a + adjust)
    } else {
        a = u8(a - adjust)
    }
    cpu.set_flag(Flags.c, adjust >= 0x60)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.z, a == 0x00)
    cpu.a = a
}

pub fn (mut cpu CPU) cpl() {
    cpu.a = ~cpu.a
    cpu.set_flag(Flags.h, true)
    cpu.set_flag(Flags.n, true)
}

pub fn (mut cpu CPU) ccf() {
    v := ((cpu.f & u8(Flags.c)) == 0)
    cpu.set_flag(Flags.c, v)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
}

pub fn (mut cpu CPU) scf() {
    cpu.set_flag(Flags.c, true)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
}

pub fn (mut cpu CPU) rlc(a u8) u8 {
    c := (a & 0x80) >> 7 == 0x01
    r := (a << 1) | (if c {u8(1)} else {u8(0)})
    cpu.set_flag(Flags.c, c)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    return r
}

pub fn (mut cpu CPU) rl(a u8) u8 {
    c := (a & 0x80) >> 7 == 0x01
    r := if (cpu.f & u8(Flags.c)) != 0 {(a << 1) + u8(1)} else {(a << 1)}
    cpu.set_flag(Flags.c, c)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    return r
}

pub fn (mut cpu CPU) rr(a u8) u8 {
    c := (a & 0x01) == 0x01
    r := if (cpu.f & u8(Flags.c)) != 0 { 0x80 | (a >> 1) } else { a >> 1 }
    cpu.set_flag(Flags.c, c)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    return r
}

pub fn (mut cpu CPU) rrc(a u8) u8 {
    c := (a & 0x01) == 0x01
    r := if c { 0x80 | (a >> 1) } else { a >> 1 }
    cpu.set_flag(Flags.c, c)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    return r
}

pub fn (mut cpu CPU) sla(a u8) u8 {
    c := ((a & 0x80) >> 7) == 0x01
    r := a << 1
    cpu.set_flag(Flags.c, c)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    return r
}

pub fn (mut cpu CPU) sra(a u8) u8 {
    c := (a & 0x01) == 0x01
    r := (a >> 1) | (a & 0x80)
    cpu.set_flag(Flags.c, c)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    return r
}

pub fn (mut cpu CPU) srl(a u8) u8 {
    c := (a & 0x01) == 0x01
    r := a >> 1
    cpu.set_flag(Flags.c, c)
    cpu.set_flag(Flags.h, false)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r == 0x00)
    return r
}

pub fn (mut cpu CPU) bit(a u8, b u8) {
    r := (a & (1 << b)) == 0x00
    cpu.set_flag(Flags.h, true)
    cpu.set_flag(Flags.n, false)
    cpu.set_flag(Flags.z, r)
}

pub fn (mut cpu CPU) set(a u8, b u8) u8 {
    return a | (1 << b)
}

pub fn (mut cpu CPU) res(a u8, b u8) u8 {
    return a & (~(1 << b))
}

pub fn (mut cpu CPU) jr(n u8) {
    v := i8(n)
    cpu.pc = u16(i32(cpu.pc) + i32(v))
}

pub fn (mut cpu CPU) power_up() {
    cpu.a = u8(if cpu.mem.is_gbc { 0x11 } else { 0x01 })
    cpu.f = 0xb0
    cpu.b = 0x00
    cpu.c = 0x13
    cpu.d = 0x00
    cpu.e = 0xd8
    cpu.h = 0x01
    cpu.l = 0x4d
    cpu.sp = 0xfffe
    cpu.pc = 0x100
}

pub fn (mut cpu CPU) interrupt() u32 {
    if !cpu.halted && !cpu.ei {
        return 0
    }
    mut intf := cpu.mem.get(0xff0f)
    inte := cpu.mem.get(0xffff)
    ii := intf & inte
    if ii == 0x00 {
        return 0
    }
    cpu.halted = false
    if !cpu.ei {
        return 0
    }
    cpu.ei = false

    n := trailing_zeroes(ii)
    intf = intf & ~(1 << n)
    cpu.mem.set(0xff0f, intf)

    cpu.push_stack(cpu.pc)

    cpu.pc = 0x0040 | (u16(n) << 3)
    return 4
}

// FINALLY!
fn (mut cpu CPU) nxt() u32 {
    opcode := cpu.immediate()
    //println("^ OPCODE A: ${cpu.a:02x} B: ${cpu.b:02x} C: ${cpu.c:02x} D: ${cpu.d:02x} E: ${cpu.e:02x} H: ${cpu.h:02x} L: ${cpu.l:02x} SP: ${cpu.sp:04x}")
    mut cbcode := u8(0)
    match opcode {
        0x06 { cpu.b = cpu.immediate() }
        0x0e { cpu.c = cpu.immediate() }
        0x16 { cpu.d = cpu.immediate() }
        0x1e { cpu.e = cpu.immediate() }
        0x26 { cpu.h = cpu.immediate() }
        0x2e { cpu.l = cpu.immediate() }
        0x36 {
            a := cpu.get_hl()
            v := cpu.immediate()
            cpu.mem.set(a, v)
        }
        0x3e { cpu.a = cpu.immediate() }

        0x02 { cpu.mem.set(cpu.get_bc(), cpu.a) }
        0x12 { cpu.mem.set(cpu.get_de(), cpu.a) }

        0x0a { cpu.a = cpu.mem.get(cpu.get_bc()) }
        0x1a { cpu.a = cpu.mem.get(cpu.get_de()) }

        0x22 {
            a := cpu.get_hl()
            cpu.mem.set(a, cpu.a)
            cpu.set_hl(a + 1)
        }
        0x32 {
            a := cpu.get_hl()
            cpu.mem.set(a, cpu.a)
            cpu.set_hl(a - 1)
        }
        0x2a {
            v := cpu.get_hl()
            cpu.a = cpu.mem.get(v)
            cpu.set_hl(v + 1)
        }
        0x3a { 
            v := cpu.get_hl()
            cpu.a = cpu.mem.get(v)
            cpu.set_hl(v - 1)
        }

        0x40 {} // If you are moving yourself to yourself, then you might as well do nothing...
        0x41 { cpu.b = cpu.c }
        0x42 { cpu.b = cpu.d }
        0x43 { cpu.b = cpu.e }
        0x44 { cpu.b = cpu.h }
        0x45 { cpu.b = cpu.l }
        0x46 { cpu.b = cpu.mem.get(cpu.get_hl()) }
        0x47 { cpu.b = cpu.a }
        0x48 { cpu.c = cpu.b }
        0x49 {} // Intentionally Empty
        0x4a { cpu.c = cpu.d }
        0x4b { cpu.c = cpu.e }
        0x4c { cpu.c = cpu.h }
        0x4d { cpu.c = cpu.l }
        0x4e { cpu.c = cpu.mem.get(cpu.get_hl()) }
        0x4f { cpu.c = cpu.a }
        0x50 { cpu.d = cpu.b }
        0x51 { cpu.d = cpu.c }
        0x52 {} // Intentionally Empty
        0x53 { cpu.d = cpu.e }
        0x54 { cpu.d = cpu.h }
        0x55 { cpu.d = cpu.l }
        0x56 { cpu.d = cpu.mem.get(cpu.get_hl()) }
        0x57 { cpu.d = cpu.a }
        0x58 { cpu.e = cpu.b }
        0x59 { cpu.e = cpu.c }
        0x5a { cpu.e = cpu.d }
        0x5b {} // Intentionally Empty
        0x5c { cpu.e = cpu.h }
        0x5d { cpu.e = cpu.l }
        0x5e { cpu.e = cpu.mem.get(cpu.get_hl()) }
        0x5f { cpu.e = cpu.a }
        0x60 { cpu.h = cpu.b }
        0x61 { cpu.h = cpu.c }
        0x62 { cpu.h = cpu.d }
        0x63 { cpu.h = cpu.e }
        0x64 {} // Intentionally Empty
        0x65 { cpu.h = cpu.l }
        0x66 { cpu.h = cpu.mem.get(cpu.get_hl()) }
        0x67 { cpu.h = cpu.a }
        0x68 { cpu.l = cpu.b }
        0x69 { cpu.l = cpu.c }
        0x6a { cpu.l = cpu.d }
        0x6b { cpu.l = cpu.e }
        0x6c { cpu.l = cpu.h }
        0x6d {} // Intentionally Empty
        0x6e { cpu.l = cpu.mem.get(cpu.get_hl()) }
        0x6f { cpu.l = cpu.a }
        0x70 { cpu.mem.set(cpu.get_hl(), cpu.b) }
        0x71 { cpu.mem.set(cpu.get_hl(), cpu.c) }
        0x72 { cpu.mem.set(cpu.get_hl(), cpu.d) }
        0x73 { cpu.mem.set(cpu.get_hl(), cpu.e) }
        0x74 { cpu.mem.set(cpu.get_hl(), cpu.h) }
        0x75 { cpu.mem.set(cpu.get_hl(), cpu.l) }
        0x77 { cpu.mem.set(cpu.get_hl(), cpu.a) }
        0x78 { cpu.a = cpu.b }
        0x79 { cpu.a = cpu.c }
        0x7a { cpu.a = cpu.d }
        0x7b { cpu.a = cpu.e }
        0x7c { cpu.a = cpu.h }
        0x7d { cpu.a = cpu.l }
        0x7e { cpu.a = cpu.mem.get(cpu.get_hl()) }
        0x7f {} // Intentionally Empty

        0xe0 {
            a := 0xff00 | u16(cpu.immediate())
            cpu.mem.set(a, cpu.a)
        }

        0xf0 {
            a := 0xff00 | u16(cpu.immediate())
            cpu.a = cpu.mem.get(a)
        }

        0xe2 { cpu.mem.set(0xff00 | u16(cpu.c), cpu.a) }

        0xf2 { cpu.a = cpu.mem.get(0xff00 | u16(cpu.c)) }

        0xea { cpu.mem.set(cpu.immediate_word(), cpu.a) }

        0xfa { cpu.a = cpu.mem.get(cpu.immediate_word()) }

        0x01 { cpu.set_bc(cpu.immediate_word()) }
        0x11 { cpu.set_de(cpu.immediate_word()) }
        0x21 { cpu.set_hl(cpu.immediate_word()) }
        0x31 { cpu.sp = cpu.immediate_word() }

        0xf9 { cpu.sp = cpu.get_hl() }
        0xf8 {
            a := cpu.sp
            b := u16(i16(i8(cpu.immediate())))
            cpu.set_flag(Flags.c, (a & 0x00ff) + (b & 0x00ff) > 0x00ff)
            cpu.set_flag(Flags.h, (a & 0x000f) + (b & 0x000f) > 0x000f)
            cpu.set_flag(Flags.n, false)
            cpu.set_flag(Flags.z, false)
            cpu.set_hl(a+b)
        }
        0x08 { cpu.mem.set_word(cpu.immediate_word(), cpu.sp) }

        0xc5 { cpu.push_stack(cpu.get_bc()) }
        0xd5 { cpu.push_stack(cpu.get_de()) }
        0xe5 { cpu.push_stack(cpu.get_hl()) }
        0xf5 { cpu.push_stack(cpu.get_af()) }

        0xc1 { cpu.set_bc(cpu.pop_stack()) }
        0xf1 { cpu.set_af(cpu.pop_stack()) }
        0xd1 { cpu.set_de(cpu.pop_stack()) }
        0xe1 { cpu.set_hl(cpu.pop_stack()) }

        0x80 { cpu.add(cpu.b) }
        0x81 { cpu.add(cpu.c) }
        0x82 { cpu.add(cpu.d) }
        0x83 { cpu.add(cpu.e) }
        0x84 { cpu.add(cpu.h) }
        0x85 { cpu.add(cpu.l) }
        0x86 {
            a := cpu.mem.get(cpu.get_hl())
            cpu.add(a)
        }
        0x87 { cpu.add(cpu.a) }
        0xc6 { cpu.add(cpu.immediate()) }

        0x88 { cpu.adc(cpu.b) }
        0x89 { cpu.adc(cpu.c) }
        0x8a { cpu.adc(cpu.d) }
        0x8b { cpu.adc(cpu.e) }
        0x8c { cpu.adc(cpu.h) }
        0x8d { cpu.adc(cpu.l) }
        0x8e {
            a := cpu.mem.get(cpu.get_hl())
            cpu.adc(a)
        }
        0x8f { cpu.adc(cpu.a) }
        0xce { cpu.adc(cpu.immediate()) }

        0x90 { cpu.sub(cpu.b) }
        0x91 { cpu.sub(cpu.c) }
        0x92 { cpu.sub(cpu.d) }
        0x93 { cpu.sub(cpu.e) }
        0x94 { cpu.sub(cpu.h) }
        0x95 { cpu.sub(cpu.l) }
        0x96 {
            a := cpu.mem.get(cpu.get_hl())
            cpu.sub(a)
        }
        0x97 { cpu.sub(cpu.a) }
        0xd6 { cpu.sub(cpu.immediate()) }

        0x98 { cpu.sbc(cpu.b) }
        0x99 { cpu.sbc(cpu.c) }
        0x9a { cpu.sbc(cpu.d) }
        0x9b { cpu.sbc(cpu.e) }
        0x9c { cpu.sbc(cpu.h) }
        0x9d { cpu.sbc(cpu.l) }
        0x9e {
            a := cpu.mem.get(cpu.get_hl())
            cpu.sbc(a)
        }
        0x9f { cpu.sbc(cpu.a) }
        0xde { cpu.sbc(cpu.immediate()) }

        0xa0 { cpu.and(cpu.b) }
        0xa1 { cpu.and(cpu.c) }
        0xa2 { cpu.and(cpu.d) }
        0xa3 { cpu.and(cpu.e) }
        0xa4 { cpu.and(cpu.h) }
        0xa5 { cpu.and(cpu.l) }
        0xa6 {
            a := cpu.mem.get(cpu.get_hl())
            cpu.and(a)
        }
        0xa7 { cpu.and(cpu.a) }
        0xe6 { cpu.and(cpu.immediate()) }

        0xb0 { cpu.or_(cpu.b) }
        0xb1 { cpu.or_(cpu.c) }
        0xb2 { cpu.or_(cpu.d) }
        0xb3 { cpu.or_(cpu.e) }
        0xb4 { cpu.or_(cpu.h) }
        0xb5 { cpu.or_(cpu.l) }
        0xb6 {
            a := cpu.mem.get(cpu.get_hl())
            cpu.or_(a)
        }
        0xb7 { cpu.or_(cpu.a) }
        0xf6 { cpu.or_(cpu.immediate()) }

        0xa8 { cpu.xor(cpu.b) }
        0xa9 { cpu.xor(cpu.c) }
        0xaa { cpu.xor(cpu.d) }
        0xab { cpu.xor(cpu.e) }
        0xac { cpu.xor(cpu.h) }
        0xad { cpu.xor(cpu.l) }
        0xae {
            a := cpu.mem.get(cpu.get_hl())
            cpu.xor(a)
        }
        0xaf { cpu.xor(cpu.a) }
        0xee { cpu.xor(cpu.immediate()) }

        0xb8 { cpu.cp(cpu.b) }
        0xb9 { cpu.cp(cpu.c) }
        0xba { cpu.cp(cpu.d) }
        0xbb { cpu.cp(cpu.e) }
        0xbc { cpu.cp(cpu.h) }
        0xbd { cpu.cp(cpu.l) }
        0xbe {
            a := cpu.mem.get(cpu.get_hl())
            cpu.cp(a)
        }
        0xbf { cpu.cp(cpu.a) }
        0xfe { cpu.cp(cpu.immediate()) }

        0x04 { cpu.b = cpu.inc(cpu.b) }
        0x0c { cpu.c = cpu.inc(cpu.c) }
        0x14 { cpu.d = cpu.inc(cpu.d) }
        0x1c { cpu.e = cpu.inc(cpu.e) }
        0x24 { cpu.h = cpu.inc(cpu.h) }
        0x2c { cpu.l = cpu.inc(cpu.l) }
        0x34 {
            a := cpu.get_hl()
            v := cpu.mem.get(a)
            h := cpu.inc(v)
            cpu.mem.set(a, h)
        }
        0x3c { cpu.a = cpu.inc(cpu.a) }

        0x05 { cpu.b = cpu.dec(cpu.b) }
        0x0d { cpu.c = cpu.dec(cpu.c) }
        0x15 { cpu.d = cpu.dec(cpu.d) }
        0x1d { cpu.e = cpu.dec(cpu.e) }
        0x25 { cpu.h = cpu.dec(cpu.h) }
        0x2d { cpu.l = cpu.dec(cpu.l) }
        0x35 {
            a := cpu.get_hl()
            v := cpu.mem.get(a)
            h := cpu.dec(v)
            cpu.mem.set(a, h)
        }
        0x3d { cpu.a = cpu.dec(cpu.a) }

        0x09 { cpu.add_hl(cpu.get_bc()) }
        0x19 { cpu.add_hl(cpu.get_de()) }
        0x29 { cpu.add_hl(cpu.get_hl()) }
        0x39 { cpu.add_hl(cpu.sp) }

        0xe8 { cpu.add_sp() }

        0x03 { cpu.set_bc(cpu.get_bc() + 1) }
        0x13 { cpu.set_de(cpu.get_de() + 1) }
        0x23 { cpu.set_hl(cpu.get_hl() + 1) }
        0x33 { cpu.sp = cpu.sp + 1}

        0x0b { cpu.set_bc(cpu.get_bc() - 1) }
        0x1b { cpu.set_de(cpu.get_de() - 1) }
        0x2b { cpu.set_hl(cpu.get_hl() - 1) }
        0x3b { cpu.sp = cpu.sp - 1 }

        0x27 { cpu.daa() }
        0x2f { cpu.cpl() }
        0x3f { cpu.ccf() }
        0x37 { cpu.scf() }

        0x00 {} // Intentionally Empty
        0x76 { cpu.halted = true }
        0x10 {} // Intentionally Empty
        0xf3 { cpu.ei = false }
        0xfb { cpu.ei = true }

        0x07 {
            cpu.a = cpu.rlc(cpu.a)
            cpu.set_flag(Flags.z, false)
        }
        0x17 {
            cpu.a = cpu.rl(cpu.a)
            cpu.set_flag(Flags.z, false)
        }
        0x0f {
            cpu.a = cpu.rrc(cpu.a)
            cpu.set_flag(Flags.z, false)
        }
        0x1f {
            cpu.a = cpu.rr(cpu.a)
            cpu.set_flag(Flags.z, false)
        }

        0xc3 { cpu.pc = cpu.immediate_word() }
        0xe9 { cpu.pc = cpu.get_hl() }
        0xc2 {
            pc := cpu.immediate_word()
            if (cpu.f & u8(Flags.z)) == 0 { cpu.pc = pc }
        }
        0xca {
            pc := cpu.immediate_word()
            if (cpu.f & u8(Flags.z)) != 0 { cpu.pc = pc }
        }
        0xd2 {
            pc := cpu.immediate_word()
            if (cpu.f & u8(Flags.c)) == 0 { cpu.pc = pc }
        }
        0xda {
            pc := cpu.immediate_word()
            if (cpu.f & u8(Flags.c)) != 0 { cpu.pc = pc }
        }

        0x18 { cpu.jr(cpu.immediate()) }
        0x20 {
            n := cpu.immediate()
            if (cpu.f & u8(Flags.z)) == 0 { cpu.jr(n) }
        }
        0x28 {
            n := cpu.immediate()
            if (cpu.f & u8(Flags.z)) != 0 { cpu.jr(n) }
        }
        0x30 {
            n := cpu.immediate()
            if (cpu.f & u8(Flags.c)) == 0 { cpu.jr(n) }
        }
        0x38 {
            n := cpu.immediate()
            if (cpu.f & u8(Flags.c)) != 0 { cpu.jr(n) }
        }

        0xcd {
            nn := cpu.immediate_word()
            cpu.push_stack(cpu.pc)
            cpu.pc = nn
        }
        0xc4 {
            nn := cpu.immediate_word()
            if (cpu.f & u8(Flags.z)) == 0 {
                cpu.push_stack(cpu.pc)
                cpu.pc = nn
            }
        }
        0xcc {
            nn := cpu.immediate_word()
            if (cpu.f & u8(Flags.z)) != 0 {
                cpu.push_stack(cpu.pc)
                cpu.pc = nn
            }
        }
        0xd4 {
            nn := cpu.immediate_word()
            if (cpu.f & u8(Flags.c)) == 0 {
                cpu.push_stack(cpu.pc)
                cpu.pc = nn
            }
        }
        0xdc {
            nn := cpu.immediate_word()
            if (cpu.f & u8(Flags.c)) != 0 {
                cpu.push_stack(cpu.pc)
                cpu.pc = nn
            }
        }

        0xc7 {
            cpu.push_stack(cpu.pc)
            cpu.pc = 0x00
        }
        0xcf {
            cpu.push_stack(cpu.pc)
            cpu.pc = 0x08
        }
        0xd7 {
            cpu.push_stack(cpu.pc)
            cpu.pc = 0x10
        }
        0xdf {
            cpu.push_stack(cpu.pc)
            cpu.pc = 0x18
        }
        0xe7 {
            cpu.push_stack(cpu.pc)
            cpu.pc = 0x20
        }
        0xef {
            cpu.push_stack(cpu.pc)
            cpu.pc = 0x28
        }
        0xf7 {
            cpu.push_stack(cpu.pc)
            cpu.pc = 0x30
        }
        0xff {
            cpu.push_stack(cpu.pc)
            cpu.pc = 0x38
        }

        0xc9 { cpu.pc = cpu.pop_stack() }
        0xc0 { if (cpu.f & u8(Flags.z)) == 0 { cpu.pc = cpu.pop_stack() } }
        0xc8 { if (cpu.f & u8(Flags.z)) != 0 { cpu.pc = cpu.pop_stack() } }
        0xd0 { if (cpu.f & u8(Flags.c)) == 0 { cpu.pc = cpu.pop_stack() } }
        0xd8 { if (cpu.f & u8(Flags.c)) != 0 { cpu.pc = cpu.pop_stack() } }

        0xd9 {
            cpu.pc = cpu.pop_stack()
            cpu.ei = true
        }

        0xcb { // Oh boy, here comes the extended bit operations...
            cbcode = cpu.mem.get(cpu.pc)
            cpu.pc += 1
            match cbcode {
                0x00 { cpu.b = cpu.rlc(cpu.b) }
                0x01 { cpu.c = cpu.rlc(cpu.c) }
                0x02 { cpu.d = cpu.rlc(cpu.d) }
                0x03 { cpu.e = cpu.rlc(cpu.e) }
                0x04 { cpu.h = cpu.rlc(cpu.h) }
                0x05 { cpu.l = cpu.rlc(cpu.l) }
                0x06 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.rlc(v)
                    cpu.mem.set(a, h)
                }
                0x07 { cpu.a = cpu.rlc(cpu.a) }

                0x08 { cpu.b = cpu.rrc(cpu.b) }
                0x09 { cpu.c = cpu.rrc(cpu.c) }
                0x0a { cpu.d = cpu.rrc(cpu.d) }
                0x0b { cpu.e = cpu.rrc(cpu.e) }
                0x0c { cpu.h = cpu.rrc(cpu.h) }
                0x0d { cpu.l = cpu.rrc(cpu.l) }
                0x0e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.rrc(v)
                    cpu.mem.set(a, h)
                }
                0x0f { cpu.a = cpu.rrc(cpu.a) }

                0x10 { cpu.b = cpu.rl(cpu.b) }
                0x11 { cpu.c = cpu.rl(cpu.c) }
                0x12 { cpu.d = cpu.rl(cpu.d) }
                0x13 { cpu.e = cpu.rl(cpu.e) }
                0x14 { cpu.h = cpu.rl(cpu.h) }
                0x15 { cpu.l = cpu.rl(cpu.l) }
                0x16 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.rl(v)
                    cpu.mem.set(a, h)
                }
                0x17 { cpu.a = cpu.rl(cpu.a) }

                0x18 { cpu.b = cpu.rr(cpu.b) }
                0x19 { cpu.c = cpu.rr(cpu.c) }
                0x1a { cpu.d = cpu.rr(cpu.d) }
                0x1b { cpu.e = cpu.rr(cpu.e) }
                0x1c { cpu.h = cpu.rr(cpu.h) }
                0x1d { cpu.l = cpu.rr(cpu.l) }
                0x1e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.rr(v)
                    cpu.mem.set(a, h)
                }
                0x1f { cpu.a = cpu.rr(cpu.a) }

                0x20 { cpu.b = cpu.sla(cpu.b) }
                0x21 { cpu.c = cpu.sla(cpu.c) }
                0x22 { cpu.d = cpu.sla(cpu.d) }
                0x23 { cpu.e = cpu.sla(cpu.e) }
                0x24 { cpu.h = cpu.sla(cpu.h) }
                0x25 { cpu.l = cpu.sla(cpu.l) }
                0x26 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.sla(v)
                    cpu.mem.set(a, h)
                }
                0x27 { cpu.a = cpu.sla(cpu.a) }

                0x28 { cpu.b = cpu.sra(cpu.b) }
                0x29 { cpu.c = cpu.sra(cpu.c) }
                0x2a { cpu.d = cpu.sra(cpu.d) }
                0x2b { cpu.e = cpu.sra(cpu.e) }
                0x2c { cpu.h = cpu.sra(cpu.h) }
                0x2d { cpu.l = cpu.sra(cpu.l) }
                0x2e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.sra(v)
                    cpu.mem.set(a, h)
                }
                0x2f { cpu.a = cpu.sra(cpu.a) }

                0x30 { cpu.b = cpu.swap(cpu.b) }
                0x31 { cpu.c = cpu.swap(cpu.c) }
                0x32 { cpu.d = cpu.swap(cpu.d) }
                0x33 { cpu.e = cpu.swap(cpu.e) }
                0x34 { cpu.h = cpu.swap(cpu.h) }
                0x35 { cpu.l = cpu.swap(cpu.l) }
                0x36 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.swap(v)
                    cpu.mem.set(a, h)
                }
                0x37 { cpu.a = cpu.swap(cpu.a) }

                0x38 { cpu.b = cpu.srl(cpu.b) }
                0x39 { cpu.c = cpu.srl(cpu.c) }
                0x3a { cpu.d = cpu.srl(cpu.d) }
                0x3b { cpu.e = cpu.srl(cpu.e) }
                0x3c { cpu.h = cpu.srl(cpu.h) }
                0x3d { cpu.l = cpu.srl(cpu.l) }
                0x3e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.srl(v)
                    cpu.mem.set(a, h)
                }
                0x3f { cpu.a = cpu.srl(cpu.a) }

                0x40 { cpu.bit(cpu.b, 0) }
                0x41 { cpu.bit(cpu.c, 0) }
                0x42 { cpu.bit(cpu.d, 0) }
                0x43 { cpu.bit(cpu.e, 0) }
                0x44 { cpu.bit(cpu.h, 0) }
                0x45 { cpu.bit(cpu.l, 0) }
                0x46 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    cpu.bit(v, 0)
                }
                0x47 { cpu.bit(cpu.a, 0) }

                0x48 { cpu.bit(cpu.b, 1) }
                0x49 { cpu.bit(cpu.c, 1) }
                0x4a { cpu.bit(cpu.d, 1) }
                0x4b { cpu.bit(cpu.e, 1) }
                0x4c { cpu.bit(cpu.h, 1) }
                0x4d { cpu.bit(cpu.l, 1) }
                0x4e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    cpu.bit(v, 1)
                }
                0x4f { cpu.bit(cpu.a, 1) }

                0x50 { cpu.bit(cpu.b, 2) }
                0x51 { cpu.bit(cpu.c, 2) }
                0x52 { cpu.bit(cpu.d, 2) }
                0x53 { cpu.bit(cpu.e, 2) }
                0x54 { cpu.bit(cpu.h, 2) }
                0x55 { cpu.bit(cpu.l, 2) }
                0x56 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    cpu.bit(v, 2)
                }
                0x57 { cpu.bit(cpu.a, 2) }
                
                0x58 { cpu.bit(cpu.b, 3) }
                0x59 { cpu.bit(cpu.c, 3) }
                0x5a { cpu.bit(cpu.d, 3) }
                0x5b { cpu.bit(cpu.e, 3) }
                0x5c { cpu.bit(cpu.h, 3) }
                0x5d { cpu.bit(cpu.l, 3) }
                0x5e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    cpu.bit(v, 3)
                }
                0x5f { cpu.bit(cpu.a, 3) }

                0x60 { cpu.bit(cpu.b, 4) }
                0x61 { cpu.bit(cpu.c, 4) }
                0x62 { cpu.bit(cpu.d, 4) }
                0x63 { cpu.bit(cpu.e, 4) }
                0x64 { cpu.bit(cpu.h, 4) }
                0x65 { cpu.bit(cpu.l, 4) }
                0x66 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    cpu.bit(v, 4)
                }
                0x67 { cpu.bit(cpu.a, 4) }

                0x68 { cpu.bit(cpu.b, 5) }
                0x69 { cpu.bit(cpu.c, 5) }
                0x6a { cpu.bit(cpu.d, 5) }
                0x6b { cpu.bit(cpu.e, 5) }
                0x6c { cpu.bit(cpu.h, 5) }
                0x6d { cpu.bit(cpu.l, 5) }
                0x6e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    cpu.bit(v, 5)
                }
                0x6f { cpu.bit(cpu.a, 5) }

                0x70 { cpu.bit(cpu.b, 6) }
                0x71 { cpu.bit(cpu.c, 6) }
                0x72 { cpu.bit(cpu.d, 6) }
                0x73 { cpu.bit(cpu.e, 6) }
                0x74 { cpu.bit(cpu.h, 6) }
                0x75 { cpu.bit(cpu.l, 6) }
                0x76 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    cpu.bit(v, 6)
                }
                0x77 { cpu.bit(cpu.a, 6) }

                0x78 { cpu.bit(cpu.b, 7) }
                0x79 { cpu.bit(cpu.c, 7) }
                0x7a { cpu.bit(cpu.d, 7) }
                0x7b { cpu.bit(cpu.e, 7) }
                0x7c { cpu.bit(cpu.h, 7) }
                0x7d { cpu.bit(cpu.l, 7) }
                0x7e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    cpu.bit(v, 7)
                }
                0x7f { cpu.bit(cpu.a, 7) }

                0x80 { cpu.b = cpu.res(cpu.b, 0) }
                0x81 { cpu.c = cpu.res(cpu.c, 0) }
                0x82 { cpu.d = cpu.res(cpu.d, 0) }
                0x83 { cpu.e = cpu.res(cpu.e, 0) }
                0x84 { cpu.h = cpu.res(cpu.h, 0) }
                0x85 { cpu.l = cpu.res(cpu.l, 0) }
                0x86 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.res(v, 0)
                    cpu.mem.set(a, h)
                }
                0x87 { cpu.a = cpu.res(cpu.a, 0) }

                0x88 { cpu.b = cpu.res(cpu.b, 1) }
                0x89 { cpu.c = cpu.res(cpu.c, 1) }
                0x8a { cpu.d = cpu.res(cpu.d, 1) }
                0x8b { cpu.e = cpu.res(cpu.e, 1) }
                0x8c { cpu.h = cpu.res(cpu.h, 1) }
                0x8d { cpu.l = cpu.res(cpu.l, 1) }
                0x8e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.res(v, 1)
                    cpu.mem.set(a, h)
                }
                0x8f { cpu.a = cpu.res(cpu.a, 1) }

                0x90 { cpu.b = cpu.res(cpu.b, 2) }
                0x91 { cpu.c = cpu.res(cpu.c, 2) }
                0x92 { cpu.d = cpu.res(cpu.d, 2) }
                0x93 { cpu.e = cpu.res(cpu.e, 2) }
                0x94 { cpu.h = cpu.res(cpu.h, 2) }
                0x95 { cpu.l = cpu.res(cpu.l, 2) }
                0x96 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.res(v, 2)
                    cpu.mem.set(a, h)
                }
                0x97 { cpu.a = cpu.res(cpu.a, 2) }

                0x98 { cpu.b = cpu.res(cpu.b, 3) }
                0x99 { cpu.c = cpu.res(cpu.c, 3) }
                0x9a { cpu.d = cpu.res(cpu.d, 3) }
                0x9b { cpu.e = cpu.res(cpu.e, 3) }
                0x9c { cpu.h = cpu.res(cpu.h, 3) }
                0x9d { cpu.l = cpu.res(cpu.l, 3) }
                0x9e {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.res(v, 3)
                    cpu.mem.set(a, h)
                }
                0x9f { cpu.a = cpu.res(cpu.a, 3) }

                0xa0 { cpu.b = cpu.res(cpu.b, 4) }
                0xa1 { cpu.c = cpu.res(cpu.c, 4) }
                0xa2 { cpu.d = cpu.res(cpu.d, 4) }
                0xa3 { cpu.e = cpu.res(cpu.e, 4) }
                0xa4 { cpu.h = cpu.res(cpu.h, 4) }
                0xa5 { cpu.l = cpu.res(cpu.l, 4) }
                0xa6 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.res(v, 4)
                    cpu.mem.set(a, h)
                }
                0xa7 { cpu.a = cpu.res(cpu.a, 4) }

                0xa8 { cpu.b = cpu.res(cpu.b, 5) }
                0xa9 { cpu.c = cpu.res(cpu.c, 5) }
                0xaa { cpu.d = cpu.res(cpu.d, 5) }
                0xab { cpu.e = cpu.res(cpu.e, 5) }
                0xac { cpu.h = cpu.res(cpu.h, 5) }
                0xad { cpu.l = cpu.res(cpu.l, 5) }
                0xae {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.res(v, 5)
                    cpu.mem.set(a, h)
                }
                0xaf { cpu.a = cpu.res(cpu.a, 5) }

                0xb0 { cpu.b = cpu.res(cpu.b, 6) }
                0xb1 { cpu.c = cpu.res(cpu.c, 6) }
                0xb2 { cpu.d = cpu.res(cpu.d, 6) }
                0xb3 { cpu.e = cpu.res(cpu.e, 6) }
                0xb4 { cpu.h = cpu.res(cpu.h, 6) }
                0xb5 { cpu.l = cpu.res(cpu.l, 6) }
                0xb6 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.res(v, 6)
                    cpu.mem.set(a, h)
                }
                0xb7 { cpu.a = cpu.res(cpu.a, 6) }

                0xb8 { cpu.b = cpu.res(cpu.b, 7) }
                0xb9 { cpu.c = cpu.res(cpu.c, 7) }
                0xba { cpu.d = cpu.res(cpu.d, 7) }
                0xbb { cpu.e = cpu.res(cpu.e, 7) }
                0xbc { cpu.h = cpu.res(cpu.h, 7) }
                0xbd { cpu.l = cpu.res(cpu.l, 7) }
                0xbe {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.res(v, 7)
                    cpu.mem.set(a, h)
                }
                0xbf { cpu.a = cpu.res(cpu.a, 7) }

                0xc0 { cpu.b = cpu.set(cpu.b, 0) }
                0xc1 { cpu.c = cpu.set(cpu.c, 0) }
                0xc2 { cpu.d = cpu.set(cpu.d, 0) }
                0xc3 { cpu.e = cpu.set(cpu.e, 0) }
                0xc4 { cpu.h = cpu.set(cpu.h, 0) }
                0xc5 { cpu.l = cpu.set(cpu.l, 0) }
                0xc6 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.set(v, 0)
                    cpu.mem.set(a, h)
                }
                0xc7 { cpu.a = cpu.set(cpu.a, 0) }

                0xc8 { cpu.b = cpu.set(cpu.b, 1) }
                0xc9 { cpu.c = cpu.set(cpu.c, 1) }
                0xca { cpu.d = cpu.set(cpu.d, 1) }
                0xcb { cpu.e = cpu.set(cpu.e, 1) }
                0xcc { cpu.h = cpu.set(cpu.h, 1) }
                0xcd { cpu.l = cpu.set(cpu.l, 1) }
                0xce {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.set(v, 1)
                    cpu.mem.set(a, h)
                }
                0xcf { cpu.a = cpu.set(cpu.a, 1) }

                0xd0 { cpu.b = cpu.set(cpu.b, 2) }
                0xd1 { cpu.c = cpu.set(cpu.c, 2) }
                0xd2 { cpu.d = cpu.set(cpu.d, 2) }
                0xd3 { cpu.e = cpu.set(cpu.e, 2) }
                0xd4 { cpu.h = cpu.set(cpu.h, 2) }
                0xd5 { cpu.l = cpu.set(cpu.l, 2) }
                0xd6 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.set(v, 2)
                    cpu.mem.set(a, h)
                }
                0xd7 { cpu.a = cpu.set(cpu.a, 2) }

                0xd8 { cpu.b = cpu.set(cpu.b, 3) }
                0xd9 { cpu.c = cpu.set(cpu.c, 3) }
                0xda { cpu.d = cpu.set(cpu.d, 3) }
                0xdb { cpu.e = cpu.set(cpu.e, 3) }
                0xdc { cpu.h = cpu.set(cpu.h, 3) }
                0xdd { cpu.l = cpu.set(cpu.l, 3) }
                0xde {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.set(v, 3)
                    cpu.mem.set(a, h)
                }
                0xdf { cpu.a = cpu.set(cpu.a, 3) }

                0xe0 { cpu.b = cpu.set(cpu.b, 4) }
                0xe1 { cpu.c = cpu.set(cpu.c, 4) }
                0xe2 { cpu.d = cpu.set(cpu.d, 4) }
                0xe3 { cpu.e = cpu.set(cpu.e, 4) }
                0xe4 { cpu.h = cpu.set(cpu.h, 4) }
                0xe5 { cpu.l = cpu.set(cpu.l, 4) }
                0xe6 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.set(v, 4)
                    cpu.mem.set(a, h)
                }
                0xe7 { cpu.a = cpu.set(cpu.a, 4) }

                0xe8 { cpu.b = cpu.set(cpu.b, 5) }
                0xe9 { cpu.c = cpu.set(cpu.c, 5) }
                0xea { cpu.d = cpu.set(cpu.d, 5) }
                0xeb { cpu.e = cpu.set(cpu.e, 5) }
                0xec { cpu.h = cpu.set(cpu.h, 5) }
                0xed { cpu.l = cpu.set(cpu.l, 5) }
                0xee {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.set(v, 5)
                    cpu.mem.set(a, h)
                }
                0xef { cpu.a = cpu.set(cpu.a, 5) }

                0xf0 { cpu.b = cpu.set(cpu.b, 6) }
                0xf1 { cpu.c = cpu.set(cpu.c, 6) }
                0xf2 { cpu.d = cpu.set(cpu.d, 6) }
                0xf3 { cpu.e = cpu.set(cpu.e, 6) }
                0xf4 { cpu.h = cpu.set(cpu.h, 6) }
                0xf5 { cpu.l = cpu.set(cpu.l, 6) }
                0xf6 {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.set(v, 6)
                    cpu.mem.set(a, h)
                }
                0xf7 { cpu.a = cpu.set(cpu.a, 6) }

                0xf8 { cpu.b = cpu.set(cpu.b, 7) }
                0xf9 { cpu.c = cpu.set(cpu.c, 7) }
                0xfa { cpu.d = cpu.set(cpu.d, 7) }
                0xfb { cpu.e = cpu.set(cpu.e, 7) }
                0xfc { cpu.h = cpu.set(cpu.h, 7) }
                0xfd { cpu.l = cpu.set(cpu.l, 7) }
                0xfe {
                    a := cpu.get_hl()
                    v := cpu.mem.get(a)
                    h := cpu.set(v, 7)
                    cpu.mem.set(a, h)
                }
                0xff { cpu.a = cpu.set(cpu.a, 7) }

                else { panic("You shouldn't be seeing this...") }
            }
        }

        else {
            C.show_alert("Opcode 0x${opcode:02x} is not supported by Lugia! Executed at 0x${cpu.pc:04x}")
        }
    }
    ecycle := match opcode {
        0x20 { if (cpu.f & u8(Flags.z)) != 0 { 0x00 } else { 0x01 } }
        0x30 { if (cpu.f & u8(Flags.z)) != 0 { 0x00 } else { 0x01 } }
        0x28 { if (cpu.f & u8(Flags.z)) != 0 { 0x01 } else { 0x00 } }
        0x38 { if (cpu.f & u8(Flags.z)) != 0 { 0x01 } else { 0x00 } }
        0xc0 { if (cpu.f & u8(Flags.z)) != 0 { 0x00 } else { 0x03 } }
        0xd0 { if (cpu.f & u8(Flags.z)) != 0 { 0x00 } else { 0x03 } }
        0xc8 { if (cpu.f & u8(Flags.z)) != 0 { 0x03 } else { 0x00 } }
        0xcc { if (cpu.f & u8(Flags.z)) != 0 { 0x03 } else { 0x00 } }
        0xd8 { if (cpu.f & u8(Flags.z)) != 0 { 0x03 } else { 0x00 } }
        0xdc { if (cpu.f & u8(Flags.z)) != 0 { 0x03 } else { 0x00 } }
        0xc2 { if (cpu.f & u8(Flags.z)) != 0 { 0x00 } else { 0x01 } }
        0xd2 { if (cpu.f & u8(Flags.z)) != 0 { 0x00 } else { 0x01 } }
        0xca { if (cpu.f & u8(Flags.z)) != 0 { 0x01 } else { 0x00 } }
        0xda { if (cpu.f & u8(Flags.z)) != 0 { 0x01 } else { 0x00 } }
        0xc4 { if (cpu.f & u8(Flags.z)) != 0 { 0x00 } else { 0x03 } }
        0xd4 { if (cpu.f & u8(Flags.z)) != 0 { 0x00 } else { 0x03 } }
        else { 0x00 }
    }
    if opcode == 0xcb {
        return cb_cycle_timings[cbcode]
    } else {
        return gbn_cycle_timings[opcode] + u32(ecycle)
    }
}

pub fn (mut cpu CPU) next() u32 {
    mut mac := u32(0)
    c := cpu.interrupt()
    if c != 0 {
        mac = c
    } else if cpu.halted {
        mac = gbn_cycle_timings[0]
    } else {
        mac = cpu.nxt()
    }
    return mac * 4
}

pub struct RealTimePerfCPU {
pub mut:
    cpu CPU
mut:
    step_cycles u32
    stopwatch time.StopWatch
    step_flip bool
}

pub fn new_rtpcpu(path string, audio &AudioPlayer) &RealTimePerfCPU {
    return &RealTimePerfCPU {
        cpu: new_cpu(path,audio)
        step_cycles: 0
        stopwatch: time.new_stopwatch(time.StopWatchOptions {auto_start: true})
        step_flip: false
    }
}

pub fn (mut self RealTimePerfCPU) next() u32 {
    if self.step_cycles > step_cycle_total {
        self.step_flip = true
        self.step_cycles -= step_cycle_total
        now := self.stopwatch.elapsed()
        time.sleep(time.Duration(math.max(i64(0),(step_time*1000000) - i64(now))))
        self.stopwatch.restart()
    }
    cycles := self.cpu.next()
    self.step_cycles += cycles
    return cycles
}

pub fn (mut self RealTimePerfCPU) flip() bool {
    r := self.step_flip
    if r { self.step_flip = false }
    return r
}