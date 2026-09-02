package com.aiworkdeck.mobile.features.settings

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aiworkdeck.mobile.AppModel
import com.aiworkdeck.mobile.BuildConfig
import com.aiworkdeck.mobile.design.Fonts
import com.aiworkdeck.mobile.design.Hairline
import com.aiworkdeck.mobile.design.Tk
import com.aiworkdeck.mobile.design.WorkdeckTheme
import com.aiworkdeck.mobile.design.tr
import com.aiworkdeck.mobile.features.auth.Eyebrow
import com.aiworkdeck.mobile.features.queue.TextAction
import com.aiworkdeck.mobile.features.queue.noRipple
import com.aiworkdeck.mobile.services.MediaUsage
import com.aiworkdeck.mobile.services.ServiceLocator
import kotlinx.coroutines.launch

/** 用量读不到时的占位。一条「—」比一行报错更符合这行信息的分量。 */
private const val DASH = "—"

/**
 * 设置。四组：影像（存相册）、归档目标（项目与云端用量）、账号（服务器、退出、注销）、关于。
 * 镜像 iOS `SettingsView`。
 */
@Composable
fun SettingsScreen(model: AppModel, onClose: () -> Unit) {
    val prefs = ServiceLocator.prefs
    val project by model.selectedProject.collectAsStateWithLifecycle()
    val account by model.account.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var saveToAlbum by remember { mutableStateOf(prefs.saveToAlbum) }
    var usage by remember { mutableStateOf<MediaUsage?>(null) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }

    // 进页面拉一次用量。失败静默——占位「—」比一条报错更符合这行信息的分量。
    LaunchedEffect(Unit) { usage = try { model.mediaUsage() } catch (_: Exception) { null } }

    WorkdeckTheme(dark = false) {
        Column(Modifier.fillMaxSize().background(Tk.L.bg).safeDrawingPadding()) {
            TopBar(onClose)

            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(horizontal = Tk.Sp.gutter).padding(bottom = Tk.Sp.s16),
            ) {
                Group(tr("settings.media")) {
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Tk.Sp.s3),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(tr("settings.saveToAlbum"), style = Fonts.body(), color = Tk.L.fg)
                            // 把权衡摆在这儿，让每次选择都是知情的：尽调影像进相册，
                            // 手机丢了或被查时它就躺在那儿。
                            Text(tr("settings.saveToAlbum.hint"), style = Fonts.nano(), color = Tk.L.fgFaint)
                        }
                        Switch(
                            checked = saveToAlbum,
                            onCheckedChange = { saveToAlbum = it; prefs.saveToAlbum = it },
                            colors = SwitchDefaults.colors(checkedTrackColor = Tk.L.accent),
                        )
                    }
                }

                Group(tr("settings.archiveTarget")) {
                    InfoRow(tr("home.eyebrow"), project?.name ?: DASH)
                    InfoRow(tr("settings.relay"), usageCaption(usage))
                    UsageBar(usage)
                    TextAction(tr("settings.switchProject"), color = Tk.L.accent) {
                        // 清掉选择即回选择页：Root 看到 selectedProject 变 null 自己路由
                        model.clearProjectSelection()
                        onClose()
                    }
                }

                Group(tr("settings.account")) {
                    InfoRow(tr("settings.signedIn"), account?.displayName ?: DASH)
                    InfoRow(tr("settings.server"), Uri.parse(BuildConfig.BASE_URL).host ?: DASH)
                    TextAction(tr("common.signOut"), color = Tk.S.failed) { model.signOut(); onClose() }
                    // 各应用商店的账号删除要求（与 App Store 5.1.1(v)）都指向这个入口。
                    // 放在退出登录下面、字号更小：它比退出重得多，不该长得一样容易误点。
                    Text(
                        tr("settings.deleteAccount"), style = Fonts.micro(), color = Tk.L.fgMuted,
                        modifier = Modifier.heightIn(min = Tk.touchMin).noRipple { confirmingDelete = true }
                            .wrapContentHeight(),
                    )
                    deleteError?.let { Text(it, style = Fonts.nano(), color = Tk.S.failed) }
                }

                Group(tr("settings.about")) {
                    InfoRow(tr("settings.version"), BuildConfig.VERSION_NAME)
                    InfoRow(tr("settings.package"), BuildConfig.APPLICATION_ID)
                }
            }
        }

        // 不可逆，所以走二次确认；文案把「删什么、不删什么」都说全——
        // 只写「无法恢复」等于没说清代价。
        if (confirmingDelete) {
            AlertDialog(
                onDismissRequest = { if (!deleting) confirmingDelete = false },
                title = { Text(tr("settings.deleteAccount.title")) },
                text = { Text(tr("settings.deleteAccount.confirm")) },
                confirmButton = {
                    TextButton(
                        enabled = !deleting,
                        onClick = {
                            deleting = true
                            scope.launch {
                                try {
                                    model.deleteAccount()
                                    confirmingDelete = false
                                    onClose()
                                } catch (e: Exception) {
                                    deleteError = e.message ?: tr("error.network")
                                    confirmingDelete = false
                                }
                                deleting = false
                            }
                        },
                    ) { Text(tr("settings.deleteAccount"), color = Tk.S.failed) }
                },
                dismissButton = {
                    TextButton(enabled = !deleting, onClick = { confirmingDelete = false }) {
                        Text(tr("common.cancel"))
                    }
                },
            )
        }
    }
}

