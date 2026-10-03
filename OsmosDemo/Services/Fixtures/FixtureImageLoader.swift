import Foundation
import CoreGraphics

final class FixtureImageLoader: ImageLoading {
    func image(for url: URL) async throws -> CGImage {
        try await sleepForRetry(0.25)
        if url.lastPathComponent == "broken.png" { throw AdError.imageUnavailable }
        let index = Int(url.deletingPathExtension().lastPathComponent) ?? 1
        return try Self.artwork(index: index)
    }

    /// Original, locally drawn artwork; not a captured real ad or a network fallback.
    static func artwork(index: Int) throws -> CGImage {
        let width = 1_200
        let height = 750
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw AdError.imageUnavailable
        }
        let palettes: [[CGColor]] = [
            [CGColor(red: 0.04, green: 0.24, blue: 0.24, alpha: 1), CGColor(red: 0.39, green: 0.68, blue: 0.57, alpha: 1)],
            [CGColor(red: 0.15, green: 0.16, blue: 0.37, alpha: 1), CGColor(red: 0.55, green: 0.51, blue: 0.76, alpha: 1)],
            [CGColor(red: 0.61, green: 0.25, blue: 0.16, alpha: 1), CGColor(red: 0.96, green: 0.65, blue: 0.41, alpha: 1)]
        ]
        let palette = palettes[abs(index % palettes.count)]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: palette as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero,
                                       end: CGPoint(x: width, y: height), options: [])
        }
        context.setFillColor(CGColor(red: 1, green: 0.92, blue: 0.68, alpha: 1))
        context.fillEllipse(in: CGRect(x: 830, y: 430, width: 170, height: 170))
        for layer in 0..<4 {
            let y = CGFloat(80 + layer * 60)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: y + 90))
            path.addCurve(to: CGPoint(x: 1_200, y: y + 80),
                          control1: CGPoint(x: 390, y: y + 400 - CGFloat(layer * 50)),
                          control2: CGPoint(x: 650, y: y - 130))
            path.addLine(to: CGPoint(x: 1_200, y: 0))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(CGColor(gray: layer % 2 == 0 ? 1 : 0, alpha: 0.12))
            context.fillPath()
        }
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.2))
        context.setLineWidth(2)
        for radius in stride(from: 70, through: 160, by: 30) {
            context.strokeEllipse(in: CGRect(x: 180 - radius, y: 460 - radius, width: radius * 2, height: radius * 2))
        }
        guard let image = context.makeImage() else { throw AdError.imageUnavailable }
        return image
    }
}