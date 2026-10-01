import UIKit

// MARK: - Shimmer skeleton

/// Rounded grey block with a moving highlight — used to build skeleton screens.
public final class SkeletonView: UIView {
    private let gradient = CAGradientLayer()

    public init(cornerRadius: CGFloat = DK.Radius.s) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = DK.Color.skeleton
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        gradient.colors = [UIColor.clear.cgColor, UIColor.white.withAlphaComponent(0.45).cgColor, UIColor.clear.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.locations = [0, 0.5, 1]
        layer.addSublayer(gradient)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width * 3, height: bounds.height)
        startAnimating()
    }

    public func startAnimating() {
        guard gradient.animation(forKey: "shimmer") == nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -bounds.width
        animation.toValue = bounds.width
        animation.duration = 1.3
        animation.repeatCount = .infinity
        gradient.add(animation, forKey: "shimmer")
    }
}

/// A ready-made skeleton list (image + two text lines per row).
public final class SkeletonListView: UIView {
    public init(rows: Int = 4, imageSize: CGFloat = 88) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.xl)
        for _ in 0..<rows {
            let image = SkeletonView(cornerRadius: DK.Radius.m)
            let line1 = SkeletonView()
            let line2 = SkeletonView()
            let text = UIStackView(axis: .vertical, spacing: DK.Spacing.s, alignment: .leading, arrangedSubviews: [line1, line2])
            let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [image, text])
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: imageSize),
                image.heightAnchor.constraint(equalToConstant: imageSize),
                line1.heightAnchor.constraint(equalToConstant: 16),
                line1.widthAnchor.constraint(equalTo: text.widthAnchor, multiplier: 0.8),
                line2.heightAnchor.constraint(equalToConstant: 12),
                line2.widthAnchor.constraint(equalTo: text.widthAnchor, multiplier: 0.5),
            ])
            stack.addArrangedSubview(row)
        }
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: DK.Spacing.l, left: DK.Spacing.page, bottom: 0, right: DK.Spacing.page))
        isAccessibilityElement = true
        accessibilityLabel = "Loading"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Empty / error states

/// Illustration + title + message + optional action. Used for empty carts,
/// no search results, errors and offline states.
public final class StateView: UIView {
    public enum Kind {
        case empty(symbol: String, title: String, message: String)
        case error(title: String, message: String)
        case offline
    }

    private let iconView = UIImageView()
    private let titleLabel = UILabel(font: DK.Font.title2, lines: 0)
    private let messageLabel = UILabel(font: DK.Font.body, color: DK.Color.textSecondary, lines: 0)
    public let actionButton: QBButton
    private var action: (() -> Void)?

    public init(_ kind: Kind, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        actionButton = QBButton(title: actionTitle ?? "", style: .primary)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.action = action

        let iconBackground = UIView()
        iconBackground.backgroundColor = DK.Color.latte
        iconBackground.layer.cornerRadius = 48
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = DK.Color.primary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.addSubview(iconView)

        titleLabel.textAlignment = .center
        messageLabel.textAlignment = .center
        actionButton.isHidden = actionTitle == nil
        actionButton.addAction(UIAction { [weak self] _ in self?.action?() }, for: .touchUpInside)

        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [iconBackground, titleLabel, messageLabel, actionButton])
        stack.setCustomSpacing(DK.Spacing.xl, after: iconBackground)
        stack.setCustomSpacing(DK.Spacing.xxl, after: messageLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            iconBackground.widthAnchor.constraint(equalToConstant: 96),
            iconBackground.heightAnchor.constraint(equalToConstant: 96),
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DK.Spacing.xxxl),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DK.Spacing.xxxl),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: DK.Spacing.xl),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
        configure(kind)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func configure(_ kind: Kind) {
        switch kind {
        case let .empty(symbol, title, message):
            iconView.image = UIImage(systemName: symbol)
            titleLabel.text = title
            messageLabel.text = message
        case let .error(title, message):
            iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
            titleLabel.text = title
            messageLabel.text = message
        case .offline:
            iconView.image = UIImage(systemName: "wifi.slash")
            titleLabel.text = "You're offline"
            messageLabel.text = "Check your internet connection. We'll show what we have saved in the meantime."
        }
        accessibilityElements = [titleLabel, messageLabel, actionButton]
    }
}