/** 「已用 / 配额」。满了之后上传会被拒并提示去桌面端收件，这行让用户提前有数。 */
private fun usageCaption(usage: MediaUsage?): String {
    val u = usage ?: return DASH
    return tr("settings.usage", mapOf("used" to formatBytes(u.usedBytes), "quota" to formatBytes(u.quotaBytes)))
}

/** 细条。配额本身不是状态，所以用中性的强调色而不是状态点那三色。 */
@Composable
private fun UsageBar(usage: MediaUsage?) {
    val fraction = usage?.takeIf { it.quotaBytes > 0 }
        ?.let { (it.usedBytes.toDouble() / it.quotaBytes).coerceIn(0.0, 1.0).toFloat() } ?: 0f
    Box(Modifier.fillMaxWidth().height(2.dp).background(Tk.L.sunken)) {
        if (fraction > 0f) {
            Box(Modifier.fillMaxWidth(fraction).height(2.dp).background(Tk.L.accent))
        }
    }
}

@Composable
private fun TopBar(onClose: () -> Unit) {
    Column {
        Row(
            Modifier.fillMaxWidth().padding(start = Tk.Sp.s2, end = Tk.Sp.gutter, bottom = Tk.Sp.s2),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Tk.Sp.s2),
        ) {
            Box(
                Modifier.size(Tk.touchMin).noRipple(onClose)
                    .semantics { contentDescription = tr("common.close") },
                contentAlignment = Alignment.Center,
            ) { Text("✕", style = Fonts.body(), color = Tk.L.fg) }
            Text(tr("home.settings"), style = Fonts.heading(), color = Tk.L.fg)
        }
        Hairline(color = Tk.L.rule)
    }
}

@Composable
private fun Group(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Tk.Sp.s3)) {
        Eyebrow(title, Modifier.padding(top = Tk.Sp.s6, bottom = Tk.Sp.s1))
        content()
        Hairline(color = Tk.L.rule, modifier = Modifier.padding(top = Tk.Sp.s2))
    }
}

@Composable
private fun InfoRow(key: String, value: String, valueColor: Color = Tk.L.fgFaint) {
    Column(Modifier.fillMaxWidth()) {
        Text(key, style = Fonts.small(), color = Tk.L.fg)
        Text(value, style = Fonts.nano(), color = valueColor)
    }
}
