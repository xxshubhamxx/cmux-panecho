import AppKit
import Darwin
import Foundation

enum BrowserEngineKind: String, Codable, Sendable {
    case webkit
    case cef
}

struct CEFEngineInstallation: Equatable, Sendable {
    let frameworkURL: URL
    let helperAppURL: URL?
    let sourceDescription: String
}

private struct CEFRuntimeManifest: Codable, Equatable, Sendable {
    let sourceDescription: String
    let frameworkRelativePath: String
    let helperRelativePaths: [String]
}

private func isDefaultCEFHelperAppName(_ name: String) -> Bool {
    name.hasSuffix(" Helper.app") && !name.contains(" (")
}

private func preferredCEFHelperApp(from candidates: [URL]) -> URL? {
    candidates.first(where: { isDefaultCEFHelperAppName($0.lastPathComponent) })
        ?? candidates.first(where: { $0.lastPathComponent == "cmux Helper.app" })
        ?? candidates.first(where: { $0.lastPathComponent == "cefclient Helper.app" })
        ?? candidates.first
}

struct CEFEngineRuntimeStatus: Equatable, Sendable {
    let isRuntimeLinked: Bool
    let installation: CEFEngineInstallation?
    let isFrameworkLoaded: Bool
    let frameworkLoadErrorDescription: String?
    let isRuntimeStarted: Bool
    let runtimeStartErrorDescription: String?
    let allowUnlinkedSurface: Bool

    var hasRuntimeAssets: Bool {
        installation != nil
    }

    var canUseLinkedRuntime: Bool {
        isRuntimeLinked && isFrameworkLoaded && isRuntimeStarted && hasRuntimeAssets
    }

    var hasLoadableRuntime: Bool {
        isFrameworkLoaded && isRuntimeStarted && hasRuntimeAssets
    }

    var canPresentSurface: Bool {
        hasLoadableRuntime || allowUnlinkedSurface
    }
}

enum BrowserEngineFeatureFlags {
    static let engineEnvironmentKey = "CMUX_BROWSER_ENGINE"
    static let engineDefaultsKey = "BrowserEngine"
    static let remoteEngineEnvironmentKey = "CMUX_REMOTE_BROWSER_ENGINE"
    static let remoteEngineDefaultsKey = "BrowserRemoteEngine"
    static let allowUnlinkedCEFEnvironmentKey = "CMUX_CEF_FORCE_SURFACE"
    static let allowUnlinkedCEFDefaultsKey = "BrowserAllowUnlinkedCEFSurface"

    static func preferredEngineKind(
        isRemoteWorkspace: Bool,
        environmentOverride: String? = nil,
        defaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) -> BrowserEngineKind {
        if let globalOverride = parseEngineKind(
            rawValue: processInfo.environment[engineEnvironmentKey]
                ?? defaults.string(forKey: engineDefaultsKey)
        ) {
            return globalOverride
        }
        guard isRemoteWorkspace else { return .webkit }
        return parseEngineKind(
            rawValue: environmentOverride
                ?? processInfo.environment[remoteEngineEnvironmentKey]
                ?? defaults.string(forKey: remoteEngineDefaultsKey)
        ) ?? .webkit
    }

    static func effectiveEngineKind(
        isRemoteWorkspace: Bool,
        runtimeStatus: CEFEngineRuntimeStatus,
        environmentOverride: String? = nil,
        defaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) -> BrowserEngineKind {
        let preferred = preferredEngineKind(
            isRemoteWorkspace: isRemoteWorkspace,
            environmentOverride: environmentOverride,
            defaults: defaults,
            processInfo: processInfo
        )
        guard preferred == .cef else { return .webkit }
        return runtimeStatus.canPresentSurface ? .cef : .webkit
    }

    static func allowUnlinkedCEFSurface(
        defaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) -> Bool {
        parseBoolFlag(
            rawValue: processInfo.environment[allowUnlinkedCEFEnvironmentKey]
                ?? defaults.string(forKey: allowUnlinkedCEFDefaultsKey)
        ) ?? false
    }

