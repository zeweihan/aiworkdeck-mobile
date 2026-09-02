package com.aiworkdeck.mobile.features.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.aiworkdeck.mobile.AppModel
import com.aiworkdeck.mobile.BuildConfig
import com.aiworkdeck.mobile.design.Fonts
import com.aiworkdeck.mobile.design.Hairline
import com.aiworkdeck.mobile.design.Tk
import com.aiworkdeck.mobile.design.tr
import com.aiworkdeck.mobile.services.ApiError
import com.aiworkdeck.mobile.services.ServiceLocator
import com.aiworkdeck.mobile.services.Unauthorized
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.IOException

private enum class Method { Phone, Email }
private enum class Step { Identity, Code }

/**
 * 首屏登录：手机号或邮箱 + 验证码。镜像 iOS `LoginView`。
 *
 * 两条路径**语义不同**，界面上必须说清：
 * - 手机号：注册与登录合一，号码没见过后端就建号。只走中国大陆短信通道。
 * - 邮箱：同样是注册登录合一，未注册的地址也会收到码，验过就建号。
 *
 * 默认哪一种由 [BuildConfig.DEFAULT_LOGIN] 决定：短信只有阿里云的大陆签名、发不到境外号码，
 * 让海外用户一进门就对着一个填不了的手机号框，是在浪费他一次尝试。两条路两个版本都留着——
 * 带 +86 号码的人在境外照样收得到码。
 */
@Composable
fun LoginScreen(model: AppModel, defaultLogin: String = BuildConfig.DEFAULT_LOGIN) {
    val backend = ServiceLocator.backend
    val scope = rememberCoroutineScope()
    var method by remember { mutableStateOf(if (defaultLogin == "sms") Method.Phone else Method.Email) }
    var step by remember { mutableStateOf(Step.Identity) }
    var phone by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var cooldown by remember { mutableIntStateOf(0) }
    val focus = remember { FocusRequester() }

    val identity = if (method == Method.Phone) phone else email
    val canSubmit = when (step) {
        Step.Identity -> if (method == Method.Phone) phone.length == 11 else looksLikeEmail(email)
        Step.Code -> code.length == 6
    }

    suspend fun send() {
        busy = true; error = null
        try {
            if (method == Method.Phone) backend.sendLoginCode(phone) else backend.sendMailLoginCode(email)
            step = Step.Code
            code = ""
            cooldown = 60
        } catch (e: Exception) {
            error = errorText(e)
        }
        busy = false
    }

    suspend fun verify() {
        if (busy) return
        busy = true; error = null
        try {
            val result = if (method == Method.Phone) backend.verifyLoginCode(phone, code)
            else backend.verifyMailLoginCode(email, code)
            model.didLogin(result)
        } catch (e: Exception) {
            error = errorText(e)
            code = ""
        }
        busy = false
    }

    // 60 秒重发冷却。后端也有冷却，这里只是别让人白点。
    LaunchedEffect(cooldown) {
        if (cooldown > 0) { delay(1000); cooldown -= 1 }
    }
    // 首帧节点还没落位时 requestFocus 会抛，接住即可——键盘晚一帧弹出好过启动就崩。
    LaunchedEffect(step, method) { runCatching { focus.requestFocus() } }

    Column(
        Modifier.fillMaxSize().background(Tk.L.bg).safeDrawingPadding()
            .padding(horizontal = Tk.Sp.gutter),
    ) {
        Spacer(Modifier.weight(1f))

        Eyebrow(tr(if (step == Step.Identity) "login.title" else "login.codeTitle"))
        Text(
            text = when {
                step == Step.Code -> tr("login.codePrompt")
                method == Method.Phone -> tr("login.phone")
                else -> tr("login.email")
            },
            style = Fonts.display(), color = Tk.L.fg, modifier = Modifier.padding(top = Tk.Sp.s2),
        )
        if (step == Step.Code) {
            Text(
                text = tr("login.sentTo", mapOf("to" to mask(method, identity))),
                style = Fonts.micro(), color = Tk.L.fgFaint, modifier = Modifier.padding(top = Tk.Sp.s1),
            )
        }

        if (step == Step.Identity) {
            MethodPicker(method, Modifier.padding(top = Tk.Sp.s4)) {
                if (method != it) { method = it; code = ""; error = null }
            }
        }

        // 输入框：一格大号等宽，看得清、核得准。手机号只收数字，验证码只收 6 位。
        val fieldTop = if (step == Step.Identity) Tk.Sp.s5 else Tk.Sp.s8
        Box(Modifier.padding(top = fieldTop)) {
            when {
                step == Step.Code -> Field(
                    value = code, placeholder = "······", mono = 28.sp, letterSpacing = true, focus = focus,
                    keyboard = KeyboardType.NumberPassword,
                ) { v ->
                    code = v.filter { it.isDigit() }.take(6)
                    error = null
                    if (code.length == 6) scope.launch { verify() }   // 满 6 位自动提交
                }
                method == Method.Phone -> Field(
                    value = phone, placeholder = tr("login.phonePlaceholder"), mono = 28.sp, focus = focus,
                    keyboard = KeyboardType.Phone,
                ) { v -> phone = v.filter { it.isDigit() }.take(11); error = null }
                else -> Field(
                    value = email, placeholder = tr("login.emailPlaceholder"), mono = 20.sp, focus = focus,
                    keyboard = KeyboardType.Email,
                ) { v -> email = v.trim(); error = null }
            }
        }
        Hairline(Modifier.padding(top = Tk.Sp.s3), color = Tk.L.rule)

        error?.let {
            Text(it, style = Fonts.micro(), color = Tk.S.failed, modifier = Modifier.padding(top = Tk.Sp.s3))
        }

        // 主动作。禁用时只是变灰不藏起来——用户要看得见「差什么才能往下走」。
        Row(
            Modifier.fillMaxWidth().heightIn(min = Tk.touchMin).padding(top = Tk.Sp.s6)
                .clickable(enabled = canSubmit && !busy) {
                    scope.launch { if (step == Step.Identity) send() else verify() }
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = tr(if (step == Step.Identity) "login.sendCode" else "login.title"),
                style = Fonts.heading(), color = if (canSubmit) Tk.L.accent else Tk.L.fgFaint,
            )
            Spacer(Modifier.weight(1f))
            Text("→", style = Fonts.heading(), color = if (canSubmit) Tk.L.accent else Tk.L.fgFaint)
        }

        if (step == Step.Code) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = Tk.touchMin).padding(top = Tk.Sp.s4),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Tk.Sp.s5),
            ) {
                val resendable = cooldown == 0 && !busy
                Text(
                    text = if (cooldown > 0) tr("login.resendIn", mapOf("s" to cooldown)) else tr("login.resend"),
                    style = Fonts.small(), color = if (resendable) Tk.L.accent else Tk.L.fgFaint,
                    modifier = Modifier.clickable(enabled = resendable) { scope.launch { send() } },
                )
                Text(
                    text = tr(if (method == Method.Phone) "login.changePhone" else "login.changeEmail"),
                    style = Fonts.small(), color = Tk.L.fgMuted,
                    modifier = Modifier.clickable { step = Step.Identity; code = ""; error = null },
                )
            }
        }

        Spacer(Modifier.weight(1f))
        Hairline(color = Tk.L.rule)
        Text(
            text = tr("login.help"), style = Fonts.nano(), color = Tk.L.fgFaint,
            modifier = Modifier.padding(top = Tk.Sp.s3, bottom = Tk.Sp.s6),
        )
    }
}

