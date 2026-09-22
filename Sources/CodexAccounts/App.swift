import AppKit
import SwiftUI

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    static weak var manager: AccountManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "local.codex.accounts")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        Self.manager?.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first(where: { $0.identifier?.rawValue == "accounts" }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.manager?.isBusy == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "请先完成当前操作"
        alert.informativeText = "正在保存登录状态或刷新额度。请等待完成；如果正在登录，可以先点击“取消登录”。"
        alert.addButton(withTitle: "继续等待")
        alert.runModal()
        return .terminateCancel
    }
}

@main
struct CodexAccountsApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var delegate
    @State private var manager: AccountManager

    init() {
        let manager = AccountManager()
        _manager = State(initialValue: manager)
        AppLifecycle.manager = manager
    }

    var body: some Scene {
        Window("Codex 账号管理器", id: "accounts") {
            ManagerWindow(manager: manager)
        }
        .defaultSize(width: 720, height: 540)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加账号") { manager.addAccount() }
                    .keyboardShortcut("n")
            }
        }

        MenuBarExtra {
            MenuContent(manager: manager)
        } label: {
            Image(systemName: "person.crop.circle.badge.clock")
                .accessibilityLabel("Codex 账号管理器")
        }
        .menuBarExtraStyle(.window)
    }
}
