import UIKit
import StoreKit
import WebKit

// MARK: - Native Settings Screen
// Provides a native UIKit settings interface with Account and About sections.
// Triggered via settingsBridge WKScriptMessageHandler from the web layer.

class SettingsBridgeHandler: NSObject, WKScriptMessageHandler {

    weak var viewController: UIViewController?

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              action == "openSettings" else { return }

        DispatchQueue.main.async { [weak self] in
            self?.presentSettings()
        }
    }

    private func presentSettings() {
        guard let vc = viewController else { return }
        let settingsVC = SettingsViewController()
        settingsVC.webView = (vc as? SettingsWebViewProvider)?.settingsWebView
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .pageSheet
        vc.present(nav, animated: true)
    }
}

protocol SettingsWebViewProvider: AnyObject {
    var settingsWebView: WKWebView? { get }
}

class SettingsViewController: UITableViewController {

    weak var webView: WKWebView?

    private enum Section: Int, CaseIterable {
        case account
        case about
    }

    private struct Row {
        let title: String
        let subtitle: String?
        let icon: String
        let iconColor: UIColor
        let detail: String?
        let action: () -> Void
    }

    private var sections: [(title: String, rows: [Row])] = []
    private var isSubscribed = false
    private var subscriptionExpiry: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismissSettings)
        )

        view.backgroundColor = UIColor.systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        buildSections()

        // Check subscription status and rebuild if needed
        if #available(iOS 15.0, *) {
            Task { await checkSubscriptionStatus() }
        }
    }

    private func buildSections() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let premiumTitle: String
        let premiumSubtitle: String?
        let premiumIcon: String
        if isSubscribed {
            premiumTitle = "Sadiky Premium"
            premiumSubtitle = "You're subscribed" + (subscriptionExpiry.map { " · Renews \($0)" } ?? "")
            premiumIcon = "checkmark.seal.fill"
        } else {
            premiumTitle = "Subscribe to Sadiky Premium"
            premiumSubtitle = "$19.99/year with 7-day free trial"
            premiumIcon = "star.fill"
        }

        sections = [
            (title: "Premium", rows: [
                Row(title: premiumTitle, subtitle: premiumSubtitle, icon: premiumIcon, iconColor: .systemYellow, detail: nil, action: { [weak self] in
                    if self?.isSubscribed == true {
                        self?.openManageSubscription()
                    } else {
                        self?.purchasePremium()
                    }
                }),
            ]),
            (title: "Account", rows: [
                Row(title: "Manage Subscription", subtitle: nil, icon: "creditcard.fill", iconColor: .systemBlue, detail: nil, action: { [weak self] in
                    self?.openManageSubscription()
                }),
                Row(title: "Restore Purchases", subtitle: nil, icon: "arrow.clockwise.circle.fill", iconColor: .systemGreen, detail: nil, action: { [weak self] in
                    self?.restorePurchases()
                }),
            ]),
            (title: "About", rows: [
                Row(title: "Version", subtitle: nil, icon: "info.circle.fill", iconColor: .systemGray, detail: "\(version) (\(build))", action: {}),
                Row(title: "Privacy Policy", subtitle: nil, icon: "hand.raised.fill", iconColor: .systemIndigo, detail: nil, action: { [weak self] in
                    self?.openURL("https://sadiky.com/privacy")
                }),
                Row(title: "Terms of Use", subtitle: nil, icon: "doc.text.fill", iconColor: .systemTeal, detail: nil, action: { [weak self] in
                    self?.openURL("https://sadiky.com/terms.html")
                }),
                Row(title: "Sources & References", subtitle: nil, icon: "book.closed.fill", iconColor: .systemOrange, detail: nil, action: { [weak self] in
                    self?.openURL("https://sadiky.com/sources")
                }),
            ])
        ]
    }

    // MARK: - Table View Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = sections[indexPath.section].rows[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.secondaryText = row.subtitle ?? row.detail
        content.image = UIImage(systemName: row.icon)
        content.imageProperties.tintColor = row.iconColor
        cell.contentConfiguration = content

        if row.detail == nil && row.title != "Version" {
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.accessoryType = .none
        }

        cell.selectionStyle = row.detail != nil ? .none : .default
        return cell
    }

    // MARK: - Table View Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        sections[indexPath.section].rows[indexPath.row].action()
    }

    // MARK: - Actions

    @objc private func dismissSettings() {
        dismiss(animated: true)
    }

    private func openManageSubscription() {
        if #available(iOS 15.0, *) {
            Task {
                if let windowScene = view.window?.windowScene {
                    try? await AppStore.showManageSubscriptions(in: windowScene)
                }
            }
        }
    }

    private func restorePurchases() {
        if #available(iOS 15.0, *) {
            let alert = UIAlertController(title: "Restoring...", message: "Checking your purchases with Apple.", preferredStyle: .alert)
            present(alert, animated: true)

            Task {
                do {
                    try await AppStore.sync()
                    // Notify web of restored status
                    await MainActor.run {
                        webView?.evaluateJavaScript("if(window.__iapResult)window.__iapResult('restored','');") { _, _ in }
                        alert.dismiss(animated: true) {
                            let success = UIAlertController(title: "Restored", message: "Your purchases have been restored.", preferredStyle: .alert)
                            success.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(success, animated: true)
                        }
                    }
                } catch {
                    await MainActor.run {
                        alert.dismiss(animated: true) {
                            let fail = UIAlertController(title: "Restore Failed", message: "Could not restore purchases. Please try again later.", preferredStyle: .alert)
                            fail.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(fail, animated: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Premium Purchase (StoreKit 2)

    private static let premiumProductID = "com.mentiumlabs.sadiky.premium.yearly.v2"
    private static let legacyProductID = "com.mentiumlabs.sadiky.premium.yearly"

    private func purchasePremium() {
        guard #available(iOS 15.0, *) else { return }
        let loadingAlert = UIAlertController(title: "Loading...", message: "Fetching subscription details from Apple.", preferredStyle: .alert)
        present(loadingAlert, animated: true)

        Task {
            await doPurchasePremium(loadingAlert: loadingAlert)
        }
    }

    @available(iOS 15.0, *)
    private func doPurchasePremium(loadingAlert: UIAlertController) async {
        do {
            let products = try await Product.products(for: [Self.premiumProductID])
            guard let product = products.first else {
                await MainActor.run {
                    loadingAlert.dismiss(animated: true) {
                        let alert = UIAlertController(title: "Not Available", message: "The subscription product could not be found. Please try again later.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
                return
            }

            await MainActor.run {
                loadingAlert.dismiss(animated: true)
            }

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await MainActor.run {
                    webView?.evaluateJavaScript("if(window.__iapResult)window.__iapResult('success','');") { _, _ in }
                    let alert = UIAlertController(title: "Welcome to Premium!", message: "Your subscription is now active. Enjoy Sadiky Premium!", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                    self.isSubscribed = true
                    self.buildSections()
                    self.tableView.reloadData()
                }

            case .userCancelled:
                break

            case .pending:
                await MainActor.run {
                    let alert = UIAlertController(title: "Pending", message: "Your purchase is awaiting approval.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }

            @unknown default:
                break
            }
        } catch {
            await MainActor.run {
                loadingAlert.dismiss(animated: true) {
                    let alert = UIAlertController(title: "Purchase Failed", message: "Could not complete the purchase. Please try again.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    @available(iOS 15.0, *)
    private func checkSubscriptionStatus() async {
        var active = false
        var expiry: Date?

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               (transaction.productID == Self.premiumProductID || transaction.productID == Self.legacyProductID) {
                if transaction.revocationDate == nil {
                    active = true
                    expiry = transaction.expirationDate
                }
            }
        }

        await MainActor.run {
            isSubscribed = active
            if let expiry = expiry {
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                subscriptionExpiry = fmt.string(from: expiry)
            }
            buildSections()
            tableView.reloadData()
        }
    }

    @available(iOS 15.0, *)
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe): return safe
        }
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
