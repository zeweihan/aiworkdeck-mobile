#!/usr/bin/env bash
#
# 安卓商店截图：8 张原始屏（未合成）→ scripts/store-shots/raw/android/zh-Hans/01..08.png
#
#   scripts/store-shots/capture-android.sh                # 全部八屏
#   scripts/store-shots/capture-android.sh --screen 6     # 只重截第 6 屏
#   scripts/store-shots/capture-android.sh --no-build     # 跳过构建/安装，只重截
#
# 前提：
#   - AVD `awd`（1080×2400，见 android/README.md「模拟器」）已启动：
#       emulator -avd awd -no-snapshot -no-boot-anim &
#   - ffmpeg（造录像/录音种子）、python3
#
# 怎么做到的（模拟器没有相机、没有 GPS、也没有桌面端）：
#   1. 装 **debug** 包，用 `--ez awdScreenshot true` 打开 `ScreenshotMode`（release 包里这段不存在）：
#      跳过服务端会话、取景区贴静态现场照、定位固定 ±5 米、选项目页给三条演示项目。
#   2. 影像本身不靠拍：`seed/build-seed.py` 摊出 16 件的 manifest + 原件，
#      `adb push` 到 /data/local/tmp 再 `run-as` 拷进沙盒（API 36 上 heredoc 收不到 stdin，
#      所以一律走文件；`shared_prefs/` 首次要 mkdir）。
#   3. 落到哪一屏由 `--es awdScreen queue|library|viewer|settings` 决定，不点坐标。
#
# 屏与内容（docs/specs/2026-09-13-store-assets-design.md §2）：
#   01 首页取景（项目名 + 归档路径 + GPS 精度 + 桌面端在线）
#   02 首页取景（换一张现场照，供合成时放大「SHA-256 · GPS · 时间戳」水印区）
#   03 上传队列顶部（上传中 / 已暂存）
#   04 图集（按项目 / 按日）
#   05 查看器（拍摄时间 / 坐标 / 设备 / 摘要）
#   06 录音中 + 常驻通知（下拉通知栏）
#   07 上传队列滚到底（已落盘）
#   08 项目选择器（三个在办项目）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/scripts/store-shots"
OUT="$HERE/raw/android/zh-Hans"
SCENES="$HERE/assets/scenes"
STAGE="${TMPDIR:-/tmp}/awd-android-seed"

PKG="com.aiworkdeck.mobile.cn"
ACT="$PKG/com.aiworkdeck.mobile.MainActivity"
: "${ANDROID_HOME:="$(brew --prefix)/share/android-commandlinetools"}"
export ANDROID_HOME
ADB="$ANDROID_HOME/platform-tools/adb"
# 真机插着时不要截到真机上去
export ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"

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

# ---- 1. 构建与安装 ---------------------------------------------------------
if [ "$BUILD" = 1 ]; then
  say "构建 :app:assembleCnDebug"
  (cd "$ROOT/android" && ./gradlew :app:assembleCnDebug --console=plain -q)
  say "安装到 $ANDROID_SERIAL"
  "$ADB" install -r -t "$ROOT/android/app/build/outputs/apk/cn/debug/app-cn-debug.apk"
fi

say "授权（模拟器上没有交互式弹窗代劳）"
for p in CAMERA RECORD_AUDIO ACCESS_FINE_LOCATION POST_NOTIFICATIONS; do
  "$ADB" shell pm grant "$PKG" "android.permission.$p" || true
done

# ---- 2. 灌种子 -------------------------------------------------------------
say "生成种子"
python3 "$HERE/seed/build-seed.py" --scenes "$SCENES" --out "$STAGE" --end android

# run-as 只能这样使唤：把要做的事写成脚本推到 /data/local/tmp 再让它执行。
# 直接 `run-as pkg sh -c '...'` 在 adb shell 这一层会被吃掉引号（API 36 上实测
# 报 `sh: -c: requires an argument`，随后在 / 下 mkdir 撞上只读文件系统）。
as_app() {  # stdin = 在应用私有目录里跑的 sh 脚本
  local tmp="$STAGE/run-as.sh"
  cat > "$tmp"
  "$ADB" push "$tmp" /data/local/tmp/awd-run-as.sh >/dev/null
  "$ADB" shell "run-as $PKG sh /data/local/tmp/awd-run-as.sh"
}

push_seed() {  # $1 = prefs 文件名
  "$ADB" shell "rm -rf /data/local/tmp/awdseed" >/dev/null
  "$ADB" push "$STAGE/FieldEvidence" /data/local/tmp/awdseed >/dev/null
  "$ADB" push "$STAGE/$1" /data/local/tmp/awdseed-prefs.xml >/dev/null
  # push 出来的目录是 drwxrwx--x shell:shell，应用 uid 进不去
  "$ADB" shell chmod -R 755 /data/local/tmp/awdseed
  as_app <<'EOF'
rm -rf files/FieldEvidence
mkdir -p files shared_prefs
cp -r /data/local/tmp/awdseed files/FieldEvidence
cp /data/local/tmp/awdseed-prefs.xml shared_prefs/prefs.xml
EOF
}

stage_scene() {  # $1 = 场景图序号，换取景区那张静态照
  "$ADB" push "$SCENES/$1.jpg" /data/local/tmp/awdseed-stage.jpg >/dev/null
  as_app <<'EOF'
mkdir -p files
cp /data/local/tmp/awdseed-stage.jpg files/screenshot-stage.jpg
EOF
}

