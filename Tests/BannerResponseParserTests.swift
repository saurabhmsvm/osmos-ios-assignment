import XCTest
@testable import OsmosDemo

final class BannerResponseParserTests: XCTestCase {
    private let parser = BannerResponseParser(adUnit: "banner_ads")

    func testValidResponseMapsAllRequiredFields() throws {
        let ad = try parser.parse(FixtureAdService.response())
        XCTAssertEqual(ad.id, "fixture-1")
        XCTAssertEqual(ad.width, 1_200)
        XCTAssertEqual(ad.height, 750)
        XCTAssertEqual(ad.aspectRatio, 1.6, accuracy: 0.001)
        XCTAssertEqual(ad.destinationURL?.absoluteString, "https://example.com")
        XCTAssertTrue(ad.imageURL.absoluteString.contains("1.png"))
        XCTAssertTrue(ad.impressionTrackingURL.absoluteString.contains("impression"))
        XCTAssertTrue(ad.clickTrackingURL.absoluteString.contains("click"))
    }

    func testExtractsFirstBannerOnly() throws {
        let first = banner()
        let response: [String: Any] = ["ads": ["banner_ads": [first, ["invalid": true]]]]
        XCTAssertEqual(try parser.parse(response).id, "fixture-1")
    }

    func testSDKEnvelopeDecodesJSONStringBeforeMappingBanner() throws {
        let response = try sdkEnvelope(FixtureAdService.response())
        let ad = try parser.parse(response)
        XCTAssertEqual(ad, try parser.parse(FixtureAdService.response()))
        XCTAssertTrue(AdResponseDiagnostics.summary(response).contains("response.code=number(200)"))
    }

    func testSDKEnvelopeRequiresTrueBooleanStatus() throws {
        let statuses: [Any] = [false, 1, "true", NSNull()]
        for status in statuses {
            var response = try sdkEnvelope(FixtureAdService.response())
            response["status"] = status
            XCTAssertThrowsError(try parser.parse(response)) { XCTAssertEqual($0 as? AdError, .invalidResponse) }
        }
        var response = try sdkEnvelope(FixtureAdService.response())
        response.removeValue(forKey: "status")
        XCTAssertThrowsError(try parser.parse(response))
    }

    func testSDKEnvelopeRejectsMalformedHTTPCodeAndEnvelope() {
        let codes: [Any] = [true, "200", 0, 600, 200.5, Double.nan, Double.infinity, NSNull()]
        for code in codes {
            let response: [String: Any] = ["status": true, "response": ["code": code, "data": "{}"]]
            XCTAssertThrowsError(try parser.parse(response)) { XCTAssertEqual($0 as? AdError, .invalidResponse) }
        }
        XCTAssertThrowsError(try parser.parse(["status": true, "response": NSNull()]))
        XCTAssertThrowsError(try parser.parse(["status": true, "response": ["data": "{}"]]))
    }

    func testSDKHTTPFailuresPreserveStatusForRetryPolicy() throws {
        for code in [400, 401, 403, 404, 408, 429, 500, 502, 503, 504] {
            let response = try sdkEnvelope(FixtureAdService.response(), code: code)
            XCTAssertThrowsError(try parser.parse(response)) { XCTAssertEqual($0 as? AdError, .http(code)) }
        }
    }

    func testSDKNoContentAndEmptyAdUnitReportNoAds() throws {
        let noContent: [String: Any] = ["status": true, "response": ["code": 204, "data": ""]]
        XCTAssertThrowsError(try parser.parse(noContent)) { XCTAssertEqual($0 as? AdError, .noAds) }
        let empty = try sdkEnvelope(["ads": ["banner_ads": []]])
        XCTAssertThrowsError(try parser.parse(empty)) { XCTAssertEqual($0 as? AdError, .noAds) }
    }

    func testSDKInvalidJSONAndNonObjectBodiesFailWithoutLeakingContent() {
        let bodies: [Any] = ["private server message", "<html>private</html>", "", "[]", "null", NSNull(), ["ads": [String: Any]()]]
        for body in bodies {
            let response: [String: Any] = ["status": true, "response": ["code": 200, "data": body]]
            XCTAssertThrowsError(try parser.parse(response)) {
                let error = $0 as? AdError
                XCTAssertNotNil(error?.diagnostic)
                XCTAssertFalse(error?.diagnostic?.contains("private") ?? true)
                XCTAssertFalse(error?.isRetryable ?? true)
            }
        }
    }

