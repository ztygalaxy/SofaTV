import AppKit

@MainActor private final class SidebarState: NSObject {
    var collapsed = true
    var changes = 0
    @objc func toggle() { collapsed.toggle(); changes += 1 }
}

@main struct SidebarToggleButtonChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let button = SidebarToggleButton()
        button.frame = NSRect(x: 0, y: 100, width: 28, height: 56)
        window.contentView!.addSubview(button)
        let sidebar = SidebarState()
        button.target = sidebar
        button.action = #selector(SidebarState.toggle)
        var tracking: [Bool] = []
        button.onTrackingChanged = { tracking.append($0) }
        func event(_ type: NSEvent.EventType, inside: Bool = true) -> NSEvent {
            let point = inside ? NSPoint(x: 14, y: 128) : NSPoint(x: 100, y: 128)
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        button.mouseDown(with: event(.leftMouseDown))
        precondition(sidebar.changes == 0)
        button.mouseUp(with: event(.leftMouseUp))
        precondition(sidebar.changes == 1 && !sidebar.collapsed && tracking == [true, false])

        // Auto-hiding the playback control must leave the channel list expanded.
        button.isHidden = true
        button.mouseUp(with: event(.leftMouseUp))
        precondition(sidebar.changes == 1 && !sidebar.collapsed)
        button.isHidden = false
        button.mouseDown(with: event(.leftMouseDown))
        button.mouseDragged(with: event(.leftMouseDragged, inside: false))
        button.mouseUp(with: event(.leftMouseUp, inside: false))
        precondition(sidebar.changes == 1 && !sidebar.collapsed)

        button.mouseDown(with: event(.leftMouseDown))
        button.isHidden = true
        button.mouseUp(with: event(.leftMouseUp))
        precondition(sidebar.changes == 1 && !sidebar.collapsed)

        button.isHidden = false
        button.performClick(nil)
        precondition(sidebar.changes == 2 && sidebar.collapsed)
        button.mouseDown(with: event(.leftMouseDown))
        button.removeFromSuperview()
        button.mouseUp(with: event(.leftMouseUp))
        precondition(sidebar.changes == 2 && tracking.count == 8)
        withExtendedLifetime(window) {}
        print("Sidebar button passed: one change per click, no delayed action on auto-hide, drag cancellation, detach, and accessibility click")
    }
}
