import AppKit
import Carbon.HIToolbox

/// A key + modifier combination for a hotkey binding.
/// Explicit nonisolated Hashable/Equatable to avoid MainActor isolation
/// (these are used in the nonisolated CGEvent tap callback).
struct KeyBinding: Sendable {
    let keyCode: UInt16
    let modifiers: ModifierSet

    /// Simplified modifier set (avoids NSEvent.ModifierFlags Hashable issues).
    struct ModifierSet: Sendable {
        let option: Bool
        let shift: Bool
        let command: Bool
        let control: Bool

        static let opt = ModifierSet(option: true, shift: false, command: false, control: false)
        static let optShift = ModifierSet(option: true, shift: true, command: false, control: false)
        static let none = ModifierSet(option: false, shift: false, command: false, control: false)
    }
}

extension KeyBinding.ModifierSet: Equatable, Hashable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.option == rhs.option && lhs.shift == rhs.shift
            && lhs.command == rhs.command && lhs.control == rhs.control
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(option)
        hasher.combine(shift)
        hasher.combine(command)
        hasher.combine(control)
    }
}

extension KeyBinding: Equatable, Hashable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.option)
        hasher.combine(modifiers.shift)
        hasher.combine(modifiers.command)
        hasher.combine(modifiers.control)
    }

    /// Check if a CGEvent matches this binding (nonisolated for CGEvent tap callback).
    nonisolated func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard self.keyCode == keyCode else { return false }
        let hasOpt = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        return modifiers.option == hasOpt
            && modifiers.shift == hasShift
            && modifiers.command == hasCmd
            && modifiers.control == hasCtrl
    }

    // MARK: - Parsing

    /// Parse a key string like "opt+shift+h" into a KeyBinding.
    static func parse(_ string: String) -> KeyBinding? {
        let parts = string.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard !parts.isEmpty else { return nil }

        // Last part is the key name, rest are modifiers
        let keyName = parts.last!
        let modifierNames = parts.dropLast()

        guard let keyCode = keyNameToCode[keyName] else { return nil }

        var option = false, shift = false, command = false, control = false
        for mod in modifierNames {
            switch mod {
            case "opt", "alt", "option":
                option = true
            case "shift":
                shift = true
            case "cmd", "command":
                command = true
            case "ctrl", "control":
                control = true
            default:
                return nil  // Unknown modifier
            }
        }

        let modifiers = ModifierSet(option: option, shift: shift, command: command, control: control)
        return KeyBinding(keyCode: keyCode, modifiers: modifiers)
    }

    /// Convert this binding to a human-readable string like "opt+shift+h".
    func toString() -> String {
        var parts: [String] = []
        if modifiers.control { parts.append("ctrl") }
        if modifiers.option { parts.append("opt") }
        if modifiers.shift { parts.append("shift") }
        if modifiers.command { parts.append("cmd") }
        parts.append(keyCodeToName[keyCode] ?? "unknown")
        return parts.joined(separator: "+")
    }
}

// MARK: - Key Code Constants

/// Virtual key codes for common keys (from Carbon HIToolbox).
enum KeyCode {
    // Letters
    static let a: UInt16 = UInt16(kVK_ANSI_A)
    static let b: UInt16 = UInt16(kVK_ANSI_B)
    static let c: UInt16 = UInt16(kVK_ANSI_C)
    static let d: UInt16 = UInt16(kVK_ANSI_D)
    static let e: UInt16 = UInt16(kVK_ANSI_E)
    static let f: UInt16 = UInt16(kVK_ANSI_F)
    static let g: UInt16 = UInt16(kVK_ANSI_G)
    static let h: UInt16 = UInt16(kVK_ANSI_H)
    static let i: UInt16 = UInt16(kVK_ANSI_I)
    static let j: UInt16 = UInt16(kVK_ANSI_J)
    static let k: UInt16 = UInt16(kVK_ANSI_K)
    static let l: UInt16 = UInt16(kVK_ANSI_L)
    static let m: UInt16 = UInt16(kVK_ANSI_M)
    static let n: UInt16 = UInt16(kVK_ANSI_N)
    static let o: UInt16 = UInt16(kVK_ANSI_O)
    static let p: UInt16 = UInt16(kVK_ANSI_P)
    static let q: UInt16 = UInt16(kVK_ANSI_Q)
    static let r: UInt16 = UInt16(kVK_ANSI_R)
    static let s: UInt16 = UInt16(kVK_ANSI_S)
    static let t: UInt16 = UInt16(kVK_ANSI_T)
    static let u: UInt16 = UInt16(kVK_ANSI_U)
    static let v: UInt16 = UInt16(kVK_ANSI_V)
    static let w: UInt16 = UInt16(kVK_ANSI_W)
    static let x: UInt16 = UInt16(kVK_ANSI_X)
    static let y: UInt16 = UInt16(kVK_ANSI_Y)
    static let z: UInt16 = UInt16(kVK_ANSI_Z)

