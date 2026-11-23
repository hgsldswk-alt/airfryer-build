import SwiftUI

@MainActor
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searching: Bool
    @State private var search = ""
    @State private var group: FoodGroup?
    let onFryers: () -> Void
    let onTimer: () -> Void
    let onFood: (FoodKey) -> Void
    let onStart: (StartRequest) -> Void
    let onPro: () -> Void
    let onConvert: () -> Void
    let onSearchFocus: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Action(model.state.fryer.title, id: "home.fryers", kind: .quiet,
                           symbol: "chevron.down", run: onFryers)
                    Spacer(minLength: 4)
                    HStack(spacing: 3) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                            Action(unit.symbol, id: "units." + unit.rawValue,
                                   kind: unit == model.state.unit ? .chip : .quiet) {
                                Task { _ = await model.commit { $0.unit = unit } }
                            }
                            .accessibilityAddTraits(unit == model.state.unit ? .isSelected : [])
                        }
                    }
                }
                PageHeader(title: L.t("app.title"))
                if model.state.timer != nil {
                    Action(L.t("home.timer"), id: "home.timer", kind: .chip,
                           symbol: "timer", run: onTimer)
                }
                searchField
                filters
                if showPreferred, !model.state.preferred.isEmpty {
                    Text(L.t("home.pinned")).font(.headline).accessibilityAddTraits(.isHeader)
                    shelf(model.state.preferred, favored: true)
                }
                if !Launch.isFree {
                    Action(entitlementLabel, id: "home.pro", kind: .quiet, run: onPro)
                }
                HStack {
                    Text(L.t("home.chart")).font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Action(L.t("convert.short"), id: "home.convert", kind: .quiet, run: onConvert)
                }
                if results.isEmpty {
                    Panel { Hint(L.t("home.empty")) }
                } else {
                    shelf(results, favored: false)
                }
                Hint(L.t("home.guide"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: searching) { _, focused in onSearchFocus(focused) }
        .onDisappear { onSearchFocus(false) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.home")
    }

    private var showPreferred: Bool { search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && group == nil }

    private var results: [Food] {
        let terms = search.split(whereSeparator: \.isWhitespace)
        let preferred = Set(model.state.preferred.map(\.id))
        let all = model.state.foods(in: model.state.activeFryerID)
        let highlighted = ["wings", "salmon"].compactMap { id in all.first { $0.id == id } }
        let ordered = highlighted + all.filter { $0.id != "wings" && $0.id != "salmon" }
        return ordered.filter { food in
            let match = terms.allSatisfy { food.searchText.localizedStandardContains(String($0)) }
            return (group == nil || food.group == group) && match && (!showPreferred || !preferred.contains(food.id))
        }
    }

    private var entitlementLabel: String {
        if model.state.entitlement.purchasedPro { return L.t("pay.unlocked") }
        if model.hasPro {
            let seconds = model.state.entitlement.trialEnd.timeIntervalSince(model.now.date)
            return L.f("pay.banner", max(1, Int(ceil(seconds / 86_400))))
        }
        return L.t("pay.title")
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField(L.t("home.search"), text: $search)
                .focused($searching)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("home.search")
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("action.clear"))
                .accessibilityIdentifier("home.clear")
            }
        }
        .padding(.leading, 12)
        .frame(minHeight: 48)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.line).allowsHitTesting(false) }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                filter(nil, title: L.t("group.all"), id: "all")
                ForEach(FoodGroup.allCases.filter { value in
                    value != .custom && value != .friend || model.state.foods(in: model.state.activeFryerID).contains { $0.group == value }
                }, id: \.self) { value in
                    filter(value, title: value.title, id: value.rawValue)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func filter(_ value: FoodGroup?, title: String, id: String) -> some View {
        Action(title, id: "filter." + id, kind: group == value ? .chip : .quiet) { group = value }
            .accessibilityAddTraits(group == value ? .isSelected : [])
    }

    private func shelf(_ foods: [Food], favored: Bool) -> some View {
        Panel(tinted: favored, inset: 0) {
            VStack(spacing: 0) {
                ForEach(foods) { food in
                    if food.id != foods.first?.id { Divider().overlay(Theme.line) }
                    row(food)
                }
            }
        }
    }

    private func row(_ food: Food) -> some View {
        let key = model.state.primaryKey(for: food)
        let saved = model.state.calibration(key)
        let settings = model.state.settings(for: food, at: key)
        let portion = saved.flatMap { $0.portion.isEmpty ? nil : $0.portion } ?? food.portion
        return HStack(spacing: 7) {
            Button {
                searching = false
                onFood(key)
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name).font(.callout.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Hint(L.f("format.join", portion, L.t(saved == nil ? "home.guideTag" : "home.savedTag")))
                        Hint(food.state)
                    }
                    Spacer(minLength: 1)
                    RecipeNumbers(settings: settings, unit: model.state.unit)
                }
                .frame(minHeight: 59)
                .padding(.leading, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("food." + food.id)
            Action(L.t("action.start"), id: "start." + food.id, kind: .chip) {
                searching = false
                onStart(StartRequest(food: food, key: key, settings: settings, portion: portion))
            }
            .accessibilityLabel(L.f("home.startFood", food.name, settings.minutes))
            .disabled(!model.ready || model.saving)
        }
        .padding(.trailing, 8)
    }
}

