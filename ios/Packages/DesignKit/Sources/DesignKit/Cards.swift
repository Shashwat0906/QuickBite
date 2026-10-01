import UIKit

/// Data a cafe card needs. Plain values, so DesignKit stays independent of the
/// app's models and can be reused in another app.
public struct CafeCardModel: Hashable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var imageURL: URL?
    public var rating: Double
    public var deliveryMinutes: Int?
    public var distanceText: String?
    public var isOpen: Bool
    public var offerText: String?

    public init(id: String, name: String, subtitle: String, imageURL: URL?, rating: Double, deliveryMinutes: Int?, distanceText: String?, isOpen: Bool, offerText: String? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.rating = rating
        self.deliveryMinutes = deliveryMinutes
        self.distanceText = distanceText
        self.isOpen = isOpen
        self.offerText = offerText
    }
}

/// Large photo card for a cafe (Home "Featured", cafe lists, search results).
public final class CafeCardCell: UICollectionViewCell {
    public static let reuseID = "CafeCardCell"

    private let imageView = RemoteImageView()
    private let nameLabel = UILabel(font: DK.Font.headline)
    private let subtitleLabel = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary)
    private let metaLabel = UILabel(font: DK.Font.captionBold, color: DK.Color.textPrimary)
    private let rating = RatingBadge()
    private let closedOverlay = UIView()
    private let closedLabel = UILabel(font: DK.Font.bodyBold, color: .white, text: "Closed now")
    private let offerLabel = PaddedLabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = DK.Color.surface
        contentView.layer.cornerRadius = DK.Radius.l
        contentView.layer.masksToBounds = true
        applyCardShadow()

        closedOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closedOverlay.translatesAutoresizingMaskIntoConstraints = false
        closedLabel.textAlignment = .center
        closedOverlay.addSubview(closedLabel)
        imageView.addSubview(closedOverlay)

        offerLabel.font = DK.Font.captionBold
        offerLabel.textColor = .white
        offerLabel.backgroundColor = DK.Color.primary
        offerLabel.layer.cornerRadius = 6
        offerLabel.layer.masksToBounds = true
        offerLabel.translatesAutoresizingMaskIntoConstraints = false
        imageView.addSubview(offerLabel)

        let titleRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [nameLabel, rating])
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rating.setContentHuggingPriority(.required, for: .horizontal)
        let text = UIStackView(axis: .vertical, spacing: DK.Spacing.xs, arrangedSubviews: [titleRow, subtitleLabel, metaLabel])
        contentView.addSubview(imageView)
        contentView.addSubview(text)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.6),
            closedOverlay.topAnchor.constraint(equalTo: imageView.topAnchor),
            closedOverlay.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            closedOverlay.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            closedOverlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            closedLabel.centerXAnchor.constraint(equalTo: closedOverlay.centerXAnchor),
            closedLabel.centerYAnchor.constraint(equalTo: closedOverlay.centerYAnchor),
            offerLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: DK.Spacing.m),
            offerLabel.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -DK.Spacing.m),
            text.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: DK.Spacing.m),
            text.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DK.Spacing.m),
            text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DK.Spacing.m),
            text.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -DK.Spacing.m),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func configure(_ model: CafeCardModel) {
        nameLabel.text = model.name
        subtitleLabel.text = model.subtitle
        rating.set(rating: model.rating)
        var meta: [String] = []
        if let minutes = model.deliveryMinutes { meta.append("⚡ \(minutes) min") }
        if let distance = model.distanceText { meta.append(distance) }
        metaLabel.text = meta.joined(separator: "  ·  ")
        imageView.setImage(url: model.imageURL)
        closedOverlay.isHidden = model.isOpen
        offerLabel.text = model.offerText
        offerLabel.isHidden = model.offerText == nil
        accessibilityIdentifier = "cafeCard_\(model.name)"
        accessibilityLabel = [model.name, model.subtitle, String(format: "rated %.1f", model.rating), metaLabel.text, model.isOpen ? nil : "closed now"]
            .compactMap { $0 }.joined(separator: ", ")
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        imageView.cancel()
    }

    public override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: DK.Motion.fast) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }
}

/// Data for a dish row/card.
public struct FoodItemCardModel: Hashable {
    public var id: String
    public var name: String
    public var description: String
    public var priceText: String
    public var imageURL: URL?
    public var diet: DietIndicator.Diet
    public var isBestseller: Bool
    public var isAvailable: Bool
    public var isCustomizable: Bool
    public var quantityInCart: Int
    public var caption: String?

    public init(id: String, name: String, description: String, priceText: String, imageURL: URL?, diet: DietIndicator.Diet, isBestseller: Bool, isAvailable: Bool, isCustomizable: Bool, quantityInCart: Int, caption: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.priceText = priceText
        self.imageURL = imageURL
        self.diet = diet
        self.isBestseller = isBestseller
        self.isAvailable = isAvailable
        self.isCustomizable = isCustomizable
        self.quantityInCart = quantityInCart
        self.caption = caption
    }
}

