# MacWindowButtons

MacWindowButtons is a Swift and AppKit menu bar utility that keeps an independent Windows-style control row above the focused macOS window. It does not move or modify the native red, yellow, and green controls.

Test build 1.4.4 is based on release 1.3, redesigns the integrated control row, and keeps the Finder file shortcut:

- Accessibility permission prompting and a System Settings shortcut.
- A classic macOS preferences layout with General, Permission, Update, Other, Shortcuts, and About tabs.
- Button size is now part of General alongside window controls, launch at login, and window scanning.
- General no longer collapses settings; window controls, control size, launch at login, and window scanning remain visible at all times.
- A compact row layout makes every General setting directly available without an extra click.
- A new Shortcuts tab includes an opt-in “Press Delete to move files to Trash” checkbox, which is disabled by default.
- The shortcut only intercepts Delete while Finder is frontmost and delegates the action to Finder's native Command-Delete behavior, preserving Undo support.
- Holding Delete triggers the action only once, preventing key repeat from moving subsequently selected files; Delete remains unchanged in every other application.
- An Other-page style selector that keeps the existing floating appearance by default or switches to an integrated title-bar appearance.
- The integrated appearance now uses the window-background material to avoid the desktop-tinted color mismatch of the previous title-bar material.
- The full control row remains visible while a 10-point backing extension is ordered directly behind the target window, filling both top-corner gaps without covering native controls or content.
- If the target's cross-process window level cannot be identified, overlap is disabled so the control row cannot obstruct the application.
- Maximized windows reserve the full control-row height in both appearance modes.
- Login-at-launch registration through macOS 13 `SMAppService`, including approval guidance and a direct Login Items settings shortcut.
- Update reminders and safe automatic installation are enabled by default, with a default 7-day check interval and optional daily or 30-day intervals.
- Manual checks remain available at any time.
- Automatic installation only after validating the DMG SHA-256, bundle identifier, version, and code signature; failed validation falls back to a manual update prompt.
- Focused-window discovery through `AXUIElement`.
- A non-activating translucent `NSPanel` that follows the focused window.
- An always-visible row matching the target window width, with an empty left placeholder and the three controls aligned right.
- Event-driven `AXObserver` tracking for immediate move, resize, and focused-window updates.
- Native title-bar moves update the overlay directly without an extra main-queue hop or focused-window rescan.
- A temporary up-to-120Hz AX geometry tracker runs only while the original window is moving and stops automatically after the mouse is released.
- Browser-extension popovers, menu-like floating panels, and transient windows without native window controls are excluded.
- Opening a browser extension keeps the control row attached to that browser's main window instead of hiding it or targeting the extension popup.
- The fallback uses `AXMainWindow` first and then the largest eligible standard window for browser versions that omit that attribute.
- Real application settings/preferences windows remain eligible, including MacWindowButtons' own settings window.
- Full-window refresh now prioritizes the actually focused eligible window instead of a previously used background window.
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

The local test package is `dist/MacWindowButtons-1.4.4.dmg`. It is ad-hoc signed and not notarized. Automatic installation also requires the Release notes to contain the DMG's 64-character SHA-256 and a writable application directory. The project does not disable SIP, modify system files, or inject code into other processes.
