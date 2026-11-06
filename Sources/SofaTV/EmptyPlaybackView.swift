import AppKit
import SwiftUI

struct EmptyPlaybackView: View {
    private let artwork = Bundle.main.url(forResource: "Television", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        VStack(spacing: 20) {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                Text("沙发电视").font(.title2.bold())
                Text("坐回沙发，好好看电视。").font(.body)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
