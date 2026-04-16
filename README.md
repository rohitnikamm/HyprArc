# HyprArc

A dynamic tiling window manager for macOS, inspired by Hyprland. Windows snap into place automatically using a layout algorithm you choose — no manual i3-style tree construction. Three layouts ship today: **Dwindle** (binary spiral), **Master-Stack**, and **Accordion** (MRU peek stack).

<img width="1512" height="982" alt="HyprArc screenshot" src="https://github.com/user-attachments/assets/810602f4-95ca-4c00-ae5f-0fd73d6d5176" />

## Install

```bash
brew tap rohitnikamm/hyprarc
brew install --cask hyprarc
```

First launch prompts for the Accessibility permission required to manage windows. Grant it in **System Settings → Privacy & Security → Accessibility**, then HyprArc auto-relaunches. (If the menu bar shows "Restart to Activate", click it.)

**Requires macOS Tahoe (26) or later.**

## Features

- 9 virtual workspaces with instant switching
- Three layout algorithms, toggled via menu bar or keybinding:
  - Dwindle — recursive binary split by aspect ratio
  - Master-Stack — dominant area + stack, configurable ratio + orientation
  - Accordion — stacked with configurable peek padding
- Geometric focus navigation (`Opt+H/J/K/L`) that works identically across layouts
- Window swap, float toggle, and per-app rules (float / assign to workspace)
- Mouse resize on split boundaries; mouse swap via title-bar drag
- TOML config at `~/.config/hyprarc/config.toml` with hot-reload
- Settings UI with Liquid Glass material and press-to-record keybindings

<img width="714" height="463" alt="HyprArc settings" src="https://github.com/user-attachments/assets/e6659366-7b3d-4d2b-b308-7b1446000c89" />
<img width="662" height="465" alt="HyprArc keybindings" src="https://github.com/user-attachments/assets/707f077f-8708-47ce-ad28-ac86a98050f1" />

## Default keybindings

| Action | Shortcut |
|---|---|
| Focus left / down / up / right | `Opt+H/J/K/L` |
| Swap left / down / up / right | `Opt+Shift+H/J/K/L` |
| Switch to workspace 1–9 | `Opt+1…9` |
| Move window to workspace 1–9 | `Opt+Shift+1…9` |
| Toggle float | `Opt+Space` |
| Cycle layout (Dwindle → Master-Stack → Accordion) | `Opt+D` |
| Jump to Dwindle / Master-Stack / Accordion | `Opt+T` / `Opt+M` / `Opt+A` |
| Toggle accordion orientation | `Opt+Shift+A` |
| Resize grow / shrink | `Opt+=` / `Opt+-` |
| Quit HyprArc | `Opt+Shift+E` |

All shortcuts are user-configurable in Settings → Keybindings or directly in `~/.config/hyprarc/config.toml`.

## Update

```bash
brew upgrade --cask hyprarc
```

## Uninstall

```bash
brew uninstall --cask hyprarc
# To also remove config + cached preferences:
brew uninstall --zap --cask hyprarc
```

## Build from source

Requires Xcode 26+.

```bash
git clone https://github.com/rohitnikamm/HyprArc.git
cd HyprArc
xcodebuild -project HyprArc.xcodeproj -scheme HyprArc -configuration Debug build
# Or open HyprArc.xcodeproj in Xcode and ⌘R.
```

## License

MIT — see [LICENSE](LICENSE).
