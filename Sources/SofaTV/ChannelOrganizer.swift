import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Library {
    func showChannelOrganizer() {
        let id = "channel-organizer-\(ObjectIdentifier(self))"
        AppWindows.shared.show(id: id, title: "整理频道分组", size: NSSize(width: 680, height: 540), titleVisible: true,
            content: ChannelOrganizer(library: self, onClose: { AppWindows.shared.close(id: id) }))
    }
    func exportChannelConfiguration() {
        let panel = NSSavePanel()
        panel.title = "导出频道配置"; panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "沙发电视频道配置.json"
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { try self.configurationBackupData().write(to: url, options: .atomic) }
            catch { AppWindows.shared.showMessage("导出未成功", detail: error.localizedDescription) }
        }
    }
    func importChannelConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "导入频道配置"; panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 32 * 1_024 * 1_024 else { throw ChannelConfigurationBackup.BackupError.invalid }
                let data = try Data(contentsOf: url)
                _ = try ChannelConfigurationBackup.decode(data)
                let alert = NSAlert()
                alert.messageText = "恢复频道配置？"
                alert.informativeText = "将替换当前频道来源、收藏、名称、分组和顺序，并停止当前播放。"
                alert.addButton(withTitle: "恢复").hasDestructiveAction = true
                alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
                AppWindows.shared.present(alert) { [weak self] result in
                    guard result == .alertFirstButtonReturn else { return }
                    do { try self?.restoreConfiguration(data) }
                    catch { AppWindows.shared.showMessage("恢复未成功", detail: error.localizedDescription) }
                }
            } catch { AppWindows.shared.showMessage("无法导入配置", detail: error.localizedDescription) }
        }
    }
}

struct ChannelOrganizer: View {
    @ObservedObject var library: Library
    let onClose: () -> Void
    @ViewState private var mode = 0
    @ViewState private var search = ""
    @ViewState private var editing: EditTarget?

    private enum EditTarget: Identifiable {
        case channel(Channel), group(String)
        var id: String {
            switch self { case .channel(let value): "channel:" + value.preferenceKey; case .group(let value): "group:" + value }
        }
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("整理内容", selection: $mode) { Text("频道").tag(0); Text("分组").tag(1) }
                    .pickerStyle(.segmented).frame(width: 160)
                Spacer()
                TextField("搜索频道或分组", text: $search).textFieldStyle(.roundedBorder).frame(width: 230)
            }
            Text("拖动调整顺序；输入新分组名以创建新分组。")
                .font(.caption).foregroundStyle(.secondary)
            if mode == 0 { channelList } else { groupList }
            HStack {
                Button("导入配置…") { library.importChannelConfiguration() }
                Button("导出配置…") { library.exportChannelConfiguration() }
                    .disabled(library.channelLists.isEmpty)
                Button("恢复默认顺序") { library.resetChannelOrder() }
                    .disabled(library.personalization.order.isEmpty && library.personalization.groupOrder.isEmpty)
                Spacer()
                Button("完成", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).background(Color.sofaBackground)
        .sheet(item: $editing) { target in
            switch target {
            case .channel(let channel):
                ChannelNameEditor(channel: channel, groups: library.orderedGroups) { name, group in
                    library.customizeChannel(channel, name: name, group: group); editing = nil
                } onCancel: { editing = nil }
            case .group(let group):
                GroupNameEditor(group: group) { name in
                    library.renameGroup(group, to: name); editing = nil
                } onCancel: { editing = nil }
            }
        }
    }

    private var channelList: some View {
        List {
            ForEach(library.channels.filter { $0.matches(query) }) { channel in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                    ChannelLogoView(channelName: channel.name, isSelected: false, contentScale: 0.7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(channel.displayName).lineLimit(1)
                        Text(channel.displayGroup).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .help("来源名称：" + channel.name)
                    Spacer()
                    Button { library.favorite(channel) } label: {
                        Image(systemName: library.favorites.contains(channel.id) ? "star.fill" : "star")
                            .foregroundStyle(library.favorites.contains(channel.id) ? Color.sofaAccent : .secondary)
                    }.help("收藏频道")
                    Button { editing = .channel(channel) } label: { Image(systemName: "pencil") }.help("编辑名称与分组")
                    Button { library.moveChannel(channel, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(!query.isEmpty || library.channels.first?.identity == channel.identity).help("上移")
                    Button { library.moveChannel(channel, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(!query.isEmpty || library.channels.last?.identity == channel.identity).help("下移")
                }
                .buttonStyle(.borderless).padding(.vertical, 5)
                .moveDisabled(!query.isEmpty)
            }
            .onMove { offsets, destination in
                guard query.isEmpty else { return }
                library.moveChannels(from: offsets, to: destination)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .appScrollStyle()
        .overlay {
            if library.channels.isEmpty { SidebarEmptyView("暂无频道", systemImage: "tv", description: "请从‘频道’菜单导入频道列表") }
        }
    }

    private var groupList: some View {
        List {
            ForEach(library.orderedGroups.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { group in
                HStack {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(group)
                    Spacer()
                    Text("\(library.channels.filter { $0.displayGroup == group }.count) 个频道")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { editing = .group(group) } label: { Image(systemName: "pencil") }.help("重命名分组")
                    Button { library.moveGroup(group, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(!query.isEmpty || library.orderedGroups.first == group).help("上移")
                    Button { library.moveGroup(group, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(!query.isEmpty || library.orderedGroups.last == group).help("下移")
                }
                .buttonStyle(.borderless).padding(.vertical, 7)
                .moveDisabled(!query.isEmpty)
            }
            .onMove { offsets, destination in
                guard query.isEmpty else { return }
                library.moveGroups(from: offsets, to: destination)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .appScrollStyle()
    }
}

private struct ChannelNameEditor: View {
    let channel: Channel
    let groups: [String]
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    @ViewState private var name: String
    @ViewState private var group: String

    init(channel: Channel, groups: [String], onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.channel = channel; self.groups = groups; self.onSave = onSave; self.onCancel = onCancel
        _name = ViewState(initialValue: channel.displayName); _group = ViewState(initialValue: channel.displayGroup)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑频道").font(.headline)
            Text("频道名称").font(.caption).foregroundStyle(.secondary)
            TextField("频道名称", text: $name).textFieldStyle(.roundedBorder)
            Text("分组名称").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("输入新分组或选择已有分组", text: $group).textFieldStyle(.roundedBorder)
                Menu("选择已有分组") { ForEach(groups, id: \.self) { value in Button(value) { group = value } } }
                    .frame(width: 130)
            }
            HStack {
                Button("恢复原名称与分组") { name = channel.name; group = channel.group }
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { onSave(name, group) }.keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(20).frame(width: 430)
    }
}

private struct GroupNameEditor: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @ViewState private var name: String
    init(group: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave; self.onCancel = onCancel; _name = ViewState(initialValue: group)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名分组").font(.headline)
            TextField("分组名称", text: $name).textFieldStyle(.roundedBorder)
            Text("使用已有分组名称时，会将这些频道合并到该分组。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { onSave(name) }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 400)
    }
}
