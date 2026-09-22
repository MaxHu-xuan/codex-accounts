import Foundation
import XCTest
@testable import CodexAccounts

final class SnapshotParserTests: XCTestCase {
    private func snapshot(_ json: String) throws -> QuotaSnapshot {
        SnapshotParser.parse(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    func testWeeklyOnlyAccountDoesNotInventFiveHourWindow() throws {
        let value = try snapshot(#"""
        {"rateLimitsByLimitId":{"codex":{"planType":"pro","primary":null,"secondary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1790000000}}}}
        """#)
        XCTAssertEqual(value.plan, "pro")
        XCTAssertEqual(value.quotas.count, 1)
        let weekly = try XCTUnwrap(value.quotas.first)
        XCTAssertEqual(weekly.id, "codex:secondary")
        XCTAssertEqual(weekly.windowMinutes, 10080)
        XCTAssertEqual(weekly.remainingPercent, 96)
        XCTAssertTrue(weekly.name.contains("每周"))
        XCTAssertFalse(value.quotas.contains { $0.windowMinutes == 300 })
    }

    func testModernBucketsArePreferredAndAllBucketsArePreserved() throws {
        let value = try snapshot(#"""
        {
          "rateLimits":{"limitId":"obsolete","primary":{"usedPercent":99}},
          "rateLimitsByLimitId":{
            "review":{"limitName":"Review","primary":{"usedPercent":20,"windowDurationMins":1440}},
            "codex":{"planType":"plus","primary":{"usedPercent":5,"windowDurationMins":300},"secondary":{"usedPercent":10,"windowDurationMins":10080}},
            "additional":{"primary":{"usedPercent":30,"windowDurationMins":45}}
          }
        }
        """#)
        XCTAssertEqual(value.quotas.map(\.id), ["codex:primary", "codex:secondary", "additional:primary", "review:primary"])
        XCTAssertEqual(value.quotas.map(\.remainingPercent), [95, 90, 70, 80])
        XCTAssertEqual(value.plan, "plus")
        XCTAssertFalse(value.quotas.contains { $0.id.hasPrefix("obsolete:") })
    }

    func testEmptyOrNullModernMapFallsBackToLegacyBucket() throws {
        for modernMap in ["{}", "null"] {
            let json = """
            {"rateLimitsByLimitId":\(modernMap),"rateLimits":{"limitId":"codex","primary":{"usedPercent":0,"windowDurationMins":300},"credits":{"unlimited":false,"balance":"0"}}}
            """
            let value = try snapshot(json)
            XCTAssertEqual(value.quotas.count, 1)
            XCTAssertEqual(value.quotas.first?.remainingPercent, 100)
            XCTAssertEqual(value.credits, "0")
        }
    }

    func testLegacyBucketWithoutLimitIDUsesCodex() throws {
        let value = try snapshot(#"{"rateLimits":{"secondary":{"usedPercent":12,"windowDurationMins":10080}}}"#)
        XCTAssertEqual(value.quotas.first?.id, "codex:secondary")
    }

    func testMissingAndNullUsageAreUnknownWhileZeroIsARealQuota() throws {
        for json in [
            #"{}"#,
            #"{"rateLimits":null}"#,
            #"{"rateLimits":{"primary":null,"secondary":{"usedPercent":null}}}"#,
            #"{"rateLimits":{"primary":{"windowDurationMins":300}}}"#
        ] {
            XCTAssertTrue(try snapshot(json).quotas.isEmpty)
        }
        let zero = try snapshot(#"{"rateLimits":{"primary":{"usedPercent":0}}}"#)
        XCTAssertEqual(zero.quotas.count, 1)
        XCTAssertEqual(zero.quotas.first?.remainingPercent, 100)
        XCTAssertNil(zero.quotas.first?.windowMinutes)
        XCTAssertNil(zero.quotas.first?.resetsAt)
    }

    func testUnknownCreditsRemainDistinctFromZeroAndUnlimited() throws {
        for credits in ["null", "{}", #"{"balance":null,"unlimited":false}"#] {
            let json = """
            {"rateLimits":{"credits":\(credits)}}
            """
            XCTAssertNil(try snapshot(json).credits)
        }
        XCTAssertNil(try snapshot(#"{"rateLimits":{}}"#).credits)
        XCTAssertEqual(try snapshot(#"{"rateLimits":{"credits":{"balance":"0","unlimited":false}}}"#).credits, "0")
        XCTAssertEqual(try snapshot(#"{"rateLimits":{"credits":{"balance":"0","unlimited":true}}}"#).credits, "不限量")
    }

    func testCreditsAreNotBorrowedFromAnotherLimitBucket() throws {
        let value = try snapshot(#"""
        {"rateLimitsByLimitId":{"review":{"credits":{"balance":"900"}},"codex":{"credits":null}}}
        """#)
        XCTAssertNil(value.credits)
    }

    func testRemainingPercentIsClampedWithoutDiscardingReportedUsage() throws {
        let value = try snapshot(#"""
        {"rateLimits":{"primary":{"usedPercent":-5},"secondary":{"usedPercent":150}}}
        """#)
        XCTAssertEqual(value.quotas.map(\.usedPercent), [-5, 150])
        XCTAssertEqual(value.quotas.map(\.remainingPercent), [100, 0])
    }

    func testPastResetDoesNotFabricateRecoveredQuota() throws {
        let value = try snapshot(#"""
        {"rateLimits":{"secondary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1}}}
        """#)
        let quota = try XCTUnwrap(value.quotas.first)
        XCTAssertEqual(quota.resetsAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(quota.usedPercent, 100)
        XCTAssertEqual(quota.remainingPercent, 0)
    }
}

final class AccountPresentationTests: XCTestCase {
    private func account(plan: String = "pro", quotas: [QuotaRecord] = []) -> AccountRecord {
        AccountRecord(id: UUID(), label: "测试账号", email: "test@example.invalid", plan: plan, serverAccountID: nil, updatedAt: nil, lastError: nil, needsLogin: false, quotas: quotas, credits: nil)
    }

    private func quota(_ id: String, minutes: Int, used: Double) -> QuotaRecord {
        QuotaRecord(id: id, name: id, usedPercent: used, windowMinutes: minutes, resetsAt: nil)
    }

    func testSavedAccountsFromPreviousVersionDecodeWithoutNewFields() throws {
        let previousState = #"""
        {
          "version":1,
          "dailyHour":9,
          "automaticAttempts":{"11111111-1111-4111-8111-111111111111":1},
          "lastAttemptAt":{"11111111-1111-4111-8111-111111111111":100},
          "accounts":[
            {
              "id":"11111111-1111-4111-8111-111111111111",
              "label":"工作",
              "email":"work@example.invalid",
              "plan":"pro",
              "serverAccountID":"fixture-work",
              "updatedAt":100,
              "lastError":"上次连接失败",
              "needsLogin":false,
              "quotas":[{"id":"codex:secondary","name":"Codex · 每周","usedPercent":4,"windowMinutes":10080,"resetsAt":200}],
              "credits":"0"
            },
            {
              "id":"22222222-2222-4222-8222-222222222222",
              "label":"个人",
              "email":"personal@example.invalid",
              "plan":"prolite",
              "needsLogin":true,
              "quotas":[]
            }
          ]
        }
        """#
        let decoded = try JSONDecoder().decode(SavedState.self, from: Data(previousState.utf8))
        XCTAssertEqual(decoded.accounts.count, 2)
        let work = decoded.accounts[0]
        XCTAssertEqual(work.id.uuidString, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(work.label, "工作")
        XCTAssertEqual(work.email, "work@example.invalid")
        XCTAssertEqual(work.plan, "pro")
        XCTAssertEqual(work.serverAccountID, "fixture-work")
        XCTAssertEqual(work.updatedAt, Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertEqual(work.lastError, "上次连接失败")
        XCTAssertFalse(work.needsLogin)
        XCTAssertEqual(work.quotas.first?.remainingPercent, 96)
        XCTAssertEqual(work.quotas.first?.resetsAt, Date(timeIntervalSinceReferenceDate: 200))
        XCTAssertEqual(work.credits, "0")
        XCTAssertEqual(decoded.accounts[1].email, "personal@example.invalid")
        XCTAssertEqual(decoded.accounts[1].plan, "prolite")
        XCTAssertTrue(decoded.accounts[1].needsLogin)
        XCTAssertEqual(decoded.automaticAttempts[work.id.uuidString], 1)
        XCTAssertEqual(decoded.lastAttemptAt[work.id.uuidString], Date(timeIntervalSinceReferenceDate: 100))
        for item in decoded.accounts {
            XCTAssertNil(item.planOverride)
            XCTAssertNil(item.subscriptionExpiresAt)
            XCTAssertNil(item.subscriptionExpirySource)
        }
    }

    func testProLabelsPreserveServicePlanAndRespectRecognizedTiers() {
        for (raw, label) in [("pro", "Pro20X"), ("prolite", "Pro5X"), ("PRO", "Pro20X"), ("plus", "Plus"), ("free", "Free"), ("unknown", "未识别"), ("business", "business")] {
            let value = account(plan: raw)
            XCTAssertEqual(value.displayPlan, label)
            XCTAssertEqual(value.plan, raw, "A display label must not replace the service's plan identifier.")
        }
    }

    func testOnlySupportedPlanOverridesChangeTheDisplayLabel() {
        var value = account(plan: "pro")
        for supported in ["Pro20X", "Pro5X"] {
            value.planOverride = supported
            XCTAssertEqual(value.displayPlan, supported)
            XCTAssertEqual(value.plan, "pro")
        }
        for unsupported in ["", "Pro100X", "pro5x", " Pro5X ", "Plus"] {
            value.planOverride = unsupported
            XCTAssertEqual(value.displayPlan, "Pro20X")
        }
        value.planOverride = nil
        XCTAssertEqual(value.displayPlan, "Pro20X")
    }

    func testSummaryPrefersOrdinaryCodexWeeklyOverPrimaryOrReserveAllowance() {
        let reserve = quota("codex-reserve:secondary", minutes: 10080, used: 0)
        let primary = quota("codex:primary", minutes: 300, used: 7)
        let weekly = quota("codex:secondary", minutes: 10080, used: 42)
        let value = account(quotas: [reserve, primary, weekly])
        XCTAssertEqual(value.summaryQuota, weekly)
        XCTAssertEqual(value.summaryQuota?.remainingPercent, 58)
    }

    func testSummaryFallsBackToOrdinaryPrimaryAndNeverUsesReserveAlone() {
        let reserve = quota("codex-reserve:secondary", minutes: 10080, used: 0)
        let secondary = quota("codex:secondary", minutes: 1440, used: 55)
        let primary = quota("codex:primary", minutes: 300, used: 25)
        XCTAssertEqual(account(quotas: [reserve, secondary, primary]).summaryQuota, primary)
        XCTAssertEqual(account(quotas: [reserve, secondary]).summaryQuota, secondary)
        XCTAssertNil(account(quotas: [reserve]).summaryQuota)
        XCTAssertNil(account(quotas: []).summaryQuota)
    }
}

final class DailyPolicyTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Hong_Kong") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    func testFirstFetchIsDueEvenBeforeDailyHour() {
        XCTAssertTrue(DailyPolicy.needsRefresh(updatedAt: nil, now: date("2026-09-21T08:00:00+08:00"), hour: 9, calendar: calendar()))
    }

    func testSameDaySuccessPreventsRepeatedAutomaticRefresh() {
        let updated = date("2026-09-21T08:00:00+08:00")
        for now in ["2026-09-21T08:30:00+08:00", "2026-09-21T09:00:00+08:00", "2026-09-21T23:59:00+08:00"] {
            XCTAssertFalse(DailyPolicy.needsRefresh(updatedAt: updated, now: date(now), hour: 9, calendar: calendar()))
        }
    }

    func testYesterdaySuccessWaitsUntilTodayAtNine() {
        let updated = date("2026-09-20T10:00:00+08:00")
        XCTAssertFalse(DailyPolicy.needsRefresh(updatedAt: updated, now: date("2026-09-21T08:59:59+08:00"), hour: 9, calendar: calendar()))
        XCTAssertTrue(DailyPolicy.needsRefresh(updatedAt: updated, now: date("2026-09-21T09:00:00+08:00"), hour: 9, calendar: calendar()))
    }

    func testMissedDaysCatchUpBeforeNineAndThenStop() {
        let now = date("2026-09-21T07:00:00+08:00")
        XCTAssertTrue(DailyPolicy.needsRefresh(updatedAt: date("2026-09-18T10:00:00+08:00"), now: now, hour: 9, calendar: calendar()))
        XCTAssertFalse(DailyPolicy.needsRefresh(updatedAt: now, now: date("2026-09-21T09:00:00+08:00"), hour: 9, calendar: calendar()))
    }

    func testBeforeNineCatchupUsesPreviousScheduledDeadline() {
        let now = date("2026-09-21T08:00:00+08:00")
        XCTAssertTrue(DailyPolicy.needsRefresh(updatedAt: date("2026-09-20T08:59:59+08:00"), now: now, hour: 9, calendar: calendar()))
        XCTAssertFalse(DailyPolicy.needsRefresh(updatedAt: date("2026-09-20T09:00:00+08:00"), now: now, hour: 9, calendar: calendar()))
    }

    func testCalendarTimezoneDefinesDayAndRefreshBoundary() {
        let instant = date("2026-09-21T01:00:00Z")
        let lastSuccess = date("2026-09-20T08:00:00Z")
        XCTAssertEqual(DailyPolicy.dayKey(instant, calendar: calendar()), "2026-9-21")
        XCTAssertEqual(DailyPolicy.dayKey(instant, calendar: calendar("America/Los_Angeles")), "2026-9-20")
        XCTAssertTrue(DailyPolicy.needsRefresh(updatedAt: lastSuccess, now: instant, hour: 9, calendar: calendar()))
        XCTAssertFalse(DailyPolicy.needsRefresh(updatedAt: lastSuccess, now: instant, hour: 9, calendar: calendar("America/Los_Angeles")))
    }

    func testNextDateStaysAtLocalNineAcrossDaylightSavingChange() {
        let ny = calendar("America/New_York")
        let beforeDST = date("2026-03-07T10:00:00-05:00")
        XCTAssertEqual(DailyPolicy.nextDate(after: beforeDST, hour: 9, calendar: ny), date("2026-03-08T09:00:00-04:00"))
    }

    func testNextDateIsTodayBeforeNineAndTomorrowAtNine() {
        XCTAssertEqual(DailyPolicy.nextDate(after: date("2026-09-21T08:59:59+08:00"), hour: 9, calendar: calendar()), date("2026-09-21T09:00:00+08:00"))
        XCTAssertEqual(DailyPolicy.nextDate(after: date("2026-09-21T09:00:00+08:00"), hour: 9, calendar: calendar()), date("2026-09-22T09:00:00+08:00"))
    }
}

final class LocalStoreTests: XCTestCase {
    private func withStore(_ body: (LocalStore) throws -> Void) throws {
        let ownedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("CodexAccountsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: ownedRoot) }
        try body(LocalStore(root: ownedRoot))
    }

    func testNewStoreHasEmptyStateAndDailyNineDefault() throws {
        try withStore { store in
            let state = try store.load()
            XCTAssertTrue(state.accounts.isEmpty)
            XCTAssertEqual(state.dailyHour, 9)
            XCTAssertTrue(state.automaticAttempts.isEmpty)
        }
    }

    func testMetadataRoundTripPreservesUnknownValuesAndRetryState() throws {
        try withStore { store in
            let id = UUID()
            let updatedAt = Date(timeIntervalSince1970: 1_790_000_000)
            let account = AccountRecord(id: id, label: "工作账号", email: "test@example.invalid", plan: "pro", serverAccountID: "fixture-account", updatedAt: updatedAt, lastError: "连接失败", needsLogin: false, quotas: [QuotaRecord(id: "codex:secondary", name: "Codex · 每周", usedPercent: 4, windowMinutes: 10080, resetsAt: nil)], credits: nil)
            var state = SavedState()
            state.accounts = [account]
            state.dailyHour = 11
            state.automaticAttempts = [id.uuidString: 1]
            state.lastAttemptAt = [id.uuidString: updatedAt]
            try store.save(state)
            let loaded = try store.load()
            XCTAssertEqual(loaded.accounts, [account])
            XCTAssertEqual(loaded.dailyHour, 11)
            XCTAssertEqual(loaded.automaticAttempts, state.automaticAttempts)
            XCTAssertEqual(loaded.lastAttemptAt, state.lastAttemptAt)

            let data = try Data(contentsOf: store.stateURL)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(json.keys), Set(["version", "accounts", "dailyHour", "automaticAttempts", "lastAttemptAt"]))
            let accountJSON = try XCTUnwrap((json["accounts"] as? [[String: Any]])?.first)
            let metadataKeys: Set<String> = ["id", "label", "email", "plan", "serverAccountID", "updatedAt", "lastError", "needsLogin", "quotas", "credits", "planOverride", "subscriptionExpiresAt", "subscriptionExpirySource"]
            XCTAssertTrue(Set(accountJSON.keys).isSubset(of: metadataKeys), "State stores account metadata only; authentication belongs in the vault.")
            for forbidden in ["access_token", "refresh_token", "id_token", "accessToken", "refreshToken", "apiKey", "OPENAI_API_KEY"] {
                XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"\(forbidden)\""))
            }
        }
    }

    func testStateAndAccountDirectoriesArePrivateAndSeparate() throws {
        try withStore { store in
            let first = try store.home(for: UUID())
            let second = try store.home(for: UUID())
            XCTAssertNotEqual(first, second)
            XCTAssertEqual(first.deletingLastPathComponent(), store.runtimes)
            try store.save(SavedState())
            for directory in [store.root, store.runtimes, first, second] {
                let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
                XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: store.stateURL.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testMalformedExistingStateIsReportedInsteadOfSilentlyDiscarded() throws {
        try withStore { store in
            try Data("{corrupt".utf8).write(to: store.stateURL)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try String(contentsOf: store.stateURL, encoding: .utf8), "{corrupt")
        }
    }

    func testCleanupRemovesOnlyUnregisteredAccountRuntimes() throws {
        try withStore { store in
            let knownID = UUID()
            let knownHome = try store.home(for: knownID)
            let abandonedHome = try store.home(for: UUID())
            let unrelatedEntry = store.runtimes.appendingPathComponent("runtime-notes.txt")
            let knownMarker = knownHome.appendingPathComponent("recovery-marker.txt")
            let abandonedMarker = abandonedHome.appendingPathComponent("abandoned-marker.txt")
            try Data("preserve account recovery data".utf8).write(to: knownMarker)
            try Data("abandoned login fixture".utf8).write(to: abandonedMarker)
            try Data("unrelated content".utf8).write(to: unrelatedEntry)

            try store.discardUnregisteredRuntimes(knownIDs: [knownID])

            XCTAssertTrue(FileManager.default.fileExists(atPath: knownHome.path))
            XCTAssertEqual(try String(contentsOf: knownMarker, encoding: .utf8), "preserve account recovery data")
            XCTAssertFalse(FileManager.default.fileExists(atPath: abandonedHome.path))
            XCTAssertEqual(try String(contentsOf: unrelatedEntry, encoding: .utf8), "unrelated content")
        }
    }

    func testManualExpiryAndTierCorrectionRoundTripWithoutInventingMissingExpiry() throws {
        try withStore { store in
            var manual = AccountRecord(id: UUID(), label: "手动记录", email: "manual@example.invalid", plan: "pro", serverAccountID: nil, updatedAt: nil, lastError: nil, needsLogin: false, quotas: [], credits: nil)
            let expiry = Date(timeIntervalSince1970: 1_800_000_000)
            manual.planOverride = "Pro5X"
            manual.subscriptionExpiresAt = expiry
            manual.subscriptionExpirySource = "manual"
            let unknown = AccountRecord(id: UUID(), label: "未记录日期", email: "unknown@example.invalid", plan: "prolite", serverAccountID: nil, updatedAt: nil, lastError: nil, needsLogin: false, quotas: [], credits: nil)
            var state = SavedState()
            state.accounts = [manual, unknown]

            try store.save(state)
            let loaded = try store.load()

            XCTAssertEqual(loaded.accounts, [manual, unknown])
            XCTAssertEqual(loaded.accounts[0].subscriptionExpiresAt, expiry)
            XCTAssertEqual(loaded.accounts[0].subscriptionExpirySource, "manual")
            XCTAssertEqual(loaded.accounts[0].plan, "pro")
            XCTAssertEqual(loaded.accounts[0].displayPlan, "Pro5X")
            XCTAssertNil(loaded.accounts[1].planOverride)
            XCTAssertNil(loaded.accounts[1].subscriptionExpiresAt)
            XCTAssertNil(loaded.accounts[1].subscriptionExpirySource)
        }
    }
}
