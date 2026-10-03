import Foundation
import Combine
import CoreGraphics

enum FeedLoadState: Equatable {
    case idle
    case loading
    case retrying(attempt: Int)
    case ready
    case failed(AdError)

    var isBusy: Bool {
        switch self {
        case .loading, .retrying: return true
        default: return false
        }
    }
}

struct BannerItem: Identifiable {
    let ad: BannerAd
    let position: Int
    var image: CGImage?
    var imageError: AdError?
    var id: String { ad.id }
}

@MainActor
final class AdFeedViewModel: ObservableObject {
    @Published private(set) var items: [BannerItem] = []
    @Published private(set) var loadState: FeedLoadState = .idle
    @Published private(set) var fractions: [String: Double] = [:]
    @Published private(set) var navigationMessage: String?
    @Published private(set) var toastMessage: String?
    @Published private(set) var toastID: UUID?
    @Published private(set) var openingDestination = false

    let analytics: AnalyticsStore
    let tracker: AdEventTracker
    let isFixture: Bool
    let modeTitle: String
    let initializationError: AdError?
    let maxBannerCount = 20

    private let service: AdServing
    private let imageLoader: ImageLoading
    private let retryPolicy: RetryPolicy
    private let sleeper: AsyncSleeper
    private let now: () -> Date
    private var loadTask: Task<Void, Never>?
    private var loadToken: UUID?
    private var imageTasks: [String: Task<Void, Never>] = [:]
    private var rectangles: [String: CGRect] = [:]
    private var viewport: CGRect = .zero
    private var sceneActive = false
    private var screenVisible = false
    private var overlayPresented = false
    private var lastTap: Date?

    init(service: AdServing, imageLoader: ImageLoading, tracker: AdEventTracker,
         analytics: AnalyticsStore, isFixture: Bool, modeTitle: String,
         retryPolicy: RetryPolicy = .standard,
         sleeper: @escaping AsyncSleeper = sleepForRetry,
         now: @escaping () -> Date = Date.init) {
        self.service = service
        self.imageLoader = imageLoader
        self.tracker = tracker
        self.analytics = analytics
        self.isFixture = isFixture
        self.modeTitle = modeTitle
        self.initializationError = service.initializationError
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
        self.now = now
        if let error = service.initializationError {
            loadState = .failed(error)
            analytics.record("Ad Failed", error.localizedDescription)
        }
    }

    var canLoad: Bool { !loadState.isBusy && items.count < maxBannerCount }
    var eligible: Bool { sceneActive && screenVisible && !overlayPresented }

