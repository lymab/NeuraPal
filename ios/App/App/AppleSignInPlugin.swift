import Foundation
import Capacitor
import AuthenticationServices

@objc(AppleSignInPlugin)
class AppleSignInPlugin: CAPPlugin, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    var savedCall: CAPPluginCall?

    @objc func signIn(_ call: CAPPluginCall) {
        savedCall = call

        DispatchQueue.main.async {
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = self.bridge?.webView?.window { return window }
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

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            savedCall?.reject("Invalid credential type")
            return
        }

        var result: [String: Any] = [
            "user": credential.user
        ]

        if let email = credential.email {
            result["email"] = email
        }
        if let givenName = credential.fullName?.givenName {
            result["givenName"] = givenName
        }
        if let familyName = credential.fullName?.familyName {
            result["familyName"] = familyName
        }
        if let tokenData = credential.identityToken,
           let token = String(data: tokenData, encoding: .utf8) {
            result["identityToken"] = token
        }
        if let codeData = credential.authorizationCode,
           let code = String(data: codeData, encoding: .utf8) {
            result["authorizationCode"] = code
        }

        savedCall?.resolve(result)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let authError = error as? ASAuthorizationError
        if authError?.code == .canceled {
            savedCall?.reject("User cancelled", "CANCELLED")
        } else {
            savedCall?.reject("Apple Sign In failed: \(error.localizedDescription)", nil, error)
        }
    }
}
