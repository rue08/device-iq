import Foundation

// The agent has no Firebase SDK (it's a plain Swift Package Manager binary,
// not a Firebase-onboarded app), so it talks to the Identity Toolkit REST
// API directly to turn the custom token minted by backend's /devices/claim
// (see backend/src/routes/pairing.js) into a real ID token, and to refresh
// that ID token thereafter. See PROJECT.md §2b.
enum AuthError: Error {
    case requestFailed(String)
}

struct IdTokenResult {
    let idToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum AuthClient {
    static func exchangeCustomToken(_ customToken: String) async throws -> IdTokenResult {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=\(Config.firebaseWebApiKey)")!
        let body: [String: Any] = ["token": customToken, "returnSecureToken": true]
        let json = try await postJSON(url: url, body: body)
        return try parseTokenResponse(json)
    }

    static func refreshIdToken(refreshToken: String) async throws -> IdTokenResult {
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(Config.firebaseWebApiKey)")!
        let body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refreshToken]
        let json = try await postJSON(url: url, body: body)

        guard let idToken = json["id_token"] as? String,
              let newRefreshToken = json["refresh_token"] as? String,
              let expiresInStr = json["expires_in"] as? String,
              let expiresIn = TimeInterval(expiresInStr)
        else {
            throw AuthError.requestFailed("Unexpected refresh response: \(json)")
        }
        return IdTokenResult(idToken: idToken, refreshToken: newRefreshToken, expiresAt: Date().addingTimeInterval(expiresIn))
    }

    private static func parseTokenResponse(_ json: [String: Any]) throws -> IdTokenResult {
        guard let idToken = json["idToken"] as? String,
              let refreshToken = json["refreshToken"] as? String,
              let expiresInStr = json["expiresIn"] as? String,
              let expiresIn = TimeInterval(expiresInStr)
        else {
            throw AuthError.requestFailed("Unexpected sign-in response: \(json)")
        }
        return IdTokenResult(idToken: idToken, refreshToken: refreshToken, expiresAt: Date().addingTimeInterval(expiresIn))
    }

    private static func postJSON(url: URL, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AuthError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(text)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.requestFailed("Non-JSON response")
        }
        return json
    }
}
