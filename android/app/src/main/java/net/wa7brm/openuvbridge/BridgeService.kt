// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.IBinder
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import javax.net.ssl.SSLSocketFactory
import kotlin.concurrent.thread

/** Loopback TAK server plus the optional upstream socket. ATAK only sees the loopback port. */
class BridgeService : Service() {
    private var server: ServerSocket? = null
    private var upstream: Socket? = null
    @Volatile private var running = true

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("bridge", "Open UV Bridge", NotificationManager.IMPORTANCE_LOW))
        val notification = Notification.Builder(this, "bridge")
            .setContentTitle("Open UV Bridge")
            .setContentText("ATAK on ${BridgeCore.connectString()}")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(1, notification)
        }
        watchPath()
        if (server == null) listen()
        if (upstream == null) maintainUpstream()
        return START_STICKY
    }

    private fun watchPath() {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        connectivity.registerNetworkCallback(
            NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    Session.bridge.pathUp = true
                    Session.listener?.invoke()
                }

                override fun onLost(network: Network) {
                    Session.bridge.pathUp = false
                    Session.bridge.serverUp = false
                    upstream?.close()
                    Session.listener?.invoke()
                }
            },
        )
    }

    private fun listen() {
        thread(name = "uv-bridge-tak", isDaemon = true) {
            val bound = ServerSocket(BridgeCore.localPort, 4, InetAddress.getByName(BridgeCore.localHost))
            server = bound
            while (running && !bound.isClosed) {
                val client = bound.accept()
                Session.clients.add(client)
                thread(isDaemon = true) { drain(client) }
            }
        }
    }

    private fun drain(client: Socket) {
        try {
            val buffer = ByteArray(4096)
            while (running && !client.isClosed) {
                val n = client.getInputStream().read(buffer)
                if (n < 0) break
            }
        } catch (_: Exception) {
        } finally {
            Session.clients.remove(client)
            client.close()
        }
    }

    private fun maintainUpstream() {
        thread(name = "uv-bridge-upstream", isDaemon = true) {
            var delay = 1_000L
            while (running) {
                val host = Session.bridge.upstreamHost
                if (!Session.bridge.pathUp || host.isBlank()) {
                    Thread.sleep(1_000)
                    delay = 1_000
                    continue
                }
                try {
                    val socket = if (Session.bridge.upstreamTls) {
                        SSLSocketFactory.getDefault().createSocket() as Socket
                    } else {
                        Socket()
                    }
                    socket.connect(InetSocketAddress(host, Session.bridge.upstreamPort), 8_000)
                    upstream = socket
                    Session.bridge.serverUp = true
                    delay = 1_000
                    for (xml in Session.bridge.flushUpstream()) {
                        socket.getOutputStream().write(xml.toByteArray())
                    }
                    val buffer = ByteArray(8192)
                    while (running && !socket.isClosed) {
                        val n = socket.getInputStream().read(buffer)
                        if (n < 0) break
                    }
                } catch (_: Exception) {
                    Session.bridge.serverUp = false
                    Thread.sleep(delay)
                    delay = minOf(delay * 2, 60_000)
                }
            }
        }
    }

    override fun onDestroy() {
        running = false
        server?.close()
        upstream?.close()
        super.onDestroy()
    }
}
