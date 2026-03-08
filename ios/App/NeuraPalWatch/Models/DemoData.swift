import Foundation

struct Medication: Identifiable {
    let id = UUID()
    let name: String
    let time: String
}

struct ScheduleItem: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let isCompleted: Bool
}

enum DemoData {
    static let medications = [
        Medication(name: "Aspirin", time: "8:00 AM"),
        Medication(name: "Vitamin D", time: "12:00 PM"),
        Medication(name: "Omega-3", time: "6:00 PM"),
    ]

    static let schedule: [ScheduleItem] = [
        ScheduleItem(time: "7:00", title: "Morning meds", isCompleted: true),
        ScheduleItem(time: "8:30", title: "Breakfast log", isCompleted: true),
        ScheduleItem(time: "12:00", title: "Vitamin D", isCompleted: false),
        ScheduleItem(time: "12:30", title: "Lunch log", isCompleted: false),
        ScheduleItem(time: "6:00", title: "Omega-3", isCompleted: false),
        ScheduleItem(time: "7:00", title: "Dinner log", isCompleted: false),
        ScheduleItem(time: "10:00", title: "Sleep check-in", isCompleted: false),
    ]
}
