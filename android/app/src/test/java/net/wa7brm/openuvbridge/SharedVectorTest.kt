// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SharedVectorTest {
    private val json = JSONObject(
        SharedVectorTest::class.java.getResource("/on-air-vectors.json")!!.readText()
    )

    @Test
    fun capturedFrameAndCotMatchTheSharedFile() {
        val position = json.getJSONObject("position")
        val payload = OnAir.kissDecode(OnAir.hexDecode(position.getString("kissHex")))!!
        val ax = OnAir.ax25Decode(payload)!!
        assertEquals(position.getString("source"), ax.source.display)
        assertEquals(position.getString("info"), ax.info.toString(Charsets.US_ASCII))
        val parsed = OnAir.parseUncompressed(ax.info.toString(Charsets.US_ASCII))!!
        assertEquals(position.getDouble("latitude"), parsed.latitude, 0.0000001)
        assertEquals(position.getDouble("longitude"), parsed.longitude, 0.0000001)
        assertEquals(position.getString("symbol"), parsed.symbol)
        assertEquals(position.getString("comment"), parsed.comment)
        val uid = OnAir.stationUid(ax.source.call, ax.source.ssid)
        assertEquals(position.getString("uid"), uid)
        val xml = OnAir.positionCot(
            parsed,
            ax.source.display,
            uid,
            json.getLong("timeUnix"),
            position.getLong("staleSeconds"),
            position.getString("txid"),
        )
        assertEquals(position.getString("cotType"), OnAir.cotType(parsed.symbol))
        assertEquals(position.getString("cotXml"), xml)
    }

    @Test
    fun builtFramesMatchTheSharedFile() {
        val message = json.getJSONObject("message")
        assertEquals(
            message.getString("info"),
            OnAir.message(message.getString("addressee"), message.getString("body"), message.getString("id")),
        )
        val ack = json.getJSONObject("ack")
        assertEquals(ack.getString("info"), OnAir.ack(ack.getString("addressee"), ack.getString("id")))

        val objectJson = json.getJSONObject("object")
        val latitude = objectJson.getDouble("latitudeDegrees") + objectJson.getDouble("latitudeMinutes") / 60.0
        val longitude = objectJson.getDouble("longitudeDegrees") + objectJson.getDouble("longitudeMinutes") / 60.0
        assertEquals(
            objectJson.getString("info"),
            OnAir.`object`(
                objectJson.getString("name"),
                latitude,
                longitude,
                objectJson.getString("comment"),
                objectJson.getLong("timestampUnix"),
            ),
        )
        assertEquals(objectJson.getString("uid"), OnAir.objectUid(objectJson.getString("name")))

        val beacon = json.getJSONObject("beacon")
        val info = OnAir.uncompressed(
            beacon.getDouble("latitude"),
            beacon.getDouble("longitude"),
            beacon.getString("symbolTable").first(),
            beacon.getString("symbol").first(),
            beacon.getString("comment"),
            beacon.getBoolean("messaging"),
        )
        assertEquals(beacon.getString("info"), info)
        val kiss = OnAir.beaconFrame(beacon.getString("source"), beacon.getInt("ssid"), info!!, beacon.getString("path"))!!
        assertEquals(beacon.getString("kissHex"), OnAir.hexEncode(kiss))
    }

    @Test
    fun chatMiceSymbolsAndUidMatchTheSharedFile() {
        val chat = json.getJSONObject("chat")
        val xml = OnAir.chatCot(
            chat.getString("from"),
            chat.getString("fromUid"),
            chat.getString("to"),
            chat.getString("toUid"),
            chat.getString("text"),
            chat.getString("messageId"),
            chat.getDouble("latitude"),
            chat.getDouble("longitude"),
            json.getLong("timeUnix"),
            chat.getLong("staleSeconds"),
        )
        assertTrue(xml.contains(chat.getString("uid")))
        assertEquals(chat.getString("cotXml"), xml)

        val mice = json.getJSONObject("mice")
        val header = OnAir.decodeMice(mice.getString("destination"))!!
        assertEquals(mice.getDouble("latitude"), header.latitude, 0.0000001)
        assertEquals(mice.getString("message"), header.message)
        assertEquals(mice.getBoolean("west"), header.west)
        assertEquals(mice.getBoolean("longitudeOffset100"), header.longitudeOffset100)

        val symbols = json.getJSONObject("symbols")
        val keys = symbols.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            assertEquals(symbols.getString(key), OnAir.cotType(key))
        }
        val station = json.getJSONObject("stationUid")
        assertEquals(station.getString("uid"), OnAir.stationUid(station.getString("base"), station.getInt("ssid")))
    }

    @Test
    fun serverUpdateDoesNotCreateASecondStation() {
        val bridge = RadioBridge()
        bridge.upstreamHost = "example.test"
        val now = json.getLong("timeUnix")
        val ax = OnAir.ax25Decode(OnAir.kissDecode(OnAir.hexDecode(json.getJSONObject("position").getString("kissHex")))!!)!!
        val first = bridge.ingest(ax, now)
        assertTrue(first!!.contains("APRS-N0CALL"))
        assertEquals(1, bridge.upstreamQueue.size)
        assertEquals(1, bridge.stations.size)
        bridge.noteServerStation("APRS-N0CALL", "N0CALL", 36.5, -115.5, "from server", "a-f-G-U-C")
        assertEquals(1, bridge.stations.size)
        assertTrue(bridge.stations["APRS-N0CALL"]!!.sources.contains("rf"))
        assertTrue(bridge.stations["APRS-N0CALL"]!!.sources.contains("server"))
        assertEquals(36.5, bridge.stations["APRS-N0CALL"]!!.latitude, 0.0001)
        bridge.callsign = ""
        assertEquals("callsignNotSet", bridge.operatorMessage("N0CALL", "hi"))
        assertTrue(bridge.txLog.isEmpty())
    }
}
