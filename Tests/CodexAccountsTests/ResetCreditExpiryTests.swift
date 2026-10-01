import Foundation
import XCTest
@testable import CodexAccounts

final class ResetCreditExpiryTests: XCTestCase {
    private func snapshot(_ json: String) throws -> QuotaSnapshot {
        SnapshotParser.parse(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    private func credit(_ id: String, expiresAt: String? = "null",
                        status: String = "available", resetType: String = "codexRateLimits") -> String {
        let expiry = expiresAt.map { ",\"expiresAt\":\($0)" } ?? ""
        return """
        {"id":"\(id)","status":"\(status)","resetType":"\(resetType)","grantedAt":1700000000\(expiry)}
        """
    }

    private func snapshot(count: Int, cards: [String]) throws -> QuotaSnapshot {
        try snapshot("""
        {"rateLimitResetCredits":{"availableCount":\(count),"credits":[\(cards.joined(separator: ","))]}}
        """)
    }

    func testUnsortedCardsChooseEarliestExpiryAndPreserveCount() throws {
        let value = try snapshot(count: 4, cards: [
            credit("later", expiresAt: "1900000000"),
            credit("never"),
            credit("earliest", expiresAt: "1800000000"),
            credit("middle", expiresAt: "1850000000")
        ])
        let expiry = try XCTUnwrap(value.resetCreditExpiry)
        XCTAssertEqual(expiry.earliestExpiresAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertTrue(expiry.detailsComplete)
        XCTAssertEqual(value.resetCreditsRemaining, 4)
    }

    func testOnlyAvailableCodexCardsContributeToExpiryAndCompleteness() throws {
        let value = try snapshot(count: 2, cards: [
            credit("redeemed", expiresAt: "100", status: "redeemed"),
            credit("redeeming", expiresAt: "200", status: "redeeming"),
            credit("unknown", expiresAt: "300", status: "unknown"),
            credit("other-limit", expiresAt: "400", resetType: "otherLimit"),
            credit("later", expiresAt: "1900000000"),
            credit("earliest", expiresAt: "1800000000")
        ])
        let expiry = try XCTUnwrap(value.resetCreditExpiry)
        XCTAssertEqual(expiry.earliestExpiresAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertTrue(expiry.detailsComplete)
        XCTAssertEqual(value.resetCreditsRemaining, 2)
    }

    func testDuplicateIDsDoNotMakeTruncatedDetailsComplete() throws {
        let card = credit("same-card", expiresAt: "1800000000")
        let value = try snapshot(count: 2, cards: [card, card])
        let expiry = try XCTUnwrap(value.resetCreditExpiry)
        XCTAssertEqual(expiry.earliestExpiresAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertFalse(expiry.detailsComplete)
        XCTAssertEqual(value.resetCreditsRemaining, 2)
    }

    func testDuplicateRowsDoNotHideCompleteUniqueCards() throws {
        let repeated = credit("first", expiresAt: "1800000000")
        let value = try snapshot(count: 2, cards: [
            repeated,
            credit("second", expiresAt: "1900000000"),
            repeated
        ])
        let expiry = try XCTUnwrap(value.resetCreditExpiry)
        XCTAssertEqual(expiry.earliestExpiresAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertTrue(expiry.detailsComplete)
        XCTAssertEqual(value.resetCreditsRemaining, 2)
    }

    func testExplicitNullExpiresAtMeansNoExpiryWhenDetailsAreComplete() throws {
        let value = try snapshot(count: 2, cards: [credit("first"), credit("second")])
        let expiry = try XCTUnwrap(value.resetCreditExpiry)
        XCTAssertNil(expiry.earliestExpiresAt)
        XCTAssertTrue(expiry.detailsComplete)
        XCTAssertEqual(value.resetCreditsRemaining, 2)
    }

    func testMissingExpiryIsUnknownInsteadOfNonExpiring() throws {
        let value = try snapshot(count: 2, cards: [
            credit("known", expiresAt: "1800000000"),
            credit("missing-expiry", expiresAt: nil)
        ])
        let expiry = try XCTUnwrap(value.resetCreditExpiry)
        XCTAssertEqual(expiry.earliestExpiresAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertFalse(expiry.detailsComplete)
        XCTAssertEqual(value.resetCreditsRemaining, 2)
    }

    func testNoKnownExpiryFieldsRemainUnknown() throws {
        let value = try snapshot(count: 1, cards: [credit("missing-expiry", expiresAt: nil)])
        XCTAssertNil(value.resetCreditExpiry)
        XCTAssertEqual(value.resetCreditsRemaining, 1)
    }

    func testMissingOrEmptyIDsCannotSupplyDatesOrFillMissingDetails() throws {
        let value = try snapshot(count: 2, cards: [
            #"{"status":"available","resetType":"codexRateLimits","expiresAt":1}"#,
            credit("", expiresAt: "2"),
            credit("known", expiresAt: "1800000000")
        ])
        let expiry = try XCTUnwrap(value.resetCreditExpiry)
        XCTAssertEqual(expiry.earliestExpiresAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertFalse(expiry.detailsComplete)
        XCTAssertEqual(value.resetCreditsRemaining, 2)
    }

    func testMalformedTimestampsCannotCreateAnExpiryOrCompleteDetails() throws {
        for timestamp in ["0", "-1", "1.5", "true", #""1800000000""#, "{}", "[]", "1e30",
                          "253402300800", "1800000000000"] {
            let value = try snapshot(count: 2, cards: [
                credit("invalid", expiresAt: timestamp),
                credit("known", expiresAt: "1800000000")
            ])
            let expiry = try XCTUnwrap(value.resetCreditExpiry, timestamp)
            XCTAssertEqual(expiry.earliestExpiresAt, Date(timeIntervalSince1970: 1800000000), timestamp)
            XCTAssertFalse(expiry.detailsComplete, timestamp)
            XCTAssertEqual(value.resetCreditsRemaining, 2, timestamp)
        }
    }

    func testTruncatedDetailsKeepKnownDateWithoutClaimingCompleteness() throws {
        let value = try snapshot(count: 5, cards: [
            credit("known-later", expiresAt: "1900000000"),
            credit("known-earliest", expiresAt: "1800000000")
        ])
        let expiry = try XCTUnwrap(value.resetCreditExpiry)
        XCTAssertEqual(expiry.earliestExpiresAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertFalse(expiry.detailsComplete)
        XCTAssertEqual(value.resetCreditsRemaining, 5)
    }

    func testPartialNonExpiringDetailsCannotProveAllCardsNeverExpire() throws {
        let value = try snapshot(count: 3, cards: [credit("known-nonexpiring")])
        XCTAssertNil(value.resetCreditExpiry?.earliestExpiresAt)
        XCTAssertNotEqual(value.resetCreditExpiry?.detailsComplete, true)
        XCTAssertEqual(value.resetCreditsRemaining, 3)
    }

    func testExpiredCardDateRemainsVisibleWithoutReducingCount() throws {
        let value = try snapshot(count: 2, cards: [
            credit("already-expired", expiresAt: "1"),
            credit("later", expiresAt: "1900000000")
        ])
        let expiry = try XCTUnwrap(value.resetCreditExpiry)
        XCTAssertEqual(expiry.earliestExpiresAt, Date(timeIntervalSince1970: 1))
        XCTAssertTrue(expiry.detailsComplete)
        XCTAssertEqual(value.resetCreditsRemaining, 2)
    }

    func testMissingSummaryOrUnavailableDetailsHaveNoExpiry() throws {
        for json in [
            #"{}"#,
            #"{"rateLimitResetCredits":null}"#,
            #"{"rateLimitResetCredits":{"availableCount":2}}"#,
            #"{"rateLimitResetCredits":{"availableCount":2,"credits":null}}"#,
            #"{"rateLimitResetCredits":{"availableCount":2,"credits":[]}}"#
        ] {
            XCTAssertNil(try snapshot(json).resetCreditExpiry, json)
        }
    }

    func testZeroOrInvalidCountCannotDeriveAvailabilityFromDetailRows() throws {
        let details = credit("card", expiresAt: "1800000000")
        for count in ["0", "null", "-1", "1.5", #""1""#, "true", "1e30"] {
            let value = try snapshot("""
            {"rateLimitResetCredits":{"availableCount":\(count),"credits":[\(details)]}}
            """)
            XCTAssertNil(value.resetCreditExpiry, count)
            if count == "0" {
                XCTAssertEqual(value.resetCreditsRemaining, 0)
            } else {
                XCTAssertNil(value.resetCreditsRemaining, count)
            }
        }
        let missingCount = try snapshot("""
        {"rateLimitResetCredits":{"credits":[\(details)]}}
        """)
        XCTAssertNil(missingCount.resetCreditExpiry)
        XCTAssertNil(missingCount.resetCreditsRemaining)
    }

    func testOldSavedAccountsLoadWithoutExpiryAndNewStatesRoundTrip() throws {
        let oldAccount = #"""
        {"id":"22222222-2222-4222-8222-222222222222","label":"Expiry fixture",
         "email":"expiry@example.invalid","plan":"pro","needsLogin":false,
         "quotas":[],"resetCreditsRemaining":3}
        """#
        var account = try JSONDecoder().decode(AccountRecord.self, from: Data(oldAccount.utf8))
        XCTAssertNil(account.resetCreditExpiry)
        XCTAssertEqual(account.resetCreditsRemaining, 3)

        let values: [ResetCreditExpiry?] = [
            nil,
            ResetCreditExpiry(earliestExpiresAt: Date(timeIntervalSince1970: 1800000000), detailsComplete: true),
            ResetCreditExpiry(earliestExpiresAt: Date(timeIntervalSince1970: 1800000000), detailsComplete: false),
            ResetCreditExpiry(earliestExpiresAt: nil, detailsComplete: true),
            ResetCreditExpiry(earliestExpiresAt: nil, detailsComplete: false)
        ]
        for expiry in values {
            account.resetCreditExpiry = expiry
            var state = SavedState()
            state.accounts = [account]
            let encoded = try JSONEncoder().encode(state)
            let loaded = try JSONDecoder().decode(SavedState.self, from: encoded)
            XCTAssertEqual(try XCTUnwrap(loaded.accounts.first), account)
        }
    }
}
