import Foundation

struct LidMotionIntent {
    private(set) var lastMovedDownTime: TimeInterval = -Double.greatestFiniteMagnitude

    mutating func update(
        angularVelocity: Double,
        at now: TimeInterval,
        closingSpeed: Double,
        openingSpeed: Double
    ) {
        if angularVelocity >= openingSpeed {
            // Opening is an intentional reversal, so an earlier close must not
            // be reused to start the effect again near the threshold.
            lastMovedDownTime = -Double.greatestFiniteMagnitude
        } else if angularVelocity <= -closingSpeed {
            lastMovedDownTime = now
        }
    }

    func wasClosingRecently(at now: TimeInterval, memoryDuration: TimeInterval) -> Bool {
        now - lastMovedDownTime < memoryDuration
    }

    mutating func reset() {
        lastMovedDownTime = -Double.greatestFiniteMagnitude
    }
}

/// How long the lid has stayed opened back above the start angle.
struct LidOpenDwell {
    private(set) var since: TimeInterval?

    mutating func update(angle: Double, at now: TimeInterval, dwellAngle: Double) {
        if angle >= dwellAngle {
            if since == nil { since = now }
        } else {
            since = nil
        }
    }

    func hasDwelled(at now: TimeInterval, duration: TimeInterval) -> Bool {
        guard let since else { return false }
        return now - since >= duration
    }

    mutating func reset() {
        since = nil
    }
}

struct LidEffectPolicy {
    let threshold: Double
    let hysteresis: Double

    /// Whether a lid rising through the effect zone with nothing showing may
    /// start a run of its own and play the effect in reverse.
    var playsOnOpen: Bool = false

    /// A lid held at or above this angle has been opened again, even when
    /// threshold + hysteresis is past what the hinge can reach. The threshold
    /// itself, so a hinge whose limit rounds to the threshold still releases.
    var dwellAngle: Double { threshold }

    /// How far the lid must have risen above its lowest reading of the run
    /// before opening speed alone releases the effect. A sensor that reports
    /// whole degrees moves in 1° steps, and one step over a sensor refresh
    /// already reads as fast opening. A lid resting on a half-degree boundary
    /// alternates between two readings, and this keeps that from flapping the
    /// effect on and off.
    static let minimumReleaseRise: Double = 1.5

    /// How far the lid must have risen from its lowest resting reading before
    /// an opening run starts. Tilting the screen up a couple of degrees to
    /// suit the seat must not play the effect; opening a lid moves much
    /// further, so the run starts a few degrees into the rise.
    static let minimumOpenStartRise: Double = 8

    /// How far below the start angle the lid must still be for an opening run
    /// to be worth starting. Any nearer and there is nothing left to animate.
    static let minimumOpenStartDrop: Double = 10

    func wantsEffect(
        isEnabled: Bool,
        isActive: Bool,
        angle: Double,
        predictedAngle: Double,
        riseSinceLowest: Double,
        riseSinceIdleLow: Double,
        hasBeenAboveThreshold: Bool,
        wasClosingRecently: Bool,
        isClearlyOpening: Bool,
        hasDwelledOpen: Bool,
        minimumDurationElapsed: Bool
    ) -> Bool {
        guard isEnabled else { return false }

        if isActive {
            // Deliberately opening back across the configured start angle is
            // sufficient to recover even when threshold + hysteresis cannot
            // be reached by the hardware. The rise rules out a single
            // whole-degree step; a smaller opening releases through the dwell.
            if isClearlyOpening, angle >= threshold, riseSinceLowest >= Self.minimumReleaseRise {
                return false
            }

            // An opening slower than that still ends with the lid held above
            // the start angle, which releases it too.
            if hasDwelledOpen { return false }

            // Keep the ordinary release hysteresis for stationary readings and
            // sensor jitter around the start angle.
            guard minimumDurationElapsed else { return true }
            return angle < threshold + hysteresis
        }

        // A lid rising through the effect zone with no run of its own plays
        // the effect in reverse, so opening it looks like closing it backwards.
        // This is the only path for a close macOS slept through, and it also
        // picks up a run the timeout ended early.
        if playsOnOpen,
           isClearlyOpening,
           angle <= threshold - Self.minimumOpenStartDrop,
           riseSinceIdleLow >= Self.minimumOpenStartRise {
            return true
        }

        // A resting or opening lid below the threshold must not start the
        // effect, including while an older closing observation is remembered.
        return hasBeenAboveThreshold
            && wasClosingRecently
            && !isClearlyOpening
            && predictedAngle <= threshold
    }
}
