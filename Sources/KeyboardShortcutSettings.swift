import AppKit
import ApplicationServices
import SwiftUI

/// Stores customizable keyboard shortcuts (definitions + persistence).
enum KeyboardShortcutSettings {
    static let didChangeNotification = Notification.Name("cmux.keyboardShortcutSettingsDidChange")
    static let actionUserInfoKey = "action"

    enum Action: String, CaseIterable, Identifiable {
        // Titlebar / primary UI
        case toggleSidebar
        case newTab
        case newWindow
        case closeWindow
        case openFolder
        case sendFeedback
        case showNotifications
        case jumpToUnread
        case triggerFlash

        // Navigation
        case nextSurface
        case prevSurface
        case selectSurfaceByNumber
        case nextSidebarTab
        case prevSidebarTab
        case selectWorkspaceByNumber
        case renameTab
        case renameWorkspace
        case closeWorkspace
        case newSurface
        case toggleTerminalCopyMode

        // Panes / splits
        case focusLeft
        case focusRight
        case focusUp
        case focusDown
        case splitRight
        case splitDown
        case toggleSplitZoom
        case splitBrowserRight
        case splitBrowserDown

        // Panels
        case openBrowser
        case toggleBrowserDeveloperTools
        case showBrowserJavaScriptConsole
        case toggleReactGrab

        var id: String { rawValue }

        var label: String {
            switch self {
            case .toggleSidebar: return String(localized: "shortcut.toggleSidebar.label", defaultValue: "Toggle Sidebar")
            case .newTab: return String(localized: "shortcut.newWorkspace.label", defaultValue: "New Workspace")
            case .newWindow: return String(localized: "shortcut.newWindow.label", defaultValue: "New Window")
            case .closeWindow: return String(localized: "shortcut.closeWindow.label", defaultValue: "Close Window")
            case .openFolder: return String(localized: "shortcut.openFolder.label", defaultValue: "Open Folder")
            case .sendFeedback: return String(localized: "sidebar.help.sendFeedback", defaultValue: "Send Feedback")
            case .showNotifications: return String(localized: "shortcut.showNotifications.label", defaultValue: "Show Notifications")
            case .jumpToUnread: return String(localized: "shortcut.jumpToUnread.label", defaultValue: "Jump to Latest Unread")
            case .triggerFlash: return String(localized: "shortcut.flashFocusedPanel.label", defaultValue: "Flash Focused Panel")
            case .nextSurface: return String(localized: "shortcut.nextSurface.label", defaultValue: "Next Surface")
            case .prevSurface: return String(localized: "shortcut.previousSurface.label", defaultValue: "Previous Surface")
            case .selectSurfaceByNumber: return String(localized: "shortcut.selectSurfaceByNumber.label", defaultValue: "Select Surface 1…9")
            case .nextSidebarTab: return String(localized: "shortcut.nextWorkspace.label", defaultValue: "Next Workspace")
            case .prevSidebarTab: return String(localized: "shortcut.previousWorkspace.label", defaultValue: "Previous Workspace")
            case .selectWorkspaceByNumber: return String(localized: "shortcut.selectWorkspaceByNumber.label", defaultValue: "Select Workspace 1…9")
            case .renameTab: return String(localized: "shortcut.renameTab.label", defaultValue: "Rename Tab")
            case .renameWorkspace: return String(localized: "shortcut.renameWorkspace.label", defaultValue: "Rename Workspace")
            case .closeWorkspace: return String(localized: "shortcut.closeWorkspace.label", defaultValue: "Close Workspace")
            case .newSurface: return String(localized: "shortcut.newSurface.label", defaultValue: "New Surface")
            case .toggleTerminalCopyMode: return String(localized: "shortcut.toggleTerminalCopyMode.label", defaultValue: "Toggle Terminal Copy Mode")
            case .focusLeft: return String(localized: "shortcut.focusPaneLeft.label", defaultValue: "Focus Pane Left")
            case .focusRight: return String(localized: "shortcut.focusPaneRight.label", defaultValue: "Focus Pane Right")
            case .focusUp: return String(localized: "shortcut.focusPaneUp.label", defaultValue: "Focus Pane Up")
            case .focusDown: return String(localized: "shortcut.focusPaneDown.label", defaultValue: "Focus Pane Down")
            case .splitRight: return String(localized: "shortcut.splitRight.label", defaultValue: "Split Right")
            case .splitDown: return String(localized: "shortcut.splitDown.label", defaultValue: "Split Down")
            case .toggleSplitZoom: return String(localized: "shortcut.togglePaneZoom.label", defaultValue: "Toggle Pane Zoom")
            case .splitBrowserRight: return String(localized: "shortcut.splitBrowserRight.label", defaultValue: "Split Browser Right")
            case .splitBrowserDown: return String(localized: "shortcut.splitBrowserDown.label", defaultValue: "Split Browser Down")
            case .openBrowser: return String(localized: "shortcut.openBrowser.label", defaultValue: "Open Browser")
            case .toggleBrowserDeveloperTools: return String(localized: "shortcut.toggleBrowserDevTools.label", defaultValue: "Toggle Browser Developer Tools")
            case .showBrowserJavaScriptConsole: return String(localized: "shortcut.showBrowserJSConsole.label", defaultValue: "Show Browser JavaScript Console")
            case .toggleReactGrab: return String(localized: "shortcut.toggleReactGrab.label", defaultValue: "Toggle React Grab")
            }
        }

