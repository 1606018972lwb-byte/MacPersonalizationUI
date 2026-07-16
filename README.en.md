# MacWindowButtons

MacWindowButtons is a Swift and AppKit menu bar utility that adds an independent Windows-style control strip to the top-right corner of the focused macOS window. It does not move or modify the native red, yellow, and green controls.

Version 1.3.1 includes:

- Accessibility permission prompting and a System Settings shortcut.
- Focused-window discovery through `AXUIElement`.
- A non-activating translucent `NSPanel` that follows the focused window.
- Minimize, maximize/restore, and close actions.
- Per-window restore frames and multi-display coordinate conversion.
- A 200ms compatibility polling interval with low timer tolerance.
- A persistent Small, Standard, or Large control-size submenu in the menu bar.
- Immediate resizing of all three buttons, their symbols, and the overlay panel.
- A native AppKit control center opened by clicking the menu bar icon.
- A clear missing-permission card and click-triggered authorization guidance.
- An original Retina macOS application icon and complete AppIcon asset catalog.
- A control-center window that opens on launch and reopens when the running app is double-clicked.
- An orange menu bar warning icon and an immediate authorization alert when permission is missing.

To test, install `dist/MacWindowButtons-1.3.1.dmg`. The control center opens automatically and reports missing Accessibility permission. Enable MacWindowButtons in System Settings → Privacy & Security → Accessibility. The same window changes button size and exits the app.

The test DMG is ad-hoc signed and not notarized. The project does not disable SIP, modify system files, or inject code into other processes.
