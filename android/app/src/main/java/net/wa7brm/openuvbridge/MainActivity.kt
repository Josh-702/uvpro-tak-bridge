// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : AppCompatActivity() {
    private val main = Handler(Looper.getMainLooper())
    private lateinit var radio: RadioHub

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { radio.scanBle() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val status = findViewById<TextView>(R.id.status)
        val stations = findViewById<TextView>(R.id.stations)
        val log = findViewById<TextView>(R.id.log)
        val callsign = findViewById<EditText>(R.id.callsign)
        radio = RadioHub(this, onFrame = { payload ->
            val ax = OnAir.ax25Decode(payload) ?: return@RadioHub
            val xml = Session.bridge.ingest(ax, System.currentTimeMillis() / 1000)
            Session.publish(xml)
        }, onStatus = { line ->
            main.post { log.text = line + "\n" + (log.text ?: "") }
        })
        Session.listener = {
            main.post {
                status.text = BridgeCore.modeSummary(Session.bridge.mode())
                stations.text = if (Session.bridge.stations.isEmpty()) {
                    "No stations yet. An iPhone running Open UV Bridge will show up here under the same APRS callsign."
                } else {
                    Session.bridge.stations.values.joinToString("\n") { station ->
                        "${station.callsign}  ${"%.5f".format(station.latitude)}, ${"%.5f".format(station.longitude)}  ${station.sources.joinToString("+")}\n${station.comment}"
                    }
                }
            }
        }
        callsign.setText(Session.bridge.callsign)
        callsign.setOnFocusChangeListener { _, _ ->
            val parts = callsign.text.toString().trim().uppercase().split("-")
            Session.bridge.callsign = parts.firstOrNull().orEmpty()
            Session.bridge.ssid = parts.getOrNull(1)?.toIntOrNull() ?: 0
        }
        findViewById<Button>(R.id.share).setOnClickListener { sharePackage() }
        findViewById<Button>(R.id.scan).setOnClickListener { ensureScan() }
        findViewById<Button>(R.id.spp).setOnClickListener {
            val device = radio.bonded().firstOrNull()
            if (device == null) log.text = "No bonded radio. Pair it in Android settings, or use BLE."
            else radio.connectSpp(device)
        }
        startService(Intent(this, BridgeService::class.java))
        Session.listener?.invoke()
    }

    private fun ensureScan() {
        val needed = mutableListOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
        if (Build.VERSION.SDK_INT < 31) needed += Manifest.permission.ACCESS_FINE_LOCATION
        val missing = needed.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) radio.scanBle() else permissionLauncher.launch(missing.toTypedArray())
    }

    private fun sharePackage() {
        val file = File(cacheDir, "OpenUVBridge-ATAK.zip")
        file.writeBytes(BridgeCore.dataPackage())
        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }, "Add to ATAK"))
    }
}