        var defaultsKey: String {
            switch self {
            case .toggleSidebar: return "shortcut.toggleSidebar"
            case .newTab: return "shortcut.newTab"
            case .newWindow: return "shortcut.newWindow"
            case .closeWindow: return "shortcut.closeWindow"
            case .openFolder: return "shortcut.openFolder"
            case .sendFeedback: return "shortcut.sendFeedback"
            case .showNotifications: return "shortcut.showNotifications"
            case .jumpToUnread: return "shortcut.jumpToUnread"
            case .triggerFlash: return "shortcut.triggerFlash"
            case .selectWorkspaceByNumber: return "shortcut.selectWorkspaceByNumber"
            case .nextSidebarTab: return "shortcut.nextSidebarTab"
            case .prevSidebarTab: return "shortcut.prevSidebarTab"
            case .renameTab: return "shortcut.renameTab"
            case .renameWorkspace: return "shortcut.renameWorkspace"
            case .closeWorkspace: return "shortcut.closeWorkspace"
            case .focusLeft: return "shortcut.focusLeft"
            case .focusRight: return "shortcut.focusRight"
            case .focusUp: return "shortcut.focusUp"
            case .focusDown: return "shortcut.focusDown"
            case .splitRight: return "shortcut.splitRight"
            case .splitDown: return "shortcut.splitDown"
            case .toggleSplitZoom: return "shortcut.toggleSplitZoom"
            case .splitBrowserRight: return "shortcut.splitBrowserRight"
            case .splitBrowserDown: return "shortcut.splitBrowserDown"
            case .nextSurface: return "shortcut.nextSurface"
            case .prevSurface: return "shortcut.prevSurface"
            case .selectSurfaceByNumber: return "shortcut.selectSurfaceByNumber"
            case .newSurface: return "shortcut.newSurface"
            case .toggleTerminalCopyMode: return "shortcut.toggleTerminalCopyMode"
            case .openBrowser: return "shortcut.openBrowser"
            case .toggleBrowserDeveloperTools: return "shortcut.toggleBrowserDeveloperTools"
            case .showBrowserJavaScriptConsole: return "shortcut.showBrowserJavaScriptConsole"
            case .toggleReactGrab: return "shortcut.toggleReactGrab"
            }
        }

