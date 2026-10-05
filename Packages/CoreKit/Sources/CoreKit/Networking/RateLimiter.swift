import Foundation

/// Token-bucket rate limiter (e.g. one per Pinterest token, one per CDN host).
///
/// `capacity` tokens are available in a burst; tokens refill continuously at `refillRate` per second.
public actor RateLimiter {
    public let capacity: Double
    public let refillRate: Double
    private var tokens: Double
    private var lastRefill: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let sleeper: @Sendable (TimeInterval) async throws -> Void

    /// - Parameters:
    ///   - capacity: burst size (≥ 1).
    ///   - refillRate: tokens per second (> 0).
    ///   - now: monotonic clock in seconds (injectable for tests).
    ///   - sleeper: waits the given number of seconds (injectable for tests).
    public init(capacity: Double, refillRate: Double,
                now: @escaping @Sendable () -> TimeInterval = RateLimiter.monotonicNow,
                sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        precondition(capacity >= 1 && refillRate > 0, "RateLimiter needs capacity ≥ 1 and refillRate > 0")
        self.capacity = capacity
        self.refillRate = refillRate
        self.tokens = capacity
        self.now = now
        self.sleeper = sleeper
        self.lastRefill = now()
    }

    /// Seconds on a monotonic clock (unaffected by wall-clock changes).
    public static let monotonicNow: @Sendable () -> TimeInterval = {
        let elapsed = ContinuousClock.now - referenceInstant
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
    private static let referenceInstant = ContinuousClock.now

    private func refill() {
        let current = now()
        let elapsed = max(0, current - lastRefill)
        tokens = min(capacity, tokens + elapsed * refillRate)
        lastRefill = current
    }

    /// Takes a token if one is available, without waiting.
    public func tryAcquire() -> Bool {
        refill()
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }

    /// Seconds until the next token is available (0 if one is available now).
    public func timeUntilNextToken() -> TimeInterval {
        refill()
        return tokens >= 1 ? 0 : (1 - tokens) / refillRate
    }

    /// Waits until a token is available, then takes it. Throws `CancellationError` if cancelled.
    public func acquire() async throws {
        while true {
            try Task.checkCancellation()
            if tryAcquire() { return }
            try await sleeper(timeUntilNextToken())
        }
    }

    /// Empties the bucket, e.g. after a 429 so other callers back off too.
    public func drain() {
        refill()
        tokens = 0
    }

    /// Currently available tokens (diagnostics / tests).
    public var availableTokens: Double {
        refill()
        return tokens
    }
}
