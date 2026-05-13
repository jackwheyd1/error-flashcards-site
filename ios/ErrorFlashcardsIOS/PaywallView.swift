import SwiftUI

struct PaywallView: View {
    @Environment(StoreKitManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let reason: PaywallReason

    enum PaywallReason {
        case ocrLimit
        case cardLimit
        case advancedStats
        case customDecks
        case upgrade

        var title: String {
            switch self {
            case .ocrLimit: return "OCR Limit Reached"
            case .cardLimit: return "Card Limit Reached"
            case .advancedStats: return "Advanced Stats"
            case .customDecks: return "Custom Tags & Decks"
            case .upgrade: return "Error Flashcards Pro"
            }
        }

        var message: String {
            switch self {
            case .ocrLimit:
                return "You've used your 3 free OCR imports today. Upgrade to Pro for unlimited imports."
            case .cardLimit:
                return "You've reached the 50-card free limit. Upgrade to Pro for unlimited cards."
            case .advancedStats:
                return "Mastery rate and weakness analysis are Pro features. Upgrade to see your full study picture."
            case .customDecks:
                return "Custom decks and tags let you organize your way. Available with Pro."
            case .upgrade:
                return "Get unlimited OCR imports, unlimited cards, advanced stats, and custom organization."
            }
        }

        var icon: String {
            switch self {
            case .ocrLimit: return "camera.viewfinder"
            case .cardLimit: return "square.grid.2x2.fill"
            case .advancedStats: return "chart.bar.fill"
            case .customDecks: return "tag.fill"
            case .upgrade: return "crown.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 16)

            Image(systemName: reason.icon)
                .font(.system(size: 48))
                .foregroundStyle(EFPalette.orange)

            Text(reason.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(EFPalette.ink)

            Text(reason.message)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(EFPalette.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(EFPalette.orange)
                        .font(.system(size: 16))
                    Text("Unlimited OCR imports")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.ink)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(EFPalette.orange)
                        .font(.system(size: 16))
                    Text("Unlimited cards in your library")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.ink)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(EFPalette.orange)
                        .font(.system(size: 16))
                    Text("Advanced stats & weakness analysis")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.ink)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(EFPalette.orange)
                        .font(.system(size: 16))
                    Text("Custom decks and tags")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.ink)
                    Spacer()
                }
            }
            .padding(20)
            .background(EFPalette.cream)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 10) {
                Button {
                    Task {
                        await storeManager.purchase()
                        if storeManager.isPro {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if storeManager.isPurchasing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(primaryButtonTitle)
                    }
                }
                .buttonStyle(ProminentWideButtonStyle())
                .disabled(!storeManager.canPurchase)

                Button("Restore Purchases") {
                    Task {
                        await storeManager.restore()
                        if storeManager.isPro {
                            dismiss()
                        }
                    }
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(EFPalette.inkSoft)
                .disabled(storeManager.isPurchasing)

                if case .unavailable(let message) = storeManager.productLoadState {
                    VStack(spacing: 10) {
                        Text(message)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(EFPalette.inkSoft)
                            .multilineTextAlignment(.center)

                        Button("Retry") {
                            Task {
                                await storeManager.fetchProduct()
                            }
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.orange)
                        .disabled(storeManager.isPurchasing)
                    }
                    .padding(.top, 4)
                } else if storeManager.productLoadState == .loading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading secure App Store pricing...")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(EFPalette.inkSoft)
                    }
                    .padding(.top, 4)
                }

                Button("Maybe Later") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(EFPalette.inkSoft)
            }

            if let error = storeManager.purchaseError {
                Text(error)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text(storeManager.subscriptionTerms)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(EFPalette.inkSoft)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Privacy Policy") {
                    openURL(URL(string: "https://jackwheyd1.github.io/error-flashcards-site/privacy-policy.html")!)
                }
                Button("Terms of Use") {
                    openURL(URL(string: "https://jackwheyd1.github.io/error-flashcards-site/terms-of-use.html")!)
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(EFPalette.orange)

            Spacer()
        }
        .padding(24)
        .background(EFBackground())
        .task {
            if storeManager.product == nil {
                await storeManager.fetchProduct()
            }
        }
    }

    private var primaryButtonTitle: String {
        if storeManager.isPurchasing {
            return "Processing..."
        }

        if storeManager.productLoadState == .loading {
            return "Loading App Store Price..."
        }

        if case .unavailable = storeManager.productLoadState {
            return "Subscription Unavailable"
        }

        return "Subscribe \(storeManager.displayPrice)/month"
    }
}
