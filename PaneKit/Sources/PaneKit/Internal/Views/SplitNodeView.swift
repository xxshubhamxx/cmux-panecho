import SwiftUI
import AppKit

/// Recursively renders a split node (pane or split)
struct SplitNodeView<Content: View, EmptyContent: View>: View {
    @Environment(SplitViewController.self) private var controller

    let node: SplitNode
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    let appearance: BonsplitConfiguration.Appearance
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch
    var onGeometryChange: ((_ isDragging: Bool) -> Void)?
    var enableAnimations: Bool = true
    var animationDuration: Double = 0.15

    var body: some View {
        switch node {
        case .pane(let paneState):
            // Wrap in NSHostingController for proper layout constraints
            SinglePaneWrapper(
                pane: paneState,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )

        case .split(let splitState):
            SplitContainerView(
                splitState: splitState,
                controller: controller,
                appearance: appearance,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle,
                onGeometryChange: onGeometryChange,
                enableAnimations: enableAnimations,
                animationDuration: animationDuration
            )
        }
    }
}

/// Container NSView for a pane inside SinglePaneWrapper.
class PaneDragContainerView: NSView {}

/// Wrapper that uses NSHostingController for proper AppKit layout constraints
struct SinglePaneWrapper<Content: View, EmptyContent: View>: NSViewRepresentable {
    @Environment(SplitViewController.self) private var controller
    
    let pane: PaneState
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    func makeNSView(context: Context) -> NSView {
        let containerView = PaneDragContainerView()
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        context.coordinator.installHostingController(
            for: pane,
            controller: controller,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle,
            in: containerView
        )

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Hide the container when inactive so AppKit's drag routing doesn't deliver
        // drag sessions to views belonging to background workspaces.
        nsView.isHidden = !controller.isInteractive
        nsView.wantsLayer = true
        nsView.layer?.masksToBounds = true

        let paneView = PaneContainerView(
            pane: pane,
            controller: controller,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
        if context.coordinator.paneId != pane.id {
            context.coordinator.installHostingController(
                for: pane,
                controller: controller,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle,
                in: nsView
            )
        } else {
            context.coordinator.hostingController?.rootView = paneView
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var paneId: PaneID?
        var hostingController: NSHostingController<PaneContainerView<Content, EmptyContent>>?

        func installHostingController(
            for pane: PaneState,
            controller: SplitViewController,
            contentBuilder: @escaping (TabItem, PaneID) -> Content,
            emptyPaneBuilder: @escaping (PaneID) -> EmptyContent,
            showSplitButtons: Bool,
            contentViewLifecycle: ContentViewLifecycle,
            in containerView: NSView
        ) {
            hostingController?.view.removeFromSuperview()

            let paneView = PaneContainerView(
                pane: pane,
                controller: controller,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )
            let nextHostingController = NSHostingController(rootView: paneView)
            nextHostingController.view.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(nextHostingController.view)

            NSLayoutConstraint.activate([
                nextHostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
                nextHostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                nextHostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                nextHostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])

            paneId = pane.id
            hostingController = nextHostingController
        }
    }
}
