import PhotosUI
import SwiftUI
import UIKit

enum RootTab: String, CaseIterable {
    case home = "Home"
    case importCard = "Import"
    case review = "Review"
    case library = "Library"
    case profile = "Profile"

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .importCard: return "camera.viewfinder"
        case .review: return "rectangle.on.rectangle"
        case .library: return "square.grid.2x2.fill"
        case .profile: return "person.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: RootTab = .home
    @StateObject private var model = AppModel()
    @Environment(StoreKitManager.self) private var storeManager
    @State private var showingPaywall = false
    @State private var paywallReason: PaywallView.PaywallReason = .upgrade

    var body: some View {
        ZStack(alignment: .bottom) {
            EFBackground()

            Group {
                switch selectedTab {
                case .home:
                    HomeScreen(model: model, selectedTab: $selectedTab, showingPaywall: $showingPaywall, paywallReason: $paywallReason)
                case .importCard:
                    ImportScreen(model: model, selectedTab: $selectedTab, showingPaywall: $showingPaywall, paywallReason: $paywallReason)
                case .review:
                    ReviewScreen(model: model)
                case .library:
                    LibraryScreen(model: model, showingPaywall: $showingPaywall, paywallReason: $paywallReason)
                case .profile:
                    ProfileScreen(model: model, showingPaywall: $showingPaywall, paywallReason: $paywallReason)
                }
            }
            .padding(.bottom, 108)

            FloatingTabBar(selectedTab: $selectedTab)
        }
        .preferredColorScheme(.light)
        .onAppear {
            model.syncProStatus(storeManager.isPro)
        }
        .onChange(of: storeManager.isPro) { _, newValue in
            model.syncProStatus(newValue)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(reason: paywallReason)
        }
    }
}

struct HomeScreen: View {
    @ObservedObject var model: AppModel
    @Binding var selectedTab: RootTab
    @Binding var showingPaywall: Bool
    @Binding var paywallReason: PaywallView.PaywallReason
    @State private var editingWeaknessItem: WeaknessItem?
    @State private var editingQueueCard: Flashcard?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                heroCard
                statsGrid
                weaknessSection
                queueSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .sheet(item: $editingWeaknessItem) { item in
            WeaknessGroupEditorSheet(model: model, item: item)
        }
        .sheet(item: $editingQueueCard) { card in
            FlashcardEditorSheet(card: card, onSave: { updatedCard in
                model.updateCard(updatedCard)
            }, isPro: model.isPro)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Error Flashcards")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(EFPalette.inkSoft)
                Text("Review only what matters today")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(EFPalette.ink)
            }

            Spacer()