@MainActor
struct FoodView: View {
    @EnvironmentObject private var model: AppModel
    @State private var key: FoodKey
    @State private var draft: Settings?
    @State private var editing = false
    @State private var restoring = false
    let food: Food
    let onBack: () -> Void
    let onStart: (StartRequest) -> Void
    let onPro: () -> Void

    init(food: Food, initialKey: FoodKey, onBack: @escaping () -> Void,
         onStart: @escaping (StartRequest) -> Void, onPro: @escaping () -> Void) {
        self.food = food
        _key = State(initialValue: initialKey)
        self.onBack = onBack
        self.onStart = onStart
        self.onPro = onPro
    }

    private var baseKey: FoodKey { FoodKey(fryerID: key.fryerID, foodID: key.foodID) }
    private var settings: Settings { draft ?? model.state.settings(for: food, at: key) }
    private var fryer: String { model.state.fryers.first { $0.id == key.fryerID }?.title ?? L.t("fryer.default") }
    private var saved: Calibration? { model.state.calibration(key) }
    private var portion: String { saved.flatMap { $0.portion.isEmpty ? nil : $0.portion } ?? food.portion }
    private var pinned: Bool { model.state.pinned.contains(baseKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Action(L.t("nav.chart"), id: "food.back", kind: .quiet, symbol: "chevron.left", run: onBack)
                    Spacer()
                    Action(L.t(pinned ? "food.pinned" : "food.pin"), id: "food.pin", kind: .quiet,
                           symbol: pinned ? "star.fill" : "star") {
                        Task {
                            _ = await model.commit { state in
                                if pinned { state.pinned.removeAll { $0 == baseKey } }
                                else { state.pinned.insert(baseKey, at: 0) }
                            }
                        }
                    }
                }
                PageHeader(title: food.name, detail: L.f("format.join", food.state, portion))
                HStack {
                    Text(L.t("food.settings")).font(.headline)
                    Spacer()
                    Hint(fryer)
                }
                variants
                Panel {
                    VStack(spacing: 8) {
                        metric(L.t("field.temperature"), model.state.unit.label(settings.celsius), id: "food.temperature.value")
                        Divider()
                        metric(L.t("field.minutes"), L.f("format.minutes", settings.minutes), id: "food.minutes.value")
                        Divider()
                        metric(L.t("field.reminder"), settings.reminderLabel, id: "food.reminder.value")
                    }
                }
                timeline
                if food.group != .custom && food.group != .friend { guide }
                if food.group == .friend { Hint(L.t("import.try")) }
                if let saved, !saved.note.isEmpty { Hint(saved.note) }
                Action(L.t("food.adjust"), id: "food.adjust") { editing = true }
                Action(L.f("food.start", settings.minutes), id: "food.start", kind: .primary) {
                    onStart(StartRequest(food: food, key: key, settings: settings, portion: portion))
                }
                if saved != nil {
                    Action(L.t("food.restore"), id: "food.restore", kind: .quiet) {
                        if model.hasPro { restoring = true } else { onPro() }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.food")
        .sheet(isPresented: $editing) {
            ParameterSheet(settings: settings, unit: model.state.unit) { value in
                draft = value
                editing = false
            } onCancel: { editing = false }
                .sheetPalette()
        }
        .alert(L.t("food.restore"), isPresented: $restoring) {
            Button(L.t("action.cancel"), role: .cancel) {}
            Button(L.t("action.restore"), role: .destructive) {
                Task {
                    if await model.commit({ $0.calibrations.removeAll { $0.key == key } }) {
                        key = baseKey
                        draft = nil
                    }
                }
            }
        } message: {
            Text(L.t("food.restore.body"))
        }
    }

    @ViewBuilder private var variants: some View {
        let options = model.state.calibrations.filter { $0.key.fryerID == key.fryerID && $0.key.foodID == key.foodID }
        if options.contains(where: { !$0.key.portion.isEmpty }) {
            Menu {
                Button(food.portion) { key = baseKey; draft = nil }
                ForEach(options.filter { !$0.key.portion.isEmpty }, id: \.key) { option in
                    Button(option.portion) { key = option.key; draft = nil }
                }
            } label: {
                Label(portion, systemImage: "chevron.down").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("food.portions")
        }
    }

    private func metric(_ name: String, _ value: String, id: String) -> some View {
        HStack(spacing: 8) {
            Hint(name)
            Spacer()
            Text(value).font(.title3.weight(.bold)).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 35)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private var timeline: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(L.t("food.timeline"))
                GeometryReader { proxy in
                    let fraction = settings.reminderMinute.map { CGFloat($0) / CGFloat(settings.minutes) } ?? 1
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(Theme.accent).frame(width: proxy.size.width * fraction)
                        if settings.reminderMinute != nil {
                            Circle().fill(Theme.accent).strokeBorderCompatible()
                                .frame(width: 13, height: 13)
                                .offset(x: max(0, proxy.size.width * fraction - 6))
                        }
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
                HStack {
                    Hint(L.t("action.start"))
                    Spacer()
                    if settings.reminder != .none { Hint(settings.reminderLabel) }
                    Spacer()
                    Hint(L.f("format.minutes", settings.minutes))
                }
            }
        }
    }

    private var guide: some View {
        Panel {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(L.t("food.guide")).font(.headline)
                    Spacer()
                    Text("\(model.state.unit.displayed(food.minC))–\(model.state.unit.label(food.maxC))")
                        .font(.callout.weight(.bold)).monospacedDigit()
                }
                Hint(L.f("food.range", food.minMinutes, food.maxMinutes))
                Hint(L.t(food.safety))
            }
        }
    }
}

