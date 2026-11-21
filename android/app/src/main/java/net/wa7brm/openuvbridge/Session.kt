// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import java.net.Socket
import java.util.Collections

object Session {
    val bridge = RadioBridge()
    val clients = Collections.synchronizedList(ArrayList<Socket>())
    @Volatile var listener: (() -> Unit)? = null

    fun publish(xml: String?) {
        if (xml != null) {
            val bytes = xml.toByteArray()
            val dead = ArrayList<Socket>()
            for (client in clients) {
                try {
                    client.getOutputStream().write(bytes)
                    client.getOutputStream().flush()
                } catch (_: Exception) {
                    dead.add(client)
                }
            }
            clients.removeAll(dead.toSet())
        }
        listener?.invoke()
    }
}
