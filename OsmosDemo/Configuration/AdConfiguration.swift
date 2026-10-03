import Foundation

struct AdConfiguration: Equatable {
    let clientID: String
    let productAdsHost: String
    let displayAdsHost: String
    let cliUbid: String
    let pageType: String
    let adUnit: String

    static let assignment = AdConfiguration(
        clientID: "10088010",
        productAdsHost: "demo.o-s.io",
        displayAdsHost: "demo-ba.o-s.io",
        cliUbid: "Any",
        pageType: "demo_page",
        adUnit: "banner_ads"
    )

    func validate() throws {
        guard !clientID.isEmpty, !cliUbid.isEmpty, !pageType.isEmpty, !adUnit.isEmpty,
              validHost(productAdsHost), validHost(displayAdsHost) else {
            throw AdError.initialization
        }
    }

    private func validHost(_ value: String) -> Bool {
        guard !value.contains(":"), !value.contains("/"),
              let url = URLPolicy.webURL("https://" + value) else { return false }
        return url.host == value
    }
}