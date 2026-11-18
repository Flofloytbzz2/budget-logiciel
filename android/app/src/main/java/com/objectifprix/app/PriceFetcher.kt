package com.objectifprix.app

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.net.URI
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern
import kotlin.coroutines.resume

data class PriceResult(
    val price: Double?,
    val title: String?,
    val currency: String?,
    val explicit: Boolean,
    val image: String? = null
)

data class FetchedPrice(
    val price: Double,
    val title: String?,
    val currency: String?,
    val explicit: Boolean,
    val image: String? = null
)

/** Lit le prix d'un produit sur la page web de n'importe quelle boutique. */
object PriceFetcher {

    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private const val UA =
        "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

    suspend fun fetch(context: Context, urlString: String): FetchedPrice {
        val url = cleanURL(urlString) ?: throw FetchError(L.t("fetch.invalid_link"))

        // 1) Lecture directe de la page (rapide)
        var firstError: FetchError? = null
        try {
            val page = download(url)
            val found = extract(page)
            if (found.price != null) {
                return FetchedPrice(found.price, found.title, found.currency, found.explicit, resolveImage(found.image, url))
            }
            firstError = FetchError(describeFailure(page))
        } catch (e: FetchError) {
            firstError = e
        } catch (e: Exception) {
            firstError = FetchError(L.t("err.network"))
        }

        // 2) Comme un vrai navigateur (WebView) : passe souvent là où la lecture directe est bloquée
        try {
            val page = loadInWebView(context, url) { extract(it).price != null }
            val found = extract(page)
            if (found.price != null) {
                return FetchedPrice(found.price, found.title, found.currency, found.explicit, resolveImage(found.image, url))
            }
            if (page.isEmpty()) throw firstError ?: FetchError(L.t("fetch.page_failed"))
            throw FetchError(describeFailure(page))
        } catch (e: FetchError) {
            throw e
        } catch (e: Exception) {
            throw firstError ?: FetchError(L.t("fetch.read_failed"))
        }
    }

    // ───────────── Lien ─────────────

    /** Retrouve l'adresse dans un texte collé (« Regarde ça : https://… »), enlève les caractères invisibles. */
    fun cleanURL(raw: String): String? {
        var text = raw
        for (invisible in listOf("​", "‌", "‍", "⁠", "﻿")) text = text.replace(invisible, "")
        text = text.trim()
        val m = Pattern.compile("https?://[^\\s<>\"']+", Pattern.CASE_INSENSITIVE).matcher(text)
        if (m.find()) text = m.group()
        val lower = text.lowercase()
        if (!(lower.startsWith("http://") || lower.startsWith("https://"))) return null
        return try {
            URI(text)
            text
        } catch (e: Exception) {
            try {
                val u = java.net.URL(text)
                URI(u.protocol, u.userInfo, u.host, u.port, u.path, u.query, u.ref).toString()
            } catch (e2: Exception) {
                null
            }
        }
    }

    // ───────────── Téléchargement direct ─────────────

    private fun acceptLanguage(): String = when (L.code) {
        "fr" -> "fr-FR,fr;q=0.9,en;q=0.5"
        "es" -> "es-ES,es;q=0.9,en;q=0.5"
        "de" -> "de-DE,de;q=0.9,en;q=0.5"
        else -> "en-US,en;q=0.9"
    }

