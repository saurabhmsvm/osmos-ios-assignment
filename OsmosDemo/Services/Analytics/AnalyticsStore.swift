import Foundation
import Combine
import OSLog

struct AnalyticsEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let name: String
    let detail: String
}

@MainActor
final class AnalyticsStore: ObservableObject {
    @Published private(set) var entries: [AnalyticsEntry] = []
    private let logger = Logger(subsystem: "com.osmos.assignment.demo", category: "Ads")
    private let capacity = 100

    func record(_ name: String, _ detail: String) {
        // Callers only supply local row numbers and sanitized errors, never tracking URLs.
        logger.info("\(name, privacy: .public): \(detail, privacy: .public)")
        entries.insert(AnalyticsEntry(name: name, detail: detail), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }
}