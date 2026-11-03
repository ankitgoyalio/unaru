//
//  prepare-ui-display.swift
//  unaru
//
//  Created by Ankit Goyal on 03/11/2026.

// Ensure CI can show the minimum app window, menu bar, and Dock without clipping.
import CoreGraphics

let display = CGMainDisplayID()
let minimumWidth = 1280
let minimumHeight = 1024
let original = CGDisplayBounds(display)
print("UI display before preparation: \(original)")

if original.width < CGFloat(minimumWidth) || original.height < CGFloat(minimumHeight) {
    let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] ?? []
    guard let mode = modes.filter({
        $0.isUsableForDesktopGUI() && $0.width >= minimumWidth && $0.height >= minimumHeight
    }).min(by: { $0.width * $0.height < $1.width * $1.height }) else {
        fatalError("UI tests need a display of at least \(minimumWidth) × \(minimumHeight) points; no supported mode fits.")
    }

    var configuration: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&configuration) == .success else {
        fatalError("Could not begin CI display configuration.")
    }
    guard CGConfigureDisplayWithDisplayMode(configuration, display, mode, nil) == .success else {
        CGCancelDisplayConfiguration(configuration)
        fatalError("Could not configure the CI display mode.")
    }
    guard CGCompleteDisplayConfiguration(configuration, .forSession) == .success else {
        fatalError("Could not apply the CI display mode for this login session.")
    }
}

let prepared = CGDisplayBounds(display)
print("UI display after preparation: \(prepared)")
guard prepared.width >= CGFloat(minimumWidth), prepared.height >= CGFloat(minimumHeight) else {
    fatalError("The CI display is still too small for UI acceptance tests.")
}
