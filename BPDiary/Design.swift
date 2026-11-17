import SwiftUI
enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        func ui(_ x: UInt32) -> UIColor { UIColor(red: CGFloat((x >> 16) & 255) / 255, green: CGFloat((x >> 8) & 255) / 255, blue: CGFloat(x & 255) / 255, alpha: 1) }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    static let background = adaptive(0xF7F6F0, 0x111C21)
    static let card = adaptive(0xFFFFFF, 0x1D2B31)
    static let ink = adaptive(0x152B33, 0xF1F5F3)
    static let teal = adaptive(0x075466, 0x9CD6DC)
    static let sub = adaptive(0x5E6E73, 0xB8C7CB)
    static let line = adaptive(0xE7E3D8, 0x41535A)
    static let tealSoft = adaptive(0xE3EEF0, 0x294047)
    static let secondaryLine = adaptive(0x7FA7B0, 0xB4D0D6)
    static let empty = adaptive(0xC5CBCC, 0x6C7C82)
    static let selected = Color(red: 7 / 255, green: 84 / 255, blue: 102 / 255)
    static func grade(_ g: BPGrade) -> Color { [adaptive(0x365C48, 0xB2D1BB), adaptive(0x755311, 0xE5C482), adaptive(0x86422B, 0xE4B39E), adaptive(0x783834, 0xE7B1AD), adaptive(0x783834, 0xE7B1AD), adaptive(0x365C48, 0xB2D1BB)][g.rawValue] }
    static func gradeSoft(_ g: BPGrade) -> Color {
        switch g {
        case .normal, .optimal: return adaptive(0xE4EEE7, 0x293E32)
        case .elevated: return adaptive(0xF5ECD9, 0x413821)
        case .stage1: return adaptive(0xF5E6DE, 0x453229)
        case .stage2, .stage3: return adaptive(0xF3E3E1, 0x452D2C)
        }
    }
}
struct LargeButton: ButtonStyle {
    var primary = false
    var height: CGFloat = 66
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: height).padding(.horizontal, 12)
            .foregroundStyle(primary ? Palette.background : Palette.teal)
            .background(primary ? Palette.teal : Palette.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.teal, lineWidth: primary ? 0 : 1.5)).opacity(configuration.isPressed ? 0.75 : 1)
    }
}
extension View {
    func card() -> some View { padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 24)) }
}
struct PillButton: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14).frame(minHeight: 48)
            .foregroundStyle(selected ? Color.white : Palette.teal)
            .background(selected ? Palette.selected : Palette.card, in: Capsule())
            .overlay(Capsule().stroke(selected ? Palette.selected : Palette.line, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct SheetFrame<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { content().background(Palette.background).foregroundStyle(Palette.ink).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("关闭")) { dismiss() }.frame(minWidth: 60, minHeight: 60).accessibilityIdentifier("closeSheet") } } }
    }
}
