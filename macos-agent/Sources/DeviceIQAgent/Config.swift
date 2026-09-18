import Foundation

// Values here match backend/.env - see PROJECT.md §2b for why the web API
// key is safe to embed client-side (it's the public Firebase Web API key,
// not a service-account secret; the backend's admin key never leaves the
// server).
enum Config {
    // Local dev backend. Point this at the deployed URL once Phase 6 lands.
    static let backendBaseURL = URL(string: "http://localhost:4000")!

    static let firebaseWebApiKey = "AIzaSyCCoLdGsaHcJ5ZFaojjVQ2DtpiFtsRT-m8"

    // How often the agent captures and uploads a snapshot, per PROJECT.md
    // Phase 1b ("every ~5-15 min, tunable").
    static let snapshotInterval: TimeInterval = 10 * 60

    static let pairingPollInterval: TimeInterval = 3

    static var credentialsFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DeviceIQAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("credentials.json")
    }
}
