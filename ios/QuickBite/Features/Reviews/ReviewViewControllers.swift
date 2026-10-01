import UIKit
import DesignKit
import NetworkKit

@MainActor
final class WriteReviewViewModel {
    let orderId: String
    let cafeName: String
    private let service: ReviewServicing
    var rating = 0
    var comment = ""

    init(orderId: String, cafeName: String, service: ReviewServicing) {
        self.orderId = orderId
        self.cafeName = cafeName
        self.service = service
    }

    var validationMessage: String? {
        if rating < 1 || rating > 5 { return "Tap the stars to rate your order" }
        if comment.count > 500 { return "Please keep your review under 500 characters" }
        return nil
    }

    func submit() async throws -> Review {
        if let message = validationMessage { throw APIError.server(status: 400, code: "VALIDATION_ERROR", message: message) }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await service.submit(orderId: orderId, rating: rating, comment: trimmed.isEmpty ? nil : trimmed)
    }

    static let ratingWords = ["", "Terrible", "Bad", "Okay", "Good", "Loved it!"]
}

/// Star rating + written review for a delivered order.
final class WriteReviewViewController: UIViewController, UITextViewDelegate {
    var onSubmitted: (() -> Void)?
    private let viewModel: WriteReviewViewModel
    private var stars: [UIButton] = []
    private let ratingLabel = UILabel(font: DK.Font.headline, color: DK.Color.textSecondary)
    private let textView = UITextView()
    private let counter = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary)
    private let submit = QBButton(title: "Submit review")

    init(viewModel: WriteReviewViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Rate your order"
        view.backgroundColor = DK.Color.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let heading = UILabel(font: DK.Font.title2, lines: 0, text: "How was your order from \(viewModel.cafeName)?")
        heading.textAlignment = .center
        let starRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.m)
        for value in 1...5 {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "star", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)), for: .normal)
            button.tintColor = DK.Color.warning
            button.accessibilityLabel = "\(value) star\(value == 1 ? "" : "s")"
            button.accessibilityIdentifier = "star_\(value)"
            button.addAction(UIAction { [weak self] _ in self?.setRating(value) }, for: .touchUpInside)
            stars.append(button)
            starRow.addArrangedSubview(button)
        }
        ratingLabel.textAlignment = .center
        textView.font = DK.Font.body
        textView.backgroundColor = DK.Color.surface
        textView.layer.cornerRadius = DK.Radius.m
        textView.layer.borderColor = DK.Color.separator.cgColor
        textView.layer.borderWidth = 1
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.delegate = self
        textView.accessibilityLabel = "Write a review (optional)"
        textView.heightAnchor.constraint(equalToConstant: 140).isActive = true
        counter.textAlignment = .right
        counter.text = "0 / 500"
        submit.isEnabled = false
        submit.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
        let hint = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, lines: 0, text: "Tell others what you liked — taste, packaging, delivery speed.")
        let centered = UIStackView(axis: .vertical, alignment: .center, arrangedSubviews: [starRow])
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l, alignment: .fill, arrangedSubviews: [heading, centered, ratingLabel, hint, textView, counter, submit])
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DK.Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.xxl),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.xxl),
        ])
    }

    private func setRating(_ value: Int) {
        viewModel.rating = value
        Haptics.selection()
        for (index, star) in stars.enumerated() {
            star.setImage(UIImage(systemName: index < value ? "star.fill" : "star", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)), for: .normal)
        }
        ratingLabel.text = WriteReviewViewModel.ratingWords[value]
        submit.isEnabled = viewModel.validationMessage == nil
    }

    func textViewDidChange(_ textView: UITextView) {
        viewModel.comment = textView.text
        counter.text = "\(textView.text.count) / 500"
        counter.textColor = textView.text.count > 500 ? DK.Color.error : DK.Color.textTertiary
        submit.isEnabled = viewModel.validationMessage == nil
    }

    private func send() {
        submit.isLoading = true
        Task {
            defer { submit.isLoading = false }
            do {
                _ = try await viewModel.submit()
                Haptics.success()
                dismiss(animated: true) { [weak self] in self?.onSubmitted?() }
            } catch {
                showError(error, title: "Couldn't submit review")
            }
        }
    }
}

/// A cafe's reviews (with rating distribution) or the user's own reviews.
final class ReviewsListViewController: UITableViewController {
    enum Mode {
        case cafe(Cafe)
        case mine
    }

    private let mode: Mode
    private let service: ReviewServicing
    private var reviews: [Review] = []
    private var distribution: [String: Int] = [:]

    init(mode: Mode, service: ReviewServicing) {
        self.mode = mode
        self.service = service
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        if case .cafe(let cafe) = mode { title = "\(cafe.name) reviews" } else { title = "My reviews" }
        tableView.backgroundColor = DK.Color.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        Task { await load() }
    }

    private func load() async {
        do {
            let response: ReviewListResponse
            switch mode {
            case .cafe(let cafe): response = try await service.cafeReviews(cafeId: cafe.id, page: 1)
            case .mine: response = try await service.myReviews(page: 1)
            }
            reviews = response.reviews
            distribution = response.distribution ?? [:]
            tableView.backgroundView = reviews.isEmpty ? StateView(.empty(symbol: "star.bubble", title: "No reviews yet", message: "Reviews appear after orders are delivered and rated.")) : nil
            tableView.reloadData()
        } catch {
            showError(error)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { distribution.isEmpty ? 1 : 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        distribution.isEmpty || section == 1 ? reviews.count : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        if !distribution.isEmpty && indexPath.section == 0 {
            let total = distribution.values.reduce(0, +)
            content.text = "Rating breakdown (\(total))"
            content.secondaryText = (1...5).reversed().map { "\($0)★  \(String(repeating: "▇", count: min(20, distribution["\($0)"] ?? 0)))  \(distribution["\($0)"] ?? 0)" }.joined(separator: "\n")
            content.secondaryTextProperties.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        } else {
            let review = reviews[indexPath.row]
            let who: String
            if case .mine = mode { who = review.cafeName ?? "Café" } else { who = review.userName ?? "Customer" }
            content.text = "\(String(repeating: "★", count: review.rating))\(String(repeating: "☆", count: 5 - review.rating))  \(who)"
            content.secondaryText = [review.comment, review.createdAt.relativeDescription].compactMap { $0 }.joined(separator: "\n")
        }
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }
}
