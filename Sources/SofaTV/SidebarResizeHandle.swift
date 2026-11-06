import AppKit
import SwiftUI

struct SidebarResizeHandle: View {
    @Binding var width: CGFloat
    let visibleWidth: CGFloat
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    @ViewState private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartWidth == nil { dragStartWidth = visibleWidth }
                                width = clamped((dragStartWidth ?? visibleWidth) + value.translation.width)
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
                    .onHover { hovering in
                        (hovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                    }
            }
            .accessibilityLabel("调整频道列表宽度")
            .accessibilityValue("\(Int(visibleWidth)) 点")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = clamped(visibleWidth + 20)
                case .decrement: width = clamped(visibleWidth - 20)
                @unknown default: break
                }
            }
    }

    private func clamped(_ proposedWidth: CGFloat) -> CGFloat {
        min(max(proposedWidth, minimumWidth), maximumWidth)
    }
}
