import Foundation

enum Foods {
    static let starter = [
        item("fries", .frozen, 185...200, 12...17, 190, 14, .shake, 7, "safety.package"),
        item("hashbrowns", .frozen, 185...200, 10...15, 190, 12, .flip, 6, "safety.package"),
        item("nuggets", .frozen, 180...200, 8...13, 190, 10, .flip, 5, "safety.precooked"),
        item("fishsticks", .frozen, 180...200, 8...13, 190, 10, .flip, 5, "safety.precooked"),
        item("wings", .meat, 185...200, 18...26, 195, 22, .flip, 11, "safety.poultry"),
        item("breast", .meat, 175...195, 14...21, 185, 17, .flip, 8, "safety.poultry"),
        item("thigh", .meat, 180...200, 16...23, 190, 19, .flip, 9, "safety.poultry"),
        item("salmon", .seafood, 175...200, 8...14, 190, 11, .none, nil, "safety.salmon"),
        item("shrimp", .seafood, 175...195, 6...10, 185, 8, .shake, 4, "safety.shrimp"),
        item("broccoli", .vegetables, 170...190, 7...12, 180, 9, .shake, 5),
        item("potato", .vegetables, 180...200, 16...24, 190, 20, .shake, 10),
        item("sweetpotato", .vegetables, 175...195, 13...21, 185, 17, .shake, 8),
        item("zucchini", .vegetables, 175...195, 8...14, 185, 11, .flip, 5),
        item("pizza", .leftovers, 150...175, 4...8, 165, 6, .check, 4, "safety.leftovers")
    ]

    private static func item(_ id: String, _ group: FoodGroup, _ celsius: ClosedRange<Int>,
                             _ duration: ClosedRange<Int>, _ c: Int, _ m: Int,
                             _ reminder: Reminder, _ minute: Int?, _ safety: String = "safety.general") -> Food {
        Food(id: id, group: group, defaults: Settings(celsius: c, minutes: m, reminder: reminder, reminderMinute: minute),
             minC: celsius.lowerBound, maxC: celsius.upperBound,
             minMinutes: duration.lowerBound, maxMinutes: duration.upperBound, safety: safety)
    }
}
