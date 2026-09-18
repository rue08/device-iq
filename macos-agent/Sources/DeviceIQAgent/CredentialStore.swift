import Foundation

// Persists just enough to re-authenticate on every run without re-pairing:
// the device id and a long-lived Firebase refresh token. Stored as a plain
// file with owner-only permissions rather than Keychain - simpler code for
// a hackathon-scoped agent; Keychain would be the hardening step if this
// agent goes past the demo.
struct StoredCredentials: Codable {
    let deviceId: String
    let refreshToken: String
}

enum CredentialStore {
    static func load() -> StoredCredentials? {
        guard let data = try? Data(contentsOf: Config.credentialsFileURL) else { return nil }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    static func save(_ credentials: StoredCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let url = Config.credentialsFileURL
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: Config.credentialsFileURL)
    }
}
