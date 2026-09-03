#!/usr/bin/env bash
# 从 iOS 1024×1024 图标源生成安卓自适应图标（前景/单色）+ 商店用 512×512 大图。
# 源：ios/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png（白底 + 深绿括号 + 薄荷绿箭头）。
# 用法：scripts/android-icon.sh   （从仓库任意目录跑都行，路径按脚本自身位置解析）
#
# 产物（进仓提交，体积很小）：
#   android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_foreground.png
#   android/app/src/main/res/mipmap-{同上}/ic_launcher_monochrome.png
#   android/app/src/main/res/values/ic_launcher_background.xml
#   android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml / ic_launcher_round.xml
#   android/store/icon-512.png   （商店大图，白底 + 图形占 80%）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/ios/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
RES="$ROOT/android/app/src/main/res"
STORE_DIR="$ROOT/android/store"

command -v magick >/dev/null || { echo "需要 ImageMagick（brew install imagemagick）" >&2; exit 1; }
[ -f "$SRC" ] || { echo "找不到图标源：$SRC" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 裁掉白边（fuzz 5% 容差），再把白底转透明，得到只含图形、四周透明的裁切版。
magick "$SRC" -fuzz 5% -trim +repage -fuzz 5% -transparent white "$WORK/glyph.png"
GLYPH_W=$(magick identify -format '%w' "$WORK/glyph.png")
GLYPH_H=$(magick identify -format '%h' "$WORK/glyph.png")
echo "图形裁切框：${GLYPH_W}x${GLYPH_H}（来自 $SRC）"

# 单色版：颜色通道全填黑，保留透明通道形状（前景色的两色合并成一个黑色轮廓）。
magick "$WORK/glyph.png" -channel RGB -fill black -colorize 100% +channel "$WORK/glyph-mono.png"

# 自适应图标安全区是画布中心 66%；前景图形定为画布的 62%，留一点余量。
# macOS 自带 bash 3.2，没有关联数组，用 "密度:像素" 的列表代替。
DENSITIES="mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432"

place_centered() {
  # place_centered <source> <canvas_px> <fill_ratio> <out>
  local src="$1" canvas="$2" ratio="$3" out="$4"
  local target
  target=$(awk -v c="$canvas" -v r="$ratio" 'BEGIN{printf "%d", c*r+0.5}')
  magick -size "${canvas}x${canvas}" xc:none \
    \( "$src" -resize "${target}x${target}" \) \
    -gravity center -compose over -composite -depth 8 -strip "$out"
}

for pair in $DENSITIES; do
  density="${pair%%:*}"
  px="${pair##*:}"
  dir="$RES/mipmap-$density"
  mkdir -p "$dir"
  place_centered "$WORK/glyph.png" "$px" 0.62 "$dir/ic_launcher_foreground.png"
  place_centered "$WORK/glyph-mono.png" "$px" 0.62 "$dir/ic_launcher_monochrome.png"
  echo "生成 $density（${px}px）：ic_launcher_foreground.png / ic_launcher_monochrome.png"
done

mkdir -p "$RES/values"
cat > "$RES/values/ic_launcher_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
EOF

mkdir -p "$RES/mipmap-anydpi-v26"
for name in ic_launcher ic_launcher_round; do
  cat > "$RES/mipmap-anydpi-v26/$name.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
EOF
done

# 商店大图：白底满铺 + 图形占 80%，不透明（各应用商店的图标要求都是不透明底）。
mkdir -p "$STORE_DIR"
target512=$(awk 'BEGIN{printf "%d", 512*0.8+0.5}')
magick -size 512x512 xc:white \
  \( "$WORK/glyph.png" -resize "${target512}x${target512}" \) \
  -gravity center -compose over -composite -depth 8 -strip "$STORE_DIR/icon-512.png"
echo "生成商店大图：$STORE_DIR/icon-512.png"

echo "完成。"
