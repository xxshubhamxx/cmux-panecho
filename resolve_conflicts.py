import re

def resolve_file(filepath, our_logic):
    with open(filepath, 'r') as f:
        content = f.read()

    # Find conflict blocks
    conflict_pattern = re.compile(r'<<<<<<< LEFT\n(.*?)(?:\|\|\|\|\|\|\| BASE\n.*?)?=======\n(.*?)\n>>>>>>> RIGHT\n', re.DOTALL)
    
    def replacer(match):
        left = match.group(1)
        right = match.group(2)
        return our_logic(filepath, left, right)
        
    new_content = conflict_pattern.sub(replacer, content)
    with open(filepath, 'w') as f:
        f.write(new_content)

def logic(filepath, left, right):
    if "MenuBarExtraController.swift" in filepath:
        # Keep Panecho branding (left) + taskManagerItem (right)
        if "showMainWindowItem" in left and "taskManagerItem" in right:
            return left + "    private let taskManagerItem = NSMenuItem(title: String(localized: \"statusMenu.taskManager\", defaultValue: \"Task Manager...\"), action: nil, keyEquivalent: \"\")\n"
        return left
    elif "KeyboardShortcutSettingsFileStore.swift" in filepath:
        # Remove telemetry but keep iMessageMode
        if "iMessageMode" in right:
            res = ""
            if "snapshot.managedUserDefaults[IMessageModeSettings.key]" in right:
                res = "        }\n        if let value = jsonBool(section[\"iMessageMode\"]) {\n            snapshot.managedUserDefaults[IMessageModeSettings.key] = .bool(value)\n"
                return res
            elif "IMessageModeSettings.defaultValue" in right:
                res = "                    \"iMessageMode\": IMessageModeSettings.defaultValue,\n"
                return res
        return left
    elif "Workspace.swift" in filepath:
        if "showMoveTabFailureAlert()" in right:
            return left
        return left
    elif "cmuxApp.swift" in filepath:
        if "geminiIntegration" in left or "settings.automation.gemini" in left or "automation.geminiIntegration" in left:
            if "cmux hooks" in right:
                # Merge logic: left has privacyModeBranded note. Right updated the command to cmux hooks ... install.
                res = left.replace("`cmux cursor install-hooks`", "`cmux hooks cursor install`")
                res = res.replace("`cmux gemini install-hooks`", "`cmux hooks gemini install`")
                # Ensure the privacy wrapper remains for the gemini/cursor note
                return res
        return left
    return left

for f in ["Sources/App/MenuBarExtraController.swift", "Sources/KeyboardShortcutSettingsFileStore.swift", "Sources/Workspace.swift", "Sources/cmuxApp.swift"]:
    resolve_file(f, logic)

