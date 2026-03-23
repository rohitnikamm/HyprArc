# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rover is a **dynamic tiling window manager for macOS**, inspired by Hyprland. The key differentiator from AeroSpace (the closest existing macOS WM) is that Rover uses **automatic layout algorithms** (dwindle, master-stack) rather than manual i3-style tree construction. Users choose a strategy; Rover builds the tree.

## Build & Run

```bash
# Build (Debug)
xcodebuild -project Rover.xcodeproj -scheme Rover -configuration Debug build

# Build (Release)
xcodebuild -project Rover.xcodeproj -scheme Rover -configuration Release build

# Run tests
xcodebuild -project Rover.xcodeproj -scheme Rover test

# Or: open Rover.xcodeproj in Xcode, Cmd+R to run, Cmd+U to test
```

Bundle ID: `rohit.Rover` | Deployment target: macOS

## Build Settings

- **App Sandbox**: `NO` (required — sandbox blocks Accessibility API)
- **LSUIElement**: `YES` (menu bar app, no Dock icon)
- **Hardened Runtime**: `YES` (required for notarization)
- **File sync groups**: Xcode auto-compiles new files under `Rover/` — no pbxproj edits needed for adding source files
- **Swift concurrency**: `MainActor` default isolation (Swift 6). Engine types are value types (implicitly `Sendable`). AX/CGEvent callbacks must dispatch to MainActor. Top-level C function pointer callbacks need `nonisolated`. Cross-isolation context objects need `@unchecked Sendable`.
- **Member import visibility**: `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` is enabled — must explicitly `import Combine` when using `@Published`/`ObservableObject`.

## Architecture

### Core Principle: Pure-Geometry Engine

The tiling engine operates on window IDs and rectangles — **zero AX dependency**. Only the controller layer touches Accessibility API. This enables comprehensive unit testing of all layout logic.

```
AX Events → TilingController → TilingEngine.calculateFrames() → LayoutResult → Apply via AX
```

### Key Protocol

`TilingEngine` is the central abstraction. Both `DwindleLayout` and `MasterStackLayout` are **value types** (`struct`) conforming to it. The engine receives window IDs + a screen rect, returns a `[WindowID: CGRect]` mapping. `WindowID` is `UInt32` (maps to `CGWindowID`).

### Module Structure

| Module | Purpose |
|--------|---------|
| `Accessibility/` | AX API integration — `WindowTracker` (AXObserver), `WindowInfo`, `AXExtensions`, `_AXUIElementGetWindow` private API |
| `TilingEngine/` | Layout algorithms conforming to `TilingEngine` protocol + geometric navigation |
| `Controller/` | `TilingController` orchestrator + `ScreenHelper` coordinate conversion |
| `Workspace/` | Virtual workspace management (9 workspaces, hide via offscreen move) |
| `Hotkeys/` | Global hotkey registration via `CGEvent.tapCreate`, `KeyBinding` model (with `parse()`/`toString()` for config strings), `CommandDispatcher` (loads bindings from config) |
| `Config/` | TOML config at `~/.config/rover/config.toml` with hot-reload via `DispatchSource`, `TOMLSerializer` for saving, `ConfigLoader` with debounced `save()` |
| `UI/` | `MenuBarView` dropdown (workspace rows with inline app icons via `Text(Image(nsImage:))`), `SettingsView` (NavigationSplitView sidebar: General, Gaps, Layouts, Keybindings, Window Rules), `SwapOverlayWindow` |

### Technical Decisions

