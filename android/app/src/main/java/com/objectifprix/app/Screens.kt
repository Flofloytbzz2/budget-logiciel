package com.objectifprix.app

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

// ───────────── Navigation ─────────────

object Nav {
    var tab by mutableStateOf(0)
    var detail by mutableStateOf<String?>(null)
    var editing by mutableStateOf(false)
    var editId by mutableStateOf<String?>(null)

    fun newGoal() {
        editId = null
        editing = true
    }

    fun editGoal(id: String) {
        editId = id
        editing = true
    }
}

@Composable
fun ScreenTitle(title: String, trailing: @Composable () -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Txt(title, size = 30, weight = FontWeight.Bold, heading = true, modifier = Modifier.weight(1f))
        trailing()
    }
}

@Composable
fun TopBar(title: String, onBack: () -> Unit, trailing: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        TextLink("←", color = Th.text, onClick = onBack)
        Txt(title, size = 17, weight = FontWeight.SemiBold, heading = true, modifier = Modifier.weight(1f), maxLines = 1)
        trailing()
    }
}

// ───────────── Liste des objectifs ─────────────

@Composable
fun BuyBadge(goal: Goal) {
    val verdict = goal.buyAdvice().verdict
    if (verdict == "lowest" || verdict == "good" || verdict == "high") {
        val good = verdict != "high"
        val key = if (verdict == "lowest") "advice.badge.great" else if (verdict == "good") "advice.badge.good" else "advice.badge.high"
        Box(Modifier.clip(CircleShape).background(if (good) Th.accent else Th.bad).padding(horizontal = 8.dp, vertical = 3.dp)) {
            Txt(L.t(key), size = 11, weight = FontWeight.Bold, color = if (good) Th.onAccent else Color.White)
        }
    }
}

@Composable
fun GoalCard(goal: Goal) {
    Card(onClick = { Nav.detail = goal.id }) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            ProductImage(goal.imageUrl, 56)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Txt(goal.displayName, size = 17, weight = FontWeight.SemiBold, heading = true, maxLines = 2)
                Txt(goal.host, size = 12, color = Th.muted, maxLines = 1)
            }
            BuyBadge(goal)
        }
        ProgressBar(goal.progress)
        val price = goal.price
        val line = if (price != null) L.f("card.saved_of", goal.money(goal.saved), goal.money(price))
        else L.f("card.saved_unknown", goal.money(goal.saved))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Txt(line, size = 14, modifier = Modifier.weight(1f))
            Txt(Math.round(goal.progress * 100).toString() + " %", size = 14, weight = FontWeight.Bold, color = Th.accent)
        }
        val (text, trend) = goal.variationInfo()
        val color = when (trend) {
            Trend.DOWN -> Th.accent
            Trend.UP -> Th.bad
            else -> Th.muted
        }
        Txt(text, size = 12, color = color)
    }
}

@Composable
fun ProgressBar(progress: Double) {
    Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(Th.panel2)) {
        Box(Modifier.fillMaxWidth(progress.toFloat().coerceIn(0f, 1f)).height(6.dp).clip(CircleShape).background(Th.accent))
    }
}

