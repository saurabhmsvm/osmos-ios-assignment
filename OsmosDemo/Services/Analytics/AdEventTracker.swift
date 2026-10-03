import Foundation
import Combine

enum ImpressionState: String {
    case submitted = "Submitted"
    case acknowledged = "Acknowledged"
    case unconfirmed = "Unconfirmed"
    case simulated = "Simulated"
    case failed = "Failed"
}

@MainActor
final class AdEventTracker: ObservableObject {
    @Published private(set) var impressions: [String: ImpressionState] = [:]
    @Published private(set) var clickCount = 0
    private let sender: AdEventSending
    private let analytics: AnalyticsStore
    private let simulated: Bool
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(sender: AdEventSending, analytics: AnalyticsStore, simulated: Bool) {
        self.sender = sender
        self.analytics = analytics
        self.simulated = simulated
    }

    func impression(for ad: BannerAd, position: Int, fraction: Double) {
        guard fraction.isFinite, fraction >= 0.5, impressions[ad.id] == nil else { return }
        // Reserve before launching work. Row lifetime, retries, and re-entrancy cannot reset it.
        impressions[ad.id] = .submitted
        analytics.record("Impression Fired", "Ad \(position) · \(Int(fraction * 100))% visible\(suffix)")
        let taskID = UUID()
        tasks[taskID] = Task { [weak self, sender] in
            do {
                let receipt = try await sender.sendImpression(for: ad, position: position)
                self?.completeImpression(ad.id, position: position, receipt: receipt)
            } catch {
                self?.impressions[ad.id] = .failed
                self?.analytics.record("Tracking Failed", "Ad \(position) · impression · \(AdError.normalize(error).localizedDescription)")
            }
            self?.tasks[taskID] = nil
        }
    }

    func click(for ad: BannerAd, position: Int) {
        clickCount += 1
        analytics.record("Click Fired", "Ad \(position) · submitted\(suffix)")
        let taskID = UUID()
        tasks[taskID] = Task { [weak self, sender] in
            do {
                let receipt = try await sender.sendClick(for: ad)
                self?.analytics.record("Click Result", "Ad \(position) · \(Self.label(receipt))")
            } catch {
                self?.analytics.record("Tracking Failed", "Ad \(position) · click · \(AdError.normalize(error).localizedDescription)")
            }
            self?.tasks[taskID] = nil
        }
    }

    private var suffix: String { simulated ? " · fixture, no network event" : " · SDK submission" }

    private func completeImpression(_ id: String, position: Int, receipt: EventReceipt) {
        switch receipt {
        case .acknowledged: impressions[id] = .acknowledged
        case .unconfirmed: impressions[id] = .unconfirmed
        case .simulated: impressions[id] = .simulated
        }
        analytics.record("Impression Result", "Ad \(position) · \(Self.label(receipt))")
    }

    private static func label(_ receipt: EventReceipt) -> String {
        switch receipt {
        case .acknowledged: return "server acknowledged"
        case .unconfirmed: return "response received; delivery unconfirmed"
        case .simulated: return "simulated locally"
        }
    }
}