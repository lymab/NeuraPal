import SwiftUI

struct DailyScheduleView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14))
                        .foregroundColor(.blueAccent)
                    Text("Today")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 4)

                ForEach(DemoData.schedule) { item in
                    HStack(spacing: 8) {
                        Text(item.time)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blueAccent)
                            .frame(width: 40, alignment: .trailing)

                        Circle()
                            .fill(item.isCompleted ? Color.green : Color.blueAccent.opacity(0.5))
                            .frame(width: 8, height: 8)

                        Text(item.title)
                            .font(.system(size: 12))
                            .foregroundColor(item.isCompleted ? .white.opacity(0.5) : .white)
                            .strikethrough(item.isCompleted)
                            .lineLimit(1)

                        Spacer()
                    }
                }

                Button(action: {}) {
                    HStack(spacing: 6) {
                        Image(systemName: "iphone")
                            .font(.system(size: 11))
                        Text("View on iPhone")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.blueAccent)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.blueAccent.opacity(0.15))
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Text("Mentium Labs")
                    .font(.system(size: 11))
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 2)
        }
        .background(Color.navyBackground)
    }
}
