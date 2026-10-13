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
}

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
