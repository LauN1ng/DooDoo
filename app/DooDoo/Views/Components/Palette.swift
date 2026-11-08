import SwiftUI

/// M1 的取色表。数值来自 `home-v1.0.html` 快照，**M4 视觉阶段会整体重校**。
enum Palette {
    static let page = Color(hex: 0xF7F5F1)
    static let card = Color.white
    static let ink = Color(hex: 0x1D1C1A)
    static let ink2 = Color(hex: 0x6B6862)
    static let sub = Color(hex: 0xA8A39A)
    static let faint = Color(hex: 0xC6C2B9)
    static let line = Color(hex: 0xEFECE5)
    static let expense = Color(hex: 0xC0392B)
    static let income = Color(hex: 0x2E9E6B)
    static let tabBed = Color(hex: 0xEBE7E0)
}

extension Color {
    /// `Color(hex: 0x1D1C1A)`，避免到处写 `Color(red:green:blue:)`。
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// 只接受 `#RRGGBB`；解析失败退回浅灰，不崩。
    init(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self.init(hex: 0xF2F1ED)
            return
        }
        self.init(hex: value)
    }
}
