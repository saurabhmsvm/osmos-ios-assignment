import Foundation

enum DemoScenario: String, CaseIterable, Identifiable {
    case live
    case success
    case missingDestination
    case noAds
    case malformed
    case offline
    case timeout
    case transient
    case imageFailure
    case initializationFailure
    case eventFailure
    case duplicate

    var id: String { rawValue }
    var title: String {
        switch self {
        case .live: return "Live Osmos"
        case .success: return "Successful ads"
        case .missingDestination: return "Missing landing URL"
        case .noAds: return "No ads returned"
        case .malformed: return "Invalid response"
        case .offline: return "Offline"
        case .timeout: return "Request timeout"
        case .transient: return "Retry then recover"
        case .imageFailure: return "Broken image"
        case .initializationFailure: return "SDK unavailable"
        case .eventFailure: return "Tracking failure"
        case .duplicate: return "Duplicate identity"
        }
    }

    var detail: String {
        switch self {
        case .live: return "Real SDK requests and tracking events."
        case .success: return "Local banners; no ad or tracking network requests."
        case .missingDestination: return "Image and impressions work; taps show a message without navigation or click tracking."
        case .noAds: return "An empty banner list with safe fallback."
        case .malformed: return "A required image URL is missing."
        case .offline: return "Three failed attempts, then manual Retry."
        case .timeout: return "A timed-out fetch uses bounded retries."
        case .transient: return "The first attempt fails; the next succeeds."
        case .imageFailure: return "Metadata loads, but the image cannot render."
        case .initializationFailure: return "Initialization fails without a crash."
        case .eventFailure: return "Ads render, but event registration fails."
        case .duplicate: return "Repeated served identity is not appended twice."
        }
    }
}