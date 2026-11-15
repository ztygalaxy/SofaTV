import AppKit

@MainActor final class SofaTVAppDelegate: NSObject, NSApplicationDelegate {
    private var updatingMenuBar = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let preference = UserDefaults.standard.string(forKey: SofaAppearance.defaultsKey)
        (preference.flatMap(SofaAppearance.init(rawValue:)) ?? .dark).apply()
        let reminders = ProgramReminderStore.shared
        reminders.onWatch = { reminder in
            let library = Library.shared
            guard let channel = library.channels.first(where: { reminder.matches($0) }) else {
                AppWindows.shared.showMessage(L10n.text("频道暂不可用"), detail: L10n.text("这个频道可能已被移除，请重新导入频道列表。"))
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
        NotificationCenter.default.addObserver(self, selector: #selector(configureMenuBar), name: L10n.didChange, object: L10n.shared)
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

    @objc private func configureMenuBar() {
        guard !updatingMenuBar, let menu = NSApplication.shared.mainMenu else { return }
        updatingMenuBar = true
        defer { updatingMenuBar = false }
        if let appItem = menu.items.first {
            setTitle(L10n.text("沙发电视"), for: appItem)
            for item in appItem.submenu?.items ?? [] {
                if let services = NSApp.servicesMenu, item.submenu === services {
                    setTitle(L10n.text("服务"), for: item)
                }
                switch item.action {
                case #selector(NSApplication.hide(_:)): setTitle(L10n.text("隐藏沙发电视"), for: item)
                case #selector(NSApplication.hideOtherApplications(_:)): setTitle(L10n.text("隐藏其他"), for: item)
                case #selector(NSApplication.unhideAllApplications(_:)): setTitle(L10n.text("全部显示"), for: item)
                case #selector(NSApplication.terminate(_:)): setTitle(L10n.text("退出沙发电视"), for: item)
                default: break
                }
            }
        }
        for item in menu.items where item.submenu != nil {
            if item.submenu === NSApp.windowsMenu { setTitle(L10n.text("窗口"), for: item) }
            if item.submenu === NSApp.helpMenu { setTitle(L10n.text("帮助"), for: item) }
        }
        for item in menu.items where ["文件", "编辑", "显示", "File", "Edit", "View"].contains(item.title) {
            // Keep standard text shortcuts available in search/address fields while hiding these menus.
            allowHiddenShortcuts(item)
            if !item.isHidden { item.isHidden = true }
        }
    }

    private func setTitle(_ title: String, for item: NSMenuItem) {
        if item.title != title { item.title = title }
        if let submenu = item.submenu, submenu.title != title { submenu.title = title }
    }

    private func allowHiddenShortcuts(_ item: NSMenuItem) {
        item.allowsKeyEquivalentWhenHidden = true
        for child in item.submenu?.items ?? [] { allowHiddenShortcuts(child) }
    }
}
