import Foundation
import CoreFoundation

/// SDK dictionaries are confined to the integration boundary, never exposed to views.
struct BannerResponseParser {
    let adUnit: String

    func parse(_ response: [String: Any]) throws -> BannerAd {
        // Live SDK 2.6.4 wraps the body in response.data as a string.
        // Keep direct payload support for fixtures and already-decoded callers.
        guard response["response"] != nil else { return try parsePayload(response) }
        guard let status = response["status"] as? NSNumber,
              CFGetTypeID(status) == CFBooleanGetTypeID(), status.boolValue,
              let envelope = response["response"] as? [String: Any],
              let code = envelope["code"] as? NSNumber,
              CFGetTypeID(code) != CFBooleanGetTypeID(),
              code.doubleValue.isFinite,
              (100...599).contains(code.doubleValue),
              code.doubleValue.rounded() == code.doubleValue else {
            throw AdError.invalidResponse
        }
        guard (200...299).contains(code.intValue) else { throw AdError.http(code.intValue) }
        if code.intValue == 204 { throw AdError.noAds }
        guard let text = envelope["data"] as? String else {
            throw AdError.unexpectedResponse("SDK response.data is not a JSON string.")
        }
        // Bound decoding work and never include the raw body in an error/log.
        guard text.utf8.count <= 1_048_576 else {
            throw AdError.unexpectedResponse("SDK response.data exceeds the 1 MiB JSON limit.")
        }
        guard let payload = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            throw AdError.unexpectedResponse("SDK response.data is not a valid JSON object.")
        }
        do {
            return try parsePayload(payload)
        } catch AdError.invalidResponse {
            throw AdError.unexpectedResponse("Decoded response.data rejected: " + AdResponseDiagnostics.summary(payload))
        } catch AdError.invalidField(let field) {
            throw AdError.unexpectedResponse("Decoded response.data has invalid " + field + ": " + AdResponseDiagnostics.summary(payload))
        }
    }

    private func parsePayload(_ response: [String: Any]) throws -> BannerAd {
        if let status = response["status"] {
            guard let number = status as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID(), number.boolValue else {
                throw AdError.invalidResponse
            }
        }
        guard let ads = response["ads"] as? [String: Any] else {
            throw AdError.invalidResponse
        }
        guard let value = ads[adUnit] else { throw AdError.noAds }
        guard let banners = value as? [[String: Any]] else { throw AdError.invalidResponse }
        guard let banner = banners.first else { throw AdError.noAds }
        let element = try imageElement(in: banner)
        let imageURL = try url(element["value"], field: "image URL", httpsOnly: true)
        let destination = try destinationURL(in: element)
        let impression = try url(banner["impression_tracking_url"], field: "impression tracking URL", httpsOnly: true)
        let click = try url(banner["click_tracking_url"], field: "click tracking URL", httpsOnly: true)
        let width = try dimension(banner["width"] ?? element["width"], field: "width")
        let height = try dimension(banner["height"] ?? element["height"], field: "height")
        let identity = try trackingIdentity(banner: banner, urls: [impression, click])
        return BannerAd(id: identity, imageURL: imageURL, destinationURL: destination,
                        impressionTrackingURL: impression, clickTrackingURL: click,
                        width: width, height: height)
    }

    private func imageElement(in banner: [String: Any]) throws -> [String: Any] {
        let element: [String: Any]
        if let object = banner["elements"] as? [String: Any] {
            element = object
        } else if let array = banner["elements"] as? [[String: Any]],
                  let image = array.first(where: { ($0["type"] as? String)?.lowercased() == "image" }) {
            element = image
        } else {
            throw AdError.invalidField("image elements")
        }
        if let type = element["type"] as? String, type.lowercased() != "image" {
            throw AdError.invalidField("image element type")
        }
        return element
    }

    private func destinationURL(in element: [String: Any]) throws -> URL? {
        // SDK model strings include both wire-format and camel-case spellings.
        // Validate every supplied value; never mask an invalid or conflicting URL.
        let values = ["destination_url", "destinationUrl"].compactMap { element[$0] }
        guard !values.isEmpty else { return nil }
        let urls = try values.map { try url($0, field: "destination URL") }
        guard let first = urls.first, urls.allSatisfy({ $0 == first }) else {
            throw AdError.invalidField("consistent destination URL")
        }
        return first
    }

    private func dimension(_ value: Any?, field: String) throws -> Double {
        let number: Double?
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            number = value.doubleValue
        } else if let value = value as? String {
            number = Double(value)
        } else {
            number = nil
        }
        guard let number, number.isFinite, number >= 1, number <= 100_000 else {
            throw AdError.invalidField(field)
        }
        return number
    }

    private func url(_ value: Any?, field: String, httpsOnly: Bool = false) throws -> URL {
        guard let text = value as? String, let url = URLPolicy.webURL(text, httpsOnly: httpsOnly) else {
            throw AdError.invalidField(field)
        }
        return url
    }

    private func trackingIdentity(banner: [String: Any], urls: [URL]) throws -> String {
        // Only the explicit uclid field/query key is supported; never infer from creative IDs.
        var identities: [String] = []
        if let value = banner["uclid"] {
            guard let value = value as? String, !value.isEmpty else {
                throw AdError.invalidField("uclid")
            }
            identities.append(value)
        }
        for url in urls {
            let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .filter { $0.name == "uclid" } ?? []
            for item in values {
                guard let value = item.value, !value.isEmpty else { throw AdError.invalidField("uclid") }
                identities.append(value)
            }
        }
        guard let first = identities.first, identities.allSatisfy({ $0 == first }),
              !first.contains(where: { $0.isWhitespace }) else {
            throw AdError.invalidField("consistent uclid tracking identity")
        }
        return first
    }
}

