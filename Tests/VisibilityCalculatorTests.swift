import XCTest
import CoreGraphics
@testable import OsmosDemo

final class VisibilityCalculatorTests: XCTestCase {
    private let creative = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testExactThresholdAndBoundaryCases() {
        for (height, expected) in [(0.0, 0.0), (49.9, 0.499), (50.0, 0.5), (100.0, 1.0)] {
            let viewport = CGRect(x: 0, y: 0, width: 100, height: height)
            XCTAssertEqual(VisibilityCalculator.fraction(creative: creative, viewport: viewport), expected, accuracy: 0.00001)
        }
    }

    func testHorizontalAndVerticalClippingUsesAreaNotHeightOnly() {
        let viewport = CGRect(x: 50, y: 50, width: 100, height: 100)
        XCTAssertEqual(VisibilityCalculator.fraction(creative: creative, viewport: viewport), 0.25)
    }

    func testOffscreenHiddenAndZeroAreaNeverCount() {
        XCTAssertEqual(VisibilityCalculator.fraction(creative: creative, viewport: .zero), 0)
        XCTAssertEqual(VisibilityCalculator.fraction(creative: .zero, viewport: creative), 0)
        XCTAssertEqual(VisibilityCalculator.fraction(creative: creative, viewport: creative, eligible: false), 0)
        XCTAssertEqual(VisibilityCalculator.fraction(creative: creative.offsetBy(dx: 101, dy: 0), viewport: creative), 0)
        XCTAssertEqual(VisibilityCalculator.fraction(creative: .null, viewport: creative), 0)
    }

    func testOversizedCreativeDoesNotPretendToMeetThreshold() {
        let big = CGRect(x: 0, y: 0, width: 100, height: 1_000)
        XCTAssertEqual(VisibilityCalculator.fraction(creative: big, viewport: creative), 0.1)
    }

    func testAspectFitMeasurementExcludesLetterboxing() {
        let rect = VisibilityCalculator.aspectFitRect(imageSize: CGSize(width: 200, height: 100), in: creative)
        XCTAssertEqual(rect, CGRect(x: 0, y: 25, width: 100, height: 50))
        XCTAssertEqual(VisibilityCalculator.fraction(creative: rect, viewport: CGRect(x: 0, y: 0, width: 100, height: 50)), 0.5)
    }

    func testTranslatedCoordinateSpaceAndInvalidImageSize() {
        let rect = VisibilityCalculator.aspectFitRect(imageSize: CGSize(width: 100, height: 100), in: creative.offsetBy(dx: 25, dy: 40))
        XCTAssertEqual(rect.origin, CGPoint(x: 25, y: 40))
        XCTAssertEqual(VisibilityCalculator.aspectFitRect(imageSize: .zero, in: creative), .zero)
    }
}