        var defaultShortcut: StoredShortcut {
            switch self {
            case .toggleSidebar:
                return StoredShortcut(key: "b", command: true, shift: false, option: false, control: false)
            case .newTab:
                return StoredShortcut(key: "n", command: true, shift: false, option: false, control: false)
            case .newWindow:
                return StoredShortcut(key: "n", command: true, shift: true, option: false, control: false)
            case .closeWindow:
                return StoredShortcut(key: "w", command: true, shift: false, option: false, control: true)
            case .openFolder:
                return StoredShortcut(key: "o", command: true, shift: false, option: false, control: false)
            case .sendFeedback:
                return StoredShortcut(key: "f", command: true, shift: false, option: true, control: false)
            case .showNotifications:
                return StoredShortcut(key: "i", command: true, shift: false, option: false, control: false)
            case .jumpToUnread:
                return StoredShortcut(key: "u", command: true, shift: true, option: false, control: false)
            case .triggerFlash:
                return StoredShortcut(key: "h", command: true, shift: true, option: false, control: false)
            case .nextSidebarTab:
                return StoredShortcut(key: "]", command: true, shift: false, option: false, control: true)
            case .prevSidebarTab:
                return StoredShortcut(key: "[", command: true, shift: false, option: false, control: true)
            case .renameTab:
                return StoredShortcut(key: "r", command: true, shift: false, option: false, control: false)
            case .renameWorkspace:
                return StoredShortcut(key: "r", command: true, shift: true, option: false, control: false)
            case .closeWorkspace:
                return StoredShortcut(key: "w", command: true, shift: true, option: false, control: false)
            case .focusLeft:
                return StoredShortcut(key: "←", command: true, shift: false, option: true, control: false)
            case .focusRight:
                return StoredShortcut(key: "→", command: true, shift: false, option: true, control: false)
            case .focusUp:
                return StoredShortcut(key: "↑", command: true, shift: false, option: true, control: false)
            case .focusDown:
                return StoredShortcut(key: "↓", command: true, shift: false, option: true, control: false)
            case .splitRight:
                return StoredShortcut(key: "d", command: true, shift: false, option: false, control: false)
            case .splitDown:
                return StoredShortcut(key: "d", command: true, shift: true, option: false, control: false)
            case .toggleSplitZoom:
                return StoredShortcut(key: "\r", command: true, shift: true, option: false, control: false)
            case .splitBrowserRight:
                return StoredShortcut(key: "d", command: true, shift: false, option: true, control: false)
            case .splitBrowserDown:
                return StoredShortcut(key: "d", command: true, shift: true, option: true, control: false)
            case .nextSurface:
                return StoredShortcut(key: "]", command: true, shift: true, option: false, control: false)
            case .prevSurface:
                return StoredShortcut(key: "[", command: true, shift: true, option: false, control: false)
            case .selectSurfaceByNumber:
                return StoredShortcut(key: "1", command: false, shift: false, option: false, control: true)
            case .newSurface:
                return StoredShortcut(key: "t", command: true, shift: false, option: false, control: false)
            case .toggleTerminalCopyMode:
                return StoredShortcut(key: "m", command: true, shift: true, option: false, control: false)
            case .selectWorkspaceByNumber:
                return StoredShortcut(key: "1", command: true, shift: false, option: false, control: false)
            case .openBrowser:
                return StoredShortcut(key: "l", command: true, shift: true, option: false, control: false)
            case .toggleBrowserDeveloperTools:
                // Safari default: Show Web Inspector.
                return StoredShortcut(key: "i", command: true, shift: false, option: true, control: false)
            case .showBrowserJavaScriptConsole:
                // Safari default: Show JavaScript Console.
                return StoredShortcut(key: "c", command: true, shift: false, option: true, control: false)
            case .toggleReactGrab:
                return StoredShortcut(key: "g", command: true, shift: true, option: false, control: false)
            }
        }

        func tooltip(_ base: String) -> String {
            "\(base) (\(displayedShortcutString(for: KeyboardShortcutSettings.shortcut(for: self))))"
        }

        var usesNumberedDigitMatching: Bool {
            switch self {
            case .selectSurfaceByNumber, .selectWorkspaceByNumber:
                return true
            default:
                return false
            }
        }

        func displayedShortcutString(for shortcut: StoredShortcut) -> String {
            if usesNumberedDigitMatching {
                return shortcut.modifierDisplayString + "1…9"
            }
            return shortcut.displayString
        }

        func normalizedRecordedShortcut(_ shortcut: StoredShortcut) -> StoredShortcut? {
            guard usesNumberedDigitMatching else { return shortcut }
            guard let digit = Int(shortcut.key), (1...9).contains(digit) else {
                return nil
            }
            return StoredShortcut(
                key: "1",
                command: shortcut.command,
                shift: shortcut.shift,
                option: shortcut.option,
                control: shortcut.control
            )
        }
    }

    static func shortcut(for action: Action) -> StoredShortcut {
        guard let data = UserDefaults.standard.data(forKey: action.defaultsKey),
              let shortcut = try? JSONDecoder().decode(StoredShortcut.self, from: data) else {
            return action.defaultShortcut
        }
        return shortcut
    }

    static func setShortcut(_ shortcut: StoredShortcut, for action: Action) {
        let storedShortcut: StoredShortcut
        if let normalizedShortcut = action.normalizedRecordedShortcut(shortcut) {
            storedShortcut = normalizedShortcut
        } else if action.usesNumberedDigitMatching {
            return
        } else {
            storedShortcut = shortcut
        }

        if let data = try? JSONEncoder().encode(storedShortcut) {
            UserDefaults.standard.set(data, forKey: action.defaultsKey)
        }
        postDidChangeNotification(action: action)
    }

