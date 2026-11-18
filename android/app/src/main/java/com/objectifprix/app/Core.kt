package com.objectifprix.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Currency
import java.util.Locale
import java.util.UUID

class FetchError(message: String) : Exception(message)

// ───────────── Traductions ─────────────

object L {
    private val tables = HashMap<String, Map<String, String>>()
    var code by mutableStateOf("fr")

    fun load(context: Context) {
        for (lang in listOf("fr", "en", "es", "de")) {
            try {
                val text = context.assets.open("strings_$lang.json").bufferedReader(Charsets.UTF_8).use { it.readText() }
                val json = JSONObject(text)
                val map = HashMap<String, String>()
                for (key in json.keys()) map[key] = json.getString(key)
                tables[lang] = map
            } catch (e: Exception) {
                tables[lang] = emptyMap()
            }
        }
    }

    fun resolve(choice: String): String {
        if (choice in listOf("fr", "en", "es", "de")) return choice
        val lang = Locale.getDefault().language.lowercase()
        return if (lang in listOf("fr", "en", "es", "de")) lang else "en"
    }

    fun t(key: String): String {
        return tables[code]?.get(key) ?: tables["fr"]?.get(key) ?: key
    }

    fun f(key: String, vararg args: String): String {
        var text = t(key)
        for ((i, a) in args.withIndex()) text = text.replace("{" + (i + 1) + "}", a)
        return text
    }

    val localeTag: String
        get() = when (code) {
            "fr" -> "fr-FR"
            "es" -> "es-ES"
            "de" -> "de-DE"
            else -> "en-US"
        }
}

// ───────────── Devises ─────────────

object Currencies {
    val all = listOf("EUR", "USD", "GBP", "CAD", "CHF", "AUD", "JPY", "SEK", "NOK", "DKK", "PLN", "CZK", "MXN", "BRL", "INR", "CNY")

    fun guessFromLocale(): String {
        return try {
            val code = Currency.getInstance(Locale.getDefault()).currencyCode
            if (code in all) code else "EUR"
        } catch (e: Exception) {
            "EUR"
        }
    }

    fun fromUnambiguousSymbol(text: String): String? {
        if (text.contains("€")) return "EUR"
        if (text.contains("£")) return "GBP"
        if (text.contains("₹")) return "INR"
        if (text.contains("zł")) return "PLN"
        if (text.contains("CHF")) return "CHF"
        return null
    }

    fun fromSymbol(text: String): String? {
        fromUnambiguousSymbol(text)?.let { return it }
        if (text.contains("$")) return "USD"
        return null
    }

    fun normalize(raw: String?): String? {
        if (raw == null) return null
        val code = raw.trim().uppercase()
        if (code.length != 3 || !code.all { it in 'A'..'Z' }) return null
        return code
    }

    fun symbolText(code: String): String = when (code) {
        "EUR" -> "€"
        "USD" -> "$"
        "GBP" -> "£"
        "JPY" -> "¥"
        "INR" -> "₹"
        else -> code
    }
}

// ───────────── Formats ─────────────

object Fmt {
    private fun numberLocale(): Locale = when (Settings.numberFormat) {
        "fr" -> Locale.forLanguageTag("fr-FR")
        "en" -> Locale.forLanguageTag("en-US")
        else -> Locale.forLanguageTag(L.localeTag)
    }

    fun money(value: Double, currency: String): String {
        return try {
            val f = NumberFormat.getCurrencyInstance(numberLocale())
            f.currency = Currency.getInstance(currency)
            f.format(value)
        } catch (e: Exception) {
            String.format(Locale.US, "%.2f %s", value, currency)
        }
    }

    private fun zone(): ZoneId = ZoneId.systemDefault()

    private fun fmt(pattern: String): DateTimeFormatter =
        DateTimeFormatter.ofPattern(pattern, Locale.forLanguageTag(L.localeTag))

