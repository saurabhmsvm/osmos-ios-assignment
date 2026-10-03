import Foundation
import CoreGraphics

@MainActor
protocol AdServing: AnyObject {
    var initializationError: AdError? { get }
    func fetchAd() async throws -> BannerAd
}

enum EventReceipt: Equatable {
    case acknowledged
    case unconfirmed
    case simulated
}

@MainActor
protocol AdEventSending: AnyObject {
    func sendImpression(for ad: BannerAd, position: Int) async throws -> EventReceipt
    func sendClick(for ad: BannerAd) async throws -> EventReceipt
}

protocol ImageLoading: AnyObject {
    func image(for url: URL) async throws -> CGImage
}

struct RetryPolicy {
    let maxAttempts: Int
    let delay: (Int) -> TimeInterval

    static let standard = RetryPolicy(maxAttempts: 3) { failedAttempt in
        pow(2, Double(failedAttempt - 1)) + Double.random(in: 0...0.2)
    }

    func retryDelay(afterAttempt attempt: Int, error: AdError) -> TimeInterval? {
        guard error.isRetryable, attempt < maxAttempts else { return nil }
        // The pinned SDK exposes status, not Retry-After headers. Avoid a tight 429 loop.
        let value = error == .http(429) ? max(5, delay(attempt)) : delay(attempt)
        return min(30, max(0, value))
    }
}

typealias AsyncSleeper = (TimeInterval) async throws -> Void

func sleepForRetry(_ seconds: TimeInterval) async throws {
    try await Task.sleep(nanoseconds: UInt64(max(0, min(seconds, 60)) * 1_000_000_000))
}