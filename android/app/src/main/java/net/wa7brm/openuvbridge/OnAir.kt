// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

package net.wa7brm.openuvbridge

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * On-air APRS and CoT mapping. This is the Android half of the contract in
 * testdata/on-air-vectors.json. The Swift package is the other half.
 */
object OnAir {
    const val fend = 0xC0.toByte()
    const val fesc = 0xDB.toByte()
    const val tfend = 0xDC.toByte()
    const val tfesc = 0xDD.toByte()
    const val sppUuid = "00001101-0000-1000-8000-00805F9B34FB"

    data class Address(val call: String, val ssid: Int = 0, val repeated: Boolean = false) {
        val display: String get() = if (ssid == 0) call else "$call-$ssid"
    }

    data class Ax25(
        val destination: Address,
        val source: Address,
        val digipeaters: List<Address>,
        val info: ByteArray,
    )

    data class Position(
        val latitude: Double,
        val longitude: Double,
        val symbolTable: String,
        val symbol: String,
        val comment: String,
    )

    data class MiceHeader(
        val latitude: Double,
        val message: String,
        val west: Boolean,
        val longitudeOffset100: Boolean,
    )

    fun hexDecode(text: String): ByteArray {
        val clean = text.filter { !it.isWhitespace() }
        return ByteArray(clean.length / 2) { i ->
            clean.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }

    fun hexEncode(data: ByteArray): String = data.joinToString("") { "%02X".format(it.toInt() and 0xFF) }

    fun kissEncode(payload: ByteArray): ByteArray {
        val out = ArrayList<Byte>(payload.size + 8)
        out.add(fend)
        out.add(0)
        for (byte in payload) {
            when (byte) {
                fend -> { out.add(fesc); out.add(tfend) }
                fesc -> { out.add(fesc); out.add(tfesc) }
                else -> out.add(byte)
            }
        }
        out.add(fend)
        return out.toByteArray()
    }

    fun kissDecode(frame: ByteArray): ByteArray? {
        val frames = KissStream().append(frame)
        return frames.firstOrNull()
    }

    class KissStream {
        private val buffer = ArrayList<Byte>()
        private var inFrame = false
        private var escaped = false

        fun append(data: ByteArray): List<ByteArray> {
            val frames = ArrayList<ByteArray>()
            for (byte in data) {
                if (byte == fend) {
                    if (inFrame && buffer.isNotEmpty()) frames.add(buffer.toByteArray())
                    buffer.clear()
                    inFrame = true
                    escaped = false
                    continue
                }
                if (!inFrame) continue
                if (escaped) {
                    if (byte == tfend) buffer.add(fend)
                    else if (byte == tfesc) buffer.add(fesc)
                    escaped = false
                } else if (byte == fesc) {
                    escaped = true
                } else {
                    buffer.add(byte)
                }
            }
            return frames.map { bytes ->
                if (bytes.isEmpty()) bytes else bytes.copyOfRange(1, bytes.size)
            }
        }
    }

    fun ax25Decode(data: ByteArray): Ax25? {
        var index = 0
        val addresses = ArrayList<Address>()
        var sawLast = false
        while (addresses.size < 10 && index + 7 <= data.size) {
            val address = decodeAddress(data, index) ?: return null
            addresses.add(address)
            val last = data[index + 6].toInt() and 0x01 != 0
            index += 7
            if (last) {
                sawLast = true
                break
            }
        }
        if (!sawLast || addresses.size < 2 || index + 2 > data.size) return null
        val info = data.copyOfRange(index + 2, data.size)
        return Ax25(addresses[0], addresses[1], addresses.drop(2), info)
    }

    fun ax25Encode(frame: Ax25): ByteArray {
        val all = listOf(frame.destination, frame.source) + frame.digipeaters
        val out = ArrayList<Byte>()
        all.forEachIndexed { i, address ->
            out.addAll(encodeAddress(address, i == all.lastIndex).toList())
        }
        out.add(0x03)
        out.add(0xF0.toByte())
        out.addAll(frame.info.toList())
        return out.toByteArray()
    }

    fun digipeaters(path: String): List<Address>? {
        val trimmed = path.trim()
        if (trimmed.isEmpty()) return emptyList()
        return trimmed.split(",").map { raw ->
            val piece = raw.trim()
            val parts = piece.split("-")
            if (parts.size > 2) return null
            val call = parts[0].uppercase()
            if (call.length !in 1..6 || call.any { !it.isLetterOrDigit() }) return null
            val ssid = if (parts.size == 2) parts[1].toIntOrNull()?.takeIf { it in 0..15 } ?: return null else 0
            Address(call, ssid)
        }
    }

    fun uncompressed(
        latitude: Double,
        longitude: Double,
        symbolTable: Char = '/',
        symbol: Char = '[',
        comment: String = "",
        messaging: Boolean = true,
    ): String? {
        val lat = formatHalf(latitude, 2, "N", "S")
        val lon = formatHalf(longitude, 3, "E", "W")
        return (if (messaging) "=" else "!") + lat + symbolTable + lon + symbol + ascii(comment)
    }

    fun message(addressee: String, body: String, id: String?): String? {
        if (body.length > 67) return null
        val padded = pad(addressee) ?: return null
        val cleanId = id?.filter { it.isLetterOrDigit() }
        if (id != null && (cleanId == null || cleanId.length !in 1..5)) return null
        return ":$padded:${ascii(body)}" + (cleanId?.let { "{$it" } ?: "")
    }

    fun ack(addressee: String, id: String): String? {
        val padded = pad(addressee) ?: return null
        val clean = id.filter { it.isLetterOrDigit() }
        if (clean.length !in 1..5) return null
        return ":$padded:ack$clean"
    }

    fun `object`(
        name: String,
        latitude: Double,
        longitude: Double,
        comment: String,
        timestampUnix: Long,
    ): String? {
        val trimmed = ascii(name).take(9)
        if (trimmed.isEmpty()) return null
        val padded = trimmed.padEnd(9, ' ')
        val stamp = formatDhm(timestampUnix)
        return ";" + padded + "*" + stamp + formatHalf(latitude, 2, "N", "S") +
            "/" + formatHalf(longitude, 3, "E", "W") + "-" + ascii(comment)
    }

    fun parseUncompressed(info: String): Position? {
        if (info.length < 20 || (info[0] != '!' && info[0] != '=')) return null
        val lat = parseHalf(info.substring(1, 9), 2) ?: return null
        val lon = parseHalf(info.substring(10, 19), 3) ?: return null
        return Position(lat, lon, info.substring(9, 10), info.substring(19, 20), info.substring(20))
    }

    fun cotType(symbol: String): String = when (symbol.firstOrNull()) {
        '[', 'b' -> "a-f-G-U-C-I"
        '>', 'k', 'j', 'v', '<' -> "a-f-G-E-V-C"
        's', 'Y' -> "a-f-S"
        '^', 'O', '\'' -> "a-f-A"
        '-', 'r' -> "a-f-G-I"
        else -> "a-f-G-U-C"
    }

    fun stationUid(base: String, ssid: Int): String = "APRS-${if (ssid == 0) base.uppercase() else "${base.uppercase()}-$ssid"}"

    fun objectUid(name: String): String {
        val cleaned = name.uppercase().filter { it.isLetterOrDigit() || it == '-' }
        return "APRS-OBJ-" + if (cleaned.isEmpty()) "OBJECT" else cleaned
    }

    fun positionCot(
        position: Position,
        callsign: String,
        uid: String,
        timeUnix: Long,
        staleSeconds: Long,
        txid: String,
    ): String {
        val time = cotTime(timeUnix)
        val stale = cotTime(timeUnix + staleSeconds)
        val type = cotType(position.symbol)
        return """<?xml version="1.0" encoding="UTF-8"?><event version="2.0" uid="${esc(uid)}" type="$type" time="$time" start="$time" stale="$stale" how="m-g"><point lat="${num(position.latitude)}" lon="${num(position.longitude)}" hae="9999999.0" ce="9999999.0" le="9999999.0"/><detail><contact callsign="${esc(callsign)}"/><remarks>${esc(position.comment)}</remarks><uvbridge origin="rf" sources="rf" txid="${esc(txid)}"/></detail></event>"""
    }

    fun chatCot(
        from: String,
        fromUid: String,
        to: String,
        toUid: String,
        text: String,
        messageId: String,
        latitude: Double,
        longitude: Double,
        timeUnix: Long,
        staleSeconds: Long,
    ): String {
        val time = cotTime(timeUnix)
        val stale = cotTime(timeUnix + staleSeconds)
        val uid = "GeoChat.$fromUid.$toUid.$messageId"
        return """<?xml version="1.0" encoding="UTF-8"?><event version="2.0" uid="${esc(uid)}" type="b-t-f" time="$time" start="$time" stale="$stale" how="h-g-i-g-o"><point lat="${num(latitude)}" lon="${num(longitude)}" hae="9999999.0" ce="9999999.0" le="9999999.0"/><detail><contact callsign="${esc(from)}"/><remarks>${esc(text)}</remarks><__chat id="${esc(toUid)}" chatroom="${esc(to)}" senderCallsign="${esc(from)}" groupOwner="false"><chatgrp id="${esc(toUid)}" uid0="${esc(fromUid)}" uid1="${esc(toUid)}"/></__chat><link uid="${esc(fromUid)}" type="b-t-f" relation="p-p"/><uvbridge origin="rf" sources="rf" txid="msg-${esc(fromUid)}-$messageId"/></detail></event>"""
    }

    fun decodeMice(destination: String): MiceHeader? {
        val bytes = destination.uppercase().encodeToByteArray()
        if (bytes.size != 6) return null
        val digits = IntArray(6)
        val flags = BooleanArray(6)
        for (i in 0..5) {
            val part = miceChar(bytes[i].toInt() and 0xFF) ?: return null
            digits[i] = part.first
            flags[i] = part.second
        }
        val degrees = digits[0] * 10 + digits[1]
        val minutes = digits[2] * 10 + digits[3]
        val hundredths = digits[4] * 10 + digits[5]
        if (degrees > 90 || minutes >= 60 || hundredths >= 100) return null
        var latitude = degrees + (minutes + hundredths / 100.0) / 60.0
        if (!flags[3]) latitude = -latitude
        val bits = booleanArrayOf(flags[0], flags[1], flags[2])
        val value = (if (bits[0]) 4 else 0) + (if (bits[1]) 2 else 0) + (if (bits[2]) 1 else 0)
        val names = arrayOf("Emergency", "Priority", "Special", "Committed", "Returning", "In Service", "En Route", "Off Duty")
        return MiceHeader(latitude, names[value], flags[5], flags[4])
    }

    fun beaconFrame(source: String, ssid: Int, info: String, path: String): ByteArray? {
        val digis = digipeaters(path) ?: return null
        val frame = Ax25(Address("APRS"), Address(source.uppercase(), ssid), digis, info.encodeToByteArray())
        return kissEncode(ax25Encode(frame))
    }

    private fun miceChar(byte: Int): Pair<Int, Boolean>? = when (byte) {
        in 48..57 -> (byte - 48) to false
        in 65..74 -> (byte - 65) to true
        75 -> 0 to true
        76 -> 0 to false
        in 80..89 -> (byte - 80) to true
        90 -> 0 to true
        else -> null
    }

    private fun pad(addressee: String): String? {
        val value = addressee.trim().uppercase()
        if (value.length !in 1..9) return null
        if (value.any { !(it.isLetterOrDigit() || it == '-') }) return null
        return value.padEnd(9, ' ')
    }

    private fun formatHalf(value: Double, width: Int, positive: String, negative: String): String {
        val hemisphere = if (value < 0) negative else positive
        var degrees = abs(value).toInt()
        var hundredths = ((abs(value) - degrees) * 6000.0).roundToInt()
        if (hundredths >= 6000) {
            hundredths -= 6000
            degrees += 1
        }
        val cap = if (width == 2) 90 else 180
        if (degrees > cap) {
            degrees = cap
            hundredths = 0
        }
        if (degrees == cap) hundredths = 0
        val minutes = hundredths / 100
        val frac = hundredths % 100
        return "%0${width}d%02d.%02d%s".format(Locale.US, degrees, minutes, frac, hemisphere)
    }

    private fun parseHalf(text: String, degreeDigits: Int): Double? {
        if (text.length != degreeDigits + 6) return null
        val hemi = text.last()
        val sign = when (hemi) {
            'N', 'E' -> 1.0
            'S', 'W' -> -1.0
            else -> return null
        }
        val degrees = text.substring(0, degreeDigits).toIntOrNull() ?: return null
        val minutes = text.substring(degreeDigits, degreeDigits + 2).toIntOrNull() ?: return null
        val hundredths = text.substring(degreeDigits + 3, degreeDigits + 5).toIntOrNull() ?: return null
        if (minutes >= 60 || hundredths >= 100) return null
        return sign * (degrees + (minutes + hundredths / 100.0) / 60.0)
    }

    private fun formatDhm(epochSeconds: Long): String {
        val zoned = Instant.ofEpochSecond(epochSeconds).atZone(ZoneOffset.UTC)
        return "%02d%02d%02dz".format(Locale.US, zoned.dayOfMonth, zoned.hour, zoned.minute)
    }

    private fun cotTime(epochSeconds: Long): String =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
            .withZone(ZoneOffset.UTC)
            .format(Instant.ofEpochSecond(epochSeconds))

    private fun num(value: Double): String = "%.6f".format(Locale.US, value)

    private fun esc(text: String): String = text
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;")

    private fun ascii(text: String): String = text.filter { it.code in 0x20..0x7E }

    private fun decodeAddress(data: ByteArray, index: Int): Address? {
        val chars = ArrayList<Char>()
        for (offset in 0..5) {
            val raw = (data[index + offset].toInt() and 0xFF) shr 1
            if (raw != 0x20) chars.add(raw.toChar())
        }
        if (chars.isEmpty()) return null
        val ssidByte = data[index + 6].toInt() and 0xFF
        return Address(chars.joinToString(""), (ssidByte shr 1) and 0x0F, ssidByte and 0x80 != 0)
    }

    private fun encodeAddress(address: Address, isLast: Boolean): ByteArray {
        val out = ByteArray(7)
        val call = address.call.uppercase()
        for (i in 0..5) {
            val c = if (i < call.length) call[i].code else 0x20
            out[i] = (c shl 1).toByte()
        }
        var ssid = 0x60 or ((address.ssid and 0x0F) shl 1)
        if (address.repeated) ssid = ssid or 0x80
        if (isLast) ssid = ssid or 0x01
        out[6] = ssid.toByte()
        return out
    }
}

data class Station(
    val uid: String,
    var callsign: String,
    var latitude: Double,
    var longitude: Double,
    var comment: String,
    var cotType: String,
    val sources: MutableSet<String> = mutableSetOf(),
)

/**
 * Same routing rules as the Swift bridge: one local picture, a queue for the
 * operator's server, and a Part 97 check before anything is handed to the radio.
 */
class RadioBridge {
    var callsign: String = ""
    var ssid: Int = 0
    var upstreamHost: String = ""
    var upstreamPort: Int = 8089
    var upstreamTls: Boolean = true
    var pathUp: Boolean = false
    var serverUp: Boolean = false
    var allowThirdParty: Boolean = false
    var mirrorServer: Boolean = false
    val stations = LinkedHashMap<String, Station>()
    val upstreamQueue = ArrayList<String>()
    val txLog = ArrayList<String>()

