package com.aiworkdeck.mobile.services

import kotlinx.serialization.Serializable

@Serializable
data class AccountUser(
    val id: Long,
    val username: String,
    val displayName: String,
    val avatarUrl: String? = null,
    val role: String? = null,
)

@Serializable
data class LoginResult(
    val sessionId: String,
    val isNewUser: Boolean? = null,
    val mustBindPhone: Boolean? = null,
    val user: AccountUser,
)

@Serializable
data class MediaStatus(
    val clientMediaId: String,
    val delivered: Boolean,
    val waitingSeconds: Long,
    val expiresAt: String? = null,
)

@Serializable
data class MediaUsage(val usedBytes: Long, val quotaBytes: Long)

@Serializable
data class UploadResult(val code: Int, val id: Long, val clientMediaId: String, val delivered: Boolean)
