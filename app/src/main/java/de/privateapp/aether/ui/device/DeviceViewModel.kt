package de.privateapp.aether.ui.device

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.privateapp.aether.AppGraph
import de.privateapp.aether.model.device.BatterySnapshot
import de.privateapp.aether.model.device.DeviceSummary
import de.privateapp.aether.model.device.ThermalSnapshot
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.stateIn

data class DeviceState(
    val summary: DeviceSummary? = null,
    val battery: BatterySnapshot? = null,
    val thermal: ThermalSnapshot? = null,
)

class DeviceViewModel(graph: AppGraph) : ViewModel() {
    /**
     * Geräteübersicht; Arbeitsspeicher und Laufzeit ändern sich – solange sichtbar, alle 30 s neu lesen. Der letzte
     * Stand bleibt erhalten, wenn man zurückkehrt (keine leeren Karten, keine springende Liste).
     */
    private val summary: StateFlow<DeviceSummary?> = flow<DeviceSummary?> {
        while (true) {
            emit(graph.deviceInfo.read())
            delay(30_000L)
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val state: StateFlow<DeviceState> = combine(summary, graph.battery, graph.thermal) { s, b, t -> DeviceState(s, b, t) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DeviceState(null, graph.battery.value, graph.thermal.value))
}
