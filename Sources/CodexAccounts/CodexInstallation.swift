import Foundation

enum CodexInstallation {
    /// New desktop releases embed a signed CLI app; older releases store a
    /// standalone executable directly in Resources. Check both on every refresh
    /// so an in-place desktop update does not leave a cached, missing path.
    static func binary(applications: [URL], standalone: [URL], fileManager: FileManager = .default) throws -> URL {
        let layouts = [
            "Contents/Resources/codex-cli/bin/codex",
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex"
        ]
        let candidates = applications.flatMap { app in layouts.map { app.appendingPathComponent($0) } } + standalone
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath()
            guard fileManager.isExecutableFile(atPath: resolved.path),
                  (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            return resolved
        }
        throw ManagerError.message("未找到可用的 Codex。请先安装或更新 Codex 桌面版或 Codex CLI。")
    }
}
