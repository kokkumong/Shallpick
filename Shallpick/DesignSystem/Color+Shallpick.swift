import SwiftUI

/// Figma 디자인 토큰 (black50, black800(main) 등)
extension Color {
    static let black50 = Color(hex: 0xFAFAFA)
    /// 고른 칸 배경 (보낼 사람 선택)
    static let black100 = Color(hex: 0xF5F5F5)
    static let black200 = Color(hex: 0xE6E6E6)
    static let black400 = Color(hex: 0xA5A5A5)
    /// 채팅 보낸 사람 이름
    static let black600 = Color(hex: 0x575757)
    static let black800 = Color(hex: 0x282828)
    static let blue50 = Color(hex: 0xF3F8FB)
    static let blue100 = Color(hex: 0xE5EEF4)
    static let brandBlue = Color(hex: 0x96BCD4)
    /// 그리드/리스트 선택 표시
    static let segmentSelected = Color(hex: 0x9EBBD2)

    /// 폴더 앞면 그라데이션 (Figma: bluegradient) 과 그 위 글자색
    static let folderBlueBottom = Color(hex: 0x6F9CC2)
    static let folderTitle = Color(hex: 0x3C506C)
    static let folderSubtitle = Color(hex: 0x5174A4)

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
