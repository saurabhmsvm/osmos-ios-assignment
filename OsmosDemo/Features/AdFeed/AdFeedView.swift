import SwiftUI

@MainActor
struct AdFeedView: View {
    @ObservedObject var model: AdFeedViewModel
    let onShowScenarios: () -> Void
    let onShowEvents: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var frames: [String: CGRect] = [:]

    private var palette: FeedPalette { FeedPalette(scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.line)
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        if model.items.isEmpty { emptyState }
                        ForEach(model.items) { item in
                            BannerAdView(item: item, fraction: model.fractions[item.id] ?? 0,
                                         isFixture: model.isFixture, tracker: model.tracker,
                                         onTap: { openDestination(id: item.id) },
                                         onRetryImage: { model.retryImage(id: item.id) })
                                .onDisappear { model.removeGeometry(id: item.id) }
                        }
                        if !model.items.isEmpty {
                            Label("An impression counts once. Scrolling back won't count again.", systemImage: "checkmark.shield")
                                .font(.caption)
                                .foregroundColor(palette.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }
                    }
                    .frame(maxWidth: 650)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
                .accessibilityIdentifier("ad-feed")
                .onPreferenceChange(BannerFramesPreference.self) { next in
                    frames = next
                    model.updateGeometry(next, viewport: CGRect(origin: .zero, size: viewport.size))
                }
                .onChange(of: viewport.size) { size in
                    model.updateGeometry(frames, viewport: CGRect(origin: .zero, size: size))
                }
            }
            .coordinateSpace(name: FeedCoordinateSpace.viewport)
            footer
        }
        .background(palette.background.ignoresSafeArea())
        .foregroundColor(palette.ink)
        .onAppear {
            model.setScreenVisible(true)
            model.setSceneActive(scenePhase == .active)
        }
        .onDisappear { model.setScreenVisible(false) }
        .onChange(of: scenePhase) { model.setSceneActive($0 == .active) }
        .task(id: model.toastID) {
            guard let id = model.toastID else { return }
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                try Task.checkCancellation()
                model.dismissToast(id: id)
            } catch { /* View disappearance or a newer toast cancels dismissal. */ }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.title2).foregroundColor(palette.accent)
                    .accessibilityHidden(true)
                Text("osmos").font(.system(.title2, design: .rounded).weight(.bold))
                Text("AD LAB").font(.system(.caption2, design: .monospaced)).tracking(1.5)
                    .foregroundColor(palette.secondary)
                Spacer()
                Button(action: onShowEvents) {
                    Image(systemName: "list.bullet.rectangle").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Event log")
                .accessibilityIdentifier("event-log")
                #if DEBUG
                Button(action: onShowScenarios) {
                    Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Demo scenarios")
                .accessibilityIdentifier("demo-scenarios")
                #endif
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Display, measured.").font(.title2.weight(.bold))
                    Text("Load a banner. Scroll to see visibility in action.")
                        .font(.subheadline).foregroundColor(palette.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Circle().fill(model.initializationError == nil ? palette.accent : .orange).frame(width: 6, height: 6)
                Text(model.isFixture ? "FIXTURE · \(model.modeTitle)" : (model.initializationError == nil ? "LIVE · SDK ready" : "LIVE · SDK unavailable"))
                    .font(.system(.caption2, design: .monospaced))
                    .accessibilityIdentifier("mode-status")
                Spacer()
                Text("\(model.items.count) / \(model.maxBannerCount) ads")
                    .font(.system(.caption2, design: .monospaced))
                    .accessibilityIdentifier("ad-count")
            }
            .foregroundColor(palette.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 38, weight: .light)).foregroundColor(palette.accent)
                Spacer()
                Text("01 / LOAD\n02 / VIEW\n03 / EXPLORE")
                    .font(.system(.caption2, design: .monospaced))
                    .lineSpacing(6).foregroundColor(palette.secondary)
            }
            Text("Your next impression\nstarts here.")
                .font(.system(.title, design: .rounded).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("A banner is counted only when at least half of its image is visible. Tap Load Ad to get started.")
                .font(.subheadline).foregroundColor(palette.secondary)
            Label(model.isFixture ? "Local artwork. No real tracking." : "Manual rendering · Real SDK tracking", systemImage: "checkmark.seal")
                .font(.caption.weight(.medium)).foregroundColor(palette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.line, style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
        .padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Reserve footer space rather than cover a measured banner image.
            if let message = model.toastMessage, let id = model.toastID {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                    Text(message).font(.subheadline)
                        .accessibilityIdentifier("missing-url-toast")
                    Spacer(minLength: 0)
                    Button { model.dismissToast(id: id) } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Dismiss message")
                }
                .foregroundColor(palette.ink)
                .padding(.leading, 12)
                .background(palette.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if case .failed(let error) = model.loadState {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Ad not available", systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.semibold))
                    Text(error.localizedDescription).font(.caption).foregroundColor(palette.secondary)
                }
                .accessibilityIdentifier("ad-error")
            }
            if let message = model.navigationMessage {
                Text(message).font(.caption).foregroundColor(.orange)
            }
            Button(action: model.loadAd) {
                HStack(spacing: 9) {
                    if model.loadState.isBusy { ProgressView().tint(.white) }
                    else { Image(systemName: "plus") }
                    Text(buttonTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canLoad)
            .accessibilityLabel(buttonTitle)
            .accessibilityIdentifier("load-ad")
            if model.items.count >= model.maxBannerCount {
                Text("Feed limit reached. Relaunch to start a new session.").font(.caption).foregroundColor(palette.secondary)
            } else if model.isFixture {
                Text("Demo mode · Events are simulated, not sent to Osmos.")
                    .font(.caption2).foregroundColor(palette.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
    }

    private var buttonTitle: String {
        switch model.loadState {
        case .loading: return "Loading Ad…"
        case .retrying(let attempt): return "Retrying · attempt \(attempt) of 3"
        case .failed: return "Retry"
        default: return "Load Ad"
        }
    }

    private func openDestination(id: String) {
        guard let url = model.beginClick(id: id) else { return }
        openURL(url) { accepted in
            Task { @MainActor in model.finishOpening(accepted: accepted) }
        }
    }
}