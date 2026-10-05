import Foundation
import Testing
@testable import CoreKit

/// URLProtocol mock. Responses are scripted per test; the suite is serialized because the
/// script is process-global.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    enum Step {
        case response(status: Int, headers: [String: String] = [:], body: Data = Data())
        case failure(URLError.Code)
    }

    nonisolated(unsafe) static var steps: [Step] = []
    nonisolated(unsafe) static var requestCount = 0
    private static let lock = NSLock()

    static func script(_ steps: [Step]) {
        lock.withLock {
            self.steps = steps
            requestCount = 0
        }
    }

    static var count: Int { lock.withLock { requestCount } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let step: Step = Self.lock.withLock {
            Self.requestCount += 1
            return Self.steps.isEmpty ? .response(status: 200) : Self.steps.removeFirst()
        }
        switch step {
        case let .response(status, headers, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

/// Records requested sleeps instead of sleeping.
actor SleepRecorder {
    private(set) var delays: [TimeInterval] = []
    func record(_ delay: TimeInterval) { delays.append(delay) }
}

@Suite("HTTPClient", .serialized)
struct HTTPClientTests {
    let url = URL(string: "https://cdn.example.com/manifest.json")!
    let sleeps = SleepRecorder()

    private func makeClient(policy: RetryPolicy = RetryPolicy(maxAttempts: 3, baseDelay: 1, maxDelay: 30, jitter: 0),
                            random: Double = 0, now: Date = Date()) -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let sleeps = self.sleeps
        return HTTPClient(session: URLSession(configuration: configuration), retryPolicy: policy,
                          sleeper: { await sleeps.record($0) }, random: { random }, now: { now })
    }

    @Test func successOnFirstAttempt() async throws {
        MockURLProtocol.script([.response(status: 200, body: Data("ok".utf8))])
        let response = try await makeClient().send(URLRequest(url: url))
        #expect(response.data == Data("ok".utf8))
        #expect(MockURLProtocol.count == 1)
        #expect(await sleeps.delays.isEmpty)
    }

    @Test func retriesServerErrorsWithExponentialBackoff() async throws {
        MockURLProtocol.script([.response(status: 500), .response(status: 502), .response(status: 200)])
        _ = try await makeClient().send(URLRequest(url: url))
        #expect(MockURLProtocol.count == 3)
        #expect(await sleeps.delays == [1, 2])
    }

    @Test func givesUpAfterMaxAttempts() async throws {
        MockURLProtocol.script([.response(status: 503), .response(status: 503), .response(status: 503)])
        await #expect {
            try await makeClient().send(URLRequest(url: url))
        } throws: { error in
            (error as? HTTPError)?.statusCode == 503
        }
        #expect(MockURLProtocol.count == 3)
    }

    @Test func doesNotRetryClientErrors() async throws {
        MockURLProtocol.script([.response(status: 404)])
        await #expect(throws: HTTPError.self) { try await makeClient().send(URLRequest(url: url)) }
        #expect(MockURLProtocol.count == 1)
    }

    @Test func honorsRetryAfterSeconds() async throws {
        MockURLProtocol.script([.response(status: 429, headers: ["Retry-After": "7"]), .response(status: 200)])
        _ = try await makeClient().send(URLRequest(url: url))
        #expect(await sleeps.delays == [7])
    }

    @Test func honorsRetryAfterHTTPDate() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = formatter.string(from: now.addingTimeInterval(12))
        MockURLProtocol.script([.response(status: 503, headers: ["Retry-After": header]), .response(status: 200)])
        _ = try await makeClient(now: now).send(URLRequest(url: url))
        #expect(await sleeps.delays == [12])
    }

    @Test func retryAfterLongerThanLimitThrowsRateLimited() async throws {
        MockURLProtocol.script([.response(status: 429, headers: ["Retry-After": "3600"])])
        await #expect {
            try await makeClient().send(URLRequest(url: url))
        } throws: { error in
            if case HTTPError.rateLimited(let after) = error { return after == 3600 }
            return false
        }
        #expect(MockURLProtocol.count == 1)
    }

    @Test func postIsNotRetriedOnServerErrorButIsOn429() async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        MockURLProtocol.script([.response(status: 500)])
        await #expect(throws: HTTPError.self) { try await makeClient().send(request) }
        #expect(MockURLProtocol.count == 1)

        MockURLProtocol.script([.response(status: 429, headers: ["Retry-After": "1"]), .response(status: 201)])
        let response = try await makeClient().send(request)
        #expect(response.statusCode == 201)
    }

    @Test func retriesTransientTransportErrors() async throws {
        MockURLProtocol.script([.failure(.timedOut), .response(status: 200)])
        _ = try await makeClient().send(URLRequest(url: url))
        #expect(MockURLProtocol.count == 2)
    }

    @Test func offlineFailsFastWithoutRetry() async throws {
        MockURLProtocol.script([.failure(.notConnectedToInternet)])
        await #expect {
            try await makeClient().send(URLRequest(url: url))
        } throws: { error in
            if case HTTPError.transport(let urlError) = error { return urlError.code == .notConnectedToInternet }
            return false
        }
        #expect(MockURLProtocol.count == 1)
    }

    @Test func decodesJSON() async throws {
        struct Manifest: Decodable, Equatable { let version: Int }
        MockURLProtocol.script([.response(status: 200, body: Data(#"{"version":3}"#.utf8))])
        let manifest = try await makeClient().send(URLRequest(url: url), decoding: Manifest.self)
        #expect(manifest == Manifest(version: 3))
    }
}

@Suite("RetryPolicy")
struct RetryPolicyTests {
    @Test func backoffDoublesAndCaps() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 5, jitter: 0)
        #expect((1...5).map { policy.backoff(forRetry: $0, random: 0.5) } == [1, 2, 4, 5, 5])
    }

    @Test func jitterStaysWithinBounds() {
        let policy = RetryPolicy(baseDelay: 4, maxDelay: 100, jitter: 0.5)
        #expect(policy.backoff(forRetry: 1, random: 0) == 2)
        #expect(policy.backoff(forRetry: 1, random: 0.999_999) < 4)
        #expect(policy.backoff(forRetry: 1, random: 0.999_999) > 3.99)
    }
}

/// Manually advanced clock.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    var now: TimeInterval { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

@Suite("RateLimiter")
struct RateLimiterTests {
    @Test func allowsBurstThenBlocks() async {
        let clock = TestClock()
        let limiter = RateLimiter(capacity: 3, refillRate: 1, now: { clock.now })
        #expect(await limiter.tryAcquire())
        #expect(await limiter.tryAcquire())
        #expect(await limiter.tryAcquire())
        #expect(await limiter.tryAcquire() == false)
        #expect(await limiter.timeUntilNextToken() == 1)
    }

    @Test func refillsOverTimeUpToCapacity() async {
        let clock = TestClock()
        let limiter = RateLimiter(capacity: 2, refillRate: 0.5, now: { clock.now })
        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()
        clock.advance(2)
        #expect(await limiter.tryAcquire())
        #expect(await limiter.tryAcquire() == false)
        clock.advance(100)
        #expect(await limiter.availableTokens == 2)
    }

    @Test func acquireWaitsForRefill() async throws {
        let clock = TestClock()
        let limiter = RateLimiter(capacity: 1, refillRate: 2, now: { clock.now }, sleeper: { clock.advance($0) })
        try await limiter.acquire()
        try await limiter.acquire()
        #expect(clock.now == 0.5)
    }

    @Test func drainForcesWait() async {
        let clock = TestClock()
        let limiter = RateLimiter(capacity: 5, refillRate: 1, now: { clock.now })
        await limiter.drain()
        #expect(await limiter.tryAcquire() == false)
    }
}
