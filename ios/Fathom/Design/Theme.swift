import SwiftUI

/// Dark mode is a night nautical chart; light mode is a paper chart.
enum Theme {
    static let abyss = Color(light: 0xF2ECDD, dark: 0x06121F)
    static let deep = Color(light: 0xE6DEC9, dark: 0x0B2236)
    static let ink = Color(light: 0x12324A, dark: 0xE6F1F5)
    static let inkMuted = Color(light: 0x4F6878, dark: 0x8FA9B8)
    static let contour = Color(light: 0x12324A, dark: 0x2EC4B6).opacity(0.10)

    /// Safe / healthy / bound.
    static let teal = Color(light: 0x1A8F86, dark: 0x2EC4B6)
    /// Expiring / pending.
    static let amber = Color(light: 0xC9781E, dark: 0xF4A261)
    /// Claims / losses / errors.
    static let coral = Color(light: 0xD9483B, dark: 0xFF6B6B)

    /// Extra hues for telling entity kinds apart; they carry no status meaning.
    /// sky, kelp and rose are the policy-type series (hull, cargo, P&I). They were checked with a
    /// colour-blindness validator against both chart surfaces, so keep them together and in this order.
    static let sky = Color(light: 0x2F6FA8, dark: 0x4F9BDB)
    static let kelp = Color(light: 0x5C8A2E, dark: 0x74A346)
    static let rose = Color(light: 0xA8457F, dark: 0xC7609F)
    static let lavender = Color(light: 0x5B4BC4, dark: 0x9B8CFF)
}

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        // @Sendable so the provider isn't main-actor isolated: MapKit resolves
        // overlay colours on a background thread.
        self.init(uiColor: UIColor { @Sendable traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

nonisolated private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