    static func parseEngineKind(rawValue: String?) -> BrowserEngineKind? {
        guard let rawValue else { return nil }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "webkit", "webkitview", "wkwebview":
            return .webkit
        case "cef", "chromium":
            return .cef
        default:
            return nil
        }
    }

    static func parseBoolFlag(rawValue: String?) -> Bool? {
        guard let rawValue else { return nil }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }
}

@MainActor
final class CEFEngineRuntime {
    static let shared = CEFEngineRuntime()

    private struct FrameworkLoadResult {
        let isLoaded: Bool
        let errorDescription: String?
    }

    private var frameworkLoadResultsByPath: [String: FrameworkLoadResult] = [:]

    private init() {}

    var isRuntimeLinked: Bool {
        CEFWorkspaceBridge.isRuntimeLinked()
    }

    func runtimeStatus(
        startGlobalRuntime: Bool = false,
        defaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default,
        mainBundle: Bundle = .main
    ) -> CEFEngineRuntimeStatus {
        let installation = discoverInstallation(
            fileManager: fileManager,
            processInfo: processInfo,
            mainBundle: mainBundle
        )
        let frameworkLoadResult = installation.map { loadFrameworkIfNeeded(at: $0.frameworkURL) }
        let runtimeStartResult = installation.flatMap {
            startGlobalRuntime && (frameworkLoadResult?.isLoaded ?? false)
                ? startRuntimeIfNeeded(
                    installation: $0,
                    mainBundle: mainBundle,
                    processInfo: processInfo
                )
                : nil
        }
        return CEFEngineRuntimeStatus(
            isRuntimeLinked: isRuntimeLinked,
            installation: installation,
            isFrameworkLoaded: frameworkLoadResult?.isLoaded ?? false,
            frameworkLoadErrorDescription: frameworkLoadResult?.errorDescription,
            isRuntimeStarted: runtimeStartResult?.isStarted ?? false,
            runtimeStartErrorDescription: runtimeStartResult?.errorDescription,
            allowUnlinkedSurface: BrowserEngineFeatureFlags.allowUnlinkedCEFSurface(
                defaults: defaults,
                processInfo: processInfo
            )
        )
    }

    func makeBridge(
        workspaceId: UUID,
        initialURL: URL?,
        proxyEndpoint: BrowserProxyEndpoint?
    ) -> CEFWorkspaceBridge {
        let visibleURLString = initialURL?.absoluteString ?? "about:blank"
        let proxyHost = proxyEndpoint?.host ?? "127.0.0.1"
        let proxyPort = Int32(proxyEndpoint?.port ?? 0)
        let cachePath = bridgeCachePath(for: workspaceId).path
        let installation = discoverInstallation(
            fileManager: .default,
            processInfo: .processInfo,
            mainBundle: .main
        )
        let frameworkPath = installation?.frameworkURL.path ?? ""
        let helperAppPath = installation?.helperAppURL?.path
        let mainBundlePath = Bundle.main.bundleURL.path
        return CEFWorkspaceBridge(
            visibleURLString: visibleURLString,
            socksProxyHost: proxyHost,
            socksProxyPort: proxyPort,
            cachePath: cachePath,
            frameworkPath: frameworkPath,
            helperAppPath: helperAppPath,
            mainBundlePath: mainBundlePath,
            runtimeCacheRootPath: runtimeCacheRootPath().path
        )
    }

    private func bridgeCachePath(for workspaceId: UUID) -> URL {
        runtimeCacheRootPath()
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(workspaceId.uuidString, isDirectory: true)
    }

