import XCTest
@testable import OsmosDemo

final class AdFeedViewModelTests: XCTestCase {
    @MainActor
    private func makeModel(_ service: StubAdService, sender: SpyEventSender,
                           imageError: AdError? = nil, now: @escaping () -> Date = Date.init) throws -> AdFeedViewModel {
        let logger = AnalyticsStore()
        let tracker = AdEventTracker(sender: sender, analytics: logger, simulated: true)
        return AdFeedViewModel(service: service, imageLoader: try StubImageLoader(error: imageError),
                               tracker: tracker, analytics: logger, isFixture: true, modeTitle: "Tests",
                               retryPolicy: RetryPolicy(maxAttempts: 3, delay: { _ in 0 }),
                               sleeper: { _ in try Task.checkCancellation() }, now: now)
    }

    @MainActor
    func testRapidLoadsProduceOnlyOneRequest() async throws {
        let service = StubAdService(results: [])
        service.shouldSuspend = true
        let model = try makeModel(service, sender: SpyEventSender())
        for _ in 0..<20 { model.loadAd() }
        await eventually { service.calls == 1 }
        XCTAssertEqual(model.loadState, .loading)
        service.resolve(.success(try TestData.ad()))
        await eventually { model.items.count == 1 }
        XCTAssertEqual(service.calls, 1)
    }

    @MainActor
    func testTransientFailuresRetryThenRecover() async throws {
        let service = StubAdService(results: [.failure(.network), .failure(.http(503)), .success(try TestData.ad())])
        let model = try makeModel(service, sender: SpyEventSender())
        model.loadAd()
        await eventually { model.loadState == .ready }
        XCTAssertEqual(service.calls, 3)
        XCTAssertEqual(model.items.count, 1)
    }

    @MainActor
    func testRetryStopsAfterThreeAttemptsAndNoFillDoesNotRetry() async throws {
        let offline = StubAdService(results: Array(repeating: .failure(.network), count: 5))
        let offlineModel = try makeModel(offline, sender: SpyEventSender())
        offlineModel.loadAd()
        await eventually { offlineModel.loadState == .failed(.network) }
        XCTAssertEqual(offline.calls, 3)
        let empty = StubAdService(results: [.failure(.noAds)])
        let emptyModel = try makeModel(empty, sender: SpyEventSender())
        emptyModel.loadAd()
        await eventually { emptyModel.loadState == .failed(.noAds) }
        XCTAssertEqual(empty.calls, 1)
    }

    @MainActor
    func testLaterFailureAndDuplicatePreserveExistingBanner() async throws {
        let ad = try TestData.ad()
        let service = StubAdService(results: [.success(ad), .failure(.noAds), .success(ad)])
        let model = try makeModel(service, sender: SpyEventSender())
        model.loadAd()
        await eventually { model.loadState == .ready }
        model.loadAd()
        await eventually { model.loadState == .failed(.noAds) }
        XCTAssertEqual(model.items.count, 1)
        model.loadAd()
        await eventually { model.loadState == .failed(.duplicateAd) }
        XCTAssertEqual(model.items.count, 1)
    }

    @MainActor
    func testInactiveOrCoveredFeedDoesNotCountAndReturnDoesNotDuplicate() async throws {
        let ad = try TestData.ad()
        let sender = SpyEventSender()
        let model = try makeModel(StubAdService(results: [.success(ad)]), sender: sender)
        model.loadAd()
        await eventually { model.items.first?.image != nil }
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.updateGeometry([ad.id: frame], viewport: frame)
        XCTAssertTrue(model.tracker.impressions.isEmpty)
        model.setScreenVisible(true)
        model.setOverlayPresented(true)
        model.setSceneActive(true)
        XCTAssertTrue(model.tracker.impressions.isEmpty)
        model.setOverlayPresented(false)
        await eventually { sender.impressionCalls.count == 1 }
        model.setSceneActive(false)
        model.setSceneActive(true)
        model.removeGeometry(id: ad.id)
        model.updateGeometry([ad.id: frame], viewport: frame)
        XCTAssertEqual(model.tracker.impressions.count, 1)
        XCTAssertEqual(sender.impressionCalls.count, 1)
    }