            Circle()
                .fill(EFPalette.whiteCard)
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "bell.badge.fill").foregroundStyle(EFPalette.orange))
                .shadow(color: EFShadow.card, radius: 18, x: 0, y: 8)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Study rhythm is staying steady")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(EFPalette.butter.opacity(0.55))
                    .clipShape(Capsule())

                Spacer()

                Text("Evening Block")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(EFPalette.inkSoft)
            }

            Text("Turn scattered mistakes into cards you actually remember.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(EFPalette.ink)

            Text("Capture a problem, auto-build a card, review on a memory-driven schedule, and use the heatmap to catch the concepts you lose most easily.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(EFPalette.inkSoft)
                .lineSpacing(3)

            HStack(spacing: 12) {
                Button("Continue Review") {
                    selectedTab = .review
                }
                .buttonStyle(FilledActionButtonStyle())

                Button("Import a Problem") {
                    selectedTab = .importCard
                }
                .buttonStyle(SoftActionButtonStyle())
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.72), EFPalette.butter.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(EFPalette.orange.opacity(0.14))
                .frame(width: 140, height: 140)
                .offset(x: 40, y: -40)
        }
        .shadow(color: EFShadow.card, radius: 28, x: 0, y: 18)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(model.stats) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(EFPalette.inkSoft)
                    Text(item.value)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.ink)
                    Text(item.accent)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .efCard()
                .contentShape(Rectangle())
                .onTapGesture {
                    if !model.isPro && item.title == "Mastery" {
                        paywallReason = .advancedStats
                        showingPaywall = true
                    }
                }
            }
        }
    }

    private var weaknessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Weak Spots", caption: "Reinforce the easiest points to miss first")

            if model.isPro {
                ForEach(model.weaknessItems) { item in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 6) {
                            ForEach(0..<5, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(index < item.level ? EFPalette.orange.opacity(0.9 - Double(index) * 0.12) : EFPalette.powder.opacity(0.65))
                                    .frame(width: 18, height: 18)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(EFPalette.ink)
                            Text(item.detail)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(EFPalette.inkSoft)
                            Text("Intensity L\(item.level)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(EFPalette.orange)
                        }

                        Spacer()

                        Button {
                            editingWeaknessItem = item
                        } label: {
                            Label("Rename", systemImage: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(EFPalette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(EFPalette.cream)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .efCard()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingWeaknessItem = item
                    }
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(EFPalette.orange)
                    Text("Unlock with Pro")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.ink)
                    Text("See your weakest areas and get targeted review recommendations.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.inkSoft)
                        .multilineTextAlignment(.center)
                    Button("Learn More") {
                        paywallReason = .advancedStats
                        showingPaywall = true
                    }
                    .buttonStyle(FilledActionButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .efCard()
            }
        }
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Up Next", caption: "Sorted automatically by due priority")

            ForEach(model.reviewQueue.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(item.subject)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(EFPalette.powder.opacity(0.65))
                            .clipShape(Capsule())

                        Spacer()

                        Button {
                            editingQueueCard = item
                        } label: {
                            Label("Edit", systemImage: "square.and.pencil")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(EFPalette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(EFPalette.cream)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Text(item.due)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(EFPalette.orange)
                    }

                    Text(item.prompt)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(EFPalette.ink)
                }
                .padding(18)
                .efCard()
                .contentShape(Rectangle())
                .onTapGesture {
                    editingQueueCard = item
                }
            }
        }
    }

    private func sectionHeader(title: String, caption: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(EFPalette.ink)
            Spacer()
            Text(caption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(EFPalette.inkSoft)
        }
    }
}

struct ImportScreen: View {
    private enum ImportFocusField: Hashable {
        case importText
    }

    @ObservedObject var model: AppModel
    @Binding var selectedTab: RootTab
    @Binding var showingPaywall: Bool
    @Binding var paywallReason: PaywallView.PaywallReason
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showsCameraCapture = false
    @FocusState private var focusedField: ImportFocusField?

    var body: some View {
        let photoPickerTitle = model.isImporting ? "Recognizing..." : "Offline Scan from Photos"
        let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

        ScreenShell(title: "Import", subtitle: "Capture or paste content and turn it into a structured card") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Photo capture area")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                        .foregroundStyle(EFPalette.butter)
                        .frame(height: 220)
                        .overlay {
                            VStack(spacing: 14) {
                                Image(systemName: model.isImporting ? "clock.arrow.circlepath" : "viewfinder.circle.fill")
                                    .font(.system(size: 54))
                                    .foregroundStyle(EFPalette.butter)
                                HStack(spacing: 12) {
                                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                        Text(photoPickerTitle)
                                    }
                                    .buttonStyle(SoftActionButtonStyle())
                                    .disabled(model.isImporting || !model.canUseOCR)

                                    Button("Use Camera") {
                                        dismissKeyboard()
                                        showsCameraCapture = true
                                    }
                                    .buttonStyle(FilledActionButtonStyle())
                                    .disabled(model.isImporting || !cameraAvailable || !model.canUseOCR)
                                }

                                if !model.isPro {
                                    Text(model.canUseOCR
                                         ? "\(model.remainingOCRToday) free OCR import\(model.remainingOCRToday == 1 ? "" : "s") left today"
                                         : "Free OCR limit reached for today")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(model.canUseOCR ? EFPalette.butter : Color.red.opacity(0.85))

                                    if !model.canUseOCR {
                                        Button("Upgrade for Unlimited OCR") {
                                            paywallReason = .ocrLimit
                                            showingPaywall = true
                                        }
                                        .buttonStyle(SoftActionButtonStyle())
                                    }
                                }
                            }
                        }
                    Text("Frame the prompt, choices, and explanation. Everything stays offline.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(20)
                .background(
                    LinearGradient(colors: [EFPalette.ink, Color(red: 63 / 255, green: 29 / 255, blue: 29 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 26, x: 0, y: 16)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(EFPalette.orange)
                    Text("Camera and photo-library OCR may miss details. After import, quickly correct the prompt, choices, and answer by hand.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(EFPalette.ink)
                        .multilineTextAlignment(.leading)
                }
                .padding(18)
                .background(EFPalette.butter.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Text Import")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    TextEditor(text: $model.importText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.inkSoft)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .focused($focusedField, equals: .importText)
                        .padding(18)
                        .background(EFPalette.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Text(model.importStatusMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.importStatusMessage.localizedCaseInsensitiveContains("failed") ? Color.red.opacity(0.85) : EFPalette.orange)

                    HStack(spacing: 12) {
                        Button("Parse Text Offline") {
                            dismissKeyboard()
                            model.prepareImportFromText()
                        }
                        .buttonStyle(FilledActionButtonStyle())
                    }
                }
                .padding(20)
                .efCard()

                if let draftBinding = importPreviewBinding {
                    ImportPreviewCard(draft: draftBinding)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if model.cardLimitReached {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(EFPalette.orange)
                        Text("Free card limit (50) reached")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(EFPalette.inkSoft)
                        Button("Upgrade") {
                            paywallReason = .cardLimit
                            showingPaywall = true
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.orange)
                    }
                }

                Button {
                    dismissKeyboard()
                    if model.commitImportDraft() {
                        selectedTab = .library
                    }
                } label: {
                    Text("Save to Library")
                }
                .buttonStyle(ProminentWideButtonStyle())
                .disabled(model.importPreview == nil || (!model.isPro && model.cardLimitReached))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .background(.ultraThinMaterial.opacity(0.96))
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }

            Task {
                do {
                    guard let data = try await newValue.loadTransferable(type: Data.self) else {
                        model.setImportError("Image loading failed. Please try again.")
                        return
                    }
                    await model.importPhotoData(data)
                } catch {
                    model.setImportError("Image loading failed. Please try again.")
                }

                selectedPhotoItem = nil
            }
        }
        .sheet(isPresented: $showsCameraCapture) {
            CameraCaptureSheet(sourceType: .camera) { data in
                Task {
                    await model.importPhotoData(data, source: "Camera Import")
                }
            }
        }
    }

    private var importPreviewBinding: Binding<FlashcardDraft>? {
        guard let preview = model.importPreview else { return nil }

        return Binding(
            get: { model.importPreview ?? preview },
            set: { model.importPreview = $0 }
        )
    }
}

struct ReviewScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScreenShell(title: "Today's Review", subtitle: "Answer first, then reveal the answer") {
            VStack(spacing: 18) {
                if let card = model.currentReviewCard {
                    ReviewCardPanel(card: card) { result in
                        model.reviewCurrent(as: result)
                    }
                    .id(card.id)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("No cards are due right now")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Import a new problem first, or head back home to check today's pace.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(EFPalette.inkSoft)
                    }
                    .padding(22)
                    .efCard()
                }
            }
        }
    }
}

