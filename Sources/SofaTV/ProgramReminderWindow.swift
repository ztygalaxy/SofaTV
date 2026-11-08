import AppKit
import SwiftUI

@MainActor enum ProgramReminderWindow {
    static func show(_ store: ProgramReminderStore = .shared) {
        AppWindows.shared.show(id: "program-reminders", title: "节目预约", size: NSSize(width: 520, height: 420),
                               titleVisible: true, content: ProgramReminderList(store: store))
    }
}

struct ProgramReminderButton: View {
    let channel: Channel
    let program: ProgramGuide.CurrentProgram
    let now: Date
    let scale: CGFloat
    @ObservedObject var store: ProgramReminderStore
    var body: some View {
        let existing = store.reminder(for: program, channel: channel)
        if program.start > now || existing != nil {
            Button {
                Task { @MainActor in
                    do {
                        try await store.toggle(program, channel: channel)
                        if existing != nil { AppToast.shared.show("已取消节目预约") }
                        else if store.reminder(for: program, channel: channel) != nil {
                            AppToast.shared.show("\(program.title) 节目预约成功")
                        }
                    }
                    catch { AppWindows.shared.showMessage("无法设置节目预约", detail: error.localizedDescription) }
                }
            } label: {
                Image(systemName: existing == nil ? "bell" : "bell.fill")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(existing == nil ? Color.secondary : Color.sofaAccent)
                    .frame(width: 24 * scale, height: 24 * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy(program, channel: channel))
            .help(existing == nil ? "节目开播前 10 秒提醒" : "取消节目预约")
            .accessibilityLabel((existing == nil ? "预约观看 " : "取消预约 ") + program.title)
        }
    }
}

struct ProgramReminderList: View {
    @ObservedObject var store: ProgramReminderStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("节目开播前 10 秒发送系统通知，点击通知即可观看。")
                .font(.callout).foregroundStyle(.secondary)
            if store.reminders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("暂无节目预约").font(.headline)
                    Text("在节目单中点击未开播节目旁的铃铛添加预约。")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    let now = store.currentDate
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.reminders.sorted { $0.start < $1.start }) { reminder in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(reminder.title).font(.headline).lineLimit(2)
                                        Text(reminder.channelName).foregroundStyle(.secondary)
                                        Text(reminder.start.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption).foregroundStyle(.secondary)
                                        if !store.channelAvailable(for: reminder) {
                                            Text("频道暂不可用").font(.caption).foregroundStyle(.orange)
                                        } else if let error = store.deliveryErrors[reminder.id] {
                                            Text("预约未能生效：" + error).font(.caption).foregroundStyle(.orange)
                                        } else if now >= reminder.end {
                                            Text("已结束").font(.caption).foregroundStyle(.secondary)
                                        } else if now >= reminder.start {
                                            Text("已开播").font(.caption).foregroundStyle(Color.sofaAccent)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if now < reminder.end {
                                        Button("观看") { store.watch(reminder) }
                                            .disabled(!store.channelAvailable(for: reminder))
                                    }
                                    Button("取消") {
                                        store.remove(reminder.id)
                                        AppToast.shared.show("已取消节目预约")
                                    }
                                        .accessibilityLabel("取消预约 " + reminder.title)
                                }.padding(.vertical, 12)
                                Divider()
                            }
                        }
                    }
                    .appScrollStyle()
                }
            }
            HStack {
                Text("首次预约时，请允许沙发电视发送通知。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.deliveryErrors.isEmpty { Button("重试") { store.retry() } }
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 320)
        .onAppear { store.start() }
    }
}