    static func resetShortcut(for action: Action) {
        UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        postDidChangeNotification(action: action)
    }

    static func resetAll() {
        for action in Action.allCases {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        }
        postDidChangeNotification()
    }

    private static func postDidChangeNotification(
        action: Action? = nil,
        center: NotificationCenter = .default
    ) {
        var userInfo: [AnyHashable: Any] = [:]
        if let action {
            userInfo[actionUserInfoKey] = action.rawValue
        }
        center.post(
            name: didChangeNotification,
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }

    // MARK: - Backwards-Compatible API (call-sites can migrate gradually)

    // Keys (used by debug socket command + UI tests)
    static let focusLeftKey = Action.focusLeft.defaultsKey
    static let focusRightKey = Action.focusRight.defaultsKey
    static let focusUpKey = Action.focusUp.defaultsKey
    static let focusDownKey = Action.focusDown.defaultsKey

    // Defaults (used by settings reset + recorder button initial title)
    static let showNotificationsDefault = Action.showNotifications.defaultShortcut
    static let jumpToUnreadDefault = Action.jumpToUnread.defaultShortcut

    static func showNotificationsShortcut() -> StoredShortcut { shortcut(for: .showNotifications) }
    static func setShowNotificationsShortcut(_ shortcut: StoredShortcut) { setShortcut(shortcut, for: .showNotifications) }

    static func jumpToUnreadShortcut() -> StoredShortcut { shortcut(for: .jumpToUnread) }
    static func setJumpToUnreadShortcut(_ shortcut: StoredShortcut) { setShortcut(shortcut, for: .jumpToUnread) }

    static func nextSidebarTabShortcut() -> StoredShortcut { shortcut(for: .nextSidebarTab) }
    static func prevSidebarTabShortcut() -> StoredShortcut { shortcut(for: .prevSidebarTab) }
    static func renameWorkspaceShortcut() -> StoredShortcut { shortcut(for: .renameWorkspace) }
    static func closeWorkspaceShortcut() -> StoredShortcut { shortcut(for: .closeWorkspace) }

    static func focusLeftShortcut() -> StoredShortcut { shortcut(for: .focusLeft) }
    static func focusRightShortcut() -> StoredShortcut { shortcut(for: .focusRight) }
    static func focusUpShortcut() -> StoredShortcut { shortcut(for: .focusUp) }
    static func focusDownShortcut() -> StoredShortcut { shortcut(for: .focusDown) }

    static func splitRightShortcut() -> StoredShortcut { shortcut(for: .splitRight) }
    static func splitDownShortcut() -> StoredShortcut { shortcut(for: .splitDown) }
    static func toggleSplitZoomShortcut() -> StoredShortcut { shortcut(for: .toggleSplitZoom) }
    static func splitBrowserRightShortcut() -> StoredShortcut { shortcut(for: .splitBrowserRight) }
    static func splitBrowserDownShortcut() -> StoredShortcut { shortcut(for: .splitBrowserDown) }

    static func nextSurfaceShortcut() -> StoredShortcut { shortcut(for: .nextSurface) }
    static func prevSurfaceShortcut() -> StoredShortcut { shortcut(for: .prevSurface) }
    static func selectSurfaceByNumberShortcut() -> StoredShortcut { shortcut(for: .selectSurfaceByNumber) }
    static func newSurfaceShortcut() -> StoredShortcut { shortcut(for: .newSurface) }
    static func selectWorkspaceByNumberShortcut() -> StoredShortcut { shortcut(for: .selectWorkspaceByNumber) }

    static func openBrowserShortcut() -> StoredShortcut { shortcut(for: .openBrowser) }
    static func toggleBrowserDeveloperToolsShortcut() -> StoredShortcut { shortcut(for: .toggleBrowserDeveloperTools) }
    static func showBrowserJavaScriptConsoleShortcut() -> StoredShortcut { shortcut(for: .showBrowserJavaScriptConsole) }
}

enum SystemWideHotkeySettings {
    static let enabledKey = "systemWideHotkey.enabled"
    static let shortcutKey = "systemWideHotkey.shortcut"
    static let defaultEnabled = false
    static let defaultShortcut = StoredShortcut(key: ".", command: true, shift: false, option: false, control: false)

    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? defaultEnabled
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func shortcut(defaults: UserDefaults = .standard) -> StoredShortcut {
        guard let data = defaults.data(forKey: shortcutKey),
              let shortcut = try? JSONDecoder().decode(StoredShortcut.self, from: data),
              isValid(shortcut) else {
            return defaultShortcut
        }
        return shortcut
    }

