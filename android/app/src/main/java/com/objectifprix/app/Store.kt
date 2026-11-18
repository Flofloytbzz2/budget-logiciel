package com.objectifprix.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit

// ───────────── Données locales ─────────────

object Store {
    lateinit var ctx: Context
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    var goals by mutableStateOf<List<Goal>>(emptyList())
        private set
    var fetching by mutableStateOf<Set<String>>(emptySet())
        private set

    private val retryAfterFailure = 3L * 3600
    private val file: File get() = File(ctx.filesDir, "objectif-prix.json")

    fun init(context: Context) {
        ctx = context.applicationContext
        try {
            if (file.exists()) {
                goals = Wire.docFromString(file.readText(Charsets.UTF_8)) ?: emptyList()
            }
        } catch (e: Exception) {
            goals = emptyList()
        }
    }

    private fun save() {
        try {
            val tmp = File(ctx.filesDir, "objectif-prix.json.tmp")
            tmp.writeText(Wire.docToString(goals, local = true), Charsets.UTF_8)
            tmp.renameTo(file)
        } catch (e: Exception) {
        }
    }

    private fun setGoals(list: List<Goal>) {
        goals = list
        save()
    }

    val visibleGoals: List<Goal> get() = goals.filter { !it.deleted }

    fun goal(id: String): Goal? = goals.firstOrNull { it.id == id && !it.deleted }

    fun add(goal: Goal) {
        setGoals(goals + goal)
        SyncService.scheduleSync()
    }

    /** `touch = false` pour les changements propres à cet appareil (dernière tentative, erreur…). */
    fun update(id: String, touch: Boolean = true, body: (Goal) -> Goal) {
        val index = goals.indexOfFirst { it.id == id }
        if (index < 0) return
        var g = body(goals[index])
        if (touch) g = g.touched()
        val list = goals.toMutableList()
        list[index] = g
        setGoals(list)
        if (touch) SyncService.scheduleSync()
    }

    fun delete(id: String) {
        update(id) { it.copy(deleted = true) }
        SavingRules.remove(id)
    }

    /** Remplace les objectifs par le résultat d'une fusion (sans relancer d'envoi). */
    fun applyRemote(merged: List<Goal>) = setGoals(merged)

    /** Retourne true si le lien a changé. */
    fun edit(id: String, name: String, url: String, monthly: Double, alert: Double, currency: String): Boolean {
        var urlChanged = false
        update(id) { g ->
            urlChanged = g.url != url
            var n = g.copy(name = name, url = url, monthly = monthly, alertBelow = alert, currency = currency)
            if (urlChanged) {
                n = n.copy(lastCheck = null, lastAttempt = null, lastError = null, alertedPrice = null)
                if (url.isNotEmpty()) n = n.copy(price = null, history = emptyList())
            }
            n
        }
        return urlChanged
    }

    // ───── Sauvegarde ─────

    fun backupText(): String = Wire.docToString(goals, local = false, pretty = true)

    /** Fusionne une sauvegarde avec les objectifs actuels. Retourne le nombre d'objectifs lus, ou null si illisible. */
    fun restore(text: String): Int? {
        val incoming = Wire.docFromString(text)
        if (incoming == null || incoming.isEmpty()) return null
        setGoals(SyncMerge.merge(goals, incoming))
        SyncService.scheduleSync()
        return incoming.count { !it.deleted }
    }

    fun sortedGoals(choice: String): List<Goal> {
        val list = visibleGoals
        return when (choice) {
            "progress" -> list.sortedByDescending { it.progress }
            "remaining" -> list.sortedBy { it.remaining ?: Double.MAX_VALUE }
            "price" -> list.sortedBy { it.price ?: Double.MAX_VALUE }
            "name" -> list.sortedBy { it.displayName.lowercase() }
            else -> list
        }
    }

    // ───── Argent ─────

    /** sign = +1 pour ajouter, -1 pour retirer. Retourne false s'il n'y a rien à faire. */
    fun moveMoney(id: String, amount: Double, note: String, sign: Int): Boolean {
        val g = goal(id) ?: return false
        if (amount <= 0) return false
        val applied = if (sign < 0) minOf(amount, g.saved) else amount
        if (applied <= 0) return false
        update(id) { x ->
            val newSaved = maxOf(Math.round((x.saved + sign * applied) * 100.0) / 100.0, 0.0)
            var log = x.log + MoneyEntry(nowSec(), sign * applied, note)
            if (log.size > 200) log = log.drop(log.size - 200)
            x.copy(saved = newSaved, log = log)
        }
        return true
    }

    // ───── Prix ─────

