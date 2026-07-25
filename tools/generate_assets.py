#!/usr/bin/env python3
"""Generate hormone app icon + splash logo as PNGs (stdlib only).

Outputs:
  assets/icon/icon.png    - 1024x1024 rounded-square icon (blue bg + white calendar card)
  assets/splash/logo.png  - 1024x1024 transparent-bg white calendar card (for splash)

Run: python3 tools/generate_assets.py
"""
import os
import zlib
import struct

S = 1024
PRIMARY = (0x5B, 0x8D, 0xEF)
WHITE = (255, 255, 255)
GRID = (0xD9, 0xDE, 0xE8)


def new_canvas() -> bytearray:
    return bytearray(S * S * 4)  # fully transparent


def set_px(buf, x, y, color, alpha=255):
    if x < 0 or y < 0 or x >= S or y >= S:
        return
    i = (y * S + x) * 4
    if alpha >= 255 and buf[i + 3] == 0:
        buf[i], buf[i + 1], buf[i + 2], buf[i + 3] = color[0], color[1], color[2], 255
        return
    sa = alpha / 255.0
    da = buf[i + 3] / 255.0
    out_a = sa + da * (1 - sa)
    if out_a <= 0:
        return
    buf[i] = int((color[0] * sa + buf[i] * da * (1 - sa)) / out_a + 0.5)
    buf[i + 1] = int((color[1] * sa + buf[i + 1] * da * (1 - sa)) / out_a + 0.5)
    buf[i + 2] = int((color[2] * sa + buf[i + 2] * da * (1 - sa)) / out_a + 0.5)
    buf[i + 3] = int(out_a * 255 + 0.5)


def fill_rect(buf, x0, y0, x1, y1, color, alpha=255):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            set_px(buf, x, y, color, alpha)


def rr_contains(px, py, x0, y0, x1, y1, r):
    if px < x0 or px > x1 or py < y0 or py > y1:
        return False
    if px < x0 + r and py < y0 + r:
        return (px - (x0 + r)) ** 2 + (py - (y0 + r)) ** 2 <= r * r
    if px > x1 - r and py < y0 + r:
        return (px - (x1 - r)) ** 2 + (py - (y0 + r)) ** 2 <= r * r
    if px < x0 + r and py > y1 - r:
        return (px - (x0 + r)) ** 2 + (py - (y1 - r)) ** 2 <= r * r
    if px > x1 - r and py > y1 - r:
        return (px - (x1 - r)) ** 2 + (py - (y1 - r)) ** 2 <= r * r
    return True


def fill_rounded_rect(buf, x0, y0, x1, y1, r, color, alpha=255):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            if rr_contains(x, y, x0, y0, x1, y1, r):
                set_px(buf, x, y, color, alpha)


def draw_calendar_card(buf, x0, y0, x1, y1, r):
    fill_rounded_rect(buf, x0, y0, x1, y1, r, WHITE, 255)
    w = x1 - x0
    h = y1 - y0
    cols, rows = 3, 4
    cw = w / cols
    rh = h / rows
    line = 10
    # vertical dividers
    for c in range(1, cols):
        lx = int(round(x0 + c * cw))
        fill_rect(buf, lx - line // 2, y0 + 14, lx + line // 2, y1 - 14, GRID, 255)
    # horizontal dividers
    for rr in range(1, rows):
        ly = int(round(y0 + rr * rh))
        fill_rect(buf, x0 + 14, ly - line // 2, x1 - 14, ly + line // 2, GRID, 255)
    # a "course" block in cell (col 0, rows 1..2)
    bx0 = int(x0 + 12)
    by0 = int(y0 + rh + 12)
    bx1 = int(x0 + cw - 12)
    by1 = int(y0 + 2 * rh - 12)
    fill_rounded_rect(buf, bx0, by0, bx1, by1, 14, PRIMARY, 255)


def write_png(path, buf):
    raw = bytearray()
    for y in range(S):
        raw.append(0)
        raw.extend(buf[y * S * 4:(y + 1) * S * 4])
    comp = zlib.compress(bytes(raw), 9)

    def chunk(typ, data):
        return struct.pack('>I', len(data)) + typ + data + struct.pack('>I', zlib.crc32(typ + data) & 0xffffffff)

    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', S, S, 8, 6, 0, 0, 0)))
        f.write(chunk(b'IDAT', comp))
        f.write(chunk(b'IEND', b''))
    print('wrote', path)


def build_icon():
    buf = new_canvas()
    fill_rounded_rect(buf, 0, 0, S - 1, S - 1, 224, PRIMARY, 255)
    m = 150
    draw_calendar_card(buf, m, m, S - 1 - m, S - 1 - m, 96)
    return buf


def build_logo():
    buf = new_canvas()  # transparent background
    m = 150
    draw_calendar_card(buf, m, m, S - 1 - m, S - 1 - m, 96)
    return buf


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icon = os.path.join(root, 'assets', 'icon', 'icon.png')
    logo = os.path.join(root, 'assets', 'splash', 'logo.png')
    write_png(icon, build_icon())
    write_png(logo, build_logo())


if __name__ == '__main__':
    main()