    static func setShortcut(_ shortcut: StoredShortcut, defaults: UserDefaults = .standard) {
        guard let normalizedShortcut = normalizedRecordedShortcut(shortcut),
              let data = try? JSONEncoder().encode(normalizedShortcut) else {
            return
        }
        defaults.set(data, forKey: shortcutKey)
    }

    static func normalizedRecordedShortcut(_ shortcut: StoredShortcut) -> StoredShortcut? {
        isValid(shortcut) ? shortcut : nil
    }

    static func isValid(_ shortcut: StoredShortcut) -> Bool {
        shortcut.hasPrimaryModifier
    }

    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let accessibilitySettingsURL else { return }
        NSWorkspace.shared.open(accessibilitySettingsURL)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: shortcutKey)
    }
}

final class SystemWideHotkeyController {
    static let shared = SystemWideHotkeyController()

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var defaultsObserver: NSObjectProtocol?
    private var applicationDidBecomeActiveObserver: NSObjectProtocol?
    private var isShortcutRecordingActive = false
    private var isEnabled = SystemWideHotkeySettings.defaultEnabled
    private var shortcut = SystemWideHotkeySettings.defaultShortcut

    private init() {}

    func start() {
        guard defaultsObserver == nil else { return }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRegistration(promptIfNeeded: false)
        }

        applicationDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRegistration(promptIfNeeded: false)
        }

        refreshRegistration(promptIfNeeded: false)
    }

    @discardableResult
    func requestAccessibilityAccess() -> Bool {
        let trusted = SystemWideHotkeySettings.isAccessibilityTrusted(prompt: true)
        refreshRegistration(promptIfNeeded: false)
        return trusted
    }

    func setShortcutRecordingActive(_ isActive: Bool) {
        isShortcutRecordingActive = isActive
    }

    private func refreshRegistration(promptIfNeeded: Bool) {
        isEnabled = SystemWideHotkeySettings.isEnabled()
        shortcut = SystemWideHotkeySettings.shortcut()

        guard isEnabled else {
            uninstallEventTap()
            return
        }

        guard SystemWideHotkeySettings.isAccessibilityTrusted(prompt: promptIfNeeded) else {
            uninstallEventTap()
            return
        }

        installEventTapIfNeeded()
    }

    private func installEventTapIfNeeded() {
        guard eventTap == nil else { return }

        let eventMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            return
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            return
        }

        self.eventTap = eventTap
        eventTapRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func uninstallEventTap() {
        if let runLoopSource = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            eventTapRunLoopSource = nil
        }

        if let eventTap = eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<SystemWideHotkeyController>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return controller.handleEventTap(type: type, event: event)
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, isEnabled, !isShortcutRecordingActive else {
            return Unmanaged.passUnretained(event)
        }

        guard matchesShortcut(event) else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.toggleApplicationVisibility()
            }
        }

        return nil
    }

    private func matchesShortcut(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let eventModifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        let eventCharacter = NSEvent(cgEvent: event)?.charactersIgnoringModifiers

        return shortcut.matches(
            keyCode: keyCode,
            modifierFlags: eventModifiers,
            eventCharacter: eventCharacter
        )
    }

    private func toggleApplicationVisibility() {
        if NSApp.isActive {
            NSApp.hide(nil)
            return
        }

        showAllApplicationWindows()
    }

    private func showAllApplicationWindows() {
        NSApp.unhide(nil)

        let windowsToReveal = NSApp.windows.filter { $0.isVisible || $0.isMiniaturized }
        for window in windowsToReveal where window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        let focusWindow = preferredFocusWindow(from: windowsToReveal)
        focusWindow?.orderFrontRegardless()
        focusWindow?.makeKeyAndOrderFront(nil)

        for window in windowsToReveal where window !== focusWindow {
            window.orderFrontRegardless()
        }
    }

    private func preferredFocusWindow(from windows: [NSWindow]) -> NSWindow? {
        if let keyWindow = NSApp.keyWindow,
           windows.contains(where: { $0 === keyWindow }) {
            return keyWindow
        }

        if let mainWindow = NSApp.mainWindow,
           windows.contains(where: { $0 === mainWindow }) {
            return mainWindow
        }

        return windows.first(where: \.canBecomeMain)
            ?? windows.first(where: \.canBecomeKey)
            ?? windows.first
    }
}