struct LibraryScreen: View {
    @ObservedObject var model: AppModel
    @Binding var showingPaywall: Bool
    @Binding var paywallReason: PaywallView.PaywallReason
    @State private var searchText = ""
    @State private var selectedDeck = "All"
    @State private var editingCard: Flashcard?
    @State private var deletingCard: Flashcard?

    var body: some View {
        ScreenShell(title: "Library", subtitle: "Keep cards by deck, then retrieve them by tag") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search & Filter")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    TextField("Search prompts, tags, or sources", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .padding(16)
                        .background(EFPalette.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            DeckFilterChip(
                                title: "All",
                                isSelected: selectedDeck == "All"
                            ) {
                                selectedDeck = "All"
                            }

                            ForEach(model.deckOptions, id: \.self) { deck in
                                DeckFilterChip(
                                    title: deck,
                                    isSelected: selectedDeck == deck
                                ) {
                                    selectedDeck = deck
                                }
                            }
                        }
                    }

                    HStack {
                        if model.isPro {
                            Text("\(filteredCards.count) cards")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(EFPalette.inkSoft)
                        } else {
                            Text("\(filteredCards.count)/50 cards")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(model.cardLimitReached ? Color.red.opacity(0.8) : EFPalette.inkSoft)

                            if model.cardLimitReached {
                                Button("Upgrade") {
                                    paywallReason = .cardLimit
                                    showingPaywall = true
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(EFPalette.orange)
                            }
                        }
                    }
                }
                .padding(20)
                .efCard()

