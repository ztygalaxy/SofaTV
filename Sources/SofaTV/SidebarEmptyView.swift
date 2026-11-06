import SwiftUI

struct SidebarEmptyView: View {
    private let title: String
    private let systemImage: String
    private let description: String?

    init(_ title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .regular))
            VStack(spacing: 8) {
                Text(title).font(.title2.bold())
                if let description {
                    Text(description).font(.body)
                }
            }
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
