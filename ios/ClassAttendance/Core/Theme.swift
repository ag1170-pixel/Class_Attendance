import SwiftUI

/// Design tokens shared across the app — the same palette, radii, and motion as
/// the web prototype (prototype/attendance-ui.html). Apple-minimal: system font,
/// soft depth, semantic present/absent kept separate from the blue accent.
enum Theme {
    // Accent + semantic (adapt to light/dark automatically).
    static let accent  = Color(light: 0x0B6BFF, dark: 0x0A84FF)
    static let present = Color(light: 0x34C759, dark: 0x32D74B)
    static let absent  = Color(light: 0xFF3B30, dark: 0xFF453A)

    // Neutrals biased slightly cool.
    static let bg       = Color(light: 0xEEF0F3, dark: 0x000000)
    static let surface  = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surface2 = Color(light: 0xF6F7F9, dark: 0x2C2C2E)
    static let text     = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let dim      = Color(light: 0x6E6E73, dark: 0x98989F)

    static let radius: CGFloat = 15

    /// The one spring the whole app animates with — keeps motion consistent.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
}

extension Color {
    /// Hex initializer with separate light/dark values, resolved per trait.
    init(light: UInt32, dark: UInt32) {
        self = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red:   CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue:  CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Primary button styling with the prototype's press-scale feedback.
struct FilledButton: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(15)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.radius))
            .scaleEffect(configuration.isPressed ? 0.968 : 1)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}
