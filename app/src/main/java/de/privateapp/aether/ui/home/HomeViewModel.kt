package de.privateapp.aether.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.privateapp.aether.AppGraph
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.StatusLine
import de.privateapp.aether.model.device.BatterySnapshot
import de.privateapp.aether.model.device.DeviceSummary
import de.privateapp.aether.model.device.ThermalSnapshot
import de.privateapp.aether.model.storage.StorageOverview
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.stateIn

/** Zustand der Übersicht. `null` = noch nicht gelesen. */
data class HomeState(
    val storage: StorageOverview? = null,
    val battery: BatterySnapshot? = null,
    val thermal: ThermalSnapshot? = null,
    val device: DeviceSummary? = null,
) {
    val statusLine: String
        get() = StatusLine.build(
            internal = storage?.internal?.capacity,
            battery = battery,
            thermal = thermal?.level,
        )

    /** Bekannte Speicherorte außer dem internen Speicher. */
    val externalVolumes get() = storage?.external.orEmpty()

    val hasAnyValue: Boolean get() = storage != null || battery != null || thermal != null

    val internalUsedFraction: Float?
        get() = (storage?.internal?.capacity as? Reading.Value)?.value?.usedFraction?.toFloat()
}

class HomeViewModel(graph: AppGraph) : ViewModel() {
    /** Gerätename u. Ä. – einmal gelesen und danach behalten (kein erneutes „Wird gelesen …“). */
    private val device: StateFlow<DeviceSummary?> = flow<DeviceSummary?> { emit(graph.deviceInfo.read()) }
        .stateIn(viewModelScope, SharingStarted.Lazily, null)

    val state: StateFlow<HomeState> = combine(graph.storage, graph.battery, graph.thermal, device) { storage, battery, thermal, d ->
        HomeState(storage, battery, thermal, d)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initialState(graph))

    private fun initialState(graph: AppGraph) = HomeState(graph.storage.value, graph.battery.value, graph.thermal.value, null)
}
