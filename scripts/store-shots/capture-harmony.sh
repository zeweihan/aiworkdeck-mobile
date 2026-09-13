#!/usr/bin/env bash
#
# 鸿蒙商店截图：8 张原始屏（未合成）→ scripts/store-shots/raw/harmony/zh-Hans/01..08.png
#
#   scripts/store-shots/capture-harmony.sh                # 全部八屏
#   scripts/store-shots/capture-harmony.sh --screen 6     # 只重截第 6 屏
#   scripts/store-shots/capture-harmony.sh --no-build     # 跳过构建/安装，只重截
#
# 前提：
#   - DevEco Studio 装在 /Applications，模拟器（Pura 90 Pro，1256×2760）已启动：
#       /Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator -start "Pura 90 Pro"
#   - `hdc list targets` 能看到 127.0.0.1:5557
#
# 与安卓的关键差别：**种子进包，不从主机灌**。
# `hdc shell` 是 uid 2000，`hdc file send` 往应用沙盒写一律 permission denied
# （2026-09-13 实测 /data/app/el2/100/base/<bundle>/haps/entry/files/），
# 所以现场照片作为 rawfile（`harmony/entry/src/main/resources/rawfile/shots/`）随 debug 包走，
# 启动参数 `--ps awdShots 1` 触发 `ScreenshotMode.seed()` 把它们摊进 FieldEvidence。
# 落到哪一屏用 `--ps awdScreen queue|library|viewer|settings`，取景图用 `--ps awdStage NN`。
#
# 屏与内容见 docs/specs/2026-09-13-store-assets-design.md §2（与安卓同一套）。
# 第 6 屏走「录音中 + 下拉通知栏」，拿不到通知就退回首页录音态。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/scripts/store-shots/raw/harmony/zh-Hans"
SCENES="$ROOT/scripts/store-shots/assets/scenes"
RAWFILE="$ROOT/harmony/entry/src/main/resources/rawfile/shots"

DEVECO="/Applications/DevEco-Studio.app/Contents"
HDC="$DEVECO/sdk/default/openharmony/toolchains/hdc"
HVIGOR="$DEVECO/tools/hvigor/bin/hvigorw"
BUNDLE="com.aiworkdeck.mobile.huawei"
HAP="$ROOT/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap"

export DEVECO_SDK_HOME="$DEVECO/sdk"
export NODE_HOME="$DEVECO/tools/node"

ONLY=""
BUILD=1
while [ $# -gt 0 ]; do
  case "$1" in
    --screen) ONLY="$(printf '%02d' "$2")"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

mkdir -p "$OUT"

# ---- 1. 种子素材进 rawfile ---------------------------------------------------
# 现场照片本身在 assets/scenes/（整目录可替换）；进包的是缩到 720 宽的副本，
# 加上一段录像与一段静音录音——种子里要有这两类才截得出「三种影像一个取景框」。
say "刷新 rawfile 种子素材"
mkdir -p "$RAWFILE"
for i in 01 02 03 04 05 06 07 08; do
  magick "$SCENES/$i.jpg" -resize 720x960 -quality 72 "$RAWFILE/$i.jpg"
done
ffmpeg -y -loop 1 -i "$SCENES/06.jpg" -t 3 -r 12 -vf scale=480:-2 -pix_fmt yuv420p \
  -c:v libx264 "$RAWFILE/clip.mp4" >/dev/null 2>&1
ffmpeg -y -f lavfi -i anullsrc=r=44100:cl=mono -t 8 -c:a aac "$RAWFILE/voice.m4a" >/dev/null 2>&1

# ---- 2. 构建与安装 ---------------------------------------------------------
if [ "$BUILD" = 1 ]; then
  say "构建 entry-default-unsigned.hap"
  (cd "$ROOT/harmony" && "$HVIGOR" assembleHap --mode module -p product=default -p buildMode=debug --no-daemon >/dev/null)
  say "安装（模拟器接受未签名 HAP）"
  "$HDC" install -r "$HAP" | tail -1
fi