    fun shortDate(sec: Long): String {
        val z = ZonedDateTime.ofInstant(Instant.ofEpochSecond(sec), zone())
        val p = when (Settings.dateFormat) {
            "dmy" -> "dd/MM"
            "mdy" -> "MM/dd"
            "ymd" -> "MM-dd"
            else -> if (L.code == "en") "MM/dd" else if (L.code == "de") "dd.MM." else "dd/MM"
        }
        return z.format(fmt(p))
    }

    fun fullDate(sec: Long): String {
        val z = ZonedDateTime.ofInstant(Instant.ofEpochSecond(sec), zone())
        val p = when (Settings.dateFormat) {
            "dmy" -> "dd/MM/yyyy"
            "mdy" -> "MM/dd/yyyy"
            "ymd" -> "yyyy-MM-dd"
            else -> if (L.code == "en") "MM/dd/yyyy" else if (L.code == "de") "dd.MM.yyyy" else "dd/MM/yyyy"
        }
        return z.format(fmt(p))
    }

    fun monthYear(sec: Long): String {
        val z = ZonedDateTime.ofInstant(Instant.ofEpochSecond(sec), zone())
        val s = z.format(fmt("LLLL yyyy"))
        return s.replaceFirstChar { it.uppercase() }
    }

    fun clock(sec: Long): String {
        val z = ZonedDateTime.ofInstant(Instant.ofEpochSecond(sec), zone())
        return z.format(fmt("HH:mm"))
    }

    fun dateTime(sec: Long): String = shortDate(sec) + " " + clock(sec)

    fun amount(raw: String): Double? = PriceFetcher.parseNumber(raw)

    /** Champ facultatif : vide = 0, invalide ou négatif = null. */
    fun optionalAmount(raw: String): Double? {
        val t = raw.trim()
        if (t.isEmpty()) return 0.0
        val v = PriceFetcher.parseNumber(t) ?: return null
        return if (v >= 0) v else null
    }

    fun plain(value: Double): String {
        return if (value == Math.rint(value)) value.toLong().toString() else value.toString().replace(".", ",")
    }
}

fun nowSec(): Long = System.currentTimeMillis() / 1000

// ───────────── Modèles ─────────────

data class PricePoint(val t: Long, val price: Double)
data class MoneyEntry(val t: Long, val amount: Double, val note: String)

enum class Trend { DOWN, UP, FLAT, NONE }

data class Goal(
    val id: String = UUID.randomUUID().toString().lowercase(),
    val name: String = "",
    val url: String = "",
    val price: Double? = null,
    val saved: Double = 0.0,
    val monthly: Double = 0.0,
    val alertBelow: Double = 0.0,
    val lastCheck: Long? = null,
    val lastAttempt: Long? = null,
    val lastError: String? = null,
    val alertedPrice: Double? = null,
    val history: List<PricePoint> = emptyList(),
    val log: List<MoneyEntry> = emptyList(),
    val imageUrl: String? = null,
    val currency: String? = null,
    val updatedAt: Long = nowSec(),
    val deleted: Boolean = false
) {
    val cur: String get() = currency ?: Settings.defaultCurrency
    fun money(v: Double): String = Fmt.money(v, cur)
    val displayName: String get() = if (name.isEmpty()) L.t("goal.unnamed") else name

    val host: String
        get() {
            if (url.isEmpty()) return L.t("goal.manual_price")
            return try {
                java.net.URI(url).host?.removePrefix("www.") ?: L.t("goal.link")
            } catch (e: Exception) {
                L.t("goal.link")
            }
        }

    val progress: Double
        get() {
            val p = price ?: return 0.0
            if (p <= 0) return 0.0
            return (saved / p).coerceIn(0.0, 1.0)
        }

    val remaining: Double? get() = price?.let { maxOf(it - saved, 0.0) }

    val sortedHistory: List<PricePoint> get() = history.sortedBy { it.t }

    /** Marque l'objectif comme modifié (toujours strictement plus récent que sa version précédente). */
    fun touched(): Goal {
        val now = nowSec()
        return copy(updatedAt = if (now > updatedAt) now else updatedAt + 1)
    }

    fun variationInfo(): Pair<String, Trend> {
        if (price == null) return Pair(L.t("var.none"), Trend.NONE)
        val h = sortedHistory
        if (h.size < 2) return Pair(L.t("var.first"), Trend.NONE)
        val diff = h[h.size - 1].price - h[h.size - 2].price
        if (Math.abs(diff) < 0.005) return Pair(L.t("var.stable"), Trend.FLAT)
        val since = Fmt.shortDate(h[h.size - 2].t)
        val arrow = if (diff < 0) "▼ " else "▲ "
        return Pair(arrow + L.f("var.since", money(Math.abs(diff)), since), if (diff < 0) Trend.DOWN else Trend.UP)
    }

    fun estimate(): Pair<String, String> {
        val rem = remaining ?: return Pair("—", L.t("est.unknown_price"))
        if (rem <= 0) return Pair(L.t("est.reached"), L.t("est.can_buy"))
        if (monthly <= 0) return Pair("—", L.t("est.set_monthly"))
        val months = rem / monthly
        val days = Math.round(months * 30.44)
        val target = nowSec() + days * 86400
        return Pair(Fmt.monthYear(target), L.f("est.months", Math.ceil(months).toInt().toString(), money(monthly)))
    }
}

