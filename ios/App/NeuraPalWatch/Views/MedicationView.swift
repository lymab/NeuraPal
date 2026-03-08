import SwiftUI

struct MedicationView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blueAccent)
                    Text("Medications")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 4)

                ForEach(DemoData.medications) { med in
                    VStack(spacing: 4) {
                        Text(med.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(med.time)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blueAccent)
                    .cornerRadius(12)
                }

                Text("Mentium Labs")
                    .font(.system(size: 11))
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 2)
        }
        .background(Color.navyBackground)
    }
}
