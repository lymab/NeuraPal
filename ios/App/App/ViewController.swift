import UIKit
import Capacitor
import WebKit
import AVFoundation
import Speech
import HealthKit
import AuthenticationServices
import UserNotifications

// MARK: - Native Speech Bridge
// Bridges iOS SFSpeechRecognizer → web SpeechRecognition API
// because webkitSpeechRecognition is Safari-only and not available in WKWebView.

class SpeechBridgeHandler: NSObject, WKScriptMessageHandler, SFSpeechRecognizerDelegate {

    weak var webView: WKWebView?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var lastTranscript = ""

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "start":
            let lang = body["lang"] as? String ?? "en-US"
            let continuous = body["continuous"] as? Bool ?? false
            startRecognition(lang: lang, continuous: continuous)
        case "stop":
            stopRecognition(abort: false)
        case "abort":
            stopRecognition(abort: true)
        case "requestPermission":
            requestPermissions()
        default:
            break
        }
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    let ok = status == .authorized && granted
                    self?.sendToJS("window.__speechBridgePermissionResult(\(ok));")
                }
            }
        }
    }

    private func startRecognition(lang: String, continuous: Bool) {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            guard authStatus == .authorized else {
                self?.sendError("not-allowed")
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                guard granted else {
                    self?.sendError("not-allowed")
                    return
                }
                DispatchQueue.main.async {
                    self?.doStart(lang: lang, continuous: continuous)
                }
            }
        }
    }

    private func doStart(lang: String, continuous: Bool) {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session for recording
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            sendError("audio-capture")
            return
        }

        // Set up recognizer
        let locale = Locale(identifier: lang)
        speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard speechRecognizer != nil else { sendError("not-allowed"); return }
        speechRecognizer?.delegate = self

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { sendError("audio-capture"); return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        lastTranscript = ""

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString
                let isFinal = result.isFinal

                if transcript != self.lastTranscript {
                    self.lastTranscript = transcript
                    let js = "window.__speechBridgeResult(\(self.safeJSString(transcript)), \(isFinal));"
                    self.sendToJS(js)
                }

                if isFinal {
                    self.stopRecognition(abort: false)
                }
            }

            if let error = error {
                // Ignore "no speech" errors silently — just end
                let nsErr = error as NSError
                if nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 1110 {
                    // No speech detected — end silently
                    self.sendToJS("window.__speechBridgeEnd();")
                } else if nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 1101 {
                    // Recognition timed out — no speech
                    self.sendError("no-speech")
                } else {
                    self.sendError("network")
                }
                self.cleanupAudio()
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            try audioEngine.start()
            sendToJS("window.__speechBridgeStart();")
        } catch {
            sendError("audio-capture")
        }
    }

    func stopRecognition(abort: Bool) {
        recognitionRequest?.endAudio()
        cleanupAudio()
        if !abort && !lastTranscript.isEmpty {
            sendToJS("window.__speechBridgeResult(\(safeJSString(lastTranscript)), true);")
        }
        sendToJS("window.__speechBridgeEnd();")
        lastTranscript = ""
    }

    private func cleanupAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    private func safeJSString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }

    private func sendError(_ error: String) {
        sendToJS("window.__speechBridgeError(\(safeJSString(error)));")
    }

    private func sendToJS(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js) { _, _ in }
        }
    }
}

// MARK: - HealthKit Bridge

class HealthKitBridgeHandler: NSObject, WKScriptMessageHandler {

    weak var webView: WKWebView?
    private let store = HKHealthStore()

