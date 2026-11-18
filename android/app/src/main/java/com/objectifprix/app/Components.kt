package com.objectifprix.app

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.core.view.WindowCompat
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import coil.compose.AsyncImage

// ───────────── Couleurs et polices lues dans les réglages ─────────────

object Th {
    val bg: Color get() = c(Settings.palette.bg)
    val panel: Color get() = c(Settings.palette.panel)
    val panel2: Color get() = c(Settings.palette.panel2)
    val input: Color get() = c(Settings.palette.input)
    val border: Color get() = c(Settings.palette.border)
    val text: Color get() = c(Settings.palette.text)
    val muted: Color get() = c(Settings.palette.muted)
    val accent: Color get() = c(Settings.accentColor)
    val onAccent: Color get() = c(Settings.onAccentColor)
    val gold: Color get() = c(Settings.palette.gold)
    val bad: Color get() = c(Settings.palette.bad)

    val pad get() = if (Settings.compact) 12.dp else 16.dp
    val gap get() = if (Settings.compact) 8.dp else 12.dp
}

object Fonts {
    val body: FontFamily
        get() = when (Settings.font) {
            "serif" -> FontFamily.Serif
            "mono" -> FontFamily.Monospace
            else -> FontFamily.Default
        }
    val heading: FontFamily
        get() = when (Settings.font) {
            "editorial", "serif" -> FontFamily.Serif
            "mono" -> FontFamily.Monospace
            else -> FontFamily.Default
        }
}

@Composable
fun AppTheme(content: @Composable () -> Unit) {
    val p = Settings.palette
    val accent = Th.accent
    val onAccent = Th.onAccent
    val scheme = if (p.isLight) {
        lightColorScheme(
            primary = accent, onPrimary = onAccent, background = Th.bg, onBackground = Th.text,
            surface = Th.panel, onSurface = Th.text, surfaceVariant = Th.panel2, onSurfaceVariant = Th.muted,
            outline = Th.border, error = Th.bad
        )
    } else {
        darkColorScheme(
            primary = accent, onPrimary = onAccent, background = Th.bg, onBackground = Th.text,
            surface = Th.panel, onSurface = Th.text, surfaceVariant = Th.panel2, onSurfaceVariant = Th.muted,
            outline = Th.border, error = Th.bad
        )
    }
    val base = Typography()
    val ff = Fonts.body
    val typography = Typography(
        displayLarge = base.displayLarge.copy(fontFamily = ff),
        displayMedium = base.displayMedium.copy(fontFamily = ff),
        displaySmall = base.displaySmall.copy(fontFamily = ff),
        headlineLarge = base.headlineLarge.copy(fontFamily = ff),
        headlineMedium = base.headlineMedium.copy(fontFamily = ff),
        headlineSmall = base.headlineSmall.copy(fontFamily = ff),
        titleLarge = base.titleLarge.copy(fontFamily = ff),
        titleMedium = base.titleMedium.copy(fontFamily = ff),
        titleSmall = base.titleSmall.copy(fontFamily = ff),
        bodyLarge = base.bodyLarge.copy(fontFamily = ff),
        bodyMedium = base.bodyMedium.copy(fontFamily = ff),
        bodySmall = base.bodySmall.copy(fontFamily = ff),
        labelLarge = base.labelLarge.copy(fontFamily = ff),
        labelMedium = base.labelMedium.copy(fontFamily = ff),
        labelSmall = base.labelSmall.copy(fontFamily = ff)
    )
    val view = LocalView.current
    val light = p.isLight
    SideEffect {
        val window = (view.context as? android.app.Activity)?.window
        if (window != null) {
            val controller = WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = light
            controller.isAppearanceLightNavigationBars = light
        }
    }
    val d = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(d.density, d.fontScale * Settings.fontScale)) {
        MaterialTheme(colorScheme = scheme, typography = typography, content = content)
    }
}

// ───────────── Éléments de base ─────────────

