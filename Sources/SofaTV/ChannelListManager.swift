import AppKit
import SwiftUI

struct ChannelListManager: View {
    @ObservedObject var library: Library
    let onResize: (NSSize) -> Void
    let onClose: () -> Void
    private static let rowHeight: CGFloat = 64
    private static let maximumVisibleSources = 5

    static func windowSize(sourceCount: Int) -> NSSize {
        NSSize(width: 560, height: 106 + rowHeight * CGFloat(max(1, min(maximumVisibleSources, sourceCount))))
    }

    private func icon(for kind: ChannelList.Kind) -> String {
        switch kind {
        case .builtIn: "shippingbox"
        case .file: "doc.text"
        case .online: "link"
        case .legacy: "tray.full"
        }
    }

    private func sourceRow(_ list: ChannelList) -> some View {
        HStack(spacing: 8) {
            Button { library.showChannels(in: list) } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon(for: list.kind))
                        .font(.title3).foregroundStyle(.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(list.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(list.detail).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).help(list.detail)
                    }
                    Spacer(minLength: 12)
                    Text("\(list.channels.count) 个频道").font(.system(size: 12)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("查看“\(list.name)”中的频道")
            Button(role: .destructive) { library.confirmDeletion(.list(list)) } label: {
                Image(systemName: "trash").frame(width: 28, height: 32)
            }
            .buttonStyle(.borderless).help("删除这份频道来源")
            .padding(.trailing, 8)
        }
        .frame(height: Self.rowHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("频道来源").font(.headline)
                Spacer()
                Text("\(library.channelLists.count) 个来源").font(.caption).foregroundStyle(.secondary)
            }
            if library.channelLists.isEmpty {
                Text("没有已导入的频道来源")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(library.channelLists) { sourceRow($0) }
                    }
                }
                .frame(height: Self.rowHeight * CGFloat(min(Self.maximumVisibleSources, library.channelLists.count)))
                .scrollIndicators(library.channelLists.count > Self.maximumVisibleSources ? .automatic : .hidden)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Text("点击来源查看频道").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完成", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.sofaBackground)
        .onChange(of: library.channelLists.count) { _, count in onResize(Self.windowSize(sourceCount: count)) }
    }
}

struct ChannelListDetail: View {
    @ObservedObject var library: Library
    let listID: String
    let onClose: () -> Void
    @ViewState private var search = ""

    var body: some View {
        let list = library.channelLists.first { $0.id == listID }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let channels = list?.channels.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.group.localizedCaseInsensitiveContains(query)
        } ?? []

        VStack(alignment: .leading, spacing: 12) {
            if let list {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name).font(.headline).lineLimit(1)
                    Text(list.detail).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(list.detail)
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索频道或分组", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help("清除搜索")
                    }
                }
                .padding(.horizontal, 9).frame(height: 28)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(channels, id: \.identity) { channel in
                            SourceChannelRow(channel: channel,
                                onDelete: { library.confirmDeletion(.channel(channel), in: list) },
                                onDeleteSource: { library.confirmDeletion(.source(channel, $0), in: list) })
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if channels.isEmpty {
                        Text(query.isEmpty ? "此来源中没有频道" : "没有匹配的频道")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("\(channels.count) / \(list.channels.count) 个频道").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("完成", action: onClose).keyboardShortcut(.defaultAction)
                }
            } else {
                Text("该频道来源已删除").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack { Spacer(); Button("关闭", action: onClose).keyboardShortcut(.defaultAction) }
            }
        }
        .padding(20)
        .background(Color.sofaBackground)
    }
}

private struct SourceChannelRow: View {
    let channel: Channel
    let onDelete: () -> Void
    let onDeleteSource: (URL) -> Void
    @ViewState private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 10) {
                    ForEach(Array(channel.sources.enumerated()), id: \.offset) { index, source in
                        HStack(alignment: .top, spacing: 8) {
                            Text("线路 \(index + 1)").font(.caption).foregroundStyle(.secondary).fixedSize()
                            Text(source.absoluteString).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled).lineLimit(2).help(source.absoluteString)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(source.absoluteString, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                            .help("复制播放地址")
                            Button(role: .destructive) { onDeleteSource(source) } label: { Image(systemName: "trash") }
                                .help("从此来源删除线路")
                        }
                    }
                }
                .buttonStyle(.borderless)
                .padding(.top, 8).padding(.bottom, 4)
            } label: {
                HStack(spacing: 10) {
                    ChannelLogoView(channelName: channel.name, isSelected: false)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(channel.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Text(channel.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("\(channel.sources.count) 条线路").font(.caption).foregroundStyle(.secondary)
                }
                .frame(minHeight: 36)
            }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").frame(width: 28, height: 32) }
                .buttonStyle(.borderless).help("从此来源删除频道")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
    }
}
