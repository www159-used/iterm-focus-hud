import AppKit
import CoreGraphics

/// 半透明遮罩：整窗深色压暗，正中一张卡片，卡片可点击回焦，遮罩区域点击穿透。
final class HUDContentView: NSView {
    var onCardClick: (() -> Void)?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
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
    var onCardClick: (() -> Void)?
    private var panels: [NSPanel] = []

    func show(frames: [[Double]]) {
        hide()
        let itermWindows = itermWindowNumbers()
        for f in frames where f.count >= 4 {
            let rect = NSRect(x: f[0], y: f[1], width: f[2], height: f[3])
            guard rect.width > 0, rect.height > 0 else { continue }
            // 遮罩排在对应 iTerm 窗口正上方（普通层级）：
            // 盖住 iTerm 本身；叠在其上的其它窗口仍在更高 z-order，永不被挡，也无需实时更新。
            let above = itermWindows.first { $0.rect.equalTo(rect) }?.number
            panels.append(makePanel(rect: rect, aboveWindow: above))
        }
    }

    func hide() {
        for p in panels {
            p.orderOut(nil)
            p.close()
        }
        panels.removeAll()
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

    private func makePanel(rect: NSRect, aboveWindow: Int?) -> NSPanel {
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let content = HUDContentView(frame: rect.offsetBy(dx: -rect.minX, dy: -rect.minY))
        content.onCardClick = onCardClick
        panel.contentView = content
        if let num = aboveWindow {
            panel.order(.above, relativeTo: num)
        } else {
            panel.orderFrontRegardless()
        }
        return panel
    }
}
