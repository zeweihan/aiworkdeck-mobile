#!/usr/bin/env bash
# 打印各依赖的最新稳定版（排除 alpha/beta/rc/dev/RC），供 gradle/libs.versions.toml 锁版本。
set -euo pipefail
latest() { # $1 = metadata URL
  curl -fsSL "$1" | grep -o '<version>[^<]*</version>' | sed 's/<[^>]*>//g' \
    | grep -viE 'alpha|beta|rc|dev|snapshot|eap|M[0-9]' | sort -V | tail -1
}
g=https://dl.google.com/android/maven2; m=https://repo1.maven.org/maven2
printf 'agp=%s\n'            "$(latest $g/com/android/tools/build/gradle/maven-metadata.xml)"
printf 'kotlin=%s\n'         "$(latest $m/org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml)"
printf 'composeBom=%s\n'     "$(latest $g/androidx/compose/compose-bom/maven-metadata.xml)"
printf 'activityCompose=%s\n' "$(latest $g/androidx/activity/activity-compose/maven-metadata.xml)"
printf 'lifecycle=%s\n'      "$(latest $g/androidx/lifecycle/lifecycle-runtime-compose/maven-metadata.xml)"
printf 'camerax=%s\n'        "$(latest $g/androidx/camera/camera-core/maven-metadata.xml)"
printf 'media3=%s\n'         "$(latest $g/androidx/media3/media3-exoplayer/maven-metadata.xml)"
printf 'work=%s\n'           "$(latest $g/androidx/work/work-runtime-ktx/maven-metadata.xml)"
printf 'securityCrypto=%s\n' "$(latest $g/androidx/security/security-crypto/maven-metadata.xml)"
printf 'coreKtx=%s\n'        "$(latest $g/androidx/core/core-ktx/maven-metadata.xml)"
printf 'okhttp=%s\n'         "$(latest $m/com/squareup/okhttp3/okhttp/maven-metadata.xml)"
printf 'serialization=%s\n'  "$(latest $m/org/jetbrains/kotlinx/kotlinx-serialization-json/maven-metadata.xml)"
printf 'coroutines=%s\n'     "$(latest $m/org/jetbrains/kotlinx/kotlinx-coroutines-android/maven-metadata.xml)"
printf 'coil=%s\n'           "$(latest $m/io/coil-kt/coil3/coil-compose/maven-metadata.xml)"
printf 'junit=%s\n'          "$(latest $m/junit/junit/maven-metadata.xml)"
