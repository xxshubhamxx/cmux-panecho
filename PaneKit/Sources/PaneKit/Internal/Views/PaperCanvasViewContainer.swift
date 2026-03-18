import SwiftUI

struct PaperCanvasViewContainer<Content: View, EmptyContent: View>: View {
    @Environment(SplitViewController.self) private var controller

    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    let appearance: BonsplitConfiguration.Appearance
    var onGeometryChange: ((_ isDragging: Bool) -> Void)? = nil
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    private func scheduleGeometryChangeNotification() {
        onGeometryChange?(false)
        DispatchQueue.main.async {
            onGeometryChange?(false)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let viewportOrigin = controller.paperViewportOrigin
            let showsOverflowHints = controller.zoomedPaneId == nil
            let showsLeftOverflowHint = showsOverflowHints && (controller.paperCanvas?.showsLeftOverflowHint ?? false)
            let showsRightOverflowHint = showsOverflowHints && (controller.paperCanvas?.showsRightOverflowHint ?? false)
            let paneLayoutSignature = (controller.paperCanvas?.panes ?? []).map { placement in
                let frame = placement.frame.integral
                return "\(placement.pane.id.id.uuidString):\(Int(frame.minX)):\(Int(frame.minY)):\(Int(frame.width)):\(Int(frame.height))"
            }.joined(separator: "|")

            ZStack(alignment: .topLeading) {
                Color.clear

                if let zoomedPaneId = controller.zoomedPaneId,
                   let placement = controller.paperCanvas?.pane(zoomedPaneId) {
                    SinglePaneWrapper(
                        pane: placement.pane,
                        contentBuilder: contentBuilder,
                        emptyPaneBuilder: emptyPaneBuilder,
                        showSplitButtons: showSplitButtons,
                        contentViewLifecycle: contentViewLifecycle
                    )
                    .id(placement.pane.id.id)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    ZStack(alignment: .topLeading) {
                        ForEach(
                            controller.paperCanvas?.panes ?? [],
                            id: \.pane.id.id
                        ) { placement in
                            SinglePaneWrapper(
                                pane: placement.pane,
                                contentBuilder: contentBuilder,
                                emptyPaneBuilder: emptyPaneBuilder,
                                showSplitButtons: showSplitButtons,
                                contentViewLifecycle: contentViewLifecycle
                            )
                            .id(placement.pane.id.id)
                            .frame(width: placement.frame.width, height: placement.frame.height)
                            .offset(x: placement.frame.minX, y: placement.frame.minY)
                            .animation(nil, value: placement.frame)
                        }
                    }
                    .offset(x: -viewportOrigin.x, y: -viewportOrigin.y)
                    .onChange(of: viewportOrigin.x) { _, _ in
                        scheduleGeometryChangeNotification()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TabBarColors.paneBackground(for: appearance))
            .overlay(alignment: .leading) {
                PaperCanvasOverflowHintEdge(
                    direction: .left,
                    isVisible: showsLeftOverflowHint,
                    appearance: appearance
                )
            }
            .overlay(alignment: .trailing) {
                PaperCanvasOverflowHintEdge(
                    direction: .right,
                    isVisible: showsRightOverflowHint,
                    appearance: appearance
                )
            }
            .clipped()
            .focusable()
            .focusEffectDisabled()
            .onAppear {
                controller.setPaperViewportFrame(geometry.frame(in: .global))
                scheduleGeometryChangeNotification()
            }
            .onChange(of: geometry.size) { _, _ in
                controller.setPaperViewportFrame(geometry.frame(in: .global))
                scheduleGeometryChangeNotification()
            }
            .onChange(of: paneLayoutSignature) { _, _ in
                scheduleGeometryChangeNotification()
            }
        }
    }
}

private struct PaperCanvasOverflowHintEdge: View {
    enum Direction {
        case left
        case right
    }

    let direction: Direction
    let isVisible: Bool
    let appearance: BonsplitConfiguration.Appearance

    var body: some View {
        ZStack(alignment: direction == .left ? .leading : .trailing) {
            LinearGradient(
                colors: gradientColors,
                startPoint: direction == .left ? .leading : .trailing,
                endPoint: direction == .left ? .trailing : .leading
            )
            .frame(width: TabBarMetrics.paperCanvasOverflowHintWidth)

            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .font(.system(size: TabBarMetrics.paperCanvasOverflowHintIconSize, weight: .semibold))
                .foregroundStyle(TabBarColors.activeText(for: appearance).opacity(0.45))
                .padding(direction == .left ? .leading : .trailing, 4)
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: TabBarMetrics.paperCanvasViewportAnimationDuration), value: isVisible)
    }

    private var gradientColors: [Color] {
        let background = TabBarColors.paneBackground(for: appearance).opacity(0.96)
        switch direction {
        case .left:
            return [background, background.opacity(0)]
        case .right:
            return [background.opacity(0), background]
        }
    }
}
