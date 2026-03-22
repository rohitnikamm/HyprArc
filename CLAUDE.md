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

- **Workspace switching** hides windows by shrinking to 1x1 then positioning at screen's bottom-right corner (AeroSpace technique) — macOS Spaces has no public API. On quit, all offscreen windows are restored to visible positions.
- **Dwindle layout** uses a binary tree with auto-split by aspect ratio (width > height → horizontal, else vertical)
- **Geometric focus navigation** finds neighbors by center-point distance, not tree traversal — works identically across layout algorithms
- **Coordinate conversion** centralized in `ScreenHelper`: NSScreen (bottom-left origin) → AX (top-left origin): `axY = totalScreenHeight - nsY - height`
- **`_AXUIElementGetWindow`** private API isolated in `AXPrivateAPIs.swift` — single swap point if Apple ever removes it
- **Debouncing**: All retile operations use cancel-and-reschedule `DispatchWorkItem` with 50ms delay
- **Constraint-aware tiling**: macOS apps enforce their own minimum sizes (unlike Wayland where compositors have absolute authority). Rover queries `kAXMinimumSizeAttribute` and auto-adjusts split ratios so windows respect their minimums without overlap.
- **Electron ghost window filtering**: `hasCloseButton` check filters out internal "Browser" helper windows from Electron apps (VSCode, Slack, etc.)
- **SwiftUI** for settings UI; core WM logic is framework-agnostic
- **MenuBarExtra observation**: `@ObservedObject` doesn't work in `RoverApp` via `appDelegate` chain — use a dedicated `MenuBarLabel` View with its own `@ObservedObject` to observe `TilingController`'s `@Published` properties
- **Settings window**: `Window(id: "settings")` scene with `.windowStyle(.automatic)` alongside `MenuBarExtra`. Uses `NavigationSplitView` with sidebar (System Settings pattern). Liquid Glass via `.containerBackground(.thinMaterial, for: .window)` + `.scrollContentBackground(.hidden)` on all Forms/Lists + `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`. Two-way sync between UI and config file. Uses `LabeledContent`, `DisclosureGroup`, `ContentUnavailableView` per Apple HIG. Inline reset confirmation in sidebar — button morphs/splits into [Cancel][Reset] with animated frame expansion (no modal alert). Text swap uses `.animation(nil)` to prevent overflow during size transition. Auto-dismisses after 5 seconds. Window Rules uses `ScrollView`+`VStack` (not `List`) for animated row insertion/deletion — macOS `List` (NSTableView-backed) doesn't support SwiftUI ForEach animations. Each rule has stable `UUID` identity and `.transition(.move(edge: .bottom).combined(with: .opacity))`. Custom `SlidingPicker` component replaces `.pickerStyle(.segmented)` — uses `matchedGeometryEffect` for a sliding pill highlight between options. Uses local `@State` for animation (Binding setters with `DispatchQueue.main.async` break animation context). Slider labels highlight with accent color + medium weight while dragging via debounced `.onChange`. Sidebar uses custom `VStack` (not `List`) with sliding hover highlight via `matchedGeometryEffect` — debounced `.onHover` per item (50ms nil delay prevents jitter), `.allowsHitTesting(false)` on the highlight prevents it from triggering hover events during animation. Haptics via `NSHapticFeedbackManager` (not `.sensoryFeedback` — doesn't trigger trackpad on macOS): sliders use `.levelChange` (notch feel), SlidingPicker uses `.alignment` (snap), reset + delete use `.generic`. Selective per Arc/Raycast philosophy — no haptics on sidebar clicks or rule adds.
- **Mouse events blocked during Settings**: `beginResize()` and `beginSwap()` guard `NSApp.keyWindow == nil` — prevents mouse resize/swap from passing through the Settings window to tiled windows below.
- **SwiftUI Binding async pattern**: All `Binding` setters in `SettingsView` wrap `@Published` mutations in `DispatchQueue.main.async` to avoid "Publishing changes from within view updates" warnings. Without this, SwiftUI triggers undefined behavior when Picker/Slider values change.
- **Config-driven layout**: All config settings are wired up and take effect immediately. `TilingController.applyConfigChanges()` switches layout engines, updates `DwindleLayout.defaultSplitRatio`, `MasterStackLayout.masterRatio`/`orientation` across all workspaces on config change. `WorkspaceManager` accepts a `defaultEngine` parameter for startup.
- **Window rules**: `syncAndRetile()` checks `configLoader.config.windowRules` when new windows appear — matching bundle IDs with `action = "float"` are auto-floated instead of tiled.
- **Configurable hotkeys**: `[keybindings]` section in config.toml maps command names to key strings (e.g. `focus-left = "opt+h"`). `KeyBinding.parse()` converts strings ↔ key codes. `CommandDispatcher` loads bindings from config and subscribes to changes. `HotkeyManager` callback uses dynamic `registeredBindings` array (not hardcoded `knownKeys`). Supports `opt`, `shift`, `cmd`, `ctrl` modifiers + all a-z, 0-9, and special keys.
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
- **Phase 10**: Config system (TOML at `~/.config/rover/config.toml`, hot-reload, 64 total tests) ✅
- **Phase 10.5**: Settings UI + configurable hotkeys + all config settings wired up (layout switching, split/master ratios, orientation, window rules auto-float) + reset to defaults ✅
- **Phase 11**: Settings UI redesign — NavigationSplitView sidebar, Apple HIG, Liquid Glass, mouse-through fix, microinteractions (inline reset morph, animated window rules rows, slider highlight, sliding pill picker, sidebar hover highlight), selective haptics (NSHapticFeedbackManager) ✅
- **Phase 12**: Menu bar workspace app icons — replaced verbose Windows list + bullet indicators with inline app icons per workspace. Icons resolved from `bundleID` via `NSWorkspace.shared.urlForApplication`. Uses `Text(Image(nsImage:))` for inline rendering (macOS NSMenu reorders standalone `Image` views). 14x14 icons with `.baselineOffset(-3)`. Invisible 1x14 spacer image in ALL rows normalizes NSMenu tracking rects (fixes off-by-one hover misalignment). `objectWillChange.send()` in `syncAndRetile()` for live updates. `spacedLabel()` helper applies the same spacer to non-workspace rows (Settings, Quit, Tiling, Layout, Reload) so ALL menu items have uniform tracking rects. ✅
