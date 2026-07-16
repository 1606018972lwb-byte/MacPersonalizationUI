# MacWindowButtons

MacWindowButtons is a Swift and AppKit menu bar utility that adds an independent Windows-style control strip to the top-right corner of the focused macOS window. It does not move or modify the native red, yellow, and green controls.

Version 1.2 includes:

- Accessibility permission prompting and a System Settings shortcut.
- Focused-window discovery through `AXUIElement`.
- A non-activating translucent `NSPanel` that follows the focused window.
- Minimize, maximize/restore, and close actions.
- Per-window restore frames and multi-display coordinate conversion.
- A 200ms compatibility polling interval with low timer tolerance.
- A persistent Small, Standard, or Large control-size submenu in the menu bar.
- Immediate resizing of all three buttons, their symbols, and the overlay panel.

To test, install `dist/MacWindowButtons-1.2.dmg`, enable MacWindowButtons in System Settings → Privacy & Security → Accessibility, then focus a standard application window. Use the menu bar icon → Button Size to change the controls.

The test DMG is ad-hoc signed and not notarized. The project does not disable SIP, modify system files, or inject code into other processes.