@Composable
fun Txt(
    text: String,
    size: Int = 14,
    weight: FontWeight = FontWeight.Normal,
    color: Color = Th.text,
    heading: Boolean = false,
    modifier: Modifier = Modifier,
    maxLines: Int = Int.MAX_VALUE,
    align: TextAlign? = null
) {
    Text(
        text = text,
        modifier = modifier,
        color = color,
        fontSize = size.sp,
        fontWeight = weight,
        fontFamily = if (heading) Fonts.heading else Fonts.body,
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
        textAlign = align
    )
}

@Composable
fun SectionLabel(text: String) {
    Txt(text.uppercase(), size = 11, weight = FontWeight.SemiBold, color = Th.muted)
}

@Composable
fun Card(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    var m = modifier
        .fillMaxWidth()
        .clip(shape)
        .background(Th.panel)
        .border(1.dp, Th.border, shape)
    if (onClick != null) m = m.clickable { onClick() }
    Column(m.padding(Th.pad), verticalArrangement = Arrangement.spacedBy(Th.gap), content = content)
}

@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Th.accent, contentColor = Th.onAccent,
            disabledContainerColor = Th.panel2, disabledContentColor = Th.muted)
    ) {
        Txt(text, size = 15, weight = FontWeight.SemiBold, color = if (enabled) Th.onAccent else Th.muted)
    }
}

@Composable
fun GhostButton(text: String, modifier: Modifier = Modifier, danger: Boolean = false, onClick: () -> Unit) {
    val tint = if (danger) Th.bad else Th.text
    OutlinedButton(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(1.dp, if (danger) Th.bad else Th.border)
    ) {
        Txt(text, size = 15, weight = FontWeight.Medium, color = tint)
    }
}

@Composable
fun TextLink(text: String, color: Color = Th.accent, onClick: () -> Unit) {
    Txt(text, size = 15, weight = FontWeight.SemiBold, color = color,
        modifier = Modifier.clickable { onClick() }.padding(horizontal = 8.dp, vertical = 8.dp))
}

@Composable
fun Field(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    keyboard: KeyboardType = KeyboardType.Text,
    singleLine: Boolean = true
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = modifier.fillMaxWidth(),
        placeholder = { Txt(placeholder, color = Th.muted) },
        singleLine = singleLine,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard),
        shape = RoundedCornerShape(12.dp),
        textStyle = androidx.compose.ui.text.TextStyle(color = Th.text, fontFamily = Fonts.body),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Th.accent, unfocusedBorderColor = Th.border,
            focusedContainerColor = Th.input, unfocusedContainerColor = Th.input,
            cursorColor = Th.accent, focusedTextColor = Th.text, unfocusedTextColor = Th.text
        )
    )
}

/** Liste déroulante : une ligne avec la valeur choisie et un menu. */
@Composable
fun Picker(label: String, current: String, options: List<Pair<String, String>>, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().clickable { open = true }.padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Txt(label, size = 15, modifier = Modifier.weight(1f))
            Txt(options.firstOrNull { it.first == current }?.second ?: current, size = 15, color = Th.muted)
            Txt("  ▾", size = 15, color = Th.muted)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = Th.panel2) {
            for ((key, text) in options) {
                DropdownMenuItem(
                    text = { Txt(text, size = 15, color = if (key == current) Th.accent else Th.text) },
                    onClick = {
                        open = false
                        onSelect(key)
                    }
                )
            }
        }
    }
}

@Composable
fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Txt(label, size = 15, modifier = Modifier.weight(1f))
        androidx.compose.material3.Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = androidx.compose.material3.SwitchDefaults.colors(
                checkedThumbColor = Th.onAccent, checkedTrackColor = Th.accent,
                uncheckedThumbColor = Th.muted, uncheckedTrackColor = Th.panel2, uncheckedBorderColor = Th.border
            )
        )
    }
}

@Composable
fun Divider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Th.border))
}

@Composable
fun ProductImage(url: String?, size: Int) {
    val shape = RoundedCornerShape((size * 0.22f).dp)
    Box(
        Modifier.size(size.dp).clip(shape).background(if (url.isNullOrEmpty()) Th.panel2 else Color.White),
        contentAlignment = Alignment.Center
    ) {
        if (!url.isNullOrEmpty()) {
            AsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(size.dp).padding((size * 0.06f).dp)
            )
        } else {
            Txt("◻", size = size / 3, color = Th.muted)
        }
    }
}

