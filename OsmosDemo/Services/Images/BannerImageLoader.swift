import Foundation
import CoreGraphics
import ImageIO

actor BannerImageLoader: ImageLoading {
    private final class CachedImage {
        let value: CGImage
        init(_ value: CGImage) { self.value = value }
    }

    private struct Flight {
        let task: Task<CGImage, Error>
        var consumers: Set<UUID>
    }

    private let session: URLSession
    private let cache = NSCache<NSURL, CachedImage>()
    private var flights: [URL: Flight] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            config.urlCache = URLCache(memoryCapacity: 4 * 1_024 * 1_024,
                                       diskCapacity: 16 * 1_024 * 1_024)
            self.session = URLSession(configuration: config)
        }
        cache.totalCostLimit = 24 * 1_024 * 1_024
        cache.countLimit = 20
    }

    func image(for url: URL) async throws -> CGImage {
        try Task.checkCancellation()
        if let cached = cache.object(forKey: url as NSURL) {
            LiveAdConsole.log("Image memory-cache hit: \(cached.value.width)x\(cached.value.height) decoded pixels. No new download.")
            return cached.value
        }
        let consumer = UUID()
        let task: Task<CGImage, Error>
        if var flight = flights[url] {
            LiveAdConsole.log("Image request joined an existing in-flight download.")
            flight.consumers.insert(consumer)
            flights[url] = flight
            task = flight.task
        } else {
            let session = self.session
            task = Task {
                // Local diagnostic ID, unrelated to the ad's tracking identity or URL.
                let trace = UUID().uuidString.prefix(8)
                LiveAdConsole.log("Image \(trace): download started (URL redacted).")
                do {
                    return try await Self.download(url, session: session, trace: String(trace))
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        LiveAdConsole.log("Image \(trace): download/decode cancelled.")
                    } else {
                        LiveAdConsole.log("Image \(trace): download/decode failed: \(AdError.normalize(error).localizedDescription)")
                    }
                    throw error
                }
            }
            flights[url] = Flight(task: task, consumers: [consumer])
        }
        return try await withTaskCancellationHandler {
            defer { release(url, consumer: consumer) }
            let image = try await task.value
            try Task.checkCancellation()
            cache.setObject(CachedImage(image), forKey: url as NSURL,
                            cost: image.bytesPerRow * image.height)
            return image
        } onCancel: {
            Task { await self.release(url, consumer: consumer) }
        }
    }

    private func release(_ url: URL, consumer: UUID) {
        guard var flight = flights[url], flight.consumers.remove(consumer) != nil else { return }
        if flight.consumers.isEmpty {
            flight.task.cancel()
            flights[url] = nil
        } else {
            flights[url] = flight
        }
    }

    private static func download(_ url: URL, session: URLSession, trace: String) async throws -> CGImage {
        guard URLPolicy.webURL(url.absoluteString, httpsOnly: true) != nil else {
            throw AdError.imageUnavailable
        }
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        if let http = response as? HTTPURLResponse {
            LiveAdConsole.log("Image \(trace): HTTP \(http.statusCode); image MIME=\(http.mimeType?.hasPrefix("image/") == true); final HTTPS=\(http.url?.scheme == "https"); declared bytes=\(http.expectedContentLength) (-1 means unknown).")
        } else {
            LiveAdConsole.log("Image \(trace): rejected non-HTTP response.")
        }
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode), response.url?.scheme == "https",
              response.mimeType?.hasPrefix("image/") == true else {
            throw AdError.imageUnavailable
        }
        let limit = 8 * 1_024 * 1_024
        guard response.expectedContentLength <= limit else { throw AdError.imageTooLarge }
        var data = Data()
        for try await byte in bytes {
            if data.count % 16_384 == 0 { try Task.checkCancellation() }
            guard data.count < limit else { throw AdError.imageTooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        LiveAdConsole.log("Image \(trace): received \(data.count) bytes. Starting image decode.")
        let image = try decode(data)
        LiveAdConsole.log("Image \(trace): decode SUCCESS, \(image.width)x\(image.height) pixels. Image content was received; these logs do not classify whether it is placeholder artwork.")
        return image
    }

    static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { throw AdError.imageUnavailable }
        guard width.doubleValue * height.doubleValue <= 80_000_000 else { throw AdError.imageTooLarge }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AdError.imageUnavailable
        }
        return image
    }
}