launch() {  # $1 = awdScreen 值（空 = 首页），$2 = 取景图场景号
  "$HDC" shell "aa force-stop $BUNDLE" >/dev/null
  sleep 1
  "$HDC" shell "aa start -a EntryAbility -b $BUNDLE --ps awdShots 1 --ps awdScreen '${1:-none}' --ps awdStage '${2:-03}'" >/dev/null
  wait_ready
}

# 冷启动 + 首启摊 16 件种子要时间，机器忙时更久。等到 EntryAbility 在前台再多留三秒
# 给 ArkUI 铺完；等短了截到的是启动图。
wait_ready() {
  local i=0
  while [ $i -lt 60 ]; do
    if "$HDC" shell "aa dump -a" 2>/dev/null \
      | grep -A4 "bundle name \[$BUNDLE\]" | grep -q "app state #FOREGROUND"; then
      sleep 8
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  sleep 4
}

shot() {  # $1 = 序号
  "$HDC" shell snapshot_display -f /data/local/tmp/awdshot.jpeg >/dev/null
  "$HDC" file recv /data/local/tmp/awdshot.jpeg "$OUT/.raw.jpeg" >/dev/null
  # 商店要 PNG（AGC 收 PNG/JPG，合成脚本统一从 PNG 走；App Store 那边还不收 alpha）
  magick "$OUT/.raw.jpeg" -alpha off "$OUT/$1.png"
  rm -f "$OUT/.raw.jpeg"
  printf '  → %s (%s)\n' "$OUT/$1.png" \
    "$(sips -g pixelWidth -g pixelHeight "$OUT/$1.png" | tr -d ' \n' | sed 's/.*pixelWidth:\([0-9]*\)pixelHeight:\([0-9]*\)/\1x\2/')"
}

# 模拟器 1256×2760 上量出来的坐标
TAP_AUDIO_X=890; TAP_AUDIO_Y=2106      # 底部「录音」档
TAP_SHUTTER_X=628; TAP_SHUTTER_Y=2378  # 快门

# ---- 3. 逐屏 ---------------------------------------------------------------
if want 01; then say "01 首页取景"; launch "" 01; shot 01; fi
if want 02; then say "02 首页取景（水印区）"; launch "" 02; shot 02; fi
if want 03; then say "03 上传队列（顶部）"; launch queue 03; shot 03; fi
if want 04; then say "04 图集"; launch library 03; shot 04; fi
if want 05; then say "05 查看器"; launch viewer 03; sleep 3; shot 05; fi

if want 06; then
  say "06 录音中 + 常驻通知"
  launch "" 03
  "$HDC" shell uitest uiInput click $TAP_AUDIO_X $TAP_AUDIO_Y >/dev/null
  sleep 2
  "$HDC" shell uitest uiInput click $TAP_SHUTTER_X $TAP_SHUTTER_Y >/dev/null
  sleep 25                       # 让计时器走到两位数
  # 拍首页录音态而不是下拉通知栏（规格 §2 两者都收）：鸿蒙的长时任务通知是系统给的
  # 「正在运行录制任务…」，**不带时长**，下拉出来还会连带拍到锁屏样式的「无 SIM 卡」；
  # 首页这一屏反而看得见计时器。要拍通知栏就把下面这行的注释去掉：
  #   "$HDC" shell uitest uiInput swipe 628 8 628 1500 600
  shot 06
  "$HDC" shell "aa force-stop $BUNDLE" >/dev/null   # 录音服务跟着停
fi

if want 07; then
  say "07 上传队列（滚到已落盘）"
  launch queue 03
  # 慢拖而不是快滑：List 吃到 fling 会带惯性回弹，截到的还是顶部
  for _ in 1 2 3 4; do "$HDC" shell uitest uiInput swipe 628 2100 628 620 600 >/dev/null; sleep 2; done
  sleep 3
  shot 07
fi

if want 08; then
  say "08 项目选择器"
  # `awdScreen projects` 让种子把当前项目清掉，Root 自己路由到选项目页——不用点坐标
  launch projects 03
  shot 08
  launch "" 03   # 把当前项目补回去，免得下次单截别的屏落在选项目页
fi

say "完成：$OUT"
ls -la "$OUT"
