import AppKit
import SwiftUI
import Testing
@testable import SofaTV

@MainActor @Suite("光标热区与侧边栏拖动", .serialized)
struct PointerInteractionTests {
    private func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat = 50, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    private func window() -> NSWindow {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let value = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 506),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        value.isReleasedWhenClosed = false
        return value
    }

    @Test func backgroundArrowRegionsNeverCoverAControlEvenWhenRegionsOverlap() {
        let bounds = NSRect(x: 0, y: 0, width: 100, height: 80)
        let controls = [NSRect(x: 4, y: 4, width: 32, height: 32), NSRect(x: 28, y: 10, width: 40, height: 30),
                        NSRect(x: 80, y: 50, width: 32, height: 32), NSRect(x: -40, y: -40, width: 10, height: 10)]
        let background = PlaybackCursorRegions.background(in: bounds, excluding: controls)
        for x in 0..<100 {
            for y in 0..<80 {
                let point = NSPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                #expect(background.filter { $0.contains(point) }.count == (controls.contains { $0.contains(point) } ? 0 : 1))
            }
        }
        #expect(PlaybackCursorRegions.background(in: bounds, excluding: [bounds]).isEmpty)
        #expect(PlaybackCursorRegions.background(in: bounds, excluding: []) == [bounds])
    }

    @Test func resizeTargetOwnsItsWholeColumnAndUsesFixedCoordinatesAsItMoves() {
        let window = window(); defer { window.close(); withExtendedLifetime(window) {} }
        let handle = SidebarResizeHandle.Handle()
        handle.frame = NSRect(x: 300, y: 0, width: SidebarResizeHandle.hitWidth, height: 506)
        handle.visibleWidth = 300; handle.minimumWidth = 294; handle.maximumWidth = 500
        window.contentView!.addSubview(handle)
        for offset in 0..<Int(SidebarResizeHandle.hitWidth) {
            #expect(window.contentView!.hitTest(NSPoint(x: 300.5 + Double(offset), y: 50)) === handle)
        }
        #expect(window.contentView!.hitTest(NSPoint(x: 299, y: 50)) !== handle)
        #expect(window.contentView!.hitTest(NSPoint(x: 311, y: 50)) !== handle)
        var widths: [CGFloat] = [], commits = 0
        handle.onChange = { width in
            widths.append(width)
            handle.frame.origin.x = width // Reproduce the layout movement during a drag.
        }
        handle.onCommit = { commits += 1 }
        handle.mouseDown(with: event(.leftMouseDown, x: 305, window: window))
        #expect(!window.areCursorRectsEnabled, "Keep the resize cursor steady even when the drag leaves the column")
        handle.mouseDragged(with: event(.leftMouseDragged, x: 345, window: window))
        handle.mouseDragged(with: event(.leftMouseDragged, x: 355, window: window))
        handle.mouseDragged(with: event(.leftMouseDragged, x: 900, window: window))
        handle.mouseDragged(with: event(.leftMouseDragged, x: 200, window: window))
        #expect(widths == [340, 350, 500, 294], "Moving the separator must not add its own motion to the gesture")
        #expect(commits == 0, "Persist the width once at the end, not on every movement")
        handle.mouseUp(with: event(.leftMouseUp, x: 200, window: window))
        #expect(commits == 1)
        #expect(window.areCursorRectsEnabled)
        handle.mouseDragged(with: event(.leftMouseDragged, x: 400, window: window))
        #expect(handle.visibleWidth == 294)
    }

    @Test func interruptedResizeAndAccessibilityKeepBoundsAndFinishOnce() {
        let window = window(); defer { window.close(); withExtendedLifetime(window) {} }
        let handle = SidebarResizeHandle.Handle(); window.contentView!.addSubview(handle)
        handle.frame = NSRect(x: 300, y: 0, width: 10, height: 506)
        handle.visibleWidth = 300; handle.minimumWidth = 294; handle.maximumWidth = 320
        var commits = 0; handle.onCommit = { commits += 1 }
        handle.mouseDown(with: event(.leftMouseDown, x: 305, window: window))
        handle.mouseDragged(with: event(.leftMouseDragged, x: 315, window: window))
        handle.isHidden = true
        #expect(window.areCursorRectsEnabled, "Hiding the separator must release the drag cursor")
        handle.mouseUp(with: event(.leftMouseUp, x: 400, window: window))
        #expect(handle.visibleWidth == 310 && commits == 1)
        #expect(handle.accessibilityPerformIncrement() && handle.visibleWidth == 320)
        #expect(handle.accessibilityPerformDecrement() && handle.visibleWidth == 300)
        #expect(handle.accessibilityPerformDecrement() && handle.visibleWidth == 294)
        #expect(commits == 4)
        handle.isHidden = false
        handle.mouseDown(with: event(.leftMouseDown, x: 305, window: window))
        #expect(!window.areCursorRectsEnabled)
        window.close()
        #expect(window.areCursorRectsEnabled && commits == 5, "Closing a window mid-drag must not leave a resize cursor behind")
    }

    @Test func buttonsOwnTheirHitTargetsAndStayVisibleWhileHovered() throws {
        let suite = "sofatv-pointer-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let app = Library(defaults: defaults, warmsChannels: false,
                          recoveryMonitor: PlaybackRecoveryMonitor(observeSystemEvents: false, pollsAutomatically: false))
        defer { app.stopPlayback(); defaults.removePersistentDomain(forName: suite) }
        app.selected = Channel(name: "测试", group: "测试", url: URL(string: "https://example.invalid/test")!)
        app.videoVisible = true
        let window = window(); defer { window.close(); withExtendedLifetime(window) {} }
        var location = NSPoint(x: 44, y: 44)
        let stage = VideoStage.Stage(library: app, pointerLocation: { _ in location })
        window.contentView = stage; stage.frame = NSRect(x: 0, y: 0, width: 900, height: 506); stage.layout()
        stage.mouseMoved(with: event(.mouseMoved, x: 44, y: 44, window: window))
        stage.layout()
        let button = stage.previousChannelButton
        #expect(!button.isHidden && !button.isEnabled)
        #expect(stage.hitTest(button.frame.center) === button)
        #expect(stage.pointer.cursorExclusions.contains { $0.contains(button.frame.center) })
        let background = PlaybackCursorRegions.background(in: stage.pointer.bounds, excluding: stage.pointer.cursorExclusions)
        #expect(!background.contains { $0.contains(button.frame.center) })
        stage.perform(NSSelectorFromString("hideIdleControls"))
        #expect(!button.isHidden, "Do not hide a control from underneath a stationary pointer")
        location = NSPoint(x: 450, y: 250)
        stage.mouseMoved(with: event(.mouseMoved, x: 450, y: 250, window: window))
        stage.perform(NSSelectorFromString("hideIdleControls"))
        #expect(button.isHidden && !stage.pointer.cursorExclusions.contains { $0.contains(button.frame.center) })
        location = NSPoint(x: 44, y: 44)
        stage.mouseMoved(with: event(.mouseMoved, x: 44, y: 44, window: window))
        #expect(!button.isHidden && stage.pointer.cursorExclusions.contains { $0.contains(button.frame.center) })
    }

    @Test func dividerOverlayKeepsOriginalLayoutAndHasNoVisibleGutter() async throws {
        let window = window(); defer { window.close(); withExtendedLifetime(window) {} }
        func content(active: Bool) -> some View {
            HStack(spacing: 0) {
                Color(nsColor: .sofaBackground).frame(width: 300)
                SidebarResizeHandle(width: .constant(300), visibleWidth: 300, minimumWidth: 294, maximumWidth: 500, isActive: active)
                    .frame(width: SidebarResizeHandle.dividerWidth, height: 300).zIndex(2)
                Color.black
            }.frame(width: 900, height: 300)
        }
        let host = NSHostingView(rootView: content(active: true))
        host.sizingOptions = []
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 900, height: 300))
        window.contentView = host; window.orderBack(nil)
        for _ in 0..<10 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        func find(_ view: NSView) -> SidebarResizeHandle.Handle? {
            if let handle = view as? SidebarResizeHandle.Handle { return handle }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let handle = try #require(find(host))
        let rect = handle.convert(handle.bounds, to: host)
        #expect(rect.width == SidebarResizeHandle.hitWidth && rect.height == 300)
        #expect(abs(rect.midX - 300.5) < 0.01, "The divider must occupy one layout point, not a wide column")
        for x in [297.5, 300.5, 303.5] {
            #expect(host.hitTest(NSPoint(x: x, y: 100)) === handle, "The transparent overlay must remain draggable")
        }
        func capture(_ name: String) throws -> NSBitmapImageRep {
            handle.displayIfNeeded(); host.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let directory = ProcessInfo.processInfo.environment["SOFATV_DIVIDER_PREVIEW_DIR"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
            }
            return bitmap
        }
        func rgb(_ bitmap: NSBitmapImageRep, _ x: CGFloat) -> [CGFloat] {
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let color = bitmap.colorAt(x: Int(x * scale), y: Int(100 * scale))!.usingColorSpace(.sRGB)!
            return [color.redComponent, color.greenComponent, color.blueComponent]
        }
        let normal = try capture("normal")
        #expect(zip(rgb(normal, 295), rgb(normal, 298)).allSatisfy { abs($0 - $1) < 0.005 })
        #expect(zip(rgb(normal, 303), rgb(normal, 306)).allSatisfy { abs($0 - $1) < 0.005 })
        handle.mouseEntered(with: event(.mouseMoved, x: 300, window: window))
        let hover = try capture("hover")
        #expect(zip(rgb(normal, 299.5), rgb(hover, 299.5)).contains { abs($0 - $1) > 0.01 }, "Hover must thicken the line without changing the layout")
        handle.mouseExited(with: event(.mouseMoved, x: 310, window: window))
        let exited = try capture("exited")
        #expect(zip(rgb(normal, 299.5), rgb(exited, 299.5)).allSatisfy { abs($0 - $1) < 0.005 })
        host.rootView = content(active: false)
        for _ in 0..<5 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        #expect(find(host) == nil, "Collapsing the sidebar must also remove the invisible drag target")
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
