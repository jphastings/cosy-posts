import XCTest
import SwiftData
import os
@testable import CosyPostsAdmin

/// Thread-safe storage for recorded TUS requests.
///
/// URLSession calls `URLProtocol.startLoading()` on arbitrary threads,
/// so all shared state is protected by an unfair lock.
final class TUSRequestLog: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: State())

    struct State {
        var requests: [URLRequest] = []
        var uploadCounter = 0
        /// When non-nil, PATCH requests whose URL path contains this string return a 500.
        var failPatchContaining: String?
        /// When non-nil, requests matching this method will hang (never complete).
        var hangMethod: String?
    }

    func append(_ request: URLRequest) {
        lock.withLock { $0.requests.append(request) }
    }

    func nextUploadID() -> Int {
        lock.withLock {
            $0.uploadCounter += 1
            return $0.uploadCounter
        }
    }

    var requests: [URLRequest] {
        lock.withLock { $0.requests }
    }

    func reset() {
        lock.withLock {
            $0.requests = []
            $0.uploadCounter = 0
            $0.failPatchContaining = nil
            $0.hangMethod = nil
        }
    }

    var failPatchContaining: String? {
        get { lock.withLock { $0.failPatchContaining } }
        set { lock.withLock { $0.failPatchContaining = newValue } }
    }

    var hangMethod: String? {
        get { lock.withLock { $0.hangMethod } }
        set { lock.withLock { $0.hangMethod = newValue } }
    }

}

/// Singleton log shared between the test and the URLProtocol subclass.
let tusLog = TUSRequestLog()

