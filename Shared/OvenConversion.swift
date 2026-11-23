import Foundation

enum OvenConversion {
    struct Estimate: Equatable {
        let temperature: Int
        let firstCheck: Int
    }

    static func range(for unit: TemperatureUnit) -> ClosedRange<Int> {
        unit.displayed(95)...unit.displayed(260)
    }

    static func suggest(oven: Int, minutes: Int, unit: TemperatureUnit) -> Estimate? {
        guard range(for: unit).contains(oven), Settings.durations.contains(minutes) else { return nil }
        let difference = unit == .fahrenheit ? 25 : 14
        let maxFryerSetting = unit.displayed(Settings.temperatures.upperBound)
        return Estimate(temperature: min(oven - difference, maxFryerSetting),
                        firstCheck: max(1, minutes * 4 / 5))
    }
}
