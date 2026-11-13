package de.privateapp.aether.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/*
 * Symbolsatz „Aether Line“ – eigene Gestaltung: 24-dp-Raster, 1,7-dp-Linie, runde Enden und Ecken,
 * großzügige Radien passend zu den Karten. Punkte (i-Punkt, Ausrufezeichen) sind gefüllte Kreise, damit sie
 * auf jedem Gerät gleich erscheinen. Die Farbe kommt immer aus dem Theme (Icon(tint = …)).
 * Vorschau aller Symbole ohne Gerät: tools/icons/preview.py.
 */

private const val STROKE = 1.7f

/** „F:“ am Anfang = gefüllte Fläche statt Linie. */
private fun icon(name: String, vararg paths: String): ImageVector {
    val b = ImageVector.Builder(name = name, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
    for (p in paths) {
        if (p.startsWith("F:")) {
            b.addPath(pathData = addPathNodes(p.removePrefix("F:")), fill = SolidColor(Color.Black))
        } else {
            b.addPath(
                pathData = addPathNodes(p),
                fill = null,
                stroke = SolidColor(Color.Black),
                strokeLineWidth = STROKE,
                strokeLineCap = StrokeCap.Round,
                strokeLineJoin = StrokeJoin.Round,
            )
        }
    }
    return b.build()
}

private fun circle(cx: Float, cy: Float, r: Float): String = "M$cx ${cy - r} A$r $r 0 1 1 $cx ${cy + r} A$r $r 0 1 1 $cx ${cy - r} Z"

object AetherIcons {
    val Home: ImageVector by lazy {
        icon(
            "Home",
            "M4.5 10.2 L12 4.2 L19.5 10.2",
            "M6 9 V18.5 A1.5 1.5 0 0 0 7.5 20 H16.5 A1.5 1.5 0 0 0 18 18.5 V9",
            "M10 20 V15.5 A2 2 0 0 1 14 15.5 V20",
        )
    }
    val Folder: ImageVector by lazy {
        icon(
            "Folder",
            "M3.75 7.25 A2 2 0 0 1 5.75 5.25 H9.4 A1.6 1.6 0 0 1 10.53 5.72 L12 7.25 H18.25 A2 2 0 0 1 20.25 9.25 V17.25 A2 2 0 0 1 18.25 19.25 H5.75 A2 2 0 0 1 3.75 17.25 Z",
            "M3.75 10.25 H20.25",
        )
    }
    val StorageRing: ImageVector by lazy {
        icon("Storage", "M12 3.75 A8.25 8.25 0 1 0 20.25 12", "M15.22 4.41 A8.25 8.25 0 0 1 19.59 8.78", circle(12f, 12f, 3f))
    }
    val Phone: ImageVector by lazy {
        icon("Phone", "M8 2.75 H16 A2.25 2.25 0 0 1 18.25 5 V19 A2.25 2.25 0 0 1 16 21.25 H8 A2.25 2.25 0 0 1 5.75 19 V5 A2.25 2.25 0 0 1 8 2.75 Z", "M10.5 18.25 H13.5")
    }
    val Sliders: ImageVector by lazy {
        icon("Settings", "M4 8 H12.5", "M17.5 8 H20", circle(15f, 8f, 2.5f), "M4 16 H6.5", "M11.5 16 H20", circle(9f, 16f, 2.5f))
    }
    val Search: ImageVector by lazy { icon("Search", circle(10.75f, 10.75f, 6.25f), "M15.4 15.4 L20 20") }
    val Battery: ImageVector by lazy {
        icon(
            "Battery",
            "M5.5 7 H16.5 A2.5 2.5 0 0 1 19 9.5 V14.5 A2.5 2.5 0 0 1 16.5 17 H5.5 A2.5 2.5 0 0 1 3 14.5 V9.5 A2.5 2.5 0 0 1 5.5 7 Z",
            "M21.25 10.5 V13.5",
        )
    }
    val Bolt: ImageVector by lazy { icon("Bolt", "M13.25 3.5 L6.75 13 H11.5 L10.75 20.5 L17.25 11 H12.5 Z") }
    val Thermometer: ImageVector by lazy {
        icon("Thermometer", "M9.75 13 V5.25 A2.25 2.25 0 0 1 14.25 5.25 V13 A4.25 4.25 0 1 1 9.75 13 Z", "M12 9 V16.5")
    }
    val SdCard: ImageVector by lazy {
        icon("SdCard", "M8.5 3 H15.25 L18.75 6.5 V19 A2 2 0 0 1 16.75 21 H8.5 A2 2 0 0 1 6.5 19 V5 A2 2 0 0 1 8.5 3 Z", "M10.25 6.5 V9", "M13.25 6.5 V9")
    }
    val Usb: ImageVector by lazy {
        icon(
            "Usb",
            "M8.25 9.25 H15.75 A1.5 1.5 0 0 1 17.25 10.75 V19 A2 2 0 0 1 15.25 21 H8.75 A2 2 0 0 1 6.75 19 V10.75 A1.5 1.5 0 0 1 8.25 9.25 Z",
            "M9 9.25 V3.5 H15 V9.25",
            "F:" + circle(11f, 6.25f, 0.9f),
            "F:" + circle(13f, 6.25f, 0.9f),
        )
    }
    val Drive: ImageVector by lazy {
        icon("Drive", "M5.5 8.5 H18.5 A2.5 2.5 0 0 1 21 11 V13 A2.5 2.5 0 0 1 18.5 15.5 H5.5 A2.5 2.5 0 0 1 3 13 V11 A2.5 2.5 0 0 1 5.5 8.5 Z", "M6.75 12 H11", "F:" + circle(17f, 12f, 1.1f))
    }
    val Chip: ImageVector by lazy {
        icon(
            "Chip",
            "M9 7 H15 A2 2 0 0 1 17 9 V15 A2 2 0 0 1 15 17 H9 A2 2 0 0 1 7 15 V9 A2 2 0 0 1 9 7 Z",
            "M10 3.75 V7", "M14 3.75 V7", "M10 17 V20.25", "M14 17 V20.25",
            "M3.75 10 H7", "M3.75 14 H7", "M17 10 H20.25", "M17 14 H20.25",
            "M10.75 10 H13.25 A0.75 0.75 0 0 1 14 10.75 V13.25 A0.75 0.75 0 0 1 13.25 14 H10.75 A0.75 0.75 0 0 1 10 13.25 V10.75 A0.75 0.75 0 0 1 10.75 10 Z",
        )
    }
    val Memory: ImageVector by lazy {
        icon(
            "Memory",
            "M4.5 7 H19.5 A1.5 1.5 0 0 1 21 8.5 V15.5 A1.5 1.5 0 0 1 19.5 17 H4.5 A1.5 1.5 0 0 1 3 15.5 V8.5 A1.5 1.5 0 0 1 4.5 7 Z",
            "M7 17 V20", "M10.33 17 V20", "M13.67 17 V20", "M17 17 V20",
            "M7.25 10.25 V13.75", "M12 10.25 V13.75", "M16.75 10.25 V13.75",
        )
    }
    val Display: ImageVector by lazy {
        icon(
            "Display",
            "M4.75 4.5 H19.25 A1.75 1.75 0 0 1 21 6.25 V15.25 A1.75 1.75 0 0 1 19.25 17 H4.75 A1.75 1.75 0 0 1 3 15.25 V6.25 A1.75 1.75 0 0 1 4.75 4.5 Z",
            "M8.5 20.5 H15.5",
            "M12 17 V20.5",
        )
    }
    val Layers: ImageVector by lazy {
        icon("Layers", "M12 3.75 L20.25 8 L12 12.25 L3.75 8 Z", "M3.75 12 L12 16.25 L20.25 12", "M3.75 16 L12 20.25 L20.25 16")
    }
    val Sensor: ImageVector by lazy {
        icon(
            "Sensor",
            "F:" + circle(12f, 12f, 1.75f),
            "M8.6 15.4 A4.8 4.8 0 0 1 8.6 8.6", "M15.4 8.6 A4.8 4.8 0 0 1 15.4 15.4",
            "M5.8 18.2 A8.75 8.75 0 0 1 5.8 5.8", "M18.2 5.8 A8.75 8.75 0 0 1 18.2 18.2",
        )
    }
    val ChevronRight: ImageVector by lazy { icon("ChevronRight", "M9.5 5.75 L15.75 12 L9.5 18.25") }
    val ChevronLeft: ImageVector by lazy { icon("ChevronLeft", "M14.5 5.75 L8.25 12 L14.5 18.25") }
    val Info: ImageVector by lazy { icon("Info", circle(12f, 12f, 8.75f), "M12 11 V16.25", "F:" + circle(12f, 7.75f, 1.15f)) }
    val Check: ImageVector by lazy { icon("Check", "M5.25 12.5 L9.75 17 L18.75 7.25") }
    val CheckCircle: ImageVector by lazy { icon("CheckCircle", circle(12f, 12f, 8.75f), "M8.25 12.25 L11 15 L15.9 9.5") }
    val Warning: ImageVector by lazy {
        icon(
            "Warning",
            "M10.27 4.75 A2 2 0 0 1 13.73 4.75 L20.6 16.75 A2 2 0 0 1 18.87 19.75 H5.13 A2 2 0 0 1 3.4 16.75 Z",
            "M12 9.5 V13.25",
            "F:" + circle(12f, 16.4f, 1.1f),
        )
    }
    val Close: ImageVector by lazy { icon("Close", "M6.5 6.5 L17.5 17.5", "M17.5 6.5 L6.5 17.5") }
    val Contrast: ImageVector by lazy { icon("Contrast", circle(12f, 12f, 8.75f), "F:M12 3.25 A8.75 8.75 0 0 1 12 20.75 Z") }
    val Sparkle: ImageVector by lazy {
        icon(
            "Sparkle",
            "M11 3.5 C11.55 7.9 13.1 9.45 17.5 10 C13.1 10.55 11.55 12.1 11 16.5 C10.45 12.1 8.9 10.55 4.5 10 C8.9 9.45 10.45 7.9 11 3.5 Z",
            "M18 15.25 V20.25", "M15.5 17.75 H20.5",
        )
    }
    val Motion: ImageVector by lazy { icon("Motion", "M3 12 C5.25 8 7.5 8 9.75 12 C12 16 14.25 16 16.5 12 C18 9.3 19.5 8.6 21 9.5") }
    val Shield: ImageVector by lazy {
        icon("Shield", "M12 3.25 L19 6 V11.25 C19 15.6 16.1 19.1 12 20.75 C7.9 19.1 5 15.6 5 11.25 V6 Z", "M9 12 L11.2 14.2 L15.2 10")
    }
    val Document: ImageVector by lazy {
        icon(
            "Document",
            "M7 3 H13.5 L18 7.5 V19 A2 2 0 0 1 16 21 H7 A2 2 0 0 1 5 19 V5 A2 2 0 0 1 7 3 Z",
            "M13.5 3 V7.5 H18",
            "M8.5 12 H14.5", "M8.5 15.5 H14.5",
        )
    }
    val Clock: ImageVector by lazy { icon("Clock", circle(12f, 12f, 8.75f), "M12 7.5 V12 L15 14") }
    val Pulse: ImageVector by lazy { icon("Pulse", "M3 12.5 H7 L9.25 7 L13.25 17.5 L15.5 12.5 H21") }
    val Refresh: ImageVector by lazy { icon("Refresh", "M19.5 12 A7.5 7.5 0 1 1 17.3 6.7", "M17.75 3.5 V7 H14.25") }
    val Lock: ImageVector by lazy {
        icon(
            "Lock",
            "M7.5 10.5 H16.5 A2.5 2.5 0 0 1 19 13 V18 A2.5 2.5 0 0 1 16.5 20.5 H7.5 A2.5 2.5 0 0 1 5 18 V13 A2.5 2.5 0 0 1 7.5 10.5 Z",
            "M8 10.5 V7.75 A4 4 0 0 1 16 7.75 V10.5",
        )
    }

    // ---- Dateiarten ----
    val FileImage: ImageVector by lazy {
        icon(
            "FileImage",
            "M5.5 4 H18.5 A1.5 1.5 0 0 1 20 5.5 V18.5 A1.5 1.5 0 0 1 18.5 20 H5.5 A1.5 1.5 0 0 1 4 18.5 V5.5 A1.5 1.5 0 0 1 5.5 4 Z",
            "M4.5 16.5 L9.5 11.5 L13.5 15.5", "M12.5 14.5 L15 12 L19.5 16.5",
            circle(15.5f, 8.5f, 1.5f),
        )
    }
    val FileVideo: ImageVector by lazy {
        icon("FileVideo", "M6 5 H14 A2 2 0 0 1 16 7 V17 A2 2 0 0 1 14 19 H6 A2 2 0 0 1 4 17 V7 A2 2 0 0 1 6 5 Z", "M16 10 L20.5 7.5 V16.5 L16 14")
    }
    val FileAudio: ImageVector by lazy {
        icon("FileAudio", "M9 17.5 V5.5 L19 3.75 V15.75", circle(6.75f, 17.5f, 2.25f), circle(16.75f, 15.75f, 2.25f))
    }
    val FileText: ImageVector by lazy {
        icon(
            "FileText",
            "M7 3 H13.5 L18 7.5 V19 A2 2 0 0 1 16 21 H7 A2 2 0 0 1 5 19 V5 A2 2 0 0 1 7 3 Z",
            "M13.5 3 V7.5 H18", "M8.5 11 H15.5", "M8.5 14.25 H15.5", "M8.5 17.5 H12.5",
        )
    }
    val FilePdf: ImageVector by lazy {
        icon(
            "FilePdf",
            "M7 3 H13.5 L18 7.5 V19 A2 2 0 0 1 16 21 H7 A2 2 0 0 1 5 19 V5 A2 2 0 0 1 7 3 Z",
            "M13.5 3 V7.5 H18",
            "F:M8 12.5 H15 A1 1 0 0 1 16 13.5 V16.5 A1 1 0 0 1 15 17.5 H8 A1 1 0 0 1 7 16.5 V13.5 A1 1 0 0 1 8 12.5 Z",
        )
    }
    val FileGeneric: ImageVector by lazy {
        icon("FileGeneric", "M7 3 H13.5 L18 7.5 V19 A2 2 0 0 1 16 21 H7 A2 2 0 0 1 5 19 V5 A2 2 0 0 1 7 3 Z", "M13.5 3 V7.5 H18")
    }
    val FileArchive: ImageVector by lazy {
        icon(
            "FileArchive",
            "M6.5 3.5 H17.5 A2 2 0 0 1 19.5 5.5 V18.5 A2 2 0 0 1 17.5 20.5 H6.5 A2 2 0 0 1 4.5 18.5 V5.5 A2 2 0 0 1 6.5 3.5 Z",
            "M12 3.5 V5.25", "M12 6.75 V8.5", "M12 10 V11.75",
            "M10.75 13.25 H13.25 A0.75 0.75 0 0 1 14 14 V16.25 A0.75 0.75 0 0 1 13.25 17 H10.75 A0.75 0.75 0 0 1 10 16.25 V14 A0.75 0.75 0 0 1 10.75 13.25 Z",
        )
    }
    val FilePackage: ImageVector by lazy {
        icon("FilePackage", "M12 3.5 L19.5 7.5 V16.5 L12 20.5 L4.5 16.5 V7.5 Z", "M4.5 7.5 L12 11.5 L19.5 7.5", "M12 11.5 V20.5")
    }
    val Download: ImageVector by lazy { icon("Download", "M12 4 V14.5", "M7.5 10.5 L12 15 L16.5 10.5", "M5 19.5 H19") }

    // ---- Aktionen ----
    val Star: ImageVector by lazy {
        icon("Star", "M12 3.75 L14.47 8.76 L20 9.56 L16 13.46 L16.94 18.97 L12 16.37 L7.06 18.97 L8 13.46 L4 9.56 L9.53 8.76 Z")
    }
    val StarFilled: ImageVector by lazy {
        icon(
            "StarFilled",
            "F:M12 3.75 L14.47 8.76 L20 9.56 L16 13.46 L16.94 18.97 L12 16.37 L7.06 18.97 L8 13.46 L4 9.56 L9.53 8.76 Z",
            "M12 3.75 L14.47 8.76 L20 9.56 L16 13.46 L16.94 18.97 L12 16.37 L7.06 18.97 L8 13.46 L4 9.56 L9.53 8.76 Z",
        )
    }
    val Trash: ImageVector by lazy {
        icon(
            "Trash",
            "M4.5 7 H19.5",
            "M9.5 7 V5.25 A1.25 1.25 0 0 1 10.75 4 H13.25 A1.25 1.25 0 0 1 14.5 5.25 V7",
            "M6.5 7 L7.4 19.1 A1.5 1.5 0 0 0 8.9 20.5 H15.1 A1.5 1.5 0 0 0 16.6 19.1 L17.5 7",
            "M10 11 V16.5", "M14 11 V16.5",
        )
    }
    val Restore: ImageVector by lazy { icon("Restore", "M4.5 12 A7.5 7.5 0 1 0 6.7 6.7", "M6.25 3.5 V7 H9.75") }
    val Copy: ImageVector by lazy {
        icon(
            "Copy",
            "M10.5 8.5 H17.5 A2 2 0 0 1 19.5 10.5 V18 A2 2 0 0 1 17.5 20 H10.5 A2 2 0 0 1 8.5 18 V10.5 A2 2 0 0 1 10.5 8.5 Z",
            "M15.5 8.5 V6 A2 2 0 0 0 13.5 4 H6.5 A2 2 0 0 0 4.5 6 V13.5 A2 2 0 0 0 6.5 15.5 H8.5",
        )
    }
    val MoveTo: ImageVector by lazy {
        icon(
            "MoveTo",
            "M3.75 7.25 A2 2 0 0 1 5.75 5.25 H9.4 A1.6 1.6 0 0 1 10.53 5.72 L12 7.25 H18.25 A2 2 0 0 1 20.25 9.25 V17.25 A2 2 0 0 1 18.25 19.25 H5.75 A2 2 0 0 1 3.75 17.25 Z",
            "M9 13.5 H15", "M12.75 11.25 L15 13.5 L12.75 15.75",
        )
    }
    val Pencil: ImageVector by lazy { icon("Pencil", "M14.8 5.2 L18.8 9.2 L9 19 H5 V15 Z", "M12.8 7.2 L16.8 11.2") }
    val Share: ImageVector by lazy {
        icon(
            "Share",
            "M12 3.5 V14", "M8 7.5 L12 3.5 L16 7.5",
            "M8 10.5 H7 A2 2 0 0 0 5 12.5 V18.5 A2 2 0 0 0 7 20.5 H17 A2 2 0 0 0 19 18.5 V12.5 A2 2 0 0 0 17 10.5 H16",
        )
    }
    val More: ImageVector by lazy { icon("More", "F:" + circle(6f, 12f, 1.5f), "F:" + circle(12f, 12f, 1.5f), "F:" + circle(18f, 12f, 1.5f)) }
    val Plus: ImageVector by lazy { icon("Plus", "M12 5 V19", "M5 12 H19") }
    val FolderPlus: ImageVector by lazy {
        icon(
            "FolderPlus",
            "M3.75 7.25 A2 2 0 0 1 5.75 5.25 H9.4 A1.6 1.6 0 0 1 10.53 5.72 L12 7.25 H18.25 A2 2 0 0 1 20.25 9.25 V17.25 A2 2 0 0 1 18.25 19.25 H5.75 A2 2 0 0 1 3.75 17.25 Z",
            "M12 10.75 V16.25", "M9.25 13.5 H14.75",
        )
    }
    val Grid: ImageVector by lazy {
        icon(
            "Grid",
            "M5.5 4.5 H9.5 A1 1 0 0 1 10.5 5.5 V9.5 A1 1 0 0 1 9.5 10.5 H5.5 A1 1 0 0 1 4.5 9.5 V5.5 A1 1 0 0 1 5.5 4.5 Z",
            "M14.5 4.5 H18.5 A1 1 0 0 1 19.5 5.5 V9.5 A1 1 0 0 1 18.5 10.5 H14.5 A1 1 0 0 1 13.5 9.5 V5.5 A1 1 0 0 1 14.5 4.5 Z",
            "M5.5 13.5 H9.5 A1 1 0 0 1 10.5 14.5 V18.5 A1 1 0 0 1 9.5 19.5 H5.5 A1 1 0 0 1 4.5 18.5 V14.5 A1 1 0 0 1 5.5 13.5 Z",
            "M14.5 13.5 H18.5 A1 1 0 0 1 19.5 14.5 V18.5 A1 1 0 0 1 18.5 19.5 H14.5 A1 1 0 0 1 13.5 18.5 V14.5 A1 1 0 0 1 14.5 13.5 Z",
        )
    }
    val ListView: ImageVector by lazy {
        icon("ListView", "M9 7 H20", "M9 12 H20", "M9 17 H20", "F:" + circle(5f, 7f, 1.25f), "F:" + circle(5f, 12f, 1.25f), "F:" + circle(5f, 17f, 1.25f))
    }
    val Sort: ImageVector by lazy { icon("Sort", "M8 5 V19", "M4.5 8.5 L8 5 L11.5 8.5", "M16 19 V5", "M12.5 15.5 L16 19 L19.5 15.5") }
    val SelectAll: ImageVector by lazy {
        icon("SelectAll", "M6.5 4 H17.5 A2.5 2.5 0 0 1 20 6.5 V17.5 A2.5 2.5 0 0 1 17.5 20 H6.5 A2.5 2.5 0 0 1 4 17.5 V6.5 A2.5 2.5 0 0 1 6.5 4 Z", "M8.25 12.25 L11 15 L15.9 9.5")
    }
    val Eye: ImageVector by lazy {
        icon("Eye", "M2.75 12 C5 7.5 8.5 5.5 12 5.5 C15.5 5.5 19 7.5 21.25 12 C19 16.5 15.5 18.5 12 18.5 C8.5 18.5 5 16.5 2.75 12 Z", circle(12f, 12f, 3f))
    }
    val EyeOff: ImageVector by lazy {
        icon(
            "EyeOff",
            "M2.75 12 C5 7.5 8.5 5.5 12 5.5 C15.5 5.5 19 7.5 21.25 12 C19 16.5 15.5 18.5 12 18.5 C8.5 18.5 5 16.5 2.75 12 Z",
            circle(12f, 12f, 3f), "M4.5 4.5 L19.5 19.5",
        )
    }
    val Extract: ImageVector by lazy {
        icon(
            "Extract",
            "M6.5 3.5 H17.5 A2 2 0 0 1 19.5 5.5 V12", "M4.5 12 V5.5 A2 2 0 0 1 6.5 3.5",
            "M12 10 V20", "M8.5 16.5 L12 20 L15.5 16.5", "M4.5 20.5 H8", "M16 20.5 H19.5",
        )
    }
    val OpenExternal: ImageVector by lazy { icon("OpenExternal", "M8 16 L16 8", "M9.5 8 H16 V14.5") }
    val ChevronDown: ImageVector by lazy { icon("ChevronDown", "M5.75 9.5 L12 15.75 L18.25 9.5") }
    val ChevronUp: ImageVector by lazy { icon("ChevronUp", "M5.75 14.5 L12 8.25 L18.25 14.5") }

    // ---- Bewegung ----
    val Gauge: ImageVector by lazy {
        icon("Gauge", "M4.8 16.5 A8.5 8.5 0 1 1 19.2 16.5", "M12 13.5 L15.75 9.25", "F:" + circle(12f, 13.5f, 1.6f))
    }
    val Mountain: ImageVector by lazy { icon("Mountain", "M3 19.5 L9.2 8.5 L13 15 L15.3 11.5 L21 19.5 Z", "M7.6 11.3 L9.2 12.4 L10.6 11") }
    val Compass: ImageVector by lazy {
        icon("Compass", circle(12f, 12f, 8.75f), "M12 6.5 L14.2 12 L12 17.5 L9.8 12 Z", "F:M12 6.5 L14.2 12 L9.8 12 Z")
    }
    val Satellite: ImageVector by lazy {
        icon(
            "Satellite",
            "M10.5 8.5 H13.5 A1 1 0 0 1 14.5 9.5 V13.5 A1 1 0 0 1 13.5 14.5 H10.5 A1 1 0 0 1 9.5 13.5 V9.5 A1 1 0 0 1 10.5 8.5 Z",
            "M3 9 H7.5 V14 H3 Z", "M16.5 9 H21 V14 H16.5 Z", "M7.5 11.5 H9.5", "M14.5 11.5 H16.5", "M12 14.5 V17",
            "M8.5 20 A4 4 0 0 1 15.5 20",
        )
    }
    val LocationPin: ImageVector by lazy {
        icon("LocationPin", "M12 21 C12 21 5.5 14.6 5.5 9.75 A6.5 6.5 0 0 1 18.5 9.75 C18.5 14.6 12 21 12 21 Z", circle(12f, 9.75f, 2.25f))
    }
    val RoutePath: ImageVector by lazy {
        icon("RoutePath", "M6.3 17.6 C9 16.4 9.5 12 12 12 C14.5 12 15 7.6 17.7 6.4", circle(5f, 18.5f, 1.5f), circle(19f, 5.5f, 1.5f))
    }
    val Wind: ImageVector by lazy {
        icon("Wind", "M3.5 9 H14 A2.5 2.5 0 1 0 11.5 6.5", "M3.5 13 H18 A2.5 2.5 0 1 1 15.5 15.5", "M3.5 17 H9")
    }
}
