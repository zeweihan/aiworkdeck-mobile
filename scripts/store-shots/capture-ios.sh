#!/usr/bin/env bash
# iOS 上架截图：出 8 张原始屏（未合成）到 scripts/store-shots/raw/ios/zh-Hans/01..08.png。
#
# 屏序见 docs/specs/2026-09-13-store-assets-design.md §2：
#   1 首页取景  2 首页取景（徽标区）  3 上传队列  4 图集按日
#   5 查看器    6 录音进行中          7 设置页    8 项目选择器
#
# 做法：Debug 包 + 启动参数 -AWDScreenshotMode -AWDScreenshotScreen <n>，
# 一屏一次冷启动直接落到那一页（ios/Sources/App/Screenshots.swift）。
# 不用坐标点击——点击依赖布局，改一次 UI 就全废。
#
# 现场照片不进 App bundle：本脚本把 assets/scenes/NN.jpg 拷进模拟器容器的
# Library/Application Support/ScreenshotSeed/，换素材重跑即可，不必重新构建
# （加 --no-build 跳过构建）。
#
# 用法：
#   scripts/store-shots/capture-ios.sh              # 构建 + 灌素材 + 截 8 屏
#   scripts/store-shots/capture-ios.sh --no-build   # 只重灌素材再截
#   scripts/store-shots/capture-ios.sh 3 6          # 只重截第 3、6 屏
#
# 每张都出现同一个系统弹窗（例如权限框）时：那是上一次跑留在 SpringBoard 上的僵尸弹窗，
# `xcrun simctl shutdown <udid> && xcrun simctl boot <udid>` 重启模拟器后重跑即可。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVICE="${AWD_SIM_DEVICE:-iPhone 17 Pro Max}"
BUNDLE_ID="com.aiworkdeck.mobile.cn"
APP="$ROOT/ios/DerivedData/Build/Products/Debug-iphonesimulator/Workdeck.app"
SCENES="$ROOT/scripts/store-shots/assets/scenes"
OUT="$ROOT/scripts/store-shots/raw/ios/zh-Hans"
# 取景水印固定在 2026-09-12 14:07:32，状态栏跟着它走，两处对不上一眼就看出来
BAR_TIME="14:07"

BUILD=1
SCREENS=()
for a in "$@"; do
  case "$a" in
    --no-build) BUILD=0 ;;
    [1-8]) SCREENS+=("$a") ;;
    *) echo "未知参数：$a" >&2; exit 2 ;;
  esac
done
[ ${#SCREENS[@]} -eq 0 ] && SCREENS=(1 2 3 4 5 6 7 8)

udid="$(xcrun simctl list devices available -j \
  | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next(x['udid'] for v in d.values() for x in v if x['name']=='$DEVICE'))")"
echo "模拟器 $DEVICE $udid"

xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null

if [ "$BUILD" = 1 ]; then
  (cd "$ROOT/ios" && xcodegen generate >/dev/null)
  xcodebuild build -project "$ROOT/ios/Workdeck.xcodeproj" -scheme Workdeck \
    -configuration Debug -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath "$ROOT/ios/DerivedData" CODE_SIGNING_ALLOWED=NO >/dev/null
fi

xcrun simctl install "$udid" "$APP"

# 现场照片灌进容器。装完 App 才有容器，所以必须在 install 之后。
container="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)"
seed="$container/Library/Application Support/ScreenshotSeed"
mkdir -p "$seed"
for n in 01 02 03 04 05 06 07 08; do
  [ -f "$SCENES/$n.jpg" ] && cp "$SCENES/$n.jpg" "$seed/$n.jpg"
done
echo "素材 $(ls "$seed" | wc -l | tr -d ' ') 张 → $seed"

# 干净状态栏：时间、满格信号与电量。不覆盖的话截图上是主机的真实时间与电量。
xcrun simctl status_bar "$udid" override \
  --time "$BAR_TIME" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

mkdir -p "$OUT"
for n in "${SCREENS[@]}"; do
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" -AWDScreenshotMode -AWDScreenshotScreen "$n" >/dev/null
  # 首帧起来就截会拍到过场动画（图集有逐格淡入，查看器要解一张 2048pt 的图）
  sleep 4
  f="$OUT/$(printf '%02d' "$n").png"
  xcrun simctl io "$udid" screenshot --type=png "$f" >/dev/null
  echo "$(basename "$f")  $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
done

xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "完成 → $OUT"
