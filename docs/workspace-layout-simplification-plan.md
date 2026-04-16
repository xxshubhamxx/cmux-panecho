# Workspace Layout Simplification Plan

## Status

Implemented on `issue-2289-appkit-split-host`:

- canonical surface identity now uses the panel UUID directly, so normal layout operations no longer depend on `surfaceIdToPanelId`
- the legacy `panelIdFromSurfaceId` shim is gone from production code, so active workspace, tab-manager, app-delegate, and terminal-controller paths now look panels up directly by `surfaceId.id`
- `TabItem` no longer carries runtime chrome payload such as icon, loading, unread, dirty, kind, or custom-title state
- visible tab chrome is projected from `Workspace` into the AppKit host instead of being read directly from mutable `PaneState` tab metadata
- the AppKit host renders from a first-class `WorkspaceLayoutRenderSnapshot` tree instead of pane-local ad hoc chrome rebuilds
- workspace-owned tab chrome now projects from explicit published workspace state plus browser chrome snapshot state, so title, pin, unread, loading, and favicon changes no longer depend on a manual refresh token
- split, create, move, reorder, and zoom operations now have one explicit `Workspace.performLayoutCommand` boundary
- the current surface kinds, terminal, browser, and markdown, now all create and split through typed helpers backed by that command boundary
- restore/import and placeholder-repair paths inside `Workspace` now also go through those typed helpers
- the old raw create-split methods are now private implementation detail inside `Workspace`, and tests were migrated to the typed helper API
- `WorkspaceLayoutController.createTab` now only accepts the layout-owned fields that survive into `TabItem`, and detached-surface transfer payloads no longer carry dead chrome data
- split-view drag state and same-process tab transfer payloads now carry stable `TabID` values instead of duplicating full tab chrome payload across controller state and pasteboard transport
- pane render snapshots no longer duplicate raw tab ordering and selection alongside pane chrome snapshots, so the native host now reads one canonical pane-tab contract
- empty-pane placeholder descriptors now expose explicit create actions instead of handing the renderer a live `Workspace` reference, so placeholder UI follows the same action-driven boundary as the other pane content kinds
- the layout host command and drag path now use typed `PanelType` surface kinds instead of raw `"terminal"` and `"browser"` strings
- browser portal and visibility assumptions now sit behind a dedicated `BrowserPanelWorkspaceContentView` mounting adapter instead of leaking through `WorkspaceSplitNativeHost`
- the keyboard/browser "insert at end" path now uses the correct reorder slot semantics, which restored the existing append-at-end invariant
- workspace no longer runs a terminal geometry recovery loop after split, close, move, reorder, or zoom mutations, and the timer-based moved-terminal refresh path is gone
- the dead `TerminalPanel.requestViewReattach()` abstraction is gone, so terminal geometry reconciliation now stays at the retained host layer instead of being driven from `Workspace`
- browser portal teardown now happens at the retained browser host boundary, and the workspace-wide browser portal follow-up loop is gone
- unfocused split and create commands now preserve pane focus and tab selection at the `WorkspaceLayoutController` boundary instead of mutating focus first and repairing it later
- the old non-focus split reassert path is gone, so split/create command flow no longer depends on nested async focus retries
- the AppKit host no longer self-observes layout state or re-computes snapshots internally, and now acts as a pure apply-the-provided-snapshot renderer
- split zoom no longer recreates the entire workspace layout subtree just to clear stale chrome
- terminal reparent focus suppression now clears from the retained host mount path, so the split path no longer uses a fixed 50 ms timing delay
- browser find focus now relies on overlay mount/update state instead of repeated notification pulses
- browser omnibar select-all now executes from the native text-field host instead of a timed retry pair
- browser address-bar pending focus now resumes from command-palette visibility change signals instead of polling
- browser portal presentation refresh now uses the same immediate-plus-next-runloop reattach shape as the local inline host, and the fixed 30 ms follow-up pass is gone
- external divider updates in `WorkspaceSplit` now suppress only the immediate geometry echo instead of reopening notifications after a fixed 50 ms delay
- browser import modal presentation now waits on popover dismissal state instead of a fixed 120 ms delay
- checkpoint commit `520b8483` preserves the pre-reset branch state before the architecture cleanup
- `ContentView` no longer owns `mountedWorkspaceIds`, `retiringWorkspaceId`, workspace handoff timers, or background workspace priming
- the window now keeps all workspaces mounted and lets selection control visibility and input instead of maintaining a second mount cache
- `TabManager` no longer defers unfocus through `pendingWorkspaceUnfocusTarget`; switching workspaces now focuses the target and unfocuses the previous workspace directly
- temporary blank-pane debug probes such as `close.blankstate.*`, `ws.handoff.*`, and `ws.mount.reconcile` are gone
- `Workspace` now owns canonical per-surface runtime metadata in one `surfaceStatesByPanelId` map instead of parallel title, directory, pin, unread, browser chrome, git, PR, port, and tty stores
- `Workspace` internals now read and mutate that canonical surface state directly for session restore, focus, close, detach/attach, sidebar ordering, browser/markdown creation, remote tty/port updates, and tab chrome projection
- `WorkspaceContentView` no longer assembles tab chrome projection state locally, and `Workspace` now builds the layout render snapshot that the AppKit host applies
- `Workspace` now also resolves terminal/browser native pane content while building that render snapshot, so the AppKit host no longer asks `WorkspaceContentView` to rebuild runtime native descriptors from tabs during rendering
- `WorkspaceLayoutView` and `WorkspaceLayoutNativeHost` no longer expose a separate native-content builder seam; the host consumes one canonical snapshot tree for all pane content
- all current surface kinds, terminal, browser, and markdown, now mount through the same workspace-owned pane-content descriptor path inside the AppKit host, and the dead `PanelContentView` fallback path is gone
- `WorkspaceLayoutView` now requires a workspace-owned render snapshot instead of synthesizing one internally, so the shell boundary is purely "apply this snapshot" even for markdown and placeholder tabs
- `TabManager`, `ContentView`, `WorkspaceContentView`, `TerminalController`, `AppleScriptSupport`, `GhosttyTerminalView`, and `TerminalImageTransfer` now consume canonical surface snapshots/accessors instead of wrapper-shaped metadata dictionaries
- the old wrapper-shaped surface metadata API is gone from `Workspace`, so production code no longer reaches into parallel `panelTitles`-style stores
- `TerminalController` workspace resolution now prefers its attached `TabManager` and only falls back to `AppDelegate` window contexts for cross-window routing, which keeps socket and telemetry ownership aligned with the runtime workspace owner
- focused behavior coverage for the ownership cut passes, including workspace state, content visibility, socket security, session persistence, sidebar ordering, browser config, and remote connection suites
- browser portal teardown is now owned by `BrowserPanel.close()` instead of a workspace-wide pre-close sweep, which keeps portal lifecycle at the retained-surface boundary
- `Workspace` now owns render-snapshot construction directly, and the old generic `workspaceLayoutMakeRenderSnapshot` builder seam is gone from production code
- `WorkspaceLayoutDelegate` is now `@MainActor`, matching the controller and workspace shell ownership boundary instead of relying on a nonisolated delegate protocol
- empty panes now also come through the workspace-owned pane-content snapshot, so `WorkspaceLayoutView` and the native host no longer accept a separate empty-pane view builder
- `workspaceSplitContextMenuState` now lives in `Sources/WorkspaceSplit.swift`, so workspace-owned chrome projection no longer depends on a helper defined in `Sources/WorkspaceSplitNativeHost.swift`
- the canonical `WorkspaceLayoutRenderSnapshot` family now lives in `Sources/WorkspaceSplit.swift` instead of `Sources/WorkspaceSplitNativeHost.swift`, so `Workspace` owns runtime snapshot assembly without depending on renderer-local type definitions