/// Call only with fixed messages, numeric metadata, or already-redacted diagnostics.
enum LiveAdConsole {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Osmos Live] \(message())")
        #endif
    }
}

/// Describes structure only; never logs URL/identifier values or server messages.
/// Debug builds additionally expose constrained schema names inside image elements.
enum AdResponseDiagnostics {
    private static let keys = [
        "status", "success", "status_code", "statusCode", "code", "ads", "banner_ads",
        "data", "response", "result", "error", "message", "elements", "type", "value",
        "width", "height", "destination_url", "destinationUrl", "uclid", "impression_tracking_url", "click_tracking_url"
    ]

    static func summary(_ response: [String: Any]) -> String {
        var parts = ["root=object(\(response.count) keys)"]
        if response["status"] == nil { parts.append("status=missing") }
        if response["ads"] == nil { parts.append("ads=missing") }
        describe(response, path: "", depth: 0, parts: &parts)
        return parts.joined(separator: "; ")
    }

    private static func describe(_ object: [String: Any], path: String, depth: Int, parts: inout [String]) {
        guard depth < 4 else { return }
        #if DEBUG
        if path.hasSuffix(".elements") || path.hasSuffix(".elements[0]") {
            // The allowlist can hide precisely the field needed to diagnose a mismatch.
            // Inspect only this schema object, never arbitrary nested user dictionaries.
            let unknown = object.keys.filter { !keys.contains($0) }.sorted()
            for key in unknown.prefix(8) where parts.count < 24 {
                let safeName = key.range(of: "^[A-Za-z_]{1,48}$", options: .regularExpression) != nil
                    ? key : "[redacted-key]"
                if let value = object[key] {
                    parts.append("\(path).\(safeName)=\(shape(value, controlField: false)) (unmapped)")
                }
            }
        }
        #endif
        for key in keys {
            guard parts.count < 24, let value = object[key] else { continue }
            let location = path.isEmpty ? key : "\(path).\(key)"
            parts.append("\(location)=\(shape(value, controlField: key == "status" || key == "success" || location == "response.code"))")
            if let child = value as? [String: Any] {
                describe(child, path: location, depth: depth + 1, parts: &parts)
            } else if let array = value as? [Any], let first = array.first as? [String: Any] {
                describe(first, path: location + "[0]", depth: depth + 1, parts: &parts)
            }
        }
    }

    private static func shape(_ value: Any, controlField: Bool) -> String {
        if value is NSNull { return "null" }
        if let value = value as? [String: Any] { return "object(\(value.count) keys)" }
        if let value = value as? [Any] { return "array(\(value.count))" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return controlField ? "bool(\(number.boolValue))" : "bool"
            }
            if controlField, [0.0, 1, 200, 204, 400, 401, 403, 404, 429, 500, 502, 503, 504].contains(number.doubleValue) {
                return "number(\(number.intValue))"
            }
            return "number"
        }
        if let text = value as? String {
            let token = text.lowercased()
            if controlField, ["ok", "success", "error", "failed", "failure", "true", "false", "200"].contains(token) {
                return "string(\(token))"
            }
            return "string"
        }
        return "other"
    }
}