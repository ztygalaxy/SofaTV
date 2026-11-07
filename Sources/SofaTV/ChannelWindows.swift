import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Library {
    func importChannels() {
        if let importPanel { importPanel.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.title = "导入频道文件"
        panel.prompt = "导入"
        panel.allowedContentTypes = [.item]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        importPanel = panel
        panel.begin { [weak self, weak panel] result in
            guard let self, let panel else { return }
            self.importPanel = nil
            guard result == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { try self.parse(String(contentsOf: url, encoding: .utf8), as: .file(url)) }
            catch { self.showError(error.localizedDescription) }
        }
    }

    func showAddressWindow(direct: Bool) {
        let id = "address-\(ObjectIdentifier(self))-\(direct)"
        let title = direct ? "打开直播地址" : "导入在线频道列表"
        AppWindows.shared.show(id: id, title: title, size: NSSize(width: 420, height: 124), titleVisible: true, content:
            ChannelAddressView(label: direct ? "直播地址" : "频道列表地址",
                initialAddress: direct ? "" : OnlineChannelSource.defaultURL.absoluteString,
                onOpen: { [weak self] address in
                AppWindows.shared.close(id: id)
                Task { await self?.load(address, direct: direct) }
            }, onClose: { AppWindows.shared.close(id: id) })
        )
    }

    func showListManager() {
        let id = "channel-lists-\(ObjectIdentifier(self))"
        AppWindows.shared.show(id: id, title: "管理频道列表", size: ChannelListManager.windowSize(sourceCount: channelLists.count), titleVisible: true, content:
            ChannelListManager(library: self,
                onResize: { AppWindows.shared.resize(id: id, size: $0) },
                onClose: { AppWindows.shared.close(id: id) })
        )
    }

    func showChannels(in list: ChannelList) {
        let id = "list-detail-\(ObjectIdentifier(self))-\(list.id)"
        AppWindows.shared.show(id: id, title: "频道详情", size: NSSize(width: 640, height: 480), titleVisible: true, content:
            ChannelListDetail(library: self, listID: list.id, onClose: { AppWindows.shared.close(id: id) })
        )
    }

    func showError(_ message: String) {
        AppWindows.shared.showMessage("无法打开", detail: message)
    }

    func confirmDeletion(_ deletion: LibraryDeletion, in list: ChannelList? = nil) {
        let alert = NSAlert()
        alert.messageText = deletion.title
        alert.informativeText = deletion.message(in: list)
        alert.addButton(withTitle: "删除").hasDestructiveAction = true
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        AppWindows.shared.present(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            switch deletion {
            case .channel(let channel): self.deleteChannel(channel, fromList: list?.id)
            case .source(let channel, let source): self.deleteSource(source, from: channel, fromList: list?.id)
            case .group(let group): self.deleteGroup(group)
            case .list(let list): self.deleteList(list)
            }
        }
    }
}

private struct ChannelAddressView: View {
    let label: String
    let onOpen: (String) -> Void
    let onClose: () -> Void
    @ViewState private var address: String
    @FocusState private var addressFocused: Bool

    init(label: String, initialAddress: String = "", onOpen: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.label = label; self.onOpen = onOpen; self.onClose = onClose
        _address = ViewState(initialValue: initialAddress)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                TextField("https://…", text: $address)
                    .font(.system(size: 13))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .accessibilityLabel(label)
                    .focused($addressFocused)
            }
            HStack(spacing: 8) {
                Spacer()
                Button(action: onClose) { Text("取消").frame(minWidth: 44) }
                    .keyboardShortcut(.cancelAction)
                Button { onOpen(address.trimmingCharacters(in: .whitespacesAndNewlines)) } label: {
                    Text("打开").frame(minWidth: 44)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .onAppear { addressFocused = true }
    }
}