    fun mode(): BridgeCore.LinkMode = BridgeCore.mode(pathUp, upstreamHost.isNotBlank(), serverUp)

    fun ingest(frame: OnAir.Ax25, nowUnix: Long): String? {
        val info = frame.info.toString(Charsets.US_ASCII)
        val position = OnAir.parseUncompressed(info) ?: return null
        if (frame.source.call.equals(callsign.trim(), true) && frame.source.ssid == ssid && callsign.isNotBlank()) {
            return null
        }
        val uid = OnAir.stationUid(frame.source.call, frame.source.ssid)
        val existing = stations[uid]
        val station = existing ?: Station(uid, frame.source.display, position.latitude, position.longitude, position.comment, OnAir.cotType(position.symbol))
        station.callsign = frame.source.display
        station.latitude = position.latitude
        station.longitude = position.longitude
        station.comment = position.comment
        station.cotType = OnAir.cotType(position.symbol)
        station.sources.add("rf")
        stations[uid] = station
        val xml = OnAir.positionCot(position, station.callsign, uid, nowUnix, 1800, "rf-$uid-$nowUnix")
        if (upstreamHost.isNotBlank() && !(pathUp && serverUp)) upstreamQueue.add(xml)
        return xml
    }

    fun noteServerStation(uid: String, callsign: String, latitude: Double, longitude: Double, comment: String, type: String) {
        val existing = stations[uid]
        if (existing == null && !mirrorServer) return
        val row = existing ?: Station(uid, callsign, latitude, longitude, comment, type)
        row.callsign = callsign.ifEmpty { row.callsign }
        row.latitude = latitude
        row.longitude = longitude
        if (comment.isNotEmpty()) row.comment = comment
        row.cotType = type
        row.sources.add("server")
        stations[uid] = row
    }

    fun operatorMessage(to: String, body: String): String? {
        val refusal = BridgeCore.transmitAllowed(callsign, encrypted = false, thirdParty = false, allowThirdParty = allowThirdParty)
        if (refusal != null) return refusal
        val info = OnAir.message(to, body, "01") ?: return "messageTooLong"
        val kiss = OnAir.beaconFrame(callsign, ssid, info, "WIDE1-1,WIDE2-1") ?: return "invalidPath"
        txLog.add(OnAir.hexEncode(kiss))
        return null
    }

    fun flushUpstream(): List<String> {
        if (!(pathUp && serverUp)) return emptyList()
        val copy = upstreamQueue.toList()
        upstreamQueue.clear()
        return copy
    }
}
