#!/usr/bin/env bash
# 出安卓正式签名包（cn APK + intl AAB），校验签名指纹与备案登记的是否一致，产物归档到
# ~/.aiworkdeck/android/releases/。口令只读进变量，绝不回显、绝不打印。
#
# 前置：~/.aiworkdeck/android/ 下要有 aiworkdeck-cn.keystore、aiworkdeck-intl.keystore、
# keystore-passwords.txt、beian-android.txt、aiworkdeck-intl.cer（发版机器一次性放好）。
#
# 用法：scripts/android-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
KS_DIR="$HOME/.aiworkdeck/android"
PW_FILE="$KS_DIR/keystore-passwords.txt"
BEIAN_FILE="$KS_DIR/beian-android.txt"
INTL_CER="$KS_DIR/aiworkdeck-intl.cer"
LOCAL_PROPS="$ANDROID_DIR/local.properties"
VERSION_PROPS="$ANDROID_DIR/version.properties"
APKSIGNER="$(brew --prefix)/share/android-commandlinetools/build-tools/37.0.0/apksigner"

for f in "$PW_FILE" "$BEIAN_FILE" "$INTL_CER"; do
  [ -f "$f" ] || { echo "缺文件：$f（先按 README「出签名包」把 ~/.aiworkdeck/android/ 备齐）" >&2; exit 1; }
done
command -v keytool >/dev/null || { echo "需要 keytool（随 JDK）" >&2; exit 1; }
[ -x "$APKSIGNER" ] || { echo "缺 apksigner：$APKSIGNER" >&2; exit 1; }

# ---------- 1. 口令写进 local.properties（幂等 upsert，不回显） ----------

upsert_prop() {
  # upsert_prop <file> <key> <value> —— key 存在就替换那一行，不存在就追加；其余行原样保留。
  local file="$1" key="$2" value="$3" tmp found=0
  tmp=$(mktemp)
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" == "$key="* ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$tmp"
        found=1
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$file"
  fi
  if [ "$found" -eq 0 ]; then
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" "$file"
}

pw_field() {
  # pw_field <keystore 文件名前缀> <alias|pass> —— 从 keystore-passwords.txt 里按字段名取值。
  awk -v pat="^$1" -v field="$2" '
    $0 !~ /^#/ && $1 ~ pat {
      for (i = 1; i <= NF; i++) {
        if (field == "alias" && $i ~ /^alias=/) { sub(/^alias=/, "", $i); print $i }
        if (field == "pass"  && $i ~ /^storepass\/keypass=/) { sub(/^storepass\/keypass=/, "", $i); print $i }
      }
    }' "$PW_FILE"
}

cn_alias=$(pw_field "aiworkdeck-cn" alias)
cn_pass=$(pw_field "aiworkdeck-cn" pass)
intl_alias=$(pw_field "aiworkdeck-intl" alias)
intl_pass=$(pw_field "aiworkdeck-intl" pass)
[ -n "$cn_alias" ] && [ -n "$cn_pass" ] && [ -n "$intl_alias" ] && [ -n "$intl_pass" ] \
  || { echo "keystore-passwords.txt 里缺 alias 或口令字段，格式对不上，检查一下" >&2; exit 1; }

upsert_prop "$LOCAL_PROPS" "signing.cn.storeFile" "$KS_DIR/aiworkdeck-cn.keystore"
upsert_prop "$LOCAL_PROPS" "signing.cn.storePassword" "$cn_pass"
upsert_prop "$LOCAL_PROPS" "signing.cn.keyAlias" "$cn_alias"
upsert_prop "$LOCAL_PROPS" "signing.cn.keyPassword" "$cn_pass"
upsert_prop "$LOCAL_PROPS" "signing.intl.storeFile" "$KS_DIR/aiworkdeck-intl.keystore"
upsert_prop "$LOCAL_PROPS" "signing.intl.storePassword" "$intl_pass"
upsert_prop "$LOCAL_PROPS" "signing.intl.keyAlias" "$intl_alias"
upsert_prop "$LOCAL_PROPS" "signing.intl.keyPassword" "$intl_pass"
unset cn_pass intl_pass
echo "已写入 android/local.properties 的签名配置（口令不回显）"

# ---------- 2. 版本号 ----------

version_name=$(awk -F= '$1=="versionName"{print $2}' "$VERSION_PROPS")
version_code=$(awk -F= '$1=="versionCode"{print $2}' "$VERSION_PROPS")
[ -n "$version_name" ] && [ -n "$version_code" ] || { echo "version.properties 缺 versionName/versionCode" >&2; exit 1; }
echo "版本：versionName=$version_name versionCode=$version_code"

# ---------- 3. 打包 ----------

export ANDROID_HOME="${ANDROID_HOME:-$(brew --prefix)/share/android-commandlinetools}"
( cd "$ANDROID_DIR" && ./gradlew :app:bundleIntlRelease :app:assembleCnRelease --console=plain )

