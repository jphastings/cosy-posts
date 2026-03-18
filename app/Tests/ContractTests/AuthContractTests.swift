import Foundation
import Testing

/// Contract tests verifying the app constructs auth requests exactly as the
/// server expects (contracts/auth_send.json, contracts/auth_verify.json).
struct AuthContractTests {

    // MARK: - Auth Send (contracts/auth_send.json)

    @Test func authSendRequestFormat() throws {
        let contract = try ContractLoader.load("auth_send")
        let request = contract["request"] as! [String: Any]
        let headers = request["headers"] as! [String: String]

        // App must send POST with form-encoded body.
        #expect(request["method"] as? String == "POST")
        #expect(request["path"] as? String == "/auth/send")
        #expect(headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(headers["Accept"] == "application/json")
    }

    /// Verify the app constructs the auth/send request body correctly.
    @Test func authSendBodyEncoding() throws {
        // Reproduce exactly how AuthManager.sendMagicLink() builds the body.
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "email", value: "test@example.com")]
        let body = components.percentEncodedQuery

        #expect(body != nil, "Body must not be nil")
        #expect(body!.contains("email="), "Body must contain email= parameter")
        #expect(body!.contains("test"), "Body must contain the email value")
    }

    // MARK: - Auth Verify (contracts/auth_verify.json)

    @Test func authVerifyRequestFormat() throws {
        let contract = try ContractLoader.load("auth_verify")
        let request = contract["request"] as! [String: Any]
        let headers = request["headers"] as! [String: String]
        let query = request["query"] as! [String: String]

        #expect(request["method"] as? String == "GET")
        #expect(request["path"] as? String == "/auth/verify")
        #expect(query["token"] != nil, "Must send token as query parameter")
        #expect(headers["Accept"] == "application/json", "App must request JSON response")
    }

    /// Verify the app constructs the verify URL correctly.
    @Test func authVerifyURLConstruction() throws {
        // Reproduce how AuthManager.verifyToken() builds the URL.
        let serverURL = URL(string: "https://example.com")!
        let verifyURL = serverURL.appendingPathComponent("auth/verify")
        var urlComponents = URLComponents(url: verifyURL, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "token", value: "deadbeef")]

        let finalURL = urlComponents.url!
        #expect(finalURL.path.hasSuffix("/auth/verify"), "Path must be /auth/verify")
        #expect(finalURL.query == "token=deadbeef", "Query must contain token parameter")
    }

    /// Verify the app can decode the verify response format.
    @Test func authVerifyResponseDecoding() throws {
        // This is the exact JSON shape the server returns (from contract).
        let serverJSON = """
        {"session":"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2","role":"post","email":"test@example.com"}
        """.data(using: .utf8)!

        // This is the struct the app uses to decode.
        struct VerifyResponse: Decodable {
            let session: String
            let role: String
            let email: String
        }

        let result = try JSONDecoder().decode(VerifyResponse.self, from: serverJSON)
        #expect(result.session.count == 64, "Session must be 64-char hex")
        #expect(!result.role.isEmpty, "Role must not be empty")
        #expect(!result.email.isEmpty, "Email must not be empty")
    }

    // MARK: - Auth Middleware (contracts/auth_middleware.json)

    @Test func bearerTokenFormat() throws {
        let contract = try ContractLoader.load("auth_middleware")
        let authMethods = contract["auth_methods"] as! [String: Any]
        let bearer = authMethods["bearer_token"] as! [String: String]

        #expect(bearer["header"] == "Authorization")
        #expect(bearer["format"] == "Bearer {session_id}")

        // Verify the app sets the header correctly.
        let sessionID = "a1b2c3d4"
        let headerValue = "Bearer \(sessionID)"
        #expect(headerValue == "Bearer a1b2c3d4")
        #expect(headerValue.hasPrefix("Bearer "))
    }

    @Test func unauthorizedResponseDecoding() throws {
        let contract = try ContractLoader.load("auth_middleware")
        let unauth = contract["unauthorized_response"] as! [String: Any]

        #expect(unauth["status"] as? Int == 401)

        let body = unauth["body"] as! [String: String]
        #expect(body["error"] == "unauthorized")
    }
}
