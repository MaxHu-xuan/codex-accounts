import Foundation
import XCTest
@testable import CodexAccounts

final class ResetCreditsTests: XCTestCase {
    private func snapshot(_ json: String) throws -> QuotaSnapshot {
        SnapshotParser.parse(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    func testAuthoritativeCountSurvivesOmittedOrTruncatedDetails() throws {
        for details in ["null", "[]", #"[{"id":"fixture-credit","status":"available"}]"#] {
            let value = try snapshot("""
            {"rateLimitResetCredits":{"availableCount":3,"credits":\(details)}}
            """)
            XCTAssertEqual(value.resetCreditsRemaining, 3)
        }
        XCTAssertEqual(try snapshot(#"{"rateLimitResetCredits":{"availableCount":2}}"#).resetCreditsRemaining, 2)
    }

    func testMissingAndInvalidCountsDoNotBecomeZero() throws {
        for json in [
            #"{}"#,
            #"{"rateLimitResetCredits":null}"#,
            #"{"rateLimitResetCredits":{}}"#,
            #"{"rateLimitResetCredits":{"availableCount":null}}"#,
            #"{"rateLimitResetCredits":{"availableCount":-1}}"#,
            #"{"rateLimitResetCredits":{"availableCount":1.5}}"#,
            #"{"rateLimitResetCredits":{"availableCount":"3"}}"#,
            #"{"rateLimitResetCredits":{"availableCount":true}}"#,
            #"{"rateLimitResetCredits":{"availableCount":1e30}}"#,
            #"{"rateLimitResetCredits":{"credits":[{"status":"available"}]}}"#
        ] {
            XCTAssertNil(try snapshot(json).resetCreditsRemaining, json)
        }
        XCTAssertEqual(try snapshot(#"{"rateLimitResetCredits":{"availableCount":0}}"#).resetCreditsRemaining, 0)
    }

    func testResetCountIsIndependentOfPaidCreditsAndQuotaBuckets() throws {
        let value = try snapshot(#"""
        {
          "rateLimits":{"credits":{"balance":"999"},"rateLimitResetCredits":{"availableCount":99}},
          "rateLimitsByLimitId":{
            "codex":{"secondary":{"usedPercent":100},"credits":{"balance":"25"}},
            "review":{"rateLimitResetCredits":{"availableCount":8}}
          },
          "rateLimitResetCredits":{"availableCount":2}
        }
        """#)
        XCTAssertEqual(value.resetCreditsRemaining, 2)
        XCTAssertEqual(value.credits, "25")
        XCTAssertEqual(value.quotas.first?.remainingPercent, 0)
        XCTAssertNil(try snapshot(#"{"rateLimits":{"credits":{"balance":"8"}}}"#).resetCreditsRemaining)
    }

    func testOldSavedAccountLoadsWithoutCountAndNewCountPersists() throws {
        let oldAccount = #"""
        {"id":"11111111-1111-4111-8111-111111111111","label":"Test",
         "email":"test@example.invalid","plan":"pro","needsLogin":false,"quotas":[]}
        """#
        var account = try JSONDecoder().decode(AccountRecord.self, from: Data(oldAccount.utf8))
        XCTAssertNil(account.resetCreditsRemaining)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(root: root)
        for count: Int? in [3, 0, nil] {
            account.resetCreditsRemaining = count
            var state = SavedState()
            state.accounts = [account]
            try store.save(state)
            let loaded = try XCTUnwrap(store.load().accounts.first)
            XCTAssertEqual(loaded, account)
        }
    }
}