                ForEach(filteredCards) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(item.subject)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(EFPalette.orange)
                            Spacer()
                            Button {
                                editingCard = item
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(EFPalette.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(EFPalette.cream)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            Button {
                                deletingCard = item
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.red.opacity(0.85))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.red.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            Text(item.due)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(EFPalette.inkSoft)
                        }
                        Text(item.prompt)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(EFPalette.ink)
                        HStack(spacing: 8) {
                            TagChip(text: item.source)
                            TagChip(text: item.tag)
                            TagChip(text: item.deck)
                        }
                    }
                    .padding(18)
                    .efCard()
                }
            }
        }
        .sheet(item: $editingCard) { card in
            FlashcardEditorSheet(card: card, onSave: { updatedCard in
                model.updateCard(updatedCard)
            }, isPro: model.isPro)
        }
        .confirmationDialog(
            "Delete this card?",
            isPresented: Binding(
                get: { deletingCard != nil },
                set: { if !$0 { deletingCard = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deletingCard {
                    model.deleteCard(deletingCard)
                }
                deletingCard = nil
            }
            Button("Cancel", role: .cancel) {
                deletingCard = nil
            }
        } message: {
            Text(deletingCard?.prompt ?? "")
        }
    }

    private var filteredCards: [Flashcard] {
        model.cards.filter { item in
            let matchesDeck = selectedDeck == "All" || item.deck == selectedDeck
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = query.isEmpty || item.prompt.localizedCaseInsensitiveContains(query) || item.tag.localizedCaseInsensitiveContains(query) || item.source.localizedCaseInsensitiveContains(query)
            return matchesDeck && matchesQuery
        }
    }
}

