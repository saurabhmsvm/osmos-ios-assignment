import XCTest

final class FeedUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testLoadAndScrollMultipleFixtureBanners() {
        let app = launch("success")
        for position in 1...3 {
            let button = app.buttons["load-ad"]
            expectEnabled(button)
            button.tap()
            let count = app.staticTexts["ad-count"]
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(position) / 20 ads"), object: count)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
            if position > 1 { app.scrollViews["ad-feed"].swipeUp() }
            XCTAssertTrue(app.buttons["banner-\(position)"].waitForExistence(timeout: 5))
        }
        XCTAssertEqual(app.staticTexts["ad-count"].label, "3 / 20 ads")
        app.scrollViews["ad-feed"].swipeUp()
        app.scrollViews["ad-feed"].swipeUp()
        app.scrollViews["ad-feed"].swipeDown()
        app.scrollViews["ad-feed"].swipeDown()
        app.buttons["event-log"].tap()
        XCTAssertTrue(app.staticTexts["impression-count"].waitForExistence(timeout: 5))
        let count = app.staticTexts["impression-count"].label
        app.buttons["Done"].tap()
        app.scrollViews["ad-feed"].swipeUp()
        app.scrollViews["ad-feed"].swipeDown()
        app.buttons["event-log"].tap()
        XCTAssertEqual(app.staticTexts["impression-count"].label, count)
    }

    func testNoFillShowsExactFallbackAndRetry() {
        let app = launch("noAds")
        app.buttons["load-ad"].tap()
        XCTAssertTrue(app.staticTexts["Ad not available"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["load-ad"].label, "Retry")
        XCTAssertEqual(app.staticTexts["ad-count"].label, "0 / 20 ads")
    }

    func testTransientFailureRecoversAndRotationKeepsAd() {
        let app = launch("transient")
        app.buttons["load-ad"].tap()
        XCTAssertTrue(app.buttons["banner-1"].waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(app.staticTexts["ad-count"].label, "1 / 20 ads")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(app.staticTexts["ad-count"].label, "1 / 20 ads")
    }

    func testBrokenImageDoesNotSubmitAnImpression() {
        let app = launch("imageFailure")
        app.buttons["load-ad"].tap()
        XCTAssertTrue(app.buttons["retry-image-1"].waitForExistence(timeout: 5))
        app.buttons["event-log"].tap()
        XCTAssertTrue(app.staticTexts["impression-count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["impression-count"].label, "0")
    }

    func testScenarioPickerIsClearlyLabeledAndCanChangeModes() {
        let app = launch("success")
        app.buttons["demo-scenarios"].tap()
        XCTAssertTrue(app.buttons["scenario-noAds"].waitForExistence(timeout: 5))
        app.buttons["scenario-noAds"].tap()
        app.buttons["load-ad"].tap()
        XCTAssertTrue(app.staticTexts["Ad not available"].waitForExistence(timeout: 5))
    }

    func testMissingDestinationRendersAndToastDismissesWithoutClickTracking() {
        let app = launch("missingDestination")
        app.buttons["load-ad"].tap()
        let banner = app.buttons["banner-1"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        expectEnabled(banner)
        XCTAssertEqual(app.staticTexts["ad-count"].label, "1 / 20 ads")
        banner.tap()
        let toast = app.staticTexts["missing-url-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: toast)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 6), .completed)
        XCTAssertTrue(banner.exists)
        app.buttons["event-log"].tap()
        XCTAssertTrue(app.staticTexts["click-count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["click-count"].label, "0")
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--scenario", scenario]
        app.launch()
        XCTAssertTrue(app.buttons["load-ad"].waitForExistence(timeout: 5))
        return app
    }

    private func expectEnabled(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}