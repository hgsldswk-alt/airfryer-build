import ActivityKit
import Foundation

enum WidgetData {
    static let group = "group.com.hgsldswk.airfryercheatsheet"
    static let storageKey = "widget.snapshot"
    static let kind = "PinnedFood"

    struct Snapshot: Codable {
        var fryerID: UUID
        var fryerName: String?
        var foodID: String
        var customName: String?
        var celsius: Int
        var duration: Int
        var unit: TemperatureUnit
        var validUntil: Date?
        var pro: Bool

        func hasPro(at date: Date) -> Bool { pro && (validUntil.map { date < $0 } ?? true) }

        var url: URL {
            URL(string: "airfryersheet://food/\(fryerID.uuidString)/\(foodID)")!
        }
    }

    static func read() -> Snapshot? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}

struct CookActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var started: Date
        var deadline: Date
        var pausedSeconds: Int?
        var temperature: String
    }

    var sessionID: UUID
    var food: String
    var fryer: String
}
