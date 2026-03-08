import SwiftUI

struct MealScoreView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text("Meal Score")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 4)

                VStack(spacing: 4) {
                    Text("8.5/10")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("Great balance!")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green.opacity(0.2))
                .cornerRadius(12)

                VStack(spacing: 6) {
                    NutrientRow(label: "Protein", value: "Excellent", valueColor: .green)
                    NutrientRow(label: "Vegetables", value: "Good", valueColor: .green)
                    NutrientRow(label: "Carbs", value: "Moderate", valueColor: .yellow)
                }
                .padding(.top, 4)

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

struct NutrientRow: View {
    let label: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
}