/// A keyboard shortcut that can be stored in UserDefaults
struct StoredShortcut: Codable, Equatable {
    var key: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    var displayString: String {
        modifierDisplayString + keyDisplayString
    }

    var modifierDisplayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        return parts.joined()
    }

    var keyDisplayString: String {
        switch key {
        case "\t":
            return "TAB"
        case "\r":
            return "↩"
        default:
            return key.uppercased()
        }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    var hasPrimaryModifier: Bool {
        command || option || control
    }

    var keyEquivalent: KeyEquivalent? {
        switch key {
        case "←":
            return .leftArrow
        case "→":
            return .rightArrow
        case "↑":
            return .upArrow
        case "↓":
            return .downArrow
        case "\t":
            return .tab
        case "\r":
            return KeyEquivalent(Character("\r"))
        default:
            let lowered = key.lowercased()
            guard lowered.count == 1, let character = lowered.first else { return nil }
            return KeyEquivalent(character)
        }
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if command {
            modifiers.insert(.command)
        }
        if shift {
            modifiers.insert(.shift)
        }
        if option {
            modifiers.insert(.option)
        }
        if control {
            modifiers.insert(.control)
        }
        return modifiers
    }

    var menuItemKeyEquivalent: String? {
        switch key {
        case "←":
            guard let scalar = UnicodeScalar(NSLeftArrowFunctionKey) else { return nil }
            return String(Character(scalar))
        case "→":
            guard let scalar = UnicodeScalar(NSRightArrowFunctionKey) else { return nil }
            return String(Character(scalar))
        case "↑":
            guard let scalar = UnicodeScalar(NSUpArrowFunctionKey) else { return nil }
            return String(Character(scalar))
        case "↓":
            guard let scalar = UnicodeScalar(NSDownArrowFunctionKey) else { return nil }
            return String(Character(scalar))
        case "\t":
            return "\t"
        case "\r":
            return "\r"
        default:
            let lowered = key.lowercased()
            guard lowered.count == 1 else { return nil }
            return lowered
        }
    }

    static func from(event: NSEvent) -> StoredShortcut? {
        guard let key = storedKey(from: event) else { return nil }

        let flags = normalizedModifierFlags(from: event.modifierFlags)

        let shortcut = StoredShortcut(
            key: key,
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )

        // Avoid recording plain typing; require at least one modifier.
        if !shortcut.command && !shortcut.shift && !shortcut.option && !shortcut.control {
            return nil
        }
        return shortcut
    }

    static func normalizedModifierFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
    }

    func matches(
        event: NSEvent,
        layoutCharacterProvider: (UInt16, NSEvent.ModifierFlags) -> String? = KeyboardLayout.character(forKeyCode:modifierFlags:)
    ) -> Bool {
        matches(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            eventCharacter: event.charactersIgnoringModifiers,
            layoutCharacterProvider: layoutCharacterProvider
        )
    }

    func matches(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventCharacter: String?,
        layoutCharacterProvider: (UInt16, NSEvent.ModifierFlags) -> String? = KeyboardLayout.character(forKeyCode:modifierFlags:)
    ) -> Bool {
        let flags = StoredShortcut.normalizedModifierFlags(from: modifierFlags)
        guard flags == self.modifierFlags else { return false }

        let shortcutKey = key.lowercased()
        if shortcutKey == "\r" {
            return keyCode == 36 || keyCode == 76
        }

        if StoredShortcut.shortcutCharacterMatches(
            eventCharacter: eventCharacter,
            shortcutKey: shortcutKey,
            applyShiftSymbolNormalization: flags.contains(.shift),
            eventKeyCode: keyCode
        ) {
            return true
        }

        let hasEventChars = !(eventCharacter?.isEmpty ?? true)
        let eventCharsAreASCII = eventCharacter?.allSatisfy(\.isASCII) ?? true
        if hasEventChars,
           eventCharsAreASCII,
           flags.contains(.command),
           !flags.contains(.control),
           StoredShortcut.shouldRequireCharacterMatchForCommandShortcut(shortcutKey: shortcutKey) {
            return false
        }

        let layoutCharacter = layoutCharacterProvider(keyCode, modifierFlags)
        if StoredShortcut.shortcutCharacterMatches(
            eventCharacter: layoutCharacter,
            shortcutKey: shortcutKey,
            applyShiftSymbolNormalization: false,
            eventKeyCode: keyCode
        ) {
            return true
        }

        let allowANSIKeyCodeFallback = flags.contains(.control)
            || (flags.contains(.command)
                && !flags.contains(.control)
                && (
                    !StoredShortcut.shouldRequireCharacterMatchForCommandShortcut(shortcutKey: shortcutKey)
                        || (hasEventChars && !eventCharsAreASCII)
                        || (!hasEventChars && (layoutCharacter?.isEmpty ?? true))
                ))
        if allowANSIKeyCodeFallback,
           let expectedKeyCode = StoredShortcut.keyCodeForShortcutKey(shortcutKey) {
            return keyCode == expectedKeyCode
        }

        return false
    }

    private static func storedKey(from event: NSEvent) -> String? {
        storedKey(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        )
    }

    private static func storedKey(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?
    ) -> String? {
        // Prefer keyCode mapping so shifted symbol keys (e.g. "}") record as "]".
        switch keyCode {
        case 123: return "←" // left arrow
        case 124: return "→" // right arrow
        case 125: return "↓" // down arrow
        case 126: return "↑" // up arrow
        case 48: return "\t" // tab
        case 36, 76: return "\r" // return, keypad enter
        case 33: return "["  // kVK_ANSI_LeftBracket
        case 30: return "]"  // kVK_ANSI_RightBracket
        case 27: return "-"  // kVK_ANSI_Minus
        case 24: return "="  // kVK_ANSI_Equal
        case 43: return ","  // kVK_ANSI_Comma
        case 47: return "."  // kVK_ANSI_Period
        case 44: return "/"  // kVK_ANSI_Slash
        case 41: return ";"  // kVK_ANSI_Semicolon
        case 39: return "'"  // kVK_ANSI_Quote
        case 50: return "`"  // kVK_ANSI_Grave
        case 42: return "\\" // kVK_ANSI_Backslash
        default:
            break
        }

        guard let chars = charactersIgnoringModifiers?.lowercased(),
              let char = chars.first else {
            return nil
        }

        // Allow letters/numbers; everything else should be handled by keyCode mapping above.
        if char.isLetter || char.isNumber {
            return String(char)
        }
        return nil
    }

    static func normalizedShortcutEventCharacter(
        _ eventCharacter: String,
        applyShiftSymbolNormalization: Bool,
        eventKeyCode: UInt16
    ) -> String {
        let lowered = eventCharacter.lowercased()
        guard applyShiftSymbolNormalization else { return lowered }

        switch lowered {
        case "{": return "["
        case "}": return "]"
        case "<": return eventKeyCode == 43 ? "," : lowered // kVK_ANSI_Comma
        case ">": return eventKeyCode == 47 ? "." : lowered // kVK_ANSI_Period
        case "?": return "/"
        case ":": return ";"
        case "\"": return "'"
        case "|": return "\\"
        case "~": return "`"
        case "+": return "="
        case "_": return "-"
        case "!": return eventKeyCode == 18 ? "1" : lowered // kVK_ANSI_1
        case "@": return eventKeyCode == 19 ? "2" : lowered // kVK_ANSI_2
        case "#": return eventKeyCode == 20 ? "3" : lowered // kVK_ANSI_3
        case "$": return eventKeyCode == 21 ? "4" : lowered // kVK_ANSI_4
        case "%": return eventKeyCode == 23 ? "5" : lowered // kVK_ANSI_5
        case "^": return eventKeyCode == 22 ? "6" : lowered // kVK_ANSI_6
        case "&": return eventKeyCode == 26 ? "7" : lowered // kVK_ANSI_7
        case "*": return eventKeyCode == 28 ? "8" : lowered // kVK_ANSI_8
        case "(": return eventKeyCode == 25 ? "9" : lowered // kVK_ANSI_9
        case ")": return eventKeyCode == 29 ? "0" : lowered // kVK_ANSI_0
        default: return lowered
        }
    }

    private static func shouldRequireCharacterMatchForCommandShortcut(shortcutKey: String) -> Bool {
        guard shortcutKey.count == 1, let scalar = shortcutKey.unicodeScalars.first else {
            return false
        }
        return CharacterSet.letters.contains(scalar)
    }

    private static func shortcutCharacterMatches(
        eventCharacter: String?,
        shortcutKey: String,
        applyShiftSymbolNormalization: Bool,
        eventKeyCode: UInt16
    ) -> Bool {
        guard let eventCharacter, !eventCharacter.isEmpty else { return false }
        return normalizedShortcutEventCharacter(
            eventCharacter,
            applyShiftSymbolNormalization: applyShiftSymbolNormalization,
            eventKeyCode: eventKeyCode
        ) == shortcutKey
    }

    private static func keyCodeForShortcutKey(_ key: String) -> UInt16? {
        switch key {
        case "a": return 0
        case "s": return 1
        case "d": return 2
        case "f": return 3
        case "h": return 4
        case "g": return 5
        case "z": return 6
        case "x": return 7
        case "c": return 8
        case "v": return 9
        case "b": return 11
        case "q": return 12
        case "w": return 13
        case "e": return 14
        case "r": return 15
        case "y": return 16
        case "t": return 17
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "6": return 22
        case "5": return 23
        case "=": return 24
        case "9": return 25
        case "7": return 26
        case "-": return 27
        case "8": return 28
        case "0": return 29
        case "]": return 30
        case "o": return 31
        case "u": return 32
        case "[": return 33
        case "i": return 34
        case "p": return 35
        case "l": return 37
        case "j": return 38
        case "'": return 39
        case "k": return 40
        case ";": return 41
        case "\\": return 42
        case ",": return 43
        case "/": return 44
        case "n": return 45
        case "m": return 46
        case ".": return 47
        case "\t": return 48
        case "`": return 50
        case "←": return 123
        case "→": return 124
        case "↓": return 125
        case "↑": return 126
        default:
            return nil
        }
    }
}

