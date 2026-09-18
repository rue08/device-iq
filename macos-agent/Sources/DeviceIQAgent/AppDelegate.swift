import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var pairMenuItem: NSMenuItem!
    private var syncMenuItem: NSMenuItem!
    private var pairingWindow: PairingWindowController?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Device Health Copilot")

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Checking status…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        pairMenuItem = NSMenuItem(title: "Link This Device…", action: #selector(showPairingWindow), keyEquivalent: "")
        pairMenuItem.target = self
        menu.addItem(pairMenuItem)

        syncMenuItem = NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "")
        syncMenuItem.target = self
        menu.addItem(syncMenuItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu

        Task { await refreshMenuState() }
        timer = Timer.scheduledTimer(withTimeInterval: Config.snapshotInterval, repeats: true) { [weak self] _ in
            self?.syncNow()
        }
    }

    @objc private func showPairingWindow() {
        let controller = PairingWindowController()
        controller.onPaired = { [weak self] deviceId, tokenResult in
            Task {
                await SessionManager.shared.adopt(deviceId: deviceId, tokenResult: tokenResult)
                await self?.refreshMenuState()
                self?.syncNow()
            }
        }
        pairingWindow = controller
        controller.start()
    }

    @objc private func syncNow() {
        Task { await performSync() }
    }

    private func performSync() async {
        guard await SessionManager.shared.isPaired else {
            statusMenuItem.title = "Status: not paired"
            return
        }
        do {
            let deviceId = try await SessionManager.shared.currentDeviceId()
            let snapshot = Telemetry.collect()
            try await ApiClient.uploadSnapshot(deviceId: deviceId, payload: snapshot.jsonPayload)
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            statusMenuItem.title = "Status: synced at \(formatter.string(from: Date()))"
        } catch {
            statusMenuItem.title = "Sync error: \(error.localizedDescription)"
        }
    }

    private func refreshMenuState() async {
        let paired = await SessionManager.shared.isPaired
        pairMenuItem.title = paired ? "Re-link This Device…" : "Link This Device…"
        syncMenuItem.isEnabled = paired
        if !paired {
            statusMenuItem.title = "Status: not paired"
        }
    }
}
