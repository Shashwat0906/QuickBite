import UIKit

// MARK: - Veg / non-veg indicator (the square-with-dot used on Indian menus)

public final class DietIndicator: UIView {
    public enum Diet: String { case veg = "VEG", nonVeg = "NON_VEG", egg = "EGG" }

    private let dot = UIView()

    public init(_ diet: Diet = .veg) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.borderWidth = 1.5
        layer.cornerRadius = 3
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 16),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        set(diet)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func set(_ diet: Diet) {
        let color: UIColor
        switch diet {
        case .veg: color = DK.Color.veg; accessibilityLabel = "Vegetarian"
        case .nonVeg: color = DK.Color.nonVeg; accessibilityLabel = "Non-vegetarian"
        case .egg: color = DK.Color.egg; accessibilityLabel = "Contains egg"
        }
        layer.borderColor = color.resolvedColor(with: traitCollection).cgColor
        dot.backgroundColor = color
    }
}

// MARK: - Rating pill

public final class RatingBadge: UIView {
    private let label = UILabel(font: DK.Font.captionBold, color: .white)

    public init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = DK.Color.rating
        layer.cornerRadius = 6
        let star = UIImageView(image: UIImage(systemName: "star.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)))
        star.tintColor = .white
        let row = UIStackView(axis: .horizontal, spacing: 3, alignment: .center, arrangedSubviews: [label, star])
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6))
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func set(rating: Double) {
        label.text = String(format: "%.1f", rating)
        accessibilityLabel = String(format: "Rated %.1f out of 5", rating)
    }
}

// MARK: - Chip

/// Selectable filter chip ("Veg only", "Rating 4.0+", categories…).
public final class ChipButton: UIButton {
    public var isOn = false { didSet { setNeedsUpdateConfiguration() } }

    public init(title: String, symbol: String? = nil) {
        super.init(frame: .zero)
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = symbol.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)) }
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
        config.background.cornerRadius = DK.Radius.pill
        config.background.strokeWidth = 1
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = DK.Font.callout
            return outgoing
        }
        configuration = config
        configurationUpdateHandler = { [weak self] button in
            guard let self, var config = button.configuration else { return }
            config.background.backgroundColor = self.isOn ? DK.Color.primary.withAlphaComponent(0.12) : DK.Color.surface
            config.background.strokeColor = self.isOn ? DK.Color.primary : DK.Color.separator
            config.baseForegroundColor = self.isOn ? DK.Color.primary : DK.Color.textPrimary
            button.configuration = config
            button.accessibilityTraits = self.isOn ? [.button, .selected] : .button
        }
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Quantity stepper ("ADD" → [– 2 +])

public final class QuantityStepper: UIView {
    public var onChange: ((Int) -> Void)?
    public var maximum = 20

    public private(set) var value = 0 { didSet { render() } }
    public var isAvailable = true { didSet { render() } }

    private let addButton = UIButton(type: .system)
    private let minus = UIButton(type: .system)
    private let plus = UIButton(type: .system)
    private let countLabel = UILabel(font: DK.Font.bodyBold, color: .white)
    private let stepperRow: UIStackView

    public init() {
        stepperRow = UIStackView(axis: .horizontal, alignment: .center, distribution: .equalCentering)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = DK.Radius.s
        layer.borderWidth = 1

        addButton.setTitle("ADD", for: .normal)
        addButton.titleLabel?.font = DK.Font.bodyBold
        addButton.addAction(UIAction { [weak self] _ in self?.step(+1) }, for: .touchUpInside)
        addButton.accessibilityIdentifier = "addToCart"
        addButton.translatesAutoresizingMaskIntoConstraints = false

        for (button, symbol, delta) in [(minus, "minus", -1), (plus, "plus", 1)] {
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
            button.tintColor = .white
            button.addAction(UIAction { [weak self] _ in self?.step(delta) }, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        }
        minus.accessibilityLabel = "Decrease quantity"
        minus.accessibilityIdentifier = "decreaseQuantity"
        plus.accessibilityLabel = "Increase quantity"
        plus.accessibilityIdentifier = "increaseQuantity"
        countLabel.textAlignment = .center
        countLabel.accessibilityIdentifier = "quantityValue"
        [minus, countLabel, plus].forEach(stepperRow.addArrangedSubview)

        addSubview(addButton)
        addSubview(stepperRow)
        addButton.pinEdges(to: self)
        stepperRow.pinEdges(to: self)
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 96), heightAnchor.constraint(equalToConstant: 36)])
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Set without firing `onChange` (used when the cart changes elsewhere).
    public func setValue(_ newValue: Int) { value = max(0, min(maximum, newValue)) }

    private func step(_ delta: Int) {
        let next = max(0, min(maximum, value + delta))
        guard next != value else { return }
        value = next
        Haptics.tap()
        onChange?(next)
    }

    private func render() {
        let showStepper = value > 0
        addButton.isHidden = showStepper
        stepperRow.isHidden = !showStepper
        countLabel.text = "\(value)"
        addButton.isEnabled = isAvailable
        backgroundColor = showStepper ? DK.Color.primary : DK.Color.surface
        layer.borderColor = (isAvailable ? DK.Color.primary : DK.Color.separator).resolvedColor(with: traitCollection).cgColor
        addButton.setTitleColor(isAvailable ? DK.Color.primary : DK.Color.textTertiary, for: .normal)
        addButton.setTitle(isAvailable ? "ADD" : "N/A", for: .normal)
        plus.isEnabled = value < maximum
        accessibilityValue = "\(value)"
    }
}

// MARK: - Section header

public final class SectionHeaderView: UICollectionReusableView {
    public static let reuseID = "SectionHeaderView"
    public let titleLabel = UILabel(font: DK.Font.title2)
    public let subtitleLabel = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary)
    public let actionButton = UIButton(type: .system)
    public var onAction: (() -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.accessibilityTraits = .header
        actionButton.titleLabel?.font = DK.Font.callout
        actionButton.tintColor = DK.Color.primary
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        let text = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [titleLabel, subtitleLabel])
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .lastBaseline, arrangedSubviews: [text, actionButton])
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: DK.Spacing.s, left: 0, bottom: DK.Spacing.s, right: 0))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func configure(title: String, subtitle: String? = nil, action: String? = nil) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        actionButton.setTitle(action, for: .normal)
        actionButton.isHidden = action == nil
    }
}
