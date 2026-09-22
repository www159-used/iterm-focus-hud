import AppKit

@main
struct HUDContentViewTests {
    static func main() {
        let view = HUDContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                      location: NSPoint(x: 400, y: 300),
                                      modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil,
                                      eventNumber: 1, clickCount: 1, pressure: 1)!
        var clicks = 0
        view.onCardClick = { clicks += 1 }
        // AppKit asks this before delivering a click to an inactive window.
        guard view.acceptsFirstMouse(for: event) else {
            print("FAIL: inactive overlay rejects the first click")
            exit(1)
        }
        view.mouseDown(with: event)
        guard clicks == 1 else {
            print("FAIL: first click did not invoke activation callback")
            exit(1)
        }
        print("PASS: inactive overlay accepts first click and invokes callback")
    }
}
