# MacWindowButtons

MacWindowButtons is a Swift and AppKit menu bar utility that adds an independent Windows-style control strip to the top-right corner of the focused macOS window. It does not move or modify the native red, yellow, and green controls.

Version 1.7 includes:

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
- A high-contrast template menu bar icon and an immediate authorization alert when permission is missing.
- A right-click menu for opening settings, restarting the app, or quitting.
- A main-window refresh action that scans all controllable windows and reports the count.
- Immediate display of the minimize, maximize/restore, and close controls on the most recent target window after a refresh.
- A persistent Dock icon while the application is running.
- A standard main window that opens on first launch and reopens after double-clicking the app or clicking its Dock icon.
- An explicit programmatic AppDelegate bootstrap for the storyboard-free project, ensuring launch callbacks always create the main window.

To test, install `dist/MacWindowButtons-1.7.dmg`. The main window opens automatically and the application icon remains visible in the Dock. Enable MacWindowButtons in System Settings → Privacy & Security → Accessibility. Click “Refresh All Application Windows” to rescan windows and show the three controls, or right-click the menu bar icon to open settings, restart, or quit.

The test DMG is ad-hoc signed and not notarized. The project does not disable SIP, modify system files, or inject code into other processes.
