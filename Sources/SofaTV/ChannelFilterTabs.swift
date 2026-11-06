import SwiftUI

/// A fixed-height segmented filter matching the adjacent search field.
struct ChannelFilterTabs: View {
    @Binding var favoritesOnly: Bool
    var body: some View {
        HStack(spacing: 0) {
            option("频道", favorites: false)
            option("收藏", favorites: true)
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("频道范围")
    }
    private func option(_ title: String, favorites: Bool) -> some View {
        Button { favoritesOnly = favorites } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(favoritesOnly == favorites ? 0.14 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(favoritesOnly == favorites ? "已选择" : "未选择")
    }
}
