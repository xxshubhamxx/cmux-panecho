import AppKit
import ObjectiveC

private var cmuxWindowCEFPortalKey: UInt8 = 0
private var cmuxWindowCEFPortalCloseObserverKey: UInt8 = 0

@MainActor
private final class WindowCEFPortal: NSObject {
    private static let hiddenAlpha: CGFloat = 0.001

    private final class OverlayHostView: NSView {
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private final class Entry {
        let hostedView: NSView
        weak var anchorView: NSView?
        var visibleInUI: Bool
        var zPriority: Int

        init(hostedView: NSView, anchorView: NSView, visibleInUI: Bool, zPriority: Int) {
            self.hostedView = hostedView
            self.anchorView = anchorView
            self.visibleInUI = visibleInUI
            self.zPriority = zPriority
        }
    }

    private weak var window: NSWindow?
    private let overlayHost = OverlayHostView(frame: .zero)
    private var entries: [ObjectIdentifier: Entry] = [:]

    init(window: NSWindow) {
        self.window = window
        super.init()
        installOverlayHostIfNeeded()
    }

    func tearDown() {
        for entry in entries.values {
            entry.hostedView.removeFromSuperview()
        }
        entries.removeAll()
        overlayHost.removeFromSuperview()
    }

    func bind(hostedView: NSView, to anchorView: NSView, visibleInUI: Bool, zPriority: Int) {
        installOverlayHostIfNeeded()
        let viewId = ObjectIdentifier(hostedView)
        let entry = entries[viewId] ?? Entry(
            hostedView: hostedView,
            anchorView: anchorView,
            visibleInUI: visibleInUI,
            zPriority: zPriority
        )
        entry.anchorView = anchorView
        entry.visibleInUI = visibleInUI
        entry.zPriority = zPriority
        entries[viewId] = entry
        synchronizeHostedView(withId: viewId)
        reorderHostedViewsByPriority()
    }

    func hideHostedView(withId viewId: ObjectIdentifier) {
        guard let entry = entries[viewId] else { return }
        entry.visibleInUI = false
        DispatchQueue.main.async { [weak self] in
            self?.synchronizeHostedView(withId: viewId)
        }
    }

    func detachHostedView(withId viewId: ObjectIdentifier) {
        guard let entry = entries.removeValue(forKey: viewId) else { return }
        entry.hostedView.removeFromSuperview()
    }

    func isHostedViewBoundToAnchor(withId viewId: ObjectIdentifier, anchorView: NSView) -> Bool {
        guard let entry = entries[viewId] else { return false }
        return entry.anchorView === anchorView
    }

    func synchronizeHostedViewForAnchor(_ anchorView: NSView) {
        for (viewId, entry) in entries where entry.anchorView === anchorView {
            synchronizeHostedView(withId: viewId)
        }
    }

    func hostedViewIds() -> Set<ObjectIdentifier> {
        Set(entries.keys)
    }

    func hostedViewAtWindowPoint(_ windowPoint: NSPoint) -> NSView? {
        installOverlayHostIfNeeded()
        let point = overlayHost.convert(windowPoint, from: nil)
        let hitView = overlayHost.hitTest(point)
        if hitView == nil || hitView === overlayHost {
            for entry in entries.values.sorted(by: { $0.zPriority > $1.zPriority }) {
                guard !entry.hostedView.isHidden,
                      entry.hostedView.alphaValue > Self.hiddenAlpha,
                      entry.hostedView.superview === overlayHost,
                      entry.hostedView.frame.contains(point) else {
                    continue
                }
                return entry.hostedView
            }
            return nil
        }

        var current: NSView? = hitView
        while let candidate = current {
            if entries[ObjectIdentifier(candidate)] != nil {
                return candidate
            }
            current = candidate.superview
        }
        return nil
    }

