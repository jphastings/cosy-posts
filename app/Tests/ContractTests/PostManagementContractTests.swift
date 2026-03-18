import XCTest
import PactSwift

/// Consumer contract tests for post management features.
final class PostManagementContractTests: XCTestCase {
    static var mockService: MockService { SharedPact.mockService }

    // MARK: - Deleting a post

    func testUserDeletesPost() {
        Self.mockService
            .uponReceiving("a user deletes one of their posts")
            .given("post abc123def456ghi789jkl exists")
            .withRequest(
                method: .DELETE,
                path: "/api/posts/abc123def456ghi789jkl",
                headers: ["Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
            )
            .willRespondWith(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: ["ok": Matcher.EqualTo(true)]
            )
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("api/posts/abc123def456ghi789jkl")
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 200)
                    done()
                }.resume()
            }
    }

    func testUserDeletesNonExistentPost() {
        Self.mockService
            .uponReceiving("a user tries to delete a post that does not exist")
            .given("no post with that ID exists")
            .withRequest(
                method: .DELETE,
                path: "/api/posts/nonexistentpost00000",
                headers: ["Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
            )
            .willRespondWith(status: 404)
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("api/posts/nonexistentpost00000")
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 404)
                    done()
                }.resume()
            }
    }

    // MARK: - Managing access requests

    func testAdminViewsPendingAccessRequests() {
        Self.mockService
            .uponReceiving("an admin views pending access requests")
            .given("there are pending access requests")
            .withRequest(
                method: .GET,
                path: "/api/access-requests",
                headers: ["Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
            )
            .willRespondWith(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: Matcher.EachLike("user@example.com", min: 1)
            )
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("api/access-requests")
                var request = URLRequest(url: url)
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 200)

                    let emails = try! JSONDecoder().decode([String].self, from: data!)
                    XCTAssertFalse(emails.isEmpty)
                    done()
                }.resume()
            }
    }

    func testAdminApprovesAccessRequest() {
        Self.mockService
            .uponReceiving("an admin approves an access request")
            .given("newuser@example.com has requested access")
            .withRequest(
                method: .POST,
                path: "/api/access-requests/newuser@example.com/approve",
                headers: ["Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
            )
            .willRespondWith(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: ["ok": Matcher.EqualTo(true)]
            )
            .run { mockServiceURL, done in
                let email = "newuser@example.com"
                let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
                let url = mockServiceURL.appendingPathComponent("api/access-requests/\(encodedEmail)/approve")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 200)
                    done()
                }.resume()
            }
    }

    func testAdminDeniesAccessRequest() {
        Self.mockService
            .uponReceiving("an admin denies an access request")
            .given("reject@example.com has requested access")
            .withRequest(
                method: .DELETE,
                path: "/api/access-requests/reject@example.com",
                headers: ["Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
            )
            .willRespondWith(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: ["ok": Matcher.EqualTo(true)]
            )
            .run { mockServiceURL, done in
                let email = "reject@example.com"
                let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
                let url = mockServiceURL.appendingPathComponent("api/access-requests/\(encodedEmail)")
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 200)
                    done()
                }.resume()
            }
    }
}
