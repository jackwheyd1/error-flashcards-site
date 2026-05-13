import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class LocalDatabase {
    private var db: OpaquePointer?
    private let path: String

    init(filename: String = "error_flashcards.sqlite") {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directoryURL = baseURL.appendingPathComponent("ErrorFlashcardsIOS", isDirectory: true)

        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        path = directoryURL.appendingPathComponent(filename).path

        do {
            try openIfNeeded()
        } catch {
            assertionFailure("Failed to open database: \(error)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func loadSnapshot(seed: AppSnapshot) -> AppSnapshot {
        do {
            try openIfNeeded()

            let storedCards = try fetchCards()
            let storedReviewActivity = try reviewActivitySetting()
            return AppSnapshot(
                cards: storedCards.isEmpty ? seed.cards : storedCards,
                reviewActivity: storedReviewActivity ?? (storedCards.isEmpty ? seed.reviewActivity : []),
                reminder: try stringSetting(for: "reminder") ?? seed.reminder,
                goal: try stringSetting(for: "goal") ?? seed.goal,
                defaultDeck: try stringSetting(for: "defaultDeck") ?? seed.defaultDeck,
                ocrDailyCount: try intSetting(for: "ocrDailyCount") ?? seed.ocrDailyCount,
                ocrDate: try stringSetting(for: "ocrDate") ?? seed.ocrDate
            )
        } catch {
            return seed
        }
    }

    func saveSnapshot(_ snapshot: AppSnapshot) {
        do {
            try openIfNeeded()
            try execute(sql: "BEGIN IMMEDIATE TRANSACTION")
            try execute(sql: "DELETE FROM cards")

            let insertCardSQL = """
            INSERT INTO cards (
                id, subject, prompt, choices_json, answer, due, deck, tag, source, strength, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertCardSQL, -1, &statement, nil) == SQLITE_OK else {
                throw databaseError()
            }
            defer { sqlite3_finalize(statement) }

            let encoder = JSONEncoder()

            for card in snapshot.cards {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)

                bind(card.id.uuidString, to: statement, at: 1)
                bind(card.subject, to: statement, at: 2)
                bind(card.prompt, to: statement, at: 3)
                bind(String(data: try encoder.encode(card.choices), encoding: .utf8) ?? "[]", to: statement, at: 4)
                bind(card.answer, to: statement, at: 5)
                bind(card.due, to: statement, at: 6)
                bind(card.deck, to: statement, at: 7)
                bind(card.tag, to: statement, at: 8)
                bind(card.source, to: statement, at: 9)
                sqlite3_bind_int(statement, 10, Int32(card.strength))
                sqlite3_bind_double(statement, 11, card.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 12, card.updatedAt.timeIntervalSince1970)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw databaseError()
                }
            }

            try upsertSetting(key: "reviewActivity", value: String(data: try encoder.encode(snapshot.reviewActivity), encoding: .utf8) ?? "[]")
            try upsertSetting(key: "reminder", value: snapshot.reminder)
            try upsertSetting(key: "goal", value: snapshot.goal)
            try upsertSetting(key: "defaultDeck", value: snapshot.defaultDeck)
            try upsertSetting(key: "ocrDailyCount", value: String(snapshot.ocrDailyCount))
            try upsertSetting(key: "ocrDate", value: snapshot.ocrDate)
            try execute(sql: "COMMIT")
        } catch {
            try? execute(sql: "ROLLBACK")
        }
    }

    private func openIfNeeded() throws {
        guard db == nil else { return }

        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            throw databaseError(handle)
        }

        db = handle
        try createTables()
    }

    private func createTables() throws {
        try execute(sql: """
        CREATE TABLE IF NOT EXISTS cards (
            id TEXT PRIMARY KEY,
            subject TEXT NOT NULL,
            prompt TEXT NOT NULL,
            choices_json TEXT NOT NULL,
            answer TEXT NOT NULL,
            due TEXT NOT NULL,
            deck TEXT NOT NULL,
            tag TEXT NOT NULL,
            source TEXT NOT NULL,
            strength INTEGER NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
    }

    private func fetchCards() throws -> [Flashcard] {
        let sql = """
        SELECT id, subject, prompt, choices_json, answer, due, deck, tag, source, strength, created_at, updated_at
        FROM cards
        ORDER BY created_at DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }

        let decoder = JSONDecoder()
        var cards: [Flashcard] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let choicesText = string(from: statement, index: 3)
            let choiceData = Data(choicesText.utf8)
            let choices = (try? decoder.decode([String].self, from: choiceData)) ?? []

            cards.append(
                Flashcard(
                    id: UUID(uuidString: string(from: statement, index: 0)) ?? UUID(),
                    subject: string(from: statement, index: 1),
                    prompt: string(from: statement, index: 2),
                    choices: choices,
                    answer: string(from: statement, index: 4),
                    due: string(from: statement, index: 5),
                    deck: string(from: statement, index: 6),
                    tag: string(from: statement, index: 7),
                    source: string(from: statement, index: 8),
                    strength: Int(sqlite3_column_int(statement, 9)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11))
                )
            )
        }

        return cards
    }

    private func stringSetting(for key: String) throws -> String? {
        try setting(for: key)
    }

    private func intSetting(for key: String) throws -> Int? {
        guard let value = try setting(for: key) else { return nil }
        return Int(value)
    }

    private func reviewActivitySetting() throws -> [DailyReviewActivity]? {
        guard let value = try setting(for: "reviewActivity") else { return nil }
        return try? JSONDecoder().decode([DailyReviewActivity].self, from: Data(value.utf8))
    }

    private func setting(for key: String) throws -> String? {
        let sql = "SELECT value FROM settings WHERE key = ? LIMIT 1"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }

        bind(key, to: statement, at: 1)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return string(from: statement, index: 0)
    }

    private func upsertSetting(key: String, value: String) throws {
        let sql = """
        INSERT INTO settings (key, value)
        VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }

        bind(key, to: statement, at: 1)
        bind(value, to: statement, at: 2)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    private func execute(sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw databaseError()
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func string(from statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    func deleteAllData() {
        do {
            try openIfNeeded()
            try execute(sql: "BEGIN IMMEDIATE TRANSACTION")
            try execute(sql: "DELETE FROM cards")
            try execute(sql: "DELETE FROM settings")
            try execute(sql: "COMMIT")
        } catch {
            try? execute(sql: "ROLLBACK")
        }
    }

    private func databaseError(_ handle: OpaquePointer? = nil) -> NSError {
        let activeHandle = handle ?? db
        let message = activeHandle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
        return NSError(domain: "LocalDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