    private fun sameDay(a: Long, b: Long): Boolean {
        val z = ZoneId.systemDefault()
        return Instant.ofEpochSecond(a).atZone(z).toLocalDate() == Instant.ofEpochSecond(b).atZone(z).toLocalDate()
    }

    fun recordPrice(id: String, price: Double, notify: Boolean = true) {
        val current = goal(id) ?: return
        val old = current.price
        val rounded = Math.round(price * 100.0) / 100.0
        val messages = ArrayList<String>()

        update(id) { x ->
            var hist = x.history
            val last = hist.lastOrNull()
            hist = if (last != null && sameDay(last.t, nowSec())) {
                hist.dropLast(1) + PricePoint(last.t, rounded)
            } else {
                hist + PricePoint(nowSec(), rounded)
            }
            if (hist.size > 365) hist = hist.drop(hist.size - 365)
            var alerted = x.alertedPrice
            if (old != null && rounded < old - 0.004) {
                messages.add(L.f("notif.drop", x.money(old), x.money(rounded)))
            }
            if (x.alertBelow > 0) {
                if (rounded <= x.alertBelow && x.alertedPrice != rounded) {
                    messages.add(L.f("notif.below", x.money(x.alertBelow)))
                    alerted = rounded
                } else if (rounded > x.alertBelow) {
                    alerted = null
                }
            }
            x.copy(price = rounded, lastCheck = nowSec(), lastError = null, history = hist, alertedPrice = alerted)
        }

        if (notify && messages.isNotEmpty()) {
            Notifier.sendPrice(current.displayName, messages.joinToString(" · "))
        }
    }

    /** Relève le prix. Retourne un message d'erreur, ou null si tout s'est bien passé. */
    suspend fun refresh(id: String, manual: Boolean): String? {
        val g = goal(id) ?: return null
        if (g.url.isEmpty() || fetching.contains(id)) return null
        fetching = fetching + id
        try {
            update(id, touch = false) { it.copy(lastAttempt = nowSec()) }
            val result = PriceFetcher.fetch(ctx, g.url)
            val current = goal(id)
            val firstReading = current?.price == null && (current?.history?.isEmpty() ?: true)
            val found = result.currency
            if (found != null) {
                if (firstReading) {
                    update(id) { it.copy(currency = found) }
                } else if (result.explicit && found != (current?.cur ?: found)) {
                    val message = L.f("err.currency_mismatch", found, current?.cur ?: "")
                    update(id, touch = false) { it.copy(lastError = message) }
                    return message
                }
            }
            update(id) { x ->
                var n = x
                if (n.name.isEmpty() && result.title != null) n = n.copy(name = result.title.take(60))
                if (result.image != null) n = n.copy(imageUrl = result.image)
                n
            }
            recordPrice(id, result.price)
            return null
        } catch (e: Exception) {
            val message = e.message ?: L.t("err.network")
            update(id, touch = false) { it.copy(lastError = message) }
            return message
        } finally {
            fetching = fetching - id
        }
    }

    private fun isDue(g: Goal): Boolean {
        val now = nowSec()
        val attempt = g.lastAttempt
        if (attempt != null && attempt > (g.lastCheck ?: 0L) && now - attempt < retryAfterFailure) return false
        val last = g.lastCheck ?: return true
        val every = maxOf(Settings.refreshHours, 1) * 3600L
        return now - last >= every
    }

    suspend fun refreshDue() {
        for (g in visibleGoals) {
            if (g.url.isNotEmpty() && isDue(g)) {
                refresh(g.id, manual = false)
                delay(2000)
            }
        }
    }
}

// ───────────── Épargne régulière (propre à cet appareil) ─────────────

data class SavingRule(val mode: String = "off", val amount: Double = 0.0, val day: Int = 1, val lastAuto: String = "")

object SavingRules {
    private val prefs get() = Store.ctx.getSharedPreferences("saving", Context.MODE_PRIVATE)
    var rules by mutableStateOf<Map<String, SavingRule>>(emptyMap())
        private set

    fun init() {
        val text = prefs.getString("rules", null) ?: return
        try {
            val o = JSONObject(text)
            val map = HashMap<String, SavingRule>()
            for (key in o.keys()) {
                val r = o.getJSONObject(key)
                map[key] = SavingRule(r.optString("mode", "off"), r.optDouble("amount", 0.0), r.optInt("day", 1), r.optString("lastAuto", ""))
            }
            rules = map
        } catch (e: Exception) {
        }
    }

