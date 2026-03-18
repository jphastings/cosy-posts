import XCTest
import PactSwift

/// Consumer contract tests for viewing site information and stats.
final class SiteInfoContractTests: XCTestCase {
    static var mockService: MockService { SharedPact.mockService }

    // MARK: - Viewing site stats

    func testUserViewsSiteInformation() {
        Self.mockService
            .uponReceiving("a signed-in user views site information")
            .given("the site has content")
            .withRequest(
                method: .GET,
                path: "/api/info",
                headers: ["Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
            )
            .willRespondWith(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: [
                    "name": Matcher.SomethingLike("My Cosy Site"),
                    "version": Matcher.SomethingLike("1.0.0"),
                    "git_sha": Matcher.SomethingLike("abc1234"),
                    "stats": [
                        "posts": Matcher.IntegerLike(10),
                        "photos": Matcher.IntegerLike(50),
                        "videos": Matcher.IntegerLike(5),
                        "audio": Matcher.IntegerLike(2),
                        "members": Matcher.IntegerLike(3),
                    ],
                    "locales": Matcher.EachLike("en", min: 0),
                ]
            )

        Self.mockService.run { baseURL, done in
                let mockServiceURL = URL(string: baseURL)!
                // Reproduce how SiteInfoLoader.load() works.
                let url = mockServiceURL.appendingPathComponent("api/info")
                var request = URLRequest(url: url)
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 200)

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

                    let info = try! JSONDecoder().decode(SiteInfo.self, from: data!)
                    XCTAssertFalse(info.name.isEmpty)
                    done()
                }.resume()
            }
    }
}