    private lazy var readTypes: Set<HKObjectType> = {
        let ids: [HKObjectType?] = [
            HKQuantityType.quantityType(forIdentifier: .stepCount),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .bodyMass),
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
        ]
        return Set(ids.compactMap { $0 })
    }()

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { completion(false); return }
        store.requestAuthorization(toShare: nil, read: readTypes) { success, _ in
            completion(success)
        }
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "getToday":
            fetchTodayData()
        case "requestPermission":
            requestAuthorization { [weak self] ok in
                DispatchQueue.main.async {
                    self?.sendToJS("if(window.__healthPermission)window.__healthPermission(\(ok ? "true" : "false"));")
                }
            }
        default: break
        }
    }

    func fetchTodayData() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Ensure authorization before querying (no-op if already granted)
        store.requestAuthorization(toShare: nil, read: readTypes) { [weak self] ok, _ in
            guard ok else { return }
            DispatchQueue.main.async { self?.doFetchTodayData() }
        }
    }

    private func doFetchTodayData() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let predToday = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        var steps: Double = 0
        var activeCal: Double = 0
        var restingCal: Double = 0
        var heartRate: Double = 0
        var sleepHours: Double = 0
        var weightKg: Double = 0
        let group = DispatchGroup()

        // Steps
        group.enter()
        querySum(.stepCount, unit: HKUnit.count(), predicate: predToday) { v in steps = v; group.leave() }

        // Active calories
        group.enter()
        querySum(.activeEnergyBurned, unit: HKUnit.kilocalorie(), predicate: predToday) { v in activeCal = v; group.leave() }

        // Resting calories
        group.enter()
        querySum(.basalEnergyBurned, unit: HKUnit.kilocalorie(), predicate: predToday) { v in restingCal = v; group.leave() }

        // Heart rate (most recent)
        group.enter()
        queryMostRecent(.heartRate, unit: HKUnit(from: "count/min"), predicate: predToday) { v in heartRate = v; group.leave() }

        // Weight (most recent ever)
        group.enter()
        queryMostRecent(.bodyMass, unit: HKUnit.gramUnit(with: .kilo), predicate: nil) { v in weightKg = v; group.leave() }

        // Sleep (last 24h)
        group.enter()
        querySleep(since: startOfDay) { h in sleepHours = h; group.leave() }

        group.notify(queue: .main) { [weak self] in
            let json = "{\"steps\":\(Int(steps)),\"activeCalories\":\(Int(activeCal)),\"restingCalories\":\(Int(restingCal)),\"heartRate\":\(Int(heartRate)),\"sleepHours\":\(String(format:"%.2f",sleepHours)),\"weight\":\(String(format:"%.2f",weightKg))}"
            self?.sendToJS("if(window.__healthDataReceived)window.__healthDataReceived(\(json));")
        }
    }

    private func querySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate?, completion: @escaping (Double) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { completion(0); return }
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
            completion(stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
        }
        store.execute(query)
    }

    private func queryMostRecent(_ id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate?, completion: @escaping (Double) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { completion(0); return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0
            completion(val)
        }
        store.execute(query)
    }

    private func querySleep(since start: Date, completion: @escaping (Double) -> Void) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { completion(0); return }
        let pred = HKQuery.predicateForSamples(withStart: start - 3600*8, end: Date(), options: .strictStartDate)
        let query = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            var secs: Double = 0
            (samples as? [HKCategorySample])?.forEach { s in
                let isAsleep: Bool
                if #available(iOS 16.0, *) {
                    isAsleep = s.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                               s.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                               s.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                               s.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                } else {
                    isAsleep = s.value == HKCategoryValueSleepAnalysis.asleep.rawValue
                }
                if isAsleep { secs += s.endDate.timeIntervalSince(s.startDate) }
            }
            completion(secs / 3600)
        }
        store.execute(query)
    }

    private func sendToJS(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js) { _, _ in }
        }
    }
}

// MARK: - Google Auth Bridge (ASWebAuthenticationSession)

class GoogleAuthBridgeHandler: NSObject, WKScriptMessageHandler, ASWebAuthenticationPresentationContextProviding {

    weak var webView: WKWebView?
    private var authSession: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return webView?.window ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "startGoogleAuth":
            guard let urlString = body["url"] as? String,
                  let url = URL(string: urlString) else { return }
            startAuth(url: url)
        default:
            break
        }
    }

    private func startAuth(url: URL) {
        authSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "sadiky-auth"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let _ = error {
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript(
                        "if(window.__googleAuthError)window.__googleAuthError('cancelled');"
                    ) { _, _ in }
                }
                return
            }

            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript(
                        "if(window.__googleAuthError)window.__googleAuthError('no_token');"
                    ) { _, _ in }
                }
                return
            }

            DispatchQueue.main.async {
                let exchangeURL = "https://sadiky.com/api/token-login.php?token=" + token
                if let url = URL(string: exchangeURL) {
                    self.webView?.load(URLRequest(url: url))
                }
            }
        }

        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }
}

