// Clicks the mouse at a screen point (origin top left, as in the window bounds windows.swift lists):
//   click <x> <y> [clicks]      e.g. click 700 90 2 = double-click
// Needs the Accessibility permission (granted to bash on GitHub's macOS runners).
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
    print("usage: click <x> <y> [clicks]")
    exit(2)
}
let clicks = args.count > 3 ? max(1, Int(args[3]) ?? 1) : 1
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
    .post(tap: .cghidEventTap)
usleep(200_000)
for n in 1...clicks {
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                                  mouseButton: .left) else { exit(1) }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(n))
        event.post(tap: .cghidEventTap)
        usleep(30_000)
    }
    usleep(80_000)
}
