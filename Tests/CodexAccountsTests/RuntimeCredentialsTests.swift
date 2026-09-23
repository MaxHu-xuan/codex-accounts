import Foundation
import XCTest
@testable import CodexAccounts

final class RuntimeCredentialsTests: XCTestCase {
    private let original = Data(#"{"fixture":"original"}"#.utf8)
    private let refreshed = Data(#"{"fixture":"refreshed"}"#.utf8)

    private func withHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAccountsRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    private func install(_ data: Data, in home: URL) throws {
        try data.write(to: home.appendingPathComponent("auth.json"))
    }

    func testUnchangedCredentialsSkipWriting() throws {
        try withHome { home in
            try install(original, in: home)
            var writes = 0
            XCTAssertFalse(try RuntimeCredentials.persist(from: home, comparedTo: original) { _ in writes += 1 })
            XCTAssertEqual(writes, 0)
        }
    }

    func testChangedCredentialsAreWrittenOnce() throws {
        try withHome { home in
            try install(refreshed, in: home)
            var saved: [Data] = []
            XCTAssertTrue(try RuntimeCredentials.persist(from: home, comparedTo: original) { saved.append($0) })
            XCTAssertEqual(saved, [refreshed])
        }
    }

    func testMissingOptionalCredentialsSkipWriting() throws {
        try withHome { home in
            var writes = 0
            XCTAssertNil(try RuntimeCredentials.load(from: home))
            XCTAssertFalse(try RuntimeCredentials.persist(from: home, comparedTo: original) { _ in writes += 1 })
            XCTAssertEqual(writes, 0)
        }
    }

    func testMissingRequiredCredentialsThrowWithoutWriting() throws {
        try withHome { home in
            var writes = 0
            XCTAssertThrowsError(try RuntimeCredentials.load(from: home, required: true))
            XCTAssertThrowsError(try RuntimeCredentials.persist(from: home, comparedTo: nil, required: true) { _ in writes += 1 })
            XCTAssertEqual(writes, 0)
        }
    }

    func testMalformedOrNonObjectCredentialsThrowWithoutWriting() throws {
        try withHome { home in
            var writes = 0
            for text in ["not json", "[]", "null", "42", "\"text\""] {
                try install(Data(text.utf8), in: home)
                XCTAssertThrowsError(try RuntimeCredentials.persist(from: home, comparedTo: nil) { _ in writes += 1 })
            }
            XCTAssertEqual(writes, 0)
        }
    }

    func testSaveFailurePreservesRecoveryFile() throws {
        enum SaveFailure: Error { case unavailable }
        try withHome { home in
            try install(refreshed, in: home)
            var writes = 0
            XCTAssertThrowsError(try RuntimeCredentials.persist(from: home, comparedTo: original) { _ in
                writes += 1
                throw SaveFailure.unavailable
            })
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent("auth.json")), refreshed)
        }
    }

    func testCredentialRotationCanBeSavedAfterQuotaFailure() throws {
        enum QuotaFailure: Error { case unavailable }
        try withHome { home in
            try install(original, in: home)
            let baseline = try RuntimeCredentials.load(from: home)
            // The session may rotate credentials before its quota request fails.
            do {
                try install(refreshed, in: home)
                throw QuotaFailure.unavailable
            } catch QuotaFailure.unavailable { }
            var saved: [Data] = []
            XCTAssertTrue(try RuntimeCredentials.persist(from: home, comparedTo: baseline) { saved.append($0) })
            XCTAssertEqual(saved, [refreshed])
        }
    }

    func testValidReadRestrictsFilePermissions() throws {
        try withHome { home in
            let file = home.appendingPathComponent("auth.json")
            try install(original, in: home)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            XCTAssertEqual(try RuntimeCredentials.load(from: home), original)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testSymlinkIsRejectedWithoutChangingTarget() throws {
        try withHome { home in
            let target = home.appendingPathComponent("fixture.json")
            try original.write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
            try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("auth.json"), withDestinationURL: target)
            XCTAssertThrowsError(try RuntimeCredentials.load(from: home))
            XCTAssertEqual(try Data(contentsOf: target), original)
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o644)
        }
    }
}