// ───────────── Anneau de progression ─────────────

@Composable
fun Ring(progress: Double, size: Int) {
    val track = Th.panel2
    val fill = Th.accent
    Box(Modifier.size(size.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size.dp)) {
            val stroke = this.size.minDimension * 0.09f
            val inset = stroke / 2f
            val arcSize = Size(this.size.width - stroke, this.size.height - stroke)
            drawArc(track, 0f, 360f, false, topLeft = Offset(inset, inset), size = arcSize, style = Stroke(stroke))
            drawArc(fill, -90f, (360.0 * progress).toFloat(), false, topLeft = Offset(inset, inset), size = arcSize,
                style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Txt(Math.round(progress * 100).toString() + " %", size = (size / 5), weight = FontWeight.Bold, heading = true)
            Txt(L.t("ring.of_goal"), size = 11, color = Th.muted)
        }
    }
}

// ───────────── Graphique du prix ─────────────

@Composable
fun PriceChart(goal: Goal) {
    val h = goal.sortedHistory
    Card {
        SectionLabel(L.t("chart.title"))
        if (h.size < 2) {
            Txt(L.t("chart.empty_title"), size = 15, weight = FontWeight.SemiBold)
            Txt(L.t("chart.empty_sub"), size = 13, color = Th.muted)
        } else {
            val lo = h.minOf { it.price }
            val hi = h.maxOf { it.price }
            Txt(L.f("chart.range", goal.money(lo), goal.money(hi)), size = 12, color = Th.muted)
            val line = Th.accent
            val grid = Th.border
            val savedLine = Th.gold
            val savedShown = goal.saved > 0 && goal.saved >= lo * 0.5
            val top = maxOf(hi, if (savedShown) goal.saved else hi)
            val bottom = minOf(lo, if (savedShown) goal.saved else lo)
            val span = if (top - bottom < 0.01) 1.0 else top - bottom
            Canvas(Modifier.fillMaxWidth().height(140.dp)) {
                val w = size.width
                val ht = size.height
                val padY = 10f
                fun yOf(v: Double): Float = padY + ((top - v) / span).toFloat() * (ht - 2 * padY)
                for (i in 0..2) {
                    val y = padY + i * (ht - 2 * padY) / 2f
                    drawLine(grid, Offset(0f, y), Offset(w, y), strokeWidth = 1f)
                }
                if (savedShown) {
                    val y = yOf(goal.saved)
                    drawLine(savedLine, Offset(0f, y), Offset(w, y), strokeWidth = 2f,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(14f, 10f)))
                }
                val t0 = h.first().t.toDouble()
                val t1 = h.last().t.toDouble()
                val tSpan = if (t1 - t0 < 1) 1.0 else t1 - t0
                val path = Path()
                h.forEachIndexed { i, p ->
                    val x = ((p.t - t0) / tSpan).toFloat() * w
                    val y = yOf(p.price)
                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                drawPath(path, line, style = Stroke(width = 4f, cap = StrokeCap.Round))
                val last = h.last()
                drawCircle(line, 8f, Offset(((last.t - t0) / tSpan).toFloat() * w, yOf(last.price)))
            }
            if (goal.saved > 0) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(width = 18.dp, height = 3.dp).background(Th.gold))
                    Spacer(Modifier.width(6.dp))
                    Txt(L.t("chart.my_savings") + " " + goal.money(goal.saved), size = 12, color = Th.muted)
                }
            }
        }
    }
}

@Composable
fun StatTile(label: String, value: String, sub: String, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier.clip(shape).background(Th.panel2).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Txt(label, size = 11, color = Th.muted, maxLines = 1)
        Txt(value, size = 18, weight = FontWeight.Bold, heading = true, maxLines = 1)
        Txt(sub, size = 11, color = Th.muted, maxLines = 2)
    }
}

@Composable
fun Dot(color: Color, size: Int = 10) {
    Box(Modifier.size(size.dp).clip(CircleShape).background(color))
}
