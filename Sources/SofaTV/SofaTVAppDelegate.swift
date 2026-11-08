import AppKit

@MainActor final class SofaTVAppDelegate: NSObject, NSApplicationDelegate {
    private var updatingMenuBar = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let reminders = ProgramReminderStore.shared
        reminders.onWatch = { reminder in
            let library = Library.shared
            guard let channel = library.channels.first(where: { reminder.matches($0) }) else {
                AppWindows.shared.showMessage("频道暂不可用", detail: "这个频道可能已被移除，请重新导入频道列表。")
                return true
            }
            library.play(channel)
            return true
        }
        reminders.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
            DockIconController.shared.configure(baseIcon: image)
            DockIconController.shared.reset()
        }
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(menuBarDidChange(_:)), name: name, object: nil)
        }
        DispatchQueue.main.async { [weak self] in self?.configureMenuBar() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configureMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DockIconController.shared.reset()
    }

    @objc private func menuBarDidChange(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu, menu === NSApplication.shared.mainMenu else { return }
        configureMenuBar()
    }

    private func configureMenuBar() {
        guard !updatingMenuBar, let menu = NSApplication.shared.mainMenu else { return }
        updatingMenuBar = true
        defer { updatingMenuBar = false }
        for item in menu.items where ["文件", "编辑", "显示", "File", "Edit", "View"].contains(item.title) {
            // Keep standard text shortcuts available in search/address fields while hiding these menus.
            allowHiddenShortcuts(item)
            if !item.isHidden { item.isHidden = true }
        }
    }

    private func allowHiddenShortcuts(_ item: NSMenuItem) {
        item.allowsKeyEquivalentWhenHidden = true
        for child in item.submenu?.items ?? [] { allowHiddenShortcuts(child) }
    }
}
