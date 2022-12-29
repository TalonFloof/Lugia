module core

pub enum Shade as u8 {
    white = u8(0xff)
    light_gray = 0xc0
    dark_gray = 0x60
    black = 0x00
}

pub struct HDMA {
mut:
    src u16
    dst u16
    active bool
    mode u8
    remain u8
}

pub fn new_hdma() &HDMA {
    return &HDMA {
        src: 0x0000
        dst: 0x8000
        active: false
        mode: 0
        remain: 0x00
    }
}

pub fn (self &HDMA) get(a u16) u8 {
    return match a {
        0xff51 { u8(self.src >> 8) }
        0xff52 { u8(self.src & 0xFF) }
        0xff53 { u8(self.dst >> 8) }
        0xff54 { u8(self.dst & 0xFF) }
        0xff55 { u8(self.remain | if self.active { 0x00 } else { 0x80 }) }
        else {panic("")}
    }
}

pub fn (mut self HDMA) set(a u16, v u8) {
    match a {
        0xff51 { self.src = (u16(v) << 8) | (self.src & 0x00ff) }
        0xff52 { self.src = (self.src & 0xff00) | u16(v & 0xf0) }
        0xff53 { self.dst = 0x8000 | (u16(v & 0x1f) << 8) | (self.dst & 0x00ff) }
        0xff54 { self.dst = (self.dst & 0xff00) | u16(v & 0xf0) }
        0xff55 {
            if self.active && self.mode == 1 {
                if v & 0x80 == 0x00 {
                    self.active = false
                }
                return
            }
            self.active = true
            self.remain = v & 0x7f
            self.mode = if v & 0x80 != 0x00 {
                u8(1)
            } else {
                u8(0)
            }
        }
        else {panic("")}
    }
}

type Lcdc = u8

fn (self Lcdc) bit7() bool { return self & 0b1000_0000 != 0x00 }
fn (self Lcdc) bit6() bool { return self & 0b0100_0000 != 0x00 }
fn (self Lcdc) bit5() bool { return self & 0b0010_0000 != 0x00 }
fn (self Lcdc) bit4() bool { return self & 0b0001_0000 != 0x00 }
fn (self Lcdc) bit3() bool { return self & 0b0000_1000 != 0x00 }
fn (self Lcdc) bit2() bool { return self & 0b0000_0100 != 0x00 }
fn (self Lcdc) bit1() bool { return self & 0b0000_0010 != 0x00 }
fn (self Lcdc) bit0() bool { return self & 0b0000_0001 != 0x00 }

pub struct GPUPrio {
mut:
    a bool
    b usize
}

pub struct GPUAttr {
mut:
    priority bool
    yflip bool
    xflip bool
    palette_number_0 usize
    bank bool
    palette_number_1 usize
}

pub fn attr_from(v u8) GPUAttr {
    return GPUAttr {
        priority: v & (1 << 7) != 0
        yflip: v & (1 << 6) != 0
        xflip: v & (1 << 5) != 0
        palette_number_0: usize(v) & (1 << 4)
        bank: v & (1 << 3) != 0
        palette_number_1: usize(v) & 0x07
    }
}

pub struct GPU {
pub mut:
    data [144][160][3]u8
    intf &&Intf
    is_gbc bool
    h_blank bool
    v_blank bool

    lcdc Lcdc = Lcdc(0b0100_1000)

    enable_ly_interrupt bool // Coincidence (That's actualy what it's called)
    enable_m2_interrupt bool // OAM
    enable_m1_interrupt bool // V-Blank
    enable_m0_interrupt bool // H-Blank
    int_mode u8

    scroll_x u8
    scroll_y u8

    window_x u8
    window_y u8

    scan_y u8
    scan_yc u8

    bgp u8
    op0 u8
    op1 u8 = 0x01

    cbg_i u8
    cbg_inc bool
    cbg_pd [][][]u8

    cob_i u8
    cob_inc bool
    cob_pd [][][]u8

    vram []u8
    vram_bank u8

    oam []u8