/// Menu row: text on the left, photo with an ADD/stepper control on the right
/// (the familiar Indian food-app layout).
public final class FoodItemCell: UICollectionViewCell {
    public static let reuseID = "FoodItemCell"

    /// New quantity chosen with the stepper.
    public var onQuantityChange: ((Int) -> Void)?

    private let diet = DietIndicator()
    private let bestseller = PaddedLabel()
    private let nameLabel = UILabel(font: DK.Font.headline, lines: 2)
    private let captionLabel = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary)
    private let priceLabel = UILabel(font: DK.Font.price)
    private let descriptionLabel = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary, lines: 2)
    private let imageView = RemoteImageView()
    private let stepper = QuantityStepper()
    private let customizableLabel = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, text: "Customisable")
    private let divider = UIView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        bestseller.text = "★ Bestseller"
        bestseller.font = DK.Font.captionBold
        bestseller.textColor = DK.Color.warning
        bestseller.backgroundColor = DK.Color.warning.withAlphaComponent(0.12)
        bestseller.layer.cornerRadius = 4
        bestseller.layer.masksToBounds = true

        imageView.layer.cornerRadius = DK.Radius.m
        stepper.onChange = { [weak self] value in self?.onQuantityChange?(value) }
        customizableLabel.textAlignment = .center
        divider.backgroundColor = DK.Color.separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let badges = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [diet, bestseller, UIView()])
        let text = UIStackView(axis: .vertical, spacing: DK.Spacing.xs, alignment: .fill, arrangedSubviews: [badges, nameLabel, captionLabel, priceLabel, descriptionLabel])
        text.setCustomSpacing(DK.Spacing.s, after: priceLabel)

        contentView.addSubview(text)
        contentView.addSubview(imageView)
        contentView.addSubview(stepper)
        contentView.addSubview(customizableLabel)
        contentView.addSubview(divider)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DK.Spacing.l),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 118),
            imageView.heightAnchor.constraint(equalToConstant: 108),
            stepper.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            stepper.centerYAnchor.constraint(equalTo: imageView.bottomAnchor),
            customizableLabel.topAnchor.constraint(equalTo: stepper.bottomAnchor, constant: DK.Spacing.xs),
            customizableLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            customizableLabel.bottomAnchor.constraint(lessThanOrEqualTo: divider.topAnchor, constant: -DK.Spacing.m),
            text.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DK.Spacing.l),
            text.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: -DK.Spacing.l),
            text.bottomAnchor.constraint(lessThanOrEqualTo: divider.topAnchor, constant: -DK.Spacing.l),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func configure(_ model: FoodItemCardModel) {
        diet.set(model.diet)
        bestseller.isHidden = !model.isBestseller
        nameLabel.text = model.name
        captionLabel.text = model.caption
        captionLabel.isHidden = model.caption == nil
        priceLabel.text = model.priceText
        descriptionLabel.text = model.description
        imageView.setImage(url: model.imageURL)
        imageView.alpha = model.isAvailable ? 1 : 0.4
        stepper.isAvailable = model.isAvailable
        stepper.setValue(model.quantityInCart)
        customizableLabel.isHidden = !model.isCustomizable
        nameLabel.textColor = model.isAvailable ? DK.Color.textPrimary : DK.Color.textTertiary
        accessibilityIdentifier = "foodItem_\(model.name)"
        stepper.accessibilityIdentifier = "stepper_\(model.name)"
        contentView.accessibilityElements = [nameLabel, priceLabel, descriptionLabel, stepper]
        nameLabel.accessibilityLabel = [model.name, model.isBestseller ? "Bestseller" : nil, model.isAvailable ? nil : "Currently unavailable"]
            .compactMap { $0 }.joined(separator: ", ")
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        imageView.cancel()
        onQuantityChange = nil
    }
}

/// Small square dish card for horizontal rails ("Popular dishes").
public final class DishTileCell: UICollectionViewCell {
    public static let reuseID = "DishTileCell"
    private let imageView = RemoteImageView()
    private let nameLabel = UILabel(font: DK.Font.callout, lines: 2)
    private let priceLabel = UILabel(font: DK.Font.captionBold, color: DK.Color.textSecondary)
    private let diet = DietIndicator()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.layer.cornerRadius = DK.Radius.m
        let priceRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.xs, alignment: .center, arrangedSubviews: [diet, priceLabel])
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.s, arrangedSubviews: [imageView, nameLabel, priceRow])
        contentView.addSubview(stack)
        stack.pinEdges(to: contentView)
        imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor).isActive = true
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func configure(_ model: FoodItemCardModel) {
        nameLabel.text = model.name
        priceLabel.text = model.priceText
        diet.set(model.diet)
        imageView.setImage(url: model.imageURL)
        accessibilityLabel = "\(model.name), \(model.priceText)\(model.caption.map { ", from \($0)" } ?? "")"
        accessibilityIdentifier = "dishTile_\(model.name)"
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        imageView.cancel()
    }
}

/// UILabel with internal padding (badges, pills).
public final class PaddedLabel: UILabel {
    public var insets = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

    public override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    public override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
