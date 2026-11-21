// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.zip.ZipInputStream
import java.io.ByteArrayInputStream

class BridgeCoreTest {
    @Test
    fun offlineAndOnlineKeepOneLocalServer() {
        assertEquals(BridgeCore.LinkMode.OFFLINE, BridgeCore.mode(false, true, false))
        assertEquals(BridgeCore.LinkMode.BRIDGING, BridgeCore.mode(true, true, true))
        assertTrue(BridgeCore.modeSummary(BridgeCore.LinkMode.BRIDGING).contains("on-phone server"))
        assertTrue(BridgeCore.modeSummary(BridgeCore.LinkMode.OFFLINE).contains("waits"))
    }

    @Test
    fun part97RefusesBlankCallsignAndEncryption() {
        assertEquals("callsignNotSet", BridgeCore.transmitAllowed("", false, false, false))
        assertEquals("encryptionNotAllowed", BridgeCore.transmitAllowed("WA7BRM", true, false, false))
        assertEquals("thirdParty", BridgeCore.transmitAllowed("WA7BRM", false, true, false))
        assertNull(BridgeCore.transmitAllowed("WA7BRM", false, false, false))
        assertTrue(BridgeCore.validCallsign("WA7BRM"))
        assertFalse(BridgeCore.validCallsign("APRS"))
    }

    @Test
    fun dataPackageIsLoopbackOnly() {
        val zip = BridgeCore.dataPackage()
        val text = ZipInputStream(ByteArrayInputStream(zip)).use { input ->
            val names = mutableListOf<String>()
            var body = ""
            while (true) {
                val entry = input.nextEntry ?: break
                names += entry.name
                body += input.readBytes().decodeToString()
            }
            body to names
        }
        assertTrue(text.first.contains("127.0.0.1:17747:tcp"))
        assertFalse(text.first.contains("8089"))
        assertFalse(text.first.contains("example.test"))
        assertTrue(text.second.contains("prefs/cot_streams.pref"))
    }

    @Test
    fun kissEscapesFrameMarkers() {
        val wrapped = BridgeCore.kissWrap(byteArrayOf(0xC0.toByte(), 0xDB.toByte()))
        assertEquals(0xC0.toByte(), wrapped.first())
        assertEquals(0xC0.toByte(), wrapped.last())
        assertTrue(wrapped.contains(0xDB.toByte()))
    }
}