    prio []GPUPrio

    dots u32
}

pub fn new_gpu(is_gbc bool, intf &&Intf) &GPU {
    return &GPU {
        data: [144][160][3]u8{init: [160][3]u8{init: [3]u8{init: 0xff}}}
        intf: intf
        is_gbc: is_gbc

        cbg_pd: [][][]u8{len: 8, init: [][]u8{len: 4, init: []u8{len: 3}}}
        cob_pd: [][][]u8{len: 8, init: [][]u8{len: 4, init: []u8{len: 3}}}

        vram: []u8{len: 0x4000, init: 0}
        
        oam: []u8{len: 0xa0, init: 0}
        prio: []GPUPrio{len: 160, init: GPUPrio {a: true, b: 0}}
    }
}

pub fn (gpu &GPU) get_vram0(a u16) u8 {
    return gpu.vram[usize(a) - 0x8000]
}

pub fn (gpu &GPU) get_vram1(a u16) u8 {
    return gpu.vram[usize(a) - 0x6000]
}

pub fn (gpu &GPU) get_shades(v u8, i usize) Shade {
    return match (v >> (2 * i)) & 0x03 {
        0x00 { Shade.white }
        0x01 { Shade.light_gray }
        0x02 { Shade.dark_gray }
        else { Shade.black }
    }
}

pub fn (mut gpu GPU) set_gre(x usize, g u8) {
    gpu.data[usize(gpu.scan_y)][x][0] = g
    gpu.data[usize(gpu.scan_y)][x][1] = g
    gpu.data[usize(gpu.scan_y)][x][2] = g
}

pub fn (mut gpu GPU) set_rgb(x usize, r u8, g u8, b u8) {
    nr := u32(r)
    ng := u32(g)
    nb := u32(b)
    lr := u8((nr * 13 + ng * 2 + nb) >> 1)
    lg := u8((ng * 3 + nb) << 1)
    lb := u8((nr * 3 + ng * 2 + nb * 11) >> 1)
    gpu.data[usize(gpu.scan_y)][x][0] = lr
    gpu.data[usize(gpu.scan_y)][x][1] = lg
    gpu.data[usize(gpu.scan_y)][x][2] = lb
}

pub fn (mut gpu GPU) next(cycles u32) {
    if !gpu.lcdc.bit7() {
        return
    }
    gpu.h_blank = false

    if cycles == 0 {
        return
    }
    c := (cycles - 1) / 80 + 1
    for i in 0..c {
        if i == (c - 1) {
            gpu.dots += cycles % 80
        } else {
            gpu.dots += 80
        }
        d := gpu.dots
        gpu.dots %= 456
        if d != gpu.dots {
            gpu.scan_y = (gpu.scan_y + 1) % 154
            if gpu.enable_ly_interrupt && gpu.scan_y == gpu.scan_yc {
                gpu.intf.hi(1)
            }
        }
        if gpu.scan_y >= 144 {
            if gpu.int_mode == 1 {
                continue
            }
            gpu.int_mode = 1
            gpu.v_blank = true
            gpu.intf.hi(0)
            if gpu.enable_m1_interrupt {
                gpu.intf.hi(1)
            }
        } else if gpu.dots <= 80 {
            if gpu.int_mode == 2 {
                continue
            }
            gpu.int_mode = 2
            if gpu.enable_m2_interrupt {
                gpu.intf.hi(1)
            }
        } else if gpu.dots <= (80 + 172) {
            gpu.int_mode = 3
        } else {
            if gpu.int_mode == 0 {
                continue
            }
            gpu.int_mode = 0
            gpu.h_blank = true
            if gpu.enable_m0_interrupt {
                gpu.intf.hi(1)
            }
            // FINALLY WE'RE ACTUALY DRAWING SOMETHING!
            if gpu.is_gbc || gpu.lcdc.bit0() {
                gpu.draw_background()
            }
            if gpu.lcdc.bit1() {
                gpu.draw_sprites()
            }
        }
    }
}