// ───────────── Format commun avec l'iPhone et le PC ─────────────

object Iso {
    private val plain: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)

    fun string(sec: Long): String = plain.format(Instant.ofEpochSecond(sec))

    fun parse(text: String?): Long? {
        if (text.isNullOrBlank()) return null
        return try {
            Instant.parse(text).epochSecond
        } catch (e: Exception) {
            try {
                OffsetDateTime.parse(text).toEpochSecond()
            } catch (e2: Exception) {
                try {
                    java.time.LocalDateTime.parse(text).toEpochSecond(ZoneOffset.UTC)
                } catch (e3: Exception) {
                    null
                }
            }
        }
    }
}

object Wire {
    private fun JSONObject.optStr(key: String): String? =
        if (has(key) && !isNull(key)) optString(key) else null

    private fun JSONObject.optNum(key: String): Double? =
        if (has(key) && !isNull(key)) optDouble(key) else null

    /** `local = true` ajoute les infos propres à cet appareil (fichier local seulement). */
    fun goalToJson(g: Goal, local: Boolean): JSONObject {
        val o = JSONObject()
        o.put("id", g.id)
        o.put("name", g.name)
        o.put("url", g.url)
        if (g.price != null) o.put("price", g.price)
        o.put("saved", g.saved)
        o.put("monthly", g.monthly)
        o.put("alertBelow", g.alertBelow)
        if (g.lastCheck != null) o.put("lastCheck", Iso.string(g.lastCheck))
        val hist = JSONArray()
        for (p in g.sortedHistory) hist.put(JSONObject().put("t", Iso.string(p.t)).put("price", p.price))
        o.put("history", hist)
        val log = JSONArray()
        for (e in g.log) log.put(JSONObject().put("t", Iso.string(e.t)).put("amount", e.amount).put("note", e.note))
        o.put("log", log)
        if (g.currency != null) o.put("currency", g.currency)
        if (g.imageUrl != null) o.put("image", g.imageUrl)
        o.put("updatedAt", Iso.string(g.updatedAt))
        o.put("deleted", g.deleted)
        if (local) {
            if (g.lastAttempt != null) o.put("lastAttempt", Iso.string(g.lastAttempt))
            if (g.lastError != null) o.put("lastError", g.lastError)
            if (g.alertedPrice != null) o.put("alertedPrice", g.alertedPrice)
        }
        return o
    }

