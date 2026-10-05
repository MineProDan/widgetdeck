import Foundation
import os

/// Errors from `HTTPClient`.
public enum HTTPError: Error, LocalizedError {
    /// The server returned a non-2xx status after all retries.
    case status(code: Int, data: Data)
    /// Rate limited and the server asked us to wait longer than `RetryPolicy.maxRetryAfter`.
    case rateLimited(retryAfter: TimeInterval?)
    /// Network-level failure after all retries.
    case transport(URLError)
    /// The response wasn't HTTP.
    case invalidResponse
    /// Decoding the body failed.
    case decoding(any Error)

    public var statusCode: Int? {
        if case .status(let code, _) = self { return code }
        return nil
    }

    public var errorDescription: String? {
        switch self {
        case .status(let code, _) where (500..<600).contains(code): "The server is having trouble. Please try again later."
        case .status: "The request couldn't be completed."
        case .rateLimited: "Too many requests right now. Please try again in a little while."
        case .transport(let error) where error.code == .notConnectedToInternet: "You're offline."
        case .transport: "Couldn't reach the server. Check your connection."
        case .invalidResponse: "The server sent an unexpected response."
        case .decoding: "The server sent data we couldn't read."
        }
    }
}

/// When and how `HTTPClient` retries.
public struct RetryPolicy: Sendable {
    /// Total attempts including the first (1 = no retries).
    public var maxAttempts: Int
    /// Delay before the first retry; doubles on each subsequent retry.
    public var baseDelay: TimeInterval
    /// Upper bound for the exponential delay.
    public var maxDelay: TimeInterval
    /// Fraction of the delay that is randomized (0 = none, 1 = "full jitter").
    public var jitter: Double
    /// Longest `Retry-After` we are willing to wait inside one call.
    public var maxRetryAfter: TimeInterval
    /// Status codes worth retrying.
    public var retryableStatusCodes: Set<Int>
    /// Retry POST/PATCH too. Off by default: they may not be idempotent.
    public var retriesNonIdempotentRequests: Bool

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 30, jitter: Double = 0.5,
                maxRetryAfter: TimeInterval = 120, retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
                retriesNonIdempotentRequests: Bool = false) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(0, maxDelay)
        self.jitter = min(max(jitter, 0), 1)
        self.maxRetryAfter = max(0, maxRetryAfter)
        self.retryableStatusCodes = retryableStatusCodes
        self.retriesNonIdempotentRequests = retriesNonIdempotentRequests
    }

    public static let `default` = RetryPolicy()
    public static let none = RetryPolicy(maxAttempts: 1)

    /// Exponential backoff with jitter for retry number `retry` (1-based).
    /// `random` is a value in 0..<1.
    public func backoff(forRetry retry: Int, random: Double) -> TimeInterval {
        let exponential = min(maxDelay, baseDelay * pow(2, Double(max(0, retry - 1))))
        return exponential * (1 - jitter) + exponential * jitter * random
    }
}

/// A successful HTTP response.
public struct HTTPResponse: Sendable {
    public let data: Data
    public let response: HTTPURLResponse
    public var statusCode: Int { response.statusCode }
}

/// Minimal async HTTP client over `URLSession` with retry, exponential backoff + jitter,
/// `429`/`503` `Retry-After` handling and optional token-bucket rate limiting.
/// **Main app only**; the widget extension never makes network calls.
public struct HTTPClient: Sendable {
    public let session: URLSession
    public let retryPolicy: RetryPolicy
    public let rateLimiter: RateLimiter?
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    private let random: @Sendable () -> Double
    private let now: @Sendable () -> Date
    private static var logger: Logger { Logger(subsystem: AppIdentifiers.appBundleID, category: "HTTP") }

    public init(session: URLSession = .shared, retryPolicy: RetryPolicy = .default, rateLimiter: RateLimiter? = nil,
                sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.retryPolicy = retryPolicy
        self.rateLimiter = rateLimiter
        self.sleeper = sleeper
        self.random = random
        self.now = now
    }

    /// Sends `request`, retrying per `retryPolicy`. Returns only 2xx responses.
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let method = (request.httpMethod ?? "GET").uppercased()
        let idempotent = ["GET", "HEAD", "PUT", "DELETE", "OPTIONS"].contains(method)
        var attempt = 0

        while true {
            attempt += 1
            try Task.checkCancellation()
            if let rateLimiter { try await rateLimiter.acquire() }

            let delay: TimeInterval
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
                if (200..<300).contains(http.statusCode) { return HTTPResponse(data: data, response: http) }

                let code = http.statusCode
                let retryAfter = Self.retryAfter(from: http, now: now())
                // 429/503 mean the server didn't process the request, so retrying is safe for any method.
                let serverRefused = code == 429 || code == 503
                let canRetry = retryPolicy.retryableStatusCodes.contains(code)
                    && (idempotent || serverRefused || retryPolicy.retriesNonIdempotentRequests)
                    && attempt < retryPolicy.maxAttempts

                if code == 429 { await rateLimiter?.drain() }
                guard canRetry else {
                    if code == 429 { throw HTTPError.rateLimited(retryAfter: retryAfter) }
                    throw HTTPError.status(code: code, data: data)
                }
                if let retryAfter {
                    guard retryAfter <= retryPolicy.maxRetryAfter else { throw HTTPError.rateLimited(retryAfter: retryAfter) }
                    delay = retryAfter
                } else {
                    delay = retryPolicy.backoff(forRetry: attempt, random: random())
                }
                Self.logger.info("HTTP \(code) for \(method) \(request.url?.host() ?? "?", privacy: .public); retry \(attempt) in \(delay)s")
            } catch let error as URLError {
                guard Self.isTransient(error), idempotent || retryPolicy.retriesNonIdempotentRequests,
                      attempt < retryPolicy.maxAttempts else {
                    if error.code == .cancelled { throw CancellationError() }
                    throw HTTPError.transport(error)
                }
                delay = retryPolicy.backoff(forRetry: attempt, random: random())
                Self.logger.info("Transport error \(error.code.rawValue); retry \(attempt) in \(delay)s")
            }
            try await sleeper(delay)
        }
    }

    /// Sends `request` and decodes a JSON body.
    public func send<T: Decodable>(_ request: URLRequest, decoding type: T.Type,
                                   decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        let response = try await send(request)
        do { return try decoder.decode(type, from: response.data) } catch { throw HTTPError.decoding(error) }
    }

    /// Parses `Retry-After` as delta-seconds or an HTTP-date.
    static func retryAfter(from response: HTTPURLResponse, now: Date) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .badServerResponse, .resourceUnavailable:
            true
        default:
            false
        }
    }
}