    func testSDKJSONBodySizeIsBounded() {
        let response: [String: Any] = ["status": true, "response": [
            "code": 200, "data": String(repeating: " ", count: 1_048_577)
        ]]
        XCTAssertThrowsError(try parser.parse(response)) {
            XCTAssertEqual(($0 as? AdError)?.diagnostic, "SDK response.data exceeds the 1 MiB JSON limit.")
        }
    }

    func testSDKDecodedBodyDiagnosticsAreRedacted() throws {
        let response = try sdkEnvelope(["data": FixtureAdService.response(), "message": "private server message"])
        XCTAssertThrowsError(try parser.parse(response)) {
            let diagnostic = ($0 as? AdError)?.diagnostic ?? ""
            XCTAssertTrue(diagnostic.contains("Decoded response.data rejected"))
            XCTAssertTrue(diagnostic.contains("data.ads.banner_ads=array(1)"))
            for secret in ["https://", "fixture-1", "private server message"] {
                XCTAssertFalse(diagnostic.contains(secret))
            }
        }
    }

    func testSDKDecodedBodyStillValidatesStatusAndTrackingIdentity() throws {
        var payload = FixtureAdService.response()
        payload["status"] = false
        XCTAssertThrowsError(try parser.parse(sdkEnvelope(payload)))
        var value = banner()
        value["click_tracking_url"] = "https://example.com/click?uclid=different"
        XCTAssertThrowsError(try parser.parse(sdkEnvelope(wrap(value)))) {
            let diagnostic = ($0 as? AdError)?.diagnostic ?? ""
            XCTAssertTrue(diagnostic.contains("consistent uclid tracking identity"))
            XCTAssertFalse(diagnostic.contains("https://"))
            XCTAssertFalse(diagnostic.contains("different"))
        }
    }

    func testEmptyAndMissingAdUnitsFailSafely() {
        let responses: [[String: Any]] = [["ads": ["banner_ads": []]], ["ads": [:]]]
        for response in responses {
            XCTAssertThrowsError(try parser.parse(response)) { XCTAssertEqual($0 as? AdError, .noAds) }
        }
        XCTAssertThrowsError(try parser.parse([:]))
        XCTAssertThrowsError(try parser.parse(["ads": ["banner_ads": "wrong type"]]))
    }

    func testFalseAndNonBooleanStatusesAreRejected() {
        let statuses: [Any] = [false, 1, "true", NSNull()]
        for status in statuses {
            var response = FixtureAdService.response()
            response["status"] = status
            XCTAssertThrowsError(try parser.parse(response))
        }
    }

    func testMissingRequiredFieldsAreRejected() {
        for key in ["width", "height", "impression_tracking_url", "click_tracking_url", "elements"] {
            var value = banner()
            value[key] = nil
            XCTAssertThrowsError(try parser.parse(wrap(value)), key)
        }
        var value = banner()
        var element = value["elements"] as? [String: Any] ?? [:]
        element["value"] = nil
        value["elements"] = element
        XCTAssertThrowsError(try parser.parse(wrap(value)))
    }

    func testCamelCaseDestinationInSDKEnvelope() throws {
        var value = banner()
        var element = try XCTUnwrap(value["elements"] as? [String: Any])
        element["destinationUrl"] = element.removeValue(forKey: "destination_url")
        // Match the observed live shape: dimensions are inside elements.
        element["width"] = value.removeValue(forKey: "width")
        element["height"] = value.removeValue(forKey: "height")
        value["elements"] = element
        let ad = try parser.parse(sdkEnvelope(wrap(value)))
        XCTAssertEqual(ad.destinationURL?.absoluteString, "https://example.com")
        XCTAssertEqual(ad.width, 1_200)
        XCTAssertEqual(ad.height, 750)
        XCTAssertEqual(ad.id, "fixture-1")
    }

