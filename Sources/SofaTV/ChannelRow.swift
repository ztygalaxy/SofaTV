import SwiftUI

/// Favorite changes update this row without invalidating every other channel's layout.
struct ChannelRow: View, Equatable {
    let channel: Channel
    let isFavorite: Bool
    let isSelected: Bool
    let currentProgram: String?
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onDeleteSource: (URL) -> Void
    let onDelete: () -> Void

    nonisolated static func == (lhs: ChannelRow, rhs: ChannelRow) -> Bool {
        lhs.channel == rhs.channel && lhs.isFavorite == rhs.isFavorite && lhs.isSelected == rhs.isSelected && lhs.currentProgram == rhs.currentProgram
    }

    var body: some View {
        HStack {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    ChannelLogoView(channelName: channel.name, isSelected: isSelected)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                        if let currentProgram {
                            Text(currentProgram)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                                .help(currentProgram)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: onFavorite) {
                FavoriteStar(isFavorite: isFavorite)
                    .frame(width: 28, height: 36, alignment: .trailing)
                    .contentShape(Rectangle())
            }.buttonStyle(FavoriteButtonStyle()).help("收藏频道")
                .transaction { transaction in
                    transaction.animation = nil; transaction.disablesAnimations = true
                }
                .accessibilityLabel(isFavorite ? "取消收藏\(channel.name)" : "收藏\(channel.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // This is the existing 44-point content plus 6 points of padding per side.
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contextMenu {
            Menu("删除播放线路") {
                ForEach(Array(channel.sources.enumerated()), id: \.offset) { index, source in
                    Button("线路 \(index + 1) · \(source.scheme == "webview" ? "后台解析" : (source.host ?? source.absoluteString))", role: .destructive) {
                        onDeleteSource(source)
                    }
                }
            }
            Divider()
            Button("删除频道…", role: .destructive, action: onDelete)
        }
    }
}

/// Preserve the label's exact geometry while the mouse is pressed.
private struct FavoriteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
