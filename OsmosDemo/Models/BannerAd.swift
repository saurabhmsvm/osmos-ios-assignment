import Foundation

/// A served ad's uclid is stable across SwiftUI view recreation, unlike a row UUID.
struct BannerAd: Identifiable, Equatable {
    let id: String
    let imageURL: URL
    let destinationURL: URL?
    let impressionTrackingURL: URL
    let clickTrackingURL: URL
    let width: Double
    let height: Double

    var aspectRatio: Double { width / height }
}

enum AdError: Error, Equatable, LocalizedError {
    case initialization
    case noAds
    case invalidResponse
    case unexpectedResponse(String)
    case invalidField(String)
    case missingDestination
    case network
    case timeout
    case http(Int)
    case imageUnavailable
    case imageTooLarge
    case duplicateAd
    case eventRejected

    var isRetryable: Bool {
        switch self {
        case .network, .timeout: return true
        case .http(let code): return code == 408 || code == 429 || (500...599).contains(code)
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .initialization: return "The ad service could not initialize. Check its configuration."
        case .noAds: return "No banner was returned. Try again later."
        case .invalidResponse, .unexpectedResponse: return "The ad service returned an unsupported response."
        case .invalidField(let name): return "The ad is missing valid \(name)."
        case .missingDestination: return "The ad service returned a banner without a landing URL."
        case .network: return "Check your internet connection and try again."
        case .timeout: return "The ad service took too long to respond."
        case .http(let code): return "The server returned HTTP \(code)."
        case .imageUnavailable: return "The banner image could not be displayed."
        case .imageTooLarge: return "The banner image exceeds the safe size limit."
        case .duplicateAd: return "This served ad is already in the feed. Try again for another ad."
        case .eventRejected: return "Tracking was not acknowledged by the ad service."
        }
    }

    var diagnostic: String? {
        if case .unexpectedResponse(let detail) = self { return detail }
        if case .missingDestination = self {
            return "No supported landing URL field in the image element. Ask the ad provider to confirm the creative destination and response contract. Tracking URLs and verification scripts are not used as fallback destinations."
        }
        return nil
    }

    static func normalize(_ error: Error) -> AdError {
        if let error = error as? AdError { return error }
        if let error = error as? URLError {
            return error.code == .timedOut ? .timeout : .network
        }
        return .invalidResponse
    }
}

enum URLPolicy {
    static func webURL(_ text: String, httpsOnly: Bool = false) -> URL? {
        guard text == text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              httpsOnly ? scheme == "https" : ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        return components.url
    }
}