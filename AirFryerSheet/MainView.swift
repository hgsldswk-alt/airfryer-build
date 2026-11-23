import StoreKit
import SwiftUI
import UIKit

enum Page: Equatable {
    case home
    case food(FoodKey, fromFryers: Bool)
    case timer
    case fryers
    case share(fromTimer: Bool)
    case importCard
    case widgets
    case history
    case converter
}

struct StartRequest {
    let food: Food
    let key: FoodKey
    let settings: Settings
    let portion: String
}

@MainActor
struct MainView: View {
    @StateObject private var model = AppModel()
    @StateObject private var purchases = Purchases()
    @Environment(\.scenePhase) private var phase
    @Environment(\.requestReview) private var requestReview
    @State private var page: Page = .home
    @State private var paywall = false
    @State private var pending: StartRequest?
    @State private var replacing = false
    @State private var stopped = false
    @State private var completion: AppModel.Completion?
    @State private var shareItems: [ShareFood] = []
    @State private var notice: String?
    @State private var externalURL: URL?
    @State private var shareIsOpen = false
    @State private var importCode = ""
    @State private var searchFocused = false

    var body: some View {
        VStack(spacing: 0) {
            if let issue = model.message {
                HStack {
                    Hint(issue)
                    Spacer()
                    Action(L.t(model.ready ? "action.dismiss" : "action.retry"), id: "error.dismiss", kind: .quiet) {
                        model.message = nil
                        if !model.ready { Task { await model.load() } }
                    }
                }
                .padding(.horizontal, 18)
                .background(Theme.tint)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("app.error")
            }
            if let notice {
                HStack {
                    Hint(notice)
                    Spacer()
                    Action(L.t("action.dismiss"), id: "notice.dismiss", kind: .quiet) { self.notice = nil }
                }
                .padding(.horizontal, 18)
                .background(Theme.tint)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("app.notice")
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.paper.ignoresSafeArea())
        .sheetPalette()
        .environmentObject(model)
        .sheet(isPresented: $paywall) {
            PaywallView(model: model, purchases: purchases) { paywall = false }
                .sheetPalette()
        }
        .alert(L.t("timer.replace.title"), isPresented: $replacing) {
            Button(L.t("timer.keep"), role: .cancel) { pending = nil }
            Button(L.t("timer.replace"), role: .destructive) {
                if let request = pending { begin(request) }
                pending = nil
            }
        } message: {
            Text(L.t("timer.replace.body"))
        }
        .alert(L.t("timer.stop.title"), isPresented: $stopped) {
            Button(L.t("action.cancel"), role: .cancel) {}
            Button(L.t("timer.stop"), role: .destructive) {
                Task {
                    if await model.commit({ $0.timer = nil }) { goHome() }
                }
            }
        }
        .task {
            await model.load()
            if model.ready {
                if model.state.timer != nil { page = .timer }
                if Launch.isTesting && Launch.arguments.contains("-paywall") { paywall = true }
                if let externalURL { open(externalURL) }
                purchases.watch(model.purchaseChanged)
                await purchases.refresh(model.purchaseChanged)
            }
        }
        .task(id: phase) {
            guard phase == .active else { return }
            await model.foreground()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                await model.tick()
                await maybeReview()
            }
        }
        .onChange(of: phase) { _, active in
            if active == .active && model.ready { Task { await purchases.refresh(model.purchaseChanged) } }
        }
        .onOpenURL { url in
            if model.ready { open(url) } else { externalURL = url }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationDelegate.opened)) { notification in
            if let value = notification.object as? String, value == model.state.timer?.id.uuidString {
                paywall = false
                completion = nil
                page = .timer
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .home:
            HomeView(onFryers: { page = .fryers }, onTimer: { page = .timer },
                     onFood: { page = .food($0, fromFryers: false) },
                     onStart: requestStart, onPro: showPaywall, onConvert: { page = .converter },
                     onSearchFocus: { searchFocused = $0 })
        case let .food(key, fromFryers):
            if let food = model.state.food(key.foodID, in: key.fryerID) {
                FoodView(food: food, initialKey: key, onBack: { page = fromFryers ? .fryers : .home },
                         onStart: requestStart, onPro: showPaywall)
                    .id(key)
            } else {
                Action(L.t("nav.chart"), id: "nav.home", run: goHome)
            }
        case .timer:
            if let completion {
                SavedView(completion: completion, onDone: goHome) {
                    showShare(fryer: completion.timer.key.fryerID, fromTimer: true, snapshot: completion)
                } onMilestone: {
                    showShare(fryer: completion.timer.key.fryerID, fromTimer: true)
                }
            } else if let timer = model.state.timer {
                if timer.remaining(at: model.now) > 0 {
                    TimerView(timer: timer, onBack: goHome, onStop: { stopped = true })
                } else {
                    DoneView(timer: timer, priorNote: model.state.calibration(timer.key)?.note ?? "",
                             onBack: goHome, onPro: showPaywall,
                             onCompletion: { value, leaving in
                                 completion = value
                                 if leaving { goHome() }
                             }, onShare: { value in
                                 showShare(fryer: timer.key.fryerID, fromTimer: true, snapshot: value)
                             })
                }
            } else {
                Action(L.t("nav.chart"), id: "nav.home", run: goHome)
            }
        case .fryers:
            FryersView(onBack: goHome, onFood: { page = .food($0, fromFryers: true) },
                       onShare: { showShare(fryer: model.state.activeFryerID, fromTimer: false) },
                       onImport: prepareImport, onWidgets: { page = .widgets }, onHistory: { page = .history },
                       onPro: showPaywall, onRestore: restore)
        case let .share(fromTimer):
            ShareView(items: shareItems, onBack: { page = fromTimer ? .timer : .fryers },
                      onSharePresentation: { shareIsOpen = $0 })
        case .importCard:
            ImportView(initialCode: importCode, onBack: { page = .fryers }, onPro: showPaywall)
        case .widgets:
            WidgetsView(onBack: { page = .fryers }, onPro: showPaywall)
        case .history:
            HistoryView(onBack: { page = .fryers })
        case .converter:
            ConverterView(onBack: goHome)
        }
    }

