import Foundation
import Combine

@MainActor
final class DemoSession: ObservableObject {
    @Published private(set) var model: AdFeedViewModel
    @Published private(set) var scenario: DemoScenario
    @Published private(set) var generation = UUID()
    private var liveService: OsmosSDKAdapter?
    private let liveImages: BannerImageLoader

    init() {
        let images = BannerImageLoader()
        liveImages = images
        let selected = Self.initialScenario()
        scenario = selected
        let analytics = AnalyticsStore()
        if selected == .live {
            let service = OsmosSDKAdapter()
            liveService = service
            model = Self.makeModel(service: service, sender: service, images: images,
                                   analytics: analytics, scenario: selected)
        } else {
            let service = FixtureAdService(scenario: selected)
            model = Self.makeModel(service: service, sender: service, images: FixtureImageLoader(),
                                   analytics: analytics, scenario: selected)
        }
    }

    func select(_ selected: DemoScenario) {
        guard selected != scenario else { return }
        model.stop()
        let analytics = AnalyticsStore()
        if selected == .live {
            let service: OsmosSDKAdapter
            if let liveService { service = liveService } else {
                service = OsmosSDKAdapter()
                liveService = service
            }
            model = Self.makeModel(service: service, sender: service, images: liveImages,
                                   analytics: analytics, scenario: selected)
        } else {
            let service = FixtureAdService(scenario: selected)
            model = Self.makeModel(service: service, sender: service, images: FixtureImageLoader(),
                                   analytics: analytics, scenario: selected)
        }
        scenario = selected
        generation = UUID()
    }

    private static func makeModel(service: AdServing, sender: AdEventSending, images: ImageLoading,
                                  analytics: AnalyticsStore, scenario: DemoScenario) -> AdFeedViewModel {
        let tracker = AdEventTracker(sender: sender, analytics: analytics, simulated: scenario != .live)
        return AdFeedViewModel(service: service, imageLoader: images, tracker: tracker,
                               analytics: analytics, isFixture: scenario != .live, modeTitle: scenario.title)
    }

    private static func initialScenario() -> DemoScenario {
        #if DEBUG
        let process = ProcessInfo.processInfo
        let args = process.arguments
        if let index = args.firstIndex(of: "--scenario"), args.indices.contains(index + 1),
           let scenario = DemoScenario(rawValue: args[index + 1]) { return scenario }
        // Hosted unit tests must not initialize the live SDK implicitly.
        if process.environment["OSMOS_TEST_MODE"] == "1" ||
            process.environment["XCTestConfigurationFilePath"] != nil { return .success }
        #endif
        return .live
    }
}