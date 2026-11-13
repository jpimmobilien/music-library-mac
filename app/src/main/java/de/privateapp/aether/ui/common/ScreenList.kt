package de.privateapp.aether.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.GlassCircleButton
import de.privateapp.aether.design.Motion
import de.privateapp.aether.design.Spacing
import kotlinx.coroutines.delay

/**
 * Bildschirm als ruhige, scrollbare Spalte: Seitenränder, Freiraum für Systemleisten und Navigation, auf
 * großen Displays mittig mit begrenzter Breite. [reselect] wächst, wenn der Bereich erneut angetippt wird –
 * dann scrollt die Liste nach oben.
 */
@Composable
fun ScreenList(
    insets: PaddingValues,
    reselect: Int,
    modifier: Modifier = Modifier,
    content: LazyListScope.() -> Unit,
) {
    val state = rememberLazyListState()
    val motion = Aether.motion
    // Nur auf ein NEUES erneutes Antippen reagieren – kehrt man später zum Bereich zurück, bleibt die Position.
    var handledReselect by rememberSaveable { mutableIntStateOf(reselect) }
    LaunchedEffect(reselect) {
        when {
            reselect > handledReselect -> {
                handledReselect = reselect
                if (motion.reduced) state.scrollToItem(0) else state.animateScrollToItem(0)
            }
            // Zähler wurde neu gestartet (z. B. nach dem Drehen) – nur übernehmen, nicht scrollen.
            reselect < handledReselect -> handledReselect = reselect
        }
    }
    val dir = LocalLayoutDirection.current
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        LazyColumn(
            state = state,
            modifier = Modifier.fillMaxHeight().widthIn(max = Spacing.contentMaxWidth).fillMaxWidth(),
            contentPadding = PaddingValues(
                start = insets.calculateStartPadding(dir) + Spacing.page,
                end = insets.calculateEndPadding(dir) + Spacing.page,
                top = insets.calculateTopPadding() + Spacing.xl,
                bottom = insets.calculateBottomPadding() + Spacing.xxl,
            ),
            verticalArrangement = Arrangement.spacedBy(Spacing.cardGap),
            content = content,
        )
    }
}

/** Kopf einer Unterseite: runde Zurück-Schaltfläche und Titel. */
@Composable
fun SubpageHeader(title: String, onBack: () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        GlassCircleButton(icon = AetherIcons.ChevronLeft, contentDescription = "Zurück", onClick = onBack)
        Spacer(Modifier.width(Spacing.l))
        Text(title, color = Aether.colors.text, style = Aether.type.title, modifier = Modifier.weight(1f).semantics { heading() })
    }
}

/**
 * Sanftes Einblenden beim ersten Erscheinen (Übersicht): leicht versetzt nacheinander, nur einmal je Element
 * und nur, wenn dekorative Bewegung erlaubt ist (nicht bei reduzierter Bewegung oder Effektstärke „Minimal“).
 */
@Composable
fun Modifier.entrance(index: Int): Modifier {
    val motion = Aether.motion
    var played by rememberSaveable { mutableStateOf(!motion.decorative) }
    val progress = remember { Animatable(if (played) 1f else 0f) }
    LaunchedEffect(Unit) {
        if (!played) {
            delay(55L * index)
            progress.animateTo(1f, tween(520, easing = Motion.Emphasized))
            played = true
        }
    }
    return this.graphicsLayer {
        alpha = progress.value
        translationY = (1f - progress.value) * 16.dp.toPx()
    }
}

/** Zwei Spalten mit gleicher Breite (z. B. Theme-Kacheln); die letzte Zeile darf eine Lücke haben. */
@Composable
fun <T> GridRows(items: List<T>, columns: Int, modifier: Modifier = Modifier, cell: @Composable (T, Modifier) -> Unit) {
    androidx.compose.foundation.layout.Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
        items.chunked(columns).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.m)) {
                row.forEach { cell(it, Modifier.weight(1f)) }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/**
 * Kleine Zeile mit der Uhrzeit eines laufenden Werts. [label] sagt ehrlich, was die Zeit bedeutet: Akku und
 * Speicher melden nur Änderungen („Zuletzt geändert“), der Thermalstatus wird regelmäßig gelesen („Gelesen“).
 */
@Composable
fun UpdatedAt(epochMillis: Long?, modifier: Modifier = Modifier, label: String = "Zuletzt geändert um") {
    if (epochMillis == null) return
    Text(
        "$label ${de.privateapp.aether.model.Fmt.clockTime(epochMillis)}",
        color = Aether.colors.textTertiary,
        style = Aether.type.footnote,
        modifier = modifier.padding(top = Spacing.s),
    )
}
