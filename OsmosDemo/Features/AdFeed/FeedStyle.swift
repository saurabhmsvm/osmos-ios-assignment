import SwiftUI

struct FeedPalette {
    let scheme: ColorScheme
    var background: Color { scheme == .dark ? Color(red: 0.05, green: 0.08, blue: 0.10) : Color(red: 0.95, green: 0.96, blue: 0.95) }
    var surface: Color { scheme == .dark ? Color(red: 0.09, green: 0.13, blue: 0.15) : .white }
    var ink: Color { scheme == .dark ? Color(red: 0.93, green: 0.96, blue: 0.94) : Color(red: 0.08, green: 0.16, blue: 0.17) }
    var secondary: Color { scheme == .dark ? Color(red: 0.67, green: 0.75, blue: 0.75) : Color(red: 0.36, green: 0.43, blue: 0.43) }
    var accent: Color { scheme == .dark ? Color(red: 0.52, green: 0.88, blue: 0.72) : Color(red: 0.08, green: 0.43, blue: 0.34) }
    var line: Color { ink.opacity(0.10) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color(red: 0.08, green: 0.32, blue: 0.27))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
    }
}