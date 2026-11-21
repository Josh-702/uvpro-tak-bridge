// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Classic SmartBeaconing: faster when moving, plus a corner peg.
/// Speeds are knots. `turnSlope` is added as degrees per knot
/// (`threshold = minTurn + slope / speed`).
public struct SmartBeaconConfig: Equatable, Codable {
    public var fastSpeedKnots: Double
    public var fastRate: TimeInterval
    public var slowSpeedKnots: Double
    public var slowRate: TimeInterval
    public var minTurnDegrees: Double
    public var turnSlope: Double
    public var minTurnTime: TimeInterval
    public var minInterval: TimeInterval
    public var maxInterval: TimeInterval

    public init(
        fastSpeedKnots: Double = 60,
        fastRate: TimeInterval = 60,
        slowSpeedKnots: Double = 5,
        slowRate: TimeInterval = 1200,
        minTurnDegrees: Double = 30,
        turnSlope: Double = 240,
        minTurnTime: TimeInterval = 15,
        minInterval: TimeInterval = 30,
        maxInterval: TimeInterval = 1800
    ) {
        self.fastSpeedKnots = fastSpeedKnots
        self.fastRate = fastRate
        self.slowSpeedKnots = slowSpeedKnots
        self.slowRate = slowRate
        self.minTurnDegrees = minTurnDegrees
        self.turnSlope = turnSlope
        self.minTurnTime = minTurnTime
        self.minInterval = minInterval
        self.maxInterval = maxInterval
    }

    public func interval(speedKnots: Double) -> TimeInterval {
        let speed = max(0, speedKnots)
        let slow = min(slowSpeedKnots, fastSpeedKnots)
        let fast = max(slowSpeedKnots, fastSpeedKnots)
        let long = max(slowRate, fastRate)
        let short = min(slowRate, fastRate)
        if speed <= slow { return min(maxInterval, max(minInterval, long)) }
        if speed >= fast { return min(maxInterval, max(minInterval, short)) }
        let span = fast - slow
        let fraction = span == 0 ? 1 : (speed - slow) / span
        let value = long + (short - long) * fraction
        return min(maxInterval, max(minInterval, value))
    }

    public func turnThreshold(speedKnots: Double) -> Double {
        let speed = max(speedKnots, 1)
        return minTurnDegrees + turnSlope / speed
    }
}

public struct SmartBeaconDecision: Equatable {
    public var shouldBeacon: Bool
    public var reason: String
}

public enum SmartBeacon {
    public static func decide(
        config: SmartBeaconConfig,
        now: Date,
        lastBeacon: Date?,
        speedKnots: Double,
        courseDegrees: Double?,
        lastCourseDegrees: Double?
    ) -> SmartBeaconDecision {
        guard let lastBeacon else {
            return SmartBeaconDecision(shouldBeacon: true, reason: "first fix")
        }
        let elapsed = now.timeIntervalSince(lastBeacon)
        if elapsed < config.minInterval {
            return SmartBeaconDecision(shouldBeacon: false, reason: "min interval")
        }
        if let courseDegrees, let lastCourseDegrees, elapsed >= config.minTurnTime {
            let delta = angleDelta(courseDegrees, lastCourseDegrees)
            let threshold = config.turnThreshold(speedKnots: speedKnots)
            if delta >= threshold {
                return SmartBeaconDecision(shouldBeacon: true, reason: "corner")
            }
        }
        if elapsed >= config.interval(speedKnots: speedKnots) {
            return SmartBeaconDecision(shouldBeacon: true, reason: "timer")
        }
        return SmartBeaconDecision(shouldBeacon: false, reason: "waiting")
    }

    public static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var delta = abs(a - b).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta = 360 - delta }
        return delta
    }
}