No required architecture work from this simplification plan remains on this branch.

Optional follow-up work, outside the scope of this refactor:

1. continue Swift 6 actor-isolation cleanup in unrelated legacy areas such as delegate conformances and AppDelegate notification glue
2. add broader e2e coverage for workspace shell behavior once the next user-visible workflow needs it
3. introduce a dedicated retained-surface registry only if future surface kinds outgrow `Workspace.panels` as the lifetime boundary

`TabItem.title` remains intentionally as the serialized fallback title used by layout snapshots, placeholders, and export/debug paths. Runtime tab chrome truth no longer depends on it.

## Problem

The current workspace layout path has too many runtime models and too many translation boundaries.

A single user action such as split, close, move, rename, or focus currently crosses AppDelegate, TabManager, Workspace, WorkspaceLayoutController, SplitViewController, and the AppKit host. Runtime state is duplicated between panel dictionaries in `Sources/Workspace.swift`, tab metadata in `Sources/WorkspaceSplit.swift`, and renderer-local snapshots in `Sources/WorkspaceSplitNativeHost.swift`. That duplication is the main source of stale tab chrome, focus churn, and brittle feature work.

## Constraints

- Keep the workspace shell in AppKit.
- Support all current and planned surface kinds: terminal, browser, markdown, file editor, VNC, embedded simulators, and similar primitives.
- Keep Ghostty-backed terminals.
- Do not require every surface implementation to be AppKit-only.
- Do not rewrite the app around a large framework such as TCA.
- Do not change user-visible workspace behavior in the first migration steps.

