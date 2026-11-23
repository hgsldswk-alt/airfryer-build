import SwiftUI

@MainActor
struct FryersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editor: FryerEditor?
    @State private var archive: Fryer?
    let onBack: () -> Void
    let onFood: (FoodKey) -> Void
    let onShare: () -> Void
    let onImport: () -> Void
    let onWidgets: () -> Void
    let onHistory: () -> Void
    let onPro: () -> Void
    let onRestore: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Action(L.t("nav.chart"), id: "fryers.back", kind: .quiet, symbol: "chevron.left", run: onBack)
                HStack(alignment: .center) {
                    PageHeader(title: L.t("fryers.title"))
                    Action(L.t("fryers.add"), id: "fryers.add", kind: .chip) { gated { editor = .add } }
                }
                Panel(inset: 0) {
                    VStack(spacing: 0) {
                        ForEach(model.state.fryers.filter { !$0.archived }) { fryer in
                            fryerRow(fryer)
                        }
                    }
                }
                HStack {
                    Text(L.t("fryers.saved")).font(.headline)
                    Spacer()
                    Action(L.t("fryers.food"), id: "fryers.food", kind: .quiet) { gated { editor = .food } }
                }
                savedRows
                Pair {
                    Action(L.t("share.title"), id: "fryers.share", run: onShare)
                    Action(L.t("import.paste"), id: "fryers.import", run: onImport)
                }
                Pair {
                    Action(L.t("widgets.title"), id: "fryers.widgets", run: onWidgets)
                    Action(L.t("history.title"), id: "fryers.history", run: onHistory)
                }
                if !Launch.isFree {
                    Pair {
                        Action(L.t("pay.title"), id: "fryers.pro", kind: .quiet, run: onPro)
                        Action(L.t("pay.restore"), id: "fryers.restore", kind: .quiet, run: onRestore)
                    }
                }
                archived
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.fryers")
        .sheet(item: $editor) { item in
            FryerEditorView(editor: item) { editor = nil }.sheetPalette()
        }
        .alert(L.t("fryers.archive"), isPresented: Binding(get: { archive != nil }, set: { if !$0 { archive = nil } }),
               presenting: archive) { fryer in
            Button(L.t("action.cancel"), role: .cancel) {}
            Button(L.t("fryers.archive"), role: .destructive) { setArchived(fryer, true) }
        } message: { _ in
            Text(L.t("fryers.archive.body"))
        }
    }

    private func fryerRow(_ fryer: Fryer) -> some View {
        let active = fryer.id == model.state.activeFryerID
        let count = model.state.calibrations.filter { $0.key.fryerID == fryer.id }.count
        return HStack(spacing: 2) {
            Button {
                Task {
                    if await model.commit({ $0.activeFryerID = fryer.id }) { onBack() }
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fryer.title).font(.callout.weight(.semibold))
                        Hint(L.f("fryers.count", count))
                    }
                    Spacer()
                    if active { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                }
                .frame(minHeight: 51)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(active ? "fryer.current" : "fryer.choose." + fryer.id.uuidString)
            .accessibilityAddTraits(active ? .isSelected : [])
            Menu {
                Button(L.t("fryers.rename")) { gated { editor = .rename(fryer) } }
                    .accessibilityIdentifier("fryer.rename")
                if model.state.fryers.filter({ !$0.archived }).count > 1 {
                    Button(L.t("fryers.archive"), role: .destructive) { gated { archive = fryer } }
                        .accessibilityIdentifier("fryer.archive")
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L.t("fryers.manage"))
            .accessibilityIdentifier("fryer.manage." + fryer.id.uuidString)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .background(active ? Theme.tint : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var savedRows: some View {
        let state = model.state
        let entries = state.calibrations.reversed().filter { $0.key.fryerID == state.activeFryerID }
        let added = state.custom.filter { $0.fryerID == state.activeFryerID && $0.food.group == .custom }
        return Panel {
            VStack(alignment: .leading, spacing: 3) {
                if entries.isEmpty, added.isEmpty { Hint(L.t("fryers.noSaved")) }
                ForEach(entries, id: \.key) { entry in
                    if let food = state.food(entry.key.foodID, in: entry.key.fryerID) {
                        savedRow(food: food, key: entry.key, settings: entry.settings, portion: entry.portion)
                    }
                }
                ForEach(added) { entry in
                    if !entries.contains(where: { $0.key.foodID == entry.food.id }) {
                        savedRow(food: entry.food, key: state.key(for: entry.food),
                                 settings: entry.food.defaults, portion: entry.food.portion)
                    }
                }
            }
        }
    }

    private func savedRow(food: Food, key: FoodKey, settings: Settings, portion: String) -> some View {
        Button {
            onFood(key)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(food.name).font(.callout.weight(.semibold))
                    Hint(portion.isEmpty ? food.portion : portion)
                    Hint(settings.reminderLabel)
                }
                Spacer()
                RecipeNumbers(settings: settings, unit: model.state.unit)
            }
            .padding(.vertical, 4)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("saved.food." + food.id)
    }

    @ViewBuilder private var archived: some View {
        let archived = model.state.fryers.filter(\.archived)
        if !archived.isEmpty {
            Text(L.t("fryers.archived")).font(.headline)
            Panel {
                ForEach(archived) { fryer in
                    HStack {
                        Text(fryer.title)
                        Spacer()
                        Action(L.t("fryers.unarchive"), id: "fryer.unarchive." + fryer.id.uuidString, kind: .quiet) {
                            gated { setArchived(fryer, false) }
                        }
                    }
                }
            }
        }
    }

    private func gated(_ action: () -> Void) {
        if model.hasPro { action() } else { onPro() }
    }

    private func setArchived(_ fryer: Fryer, _ value: Bool) {
        Task {
            _ = await model.commit { state in
                guard let index = state.fryers.firstIndex(where: { $0.id == fryer.id }) else { return }
                state.fryers[index].archived = value
                if value && state.activeFryerID == fryer.id, let next = state.fryers.first(where: { !$0.archived }) {
                    state.activeFryerID = next.id
                }
            }
        }
    }
}

enum FryerEditor: Identifiable {
    case add
    case rename(Fryer)
    case food

    var id: String {
        switch self {
        case .add: "add"
        case .rename: "rename"
        case .food: "food"
        }
    }

    var title: String {
        switch self {
        case .add: L.t("fryers.add")
        case .rename: L.t("fryers.rename")
        case .food: L.t("fryers.food")
        }
    }
}

@MainActor
struct FryerEditorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var name: String
    @State private var portion = ""
    @State private var stateLabel = ""
    @State private var settings = Settings(celsius: 180, minutes: 12)
    let editor: FryerEditor
    let onClose: () -> Void

    init(editor: FryerEditor, onClose: @escaping () -> Void) {
        self.editor = editor
        self.onClose = onClose
        if case .rename(let fryer) = editor { _name = State(initialValue: fryer.title) }
        else { _name = State(initialValue: "") }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L.t(editor.id == "food" ? "field.foodName" : "field.fryerName"), text: $name)
                    .accessibilityIdentifier("editor.name")
                if case .food = editor {
                    TextField(L.t("field.state"), text: $stateLabel).accessibilityIdentifier("editor.state")
                    TextField(L.t("field.portion"), text: $portion).accessibilityIdentifier("editor.portion")
                    ParameterFields(settings: $settings, unit: model.state.unit)
                }
            }
            .navigationTitle(editor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Action(L.t("action.cancel"), id: "editor.cancel", kind: .quiet, run: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Action(L.t("action.save"), id: "editor.save", kind: .quiet, run: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  model.saving || !model.hasPro || (editor.id == "food" && !settings.valid))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = model.message { Hint(message).padding(12).background(Theme.tint) }
            }
        }
    }

    private func cleaned(_ input: String) -> String {
        String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ShareCode.fieldLimit))
    }

    private func save() {
        let name = cleaned(name)
        let portion = cleaned(portion)
        let label = cleaned(stateLabel)
        Task {
            if await model.commit({ state in
                switch editor {
                case .add:
                    let fryer = Fryer(id: UUID(), name: name)
                    state.fryers.append(fryer)
                    state.activeFryerID = fryer.id
                case .rename(let fryer):
                    if let index = state.fryers.firstIndex(where: { $0.id == fryer.id }) {
                        state.fryers[index].name = name
                    }
                case .food:
                    let food = Food(id: UUID().uuidString, group: .custom, customName: name,
                                    customPortion: portion.isEmpty ? L.t("field.standard") : portion,
                                    customState: label.isEmpty ? nil : label, defaults: settings,
                                    minC: settings.celsius, maxC: settings.celsius,
                                    minMinutes: settings.minutes, maxMinutes: settings.minutes)
                    state.custom.append(CustomFood(fryerID: state.activeFryerID, food: food))
                }
            }) { onClose() }
        }
    }
}

@MainActor
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Action(L.t("fryers.title"), id: "history.back", kind: .quiet, symbol: "chevron.left", run: onBack)
                PageHeader(title: L.t("history.title"))
                if model.state.records.isEmpty { Hint(L.t("history.empty")) }
                ForEach(model.state.records.reversed()) { record in
                    Panel {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.state.food(record.key.foodID, in: record.key.fryerID)?.name ?? record.name)
                                    .font(.headline)
                                Hint(model.state.fryers.first { $0.id == record.key.fryerID }?.title ?? L.t("fryer.default"))
                                Hint(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            Spacer()
                            RecipeNumbers(settings: record.settings, unit: model.state.unit)
                        }
                    }
                }
            }
            .padding(18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.history")
    }
}
