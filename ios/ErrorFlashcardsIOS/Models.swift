import Foundation
import SwiftUI
import UserNotifications

struct StatItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let accent: String
}

struct WeaknessItem: Identifiable {
    let tag: String
    let deck: String
    let dueTodayCount: Int
    let cardCount: Int
    let detail: String
    let level: Int

    var id: String { tag }
    var title: String { tag }
}

struct Flashcard: Identifiable, Codable, Hashable {
    var id: UUID
    var subject: String
    var prompt: String
    var choices: [String]
    var answer: String
    var due: String
    var deck: String
    var tag: String
    var source: String
    var strength: Int
    var createdAt: Date
    var updatedAt: Date

    var displayChoices: [String] {
        let normalized = choices
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return normalized == FlashcardDraft.placeholderChoices ? [] : normalized
    }

    init(
        id: UUID = UUID(),
        subject: String,
        prompt: String,
        choices: [String],
        answer: String,
        due: String,
        deck: String,
        tag: String,
        source: String,
        strength: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.subject = subject
        self.prompt = prompt
        self.choices = choices
        self.answer = answer
        self.due = due
        self.deck = deck
        self.tag = tag
        self.source = source
        self.strength = strength
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct DailyReviewActivity: Codable, Hashable {
    var dayKey: String
    var completedCount: Int
}

struct AppSnapshot {
    var cards: [Flashcard]
    var reviewActivity: [DailyReviewActivity]
    var reminder: String
    var goal: String
    var defaultDeck: String
    var ocrDailyCount: Int = 0
    var ocrDate: String = ""
}

enum ReviewResult {
    case again
    case hard
    case good
}

actor ReminderNotificationScheduler {
    static let shared = ReminderNotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let reminderIdentifier = "daily-review-reminder"

    func sync(reminder: String, reviewCount: Int, goal: String) async {
        guard let time = parseReminderTime(from: reminder) else {
            center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
            return
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted == true else { return }
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return
        @unknown default:
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Time to review"
        content.body = reviewCount > 0
            ? "You have \(reviewCount) cards due. Keep moving toward \(goal)."
            : "Start with one pass today, keep the rhythm steady, and keep moving toward \(goal)."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = time.hour
        dateComponents.minute = time.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func parseReminderTime(from reminder: String) -> (hour: Int, minute: Int)? {
        let pattern = #"([01]?\d|2[0-3])[:：]([0-5]\d)"#
        guard let range = reminder.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        let parts = String(reminder[range])
            .replacingOccurrences(of: "：", with: ":")
            .split(separator: ":")

        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        return (hour, minute)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var cards: [Flashcard] = []
    @Published private var reviewActivity: [DailyReviewActivity] = []
    @Published var reminder = "Every day 7:30 PM"
    @Published var goal = ""
    @Published var defaultDeck = ""
    @Published var importText = """
    What is the core role of formative assessment?
    A. Used for ranking
    B. Helps adjust learning
    C. Replaces exams
    D. Increases homework volume
    """
    @Published var importPreview: FlashcardDraft?
    @Published var importStatusMessage = "Text parsing and photo import both run fully offline."
    @Published var isImporting = false
    @Published var isPro = false
    @Published var ocrDailyCount = 0
    @Published var ocrDate = ""

    private let repository: LocalDatabase
    private let importPipeline: OfflineImportPipeline

    init(
        repository: LocalDatabase = LocalDatabase(),
        importPipeline: OfflineImportPipeline = OfflineImportPipeline()
    ) {
        self.repository = repository
        self.importPipeline = importPipeline
        apply(snapshot: normalizeSnapshot(repository.loadSnapshot(seed: Self.seedSnapshot)))
        syncReminderNotification()
    }

    var todayTarget: Int {
        cards.count
    }

    var completedToday: Int {
        reviewActivity.first(where: { $0.dayKey == Self.dayKey(from: .now) })?.completedCount ?? 0
    }

    var streak: Int {
        let usedDays = Set(reviewActivity.map(\.dayKey))
        var count = 0
        var cursor = Calendar.current.startOfDay(for: .now)

        while usedDays.contains(Self.dayKey(from: cursor)) {
            count += 1
            guard let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }

        return count
    }

    var displayGoal: String {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedGoal.isEmpty ? "Set your study goal" : trimmedGoal
    }

    var canUseOCR: Bool {
        isPro || ocrUsageToday < 3
    }

    var remainingOCRToday: Int {
        max(0, 3 - ocrUsageToday)
    }

    var canAddCard: Bool {
        isPro || cards.count < 50
    }

    var cardLimitReached: Bool {
        !isPro && cards.count >= 50
    }

    private var ocrUsageToday: Int {
        let todayKey = Self.dayKey(from: .now)
        if ocrDate == todayKey {
            return ocrDailyCount
        }
        return 0
    }

    func recordOCRUsage() {
        let todayKey = Self.dayKey(from: .now)
        if ocrDate != todayKey {
            ocrDate = todayKey
            ocrDailyCount = 1
        } else {
            ocrDailyCount += 1
        }
    }

    func syncProStatus(_ pro: Bool) {
        isPro = pro
    }

    var stats: [StatItem] {
        let progressValue = todayTarget == 0 ? "0/0" : "\(min(completedToday, todayTarget))/\(todayTarget)"
        let progressAccent = todayTarget == 0
            ? "Import your first card"
            : "\(max(todayTarget - completedToday, 0)) left today"

        return [
            StatItem(title: "Done Today", value: progressValue, accent: progressAccent),
            StatItem(title: "Due", value: "\(reviewQueue.count)", accent: "Queued locally"),
            StatItem(title: "Streak", value: "\(streak) days", accent: "Steady rhythm"),
            StatItem(title: "Mastery", value: isPro ? "\(masteryRate)%" : "Pro", accent: isPro ? "Current deck mix" : "Unlock with Pro")
        ]
    }

    var masteryRate: Int {
        guard isPro, !cards.isEmpty else { return 0 }
        let total = cards.reduce(0) { $0 + min(max($1.strength, 1), 5) }
        return Int((Double(total) / Double(cards.count * 5) * 100).rounded())
    }

    var weaknessItems: [WeaknessItem] {
        guard isPro else { return [] }
        let grouped = Dictionary(grouping: cards, by: \.tag)
        return grouped
            .map { tag, groupedCards in
                let lowestStrength = groupedCards.map(\.strength).min() ?? 1
                let dueToday = groupedCards.filter { $0.due.contains("Today") }.count
                let level = min(5, max(1, dueToday + (6 - lowestStrength)))
                return WeaknessItem(
                    tag: tag,
                    deck: groupedCards.first?.deck ?? fallbackDeckName,
                    dueTodayCount: dueToday,
                    cardCount: groupedCards.count,
                    detail: "\(groupedCards.first?.deck ?? "Unsorted") · \(dueToday) due today · \(groupedCards.count) cards total",
                    level: level
                )
            }
            .sorted { lhs, rhs in
                if lhs.level == rhs.level {
                    return lhs.title < rhs.title
                }
                return lhs.level > rhs.level
            }
            .prefix(3)
            .map { $0 }
    }

    var reviewQueue: [Flashcard] {
        cards.sorted {
            if $0.strength == $1.strength {
                return $0.due < $1.due
            }
            return $0.strength < $1.strength
        }
    }

    var currentReviewCard: Flashcard? {
        reviewQueue.first
    }

    var profileSummary: String {
        "You have finished \(completedToday) reviews today. Your weakest tag is \(weaknessItems.first?.title ?? "None yet"), and \(reviewQueue.first?.deck ?? "Library") is the best deck to reinforce next."
    }

    var deckOptions: [String] {
        Array(Set(cards.map(\.deck) + [defaultDeck]))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted()
    }

    func prepareImportFromText() {
        guard let draft = importPipeline.parse(text: importText) else {
            setImportError("No valid prompt detected. Add the prompt or choices first.")
            return
        }
        applyImportDraft(normalizedImportDraft(draft), successMessage: "Offline parsing finished. Preview it before saving.")
    }

    func commitImportDraft() -> Bool {
        guard var draft = importPreview else { return false }

        guard canAddCard else {
            importStatusMessage = "Free card limit (50) reached. Upgrade to Pro for unlimited cards."
            return false
        }

        draft.prompt = draft.trimmedPrompt
        draft.answer = draft.trimmedAnswer

        guard !draft.prompt.isEmpty else {
            importPreview = draft
            importStatusMessage = "Complete the prompt before saving."
            return false
        }

        guard !draft.isAnswerPending else {
            importPreview = draft
            importStatusMessage = "Confirm the correct answer before saving."
            return false
        }

        cards.insert(
            draft.makeFlashcard(
                due: "Today 10:10 PM",
                source: draft.source
            ),
            at: 0
        )
        importPreview = nil
        importText = ""
        importStatusMessage = "Saved to the local database."
        persistState()
        return true
    }

    func importPhotoData(_ data: Data) async {
        await importPhotoData(data, source: "Photo Library Import")
    }

    func importPhotoData(_ data: Data, source: String) async {
        isImporting = true
        importStatusMessage = "Running offline OCR on the image..."

        do {
            let recognizedText = try await importPipeline.recognizeText(from: data)
            importText = recognizedText
            recordOCRUsage()

            if let draft = importPipeline.parse(text: recognizedText) {
                var normalizedDraft = normalizedImportDraft(draft)
                normalizedDraft.source = source
                applyImportDraft(normalizedDraft, successMessage: "Vision OCR and local parsing completed.")
            } else {
                importPreview = nil
                importStatusMessage = "Text was recognized, but the full prompt could not be extracted yet."
            }
        } catch {
            setImportError("Offline OCR failed. Try a clearer image.")
        }

        isImporting = false
    }

    func setImportError(_ message: String) {
        importPreview = nil
        importStatusMessage = message
    }

    func updateCard(_ updatedCard: Flashcard) {
        guard let index = cards.firstIndex(where: { $0.id == updatedCard.id }) else { return }
        cards[index] = updatedCard
        persistState()
    }

    func cards(for tag: String) -> [Flashcard] {
        cards
            .filter { $0.tag == tag }
            .sorted { lhs, rhs in
                if lhs.strength == rhs.strength {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.strength < rhs.strength
            }
    }

    func updateWeaknessGroup(originalTag: String, newTag: String) {
        let trimmedTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTag.isEmpty else { return }

        var didChange = false

        for index in cards.indices where cards[index].tag == originalTag {
            cards[index].tag = trimmedTag
            cards[index].updatedAt = .now
            didChange = true
        }

        if didChange {
            persistState()
        }
    }

    func deleteCard(_ card: Flashcard) {
        cards.removeAll { $0.id == card.id }
        persistState()
    }

    func deleteAllData() {
        repository.deleteAllData()
        cards = []
        reviewActivity = []
        reminder = "Every day 7:30 PM"
        goal = ""
        defaultDeck = ""
        ocrDailyCount = 0
        ocrDate = ""
        importText = ""
        importPreview = nil
        importStatusMessage = "All data has been deleted."
        syncReminderNotification()
    }

    func reviewCurrent(as result: ReviewResult) {
        guard let card = reviewQueue.first, let index = cards.firstIndex(where: { $0.id == card.id }) else { return }

        switch result {
        case .again:
            cards[index].strength = max(1, cards[index].strength - 1)
            cards[index].due = "Today 10:30 PM"
            recordReviewActivity(completedIncrement: 0)
        case .hard:
            cards[index].strength = min(5, cards[index].strength + 1)
            cards[index].due = "Tomorrow 7:00 AM"
            recordReviewActivity(completedIncrement: 1)
        case .good:
            cards[index].strength = min(5, cards[index].strength + 2)
            cards[index].due = "In 2 days"
            recordReviewActivity(completedIncrement: 1)
        }

        cards[index].updatedAt = .now
        persistState()
    }

    func updateReminder(_ newValue: String) {
        reminder = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        persistState()
    }

    func updateGoal(_ newValue: String) {
        goal = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        persistState()
    }

    func updateProfile(
        goal: String,
        reminder: String,
        defaultDeck: String
    ) {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReminder = reminder.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDefaultDeck = defaultDeck.trimmingCharacters(in: .whitespacesAndNewlines)

        self.goal = trimmedGoal
        self.reminder = trimmedReminder
        self.defaultDeck = trimmedDefaultDeck
        persistState()
    }

    private func apply(snapshot: AppSnapshot) {
        cards = snapshot.cards
        reviewActivity = snapshot.reviewActivity
        reminder = snapshot.reminder
        goal = snapshot.goal
        defaultDeck = snapshot.defaultDeck
        ocrDailyCount = snapshot.ocrDailyCount
        ocrDate = snapshot.ocrDate
    }

    private func normalizeSnapshot(_ snapshot: AppSnapshot) -> AppSnapshot {
        AppSnapshot(
            cards: snapshot.cards.map(normalizeCard(_:)),
            reviewActivity: snapshot.reviewActivity,
            reminder: translateLegacyCopy(snapshot.reminder) ?? snapshot.reminder,
            goal: translateLegacyCopy(snapshot.goal) ?? snapshot.goal,
            defaultDeck: translateLegacyCopy(snapshot.defaultDeck) ?? snapshot.defaultDeck
        )
    }

    private func normalizeCard(_ card: Flashcard) -> Flashcard {
        var normalized = card
        normalized.subject = translateLegacyCopy(card.subject) ?? card.subject
        normalized.deck = translateLegacyCopy(card.deck) ?? card.deck
        normalized.tag = translateLegacyCopy(card.tag) ?? card.tag
        normalized.source = translateLegacyCopy(card.source) ?? card.source
        normalized.due = translateLegacyCopy(card.due) ?? card.due

        switch card.prompt {
        case "\u{5F62}\u{6210}\u{6027}\u{8BC4}\u{4EF7}\u{6700}\u{6838}\u{5FC3}\u{7684}\u{4F5C}\u{7528}\u{662F}\u{4EC0}\u{4E48}\u{FF1F}":
            normalized.subject = "Education"
            normalized.prompt = "What is the core role of formative assessment?"
            normalized.choices = ["Used for ranking", "Helps adjust learning", "Replaces exams", "Increases homework volume"]
            normalized.answer = "Helps adjust learning"
            normalized.deck = "Teaching Credential"
            normalized.tag = "Concept confusion"
            normalized.source = "Photo Import"
        case "\u{9605}\u{8BFB}\u{4E2D}\u{9047}\u{5230}\u{8F6C}\u{6298}\u{8BCD} however \u{65F6}\u{FF0C}\u{4F18}\u{5148}\u{5173}\u{6CE8}\u{54EA}\u{90E8}\u{5206}\u{4FE1}\u{606F}\u{FF1F}":
            normalized.subject = "English"
            normalized.prompt = "After \"however,\" which idea should you prioritize first?"
            normalized.choices = ["The idea before the transition", "The idea after the transition", "Opening context", "Closing detail"]
            normalized.answer = "The idea after the transition"
            normalized.deck = "English Reading Set"
            normalized.tag = "Reading precision"
            normalized.source = "Library Import"
        case "\u{6781}\u{503C}\u{9898}\u{5224}\u{5B9A}\u{533A}\u{95F4}\u{7AEF}\u{70B9}\u{65F6}\u{6700}\u{5E38}\u{6F0F}\u{6389}\u{4EC0}\u{4E48}\u{FF1F}":
            normalized.subject = "Math"
            normalized.prompt = "What is most often missed when checking interval endpoints in an extrema problem?"
            normalized.choices = ["The domain", "Monotonic intervals", "Derivative signs", "Graph opening"]
            normalized.answer = "The domain"
            normalized.deck = "Functions & Extrema"
            normalized.tag = "Calculation slip"
            normalized.source = "Manual Entry"
        default:
            break
        }

        return normalized
    }

    private func translateLegacyCopy(_ value: String) -> String? {
        let map: [String: String] = [
            "\u{6559}\u{80B2}\u{5B66}": "Education",
            "\u{82F1}\u{8BED}\u{4E8C}": "English",
            "\u{6570}\u{5B66}": "Math",
            "\u{6559}\u{5E08}\u{8D44}\u{683C}\u{8BC1}": "Teaching Credential",
            "\u{82F1}\u{8BED}\u{4E8C}\u{9605}\u{8BFB}": "English Reading Set",
            "\u{51FD}\u{6570}\u{6781}\u{503C}": "Functions & Extrema",
            "\u{6982}\u{5FF5}\u{6DF7}\u{6DC6}": "Concept confusion",
            "\u{5BA1}\u{9898}\u{504F}\u{5DEE}": "Reading precision",
            "\u{8BA1}\u{7B97}\u{5931}\u{8BEF}": "Calculation slip",
            "\u{8BB0}\u{5FC6}\u{65AD}\u{70B9}": "Memory gap",
            "\u{62CD}\u{7167}\u{5BFC}\u{5165}": "Photo Import",
            "\u{9898}\u{5E93}\u{5BFC}\u{5165}": "Library Import",
            "\u{624B}\u{52A8}\u{5F55}\u{5165}": "Manual Entry",
            "\u{76F8}\u{518C}\u{5BFC}\u{5165}": "Photo Library Import",
            "\u{6BCF}\u{5929} 19:30": "Every day 7:30 PM",
            "\u{4ECA}\u{5929} 19:30": "Today 7:30 PM",
            "\u{4ECA}\u{5929} 21:00": "Today 9:00 PM",
            "\u{660E}\u{5929} 07:20": "Tomorrow 7:20 AM",
            "2026 \u{6559}\u{5E08}\u{8D44}\u{683C}\u{8BC1}\u{7B14}\u{8BD5}": "2026 Teaching Credential Exam"
        ]
        return map[value]
    }

    private func applyImportDraft(_ draft: FlashcardDraft, successMessage: String) {
        importPreview = draft
        importStatusMessage = draft.isAnswerPending ? "Prompt parsed. Confirm the correct answer before saving." : successMessage
    }

    private func normalizedImportDraft(_ draft: FlashcardDraft) -> FlashcardDraft {
        var normalized = draft
        let trimmedDefaultDeck = defaultDeck.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.deck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.deck = fallbackDeckName
        } else if normalized.subject == "Fresh Import", !trimmedDefaultDeck.isEmpty {
            normalized.deck = trimmedDefaultDeck
        }

        return normalized
    }

    private func persistState() {
        repository.saveSnapshot(
            AppSnapshot(
                cards: cards,
                reviewActivity: reviewActivity,
                reminder: reminder,
                goal: goal,
                defaultDeck: defaultDeck,
                ocrDailyCount: ocrDailyCount,
                ocrDate: ocrDate
            )
        )
        syncReminderNotification()
    }

    private func syncReminderNotification() {
        let reminder = reminder
        let reviewCount = reviewQueue.count
        let goal = goal

        Task {
            await ReminderNotificationScheduler.shared.sync(
                reminder: reminder,
                reviewCount: reviewCount,
                goal: goal
            )
        }
    }

    private var fallbackDeckName: String {
        let trimmedDefaultDeck = defaultDeck.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDefaultDeck.isEmpty ? "Untitled Deck" : trimmedDefaultDeck
    }

    private func recordReviewActivity(completedIncrement: Int) {
        let todayKey = Self.dayKey(from: .now)

        if let index = reviewActivity.firstIndex(where: { $0.dayKey == todayKey }) {
            reviewActivity[index].completedCount += completedIncrement
        } else {
            reviewActivity.append(
                DailyReviewActivity(
                    dayKey: todayKey,
                    completedCount: max(0, completedIncrement)
                )
            )
        }

        reviewActivity.sort { $0.dayKey > $1.dayKey }

        if reviewActivity.count > 90 {
            reviewActivity = Array(reviewActivity.prefix(90))
        }
    }

    private static func dayKey(from date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let seedSnapshot = AppSnapshot(
        cards: [
            Flashcard(
                subject: "Education",
                prompt: "What is the core role of formative assessment?",
                choices: ["Used for ranking", "Helps adjust learning", "Replaces exams", "Increases homework volume"],
                answer: "Helps adjust learning",
                due: "Today 7:30 PM",
                deck: "Teaching Credential",
                tag: "Concept confusion",
                source: "Photo Import",
                strength: 2
            ),
            Flashcard(
                subject: "English",
                prompt: "After \"however,\" which idea should you prioritize first?",
                choices: ["The idea before the transition", "The idea after the transition", "Opening context", "Closing detail"],
                answer: "The idea after the transition",
                due: "Today 9:00 PM",
                deck: "English Reading Set",
                tag: "Reading precision",
                source: "Library Import",
                strength: 3
            ),
            Flashcard(
                subject: "Math",
                prompt: "What is most often missed when checking interval endpoints in an extrema problem?",
                choices: ["The domain", "Monotonic intervals", "Derivative signs", "Graph opening"],
                answer: "The domain",
                due: "Tomorrow 7:20 AM",
                deck: "Functions & Extrema",
                tag: "Calculation slip",
                source: "Manual Entry",
                strength: 1
            )
        ],
        reviewActivity: [
            DailyReviewActivity(dayKey: dayKey(from: .now), completedCount: 2),
            DailyReviewActivity(dayKey: dayKey(from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now), completedCount: 3),
            DailyReviewActivity(dayKey: dayKey(from: Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now), completedCount: 1)
        ],
        reminder: "Every day 7:30 PM",
        goal: "",
        defaultDeck: ""
    )
}