// MARK: - Apple Sign-In Bridge (Native ASAuthorizationAppleIDProvider)

class AppleSignInBridgeHandler: NSObject, WKScriptMessageHandler,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    weak var webView: WKWebView?

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = webView?.window { return window }
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .first?.keyWindow { return window }
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) { return window }
        return ASPresentationAnchor()
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              action == "startAppleAuth" else { return }
        startAppleSignIn()
    }

    private func startAppleSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // Success
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            sendError("no_token")
            return
        }

        let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let email = credential.email ?? ""
        let firstName = credential.fullName?.givenName ?? ""
        let lastName = credential.fullName?.familyName ?? ""

        Task { await exchangeWithServer(identityToken: identityToken, authCode: authCode,
                                         email: email, firstName: firstName, lastName: lastName) }
    }

    // Failure / cancel
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let code = (error as? ASAuthorizationError)?.code
        let msg = code == .canceled ? "cancelled" : "error"
        sendError(msg)
    }

    private func exchangeWithServer(identityToken: String, authCode: String,
                                     email: String, firstName: String, lastName: String) async {
        guard let url = URL(string: "https://sadiky.com/api/apple-native-auth.php") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "identityToken": identityToken,
            "authorizationCode": authCode,
            "email": email,
            "firstName": firstName,
            "lastName": lastName
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode >= 200 && statusCode < 300,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String else {
                sendError("server_error")
                return
            }
            await MainActor.run {
                webView?.evaluateJavaScript("window.__appleAuthPending = false;") { _, _ in }
                if let loginURL = URL(string: "https://sadiky.com/api/token-login.php?token=" + token) {
                    webView?.load(URLRequest(url: loginURL))
                }
            }
        } catch {
            sendError("network_error")
        }
    }

    private func sendError(_ msg: String) {
        let safe = safeJSString(msg)
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(
                "if(window.__appleAuthError)window.__appleAuthError(\(safe));"
            ) { _, _ in }
        }
    }

    private func safeJSString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }
}

// MARK: - Notification Bridge
// Receives messages from the web's SadikyNotifications module and schedules
// local notifications via UNUserNotificationCenter.

class NotificationBridgeHandler: NSObject, WKScriptMessageHandler {

    weak var webView: WKWebView?
    private let center = UNUserNotificationCenter.current()

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "requestPermission":
            requestPermission()
        case "schedule":
            guard let id = body["id"] as? String,
                  let title = body["title"] as? String,
                  let bodyText = body["body"] as? String else { return }
            let timestamp = body["timestamp"] as? Double ?? 0
            let repeating = body["repeating"] as? Bool ?? false
            scheduleNotification(id: id, title: title, body: bodyText, timestamp: timestamp, repeating: repeating)
        case "cancel":
            if let id = body["id"] as? String {
                cancelNotification(id: id)
            }
        default:
            break
        }
    }

    private func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.sendToJS("if(window.__notifPermissionResult)window.__notifPermissionResult(\(granted));")
            }
        }
    }

    private func scheduleNotification(id: String, title: String, body: String, timestamp: Double, repeating: Bool) {
        // Remove any existing notification with same ID
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger: UNNotificationTrigger

        if repeating && timestamp > 0 {
            // If timestamp looks like a time-of-day (ms since epoch), extract hour/minute
            // and create a daily repeating calendar trigger
            let date = Date(timeIntervalSince1970: timestamp / 1000.0)
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        } else if timestamp > 86400000 {
            // Looks like a future timestamp (ms since epoch) — schedule once
            let interval = (timestamp / 1000.0) - Date().timeIntervalSince1970
            guard interval > 0 else { return }
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        } else if timestamp > 0 {
            // Small value — treat as interval in ms (e.g. water reminder every 2h)
            let intervalSec = timestamp / 1000.0
            // UNTimeIntervalNotificationTrigger requires >= 60s for repeating
            let safeSec = max(intervalSec, 60)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: safeSec, repeats: repeating)
        } else {
            // No timestamp — fire in 1 second (testing/debug)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                print("[NotificationBridge] Error scheduling \(id): \(error.localizedDescription)")
            }
        }
    }

    private func cancelNotification(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    private func sendToJS(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js) { _, _ in }
        }
    }
}

