import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = AppState()
    @Published private(set) var ready = false
    @Published private(set) var saving = false
    @Published var message: String?
    @Published private(set) var notificationsAvailable = true
    @Published private(set) var notificationError = false
    @Published private(set) var now = ClockReading.now

    private let store = LocalStore(testing: Launch.isTesting, reset: Launch.arguments.contains("-reset"))
    private let effects = TimerEffects()
    private var loading = false
    private var lastClock = ClockReading.now
    private var currentWidget: Data?

    var hasPro: Bool { state.entitlement.hasPro(at: now.date) }
    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }

    func load() async {
        guard !ready, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            var loaded = try await store.load()
            let clock = ClockReading.now
            if Launch.isTesting { seed(&loaded, clock: clock) }
            loaded.timer?.recover(at: clock)
            try await store.write(loaded)
            state = loaded
            now = clock
            lastClock = clock
            ready = true
            synchronize()
            updateWidget()
        } catch {
            self.message = L.t("error.load")
        }
    }

    func commit(_ edit: (inout AppState) -> Void) async -> Bool {
        guard ready, !saving else { return false }
        var updated = state
        edit(&updated)
        if updated == state { return true }
        saving = true
        defer { saving = false }
        do {
            try await store.write(updated)
            let previous = state
            state = updated
            updateWidget()
            if previous.timer != updated.timer {
                synchronize(ask: updated.timer?.id != previous.timer?.id && updated.timer != nil,
                            allowStart: updated.timer?.runningSince != nil)
            } else if previous.entitlement != updated.entitlement {
                synchronize(allowStart: true)
            }
            return true
        } catch {
            self.message = L.t("error.save")
            return false
        }
    }

    func tick() async {
        let clock = ClockReading.now
        let previous = lastClock
        lastClock = clock
        let oldPro = hasPro
        let wasRunning = (state.timer?.remaining(at: now) ?? 0) > 0
        now = clock
        if previous.uptime <= clock.uptime,
           abs(clock.date.timeIntervalSince(previous.date) - (clock.uptime - previous.uptime)) > 2 {
            _ = await commit { $0.timer?.reanchor(at: clock) }
        }
        if wasRunning, let timer = state.timer, timer.remaining(at: clock) == 0, timer.runningSince != nil {
            _ = await commit { $0.timer?.pause(at: clock) }
        }
        if oldPro != hasPro {
            synchronize()
            updateWidget()
        }
    }

    func foreground() async {
        await tick()
        if ready { synchronize(allowStart: true) }
    }

    private func synchronize(ask: Bool = false, allowStart: Bool = false) {
        effects.update(state.timer, unit: state.timer?.unit ?? state.unit, pro: hasPro, ask: ask, allowStart: allowStart) { [weak self] available, failed in
            self?.notificationsAvailable = available
            self?.notificationError = failed
        }
    }

    private func updateWidget() {
        guard !Launch.isTesting else { return }
        let data: Data?
        if let food = state.preferred.first {
            let key = state.primaryKey(for: food)
            let settings = state.settings(for: food, at: key)
            let permanent = state.entitlement.purchasedPro || Launch.isFree
            let snapshot = WidgetData.Snapshot(fryerID: key.fryerID, fryerName: state.fryer.name,
                                              foodID: food.id, customName: food.customName,
                                              celsius: settings.celsius, duration: settings.minutes,
                                              unit: state.unit, validUntil: permanent ? nil : state.entitlement.trialEnd,
                                              pro: hasPro)
            data = try? JSONEncoder().encode(snapshot)
        } else {
            data = nil
        }
        guard currentWidget != data || (data == nil && WidgetData.read() != nil) else { return }
        currentWidget = data
        UserDefaults(suiteName: WidgetData.group)?.set(data, forKey: WidgetData.storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetData.kind)
    }

    func purchaseChanged(_ bought: Bool, _ claimed: Date?) async {
        while saving { try? await Task.sleep(for: .milliseconds(50)); if Task.isCancelled { return } }
        _ = await commit {
            $0.entitlement.purchasedPro = bought
            if let claimed {
                $0.entitlement.trialClaimedAt = min(claimed, $0.entitlement.trialClaimedAt ?? claimed)
            }
        }
    }

    func start(_ food: Food, key: FoodKey, settings: Settings, portion: String) async -> Bool {
        guard settings.valid else { return false }
        let clock = ClockReading.now
        var timer = CookTimer(key: key, food: food, fryerName: state.fryers.first { $0.id == key.fryerID }?.name,
                              portion: portion, settings: settings, now: clock)
        timer.unit = state.unit
        if Launch.isTesting {
            if Launch.arguments.contains("-done") { timer.spent = timer.total; timer.runningSince = nil }
            if Launch.arguments.contains("-shake") { timer.spent = timer.plannedReminder ?? 0 }
        }
        now = clock
        return await commit { $0.timer = timer; $0.remember(key) }
    }

    func adjustTimer(_ edit: (inout CookTimer, ClockReading) -> Void) async {
        let clock = ClockReading.now
        _ = await commit {
            guard var timer = $0.timer else { return }
            edit(&timer, clock)
            $0.timer = timer
        }
        now = clock
    }

    struct Completion {
        let timer: CookTimer
        let settings: Settings
        let portion: String
        let milestone: Bool
    }

    func finish(celsius: Int, portion: String, note: String, save: Bool) async -> Completion? {
        let clock = ClockReading.now
        guard let timer = state.timer, timer.remaining(at: clock) == 0, !save || hasPro else { return nil }
        let settings = timer.actual(celsius: celsius)
        guard settings.valid else { return nil }
        var milestone = false
        let written = await commit {
            milestone = $0.finish(timer, settings: settings, portion: portion, note: note, save: save, at: clock.date)
        }
        guard written else { return nil }
        return Completion(timer: timer, settings: settings, portion: portion.isEmpty ? timer.portion : portion, milestone: milestone)
    }

    private func seed(_ state: inout AppState, clock: ClockReading) {
        if Launch.arguments.contains("-celsius") { state.unit = .celsius }
        if Launch.arguments.contains("-expired") { state.entitlement.firstOpen = clock.date.addingTimeInterval(-31 * 86_400) }
        if Launch.arguments.contains("-purchased") { state.entitlement.purchasedPro = true }
        guard Launch.arguments.contains("-reset") else { return }
        let seededTwo = Launch.arguments.contains("-seed-two")
        if Launch.arguments.contains("-seed") || seededTwo {
            state.fryers.append(Fryer(id: UUID(), name: L.t("test.fryer")))
            let foods = seededTwo ? [Foods.starter[4], Foods.starter[9]] : [Foods.starter[0], Foods.starter[4], Foods.starter[9]]
            for food in foods {
                var settings = food.defaults
                settings.celsius -= 10
                let key = state.key(for: food)
                state.calibrations.append(Calibration(key: key, settings: settings, portion: "", note: ""))
            }
        }
        if Launch.arguments.contains("-review-days") {
            for day in [1, 2] { state.review.record(at: Calendar.current.date(byAdding: .day, value: -day, to: clock.date) ?? clock.date) }
        }
    }
}