    fun goalFromJson(o: JSONObject): Goal? {
        val id = o.optStr("id")?.lowercase() ?: return null
        try {
            UUID.fromString(id)
        } catch (e: Exception) {
            return null
        }
        val history = ArrayList<PricePoint>()
        val ha = o.optJSONArray("history")
        if (ha != null) {
            for (i in 0 until ha.length()) {
                val p = ha.optJSONObject(i) ?: continue
                val t = Iso.parse(p.optStr("t")) ?: continue
                history.add(PricePoint(t, p.optDouble("price")))
            }
        }
        val log = ArrayList<MoneyEntry>()
        val la = o.optJSONArray("log")
        if (la != null) {
            for (i in 0 until la.length()) {
                val e = la.optJSONObject(i) ?: continue
                val t = Iso.parse(e.optStr("t")) ?: continue
                log.add(MoneyEntry(t, e.optDouble("amount"), e.optString("note", "")))
            }
        }
        return Goal(
            id = id,
            name = o.optString("name", ""),
            url = o.optString("url", ""),
            price = o.optNum("price"),
            saved = o.optDouble("saved", 0.0),
            monthly = o.optDouble("monthly", 0.0),
            alertBelow = o.optDouble("alertBelow", 0.0),
            lastCheck = Iso.parse(o.optStr("lastCheck")),
            lastAttempt = Iso.parse(o.optStr("lastAttempt")),
            lastError = o.optStr("lastError"),
            alertedPrice = o.optNum("alertedPrice"),
            history = history.sortedBy { it.t },
            log = log,
            imageUrl = o.optStr("image"),
            currency = Currencies.normalize(o.optStr("currency")) ?: "EUR",
            updatedAt = Iso.parse(o.optStr("updatedAt")) ?: 0L,
            deleted = o.optBoolean("deleted", false)
        )
    }

    fun docToString(goals: List<Goal>, local: Boolean, pretty: Boolean = false): String {
        val arr = JSONArray()
        for (g in goals) arr.put(goalToJson(g, local))
        val doc = JSONObject()
        doc.put("app", "objectif-prix")
        doc.put("version", 1)
        doc.put("goals", arr)
        return if (pretty) doc.toString(2) else doc.toString()
    }

    /** Décode un document en ignorant les éléments abîmés. Retourne null si le texte est illisible. */
    fun docFromString(text: String): List<Goal>? {
        val t = text.trim()
        if (t.isEmpty()) return emptyList()
        return try {
            val doc = JSONObject(t)
            val arr = doc.optJSONArray("goals") ?: return emptyList()
            val out = ArrayList<Goal>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val g = try { goalFromJson(o) } catch (e: Exception) { null }
                if (g != null) out.add(g)
            }
            out
        } catch (e: Exception) {
            null
        }
    }
}

// ───────────── Fusion : pour chaque objectif, la version modifiée en dernier gagne ─────────────

object SyncMerge {
    fun merge(local: List<Goal>, remote: List<Goal>): List<Goal> {
        val byId = LinkedHashMap<String, Goal>()
        for (g in local) byId[g.id] = g
        for (r in remote) {
            val l = byId[r.id]
            if (l == null) {
                byId[r.id] = r
            } else if (r.updatedAt > l.updatedAt) {
                byId[r.id] = r.copy(lastAttempt = l.lastAttempt, lastError = l.lastError, alertedPrice = l.alertedPrice)
            }
        }
        val cutoff = nowSec() - 60L * 86400
        return byId.values.filter { !(it.deleted && it.updatedAt < cutoff) }
    }

    private fun stamps(goals: List<Goal>): Map<String, Long> {
        val m = HashMap<String, Long>()
        for (g in goals) m[g.id] = g.updatedAt
        return m
    }

    fun differs(a: List<Goal>, b: List<Goal>): Boolean = stamps(a) != stamps(b)

    fun needsPush(merged: List<Goal>, remote: List<Goal>): Boolean {
        val known = stamps(remote)
        return merged.any { known[it.id] != it.updatedAt }
    }
}