// MARK: - Main View Controller

class ViewController: CAPBridgeViewController, SettingsWebViewProvider {

    private let speechHandler = SpeechBridgeHandler()
    private let healthHandler = HealthKitBridgeHandler()
    private let googleAuthHandler = GoogleAuthBridgeHandler()
    private let appleAuthHandler = AppleSignInBridgeHandler()
    private let notificationHandler = NotificationBridgeHandler()
    private let settingsHandler = SettingsBridgeHandler()
    private var storeKitManager: Any?  // StoreKitManager (iOS 15+, typed as Any for compilation)
    private var hasLoadedRemoteURL = false
    private var settingsButton: UIButton?

    var settingsWebView: WKWebView? { webView }

    // MARK: Branding

    private static let replacementJS = """
    (function() {
        var pairs = [
            ['NeuraPal', 'Sadiky'],
            ['Neurapal', 'Sadiky'],
            ['NEURAPAL', 'SADIKY'],
            ['neurapal', 'sadiky']
        ];
        document.querySelectorAll('a.nav-logo, .nav-logo, [class*="nav-logo"]').forEach(function(el) {
            if (el.textContent.indexOf('NeuraPal') !== -1 || el.textContent.indexOf('Neura') !== -1) {
                el.innerHTML = 'Sadi<span style="color:#3B82F6">ky</span>';
            }
        });
        var walker = document.createTreeWalker(document.body || document.documentElement, 0x4, null, false);
        var node, toFix = [];
        while ((node = walker.nextNode())) {
            var v = node.nodeValue;
            if (!v) continue;
            for (var i = 0; i < pairs.length; i++) {
                if (v.indexOf(pairs[i][0]) !== -1) { toFix.push(node); break; }
            }
        }
        toFix.forEach(function(n) {
            var v = n.nodeValue;
            for (var i = 0; i < pairs.length; i++) { v = v.split(pairs[i][0]).join(pairs[i][1]); }
            n.nodeValue = v;
        });
        if (document.title) {
            var t = document.title;
            for (var i = 0; i < pairs.length; i++) { t = t.split(pairs[i][0]).join(pairs[i][1]); }
            document.title = t;
        }
        return 'ok';
    })();
    """