## Original Pain Points

### Duplicated chrome state

Before this migration, `TabItem` in `Sources/WorkspaceSplit.swift` stored title, icon, loading, unread, pinned, and related chrome state, even though the real source of truth already existed on the surface or panel owned by `Workspace`.

### Parallel identity systems

Before this migration, `Workspace` maintained `surfaceIdToPanelId` in `Sources/Workspace.swift`. That meant normal operations translated between layout IDs and panel IDs instead of operating on one canonical identity.

### Renderer observes nested mutable state directly

Before the snapshot conversion, `WorkspaceLayoutRootHostView` in `Sources/WorkspaceSplitNativeHost.swift` depended on nested pane and tab observation for chrome rebuild timing. That made redraw behavior depend on mutation shape instead of an explicit render contract.

### Content mounting is type-switched in the renderer

`WorkspaceNativePaneContent` and the AppKit host special-case terminal, browser, and SwiftUI fallback content. That makes each new surface kind more expensive to add.

### Layout and content responsibilities are mixed

The layout tree owns tab order and selection, but it also owns tab chrome payload. The renderer mounts views, computes presentation state, and knows about content kind. That is too much coupling for the core workspace shell.

## Design Principles

### 1. One canonical workspace owner

There should be one workspace-owned source of truth for:
- layout topology
- surface identity
- selected surface per pane
- focused pane
- zoomed pane
- per-surface chrome state

The simplest first step is not to add a new wrapper store. It is to make `Workspace` become the canonical `@MainActor @Observable` owner of this state over time.

### 2. Layout state and surface state are separate

The split tree should know only layout facts:
- pane IDs
- ordered `SurfaceID`s in each pane
- selected `SurfaceID` per pane
- focus state
- split ratios and orientation

It should not own title, icon, loading, unread, pinned, dirty, or custom-title state. Those belong to the surface model.

### 3. AppKit shell, pluggable surfaces

Workspace layout, split dividers, tab strip, drag and drop, focus routing, and hit testing stay AppKit.

Individual surfaces can be:
- pure AppKit
- SwiftUI behind one hosting adapter
- mixed wrappers such as Ghostty terminal or WKWebView browser

This keeps the shell deterministic while allowing surface-specific implementation freedom.

### 4. Snapshot-driven shell rendering, retained native surfaces

The AppKit host should render the shell from immutable snapshots. It should not depend on nested observation over mutable pane and tab collections.

But live native surfaces are not snapshot data. Ghostty surfaces, WKWebViews, and similar retained views should live in a separate retained registry keyed by `SurfaceID`. The snapshot tells the shell what should be visible and where it should be. The retained registry owns the real `NSView` objects.

### 5. State is synchronous and main-actor owned

Workspace mutation and rendering should stay on `@MainActor`. Per the SwiftGuidanceSkill guidance, UI state should use Observation-era models and explicit ownership, not scattered callback glue or GCD hops.

Heavy non-UI work can still happen off-main, but the workspace shell itself should have a single synchronous state boundary.

### 6. Focus is a separate imperative subsystem

The snapshot can describe intended focus. Actual `firstResponder` changes still need explicit imperative focus APIs. Focus should not depend on incidental redraw or remount behavior.