struct ProfileScreen: View {
    @ObservedObject var model: AppModel
    @Binding var showingPaywall: Bool
    @Binding var paywallReason: PaywallView.PaywallReason
    @Environment(StoreKitManager.self) private var storeManager
    @Environment(\.openURL) private var openURL
    @State private var draftReminder = ""
    @State private var draftGoal = ""
    @State private var draftDefaultDeck = ""
    @State private var didLoadDrafts = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScreenShell(title: "Profile", subtitle: "Device, goals, and review preferences") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.displayGoal)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(model.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? EFPalette.inkSoft : EFPalette.ink)
                    Text("Offline on this device · SQLite + Vision")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(
                    LinearGradient(colors: [EFPalette.whiteCard, EFPalette.powder.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: EFShadow.card, radius: 26, x: 0, y: 16)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Subscription")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.ink)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(storeManager.isPro ? "Pro" : "Free")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(storeManager.isPro ? EFPalette.orange : EFPalette.inkSoft)
                            Text(storeManager.isPro ? "You have full access to all features." : "Limited to 50 cards and 3 OCR imports per day.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(EFPalette.inkSoft)
                        }

                        Spacer()

                        if !storeManager.isPro {
                            Button("Upgrade") {
                                paywallReason = .upgrade
                                showingPaywall = true
                            }
                            .buttonStyle(FilledActionButtonStyle())
                        }
                    }
                    .padding(18)
                    .background(EFPalette.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if storeManager.isPro {
                        Button("Restore Purchases") {
                            Task {
                                await storeManager.restore()
                            }
                        }
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.inkSoft)
                    }
                }
                .padding(20)
                .efCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Editable Preferences")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.ink)

                    profileTextField(title: "Study Goal", placeholder: "Set your study goal", text: $draftGoal)
                    profileTextField(title: "Review Reminder", placeholder: "e.g. Every day 8:00 PM", text: $draftReminder)
                    profileTextField(title: "Default Deck", placeholder: "Set a default deck", text: $draftDefaultDeck)
                    PreferenceRow(title: "OCR Mode", value: "Offline First")
                    PreferenceRow(title: "Study Summary", value: model.profileSummary)

                    Button("Save My Settings") {
                        dismissKeyboard()
                        model.updateProfile(
                            goal: draftGoal,
                            reminder: draftReminder,
                            defaultDeck: draftDefaultDeck
                        )
                        loadDrafts(force: true)
                    }
                    .buttonStyle(ProminentWideButtonStyle())
                }
                .padding(20)
                .efCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Legal")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.ink)

                    Button("Privacy Policy") {
                        openURL(URL(string: "https://jackwheyd1.github.io/error-flashcards-site/privacy-policy.html")!)
                    }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(EFPalette.orange)

                    Button("Terms of Use") {
                        openURL(URL(string: "https://jackwheyd1.github.io/error-flashcards-site/terms-of-use.html")!)
                    }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(EFPalette.orange)
                }
                .padding(20)
                .efCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Data & Privacy")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.ink)

                    Text("All your flashcards and settings are stored locally on this device. You can delete all data at any time.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.inkSoft)

                    Button("Delete All Data") {
                        showDeleteConfirmation = true
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                }
                .padding(20)
                .efCard()
            }
        }
        .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                model.deleteAllData()
            }
        } message: {
            Text("This will permanently delete all your flashcards, settings, and review history. This cannot be undone.")
        }
        .onAppear {
            loadDrafts()
        }
    }

    @ViewBuilder
    private func profileTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(EFPalette.ink)
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .padding(16)
                .background(EFPalette.cream)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func loadDrafts(force: Bool = false) {
        guard force || !didLoadDrafts else { return }
        draftGoal = model.goal
        draftReminder = model.reminder
        draftDefaultDeck = model.defaultDeck
        didLoadDrafts = true
    }
}

struct ScreenShell<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.ink)
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.inkSoft)
                }
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            dismissKeyboard()
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: RootTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == tab ? EFPalette.orange : EFPalette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(EFPalette.cream)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: EFShadow.card, radius: 26, x: 0, y: 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }
}

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(EFPalette.cream)
            .clipShape(Capsule())
    }
}

struct CameraCaptureSheet: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onCapture: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraCaptureSheet

        init(parent: CameraCaptureSheet) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.92) {
                parent.onCapture(data)
            }

            picker.dismiss(animated: true)
        }
    }
}

struct WeaknessGroupEditorSheet: View {
    @ObservedObject var model: AppModel
    let item: WeaknessItem

    @Environment(\.dismiss) private var dismiss

    @State private var draftTag: String