    /// JavaScript polyfill — installed once at page start so the web app's
    /// SpeechRecognition calls are routed through our native SFSpeechRecognizer bridge.
    private static let speechPolyfillJS = """
    (function() {
        if (window.__speechBridgeInstalled) return;
        window.__speechBridgeInstalled = true;

        var _listeners = {};   // instanceId -> SpeechRecognition instance
        var _nextId = 1;

        // Callbacks invoked by Swift
        window.__speechBridgeStart = function() {
            Object.values(_listeners).forEach(function(r) {
                if (r.onstart) r.onstart(new Event('start'));
                r.dispatchEvent && r.dispatchEvent(new Event('start'));
            });
        };
        window.__speechBridgeEnd = function() {
            Object.values(_listeners).forEach(function(r) {
                if (r.onend) r.onend(new Event('end'));
                r.dispatchEvent && r.dispatchEvent(new Event('end'));
            });
            _listeners = {};
        };
        window.__speechBridgeError = function(err) {
            Object.values(_listeners).forEach(function(r) {
                var e = new Event('error');
                e.error = err;
                if (r.onerror) r.onerror(e);
                r.dispatchEvent && r.dispatchEvent(e);
            });
        };
        window.__speechBridgeResult = function(transcript, isFinal) {
            Object.values(_listeners).forEach(function(r) {
                try {
                    // Build a SpeechRecognitionResult-like object
                    var alt = { transcript: transcript, confidence: undefined };
                    var result = [alt];
                    result.isFinal = isFinal;
                    var resultList = [result];
                    var e = new Event('result');
                    e.resultIndex = 0;
                    e.results = resultList;
                    if (r.onresult) r.onresult(e);
                    r.dispatchEvent && r.dispatchEvent(e);
                } catch(ex) {}
            });
        };
        window.__speechBridgePermissionResult = function(granted) {};

        // SpeechRecognition class
        function NativeSpeechRecognition() {
            this._id = _nextId++;
            this.lang = navigator.language || 'en-US';
            this.continuous = false;
            this.interimResults = true;
            this.maxAlternatives = 1;
            this.onstart = null;
            this.onend = null;
            this.onresult = null;
            this.onerror = null;
            this.onnomatch = null;
            this._evtListeners = {};
        }
        NativeSpeechRecognition.prototype.start = function() {
            _listeners[this._id] = this;
            webkit.messageHandlers.speechBridge.postMessage({
                action: 'start',
                lang: this.lang,
                continuous: this.continuous,
                interimResults: this.interimResults
            });
        };
        NativeSpeechRecognition.prototype.stop = function() {
            delete _listeners[this._id];
            webkit.messageHandlers.speechBridge.postMessage({ action: 'stop' });
        };
        NativeSpeechRecognition.prototype.abort = function() {
            delete _listeners[this._id];
            webkit.messageHandlers.speechBridge.postMessage({ action: 'abort' });
        };
        NativeSpeechRecognition.prototype.addEventListener = function(type, fn) {
            if (!this._evtListeners[type]) this._evtListeners[type] = [];
            this._evtListeners[type].push(fn);
        };
        NativeSpeechRecognition.prototype.removeEventListener = function(type, fn) {
            if (!this._evtListeners[type]) return;
            this._evtListeners[type] = this._evtListeners[type].filter(function(f) { return f !== fn; });
        };
        NativeSpeechRecognition.prototype.dispatchEvent = function(e) {
            var listeners = this._evtListeners[e.type] || [];
            listeners.forEach(function(fn) { try { fn(e); } catch(ex) {} });
        };

        // Install — only if not already natively supported
        if (!window.SpeechRecognition && !window.webkitSpeechRecognition) {
            window.SpeechRecognition = NativeSpeechRecognition;
            window.webkitSpeechRecognition = NativeSpeechRecognition;
            window.SpeechGrammarList = function() {};
            window.webkitSpeechGrammarList = window.SpeechGrammarList;
        }
    })();
    """

    /// JavaScript snippet injected on every page to ensure subscription compliance
    /// links (Terms, Privacy, EULA) are available to the web layer even if the
    /// remote page doesn't render them.  Exposes a global helper the paywall can call.
    private static let complianceLinksJS = """
    (function() {
        if (window.__complianceLinksReady) return;
        window.__complianceLinksReady = true;

        window.__complianceURLs = {
            terms:   'https://sadiky.com/terms.html',
            privacy: 'https://sadiky.com/privacy.html',
            eula:    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'
        };

        window.__openComplianceLink = function(type) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.iapBridge) {
                var action = 'open' + type.charAt(0).toUpperCase() + type.slice(1);
                window.webkit.messageHandlers.iapBridge.postMessage({ action: action });
            } else {
                var url = window.__complianceURLs[type];
                if (url) window.open(url, '_blank');
            }
        };

        // Inject compliance footer on subscription / paywall pages
        function injectComplianceFooter() {
            if (document.getElementById('sadiky-compliance-footer')) return;
            // Try broad set of selectors for the paywall container
            var paywallEl = document.querySelector('[data-paywall], .paywall, .subscription-page, .premium-page, #paywall, #subscription, .pricing, .plans, .upgrade, [data-premium], [data-subscription]');

            var footer = document.createElement('div');
            footer.id = 'sadiky-compliance-footer';
            footer.style.cssText = 'text-align:center;padding:12px 16px 20px;font-size:11px;color:rgba(255,255,255,0.5);line-height:1.6;';
            footer.innerHTML =
                'Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. ' +
                'Payment will be charged to your Apple ID account. ' +
                'Manage subscriptions in your device Settings.<br>' +
                '<a href="#" onclick="__openComplianceLink(\\'terms\\');return false;" style="color:#3B82F6;text-decoration:underline;">Terms of Use</a>' +
                ' · ' +
                '<a href="#" onclick="__openComplianceLink(\\'privacy\\');return false;" style="color:#3B82F6;text-decoration:underline;">Privacy Policy</a>' +
                ' · ' +
                '<a href="#" onclick="__openComplianceLink(\\'eula\\');return false;" style="color:#3B82F6;text-decoration:underline;">EULA</a>';

            if (!paywallEl) return;
            paywallEl.appendChild(footer);
        }

        // Run on load and observe DOM changes for SPA navigations
        if (document.readyState === 'complete' || document.readyState === 'interactive') {
            setTimeout(injectComplianceFooter, 500);
        } else {
            document.addEventListener('DOMContentLoaded', function() { setTimeout(injectComplianceFooter, 500); });
        }
        var _compObs = new MutationObserver(function() { setTimeout(injectComplianceFooter, 300); });
        _compObs.observe(document.body || document.documentElement, { childList: true, subtree: true });
    })();
    """

