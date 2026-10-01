import UIKit
import DesignKit
import NetworkKit

/// Generic screen state used by view models.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }
}

extension UIViewController {
    func showError(_ error: Error, title: String = "Something went wrong") {
        let message = (error as? APIError)?.userMessage ?? error.localizedDescription
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func confirm(title: String, message: String?, confirmTitle: String, destructive: Bool = false, onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: confirmTitle, style: destructive ? .destructive : .default) { _ in onConfirm() })
        present(alert, animated: true)
    }

    func toast(_ message: String, style: ToastView.Style = .success) {
        ToastView.show(message, style: style, in: navigationController?.view ?? view, duration: 2.2)
    }

    /// Places a full-screen overlay (empty/error/loading) above the content.
    @discardableResult
    func installOverlay(_ overlay: UIView?, in container: UIView? = nil, tag: Int = 9_001, below topAnchor: NSLayoutYAxisAnchor? = nil) -> UIView? {
        let host = container ?? view!
        host.viewWithTag(tag)?.removeFromSuperview()
        guard let overlay else { return nil }
        overlay.tag = tag
        overlay.backgroundColor = overlay.backgroundColor ?? DK.Color.background
        host.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: topAnchor ?? host.safeAreaLayoutGuide.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        return overlay
    }

    func makeStateView(for error: APIError, retry: @escaping () -> Void) -> StateView {
        let view: StateView
        if error == .offline {
            view = StateView(.offline, actionTitle: "Try again", action: retry)
        } else {
            view = StateView(.error(title: "Couldn't load this", message: error.userMessage), actionTitle: "Try again", action: retry)
        }
        view.backgroundColor = DK.Color.background
        return view
    }
}

/// A rounded "card" container view.
final class CardView: UIView {
    init(padding: CGFloat = DK.Spacing.l, content: UIView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = DK.Color.surface
        layer.cornerRadius = DK.Radius.l
        applyCardShadow(opacity: 0.05, radius: 8, y: 2)
        addSubview(content)
        content.pinEdges(to: self, insets: UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Bill breakdown rows: Item total, Delivery, Taxes, Discount, To pay.
final class BillView: UIView {
    private let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.s)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.pinEdges(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ bill: Bill, isEstimate: Bool = false, couponCode: String? = nil) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(row("Item total", Money.format(bill.subtotalPaise)))
        stack.addArrangedSubview(row("Delivery fee", bill.deliveryFeePaise == 0 ? "FREE" : Money.format(bill.deliveryFeePaise), valueColor: bill.deliveryFeePaise == 0 ? DK.Color.success : nil))
        stack.addArrangedSubview(row("Taxes & charges (5% GST)", Money.format(bill.taxPaise)))
        if bill.discountPaise > 0 {
            stack.addArrangedSubview(row(couponCode.map { "Coupon (\($0))" } ?? "Discount", Money.discount(bill.discountPaise), valueColor: DK.Color.success))
        }
        let divider = UIView()
        divider.backgroundColor = DK.Color.separator
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.addArrangedSubview(divider)
        let total = row(isEstimate ? "Estimated total" : "To pay", Money.format(bill.totalPaise), bold: true)
        total.accessibilityIdentifier = "billTotal"
        stack.addArrangedSubview(total)
        if isEstimate {
            let note = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, lines: 0, text: "Final amount is confirmed by the cafe's live prices at checkout.")
            stack.addArrangedSubview(note)
        }
    }

    private func row(_ title: String, _ value: String, bold: Bool = false, valueColor: UIColor? = nil) -> UIView {
        let left = UILabel(font: bold ? DK.Font.headline : DK.Font.body, color: bold ? DK.Color.textPrimary : DK.Color.textSecondary, text: title)
        let right = UILabel(font: bold ? DK.Font.headline : DK.Font.price, color: valueColor ?? DK.Color.textPrimary, text: value)
        right.textAlignment = .right
        right.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, arrangedSubviews: [left, right])
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(title), \(value)"
        return row
    }
}

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var orderDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, h:mm a"
        return formatter.string(from: self)
    }
}
