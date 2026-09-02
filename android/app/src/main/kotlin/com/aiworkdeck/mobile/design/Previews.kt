package com.aiworkdeck.mobile.design

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.aiworkdeck.mobile.model.TransferState
import com.aiworkdeck.mobile.model.TransferTally

/** 靠 Preview 目视走查，无单测：明暗各一份，验证 [Tk] 令牌落到组件上的实际观感。 */
@Preview(name = "TallyRow · light", showBackground = true, backgroundColor = 0xFFFFFFFF)
@Composable
private fun TallyRowLightPreview() {
    WorkdeckTheme(dark = false) {
        Box(Modifier.background(Tk.L.bg).padding(Tk.Sp.gutter)) {
            TallyRow(tally = TransferTally(uploading = 3, failed = 1, staged = 2, landed = 12), onDark = false)
        }
    }
}

@Preview(name = "TallyRow · dark", showBackground = true, backgroundColor = 0xFF0A0B0D)
@Composable
private fun TallyRowDarkPreview() {
    WorkdeckTheme(dark = true) {
        Box(Modifier.background(Tk.D.bg).padding(Tk.Sp.gutter)) {
            TallyRow(tally = TransferTally(uploading = 3, failed = 1, staged = 2, landed = 12), onDark = true)
        }
    }
}

@Preview(name = "StatusDot row · light", showBackground = true, backgroundColor = 0xFFFFFFFF)
@Composable
private fun StatusDotRowLightPreview() {
    WorkdeckTheme(dark = false) {
        Row(
            modifier = Modifier.background(Tk.L.bg).padding(Tk.Sp.gutter),
            horizontalArrangement = Arrangement.spacedBy(Tk.Sp.s4),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (state in TransferState.entries) StatusDot(state = state, onDark = false)
        }
    }
}

@Preview(name = "StatusDot row · dark", showBackground = true, backgroundColor = 0xFF0A0B0D)
@Composable
private fun StatusDotRowDarkPreview() {
    WorkdeckTheme(dark = true) {
        Row(
            modifier = Modifier.background(Tk.D.bg).padding(Tk.Sp.gutter),
            horizontalArrangement = Arrangement.spacedBy(Tk.Sp.s4),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (state in TransferState.entries) StatusDot(state = state, onDark = true)
        }
    }
}

@Preview(name = "GlassBar · light backdrop", showBackground = true, backgroundColor = 0xFFFFFFFF)
@Composable
private fun GlassBarLightBackdropPreview() {
    WorkdeckTheme(dark = false) {
        Box(Modifier.background(Tk.L.accentWash).fillMaxSize()) {
            GlassBar(modifier = Modifier.fillMaxSize().padding(Tk.Sp.s6)) {
                Box(Modifier.padding(Tk.Sp.gutter)) {
                    TallyRow(tally = TransferTally(uploading = 1, failed = 0, staged = 4, landed = 9), onDark = true)
                }
            }
        }
    }
}

@Preview(name = "GlassBar · dark backdrop", showBackground = true, backgroundColor = 0xFF0A0B0D)
@Composable
private fun GlassBarDarkBackdropPreview() {
    WorkdeckTheme(dark = true) {
        Box(Modifier.background(Tk.D.bg).fillMaxSize()) {
            GlassBar(modifier = Modifier.fillMaxSize().padding(Tk.Sp.s6)) {
                Box(Modifier.padding(Tk.Sp.gutter)) {
                    TallyRow(tally = TransferTally(uploading = 1, failed = 0, staged = 4, landed = 9), onDark = true)
                }
            }
        }
    }
}

@Preview(name = "PrimaryButton · light", showBackground = true, backgroundColor = 0xFFFFFFFF)
@Composable
private fun PrimaryButtonLightPreview() {
    WorkdeckTheme(dark = false) {
        Box(Modifier.background(Tk.L.bg).padding(Tk.Sp.gutter)) {
            PrimaryButton(text = tr("where.failed"), onClick = {})
        }
    }
}

@Preview(name = "PrimaryButton · dark", showBackground = true, backgroundColor = 0xFF0A0B0D)
@Composable
private fun PrimaryButtonDarkPreview() {
    WorkdeckTheme(dark = true) {
        Box(Modifier.background(Tk.D.bg).padding(Tk.Sp.gutter)) {
            PrimaryButton(text = tr("where.failed"), onClick = {})
        }
    }
}
