import AppKit

// The first-run / re-pair window: shows a QR code for the phone to scan
// (WhatsApp-linked-devices style, see PROJECT.md §2b) and polls the backend
// until the phone claims it.
final class PairingWindowController: NSWindowController {
    private let statusLabel = NSTextField(labelWithString: "Generating pairing code…")
    private let imageView = NSImageView()
    private var pollTask: Task<Void, Never>?
    var onPaired: ((_ deviceId: String, _ tokenResult: IdTokenResult) -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Link This Laptop"
        window.center()
        self.init(window: window)
        buildContent()
    }

    private func buildContent() {
        guard let window else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Scan with the DeviceIQ app")
        title.font = .systemFont(ofSize: 13, weight: .medium)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.widthAnchor.constraint(equalToConstant: 220).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 220).isActive = true

        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(statusLabel)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
        ])
        window.contentView = container
    }

    func start() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pollTask = Task { await runPairingFlow() }
    }

    override func close() {
        pollTask?.cancel()
        super.close()
    }

    private func runPairingFlow() async {
        do {
            let pending = try await ApiClient.createPendingPairing()
            imageView.image = QRCodeGenerator.image(for: pending.token)
            statusLabel.stringValue = "Waiting for phone to scan…"

            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: UInt64(Config.pairingPollInterval * 1_000_000_000))
                let status = try await ApiClient.pairingStatus(token: pending.token)
                guard status.claimed else { continue }

                guard let deviceId = status.deviceId, let deviceToken = status.deviceToken else {
                    // Already claimed and delivered in a previous poll (e.g.
                    // window reopened) - nothing left for us to pick up.
                    statusLabel.stringValue = "Already claimed - close and reopen to retry."
                    return
                }

                statusLabel.stringValue = "Paired! Finishing setup…"
                let tokenResult = try await AuthClient.exchangeCustomToken(deviceToken)
                onPaired?(deviceId, tokenResult)
                statusLabel.stringValue = "Done."
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { self.close() }
                return
            }
        } catch {
            statusLabel.stringValue = "Error: \(error.localizedDescription)"
        }
    }
}
