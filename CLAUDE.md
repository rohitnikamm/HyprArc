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
| `Hotkeys/` | Global hotkey registration via `CGEvent.tapCreate`, `KeyBinding` model, `CommandDispatcher` |
| `Config/` | TOML config at `~/.config/rover/config.toml` with hot-reload via `DispatchSource` |
| `UI/` | `MenuBarView` dropdown + `SettingsView` |

### Technical Decisions

- **Workspace switching** hides windows by moving offscreen to `CGPoint(x: 99999, y: 99999)` (AeroSpace technique) — macOS Spaces has no public API
- **Dwindle layout** uses a binary tree with auto-split by aspect ratio (width > height → horizontal, else vertical)
- **Geometric focus navigation** finds neighbors by center-point distance, not tree traversal — works identically across layout algorithms
- **Coordinate conversion** centralized in `ScreenHelper`: NSScreen (bottom-left origin) → AX (top-left origin): `axY = totalScreenHeight - nsY - height`
- **`_AXUIElementGetWindow`** private API isolated in `AXPrivateAPIs.swift` — single swap point if Apple ever removes it
- **Debouncing**: All retile operations use cancel-and-reschedule `DispatchWorkItem` with 50ms delay
- **SwiftUI** for settings UI; core WM logic is framework-agnostic

## Implementation Progress

Full 10-phase plan at `.claude/plans/steady-wishing-clover.md`.

- **Phase 1**: Menu bar app + AX permissions ✅
- **Phase 2**: Window detection & tracking ✅
- **Phase 3**: Dwindle layout engine (pure geometry) ← next
- **Phase 4–10**: Controller, focus nav, operations, master-stack, workspaces, hotkeys, config