    private func installOverlayHostIfNeeded() {
        guard let window, let contentView = window.contentView else { return }
        guard overlayHost.superview !== contentView else { return }
        overlayHost.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(overlayHost)
        NSLayoutConstraint.activate([
            overlayHost.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlayHost.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlayHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlayHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func synchronizeHostedView(withId viewId: ObjectIdentifier) {
        guard let window,
              let entry = entries[viewId],
              let anchorView = entry.anchorView,
              anchorView.window === window,
              entry.visibleInUI else {
            if let entry = entries[viewId] {
                applyHiddenState(to: entry)
            }
            return
        }

        installOverlayHostIfNeeded()

        let rectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let rectInOverlay = overlayHost.convert(rectInWindow, from: nil)
        guard rectInOverlay.width > 0, rectInOverlay.height > 0 else {
            applyHiddenState(to: entry)
            return
        }

        if entry.hostedView.superview !== overlayHost {
            entry.hostedView.removeFromSuperview()
            entry.hostedView.frame = rectInOverlay
            overlayHost.addSubview(entry.hostedView)
        } else if entry.hostedView.frame != rectInOverlay {
            entry.hostedView.frame = rectInOverlay
        }

        if entry.hostedView.alphaValue != 1.0 {
            entry.hostedView.alphaValue = 1.0
        }
    }

    private func applyHiddenState(to entry: Entry) {
        if entry.hostedView.alphaValue != Self.hiddenAlpha {
            entry.hostedView.alphaValue = Self.hiddenAlpha
        }
        if entry.hostedView.frame != .zero {
            entry.hostedView.frame = .zero
        }
    }

    private func reorderHostedViewsByPriority() {
        let sorted = entries.values.sorted { lhs, rhs in
            if lhs.zPriority == rhs.zPriority {
                return ObjectIdentifier(lhs.hostedView).debugDescription < ObjectIdentifier(rhs.hostedView).debugDescription
            }
            return lhs.zPriority < rhs.zPriority
        }
        for view in sorted.map(\.hostedView) where view.superview === overlayHost {
            overlayHost.addSubview(view, positioned: .above, relativeTo: nil)
        }
    }
}

@MainActor
enum CEFWindowPortalRegistry {
    private static var portalsByWindowId: [ObjectIdentifier: WindowCEFPortal] = [:]
    private static var hostedViewToWindowId: [ObjectIdentifier: ObjectIdentifier] = [:]

    private static func installWindowCloseObserverIfNeeded(for window: NSWindow) {
        guard objc_getAssociatedObject(window, &cmuxWindowCEFPortalCloseObserverKey) == nil else { return }
        let windowId = ObjectIdentifier(window)
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                if let window {
                    removePortal(for: window)
                } else {
                    removePortal(windowId: windowId, window: nil)
                }
            }
        }
        objc_setAssociatedObject(
            window,
            &cmuxWindowCEFPortalCloseObserverKey,
            observer,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private static func portal(for window: NSWindow) -> WindowCEFPortal {
        if let existing = objc_getAssociatedObject(window, &cmuxWindowCEFPortalKey) as? WindowCEFPortal {
            portalsByWindowId[ObjectIdentifier(window)] = existing
            installWindowCloseObserverIfNeeded(for: window)
            return existing
        }

        let portal = WindowCEFPortal(window: window)
        objc_setAssociatedObject(window, &cmuxWindowCEFPortalKey, portal, .OBJC_ASSOCIATION_RETAIN)
        portalsByWindowId[ObjectIdentifier(window)] = portal
        installWindowCloseObserverIfNeeded(for: window)
        return portal
    }

    private static func removePortal(for window: NSWindow) {
        removePortal(windowId: ObjectIdentifier(window), window: window)
    }

    private static func removePortal(windowId: ObjectIdentifier, window: NSWindow?) {
        if let portal = portalsByWindowId.removeValue(forKey: windowId) {
            portal.tearDown()
        }
        hostedViewToWindowId = hostedViewToWindowId.filter { $0.value != windowId }

        guard let window else { return }
        if let observer = objc_getAssociatedObject(window, &cmuxWindowCEFPortalCloseObserverKey) {
            NotificationCenter.default.removeObserver(observer)
        }
        objc_setAssociatedObject(window, &cmuxWindowCEFPortalCloseObserverKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(window, &cmuxWindowCEFPortalKey, nil, .OBJC_ASSOCIATION_RETAIN)
    }

    private static func pruneMappings(for windowId: ObjectIdentifier, validViewIds: Set<ObjectIdentifier>) {
        hostedViewToWindowId = hostedViewToWindowId.filter { viewId, mappedWindowId in
            mappedWindowId != windowId || validViewIds.contains(viewId)
        }
    }

    static func bind(hostedView: NSView, to anchorView: NSView, visibleInUI: Bool, zPriority: Int = 0) {
        guard let window = anchorView.window else { return }
        let windowId = ObjectIdentifier(window)
        let viewId = ObjectIdentifier(hostedView)
        let nextPortal = portal(for: window)

        if let oldWindowId = hostedViewToWindowId[viewId], oldWindowId != windowId {
            portalsByWindowId[oldWindowId]?.detachHostedView(withId: viewId)
        }

        nextPortal.bind(hostedView: hostedView, to: anchorView, visibleInUI: visibleInUI, zPriority: zPriority)
        hostedViewToWindowId[viewId] = windowId
        pruneMappings(for: windowId, validViewIds: nextPortal.hostedViewIds())
    }

    static func synchronizeForAnchor(_ anchorView: NSView) {
        guard let window = anchorView.window else { return }
        portal(for: window).synchronizeHostedViewForAnchor(anchorView)
    }

    static func isHostedView(_ hostedView: NSView, boundTo anchorView: NSView) -> Bool {
        let viewId = ObjectIdentifier(hostedView)
        guard let window = anchorView.window else { return false }
        let windowId = ObjectIdentifier(window)
        guard hostedViewToWindowId[viewId] == windowId,
              let portal = portalsByWindowId[windowId] else { return false }
        return portal.isHostedViewBoundToAnchor(withId: viewId, anchorView: anchorView)
    }

    static func hide(hostedView: NSView) {
        let viewId = ObjectIdentifier(hostedView)
        guard let windowId = hostedViewToWindowId[viewId],
              let portal = portalsByWindowId[windowId] else { return }
        portal.hideHostedView(withId: viewId)
    }

    static func detach(hostedView: NSView) {
        let viewId = ObjectIdentifier(hostedView)
        guard let windowId = hostedViewToWindowId.removeValue(forKey: viewId) else { return }
        portalsByWindowId[windowId]?.detachHostedView(withId: viewId)
    }

    static func hostedViewAtWindowPoint(_ windowPoint: NSPoint, in window: NSWindow) -> NSView? {
        let windowId = ObjectIdentifier(window)
        return portalsByWindowId[windowId]?.hostedViewAtWindowPoint(windowPoint)
    }
}
