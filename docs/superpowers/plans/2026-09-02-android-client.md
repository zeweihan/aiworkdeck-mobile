# 安卓客户端（Kotlin + Compose）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `android/` 建成与 iOS 功能对位的安卓客户端（登录、选项目、拍照/录像/录音、真后台上传队列、图集分组三态、查看器、设置含注销），从契约生成物起步，领域层过同一套夹具。

**Architecture:** 单应用模块 `:app` + 生成物模块 `:contract`，目录按 iOS 的 Services / Model / Features 对位。领域与服务核心（状态机、分组、EvidenceStore、UploadQueue、Backend）是纯 Kotlin/JVM 可测；Android 适配（CameraX、MediaRecorder、LocationManager、WorkManager、MediaStore、EncryptedSharedPreferences）薄封装在外层。两个 productFlavor `intl`/`cn`，零 Google 依赖。

**Tech Stack:** Kotlin 2.x、AGP 稳定版、Jetpack Compose（BOM）、Material3 仅作容器、CameraX、AndroidX Media3、WorkManager、OkHttp + MockWebServer、kotlinx.serialization、AndroidX Security Crypto、Coil 3、JUnit4。JDK 21。

**Spec:** `docs/specs/2026-09-02-android-client-design.md`

## Global Constraints

- minSdk 29；compileSdk/targetSdk = 装 SDK 时 `sdkmanager --list` 里最高的稳定 `platforms;android-N`（金标联盟要求 Android 17）。
- 包名：`intl` = `com.aiworkdeck.mobile`，`cn` = `com.aiworkdeck.mobile.cn`；后端：`intl` = `https://addin.workdeck.ai`，`cn` = `https://addin.aiworkdeck.com`；默认登录：`intl` 邮箱，`cn` 短信。
- **零 Google 依赖**：任何 `com.google.android.gms` / `firebase` 都不许进依赖树；定位用 `LocationManager`。
- 状态正式名 `waiting/uploading/uploaded/arrived/failed`，`moving` 只解码；桶 `uploading/staged/landed`；全部来自 `ContractStates`（生成物，不得手改）。用户可见文案一律 `tr(key)`，Kotlin 里不写取证主流程中文字面量。
- 上传 multipart 字段：`deviceId, projectKey, clientMediaId(小写 UUID), fileName, mediaType(image|video|audio), capturedAt(ISO8601)` + `file`；一次一条；退避 60s 翻倍封顶 900s；成功复位。
- 文件名：`现场影像-yyyyMMdd-HHmmss-{uuid前4位}.jpg|mp4`，`现场录音-yyyyMMdd-HHmmss-{uuid前4位}.m4a`（前缀经 `tr("file.prefix.media")` / `tr("file.prefix.audio")`，键在 Task 1 加进契约）。
- 本地目录 `filesDir/FieldEvidence/media/{uuid}.{jpg|mp4|m4a}`、`filesDir/FieldEvidence/manifest/{uuid}.json`；先写原件 → 流式 SHA-256 → 写 manifest。
- 签名与后端地址不进仓：`android/local.properties` gitignored；keystore 在 `~/.aiworkdeck/android/`。
- 每次提交前 `node contract/tools/check.mjs` 必须绿（pre-commit 会跑）；提交信息末尾 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`。
- 每个任务的 Gradle 验证命令都在 `android/` 目录下用 `./gradlew` 跑；首次会下载依赖，慢是正常的。
- 在 worktree 里执行；不要 `cd` 到主检出；不要裸 `git stash`。

---

## 文件结构

| 路径 | 职责 |
|---|---|
| `android/settings.gradle.kts`、`build.gradle.kts`、`gradle/libs.versions.toml`、`gradle/wrapper/*`、`gradle.properties` | 工程与版本锁 |
| `android/scripts/latest-versions.sh` | 从 Maven 元数据打印各库最新稳定版，Task 0 用它填 toml |
| `android/contract/build.gradle.kts` | 生成物纯 Kotlin JVM 库 |
| `android/app/build.gradle.kts`、`src/main/AndroidManifest.xml`、`src/main/res/**` | 应用模块、flavor、权限、通知渠道字串 |
| `app/src/main/kotlin/com/aiworkdeck/mobile/model/*.kt` | `TransferState`、`TransferPhase`、`TransferEvent`、`TransferTally`、`CaptureManifest`、`CaptureItem`、`StoredRow`、`RelayProject`、`MediaKind`、`LibraryGrouping` |
| `.../design/L10n.kt`、`Tokens.kt`、`Typography.kt`、`Components.kt`、`Theme.kt` | 契约文案与令牌的 Compose 化 |
| `.../services/Backend.kt`、`ApiTypes.kt`、`SessionStore.kt` | 网络与会话 |
| `.../services/EvidenceStore.kt`、`Prefs.kt` | 本地仓库 |
| `.../services/UploadQueue.kt`、`UploadWorker.kt`、`UploadNaming.kt` | 上传 |
| `.../services/CameraService.kt`、`AudioRecorderService.kt`、`LocationStamper.kt`、`AlbumSaver.kt`、`DeviceFacts.kt` | 采集与相册 |
| `.../AppModel.kt`、`MainActivity.kt`、`App.kt` | 根状态、路由、进程级初始化 |
| `.../features/auth/LoginScreen.kt`、`ProjectPickerScreen.kt`；`features/home/HomeScreen.kt`、`CameraPreview.kt`、`Watermark.kt`；`features/library/LibraryScreen.kt`、`ViewerScreen.kt`；`features/queue/QueueScreen.kt`；`features/settings/SettingsScreen.kt` | 七屏 |
| `app/src/test/kotlin/com/aiworkdeck/mobile/**` | JVM 单测（契约夹具、状态机、仓库、队列、网络解码） |
| `.github/workflows/android.yml` | CI |
| `contract/tools/check.mjs`、`contract/strings.json`、`contract/capabilities.json` | 契约侧改动（Task 1、2、11） |
| `android/README.md` | 构建、签名、模拟器、发版 |

---

### Task 0: 工具链、工程骨架、CI

**Files:**
- Create: `android/scripts/latest-versions.sh`、`android/settings.gradle.kts`、`android/build.gradle.kts`、`android/gradle.properties`、`android/gradle/libs.versions.toml`、`android/contract/build.gradle.kts`、`android/app/build.gradle.kts`、`android/app/src/main/AndroidManifest.xml`、`android/app/src/main/kotlin/com/aiworkdeck/mobile/MainActivity.kt`、`android/app/src/main/res/values/strings.xml`、`android/README.md`、`.github/workflows/android.yml`
- Modify: `.gitignore`（加 `android/local.properties`、`android/.gradle/`、`android/**/build/`、`android/.kotlin/`）
- 生成：`android/gradle/wrapper/*`、`android/gradlew`、`android/gradlew.bat`

**Interfaces:**
- Produces: 可构建的 `:app`（flavors `intl`/`cn`，`BuildConfig.BASE_URL: String`、`BuildConfig.DEFAULT_LOGIN: String`（`"sms"|"mail"`）、`BuildConfig.FLAVOR`）；`:contract` 可被 `:app` 依赖；版本目录别名 `libs.*`；环境变量 `ANDROID_HOME`。

- [ ] **Step 1: 安装 SDK 与 Gradle（用户已同意下载）**

```bash
brew install --cask android-commandlinetools
brew install gradle
export ANDROID_HOME="$(brew --prefix)/share/android-commandlinetools"
yes | sdkmanager --licenses >/dev/null
sdkmanager --list 2>/dev/null | grep -E "^\s*platforms;android-[0-9]+\s" | sed 's/^ *//' | cut -d'|' -f1 | sort -t- -k2 -n | tail -3
```
把最高的稳定 `platforms;android-N` 记为 `N`（不含 `-ext`、不含预览字母），然后：
```bash
sdkmanager "platform-tools" "platforms;android-N" "build-tools;N.0.0" "emulator" "system-images;android-N;default;arm64-v8a"
grep -q ANDROID_HOME ~/.zshrc || printf '\nexport ANDROID_HOME="%s"\nexport PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"\n' "$ANDROID_HOME" >> ~/.zshrc
```
若 `build-tools;N.0.0` 不存在，用 `sdkmanager --list | grep "build-tools;N\."` 里最高的那个。

- [ ] **Step 2: 写版本查询脚本并运行**

`android/scripts/latest-versions.sh`：
```bash
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
```
Run: `chmod +x android/scripts/latest-versions.sh && android/scripts/latest-versions.sh`
把输出逐项填进 Step 3 的 toml。`securityCrypto` 若只有 alpha 可用则取 `1.1.0-alpha06` 或更高（该库长期停在 alpha，允许例外并在 toml 注释说明）。

- [ ] **Step 3: 工程文件**

`android/settings.gradle.kts`：
```kotlin
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "aiworkdeck-android"
include(":app", ":contract")
```

`android/build.gradle.kts`：
```kotlin
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
```

`android/gradle.properties`：
```
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
org.gradle.configuration-cache=true
```

`android/gradle/libs.versions.toml`（版本号用 Step 2 的输出替换尖括号）：
```toml
[versions]
agp = "<agp>"
kotlin = "<kotlin>"
composeBom = "<composeBom>"
activityCompose = "<activityCompose>"
lifecycle = "<lifecycle>"
camerax = "<camerax>"
media3 = "<media3>"
work = "<work>"
securityCrypto = "<securityCrypto>"
coreKtx = "<coreKtx>"
okhttp = "<okhttp>"
serialization = "<serialization>"
coroutines = "<coroutines>"
coil = "<coil>"
junit = "<junit>"

