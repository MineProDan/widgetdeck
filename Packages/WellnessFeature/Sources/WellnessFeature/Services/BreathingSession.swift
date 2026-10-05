import ActivityKit
import AVFoundation
import CoreKit
import Foundation
import Observation
import os
import UIKit
import WellnessFeatureWidgetKit

/// Runs a breathing session (W-04): the precomputed plan, haptics, an optional soft chime and the
/// Live Activity. Nothing plays or starts until the user taps Start.
@MainActor
@Observable
public final class BreathingSession {
    public private(set) var plan: BreathingPlan?
    public private(set) var isRunning = false
    public private(set) var phaseIndex = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var activityID: String?
    @ObservationIgnored private var chime: ChimePlayer?
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .soft)
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Wellness")

    public init() {}

    /// Starts a session. Call only from a user action (it may start audio).
    public func start(pattern: BreathingPattern, minutes: Int, sound: Bool) {
        stop()
        let plan = BreathingPlan(pattern: pattern, minutes: minutes, start: .now.addingTimeInterval(0.4))
        self.plan = plan
        isRunning = true
        phaseIndex = 0
        chime = sound ? ChimePlayer() : nil
        haptics.prepare()
        startActivity(plan)
        task = Task { [weak self] in await self?.run(plan) }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        chime = nil
        endActivity()
    }

    private func run(_ plan: BreathingPlan) async {
        var index = 0
        while index < plan.phases.count, !Task.isCancelled {
            // Catch up after the app was suspended: jump to the phase that's current now.
            let now = Date.now
            while index < plan.phases.count - 1, plan.phases[index].end <= now { index += 1 }
            let phase = plan.phases[index]
            phaseIndex = index
            if phase.start <= now.addingTimeInterval(0.5) {
                haptics.impactOccurred(intensity: phase.kind == .inhale ? 1 : 0.6)
                chime?.play(high: phase.kind == .inhale)
                await updateActivity(plan, phase: phase)
            }
            try? await Task.sleep(for: .seconds(max(phase.end.timeIntervalSinceNow, 0.05)))
            index += 1
        }
        guard !Task.isCancelled else { return }
        isRunning = false
        chime = nil
        endActivity()
    }

    // MARK: Live Activity

    private func startActivity(_ plan: BreathingPlan) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let first = plan.phases.first else { return }
        let attributes = BreathingActivityAttributes(pattern: plan.pattern, sessionStart: plan.start)
        do {
            activityID = try Activity.request(attributes: attributes, content: content(plan, phase: first), pushType: nil).id
        } catch {
            // Live Activities off, or too many running: the in-app session still works.
            Self.logger.info("Breathing Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func content(_ plan: BreathingPlan, phase: BreathPhase) -> ActivityContent<BreathingActivityAttributes.ContentState> {
        ActivityContent(state: .init(phase: phase.kind, phaseSeconds: phase.seconds, phaseStart: phase.start,
                                     phaseEnd: phase.end, sessionEnd: plan.end),
                        staleDate: phase.end.addingTimeInterval(1))
    }

    private func updateActivity(_ plan: BreathingPlan, phase: BreathPhase) async {
        guard let activityID else { return }
        await Self.update(id: activityID, content: content(plan, phase: phase))
    }

    private func endActivity() {
        guard let activityID else { return }
        self.activityID = nil
        let final = ActivityContent(state: BreathingActivityAttributes.ContentState(
            phase: nil, phaseSeconds: 0, phaseStart: .now, phaseEnd: .now, sessionEnd: .now), staleDate: nil)
        Task { await Self.end(id: activityID, content: final) }
    }

    // Activities are looked up by id inside nonisolated helpers (`Activity` isn't Sendable).
    private nonisolated static func update(id: String, content: ActivityContent<BreathingActivityAttributes.ContentState>) async {
        await Activity<BreathingActivityAttributes>.activities.first { $0.id == id }?.update(content)
    }

    private nonisolated static func end(id: String, content: ActivityContent<BreathingActivityAttributes.ContentState>) async {
        await Activity<BreathingActivityAttributes>.activities.first { $0.id == id }?.end(content, dismissalPolicy: .immediate)
    }
}

/// A short, soft sine chime generated in memory (no bundled audio). Uses the `.ambient` session
/// category, so it mixes with other audio and respects the silent switch.
@MainActor
final class ChimePlayer {
    private var low: AVAudioPlayer?
    private var high: AVAudioPlayer?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        low = try? AVAudioPlayer(data: Self.tone(frequency: 392))
        high = try? AVAudioPlayer(data: Self.tone(frequency: 523))
        low?.volume = 0.35
        high?.volume = 0.35
        low?.prepareToPlay()
        high?.prepareToPlay()
    }

    func play(high isHigh: Bool) {
        let player = isHigh ? high : low
        player?.currentTime = 0
        player?.play()
    }

    /// 16-bit mono WAV, 0.35 s, with a gentle attack and exponential release.
    static func tone(frequency: Double, duration: Double = 0.35, sampleRate: Double = 22_050) -> Data {
        let count = Int(duration * sampleRate)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = min(t / 0.02, 1) * exp(-t * 9)
            samples[i] = Int16(sin(2 * .pi * frequency * t) * envelope * 0.6 * Double(Int16.max))
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
        for sample in samples { append(sample) }
        return data
    }
}
