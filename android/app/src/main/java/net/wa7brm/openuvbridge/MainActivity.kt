// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.ParcelUuid
import android.view.View
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID

class MainActivity : AppCompatActivity() {
    private lateinit var status: TextView
    private lateinit var stations: TextView
    private lateinit var log: TextView
    private val lines = ArrayList<String>()

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { scan() }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.device.name ?: "KISS TNC"
            note("Heard $name ${result.rssi} dBm")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        status = findViewById(R.id.status)
        stations = findViewById(R.id.stations)
        log = findViewById(R.id.log)
        val mode = BridgeCore.mode(pathUp = false, serverConfigured = false, serverUp = false)
        status.text = BridgeCore.modeSummary(mode)
        stations.text = "No stations yet. Connect a BLE KISS radio, or wait for your TAK server while you are online."
        findViewById<View>(R.id.share).setOnClickListener { sharePackage() }
        findViewById<View>(R.id.scan).setOnClickListener { ensureScan() }
        startService(Intent(this, BridgeService::class.java))
    }

    private fun ensureScan() {
        val needed = mutableListOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
        if (Build.VERSION.SDK_INT < 31) {
            needed += Manifest.permission.ACCESS_FINE_LOCATION
        }
        val missing = needed.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) scan() else permissionLauncher.launch(missing.toTypedArray())
    }

    private fun scan() {
        val manager = getSystemService(BluetoothManager::class.java) ?: return
        val scanner = manager.adapter?.bluetoothLeScanner ?: run {
            note("Bluetooth is off")
            return
        }
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(UUID.fromString(BridgeCore.kissService)))
            .build()
        scanner.startScan(listOf(filter), ScanSettings.Builder().build(), scanCallback)
        note("Looking for a KISS TNC")
    }

    private fun sharePackage() {
        val file = File(cacheDir, "OpenUVBridge-ATAK.zip")
        file.writeBytes(BridgeCore.dataPackage())
        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
        val share = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(share, "Add to ATAK"))
    }

    private fun note(line: String) {
        lines.add(0, line)
        log.text = lines.take(12).joinToString("\n")
    }
}
