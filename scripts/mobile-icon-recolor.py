#!/usr/bin/env python3
"""把白底 K 字标图标翻转成深绿底反色版（dev-board#412）。

输入：docs/design/app-icon-1024-white.png（旧白底原图，纯白底 + 深绿括号/斜杠 + 薄荷绿箭头）
输出：ios/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png（深绿底 + 白括号/斜杠 + 薄荷绿箭头）
      docs/design/app-icon-1024-dark-green.png（同一张，供小程序/安卓商店后台上传）
      --foreground <path>：另存一张去掉深绿底、带真 alpha 的 RGBA 字标（供 android-icon.sh 用，
      不进仓）。用同一份覆盖率算 alpha，比 ImageMagick 的 -fuzz + -transparent 干净得多：
      后者只能给出 0/255 的硬 alpha，会在字标外圈留一整圈深绿描边。

原理：没有矢量源，只能从 PNG 栅格反推。把每个像素看成三种纯色的线性混合
      p = a·DG + b·MINT + c·WHITE（a+b+c=1，即抗锯齿边缘的覆盖率），
      用最小二乘解出 (a, b)，再按 新 = a·WHITE + b·MINT + c·DG 重合成。
      这样边缘的过渡自然反转，不会留白色毛边或深绿残边。

用法：python3 scripts/mobile-icon-recolor.py [--foreground out.png]  （从仓库任意目录跑都行）
"""
import argparse
import pathlib
import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "docs/design/app-icon-1024-white.png"
OUT_IOS = ROOT / "ios/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
OUT_DOC = ROOT / "docs/design/app-icon-1024-dark-green.png"

# 从原图括号内部 / 箭头内部（腐蚀后）取的中位色，见 dev-board#412。
DG = np.array([0x08, 0x46, 0x2C], float)    # #08462C 深绿
MINT = np.array([0x68, 0xD7, 0xAC], float)  # #68D7AC 薄荷绿
WHITE = np.array([255.0, 255.0, 255.0])
# 纯色吸附半径（RGB 欧氏距离）。原图三块纯色内部有压缩噪点（距纯色最大 23.8），
# 而 DG/MINT/WHITE 两两间距最近也有 176.9，所以 25 只吃掉噪点、不吃抗锯齿过渡带。
# 必须在 RGB 空间吸附而不是在 (a,b) 上：DG-WHITE 与 MINT-WHITE 两个方向近乎共线，
# 最小二乘病态，几个灰度的噪点会被放大成 ±0.2 的覆盖率抖动。
SNAP = 25.0

args = argparse.ArgumentParser(description=__doc__)
args.add_argument("--foreground", type=pathlib.Path,
                  help="额外写出一张去掉深绿底、带 alpha 的 RGBA 字标（已裁到外接框）")
opts = args.parse_args()

src = np.asarray(Image.open(SRC).convert("RGB"), dtype=float)
h, w, _ = src.shape

# 解 p - WHITE = a·(DG-WHITE) + b·(MINT-WHITE)
basis = np.stack([DG - WHITE, MINT - WHITE], axis=1)          # 3x2
coef = np.linalg.lstsq(basis, (src - WHITE).reshape(-1, 3).T, rcond=None)[0]  # 2xN
a, b = coef[0], coef[1]

a = np.clip(a, 0.0, 1.0)
b = np.clip(b, 0.0, 1.0)
over = a + b > 1.0                                            # 两色覆盖率之和不能超 1
scale = np.where(over, 1.0 / np.maximum(a + b, 1e-9), 1.0)
a, b = a * scale, b * scale

# 纯色区吸附：去掉噪点，保证底色/括号/箭头各自是完全一致的单一色。
flat = src.reshape(-1, 3)
for ref, (va, vb) in ((DG, (1.0, 0.0)), (MINT, (0.0, 1.0)), (WHITE, (0.0, 0.0))):
    m = np.linalg.norm(flat - ref, axis=1) < SNAP
    a[m], b[m] = va, vb

# 反色重合成：原来的深绿 → 白，白底 → 深绿，薄荷绿不动。
out = (a[:, None] * WHITE + b[:, None] * MINT
       + (1.0 - a - b)[:, None] * DG)
out = np.clip(out, 0, 255).round().astype(np.uint8).reshape(h, w, 3)

img = Image.fromarray(out, "RGB")  # 无 alpha：iOS 图标不允许透明通道
OUT_IOS.parent.mkdir(parents=True, exist_ok=True)
OUT_DOC.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT_IOS, optimize=True)
img.save(OUT_DOC, optimize=True)
print(f"写出 {OUT_IOS.relative_to(ROOT)} 与 {OUT_DOC.relative_to(ROOT)}（{w}x{h}, RGB）")

if opts.foreground:
    # 前景 = 白括号 + 薄荷箭头，深绿底变透明。
    # alpha 就是两者的覆盖率之和；颜色按覆盖率归一化（非预乘），缩放时不会渗出深绿。
    cov = np.clip(a + b, 0.0, 1.0)
    denom = np.maximum(cov, 1e-9)[:, None]
    rgb = (a[:, None] * WHITE + b[:, None] * MINT) / denom
    rgb = np.where(cov[:, None] > 0, rgb, WHITE)
    rgba = np.concatenate([rgb, (cov * 255.0)[:, None]], axis=1)
    rgba = np.clip(rgba, 0, 255).round().astype(np.uint8).reshape(h, w, 4)
    fg = Image.fromarray(rgba, "RGBA")
    fg = fg.crop(fg.getchannel("A").getbbox())          # 裁到字标外接框
    opts.foreground.parent.mkdir(parents=True, exist_ok=True)
    fg.save(opts.foreground, optimize=True)
    print(f"写出前景 {opts.foreground}（{fg.width}x{fg.height}, RGBA）")
