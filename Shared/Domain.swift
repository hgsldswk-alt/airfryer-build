import Foundation

enum TemperatureUnit: String, Codable, CaseIterable {
    case celsius, fahrenheit

    static var regional: Self { Locale.current.measurementSystem == .us ? .fahrenheit : .celsius }

    var symbol: String { self == .celsius ? "°C" : "°F" }

    func displayed(_ celsius: Int) -> Int {
        self == .celsius ? celsius : Int((Double(celsius) * 1.8 + 32).rounded())
    }

    func canonical(_ value: Int) -> Int {
        self == .celsius ? value : Int(((Double(value) - 32) / 1.8).rounded())
    }

    func label(_ celsius: Int) -> String { "\(displayed(celsius))\(symbol)" }
}

enum FoodGroup: String, Codable, CaseIterable {
    case frozen, meat, seafood, vegetables, leftovers, custom, friend
    var title: String { L.t("group." + rawValue) }
}

enum Reminder: String, Codable, CaseIterable {
    case none, shake, flip, check
    var title: String { L.t("reminder." + rawValue) }
    var prompt: String { L.t("prompt." + rawValue) }
    var confirmation: String { L.t("confirm." + rawValue) }
}

struct Settings: Codable, Equatable, Hashable {
    static let temperatures = 60...230
    static let durations = 1...180

    var celsius: Int
    var minutes: Int
    var reminder: Reminder = .none
    var reminderMinute: Int? = nil

    var valid: Bool {
        guard Self.temperatures.contains(celsius), Self.durations.contains(minutes) else { return false }
        if reminder == .none { return reminderMinute == nil }
        guard let reminderMinute else { return false }
        return (1..<minutes).contains(reminderMinute)
    }

    mutating func normalizeReminder() {
        guard reminder != .none, minutes > 1 else {
            reminder = .none
            reminderMinute = nil
            return
        }
        reminderMinute = min(minutes - 1, max(1, reminderMinute ?? minutes / 2))
    }

    var reminderLabel: String {
        guard let reminderMinute else { return reminder.title }
        return L.f("reminder.at", reminder.title, reminderMinute)
    }
}

struct Food: Codable, Equatable, Identifiable {
    var id: String
    var group: FoodGroup
    var customName: String? = nil
    var customPortion: String? = nil
    var customState: String? = nil
    var defaults: Settings
    var minC: Int
    var maxC: Int
    var minMinutes: Int
    var maxMinutes: Int
    var safety: String = "safety.general"

    var name: String { customName ?? L.t("food." + id) }
    var portion: String { customPortion ?? L.t("portion." + id) }
    var state: String {
        if let customState, !customState.isEmpty { return customState }
        switch id {
        case "wings", "breast", "thigh", "salmon", "shrimp", "pizza": return L.t("state.chilled")
        case "nuggets", "fishsticks": return L.t("state.precooked")
        case "broccoli", "potato", "sweetpotato", "zucchini": return L.t("state.fresh")
        default: return group.title
        }
    }

    var searchText: String {
        [name, state, portion, customName == nil ? L.t("alias." + id) : ""].joined(separator: " ")
    }
}

struct Fryer: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String? = nil
    var archived = false

    var title: String { name ?? L.t("fryer.default") }
}

struct FoodKey: Codable, Equatable, Hashable {
    var fryerID: UUID
    var foodID: String
    var portion: String = ""
}

struct Calibration: Codable, Equatable {
    var key: FoodKey
    var settings: Settings
    var portion: String
    var note: String
}

struct CustomFood: Codable, Equatable, Identifiable {
    var fryerID: UUID
    var food: Food
    var originalID: String? = nil
    var id: String { food.id }
}

struct CookRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var key: FoodKey
    var name: String
    var settings: Settings
    var completedAt: Date
}

struct CoreReviewProgress: Codable, Equatable {
    private var localDays: Set<String> = []

    var isEligible: Bool { localDays.count >= 3 }

    mutating func record(at date: Date, calendar: Calendar = .current) {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        if let year = parts.year, let month = parts.month, let day = parts.day {
            localDays.insert("\(year)-\(month)-\(day)")
        }
    }
}
