import SwiftUI
import StoreKit

// MARK: - Native Subscription Store (iOS 17+)
// Presents Apple's SubscriptionStoreView which automatically displays
// all required 3.1.2(c) information: title, price, duration, trial,
// auto-renewal terms, and links to Terms of Use / Privacy Policy.

@available(iOS 17.0, *)
struct NativeSubscriptionView: View {

    @Environment(\.dismiss) private var dismiss
    var onPurchaseComplete: (() -> Void)?

    var body: some View {
        SubscriptionStoreView(groupID: "21945240") {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Sadiky Premium")
                    .font(.title.bold())

                Text("Unlimited AI meal analysis, personalized plans, advanced health insights, and more.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 20)
        }
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(_)) = result {
                onPurchaseComplete?()
                dismiss()
            }
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .redeemCode)
    }
}
