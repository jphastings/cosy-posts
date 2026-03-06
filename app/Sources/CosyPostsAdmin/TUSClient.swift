import Foundation
import os

private let tusLog = Logger(subsystem: "com.cosyposts", category: "TUS")

/// TUS (tus.io) resumable upload client.
///
/// Implements the core TUS protocol:
/// 1. Creation: POST to create an upload resource with metadata
/// 2. Upload: PATCH to send file data with offset-based resume
actor TUSClient {
    private let endpoint: URL
    private let session: URLSession
    private var authToken: String?

    /// Initialize the TUS client.
    /// - Parameters:
    ///   - endpoint: The TUS upload endpoint URL (e.g., https://example.com/files/).
    ///   - session: URLSession to use for requests.
    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    /// Set the Bearer auth token for authenticated requests.
    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    /// Apply auth header to a request if a token is set.
    private func applyAuth(to request: inout URLRequest) {
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Create a new upload on the server.
    /// - Parameters:
    ///   - size: Total size of the file in bytes.
    ///   - metadata: Key-value metadata pairs to attach to the upload.
    /// - Returns: The upload URL returned by the server.
    func create(size: Int64, metadata: [String: String]) async throws -> URL {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(size), forHTTPHeaderField: "Upload-Length")

        if !metadata.isEmpty {
            let encoded = metadata.map { key, value in
                let base64Value = Data(value.utf8).base64EncodedString()
                return "\(key) \(base64Value)"
            }.joined(separator: ",")
            request.setValue(encoded, forHTTPHeaderField: "Upload-Metadata")
        }

        applyAuth(to: &request)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TUSError.invalidResponse
        }

        guard httpResponse.statusCode == 201 else {
            throw TUSError.serverError(statusCode: httpResponse.statusCode)
        }

        guard let location = httpResponse.value(forHTTPHeaderField: "Location") else {
            throw TUSError.missingLocation
        }

        // Location may be relative or absolute
        guard let uploadURL = URL(string: location, relativeTo: endpoint) else {
            throw TUSError.invalidLocation(location)
        }

        tusLog.info("Created upload: Location=\(location) resolved=\(uploadURL.absoluteString)")
        return uploadURL
    }

    /// Query the server for the current offset of an upload.
    /// - Parameter uploadURL: The upload resource URL.
    /// - Returns: The current byte offset on the server.
    func getOffset(uploadURL: URL) async throws -> Int64 {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "HEAD"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        applyAuth(to: &request)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TUSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw TUSError.serverError(statusCode: httpResponse.statusCode)
        }

        guard let offsetString = httpResponse.value(forHTTPHeaderField: "Upload-Offset"),
              let offset = Int64(offsetString) else {
            throw TUSError.missingOffset
        }

        return offset
    }

    /// Upload file data to the server, resuming from the given offset.
    /// - Parameters:
    ///   - uploadURL: The upload resource URL.
    ///   - data: The complete file data.
    ///   - offset: The byte offset to resume from.
    /// - Returns: The new offset after the upload completes.
    func upload(uploadURL: URL, data: Data, offset: Int64 = 0) async throws -> Int64 {
        let chunk = data.suffix(from: Int(offset))
        tusLog.info("PATCH \(uploadURL.absoluteString) offset=\(offset) size=\(chunk.count)")

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = chunk
        applyAuth(to: &request)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TUSError.invalidResponse
        }

        guard httpResponse.statusCode == 204 else {
            throw TUSError.serverError(statusCode: httpResponse.statusCode)
        }

        guard let newOffsetString = httpResponse.value(forHTTPHeaderField: "Upload-Offset"),
              let newOffset = Int64(newOffsetString) else {
            throw TUSError.missingOffset
        }

        return newOffset
    }

    /// Upload a complete file with automatic resume support.
    /// - Parameters:
    ///   - data: The file data.
    ///   - metadata: Key-value metadata pairs.
    ///   - existingURL: An optional existing upload URL to resume.
    /// - Returns: The upload URL.
    func uploadFile(data: Data, metadata: [String: String], existingURL: URL? = nil) async throws -> URL {
        let uploadURL: URL
        var offset: Int64 = 0

        if let existing = existingURL {
            // Try to resume
            uploadURL = existing
            offset = try await getOffset(uploadURL: existing)
        } else {
            uploadURL = try await create(size: Int64(data.count), metadata: metadata)
        }

        if offset < Int64(data.count) {
            _ = try await upload(uploadURL: uploadURL, data: data, offset: offset)
        }

        return uploadURL
    }
}

/// Errors that can occur during TUS operations.
enum TUSError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case missingLocation
    case invalidLocation(String)
    case missingOffset

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: HTTP \(code)"
        case .missingLocation:
            return "Server did not return upload location"
        case .invalidLocation(let location):
            return "Invalid upload location: \(location)"
        case .missingOffset:
            return "Server did not return upload offset"
        }
    }
}