    /// JavaScript injected on every page to intercept web-based Apple sign-in
    /// clicks and route them through the native ASAuthorizationController bridge.
    private static let appleSignInInterceptJS = """
    (function() {
        document.addEventListener('click', function(e) {
            var el = e.target.closest('a[href*="apple_login"], a[href*="apple-login"], button[class*="apple"], .apple-signin, .apple-login, [data-apple-signin], [onclick*="apple_login"], [onclick*="appleLogin"]');
            if (!el) return;
            e.preventDefault();
            e.stopPropagation();
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.appleAuthBridge) {
                window.webkit.messageHandlers.appleAuthBridge.postMessage({ action: 'startAppleAuth' });
            }
        }, true);
    })();
    """

    /// Hides "Skip for now" / "Maybe later" buttons in HealthKit permission contexts (Guideline 5.1.1(iv))
    private static let enforceHealthPermissionJS = """
    (function(){
        new MutationObserver(function(){
            document.querySelectorAll('button,a,[role="button"]').forEach(function(el){
                var t=(el.textContent||'').toLowerCase().trim();
                if((t==='skip for now'||t==='skip'||t==='maybe later')&&
                   el.closest('[class*="health"],[class*="permission"],[data-modal*="health"]')){
                    el.style.display='none';
                }
            });
        }).observe(document.body||document.documentElement,{childList:true,subtree:true});
    })();
    """

    /// Scrolls focused inputs into view when keyboard appears (Guideline 4 — keyboard fix)
    private static let keyboardFixJS = """
    (function(){
        window.addEventListener('keyboardWillShow',function(){
            var f=document.activeElement;
            if(f&&(f.tagName==='INPUT'||f.tagName==='TEXTAREA')){
                setTimeout(function(){f.scrollIntoView({behavior:'smooth',block:'center'});},300);
            }
        });
    })();
    """

    /// Intercepts subscribe.php page loads and triggers the native SubscriptionStoreView
    /// via the iapBridge, ensuring Apple's Guideline 3.1.2(c) compliance.
    private static let subscribeInterceptJS = """
    (function(){
        if(window.location.pathname.indexOf('/subscribe') === -1) return;
        if(!window.webkit||!window.webkit.messageHandlers||!window.webkit.messageHandlers.iapBridge) return;
        window.webkit.messageHandlers.iapBridge.postMessage({action:'showNativeSubscription'});
    })();
    """

