import SwiftUI

@MainActor
struct TimerView: View {
    @EnvironmentObject private var model: AppModel
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 58
    let timer: CookTimer
    let onBack: () -> Void
    let onStop: () -> Void

    private var remaining: TimeInterval { timer.remaining(at: model.now) }
    private var paused: Bool { timer.runningSince == nil }
    private var elapsed: TimeInterval { timer.elapsed(at: model.now) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Action(L.t("nav.chart"), id: "timer.back", kind: .quiet, symbol: "chevron.left", run: onBack)
                    Spacer()
                    Hint(timer.fryerName ?? L.t("fryer.default"))
                }
                PageHeader(title: timer.food.name, detail: L.f("timer.summary",
                           (timer.unit ?? model.state.unit).label(timer.original.celsius), Int(ceil(timer.total / 60))))
                ring
                reminder
                Pair {
                    Action(L.t(paused ? "timer.resume" : "timer.pause"), id: paused ? "timer.resume" : "timer.pause") {
                        Task {
                            await model.adjustTimer { active, clock in
                                if paused { active.resume(at: clock) } else { active.pause(at: clock) }
                            }
                        }
                    }
                    Action(L.f("timer.add", 1), id: "timer.add1") {
                        Task { await model.adjustTimer { $0.add(minutes: 1, at: $1) } }
                    }
                    .disabled(timer.total >= Double(Settings.durations.upperBound * 60))
                }
                HStack {
                    if !paused {
                        Hint(L.f("timer.ends", model.now.date.addingTimeInterval(remaining).formatted(date: .omitted, time: .shortened)))
                    }
                    Spacer()
                    Action(L.t("timer.stop"), id: "timer.stop", kind: .quiet, run: onStop)
                }
                Hint(L.t("timer.fallback"))
                    .accessibilityIdentifier(!model.notificationsAvailable || model.notificationError
                                             ? "timer.notificationFallback" : "timer.soundHelp")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.timer")
    }

    private var ring: some View {
        let seconds = max(0, Int(ceil(remaining)))
        let value = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        return ZStack {
            Circle().fill(Theme.surface)
            Circle().strokeBorder(Theme.line, lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(remaining / max(1, timer.total)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3.5)
            VStack(spacing: 4) {
                Text(value).font(.system(size: clockSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityIdentifier("timer.remaining")
                Hint(L.t(paused ? "timer.paused" : "timer.remaining"))
            }
            .padding(18)
        }
        .frame(width: 225, height: 225)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var reminder: some View {
        if timer.reminderIsDue(at: model.now) {
            Panel(tinted: true) {
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(L.f("timer.elapsed", Int(elapsed / 60)))
                    Text(timer.original.reminder.prompt).font(.headline)
                    Hint(L.t("timer.keepsRunning"))
                    Action(timer.original.reminder.confirmation, id: "timer.confirm", kind: .primary) {
                        Task { await model.adjustTimer { $0.confirmReminder(at: $1) } }
                    }
                }
            }
        } else if timer.original.reminder != .none {
            Panel {
                Hint(timer.confirmedAt == nil ? timer.original.reminderLabel : L.t("timer.confirmed"))
            }
        }
    }
}

@MainActor
struct DoneView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft: ResultDraft
    @State private var editDetails = false
    let timer: CookTimer
    let onBack: () -> Void
    let onPro: () -> Void
    let onCompletion: (AppModel.Completion, Bool) -> Void
    let onShare: (AppModel.Completion) -> Void

    init(timer: CookTimer, priorNote: String, onBack: @escaping () -> Void, onPro: @escaping () -> Void,
         onCompletion: @escaping (AppModel.Completion, Bool) -> Void, onShare: @escaping (AppModel.Completion) -> Void) {
        self.timer = timer
        self.onBack = onBack
        self.onPro = onPro
        self.onCompletion = onCompletion
        self.onShare = onShare
        _draft = State(initialValue: timer.resultDraft ?? ResultDraft(celsius: timer.original.celsius, note: priorNote))
    }

    private var unit: TemperatureUnit { timer.unit ?? model.state.unit }
    private var actual: Settings { timer.actual(celsius: draft.celsius) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Action(L.t("nav.chart"), id: "done.back", kind: .quiet, symbol: "chevron.left", run: onBack)
                    Spacer()
                    Hint(timer.fryerName ?? L.t("fryer.default"))
                }
                PageHeader(title: L.t("done.title"), detail: L.f("format.join", timer.food.name, timer.portion))
                Panel(tinted: true) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(L.t("done.check")).font(.headline)
                            Spacer()
                            Text(L.f("format.minutes", actual.minutes)).font(.headline).monospacedDigit()
                        }
                        if actual.minutes > timer.original.minutes {
                            Hint(L.f("done.extra", actual.minutes - timer.original.minutes))
                        }
                        if timer.food.group != .friend && timer.food.group != .custom { Hint(L.t(timer.food.safety)) }
                    }
                }
                Action(L.f("timer.add", 2), id: "done.add2") {
                    Task {
                        await model.adjustTimer { active, clock in
                            active.resultDraft = draft
                            active.add(minutes: 2, at: clock)
                        }
                    }
                }
                .disabled(timer.total >= Double(Settings.durations.upperBound * 60))
                comparison
                Action(L.t("done.save"), id: "done.save", kind: .primary) { finish(save: true) }
                Pair {
                    Action(L.t("share.title"), id: "done.share") {
                        onShare(AppModel.Completion(timer: timer, settings: actual,
                                                    portion: draft.portion.isEmpty ? timer.portion : draft.portion,
                                                    milestone: false))
                    }
                    Action(L.t("action.done"), id: "done.confirm") { finish(save: false) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.done")
    }

    private var comparison: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("done.next")).font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Hint(L.t("done.used"))
                        Spacer()
                        temperature
                    }
                    VStack(alignment: .leading) { Hint(L.t("done.used")); temperature }
                }
                Divider()
                HStack(alignment: .top) {
                    Hint(L.t("done.previous"))
                    Spacer()
                    RecipeNumbers(settings: timer.original, unit: unit)
                }
                Hint(actual.reminderLabel)
                Action(L.t("done.details"), id: "done.details", kind: .quiet) { editDetails.toggle() }
                if editDetails {
                    TextField(L.t("field.portion"), text: $draft.portion)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("done.portion")
                    TextField(L.t("field.note"), text: $draft.note)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("done.note")
                }
            }
        }
    }

    private var temperature: some View {
        HStack(spacing: 6) {
            Action("−", id: "done.temperature.down", kind: .chip) {
                draft.celsius = max(Settings.temperatures.lowerBound, draft.celsius - 10)
            }
            .accessibilityLabel(L.t("done.lower"))
            Text(unit.label(draft.celsius)).font(.title2.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier("done.temperature.value")
            Action("+", id: "done.temperature.up", kind: .chip) {
                draft.celsius = min(Settings.temperatures.upperBound, draft.celsius + 10)
            }
            .accessibilityLabel(L.t("done.raise"))
        }
    }

    private func finish(save: Bool) {
        if save && !model.hasPro { onPro(); return }
        Task {
            if let completed = await model.finish(celsius: draft.celsius, portion: draft.portion,
                                                  note: draft.note, save: save) {
                onCompletion(completed, !save)
            }
        }
    }
}

@MainActor
struct SavedView: View {
    @EnvironmentObject private var model: AppModel
    let completion: AppModel.Completion
    let onDone: () -> Void
    let onShare: () -> Void
    let onMilestone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Action(L.t("nav.chart"), id: "saved.back", kind: .quiet, symbol: "chevron.left", run: onDone)
                PageHeader(title: L.t("done.saved"), detail: completion.timer.fryerName ?? L.t("fryer.default"))
                Panel(tinted: true) {
                    HStack {
                        Text(completion.timer.food.name).font(.headline)
                        Spacer()
                        RecipeNumbers(settings: completion.settings, unit: model.state.unit)
                    }
                }
                if completion.milestone {
                    Action(L.t("share.milestone"), id: "saved.milestone", kind: .primary, run: onMilestone)
                }
                Action(L.t("share.title"), id: "saved.share", kind: completion.milestone ? .secondary : .primary, run: onShare)
                Action(L.t("action.done"), id: "saved.done", run: onDone)
            }
            .padding(18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.saved")
    }
}
