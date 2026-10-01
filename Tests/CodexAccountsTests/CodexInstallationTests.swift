import Foundation
import XCTest
@testable import CodexAccounts

final class CodexInstallationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func fixture(_ relativePath: String, executable: Bool = true) throws -> URL {
        let path = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture, never executed".utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: path.path)
        return path.resolvingSymlinksInPath()
    }

    func testDesktopUpdateFromLegacyToNestedCLIIsRediscovered() throws {
        let app = root.appendingPathComponent("ChatGPT.app")
        let old = try fixture("ChatGPT.app/Contents/Resources/codex")
        XCTAssertEqual(try CodexInstallation.binary(applications: [app], standalone: []), old)
        try FileManager.default.removeItem(at: old)
        let new = try fixture("ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        XCTAssertEqual(try CodexInstallation.binary(applications: [app], standalone: []), new)
    }

    func testRegisteredAppCanLiveAtACustomLocationAndPrefersPackageEntrypoint() throws {
        let app = root.appendingPathComponent("Custom/Named Desktop.app")
        _ = try fixture("Custom/Named Desktop.app/Contents/Resources/codex")
        let modern = try fixture("Custom/Named Desktop.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        XCTAssertEqual(try CodexInstallation.binary(applications: [app], standalone: []), modern)
        let entrypoint = try fixture("Custom/Named Desktop.app/Contents/Resources/codex-cli/bin/codex")
        XCTAssertEqual(try CodexInstallation.binary(applications: [app], standalone: []), entrypoint)
    }

    func testUnusableAppPathsFallBackToStandaloneSymlink() throws {
        let app = root.appendingPathComponent("Codex.app")
        _ = try fixture("Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", executable: false)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources/codex"), withIntermediateDirectories: true)
        let cli = try fixture("cli/codex")
        let link = root.appendingPathComponent("codex-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cli)
        XCTAssertEqual(try CodexInstallation.binary(applications: [app], standalone: [link]), cli)
    }

    func testMissingInstallationReportsActionableError() {
        XCTAssertThrowsError(try CodexInstallation.binary(applications: [root.appendingPathComponent("missing.app")], standalone: [])) {
            XCTAssertTrue($0.localizedDescription.contains("未找到可用的 Codex"))
        }
    }
}
