import AppKit

@main struct AppWindowsChecks {
    @MainActor static func main() {
        _ = NSApplication.shared

        func makeAlert() -> NSAlert {
            let alert = NSAlert()
            alert.messageText = "确认操作"
            alert.addButton(withTitle: "确认")
            alert.addButton(withTitle: "取消")
            return alert
        }

        // Construct off-screen native windows without entering a modal session.
        // Verify button actions explicitly, since NSAlert's default actions
        // expect runModal/beginSheetModal and cannot be reused modelessly.
        for index in 0..<2 {
            let alert = makeAlert()
            var responses: [NSApplication.ModalResponse] = []
            var closed = 0
            let controller = AppWindowController(alert: alert) { responses.append($0) }
            controller.onClose = { closed += 1 }
            precondition(NSApp.modalWindow == nil && alert.window.sheetParent == nil)
            alert.buttons[index].performClick(nil)
            precondition(responses == [NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index)])
            precondition(closed == 1)
            alert.buttons[index].performClick(nil)
            precondition(responses.count == 1 && closed == 1, "A response must run only once")
        }

        let alert = makeAlert()
        var confirmed = false
        let controller = AppWindowController(alert: alert) { _ in confirmed = true }
        controller.close()
        alert.buttons[0].performClick(nil)
        precondition(!confirmed, "Closing a confirmation must not accept it")
        precondition(NSApp.modalWindow == nil)
        print("Independent window checks passed: no modal session, confirm/cancel routing, single response, close without confirmation")
    }
}
