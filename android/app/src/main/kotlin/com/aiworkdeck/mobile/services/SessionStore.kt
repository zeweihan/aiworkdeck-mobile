package com.aiworkdeck.mobile.services

import android.content.Context
import java.util.logging.Logger

interface SessionStore {
    fun current(): String?
    fun save(id: String)
    fun clear()
}

/** 内存会话存储，测试用；不落盘。 */
class MemorySessionStore : SessionStore {
    private var id: String? = null
    override fun current(): String? = id
    override fun save(id: String) { this.id = id }
    override fun clear() { id = null }
}

/**
 * 会话存储的装配点。[EncryptedSessionStore] 的主密钥在 Keystore 里，重装系统、恢复出厂、
 * 从别的机器传数据过来都可能让密钥与密文对不上——那时 `create` 会抛，而它是在
 * `Application.onCreate` 里调的，抛出去就是「一开就崩」的死循环，用户连卸载都不好定位。
 *
 * 所以：抛了就把那份已经解不开的 prefs 文件删掉重来一次（代价只是要重新登录一次），
 * 再不行退到内存存储——这一程用不了「记住登录」，但至少 App 能开、现场能拍。
 */
object SessionStores {
    private val logger = Logger.getLogger("SessionStores")
    private const val FILE = "session"

    fun create(ctx: Context): SessionStore = try {
        EncryptedSessionStore(ctx)
    } catch (first: Exception) {
        logger.warning("加密会话存储打不开，清掉重建: ${first.message}")
        runCatching { ctx.deleteSharedPreferences(FILE) }
        try {
            EncryptedSessionStore(ctx)
        } catch (second: Exception) {
            logger.warning("加密会话存储重建仍失败，本次退到内存存储: ${second.message}")
            MemorySessionStore()
        }
    }
}