fn (mut gpu GPU) draw_background() {
    render_window := (gpu.lcdc.bit5() && gpu.window_y <= gpu.scan_y)
    tile_base := u16(if gpu.lcdc.bit4() { 0x8000 } else { 0x8800 })
    
    wx := gpu.window_x - 7
    py := u8(if render_window { gpu.scan_y - gpu.window_y } else { gpu.scroll_y + gpu.scan_y })
    ty := (u16(py) >> 3) & 31

    for x in 0..160 {
        px := if render_window && u8(x) >= wx {
            x - wx
        } else {
            gpu.scroll_x + x
        }
        tx := (u16(px) >> 3) & 31

        bg_base := if render_window && u8(x) >= wx {
            if gpu.lcdc.bit6() {
                0x9c00
            } else {
                0x9800
            }
        } else if gpu.lcdc.bit3() {
            0x9c00
        } else {
            0x9800
        }

        tile_addr := u16(bg_base + ty * 32 + tx)
        tile_number := gpu.get_vram0(tile_addr)
        tile_offset := u16(if gpu.lcdc.bit4() {
            i16(tile_number)
        } else {
            i16(i8(tile_number)) + 128
        }) * 16
        tile_location := tile_base + tile_offset
        tile_attr := attr_from(gpu.get_vram1(tile_addr))

        tile_y := if tile_attr.yflip { 7 - py % 8 } else { py % 8 }
        tile_y_data := if gpu.is_gbc && tile_attr.bank {
            a := gpu.get_vram1(tile_location + u16(tile_y * 2))
            b := gpu.get_vram1(tile_location + u16(tile_y * 2) + 1)
            [u8(a), b]
        } else {
            a := gpu.get_vram0(tile_location + u16(tile_y * 2))
            b := gpu.get_vram0(tile_location + u16(tile_y * 2) + 1)
            [u8(a), b]
        }
        tile_x := if tile_attr.xflip { 7 - px % 8 } else { px % 8 }

        color_l := if tile_y_data[0] & (0x80 >> tile_x) != 0 { 1 } else { 0 }
        color_h := if tile_y_data[1] & (0x80 >> tile_x) != 0 { 2 } else { 0 }
        mut color := u8(color_h | color_l)

        gpu.prio[x] = GPUPrio {a: tile_attr.priority, b: usize(color)}

        if gpu.is_gbc {
            r := gpu.cbg_pd[tile_attr.palette_number_1][color][0]
            g := gpu.cbg_pd[tile_attr.palette_number_1][color][1]
            b := gpu.cbg_pd[tile_attr.palette_number_1][color][2]
            gpu.set_rgb(x, r, g, b)
        } else {
            color = u8(gpu.get_shades(gpu.bgp, color))
            gpu.set_gre(x, color)
        }
    }
}