    @MainActor
    func testImageFailureNeverCountsAnImpression() async throws {
        let ad = try TestData.ad()
        let model = try makeModel(StubAdService(results: [.success(ad)]), sender: SpyEventSender(), imageError: .imageUnavailable)
        model.setScreenVisible(true)
        model.setSceneActive(true)
        model.loadAd()
        await eventually { model.items.first?.imageError != nil }
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.updateGeometry([ad.id: frame], viewport: frame)
        XCTAssertTrue(model.tracker.impressions.isEmpty)
    }

    @MainActor
    func testBackgroundCancellationIgnoresLateSDKResultWithoutOverlappingFetch() async throws {
        let service = StubAdService(results: [])
        service.shouldSuspend = true
        let model = try makeModel(service, sender: SpyEventSender())
        model.loadAd()
        await eventually { service.calls == 1 }
        model.setSceneActive(false)
        model.setSceneActive(true)
        model.loadAd()
        XCTAssertEqual(service.calls, 1)
        service.resolve(.success(try TestData.ad()))
        await eventually { model.loadState == .idle }
        XCTAssertTrue(model.items.isEmpty)
    }

    @MainActor
    func testClicksBelowThresholdStillOpenAndDoNotForceImpressions() async throws {
        let ad = try TestData.ad()
        let sender = SpyEventSender()
        sender.error = .eventRejected
        var time = Date(timeIntervalSince1970: 1_000)
        let model = try makeModel(StubAdService(results: [.success(ad)]), sender: sender, now: { time })
        model.setScreenVisible(true)
        model.setSceneActive(true)
        model.loadAd()
        await eventually { model.items.first?.image != nil }
        XCTAssertEqual(model.beginClick(id: ad.id), ad.destinationURL)
        XCTAssertNil(model.beginClick(id: ad.id))
        model.finishOpening(accepted: true)
        XCTAssertNil(model.beginClick(id: ad.id))
        time = time.addingTimeInterval(1)
        XCTAssertEqual(model.beginClick(id: ad.id), ad.destinationURL)
        model.finishOpening(accepted: false)
        XCTAssertNotNil(model.navigationMessage)
        await eventually { sender.clickIDs.count == 2 }
        XCTAssertTrue(model.tracker.impressions.isEmpty)
    }

    @MainActor
    func testInitializationFailureIsRepresentedWithoutCrashing() async throws {
        let service = StubAdService(results: [])
        service.initializationError = .initialization
        let model = try makeModel(service, sender: SpyEventSender())
        XCTAssertEqual(model.loadState, .failed(.initialization))
        XCTAssertEqual(model.analytics.entries.first?.name, "Ad Failed")
    }

    @MainActor
    func testMissingDestinationRendersCountsImpressionAndToastsWithoutClick() async throws {
        let ad = try BannerResponseParser(adUnit: "banner_ads").parse(FixtureAdService.response(missingDestination: true))
        let sender = SpyEventSender()
        var time = Date(timeIntervalSince1970: 1_000)
        let model = try makeModel(StubAdService(results: [.success(ad)]), sender: sender, now: { time })
        model.setScreenVisible(true)
        model.setSceneActive(true)
        model.loadAd()
        await eventually { model.items.first?.image != nil }
        XCTAssertEqual(model.loadState, .ready)
        XCTAssertNotNil(model.toastMessage)
        let initialToast = try XCTUnwrap(model.toastID)
        model.dismissToast(id: initialToast)
        XCTAssertNil(model.toastMessage)

        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.updateGeometry([ad.id: frame], viewport: frame)
        await eventually { sender.impressionCalls.count == 1 }
        XCTAssertNil(model.beginClick(id: ad.id))
        XCTAssertFalse(model.openingDestination)
        XCTAssertEqual(model.tracker.clickCount, 0)
        XCTAssertTrue(sender.clickIDs.isEmpty)
        let firstTapToast = try XCTUnwrap(model.toastID)
        XCTAssertNil(model.beginClick(id: ad.id))
        XCTAssertEqual(model.toastID, firstTapToast)

        time = time.addingTimeInterval(1)
        XCTAssertNil(model.beginClick(id: ad.id))
        XCTAssertNotEqual(model.toastID, firstTapToast)
        model.dismissToast(id: firstTapToast)
        XCTAssertNotNil(model.toastMessage, "An old dismissal must not clear a newer toast")
        model.setSceneActive(false)
        XCTAssertNil(model.toastMessage)
        XCTAssertEqual(sender.impressionCalls.count, 1)
        XCTAssertTrue(sender.clickIDs.isEmpty)
        model.stop()
    }
}