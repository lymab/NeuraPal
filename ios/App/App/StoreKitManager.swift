import StoreKit
import UIKit
import WebKit
import os.log

// MARK: - StoreKit 2 IAP Bridge
// Bridges Apple In-App Purchase to the web layer via WKScriptMessageHandler.
// The web calls: webkit.messageHandlers.iapBridge.postMessage({ action: "..." })
// Results sent back via window.__iap* JavaScript callbacks.

@available(iOS 15.0, *)
class StoreKitManager: NSObject, WKScriptMessageHandler {

    weak var webView: WKWebView?

    private static let productID = "com.mentiumlabs.sadiky.premium.yearly.v2"
    // Legacy product ID — needed to honor existing subscribers' entitlements
    private static let legacyProductID = "com.mentiumlabs.sadiky.premium.yearly"
    private static let serverBaseURL = "https://sadiky.com"

    // Compliance URLs required by App Store Guidelines 3.1.2(c)
    private static let termsURL = "https://sadiky.com/terms.html"
    private static let privacyURL = "https://sadiky.com/privacy.html"
    private static let eulaURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    private var products: [Product] = []
    private var updateListenerTask: Task<Void, Error>?
    private static let log = Logger(subsystem: "com.mentiumlabs.sadiky", category: "IAP")

    override init() {
        super.init()
        updateListenerTask = listenForTransactions()
        Task { await loadProducts() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "getProducts":
            Task { await sendProductInfo() }
        case "purchase":
            Task { await purchase() }
        case "restore":
            Task { await restore() }
        case "checkStatus":
            Task { await checkEntitlement() }
        case "manageSubscription":
            Task { await openManageSubscriptions() }
        case "openTerms":
            openURL(Self.termsURL)
        case "openPrivacy":
            openURL(Self.privacyURL)
        case "openEULA":
            openURL(Self.eulaURL)
        default:
            break
        }
    }

    // MARK: - Load Products

    private func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.productID])
        } catch {
            #if DEBUG
            Self.log.error("[IAP] Failed to load products: \(error.localizedDescription)")
            #endif
        }
    }

    private func sendProductInfo() async {
        if products.isEmpty {
            await loadProducts()
        }

        guard let product = products.first else {
            sendToJS("if(window.__iapProducts)window.__iapProducts(null);")
            return
        }

        // Extract introductory offer (free trial) info
        var trialDays = 0
        var hasTrialOffer = false
        if let sub = product.subscription,
           let intro = sub.introductoryOffer,
           intro.paymentMode == .freeTrial {
            hasTrialOffer = true
            let period = intro.period
            switch period.unit {
            case .day:   trialDays = period.value
            case .week:  trialDays = period.value * 7
            case .month: trialDays = period.value * 30
            case .year:  trialDays = period.value * 365
            @unknown default: trialDays = 0
            }
        }

        // Extract subscription period
        var periodUnit = ""
        if let sub = product.subscription {
            switch sub.subscriptionPeriod.unit {
            case .day:   periodUnit = "day"
            case .week:  periodUnit = "week"
            case .month: periodUnit = "month"
            case .year:  periodUnit = "year"
            @unknown default: periodUnit = ""
            }
        }

        let json = """
        {"id":"\(product.id)","title":"\(escapeJS(product.displayName))","description":"\(escapeJS(product.description))","price":"\(product.displayPrice)","hasTrialOffer":\(hasTrialOffer),"trialDays":\(trialDays),"periodUnit":"\(periodUnit)","termsURL":"\(Self.termsURL)","privacyURL":"\(Self.privacyURL)","eulaURL":"\(Self.eulaURL)"}
        """
        sendToJS("if(window.__iapProducts)window.__iapProducts(\(json));")
    }

    // MARK: - Purchase

    private func purchase() async {
        guard let product = products.first else {
            if products.isEmpty { await loadProducts() }
            guard let product = products.first else {
                sendToJS("if(window.__iapResult)window.__iapResult('error','Product not available');")
                return
            }
            return await doPurchase(product)
        }
        await doPurchase(product)
    }

    private func doPurchase(_ product: Product) async {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                // Notify server of the purchase
                await syncWithServer(transaction: transaction)
                sendToJS("if(window.__iapResult)window.__iapResult('success','');")

            case .userCancelled:
                sendToJS("if(window.__iapResult)window.__iapResult('cancelled','');")

            case .pending:
                sendToJS("if(window.__iapResult)window.__iapResult('pending','Waiting for approval');")

            @unknown default:
                sendToJS("if(window.__iapResult)window.__iapResult('error','Unknown result');")
            }
        } catch {
            #if DEBUG
            Self.log.error("[IAP] Purchase error: \(error.localizedDescription)")
            #endif
            // Send a generic error message to the web layer — don't leak system error details
            sendToJS("if(window.__iapResult)window.__iapResult('error','Purchase could not be completed. Please try again.');")
        }
    }

    // MARK: - Restore Purchases

    private func restore() async {
        do {
            try await AppStore.sync()
            await checkEntitlement()
        } catch {
            sendToJS("if(window.__iapResult)window.__iapResult('error','Restore failed');")
        }
    }

    // MARK: - Manage Subscription

    private func openManageSubscriptions() async {
        await MainActor.run {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                Task {
                    try? await AppStore.showManageSubscriptions(in: windowScene)
                }
            }
        }
    }

    // MARK: - Check Entitlement

    func checkEntitlement() async {
        var isActive = false
        var expiryDate: Date?

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               (transaction.productID == Self.productID || transaction.productID == Self.legacyProductID) {
                if transaction.revocationDate == nil {
                    isActive = true
                    expiryDate = transaction.expirationDate
                }
            }
        }

        // Only send active status and expiry to web — no transaction IDs
        let expiryStr = expiryDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        let json = "{\"active\":\(isActive),\"expiry\":\"\(expiryStr)\"}"
        sendToJS("if(window.__iapStatus)window.__iapStatus(\(json));")
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.syncWithServer(transaction: transaction)
                    await self?.checkEntitlement()
                }
            }
        }
    }

    // MARK: - Server Sync

    private func syncWithServer(transaction: Transaction) async {
        guard let url = URL(string: "\(Self.serverBaseURL)/api/apple-iap-verify.php") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        // Get session cookies from shared storage for authentication
        let baseURL = URL(string: Self.serverBaseURL)!
        let cookies = await MainActor.run {
            HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        }

        // Let URLSession cookie handling manage HttpOnly cookies; manually set only the header
        let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in cookieHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Pass the CSRF token if available
        if let csrf = cookies.first(where: { $0.name == "csrf_token" })?.value {
            request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        }

        let body: [String: Any] = [
            "transactionId": transaction.id,
            "productId": transaction.productID,
            "originalTransactionId": transaction.originalID,
            "expirationDate": transaction.expirationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "environment": {
                if #available(iOS 16.0, *) {
                    return transaction.environment == .sandbox ? "sandbox" : "production"
                }
                return "unknown"
            }()
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            Self.log.debug("[IAP] Server sync: HTTP \(statusCode)")
            #endif
            if statusCode < 200 || statusCode >= 300 {
                Self.log.error("[IAP] Server sync unexpected status: \(statusCode)")
            }
        } catch {
            #if DEBUG
            Self.log.error("[IAP] Server sync error: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Open URL

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - JS Helpers

    private func escapeJS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "'", with: "\\'")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func sendToJS(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js) { _, _ in }
        }
    }
}
