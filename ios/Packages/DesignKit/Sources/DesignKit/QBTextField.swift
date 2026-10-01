import UIKit

/// Labeled text field with inline validation error and an optional
/// show/hide password toggle.
public final class QBTextField: UIView, UITextFieldDelegate {
    public let textField = UITextField()
    private let titleLabel = UILabel(font: DK.Font.captionBold, color: DK.Color.textSecondary)
    private let errorLabel = UILabel(font: DK.Font.caption, color: DK.Color.error, lines: 0)
    private let container = UIView()
    private var toggleButton: UIButton?

    /// Called when the user taps return.
    public var onReturn: (() -> Void)?
    public var onChange: ((String) -> Void)?

    public var text: String {
        get { textField.text ?? "" }
        set { textField.text = newValue }
    }

    public var errorMessage: String? {
        didSet {
            errorLabel.text = errorMessage
            errorLabel.isHidden = errorMessage == nil
            container.layer.borderColor = (errorMessage == nil ? DK.Color.separator : DK.Color.error).resolvedColor(with: traitCollection).cgColor
            if let errorMessage { UIAccessibility.post(notification: .announcement, argument: errorMessage) }
        }
    }

    public init(title: String, placeholder: String, isSecure: Bool = false, keyboard: UIKeyboardType = .default, contentType: UITextContentType? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title.uppercased()

        container.backgroundColor = DK.Color.surface
        container.layer.cornerRadius = DK.Radius.m
        container.layer.borderWidth = 1
        container.layer.borderColor = DK.Color.separator.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        textField.placeholder = placeholder
        textField.font = DK.Font.body
        textField.textColor = DK.Color.textPrimary
        textField.adjustsFontForContentSizeCategory = true
        textField.isSecureTextEntry = isSecure
        textField.keyboardType = keyboard
        textField.textContentType = contentType
        textField.autocapitalizationType = (keyboard == .emailAddress || isSecure) ? .none : .words
        textField.autocorrectionType = .no
        textField.delegate = self
        textField.accessibilityLabel = title
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.errorMessage != nil { self.errorMessage = nil }
            self.onChange?(self.text)
        }, for: .editingChanged)
        container.addSubview(textField)

        var trailing = container.trailingAnchor
        if isSecure {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "eye"), for: .normal)
            button.tintColor = DK.Color.textSecondary
            button.accessibilityLabel = "Show password"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addAction(UIAction { [weak self] _ in self?.toggleSecure() }, for: .touchUpInside)
            container.addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DK.Spacing.s),
                button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 40),
                button.heightAnchor.constraint(equalToConstant: 40),
            ])
            trailing = button.leadingAnchor
            toggleButton = button
        }

        errorLabel.isHidden = true
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.xs, arrangedSubviews: [titleLabel, container, errorLabel])
        addSubview(stack)
        stack.pinEdges(to: self)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DK.Spacing.l),
            textField.trailingAnchor.constraint(equalTo: trailing, constant: -DK.Spacing.s),
            textField.topAnchor.constraint(equalTo: container.topAnchor),
            textField.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func toggleSecure() {
        textField.isSecureTextEntry.toggle()
        let showing = !textField.isSecureTextEntry
        toggleButton?.setImage(UIImage(systemName: showing ? "eye.slash" : "eye"), for: .normal)
        toggleButton?.accessibilityLabel = showing ? "Hide password" : "Show password"
        Haptics.selection()
    }

    public func textFieldDidBeginEditing(_ textField: UITextField) {
        UIView.animate(withDuration: DK.Motion.fast) { self.container.layer.borderColor = DK.Color.primary.cgColor }
    }

    public func textFieldDidEndEditing(_ textField: UITextField) {
        container.layer.borderColor = (errorMessage == nil ? DK.Color.separator : DK.Color.error).resolvedColor(with: traitCollection).cgColor
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onReturn?()
        return true
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        container.layer.borderColor = (errorMessage == nil ? DK.Color.separator : DK.Color.error).resolvedColor(with: traitCollection).cgColor
    }
}