- **Workspace switching** hides windows by positioning at screen's bottom-right corner `(maxX-1, maxY-1)` without shrinking — windows keep their full size so content buffers stay rendered (no re-render flicker on switch back). Window body extends off-screen; only 1px origin on-screen (invisible). macOS clamps far-offscreen coordinates like `(100000,100000)` back to visible area, so must use the corner position. Two-pass show: resize only if needed (offscreen), then setPosition in tight burst. On quit, all offscreen windows are restored to visible positions.
- **Dwindle layout** uses a binary tree with auto-split by aspect ratio (width > height → horizontal, else vertical)
- **Geometric focus navigation** finds neighbors by center-point distance, not tree traversal — works identically across layout algorithms
- **Coordinate conversion** centralized in `ScreenHelper`: NSScreen (bottom-left origin) → AX (top-left origin): `axY = totalScreenHeight - nsY - height`
- **`_AXUIElementGetWindow`** private API isolated in `AXPrivateAPIs.swift` — single swap point if Apple ever removes it
- **Debouncing**: All retile operations use cancel-and-reschedule `DispatchWorkItem` with 50ms delay. AX destruction notifications extract `windowID` synchronously in the C callback before async MainActor dispatch (element becomes invalid after async hop). `syncAndRetile()` also prunes windows with invalid AX elements (`role == nil`) as a safety net against ghost windows.
- **Constraint-aware tiling**: macOS apps enforce their own minimum sizes (unlike Wayland where compositors have absolute authority). Rover queries `kAXMinimumSizeAttribute` and auto-adjusts split ratios so windows respect their minimums without overlap.
- **Electron ghost window filtering**: `hasCloseButton` check filters out internal "Browser" helper windows from Electron apps (VSCode, Slack, etc.)
- **Apple system app tiling**: `isTileable` accepts windows with subrole `kAXStandardWindowSubrole` OR nil/empty — Apple system apps (Calendar, Notes, Reminders) don't report a subrole (known macOS AX limitation, yabai #2629). Dialogs/sheets/floating windows still rejected since they report explicit non-standard subroles.
- **SwiftUI** for settings UI; core WM logic is framework-agnostic
- **MenuBarExtra observation**: `@ObservedObject` doesn't work in `RoverApp` via `appDelegate` chain — use a dedicated `MenuBarLabel` View with its own `@ObservedObject` to observe `TilingController`'s `@Published` properties
- **Settings window**: `Window(id: "settings")` scene with `.windowStyle(.automatic)` alongside `MenuBarExtra`. Uses `NavigationSplitView` with sidebar (System Settings pattern). Liquid Glass via `.containerBackground(.thinMaterial, for: .window)` + `.scrollContentBackground(.hidden)` on all Forms/Lists + `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`. Two-way sync between UI and config file. Uses `LabeledContent`, `DisclosureGroup`, `ContentUnavailableView` per Apple HIG. Inline reset confirmation in sidebar — button morphs/splits into [Cancel][Reset] with animated frame expansion (no modal alert). Text swap uses `.animation(nil)` to prevent overflow during size transition. Auto-dismisses after 5 seconds. Window Rules uses `ScrollView`+`VStack` (not `List`) for animated row insertion/deletion — macOS `List` (NSTableView-backed) doesn't support SwiftUI ForEach animations. Each rule has stable `UUID` identity and `.transition(.move(edge: .bottom).combined(with: .opacity))`. Custom `SlidingPicker` component replaces `.pickerStyle(.segmented)` — uses `matchedGeometryEffect` for a sliding pill highlight between options. Uses local `@State` for animation (Binding setters with `DispatchQueue.main.async` break animation context). Slider labels highlight with accent color + medium weight while dragging via debounced `.onChange`. Sidebar uses custom `VStack` (not `List`) with sliding hover highlight via `matchedGeometryEffect` — debounced `.onHover` per item (50ms nil delay prevents jitter), `.allowsHitTesting(false)` on the highlight prevents it from triggering hover events during animation. Haptics via `NSHapticFeedbackManager` (not `.sensoryFeedback` — doesn't trigger trackpad on macOS): sliders use `.levelChange` (notch feel), SlidingPicker uses `.alignment` (snap), reset + delete use `.generic`. Selective per Arc/Raycast philosophy — no haptics on sidebar clicks or rule adds.
- **Mouse events blocked during Settings**: `beginResize()` and `beginSwap()` guard `NSApp.keyWindow == nil` — prevents mouse resize/swap from passing through the Settings window to tiled windows below.
- **SwiftUI Binding async pattern**: All `Binding` setters in `SettingsView` wrap `@Published` mutations in `DispatchQueue.main.async` to avoid "Publishing changes from within view updates" warnings. Without this, SwiftUI triggers undefined behavior when Picker/Slider values change.
- **Config-driven layout**: All config settings are wired up and take effect immediately. `TilingController.applyConfigChanges()` switches layout engines, updates `DwindleLayout.defaultSplitRatio`, `MasterStackLayout.masterRatio`/`orientation` across all workspaces on config change, reassigns windows to their configured workspaces, and reconciles float/tile state (moves running apps immediately and toggles float/unfloat when rules change). `WorkspaceManager` accepts a `defaultEngine` parameter for startup.
- **Window rules**: `WindowRule` supports `action` ("float" or ""), `workspace` (1-9 or nil), or both. `syncAndRetile()` checks rules when new windows appear — matching bundle IDs with `action = "float"` are auto-floated; rules with `workspace = N` assign windows to that workspace (hidden offscreen if inactive). `applyConfigChanges()` also reassigns existing managed windows when rules change (so running apps move immediately). Settings UI `+` button shows a `Menu` of running apps (via `NSWorkspace.shared.runningApplications`) with 4x Retina app icons via `Label`, for error-free bundle ID selection, with "Custom..." fallback for manual entry. Menu auto-refreshes via `.onReceive` of `NSWorkspace.didLaunchApplicationNotification`/`didTerminateApplicationNotification`.
- **Configurable hotkeys**: `[keybindings]` section in config.toml maps command names to key strings (e.g. `focus-left = "opt+h"`). `KeyBinding.parse()` converts strings ↔ key codes; `toDisplayString()` renders with macOS symbols (⌃⌥⇧⌘). `CommandDispatcher` loads bindings from config and subscribes to changes. `HotkeyManager` callback uses dynamic `registeredBindings` array (not hardcoded `knownKeys`). Supports `opt`, `shift`, `cmd`, `ctrl` modifiers + all a-z, 0-9, and special keys. Settings UI uses Raycast-style `KeyRecorderField` (`KeyRecorderField.swift`) — press-to-record via `.popover()` with four states: idle (4 dim modifier badges), modifiers-held (active badges + dashed placeholder), success (green badges + key + "Your new hotkey is set!", auto-dismiss 0.8s), error (red key badge + message, auto-dismiss 2s). All timed dismissals use `.task(id:)` with `guard !Task.isCancelled` (never `DispatchWorkItem` — crashes when popover dismissed during timer). Close button as `.overlay(alignment: .topTrailing)` to avoid VStack layout impact. `KeyCaptureRepresentable` in `.background` (not VStack child) to avoid spacing. State cleared in button action before `isRecording = true` (not `.onChange` — prevents NSPopover animated resize crash). Fixed `minHeight: 80` prevents popover size changes between states. `isRecordingKeybinding` flag bypasses CGEvent tap during recording. `DisclosureGroup` replaced with custom `Section` + full-width `Button` header for clickable expand/collapse rows.
- **Nonisolated Hashable/Equatable**: `KeyBinding` and `ModifierSet` have explicit `nonisolated` conformances to avoid Swift 6 MainActor isolation conflicts in the CGEvent tap callback.
- **Mouse resize**: No modifier needed — drag directly on split boundary gap. Uses `retileFast()` (skips constraint checks) + frame-diff tracking (only AX calls for changed windows) for smooth performance
- **Mouse swap**: No modifier needed — drag from window title bar (top 30px) to another window. Orange translucent overlay (`SwapOverlayWindow`) highlights the target during drag. Uses `DispatchQueue.main.async` (not Task) for low-latency mouse event handling