/// View for recording a keyboard shortcut
struct KeyboardShortcutRecorder: View {
    let label: String
    @Binding var shortcut: StoredShortcut
    var displayString: (StoredShortcut) -> String = { $0.displayString }
    var transformRecordedShortcut: (StoredShortcut) -> StoredShortcut? = { $0 }
    var onRecordingChanged: (Bool) -> Void = { _ in }
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(label)

            Spacer()

            ShortcutRecorderButton(
                shortcut: $shortcut,
                isRecording: $isRecording,
                displayString: displayString,
                transformRecordedShortcut: transformRecordedShortcut,
                onRecordingChanged: onRecordingChanged
            )
                .frame(width: 120)
        }
    }
}

private struct ShortcutRecorderButton: NSViewRepresentable {
    @Binding var shortcut: StoredShortcut
    @Binding var isRecording: Bool
    let displayString: (StoredShortcut) -> String
    let transformRecordedShortcut: (StoredShortcut) -> StoredShortcut?
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSButton {
        let button = ShortcutRecorderNSButton()
        button.shortcut = shortcut
        button.displayString = displayString
        button.transformRecordedShortcut = transformRecordedShortcut
        button.onShortcutRecorded = { newShortcut in
            shortcut = newShortcut
            isRecording = false
        }
        button.onRecordingChanged = { recording in
            isRecording = recording
            onRecordingChanged(recording)
        }
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderNSButton, context: Context) {
        nsView.shortcut = shortcut
        nsView.displayString = displayString
        nsView.transformRecordedShortcut = transformRecordedShortcut
        nsView.onRecordingChanged = { recording in
            isRecording = recording
            onRecordingChanged(recording)
        }
        nsView.updateTitle()
    }
}