CN_APK="$ANDROID_DIR/app/build/outputs/apk/cn/release/app-cn-release.apk"
INTL_AAB="$ANDROID_DIR/app/build/outputs/bundle/intlRelease/app-intl-release.aab"
[ -f "$CN_APK" ] || { echo "没找到 cn APK：$CN_APK" >&2; exit 1; }
[ -f "$INTL_AAB" ] || { echo "没找到 intl AAB：$INTL_AAB" >&2; exit 1; }

# ---------- 4. 签名指纹校验 ----------

norm() { tr -d ':[:space:]' <<< "$1" | tr 'a-f' 'A-F'; }

# cn：apksigner --print-certs 取 SHA-1 / MD5。
cn_certs_out=$("$APKSIGNER" verify --print-certs "$CN_APK")
cn_sha1_actual=$(norm "$(echo "$cn_certs_out" | grep -m1 'certificate SHA-1 digest:' | sed 's/.*digest: //')")
cn_md5_actual=$(norm "$(echo "$cn_certs_out" | grep -m1 'certificate MD5 digest:' | sed 's/.*digest: //')")
[ -n "$cn_sha1_actual" ] && [ -n "$cn_md5_actual" ] || { echo "apksigner 没解析出 cn 签名指纹，看下原始输出：" >&2; echo "$cn_certs_out" >&2; exit 1; }

# cn 预期值：beian-android.txt 里「只填国内版」小节（截止到「国际版」小节之前）。
cn_section=$(awk '/安卓平台特征信息/{flag=1; next} /国际版/{flag=0} flag' "$BEIAN_FILE")
cn_md5_expected=$(norm "$(echo "$cn_section" | grep -oE '^[[:space:]]*[0-9A-Fa-f]{32}[[:space:]]*$' | head -1)")
cn_sha1_expected=$(norm "$(echo "$cn_section" | grep -oE '([0-9A-Fa-f]{2}:){19}[0-9A-Fa-f]{2}' | head -1)")
[ -n "$cn_md5_expected" ] && [ -n "$cn_sha1_expected" ] || { echo "beian-android.txt 解析不出国内版指纹，检查文件格式" >&2; exit 1; }

# intl：keytool -printcert -jarfile 取 SHA1；预期值来自 aiworkdeck-intl.cer 本身（动态算，不写死）。
intl_certs_out=$(keytool -printcert -jarfile "$INTL_AAB")
intl_sha1_actual=$(norm "$(echo "$intl_certs_out" | grep -m1 'SHA1:' | sed 's/.*SHA1: //')")
intl_sha1_expected=$(norm "$(keytool -printcert -file "$INTL_CER" | grep -m1 'SHA1:' | sed 's/.*SHA1: //')")
[ -n "$intl_sha1_actual" ] && [ -n "$intl_sha1_expected" ] || { echo "keytool 没解析出 intl 签名指纹" >&2; exit 1; }

mismatch=0
if [ "$cn_sha1_actual" != "$cn_sha1_expected" ] || [ "$cn_md5_actual" != "$cn_md5_expected" ]; then
  echo "!! cn APK 签名指纹跟备案登记的不一致 —— 换了 keystore 却继续发包，用户端会被判定「与已备案版本不一致」。" >&2
  echo "   实际  SHA-1=$cn_sha1_actual MD5=$cn_md5_actual" >&2
  echo "   备案  SHA-1=$cn_sha1_expected MD5=$cn_md5_expected（来自 $BEIAN_FILE）" >&2
  mismatch=1
fi
if [ "$intl_sha1_actual" != "$intl_sha1_expected" ]; then
  echo "!! intl AAB 签名指纹跟 $INTL_CER 存档的不一致。" >&2
  echo "   实际  SHA-1=$intl_sha1_actual" >&2
  echo "   存档  SHA-1=$intl_sha1_expected" >&2
  mismatch=1
fi
[ "$mismatch" -eq 0 ] || exit 1
echo "签名指纹校验通过（cn 与 intl 均与登记/存档一致）"

# ---------- 5. 归档 ----------

RELEASE_DIR="$KS_DIR/releases/${version_name}-${version_code}"
mkdir -p "$RELEASE_DIR"
cp "$CN_APK" "$RELEASE_DIR/"
cp "$INTL_AAB" "$RELEASE_DIR/"
( cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$CN_APK")" "$(basename "$INTL_AAB")" > SHA256SUMS )
echo "产物已拷到：$RELEASE_DIR"

# ---------- 6. 报告 ----------

echo
echo "== 产物大小 =="
ls -lh "$RELEASE_DIR/$(basename "$CN_APK")" "$RELEASE_DIR/$(basename "$INTL_AAB")" | awk '{print $9, $5}'
echo
echo "== 签名指纹（公开信息） =="
echo "cn   SHA-1=$cn_sha1_actual MD5=$cn_md5_actual"
echo "intl SHA-1=$intl_sha1_actual"
echo
echo "完成：$version_name-$version_code"
