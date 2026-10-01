import UIKit

/// The app's button. One component, four styles, with a built-in loading state
/// (so a "Place order" button can't be tapped twice while a request is running).
public final class QBButton: UIButton {
    public enum Style {
        case primary, secondary, outline, text
    }

    public let style: Style
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var storedTitle: String?

    public var isLoading = false {
        didSet {
            guard isLoading != oldValue else { return }
            isUserInteractionEnabled = !isLoading
            if isLoading {
                storedTitle = configuration?.title
                configuration?.title = ""
                configuration?.image = nil
                spinner.startAnimating()
            } else {
                configuration?.title = storedTitle
                spinner.stopAnimating()
            }
            accessibilityValue = isLoading ? "Loading" : nil
        }
    }

    public init(title: String, style: Style = .primary, image: UIImage? = nil) {
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        var config: UIButton.Configuration
        switch style {
        case .primary: config = .filled()
        case .secondary: config = .tinted()
        case .outline: config = .bordered()
        case .text: config = .plain()
        }
        config.title = title
        config.image = image
        config.imagePadding = DK.Spacing.s
        config.cornerStyle = .large
        config.buttonSize = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = DK.Font.headline
            return outgoing
        }
        configuration = config
        configurationUpdateHandler = { [weak self] button in
            guard let self else { return }
            var updated = button.configuration
            switch self.style {
            case .primary:
                updated?.baseBackgroundColor = button.isHighlighted ? DK.Color.primaryPressed : DK.Color.primary
                updated?.baseForegroundColor = .white
            case .secondary:
                updated?.baseBackgroundColor = DK.Color.primary
                updated?.baseForegroundColor = DK.Color.primary
            case .outline:
                updated?.baseBackgroundColor = DK.Color.surface
                updated?.baseForegroundColor = DK.Color.textPrimary
                updated?.background.strokeColor = DK.Color.separator
                updated?.background.strokeWidth = 1
            case .text:
                updated?.baseForegroundColor = DK.Color.primary
            }
            button.configuration = updated
            button.alpha = button.isEnabled ? 1 : 0.45
        }

        spinner.color = style == .primary ? .white : DK.Color.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: style == .text ? 36 : 52),
        ])
        addAction(UIAction { _ in Haptics.tap() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func setTitle(_ title: String) {
        if isLoading { storedTitle = title } else { configuration?.title = title }
    }
}
