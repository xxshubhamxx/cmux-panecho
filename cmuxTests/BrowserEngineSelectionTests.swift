import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class BrowserEngineSelectionTests: XCTestCase {
    private let unavailableRuntime = CEFEngineRuntimeStatus(
        isRuntimeLinked: false,
        installation: nil,
        isFrameworkLoaded: false,
        frameworkLoadErrorDescription: nil,
        isRuntimeStarted: false,
        runtimeStartErrorDescription: nil,
        allowUnlinkedSurface: false
    )

    func testLocalWorkspaceDefaultsToWebKit() {
        XCTAssertEqual(
            BrowserEngineFeatureFlags.preferredEngineKind(
                isRemoteWorkspace: false,
                environmentOverride: nil
            ),
            .webkit
        )
    }

    func testLocalWorkspaceCanPreferCEFWithGlobalOverride() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("cef", forKey: BrowserEngineFeatureFlags.engineDefaultsKey)
        XCTAssertEqual(
            BrowserEngineFeatureFlags.preferredEngineKind(
                isRemoteWorkspace: false,
                environmentOverride: nil,
                defaults: defaults
            ),
            .cef
        )
    }

    func testRemoteWorkspaceDefaultsToWebKit() {
        XCTAssertEqual(
            BrowserEngineFeatureFlags.preferredEngineKind(
                isRemoteWorkspace: true,
                environmentOverride: nil
            ),
            .webkit
        )
    }

    func testRemoteWorkspaceCanPreferCEF() {
        XCTAssertEqual(
            BrowserEngineFeatureFlags.preferredEngineKind(
                isRemoteWorkspace: true,
                environmentOverride: "cef"
            ),
            .cef
        )
    }

    func testRemoteWorkspaceFallsBackToWebKitWhenCEFIsUnavailable() {
        XCTAssertEqual(
            BrowserEngineFeatureFlags.effectiveEngineKind(
                isRemoteWorkspace: true,
                runtimeStatus: unavailableRuntime,
                environmentOverride: "cef"
            ),
            .webkit
        )
    }

    func testRemoteWorkspaceUsesCEFWhenLinkedRuntimeIsAvailable() {
        let runtime = CEFEngineRuntimeStatus(
            isRuntimeLinked: true,
            installation: CEFEngineInstallation(
                frameworkURL: URL(fileURLWithPath: "/tmp/Chromium Embedded Framework.framework"),
                helperAppURL: URL(fileURLWithPath: "/tmp/cmux Helper.app"),
                sourceDescription: "test"
            ),
            isFrameworkLoaded: true,
            frameworkLoadErrorDescription: nil,
            isRuntimeStarted: true,
            runtimeStartErrorDescription: nil,
            allowUnlinkedSurface: false
        )
        XCTAssertEqual(
            BrowserEngineFeatureFlags.effectiveEngineKind(
                isRemoteWorkspace: true,
                runtimeStatus: runtime,
                environmentOverride: "cef"
            ),
            .cef
        )
    }

    func testRemoteWorkspaceCanForceUnlinkedCEFForDevWork() {
        let runtime = CEFEngineRuntimeStatus(
            isRuntimeLinked: false,
            installation: nil,
            isFrameworkLoaded: false,
            frameworkLoadErrorDescription: "not loaded",
            isRuntimeStarted: false,
            runtimeStartErrorDescription: "not started",
            allowUnlinkedSurface: true
        )
        XCTAssertEqual(
            BrowserEngineFeatureFlags.effectiveEngineKind(
                isRemoteWorkspace: true,
                runtimeStatus: runtime,
                environmentOverride: "cef"
            ),
            .cef
        )
    }

    func testRuntimeAssetsWithoutSuccessfulLoadStayOnWebKit() {
        let runtime = CEFEngineRuntimeStatus(
            isRuntimeLinked: true,
            installation: CEFEngineInstallation(
                frameworkURL: URL(fileURLWithPath: "/tmp/Chromium Embedded Framework.framework"),
                helperAppURL: nil,
                sourceDescription: "test"
            ),
            isFrameworkLoaded: false,
            frameworkLoadErrorDescription: "dlopen failed",
            isRuntimeStarted: false,
            runtimeStartErrorDescription: "init skipped",
            allowUnlinkedSurface: false
        )
        XCTAssertEqual(
            BrowserEngineFeatureFlags.effectiveEngineKind(
                isRemoteWorkspace: true,
                runtimeStatus: runtime,
                environmentOverride: "cef"
            ),
            .webkit
        )
    }

    func testLoadedRuntimeWithoutSuccessfulStartupStaysOnWebKit() {
        let runtime = CEFEngineRuntimeStatus(
            isRuntimeLinked: true,
            installation: CEFEngineInstallation(
                frameworkURL: URL(fileURLWithPath: "/tmp/Chromium Embedded Framework.framework"),
                helperAppURL: URL(fileURLWithPath: "/tmp/cmux Helper.app"),
                sourceDescription: "test"
            ),
            isFrameworkLoaded: true,
            frameworkLoadErrorDescription: nil,
            isRuntimeStarted: false,
            runtimeStartErrorDescription: "cef_initialize failed",
            allowUnlinkedSurface: false
        )
        XCTAssertEqual(
            BrowserEngineFeatureFlags.effectiveEngineKind(
                isRemoteWorkspace: true,
                runtimeStatus: runtime,
                environmentOverride: "cef"
            ),
            .webkit
        )
    }

    func testRemoteWorkspaceAcceptsChromiumAlias() {
        XCTAssertEqual(
            BrowserEngineFeatureFlags.preferredEngineKind(
                isRemoteWorkspace: true,
                environmentOverride: "chromium"
            ),
            .cef
        )
    }

    func testUnknownRemoteWorkspaceEngineFallsBackToWebKit() {
        XCTAssertEqual(
            BrowserEngineFeatureFlags.preferredEngineKind(
                isRemoteWorkspace: true,
                environmentOverride: "bogus"
            ),
            .webkit
        )
    }
}
