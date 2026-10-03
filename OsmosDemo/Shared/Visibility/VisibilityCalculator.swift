import CoreGraphics

enum VisibilityCalculator {
    static func fraction(creative: CGRect, viewport: CGRect, eligible: Bool = true) -> Double {
        guard eligible, valid(creative), valid(viewport) else { return 0 }
        let intersection = creative.intersection(viewport)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let area = creative.width * creative.height
        guard area.isFinite, area > 0 else { return 0 }
        return min(1, max(0, Double(intersection.width * intersection.height / area)))
    }

    static func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard valid(bounds), imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                      width: width, height: height)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite &&
        rect.height.isFinite && rect.width > 0 && rect.height > 0 && !rect.isNull
    }
}