    private suspend fun download(url: String): String = withContext(Dispatchers.IO) {
        val request = try {
            Request.Builder()
                .url(url)
                .header("User-Agent", UA)
                .header("Accept-Language", acceptLanguage())
                .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                .build()
        } catch (e: Exception) {
            throw FetchError(L.t("fetch.invalid_link"))
        }
        try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    if (response.code == 403 || response.code == 429) {
                        throw FetchError(L.f("fetch.refused", response.code.toString()))
                    }
                    throw FetchError(L.f("fetch.http", response.code.toString()))
                }
                val body = response.body ?: return@use ""
                val bytes = body.source().let { src ->
                    src.request(6_000_000)
                    src.buffer.snapshot().toByteArray()
                }
                String(bytes, Charsets.UTF_8)
            }
        } catch (e: FetchError) {
            throw e
        } catch (e: Exception) {
            throw FetchError(L.t("err.network"))
        }
    }

    // ───────────── WebView de secours ─────────────

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun loadInWebView(context: Context, url: String, accept: (String) -> Boolean): String =
        withContext(Dispatchers.Main) {
            suspendCancellableCoroutine<String> { cont ->
                val handler = Handler(Looper.getMainLooper())
                val view = WebView(context.applicationContext)
                view.settings.javaScriptEnabled = true
                view.settings.domStorageEnabled = true
                view.settings.userAgentString = UA
                var finished = false
                var lastHtml = ""
                val started = System.currentTimeMillis()

                fun finish(result: String) {
                    if (finished) return
                    finished = true
                    handler.removeCallbacksAndMessages(null)
                    try {
                        view.stopLoading()
                        view.destroy()
                    } catch (e: Exception) {
                    }
                    if (cont.isActive) cont.resume(result)
                }

                view.webViewClient = object : WebViewClient() {
                    override fun onReceivedError(v: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                        // les erreurs de ressources secondaires sont normales ; on continue d'attendre la page
                    }
                }

                fun poll() {
                    if (finished) return
                    view.evaluateJavascript("(function(){return document.documentElement.outerHTML;})()") { raw ->
                        if (finished) return@evaluateJavascript
                        val html = try {
                            (JSONTokener(raw ?: "null").nextValue() as? String) ?: ""
                        } catch (e: Exception) {
                            ""
                        }
                        if (html.isNotEmpty()) {
                            lastHtml = html
                            if (accept(html)) {
                                finish(html)
                                return@evaluateJavascript
                            }
                        }
                        if (System.currentTimeMillis() - started > 25_000) {
                            finish(lastHtml)
                        } else {
                            handler.postDelayed({ poll() }, 1500)
                        }
                    }
                }

                cont.invokeOnCancellation { handler.post { finish("") } }
                view.loadUrl(url)
                handler.postDelayed({ poll() }, 2000)
            }
        }

    /** Message d'erreur qui dit ce que la page contenait. */
    fun describeFailure(page: String): String {
        val lower = page.lowercase()
        if (page.length < 60_000 &&
            (lower.contains("captcha") || lower.contains("datadome") || lower.contains("access denied") ||
                lower.contains("are you a robot") || lower.contains("unusual traffic"))
        ) {
            return L.t("fetch.robot")
        }
        var details = (page.length / 1000).toString() + " KB"
        val title = extract(page).title
        if (!title.isNullOrEmpty()) details = "« " + title.take(50) + " », " + details
        return L.f("fetch.notfound", details)
    }

    // ───────────── Extraction ─────────────

    private const val NUMBER = "([0-9]+(?:[ \\x{00A0}\\x{202F}.,][0-9]+)*)"
    private const val CURRENCY_MARKS = "(?:€|\\$|£|EUR|USD|GBP|CHF)"

    fun extract(page: String): PriceResult {
        val core = extractCore(page)
        return core.copy(image = findImage(page))
    }

    fun findImage(page: String): String? {
        val patterns = listOf(
            "<meta[^>]+property=[\"']og:image(?::secure_url)?[\"'][^>]*?content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*?property=[\"']og:image(?::secure_url)?[\"']",
            "<meta[^>]+name=[\"']twitter:image(?::src)?[\"'][^>]*?content=[\"']([^\"']+)[\"']",
            "\"image\"\\s*:\\s*\"([^\"]+)\"",
            "\"image\"\\s*:\\s*\\[\\s*\"([^\"]+)\"",
            "\"image\"\\s*:\\s*\\{[^}]*?\"url\"\\s*:\\s*\"([^\"]+)\""
        )
        for (pattern in patterns) {
            for (m in matches(pattern, page)) {
                val raw = unescape(m[1]).replace("\\/", "/")
                if (raw.startsWith("http") || raw.startsWith("//") || raw.startsWith("/")) return raw
            }
        }
        return null
    }

    fun resolveImage(raw: String?, base: String): String? {
        if (raw.isNullOrEmpty()) return null
        return try {
            var text = URI(base).resolve(raw.replace(" ", "%20")).toString()
            if (text.startsWith("http://")) text = "https://" + text.removePrefix("http://")
            text
        } catch (e: Exception) {
            null
        }
    }

    private fun extractCore(page: String): PriceResult {
        var title: String? = null
        val ogTitle = matches("<meta[^>]+property=\"og:title\"[^>]+content=\"([^\"]+)\"", page).firstOrNull()
        if (ogTitle != null) {
            title = unescape(ogTitle[1])
        } else {
            val t = matches("<title[^>]*>(.*?)</title>", page).firstOrNull()
            if (t != null) title = unescape(t[1])
        }

        // 1) Données structurées JSON-LD (le plus fiable)
        val blocks = matches("<script[^>]+type=[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>", page)
        for (block in blocks) {
            val node: Any = try {
                JSONTokener(block[1].trim()).nextValue()
            } catch (e: Exception) {
                continue
            }
            val offers = ArrayList<Pair<Double, String?>>()
            offersIn(node, offers)
            val first = offers.firstOrNull { it.first > 0 }
            if (first != null) return finish(first.first, title, first.second, null, page)
        }

        // 1 bis) JSON-LD que le décodeur n'a pas lu : on cherche quand même le prix dedans
        for (block in blocks) {
            val price = firstPrice("\"(?:lowPrice|price)\"\\s*:\\s*\"?$NUMBER", block[1])
            if (price != null) return finish(price, title, null, null, page)
        }

        // 2) Balises meta (dans les deux ordres d'attributs)
        val names = "(?:product:price:amount|og:price:amount|price|lowPrice)"
        val metaA = "<meta[^>]+(?:property|itemprop|name)=[\"']$names[\"'][^>]*?content=[\"']([^\"']+)[\"']"
        val metaB = "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*?(?:property|itemprop|name)=[\"']$names[\"']"
        for (pattern in listOf(metaA, metaB)) {
            val price = firstPrice(pattern, page)
            if (price != null) return finish(price, title, null, null, page)
        }

        // 3) Prix présent dans l'état JSON de la page
        val state = "\"\\\\?(?:lowPrice|lowestPrice|minPrice|priceAmount|currentPrice|salePrice|finalPrice)\\\\?\"\\s*:\\s*\\\\?\"?$NUMBER"
        val statePrice = firstPrice(state, page)
        if (statePrice != null) return finish(statePrice, title, null, null, page)

        // 4) Amazon et boutiques voisines : le prix est dans un texte caché pour les lecteurs d'écran
        for (m in matches("class=\"a-offscreen\"[^>]*>\\s*([^<]{1,40}?)\\s*<", page)) {
            val num = firstNumber(m[1]) ?: continue
            val price = parsePrice(num)
            if (price != null && price > 0) return finish(price, title, null, m[1], page)
        }

        // 5) Texte « à partir de 299,00 € », « from $299 », « ab 299 € »
        val words = "\\b(?:à partir de|dès|ab|ab nur|from|starting at|desde|a partir de)\\b"
        val before = "$words\\s*(?:<[^>]+>\\s*)*[€$£]\\s*$NUMBER"
        val after = "$words\\s*(?:<[^>]+>\\s*)*$NUMBER\\s*(?:<[^>]+>\\s*)*$CURRENCY_MARKS"
        for (pattern in listOf(before, after)) {
            for (m in matches(pattern, page)) {
                val price = parsePrice(m[1])
                if (price != null && price > 0) return finish(price, title, null, m[0], page)
            }
        }

        val pc = pageCurrency(page)
        return PriceResult(null, title, pc, pc != null)
    }

    private fun finish(price: Double, title: String?, currency: String?, snippet: String?, page: String): PriceResult {
        Currencies.normalize(currency)?.let { return PriceResult(price, title, it, true) }
        pageCurrency(page)?.let { return PriceResult(price, title, it, true) }
        if (snippet != null) {
            Currencies.fromUnambiguousSymbol(snippet)?.let { return PriceResult(price, title, it, true) }
            Currencies.fromSymbol(snippet)?.let { return PriceResult(price, title, it, false) }
        }
        return PriceResult(price, title, null, false)
    }

    /** Devise annoncée par la page (balises meta ou données structurées). */
    private fun pageCurrency(page: String): String? {
        val metaNames = "(?:product:price:currency|og:price:currency|priceCurrency)"
        val patterns = listOf(
            "<meta[^>]+(?:property|itemprop|name)=[\"']$metaNames[\"'][^>]*?content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*?(?:property|itemprop|name)=[\"']$metaNames[\"']",
            "\\\\?\"priceCurrency\\\\?\"\\s*:\\s*\\\\?\"([A-Za-z]{3})",
            "\\\\?\"currencyCode\\\\?\"\\s*:\\s*\\\\?\"([A-Za-z]{3})",
            "itemprop=[\"']priceCurrency[\"'][^>]*content=[\"']([A-Za-z]{3})[\"']"
        )
        for (pattern in patterns) {
            for (m in matches(pattern, page)) {
                Currencies.normalize(m[1])?.let { return it }
            }
        }
        return null
    }

    private fun firstPrice(pattern: String, text: String): Double? {
        for (m in matches(pattern, text)) {
            val v = parsePrice(m[1])
            if (v != null && v > 0) return v
        }
        return null
    }

    private fun firstNumber(text: String): String? = matches(NUMBER, text).firstOrNull()?.get(1)

    private fun offersIn(node: Any?, out: MutableList<Pair<Double, String?>>) {
        when (node) {
            is JSONObject -> {
                val cur = Currencies.normalize(if (node.has("priceCurrency")) node.optString("priceCurrency") else null)
                for (key in listOf("lowPrice", "price")) {
                    if (!node.has(key) || node.isNull(key)) continue
                    val value = node.get(key)
                    if (value is Number) {
                        out.add(Pair(value.toDouble(), cur))
                    } else if (value is String) {
                        val n = parsePrice(value)
                        if (n != null) out.add(Pair(n, cur))
                    }
                }
                val keys = node.keys()
                while (keys.hasNext()) {
                    offersIn(node.opt(keys.next()), out)
                }
            }
            is JSONArray -> {
                for (i in 0 until node.length()) offersIn(node.opt(i), out)
            }
            else -> {}
        }
    }

    /** Convertit "1 299,99", "1299.99", "1.299,99" ou "1,299.99" en Double (saisie de l'utilisateur). */
    fun parseNumber(raw: String): Double? {
        var t = raw.trim()
        for (junk in listOf(" ", " ", " ", "€", "EUR")) t = t.replace(junk, "")
        if (t.contains(",") && t.contains(".")) {
            t = if (t.lastIndexOf(',') > t.lastIndexOf('.')) {
                t.replace(".", "").replace(",", ".")
            } else {
                t.replace(",", "")
            }
        } else if (t.contains(",")) {
            t = t.replace(",", ".")
        }
        return t.toDoubleOrNull()
    }

    /** Comme parseNumber, mais pour les prix lus sur une page : « 1,299 » est mille deux cent quatre-vingt-dix-neuf. */
    fun parsePrice(raw: String): Double? {
        val t = raw.trim()
        if (t.contains(",") && !t.contains(".")) {
            val parts = t.split(",")
            val last = parts.last()
            val first = parts.first()
            if (last.length == 3 && first != "0" && first.isNotEmpty()) {
                return parts.joinToString("").toDoubleOrNull()
            }
        }
        return parseNumber(t)
    }

    // ───────────── Utilitaires ─────────────

    private fun matches(pattern: String, text: String): List<List<String>> {
        val regex = try {
            Pattern.compile(pattern, Pattern.CASE_INSENSITIVE or Pattern.DOTALL)
        } catch (e: Exception) {
            return emptyList()
        }
        val m = regex.matcher(text)
        val out = ArrayList<List<String>>()
        while (m.find()) {
            val groups = ArrayList<String>()
            for (i in 0..m.groupCount()) groups.add(m.group(i) ?: "")
            out.add(groups)
        }
        return out
    }

    private fun unescape(s: String): String =
        s.replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&#x27;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .trim()
}
