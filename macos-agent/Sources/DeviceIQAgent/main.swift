import AppKit

// Menu-bar-only process (no Dock icon) - see Info.plist-equivalent below via
// NSApp.setActivationPolicy, since this SPM executable has no Info.plist.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