private class ShortcutRecorderNSButton: NSButton {
    var shortcut: StoredShortcut = KeyboardShortcutSettings.showNotificationsDefault
    var displayString: (StoredShortcut) -> String = { $0.displayString }
    var transformRecordedShortcut: (StoredShortcut) -> StoredShortcut? = { $0 }
    var onShortcutRecorded: ((StoredShortcut) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private var isRecording = false
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(buttonClicked)
        updateTitle()
    }

    func updateTitle() {
        if isRecording {
            title = String(localized: "shortcut.pressShortcut.prompt", defaultValue: "Press shortcut…")
        } else {
            title = displayString(shortcut)
        }
    }

    @objc private func buttonClicked() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        onRecordingChanged?(true)
        updateTitle()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if event.keyCode == 53 { // Escape
                self.stopRecording()
                return nil
            }

            if let newShortcut = StoredShortcut.from(event: event) {
                guard let transformedShortcut = self.transformRecordedShortcut(newShortcut) else {
                    NSSound.beep()
                    return nil
                }
                self.shortcut = transformedShortcut
                self.onShortcutRecorded?(transformedShortcut)
                self.stopRecording()
                return nil
            }

            // Consume unsupported keys while recording to avoid triggering app shortcuts.
            return nil
        }

        // Also stop recording if window loses focus
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowResigned),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    private func stopRecording() {
        isRecording = false
        onRecordingChanged?(false)
        updateTitle()

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
    }

    @objc private func windowResigned() {
        stopRecording()
    }

    deinit {
        stopRecording()
    }
}