    func loadAd() {
        guard canLoad else { return }
        navigationMessage = nil
        clearToast()
        let token = UUID()
        loadToken = token
        loadState = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(token: token)
        }
    }

    private func performLoad(token: UUID) async {
        defer {
            if loadToken == token {
                loadTask = nil
                loadToken = nil
            }
        }
        var attempt = 1
        while true {
            do {
                try Task.checkCancellation()
                let ad = try await service.fetchAd()
                try Task.checkCancellation()
                guard loadToken == token else { return }
                guard !items.contains(where: { $0.id == ad.id }) else { throw AdError.duplicateAd }
                let position = items.count + 1
                items.append(BannerItem(ad: ad, position: position))
                loadState = .ready
                analytics.record("Ad Loaded", "Ad \(position) · attempt \(attempt)\(isFixture ? " · fixture" : " · live SDK")")
                if ad.destinationURL == nil {
                    analytics.record("Ad Warning", AdError.missingDestination.localizedDescription)
                    showMissingDestinationToast()
                }
                startImage(for: ad)
                return
            } catch {
                guard loadToken == token else { return }
                if Task.isCancelled || error is CancellationError {
                    loadState = items.isEmpty ? .idle : .ready
                    return
                }
                let failure = AdError.normalize(error)
                if let diagnostic = failure.diagnostic {
                    analytics.record("Response Diagnostic", diagnostic)
                }
                guard let delay = retryPolicy.retryDelay(afterAttempt: attempt, error: failure) else {
                    loadState = .failed(failure)
                    analytics.record("Ad Failed", "Attempt \(attempt) · \(failure.localizedDescription)")
                    return
                }
                attempt += 1
                loadState = .retrying(attempt: attempt)
                analytics.record("Retry Scheduled", "Attempt \(attempt) of \(retryPolicy.maxAttempts)")
                do {
                    try await sleeper(delay)
                } catch {
                    loadState = items.isEmpty ? .idle : .ready
                    return
                }
            }
        }
    }

    private func startImage(for ad: BannerAd) {
        guard imageTasks[ad.id] == nil else { return }
        let loader = imageLoader
        imageTasks[ad.id] = Task { [weak self] in
            do {
                let image = try await loader.image(for: ad.imageURL)
                try Task.checkCancellation()
                self?.finishImage(image, for: ad.id)
            } catch {
                if !Task.isCancelled, !(error is CancellationError) {
                    self?.failImage(for: ad.id, error: AdError.normalize(error))
                }
            }
            self?.imageTasks[ad.id] = nil
        }
    }

    func retryImage(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), imageTasks[id] == nil else { return }
        items[index].imageError = nil
        startImage(for: items[index].ad)
    }

    private func finishImage(_ image: CGImage, for id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].image = image
        items[index].imageError = nil
        // Measurement only arrives once SwiftUI has actually inserted the rendered image.
        // Do not count a placeholder rectangle at network completion time.
        analytics.record("Image Ready", "Ad \(items[index].position)")
        if !isFixture {
            LiveAdConsole.log("Ad \(items[index].position): decoded image assigned to SwiftUI state (\(image.width)x\(image.height) pixels). Awaiting view layout.")
        }
    }

    private func failImage(for id: String, error: AdError) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].imageError = error
        rectangles[id] = nil
        fractions[id] = nil
        analytics.record("Ad Failed", "Ad \(items[index].position) · \(error.localizedDescription)")
        if !isFixture {
            LiveAdConsole.log("Ad \(items[index].position): image unavailable; showing image-error UI. \(error.localizedDescription)")
        }
    }

    func updateGeometry(_ rectangles: [String: CGRect], viewport: CGRect) {
        guard rectangles != self.rectangles || viewport != self.viewport else { return }
        self.rectangles = rectangles
        self.viewport = viewport
        evaluateVisibility()
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if !active {
            clearToast()
            // Keep the in-flight guard until the SDK returns, even if it ignores cancellation.
            loadTask?.cancel()
        }
        evaluateVisibility()
    }

    func setScreenVisible(_ visible: Bool) {
        screenVisible = visible
        if !visible { clearToast() }
        evaluateVisibility()
    }

    func setOverlayPresented(_ presented: Bool) {
        overlayPresented = presented
        evaluateVisibility()
    }

    func removeGeometry(id: String) {
        rectangles[id] = nil
        fractions[id] = nil
    }

    private func evaluateVisibility() {
        var updated: [String: Double] = [:]
        for item in items where item.image != nil {
            guard let rect = rectangles[item.id] else { continue }
            let fraction = VisibilityCalculator.fraction(creative: rect, viewport: viewport, eligible: eligible)
            // Published indicators use integer percentages; threshold uses unrounded geometry.
            updated[item.id] = floor(fraction * 100) / 100
            if fraction >= 0.5 {
                tracker.impression(for: item.ad, position: item.position, fraction: fraction)
            }
        }
        if fractions != updated { fractions = updated }
    }

    /// Returns a validated destination; the view supplies SwiftUI's environment openURL action.
    func beginClick(id: String) -> URL? {
        guard eligible, !openingDestination,
              let item = items.first(where: { $0.id == id }), item.image != nil else { return nil }
        let date = now()
        if let lastTap, date.timeIntervalSince(lastTap) < 0.7 { return nil }
        lastTap = date
        guard let destination = item.ad.destinationURL else {
            showMissingDestinationToast()
            analytics.record("Navigation Unavailable", "Ad \(item.position) · missing landing URL; click not submitted")
            return nil
        }
        guard URLPolicy.webURL(destination.absoluteString) != nil else { return nil }
        openingDestination = true
        navigationMessage = nil
        tracker.click(for: item.ad, position: item.position)
        return destination
    }

    private func showMissingDestinationToast() {
        toastMessage = "Landing URL unavailable. This banner cannot open a website."
        toastID = UUID()
    }

    func dismissToast(id: UUID) {
        guard toastID == id else { return }
        clearToast()
    }

    private func clearToast() {
        toastMessage = nil
        toastID = nil
    }

    func finishOpening(accepted: Bool) {
        openingDestination = false
        if !accepted {
            navigationMessage = "The destination could not be opened. Please try again."
            analytics.record("Navigation Failed", "System declined the destination")
        } else {
            analytics.record("Destination Opened", "System accepted URL; page load is not verified")
        }
    }

    func stop() {
        screenVisible = false
        clearToast()
        loadTask?.cancel()
        for task in imageTasks.values { task.cancel() }
        rectangles = [:]
        fractions = [:]
    }
}