    init(model: AppModel, item: WeaknessItem) {
        self.model = model
        self.item = item
        _draftTag = State(initialValue: item.tag)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Group Name")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(EFPalette.ink)

                Text("Give it a name you can recognize instantly.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(EFPalette.inkSoft)

                TextField("Enter a group name", text: $draftTag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .padding(16)
                    .background(EFPalette.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
            .navigationTitle("Rename Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.updateWeaknessGroup(
                            originalTag: item.tag,
                            newTag: draftTag
                        )
                        dismiss()
                    }
                    .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ImportPreviewCard: View {
    @Binding var draft: FlashcardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Parse Preview")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Text(draft.subject)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(EFPalette.powder.opacity(0.72))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Prompt")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(EFPalette.inkSoft)

                TextEditor(text: $draft.prompt)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(16)
                    .background(EFPalette.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            if !draft.choices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choices & Answer Check")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(EFPalette.inkSoft)

                    ForEach(Array(draft.choices.enumerated()), id: \.offset) { index, choice in
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(choiceLabel(for: index)). \(choice)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(EFPalette.ink)
                                    .multilineTextAlignment(.leading)
                                if draft.answer == choice {
                                    Text("Current confirmed answer")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(EFPalette.orange)
                                }
                            }

                            Spacer()

                            Button {
                                draft.answer = choice
                            } label: {
                                HStack(spacing: 6) {
                                    Text(draft.answer == choice ? "Confirmed" : "Set as Answer")
                                    if draft.answer == choice {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(draft.answer == choice ? .white : EFPalette.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(draft.answer == choice ? EFPalette.orange : EFPalette.whiteCard)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(EFPalette.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }

            Text("Recognition is only a draft. Before saving, quickly correct the prompt, choices, and answer.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(EFPalette.orange)

            VStack(alignment: .leading, spacing: 10) {
                Text("Confirm Answer")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(EFPalette.inkSoft)

                TextField("Type the answer manually if needed", text: $draft.answer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .padding(18)
                    .background(EFPalette.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(
                    draft.isAnswerPending
                    ? "Confirm the correct answer before saving."
                    : "Current answer: \(draft.answer)"
                )
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(draft.isAnswerPending ? Color.red.opacity(0.8) : EFPalette.orange)
            }
        }
        .padding(20)
        .efCard()
    }

    private func choiceLabel(for index: Int) -> String {
        ["A", "B", "C", "D", "E"][safe: index] ?? "Choice"
    }
}

struct ReviewCardPanel: View {
    let card: Flashcard
    let onRate: (ReviewResult) -> Void

    @State private var showsAnswer = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(card.subject)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(EFPalette.powder.opacity(0.7))
                        .clipShape(Capsule())
                    Spacer()
                    Text(showsAnswer ? "Prompt + Answer" : "Prompt")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(EFPalette.inkSoft)
                }

                Text(card.prompt.isEmpty ? "This card does not have a prompt yet. Open it from the library and finish it there." : card.prompt)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(EFPalette.ink)

                if !card.displayChoices.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(card.displayChoices, id: \.self) { choice in
                            HStack {
                                Text(choice)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(EFPalette.ink)
                                Spacer()
                            }
                            .padding(16)
                            .background(EFPalette.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }

                if showsAnswer {
                    Text("Answer: \(card.answer)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(EFPalette.orange)
                } else {
                    Button("Show Answer") {
                        showsAnswer = true
                    }
                    .buttonStyle(FilledActionButtonStyle())
                }
            }
            .padding(22)
            .efCard()

            HStack(spacing: 12) {
                Button("Again") {
                    onRate(.again)
                }
                .buttonStyle(TonalReviewButtonStyle(background: Color.red.opacity(0.12), foreground: Color.red.opacity(0.8)))
                Button("Hard") {
                    onRate(.hard)
                }
                .buttonStyle(TonalReviewButtonStyle(background: EFPalette.butter.opacity(0.4), foreground: EFPalette.orange))
                Button("Good") {
                    onRate(.good)
                }
                .buttonStyle(TonalReviewButtonStyle(background: EFPalette.powder.opacity(0.75), foreground: EFPalette.ink))
            }
            .opacity(showsAnswer ? 1 : 0.45)
            .disabled(!showsAnswer)
        }
    }
}

struct FlashcardEditorSheet: View {
    let card: Flashcard
    let onSave: (Flashcard) -> Void
    let isPro: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var subject: String
    @State private var prompt: String
    @State private var answer: String
    @State private var deck: String
    @State private var tag: String
    @State private var source: String
    @State private var choiceA: String
    @State private var choiceB: String
    @State private var choiceC: String
    @State private var choiceD: String
    @State private var choiceE: String

    init(card: Flashcard, onSave: @escaping (Flashcard) -> Void, isPro: Bool = false) {
        self.card = card
        self.onSave = onSave
        self.isPro = isPro

        let paddedChoices = Array(card.choices.prefix(5)) + Array(repeating: "", count: max(0, 5 - card.choices.count))

        _subject = State(initialValue: card.subject)
        _prompt = State(initialValue: card.prompt)
        _answer = State(initialValue: card.answer)
        _deck = State(initialValue: card.deck)
        _tag = State(initialValue: card.tag)
        _source = State(initialValue: card.source)
        _choiceA = State(initialValue: paddedChoices[0])
        _choiceB = State(initialValue: paddedChoices[1])
        _choiceC = State(initialValue: paddedChoices[2])
        _choiceD = State(initialValue: paddedChoices[3])
        _choiceE = State(initialValue: paddedChoices[4])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Subject", text: $subject)
                    TextEditor(text: $prompt)
                        .frame(minHeight: 120)
                    TextField("Answer", text: $answer)
                }

                Section("Choices") {
                    TextField("A", text: $choiceA)
                    TextField("B", text: $choiceB)
                    TextField("C", text: $choiceC)
                    TextField("D", text: $choiceD)
                    TextField("E", text: $choiceE)
                }

                Section("Metadata") {
                    HStack {
                        TextField("Deck", text: $deck)
                            .disabled(!isPro)
                        if !isPro {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(EFPalette.orange)
                        }
                    }
                    HStack {
                        TextField("Tag", text: $tag)
                            .disabled(!isPro)
                        if !isPro {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(EFPalette.orange)
                        }
                    }
                    TextField("Source", text: $source)
                }

                if !isPro {
                    Section {
                        Text("Custom decks and tags are Pro features. Upgrade to organize cards your way.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(EFPalette.orange)
                    }
                }
            }
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(makeUpdatedCard())
                        dismiss()
                    }
                    .disabled(trimmedPrompt.isEmpty || trimmedAnswer.isEmpty)
                }
            }
        }
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAnswer: String {
        answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeUpdatedCard() -> Flashcard {
        Flashcard(
            id: card.id,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? card.subject : subject.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: trimmedPrompt,
            choices: [choiceA, choiceB, choiceC, choiceD, choiceE]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            answer: trimmedAnswer,
            due: card.due,
            deck: deck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? card.deck : deck.trimmingCharacters(in: .whitespacesAndNewlines),
            tag: tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? card.tag : tag.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? card.source : source.trimmingCharacters(in: .whitespacesAndNewlines),
            strength: card.strength,
            createdAt: card.createdAt,
            updatedAt: .now
        )
    }
}

struct DeckFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : EFPalette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? EFPalette.orange : EFPalette.cream)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PreferenceRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(EFPalette.ink)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(title == "Study Summary" ? EFPalette.inkSoft : EFPalette.orange)
        }
    }
}

struct FilledActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(EFPalette.orange.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(Capsule())
    }
}

struct SoftActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(EFPalette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(EFPalette.whiteCard.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(Capsule())
    }
}

struct ProminentWideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(EFPalette.orange.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: EFPalette.orange.opacity(0.22), radius: 18, x: 0, y: 10)
    }
}

struct TonalReviewButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(background.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
