import SwiftUI

/// Figma 디자인 토큰 (black50, black800(main) 등)
extension Color {
    static let black50 = Color(hex: 0xFAFAFA)
    static let black400 = Color(hex: 0xA5A5A5)
    static let black800 = Color(hex: 0x282828)
    static let blue50 = Color(hex: 0xF3F8FB)
    static let brandBlue = Color(hex: 0x96BCD4)

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
