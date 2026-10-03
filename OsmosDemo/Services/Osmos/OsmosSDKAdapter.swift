import Foundation
import CoreFoundation
import osmos

@MainActor
final class OsmosSDKAdapter: AdServing, AdEventSending {
    private let configuration: AdConfiguration
    private let sdk: OSMOS?
    let initializationError: AdError?
    private var fetchInProgress = false

    init(configuration: AdConfiguration = .assignment) {
        self.configuration = configuration
        do {
            try configuration.validate()
            let instance = try OSMOS.Builder()
                .clientId(configuration.clientID)
                .productAdsHost(configuration.productAdsHost)
                .displayAdsHost(configuration.displayAdsHost)
                .shareAdvertisingId(false)
                .debug(false)
                .enableBatchProcessing(false)
                .enableRetryBatchProcessing(false)
                .build()
            guard instance.adFetcher() != nil, instance.registerEvent() != nil else {
                throw AdError.initialization
            }
            sdk = instance
            initializationError = nil
            LiveAdConsole.log("SDK initialized. Awaiting Load Ad; no fetch has been issued.")
        } catch {
            sdk = nil
            initializationError = .initialization
            LiveAdConsole.log("SDK initialization failed. No ad can be fetched.")
        }
    }

    func fetchAd() async throws -> BannerAd {
        LiveAdConsole.log("Fetch requested: display ads via AU, productCount=1.")
        do {
            let ad = try await fetchBanner()
            LiveAdConsole.log("Banner parsed: image URL present; metadata size=\(ad.width)x\(ad.height); landing URL=\(ad.destinationURL == nil ? "MISSING" : "present"); tracking URLs and identity validated.")
            if ad.destinationURL == nil {
                LiveAdConsole.log("Missing landing URL does NOT block the image. Navigation will be skipped.")
            }
            return ad
        } catch {
            if error is CancellationError || Task.isCancelled {
                LiveAdConsole.log("Fetch cancelled; any late response is discarded.")
            } else {
                let failure = AdError.normalize(error)
                LiveAdConsole.log("Fetch/parse failed: \(failure.localizedDescription)")
                if let diagnostic = failure.diagnostic { LiveAdConsole.log(diagnostic) }
            }
            throw error
        }
    }

    private func fetchBanner() async throws -> BannerAd {
        guard let fetcher = sdk?.adFetcher() else { throw AdError.initialization }
        guard !fetchInProgress else { throw AdError.invalidResponse }
        fetchInProgress = true
        defer { fetchInProgress = false }
        try Task.checkCancellation()
        let captured = SDKErrorCapture()
        let response = await fetcher.fetchDisplayAdsWithAu(
            cliUbid: configuration.cliUbid, pageType: configuration.pageType,
            productCount: 1, adUnits: [configuration.adUnit], targetingParams: nil,
            onError: { captured.store($0) }
        )
        try Task.checkCancellation()
        if let error = captured.error {
            LiveAdConsole.log("SDK error callback received; banner parsing will not proceed.")
            throw error
        }
        guard let response else {
            LiveAdConsole.log("SDK returned NO response dictionary.")
            throw AdError.unexpectedResponse("SDK returned nil without an error callback.")
        }
        LiveAdConsole.log("SDK response received: " + AdResponseDiagnostics.summary(response))
        do {
            return try BannerResponseParser(adUnit: configuration.adUnit).parse(response)
        } catch AdError.invalidResponse {
            throw AdError.unexpectedResponse("Parser rejected response: " + AdResponseDiagnostics.summary(response))
        }
    }

    func sendImpression(for ad: BannerAd, position: Int) async throws -> EventReceipt {
        guard let events = sdk?.registerEvent() else { throw AdError.initialization }
        let captured = SDKErrorCapture()
        let response = await events.registerAdImpressionEvent(
            cliUbid: configuration.cliUbid, uclid: ad.id, position: position,
            trackingParams: nil, onError: { captured.store($0) }
        )
        return try receipt(response, error: captured.error)
    }

    func sendClick(for ad: BannerAd) async throws -> EventReceipt {
        guard let events = sdk?.registerEvent() else { throw AdError.initialization }
        let captured = SDKErrorCapture()
        let response = await events.registerAdClickEvent(
            cliUbid: configuration.cliUbid, uclid: ad.id,
            trackingParams: nil, onError: { captured.store($0) }
        )
        return try receipt(response, error: captured.error)
    }

    private func receipt(_ response: [String: Any]?, error: AdError?) throws -> EventReceipt {
        if let error { throw error }
        guard let response else { throw AdError.eventRejected }
        if let rawStatus = response["status"] {
            guard let status = rawStatus as? NSNumber,
                  CFGetTypeID(status) == CFBooleanGetTypeID(), status.boolValue else {
                throw AdError.eventRejected
            }
            return .acknowledged
        }
        // A non-nil response alone is not proof of successful server registration.
        return .unconfirmed
    }
}

/// The SDK does not document callback executor affinity. Protect callback state explicitly.
private final class SDKErrorCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AdError?

    var error: AdError? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func store(_ error: OsmosError) {
        let mapped: AdError
        switch error {
        case .networkUnavailable: mapped = .network
        case .connectionTimeout: mapped = .timeout
        case .badStatus(let code, _): mapped = .http(code)
        case .notInitialized, .alreadyInitialized, .missingClientId, .missingConfiguration,
             .missingDisplayAdConfig, .missingPlaAdConfig, .missingRegisterEventConfig:
            mapped = .initialization
        case .defaultError(let underlying):
            let normalized = AdError.normalize(underlying)
            mapped = normalized == .invalidResponse
                ? .unexpectedResponse("SDK callback: defaultError; no readable ad response.") : normalized
        case .badResponse: mapped = .unexpectedResponse("SDK callback: badResponse; rejected before app parsing.")
        case .failedToDecode: mapped = .unexpectedResponse("SDK callback: failedToDecode; rejected before app parsing.")
        case .failedToEncode: mapped = .unexpectedResponse("SDK callback: failedToEncode; request encoding failed.")
        case .badUrl: mapped = .unexpectedResponse("SDK callback: badUrl; request URL was invalid.")
        case .invalidRequest: mapped = .unexpectedResponse("SDK callback: invalidRequest; request was rejected.")
        default: mapped = .unexpectedResponse("SDK callback: unrecognized error; no readable ad response.")
        }
        lock.lock()
        stored = mapped
        lock.unlock()
    }
}