fn (mut self GPU) draw_sprites() {
    sprite_size := if self.lcdc.bit2() { 16 } else { 8 }
    for i in 0..40 {
        sprite_addr := 0xfe00 + u16(i) * 4
        py := u8(self.get(sprite_addr) - 16)
        px := u8(self.get(sprite_addr + 1) - 8)
        tile_number := u8(self.get(sprite_addr + 2)) & u8(if self.lcdc.bit2() { 0xfe } else { 0xff })
        tile_attr := attr_from(self.get(sprite_addr + 3))

        // If this is true the scanline is out of the area we care about
        if py <= 0xff - sprite_size + 1 {
            if self.scan_y < py || self.scan_y > py + sprite_size - 1 {
                continue
            }
        } else {
            if self.scan_y > u8(py + sprite_size) - 1 {
                continue
            }
        }
        if px >= 160 && px <= (0xff - 7) {
            continue
        }

        tile_y := if tile_attr.yflip {
            u8(sprite_size - 1 - u8(self.scan_y - py))
        } else {
            u8(self.scan_y - py)
        }
        tile_y_addr := u16(0x8000) + u16(tile_number) * 16 + u16(tile_y) * 2
        tile_y_data := if self.is_gbc && tile_attr.bank {
            b1 := self.get_vram1(tile_y_addr)
            b2 := self.get_vram1(tile_y_addr + 1)
            [u8(b1), b2]
        } else {
            b1 := self.get_vram0(tile_y_addr)
            b2 := self.get_vram0(tile_y_addr + 1)
            [u8(b1), b2]
        }

        for x in 0..8 {
            if (px + x) >= 160 {
                continue
            }
            tile_x := if tile_attr.xflip { 7 - x } else { x }

            // Palettes
            color_l := if tile_y_data[0] & (0x80 >> tile_x) != 0 { 1 } else { 0 }
            color_h := if tile_y_data[1] & (0x80 >> tile_x) != 0 { 2 } else { 0 }
            mut color := u8(color_h | color_l)
            if color == 0 {
                continue
            }

            // Confirm the priority of background and sprite.
            prio := self.prio[px + x]
            skip := if self.is_gbc && !self.lcdc.bit0() {
                prio.b == 0
            } else if prio.a {
                prio.b != 0
            } else {
                tile_attr.priority && prio.b != 0
            }
            if skip {
                continue
            }

            if self.is_gbc {
                r := self.cob_pd[tile_attr.palette_number_1][color][0]
                g := self.cob_pd[tile_attr.palette_number_1][color][1]
                b := self.cob_pd[tile_attr.palette_number_1][color][2]
                self.set_rgb(usize(px + x), r, g, b)
            } else {
                color = u8(if tile_attr.palette_number_0 == 1 {
                    self.get_shades(self.op1, color)
                } else {
                    self.get_shades(self.op0, color)
                })
                self.set_gre(usize(px + x), color)
            }
        }
    }
}

pub fn (gpu &GPU) get(a u16) u8 {
    match true {
        a >= 0x8000 && a <= 0x9fff { return gpu.vram[gpu.vram_bank * 0x2000 + usize(a) - 0x8000] }
        a >= 0xfe00 && a <= 0xfe9f { return gpu.oam[a - 0xfe00] }
        a == 0xff40 { return u8(gpu.lcdc) }
        a == 0xff41 {
            bit6 := if gpu.enable_ly_interrupt { 0x40 } else { 0x00 }
            bit5 := if gpu.enable_m2_interrupt { 0x20 } else { 0x00 }
            bit4 := if gpu.enable_m1_interrupt { 0x10 } else { 0x00 }
            bit3 := if gpu.enable_m0_interrupt { 0x08 } else { 0x00 }
            bit2 := if gpu.scan_y == gpu.scan_yc { 0x04 } else { 0x00 }
            return u8(bit6 | bit5 | bit4 | bit3 | bit2 | gpu.int_mode)
        }
        a == 0xff42 { return gpu.scroll_y }
        a == 0xff43 { return gpu.scroll_x }
        a == 0xff44 { return gpu.scan_y }
        a == 0xff45 { return gpu.scan_yc }
        a == 0xff47 { return gpu.bgp }
        a == 0xff48 { return gpu.op0 }
        a == 0xff49 { return gpu.op1 }
        a == 0xff4a { return gpu.window_y }
        a == 0xff4b { return gpu.window_x }
        a == 0xff4f { return u8(0xfe | gpu.vram_bank) }
        a == 0xff68 { return if gpu.cbg_inc { 0x80 | gpu.cbg_i } else { gpu.cbg_i } }
        a == 0xff69 {
            r := usize(gpu.cbg_i) >> 3
            c := usize(gpu.cbg_i) >> 1 & 0x3
            if gpu.cbg_i & 0x01 == 0x00 {
                return (gpu.cbg_pd[r][c][0]) | (gpu.cbg_pd[r][c][1] << 5)
            } else {
                return (gpu.cbg_pd[r][c][1] >> 3) | (gpu.cbg_pd[r][c][2] << 2)
            }
        }
        a == 0xff6a { return if gpu.cob_inc { 0x80 | gpu.cob_i } else { gpu.cob_i } }
        a == 0xff6b {
            r := usize(gpu.cob_i) >> 3
            c := usize(gpu.cob_i) >> 1 & 0x3
            if gpu.cob_i & 0x01 == 0x00 {
                return (gpu.cob_pd[r][c][0]) | (gpu.cob_pd[r][c][1] << 5)
            } else {
                return (gpu.cob_pd[r][c][1] >> 3) | (gpu.cob_pd[r][c][2] << 2)
            }
        }
        else { panic("You shouldn't be seeing this...") }
    }
}