private extension View {
    func strokeBorderCompatible() -> some View {
        overlay { Circle().strokeBorder(.white, lineWidth: 2) }
    }
}

@MainActor
struct ParameterSheet: View {
    @State var settings: Settings
    let unit: TemperatureUnit
    let onSave: (Settings) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form { ParameterFields(settings: $settings, unit: unit) }
                .navigationTitle(L.t("food.adjust"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Action(L.t("action.cancel"), id: "adjust.cancel", kind: .quiet, run: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Action(L.t("action.apply"), id: "adjust.apply", kind: .quiet) { onSave(settings) }
                    }
                }
        }
    }
}

@MainActor
struct ParameterFields: View {
    @Binding var settings: Settings
    let unit: TemperatureUnit

    var body: some View {
        Stepper(value: $settings.celsius, in: Settings.temperatures) {
            Text(L.f("format.join", L.t("field.temperature"), unit.label(settings.celsius)))
        }
        .accessibilityIdentifier("adjust.temperature")
        Stepper(value: $settings.minutes, in: Settings.durations) {
            Text(L.f("format.join", L.t("field.minutes"), L.f("format.minutes", settings.minutes)))
        }
        .onChange(of: settings.minutes) { _, _ in settings.normalizeReminder() }
        .accessibilityIdentifier("adjust.minutes")
        Picker(L.t("field.reminder"), selection: $settings.reminder) {
            ForEach(Reminder.allCases, id: \.self) { reminder in
                Text(reminder.title).tag(reminder)
            }
        }
        .onChange(of: settings.reminder) { _, _ in settings.normalizeReminder() }
        .accessibilityIdentifier("adjust.reminder")
        if settings.minutes > 1, settings.reminder != .none {
            Stepper(value: Binding(get: { settings.reminderMinute ?? 1 }, set: { settings.reminderMinute = $0 }),
                    in: 1...(settings.minutes - 1)) {
                Text(L.f("format.join", L.t("field.reminderMinute"),
                         L.f("format.minutes", settings.reminderMinute ?? 1)))
            }
            .accessibilityIdentifier("adjust.reminderMinute")
        }
    }
}
