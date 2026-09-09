import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: SocketServer?
    private let panels = PanelManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Paths.ensureSupportDir()

        panels.onCardClick = { [weak self] in
            self?.clickCard()
        }

        let server = SocketServer(path: Paths.socketPath)
        server.onMessage = { [weak self] text in
            DispatchQueue.main.async {
                self?.handle(text)
            }
        }
        do {
            try server.start()
        } catch {
            NSLog("focus-hud: failed to start socket server: %@", "\(error)")
        }
        self.server = server

        observeFrontmostApp()
    }

    /// 事件驱动：前台 App 变为 Finder（含「显示桌面」）→ 隐藏遮罩；回到其它 App → 恢复（iTerm 仍失焦时）。
    private func observeFrontmostApp() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            switch bundleID {
            case "com.apple.finder":
                self?.panels.suspendForDesktop()
            case "com.googlecode.iterm2":
                break
            default:
                self?.panels.resumeFromDesktop()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panels.hide()
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONDecoder().decode(ControlMessage.self, from: data) else { return }
        switch msg.cmd {
        case "show":
            panels.show(frames: msg.frames ?? [])
        case "hide":
            panels.hide()
        default:
            break
        }
    }

    private func clickCard() {
        panels.hide()
        if let iterm = NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first {
            iterm.activate(options: [.activateAllWindows])
        }
    }
}
