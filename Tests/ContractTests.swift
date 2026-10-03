import XCTest
@testable import OsmosDemo

final class ContractTests: XCTestCase {
    func testAssignmentConfigurationIsExact() throws {
        let config = AdConfiguration.assignment
        XCTAssertEqual(config.clientID, "10088010")
        XCTAssertEqual(config.productAdsHost, "demo.o-s.io")
        XCTAssertEqual(config.displayAdsHost, "demo-ba.o-s.io")
        XCTAssertEqual(config.cliUbid, "Any")
        XCTAssertEqual(config.pageType, "demo_page")
        XCTAssertEqual(config.adUnit, "banner_ads")
        XCTAssertNoThrow(try config.validate())
    }

    func testHostMustNotIncludeScheme() {
        let config = AdConfiguration(clientID: "10088010", productAdsHost: "https://demo.o-s.io",
                                     displayAdsHost: "demo-ba.o-s.io", cliUbid: "Any",
                                     pageType: "demo_page", adUnit: "banner_ads")
        XCTAssertThrowsError(try config.validate())
    }

    func testRetryPolicyStopsAfterThreeTotalAttempts() {
        let policy = RetryPolicy(maxAttempts: 3, delay: { Double($0) })
        XCTAssertEqual(policy.retryDelay(afterAttempt: 1, error: .network), 1)
        XCTAssertEqual(policy.retryDelay(afterAttempt: 2, error: .timeout), 2)
        XCTAssertNil(policy.retryDelay(afterAttempt: 3, error: .http(503)))
        XCTAssertNil(policy.retryDelay(afterAttempt: 1, error: .noAds))
        XCTAssertNil(policy.retryDelay(afterAttempt: 1, error: .invalidResponse))
        XCTAssertNil(policy.retryDelay(afterAttempt: 1, error: .http(403)))
        XCTAssertEqual(policy.retryDelay(afterAttempt: 1, error: .http(429)), 5)
    }

    func testURLPolicyRejectsUnsafeOrAmbiguousDestinations() {
        for value in ["javascript:alert(1)", "file:///tmp/a", "https://", "https://user:pass@example.com", " https://example.com", "https://exa mple.com"] {
            XCTAssertNil(URLPolicy.webURL(value), value)
        }
        XCTAssertNotNil(URLPolicy.webURL("https://example.com/path?q=one%20two"))
        XCTAssertNotNil(URLPolicy.webURL("http://example.com"))
        XCTAssertNil(URLPolicy.webURL("http://example.com", httpsOnly: true))
    }
}