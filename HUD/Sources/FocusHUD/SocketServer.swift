import Foundation

/// 监听 unix socket，收到的新行 JSON 逐个回调（调用方自行决定线程）。
final class SocketServer {
    private let path: String
    var onMessage: ((String) -> Void)?

    private var serverFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "focus-hud.accept")
    private let readQueue = DispatchQueue(label: "focus-hud.read", attributes: .concurrent)
    private var running = false

    init(path: String) {
        self.path = path
    }

    func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        pathBytes.withUnsafeBufferPointer { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: UInt8.self, capacity: pathBytes.count) { dstBuf in
                    dstBuf.update(from: src.baseAddress!, count: pathBytes.count)
                }
            }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.offset(of: \.sun_path)! + pathBytes.count)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addrLen) }
        }
        guard bindResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard listen(fd, 8) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

        running = true
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        running = false
        if serverFD >= 0 { close(serverFD) }
        serverFD = -1
    }

    private func acceptLoop() {
        while running {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { continue }
            readQueue.async { [weak self] in self?.readLoop(clientFD) }
        }
    }

    private func readLoop(_ fd: Int32) {
        var buffer = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            buffer.append(contentsOf: buf[0..<n])
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let text = String(data: line, encoding: .utf8), !text.isEmpty {
                    onMessage?(text)
                }
            }
        }
        close(fd)
    }
}

/// 一次性客户端：把 payload（自动补 \n）写到 socket 后退出。
func sendOnce(payload: String, to path: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return 1 }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return 1 }
    pathBytes.withUnsafeBufferPointer { src in
        withUnsafeMutablePointer(to: &addr.sun_path) { dst in
            dst.withMemoryRebound(to: UInt8.self, capacity: pathBytes.count) { dstBuf in
                dstBuf.update(from: src.baseAddress!, count: pathBytes.count)
            }
        }
    }
    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.offset(of: \.sun_path)! + pathBytes.count)
    let connectResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, addrLen) }
    }
    guard connectResult == 0 else { return 1 }

    let data = (payload + "\n").data(using: .utf8) ?? Data()
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        _ = write(fd, raw.baseAddress, raw.count)
    }
    return 0
}