## Proposed Target Architecture

### Workspace runtime store

Use `Workspace` as the initial canonical `@MainActor @Observable` runtime store. It should own:
- `layout: WorkspaceLayoutState`
- `surfaces: [SurfaceID: SurfaceModel]`
- workspace-level focus and selection state
- drag state and drop targets
- command entry points for split, close, move, select, rename, pin, unread, loading, zoom, and drop handling

A separate `WorkspaceStore` type is optional later. It is not required for the first simplification cut.

### WorkspaceLayoutState

Keep this as a pure value-oriented model:
- split tree
- pane IDs
- ordered `surfaceIDs` per pane
- selected `SurfaceID` per pane
- focused pane ID
- zoomed pane ID
- split ratios and orientation

This model should not carry tab chrome payload.

### SurfaceModel

Each user-visible thing in the workspace becomes a surface.

```swift
@MainActor
@Observable
final class SurfaceModel {
    let id: SurfaceID
    let kind: SurfaceKind
    var chrome: SurfaceChromeState
}
```

`SurfaceChromeState` contains:
- title
- custom title flag
- icon descriptor
- loading
- dirty
- unread
- pinned
- closeability and similar tab-strip metadata

The actual live surface implementation stays outside this value-like state.

`SurfaceID` should be the panel identity, or a thin wrapper around it. The plan should not preserve a peer `panelID` inside runtime surface state.

### Retained surface lifetime

Use `Workspace.panels` as the provisional retained surface registry in the first migration slices. That keeps lifetime ownership flat while identity and chrome ownership are being simplified.

A dedicated `RetainedSurfaceRegistry` is only worth adding later if `Workspace.panels` can no longer express retained surface lifetime cleanly after the ownership cut.

The renderer should never treat live surface objects as snapshot payload.

### Surface boundary

Do not introduce a second controller hierarchy unless `Panel` proves insufficient.

The current default plan is:
- keep `Panel` as the canonical surface boundary during the first migration
- extract chrome and layout ownership out of `TabItem`
- add a thin mounting adapter only where a panel needs extra host-specific behavior

If later we still need a cleaner protocol, define it after the ownership cut, not before.

### WorkspaceRenderSnapshot

The renderer consumes one immutable shell snapshot.

```swift
struct WorkspaceRenderSnapshot {
    let layout: WorkspaceLayoutSnapshot
    let panes: [PaneID: PaneChromeSnapshot]
    let surfaces: [SurfaceID: SurfaceRenderSnapshot]
    let focusedPaneID: PaneID?
    let selectedSurfaceIDs: [PaneID: SurfaceID]
    let zoomedPaneID: PaneID?
    let dragState: WorkspaceDragSnapshot?
}
```

`SurfaceRenderSnapshot` should contain only shell-facing presentation data, for example:
- title
- icon
- loading
- dirty
- unread
- pinned
- selected and visible flags

It should not contain live controllers, `NSView`s, or other retained runtime objects.

### AppKit host responsibilities

The AppKit host should do only this:
- `applyLayout(snapshot.layout)`
- `applyPaneChrome(snapshot.panes)`
- `applySurfaceChrome(snapshot.surfaces)`
- ask the retained surface lifetime owner, initially `Workspace.panels`, to show, hide, move, or focus the visible surfaces

The host does not compute business state. It applies state.

## Required Invariants

These need to be explicit before implementation starts.

### Identity

- `SurfaceID` is the canonical ID for every user-visible surface.
- Normal layout operations do not translate through `surfaceIdToPanelId`.
- `TabID` stops being a separate runtime identity.

### Focus

- one canonical focused pane ID
- one canonical selected `SurfaceID` per pane
- one canonical focused surface intent
- one canonical `PanelFocusIntent` or equivalent sub-focus intent
- explicit rule for AppKit `firstResponder`
- explicit rule for browser address-bar focus vs pane focus
- explicit rule for terminal find focus and similar sub-focus modes

### Visibility

- one rule for which surfaces are mounted
- one rule for which mounted surfaces are hidden vs visible
- one rule for browser portal visibility
- one rule for zoomed-pane behavior

### Empty panes and transfers