    private func runtimeCacheRootPath(
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> URL {
        let basePath = canonicalExistingPath(fileManager.temporaryDirectory.path)
        return URL(fileURLWithPath: basePath, isDirectory: true)
            .appendingPathComponent("cmux-cef-runtime", isDirectory: true)
            .appendingPathComponent(String(processInfo.processIdentifier), isDirectory: true)
    }

    private func canonicalExistingPath(_ path: String) -> String {
        path.withCString { cPath in
            guard let resolvedPath = realpath(cPath, nil) else {
                return path
            }
            defer { free(resolvedPath) }
            return String(cString: resolvedPath)
        }
    }

    private struct RuntimeStartResult {
        let isStarted: Bool
        let errorDescription: String?
    }

    private func startRuntimeIfNeeded(
        installation: CEFEngineInstallation,
        mainBundle: Bundle,
        processInfo: ProcessInfo
    ) -> RuntimeStartResult {
        var errorDescription: NSString?
        let started = CEFWorkspaceBridge.ensureGlobalRuntime(
            withFrameworkPath: installation.frameworkURL.path,
            helperAppPath: installation.helperAppURL?.path,
            mainBundlePath: mainBundle.bundleURL.path,
            runtimeCacheRootPath: runtimeCacheRootPath(processInfo: processInfo).path,
            errorDescription: &errorDescription
        )
        return RuntimeStartResult(
            isStarted: started,
            errorDescription: errorDescription as String?
        )
    }

    private func discoverInstallation(
        fileManager: FileManager,
        processInfo: ProcessInfo,
        mainBundle: Bundle
    ) -> CEFEngineInstallation? {
        for candidate in candidateSearchRoots(processInfo: processInfo, mainBundle: mainBundle) {
            if let installation = resolveInstallation(
                from: candidate.url,
                sourceDescription: candidate.sourceDescription,
                fileManager: fileManager
            ) {
                return installation
            }
        }
        return nil
    }

    private func candidateSearchRoots(
        processInfo: ProcessInfo,
        mainBundle: Bundle
    ) -> [(url: URL, sourceDescription: String)] {
        var candidates: [(URL, String)] = []

        let env = processInfo.environment
        if let raw = env["CMUX_CEF_FRAMEWORK_DIR"], !raw.isEmpty {
            candidates.append((URL(fileURLWithPath: raw), "env:CMUX_CEF_FRAMEWORK_DIR"))
        }
        if let raw = env["CMUX_CEF_APP_BUNDLE"], !raw.isEmpty {
            candidates.append((URL(fileURLWithPath: raw), "env:CMUX_CEF_APP_BUNDLE"))
        }
        if let raw = env["CMUX_CEF_SDK_ROOT"], !raw.isEmpty {
            candidates.append((URL(fileURLWithPath: raw), "env:CMUX_CEF_SDK_ROOT"))
        }

        if let frameworksURL = mainBundle.privateFrameworksURL {
            candidates.append((frameworksURL, "bundle:PrivateFrameworks"))
        }
        if let builtInPlugInsURL = mainBundle.builtInPlugInsURL {
            candidates.append((builtInPlugInsURL, "bundle:PlugIns"))
        }
        if let resourceURL = mainBundle.resourceURL {
            candidates.append((
                resourceURL.appendingPathComponent("CEFRuntime", isDirectory: true),
                "bundle:Resources/CEFRuntime"
            ))
        }

        candidates.append((
            URL(fileURLWithPath: "/tmp/cef-sdk", isDirectory: true),
            "cache:/tmp/cef-sdk"
        ))

        let homeCache = fileManagerHomeCacheDirectory()
        candidates.append((
            homeCache.appendingPathComponent("cmux-cef-probe", isDirectory: true),
            "cache:~/Library/Caches/cmux-cef-probe"
        ))

        return candidates
    }

    private func fileManagerHomeCacheDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
    }

    private func resolveInstallation(
        from candidateURL: URL,
        sourceDescription: String,
        fileManager: FileManager
    ) -> CEFEngineInstallation? {
        let standardized = candidateURL.standardizedFileURL

        if let manifestInstallation = resolveManifestInstallation(
            from: standardized,
            fileManager: fileManager
        ) {
            return manifestInstallation
        }

        let rootsToProbe = probeRoots(for: standardized)
        for root in rootsToProbe {
            guard let frameworkURL = frameworkURL(in: root, fileManager: fileManager) else { continue }
            return CEFEngineInstallation(
                frameworkURL: frameworkURL,
                helperAppURL: helperAppURL(near: frameworkURL.deletingLastPathComponent(), fileManager: fileManager),
                sourceDescription: sourceDescription
            )
        }
        return nil
    }

