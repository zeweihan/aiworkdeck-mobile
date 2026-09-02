package com.aiworkdeck.mobile.services

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/** 加密会话存储：EncryptedSharedPreferences 文件 "session"，键 "sessionId"。仅此文件依赖 Android，不参与 JVM 单测。 */
class EncryptedSessionStore(context: Context) : SessionStore {
    private val prefs = EncryptedSharedPreferences.create(
        context,
        "session",
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    override fun current(): String? = prefs.getString(KEY, null)
    override fun save(id: String) { prefs.edit().putString(KEY, id).apply() }
    override fun clear() { prefs.edit().remove(KEY).apply() }

    private companion object { const val KEY = "sessionId" }
}
