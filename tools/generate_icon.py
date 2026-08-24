# -*- coding: utf-8 -*-
"""生成 Hormone 的应用图标与启动屏 logo。

设计：「Hormone 分子糖链」——白/奶油色圆润分子珠（激素=化学分子），
由圆头化学键连接成六边形环结构；其中一颗珠为粉色爱心（快乐荷尔蒙），
简约可爱，马卡龙配色。

产物：
  assets/icon/icon.png         1024x1024，主色蓝全填充（app 图标）
  assets/splash/logo.png       1024x1024，透明底（启动屏 logo）

用法：python tools/generate_icon.py
"""

import math

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # 超采样倍数（抗锯齿）

# ── 配色（与 lib/core/theme/app_theme.dart 主色一致）──
BG = (91, 141, 239, 255)  # #5B8DEF 主蓝
WHITE = (255, 255, 255, 255)
CREAM = (255, 242, 225, 255)  # 奶油
LAVENDER = (214, 200, 255, 255)  # 浅紫
PINK = (250, 134, 167, 255)  # 爱心粉
BEAD_OUTLINE = (176, 196, 255, 150)  # 白珠淡蓝描边（微立体）


def heart_points(cx, cy, s, n=200):
    """心形曲线采样（参数方程），s 为缩放。"""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        # Pillow y 轴向下，且心形质心略偏上，整体下移使视觉居中
        pts.append((cx + s * x, cy - s * y + s * 4))
    return pts


def draw_molecule(draw, cx, cy, scale=1.0):
    """在 (cx, cy) 绘制分子图形，尺寸基于中心珠半径 rc（按 scale 缩放）。"""
    rc = 170.0 * scale
    radius = 330.0 * scale  # 中心珠 -> 环绕珠的中心距
    rp = 125.0 * scale  # 环绕珠半径
    bond_w = 60.0 * scale
    # 六颗环绕珠：正上方开始每 60° 一颗
    beads = []
    for k in range(6):
        a = math.radians(-90 + 60 * k)
        beads.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    colors = [  # 上（爱心珠）、右上、右下、下、左下、左上
        PINK, WHITE, CREAM, WHITE, LAVENDER, WHITE,
    ]
    # 1) 化学键（粗线 + 圆头端帽），先画键再画珠
    for bx, by in beads:
        draw.line([(cx, cy), (bx, by)], fill=WHITE, width=int(bond_w))
        r_end = bond_w / 2
        for px, py in ((cx, cy), (bx, by)):
            draw.ellipse([px - r_end, py - r_end, px + r_end, py + r_end], fill=WHITE)
    # 2) 环绕珠（彩色珠带淡淡描边）
    for (bx, by), color in zip(beads, colors):
        bbox = [bx - rp, by - rp, bx + rp, by + rp]
        if color == PINK:
            # 爱心珠：粉色心形 + 白描边（宽度约珠径的 88%）
            heart = heart_points(bx, by, rp * 0.0625)
            draw.polygon(heart, fill=PINK, outline=WHITE, width=int(20 * scale))
        else:
            draw.ellipse(bbox, fill=color)
            draw.ellipse(bbox, outline=BEAD_OUTLINE, width=int(14 * scale))
    # 3) 中心大珠（白 + 淡蓝描边 + 珠内柔和高光弧）
    cbox = [cx - rc, cy - rc, cx + rc, cy + rc]
    draw.ellipse(cbox, fill=WHITE)
    draw.ellipse(cbox, outline=BEAD_OUTLINE, width=int(16 * scale))
    draw.arc(
        [cx - rc * 0.92, cy - rc * 0.92, cx + rc * 0.92, cy + rc * 0.4],
        start=200,
        end=290,
        fill=(224, 234, 255, 170),
        width=int(rc * 0.13),
    )


def make_icon():
    """1024x1024 主蓝全填充图标。"""
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), BG)
    draw = ImageDraw.Draw(img)
    draw_molecule(draw, SIZE * SS // 2, SIZE * SS // 2, scale=SS)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def make_splash_logo():
    """1024x1024 透明底启动屏 logo（分子图形放大一号）。"""
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_molecule(draw, SIZE * SS // 2, SIZE * SS // 2, scale=SS * 1.18)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    icon = make_icon()
    icon.save("assets/icon/icon.png")
    logo = make_splash_logo()
    logo.save("assets/splash/logo.png")
    print("OK: assets/icon/icon.png, assets/splash/logo.png")


if __name__ == "__main__":
    main()
