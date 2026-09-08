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
