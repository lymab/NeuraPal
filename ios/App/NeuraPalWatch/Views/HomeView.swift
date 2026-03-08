import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer(minLength: 8)

                HStack(spacing: 0) {
                    Text("Neura")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text("Pal")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.blueAccent)
                }

                Text("AI Health Companion")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)

                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    FeatureRow(icon: "waveform", text: "Voice Coaching")
                    FeatureRow(icon: "pills", text: "Medication Tracking")
                    FeatureRow(icon: "fork.knife", text: "Meal Analysis")
                }

                Spacer(minLength: 16)

                Text("Mentium Labs")
                    .font(.system(size: 11))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.navyBackground)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.blueAccent)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
    }
}