    private fun persist() {
        val o = JSONObject()
        for ((k, r) in rules) {
            o.put(k, JSONObject().put("mode", r.mode).put("amount", r.amount).put("day", r.day).put("lastAuto", r.lastAuto))
        }
        prefs.edit().putString("rules", o.toString()).apply()
    }

    fun rule(id: String): SavingRule = rules[id] ?: SavingRule()

    fun set(rule: SavingRule, id: String) {
        var updated = rule
        val old = rules[id]
        if (updated.mode == "auto") {
            val changed = old?.mode != "auto" || old?.day != updated.day
            updated = if (changed || (old?.lastAuto ?: "").isEmpty()) {
                // pas de rattrapage : on part du dernier passage prévu
                updated.copy(lastAuto = monthKey(lastScheduled(updated.day, LocalDateTime.now())))
            } else {
                updated.copy(lastAuto = old?.lastAuto ?: "")
            }
        }
        val map = rules.toMutableMap()
        if (updated.mode == "off") map.remove(id) else map[id] = updated
        rules = map
        persist()
    }

    fun remove(id: String) {
        if (rules[id] == null) return
        val map = rules.toMutableMap()
        map.remove(id)
        rules = map
        persist()
    }

    fun monthKey(d: LocalDateTime): String = String.format("%04d-%02d", d.year, d.monthValue)

    fun parseKey(key: String): LocalDateTime? {
        val parts = key.split("-")
        if (parts.size != 2) return null
        val y = parts[0].toIntOrNull() ?: return null
        val m = parts[1].toIntOrNull() ?: return null
        return try {
            LocalDateTime.of(y, m, 1, 12, 0)
        } catch (e: Exception) {
            null
        }
    }

    fun lastScheduled(day: Int, now: LocalDateTime): LocalDateTime {
        val d = day.coerceIn(1, 28)
        val thisMonth = LocalDateTime.of(now.year, now.monthValue, d, 9, 0)
        return if (thisMonth <= now) thisMonth else thisMonth.minusMonths(1)
    }

    /** Ajoute l'épargne des mois écoulés depuis le dernier passage (12 mois maximum d'un coup). */
    fun applyAuto() {
        val now = LocalDateTime.now()
        var changed = false
        for (goal in Store.visibleGoals) {
            var current = rule(goal.id)
            if (current.mode != "auto" || current.amount <= 0) continue
            var cursor = parseKey(current.lastAuto)
            if (cursor == null) {
                current = current.copy(lastAuto = monthKey(lastScheduled(current.day, now)))
                rules = rules + (goal.id to current)
                changed = true
                continue
            }
            var applied = 0
            while (applied < 12) {
                val next = cursor!!.plusMonths(1)
                val whenDue = LocalDateTime.of(next.year, next.monthValue, current.day.coerceIn(1, 28), 9, 0)
                if (whenDue > now) break
                Store.moveMoney(goal.id, current.amount, L.t("save.auto_note"), 1)
                cursor = next
                current = current.copy(lastAuto = monthKey(next))
                applied++
            }
            if (applied > 0) {
                rules = rules + (goal.id to current)
                changed = true
            }
        }
        if (changed) persist()
    }
}

// ───────────── Notifications ─────────────

object Notifier {
    private const val CH_PRICE = "prices"
    private const val CH_SAVE = "reminders"
    private var counter = 1000

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(CH_PRICE, L.t("set.notifications"), NotificationManager.IMPORTANCE_DEFAULT))
        nm.createNotificationChannel(NotificationChannel(CH_SAVE, L.t("save.section"), NotificationManager.IMPORTANCE_DEFAULT))
    }

    fun hasPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    fun sendPrice(title: String, body: String) {
        if (!Settings.notifications) return
        val context = Store.ctx
        if (!hasPermission(context)) return
        createChannels(context)
        val n = NotificationCompat.Builder(context, CH_PRICE)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openApp(context))
            .build()
        try {
            NotificationManagerCompat.from(context).notify(counter++, n)
        } catch (e: SecurityException) {
        }
    }

    fun sendReminder(goalId: String, name: String, amount: Double, amountText: String) {
        val context = Store.ctx
        if (!hasPermission(context)) return
        createChannels(context)
        val body = if (amount > 0) L.f("rem.body", amountText, name) else L.f("rem.body_generic", name)
        val builder = NotificationCompat.Builder(context, CH_SAVE)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(L.t("app.name"))
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openApp(context))
        val notifId = counter++
        if (amount > 0) {
            val intent = Intent(context, AddReceiver::class.java)
                .putExtra("goal", goalId)
                .putExtra("amount", amount)
                .putExtra("notif", notifId)
            val pending = PendingIntent.getBroadcast(
                context, notifId, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            builder.addAction(0, L.t("rem.add_action"), pending)
        }
        try {
            NotificationManagerCompat.from(context).notify(notifId, builder.build())
        } catch (e: SecurityException) {
        }
    }
}

