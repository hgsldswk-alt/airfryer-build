import SwiftUI

@MainActor
struct PaywallView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var purchases: Purchases
    let onClose: () -> Void

    private var bought: Bool { model.state.entitlement.purchasedPro }
    private var testPrice: String? { Launch.isTesting ? L.t("test.price") : nil }
    private var price: String? { purchases.pro?.displayPrice ?? testPrice }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Spacer()
                    Action(L.t("action.close"), id: "pay.close", kind: .quiet,
                           symbol: "xmark", run: onClose)
                }
                PageHeader(title: L.t("pay.title"), detail: L.t("pay.subtitle"))
                Panel(tinted: true) {
                    VStack(alignment: .leading, spacing: 7) {
                        Eyebrow(L.t(statusKey))
                        Hint(L.t("pay.trialDetails"))
                        Hint(L.t("pay.after"))
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 11) {
                        feature("slider.horizontal.3", "pay.feature.settings")
                        feature("square.stack", "pay.feature.fryers")
                        feature("square.and.arrow.down", "pay.feature.import")
                        feature("rectangle.on.rectangle", "pay.feature.widgets")
                    }
                }
                if let message = purchases.message { Hint(message).accessibilityIdentifier("pay.status") }
                if !bought {
                    Action(price.map { L.f("pay.buyPrice", $0) } ?? L.t("pay.buy"), id: "pay.buy", kind: .primary) {
                        Task { await purchases.buy(purchases.pro, apply: model.purchaseChanged) }
                    }
                    .disabled(purchases.busy || (price == nil && purchases.pro == nil))
                    if model.hasPro && model.state.entitlement.trialClaimedAt == nil {
                        Action(L.t("pay.claim"), id: "pay.trial") {
                            Task { await purchases.buy(purchases.trial, apply: model.purchaseChanged) }
                        }
                        .disabled(purchases.busy || (!Launch.isTesting && (purchases.trial == nil || price == nil)))
                    }
                }
                Action(L.t("pay.restore"), id: "pay.restore", kind: .quiet) {
                    Task { await purchases.restore(apply: model.purchaseChanged) }
                }
                .disabled(purchases.busy)
                if !Launch.isTesting && price == nil {
                    Action(L.t("action.retry"), id: "pay.reload", kind: .quiet) { Task { await purchases.products() } }
                }
            }
            .padding(18)
        }
        .background(Theme.paper.ignoresSafeArea())
        .task { await purchases.products() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.paywall")
    }

    private var statusKey: String {
        if bought { return "pay.unlocked" }
        return model.hasPro ? "pay.trialActive" : "pay.expired"
    }

    private func feature(_ symbol: String, _ key: String) -> some View {
        Label {
            Text(L.t(key)).font(.callout.weight(.semibold))
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
        }
    }
}

@MainActor
struct WidgetsView: View {
    @EnvironmentObject private var model: AppModel
    let onBack: () -> Void
    let onPro: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Action(L.t("fryers.title"), id: "widgets.back", kind: .quiet, symbol: "chevron.left", run: onBack)
                PageHeader(title: L.t("widgets.title"), detail: Launch.isFree ? nil : L.t("widgets.included"))
                Text(L.t("widgets.home")).font(.headline)
                Panel(tinted: true) {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(L.t("widgets.pinned"))
                        if let food = model.state.preferred.first {
                            Text(food.name).font(.title3.weight(.bold))
                            Hint(model.state.fryer.title)
                            RecipeNumbers(settings: model.state.settings(for: food, at: model.state.primaryKey(for: food)),
                                          unit: model.state.unit)
                        } else {
                            Hint(L.t("widgets.noFood"))
                        }
                    }
                }
                Hint(L.t("widgets.homeHelp"))
                Text(L.t("widgets.lock")).font(.headline)
                Panel {
                    HStack {
                        Image(systemName: "timer").foregroundStyle(Theme.accent).accessibilityHidden(true)
                        Text(L.t("widgets.live")).font(.title3.weight(.semibold))
                    }
                }
                Text(L.t("widgets.island")).font(.headline)
                Hint(L.t("widgets.liveHelp"))
                if !model.hasPro {
                    Action(L.t("pay.title"), id: "widgets.pro", kind: .primary, run: onPro)
                }
            }
            .padding(18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.widgets")
    }
}