pub fn (mut gpu GPU) set(a u16, v u8) {
    match true {
        a >= 0x8000 && a <= 0x9fff { gpu.vram[gpu.vram_bank * 0x2000 + usize(a) - 0x8000] = v }
        a >= 0xfe00 && a <= 0xfe9f { gpu.oam[a - 0xfe00] = v }
        a == 0xff40 {
            gpu.lcdc = Lcdc(v)
            if !gpu.lcdc.bit7() {
                gpu.dots = 0
                gpu.scan_y = 0
                gpu.int_mode = 0
                gpu.data = [144][160][3]u8{init: [160][3]u8{init: [3]u8{init: 0xff}}}
                gpu.v_blank = true
            }
        }
        a == 0xff41 {
            gpu.enable_ly_interrupt = v & 0x40 != 0x00
            gpu.enable_m2_interrupt = v & 0x20 != 0x00
            gpu.enable_m1_interrupt = v & 0x10 != 0x00
            gpu.enable_m0_interrupt = v & 0x08 != 0x00
        }
        a == 0xff42 { gpu.scroll_y = v }
        a == 0xff43 { gpu.scroll_x = v }
        a == 0xff44 {} // Intentionally Empty
        a == 0xff45 { gpu.scan_yc = v }
        a == 0xff47 { gpu.bgp = v }
        a == 0xff48 { gpu.op0 = v }
        a == 0xff49 { gpu.op1 = v }
        a == 0xff4a { gpu.window_y = v }
        a == 0xff4b { gpu.window_x = v }
        a == 0xff4f { gpu.vram_bank = (v & 0x01) }
        a == 0xff68 {
            gpu.cbg_inc = (v & 0x80) != 0x00
            gpu.cbg_i = v & 0x3f
        }
        a == 0xff69 {
            r := usize(gpu.cbg_i) >> 3
            c := usize(gpu.cbg_i) >> 1 & 0x03
            if gpu.cbg_i & 0x01 == 0x00 {
                gpu.cbg_pd[r][c][0] = v & 0x1f
                gpu.cbg_pd[r][c][1] = (gpu.cbg_pd[r][c][1] & 0x18) | (v >> 5)
            } else {
                gpu.cbg_pd[r][c][1] = (gpu.cbg_pd[r][c][1] & 0x07) | ((v & 0x03) << 3)
                gpu.cbg_pd[r][c][2] = (v >> 2) & 0x1f
            }
            if gpu.cbg_inc {
                gpu.cbg_i += 0x01
                gpu.cbg_i &= 0x3f
            }
        }
        a == 0xff6a {
            gpu.cob_inc = v & 0x80 != 0x00
            gpu.cob_i = v & 0x3f
        }
        a == 0xff6b {
            r := usize(gpu.cob_i) >> 3
            c := usize(gpu.cob_i) >> 1 & 0x03
            if gpu.cob_i & 0x01 == 0x00 {
                gpu.cob_pd[r][c][0] = v & 0x1f
                gpu.cob_pd[r][c][1] = (gpu.cob_pd[r][c][1] & 0x18) | (v >> 5)
            } else {
                gpu.cob_pd[r][c][1] = (gpu.cob_pd[r][c][1] & 0x07) | ((v & 0x03) << 3)
                gpu.cob_pd[r][c][2] = (v >> 2) & 0x1f
            }
            if gpu.cob_inc {
                gpu.cob_i += 0x01
                gpu.cob_i &= 0x3f
            }
        }
        else { panic("You shouldn't be seeing this...") }
    }
}