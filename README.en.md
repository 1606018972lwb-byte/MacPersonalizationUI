# MacWindowButtons

MacWindowButtons is a Swift and AppKit menu bar utility that keeps an independent Windows-style control row above the focused macOS window. It does not move or modify the native red, yellow, and green controls.

Local test version 1.1.3 includes:

- Accessibility permission prompting and a System Settings shortcut.
- Focused-window discovery through `AXUIElement`.
- A non-activating translucent `NSPanel` that follows the focused window.
- An always-visible row matching the target window width, with an empty left placeholder and the three controls aligned right.
- Event-driven `AXObserver` tracking for immediate move, resize, and focused-window updates.
- Dragging the empty left area moves the target window like a Windows title bar.
- Maximization reserves one full control-row above the target window so the controls never cover its title bar or content.
- Minimize, maximize/restore, and close actions.
- Per-window restore frames and multi-display coordinate conversion.
- A 1-second low-frequency compatibility fallback for applications that do not emit AX notifications.
- A persistent Small, Standard, or Large control-size submenu in the menu bar.
- Immediate resizing of all three buttons, their symbols, and the overlay panel.
- Full rectangular hit targets of 38×30, 46×35, or 54×42 points, with no gaps or hidden alignment insets.
- A native AppKit control center opened by clicking the menu bar icon.
- A clear missing-permission card and click-triggered authorization guidance.
- An original Retina macOS application icon and complete AppIcon asset catalog.
- A control-center window that opens on launch and reopens when the running app is double-clicked.
- A high-contrast template menu bar icon and a visible permission status card when permission is missing.
- A right-click menu for opening settings, restarting the app, or quitting.
- A main-window refresh action that scans all controllable windows and reports the count.
- Immediate display of the minimize, maximize/restore, and close controls on the most recent target window after a refresh.
- A UIElement menu bar mode that keeps the Dock icon hidden while the application is running.
- A standard main window that opens on first launch and reopens after double-clicking the app or clicking its menu bar icon.
- An explicit programmatic AppDelegate bootstrap for the storyboard-free project, ensuring launch callbacks always create the main window.
- A process-level lock that permits only one running instance; repeated launches activate the existing instance and show its main window.
- A single-instance-aware restart flow that releases the lock before launching the replacement process.
- No repeated permission prompt on launch or refresh; the system prompt appears only after an explicit user action.
- A repair action that resets stale Accessibility records left by older ad-hoc signatures.
- Automatic window scanning as soon as Accessibility permission becomes effective.
- A DMG build script with a stable designated requirement for consistent local TCC identity across test updates.

The main window opens automatically while the application stays out of the Dock. A full-width control row remains visible above the focused window, with the three controls on its right. Repeated launches reuse the existing process, and the menu bar icon reopens the main window.

The test DMG is ad-hoc signed and not notarized. The project does not disable SIP, modify system files, or inject code into other processes.
