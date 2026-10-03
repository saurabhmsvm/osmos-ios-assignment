import XCTest
import ImageIO
import CoreGraphics
@testable import OsmosDemo

final class BannerImageLoaderTests: XCTestCase {
    func testCorruptImageIsRejected() {
        XCTAssertThrowsError(try BannerImageLoader.decode(Data("not an image".utf8)))
    }

    func testValidImageDecodesWithoutChangingAspectRatio() throws {
        let decoded = try BannerImageLoader.decode(png())
        XCTAssertEqual(Double(decoded.width) / Double(decoded.height), 1.6, accuracy: 0.001)
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 1_600)
    }

    func testRepeatedLoadsUseDecodedImageCache() async throws {
        ImageURLProtocol.configure(data: try png())
        let loader = makeLoader()
        let url = try XCTUnwrap(URL(string: "https://images.example.invalid/banner.png"))
        let first = try await loader.image(for: url)
        let second = try await loader.image(for: url)
        XCTAssertEqual(first.width, second.width)
        XCTAssertEqual(ImageURLProtocol.requestCount, 1)
    }

    func testConcurrentConsumersShareDownload() async throws {
        ImageURLProtocol.configure(data: try png())
        let loader = makeLoader()
        let url = try XCTUnwrap(URL(string: "https://images.example.invalid/shared.png"))
        async let first = loader.image(for: url)
        async let second = loader.image(for: url)
        let images = try await (first, second)
        XCTAssertEqual(images.0.width, images.1.width)
        XCTAssertEqual(ImageURLProtocol.requestCount, 1)
    }

    func testOversizedResponseIsRejectedBeforeDecode() async throws {
        ImageURLProtocol.configure(data: Data(), declaredLength: 9 * 1_024 * 1_024)
        let url = try XCTUnwrap(URL(string: "https://images.example.invalid/large.png"))
        do {
            _ = try await makeLoader().image(for: url)
            XCTFail("Oversized image should fail")
        } catch {
            XCTAssertEqual(error as? AdError, .imageTooLarge)
        }
    }

    func testHTTPFailureIsRejected() async throws {
        ImageURLProtocol.configure(data: Data(), status: 404)
        let url = try XCTUnwrap(URL(string: "https://images.example.invalid/missing.png"))
        do {
            _ = try await makeLoader().image(for: url)
            XCTFail("404 should fail")
        } catch {
            XCTAssertEqual(error as? AdError, .imageUnavailable)
        }
    }

    func testAlreadyCancelledConsumerDoesNotDownload() async throws {
        ImageURLProtocol.configure(data: Data())
        let loader = makeLoader()
        let url = try XCTUnwrap(URL(string: "https://images.example.invalid/cancelled.png"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.image(for: url)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled consumer should throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(ImageURLProtocol.requestCount, 0)
    }

    private func makeLoader() -> BannerImageLoader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageURLProtocol.self]
        config.urlCache = nil
        return BannerImageLoader(session: URLSession(configuration: config))
    }

    private func png() throws -> Data {
        let image = try FixtureImageLoader.artwork(index: 1)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class ImageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var data = Data()
    private static var status = 200
    private static var length = 0
    private static var count = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    static func configure(data: Data, status: Int = 200, declaredLength: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        self.data = data
        self.status = status
        self.length = declaredLength ?? data.count
        count = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "images.example.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let data = Self.data
        let status = Self.status
        let length = Self.length
        Self.count += 1
        Self.lock.unlock()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "image/png", "Content-Length": "\(length)"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}