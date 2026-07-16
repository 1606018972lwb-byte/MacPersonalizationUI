# MacWindowButtons

MacWindowButtons is a macOS window enhancement utility built with Swift, AppKit, and the Accessibility API. It will display an independent control strip at the top-right corner of another application's window instead of modifying the native red, yellow, and green controls.

## Current delivery

This commit intentionally implements one feature only: the AppKit menu bar application foundation.

- A macOS 13+ Xcode application project.
- An `NSStatusItem` with Enable, Pause, and Quit actions.
- Mutually exclusive Enable and Pause state ready for future window services.
- No Dock or Command-Tab entry, configured through `LSUIElement` and the accessory activation policy.
- A Retina-ready SF Symbol with a text fallback.

Accessibility permission handling, focused-window discovery, and the overlay panel will be delivered as separate commits.

## Build

1. Install Xcode 14 or newer.
2. Open `MacWindowButtons.xcodeproj`.
3. Select your development team in Signing & Capabilities.
4. Select My Mac and run the project.

The project does not disable SIP, modify system files, or inject code into other processes. Accessibility permission will be required by later window-control features.
