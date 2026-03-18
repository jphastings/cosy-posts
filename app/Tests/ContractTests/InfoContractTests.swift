import Foundation
import Testing

/// Contract tests for GET /api/info response (contracts/info.json).
/// Verifies the app's SiteInfo struct matches the server's response shape.
struct InfoContractTests {

    @Test func infoRequestFormat() throws {
        let contract = try ContractLoader.load("info")
        let request = contract["request"] as! [String: Any]
        let headers = request["headers"] as! [String: String]

        #expect(request["method"] as? String == "GET")
        #expect(request["path"] as? String == "/api/info")
        #expect(headers["Authorization"] != nil, "Must send Authorization header")
    }

    /// Verify the app's SiteInfo struct can decode a response matching the contract.
    @Test func infoResponseDecoding() throws {
        // Build a response matching the contract shape exactly.
        let serverJSON = """
        {
            "name": "Test Site",
            "version": "1.0.0",
            "git_sha": "abc123",
            "stats": {
                "posts": 10,
                "photos": 50,
                "videos": 5,
                "audio": 2,
                "members": 3
            },
            "locales": ["en", "es"]
        }
        """.data(using: .utf8)!

        // Replicate the app's SiteInfo struct for decoding.
        struct SiteStats: Decodable {
            let posts: Int
            let photos: Int
            let videos: Int
            let audio: Int
            let members: Int
        }

        struct SiteInfo: Decodable {
            let name: String
            let version: String
            let gitSHA: String
            let stats: SiteStats
            let locales: [String]

            enum CodingKeys: String, CodingKey {
                case name, version
                case gitSHA = "git_sha"
                case stats, locales
            }
        }

        let result = try JSONDecoder().decode(SiteInfo.self, from: serverJSON)
        #expect(result.name == "Test Site")
        #expect(result.stats.posts == 10)
        #expect(result.locales.count == 2)
    }

    /// Verify the contract response has all the keys the app expects.
    @Test func infoResponseRequiredKeys() throws {
        let contract = try ContractLoader.load("info")
        let response = contract["response"] as! [String: Any]
        let body = response["body"] as! [String: Any]

        // Keys the app's SiteInfo CodingKeys expect.
        let appExpectedKeys = ["name", "version", "git_sha", "stats", "locales"]
        for key in appExpectedKeys {
            #expect(body[key] != nil, "Contract response must include '\(key)' (app depends on it)")
        }

        // Stats sub-keys the app's SiteStats expects.
        let stats = body["stats"] as! [String: Any]
        let appStatsKeys = ["posts", "photos", "videos", "audio", "members"]
        for key in appStatsKeys {
            #expect(stats[key] != nil, "Contract stats must include '\(key)' (app depends on it)")
        }
    }

    /// Verify the app can handle empty locales array.
    @Test func infoResponseEmptyLocales() throws {
        let serverJSON = """
        {
            "name": "Test",
            "version": "dev",
            "git_sha": "unknown",
            "stats": {"posts":0,"photos":0,"videos":0,"audio":0,"members":0},
            "locales": []
        }
        """.data(using: .utf8)!

        struct SiteInfo: Decodable {
            let locales: [String]
        }

        let result = try JSONDecoder().decode(SiteInfo.self, from: serverJSON)
        #expect(result.locales.isEmpty)
    }
}
