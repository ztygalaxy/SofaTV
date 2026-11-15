import SwiftUI

/// A fixed-height segmented filter matching the adjacent search field.
struct ChannelFilterTabs: View {
    @Binding var favoritesOnly: Bool
    var contentScale: CGFloat = 1
    var body: some View {
        HStack(spacing: 2 * contentScale) {
            option(L10n.text("频道"), favorites: false)
            option(L10n.text("收藏"), favorites: true)
        }
        .padding(2 * contentScale)
        .frame(height: 26 * contentScale)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6 * contentScale))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("频道范围"))
    }
    private func option(_ title: String, favorites: Bool) -> some View {
        Button { favoritesOnly = favorites } label: {
            Text(title)
                .font(.system(size: 13 * contentScale, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10 * contentScale)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 50 * contentScale, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 4 * contentScale)
                        .fill(Color.primary.opacity(favoritesOnly == favorites ? 0.14 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(favoritesOnly == favorites ? L10n.text("已选择") : L10n.text("未选择"))
    }
}
