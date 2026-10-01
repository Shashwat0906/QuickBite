import UIKit

/// Design tokens. Every screen uses these instead of literal values, so the
/// whole app can be re-themed from one file.
public enum DK {
    // MARK: Colors — warm "café" palette, light first with a dark variant.
    public enum Color {
        /// Brand accent: buttons, highlights, selected tabs.
        public static let primary = dynamic(light: 0xE2572B, dark: 0xFF7A4D)
        public static let primaryPressed = dynamic(light: 0xC0441C, dark: 0xE2572B)
        /// Deep espresso for headings and text.
        public static let textPrimary = dynamic(light: 0x2B1D16, dark: 0xF6EEE7)
        public static let textSecondary = dynamic(light: 0x7A6A60, dark: 0xB8AAA0)
        public static let textTertiary = dynamic(light: 0xA89990, dark: 0x8A7E77)
        /// Cream page background.
        public static let background = dynamic(light: 0xFFF9F3, dark: 0x14100E)
        public static let surface = dynamic(light: 0xFFFFFF, dark: 0x221B18)
        public static let surfaceMuted = dynamic(light: 0xF6ECE2, dark: 0x2D2420)
        /// Latte tint used for chips and soft fills.
        public static let latte = dynamic(light: 0xF3E1CF, dark: 0x3A2E27)
        public static let separator = dynamic(light: 0xEADDD2, dark: 0x3A302B)
        public static let success = dynamic(light: 0x1E8E3E, dark: 0x4CC26E)
        public static let veg = dynamic(light: 0x1E8E3E, dark: 0x4CC26E)
        public static let nonVeg = dynamic(light: 0xB3261E, dark: 0xF2766B)
        public static let egg = dynamic(light: 0xD39B12, dark: 0xF2C14E)
        public static let warning = dynamic(light: 0xB76E00, dark: 0xF5B04A)
        public static let error = dynamic(light: 0xB3261E, dark: 0xF2766B)
        public static let rating = dynamic(light: 0x1E8E3E, dark: 0x2FA552)
        public static let skeleton = dynamic(light: 0xF0E4D9, dark: 0x2D2420)
        public static let shadow = UIColor(red: 0.17, green: 0.11, blue: 0.08, alpha: 1)

        public static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
            UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: alpha
            )
        }

        public static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
            UIColor { $0.userInterfaceStyle == .dark ? hex(dark) : hex(light) }
        }
    }

    // MARK: Spacing — 4pt grid.
    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
        /// Horizontal page margin.
        public static let page: CGFloat = 16
    }

    // MARK: Corner radii
    public enum Radius {
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let pill: CGFloat = 999
    }

    // MARK: Typography — SF Rounded for display text, SF Pro for body. All styles scale with Dynamic Type.
    public enum Font {
        public static var largeTitle: UIFont { rounded(30, .bold, style: .largeTitle) }
        public static var title: UIFont { rounded(24, .bold, style: .title1) }
        public static var title2: UIFont { rounded(20, .bold, style: .title2) }
        public static var headline: UIFont { rounded(17, .semibold, style: .headline) }
        public static var body: UIFont { scaled(UIFont.systemFont(ofSize: 15, weight: .regular), style: .body) }
        public static var bodyBold: UIFont { scaled(UIFont.systemFont(ofSize: 15, weight: .semibold), style: .body) }
        public static var callout: UIFont { scaled(UIFont.systemFont(ofSize: 14, weight: .medium), style: .callout) }
        public static var caption: UIFont { scaled(UIFont.systemFont(ofSize: 12, weight: .medium), style: .caption1) }
        public static var captionBold: UIFont { scaled(UIFont.systemFont(ofSize: 12, weight: .bold), style: .caption1) }
        public static var price: UIFont { scaled(UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold), style: .body) }

        public static func rounded(_ size: CGFloat, _ weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            return scaled(font, style: style)
        }

        static func scaled(_ font: UIFont, style: UIFont.TextStyle) -> UIFont {
            UIFontMetrics(forTextStyle: style).scaledFont(for: font, maximumPointSize: font.pointSize * 1.6)
        }
    }

    // MARK: Motion
    public enum Motion {
        public static let fast: TimeInterval = 0.18
        public static let standard: TimeInterval = 0.3
        public static let spring = (damping: CGFloat(0.82), velocity: CGFloat(0.4))
    }
}

public extension UIView {
    /// Soft card shadow used across the app.
    func applyCardShadow(opacity: Float = 0.08, radius: CGFloat = 12, y: CGFloat = 4) {
        layer.shadowColor = DK.Color.shadow.cgColor
        layer.shadowOpacity = opacity
        layer.shadowRadius = radius
        layer.shadowOffset = CGSize(width: 0, height: y)
    }

    /// Pins all edges to the superview (optionally with insets).
    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }

    func pinEdges(to guide: UILayoutGuide, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: guide.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -insets.bottom),
        ])
    }
}

public extension UILabel {
    convenience init(font: UIFont, color: UIColor = DK.Color.textPrimary, lines: Int = 1, text: String? = nil) {
        self.init()
        self.font = font
        self.textColor = color
        self.numberOfLines = lines
        self.text = text
        self.adjustsFontForContentSizeCategory = true
        self.translatesAutoresizingMaskIntoConstraints = false
    }
}

public extension UIStackView {
    convenience init(axis: NSLayoutConstraint.Axis, spacing: CGFloat = 0, alignment: Alignment = .fill, distribution: Distribution = .fill, arrangedSubviews: [UIView] = []) {
        self.init(arrangedSubviews: arrangedSubviews)
        self.axis = axis
        self.spacing = spacing
        self.alignment = alignment
        self.distribution = distribution
        self.translatesAutoresizingMaskIntoConstraints = false
    }
}

/// Light haptic feedback helpers.
public enum Haptics {
    public static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    public static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    public static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
