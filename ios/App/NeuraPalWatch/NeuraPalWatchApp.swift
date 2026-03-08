import SwiftUI

@main
struct NeuraPalWatchApp: App {
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                HomeView().tag(0)
                MedicationView().tag(1)
                MealScoreView().tag(2)
                DailyScheduleView().tag(3)
            }
            .tabViewStyle(.verticalPage)
            .background(Color.navyBackground)
        }
    }
}
