import SwiftUI

@MainActor
struct BannerAdView: View {
    let item: BannerItem
    let fraction: Double
    let isFixture: Bool
    @ObservedObject var tracker: AdEventTracker
    let onTap: () -> Void
    let onRetryImage: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var palette: FeedPalette { FeedPalette(scheme: scheme) }
    private var impression: ImpressionState? { tracker.impressions[item.id] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(format: "BANNER %02d", item.position))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .tracking(1.4)
                Spacer()
                Text(isFixture ? "SAMPLE CREATIVE" : "SPONSORED")
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundColor(palette.secondary)
            .padding(16)

            Button(action: onTap) {
                creative
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.image == nil)
            .accessibilityIdentifier("banner-\(item.position)")
            .accessibilityLabel("\(isFixture ? "Sample" : "Sponsored") banner \(item.position)")
            .accessibilityHint(item.ad.destinationURL == nil ? "Landing URL unavailable" : "Opens advertiser website")

            if let error = item.imageError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription).font(.caption).foregroundColor(palette.secondary)
                    Button("Retry Image", action: onRetryImage)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("retry-image-\(item.position)")
                        .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isFixture ? "A little room to explore." : "Discover something new.")
                            .font(.headline)
                        Label(item.ad.destinationURL?.host ?? "Landing URL unavailable",
                              systemImage: item.ad.destinationURL == nil ? "exclamationmark.circle" : "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(palette.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("\(Int(fraction * 100))%")
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .foregroundColor(palette.accent)
                        .accessibilityLabel("\(Int(fraction * 100)) percent visible")
                        .accessibilityIdentifier("visibility-\(item.position)")
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.line)
                        Capsule().fill(palette.accent)
                            .frame(width: geometry.size.width * CGFloat(min(1, max(0, fraction))))
                        Rectangle().fill(palette.secondary).frame(width: 1, height: 10)
                            .offset(x: geometry.size.width * 0.5)
                    }
                }
                .frame(height: 5)
                .accessibilityHidden(true)

                HStack {
                    Label(impression?.rawValue ?? "Awaiting 50%", systemImage: statusSymbol)
                        .font(.caption.weight(.medium))
                        .foregroundColor(impression == .failed ? .orange : palette.accent)
                        .accessibilityIdentifier("impression-\(item.position)")
                    Spacer()
                    Text("50% threshold").font(.caption2).foregroundColor(palette.secondary)
                }
            }
            .padding(16)
        }
        .foregroundColor(palette.ink)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.line, lineWidth: 1))
    }

    private var statusSymbol: String {
        switch impression {
        case .acknowledged, .simulated: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        case .submitted, .unconfirmed: return "paperplane"
        case nil: return "viewfinder"
        }
    }

    private var creative: some View {
        Rectangle()
            .fill(palette.line)
            .aspectRatio(CGFloat(item.ad.aspectRatio), contentMode: .fit)
            .overlay {
                if let image = item.image {
                    GeometryReader { geometry in
                        let bounds = geometry.frame(in: .named(FeedCoordinateSpace.viewport))
                        let rect = VisibilityCalculator.aspectFitRect(
                            imageSize: CGSize(width: image.width, height: image.height), in: bounds
                        )
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .preference(key: BannerFramesPreference.self, value: [item.id: rect])
                    }
                } else if item.imageError != nil {
                    VStack(spacing: 8) {
                        Image(systemName: "photo").font(.title2)
                        Text("Ad not available").font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(palette.secondary)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Preparing image…").font(.caption).foregroundColor(palette.secondary)
                    }
                }
            }
    }
}