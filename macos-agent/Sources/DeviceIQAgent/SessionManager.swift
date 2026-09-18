import Foundation

// Keeps a cached ID token fresh, refreshing via AuthClient when it's close
// to expiry, and persists the refresh token so re-launching the agent
// (e.g. after a reboot, via the LaunchAgent) doesn't require re-pairing.
actor SessionManager {
    static let shared = SessionManager()

    private var deviceId: String?
    private var idToken: String?
    private var idTokenExpiresAt: Date = .distantPast
    private var refreshToken: String?

    private init() {
        if let stored = CredentialStore.load() {
            deviceId = stored.deviceId
            refreshToken = stored.refreshToken
        }
    }

    var isPaired: Bool {
        deviceId != nil
    }

    func adopt(deviceId: String, tokenResult: IdTokenResult) {
        self.deviceId = deviceId
        self.idToken = tokenResult.idToken
        self.idTokenExpiresAt = tokenResult.expiresAt
        self.refreshToken = tokenResult.refreshToken
        CredentialStore.save(StoredCredentials(deviceId: deviceId, refreshToken: tokenResult.refreshToken))
    }

    func unpair() {
        deviceId = nil
        idToken = nil
        refreshToken = nil
        idTokenExpiresAt = .distantPast
        CredentialStore.clear()
    }

    func currentDeviceId() throws -> String {
        guard let deviceId else { throw AuthError.requestFailed("Not paired yet") }
        return deviceId
    }

    // 60s safety margin before actual expiry.
    func currentIdToken() async throws -> String {
        if let idToken, Date() < idTokenExpiresAt.addingTimeInterval(-60) {
            return idToken
        }
        guard let refreshToken else { throw AuthError.requestFailed("Not paired yet") }
        let result = try await AuthClient.refreshIdToken(refreshToken: refreshToken)
        self.idToken = result.idToken
        self.idTokenExpiresAt = result.expiresAt
        self.refreshToken = result.refreshToken
        if let deviceId {
            CredentialStore.save(StoredCredentials(deviceId: deviceId, refreshToken: result.refreshToken))
        }
        return result.idToken
    }
}
