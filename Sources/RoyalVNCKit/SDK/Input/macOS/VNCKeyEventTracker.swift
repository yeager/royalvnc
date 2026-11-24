#if os(macOS)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import AppKit
import CoreGraphics

/// Keeps each VNC key-up paired with the key symbol emitted for its key-down.
struct VNCKeyEventTracker {
    private var pressedKeys: [CGKeyCode: [VNCKeyCode]] = [:]

    static func resolvedCharacters(for event: NSEvent) -> String? {
        if let characters = event.characters, !characters.isEmpty {
            return characters
        }
        return event.charactersIgnoringModifiers
    }

    mutating func keyDown(for keyCode: CGKeyCode, characters: String?) -> [VNCKeyCode] {
        if let pressed = pressedKeys[keyCode] {
            return pressed
        }

        let keys = VNCKeyCode.keyCodesFrom(cgKeyCode: keyCode, characters: characters)
        if !keys.isEmpty {
            pressedKeys[keyCode] = keys
        }
        return keys
    }

    mutating func keyUp(for keyCode: CGKeyCode) -> [VNCKeyCode] {
        pressedKeys.removeValue(forKey: keyCode) ?? []
    }

    mutating func releaseAll() -> [VNCKeyCode] {
        let keys = pressedKeys.keys.sorted().flatMap { pressedKeys[$0] ?? [] }
        pressedKeys.removeAll()
        return keys
    }
}
#endif
