import SwiftUI

@MainActor
struct DemoRootView: View {
    @ObservedObject var session: DemoSession
    @State private var sheet: DiagnosticSheet?

    var body: some View {
        AdFeedView(model: session.model,
                   onShowScenarios: { present(.scenarios) },
                   onShowEvents: { present(.events) })
            .id(session.generation)
            .sheet(item: $sheet, onDismiss: { session.model.setOverlayPresented(false) }) { destination in
                switch destination {
                case .scenarios:
                    ScenarioPicker(selected: session.scenario) { scenario in
                        session.select(scenario)
                        session.model.setOverlayPresented(true)
                        sheet = nil
                    }
                case .events:
                    EventLogView(analytics: session.model.analytics, tracker: session.model.tracker,
                                 isFixture: session.model.isFixture)
                }
            }
    }

    private func present(_ destination: DiagnosticSheet) {
        session.model.setOverlayPresented(true)
        sheet = destination
    }
}

private enum DiagnosticSheet: String, Identifiable {
    case scenarios, events
    var id: String { rawValue }
}

@MainActor
private struct ScenarioPicker: View {
    let selected: DemoScenario
    let onSelect: (DemoScenario) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Changing modes starts a fresh feed. Fixture modes use local images and a fake event sender; only Live Osmos sends real ad traffic.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                ForEach(DemoScenario.allCases) { scenario in
                    Button { onSelect(scenario) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: scenario == selected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(scenario.title).font(.headline)
                                Text(scenario.detail).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .accessibilityIdentifier("scenario-\(scenario.rawValue)")
                }
            }
            .navigationTitle("Demo scenarios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }
}

@MainActor
private struct EventLogView: View {
    @ObservedObject var analytics: AnalyticsStore
    @ObservedObject var tracker: AdEventTracker
    let isFixture: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        metric("Impressions", tracker.impressions.count, id: "impression-count")
                        Spacer()
                        metric("Clicks", tracker.clickCount, id: "click-count")
                    }
                    Text(isFixture ? "Simulated events only. No tracking requests leave this app." : "Fired means submitted to the SDK. Acknowledgement is logged separately; delivery is not guaranteed.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("Recent events · newest first") {
                    if analytics.entries.isEmpty {
                        Text("Load an ad to start the event log.").foregroundColor(.secondary)
                    }
                    ForEach(analytics.entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(entry.date, style: .time).font(.caption2).foregroundColor(.secondary)
                            }
                            Text(entry.detail).font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Event log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }

    private func metric(_ title: String, _ value: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .accessibilityIdentifier(id)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
    }
}