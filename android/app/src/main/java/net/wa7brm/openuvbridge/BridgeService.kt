// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

/** Loopback TAK listener so ATAK has one server entry on the phone. */
class BridgeService : Service() {
    private var socket: ServerSocket? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel("bridge", "Open UV Bridge", NotificationManager.IMPORTANCE_LOW)
        manager.createNotificationChannel(channel)
        val notification = Notification.Builder(this, "bridge")
            .setContentTitle("Open UV Bridge")
            .setContentText("ATAK server on ${BridgeCore.connectString()}")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(1, notification)
        }
        if (socket == null) {
            thread(name = "uv-bridge-tak", isDaemon = true) {
                val server = ServerSocket(BridgeCore.localPort, 2, InetAddress.getByName(BridgeCore.localHost))
                socket = server
                while (!server.isClosed) {
                    val client = server.accept()
                    client.close()
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        socket?.close()
        super.onDestroy()
    }
}
