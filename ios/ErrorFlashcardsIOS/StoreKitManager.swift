import Foundation
import StoreKit

enum StoreError: Error {
    case productNotFound
    case purchaseFailed
    case verificationFailed
}

@MainActor
@Observable
final class StoreKitManager {
    static let productID = "com.legaliss.errorflashcardsios.pro.monthly.v2"

    enum ProductLoadState: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    var isPro = false
    var product: Product?
    var productLoadState: ProductLoadState = .loading
    var isPurchasing = false
    var purchaseError: String?

    init() {
        Task {
            await fetchProduct()
            await updateEntitlements()
        }

        Task {
            for await result in Transaction.updates {
                await self.handle(transaction: result)
            }
        }
    }

    var canPurchase: Bool {
        product != nil && productLoadState == .ready && !isPurchasing
    }

    var displayPrice: String {
        product?.displayPrice ?? "..."
    }

    var subscriptionTerms: String {
        guard let product else { return "Subscription details are loaded securely from the App Store." }
        let period = product.subscription?.subscriptionPeriod
        let unit: String = {
            switch period?.unit {
            case .day: return "day"
            case .month: return "month"
            case .year: return "year"
            case .week: return "week"
            default: return "period"
            }
        }()
        return "\(product.displayPrice)/\(unit), auto-renewing. Cancel anytime."
    }

    func fetchProduct() async {
        productLoadState = .loading
        purchaseError = nil

        do {
            let products = try await Product.products(for: [Self.productID])
            guard let matchedProduct = products.first(where: { $0.id == Self.productID }) else {
                product = nil
                productLoadState = .unavailable("The subscription is temporarily unavailable. Please try again in a moment.")
                return
            }

            product = matchedProduct
            productLoadState = .ready
        } catch {
            product = nil
            productLoadState = .unavailable("We couldn't load the subscription from the App Store. Please check your connection and try again.")
            purchaseError = error.localizedDescription
        }
    }

    func purchase() async {
        var activeProduct = product

        if activeProduct == nil {
            await fetchProduct()
            activeProduct = self.product
        }

        guard let activeProduct else {
            purchaseError = "The subscription is not available yet. Please tap Retry and try again."
            return
        }

        isPurchasing = true
        purchaseError = nil

        do {
            let result = try await activeProduct.purchase()
            switch result {
            case .success(let verification):
                await handle(transaction: verification)
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isPurchasing = false
    }

    func restore() async {
        isPurchasing = true
        purchaseError = nil

        do {
            try await AppStore.sync()
            await updateEntitlements()
            if !isPro {
                purchaseError = "No active Error Flashcards Pro subscription was found for this Apple ID."
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isPurchasing = false
    }

    func updateEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            if transaction.productID == Self.productID,
               transaction.productType == .autoRenewable,
               transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true,
               !transaction.isUpgraded {
                isPro = true
                return
            }
        }

        isPro = false
    }

    private func handle(transaction verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else {
            purchaseError = "We couldn't verify the purchase. Please try again or contact Apple Support."
            return
        }

        guard transaction.productID == Self.productID else {
            return
        }

        await transaction.finish()
        await updateEntitlements()
    }
}
