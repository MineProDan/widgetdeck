import ActivityKit
import CoreKit
import Foundation

/// A focus timer preset (S-08): focus length, break length and how many focus rounds.
public struct FocusPreset: Codable, Hashable, Sendable, Identifiable {
    public var focusMinutes: Int
    public var breakMinutes: Int
    public var rounds: Int

    public init(focusMinutes: Int, breakMinutes: Int, rounds: Int) {
        self.focusMinutes = min(max(focusMinutes, 1), 180)
        self.breakMinutes = min(max(breakMinutes, 0), 60)
        self.rounds = min(max(rounds, 1), 8)
    }

    public var id: String { "\(focusMinutes)-\(breakMinutes)-\(rounds)" }

    /// Classic Pomodoro: 4 × (25 min focus + 5 min break).
    public static let pomodoro = FocusPreset(focusMinutes: 25, breakMinutes: 5, rounds: 4)
    /// Long blocks: 2 × (50 min focus + 10 min break).
    public static let deepWork = FocusPreset(focusMinutes: 50, breakMinutes: 10, rounds: 2)

    /// "25 / 5".
    public var title: String { "\(focusMinutes) / \(breakMinutes)" }
}

public enum FocusBlockKind: String, Codable, Sendable, Hashable {
    case focus, rest

    public var title: String {
        switch self {
        case .focus: String(localized: "Focus")
        case .rest: String(localized: "Break")
        }
    }
}

/// One precomputed block with absolute dates, so every view can use `Text(timerInterval:)` and
/// `ProgressView(timerInterval:)` without timers (Platform Reality Rule 1).
public struct FocusBlock: Codable, Hashable, Sendable {
    public var kind: FocusBlockKind
    /// 1-based round this block belongs to.
    public var round: Int
    public var start: Date
    public var end: Date

    public init(kind: FocusBlockKind, round: Int, start: Date, end: Date) {
        self.kind = kind
        self.round = round
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A whole focus session laid out in advance: focus, break, focus, … (no break after the last round).
public struct FocusPlan: Codable, Sendable, Equatable {
    public var preset: FocusPreset
    public var blocks: [FocusBlock]

    public init(preset: FocusPreset, start: Date) {
        self.preset = preset
        var blocks: [FocusBlock] = []
        var cursor = start
        for round in 1...preset.rounds {
            let focusEnd = cursor.addingTimeInterval(TimeInterval(preset.focusMinutes * 60))
            blocks.append(FocusBlock(kind: .focus, round: round, start: cursor, end: focusEnd))
            cursor = focusEnd
            if round < preset.rounds && preset.breakMinutes > 0 {
                let breakEnd = cursor.addingTimeInterval(TimeInterval(preset.breakMinutes * 60))
                blocks.append(FocusBlock(kind: .rest, round: round, start: cursor, end: breakEnd))
                cursor = breakEnd
            }
        }
        self.blocks = blocks
    }

    public init(preset: FocusPreset, blocks: [FocusBlock]) {
        self.preset = preset
        self.blocks = blocks
    }

    public var start: Date { blocks.first?.start ?? .distantPast }
    public var end: Date { blocks.last?.end ?? .distantPast }

    /// Index of the block running at `date` (`nil` before the start or after the end).
    public func index(at date: Date) -> Int? {
        blocks.firstIndex { $0.start <= date && date < $0.end }
    }

    public func block(at date: Date) -> FocusBlock? { index(at: date).map { blocks[$0] } }

    public func isFinished(at date: Date) -> Bool { date >= end }

    /// The plan after a pause from `pausedAt` to `now`: every block that hadn't ended when the
    /// pause began moves later by the pause length (the running block keeps its remaining time).
    public func resumed(pausedAt: Date, now: Date) -> FocusPlan {
        let shift = max(0, now.timeIntervalSince(pausedAt))
        var copy = self
        copy.blocks = blocks.map { block in
            guard block.end > pausedAt else { return block }
            var moved = block
            // Shifting the start too keeps the progress bar's elapsed share right after resuming.
            moved.start = block.start.addingTimeInterval(shift)
            moved.end = block.end.addingTimeInterval(shift)
            return moved
        }
        return copy
    }
}

/// Live Activity for a focus session (Lock Screen chip + Dynamic Island, LockScreen.png).
///
/// The countdown and progress bar are `Text(timerInterval:)` / `ProgressView(timerInterval:)`,
/// so they tick on their own. The app updates the state at each block boundary while it's in the
/// foreground; every update carries `staleDate = blockEnd`, and a stale activity says the block
/// is over instead of showing a wrong phase. No code runs in the background.
public struct FocusActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var kind: FocusBlockKind
        public var round: Int
        public var blockStart: Date
        public var blockEnd: Date
        /// Remaining seconds while paused; `nil` while running.
        public var pausedRemaining: TimeInterval?

        public init(kind: FocusBlockKind, round: Int, blockStart: Date, blockEnd: Date, pausedRemaining: TimeInterval? = nil) {
            self.kind = kind
            self.round = round
            self.blockStart = blockStart
            self.blockEnd = blockEnd
            self.pausedRemaining = pausedRemaining
        }
    }

    /// What the user is working on ("Chem lab report"), or the course code, or "Focus".
    public var title: String
    public var courseID: UUID?
    public var paint: CoursePaint
    public var rounds: Int

    public init(title: String, courseID: UUID?, paint: CoursePaint, rounds: Int) {
        self.title = title
        self.courseID = courseID
        self.paint = paint
        self.rounds = rounds
    }
}

/// Deep link to the Student section's Focus tab.
public enum FocusDeepLink {
    public static var url: URL {
        var components = URLComponents(url: AppSection.student.deepLink, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "tab", value: "focus")]
        return components?.url ?? AppSection.student.deepLink
    }

    /// Whether a Student deep link asks for the Focus tab.
    public static func isFocus(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "tab" && $0.value == "focus" } ?? false
    }
}