@Composable
fun GoalsTab() {
    val scope = rememberCoroutineScope()
    val goals = Store.sortedGoals(Settings.sort)
    var refreshing by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        ScreenTitle(L.t("tab.goals")) {
            if (goals.any { it.url.isNotEmpty() }) {
                TextLink(if (refreshing) "…" else "↻", color = Th.muted) {
                    if (!refreshing) {
                        refreshing = true
                        scope.launch {
                            for (g in Store.visibleGoals) if (g.url.isNotEmpty()) Store.refresh(g.id, manual = true)
                            refreshing = false
                        }
                    }
                }
            }
            TextLink("＋") { Nav.newGoal() }
        }
        if (goals.isEmpty()) {
            Column(
                Modifier.fillMaxSize().padding(32.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Txt(L.t("empty.title"), size = 22, weight = FontWeight.Bold, heading = true)
                Spacer(Modifier.height(8.dp))
                Txt(L.t("empty.sub"), size = 15, color = Th.muted, align = androidx.compose.ui.text.style.TextAlign.Center)
                Spacer(Modifier.height(20.dp))
                PrimaryButton(L.t("empty.cta")) { Nav.newGoal() }
            }
        } else {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(Th.gap)
            ) {
                for (g in goals) GoalCard(g)
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

// ───────────── Conseil d'achat, statistiques, jalons ─────────────

data class BuyAdvice(val verdict: String, val position: Double, val low: Double, val high: Double)

fun Goal.buyAdvice(): BuyAdvice {
    val prices = sortedHistory.map { it.price }
    val current = price
    if (current == null || prices.size < 3) return BuyAdvice("unknown", 0.5, price ?: 0.0, price ?: 0.0)
    val lo = prices.min()
    val hi = prices.max()
    if (hi - lo < 0.005) return BuyAdvice("stable", 0.5, lo, hi)
    val position = ((current - lo) / (hi - lo)).coerceIn(0.0, 1.0)
    val verdict = if (current <= lo + 0.005) "lowest" else if (position < 0.25) "good" else if (position < 0.65) "average" else "high"
    return BuyAdvice(verdict, position, lo, hi)
}

@Composable
fun BuyAdviceCard(goal: Goal) {
    val advice = goal.buyAdvice()
    Card {
        SectionLabel(L.t("advice.title"))
        if (advice.verdict == "unknown") {
            Txt(L.t("advice.need_data"), size = 14, color = Th.muted)
        } else {
            val color = when (advice.verdict) {
                "lowest", "good" -> Th.accent
                "average" -> Th.gold
                "high" -> Th.bad
                else -> Th.muted
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Dot(color, 14)
                Txt(L.t("advice." + advice.verdict), size = 16, weight = FontWeight.Bold)
            }
            if (advice.verdict != "stable") {
                Box(Modifier.fillMaxWidth().height(14.dp), contentAlignment = Alignment.CenterStart) {
                    Box(Modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(Th.panel2))
                    Row(Modifier.fillMaxWidth()) {
                        val before = advice.position.toFloat().coerceIn(0.001f, 0.999f)
                        Spacer(Modifier.weight(before))
                        Dot(color, 14)
                        Spacer(Modifier.weight(1f - before))
                    }
                }
                Row {
                    Txt(L.t("advice.min") + " " + goal.money(advice.low), size = 12, color = Th.muted, modifier = Modifier.weight(1f))
                    Txt(L.t("advice.max") + " " + goal.money(advice.high), size = 12, color = Th.muted)
                }
            }
        }
    }
}

data class GoalStats(val savedThisMonth: Double, val averagePerMonth: Double, val depositCount: Int, val streakWeeks: Int, val firstDate: Long?)

fun Goal.stats(): GoalStats {
    val zone = java.time.ZoneId.systemDefault()
    val now = java.time.LocalDate.now(zone)
    fun dateOf(t: Long) = java.time.Instant.ofEpochSecond(t).atZone(zone).toLocalDate()
    var thisMonth = 0.0
    for (e in log) {
        val d = dateOf(e.t)
        if (d.year == now.year && d.monthValue == now.monthValue) thisMonth += e.amount
    }
    val deposits = log.count { it.amount > 0 }
    val first = log.minOfOrNull { it.t }
    var average = 0.0
    if (first != null) {
        val days = java.time.temporal.ChronoUnit.DAYS.between(dateOf(first), now)
        average = saved / maxOf(days / 30.44, 1.0)
    }
    val weekStart = { d: java.time.LocalDate -> d.minusDays((d.dayOfWeek.value - 1).toLong()) }
    val weeks = HashSet<java.time.LocalDate>()
    for (e in log) if (e.amount > 0) weeks.add(weekStart(dateOf(e.t)))
    var streak = 0
    var cursor = weekStart(now)
    if (!weeks.contains(cursor)) cursor = cursor.minusWeeks(1)
    while (weeks.contains(cursor)) {
        streak++
        cursor = cursor.minusWeeks(1)
    }
    return GoalStats(thisMonth, average, deposits, streak, first)
}

@Composable
fun StatsCard(goal: Goal) {
    val s = goal.stats()
    Card {
        SectionLabel(L.t("stats.title"))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatTile(L.t("stats.this_month"), goal.money(s.savedThisMonth), Fmt.monthYear(nowSec()), Modifier.weight(1f))
            StatTile(L.t("stats.avg_month"), goal.money(s.averagePerMonth),
                s.firstDate?.let { L.f("stats.since", Fmt.shortDate(it)) } ?: "—", Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatTile(L.t("stats.deposits"), s.depositCount.toString(), L.t("stats.deposits_sub"), Modifier.weight(1f))
            StatTile(L.t("stats.streak"), L.f("stats.weeks", s.streakWeeks.toString()), L.t("stats.streak_sub"), Modifier.weight(1f))
        }
        SectionLabel(L.t("stats.milestones"))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            for (step in listOf(0.25, 0.5, 0.75, 1.0)) {
                val reached = goal.progress >= step - 0.0005
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(
                        Modifier.size(40.dp).clip(CircleShape).background(if (reached) Th.accent else Th.panel2),
                        contentAlignment = Alignment.Center
                    ) {
                        Txt(if (reached) "✓" else "⚑", size = 16, weight = FontWeight.Bold, color = if (reached) Th.onAccent else Th.muted)
                    }
                    Txt(Math.round(step * 100).toString() + " %", size = 12, weight = FontWeight.SemiBold,
                        color = if (reached) Th.text else Th.muted)
                }
            }
        }
    }
}

// ───────────── Fiche d'un objectif ─────────────

@Composable
fun DetailScreen(id: String) {
    val goal = Store.goal(id)
    if (goal == null) {
        LaunchedEffect(Unit) { Nav.detail = null }
        return
    }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var amountText by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    var messageBad by remember { mutableStateOf(false) }
    var manual by remember { mutableStateOf(false) }
    val fetching = Store.fetching.contains(id)

    fun move(sign: Int) {
        val v = Fmt.amount(amountText)
        if (v == null || v <= 0) {
            message = L.t("money.invalid")
            messageBad = true
            return
        }
        val before = goal.progress
        if (!Store.moveMoney(id, v, note.trim(), sign)) {
            message = L.t("money.nothing_to_remove")
            messageBad = true
            return
        }
        amountText = ""
        note = ""
        message = ""
        val after = Store.goal(id)?.progress ?: before
        if (sign > 0) {
            for (step in listOf(1.0, 0.75, 0.5, 0.25)) {
                if (before < step - 0.0005 && after >= step - 0.0005) {
                    Toast.makeText(context, L.f("milestone.reached", Math.round(step * 100).toString()), Toast.LENGTH_LONG).show()
                    break
                }
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(goal.displayName, onBack = { Nav.detail = null }) {
            if (goal.url.isNotEmpty()) {
                TextLink(if (fetching) "…" else "↻", color = Th.muted) {
                    if (!fetching) scope.launch {
                        val err = Store.refresh(id, manual = true)
                        message = err ?: L.t("detail.price_updated")
                        messageBad = err != null
                    }
                }
            }
            TextLink(L.t("menu.manual_price"), color = Th.muted) { manual = true }
            TextLink(L.t("menu.edit_goal")) { Nav.editGoal(id) }
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(Th.gap)
        ) {
            Card {
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    ProductImage(goal.imageUrl, 72)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Txt(goal.displayName, size = 20, weight = FontWeight.Bold, heading = true, maxLines = 3)
                        Txt(goal.host, size = 12, color = Th.muted, maxLines = 1)
                        val price = goal.price
                        if (price != null) Txt(goal.money(price), size = 18, weight = FontWeight.SemiBold, color = Th.accent)
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) { Ring(goal.progress, 150) }
                val (est, sub) = goal.estimate()
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    SectionLabel(L.t("stat.estimated_date"))
                    Txt(est, size = 20, weight = FontWeight.Bold, heading = true)
                    Txt(sub, size = 12, color = Th.muted)
                }
                val err = goal.lastError
                if (err != null) Txt(L.f("detail.last_failed", err), size = 12, color = Th.bad)
                if (goal.url.isEmpty()) Txt(L.t("detail.no_link"), size = 12, color = Th.muted)
                val checked = goal.lastCheck
                if (checked != null) Txt(L.f("detail.updated_on", Fmt.dateTime(checked)), size = 12, color = Th.muted)
                if (message.isNotEmpty()) Txt(message, size = 13, color = if (messageBad) Th.bad else Th.accent)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                val price = goal.price
                StatTile(L.t("stat.current_price"), price?.let { goal.money(it) } ?: "—",
                    goal.history.minOfOrNull { it.price }?.let { L.f("stat.lowest", goal.money(it)) } ?: L.t("stat.waiting"),
                    Modifier.weight(1f))
                StatTile(L.t("stat.saved"), goal.money(goal.saved),
                    L.f("stat.percent_of_goal", Math.round(goal.progress * 100).toString()), Modifier.weight(1f))
                StatTile(L.t("stat.missing"), goal.remaining?.let { goal.money(it) } ?: "—", " ", Modifier.weight(1f))
            }

            Card {
                SectionLabel(L.t("money.title"))
                Field(amountText, { amountText = it }, "0", keyboard = KeyboardType.Decimal)
                Field(note, { note = it }, L.t("money.note_placeholder"))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    PrimaryButton(L.t("money.add"), Modifier.weight(1f)) { move(1) }
                    GhostButton(L.t("money.remove"), Modifier.weight(1f)) { move(-1) }
                }
            }

            BuyAdviceCard(goal)
            PriceChart(goal)
            StatsCard(goal)

            Card {
                SectionLabel(L.t("activity.title"))
                if (goal.log.isEmpty()) {
                    Txt(L.t("activity.empty"), size = 14, color = Th.muted)
                } else {
                    for (e in goal.log.reversed().take(30)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Txt(Fmt.dateTime(e.t), size = 12, color = Th.muted)
                                if (e.note.isNotEmpty()) Txt(e.note, size = 13, maxLines = 2)
                            }
                            Txt((if (e.amount >= 0) "+" else "−") + goal.money(Math.abs(e.amount)), size = 15,
                                weight = FontWeight.SemiBold, color = if (e.amount >= 0) Th.accent else Th.bad)
                        }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (manual) ManualPriceDialog(id) { manual = false }
}

@Composable
fun ManualPriceDialog(id: String, onClose: () -> Unit) {
    var price by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    val goal = Store.goal(id)
    var footer = L.t("manual.help")
    val current = goal?.price
    if (goal != null && current != null) footer = L.f("manual.current", goal.money(current)) + " " + footer
    AlertDialog(
        onDismissRequest = onClose,
        containerColor = Th.panel,
        title = { Txt(L.f("manual.title_cur", goal?.cur ?: Settings.defaultCurrency), size = 18, weight = FontWeight.Bold, heading = true) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Field(price, { price = it }, L.t("manual.placeholder"), keyboard = KeyboardType.Decimal)
                Txt(footer, size = 12, color = Th.muted)
                if (error.isNotEmpty()) Txt(error, size = 13, color = Th.bad)
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val v = Fmt.amount(price)
                if (v == null || v <= 0) {
                    error = L.t("manual.invalid")
                } else {
                    Store.recordPrice(id, v, notify = false)
                    onClose()
                }
            }) { Txt(L.t("common.save"), color = Th.accent, weight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onClose) { Txt(L.t("common.cancel"), color = Th.muted) } }
    )
}

// ───────────── Création / modification ─────────────

@Composable
fun EditScreen(goalId: String?) {
    val existing = if (goalId != null) Store.goal(goalId) else null
    val rule0 = if (goalId != null) SavingRules.rule(goalId) else SavingRule()
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var url by remember { mutableStateOf(existing?.url ?: "") }
    var currency by remember { mutableStateOf(existing?.cur ?: Settings.defaultCurrency) }
    var monthly by remember { mutableStateOf(existing?.monthly?.takeIf { it > 0 }?.let { Fmt.plain(it) } ?: "") }
    var alert by remember { mutableStateOf(existing?.alertBelow?.takeIf { it > 0 }?.let { Fmt.plain(it) } ?: "") }
    var saveMode by remember { mutableStateOf(rule0.mode) }
    var saveAmount by remember { mutableStateOf(if (rule0.amount > 0) Fmt.plain(rule0.amount) else "") }
    var saveDay by remember { mutableStateOf(rule0.day.coerceIn(1, 28)) }
    var error by remember { mutableStateOf("") }
    var confirmDelete by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun close() {
        Nav.editing = false
    }

    fun deleteNow() {
        if (goalId != null) {
            Store.delete(goalId)
            Nav.detail = null
        }
        close()
    }

    fun save() {
        val m = Fmt.optionalAmount(monthly)
        val a = Fmt.optionalAmount(alert)
        if (m == null || a == null) {
            error = L.t("edit.err_amounts")
            return
        }
        val cleanName = name.trim()
        var cleanUrl = url.trim()
        if (cleanUrl.isNotEmpty()) {
            val parsed = PriceFetcher.cleanURL(cleanUrl)
            if (parsed == null) {
                error = L.t("edit.err_link")
                return
            }
            cleanUrl = parsed
        }
        if (cleanName.isEmpty() && cleanUrl.isEmpty()) {
            error = L.t("edit.err_empty")
            return
        }
        val rawSave = Fmt.optionalAmount(saveAmount)
        if (rawSave == null) {
            error = L.t("edit.err_amounts")
            return
        }
        if (saveMode == "auto" && rawSave <= 0) {
            error = L.t("err.save_amount")
            return
        }
        val rule = SavingRule(saveMode, rawSave, saveDay, "")
        if (goalId != null) {
            val changed = Store.edit(goalId, cleanName, cleanUrl, m, a, currency)
            SavingRules.set(rule, goalId)
            if (changed && cleanUrl.isNotEmpty()) scope.launch { Store.refresh(goalId, manual = true) }
        } else {
            val goal = Goal(name = cleanName, url = cleanUrl, monthly = m, alertBelow = a, currency = currency)
            Store.add(goal)
            SavingRules.set(rule, goal.id)
            if (cleanUrl.isNotEmpty()) Store.scope.launch { Store.refresh(goal.id, manual = true) }
        }
        if (saveMode == "weekly" || saveMode == "monthly" || a > 0) App.askNotifications()
        close()
    }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            TextLink(L.t("common.cancel"), color = Th.muted) { close() }
            Txt(if (existing != null) L.t("edit.title_edit") else L.t("edit.title_new"), size = 17,
                weight = FontWeight.SemiBold, heading = true, modifier = Modifier.weight(1f), align = androidx.compose.ui.text.style.TextAlign.Center)
            TextLink(L.t("common.save")) { save() }
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(Th.gap)
        ) {
            Card {
                SectionLabel(L.t("edit.product"))
                Field(name, { name = it }, L.t("edit.name_placeholder"))
            }
            Card {
                SectionLabel(L.t("edit.link"))
                Field(url, { url = it }, "https://…", keyboard = KeyboardType.Uri)
                Txt(L.t("edit.link_help"), size = 12, color = Th.muted)
            }
            Card {
                val choices = if (currency in Currencies.all) Currencies.all else listOf(currency) + Currencies.all
                Picker(L.t("edit.currency"), currency, choices.map { Pair(it, it + " " + Currencies.symbolText(it)) }) { currency = it }
                Txt(L.t("edit.currency_help"), size = 12, color = Th.muted)
            }
            Card {
                SectionLabel(L.t("edit.monthly"))
                Field(monthly, { monthly = it }, L.t("edit.monthly_placeholder"), keyboard = KeyboardType.Decimal)
                Txt(L.t("edit.monthly_help"), size = 12, color = Th.muted)
            }
            Card {
                SectionLabel(L.t("edit.alert"))
                Field(alert, { alert = it }, L.t("edit.alert_placeholder"), keyboard = KeyboardType.Decimal)
                Txt(L.t("edit.alert_help"), size = 12, color = Th.muted)
            }
            Card {
                SectionLabel(L.t("save.section"))
                Picker(L.t("save.mode"), saveMode, listOf("off", "weekly", "monthly", "auto").map { Pair(it, L.t("save.mode.$it")) }) { saveMode = it }
                if (saveMode != "off") Field(saveAmount, { saveAmount = it }, L.t("save.amount_ph"), keyboard = KeyboardType.Decimal)
                if (saveMode == "monthly" || saveMode == "auto") {
                    Picker(L.t("save.day"), saveDay.toString(), (1..28).map { Pair(it.toString(), it.toString()) }) { saveDay = it.toInt() }
                }
                if (saveMode == "auto") Txt(L.t("save.help_auto"), size = 12, color = Th.muted)
                else if (saveMode != "off") Txt(L.t("save.help_reminder"), size = 12, color = Th.muted)
            }
            if (error.isNotEmpty()) Txt(error, size = 14, color = Th.bad)
            if (existing != null) {
                GhostButton(L.t("edit.delete"), Modifier.fillMaxWidth(), danger = true) {
                    if (Settings.confirmDelete) confirmDelete = true else deleteNow()
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            containerColor = Th.panel,
            title = { Txt(L.t("edit.delete_q"), size = 17, weight = FontWeight.Bold) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    deleteNow()
                }) { Txt(L.t("common.delete"), color = Th.bad, weight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Txt(L.t("common.cancel"), color = Th.muted) } }
        )
    }
}
