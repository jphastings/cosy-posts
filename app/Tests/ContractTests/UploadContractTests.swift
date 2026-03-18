import XCTest
import PactSwift
import Foundation

/// Consumer contract tests for uploading photos and publishing posts.
///
/// The upload flow uses the TUS resumable upload protocol:
/// 1. Create an upload resource (POST /files/) with metadata
/// 2. Send file data (PATCH /files/{id})
/// 3. Upload body text last to trigger post assembly
final class UploadContractTests: XCTestCase {
    static var mockService: MockService { SharedPact.mockService }

    // MARK: - Uploading a photo

    func testUserUploadsPhotoToPost() {
        // TUS metadata is base64-encoded: "key base64(value)" pairs joined by commas.
        let metadata = encodeTUSMetadata([
            "post-id": "abc123def456ghi789jkl",
            "filename": "media_0.jpg",
            "content-type": "image/jpeg",
            "author": "test@example.com",
        ])

        Self.mockService
            .uponReceiving("a user uploads a photo to their post")
            .given("the user is signed in with post access")
            .withRequest(
                method: .POST,
                path: "/files/",
                headers: [
                    "Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "Tus-Resumable": "1.0.0",
                    "Upload-Length": "1024",
                    "Upload-Metadata": Matcher.SomethingLike(metadata),
                ]
            )
            .willRespondWith(
                status: 201,
                headers: [
                    "Location": Matcher.RegexLike(
                        value: "http://localhost/files/upload123",
                        pattern: ".*\\/files\\/.*"
                    ),
                ]
            )
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("files/")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")
                request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
                request.setValue("1024", forHTTPHeaderField: "Upload-Length")
                request.setValue(metadata, forHTTPHeaderField: "Upload-Metadata")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 201)
                    XCTAssertNotNil(http.value(forHTTPHeaderField: "Location"))
                    done()
                }.resume()
            }
    }

    // MARK: - Sending upload data

    func testUserSendsPhotoData() {
        Self.mockService
            .uponReceiving("a user sends photo data to an existing upload")
            .given("an upload resource exists")
            .withRequest(
                method: .PATCH,
                path: "/files/upload123",
                headers: [
                    "Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "Tus-Resumable": "1.0.0",
                    "Upload-Offset": "0",
                    "Content-Type": "application/offset+octet-stream",
                ]
            )
            .willRespondWith(
                status: 204,
                headers: [
                    "Upload-Offset": Matcher.SomethingLike("1024"),
                ]
            )
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("files/upload123")
                var request = URLRequest(url: url)
                request.httpMethod = "PATCH"
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")
                request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
                request.setValue("0", forHTTPHeaderField: "Upload-Offset")
                request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data(repeating: 0xFF, count: 5)

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 204)
                    XCTAssertNotNil(http.value(forHTTPHeaderField: "Upload-Offset"))
                    done()
                }.resume()
            }
    }

    // MARK: - Publishing a post (body upload)

    func testUserPublishesPost() {
        let metadata = encodeTUSMetadata([
            "post-id": "abc123def456ghi789jkl",
            "filename": "body",
            "content-type": "text/plain",
            "role": "body",
            "date": "2026-03-18T12:34:56Z",
            "locale": "en",
            "content-ext": "md",
            "author": "test@example.com",
        ])

        Self.mockService
            .uponReceiving("a user publishes their post")
            .given("the user is signed in with post access")
            .withRequest(
                method: .POST,
                path: "/files/",
                headers: [
                    "Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "Tus-Resumable": "1.0.0",
                    "Upload-Length": "28",
                    "Upload-Metadata": Matcher.SomethingLike(metadata),
                ]
            )
            .willRespondWith(
                status: 201,
                headers: [
                    "Location": Matcher.RegexLike(
                        value: "http://localhost/files/upload456",
                        pattern: ".*\\/files\\/.*"
                    ),
                ]
            )
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("files/")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")
                request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
                request.setValue("28", forHTTPHeaderField: "Upload-Length")
                request.setValue(metadata, forHTTPHeaderField: "Upload-Metadata")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 201)
                    done()
                }.resume()
            }
    }

    // MARK: - Adding a translation

    func testUserAddsTranslationToPost() {
        let metadata = encodeTUSMetadata([
            "post-id": "abc123def456ghi789jkl",
            "filename": "body-es",
            "content-type": "text/plain",
            "role": "body-locale",
            "locale": "es",
            "content-ext": "md",
            "author": "test@example.com",
        ])

        Self.mockService
            .uponReceiving("a user adds a translation to their post")
            .given("the user is signed in with post access")
            .withRequest(
                method: .POST,
                path: "/files/",
                headers: [
                    "Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "Tus-Resumable": "1.0.0",
                    "Upload-Length": "20",
                    "Upload-Metadata": Matcher.SomethingLike(metadata),
                ]
            )
            .willRespondWith(
                status: 201,
                headers: [
                    "Location": Matcher.RegexLike(
                        value: "http://localhost/files/upload789",
                        pattern: ".*\\/files\\/.*"
                    ),
                ]
            )
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("files/")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")
                request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
                request.setValue("20", forHTTPHeaderField: "Upload-Length")
                request.setValue(metadata, forHTTPHeaderField: "Upload-Metadata")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 201)
                    done()
                }.resume()
            }
    }

    // MARK: - Checking upload progress (for resume)

    func testUserResumesInterruptedUpload() {
        Self.mockService
            .uponReceiving("a user checks upload progress to resume")
            .given("an upload resource exists with some data")
            .withRequest(
                method: .HEAD,
                path: "/files/upload123",
                headers: [
                    "Authorization": "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "Tus-Resumable": "1.0.0",
                ]
            )
            .willRespondWith(
                status: 200,
                headers: [
                    "Upload-Offset": Matcher.SomethingLike("512"),
                ]
            )
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("files/upload123")
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.setValue("Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", forHTTPHeaderField: "Authorization")
                request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 200)

                    let offset = http.value(forHTTPHeaderField: "Upload-Offset")
                    XCTAssertNotNil(offset)
                    XCTAssertNotNil(Int64(offset!))
                    done()
                }.resume()
            }
    }

    // MARK: - Viewer cannot upload

    func testViewerCannotUpload() {
        Self.mockService
            .uponReceiving("a viewer tries to upload content")
            .given("the user is signed in with view-only access")
            .withRequest(
                method: .POST,
                path: "/files/",
                headers: [
                    "Authorization": "Bearer bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    "Tus-Resumable": "1.0.0",
                    "Upload-Length": "100",
                ]
            )
            .willRespondWith(status: 403)
            .run { mockServiceURL, done in
                let url = mockServiceURL.appendingPathComponent("files/")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", forHTTPHeaderField: "Authorization")
                request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
                request.setValue("100", forHTTPHeaderField: "Upload-Length")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    let http = response as! HTTPURLResponse
                    XCTAssertEqual(http.statusCode, 403)
                    done()
                }.resume()
            }
    }

    // MARK: - Helpers

    /// Encode TUS metadata exactly as TUSClient does: "key base64(value)" pairs joined by commas.
    /// Keys are sorted for reproducible output (Swift dictionaries have non-deterministic ordering).
    private func encodeTUSMetadata(_ metadata: [String: String]) -> String {
        metadata.sorted { $0.key < $1.key }.map { key, value in
            let base64Value = Data(value.utf8).base64EncodedString()
            return "\(key) \(base64Value)"
        }.joined(separator: ",")
    }
}
