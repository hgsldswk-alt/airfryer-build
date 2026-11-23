import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct ShareView: View {
    @EnvironmentObject private var model: AppModel
    @State private var excluded: Set<String> = []
    @State private var showChoice = false
    @State private var payload: SharePayload?
    @State private var status: String?
    @State private var sent = false
    @State private var qr: UIImage?
    let items: [ShareFood]
    let onBack: () -> Void
    let onSharePresentation: (Bool) -> Void

    private var selected: [ShareFood] { items.filter { !excluded.contains($0.id) } }
    private var storeID: String? { Bundle.main.infoDictionary?["APP_STORE_ID"] as? String }
    private var isPreview: Bool { ShareQR.downloadURL(storeID: storeID) == ShareQR.placeholder }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Action(L.t("action.back"), id: "share.back", kind: .quiet, symbol: "chevron.left", run: onBack)
                PageHeader(title: L.t("share.title"))
                Panel(inset: 0) {
                    ShareCardArt(items: selected, unit: model.state.unit, qr: qr, preview: isPreview)
                }
                HStack {
                    Hint(L.t("share.privacy"))
                    Spacer()
                    Action(L.t("share.caption"), id: "share.caption", kind: .quiet) {
                        sent = false
                        UIPasteboard.general.string = L.t("share.captionText")
                        status = L.t("share.copied")
                    }
                }
                if let status { Hint(status).accessibilityIdentifier(sent ? "share.requested" : "share.status") }
                Action(L.t("share.image"), id: "share.image", kind: .primary, run: render)
                    .disabled(qr == nil || selected.isEmpty)
                Action(L.t("share.code"), id: "share.code") {
                    withCode { code in
                        UIPasteboard.general.string = code
                        status = L.t("share.copied")
                    }
                }
                Pair {
                    Action(L.t("share.file"), id: "share.file", kind: .quiet, run: shareFile)
                    if items.count > 1 {
                        Action(L.t("share.choose"), id: "share.choose", kind: .quiet) { showChoice.toggle() }
                    }
                }
                if showChoice {
                    Panel {
                        ForEach(items) { item in
                            Action(item.name, id: "share.item." + (item.catalogID ?? item.name), kind: .quiet,
                                   symbol: excluded.contains(item.id) ? "circle" : "checkmark.circle.fill") {
                                if excluded.contains(item.id) { excluded.remove(item.id) }
                                else if selected.count > 1 { excluded.insert(item.id) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.share")
        .task {
            let url = ShareQR.downloadURL(storeID: storeID)
            qr = ShareQR.image(for: url)
        }
        .onDisappear { onSharePresentation(false) }
        .sheet(item: $payload, onDismiss: { onSharePresentation(false) }) { value in
            ActivitySheet(items: value.items)
        }
    }

    private func render() {
        let renderer = ImageRenderer(content:
            ShareCardArt(items: selected, unit: model.state.unit, qr: qr, preview: isPreview, export: true)
                .frame(width: 360, height: 450))
        renderer.scale = 3
        renderer.isOpaque = true
        if let image = renderer.uiImage { present([image, L.t("share.captionText")]) }
        else { sent = false; status = L.t("share.error") }
    }

    private func shareFile() {
        withCode { code in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AirFryerCards", isDirectory: true)
            let url = directory.appendingPathComponent("AirFryerCard-\(UUID().uuidString.prefix(8)).txt")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data(code.utf8).write(to: url, options: .atomic)
                present([url])
            } catch {
                sent = false
                self.status = L.t("share.error")
            }
        }
    }

    private func withCode(_ use: (String) -> Void) {
        do {
            sent = false
            use(try ShareCode(foods: selected).encode())
        } catch {
            self.status = L.t("share.error")
        }
    }

    private func present(_ items: [Any]) {
        if Launch.isTesting {
            sent = true
            status = L.t("share.requested")
        } else {
            onSharePresentation(true)
            payload = SharePayload(items: items)
        }
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

@MainActor
private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

@MainActor
struct ShareCardArt: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let items: [ShareFood]
    let unit: TemperatureUnit
    let qr: UIImage?
    let preview: Bool
    var export = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Eyebrow(L.t("app.title"))
            Text(L.f("share.count", items.count)).font(.largeTitle.weight(.heavy))
                .lineLimit(2).minimumScaleFactor(0.7)
            Hint(L.t("share.check"))
            ForEach(items) { item in
                Divider()
                HStack(alignment: .top, spacing: 5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.callout.weight(.bold)).lineLimit(2)
                        Text(L.f("format.join", item.state, item.portion))
                            .font(.caption).foregroundStyle(Theme.muted).lineLimit(export ? 1 : nil)
                        Text(item.settings.reminderLabel)
                            .font(.caption).foregroundStyle(Theme.muted).lineLimit(export ? 1 : nil)
                    }
                    Spacer(minLength: 2)
                    RecipeNumbers(settings: item.settings, unit: unit)
                }
            }
            if export { Spacer(minLength: 0) }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("share.tags")).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    Hint(L.t(preview ? "share.previewQR" : "share.download"))
                }
                Spacer(minLength: 2)
                if let qr {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 84, height: 84)
                        .accessibilityLabel(L.t(preview ? "share.previewQR" : "share.download"))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: export ? .infinity : nil, alignment: .topLeading)
        .foregroundStyle(Theme.ink)
        .background(Theme.surface)
        .environment(\.dynamicTypeSize, export ? .large : dynamicType)
    }
}

