import ActivityKit
import SwiftUI
import UserNotifications
import WidgetKit

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let opened = Notification.Name("airfryer.notification.opened")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["session"] as? String
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.opened, object: id)
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
final class TimerEffects {
    private var task: Task<Void, Never>?

    func update(_ timer: CookTimer?, unit: TemperatureUnit, pro: Bool, ask: Bool,
                allowStart: Bool, onStatus: @escaping (Bool, Bool) -> Void) {
        guard !Launch.isTesting else {
            onStatus(!Launch.arguments.contains("-deny-notifications"), false)
            return
        }
        let previous = task
        task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await activities(timer, unit: unit, pro: pro, allowStart: allowStart)
            if Task.isCancelled { return }
            await notifications(timer, ask: ask, onStatus: onStatus)
        }
        previous?.cancel()
    }

    private func notifications(_ timer: CookTimer?, ask: Bool, onStatus: (Bool, Bool) -> Void) async {
        let center = UNUserNotificationCenter.current()
        var permissions = await center.notificationSettings().authorizationStatus
        if permissions == .notDetermined && ask {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            permissions = await center.notificationSettings().authorizationStatus
        }
        guard !Task.isCancelled else { return }
        let allowed = permissions == .authorized || permissions == .provisional || permissions == .ephemeral
        let previous = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: previous.filter { $0.identifier.hasPrefix("cook.") }.map(\.identifier))
        guard allowed, let timer, timer.runningSince != nil else { onStatus(allowed, false); return }
        let now = ClockReading.now
        let remaining = timer.remaining(at: now)
        guard remaining > 0 else { onStatus(allowed, false); return }
        var alerts = [(kind: "end", interval: remaining, message: L.t("done.check"))]
        if timer.confirmedAt == nil, let minutes = timer.plannedReminder {
            let interval = minutes - timer.elapsed(at: now)
            if interval > 0, interval < remaining {
                alerts.append((kind: "action", interval: interval, message: timer.original.reminder.prompt))
            }
        }
        var failed = false
        for alert in alerts {
            guard !Task.isCancelled else { return }
            do {
                try await schedule(center, timer: timer, event: alert.kind,
                                   interval: alert.interval, message: alert.message)
            } catch {
                failed = true
            }
        }
        if !Task.isCancelled { onStatus(allowed, failed) }
    }

    private func schedule(_ center: UNUserNotificationCenter, timer: CookTimer, event: String,
                          interval: TimeInterval, message: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = timer.food.name
        content.body = message
        content.sound = .default
        content.threadIdentifier = timer.id.uuidString
        content.userInfo = ["session": timer.id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let identifier = "cook.\(timer.id.uuidString).\(timer.revision).\(event)"
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func activities(_ timer: CookTimer?, unit: TemperatureUnit, pro: Bool, allowStart: Bool) async {
        let clock = ClockReading.now
        let live = ActivityAuthorizationInfo().areActivitiesEnabled && pro && (timer?.remaining(at: clock) ?? 0) > 0
        let all = Activity<CookActivity>.activities
        for activity in all where !live || activity.attributes.sessionID != timer?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard !Task.isCancelled, live, let timer else { return }
        let remaining = timer.remaining(at: clock)
        let paused = timer.runningSince == nil
        let deadline = clock.date.addingTimeInterval(remaining)
        let state = CookActivity.ContentState(started: clock.date.addingTimeInterval(-timer.elapsed(at: clock)),
                                             deadline: deadline, pausedSeconds: paused ? Int(ceil(remaining)) : nil,
                                             temperature: unit.label(timer.original.celsius))
        let content = ActivityContent(state: state, staleDate: paused ? nil : deadline)
        if let activity = all.first(where: { $0.attributes.sessionID == timer.id }) {
            await activity.update(content)
        } else if allowStart {
            let data = CookActivity(sessionID: timer.id, food: timer.food.name,
                                    fryer: timer.fryerName ?? L.t("fryer.default"))
            _ = try? Activity.request(attributes: data, content: content, pushType: nil)
        }
    }
}