    // MARK: Lifecycle

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !OnboardingViewController.hasCompletedOnboarding {
            presentOnboarding()
        } else if !hasLoadedRemoteURL {
            loadRemoteApp()
        }
    }

    private func presentOnboarding() {
        let onboarding = OnboardingViewController()
        onboarding.modalPresentationStyle = .fullScreen
        onboarding.onComplete = { [weak self] in
            self?.dismiss(animated: true) {
                self?.loadRemoteApp()
            }
        }
        present(onboarding, animated: false)
    }

    private func loadRemoteApp() {
        guard !hasLoadedRemoteURL else { return }
        hasLoadedRemoteURL = true
        if let url = URL(string: "https://sadiky.com/") {
            webView?.load(URLRequest(url: url))
        }
    }

    override func capacitorDidLoad() {
        super.capacitorDidLoad()

        // Wire speech handler to the webview
        speechHandler.webView = webView
        webView?.configuration.userContentController
            .add(speechHandler, name: "speechBridge")

        // Wire HealthKit bridge
        healthHandler.webView = webView
        webView?.configuration.userContentController
            .add(healthHandler, name: "healthBridge")

        // Wire Google Auth bridge
        googleAuthHandler.webView = webView
        webView?.configuration.userContentController
            .add(googleAuthHandler, name: "googleAuthBridge")

        // Wire Apple Sign-In bridge
        appleAuthHandler.webView = webView
        webView?.configuration.userContentController
            .add(appleAuthHandler, name: "appleAuthBridge")

        // Wire Notification bridge
        notificationHandler.webView = webView
        webView?.configuration.userContentController
            .add(notificationHandler, name: "notificationBridge")

        // Wire StoreKit IAP bridge
        if #available(iOS 15.0, *) {
            let skm = StoreKitManager()
            skm.webView = webView
            skm.viewController = self
            webView?.configuration.userContentController
                .add(skm, name: "iapBridge")
            storeKitManager = skm
        }

        // Wire Settings bridge
        settingsHandler.viewController = self
        webView?.configuration.userContentController
            .add(settingsHandler, name: "settingsBridge")

        // Keyboard dismiss on scroll (Guideline 4)
        webView?.scrollView.keyboardDismissMode = .interactive

        // Inject speech polyfill on every page load
        injectSpeechPolyfill()

        // Inject compliance links for App Store Guidelines 3.1.2(c)
        injectComplianceLinks()

        // Inject Apple Sign-In intercept to route web clicks to native bridge
        let appleScript = WKUserScript(
            source: Self.appleSignInInterceptJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView?.configuration.userContentController.addUserScript(appleScript)

        // Inject HealthKit skip-button enforcement (Guideline 5.1.1(iv))
        let healthScript = WKUserScript(
            source: Self.enforceHealthPermissionJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView?.configuration.userContentController.addUserScript(healthScript)

        // Inject keyboard scroll-into-view fix (Guideline 4)
        let keyboardScript = WKUserScript(
            source: Self.keyboardFixJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView?.configuration.userContentController.addUserScript(keyboardScript)

        // Intercept subscribe.php to present native SubscriptionStoreView (Guideline 3.1.2(c))
        let subscribeInterceptScript = WKUserScript(
            source: Self.subscribeInterceptJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView?.configuration.userContentController.addUserScript(subscribeInterceptScript)

        startBrandingTimer()

        // Add native floating gear button for Settings access (Guideline 2.1(b))
        addSettingsButton()

        // Re-check entitlement after webview is ready so the web layer
        // receives __iapStatus on launch (the init() check fires before
        // webView is assigned, so its callback goes to nil).
        if #available(iOS 15.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                if let skm = self?.storeKitManager as? StoreKitManager {
                    Task { await skm.checkEntitlement() }
                }
            }
        }
    }

    private func addSettingsButton() {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        button.setImage(UIImage(systemName: "gearshape.fill", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.layer.cornerRadius = 22
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(openSettingsFromButton), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
        ])
        settingsButton = button
    }

    @objc private func openSettingsFromButton() {
        let settingsVC = SettingsViewController()
        settingsVC.webView = webView
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func injectSpeechPolyfill() {
        let script = ViewController.speechPolyfillJS
        webView?.evaluateJavaScript(script) { _, _ in }

        // Also set up a navigation observer to re-inject on SPA navigations
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onNavigation),
            name: .capacitorDecidePolicyForNavigationAction,
            object: nil
        )
    }

    private func injectComplianceLinks() {
        webView?.evaluateJavaScript(ViewController.complianceLinksJS) { _, _ in }
    }

    @objc private func onNavigation() {
        // Re-inject after a short delay to let the new page initialise
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let js = Self.speechPolyfillJS
            self?.webView?.evaluateJavaScript(js) { _, _ in }
            // Re-inject compliance links on SPA navigation
            self?.webView?.evaluateJavaScript(Self.complianceLinksJS) { _, _ in }
        }
    }

    private func startBrandingTimer() {
        // Server NeuraPal branding is fixed. Run branding replacement twice as a safety
        // net for cached pages — once after 0.5s and once after 2s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.applyBranding()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.applyBranding()
        }
    }

    private func applyBranding() {
        webView?.evaluateJavaScript(ViewController.replacementJS) { _, _ in }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "speechBridge")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "healthBridge")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "iapBridge")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "googleAuthBridge")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "appleAuthBridge")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "notificationBridge")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "settingsBridge")
    }
}