- decide whether empty panes are valid steady-state layout or only transient state
- define detach, move, restore, and cross-workspace transfer in terms of `SurfaceID`

## Why This Is Simpler

### Simpler than the current path

This removes:
- duplicated tab chrome metadata in `TabItem`
- most `surfaceIdToPanelId` lookup churn
- renderer observation over nested mutable arrays
- renderer-side branching as the main extensibility mechanism
- mixed ownership of focus, visibility, and title state

### Simpler than a full SwiftUI shell

Ghostty's upstream split path is simpler because it has one immutable terminal tree and one renderer. Our problem is not that we use AppKit. Our problem is that we have duplicated state and heterogeneous surface kinds.

AppKit is still the better shell for desktop split layout, hit testing, drag and drop, portal-hosted views, and future complex primitives.

### Simpler than forcing every surface into AppKit

The workspace shell should be AppKit. Surface internals do not all need to be AppKit. A markdown editor or settings-like surface can still live behind one hosting adapter if that is the lowest-complexity implementation.

## Alternative Approaches Rejected

### 1. Keep the current model and patch invalidation harder

Rejected because it keeps duplicated state and translation tables. It may hide symptoms, but it does not simplify the design.

### 2. Make the full workspace shell SwiftUI

Rejected because cmux is not just a terminal split tree. We need deterministic desktop behavior for drag, focus, portals, and mixed hosted content.

### 3. Rewrite around a large reducer framework

Rejected because the main problem is state shape, not lack of a framework. Plain `@Observable` models and immutable render snapshots are enough.

## Migration Plan

### Phase 1. Collapse identity first, completed

Add `SurfaceID` as the canonical runtime identity everywhere layout code currently uses a separate tab identity. In the first cut, `SurfaceID` should be the panel identity, or a thin wrapper around it.

The main goal of this phase is to delete `surfaceIdToPanelId` from normal layout operations as early as possible. This phase also needs a session and restore audit, because persisted layout snapshots currently depend on the old identity path.

### Phase 2. Write down invariants, completed

Before deeper refactors, define the exact invariants for:
- focus
- visibility
- empty panes
- detach and restore
- cross-workspace transfer

This prevents the migration from merely relocating ambiguous behavior.

### Phase 3. Move chrome truth out of layout, completed for runtime chrome

Change pane state so panes store ordered `SurfaceID`s and selected `SurfaceID`, not `TabItem` payloads.

The layout algorithms stay the same. Only ownership of title, icon, loading, unread, pinned, and dirty moves to `SurfaceModel.chrome`.

### Phase 4. Make retained surface lifetime explicit, completed

Use `Workspace.panels` as the provisional retained surface registry and make surface lifetime rules explicit.

The goal is to preserve live terminal and browser objects across layout changes while moving shell state out of the renderer. Add a separate `RetainedSurfaceRegistry` type only if the simpler ownership shape later proves insufficient.

### Phase 5. Add shell snapshot projection, completed

Add one projection layer from `Workspace` to `WorkspaceRenderSnapshot`.

This is the key seam. It gives us one render contract and one place to reason about visible shell state.

### Phase 6. Convert the AppKit host to snapshot application, completed

Refactor the AppKit host to:
- stop observing nested pane tab metadata directly
- stop computing business decisions in tab views
- apply pane and tab changes from snapshots only
- ask the retained surface lifetime owner, initially `Workspace.panels`, to update live surface views imperatively

At the end of this phase, stale UI bugs should reduce to either a bad snapshot or a bad apply step.

### Phase 7. Normalize surface mounting boundaries, completed for the current shell

Keep `Panel` as the initial surface boundary. Add thin mounting adapters only where a panel needs extra host-specific behavior.

Only introduce a new surface protocol if the simplified `Panel` boundary still proves inadequate after the ownership cut.

### Phase 8. Flatten command flow, completed for active callers

Flatten the current command flow so split, close, move, rename, and focus operate through one workspace command boundary.

The likely end state is:
- AppDelegate resolves shortcut intent
- `Workspace` executes command
- `Workspace` mutates state
- renderer applies new snapshot
- focus and retained-surface visibility update imperatively

This keeps TabManager and other compatibility layers thinner over time.

