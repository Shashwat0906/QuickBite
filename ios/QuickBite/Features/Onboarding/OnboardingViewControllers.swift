import UIKit
import DesignKit

/// Branded splash: the logo pops in, the name fades up, then we move on.
final class SplashViewController: UIViewController {
    private let onFinish: () -> Void
    private let logo = UIImageView(image: UIImage(named: "LaunchLogo"))
    private let titleLabel = UILabel(font: DK.Font.rounded(36, .heavy, style: .largeTitle), text: "QuickBite")
    private let tagline = UILabel(font: DK.Font.callout, color: DK.Color.textSecondary, text: "Fresh from the café. At your door in minutes.")

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DK.Color.background
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = DK.Color.primary
        tagline.textAlignment = .center
        tagline.numberOfLines = 0
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [logo, titleLabel, tagline])
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 120),
            logo.heightAnchor.constraint(equalToConstant: 120),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.xxxl),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.xxxl),
        ])
        logo.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        titleLabel.alpha = 0
        tagline.alpha = 0
        titleLabel.transform = CGAffineTransform(translationX: 0, y: 12)
        view.accessibilityIdentifier = "splash"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled || !UIView.areAnimationsEnabled
        UIView.animate(withDuration: reduceMotion ? 0 : 0.6, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
            self.logo.transform = .identity
        }
        UIView.animate(withDuration: reduceMotion ? 0 : 0.45, delay: reduceMotion ? 0 : 0.2) {
            self.titleLabel.alpha = 1
            self.titleLabel.transform = .identity
            self.tagline.alpha = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.1 : 1.2)) { [weak self] in self?.onFinish() }
    }
}

/// Three-page onboarding: fast ordering, fresh food, live tracking.
final class OnboardingViewController: UIViewController, UIScrollViewDelegate {
    private struct Page {
        let symbol: String
        let title: String
        let body: String
        let tint: UIColor
    }

    private let pages = [
        Page(symbol: "bolt.fill", title: "Order in seconds", body: "Your favourite cafés, one tap away. Reorder in a flash and skip the queue.", tint: DK.Color.primary),
        Page(symbol: "leaf.fill", title: "Fresh, every time", body: "Every coffee and bake is made after you order — never sitting on a shelf.", tint: DK.Color.success),
        Page(symbol: "location.fill", title: "Track it live", body: "Follow your order from the espresso machine to your doorstep, step by step.", tint: DK.Color.warning),
    ]

    private let onSignIn: () -> Void
    private let onGuest: () -> Void
    private let scrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private let nextButton = QBButton(title: "Next")
    private let guestButton = QBButton(title: "Browse as guest", style: .text)
    private let skipButton = UIButton(type: .system)

    init(onSignIn: @escaping () -> Void, onGuest: @escaping () -> Void) {
        self.onSignIn = onSignIn
        self.onGuest = onGuest
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DK.Color.background
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "onboardingPages"
        view.addSubview(scrollView)

        let row = UIStackView(axis: .horizontal, distribution: .fillEqually)
        scrollView.addSubview(row)
        for (index, page) in pages.enumerated() {
            let pageView = makePage(page, index: index)
            row.addArrangedSubview(pageView)
            pageView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        }

        pageControl.numberOfPages = pages.count
        pageControl.currentPageIndicatorTintColor = DK.Color.primary
        pageControl.pageIndicatorTintColor = DK.Color.separator
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.addAction(UIAction { [weak self] _ in self?.scroll(to: self?.pageControl.currentPage ?? 0) }, for: .valueChanged)

        skipButton.setTitle("Skip", for: .normal)
        skipButton.titleLabel?.font = DK.Font.bodyBold
        skipButton.tintColor = DK.Color.textSecondary
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.accessibilityIdentifier = "onboardingSkip"
        skipButton.addAction(UIAction { [weak self] _ in self?.scroll(to: (self?.pages.count ?? 1) - 1) }, for: .touchUpInside)

        nextButton.accessibilityIdentifier = "onboardingNext"
        nextButton.addAction(UIAction { [weak self] _ in self?.nextTapped() }, for: .touchUpInside)
        guestButton.accessibilityIdentifier = "onboardingGuest"
        guestButton.addAction(UIAction { [weak self] _ in self?.onGuest() }, for: .touchUpInside)

        let buttons = UIStackView(axis: .vertical, spacing: DK.Spacing.s, arrangedSubviews: [pageControl, nextButton, guestButton])
        view.addSubview(buttons)
        view.addSubview(skipButton)

        NSLayoutConstraint.activate([
            skipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DK.Spacing.s),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.page),
            scrollView.topAnchor.constraint(equalTo: skipButton.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -DK.Spacing.l),
            row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.xxl),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.xxl),
            buttons.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DK.Spacing.l),
        ])
        updateButtons()
    }

    private func makePage(_ page: Page, index: Int) -> UIView {
        let container = UIView()
        let circle = UIView()
        circle.backgroundColor = page.tint.withAlphaComponent(0.12)
        circle.layer.cornerRadius = 110
        circle.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: page.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 80, weight: .semibold)))
        icon.tintColor = page.tint
        icon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(icon)
        let title = UILabel(font: DK.Font.largeTitle, lines: 0, text: page.title)
        title.textAlignment = .center
        title.accessibilityTraits = .header
        title.accessibilityIdentifier = "onboardingTitle_\(index)"
        let body = UILabel(font: DK.Font.body, color: DK.Color.textSecondary, lines: 0, text: page.body)
        body.textAlignment = .center
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l, alignment: .center, arrangedSubviews: [circle, title, body])
        stack.setCustomSpacing(DK.Spacing.xxxl, after: circle)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 220),
            circle.heightAnchor.constraint(equalToConstant: 220),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DK.Spacing.xxxl),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DK.Spacing.xxxl),
        ])
        return container
    }

    private var currentPage: Int {
        guard scrollView.bounds.width > 0 else { return 0 }
        return Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
    }

    private func scroll(to page: Int) {
        let x = CGFloat(page) * scrollView.bounds.width
        scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: UIView.areAnimationsEnabled)
        pageControl.currentPage = page
        updateButtons(page: page)
    }

    private func nextTapped() {
        let page = pageControl.currentPage
        if page < pages.count - 1 {
            scroll(to: page + 1)
        } else {
            onSignIn()
        }
    }

    private func updateButtons(page: Int? = nil) {
        let isLast = (page ?? currentPage) == pages.count - 1
        nextButton.setTitle(isLast ? "Get started" : "Next")
        skipButton.isHidden = isLast
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        pageControl.currentPage = currentPage
        updateButtons()
    }
}
