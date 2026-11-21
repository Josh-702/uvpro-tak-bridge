// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Android-side rules that must match the Swift package.
 * The phone's TAK client always uses the loopback endpoint. The operator's
 * own TAK server is optional and is never written into the data package.
 */
object BridgeCore {
    const val name = "Open UV Bridge"
    const val localHost = "127.0.0.1"
    const val localPort = 17747
    const val kissService = "00000001-ba2a-46c9-ae49-01b0961f68bb"

    enum class LinkMode { OFFLINE, ONLINE_LOCAL_ONLY, SERVER_UNREACHABLE, BRIDGING }

    fun mode(pathUp: Boolean, serverConfigured: Boolean, serverUp: Boolean): LinkMode = when {
        !pathUp -> LinkMode.OFFLINE
        !serverConfigured -> LinkMode.ONLINE_LOCAL_ONLY
        serverUp -> LinkMode.BRIDGING
        else -> LinkMode.SERVER_UNREACHABLE
    }

    fun modeSummary(mode: LinkMode): String = when (mode) {
        LinkMode.OFFLINE ->
            "No network. ATAK stays on the on-phone server. APRS is radio to radio, and server traffic waits here."
        LinkMode.ONLINE_LOCAL_ONLY ->
            "The phone is online and no TAK server is configured. ATAK and the radio still work together on this phone."
        LinkMode.SERVER_UNREACHABLE ->
            "The phone has a network path, but your TAK server is not answering. ATAK is unaffected."
        LinkMode.BRIDGING ->
            "Online. ATAK is still using only the on-phone server. RF stations are also bridged to your TAK server."
    }

    fun validCallsign(raw: String): Boolean {
        val value = raw.trim().uppercase()
        if (value.length !in 3..6) return false
        if (!value.all { it.isLetterOrDigit() }) return false
        return value.any { it.isLetter() } && value.any { it.isDigit() }
    }

    /** Amateur RF is never encrypted. A blank callsign cannot transmit. */
    fun transmitAllowed(callsign: String, encrypted: Boolean, thirdParty: Boolean, allowThirdParty: Boolean): String? {
        if (callsign.isBlank()) return "callsignNotSet"
        if (!validCallsign(callsign)) return "invalidCallsign"
        if (encrypted) return "encryptionNotAllowed"
        if (thirdParty && !allowThirdParty) return "thirdParty"
        return null
    }

    fun connectString(host: String = localHost, port: Int = localPort, tls: Boolean = false): String =
        "$host:$port:${if (tls) "ssl" else "tcp"}"

    fun dataPackage(tls: Boolean = false): ByteArray {
        val connect = connectString(tls = tls)
        val pref = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <preferences>
              <preference version="1" name="cot_streams">
                <entry key="count" class="class java.lang.Integer">1</entry>
                <entry key="description0" class="class java.lang.String">Open UV Bridge</entry>
                <entry key="enabled0" class="class java.lang.Boolean">true</entry>
                <entry key="connectString0" class="class java.lang.String">$connect</entry>
                <entry key="useAuth0" class="class java.lang.Boolean">false</entry>
              </preference>
            </preferences>
        """.trimIndent()
        val readme = "Import once. Leave $connect in ATAK. Do not point ATAK at your upstream server."
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            zip.putNextEntry(ZipEntry("prefs/cot_streams.pref"))
            zip.write(pref.toByteArray())
            zip.closeEntry()
            zip.putNextEntry(ZipEntry("readme.txt"))
            zip.write(readme.toByteArray())
            zip.closeEntry()
        }
        return out.toByteArray()
    }

    fun kissWrap(payload: ByteArray): ByteArray {
        val out = ArrayList<Byte>(payload.size + 4)
        out.add(0xC0.toByte())
        out.add(0x00)
        for (byte in payload) {
            if (byte == 0xC0.toByte()) {
                out.add(0xDB.toByte()); out.add(0xDC.toByte())
            } else if (byte == 0xDB.toByte()) {
                out.add(0xDB.toByte()); out.add(0xDD.toByte())
            } else {
                out.add(byte)
            }
        }
        out.add(0xC0.toByte())
        return out.toByteArray()
    }
}
