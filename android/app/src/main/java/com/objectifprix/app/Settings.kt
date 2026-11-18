package com.objectifprix.app

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color

class Palette(
    val bg: Long, val panel: Long, val panel2: Long, val input: Long, val border: Long,
    val text: Long, val muted: Long, val accent: Long, val gold: Long, val bad: Long,
    val onAccent: Long, val isLight: Boolean
)

fun c(hex: Long): Color = Color(0xFF000000L or hex)

object Themes {
    val ids = listOf("graphite", "ink", "sage", "clay", "amoled", "paper", "mist")

    fun palette(id: String): Palette = when (id) {
        "ink" -> Palette(0x0F1218, 0x161A22, 0x1F2430, 0x12161D, 0x2A303D, 0xE9EBF0, 0x848B9A, 0x7FA8D6, 0xD2B06A, 0xDD6F6F, 0x0B1522, false)
        "sage" -> Palette(0x121512, 0x191D19, 0x232923, 0x151815, 0x2D342D, 0xECEFE8, 0x8A9487, 0x9DB88A, 0xCDB46A, 0xDA7468, 0x121A0F, false)
        "clay" -> Palette(0x171210, 0x1F1815, 0x2A211D, 0x1B1512, 0x372C26, 0xF3ECE6, 0x9A8B80, 0xD4825A, 0xD9A441, 0xD9645A, 0x2A1208, false)
        "amoled" -> Palette(0x000000, 0x0B0B0B, 0x171717, 0x0B0B0B, 0x262626, 0xFFFFFF, 0x8A8A8A, 0xD9A441, 0xD9A441, 0xE0685A, 0x1A1405, false)
        "paper" -> Palette(0xF4F1EA, 0xFBFAF6, 0xECE8DE, 0xF0EDE4, 0xDDD8CB, 0x1F1D1A, 0x77726A, 0x2F6B4F, 0xA8741A, 0xB8402F, 0xFFFFFF, true)
        "mist" -> Palette(0xEEF1F3, 0xFAFBFC, 0xE3E8EB, 0xEAEEF0, 0xD3DADF, 0x16202A, 0x63717D, 0x1F6F8B, 0xA8741A, 0xB8402F, 0xFFFFFF, true)
        else -> Palette(0x141414, 0x1C1C1D, 0x262628, 0x181819, 0x303033, 0xF2F0EB, 0x8E8B85, 0xD9A441, 0xD9A441, 0xE0685A, 0x1A1405, false)
    }

    val accents = listOf(0xD9A441L, 0xD4825AL, 0xC9677AL, 0x9B7FD1L, 0x7FA8D6L, 0x4FB3A9L, 0x9DB88AL, 0x2F6B4FL)

    fun readableOn(hex: Long): Long {
        val r = ((hex shr 16) and 0xFF) / 255.0
        val g = ((hex shr 8) and 0xFF) / 255.0
        val b = (hex and 0xFF) / 255.0
        val lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return if (lum > 0.6) 0x0B1220 else 0xFFFFFF
    }
}

/** Réglages enregistrés sur cet appareil (non synchronisés). Chaque champ est observé par l'interface. */
object Settings {
    private var prefs: SharedPreferences? = null

    var language by mutableStateOf("auto")            // auto, fr, en, es, de
    var theme by mutableStateOf("graphite")
    var accent by mutableStateOf(-1L)                 // -1 = couleur du thème
    var font by mutableStateOf("editorial")           // editorial, standard, rounded, serif, mono
    var fontScale by mutableStateOf(1.0f)
    var compact by mutableStateOf(false)
    var defaultCurrency by mutableStateOf("EUR")
    var numberFormat by mutableStateOf("auto")        // auto, fr, en
    var dateFormat by mutableStateOf("auto")          // auto, dmy, mdy, ymd
    var refreshHours by mutableStateOf(24)            // 0 = manuel
    var notifications by mutableStateOf(true)
    var confirmDelete by mutableStateOf(true)
    var sort by mutableStateOf("added")
    var onboarded by mutableStateOf(false)

    // Pas enregistrés
    var tutorialShown by mutableStateOf(false)

    val palette: Palette get() = Themes.palette(theme)
    val accentColor: Long get() = if (accent >= 0) accent else palette.accent
    val onAccentColor: Long get() = if (accent >= 0) Themes.readableOn(accent) else palette.onAccent

    fun load(context: Context) {
        val p = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        prefs = p
        language = p.getString("language", "auto") ?: "auto"
        theme = p.getString("theme", "graphite") ?: "graphite"
        accent = p.getLong("accent", -1L)
        font = p.getString("font", "editorial") ?: "editorial"
        fontScale = p.getFloat("fontScale", 1.0f).coerceIn(0.85f, 1.4f)
        compact = p.getBoolean("compact", false)
        val cur = p.getString("currency", null)
        defaultCurrency = if (cur != null && cur in Currencies.all) cur else Currencies.guessFromLocale()
        numberFormat = p.getString("numfmt", "auto") ?: "auto"
        dateFormat = p.getString("datefmt", "auto") ?: "auto"
        refreshHours = p.getInt("refresh", 24)
        notifications = p.getBoolean("notifs", true)
        confirmDelete = p.getBoolean("confirmDelete", true)
        sort = p.getString("sort", "added") ?: "added"
        onboarded = p.getBoolean("onboarded", false)
        L.code = L.resolve(language)
    }

    /** Modifie un ou plusieurs réglages, puis enregistre. */
    fun edit(block: Settings.() -> Unit) {
        block(this)
        L.code = L.resolve(language)
        save()
    }

    private fun save() {
        val p = prefs ?: return
        p.edit()
            .putString("language", language)
            .putString("theme", theme)
            .putLong("accent", accent)
            .putString("font", font)
            .putFloat("fontScale", fontScale)
            .putBoolean("compact", compact)
            .putString("currency", defaultCurrency)
            .putString("numfmt", numberFormat)
            .putString("datefmt", dateFormat)
            .putInt("refresh", refreshHours)
            .putBoolean("notifs", notifications)
            .putBoolean("confirmDelete", confirmDelete)
            .putString("sort", sort)
            .putBoolean("onboarded", onboarded)
            .apply()
    }

    fun resetAll() {
        edit {
            language = "auto"
            theme = "graphite"
            accent = -1L
            font = "editorial"
            fontScale = 1.0f
            compact = false
            defaultCurrency = Currencies.guessFromLocale()
            numberFormat = "auto"
            dateFormat = "auto"
            refreshHours = 24
            notifications = true
            confirmDelete = true
            sort = "added"
        }
    }
}
