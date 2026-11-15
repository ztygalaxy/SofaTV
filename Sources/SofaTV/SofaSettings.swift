import AppKit
import SwiftUI

enum SofaAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let defaultsKey = "interfaceAppearance"
    var id: Self { self }

    var title: String {
        switch self {
        case .system: L10n.text("跟随系统")
        case .light: L10n.text("浅色")
        case .dark: L10n.text("深色")
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.fill"
        }
    }

    @MainActor func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor enum SofaSettings {
    static func show() {
        AppWindows.shared.show(id: "settings", title: "沙发电视设置",
                               size: NSSize(width: 580, height: 156), titleVisible: true,
                               content: SofaSettingsView())
    }
}

private struct SofaSettingsView: View {
    @AppStorage(SofaAppearance.defaultsKey) private var appearance: SofaAppearance = .dark

    var body: some View {
        VStack(spacing: 0) {
            row(L10n.text("主题"), icon: "circle.lefthalf.filled") {
                HStack(spacing: 2) {
                    ForEach(SofaAppearance.allCases) { option in
                        Button { appearance = option } label: {
                            Label(option.title, systemImage: option.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(appearance == option ? Color.primary : .secondary)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background {
                                    if appearance == option {
                                        RoundedRectangle(cornerRadius: 7).fill(Color.sofaAccent.opacity(0.14))
                                            .strokeBorder(Color.sofaAccent, lineWidth: 1)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(appearance == option ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.12)))
            }
            Divider().opacity(0.6)
            row(L10n.text("显示语言"), icon: "globe") {
                Picker(L10n.text("显示语言"), selection: Binding(
                    get: { L10n.shared.preference },
                    set: { L10n.shared.select($0) }
                )) {
                    Text(L10n.text("跟随系统")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("简体中文").tag(AppLanguage.chinese)
                }
                .labelsHidden()
                .frame(width: 154)
            }
        }
        .padding(.horizontal, 16)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
        .padding(16)
        .background(Color.sofaBackground)
        .onChange(of: appearance) { _, value in value.apply() }
    }

    private func row<Control: View>(_ title: String, icon: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 14)
            control()
        }
        .frame(height: 58)
    }
}
