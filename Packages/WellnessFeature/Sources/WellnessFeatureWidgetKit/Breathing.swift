import ActivityKit
import Foundation

/// Breathing patterns (W-04).
public enum BreathingPattern: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    /// Box breathing: in 4 · hold 4 · out 4 · hold 4.
    case box
    /// 4-7-8: in 4 · hold 7 · out 8.
    case fourSevenEight = "478"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .box: String(localized: "Box breathing")
        case .fourSevenEight: String(localized: "4-7-8 breathing")
        }
    }

    public var shortTitle: String {
        switch self {
        case .box: String(localized: "Box 4-4-4-4")
        case .fourSevenEight: String(localized: "4-7-8")
        }
    }

    /// One cycle's phases with their lengths in seconds.
    public var cycle: [(kind: BreathPhaseKind, seconds: Int)] {
        switch self {
        case .box: [(.inhale, 4), (.holdIn, 4), (.exhale, 4), (.holdOut, 4)]
        case .fourSevenEight: [(.inhale, 4), (.holdIn, 7), (.exhale, 8)]
        }
    }

    public var cycleSeconds: Int { cycle.reduce(0) { $0 + $1.seconds } }
}

public enum BreathPhaseKind: String, Codable, Sendable, Hashable {
    case inhale, holdIn, exhale, holdOut

    public var title: String {
        switch self {
        case .inhale: String(localized: "Breathe in")
        case .holdIn, .holdOut: String(localized: "Hold")
        case .exhale: String(localized: "Breathe out")
        }
    }
}

/// Session lengths offered in the app.
public enum BreathingDuration: Int, CaseIterable, Codable, Sendable, Identifiable {
    case three = 3, five = 5, ten = 10

    public var id: Int { rawValue }
    public var title: String { String(localized: "\(rawValue) minutes") }
}

/// One precomputed phase with absolute dates, so views and the Live Activity can render with
/// `Text(timerInterval:)` / `ProgressView(timerInterval:)` and no timers.
public struct BreathPhase: Codable, Hashable, Sendable {
    public var kind: BreathPhaseKind
    public var seconds: Int
    public var start: Date
    public var end: Date

    public init(kind: BreathPhaseKind, seconds: Int, start: Date, end: Date) {
        self.kind = kind
        self.seconds = seconds
        self.start = start
        self.end = end
    }
}

/// A whole session laid out in advance. The length is rounded to whole cycles (never cut
/// mid-breath), so a "3 minute" 4-7-8 session is 9 cycles = 2 min 51 s.
public struct BreathingPlan: Sendable, Equatable {
    public let pattern: BreathingPattern
    public let start: Date
    public let phases: [BreathPhase]

    public init(pattern: BreathingPattern, minutes: Int, start: Date) {
        self.pattern = pattern
        self.start = start
        let cycles = max(1, Int((Double(minutes * 60) / Double(pattern.cycleSeconds)).rounded()))
        var phases: [BreathPhase] = []
        var cursor = start
        for _ in 0..<cycles {
            for step in pattern.cycle {
                let end = cursor.addingTimeInterval(TimeInterval(step.seconds))
                phases.append(BreathPhase(kind: step.kind, seconds: step.seconds, start: cursor, end: end))
                cursor = end
            }
        }
        self.phases = phases
    }

    public var end: Date { phases.last?.end ?? start }
    public var cycles: Int { phases.count / max(pattern.cycle.count, 1) }

    /// The phase at `date`, or `nil` before the start / after the end.
    public func phase(at date: Date) -> BreathPhase? {
        guard date >= start, date < end else { return nil }
        // Binary search: phases are contiguous and sorted.
        var low = 0, high = phases.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if date < phases[mid].start { high = mid - 1 } else if date >= phases[mid].end { low = mid + 1 } else { return phases[mid] }
        }
        return nil
    }

    /// Index of the phase at `date` within its cycle (0 = inhale).
    public func stepIndex(at date: Date) -> Int? {
        guard let phase = phase(at: date), let index = phases.firstIndex(of: phase) else { return nil }
        return index % pattern.cycle.count
    }
}

/// Live Activity for a breathing session (Lock Screen + Dynamic Island).
///
/// The countdown is `Text(timerInterval:)`, so it ticks on its own. The phase label is updated by
/// the app at each phase boundary while it's in the foreground; each update carries
/// `staleDate = phaseEnd`, and a stale activity shows only the countdown (never a wrong phase).
public struct BreathingActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: BreathPhaseKind?
        public var phaseSeconds: Int
        public var phaseStart: Date
        public var phaseEnd: Date
        public var sessionEnd: Date

        public init(phase: BreathPhaseKind?, phaseSeconds: Int, phaseStart: Date, phaseEnd: Date, sessionEnd: Date) {
            self.phase = phase
            self.phaseSeconds = phaseSeconds
            self.phaseStart = phaseStart
            self.phaseEnd = phaseEnd
            self.sessionEnd = sessionEnd
        }
    }

    public var pattern: BreathingPattern
    public var sessionStart: Date

    public init(pattern: BreathingPattern, sessionStart: Date) {
        self.pattern = pattern
        self.sessionStart = sessionStart
    }
}