    private func resolveManifestInstallation(
        from candidateURL: URL,
        fileManager: FileManager
    ) -> CEFEngineInstallation? {
        let manifestURL = candidateURL.appendingPathComponent("runtime-manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(CEFRuntimeManifest.self, from: data) else {
            return nil
        }

        let frameworkURL = candidateURL.appendingPathComponent(
            manifest.frameworkRelativePath,
            isDirectory: true
        ).standardizedFileURL
        guard fileManager.fileExists(atPath: frameworkURL.path) else {
            return nil
        }

        let helperCandidates = manifest.helperRelativePaths
            .map { candidateURL.appendingPathComponent($0, isDirectory: true).standardizedFileURL }
            .filter { fileManager.fileExists(atPath: $0.path) }
        let helperURL = preferredCEFHelperApp(from: helperCandidates)

        return CEFEngineInstallation(
            frameworkURL: frameworkURL,
            helperAppURL: helperURL,
            sourceDescription: manifest.sourceDescription
        )
    }

    private func probeRoots(for candidateURL: URL) -> [URL] {
        var roots = [candidateURL]

        if candidateURL.pathExtension == "app" {
            roots.append(candidateURL.appendingPathComponent("Contents/Frameworks", isDirectory: true))
        } else {
            roots.append(candidateURL.appendingPathComponent("Release", isDirectory: true))
            roots.append(candidateURL.appendingPathComponent("Contents/Frameworks", isDirectory: true))
            roots.append(candidateURL.appendingPathComponent("Frameworks", isDirectory: true))
            roots.append(candidateURL.appendingPathComponent("Helpers", isDirectory: true))
        }

        return roots
    }

    private func frameworkURL(in root: URL, fileManager: FileManager) -> URL? {
        let directFramework = root.appendingPathComponent(
            "Chromium Embedded Framework.framework",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: directFramework.path) {
            return directFramework
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for child in children where child.pathExtension == "app" {
            let nestedFramework = child
                .appendingPathComponent("Contents/Frameworks", isDirectory: true)
                .appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)
            if fileManager.fileExists(atPath: nestedFramework.path) {
                return nestedFramework
            }
        }

        for child in children {
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
                continue
            }
            let nestedFramework = child.appendingPathComponent(
                "Chromium Embedded Framework.framework",
                isDirectory: true
            )
            if fileManager.fileExists(atPath: nestedFramework.path) {
                return nestedFramework
            }
        }

        return nil
    }

    private func helperAppURL(near frameworksRoot: URL, fileManager: FileManager) -> URL? {
        guard let children = try? fileManager.contentsOfDirectory(
            at: frameworksRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let directHelpers = children.filter {
            $0.pathExtension == "app" && $0.lastPathComponent.contains("Helper")
        }
        if let directHelper = preferredCEFHelperApp(from: directHelpers) {
            return directHelper
        }

        if let helpersDir = children.first(where: { $0.lastPathComponent == "Helpers" }),
           let helperChildren = try? fileManager.contentsOfDirectory(
                at: helpersDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
           ) {
            let nestedHelpers = helperChildren.filter {
                $0.pathExtension == "app" && $0.lastPathComponent.contains("Helper")
            }
            return preferredCEFHelperApp(from: nestedHelpers)
        }

        return nil
    }

    private func loadFrameworkIfNeeded(at frameworkURL: URL) -> FrameworkLoadResult {
        let key = frameworkURL.standardizedFileURL.path
        if let cached = frameworkLoadResultsByPath[key] {
            return cached
        }

        guard let bundle = Bundle(path: key) else {
            let result = FrameworkLoadResult(
                isLoaded: false,
                errorDescription: "Missing bundle at \(key)"
            )
            frameworkLoadResultsByPath[key] = result
            return result
        }

        let isLoaded = bundle.isLoaded || bundle.load()
        let result = FrameworkLoadResult(
            isLoaded: isLoaded,
            errorDescription: isLoaded ? nil : "Bundle.load() returned false for \(key)"
        )
        frameworkLoadResultsByPath[key] = result
        return result
    }
}
