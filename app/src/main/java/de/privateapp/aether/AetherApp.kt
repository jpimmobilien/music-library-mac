package de.privateapp.aether

import android.app.Application

/** Anwendung: hält die zentrale Verdrahtung. Keine Analyse-, Absturz- oder Werbedienste. */
class AetherApp : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }
}