/// Intercepts TUS HTTP requests, records them, and returns valid TUS responses.
final class TUSMockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        // Snapshot the body — URLSession may clear httpBody and provide a stream instead
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            recorded.httpBody = Self.readStream(stream)
        }
        tusLog.append(recorded)

        // Hang mode: never complete the request (simulates unresponsive server)
        if let hangMethod = tusLog.hangMethod, request.httpMethod == hangMethod {
            // Don't call any client methods — the request hangs until cancelled
            return
        }

        let response: HTTPURLResponse

        switch request.httpMethod {
        case "POST":
            // TUS creation → 201 with relative Location
            let uploadID = tusLog.nextUploadID()
            response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Location": "upload\(uploadID)"]
            )!

        case "PATCH":
            // Check if this PATCH should fail (for resume testing)
            if let failMatch = tusLog.failPatchContaining,
               request.url?.absoluteString.contains(failMatch) == true {
                response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
            } else {
                let bodySize = recorded.httpBody?.count ?? 0
                let currentOffset = Int(request.value(forHTTPHeaderField: "Upload-Offset") ?? "0") ?? 0
                response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 204,
                    httpVersion: nil,
                    headerFields: ["Upload-Offset": String(currentOffset + bodySize)]
                )!
            }

        case "HEAD":
            // TUS offset check → 200 with Upload-Offset: 0 (nothing uploaded yet)
            response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Upload-Offset": "0"]
            )!

        default:
            response = HTTPURLResponse(
                url: request.url!,
                statusCode: 405,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Read an entire input stream into Data.
    private static func readStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Tests

@MainActor
final class UploadFlowTests: XCTestCase {
    var session: URLSession!
    var modelContainer: ModelContainer!
    var networkMonitor: NetworkMonitor!
    var uploadManager: UploadManager!
    var tempDir: URL!

    override func setUp() async throws {
        tusLog.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TUSMockProtocol.self]
        session = URLSession(configuration: config)

        modelContainer = try ModelContainer(
            for: PendingPost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        networkMonitor = NetworkMonitor()
        networkMonitor.isConnected = true

        uploadManager = UploadManager(
            serverURL: URL(string: "https://example.com")!,
            networkMonitor: networkMonitor,
            modelContainer: modelContainer,
            session: session
        )

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Photo + text sends TUS create and upload for media then body

    func testPostWithPhotoSendsTUSRequests() async throws {
        let imageData = Data(repeating: 0xFF, count: 256)
        let imageURL = tempDir.appendingPathComponent("media_0.jpg")
        try imageData.write(to: imageURL)

        let context = ModelContext(modelContainer)
        let post = PendingPost(
            postID: "testpost123456789ab",
            date: Date(),
            bodyText: "Hello world!",
            locale: "en",
            mediaURLs: [imageURL]
        )
        context.insert(post)
        try context.save()

        await uploadManager.processQueue()

        let requests = tusLog.requests
        XCTAssertEqual(requests.count, 4, "Expected POST+PATCH for media, then POST+PATCH for body")

        // Media creation
        let mediaCreate = requests[0]
        XCTAssertEqual(mediaCreate.httpMethod, "POST")
        XCTAssertEqual(mediaCreate.value(forHTTPHeaderField: "Tus-Resumable"), "1.0.0")
        XCTAssertEqual(mediaCreate.value(forHTTPHeaderField: "Upload-Length"), "256")

        let mediaMeta = decodeTUSMetadata(mediaCreate.value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(mediaMeta["post-id"], "testpost123456789ab")
        XCTAssertEqual(mediaMeta["filename"], "media_0.jpg")
        XCTAssertEqual(mediaMeta["content-type"], "image/jpeg")

        // Media data
        let mediaPatch = requests[1]
        XCTAssertEqual(mediaPatch.httpMethod, "PATCH")
        XCTAssertEqual(mediaPatch.value(forHTTPHeaderField: "Content-Type"), "application/offset+octet-stream")
        XCTAssertEqual(mediaPatch.httpBody?.count, 256)

        // Body creation
        let bodyCreate = requests[2]
        XCTAssertEqual(bodyCreate.httpMethod, "POST")

        let bodyMeta = decodeTUSMetadata(bodyCreate.value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(bodyMeta["post-id"], "testpost123456789ab")
        XCTAssertEqual(bodyMeta["role"], "body")
        XCTAssertEqual(bodyMeta["content-ext"], "md")
        XCTAssertEqual(bodyMeta["locale"], "en")
        XCTAssertNotNil(bodyMeta["date"])

        // Body data
        let bodyPatch = requests[3]
        XCTAssertEqual(bodyPatch.httpMethod, "PATCH")
        XCTAssertEqual(String(data: bodyPatch.httpBody ?? Data(), encoding: .utf8), "Hello world!")

        // Post marked completed
        let fetched = try context.fetch(FetchDescriptor<PendingPost>()).first
        XCTAssertEqual(fetched?.postStatus, .completed)
    }

    // MARK: - Text-only post sends body upload only

    func testTextOnlyPostSendsBodyUpload() async throws {
        let context = ModelContext(modelContainer)
        let post = PendingPost(
            postID: "textonly12345678901",
            date: Date(),
            bodyText: "Just some thoughts.",
            locale: "en"
        )
        context.insert(post)
        try context.save()

        await uploadManager.processQueue()

        let requests = tusLog.requests
        XCTAssertEqual(requests.count, 2, "Expected POST+PATCH for body only")

        let bodyMeta = decodeTUSMetadata(requests[0].value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(bodyMeta["role"], "body")
        XCTAssertEqual(bodyMeta["post-id"], "textonly12345678901")

        XCTAssertEqual(String(data: requests[1].httpBody ?? Data(), encoding: .utf8), "Just some thoughts.")
    }

    // MARK: - Auth token on every request, author in metadata

    func testAuthTokenIncludedInRequests() async throws {
        await uploadManager.configure(
            serverURL: URL(string: "https://example.com")!,
            authToken: "test-session-token",
            email: "test@example.com"
        )

        let context = ModelContext(modelContainer)
        let post = PendingPost(
            postID: "authtest12345678901",
            date: Date(),
            bodyText: "Authenticated post",
            locale: "en"
        )
        context.insert(post)
        try context.save()

        await uploadManager.processQueue()

        let requests = tusLog.requests
        XCTAssertEqual(requests.count, 2) // POST + PATCH for body

        // Every request carries the Bearer token
        for (i, request) in requests.enumerated() {
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer test-session-token",
                "Request \(i) missing auth header"
            )
        }

        // POST creation carries author in metadata
        let bodyMeta = decodeTUSMetadata(requests[0].value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(bodyMeta["author"], "test@example.com")
    }

    // MARK: - Offline prevents uploads

    func testOfflineDoesNotUpload() async throws {
        networkMonitor.isConnected = false

        let context = ModelContext(modelContainer)
        let post = PendingPost(
            postID: "offline12345678901a",
            date: Date(),
            bodyText: "Will upload later",
            locale: "en"
        )
        context.insert(post)
        try context.save()

        await uploadManager.processQueue()

        XCTAssertTrue(tusLog.requests.isEmpty, "No requests should be sent when offline")

        let fetched = try context.fetch(FetchDescriptor<PendingPost>()).first
        XCTAssertEqual(fetched?.postStatus, .pending, "Post should remain pending when offline")
    }

    // MARK: - Locale bodies uploaded before primary body

    func testPostWithTranslationSendsLocaleBodyThenPrimaryBody() async throws {
        let context = ModelContext(modelContainer)
        let post = PendingPost(
            postID: "i18ntest1234567890a",
            date: Date(),
            bodyText: "Hello!",
            locale: "en",
            localeTexts: ["es": "¡Hola!"]
        )
        context.insert(post)
        try context.save()

        await uploadManager.processQueue()

        let requests = tusLog.requests
        XCTAssertEqual(requests.count, 4, "Expected POST+PATCH for locale body, then POST+PATCH for primary body")

        // Locale body first
        let localeMeta = decodeTUSMetadata(requests[0].value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(localeMeta["role"], "body-locale")
        XCTAssertEqual(localeMeta["locale"], "es")
        XCTAssertEqual(localeMeta["filename"], "body-es")
        XCTAssertEqual(String(data: requests[1].httpBody ?? Data(), encoding: .utf8), "¡Hola!")

        // Primary body last (triggers server assembly)
        let primaryMeta = decodeTUSMetadata(requests[2].value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(primaryMeta["role"], "body")
        XCTAssertEqual(primaryMeta["locale"], "en")
        XCTAssertEqual(String(data: requests[3].httpBody ?? Data(), encoding: .utf8), "Hello!")
    }

    // MARK: - Multiple media files uploaded in order before body

    func testMultipleMediaFilesUploadedInOrder() async throws {
        let photo1 = Data(repeating: 0xAA, count: 100)
        let photo2 = Data(repeating: 0xBB, count: 200)
        let url1 = tempDir.appendingPathComponent("media_0.png")
        let url2 = tempDir.appendingPathComponent("media_1.jpg")
        try photo1.write(to: url1)
        try photo2.write(to: url2)

        let context = ModelContext(modelContainer)
        let post = PendingPost(
            postID: "multi1234567890abcd",
            date: Date(),
            bodyText: "Two photos",
            locale: "en",
            mediaURLs: [url1, url2]
        )
        context.insert(post)
        try context.save()

        await uploadManager.processQueue()

        let requests = tusLog.requests
        XCTAssertEqual(requests.count, 6)

        // First media
        let meta0 = decodeTUSMetadata(requests[0].value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(meta0["filename"], "media_0.png")
        XCTAssertEqual(meta0["content-type"], "image/png")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Upload-Length"), "100")
        XCTAssertEqual(requests[1].httpBody?.count, 100)

        // Second media
        let meta1 = decodeTUSMetadata(requests[2].value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(meta1["filename"], "media_1.jpg")
        XCTAssertEqual(meta1["content-type"], "image/jpeg")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Upload-Length"), "200")
        XCTAssertEqual(requests[3].httpBody?.count, 200)

        // Body last
        let bodyMeta = decodeTUSMetadata(requests[4].value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(bodyMeta["role"], "body")
    }

    // MARK: - Resume skips already-uploaded media

    func testResumeSkipsAlreadyUploadedMedia() async throws {
        let photo1 = Data(repeating: 0xAA, count: 50)
        let photo2 = Data(repeating: 0xBB, count: 60)
        let url1 = tempDir.appendingPathComponent("media_0.jpg")
        let url2 = tempDir.appendingPathComponent("media_1.jpg")
        try photo1.write(to: url1)
        try photo2.write(to: url2)

        // Create a post that already has 1 of 2 media uploaded (simulating a resumed upload)
        let context = ModelContext(modelContainer)
        let post = PendingPost(
            postID: "resume1234567890abc",
            date: Date(),
            bodyText: "Resume test",
            locale: "en",
            mediaURLs: [url1, url2]
        )
        post.mediaUploaded = 1 // first media already uploaded
        context.insert(post)
        try context.save()

        await uploadManager.processQueue()

        let requests = tusLog.requests
        // Only second media (POST+PATCH) + body (POST+PATCH) = 4 requests
        XCTAssertEqual(requests.count, 4, "Should skip already-uploaded first media")

        // The first upload should be for the second media file
        let meta = decodeTUSMetadata(requests[0].value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(meta["filename"], "media_1.jpg")
        XCTAssertEqual(requests[1].httpBody?.count, 60)

        // Then body
        let bodyMeta = decodeTUSMetadata(requests[2].value(forHTTPHeaderField: "Upload-Metadata") ?? "")
        XCTAssertEqual(bodyMeta["role"], "body")

        let fetched = try context.fetch(FetchDescriptor<PendingPost>()).first
        XCTAssertEqual(fetched?.postStatus, .completed)
        XCTAssertEqual(fetched?.mediaUploaded, 2)
    }

    // MARK: - Server error marks post as failed

    func testUploadFailsOnServerError() async throws {
        tusLog.failPatchContaining = "upload"

        let context = ModelContext(modelContainer)
        let post = PendingPost(
            postID: "fail500123456789abc",
            date: Date(),
            bodyText: "This will fail",
            locale: "en"
        )
        context.insert(post)
        try context.save()

        await uploadManager.processQueue()

        let fetched = try context.fetch(FetchDescriptor<PendingPost>()).first
        XCTAssertEqual(fetched?.postStatus, .failed, "Post should be marked failed on server error")
        XCTAssertNotNil(fetched?.errorMessage, "Error message should be stored")
        XCTAssertFalse(uploadManager.isProcessing, "isProcessing should be false after queue completes")
    }

    // MARK: - Upload timeout completes instead of hanging

    func testUploadCompletesOnServerTimeout() async throws {
        // Use a session with a very short timeout
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TUSMockProtocol.self]
        config.timeoutIntervalForRequest = 1  // 1 second timeout
        let shortSession = URLSession(configuration: config)

        let shortUploadManager = UploadManager(
            serverURL: URL(string: "https://example.com")!,
            networkMonitor: networkMonitor,
            modelContainer: modelContainer,
            session: shortSession
        )

        // Make POST requests hang (simulates unreachable server)
        tusLog.hangMethod = "POST"

        let context = ModelContext(modelContainer)
        let post = PendingPost(
            postID: "timeout12345678901a",
            date: Date(),
            bodyText: "This will timeout",
            locale: "en"
        )
        context.insert(post)
        try context.save()

        let start = ContinuousClock.now
        await shortUploadManager.processQueue()
        let elapsed = ContinuousClock.now - start

        XCTAssertLessThan(elapsed, .seconds(10), "processQueue should complete within the timeout, not hang")
        XCTAssertFalse(shortUploadManager.isProcessing, "isProcessing should be false after queue completes")

        let fetched = try context.fetch(FetchDescriptor<PendingPost>()).first
        XCTAssertEqual(fetched?.postStatus, .failed, "Post should be marked failed on timeout")
    }

    // MARK: - withTimeout helper returns immediately on operation failure

    func testTimeoutReturnsImmediatelyOnOperationFailure() async throws {
        let start = ContinuousClock.now
        let result: Int? = await withTimeout(.seconds(60)) { return nil }
        let elapsed = ContinuousClock.now - start

        XCTAssertNil(result)
        XCTAssertLessThan(elapsed, .seconds(1), "Should return immediately when operation returns nil, not wait for 60s timeout")
    }

    // MARK: - withTimeout helper enforces deadline

    func testTimeoutEnforcesDeadline() async throws {
        let start = ContinuousClock.now
        let result: Int? = await withTimeout(.milliseconds(100)) {
            try? await Task.sleep(for: .seconds(60))
            return 42
        }
        let elapsed = ContinuousClock.now - start

        XCTAssertNil(result, "Should return nil when operation exceeds timeout")
        XCTAssertLessThan(elapsed, .seconds(2), "Should return near the timeout duration, not wait for the operation")
    }

    // MARK: - Helpers

    /// Decode TUS metadata header: "key base64(value),key2 base64(value2)"
    private func decodeTUSMetadata(_ header: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in header.split(separator: ",") {
            let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            if parts.count == 2,
               let data = Data(base64Encoded: String(parts[1]).trimmingCharacters(in: .whitespaces)),
               let value = String(data: data, encoding: .utf8) {
                result[String(parts[0]).trimmingCharacters(in: .whitespaces)] = value
            }
        }
        return result
    }
}
