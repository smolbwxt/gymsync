import Foundation
import StoreKit

// MARK: - StoreKitService (Monetization M1)
//
// StoreKit 2 plumbing for GymSync Pro: products, purchase, restore, and
// the entitlement sync. The write path honors the server's security
// shape — the device NEVER writes profiles.pro_until; it forwards Apple's
// signed transaction JWS to the verify-entitlement edge function, the
// column's only permitted writer (guard trigger 20260730000004).
//
// Products must exist in App Store Connect (paid-apps agreement, banking,
// tax, product IDs — owner-side setup) before loadProducts() returns
// anything; until then PaywallView keeps its honest roadmap fallback.
@MainActor
@Observable
final class StoreKitService {
    static let shared = StoreKitService()

    static let monthlyID = "gymsync.pro.monthly"
    static let yearlyID = "gymsync.pro.yearly"

    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    /// Set after a successful entitlement sync — PaywallView's "you're in".
    private(set) var proUntil: Date?

    private var updatesTask: Task<Void, Never>?

    private init() {}

    /// Idempotent. The Transaction.updates listener must run for the whole
    /// app session (Apple delivers renewals/refunds whenever they land).
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await update in Transaction.updates {
                await handle(update)
            }
        }
    }

    func loadProducts() async {
        let loaded = (try? await Product.products(
            for: [Self.monthlyID, Self.yearlyID])) ?? []
        // Monthly first — the anchor price; yearly reads as the deal.
        products = loaded.sorted { $0.id == Self.monthlyID && $1.id != Self.monthlyID }
    }

    /// Returns true when the purchase completed (not cancelled/pending).
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        guard let result = try? await product.purchase() else { return false }
        switch result {
        case .success(let verification):
            await handle(verification)
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        for await entitlement in Transaction.currentEntitlements {
            await handle(entitlement)
        }
    }

    private struct SyncBody: Encodable { let jws: String }
    private struct SyncResponse: Decodable {
        let proUntil: String?
        enum CodingKeys: String, CodingKey { case proUntil = "pro_until" }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        // On-device cryptographic verification is StoreKit 2's whole deal —
        // unverified transactions go nowhere.
        guard case .verified(let transaction) = result,
              transaction.productID == Self.monthlyID
                || transaction.productID == Self.yearlyID else { return }
        // Server-side entitlement write — best-effort here; the listener
        // re-delivers on next launch if the network ate this attempt.
        // `.init(body:)` without naming the options type — the
        // VoiceRoomService/AccountDeletionRepository invoke idiom (avoids
        // an explicit `import Supabase` here).
        let response: SyncResponse? = try? await SupabaseService.shared.client.functions.invoke(
            "verify-entitlement",
            options: .init(body: SyncBody(jws: result.jwsRepresentation))
        )
        if let until = response?.proUntil {
            proUntil = ISO8601DateFormatter().date(from: until)
                ?? ISO8601DateFormatter.withFractionalSeconds.date(from: until)
        }
        await transaction.finish()
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
