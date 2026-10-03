import XCTest
import CoreGraphics
@testable import OsmosDemo

enum TestData {
    static func ad(_ number: Int = 1) throws -> BannerAd {
        try BannerResponseParser(adUnit: "banner_ads").parse(FixtureAdService.response(number: number))
    }
}

@MainActor
final class StubAdService: AdServing {
    var initializationError: AdError?
    var results: [Result<BannerAd, AdError>]
    var shouldSuspend = false
    private(set) var calls = 0
    private var continuation: CheckedContinuation<BannerAd, Error>?

    init(results: [Result<BannerAd, AdError>]) { self.results = results }

    func fetchAd() async throws -> BannerAd {
        calls += 1
        if shouldSuspend {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        await Task.yield()
        guard !results.isEmpty else { throw AdError.noAds }
        return try results.removeFirst().get()
    }

    func resolve(_ result: Result<BannerAd, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
final class SpyEventSender: AdEventSending {
    private(set) var impressionCalls: [(id: String, position: Int)] = []
    private(set) var clickIDs: [String] = []
    var error: AdError?

    func sendImpression(for ad: BannerAd, position: Int) async throws -> EventReceipt {
        impressionCalls.append((ad.id, position))
        if let error { throw error }
        return .simulated
    }

    func sendClick(for ad: BannerAd) async throws -> EventReceipt {
        clickIDs.append(ad.id)
        if let error { throw error }
        return .simulated
    }
}

actor StubImageLoader: ImageLoading {
    let imageValue: CGImage
    var error: AdError?

    init(error: AdError? = nil) throws {
        imageValue = try FixtureImageLoader.artwork(index: 1)
        self.error = error
    }

    func image(for url: URL) async throws -> CGImage {
        if let error { throw error }
        return imageValue
    }
}

@MainActor
func eventually(file: StaticString = #filePath, line: UInt = #line,
                _ condition: @escaping () -> Bool) async {
    for _ in 0..<2_000 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("Condition did not become true", file: file, line: line)
}