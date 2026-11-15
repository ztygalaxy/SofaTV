import SwiftUI

struct ChannelBrowserHeader: View {
    @Binding var favoritesOnly: Bool
    @Binding var search: String
    var scale: CGFloat = 1
    let onMinimumWidthChange: (CGFloat) -> Void

    var body: some View {
        let spacing = 10 * scale
        HStack(spacing: 0) {
            measure(ChannelFilterTabs(favoritesOnly: $favoritesOnly, contentScale: scale))
            Spacer(minLength: spacing)
            measure(ChannelSearchField(text: $search, scale: scale))
        }
        .onPreferenceChange(ItemWidths.self) { width in
            if width > 0 { onMinimumWidthChange(ceil(width + spacing)) }
        }
    }

    private func measure<Content: View>(_ content: Content) -> some View {
        content
            .fixedSize(horizontal: true, vertical: false)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: ItemWidths.self, value: geometry.size.width)
                }
            }
    }

    private struct ItemWidths: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value += nextValue()
        }
    }
}

struct ChannelSearchField: View {
    @Binding var text: String
    var scale: CGFloat = 1

    var body: some View {
        let placeholder = L10n.text("搜索频道或节目")
        let clearIcon = Image(systemName: "xmark.circle.fill")
        HStack(spacing: 5 * scale) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(placeholder)
                .fixedSize()
                .hidden()
                .overlay(alignment: .leading) {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .accessibilityLabel(placeholder)
                }
            clearIcon.hidden().overlay {
                if !text.isEmpty {
                    Button { text = "" } label: {
                        clearIcon.foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("清除搜索"))
                    .accessibilityLabel(L10n.text("清除搜索"))
                }
            }
        }
        .font(.system(size: 13 * scale))
        .padding(.horizontal, 8 * scale)
        .frame(height: 26 * scale)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6 * scale))
    }
}

struct ProgramSearchRows: View {
    let results: ProgramGuideStore.SearchResults
    let date: Date
    let reminders: ProgramReminderStore?
    let rowBackground: Color
    var scale: CGFloat = 1
    let onPlay: (ProgramGuideStore.ProgramMatch) -> Void

    var body: some View {
        rows(results.live, heading: L10n.text("正在播出"), isLive: true)
        rows(results.upcoming, heading: L10n.text("即将播出"), isLive: false)
    }

    @ViewBuilder private func rows(_ matches: [ProgramGuideStore.ProgramMatch], heading: String, isLive: Bool) -> some View {
        if !matches.isEmpty {
            Text(heading)
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12 * scale)
                .padding(.vertical, 9 * scale)
                .accessibilityAddTraits(.isHeader)
                .listRowInsets(EdgeInsets())
                .listRowBackground(rowBackground)
                .listRowSeparator(.hidden)

            ForEach(matches) { match in
                row(match, isLive: isLive)
                    .padding(.horizontal, 12 * scale)
                    .padding(.vertical, 8 * scale)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(rowBackground)
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder private func row(_ match: ProgramGuideStore.ProgramMatch, isLive: Bool) -> some View {
        if isLive {
            Button { onPlay(match) } label: {
                HStack(spacing: 8 * scale) {
                    details(for: match)
                    Image(systemName: "play.circle")
                        .font(.system(size: 16 * scale))
                        .foregroundStyle(Color.sofaAccent)
                        .frame(width: 24 * scale)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("观看\(match.channel.displayName)的\(match.program.title)"))
            .accessibilityHint(match.program.timeRange())
        } else {
            HStack(spacing: 8 * scale) {
                details(for: match)
                    .accessibilityElement(children: .combine)
                if let reminders {
                    ProgramReminderButton(channel: match.channel, program: match.program, now: date,
                                          scale: scale, store: reminders)
                }
            }
        }
    }

    private func details(for match: ProgramGuideStore.ProgramMatch) -> some View {
        let start = match.program.start
        let day = Calendar.current.isDate(start, inSameDayAs: date)
            ? "" : start.formatted(.dateTime.month().day().locale(L10n.locale)) + " "
        return VStack(alignment: .leading, spacing: 4 * scale) {
            Text(match.program.title)
                .font(.system(size: 14 * scale, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(match.channel.displayName) · \(day)\(match.program.timeRange())")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
