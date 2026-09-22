import Foundation
import XCTest
@testable import CodexAccounts

final class ManualMarkerTests: XCTestCase {
    private func withStore(_ body: @MainActor @escaping (LocalStore) throws -> Void) async throws {
        let ownedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("ManualMarkerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: ownedRoot) }
        let store = try LocalStore(root: ownedRoot)
        try await MainActor.run { try body(store) }
    }

    private func fixtureAccounts() -> [AccountRecord] {
        ["First", "Last"].map { label in
            AccountRecord(id: UUID(), label: label, email: "\(label.lowercased())@example.invalid", plan: "pro", serverAccountID: nil, updatedAt: nil, lastError: nil, needsLogin: false, quotas: [], credits: nil)
        }
    }

    func testLegacyStateDoesNotInferCurrentAccountFromListOrder() async throws {
        try await withStore { store in
            let legacy = #"""
            {
              "version":1,
              "dailyHour":9,
              "automaticAttempts":{},
              "lastAttemptAt":{},
              "accounts":[
                {"id":"11111111-1111-4111-8111-111111111111","label":"First","email":"first@example.invalid","plan":"pro","needsLogin":false,"quotas":[]},
                {"id":"22222222-2222-4222-8222-222222222222","label":"Last","email":"last@example.invalid","plan":"prolite","needsLogin":false,"quotas":[]}
              ]
            }
            """#
            try Data(legacy.utf8).write(to: store.stateURL)

            let manager = AccountManager(storage: store)

            XCTAssertEqual(manager.accounts.map(\.label), ["First", "Last"])
            XCTAssertNil(manager.manualCurrentAccountID)
            XCTAssertNil(manager.manualCurrentConfirmedAt)
            XCTAssertNil(manager.lastError)
            XCTAssertEqual(try Data(contentsOf: store.stateURL), Data(legacy.utf8), "Loading must not infer or persist a current account.")
        }
    }

    func testManualConfirmationPersistsAccountAndActualConfirmationTime() async throws {
        let fixtures = fixtureAccounts()
        try await withStore { store in
            var state = SavedState()
            state.accounts = fixtures
            try store.save(state)
            let manager = AccountManager(storage: store)
            let before = Date()

            manager.markCurrentAccount(fixtures[1].id)

            let after = Date()
            let confirmedAt = try XCTUnwrap(manager.manualCurrentConfirmedAt)
            XCTAssertEqual(manager.manualCurrentAccountID, fixtures[1].id)
            XCTAssertGreaterThanOrEqual(confirmedAt, before)
            XCTAssertLessThanOrEqual(confirmedAt, after)
            let saved = try store.load()
            XCTAssertEqual(saved.manualCurrentAccountID, fixtures[1].id)
            XCTAssertEqual(saved.manualCurrentConfirmedAt, confirmedAt)
            XCTAssertEqual(saved.accounts, fixtures)

            let reloaded = AccountManager(storage: store)
            XCTAssertEqual(reloaded.manualCurrentAccountID, fixtures[1].id)
            XCTAssertEqual(reloaded.manualCurrentConfirmedAt, confirmedAt)
        }
    }

    func testMarkingAnotherAccountReplacesTheSingleManualSelection() async throws {
        let fixtures = fixtureAccounts()
        try await withStore { store in
            var state = SavedState()
            state.accounts = fixtures
            try store.save(state)
            let manager = AccountManager(storage: store)
            manager.markCurrentAccount(fixtures[0].id)
            let firstConfirmation = try XCTUnwrap(manager.manualCurrentConfirmedAt)

            manager.markCurrentAccount(fixtures[1].id)

            XCTAssertEqual(manager.manualCurrentAccountID, fixtures[1].id)
            XCTAssertEqual(manager.accounts.filter { $0.id == manager.manualCurrentAccountID }.count, 1)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(manager.manualCurrentConfirmedAt), firstConfirmation)
            let saved = try store.load()
            XCTAssertEqual(saved.manualCurrentAccountID, fixtures[1].id)
            XCTAssertEqual(saved.accounts, fixtures)
            XCTAssertEqual(AccountManager(storage: store).manualCurrentAccountID, fixtures[1].id)
        }
    }

    func testUnknownAccountDoesNotReplaceAnExistingManualConfirmation() async throws {
        let fixtures = fixtureAccounts()
        try await withStore { store in
            var state = SavedState()
            state.accounts = fixtures
            try store.save(state)
            let manager = AccountManager(storage: store)
            manager.markCurrentAccount(fixtures[0].id)
            let originalTime = manager.manualCurrentConfirmedAt
            let originalData = try Data(contentsOf: store.stateURL)

            manager.markCurrentAccount(UUID())

            XCTAssertEqual(manager.manualCurrentAccountID, fixtures[0].id)
            XCTAssertEqual(manager.manualCurrentConfirmedAt, originalTime)
            XCTAssertEqual(try Data(contentsOf: store.stateURL), originalData)
        }
    }

    func testClearingManualConfirmationPersistsBothFieldsAsAbsent() async throws {
        let fixtures = fixtureAccounts()
        try await withStore { store in
            var state = SavedState()
            state.accounts = fixtures
            state.manualCurrentAccountID = fixtures[0].id
            state.manualCurrentConfirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
            try store.save(state)
            let manager = AccountManager(storage: store)

            manager.clearCurrentAccount()

            XCTAssertNil(manager.manualCurrentAccountID)
            XCTAssertNil(manager.manualCurrentConfirmedAt)
            let saved = try store.load()
            XCTAssertNil(saved.manualCurrentAccountID)
            XCTAssertNil(saved.manualCurrentConfirmedAt)
            XCTAssertEqual(saved.accounts, fixtures)
            let reloaded = AccountManager(storage: store)
            XCTAssertNil(reloaded.manualCurrentAccountID)
            XCTAssertNil(reloaded.manualCurrentConfirmedAt)
        }
    }

    func testOrphanSavedMarkerIsNotExposedOrReassignedOnLoad() async throws {
        let fixtures = fixtureAccounts()
        try await withStore { store in
            var state = SavedState()
            state.accounts = fixtures
            state.manualCurrentAccountID = UUID()
            state.manualCurrentConfirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
            try store.save(state)

            let manager = AccountManager(storage: store)

            XCTAssertEqual(manager.accounts, fixtures)
            XCTAssertNil(manager.manualCurrentAccountID)
            XCTAssertNil(manager.manualCurrentConfirmedAt)
            XCTAssertNil(manager.lastError)
        }
    }
}
