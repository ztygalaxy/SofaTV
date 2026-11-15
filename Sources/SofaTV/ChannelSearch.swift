import SwiftUI

struct ChannelSearchField: View {
    @Binding var text: String
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索频道或节目", text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel("搜索频道或节目")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
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
        rows(results.live, heading: "正在播出", isLive: true)
        rows(results.upcoming, heading: "即将播出", isLive: false)
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
            .accessibilityLabel("观看\(match.channel.displayName)的\(match.program.title)")
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
            ? "" : start.formatted(.dateTime.month().day()) + " "
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
