import Foundation

/// Separate service, never delegates to Osmos. Fixtures cannot send real ad events.
@MainActor
final class FixtureAdService: AdServing, AdEventSending {
    let scenario: DemoScenario
    private var requestCount = 0

    init(scenario: DemoScenario) { self.scenario = scenario }

    var initializationError: AdError? {
        scenario == .initializationFailure ? .initialization : nil
    }

    func fetchAd() async throws -> BannerAd {
        try await sleepForRetry(0.45)
        requestCount += 1
        switch scenario {
        case .initializationFailure: throw AdError.initialization
        case .offline: throw AdError.network
        case .timeout: throw AdError.timeout
        case .transient where requestCount == 1: throw AdError.http(503)
        default: break
        }
        var response = Self.response(number: scenario == .duplicate ? 1 : requestCount,
                                     brokenImage: scenario == .imageFailure,
                                     missingDestination: scenario == .missingDestination)
        if scenario == .noAds {
            response["ads"] = ["banner_ads": [[String: Any]]()]
        } else if scenario == .malformed {
            response["ads"] = ["banner_ads": [["elements": ["destination_url": "https://example.com"]]]]
        }
        return try BannerResponseParser(adUnit: "banner_ads").parse(response)
    }

    func sendImpression(for ad: BannerAd, position: Int) async throws -> EventReceipt {
        try await eventResult()
    }

    func sendClick(for ad: BannerAd) async throws -> EventReceipt {
        try await eventResult()
    }

    private func eventResult() async throws -> EventReceipt {
        try await sleepForRetry(0.15)
        if scenario == .eventFailure { throw AdError.eventRejected }
        return .simulated
    }

    nonisolated static func response(number: Int = 1, brokenImage: Bool = false, missingDestination: Bool = false) -> [String: Any] {
        let id = "fixture-\(number)"
        var element: [String: Any] = [
            "type": "image",
            "value": "https://images.example.invalid/\(brokenImage ? "broken" : String(number)).png"
        ]
        if !missingDestination { element["destination_url"] = "https://example.com" }
        return ["status": true, "ads": ["banner_ads": [[
            "uclid": id, "width": 1_200, "height": 750,
            "elements": element,
            "impression_tracking_url": "https://events.example.invalid/impression?uclid=\(id)",
            "click_tracking_url": "https://events.example.invalid/click?uclid=\(id)"
        ]]]]
    }
}