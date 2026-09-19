import Foundation

// Talks to backend/src/routes/{devices,pairing}.js at Config.backendBaseURL.
enum ApiError: Error {
    case requestFailed(Int, String)
}

struct PendingPairing: Decodable {
    let token: String
    let expiresAt: String
}

struct PairingStatus: Decodable {
    let claimed: Bool
    let deviceId: String?
    let deviceToken: String?
}

enum ApiClient {
    static func createPendingPairing() async throws -> PendingPairing {
        let url = Config.backendBaseURL.appendingPathComponent("devices/pending-pairing")
        let (data, response) = try await post(url: url, body: nil, bearerToken: nil)
        try assertOk(response, data: data)
        return try JSONDecoder().decode(PendingPairing.self, from: data)
    }

    static func pairingStatus(token: String) async throws -> PairingStatus {
        let url = Config.backendBaseURL.appendingPathComponent("devices/pending-pairing/\(token)/status")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try assertOk(response, data: data)
        return try JSONDecoder().decode(PairingStatus.self, from: data)
    }

    static func uploadSnapshot(deviceId: String, payload: [String: Any]) async throws {
        let idToken = try await SessionManager.shared.currentIdToken()
        let url = Config.backendBaseURL.appendingPathComponent("devices/\(deviceId)/snapshots")
        let (data, response) = try await post(url: url, body: payload, bearerToken: idToken)
        try assertOk(response, data: data)
    }

    private static func post(url: URL, body: [String: Any]?, bearerToken: String?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await URLSession.shared.data(for: request)
    }

    private static func assertOk(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            throw ApiError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1, text)
        }
    }
}
