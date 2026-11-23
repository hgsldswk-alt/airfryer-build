import Foundation
import Darwin

struct ClockReading: Codable, Equatable {
    var date: Date
    var uptime: TimeInterval

    static var now: Self {
        Self(date: Date(), uptime: Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000)
    }

    func seconds(since start: Self, sameBoot: Bool) -> TimeInterval {
        let wall = date.timeIntervalSince(start.date)
        let monotonic = uptime - start.uptime
        if monotonic >= 0, sameBoot || abs(wall - monotonic) < 5 { return monotonic }
        return max(0, wall)
    }
}

struct ResultDraft: Codable, Equatable {
    var celsius: Int
    var portion = ""
    var note = ""
}

struct CookTimer: Codable, Equatable, Identifiable {
    var id = UUID()
    var key: FoodKey
    var food: Food
    var fryerName: String?
    var portion: String
    var original: Settings
    var total: TimeInterval
    var spent: TimeInterval = 0
    var runningSince: ClockReading?
    var confirmedAt: TimeInterval?
    var revision = 0
    var unit: TemperatureUnit?
    var resultDraft: ResultDraft?

    init(key: FoodKey, food: Food, fryerName: String?, portion: String,
         settings: Settings, now: ClockReading) {
        self.key = key
        self.food = food
        self.fryerName = fryerName
        self.portion = portion
        original = settings
        total = Double(settings.minutes * 60)
        runningSince = now
    }

    var plannedReminder: TimeInterval? { original.reminderMinute.map { Double($0 * 60) } }

    func elapsed(at now: ClockReading, sameBoot: Bool = true) -> TimeInterval {
        min(total, spent + (runningSince.map { now.seconds(since: $0, sameBoot: sameBoot) } ?? 0))
    }

    func remaining(at now: ClockReading) -> TimeInterval { max(0, total - elapsed(at: now)) }

    func reminderIsDue(at now: ClockReading) -> Bool {
        guard confirmedAt == nil, let plannedReminder else { return false }
        let time = elapsed(at: now)
        return time >= plannedReminder && time < total
    }

    mutating func recover(at now: ClockReading) {
        guard runningSince != nil else { return }
        spent = elapsed(at: now, sameBoot: false)
        runningSince = spent < total ? now : nil
        revision += 1
    }

    mutating func reanchor(at now: ClockReading) {
        guard runningSince != nil else { return }
        spent = elapsed(at: now)
        runningSince = spent < total ? now : nil
        revision += 1
    }

    mutating func pause(at now: ClockReading) {
        spent = elapsed(at: now)
        runningSince = nil
        revision += 1
    }

    mutating func resume(at now: ClockReading) {
        guard runningSince == nil, spent < total else { return }
        runningSince = now
        revision += 1
    }

    mutating func add(minutes: Int, at now: ClockReading) {
        let wasComplete = remaining(at: now) == 0
        let wasRunning = runningSince != nil
        pause(at: now)
        total = min(Double(Settings.durations.upperBound * 60), total + Double(minutes * 60))
        if wasComplete, confirmedAt == nil, plannedReminder != nil { confirmedAt = plannedReminder }
        if wasComplete || wasRunning { resume(at: now) }
    }

    mutating func confirmReminder(at now: ClockReading) {
        guard reminderIsDue(at: now) else { return }
        confirmedAt = elapsed(at: now)
        revision += 1
    }

    func actual(celsius: Int) -> Settings {
        var result = original
        result.celsius = celsius
        result.minutes = Int(ceil(total / 60))
        if let confirmedAt {
            result.reminderMinute = max(1, Int((confirmedAt / 60).rounded()))
        }
        result.normalizeReminder()
        return result
    }
}
