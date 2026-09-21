import AppKit
import CoreGraphics

/// 独立窗口遮罩：应用内切换时浅色压暗，所有失焦窗口显示统一提示卡。
final class HUDContentView: NSView {
    var onCardClick: (() -> Void)?

    var subtle = false

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(subtle ? 0.18 : 0.35).setFill()
        bounds.fill()

        let card = cardFrame()
        let path = NSBezierPath(roundedRect: card, xRadius: 16, yRadius: 16)
        NSColor(calibratedWhite: 0.10, alpha: 0.92).setFill()
        path.fill()

        let title = "iTerm 已失焦" as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let titleSize = title.size(withAttributes: titleAttrs)

        let subtitle = "点击任意处返回" as NSString
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let subSize = subtitle.size(withAttributes: subAttrs)

        let total = titleSize.height + 10 + subSize.height
        let y0 = card.midY + total / 2
        title.draw(at: NSPoint(x: card.midX - titleSize.width / 2, y: y0 - titleSize.height), withAttributes: titleAttrs)
        subtitle.draw(at: NSPoint(x: card.midX - subSize.width / 2, y: y0 - titleSize.height - 10 - subSize.height), withAttributes: subAttrs)
    }

    /// 整块遮罩可点击：点击 iTerm 窗口任意位置即回焦。
    override func mouseDown(with event: NSEvent) {
        onCardClick?()
    }

    private func cardFrame() -> NSRect {
        NSRect(x: bounds.midX - 160, y: bounds.midY - 80, width: 320, height: 160)
    }
}

/// 管理当前显示的一组遮罩 panel。
final class PanelManager {
    var onCardClick: ((String?) -> Void)?
    private var windows: [WindowOverlay] = []
    private var subtle = false
    private var renderedWindows: [WindowOverlay] = []
    private var renderedNumbers: [Int] = []
    private var renderedSubtle = false
    private var panels: [NSPanel] = []
    private var active = false
    private var suspended = false
    private var resumeTimer: Timer?

    func show(windows: [WindowOverlay], subtle: Bool) {
        self.windows = windows
        self.subtle = subtle
        active = true
        // 显示桌面时 iTerm 失焦的 show 会晚到：若此刻前台是 Finder（显示桌面中），先挂起不显示
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
            enterSuspend()
        } else {
            leaveSuspend()
            displayCurrentITermWindows()
        }
    }

    func hide() {
        active = false
        leaveSuspend()
        destroyPanels()
    }

    /// 显示桌面 / 前台变为 Finder 时：隐藏遮罩，等 iTerm 窗口回到屏上再自动恢复。
    func suspendForDesktop() {
        guard active else { return }
        enterSuspend()
    }

    /// 回到其它 App：用当前在屏的 iTerm 窗口恢复遮罩。
    func resumeFromDesktop() {
        guard active, suspended else { return }
        leaveSuspend()
        displayCurrentITermWindows()
    }

    private func enterSuspend() {
        guard !suspended else { return }
        suspended = true
        destroyPanels()
        startResumeTimer()
    }

    private func leaveSuspend() {
        stopResumeTimer()
        suspended = false
    }

    /// 挂起期间每秒检查：iTerm 窗口回到屏上（显示桌面已恢复）→ 自动恢复遮罩。
    private func checkResume() {
        guard active, suspended else { return }
        let iterms = itermWindowNumbers()
        guard !iterms.isEmpty else { return }
        leaveSuspend()
        displayCurrentITermWindows()
    }

    private func startResumeTimer() {
        stopResumeTimer()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkResume()
        }
        RunLoop.main.add(t, forMode: .common)
        resumeTimer = t
    }

    private func stopResumeTimer() {
        resumeTimer?.invalidate()
        resumeTimer = nil
    }

    private func displayCurrentITermWindows() {
        display(windows)
    }

    private func display(_ windows: [WindowOverlay]) {
        let visible = itermWindowNumbers()
        let matches: [(WindowOverlay, NSRect, Int)] = windows.compactMap { window in
            let f = window.frame
            guard f.count == 4 else { return nil }
            let rect = NSRect(x: f[0], y: f[1], width: f[2], height: f[3])
            // Geometry alone cannot distinguish perfectly overlapping windows.
            // Skip ambiguous matches instead of shading/activating the wrong one.
            let candidates = visible.filter { $0.rect.equalTo(rect) }
            guard candidates.count == 1, let target = candidates.first else { return nil }
            return (window, rect, target.number)
        }
        let nextWindows = matches.map { $0.0 }
        let nextNumbers = matches.map { $0.2 }
        guard nextWindows != renderedWindows || nextNumbers != renderedNumbers || subtle != renderedSubtle else { return }
        destroyPanels()
        renderedWindows = nextWindows
        renderedNumbers = nextNumbers
        renderedSubtle = subtle
        for (window, rect, number) in matches {
            panels.append(makePanel(rect: rect, aboveWindow: number, windowID: window.windowID))
        }
    }

    private func destroyPanels() {
        for p in panels {
            p.orderOut(nil)
            p.close()
        }
        panels.removeAll()
        renderedWindows = []
        renderedNumbers = []
    }

    /// 当前在屏上的 iTerm 窗口（层 0）的 AppKit 矩形 + 全局窗口号。
    private func itermWindowNumbers() -> [(rect: NSRect, number: Int)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let anchor = NSScreen.screens.first(where: { $0.frame.minY == 0 })?.frame.maxY
            ?? NSScreen.screens.first?.frame.maxY ?? 0
        return list.compactMap { w -> (NSRect, Int)? in
            guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "iTerm2",
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let num = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let x = b["X"] ?? 0, y = b["Y"] ?? 0, width = b["Width"] ?? 0, height = b["Height"] ?? 0
            guard width > 0, height > 0 else { return nil }
            return (NSRect(x: x, y: anchor - (y + height), width: width, height: height), num)
        }
    }

    private func makePanel(rect: NSRect, aboveWindow: Int?, windowID: String?) -> NSPanel {
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let content = HUDContentView(frame: rect.offsetBy(dx: -rect.minX, dy: -rect.minY))
        content.subtle = subtle
        content.onCardClick = { [weak self] in self?.onCardClick?(windowID) }
        panel.contentView = content
        if let num = aboveWindow {
            panel.order(.above, relativeTo: num)
        } else {
            panel.orderFrontRegardless()
        }
        return panel
    }
}
