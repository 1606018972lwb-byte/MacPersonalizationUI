# MacWindowButtons

MacWindowButtons is a Swift and AppKit menu bar utility that keeps an independent Windows-style control row above the focused macOS window. It does not move or modify the native red, yellow, and green controls.

The current version is 26.0825.01. Versions use `YY.MMDD.NN`: two-digit year, month and day, and the modification sequence for that day.

- Accessibility permission prompting and a System Settings shortcut.
- An irreversible salted SHA-256 encrypted device code derived from `IOPlatformUUID`; the raw hardware UUID is never displayed or passed to the issuing tool.
- Offline Ed25519-signed activation codes bound to the device and an expiry timestamp; zero-day licenses are permanent and app updates retain activation.
- Clock-rollback detection backed by both Login Keychain and Application Support state, plus monotonic uptime checks while the process is running.
- A classic macOS preferences layout with General, Permission, Update, Other, Shortcuts, and About tabs.
- Button size is now part of General alongside window controls, launch at login, and window scanning.
- General no longer collapses settings; window controls, control size, launch at login, and window scanning remain visible at all times.
- A compact row layout makes every General setting directly available without an extra click.
- The checkbox now uses the concise “Silent Launch” title, while its detailed behavior is shown as secondary text below it.
- Silent launch is enabled by default, so initial launch, login launch, and in-app restart show only the menu bar item instead of opening Settings automatically.
- Clicking the menu bar item, choosing Open Settings, or launching the app again while it is already running still opens Settings explicitly.
- The Shortcuts tab includes an opt-in “Press Delete to delete files or eject disks” checkbox, which is disabled by default.
- Finder now provides a Windows-style “Send To → Desktop Shortcut” context submenu that creates Finder aliases for selected files and folders.
- Desktop alias names omit the “ - Shortcut” suffix by default, with an optional suffix selector; collisions are numbered from `(1)` upward.
- The shortcut only intercepts Delete while Finder is frontmost: ejectable volumes use native Command-E, while regular files and folders use native Command-Delete with Undo support.
- Holding Delete triggers the action only once, preventing key repeat from moving subsequently selected files; Delete remains unchanged in every other application.
- The first Shortcuts action opens macOS Keyboard Shortcuts settings directly.
- Separate opt-in shortcuts can be recorded for cycling input methods and toggling Chinese/English; both are disabled by default and only act in text fields, search/address fields, multiline editors, and editable web content.
- Input-method shortcuts now use a listen-only `CGEventTap` with automatic retry after Accessibility permission becomes available, preventing missed events in VS Code and other Electron editors.
- Focus detection follows nested Accessibility focus nodes and recognizes selection, insertion-point, and editable-value capabilities used by VS Code editors and browser chat inputs.
- A single modifier, multiple modifiers, or modifiers plus a regular key can be recorded. Regular keys are stored as physical key codes, independent of the active keyboard layout.
- The two input-source actions cannot share the same combination; duplicates show a warning and preserve the previous setting.
- Modifier-only shortcuts fire after all modifiers are released and are cancelled if a regular key is pressed, preventing Command-Shift-T and similar shortcuts from being mistaken for Command-Shift.
- Cycling moves through enabled keyboard input sources, while Chinese/English toggle remembers the most recently used source in each language group.
- An Other-page style selector that keeps the existing floating appearance by default or switches to an integrated title-bar appearance.
- Integrated appearance keeps a real panel as wide as the target window while making all space outside the three controls fully transparent.
- Dragging the transparent empty area is handled by the overlay itself, which moves the AX target window directly instead of waiting for the original window to move first.
- Both appearances enforce enough distance between the target window and the screen's visible top edge for the complete control row, preventing the transparent panel from covering native window functions.
- A screen-filling window is shortened when necessary so that reserving the top row does not push its bottom edge off screen.
- Both appearances reserve an extra row for maximized windows so the complete control panel remains outside the native window.
- Login-at-launch registration through macOS 13 `SMAppService`, including approval guidance and a direct Login Items settings shortcut.
- Update reminders and safe automatic installation are enabled by default, with a default 7-day check interval and optional daily or 30-day intervals.
- Manual checks remain available at any time.
- Automatic installation only after validating the DMG SHA-256, bundle identifier, version, and code signature; failed validation falls back to a manual update prompt.
- Focused-window discovery through `AXUIElement`.
- A non-activating translucent `NSPanel` that follows the focused window.
- Both modes use an always-visible full-width row above the target; integrated mode hides the row background and leaves only the three controls visible.
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
- Maximization verifies the final Accessibility frame and corrects delayed VS Code/Electron layout changes so the window fills the screen's usable area exactly.
- Per-window restore frames and multi-display coordinate conversion.
- A 1-second low-frequency compatibility fallback for applications that do not emit AX notifications.
- A persistent Small, Standard, or Large control-size submenu in the menu bar.
- Immediate resizing of all three buttons, their symbols, and the overlay panel.
- Full rectangular hit targets of 38×30, 46×35, or 54×42 points, with no gaps or hidden alignment insets.
- A native AppKit control center opened by clicking the menu bar icon.
- A clear missing-permission card and click-triggered authorization guidance.
- An original Retina macOS application icon and complete AppIcon asset catalog.
- An optional control-center window on first launch that always reopens when the running app is launched again or its menu bar item is clicked.
- A high-contrast template menu bar icon and a visible permission status card when permission is missing.
- A right-click menu for opening settings, restarting the app, or quitting.
- A main-window refresh action that scans all controllable windows and reports the count.
- Immediate display of the minimize, maximize/restore, and close controls on the most recent target window after a refresh.
- A UIElement menu bar mode that keeps the Dock icon hidden while the application is running.
- A standard settings window that opens on first launch when silent launch is disabled and remains directly accessible from the menu bar.
- An explicit programmatic AppDelegate bootstrap for the storyboard-free project, ensuring launch callbacks always create the main window.
- A process-level lock that permits only one running instance; repeated launches activate the existing instance and show its main window.
- A single-instance-aware restart flow that releases the lock before launching the replacement process.
- No repeated permission prompt on launch or refresh; the system prompt appears only after an explicit user action.
- A repair action that resets stale Accessibility records left by older ad-hoc signatures.
- Automatic window scanning as soon as Accessibility permission becomes effective.
- A DMG build script with a stable designated requirement for consistent local TCC identity across test updates.

The application starts silently by default and stays out of the Dock. A full-width control row remains visible above the focused window, with the three controls on its right. Repeated launches reuse the existing process, and the menu bar icon opens the settings window.

The local test package is `dist/MacWindowButtons-26.0825.01.dmg`. It is ad-hoc signed and not notarized. Automatic installation also requires the Release notes to contain the DMG's 64-character SHA-256 and a writable application directory. The project does not disable SIP, modify system files, or inject code into other processes.

The offline issuer is `licenseGet/generate_license.py`. It stores the Ed25519 signing key as a password-encrypted PKCS#8 `license_private_key.pem`; migrate the legacy plaintext JSON with `--migrate-key` so the embedded public key and existing licenses remain valid. Keep the encrypted key and password in separate offline backups, and never ship either private-key file in the application or DMG.
