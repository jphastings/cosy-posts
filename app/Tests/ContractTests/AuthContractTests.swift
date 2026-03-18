import XCTest
import PactSwift

/// Consumer contract tests for authentication features.
///
/// These tests define how the app interacts with the server's auth endpoints.
/// Running these tests generates a pact file in contracts/pacts/ that the
/// Go provider tests verify against.
final class AuthContractTests: XCTestCase {
    static var mockService: MockService { SharedPact.mockService }

    // MARK: - Signing in with a magic link

    func testUserSignsInWithMagicLink() {
        Self.mockService
            .uponReceiving("a user signs in with a magic link")
            .given("a valid magic link token exists for test@example.com")
            .withRequest(
                method: .GET,
                path: "/auth/verify",
                query: ["token": ["deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"]],
                headers: ["Accept": "application/json"]
            )
            .willRespondWith(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: [
                    "session": Matcher.RegexLike(
                        value: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
                        pattern: "^[0-9a-f]{64}$"
                    ),
                    "role": Matcher.SomethingLike("post"),
                    "email": Matcher.SomethingLike("test@example.com"),
                ]
            )
            .run { mockServiceURL, done in
                // Reproduce how AuthManager.verifyToken() works.
                let verifyURL = mockServiceURL.appendingPathComponent("auth/verify")
                var components = URLComponents(url: verifyURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "token", value: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")]

                var request = URLRequest(url: components.url!)
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 200)

                    struct VerifyResponse: Decodable {
                        let session: String
                        let role: String
                        let email: String
                    }

                    let result = try! JSONDecoder().decode(VerifyResponse.self, from: data!)
                    XCTAssertEqual(result.session.count, 64)
                    XCTAssertFalse(result.role.isEmpty)
                    XCTAssertFalse(result.email.isEmpty)
                    done()
                }.resume()
            }
    }

    func testUserSignsInWithExpiredToken() {
        Self.mockService
            .uponReceiving("a user tries to sign in with an expired magic link")
            .given("no valid token exists")
            .withRequest(
                method: .GET,
                path: "/auth/verify",
                query: ["token": ["0000000000000000000000000000000000000000000000000000000000000000"]],
                headers: ["Accept": "application/json"]
            )
            .willRespondWith(
                status: 401,
                headers: ["Content-Type": "application/json"],
                body: ["error": Matcher.SomethingLike("invalid or expired token")]
            )
            .run { mockServiceURL, done in
                let verifyURL = mockServiceURL.appendingPathComponent("auth/verify")
                var components = URLComponents(url: verifyURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "token", value: "0000000000000000000000000000000000000000000000000000000000000000")]

                var request = URLRequest(url: components.url!)
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 401)
                    done()
                }.resume()
            }
    }

    // MARK: - Requesting a sign-in link

    func testUserRequestsSignInLink() {
        Self.mockService
            .uponReceiving("a user requests a sign-in link")
            .given("test@example.com is an authorized user")
            .withRequest(
                method: .POST,
                path: "/auth/send",
                headers: [
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Accept": "application/json",
                ],
                body: "email=test%40example.com"
            )
            .willRespondWith(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: ["ok": Matcher.EqualTo(true)]
            )
            .run { mockServiceURL, done in
                // Reproduce how AuthManager.sendMagicLink() works.
                let sendURL = mockServiceURL.appendingPathComponent("auth/send")
                var request = URLRequest(url: sendURL)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                var components = URLComponents()
                components.queryItems = [URLQueryItem(name: "email", value: "test@example.com")]
                request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 200)
                    done()
                }.resume()
            }
    }

    // MARK: - Accessing a protected resource without signing in

    func testUnauthenticatedAccessIsRejected() {
        Self.mockService
            .uponReceiving("an unauthenticated user tries to access protected content")
            .given("no session exists")
            .withRequest(
                method: .GET,
                path: "/api/info"
            )
            .willRespondWith(
                status: 401,
                headers: ["Content-Type": "application/json"],
                body: ["error": Matcher.EqualTo("unauthorized")]
            )
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("api/info")
                // No Authorization header — just like an expired/missing session.
                URLSession.shared.dataTask(with: url) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 401)
                    done()
                }.resume()
            }
    }
}
