import AppKit

let args = CommandLine.arguments

if args.count >= 2, args[1] == "send" {
    let payload = args.dropFirst(2).joined(separator: " ")
    exit(sendOnce(payload: payload, to: Paths.socketPath))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