    // Numbers
    static let zero: UInt16 = UInt16(kVK_ANSI_0)
    static let one: UInt16 = UInt16(kVK_ANSI_1)
    static let two: UInt16 = UInt16(kVK_ANSI_2)
    static let three: UInt16 = UInt16(kVK_ANSI_3)
    static let four: UInt16 = UInt16(kVK_ANSI_4)
    static let five: UInt16 = UInt16(kVK_ANSI_5)
    static let six: UInt16 = UInt16(kVK_ANSI_6)
    static let seven: UInt16 = UInt16(kVK_ANSI_7)
    static let eight: UInt16 = UInt16(kVK_ANSI_8)
    static let nine: UInt16 = UInt16(kVK_ANSI_9)

    // Special keys
    static let equal: UInt16 = UInt16(kVK_ANSI_Equal)
    static let minus: UInt16 = UInt16(kVK_ANSI_Minus)
    static let space: UInt16 = UInt16(kVK_Space)
    static let tab: UInt16 = UInt16(kVK_Tab)
    static let returnKey: UInt16 = UInt16(kVK_Return)
    static let escape: UInt16 = UInt16(kVK_Escape)
    static let delete: UInt16 = UInt16(kVK_Delete)

    // Arrow keys
    static let leftArrow: UInt16 = UInt16(kVK_LeftArrow)
    static let rightArrow: UInt16 = UInt16(kVK_RightArrow)
    static let upArrow: UInt16 = UInt16(kVK_UpArrow)
    static let downArrow: UInt16 = UInt16(kVK_DownArrow)

    // Punctuation
    static let comma: UInt16 = UInt16(kVK_ANSI_Comma)
    static let period: UInt16 = UInt16(kVK_ANSI_Period)
    static let slash: UInt16 = UInt16(kVK_ANSI_Slash)
    static let semicolon: UInt16 = UInt16(kVK_ANSI_Semicolon)
    static let quote: UInt16 = UInt16(kVK_ANSI_Quote)
    static let leftBracket: UInt16 = UInt16(kVK_ANSI_LeftBracket)
    static let rightBracket: UInt16 = UInt16(kVK_ANSI_RightBracket)
    static let backslash: UInt16 = UInt16(kVK_ANSI_Backslash)
    static let grave: UInt16 = UInt16(kVK_ANSI_Grave)
}

// MARK: - Key Name ↔ Key Code Maps

/// Maps string key names to Carbon virtual key codes.
let keyNameToCode: [String: UInt16] = {
    var map: [String: UInt16] = [:]
    // Letters
    for (name, code) in [
        ("a", KeyCode.a), ("b", KeyCode.b), ("c", KeyCode.c), ("d", KeyCode.d),
        ("e", KeyCode.e), ("f", KeyCode.f), ("g", KeyCode.g), ("h", KeyCode.h),
        ("i", KeyCode.i), ("j", KeyCode.j), ("k", KeyCode.k), ("l", KeyCode.l),
        ("m", KeyCode.m), ("n", KeyCode.n), ("o", KeyCode.o), ("p", KeyCode.p),
        ("q", KeyCode.q), ("r", KeyCode.r), ("s", KeyCode.s), ("t", KeyCode.t),
        ("u", KeyCode.u), ("v", KeyCode.v), ("w", KeyCode.w), ("x", KeyCode.x),
        ("y", KeyCode.y), ("z", KeyCode.z),
    ] { map[name] = code }
    // Numbers
    for (name, code) in [
        ("0", KeyCode.zero), ("1", KeyCode.one), ("2", KeyCode.two), ("3", KeyCode.three),
        ("4", KeyCode.four), ("5", KeyCode.five), ("6", KeyCode.six), ("7", KeyCode.seven),
        ("8", KeyCode.eight), ("9", KeyCode.nine),
    ] { map[name] = code }
    // Special
    for (name, code) in [
        ("space", KeyCode.space), ("tab", KeyCode.tab), ("return", KeyCode.returnKey),
        ("escape", KeyCode.escape), ("delete", KeyCode.delete),
        ("equal", KeyCode.equal), ("minus", KeyCode.minus),
        ("left", KeyCode.leftArrow), ("right", KeyCode.rightArrow),
        ("up", KeyCode.upArrow), ("down", KeyCode.downArrow),
        ("comma", KeyCode.comma), ("period", KeyCode.period), ("slash", KeyCode.slash),
        ("semicolon", KeyCode.semicolon), ("quote", KeyCode.quote),
        ("leftbracket", KeyCode.leftBracket), ("rightbracket", KeyCode.rightBracket),
        ("backslash", KeyCode.backslash), ("grave", KeyCode.grave),
    ] { map[name] = code }
    return map
}()

/// Reverse map: key code → string name.
let keyCodeToName: [UInt16: String] = {
    var map: [UInt16: String] = [:]
    for (name, code) in keyNameToCode {
        map[code] = name
    }
    return map
}()