[libraries]
androidx-core-ktx = { module = "androidx.core:core-ktx", version.ref = "coreKtx" }
androidx-activity-compose = { module = "androidx.activity:activity-compose", version.ref = "activityCompose" }
androidx-lifecycle-runtime-compose = { module = "androidx.lifecycle:lifecycle-runtime-compose", version.ref = "lifecycle" }
compose-bom = { module = "androidx.compose:compose-bom", version.ref = "composeBom" }
compose-ui = { module = "androidx.compose.ui:ui" }
compose-ui-tooling-preview = { module = "androidx.compose.ui:ui-tooling-preview" }
compose-ui-tooling = { module = "androidx.compose.ui:ui-tooling" }
compose-foundation = { module = "androidx.compose.foundation:foundation" }
compose-material3 = { module = "androidx.compose.material3:material3" }
camerax-core = { module = "androidx.camera:camera-core", version.ref = "camerax" }
camerax-camera2 = { module = "androidx.camera:camera-camera2", version.ref = "camerax" }
camerax-lifecycle = { module = "androidx.camera:camera-lifecycle", version.ref = "camerax" }
camerax-video = { module = "androidx.camera:camera-video", version.ref = "camerax" }
camerax-view = { module = "androidx.camera:camera-view", version.ref = "camerax" }
media3-exoplayer = { module = "androidx.media3:media3-exoplayer", version.ref = "media3" }
media3-ui = { module = "androidx.media3:media3-ui", version.ref = "media3" }
work-runtime = { module = "androidx.work:work-runtime-ktx", version.ref = "work" }
security-crypto = { module = "androidx.security:security-crypto", version.ref = "securityCrypto" }
okhttp = { module = "com.squareup.okhttp3:okhttp", version.ref = "okhttp" }
okhttp-mockwebserver = { module = "com.squareup.okhttp3:mockwebserver", version.ref = "okhttp" }
kotlinx-serialization-json = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version.ref = "serialization" }
kotlinx-coroutines-android = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-android", version.ref = "coroutines" }
kotlinx-coroutines-test = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-test", version.ref = "coroutines" }
coil-compose = { module = "io.coil-kt.coil3:coil-compose", version.ref = "coil" }
coil-video = { module = "io.coil-kt.coil3:coil-video", version.ref = "coil" }
junit = { module = "junit:junit", version.ref = "junit" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-compose = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
```

`android/contract/build.gradle.kts`：
```kotlin
plugins { alias(libs.plugins.kotlin.jvm) }
kotlin { jvmToolchain(21) }
```
（生成物已在 `android/contract/src/main/kotlin/`，不要改。）

`android/app/build.gradle.kts`：
```kotlin
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

val localProps = Properties().apply {
    val f = rootProject.file("local.properties"); if (f.exists()) f.inputStream().use { load(it) }
}
fun prop(name: String): String? = localProps.getProperty(name) ?: System.getenv(name.uppercase().replace('.', '_'))

android {
    namespace = "com.aiworkdeck.mobile"
    compileSdk = <N>
    defaultConfig {
        minSdk = 29
        targetSdk = <N>
        versionCode = 1
        versionName = "1.0.0"
        vectorDrawables.useSupportLibrary = true
    }
    flavorDimensions += "market"
    productFlavors {
        create("intl") {
            dimension = "market"
            applicationId = "com.aiworkdeck.mobile"
            buildConfigField("String", "BASE_URL", "\"https://addin.workdeck.ai\"")
            buildConfigField("String", "DEFAULT_LOGIN", "\"mail\"")
        }
        create("cn") {
            dimension = "market"
            applicationId = "com.aiworkdeck.mobile.cn"
            buildConfigField("String", "BASE_URL", "\"https://addin.aiworkdeck.com\"")
            buildConfigField("String", "DEFAULT_LOGIN", "\"sms\"")
        }
    }
    signingConfigs {
        // 口令与路径来自 android/local.properties（gitignored）或环境变量 SIGNING_CN_*/SIGNING_INTL_*：
        //   signing.cn.storeFile / signing.cn.storePassword / signing.cn.keyAlias / signing.cn.keyPassword（intl 同）
        for (fl in listOf("cn", "intl")) {
            val store = prop("signing.$fl.storeFile") ?: continue
            create("release-$fl") {
                storeFile = file(store)
                storePassword = prop("signing.$fl.storePassword")
                keyAlias = prop("signing.$fl.keyAlias") ?: "aiworkdeck-$fl"
                keyPassword = prop("signing.$fl.keyPassword")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            productFlavors.getByName("cn").signingConfig = signingConfigs.findByName("release-cn")
            productFlavors.getByName("intl").signingConfig = signingConfigs.findByName("release-intl")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_21; targetCompatibility = JavaVersion.VERSION_21 }
    kotlin { jvmToolchain(21) }
    testOptions.unitTests.isIncludeAndroidResources = false
}

dependencies {
    implementation(project(":contract"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui); implementation(libs.compose.foundation); implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview); debugImplementation(libs.compose.ui.tooling)
    implementation(libs.camerax.core); implementation(libs.camerax.camera2); implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.video); implementation(libs.camerax.view)
    implementation(libs.media3.exoplayer); implementation(libs.media3.ui)
    implementation(libs.work.runtime)
    implementation(libs.security.crypto)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.coil.compose); implementation(libs.coil.video)
    testImplementation(libs.junit); testImplementation(libs.okhttp.mockwebserver); testImplementation(libs.kotlinx.coroutines.test)
}
```

`android/app/src/main/AndroidManifest.xml`：
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <uses-feature android:name="android.hardware.camera.any" android:required="true" />

    <application
        android:name=".App"
        android:allowBackup="false"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:label="@string/app_name"
        android:supportsRtl="false"
        android:theme="@android:style/Theme.Material.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true"
            android:screenOrientation="portrait" android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name="androidx.work.impl.foreground.SystemForegroundService"
            android:foregroundServiceType="dataSync" tools:node="merge"
            xmlns:tools="http://schemas.android.com/tools" />
    </application>
</manifest>
```
`android/app/src/main/res/xml/data_extraction_rules.xml`：
```xml
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup><exclude domain="file" path="FieldEvidence/" /></cloud-backup>
    <device-transfer><exclude domain="file" path="FieldEvidence/" /></device-transfer>
</data-extraction-rules>
```
`android/app/src/main/res/values/strings.xml`（系统级字串，不属取证主流程，允许在此）：
```xml
<resources>
    <string name="app_name">AI WorkDeck</string>
    <string name="notif_channel_upload">上传</string>
    <string name="notif_uploading">正在上传现场影像</string>
</resources>
```
`android/app/src/main/kotlin/com/aiworkdeck/mobile/MainActivity.kt`（骨架，Task 7 替换内容）：
```kotlin
package com.aiworkdeck.mobile

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Text

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { Text("AI WorkDeck ${BuildConfig.FLAVOR}") }
    }
}
```
`App.kt`：
```kotlin
package com.aiworkdeck.mobile

import android.app.Application

class App : Application()
```

- [ ] **Step 4: Gradle wrapper 与 local.properties**

```bash
cd android && gradle wrapper && ./gradlew --version | head -5
printf 'sdk.dir=%s\n' "$ANDROID_HOME" > local.properties
```
在仓库 `.gitignore` 追加：
```
android/local.properties
android/.gradle/
android/.kotlin/
android/**/build/
```

- [ ] **Step 5: 编译两个变体**

Run: `cd android && ./gradlew :app:assembleIntlDebug :app:assembleCnDebug --console=plain 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`，产物 `app/build/outputs/apk/intl/debug/app-intl-debug.apk` 与 `cn/debug/app-cn-debug.apk`。若 AGP 与 Gradle 版本不兼容，按报错把 wrapper 换到 AGP 要求的 Gradle 版本（`./gradlew wrapper --gradle-version X`）。

- [ ] **Step 6: CI 与 README**

`.github/workflows/android.yml`：
```yaml
name: android
on:
  push:
    branches: [main]
    paths: ["android/**", "contract/**", ".github/workflows/android.yml"]
  pull_request:
    paths: ["android/**", "contract/**", ".github/workflows/android.yml"]
jobs:
  build:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: android } }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "21" }
      - uses: android-actions/setup-android@v3
      - uses: gradle/actions/setup-gradle@v4
      - run: ./gradlew :app:testIntlDebugUnitTest :app:assembleIntlDebug :app:assembleCnDebug --console=plain
      - name: 大陆变体不得含 GMS
        run: ./gradlew :app:dependencies --configuration cnDebugRuntimeClasspath --console=plain | grep -c "com.google.android.gms" | grep -qx 0
```
`android/README.md`：构建命令、`local.properties` 签名字段、模拟器创建命令（`avdmanager create avd -n awd -k "system-images;android-N;default;arm64-v8a"`，`emulator -avd awd`）、发版指路总表 §7。

- [ ] **Step 7: 提交**

```bash
git add .gitignore android .github/workflows/android.yml
git commit -m "feat(android): 工程骨架——双 flavor、版本目录、CI；本机 SDK 就位

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 1: 领域层与契约夹具适配

**Files:**
- Modify（走契约顺序）: `contract/strings.json`（加 `file.prefix.media`、`file.prefix.audio`、`archive.path`、`login.*`、`home.*`、`settings.*` 等本任务与后续屏需要的键，见 Step 2）→ `node contract/tools/gen.mjs`
- Create: `android/app/src/main/kotlin/com/aiworkdeck/mobile/model/{TransferState,TransferTally,Capture,RelayProject,LibraryGrouping}.kt`、`.../design/L10n.kt`
- Test: `android/app/src/test/kotlin/com/aiworkdeck/mobile/{ContractFixturesTest,TransferStateTest,L10nTest,LibraryGroupingTest}.kt`

**Interfaces:**
- Produces:
  - `enum class TransferState(val raw: String) { waiting, uploading, uploaded, arrived, failed; companion fun fromRaw(s: String): TransferState?（经 aliases）; val phase: TransferPhase; val caption: String; val detail: String; val whereItIs: String; fun next(event: TransferEvent, attempts: Int = 0): TransferState?; fun recovered(attempts: Int = 0): TransferState; fun applyingStatus(delivered: Boolean, waitingSeconds: Long, expiresAt: String?): StatusMerge }`
  - `data class StatusMerge(val state: TransferState, val waitingSeconds: Long?, val expiresAt: String?)`
  - `enum class TransferEvent(val raw: String) { kick("kick"), http2xx("http_2xx"), httpError("http_error"), networkError("network_error"), retryManual("retry_manual"), retryAuto("retry_auto"), statusDelivered("status_delivered"), statusPending("status_pending"), appLaunch("app_launch") }`
  - `enum class TransferPhase(val raw: String) { uploading, staged, landed; val caption: String }`
  - `data class TransferTally(val uploading: Int, val failed: Int, val staged: Int, val landed: Int) { val total get() = uploading + staged + landed; companion fun of(items: List<CaptureItem>) }`
  - `enum class MediaKind { photo, video, audio }`；`@Serializable data class CaptureManifest(...)`；`@Serializable data class RelayProject(deviceId, deviceName?, key, name) { val id get() = "$deviceId:$key" }`；`@Serializable data class StoredRow(kind, state: String, progress: Double, manifest, lastError?, savedToAlbum?, project?)`；`data class CaptureItem(id: String, kind, state, manifest, localFile: File, progress: Double, lastError: String?, savedToAlbum: Boolean, project: RelayProject?) { val capturedAt get() = manifest.capturedAt }`
  - `object LibraryGrouping { fun deleteWarningLevel(states: List<TransferState>): Pair<String, Int>; fun deleteWarning(items: List<CaptureItem>): String; fun projectId(deviceId, key): String; fun groupByDay(items: List<CaptureItem>, zone: ZoneId = ZoneId.systemDefault()): List<DaySection>; fun projectsIn(items, current: RelayProject?): List<ProjectChoice> }`
  - `fun tr(key: String, vars: Map<String, Any> = emptyMap()): String`；`object L10n { var locale: String = "zh-Hans" }`
  - ISO 时间：`object IsoTime { fun format(instant: Instant): String /* yyyy-MM-dd'T'HH:mm:ssXXX 本地时区 */; fun parse(s: String): Instant? /* 宽容：无时区按本地，有小数秒截断 */ }`

- [ ] **Step 1: 写夹具适配测试（先失败）**

`android/app/src/test/kotlin/com/aiworkdeck/mobile/ContractFixturesTest.kt`：
```kotlin
package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File

/** 契约夹具适配：contract/fixtures/*.json 驱动 Kotlin 领域函数。Gradle 单测工作目录 = 模块目录 android/app。 */
class ContractFixturesTest {
    private fun fixture(name: String): JsonObject =
        Json.parseToJsonElement(File("../../contract/fixtures/$name.json").readText()).jsonObject
    private fun cases(name: String) = fixture(name)["cases"]!!.jsonArray.map { it.jsonObject }
    private fun st(s: String) = TransferState.fromRaw(s) ?: error("unknown state $s")
    private fun item(state: TransferState) = TestItems.make(state)

    @Test fun tally() {
        for (k in cases("tally")) {
            val items = k["states"]!!.jsonArray.map { item(st(it.jsonPrimitive.content)) }
            val t = TransferTally.of(items); val e = k["expect"]!!.jsonObject
            val name = k["name"]!!.jsonPrimitive.content
            assertEquals(name, e["uploading"]!!.jsonPrimitive.int, t.uploading)
            assertEquals(name, e["failed"]!!.jsonPrimitive.int, t.failed)
            assertEquals(name, e["staged"]!!.jsonPrimitive.int, t.staged)
            assertEquals(name, e["landed"]!!.jsonPrimitive.int, t.landed)
            assertEquals(name, e["total"]!!.jsonPrimitive.int, t.total)
        }
    }

    @Test fun transitions() {
        for (k in cases("transitions")) {
            val from = st(k["from"]!!.jsonPrimitive.content)
            val ev = TransferEvent.entries.first { it.raw == k["event"]!!.jsonPrimitive.content }
            val attempts = k["attempts"]!!.jsonPrimitive.int
            val want = k["to"]!!.let { if (it is JsonNull) null else st(it.jsonPrimitive.content) }
            assertEquals("$from+${ev.raw}($attempts)", want, from.next(ev, attempts))
        }
    }

    @Test fun restore() {
        for (k in cases("restore")) {
            assertEquals(st(k["expect"]!!.jsonPrimitive.content),
                st(k["state"]!!.jsonPrimitive.content).recovered(k["attempts"]!!.jsonPrimitive.int))
        }
    }

    @Test fun statusMerge() {
        for (k in cases("status-merge")) {
            val s = k["status"]!!.jsonObject; val e = k["expect"]!!.jsonObject
            val got = st(k["state"]!!.jsonPrimitive.content).applyingStatus(
                delivered = s["delivered"]!!.jsonPrimitive.boolean,
                waitingSeconds = s["waitingSeconds"]!!.jsonPrimitive.long,
                expiresAt = s["expiresAt"]?.jsonPrimitive?.contentOrNull)
            val name = k["name"]!!.jsonPrimitive.content
            assertEquals(name, st(e["state"]!!.jsonPrimitive.content), got.state)
            assertEquals(name, e["waitingSeconds"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.long }, got.waitingSeconds)
            assertEquals(name, e["expiresAt"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.content }, got.expiresAt)
        }
    }

    @Test fun deleteWarning() {
        for (k in cases("delete-warning")) {
            val states = k["states"]!!.jsonArray.map { st(it.jsonPrimitive.content) }
            val e = k["expect"]!!.jsonObject
            val (level, n) = LibraryGrouping.deleteWarningLevel(states)
            assertEquals(e["level"]!!.jsonPrimitive.content, level)
            assertEquals(e["n"]!!.jsonPrimitive.int, n)
        }
    }

    @Test fun legacyMovingDecodes() {
        assertEquals(TransferState.uploading, TransferState.fromRaw("moving"))
        assertEquals("uploading", TransferState.uploading.raw)
    }
}
```
`android/app/src/test/kotlin/com/aiworkdeck/mobile/TestItems.kt`：
```kotlin
package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.*
import java.io.File
import java.time.Instant
import java.util.UUID

object TestItems {
    fun make(state: TransferState, project: RelayProject? = null, at: Instant = Instant.now(), kind: MediaKind = MediaKind.photo): CaptureItem {
        val id = UUID.randomUUID().toString().lowercase()
        return CaptureItem(id = id, kind = kind, state = state,
            manifest = CaptureManifest(clientMediaId = id, sha256 = "a".repeat(64), capturedAt = IsoTime.format(at),
                serverReceivedAt = null, latitude = null, longitude = null, horizontalAccuracy = null,
                deviceModel = "x", osVersion = "x", appVersion = "x", fromCamera = true, tsaToken = null),
            localFile = File("/dev/null"), progress = 0.0, lastError = null, savedToAlbum = false, project = project)
    }
}
```

- [ ] **Step 2: 加契约键（契约顺序）**

在 `contract/strings.json` 追加（zh-Hans / en 两栏都写）：
```json
"file.prefix.media":      { "zh-Hans": "现场影像", "en": "Field media" },
"file.prefix.audio":      { "zh-Hans": "现场录音", "en": "Field audio" },
"archive.path":           { "zh-Hans": "现场影像 / {date}", "en": "Field media / {date}" },
"login.title":            { "zh-Hans": "登录", "en": "Sign in" },
"login.phone":            { "zh-Hans": "手机号", "en": "Phone" },
"login.email":            { "zh-Hans": "邮箱", "en": "Email" },
"login.code":             { "zh-Hans": "验证码", "en": "Verification code" },
"login.sendCode":         { "zh-Hans": "发送验证码", "en": "Send code" },
"login.resend":           { "zh-Hans": "重新发送", "en": "Resend" },
"login.switchToEmail":    { "zh-Hans": "用邮箱登录", "en": "Use email" },
"login.switchToPhone":    { "zh-Hans": "用手机号登录", "en": "Use phone" },
"project.title":          { "zh-Hans": "选择归档项目", "en": "Choose a project" },
"project.retry":          { "zh-Hans": "重试", "en": "Retry" },
"project.signOut":        { "zh-Hans": "退出登录", "en": "Sign out" },
"home.mode.photo":        { "zh-Hans": "照片", "en": "Photo" },
"home.mode.video":        { "zh-Hans": "录像", "en": "Video" },
"home.mode.audio":        { "zh-Hans": "录音", "en": "Audio" },
"home.desktop.online":    { "zh-Hans": "电脑在线", "en": "Desktop online" },
"home.desktop.offline":   { "zh-Hans": "电脑离线 · 已等待 {mins} 分钟", "en": "Desktop offline · waiting {mins} min" },
"home.gps.none":          { "zh-Hans": "无定位", "en": "No GPS" },
"home.gps.accuracy":      { "zh-Hans": "±{m} 米", "en": "±{m} m" },
"home.permission.camera": { "zh-Hans": "需要相机权限才能取证拍摄", "en": "Camera permission is required" },
"library.title":          { "zh-Hans": "影像", "en": "Media" },
"library.unknownProject": { "zh-Hans": "未知项目", "en": "Unknown project" },
"library.otherPending":   { "zh-Hans": "其他项目还有 {n} 件未落盘", "en": "{n} more in other projects not landed" },
"library.empty":          { "zh-Hans": "这个项目还没有拍摄的影像", "en": "No media in this project yet" },
"library.select":         { "zh-Hans": "选择", "en": "Select" },
"library.cancel":         { "zh-Hans": "取消", "en": "Cancel" },
"library.delete":         { "zh-Hans": "删除", "en": "Delete" },
"queue.title":            { "zh-Hans": "上传队列", "en": "Upload queue" },
"queue.retry":            { "zh-Hans": "重试", "en": "Retry" },
"queue.retryAll":         { "zh-Hans": "全部重试", "en": "Retry all" },
"queue.expires":          { "zh-Hans": "中转区 {days} 天后清理", "en": "Relay clears in {days} days" },
"settings.title":         { "zh-Hans": "设置", "en": "Settings" },
"settings.saveToAlbum":   { "zh-Hans": "拍摄件同时存入相册", "en": "Also save captures to album" },
"settings.archiveTarget": { "zh-Hans": "归档目标", "en": "Archive target" },
"settings.switchProject": { "zh-Hans": "切换项目", "en": "Switch project" },
"settings.account":       { "zh-Hans": "账号", "en": "Account" },
"settings.server":        { "zh-Hans": "服务器", "en": "Server" },
"settings.signOut":       { "zh-Hans": "退出登录", "en": "Sign out" },
"settings.deleteAccount": { "zh-Hans": "注销账号", "en": "Delete account" },
"settings.deleteAccount.confirm": { "zh-Hans": "注销后云端账号与中转区数据删除，本机原图保留。确认注销？", "en": "Your cloud account and relay data will be deleted; local originals stay. Delete account?" },
"settings.usage":         { "zh-Hans": "中转区用量 {used} / {quota}", "en": "Relay usage {used} / {quota}" },
"settings.about":         { "zh-Hans": "关于", "en": "About" },
"common.ok":              { "zh-Hans": "确定", "en": "OK" },
"common.cancel":          { "zh-Hans": "取消", "en": "Cancel" },
"common.close":           { "zh-Hans": "关闭", "en": "Close" },
"error.network":          { "zh-Hans": "网络不可用", "en": "Network unavailable" },
"error.unauthorized":     { "zh-Hans": "登录已失效，请重新登录", "en": "Session expired, please sign in again" }
```
Run: `node contract/tools/gen.mjs && node contract/tools/check.mjs`（生成物含 `android/contract/.../Strings.kt` 更新；commit 时一起提交）。

- [ ] **Step 3: 跑测试确认失败**

Run: `cd android && ./gradlew :app:testIntlDebugUnitTest --tests "com.aiworkdeck.mobile.ContractFixturesTest" --console=plain 2>&1 | tail -15`
Expected: 编译失败，`Unresolved reference: TransferState` 等。

- [ ] **Step 4: 领域层实现**

`model/TransferState.kt`：
```kotlin
package com.aiworkdeck.mobile.model

import com.aiworkdeck.contract.ContractStates
import com.aiworkdeck.mobile.design.tr

data class StatusMerge(val state: TransferState, val waitingSeconds: Long?, val expiresAt: String?)

enum class TransferEvent(val raw: String) {
    kick("kick"), http2xx("http_2xx"), httpError("http_error"), networkError("network_error"),
    retryManual("retry_manual"), retryAuto("retry_auto"), statusDelivered("status_delivered"),
    statusPending("status_pending"), appLaunch("app_launch")
}

enum class TransferPhase(val raw: String) {
    uploading("uploading"), staged("staged"), landed("landed");
    val caption: String get() = tr(ContractStates.phaseLabelKey.getValue(raw))
    companion object { fun fromRaw(s: String) = entries.first { it.raw == s } }
}

/** 一张影像在「拍摄 → 抵达电脑」链上的位置。名称、别名、映射、文案键全部来自 ContractStates。 */
enum class TransferState(val raw: String) {
    waiting("waiting"), uploading("uploading"), uploaded("uploaded"), arrived("arrived"), failed("failed");

    val phase: TransferPhase get() = TransferPhase.fromRaw(ContractStates.phaseOf.getValue(raw))
    val caption: String get() = tr(ContractStates.stateTextKey.getValue(raw))
    val detail: String get() = tr(ContractStates.stateDetailKey.getValue(raw))
    val whereItIs: String get() = tr(ContractStates.whereKey.getValue(raw))

    /** 迁移表驱动。无规则 → null（非法迁移）；有规则但 guard 不满足 → 原态。 */
    fun next(event: TransferEvent, attempts: Int = 0): TransferState? {
        val rules = ContractStates.transitions.filter { it.from == raw && it.event == event.raw }
        if (rules.isEmpty()) return null
        for (r in rules) if (guardOk(r.guard, attempts)) return fromRaw(r.to) ?: error("契约迁移目标未知: ${r.to}")
        return this
    }

    /** 冷启动回拨 = app_launch 事件。 */
    fun recovered(attempts: Int = 0): TransferState = next(TransferEvent.appLaunch, attempts) ?: this

    /** status 轮询只对 uploaded 有意义；delivered 清掉等待字段，pending 回填。 */
    fun applyingStatus(delivered: Boolean, waitingSeconds: Long, expiresAt: String?): StatusMerge {
        if (this != uploaded) return StatusMerge(this, null, null)
        return if (delivered) StatusMerge(next(TransferEvent.statusDelivered) ?: this, null, null)
        else StatusMerge(next(TransferEvent.statusPending) ?: this, waitingSeconds, expiresAt)
    }

    companion object {
        /** 旧值（如 moving）按契约别名解码；编码始终用正式名。 */
        fun fromRaw(s: String): TransferState? {
            val canonical = ContractStates.aliases[s] ?: s
            return entries.firstOrNull { it.raw == canonical }
        }
        private fun guardOk(guard: String?, attempts: Int): Boolean = when (guard) {
            null -> true
            "attempts <= maxAutoRetries" -> attempts <= ContractStates.maxAutoRetries
            else -> error("未知 guard: $guard")
        }
    }
}
```

`model/TransferTally.kt`：
```kotlin
package com.aiworkdeck.mobile.model

data class TransferTally(val uploading: Int, val failed: Int, val staged: Int, val landed: Int) {
    val total: Int get() = uploading + staged + landed
    companion object {
        val zero = TransferTally(0, 0, 0, 0)
        fun of(items: List<CaptureItem>): TransferTally {
            var u = 0; var f = 0; var s = 0; var l = 0
            for (i in items) {
                when (i.state.phase) { TransferPhase.uploading -> u++; TransferPhase.staged -> s++; TransferPhase.landed -> l++ }
                if (i.state == TransferState.failed) f++
            }
            return TransferTally(u, f, s, l)
        }
    }
}
```

`model/Capture.kt`：
```kotlin
package com.aiworkdeck.mobile.model

import kotlinx.serialization.Serializable
import java.io.File
import java.time.*
import java.time.format.DateTimeFormatter

enum class MediaKind { photo, video, audio;
    val ext: String get() = when (this) { photo -> "jpg"; video -> "mp4"; audio -> "m4a" }
    val mediaType: String get() = when (this) { photo -> "image"; video -> "video"; audio -> "audio" }
}

/** 取证归档信息，字段与 iOS CaptureManifest.swift 一致。日期为 ISO8601 字符串。 */
@Serializable
data class CaptureManifest(
    val clientMediaId: String, val sha256: String, val capturedAt: String, val serverReceivedAt: String? = null,
    val latitude: Double? = null, val longitude: Double? = null, val horizontalAccuracy: Double? = null,
    val deviceModel: String, val osVersion: String, val appVersion: String, val fromCamera: Boolean, val tsaToken: String? = null,
)

@Serializable
data class RelayProject(val deviceId: String, val deviceName: String? = null, val key: String, val name: String) {
    val id: String get() = "$deviceId:$key"
}

/** 落盘行，与 iOS StoredRow 同形。state 存正式名字符串。 */
@Serializable
data class StoredRow(
    val kind: MediaKind, val state: String, val progress: Double, val manifest: CaptureManifest,
    val lastError: String? = null, val savedToAlbum: Boolean? = null, val project: RelayProject? = null,
)

data class CaptureItem(
    val id: String, val kind: MediaKind, val state: TransferState, val manifest: CaptureManifest, val localFile: File,
    val progress: Double, val lastError: String?, val savedToAlbum: Boolean, val project: RelayProject?,
) {
    val capturedAt: Instant get() = IsoTime.parse(manifest.capturedAt) ?: Instant.EPOCH
}

object IsoTime {
    private val out = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX")
    fun format(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): String = out.format(instant.atZone(zone))
    /** 宽容解析：带偏移用偏移；无偏移按本地；小数秒截断。 */
    fun parse(s: String, zone: ZoneId = ZoneId.systemDefault()): Instant? = try {
        val t = s.substringBefore('.').let { if (s.contains('.') && (s.endsWith("Z") || s.matches(Regex(".*[+-]\\d\\d:\\d\\d$")))) it + s.takeLastWhile { c -> c != '.' }.dropWhile { c -> c.isDigit() } else it }
        runCatching { OffsetDateTime.parse(t).toInstant() }.getOrElse { LocalDateTime.parse(t).atZone(zone).toInstant() }
    } catch (_: Exception) { null }
}
```

`model/LibraryGrouping.kt`：
```kotlin
package com.aiworkdeck.mobile.model

import com.aiworkdeck.contract.ContractStates
import com.aiworkdeck.mobile.design.tr
import java.time.LocalDate
import java.time.ZoneId

data class DaySection(val day: LocalDate, val title: String, val items: List<CaptureItem>)
data class ProjectChoice(val id: String, val name: String)

object LibraryGrouping {
    fun projectId(deviceId: String, key: String) = "$deviceId:$key"

    /** 删除确认等级：按所选里最坏的桶说话。n = 该桶件数；landed 时 n = 总数。 */
    fun deleteWarningLevel(states: List<TransferState>): Pair<String, Int> {
        for (phase in ContractStates.deleteWarnOrder) {
            if (phase == "landed") break
            val n = states.count { it.phase.raw == phase }
            if (n > 0) return ContractStates.deleteWarnLevel.getValue(phase) to n
        }
        return "landed" to states.size
    }

    fun deleteWarning(items: List<CaptureItem>): String {
        val (level, n) = deleteWarningLevel(items.map { it.state })
        return tr(ContractStates.deleteWarnKey.getValue(level), mapOf("n" to n))
    }

    /** 按本地自然日分段，新的在前；段内按时间倒序。段头「M月d日 · N 件」。 */
    fun groupByDay(items: List<CaptureItem>, zone: ZoneId = ZoneId.systemDefault()): List<DaySection> =
        items.groupBy { it.capturedAt.atZone(zone).toLocalDate() }.entries
            .sortedByDescending { it.key }
            .map { (day, list) ->
                val sorted = list.sortedByDescending { it.capturedAt }
                DaySection(day, tr("library.dayTitle", mapOf("m" to day.monthValue, "d" to day.dayOfMonth, "n" to sorted.size)), sorted)
            }

    /** 可切换的项目：当前项目永远第一，其余有记录的按名称排；无项目的记录归「未知项目」。 */
    fun projectsIn(items: List<CaptureItem>, current: RelayProject?): List<ProjectChoice> {
        val seen = LinkedHashMap<String, String>()
        for (it in items) {
            val p = it.project
            if (p == null) seen.putIfAbsent("unknown", tr("library.unknownProject")) else seen.putIfAbsent(p.id, p.name)
        }
        current?.let { seen.remove(it.id) }
        val rest = seen.entries.map { ProjectChoice(it.key, it.value) }.sortedBy { it.name }
        return listOfNotNull(current?.let { ProjectChoice(it.id, it.name) }) + rest
    }
}
```
`library.dayTitle` 键也要加进 `strings.json`：`{ "zh-Hans": "{m}月{d}日 · {n} 件", "en": "{m}/{d} · {n} items" }`，再跑 gen。

`design/L10n.kt`：
```kotlin
package com.aiworkdeck.mobile.design

import com.aiworkdeck.contract.ContractStrings

/** 契约文案。语言由 L10n.locale 决定，默认 zh-Hans（与 iOS 一致，英文待词典覆盖后再开）。缺键回显键名。 */
object L10n { @Volatile var locale: String = "zh-Hans" }

fun tr(key: String, vars: Map<String, Any> = emptyMap()): String {
    val entry = ContractStrings.table[key]
    var s = entry?.get("zh-Hans") ?: key
    if (L10n.locale != "zh-Hans") entry?.get(L10n.locale)?.takeIf { it.isNotEmpty() }?.let { s = it }
    for ((k, v) in vars) s = s.replace("{$k}", v.toString())
    return s
}
```

其余单测 `TransferStateTest.kt`（别名、非法迁移 null、guard 边界）、`L10nTest.kt`（占位替换、缺键回显、`L10n.locale="en"` 时取 en 并复原）、`LibraryGroupingTest.kt`（分段倒序与段头、projectsIn 当前优先与未知项目）各写 3–5 个断言。

- [ ] **Step 5: 跑测试**

Run: `cd android && ./gradlew :app:testIntlDebugUnitTest --console=plain 2>&1 | tail -12 && cd .. && node contract/tools/check.mjs`
Expected: 全过；`契约校验通过`。

- [ ] **Step 6: 提交**

```bash
git add contract android
git commit -m "feat(android): 领域层——契约驱动的状态机/计数/分组，5 夹具适配全过；词典加安卓各屏键

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: 契约扫描覆盖安卓源码（contract-change）

**Files:**
- Modify: `contract/tools/check.mjs`（`checkInline` 的 walk 列表加 `android/app/src/main`，扩展 `.kt`）
- Test: `tests/contract-tools.test.ts`

**Interfaces:**
- Produces: `check.mjs` ⑤ 扫描 `android/app/src/main/**/*.kt`（不含 `android/contract/`）。

- [ ] **Step 1: 失败测试**：在 `tests/contract-tools.test.ts` 追加：tempCopy 后写 `android/app/src/main/kotlin/Foo.kt` 含 `val x = "已落盘"`，`runChecks(dir,{quick:false})` 应有含 `Foo.kt` 与 `内联` 的问题。Run `npm test` → 该例 FAIL。
- [ ] **Step 2: 实现**：`checkInline` 的 files 里加 `...walk(join(c.root,'android','app','src','main'), ['.kt'], [])`。Run `npm test && node contract/tools/check.mjs` → 全绿（Task 1 的 Kotlin 源必须已无内联词典值；有则改 `tr`）。
- [ ] **Step 3: 提交** `git add contract/tools/check.mjs tests/contract-tools.test.ts` → `feat(contract): 内联文案扫描覆盖 android/app 源码`。

---

### Task 3: Backend 与 SessionStore

**Files:**
- Create: `services/ApiTypes.kt`、`services/Backend.kt`、`services/SessionStore.kt`
- Test: `test/.../BackendTest.kt`（MockWebServer）

**Interfaces:**
- Produces:
  - `interface SessionStore { fun current(): String?; fun save(id: String); fun clear() }`；`class EncryptedSessionStore(context) : SessionStore`（EncryptedSharedPreferences 文件 `session`，键 `sessionId`）；`class MemorySessionStore : SessionStore`（测试）
  - `class ApiError(val code: Int, message: String) : Exception(message)`；`class Unauthorized : Exception()`
  - `@Serializable data class AccountUser(id: Long, username: String, displayName: String, avatarUrl: String? = null, role: String? = null)`；`@Serializable data class LoginResult(sessionId: String, isNewUser: Boolean? = null, mustBindPhone: Boolean? = null, user: AccountUser)`；`@Serializable data class MediaStatus(clientMediaId: String, delivered: Boolean, waitingSeconds: Long, expiresAt: String? = null)`；`@Serializable data class MediaUsage(usedBytes: Long, quotaBytes: Long)`
  - `class Backend(baseUrl: String, session: SessionStore, client: OkHttpClient = OkHttpClient())`：`suspend fun sendLoginCode(phone)`、`verifyLoginCode(phone, code): LoginResult`、`sendMailLoginCode(email)`、`verifyMailLoginCode(email, code): LoginResult`、`myProjects(): List<RelayProject>`、`upload(file: File, deviceId, projectKey, clientMediaId, fileName, mediaType, capturedAt, onProgress: (Double) -> Unit): UploadResult`、`mediaStatus(ids: List<String>): List<MediaStatus>`、`mediaUsage(): MediaUsage`、`deleteAccount()`、`fun logout()`（本地清会话，无网络）
  - `@Serializable data class UploadResult(code: Int, id: Long, clientMediaId: String, delivered: Boolean)`

- [ ] **Step 1: 失败测试** `BackendTest.kt`（MockWebServer）：① `verifyLoginCode` 解信封 `{"code":0,"data":{...}}` 并保存 session；② `myProjects` 裸数组；③ 未登录 `{"code":4010}` → 抛 `Unauthorized` 且 `session.clear()`；④ `upload` multipart 含六个字段与 `file` part，请求头 `X-Session-Id`；⑤ `code:1` → `ApiError(message)`；⑥ `mediaStatus` 拼 `clientMediaIds=a,b`。
- [ ] **Step 2: 确认失败**：`./gradlew :app:testIntlDebugUnitTest --tests "*BackendTest*"` → 编译失败。
- [ ] **Step 3: 实现** `Backend.kt`：
```kotlin
package com.aiworkdeck.mobile.services

import com.aiworkdeck.mobile.model.RelayProject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import java.io.File

class ApiError(val code: Int, message: String) : Exception(message)
class Unauthorized : Exception("unauthorized")

class Backend(private val baseUrl: String, private val session: SessionStore, private val client: OkHttpClient = OkHttpClient()) {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }
    private val jsonType = "application/json; charset=utf-8".toMediaType()

    suspend fun sendLoginCode(phone: String) { envelope(post("/api/auth/sms-login/send-code", buildJsonObject { put("phone", phone) })) }
    suspend fun verifyLoginCode(phone: String, code: String): LoginResult =
        login(post("/api/auth/sms-login/verify", buildJsonObject { put("phone", phone); put("code", code) }))
    suspend fun sendMailLoginCode(email: String) { envelope(post("/api/auth/mail-login/send-code", buildJsonObject { put("email", email) })) }
    suspend fun verifyMailLoginCode(email: String, code: String): LoginResult =
        login(post("/api/auth/mail-login/verify", buildJsonObject { put("email", email); put("code", code) }))
    suspend fun deleteAccount() { envelope(post("/api/auth/account/delete", buildJsonObject {})) }
    fun logout() = session.clear()

    suspend fun myProjects(): List<RelayProject> = bare("/api/mobile/projects")
    suspend fun mediaUsage(): MediaUsage = bare("/api/mobile/media/usage")
    suspend fun mediaStatus(ids: List<String>): List<MediaStatus> =
        if (ids.isEmpty()) emptyList() else bare("/api/mobile/media/status?clientMediaIds=" + ids.joinToString(","))

    suspend fun upload(file: File, deviceId: String, projectKey: String, clientMediaId: String, fileName: String,
                       mediaType: String, capturedAt: String, onProgress: (Double) -> Unit): UploadResult = withContext(Dispatchers.IO) {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("deviceId", deviceId).addFormDataPart("projectKey", projectKey)
            .addFormDataPart("clientMediaId", clientMediaId).addFormDataPart("fileName", fileName)
            .addFormDataPart("mediaType", mediaType).addFormDataPart("capturedAt", capturedAt)
            .addFormDataPart("file", fileName, ProgressBody(file, onProgress)).build()
        val text = execute(Request.Builder().url(baseUrl + "/api/mobile/media").post(body))
        val el = json.parseToJsonElement(text).jsonObject
        checkEnvelopeCode(el)
        json.decodeFromJsonElement<UploadResult>(el)
    }

    // ---- 内部 ----
    private suspend fun post(path: String, body: JsonObject): String =
        execute(Request.Builder().url(baseUrl + path).post(body.toString().toRequestBody(jsonType)))
    private suspend inline fun <reified T> bare(path: String): T {
        val text = execute(Request.Builder().url(baseUrl + path).get())
        val el = json.parseToJsonElement(text)
        if (el is JsonObject) checkEnvelopeCode(el)   // 未登录 4010 信封
        return json.decodeFromJsonElement(el)
    }
    private fun envelope(text: String): JsonObject { val el = json.parseToJsonElement(text).jsonObject; checkEnvelopeCode(el); return el }
    private fun login(text: String): LoginResult {
        val r = json.decodeFromJsonElement<LoginResult>(envelope(text)["data"] ?: throw ApiError(1, "empty data"))
        session.save(r.sessionId); return r
    }
    /** 全站信封：code 0 成功；4010 未登录（清会话）；其他为业务错误。裸数组不进这里。 */
    private fun checkEnvelopeCode(el: JsonObject) {
        val code = el["code"]?.jsonPrimitive?.intOrNull ?: return
        if (code == 4010) { session.clear(); throw Unauthorized() }
        if (code != 0) throw ApiError(code, el["message"]?.jsonPrimitive?.contentOrNull ?: "code $code")
    }
    private suspend fun execute(b: Request.Builder): String = withContext(Dispatchers.IO) {
        session.current()?.let { b.header("X-Session-Id", it) }
        client.newCall(b.build()).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw ApiError(resp.code, "HTTP ${resp.code}")
            text
        }
    }
}

/** 带进度回调的文件体。 */
class ProgressBody(private val file: File, private val onProgress: (Double) -> Unit) : RequestBody() {
    override fun contentType() = "application/octet-stream".toMediaType()
    override fun contentLength() = file.length()
    override fun writeTo(sink: BufferedSink) {
        val total = file.length().coerceAtLeast(1); var sent = 0L
        file.inputStream().use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) { val n = input.read(buf); if (n < 0) break; sink.write(buf, 0, n); sent += n; onProgress(sent.toDouble() / total) }
        }
    }
}
```
`ApiTypes.kt` 放上面列的 `@Serializable` 类型；`SessionStore.kt` 放接口、`MemorySessionStore`、`EncryptedSessionStore`（`EncryptedSharedPreferences.create(context, "session", MasterKey.Builder(context).setKeyScheme(AES256_GCM).build(), PrefKeyEncryptionScheme.AES256_SIV, PrefValueEncryptionScheme.AES256_GCM)`）。
- [ ] **Step 4: 跑测试** → 6/6 过。
- [ ] **Step 5: 提交** `feat(android): Backend（OkHttp+信封解码+multipart 进度）与加密会话存储`。

---

### Task 4: EvidenceStore 与 Prefs

**Files:**
- Create: `services/EvidenceStore.kt`、`services/Prefs.kt`、`services/DeviceFacts.kt`
- Test: `test/.../EvidenceStoreTest.kt`

**Interfaces:**
- Produces: `class EvidenceStore(root: File, facts: DeviceFacts)`：`suspend fun save(kind, tempFile: File, capturedAt: Instant, location: Loc?, project: RelayProject?): CaptureItem`（移动到 `media/{id}.{ext}` → SHA-256 → 写 `manifest/{id}.json`，state=waiting）；`suspend fun loadAll(): List<CaptureItem>`（按 capturedAt 倒序；解析失败的行跳过并记日志）；`suspend fun updateState(id, to: TransferState, progress: Double = 0.0, error: String? = null)`；`suspend fun setProject(id, project)`；`suspend fun markSavedToAlbum(id)`；`suspend fun delete(ids: Set<String>)`；`suspend fun sweepOrphans(): Int`；`data class Loc(lat: Double, lon: Double, accuracy: Double?)`；`data class DeviceFacts(model, osVersion, appVersion)`；`class Prefs(context)`：`saveToAlbum: Boolean`（默认 true）、`selectedProject: RelayProject?`。所有写操作在 `Mutex` 内。

- [ ] **Step 1: 失败测试** `EvidenceStoreTest.kt`（`@Rule TemporaryFolder`）：① save 后 `media/` 有文件、`manifest/` 有 JSON、`sha256` 等于 `MessageDigest` 算的；② loadAll 解析出的 `state`、`project`；③ 旧 iOS 格式行（含 `"state":"moving"`）解码为 uploading；④ `updateState` 持久化；⑤ 有原件无 manifest 的孤儿被 `sweepOrphans` 清掉；⑥ `delete` 同时删原件与 manifest。
- [ ] **Step 2: 确认失败**。
- [ ] **Step 3: 实现**（关键片段）：
```kotlin
class EvidenceStore(private val root: File, private val facts: DeviceFacts) {
    private val media = File(root, "media").apply { mkdirs() }
    private val manifests = File(root, "manifest").apply { mkdirs() }
    private val mutex = Mutex()
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; prettyPrint = true }

    suspend fun save(kind: MediaKind, temp: File, capturedAt: Instant, loc: Loc?, project: RelayProject?): CaptureItem = mutex.withLock {
        val id = UUID.randomUUID().toString().lowercase()
        val dst = File(media, "$id.${kind.ext}")
        if (!temp.renameTo(dst)) { temp.copyTo(dst, overwrite = true); temp.delete() }
        val sha = sha256(dst)                                  // 落盘后再算，1MB 块流式
        val manifest = CaptureManifest(id, sha, IsoTime.format(capturedAt), null, loc?.lat, loc?.lon, loc?.accuracy,
            facts.model, facts.osVersion, facts.appVersion, fromCamera = true, tsaToken = null)
        val row = StoredRow(kind, TransferState.waiting.raw, 0.0, manifest, null, false, project)
        writeRow(id, row)                                      // manifest 最后写：存在即完整
        toItem(id, row)
    }
    // loadAll / updateState / setProject / markSavedToAlbum / delete / sweepOrphans 按接口实现；
    // toItem 用 TransferState.fromRaw(row.state)（别名解码），解不出的 state 视为 failed 并记 lastError。
    private fun sha256(f: File): String { val md = MessageDigest.getInstance("SHA-256"); f.inputStream().use { i -> val b = ByteArray(1 shl 20); while (true) { val n = i.read(b); if (n < 0) break; md.update(b, 0, n) } }; return md.digest().joinToString("") { "%02x".format(it) } }
}
```
`Prefs`：SharedPreferences `prefs`，`saveToAlbum` 默认 `true`，`selectedProject` 存 JSON。
- [ ] **Step 4: 跑测试** → 全过。
- [ ] **Step 5: 提交** `feat(android): EvidenceStore——原件→SHA-256→manifest 落盘顺序、别名解码、孤儿清理`。

---

### Task 5: UploadQueue、UploadWorker、文件命名

**Files:**
- Create: `services/UploadNaming.kt`、`services/UploadQueue.kt`、`services/UploadWorker.kt`、`services/Uploader.kt`（接口）
- Test: `test/.../UploadNamingTest.kt`、`UploadQueueTest.kt`

**Interfaces:**
- Produces:
  - `object UploadNaming { fun fileName(item: CaptureItem, zone: ZoneId = ZoneId.systemDefault()): String /* {prefix}-yyyyMMdd-HHmmss-{id前4}.{ext}，prefix = tr("file.prefix.media"|"file.prefix.audio") */ }`
  - `interface Uploader { suspend fun upload(item: CaptureItem, project: RelayProject, fileName: String, onProgress: (Double) -> Unit): UploadResult; suspend fun mediaStatus(ids: List<String>): List<MediaStatus> }`（`Backend` 实现它）
  - `class UploadQueue(store: EvidenceStore, uploader: Uploader, deviceIdProvider: () -> String, clock: () -> Long = System::currentTimeMillis)`：`val progress: StateFlow<Map<String, Double>>`；`val changes: SharedFlow<Unit>`；`suspend fun kick(): KickResult`（单飞；开头 `recovered()` 滞留件；逐件上传；成功 `http2xx`→uploaded；失败 `httpError|networkError`→failed 记 `lastError`；返回是否还有 waiting）；`suspend fun autoKick()`（退避到期才 kick：首败 60s，翻倍封顶 900s，成功复位）；`suspend fun retryFailed()`（failed→waiting 再 kick）；`suspend fun checkDelivered(): Map<String, String>`（uploaded 件查 status，用 `applyingStatus` 合并，返回 `clientMediaId→expiresAt`）；`val nextAutoKickAt: Long`
  - `class UploadWorker(ctx, params) : CoroutineWorker`：`companion fun enqueue(ctx)`（唯一名 `upload`，`ExistingWorkPolicy.KEEP`，约束 CONNECTED，`setExpedited(RUN_AS_NON_EXPEDITED_WORK_REQUEST)`）；`doWork` 内 `setForeground(通知渠道 upload)` 后循环 `kick()` 直到无 waiting 或失败退避。

- [ ] **Step 1: 失败测试**：`UploadNamingTest`：photo/video/audio 三种前缀与扩展名、时间戳格式、id 前 4 位；`UploadQueueTest`（FakeUploader 可编程成功/失败/抛 IOException，FakeStore 用 TemporaryFolder 上的真 EvidenceStore）：① 两个 waiting 件顺序上传、都变 uploaded、`fileName` 正确；② 失败→failed 且 `lastError` 有值，`nextAutoKickAt` 为 now+60s，再失败为 +120s，成功后复位；③ kick 开头把 uploading 滞留件回拨 waiting 后上传；④ `checkDelivered` delivered→arrived，pending 返回 expiresAt；⑤ 无 project 的件跳过不上传并保持 waiting。
- [ ] **Step 2: 确认失败**。
- [ ] **Step 3: 实现**（要点）：`kick` 用 `mutex.tryLock()` 单飞；每件 `store.updateState(id, uploading)` → `uploader.upload(...)` → 成功 `updateState(uploaded, 1.0)`；异常分类：`IOException`→`networkError`，`ApiError`→`httpError`，均 `updateState(failed, error = e.message)`；`attempts` 从 `lastError` 无法得知 → 队列内存计数 `attempts[id]`，成功清零；退避字段 `backoffSeconds` 初 60，失败 `min(backoff*2, 900)`，成功复位 60。`checkDelivered`：`uploaded` 件 id 列表分批 50 个查询；`applyingStatus` 后 `state != item.state` 才写。Worker：`setForeground(ForegroundInfo(id, notification, FOREGROUND_SERVICE_TYPE_DATA_SYNC))`，通知渠道 `upload`（`strings.xml` 的系统字串）。
- [ ] **Step 4: 跑测试** → 全过。
- [ ] **Step 5: 提交** `feat(android): 上传队列——单飞、退避、回拨、回执合并；WorkManager 前台任务驱动`。

---

### Task 6: 设计层（令牌、字体、组件、主题）

**Files:**
- Create: `design/Tokens.kt`、`design/Typography.kt`、`design/Theme.kt`、`design/Components.kt`

**Interfaces:**
- Produces: `object Tk { object L { val bg: Color … }; object D {…}; object S {…}; object Sp { val s1: Dp … gutter }; object Ty { val hero: TextUnit … } ; val touchMin: Dp }`（全部由 `com.aiworkdeck.contract.T` 转换：`Color(T.L.bg)`（Long ARGB）、`T.Sp.s4.dp`、`T.Ty.body.sp`）；`object Fonts { fun hero(): TextStyle（等宽、Light）; display(); title(); heading(); body(); small(); micro(); nano()（全大写字距 0.14em）; mono(size) }`；`@Composable fun WorkdeckTheme(dark: Boolean, content)`（`MaterialTheme` 仅提供 colorScheme.background/onBackground，其余全用 `Tk`）；组件：`StatusDot(state: TransferState, onDark: Boolean)`（`S.waiting/moving/arrived/failed`，深色用 `*OnDark`，映射按 `ContractStates.phaseDot/failedDot` 的令牌名解析）、`Pill(count, label, color)`、`TallyRow(tally, onDark)`（`phase.*` 标签 + `tally.failedSuffix`）、`GlassBar(content)`（API ≥ 31 `Modifier.graphicsLayer { renderEffect = BlurEffect(24f,24f) }` 叠底层截图不可行 → 实现为半透明底 + `RenderEffect` 仅在支持时对背景层模糊；否则实色 `D.surface`）、`Hairline()`、`PrimaryButton`、`RowItem`。

- [ ] **Step 1: 编写**（无单测，靠 Preview 与后续屏使用）：`Tokens.kt` 用反射禁止——手写映射每个字段；`Theme.kt` 提供 `LocalOnDark`。
- [ ] **Step 2: 编译** `./gradlew :app:assembleIntlDebug` 绿；`node contract/tools/check.mjs` 绿（组件里不写词典中文）。
- [ ] **Step 3: 提交** `feat(android): 设计层——契约令牌到 Compose、字体阶、状态点/计数行/玻璃条组件`。

---

### Task 7: AppModel、根路由、登录、选项目

**Files:**
- Create: `AppModel.kt`、`features/auth/LoginScreen.kt`、`features/auth/ProjectPickerScreen.kt`；Modify: `MainActivity.kt`、`App.kt`
- 对照 iOS：`ios/Sources/App/WorkdeckApp.swift:20-77`、`ios/Sources/App/AppModel.swift`、`ios/Sources/Features/Auth/LoginView.swift`、`ProjectPickerView.swift`

**Interfaces:**
- Produces: `class AppModel(app: Application) : ViewModel`（`StateFlow` 暴露）：`didRestore`、`isSignedIn`、`selectedProject: RelayProject?`、`items: List<CaptureItem>`（全部）、`currentItems`（当前项目）、`tally`、`otherPendingCount`、`cloudExpiry: Map<String,String>`、`desktopOnline: Boolean`（最近一次 `myProjects` 成功且含当前 deviceId 的时间 < 3 分钟）；动作：`bootstrap()`（恢复会话与项目、`sweepOrphans`、`loadAll`、启动 60s 心跳 `autoKick` + `checkDelivered`）、`didLogin(LoginResult)`、`selectProject(p)`、`clearProjectSelection()`、`signOut()`、`deleteAccount()`、`store(kind, tempFile, capturedAt, loc)`（写库 + 存相册（Prefs 开时）+ `UploadWorker.enqueue` + `kick`）、`retry(id)`、`retryFailedUploads()`、`checkDelivered()`、`delete(ids)`；`enum class Overlay { None, Library, Queue, Settings }`。
- `LoginScreen(model, defaultMethod = BuildConfig.DEFAULT_LOGIN)`：手机/邮箱切换、两步验证码、6 位自动提交、错误文案 `error.*`；`ProjectPickerScreen(model)`：列表、空态 `empty.projects`、错误重试、退出。
- `MainActivity.setContent { WorkdeckTheme(dark = route in {Home, Library, Viewer}) { Root(model) } }`；`Root`：`!didRestore` 占位色块 → `!isSignedIn` Login → `selectedProject == null` ProjectPicker → Home + overlay。

- [ ] **Step 1: 实现**（UI 无单测；`AppModel` 的纯逻辑 `otherPendingCount`/`desktopOnline` 判定抽成顶层函数并写 2 个单测）。
- [ ] **Step 2: 模拟器走查**：`avdmanager create avd -n awd -k "system-images;android-N;default;arm64-v8a" --force && emulator -avd awd -no-snapshot &`；`./gradlew :app:installCnDebug`；`adb shell am start -n com.aiworkdeck.mobile.cn/com.aiworkdeck.mobile.MainActivity`；用审核/演示账号（见项目记忆 mobile-local-verify-recipe，不入仓）登录 → 见项目列表（桌面端离线时为空态文案）。截图 `adb exec-out screencap -p > /tmp/awd-login.png` 存入报告。
- [ ] **Step 3: 提交** `feat(android): 根路由与 AppModel、登录、选项目`。

---

### Task 8: 采集服务与取景器主界面

**Files:**
- Create: `services/CameraService.kt`、`services/AudioRecorderService.kt`、`services/LocationStamper.kt`、`services/AlbumSaver.kt`、`features/home/HomeScreen.kt`、`features/home/CameraPreview.kt`、`features/home/Watermark.kt`
- 对照 iOS：`ios/Sources/Features/Home/HomeView.swift`、`ios/Sources/Services/CameraService.swift`、`AudioRecorderService.swift`、`AlbumSaver.swift`

**Interfaces:**
- Produces: `class CameraService(ctx, lifecycleOwner)`：`bind(previewView)`、`suspend fun takePhoto(): File`（`ImageCapture.OutputFileOptions` 写 cacheDir 临时文件，`CAPTURE_MODE_MAXIMIZE_QUALITY`，不做二次编码/EXIF 改写）、`startVideo(): Unit`、`suspend fun stopVideo(): File`（`Recorder` 输出 MP4 到 cacheDir）；`class AudioRecorderService`：`start()`/`stop(): File`（MediaRecorder AAC 44100 单声道 64kbps `.m4a`）；`class LocationStamper(ctx)`：`suspend fun current(timeoutMs = 4000): Loc?`（`LocationManager.getCurrentLocation(GPS_PROVIDER)`，API 30+；权限缺失返回 null）；`object AlbumSaver { fun save(ctx, file: File, kind: MediaKind) }`（`MediaStore` 插入 `Pictures/AI WorkDeck` 或 `Movies/AI WorkDeck`，音频不存）。
- `HomeScreen`：深色；顶部信息（项目名、`archive.path`、`TallyRow`、GPS 精度 `home.gps.*`、设置按钮）；中部 `CameraPreview`（`PreviewView` in `AndroidView`）+ 左下 `Watermark`（秒级时间、项目名、坐标±精度，只叠加）；底部三档 `home.mode.*` + 大快门（44dp 最小触控，照片单击、录像/录音切换开始/停止）+ 最近缩略图（进 Library）+ 桌面端状态 `home.desktop.*`；`ON_STOP` 时若在录停止并落库；相机权限缺失显示 `home.permission.camera` 与去设置按钮。

- [ ] **Step 1: 实现**；`Watermark` 的时间/坐标格式化函数写 2 个单测。
- [ ] **Step 2: 模拟器走查**：拍一张照、录 5 秒像、录 5 秒音；`adb shell ls /data/data/com.aiworkdeck.mobile.cn/files/FieldEvidence/{media,manifest}` 各 3 个文件；队列自动开始上传（有网时）；切后台再回来无崩溃。截图存报告。
- [ ] **Step 3: 提交** `feat(android): 相机/录音/单次定位/相册保存 + 取景器主界面`。

---

### Task 9: 图集与查看器

**Files:**
- Create: `features/library/LibraryScreen.kt`、`features/library/ViewerScreen.kt`
- 对照 iOS：`ios/Sources/Features/Library/LibraryView.swift`、`ViewerView.swift`、`ios/Sources/Model/LibraryGrouping.swift`

**Interfaces:**
- `LibraryScreen(model, onClose)`：深色；顶栏 `GlassBar`：项目菜单（`LibraryGrouping.projectsIn`，默认当前项目，`library.unknownProject`）、`TallyRow`（按 viewing 项目）、列数切换（2/3/4）、`library.select`；内容 `LazyVerticalGrid` 按 `groupByDay` 分段、粘性段头 `library.dayTitle`；多选：底部 `library.delete` → `AlertDialog(title = tr("delete.title",{n}), text = LibraryGrouping.deleteWarning(selected))`；空态 `library.empty`；底部小字 `library.otherPending`（N>0）；点击进 Viewer。缩略图用 Coil（视频用 `coil-video` 取帧）。
- `ViewerScreen(items: List<CaptureItem>, start: Int, onClose)`：`HorizontalPager` 同日条目；图片 `graphicsLayer` 双指缩放/双击复位；视频/音频 Media3 `ExoPlayer` + `PlayerView`；顶部 `item.state.caption` + 时间。

- [ ] **Step 1: 实现**（`LibraryGrouping` 已在 Task 1 有测；界面无单测）。
- [ ] **Step 2: 模拟器走查**：两天数据（用 `adb shell date` 改时间再拍，或直接修改 manifest 的 capturedAt）→ 分段正确；切项目菜单；多选删除三级警告文案各出现一次；Viewer 滑动/缩放/播放。截图存报告。
- [ ] **Step 3: 提交** `feat(android): 图集按项目分组分日、多选删除三级警告、全屏查看器`。

---

### Task 10: 队列页与设置页

**Files:**
- Create: `features/queue/QueueScreen.kt`、`features/settings/SettingsScreen.kt`
- 对照 iOS：`ios/Sources/Features/Queue/QueueView.swift`、`ios/Sources/Features/Settings/SettingsView.swift`

**Interfaces:**
- `QueueScreen(model, onClose)`：浅色；四段 `queue.section.failed / uploading / staged / landed`（只列当前项目）；行：缩略图、`StatusDot`、`state.caption`（failed 行附 `lastError`）、进度条（uploading）、SHA 前 12 位等宽、`queue.retry`；段末 `library.otherPending`；已暂存段 `queue.expires`（由 `cloudExpiry` 算剩余天数，<3 天黄字）；`LaunchedEffect` 每 20 秒 `model.checkDelivered()`；顶部 `queue.retryAll`。
- `SettingsScreen(model, onClose)`：浅色；开关 `settings.saveToAlbum`（`Prefs`）；`settings.archiveTarget` 显示项目名 + `settings.switchProject`（`clearProjectSelection`）；`settings.account`：`settings.server`（`BuildConfig.BASE_URL` 主机）、`settings.signOut`、`settings.deleteAccount`（二次确认 `settings.deleteAccount.confirm` → `deleteAccount()` → 回登录）；`settings.usage`（`mediaUsage`，MB/GB 格式化）；`settings.about`（versionName、包名）。

- [ ] **Step 1: 实现**；用量格式化函数写 2 个单测。
- [ ] **Step 2: 模拟器走查**：断网拍一张 → 队列失败段出现原因 → 联网点重试 → 上传中→已暂存；桌面端取件后（或用服务端测试账号手动 ack）20 秒内翻已落盘；设置里开关持久化、注销二次确认可取消。截图存报告。
- [ ] **Step 3: 提交** `feat(android): 上传队列页四段与轮询、设置页（相册/归档/账号/注销/用量）`。

---

### Task 11: 收尾——能力校正、后台上传验证、README、PR

**Files:**
- Modify（contract-change）: `contract/capabilities.json`（安卓实测值：`backgroundUpload: true`、`maxVideoSeconds: null`、`continuousSegments: false`、`glassBlur: "runtime"`、`deviceAttestation: false`；如实测不同以实测为准）→ gen → 提交生成物
- Modify: `android/README.md`（走查清单、已知限制）、总表 `EXTERNAL_SERVICES.md` §7.1 备注（可选）

- [ ] **Step 1: 后台上传验证**：断网拍 2 张 → 按 Home 键退到后台 → 联网 → 通知栏出现「正在上传现场影像」→ 两件变已暂存（`adb logcat | grep UploadWorker`）。
- [ ] **Step 2: 无 GMS 验证**：`./gradlew :app:dependencies --configuration cnReleaseRuntimeClasspath | grep -c gms` → 0。
- [ ] **Step 3: 全量**：`./gradlew :app:testIntlDebugUnitTest :app:assembleIntlDebug :app:assembleCnDebug`；`node contract/tools/check.mjs`；`npm test`。
- [ ] **Step 4: 提交、PR、看板**：PR 标题 `feat(android): Kotlin+Compose 客户端首版——对位 iOS 全功能（dev-board#400）`；在 #400 评论落实记录（落实情况 / PR / 模型 / 起止 / 分支 / 自验证含截图路径 / 复测提示）并置「待复测」。发版（签正式包、上商店）不在本计划，按总表 §7。