# 每屏都要 force-stop 重开：`awdScreen` 是 onCreate 里读的，热启动只走 onNewIntent。
# 代价是每次都是冷启动——模拟器上从 splash 到第一帧要好几秒，等短了截到的就是那张启动图。
launch() {  # $1 = awdScreen 值（空 = 首页）
  "$ADB" shell am force-stop "$PKG"
  sleep 1
  if [ -z "${1:-}" ]; then
    "$ADB" shell am start -n "$ACT" --ez awdScreenshot true >/dev/null
  else
    "$ADB" shell am start -n "$ACT" --ez awdScreenshot true --es awdScreen "$1" >/dev/null
  fi
  wait_ready
}

# 冷启动到第一帧的时间随主机负载浮动：机器闲时四五秒，load 30 时实测要一分半。
# 固定 sleep 截到的是启动图，所以改成等「闪屏窗口消失」再多留三秒给 Compose 铺完。
wait_ready() {
  local i=0 dump
  while [ $i -lt 150 ]; do
    dump="$("$ADB" shell dumpsys window windows 2>/dev/null || true)"
    # 两个条件都要：窗口列表里有我们这个包（dumpsys 在高负载下会超时返回空，
    # 只看「没有闪屏窗口」会把空结果当成画好了，截下来是桌面），且闪屏窗口已经没了
    if printf '%s' "$dump" | grep -q "$PKG" \
      && ! printf '%s' "$dump" | grep -q "Splash Screen $PKG"; then
      # 闪屏没了不等于画好了：Compose 还要铺一遍，图集/队列的缩略图还要 Coil 解码，
      # 机器忙时这段能到十几秒——等短了截到的是一张白屏或者一格格空缩略图
      sleep 14
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  echo "  （等了 5 分钟还没画出来，先截一张看看）" >&2
}

# 主机负载高时系统会给这个（其实只是慢的）应用弹一张「isn't responding」，
# 弹在截图正中间。按返回键等同于选「Wait」：对话框消失，应用继续跑。
dismiss_anr() {
  local i=0
  while [ $i -lt 6 ]; do
    "$ADB" shell dumpsys window windows 2>/dev/null | grep -q "Application Not Responding" || return 0
    "$ADB" shell input keyevent KEYCODE_BACK
    sleep 4
    i=$((i + 1))
  done
}

shot() {  # $1 = 序号
  dismiss_anr
  "$ADB" exec-out screencap -p > "$OUT/$1.png"
  printf '  → %s (%s)\n' "$OUT/$1.png" "$(sips -g pixelWidth -g pixelHeight "$OUT/$1.png" | tr -d ' \n' | sed 's/.*pixelWidth:\([0-9]*\)pixelHeight:\([0-9]*\)/\1x\2/')"
}

# 状态栏走 SystemUI demo mode：固定 09:41、满格信号、满电，别把跑机器那一刻的
# 时间与电量拍进商店图。脚本结束时 exit 掉。
"$ADB" shell settings put global sysui_demo_allowed 1
demo() { "$ADB" shell am broadcast -a com.android.systemui.demo "$@" >/dev/null; }
demo -e command enter
demo -e command clock -e hhmm 0941
demo -e command battery -e level 100 -e plugged false
demo -e command network -e wifi show -e level 4
demo -e command network -e mobile show -e datatype none -e level 4
trap '"$ADB" shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null 2>&1 || true' EXIT

say "灌数据"
push_seed prefs.xml

# ---- 3. 逐屏 ---------------------------------------------------------------
if want 01; then say "01 首页取景"; stage_scene 01; launch ""; shot 01; fi
if want 02; then say "02 首页取景（水印区）"; stage_scene 02; launch ""; shot 02; fi
if want 03; then say "03 上传队列（顶部）"; launch queue; sleep 8; shot 03; fi
if want 04; then say "04 图集"; launch library; sleep 8; shot 04; fi
if want 05; then say "05 查看器"; launch viewer; sleep 8; shot 05; fi

if want 06; then
  say "06 录音中 + 常驻通知"
  stage_scene 03
  launch ""
  # 切到「录音」档并按快门：模式条与快门的坐标是 1080×2400 上量出来的
  "$ADB" shell input tap 740 1860   # 录音
  sleep 1
  "$ADB" shell input tap 540 2076   # 快门
  sleep 25                          # 让计时器走到两位数，通知里也才有时长
  "$ADB" shell cmd statusbar expand-notifications
  sleep 6
  shot 06
  "$ADB" shell cmd statusbar collapse
  sleep 1
  "$ADB" shell am force-stop "$PKG"  # 录音服务跟着停，别把这一件也传出去
fi

if want 07; then
  say "07 上传队列（滚到已落盘）"
  launch queue
  # 慢拖而不是快滑：LazyColumn 吃到 fling 会带惯性回弹，截到的还是顶部
  for _ in 1 2 3 4; do "$ADB" shell input swipe 540 1900 540 520 900; sleep 2; done
  sleep 3
  shot 07
fi

if want 08; then
  say "08 项目选择器"
  push_seed prefs-no-project.xml
  launch ""
  shot 08
  push_seed prefs.xml
fi

say "完成：$OUT"
ls -la "$OUT"