@MainActor
struct ImportView: View {
    @EnvironmentObject private var model: AppModel
    @State private var text: String
    @State private var card: ShareCode?
    @State private var destination: UUID?
    @State private var status: String?
    @State private var files = false
    let onBack: () -> Void
    let onPro: () -> Void

    init(initialCode: String, onBack: @escaping () -> Void, onPro: @escaping () -> Void) {
        _text = State(initialValue: initialCode)
        _card = State(initialValue: try? ShareCode.decode(initialCode))
        self.onBack = onBack
        self.onPro = onPro
    }

    private var fryerID: UUID { destination ?? model.state.activeFryerID }
    private var fryer: Fryer? { model.state.fryers.first { $0.id == fryerID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Action(L.t("fryers.title"), id: "import.back", kind: .quiet, symbol: "chevron.left", run: onBack)
                PageHeader(title: L.t("import.title"), detail: card.map { L.f("import.count", $0.foods.count) })
                if let status { Hint(status).accessibilityIdentifier("import.status") }
                if let card {
                    preview(card)
                } else {
                    input
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.import")
        .fileImporter(isPresented: $files, allowedContentTypes: [.plainText]) { result in
            if case .success(let url) = result { read(url) }
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 9) {
            Hint(L.t("import.instructions"))
            Panel {
                TextEditor(text: $text)
                    .font(.footnote.monospaced())
                    .frame(minHeight: 100)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(L.t("import.code"))
                    .accessibilityIdentifier("import.code")
            }
            Action(L.t("import.preview"), id: "import.preview", kind: .primary) { parse(text) }
            Pair {
                Action(L.t("import.paste"), id: "import.paste") {
                    if let code = UIPasteboard.general.string { parse(code) }
                    else { status = L.t("import.empty") }
                }
                Action(L.t("import.file"), id: "import.file") { files = true }
            }
        }
    }

    private func preview(_ card: ShareCode) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Panel(tinted: true) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(L.t("import.target"))
                        Text(fryer?.title ?? L.t("fryer.default")).font(.headline)
                    }
                    Spacer()
                    if model.state.fryers.filter({ !$0.archived }).count > 1 {
                        Menu {
                            ForEach(model.state.fryers.filter { !$0.archived }) { fryer in
                                Button(fryer.title) { destination = fryer.id }
                            }
                        } label: {
                            Text(L.t("import.change")).font(.footnote.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("import.fryer")
                    }
                }
            }
            ForEach(card.foods) { item in
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.f("format.join", item.name, item.portion)).font(.headline)
                        if let original = existing(item) { comparison("import.yours", original) }
                        comparison("import.theirs", item.settings)
                        Hint(item.settings.reminderLabel)
                    }
                }
            }
            Hint(L.t("import.try"))
            Action(L.t("import.commit"), id: "import.commit", kind: .primary) {
                if model.hasPro { accept(card) } else { onPro() }
            }
            Action(L.t("import.another"), id: "import.another") {
                self.card = nil
                text = ""
                status = nil
            }
        }
    }

    private func existing(_ item: ShareFood) -> Settings? {
        let foods = model.state.foods(in: fryerID)
        guard let match = foods.first(where: { food in
            food.group != .friend && (food.id == item.catalogID || food.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame)
        }) else { return nil }
        let portion = match.portion == item.portion ? "" : item.portion.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let key = FoodKey(fryerID: fryerID, foodID: match.id, portion: portion)
        return model.state.calibration(key)?.settings ?? match.defaults
    }

    private func comparison(_ key: String, _ settings: Settings) -> some View {
        HStack {
            Hint(L.t(key))
            Spacer()
            RecipeNumbers(settings: settings, unit: model.state.unit)
        }
    }

    private func parse(_ source: String) {
        text = String(source.prefix(ShareCode.byteLimit))
        do {
            card = try ShareCode.decode(source)
            status = nil
        } catch {
            self.status = L.t("import.invalid")
        }
    }

    private func accept(_ card: ShareCode) {
        Task {
            var added = false
            let saved = await model.commit { state in
                added = (try? state.addCard(card, to: fryerID)) ?? false
            }
            if saved {
                status = L.t(added ? "import.added" : "import.duplicate")
                if added { self.card = nil; text = "" }
            }
        }
    }

    private func read(_ url: URL) {
        Task {
            let source = await Task.detached { () -> String? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
                defer { try? handle.close() }
                let read = try? handle.read(upToCount: ShareCode.byteLimit + 1)
                guard let read, read.count <= ShareCode.byteLimit else { return nil }
                return String(data: read, encoding: .utf8)
            }.value
            if let source { parse(source) } else { status = L.t("import.invalid") }
        }
    }
}