### Phase 9. Delete old translation and invalidation paths, completed for this migration

Remove:
- `TabItem` as the runtime source of chrome truth
- `surfaceIdToPanelId` for normal layout operations
- renderer-local type switches as the main content extension point
- old observation-based rerender hooks that exist only to compensate for duplicated state

### Phase 10. Preserve retained hosts across topology changes, completed

Completed in this phase:

- `WorkspaceLayoutRootHostView` no longer resets pane and split host caches when the split topology changes
- pane-host cleanup now runs after every tree rebuild, so removed panes and splits still tear down cleanly without forcing surviving panes to remount
- the unused `recreateOnSwitch` lifecycle mode was deleted, and the AppKit shell now always keeps pane content alive
- the workspace-level terminal geometry recovery pass is deleted, so split, close, move, reorder, and zoom no longer force terminal reattach and refresh from `Workspace`
- the timer-based moved-terminal refresh path is deleted, and debug-stress callers now reconcile geometry directly on the retained hosted view instead of going through workspace-owned reattach helpers
- browser portal teardown and visibility repair now live at the retained browser host boundary instead of a workspace-owned follow-up loop

### Phase 11. Delete repair loops and duplicate renderer observation, completed

Completed in this phase:

- unfocused split and create paths now express their focus intent at the layout-controller boundary instead of mutating focus and reasserting it later from `Workspace`
- the old non-focus split reassert state machine is deleted
- the workspace-wide event-driven layout follow-up loop is deleted
- `WorkspaceLayoutRootHostView` no longer tracks nested mutable controller state on its own or re-projects snapshots internally
- split zoom no longer recreates the entire workspace layout subtree
- terminal reparent focus suppression now resumes from retained-host mount readiness instead of a fixed delay

## Browser and Future Surface Kinds

### Browser

Browser portal and visibility assumptions now live behind the browser's retained surface entry and mounting adapter instead of leaking into the layout host.

If browsers eventually move to a different engine, this architecture still holds. The shell continues to mount one surface by `SurfaceID`.

### Future primitives

Editors, VNC, simulators, and similar views fit this model cleanly. They each provide:
- a surface model
- a retained surface entry
- chrome state
- focus and visibility hooks

No new layout architecture is needed per surface kind.

## Risks

### Risk 1. Migration churn

This touches core workspace behavior. The migration must keep user-visible behavior stable and land in phases.

### Risk 2. Focus regressions

Focus is still the trickiest part of the current code. Each phase needs explicit invariants and behavior checks.

### Risk 3. Snapshot bloat

Do not let `WorkspaceRenderSnapshot` become a dumping ground. It should contain only the data the shell renderer needs to draw and place chrome.

### Risk 4. Retained-surface churn

If the retained lifetime owner remounts terminals or browsers too aggressively, the architecture still fails. Surface lifetime must stay stable across selection, split, and zoom changes.

### Risk 5. Placeholder and transfer semantics

The current split logic still depends on placeholder and detach-transfer behavior. Identity collapse and snapshot projection must account for empty-pane creation, detach, attach, and restore semantics explicitly.

## Verification Strategy

Prefer behavior-level verification:
- split right and split down
- close selected surface
- move surface between panes
- rename surface
- unread, loading, dirty, and pinned state updates
- focus changes between panes and surfaces
- browser and terminal visibility correctness during drag and close
- detach and restore behavior
- startup and restore behavior after the main architecture cutovers

Add deterministic unit coverage around:
- pure layout state transitions
- shell snapshot projection
- command reducers or command handlers
- retained-surface registry decisions

Do not add source-shape tests.

## Recommended First Implementation Slice

The first slice should be the highest-leverage cut with the lowest behavior risk:
- make `SurfaceID` the only runtime identity used by layout
- move tab chrome payload out of `TabItem`
- add a shell-only `WorkspaceRenderSnapshot`
- use `Workspace.panels` as the provisional retained surface registry
- keep `Workspace` as the initial canonical owner instead of adding a wrapper store
- keep `Panel` as the initial surface boundary unless it proves insufficient
- audit session restore, detach, and transfer paths during identity collapse

That slice removes the worst duplication without forcing an all-at-once rewrite.
