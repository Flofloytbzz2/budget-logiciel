package com.objectifprix.app

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.launch

// ───────────── Compte (synchronisation) ─────────────

@Composable
fun AccountScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var token by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var confirmOut by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize()) {
        ScreenTitle(L.t("tab.account"))
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(Th.gap)
        ) {
            Card {
                SectionLabel(L.t("acct.sync"))
                if (SyncService.connected) {
                    Txt(L.f("acct.connected_as", SyncService.login ?: ""), size = 17, weight = FontWeight.Bold, heading = true)
                    Txt(L.t("acct.connected_info"), size = 13, color = Th.muted)
                    Txt(L.f("acct.goal_count", Store.visibleGoals.size.toString()), size = 13, color = Th.muted)
                    if (SyncService.status.isNotEmpty()) {
                        Txt(SyncService.status, size = 13, color = if (SyncService.isError) Th.bad else Th.accent)
                    }
                    PrimaryButton(L.t("acct.sync_now"), Modifier.fillMaxWidth(), enabled = !SyncService.isSyncing) {
                        scope.launch { SyncService.syncNow() }
                    }
                    GhostButton(L.t("acct.disconnect"), Modifier.fillMaxWidth(), danger = true) { confirmOut = true }
                } else {
                    Txt(L.t("acct.intro"), size = 14)
                    Txt("1. " + L.t("acct.step1"), size = 13, color = Th.muted)
                    Txt("2. " + L.t("acct.step2"), size = 13, color = Th.muted)
                    Txt("3. " + L.t("acct.step3"), size = 13, color = Th.muted)
                    GhostButton(L.t("acct.create_token"), Modifier.fillMaxWidth()) {
                        val url = "https://github.com/settings/tokens/new?scopes=gist&description=Objectif%20Prix"
                        try {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        } catch (e: Exception) {
                        }
                    }
                    Field(token, { token = it }, L.t("acct.token_placeholder"))
                    if (error.isNotEmpty()) Txt(error, size = 13, color = Th.bad)
                    PrimaryButton(if (busy) "…" else L.t("acct.connect"), Modifier.fillMaxWidth(), enabled = !busy) {
                        busy = true
                        error = ""
                        scope.launch {
                            val err = SyncService.connect(token)
                            busy = false
                            if (err != null) error = err else token = ""
                        }
                    }
                }
            }
            Card {
                SectionLabel(L.t("acct.privacy_title"))
                Txt(L.t("acct.privacy1"), size = 13, color = Th.muted)
                Txt(L.t("acct.privacy2"), size = 13, color = Th.muted)
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (confirmOut) {
        AlertDialog(
            onDismissRequest = { confirmOut = false },
            containerColor = Th.panel,
            title = { Txt(L.t("acct.disconnect_q"), size = 17, weight = FontWeight.Bold) },
            text = { Txt(L.t("acct.disconnect_msg"), size = 14, color = Th.muted) },
            confirmButton = {
                TextButton(onClick = {
                    confirmOut = false
                    SyncService.disconnect()
                }) { Txt(L.t("acct.disconnect"), color = Th.bad, weight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { confirmOut = false }) { Txt(L.t("common.cancel"), color = Th.muted) } }
        )
    }
}

// ───────────── Réglages ─────────────

@Composable
fun ThemeSwatches() {
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for (id in Themes.ids) {
            val p = Themes.palette(id)
            val selected = Settings.theme == id
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.clickable { Settings.edit { theme = id } }) {
                Box(
                    Modifier.size(54.dp).clip(RoundedCornerShape(14.dp)).background(c(p.bg))
                        .border(if (selected) 3.dp else 1.dp, if (selected) Th.accent else Th.border, RoundedCornerShape(14.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Box(Modifier.size(22.dp).clip(CircleShape).background(c(p.accent)))
                }
                Txt(L.t("theme.$id"), size = 11, color = if (selected) Th.text else Th.muted, maxLines = 1)
            }
        }
    }
}

@Composable
fun AccentSwatches() {
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(36.dp).clip(CircleShape).background(c(Settings.palette.accent))
                .border(if (Settings.accent < 0) 3.dp else 1.dp, if (Settings.accent < 0) Th.text else Th.border, CircleShape)
                .clickable { Settings.edit { accent = -1L } },
            contentAlignment = Alignment.Center
        ) { Txt("A", size = 12, weight = FontWeight.Bold, color = c(Settings.palette.onAccent)) }
        for (hex in Themes.accents) {
            val selected = Settings.accent == hex
            Box(
                Modifier.size(36.dp).clip(CircleShape).background(c(hex))
                    .border(if (selected) 3.dp else 1.dp, if (selected) Th.text else Th.border, CircleShape)
                    .clickable { Settings.edit { accent = hex } }
            )
        }
    }
}

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    var resetAsk by remember { mutableStateOf(false) }
    var info by remember { mutableStateOf("") }

    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) {
            try {
                context.contentResolver.openOutputStream(uri)?.use { it.write(Store.backupText().toByteArray(Charsets.UTF_8)) }
                info = L.t("common.ok")
            } catch (e: Exception) {
                info = L.t("set.import_failed")
            }
        }
    }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            try {
                val text = context.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) } ?: ""
                val n = Store.restore(text)
                info = if (n == null) L.t("set.import_failed") else L.f("set.import_ok", n.toString())
            } catch (e: Exception) {
                info = L.t("set.import_failed")
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        ScreenTitle(L.t("tab.settings"))
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(Th.gap)
        ) {
            Card {
                SectionLabel(L.t("set.appearance"))
                Txt(L.t("set.theme"), size = 15)
                ThemeSwatches()
                Txt(L.t("set.accent"), size = 15)
                AccentSwatches()
                Picker(L.t("set.font"), Settings.font,
                    listOf("editorial", "standard", "rounded", "serif", "mono").map { Pair(it, L.t("font.$it")) }) {
                    Settings.edit { font = it }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Txt(L.t("set.font_size"), size = 15, modifier = Modifier.weight(1f))
                    Txt(Math.round(Settings.fontScale * 100).toString() + " %", size = 14, color = Th.muted)
                }
                Slider(
                    value = Settings.fontScale,
                    onValueChange = { v -> Settings.edit { fontScale = Math.round(v * 20f) / 20f } },
                    valueRange = 0.85f..1.4f,
                    colors = SliderDefaults.colors(thumbColor = Th.accent, activeTrackColor = Th.accent, inactiveTrackColor = Th.panel2)
                )
                SwitchRow(L.t("set.compact"), Settings.compact) { v -> Settings.edit { compact = v } }
            }

            Card {
                SectionLabel(L.t("set.language_formats"))
                Picker(L.t("set.language"), Settings.language,
                    listOf(Pair("auto", L.t("lang.auto")), Pair("fr", "Français"), Pair("en", "English"),
                        Pair("es", "Español"), Pair("de", "Deutsch"))) { Settings.edit { language = it } }
                Picker(L.t("set.currency"), Settings.defaultCurrency,
                    Currencies.all.map { Pair(it, it + " " + Currencies.symbolText(it)) }) { Settings.edit { defaultCurrency = it } }
                Picker(L.t("set.number_format"), Settings.numberFormat,
                    listOf(Pair("auto", L.t("fmt.auto")), Pair("fr", "1 234,56"), Pair("en", "1,234.56"))) { Settings.edit { numberFormat = it } }
                Picker(L.t("set.date_format"), Settings.dateFormat,
                    listOf(Pair("auto", L.t("fmt.auto")), Pair("dmy", "31/12/2026"), Pair("mdy", "12/31/2026"), Pair("ymd", "2026-12-31"))) {
                    Settings.edit { dateFormat = it }
                }
                Txt(L.t("set.currency_help"), size = 12, color = Th.muted)
            }

            Card {
                SectionLabel(L.t("set.prices"))
                Picker(L.t("set.refresh"), Settings.refreshHours.toString(),
                    listOf(6, 12, 24, 48, 0).map { Pair(it.toString(), L.t(if (it == 0) "refresh.manual" else "refresh.h$it")) }) {
                    Settings.edit { refreshHours = it.toInt() }
                }
                Txt(L.t("set.refresh_help"), size = 12, color = Th.muted)
                SwitchRow(L.t("set.notifications"), Settings.notifications) { v ->
                    Settings.edit { notifications = v }
                    if (v) App.askNotifications()
                }
                TextLink(L.t("set.system_notifications")) {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                    } catch (e: Exception) {
                    }
                }
            }

            Card {
                SectionLabel(L.t("set.experience"))
                SwitchRow(L.t("set.confirm_delete"), Settings.confirmDelete) { v -> Settings.edit { confirmDelete = v } }
                Picker(L.t("set.sort"), Settings.sort,
                    listOf("added", "progress", "remaining", "price", "name").map { Pair(it, L.t("sort.$it")) }) {
                    Settings.edit { sort = it }
                }
            }

            Card {
                SectionLabel(L.t("set.data"))
                Txt(L.t("set.data_help"), size = 12, color = Th.muted)
                GhostButton(L.t("set.export"), Modifier.fillMaxWidth()) { exportLauncher.launch("objectif-prix-sauvegarde.json") }
                GhostButton(L.t("set.import"), Modifier.fillMaxWidth()) { importLauncher.launch(arrayOf("application/json", "text/plain", "*/*")) }
                if (info.isNotEmpty()) Txt(info, size = 13, color = Th.accent)
            }

            Card {
                SectionLabel(L.t("set.help"))
                GhostButton(L.t("set.replay_tutorial"), Modifier.fillMaxWidth()) { Settings.tutorialShown = true }
                GhostButton(L.t("set.reset"), Modifier.fillMaxWidth(), danger = true) { resetAsk = true }
                Txt(L.f("set.about", L.t("app.name"), "1.0"), size = 12, color = Th.muted, align = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth())
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (resetAsk) {
        AlertDialog(
            onDismissRequest = { resetAsk = false },
            containerColor = Th.panel,
            title = { Txt(L.t("set.reset_q"), size = 17, weight = FontWeight.Bold) },
            text = { Txt(L.t("set.reset_msg"), size = 14, color = Th.muted) },
            confirmButton = {
                TextButton(onClick = {
                    resetAsk = false
                    Settings.resetAll()
                }) { Txt(L.t("set.reset"), color = Th.bad, weight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { resetAsk = false }) { Txt(L.t("common.cancel"), color = Th.muted) } }
        )
    }
}

// ───────────── Tutoriel de première ouverture ─────────────

@Composable
fun Tutorial() {
    var step by remember { mutableStateOf(0) }
    var asked by remember { mutableStateOf(false) }
    val last = 5

    fun finish() {
        Settings.edit { onboarded = true }
        Settings.tutorialShown = false
    }

    Box(Modifier.fillMaxSize().background(Th.bg).clickable(enabled = false) {}) {
        Column(Modifier.fillMaxSize().padding(20.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (i in 0..last) {
                        Box(Modifier.size(width = if (i == step) 22.dp else 8.dp, height = 8.dp).clip(CircleShape)
                            .background(if (i == step) Th.accent else Th.panel2))
                    }
                }
                TextLink(L.t("tuto.skip"), color = Th.muted) { finish() }
            }
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                val key = listOf("welcome", "theme", "link", "money", "alerts", "sync")[step]
                Txt(L.t("tuto.$key.title"), size = 32, weight = FontWeight.Bold, heading = true)
                Txt(L.t("tuto.$key.text"), size = 17, color = Th.muted)
                when (key) {
                    "theme" -> {
                        ThemeSwatches()
                        AccentSwatches()
                    }
                    "link" -> {
                        Card {
                            SectionLabel(L.t("tuto.link.stores"))
                            Txt("Amazon · Best Buy · Walmart · eBay · Fnac · idealo · Zalando · Decathlon…", size = 14)
                        }
                        Txt(L.t("tuto.link.manual"), size = 14, color = Th.muted)
                    }
                    "money" -> Txt(L.t("tuto.money.hint"), size = 14, color = Th.muted)
                    "alerts" -> {
                        PrimaryButton(if (asked) L.t("tuto.alerts.asked") else L.t("tuto.alerts.enable"), enabled = !asked) {
                            asked = true
                            App.askNotifications()
                        }
                        Txt(L.t("tuto.alerts.hint"), size = 14, color = Th.muted)
                    }
                    "sync" -> {
                        Card {
                            SectionLabel(L.t("tuto.sync.where"))
                            Txt(L.t("tuto.sync.hint"), size = 14)
                        }
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                if (step > 0) GhostButton(L.t("tuto.back"), Modifier.weight(1f)) { step-- }
                PrimaryButton(if (step >= last) L.t("tuto.start") else L.t("tuto.next"), Modifier.weight(1f)) {
                    if (step >= last) finish() else step++
                }
            }
        }
    }
}
