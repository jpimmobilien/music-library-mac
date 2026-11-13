package de.privateapp.aether.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.privateapp.aether.AppGraph
import de.privateapp.aether.model.device.ChargeStatus
import de.privateapp.aether.model.orbit.CounterRate
import de.privateapp.aether.model.orbit.OrbitBasis
import de.privateapp.aether.model.orbit.OrbitCore
import de.privateapp.aether.model.orbit.OrbitRing
import de.privateapp.aether.model.orbit.OrbitRingState
import de.privateapp.aether.model.orbit.RollingPeak
import de.privateapp.aether.model.valueOrNull
import de.privateapp.aether.platform.device.LiveVitalsReader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.stateIn

/** Eine Sekunde Messung für den ORBIT Core. */
data class VitalsSample(val memory: LiveVitalsReader.Memory?, val networkRate: Double?, val networkPeak: Double?)

/** Zustand des ORBIT Core – nur gemessene Anteile, fehlende Werte bleiben `null`. */
data class OrbitCoreState(
    val rings: List<OrbitRingState> = OrbitRing.entries.map { OrbitRingState.of(it, null) },
    val sample: VitalsSample = VitalsSample(null, null, null),
    val batteryPercent: Int? = null,
    val charging: Boolean = false,
    val batteryTemperature: Double? = null,
    val storageUsedBytes: Long? = null,
    val storageTotalBytes: Long? = null,
    val thermalLabel: String? = null,
) {
    fun ring(r: OrbitRing): OrbitRingState = rings.first { it.ring == r }

    /** Durchsatz relativ zur Spitze (0…1) für den Lichtpunkt. */
    val flow: Float get() = ring(OrbitRing.NETWORK).fraction ?: 0f
}

class OrbitCoreViewModel(graph: AppGraph) : ViewModel() {
    private val vitals = graph.vitals
    private val rate = CounterRate()
    private val peak = RollingPeak()

    private val ticker = flow {
        while (true) {
            val now = System.currentTimeMillis()
            val r = rate.next(vitals.trafficTotalBytes(), now)
            if (r != null) peak.add(r, now)
            emit(VitalsSample(vitals.memory(), r, peak.peak(now)))
            delay(1_000)
        }
    }.flowOn(Dispatchers.Default)

    val state: StateFlow<OrbitCoreState> = combine(ticker, graph.storage, graph.battery, graph.thermal) { sample, storage, battery, thermal ->
        val capacity = storage?.internal?.capacity?.valueOrNull
        val level = battery?.takeIf { it.present }?.level?.valueOrNull
        val headroom = thermal?.headroom?.valueOrNull
        val rings = listOf(
            OrbitRingState.of(OrbitRing.MEMORY, OrbitCore.memoryFraction(sample.memory?.totalBytes, sample.memory?.availableBytes)),
            OrbitRingState.of(OrbitRing.STORAGE, capacity?.usedFraction?.toFloat()),
            OrbitRingState.of(OrbitRing.THERMAL, headroom?.usedFraction),
            OrbitRingState.of(OrbitRing.NETWORK, OrbitCore.networkFraction(sample.networkRate, sample.networkPeak), OrbitBasis.RELATIVE_TO_PEAK),
            OrbitRingState.of(OrbitRing.BATTERY, level?.let { it / 100f }),
        )
        OrbitCoreState(
            rings = rings,
            sample = sample,
            batteryPercent = level,
            charging = battery?.status == ChargeStatus.CHARGING,
            batteryTemperature = battery?.temperatureCelsius?.valueOrNull,
            storageUsedBytes = capacity?.usedBytes,
            storageTotalBytes = capacity?.totalBytes,
            thermalLabel = thermal?.level?.valueOrNull?.label,
        )
    }.distinctUntilChanged().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), OrbitCoreState())
}