    func testDestinationAliasesMustAgree() throws {
        var value = banner()
        var element = try XCTUnwrap(value["elements"] as? [String: Any])
        element["destinationUrl"] = element["destination_url"]
        value["elements"] = element
        XCTAssertEqual(try parser.parse(wrap(value)).destinationURL?.absoluteString, "https://example.com")
        element["destinationUrl"] = "https://other.example.com"
        value["elements"] = element
        XCTAssertThrowsError(try parser.parse(wrap(value))) {
            XCTAssertEqual($0 as? AdError, .invalidField("consistent destination URL"))
        }
    }

    func testObservedLiveShapeWithoutDestinationPreservesRenderableBanner() throws {
        var value = banner()
        value["width"] = nil
        value["height"] = nil
        value["elements"] = [
            "type": "IMAGE", "value": "https://images.example.invalid/banner.png",
            "width": 1_200, "height": 750,
            "omVerificationScripts": [["resource_url": "https://verification.example.invalid/script.js"]]
        ]
        // Existing click/impression URLs must not become substitute landing pages.
        for response in [wrap(value), try sdkEnvelope(wrap(value))] {
            let ad = try parser.parse(response)
            XCTAssertNil(ad.destinationURL)
            XCTAssertEqual(ad.imageURL.absoluteString, "https://images.example.invalid/banner.png")
            XCTAssertEqual(ad.width, 1_200)
            XCTAssertEqual(ad.height, 750)
            XCTAssertEqual(ad.id, "fixture-1")
        }
    }

    func testDestinationAliasDoesNotBypassURLValidation() throws {
        let invalid: [Any] = [NSNull(), 123, "", "javascript:alert(1)", "file:///private/file", "https://user:password@example.com", " https://example.com"]
        for raw in invalid {
            var value = banner()
            var element = try XCTUnwrap(value["elements"] as? [String: Any])
            element["destination_url"] = nil
            element["destinationUrl"] = raw
            value["elements"] = element
            XCTAssertThrowsError(try parser.parse(wrap(value)))
            element["destination_url"] = "https://example.com"
            value["elements"] = element
            XCTAssertThrowsError(try parser.parse(wrap(value)))
            element["destination_url"] = raw
            element["destinationUrl"] = "https://example.com"
            value["elements"] = element
            XCTAssertThrowsError(try parser.parse(wrap(value)))
        }
    }

    func testCamelCaseDestinationDiagnosticDoesNotExposeURL() {
        let payload: [String: Any] = ["ads": ["banner_ads": [["elements": [
            "destinationUrl": "https://example.com/private?token=secret"
        ]]]]]
        let summary = AdResponseDiagnostics.summary(payload)
        XCTAssertTrue(summary.contains("ads.banner_ads[0].elements.destinationUrl=string"))
        for secret in ["https://", "example.com", "private", "secret"] {
            XCTAssertFalse(summary.contains(secret))
        }
    }

    func testDimensionsRejectZeroNegativeBoolNaNAndHugeValues() {
        let values: [Any] = [0, -1, true, Double.leastNonzeroMagnitude, Double.nan, Double.infinity, "NaN", 100_001, NSNull()]
        for invalid in values {
            var value = banner()
            value["width"] = invalid
            XCTAssertThrowsError(try parser.parse(wrap(value)), "\(invalid)")
        }
    }

    func testNumericStringAndElementDimensionsAreSupported() throws {
        var value = banner()
        value["width"] = nil
        value["height"] = nil
        var element = value["elements"] as? [String: Any] ?? [:]
        element["width"] = "1200"
        element["height"] = "750"
        value["elements"] = element
        XCTAssertEqual(try parser.parse(wrap(value)).aspectRatio, 1.6, accuracy: 0.001)
    }

    func testExplicitImageElementInArrayIsSelected() throws {
        var value = banner()
        let element = try XCTUnwrap(value["elements"] as? [String: Any])
        value["elements"] = [["type": "text", "value": "not an image"], element]
        XCTAssertEqual(try parser.parse(wrap(value)).id, "fixture-1")
    }

    func testUnsupportedCreativeAndHTTPImagesAreRejected() {
        var value = banner()
        value["elements"] = ["type": "video", "value": "https://example.com/video.mp4"]
        XCTAssertThrowsError(try parser.parse(wrap(value)))
        value = banner()
        value["elements"] = ["type": "image", "value": "http://example.com/a.png", "destination_url": "https://example.com"]
        XCTAssertThrowsError(try parser.parse(wrap(value)))
    }

