// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import java.io.InputStream
import java.util.UUID
import kotlin.concurrent.thread

/**
 * BLE KISS first. If the radio does not offer the open GATT service, Android
 * falls back to Bluetooth Classic SPP, which iOS cannot use.
 */
class RadioHub(private val context: Context, private val onFrame: (ByteArray) -> Unit, private val onStatus: (String) -> Unit) {
    private val spp = UUID.fromString(OnAir.sppUuid)
    private val service = UUID.fromString(BridgeCore.kissService)
    private val txUuid = UUID.fromString("00000002-ba2a-46c9-ae49-01b0961f68bb")
    private val rxUuid = UUID.fromString("00000003-ba2a-46c9-ae49-01b0961f68bb")
    private val cccd = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    private var gatt: BluetoothGatt? = null
    private var tx: BluetoothGattCharacteristic? = null
    private var socket: BluetoothSocket? = null
    private val bleStream = OnAir.KissStream()
    private val writes = ArrayDeque<ByteArray>()
    private var writing = false
    private var triedSpp = false
    @Volatile private var sppRunning = false

    val found = LinkedHashMap<String, BluetoothDevice>()

    @SuppressLint("MissingPermission")
    fun scanBle() {
        val scanner = context.getSystemService(BluetoothManager::class.java)?.adapter?.bluetoothLeScanner
        if (scanner == null) {
            onStatus("Bluetooth is off")
            return
        }
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(service)).build()
        scanner.startScan(listOf(filter), ScanSettings.Builder().build(), object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                found[result.device.address] = result.device
                onStatus("BLE ${result.device.name ?: "KISS TNC"} ${result.rssi} dBm")
            }
        })
        onStatus("Looking for a BLE KISS TNC")
    }

    @SuppressLint("MissingPermission")
    fun connect(device: BluetoothDevice) {
        close()
        triedSpp = false
        onStatus("Connecting BLE to ${device.name ?: device.address}")
        gatt = device.connectGatt(context, false, callback)
    }

    @SuppressLint("MissingPermission")
    fun connectSpp(device: BluetoothDevice) {
        close()
        onStatus("Classic SPP to ${device.name ?: device.address}")
        thread(name = "uv-spp", isDaemon = true) {
            try {
                val link = device.createInsecureRfcommSocketToServiceRecord(spp)
                link.connect()
                socket = link
                sppRunning = true
                onStatus("SPP KISS connected")
                readLoop(link.inputStream)
            } catch (error: Exception) {
                onStatus("SPP failed: ${error.message}. Quit the radio's own app and try again.")
            }
        }
    }

    fun bonded(): List<BluetoothDevice> {
        val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter ?: return emptyList()
        return adapter.bondedDevices?.toList().orEmpty()
    }

    @SuppressLint("MissingPermission")
    fun write(frame: ByteArray) {
        val characteristic = tx
        val link = gatt
        if (characteristic != null && link != null) {
            var offset = 0
            while (offset < frame.size) {
                val end = minOf(offset + 20, frame.size)
                writes.addLast(frame.copyOfRange(offset, end))
                offset = end
            }
            pump()
            return
        }
        socket?.outputStream?.write(frame)
    }

    @SuppressLint("MissingPermission")
    private fun pump() {
        if (writing) return
        val next = writes.removeFirstOrNull() ?: return
        val characteristic = tx ?: return
        val link = gatt ?: return
        writing = true
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = next
        link.writeCharacteristic(characteristic)
    }

    fun close() {
        sppRunning = false
        gatt?.close()
        gatt = null
        tx = null
        socket?.close()
        socket = null
    }

    private fun readLoop(input: InputStream) {
        val stream = OnAir.KissStream()
        val buf = ByteArray(256)
        while (sppRunning) {
            val n = input.read(buf)
            if (n < 0) break
            stream.append(buf.copyOf(n)).forEach(onFrame)
        }
    }

    private val callback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                gatt.discoverServices()
            } else if (newState == BluetoothGatt.STATE_DISCONNECTED && !triedSpp) {
                triedSpp = true
                onStatus("BLE dropped. Trying Classic SPP.")
                connectSpp(gatt.device)
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val kiss = gatt.getService(service)
            if (kiss == null) {
                triedSpp = true
                onStatus("No BLE KISS service. Trying Classic SPP.")
                val device = gatt.device
                gatt.close()
                connectSpp(device)
                return
            }
            val rx = kiss.getCharacteristic(rxUuid)
            tx = kiss.getCharacteristic(txUuid)
            if (rx != null) {
                gatt.setCharacteristicNotification(rx, true)
                val descriptor = rx.getDescriptor(cccd)
                descriptor?.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                if (descriptor != null) gatt.writeDescriptor(descriptor)
            }
            onStatus(if (tx != null) "BLE KISS connected" else "KISS transmit characteristic missing")
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            val value = characteristic.value ?: return
            bleStream.append(value).forEach(onFrame)
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            writing = false
            pump()
        }
    }
}
