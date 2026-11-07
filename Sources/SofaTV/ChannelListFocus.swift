import SwiftUI

/// Scroll only the active channel list after filters/groups have made its row visible.
struct ChannelListFocus: ViewModifier {
    let preview: ProgramGuidePreview
    let presentation: ProgramGuidePreview.Presentation
    let favorites: Set<String>
    @Binding var search: String
    @Binding var favoritesOnly: Bool
    @Binding var collapsedGroups: Set<String>
    @ViewState private var request: ProgramGuidePreview.ChannelFocusRequest?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onReceive(preview.channelFocusRequests) { value in
                    guard value.presentation == presentation else { return }
                    let channel = value.channel
                    if favoritesOnly, !favorites.contains(channel.id) { favoritesOnly = false }
                    if !search.isEmpty,
                       !channel.name.localizedCaseInsensitiveContains(search),
                       !channel.group.localizedCaseInsensitiveContains(search) {
                        search = ""
                    }
                    if collapsedGroups.contains(channel.group) { collapsedGroups.remove(channel.group) }
                    request = value
                }
                .onChange(of: request) { _, value in
                    guard let value else { return }
                    proxy.scrollTo(value.channel.id, anchor: .center)
                }
        }
    }
}