/** 全大写、字距拉开的小标签——这套排版的签名。 */
@Composable
internal fun Eyebrow(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), style = Fonts.nano(), color = Tk.L.fgMuted, modifier = modifier)
}

/**
 * 两个方式之间切换。切换要清掉验证码与报错，否则会出现「填了邮箱、报的是手机号那条的错」
 * 这种对不上号的状态。
 */
@Composable
private fun MethodPicker(current: Method, modifier: Modifier = Modifier, onPick: (Method) -> Unit) {
    Row(
        modifier.heightIn(min = Tk.touchMin),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tk.Sp.s5),
    ) {
        for (m in Method.entries) {
            Text(
                text = tr(if (m == Method.Phone) "login.phone" else "login.email"),
                style = Fonts.small(), color = if (m == current) Tk.L.accent else Tk.L.fgMuted,
                modifier = Modifier.clickable { onPick(m) },
            )
        }
    }
}

@Composable
private fun Field(
    value: String,
    placeholder: String,
    mono: TextUnit,
    focus: FocusRequester,
    keyboard: KeyboardType,
    letterSpacing: Boolean = false,
    onChange: (String) -> Unit,
) {
    val style = Fonts.mono(mono, FontWeight.Light).copy(
        color = Tk.L.fg, letterSpacing = if (letterSpacing) 0.3.em else TextStyle.Default.letterSpacing,
    )
    BasicTextField(
        value = value,
        onValueChange = onChange,
        singleLine = true,
        textStyle = style,
        cursorBrush = SolidColor(Tk.L.accent),
        keyboardOptions = KeyboardOptions(keyboardType = keyboard),
        modifier = Modifier.fillMaxWidth().focusRequester(focus),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, style = style.copy(color = Tk.L.fgFaint))
                inner()
            }
        },
    )
}

/** 只做「明显不是邮箱」的拦截，不做 RFC 校验——真正的判定在后端，客户端把合法地址挡下来更糟。 */
internal fun looksLikeEmail(email: String): Boolean {
    val at = email.indexOf('@')
    if (at <= 0) return false
    val domain = email.substring(at + 1)
    return domain.contains('.') && !domain.startsWith('.') && !domain.endsWith('.')
}

/** 回显发到哪去了，但不把标识完整重复一遍——旁边有人时那是一次不必要的泄露。 */
private fun mask(method: Method, value: String): String = when (method) {
    Method.Phone -> if (value.length < 7) value else value.take(3) + "****" + value.takeLast(4)
    Method.Email -> {
        val at = value.indexOf('@')
        if (at < 0) value else {
            val name = value.substring(0, at)
            (if (name.length <= 1) "***" else name.take(1) + "***") + value.substring(at)
        }
    }
}

/**
 * 报错文案。网络失败与业务失败要分开说——用户看到「验证码错误」和看到「网络不通」，
 * 下一步该做什么完全不同。
 */
internal fun errorText(e: Throwable): String = when (e) {
    is Unauthorized -> tr("error.unauthorized")
    is IOException -> tr("error.network")
    is ApiError -> e.message ?: tr("error.network")
    else -> e.message ?: tr("error.network")
}
