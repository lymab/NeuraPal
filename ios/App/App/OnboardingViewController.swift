import UIKit

// MARK: - Native Onboarding Flow
// Shown once on first launch to demonstrate native iOS capabilities.
// Stores completion in UserDefaults so it only shows once.

class OnboardingViewController: UIViewController {

    static let hasCompletedKey = "hasCompletedOnboarding"

    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: hasCompletedKey)
    }

    var onComplete: (() -> Void)?

    private let pages: [(icon: String, title: String, subtitle: String, color: UIColor)] = [
        (
            icon: "heart.text.square.fill",
            title: "Track Your Health",
            subtitle: "Sadiky reads your steps, calories, heart rate, sleep, and weight directly from Apple Health — keeping your wellness data in sync automatically.",
            color: UIColor.systemPink
        ),
        (
            icon: "waveform.circle.fill",
            title: "Talk to Sadiky",
            subtitle: "Use your voice to chat with Sadiky. Native iOS speech recognition understands you in real time — just tap the microphone and speak naturally.",
            color: UIColor.systemBlue
        ),
        (
            icon: "bell.badge.fill",
            title: "Stay on Schedule",
            subtitle: "Get native push notifications for medications, meals, hydration, and gym sessions. Sadiky makes sure you never miss a beat.",
            color: UIColor.systemOrange
        )
    ]

    private var currentPage = 0

    // MARK: UI Elements

    private lazy var iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .white
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var iconBackground: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 50
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        l.textColor = UIColor.white.withAlphaComponent(0.8)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var pageControl: UIPageControl = {
        let pc = UIPageControl()
        pc.numberOfPages = pages.count
        pc.currentPage = 0
        pc.currentPageIndicatorTintColor = .white
        pc.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.3)
        pc.translatesAutoresizingMaskIntoConstraints = false
        pc.isUserInteractionEnabled = false
        return pc
    }()

    private lazy var nextButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Continue", for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        b.setTitleColor(UIColor(red: 0.106, green: 0.165, blue: 0.290, alpha: 1), for: .normal) // #1B2A4A
        b.backgroundColor = .white
        b.layer.cornerRadius = 14
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        return b
    }()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.106, green: 0.165, blue: 0.290, alpha: 1) // #1B2A4A
        setupLayout()
        updatePage(animated: false)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(swipedLeft))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(swipedRight))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: Layout

    private func setupLayout() {
        view.addSubview(iconBackground)
        iconBackground.addSubview(iconImageView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(pageControl)
        view.addSubview(nextButton)

        NSLayoutConstraint.activate([
            iconBackground.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            iconBackground.widthAnchor.constraint(equalToConstant: 100),
            iconBackground.heightAnchor.constraint(equalToConstant: 100),

            iconImageView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 50),
            iconImageView.heightAnchor.constraint(equalToConstant: 50),

            titleLabel.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            pageControl.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -24),
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            nextButton.heightAnchor.constraint(equalToConstant: 54),
        ])
    }

    // MARK: Page Updates

    private func updatePage(animated: Bool) {
        let page = pages[currentPage]
        pageControl.currentPage = currentPage

        let isLast = currentPage == pages.count - 1
        nextButton.setTitle(isLast ? "Get Started" : "Continue", for: .normal)

        if animated {
            UIView.transition(with: view, duration: 0.3, options: .transitionCrossDissolve) {
                self.applyPageContent(page)
            }
        } else {
            applyPageContent(page)
        }
    }

    private func applyPageContent(_ page: (icon: String, title: String, subtitle: String, color: UIColor)) {
        iconImageView.image = UIImage(systemName: page.icon)
        iconBackground.backgroundColor = page.color.withAlphaComponent(0.25)
        iconImageView.tintColor = page.color
        titleLabel.text = page.title
        subtitleLabel.text = page.subtitle
    }

    // MARK: Actions

    @objc private func nextTapped() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if currentPage < pages.count - 1 {
            currentPage += 1
            updatePage(animated: true)
        } else {
            completeOnboarding()
        }
    }

    @objc private func swipedLeft() {
        if currentPage < pages.count - 1 {
            currentPage += 1
            updatePage(animated: true)
        }
    }

    @objc private func swipedRight() {
        if currentPage > 0 {
            currentPage -= 1
            updatePage(animated: true)
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.hasCompletedKey)
        onComplete?()
    }
}