    private func prepareImport() {
        importCode = Launch.isTesting ? (ProcessInfo.processInfo.environment["AF_IMPORT_CODE"] ?? "")
            : (UIPasteboard.general.string ?? "")
        importCode = String(importCode.prefix(ShareCode.byteLimit + 1))
        page = .importCard
    }

    private func showPaywall() {
        purchases.message = nil
        paywall = true
    }

    private func restore() {
        Task {
            await purchases.restore(apply: model.purchaseChanged)
            notice = purchases.message
        }
    }

    private func goHome() {
        completion = nil
        page = .home
    }

    private func requestStart(_ request: StartRequest) {
        guard model.ready, !model.saving else { return }
        if model.state.timer != nil {
            pending = request
            replacing = true
        } else {
            begin(request)
        }
    }

    private func begin(_ request: StartRequest) {
        Task {
            if await model.start(request.food, key: request.key, settings: request.settings, portion: request.portion) {
                completion = nil
                page = .timer
            }
        }
    }

    private func showShare(fryer: UUID, fromTimer: Bool, snapshot: AppModel.Completion? = nil) {
        let state = model.state
        var items: [ShareFood] = []
        if let snapshot {
            let item = snapshot.timer.food
            let id = Foods.starter.contains { $0.id == item.id } ? item.id : nil
            items = [ShareFood(catalogID: id, name: item.name, state: item.state,
                               portion: snapshot.portion.isEmpty ? item.portion : snapshot.portion,
                               settings: snapshot.settings)]
        } else {
            var seen = Set<String>()
            for saved in state.calibrations.reversed() where saved.key.fryerID == fryer && seen.insert(saved.key.foodID).inserted {
                guard let item = state.food(saved.key.foodID, in: fryer) else { continue }
                let id = Foods.starter.contains { $0.id == item.id } ? item.id : nil
                items.append(ShareFood(catalogID: id, name: item.name, state: item.state,
                                       portion: saved.portion.isEmpty ? item.portion : saved.portion, settings: saved.settings))
            }
            if items.isEmpty {
                for item in state.preferred.prefix(3) {
                    let id = Foods.starter.contains { $0.id == item.id } ? item.id : nil
                    items.append(ShareFood(catalogID: id, name: item.name, state: item.state, portion: item.portion,
                                           settings: state.settings(for: item, at: state.primaryKey(for: item))))
                }
            }
        }
        guard !items.isEmpty else { notice = L.t("share.empty"); return }
        shareItems = Array(items.prefix(ShareCode.itemLimit))
        page = .share(fromTimer: fromTimer)
    }

    private func open(_ url: URL) {
        guard url.scheme == "airfryersheet" else { return }
        if url.host == "timer", model.state.timer != nil {
            paywall = false
            completion = nil
            page = .timer
        }
        if url.host == "food", model.hasPro {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2, let id = UUID(uuidString: parts[0]),
                  model.state.fryers.contains(where: { $0.id == id && !$0.archived }),
                  let food = model.state.food(parts[1], in: id) else { return }
            page = .food(model.state.primaryKey(for: food, fryer: id), fromFryers: false)
        }
    }

    private var canShowReview: Bool {
        phase == .active && page == .home && !searchFocused && !paywall && !shareIsOpen && !replacing && !stopped &&
            model.message == nil && notice == nil && model.state.timer == nil && !model.notificationError
    }

    private func maybeReview() async {
        let version = model.version
        guard canShowReview, model.state.review.isEligible, !model.state.reviewedVersions.contains(version) else { return }
        guard await model.commit({ $0.reviewedVersions.insert(version) }) else { return }
        guard canShowReview else {
            _ = await model.commit { $0.reviewedVersions.remove(version) }
            return
        }
        if Launch.isTesting { notice = L.t("test.review") } else { requestReview() }
    }
}
