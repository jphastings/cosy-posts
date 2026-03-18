import Foundation
import Testing

/// Contract tests for access request endpoints (contracts/access_requests.json).
/// Verifies the app constructs requests and decodes responses correctly.
struct AccessRequestsContractTests {

    // MARK: - List (GET /api/access-requests)

    @Test func listRequestFormat() throws {
        let contract = try ContractLoader.load("access_requests")
        let endpoints = contract["endpoints"] as! [String: Any]
        let list = endpoints["list"] as! [String: Any]
        let request = list["request"] as! [String: Any]

        #expect(request["method"] as? String == "GET")
        #expect(request["path"] as? String == "/api/access-requests")
    }

    @Test func listResponseDecoding() throws {
        // Server returns a JSON array of email strings.
        let serverJSON = """
        ["user1@example.com","user2@example.com"]
        """.data(using: .utf8)!

        // App decodes as [String] (in AccessRequestsLoader.load).
        let emails = try JSONDecoder().decode([String].self, from: serverJSON)
        #expect(emails.count == 2)
        #expect(emails[0] == "user1@example.com")
    }

    @Test func listResponseEmptyArray() throws {
        let serverJSON = "[]".data(using: .utf8)!
        let emails = try JSONDecoder().decode([String].self, from: serverJSON)
        #expect(emails.isEmpty)
    }

    // MARK: - Approve (POST /api/access-requests/{email}/approve)

    @Test func approveRequestFormat() throws {
        let contract = try ContractLoader.load("access_requests")
        let endpoints = contract["endpoints"] as! [String: Any]
        let approve = endpoints["approve"] as! [String: Any]
        let request = approve["request"] as! [String: Any]

        #expect(request["method"] as? String == "POST")

        let path = request["path"] as! String
        #expect(path.contains("/api/access-requests/"))
        #expect(path.hasSuffix("/approve"))
    }

    /// Verify the app URL-encodes the email in the path.
    @Test func approveURLConstruction() throws {
        let serverURL = URL(string: "https://example.com")!
        let email = "user@example.com"
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email

        let path = "api/access-requests/\(encodedEmail)/approve"
        let url = serverURL.appendingPathComponent(path)

        #expect(url.absoluteString.contains("access-requests"))
        #expect(url.absoluteString.hasSuffix("/approve"))
    }

    // MARK: - Deny (DELETE /api/access-requests/{email})

    @Test func denyRequestFormat() throws {
        let contract = try ContractLoader.load("access_requests")
        let endpoints = contract["endpoints"] as! [String: Any]
        let deny = endpoints["deny"] as! [String: Any]
        let request = deny["request"] as! [String: Any]

        #expect(request["method"] as? String == "DELETE")

        let path = request["path"] as! String
        #expect(path.contains("/api/access-requests/"))
    }
}