/** Bouton « Ajouter le montant » d'un rappel d'épargne. */
class AddReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("goal") ?: return
        val amount = intent.getDoubleExtra("amount", 0.0)
        val notifId = intent.getIntExtra("notif", -1)
        if (amount > 0) Store.moveMoney(id, amount, L.t("rem.note"), 1)
        if (notifId >= 0) NotificationManagerCompat.from(context).cancel(notifId)
    }
}

object Reminders {
    private val prefs get() = Store.ctx.getSharedPreferences("reminders", Context.MODE_PRIVATE)

    /** Envoie les rappels du jour (appelé régulièrement par le travail de fond et à l'ouverture). */
    fun check() {
        if (!Settings.notifications) return
        val now = LocalDateTime.now()
        if (now.hour < 10) return
        val today = now.toLocalDate()
        for (goal in Store.visibleGoals) {
            val rule = SavingRules.rule(goal.id)
            val due = when (rule.mode) {
                "weekly" -> today.dayOfWeek == DayOfWeek.SUNDAY
                "monthly" -> today.dayOfMonth == rule.day.coerceIn(1, 28)
                else -> false
            }
            if (!due) continue
            val key = "last." + goal.id
            if (prefs.getString(key, "") == today.toString()) continue
            prefs.edit().putString(key, today.toString()).apply()
            Notifier.sendReminder(goal.id, goal.displayName, rule.amount, goal.money(rule.amount))
        }
    }
}

// ───────────── Travail en arrière-plan ─────────────

class RefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        try {
            withContext(Dispatchers.Main) {
                SyncService.syncNow()
                SavingRules.applyAuto()
                if (Settings.refreshHours > 0) Store.refreshDue()
                Reminders.check()
                SyncService.syncNow()
            }
        } catch (e: Exception) {
            return Result.retry()
        }
        return Result.success()
    }

    companion object {
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<RefreshWorker>(3, TimeUnit.HOURS).build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork("refresh", ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}

// ───────────── Synchronisation GitHub (gist secret) ─────────────

class GistClient(private val token: String) {
    companion object {
        const val FILE_NAME = "objectif-prix.json"
        const val DESCRIPTION = "Objectif Prix (données synchronisées)"
        private const val BASE = "https://api.github.com"
    }

    private suspend fun call(method: String, path: String, body: String? = null): String = withContext(Dispatchers.IO) {
        val requestBody = body?.toRequestBody("application/json".toMediaType())
        val request = try {
            Request.Builder()
                .url(BASE + path)
                .method(method, requestBody)
                .header("Authorization", "Bearer $token")
                .header("Accept", "application/vnd.github+json")
                .header("X-GitHub-Api-Version", "2022-11-28")
                .header("User-Agent", "objectif-prix-android")
                .build()
        } catch (e: Exception) {
            throw FetchError(L.t("err.bad_address"))
        }
        try {
            PriceFetcher.http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    when (response.code) {
                        401 -> throw FetchError(L.t("sync.err.token"))
                        403 -> throw FetchError(L.t("sync.err.forbidden"))
                        404 -> throw FetchError(L.t("sync.err.notfound"))
                        else -> throw FetchError(L.f("sync.err.http", response.code.toString()))
                    }
                }
                response.body?.string() ?: ""
            }
        } catch (e: FetchError) {
            throw e
        } catch (e: Exception) {
            throw FetchError(L.t("err.network"))
        }
    }

    suspend fun whoami(): String {
        val text = call("GET", "/user")
        return try {
            JSONObject(text).getString("login")
        } catch (e: Exception) {
            throw FetchError(L.t("sync.err.unexpected"))
        }
    }

    /** Id du plus ancien gist « Objectif Prix » du compte, ou null s'il n'y en a pas encore. */
    suspend fun findGist(): String? {
        var bestId: String? = null
        var bestCreated = ""
        for (page in 1..5) {
            val text = call("GET", "/gists?per_page=100&page=$page")
            val items = try {
                JSONArray(text)
            } catch (e: Exception) {
                break
            }
            for (i in 0 until items.length()) {
                val item = items.optJSONObject(i) ?: continue
                val files = item.optJSONObject("files") ?: continue
                val description = item.optString("description", "")
                val id = item.optString("id", "")
                if (!files.has(FILE_NAME) || !description.startsWith("Objectif Prix") || id.isEmpty()) continue
                val created = item.optString("created_at", "")
                if (bestId == null || created < bestCreated) {
                    bestId = id
                    bestCreated = created
                }
            }
            if (items.length() < 100) break
        }
        return bestId
    }

    suspend fun create(goals: List<Goal>): String {
        val payload = JSONObject()
            .put("description", DESCRIPTION)
            .put("public", false)
            .put("files", JSONObject().put(FILE_NAME, JSONObject().put("content", Wire.docToString(goals, local = false))))
        val text = call("POST", "/gists", payload.toString())
        return try {
            JSONObject(text).getString("id")
        } catch (e: Exception) {
            throw FetchError(L.t("sync.err.unexpected"))
        }
    }

    suspend fun read(id: String): List<Goal> {
        val text = call("GET", "/gists/$id")
        val file = try {
            JSONObject(text).getJSONObject("files").getJSONObject(FILE_NAME)
        } catch (e: Exception) {
            throw FetchError(L.t("sync.err.nofile"))
        }
        var content = file.optString("content", "")
        val raw = file.optString("raw_url", "")
        if (file.optBoolean("truncated", false) && raw.startsWith("https://gist.githubusercontent.com/")) {
            content = withContext(Dispatchers.IO) {
                try {
                    PriceFetcher.http.newCall(Request.Builder().url(raw).build()).execute().use { it.body?.string() ?: "" }
                } catch (e: Exception) {
                    throw FetchError(L.t("err.network"))
                }
            }
        }
        if (content.isBlank()) return emptyList()
        return Wire.docFromString(content) ?: throw FetchError(L.t("sync.err.unreadable"))
    }

    suspend fun write(id: String, goals: List<Goal>) {
        val payload = JSONObject()
            .put("files", JSONObject().put(FILE_NAME, JSONObject().put("content", Wire.docToString(goals, local = false))))
        call("PATCH", "/gists/$id", payload.toString())
    }
}