// MARK: - Toast / in-app banner

/// Slide-down banner, used for in-app notifications (the fallback when push is
/// unavailable) and quick confirmations ("Added to cart").
public final class ToastView: UIView {
    public enum Style { case info, success, error }

    public static func show(_ message: String, title: String? = nil, style: Style = .info, in view: UIView, duration: TimeInterval = 3, onTap: (() -> Void)? = nil) {
        let toast = ToastView(message: message, title: title, style: style, onTap: onTap)
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: DK.Spacing.page),
            toast.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -DK.Spacing.page),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DK.Spacing.s),
        ])
        toast.transform = CGAffineTransform(translationX: 0, y: -120)
        toast.alpha = 0
        UIView.animate(withDuration: DK.Motion.standard, delay: 0, usingSpringWithDamping: DK.Motion.spring.damping, initialSpringVelocity: DK.Motion.spring.velocity) {
            toast.transform = .identity
            toast.alpha = 1
        }
        UIAccessibility.post(notification: .announcement, argument: [title, message].compactMap { $0 }.joined(separator: ". "))
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak toast] in toast?.dismiss() }
    }

    private var onTap: (() -> Void)?

    private init(message: String, title: String?, style: Style, onTap: (() -> Void)?) {
        self.onTap = onTap
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = DK.Color.textPrimary
        layer.cornerRadius = DK.Radius.l
        applyCardShadow(opacity: 0.2, radius: 16, y: 6)

        let symbol: String
        let tint: UIColor
        switch style {
        case .info: symbol = "bell.fill"; tint = DK.Color.primary
        case .success: symbol = "checkmark.circle.fill"; tint = DK.Color.success
        case .error: symbol = "exclamationmark.circle.fill"; tint = DK.Color.error
        }
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = tint
        icon.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel(font: DK.Font.bodyBold, color: DK.Color.background, lines: 1, text: title)
        titleLabel.isHidden = title == nil
        let messageLabel = UILabel(font: DK.Font.callout, color: DK.Color.background.withAlphaComponent(0.85), lines: 2, text: message)
        let text = UIStackView(axis: .vertical, spacing: DK.Spacing.xxs, arrangedSubviews: [titleLabel, messageLabel])
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [icon, text])
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 14, left: DK.Spacing.l, bottom: 14, right: DK.Spacing.l))
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24)])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissNow))
        swipe.direction = .up
        addGestureRecognizer(swipe)
        isAccessibilityElement = true
        accessibilityLabel = [title, message].compactMap { $0 }.joined(separator: ". ")
        accessibilityTraits = onTap == nil ? .staticText : .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func tapped() {
        onTap?()
        dismiss()
    }

    @objc private func dismissNow() { dismiss() }

    func dismiss() {
        UIView.animate(withDuration: DK.Motion.fast, animations: {
            self.transform = CGAffineTransform(translationX: 0, y: -120)
            self.alpha = 0
        }, completion: { _ in self.removeFromSuperview() })
    }
}

// MARK: - Offline banner

/// Thin bar shown at the top of a screen while offline.
public final class OfflineBanner: UIView {
    public init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = DK.Color.warning
        let label = UILabel(font: DK.Font.captionBold, color: .white, text: "Offline · showing saved content")
        label.textAlignment = .center
        let icon = UIImageView(image: UIImage(systemName: "wifi.slash"))
        icon.tintColor = .white
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [icon, label])
        addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        isAccessibilityElement = true
        accessibilityLabel = "You are offline. Showing saved content."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
