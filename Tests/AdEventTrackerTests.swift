import XCTest
@testable import OsmosDemo

final class AdEventTrackerTests: XCTestCase {
    @MainActor
    func testImpressionIsReservedBeforeAsyncSubmissionAndFiresOnce() async throws {
        let sender = SpyEventSender()
        let logger = AnalyticsStore()
        let tracker = AdEventTracker(sender: sender, analytics: logger, simulated: true)
        let ad = try TestData.ad()
        tracker.impression(for: ad, position: 1, fraction: 0.499)
        XCTAssertTrue(tracker.impressions.isEmpty)
        for _ in 0..<20 { tracker.impression(for: ad, position: 1, fraction: 0.5) }
        XCTAssertEqual(tracker.impressions[ad.id], .submitted)
        await eventually { tracker.impressions[ad.id] == .simulated }
        XCTAssertEqual(sender.impressionCalls.count, 1)
        XCTAssertEqual(sender.impressionCalls.first?.id, ad.id)
        XCTAssertEqual(sender.impressionCalls.first?.position, 1)
        XCTAssertEqual(logger.entries.filter { $0.name == "Impression Fired" }.count, 1)
    }

    @MainActor
    func testFailureDoesNotCauseAnAmbiguousEventToBeResubmitted() async throws {
        let sender = SpyEventSender()
        sender.error = .eventRejected
        let tracker = AdEventTracker(sender: sender, analytics: AnalyticsStore(), simulated: true)
        let ad = try TestData.ad()
        tracker.impression(for: ad, position: 1, fraction: 1)
        await eventually { tracker.impressions[ad.id] == .failed }
        tracker.impression(for: ad, position: 1, fraction: 1)
        XCTAssertEqual(sender.impressionCalls.count, 1)
    }

    @MainActor
    func testNewServedIdentityCanCountAndClicksAreNotOnceOnly() async throws {
        let sender = SpyEventSender()
        let tracker = AdEventTracker(sender: sender, analytics: AnalyticsStore(), simulated: true)
        let first = try TestData.ad(1)
        let second = try TestData.ad(2)
        tracker.impression(for: first, position: 1, fraction: 1)
        tracker.impression(for: second, position: 2, fraction: 1)
        tracker.click(for: first, position: 1)
        tracker.click(for: first, position: 1)
        await eventually { sender.impressionCalls.count == 2 && sender.clickIDs.count == 2 }
        XCTAssertEqual(tracker.clickCount, 2)
    }

    @MainActor
    func testAnalyticsHistoryIsBounded() async {
        let logger = AnalyticsStore()
        for index in 0..<150 { logger.record("Test", "Entry \(index)") }
        XCTAssertEqual(logger.entries.count, 100)
        XCTAssertEqual(logger.entries.first?.detail, "Entry 149")
    }
}