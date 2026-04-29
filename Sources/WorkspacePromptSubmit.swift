import Foundation

enum IMessageModeSettings {
    static let key = "iMessageMode"
    static let defaultValue = false

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}

extension TabManager {
    @discardableResult
    func handlePromptSubmit(
        workspaceId: UUID,
        message: String?,
        iMessageModeEnabled: Bool = IMessageModeSettings.isEnabled()
    ) -> (messageRecorded: Bool, reordered: Bool, index: Int)? {
        guard let originalIndex = tabs.firstIndex(where: { $0.id == workspaceId }) else {
            return nil
        }
        guard iMessageModeEnabled else {
            return (false, false, originalIndex)
        }

        let workspace = tabs[originalIndex]
        let messageRecorded = workspace.recordSubmittedMessage(message)
        moveTabToTop(workspaceId)
        let newIndex = tabs.firstIndex(where: { $0.id == workspaceId }) ?? originalIndex
        return (messageRecorded, newIndex != originalIndex, newIndex)
    }
}

extension Workspace {
    static func submittedMessagePreview(from message: String?, maxLength: Int = 240) -> String? {
        guard let message else { return nil }
        let collapsed = message
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxLength else { return collapsed }
        return "\(collapsed.prefix(maxLength))..."
    }
}
