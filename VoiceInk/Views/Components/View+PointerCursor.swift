//
//  View+PointerCursor.swift
//  VoiceInk
//
//  macOS doesn't switch to the pointing-hand cursor over custom clickable SwiftUI
//  views the way the web does for `cursor: pointer`. This modifier adds that hint so
//  buttons/rows/cards read as clickable.
//

import SwiftUI

extension View {
    /// Shows the pointing-hand cursor while the pointer is over this view.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