    func testConsistentUclidQueryFallback() throws {
        var value = banner()
        value["uclid"] = nil
        XCTAssertEqual(try parser.parse(wrap(value)).id, "fixture-1")
    }

    func testMissingOrConflictingIdentityFailsClosed() {
        var value = banner()
        value["click_tracking_url"] = "https://example.com/click?uclid=different"
        XCTAssertThrowsError(try parser.parse(wrap(value)))
        value = banner()
        value["uclid"] = nil
        value["impression_tracking_url"] = "https://example.com/impression"
        value["click_tracking_url"] = "https://example.com/click"
        XCTAssertThrowsError(try parser.parse(wrap(value)))
    }

    func testDiagnosticsShowEnvelopeAndStatusWithoutLeakingValues() {
        let response: [String: Any] = [
            "status": "success",
            "data": FixtureAdService.response(),
            "message": "sensitive server message",
            "private-user-key": "private value"
        ]
        let summary = AdResponseDiagnostics.summary(response)
        XCTAssertTrue(summary.contains("status=string(success)"))
        XCTAssertTrue(summary.contains("ads=missing"))
        XCTAssertTrue(summary.contains("data.ads.banner_ads=array(1)"))
        for secret in ["https://", "fixture-1", "sensitive server message", "private-user-key", "private value"] {
            XCTAssertFalse(summary.contains(secret), secret)
        }
    }

    func testDiagnosticsHandleUnexpectedTypesAndLimitOutput() {
        let summary = AdResponseDiagnostics.summary(["status": 200, "ads": NSNull()])
        XCTAssertTrue(summary.contains("status=number(200)"))
        XCTAssertTrue(summary.contains("ads=null"))
        let nested: [String: Any] = ["data": ["data": ["data": ["data": ["status": "private value"]]]]]
        XCTAssertFalse(AdResponseDiagnostics.summary(nested).contains("private value"))
        XCTAssertLessThanOrEqual(summary.components(separatedBy: "; ").count, 24)
    }

    func testDiagnosticsRevealUnmappedElementSchemaWithoutValues() throws {
        var value = banner()
        var element = try XCTUnwrap(value["elements"] as? [String: Any])
        element["destination_url"] = nil
        element["landing_href"] = "https://example.com/private?token=secret"
        value["elements"] = element
        let summary = AdResponseDiagnostics.summary(wrap(value))
        #if DEBUG
        XCTAssertTrue(summary.contains("elements.landing_href=string (unmapped)"))
        #else
        XCTAssertFalse(summary.contains("landing_href"))
        #endif
        for secret in ["https://", "example.com", "private", "secret"] {
            XCTAssertFalse(summary.contains(secret))
        }
        // Discovery must not silently treat an unknown field as a landing URL.
        XCTAssertNil(try parser.parse(wrap(value)).destinationURL)
    }

    func testUnmappedElementDiagnosticsAreScopedRedactedAndBounded() {
        let unsafeKey = "https://example.com/user?id=secret"
        let element: [String: Any] = [
            unsafeKey: "private value", "user_12345": "private ID",
            "unknown_nested": ["secretKey": "secretValue"],
            String(repeating: "a", count: 49): true
        ]
        let payload: [String: Any] = [
            "ads": ["banner_ads": [["elements": element]]],
            "outside_schema": "not an element field"
        ]
        let summary = AdResponseDiagnostics.summary(payload)
        for secret in [unsafeKey, "user_12345", "private", "secretKey", "secretValue", "outside_schema", String(repeating: "a", count: 49)] {
            XCTAssertFalse(summary.contains(secret))
        }
        XCTAssertLessThanOrEqual(summary.components(separatedBy: "; ").count, 24)
    }

    private func banner() -> [String: Any] {
        let ads = FixtureAdService.response()["ads"] as? [String: Any]
        return (ads?["banner_ads"] as? [[String: Any]])?.first ?? [:]
    }

    private func wrap(_ value: [String: Any]) -> [String: Any] {
        ["ads": ["banner_ads": [value]]]
    }

    private func sdkEnvelope(_ payload: [String: Any], code: Int = 200) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return ["status": true, "response": ["code": code, "data": String(decoding: data, as: UTF8.self)], "error": NSNull()]
    }
}