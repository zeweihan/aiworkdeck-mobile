package com.aiworkdeck.mobile.services

import android.os.Build
import com.aiworkdeck.mobile.BuildConfig

/** 落盘 manifest 里记的设备指纹，与 iOS DeviceFacts 同形。数据类本身不依赖 Android（EvidenceStore 才能留在 JVM 单测里跑），取值的工厂在文件末尾。 */
data class DeviceFacts(val model: String, val osVersion: String, val appVersion: String)

/** 本机指纹。取 Build 的两个字段与包版本号——只在 App 进程里调用，单测直接构造 [DeviceFacts]。 */
fun deviceFacts(): DeviceFacts = DeviceFacts(
    model = Build.MODEL,
    osVersion = "Android " + Build.VERSION.RELEASE,
    appVersion = BuildConfig.VERSION_NAME,
)
