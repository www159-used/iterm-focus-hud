import Foundation

/// 简化版 socket 路径，供 daemon 与 send 客户端共用。
enum Paths {
    static let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/iterm-focus-hud")

    static let socketPath = supportDir.appendingPathComponent("control.sock").path

    static func ensureSupportDir() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }
}

/// unix socket 上新行分隔的 JSON 控制消息。
struct ControlMessage: Decodable {
    let cmd: String
    /// show 时的窗口 frame 列表，每项为 [x, y, width, height]（AppKit 屏幕坐标，左下原点）。
    let frames: [[Double]]?
    let windows: [WindowOverlay]?
    let subtle: Bool?
}

struct WindowOverlay: Decodable, Equatable {
    let windowID: String?
    let frame: [Double]
}