object SyncService {
    var connected by mutableStateOf(false)
        private set
    var login by mutableStateOf<String?>(null)
        private set
    var status by mutableStateOf("")
        private set
    var isError by mutableStateOf(false)
        private set
    var isSyncing by mutableStateOf(false)
        private set

    private var token: String? = null
    private var gistId: String? = null
    private var again = false
    private var pending: Job? = null
    private val prefs get() = Store.ctx.getSharedPreferences("sync", Context.MODE_PRIVATE)

    fun init() {
        token = prefs.getString("token", null)
        gistId = prefs.getString("gist", null)
        login = prefs.getString("login", null)
        connected = token != null && gistId != null
    }

    /** Retourne un message d'erreur, ou null si la connexion a réussi. */
    suspend fun connect(newToken: String): String? {
        val trimmed = newToken.trim()
        if (trimmed.isEmpty()) return L.t("sync.paste_token")
        val client = GistClient(trimmed)
        try {
            val name = client.whoami()
            var id = client.findGist()
            if (id == null) id = client.create(Store.goals)
            prefs.edit().putString("token", trimmed).putString("gist", id).putString("login", name).apply()
            token = trimmed
            gistId = id
            login = name
            connected = true
            status = L.t("sync.connected_status")
            isError = false
        } catch (e: Exception) {
            return e.message ?: L.t("err.network")
        }
        syncNow()
        return null
    }

    fun disconnect() {
        pending?.cancel()
        prefs.edit().clear().apply()
        token = null
        gistId = null
        login = null
        connected = false
        status = ""
        isError = false
    }

    /** À appeler après une modification : envoie les changements quelques secondes plus tard. */
    fun scheduleSync(afterSeconds: Long = 4) {
        if (!connected) return
        pending?.cancel()
        pending = Store.scope.launch {
            delay(afterSeconds * 1000)
            syncNow()
        }
    }

    suspend fun syncNow() {
        val t = token ?: return
        val id = gistId ?: return
        if (isSyncing) {
            again = true
            return
        }
        isSyncing = true
        isError = false
        status = L.t("sync.syncing")
        val client = GistClient(t)
        try {
            val remote = client.read(id)
            val merged = SyncMerge.merge(Store.goals, remote)
            if (SyncMerge.differs(merged, Store.goals)) Store.applyRemote(merged)
            if (SyncMerge.needsPush(merged, remote)) client.write(id, merged)
            status = L.f("sync.synced_at", Fmt.clock(nowSec()))
        } catch (e: Exception) {
            isError = true
            status = e.message ?: L.t("err.network")
        }
        isSyncing = false
        if (again) {
            again = false
            scheduleSync(1)
        }
    }
}