## Implementation Progress

Full 10-phase plan at `.claude/plans/steady-wishing-clover.md`.

- **Phase 1**: Menu bar app + AX permissions ✅
- **Phase 2**: Window detection & tracking ✅
- **Phase 3**: Dwindle layout engine + 35 unit tests ✅
- **Phase 4**: Tiling controller (AX → engine) ✅
- **Phase 5**: Focus navigation (geometric, menu bar buttons) ✅
- **Phase 6**: Window operations (swap, resize, float) ✅
- **Phase 7**: Master-stack layout + 21 tests (56 total) ✅
- **Phase 8**: Virtual workspaces (1–9, offscreen hiding) ✅
- **Phase 9**: Global hotkeys (CGEvent tap, Hyprland bindings) ✅
- **Phase 9.5**: Mouse-driven resize (drag boundary) & swap (drag title bar, orange overlay) ✅
- **Phase 10**: Config system (TOML at `~/.config/rover/config.toml`, hot-reload) ✅
- **Phase 10.5**: Settings UI + configurable hotkeys + all config settings wired up (layout switching, split/master ratios, orientation, window rules auto-float) + reset to defaults ✅
- **Phase 11**: Settings UI redesign — NavigationSplitView sidebar, Apple HIG, Liquid Glass, mouse-through fix, microinteractions (inline reset morph, animated window rules rows, slider highlight, sliding pill picker, sidebar hover highlight), selective haptics (NSHapticFeedbackManager) ✅
- **Phase 12**: Menu bar workspace app icons — replaced verbose Windows list + bullet indicators with inline app icons per workspace. Icons resolved from `bundleID` via `NSWorkspace.shared.urlForApplication`. Uses `Text(Image(nsImage:))` for inline rendering (macOS NSMenu reorders standalone `Image` views). 14x14pt icons rendered at 4x pixel density (56x56px) via `NSBitmapImageRep` for Retina sharpness — `Text(Image(nsImage:))` rasterizes at 1x without this. `.baselineOffset(-3)`. Invisible 1x14 spacer image in ALL rows normalizes NSMenu tracking rects (fixes off-by-one hover misalignment). `objectWillChange.send()` in `syncAndRetile()` for live updates. `spacedLabel()` helper applies the same spacer to non-workspace rows (Settings, Quit, Tiling, Layout, Reload) so ALL menu items have uniform tracking rects. ✅
- **Phase 13**: Workspace assignment — `WindowRule.workspace: Int?` assigns apps to specific workspaces on launch. Running-apps picker in Settings (`Menu` of `NSWorkspace.shared.runningApplications`). `applyConfigChanges()` reassigns existing windows immediately on rule change. TOML parser/serializer extended. 71 total tests. ✅
- **Bugfix**: Ghost window space after popup close — AX destruction notifications now extract `windowID` synchronously in C callback before async MainActor dispatch (element invalidates during hop). `syncAndRetile()` prunes windows with invalid AX elements as safety net. ✅
- **Bugfix**: Instant workspace switching — removed 1x1 shrink (destroyed content buffers, caused re-render flicker). Windows now hide at full size at screen corner `(maxX-1, maxY-1)` preserving rendered content. Two-pass show: conditional resize (offscreen) then batch setPosition. macOS clamps far-offscreen coords, so corner position is required. ✅
- **Bugfix**: Apple system apps (Calendar, Notes, Reminders) not tiled — relaxed `isTileable` subrole check to accept nil/empty (Apple system apps don't report `kAXStandardWindowSubrole`). ✅
- **Bugfix**: Float/tile rule changes not applied to running apps — `applyConfigChanges()` now reconciles float/tile state across all workspaces when rules change (tiled windows with new float rule → float immediately, floating windows with removed float rule → re-tile immediately). ✅
- **Phase 14**: Press-to-record keybinding UI — Raycast-style `KeyRecorderField` with `.popover()`, live modifier badges, error state for naked keys, `NSViewRepresentable` key capture, `isRecordingKeybinding` flag to bypass CGEvent tap. Replaced `DisclosureGroup` with full-width clickable section headers. New file: `KeyRecorderField.swift`. ✅
