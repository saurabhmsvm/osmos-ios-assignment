import SwiftUI

struct BannerFramesPreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum FeedCoordinateSpace {
    static let viewport = "ad-feed-viewport"
}