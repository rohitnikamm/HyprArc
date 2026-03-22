import AppKit
import Carbon.HIToolbox

/// A key + modifier combination for a hotkey binding.
struct KeyBinding: Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: ModifierSet

    /// Simplified modifier set (avoids NSEvent.ModifierFlags Hashable issues).
    struct ModifierSet: Hashable, Sendable {
        let option: Bool
        let shift: Bool
        let command: Bool
        let control: Bool

        static let opt = ModifierSet(option: true, shift: false, command: false, control: false)
        static let optShift = ModifierSet(option: true, shift: true, command: false, control: false)
    }

    /// Check if a CGEvent matches this binding.
    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
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
}

// MARK: - Key Code Constants

/// Virtual key codes for common keys (from Carbon HIToolbox).
enum KeyCode {
    static let h: UInt16 = UInt16(kVK_ANSI_H)
    static let j: UInt16 = UInt16(kVK_ANSI_J)
    static let k: UInt16 = UInt16(kVK_ANSI_K)
    static let l: UInt16 = UInt16(kVK_ANSI_L)
    static let d: UInt16 = UInt16(kVK_ANSI_D)
    static let e: UInt16 = UInt16(kVK_ANSI_E)
    static let equal: UInt16 = UInt16(kVK_ANSI_Equal)
    static let minus: UInt16 = UInt16(kVK_ANSI_Minus)
    static let space: UInt16 = UInt16(kVK_Space)
    static let one: UInt16 = UInt16(kVK_ANSI_1)
    static let two: UInt16 = UInt16(kVK_ANSI_2)
    static let three: UInt16 = UInt16(kVK_ANSI_3)
    static let four: UInt16 = UInt16(kVK_ANSI_4)
    static let five: UInt16 = UInt16(kVK_ANSI_5)
    static let six: UInt16 = UInt16(kVK_ANSI_6)
    static let seven: UInt16 = UInt16(kVK_ANSI_7)
    static let eight: UInt16 = UInt16(kVK_ANSI_8)
    static let nine: UInt16 = UInt16(kVK_ANSI_9)
}
