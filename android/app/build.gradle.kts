import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    // kotlin-android 插件自 AGP 9.0 起内置于 android-application 插件，不再单独 apply（否则报错，
    // 见 https://kotl.in/gradle/agp-built-in-kotlin）；kotlin-compose / kotlin-serialization 仍需单独声明。
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

val localProps = Properties().apply {
    val f = rootProject.file("local.properties"); if (f.exists()) f.inputStream().use { load(it) }
}
fun prop(name: String): String? = localProps.getProperty(name) ?: System.getenv(name.uppercase().replace('.', '_'))

android {
    namespace = "com.aiworkdeck.mobile"
    compileSdk = 37
    defaultConfig {
        minSdk = 29
        targetSdk = 37
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
