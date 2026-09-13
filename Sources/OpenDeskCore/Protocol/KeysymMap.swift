import Foundation

/// Maps macOS virtual key codes / characters to X11 keysyms, which is the
/// key encoding RFB KeyEvent messages use (RFC 6143 §7.5.4).
public enum KeysymMap {
    /// X11 keysyms for special keys.
    public enum SpecialKeysym: UInt32 {
        case backspace = 0xFF08
        case tab = 0xFF09
        case linefeed = 0xFF0A
        case clear = 0xFF0B
        case escape = 0xFF1B
        case returnKey = 0xFF0D
        case left = 0xFF51
        case up = 0xFF52
        case right = 0xFF53
        case down = 0xFF54
        case pageUp = 0xFF55
        case pageDown = 0xFF56
        case home = 0xFF50
        case end = 0xFF57
        case forwardDelete = 0xFFFF
        case f1 = 0xFFBE
        case f2 = 0xFFBF
        case f3 = 0xFFC0
        case f4 = 0xFFC1
        case f5 = 0xFFC2
        case f6 = 0xFFC3
        case f7 = 0xFFC4
        case f8 = 0xFFC5
        case f9 = 0xFFC6
        case f10 = 0xFFC7
        case f11 = 0xFFC8
        case f12 = 0xFFC9
        case shiftLeft = 0xFFE1
        case shiftRight = 0xFFE2
        case controlLeft = 0xFFE3
        case controlRight = 0xFFE4
        case capsLock = 0xFFE5
        case metaLeft = 0xFFE7
        case metaRight = 0xFFE8
        case altLeft = 0xFFE9
        case altRight = 0xFFEA
        case space = 0x0020
    }

    /// Map a macOS virtual keycode (NSEvent.keyCode) to an X11 keysym.
    public static func keysym(forVirtualKey keyCode: UInt16) -> UInt32? {
        switch keyCode {
        case 0x24: return SpecialKeysym.returnKey.rawValue
        case 0x30: return SpecialKeysym.tab.rawValue
        case 0x33: return SpecialKeysym.backspace.rawValue
        case 0x35: return SpecialKeysym.escape.rawValue
        case 0x39: return SpecialKeysym.capsLock.rawValue
        case 0x31: return SpecialKeysym.space.rawValue
        case 0x4C: return SpecialKeysym.returnKey.rawValue // keypad enter
        case 0x75: return SpecialKeysym.forwardDelete.rawValue
        case 0x73: return SpecialKeysym.home.rawValue
        case 0x77: return SpecialKeysym.end.rawValue
        case 0x74: return SpecialKeysym.pageUp.rawValue
        case 0x79: return SpecialKeysym.pageDown.rawValue
        case 0x7B: return SpecialKeysym.left.rawValue
        case 0x7C: return SpecialKeysym.right.rawValue
        case 0x7D: return SpecialKeysym.down.rawValue
        case 0x7E: return SpecialKeysym.up.rawValue
        case 0x38, 0x3C: return SpecialKeysym.shiftLeft.rawValue
        case 0x3B, 0x40: return SpecialKeysym.controlLeft.rawValue
        case 0x3A, 0x36: return SpecialKeysym.metaLeft.rawValue // option = alt
        case 0x37, 0x54: return SpecialKeysym.metaRight.rawValue // command
        default: break
        }
        // Function keys F1-F12
        let functionKeyCodes: [UInt16: SpecialKeysym] = [
            0x7A: .f1, 0x78: .f2, 0x63: .f3, 0x76: .f4,
            0x60: .f5, 0x61: .f6, 0x62: .f7, 0x64: .f8,
            0x65: .f9, 0x6D: .f10, 0x67: .f11, 0x6F: .f12,
        ]
        if let fn = functionKeyCodes[keyCode] {
            return fn.rawValue
        }
        return nil
    }

    /// Map a typed character to an X11 keysym.
    /// Latin-1 characters share their keysym with their Unicode scalar;
    /// ASCII printable range (0x20–0x7E) is the common case.
    public static func keysym(forCharacter character: Character) -> UInt32? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        if scalar.value >= 0x20 && scalar.value <= 0x7E {
            return UInt32(scalar.value)
        }
        if scalar.value >= 0xA0 && scalar.value <= 0xFF {
            return UInt32(scalar.value) // Latin-1 keysyms
        }
        return nil
    }

    /// Full mapping for an NSEvent-like description: prefer charactersIgnoringModifiers,
    /// fall back to the virtual key table for non-printable keys.
    public static func keysym(character: Character?, keyCode: UInt16) -> UInt32? {
        if let character, let ks = keysym(forCharacter: character) {
            return ks
        }
        return keysym(forVirtualKey: keyCode)
    }
}
