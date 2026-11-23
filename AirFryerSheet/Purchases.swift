import StoreKit
import SwiftUI

@MainActor
final class Purchases: ObservableObject {
    @Published private(set) var pro: Product?
    @Published private(set) var trial: Product?
    @Published private(set) var busy = false
    @Published var message: String?
    private var listener: Task<Void, Never>?

    func products() async {
        guard !Launch.isTesting else { return }
        do {
            let items = try await Product.products(for: [Launch.proID, Launch.trialID])
            pro = items.first { $0.id == Launch.proID }
            trial = items.first { $0.id == Launch.trialID }
            if pro == nil { message = L.t("pay.unavailable") }
        } catch {
            self.message = L.t("pay.unavailable")
        }
    }

    func watch(_ apply: @escaping (Bool, Date?) async -> Void) {
        guard !Launch.isTesting, listener == nil else { return }
        listener = Task {
            for await update in StoreKit.Transaction.updates {
                guard case let .verified(transaction) = update,
                      [Launch.proID, Launch.trialID].contains(transaction.productID) else { continue }
                await refresh(apply)
                await transaction.finish()
            }
        }
    }

    func refresh(_ apply: (Bool, Date?) async -> Void) async {
        guard !Launch.isTesting else { return }
        var bought = false
        var date: Date?
        for await item in StoreKit.Transaction.currentEntitlements {
            guard case let .verified(transaction) = item, transaction.revocationDate == nil else { continue }
            if transaction.productID == Launch.proID { bought = true }
            if transaction.productID == Launch.trialID { date = transaction.originalPurchaseDate }
        }
        await apply(bought, date)
    }

    func buy(_ product: Product?, apply: (Bool, Date?) async -> Void) async {
        guard !busy else { return }
        guard let product else { message = L.t("pay.unavailable"); return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await refresh(apply)
                await transaction.finish()
                message = L.t(product.id == Launch.proID ? "pay.unlocked" : "pay.claimed")
            case .success(.unverified(_, _)):
                message = L.t("pay.verify")
            case .pending:
                message = L.t("pay.pending")
            case .userCancelled:
                break
            @unknown default:
                message = L.t("pay.unavailable")
            }
        } catch {
            self.message = L.t("pay.failed")
        }
    }

    func restore(apply: (Bool, Date?) async -> Void) async {
        guard !busy else { return }
        if Launch.isTesting { message = L.t("pay.restore.done"); return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh(apply)
            message = L.t("pay.restore.done")
        } catch {
            self.message = L.t("pay.failed")
        }
    }
}
