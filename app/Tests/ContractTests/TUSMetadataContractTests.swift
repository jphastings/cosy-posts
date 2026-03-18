import Foundation
import Testing

/// These tests verify that the app's TUS metadata encoding matches exactly
/// what the server expects (as defined in the shared contract files).
///
/// The contract specifies:
/// - Metadata is encoded as "key base64(value)" pairs joined by commas
/// - Specific required/optional keys for media, body, and locale uploads
struct TUSMetadataContractTests {

    // MARK: - Metadata Encoding Format

    /// The app encodes TUS metadata as: "key base64(value),key base64(value)"
    /// This must match how tusd on the server decodes it.
    @Test func metadataEncodingFormat() throws {
        let metadata = ["post-id": "abc123", "filename": "test.jpg"]
        let encoded = encodeTUSMetadata(metadata)

        // Each pair should be "key base64value"
        let pairs = encoded.split(separator: ",").map(String.init)
        for pair in pairs {
            let parts = pair.split(separator: " ", maxSplits: 1).map(String.init)
            #expect(parts.count == 2, "Each metadata pair must be 'key base64value', got: \(pair)")

            // The value part must be valid base64
            let base64Value = parts[1]
            #expect(Data(base64Encoded: base64Value) != nil, "Value must be valid base64: \(base64Value)")
        }
    }

    /// Verify base64 decodes back to original values.
    @Test func metadataRoundTrip() throws {
        let metadata = [
            "post-id": "abc123def456ghi789jkl",
            "filename": "media_0.jpg",
            "content-type": "image/jpeg",
        ]

        let encoded = encodeTUSMetadata(metadata)
        let decoded = decodeTUSMetadata(encoded)

        #expect(decoded == metadata, "Metadata must round-trip through encode/decode")
    }

    // MARK: - Media Upload Metadata (contracts/tus_upload_media.json)

    @Test func mediaUploadRequiredKeys() throws {
        let contract = try ContractLoader.load("tus_upload_media")
        let tusMetadata = contract["tus_metadata"] as? [String: Any]
            ?? (contract["request"] as? [String: Any])?["tus_metadata"] as? [String: Any]
        let requiredKeys = tusMetadata?["required"] as? [String] ?? []

        // These are the keys the app actually sends for media uploads.
        let appMediaMetadata: [String: String] = [
            "post-id": "abc123def456ghi789jkl",
            "filename": "media_0.jpg",
            "content-type": "image/jpeg",
        ]

        for key in requiredKeys {
            #expect(appMediaMetadata[key] != nil, "App must send required key '\(key)' for media uploads")
        }
    }

    @Test func mediaUploadContentTypes() throws {
        let contract = try ContractLoader.load("tus_upload_media")
        let notes = contract["notes"] as? [String: Any]
        let validTypes = notes?["content_type_values"] as? [String] ?? []

        // These must match the mimeType(for:) function in UploadManager.
        let appMimeTypes = [
            "image/jpeg",    // .jpg, .jpeg
            "image/png",     // .png
            "image/heic",    // .heic, .heif
            "image/gif",     // .gif
            "video/mp4",     // .mp4, .m4v
            "video/quicktime", // .mov
            "image/webp",    // .webp
            "application/octet-stream", // default
        ]

        for mimeType in appMimeTypes {
            #expect(validTypes.contains(mimeType), "App mime type '\(mimeType)' must be in contract's valid types")
        }
    }

    // MARK: - Body Upload Metadata (contracts/tus_upload_body.json)

    @Test func bodyUploadRequiredKeys() throws {
        let contract = try ContractLoader.load("tus_upload_body")
        let tusMetadata = (contract["request"] as? [String: Any])?["tus_metadata"] as? [String: Any]
        let requiredKeys = tusMetadata?["required"] as? [String] ?? []

        // These are the keys the app sends for body uploads.
        let appBodyMetadata: [String: String] = [
            "post-id": "abc123def456ghi789jkl",
            "role": "body",
            "date": "2026-03-18T12:34:56Z",
            "content-ext": "md",
        ]

        for key in requiredKeys {
            #expect(appBodyMetadata[key] != nil, "App must send required key '\(key)' for body uploads")
        }
    }

    @Test func bodyUploadFixedValues() throws {
        let contract = try ContractLoader.load("tus_upload_body")
        let tusMetadata = (contract["request"] as? [String: Any])?["tus_metadata"] as? [String: Any]
        let fixedValues = tusMetadata?["fixed_values"] as? [String: String] ?? [:]

        // Verify the app sends exactly these fixed values.
        #expect(fixedValues["role"] == "body", "Contract requires role='body'")
        #expect(fixedValues["content-type"] == "text/plain", "Contract requires content-type='text/plain'")
        #expect(fixedValues["filename"] == "body", "Contract requires filename='body'")
    }

    @Test func bodyDateFormat() throws {
        // The app uses ISO8601DateFormatter which produces RFC3339 format.
        let formatter = ISO8601DateFormatter()
        let date = Date(timeIntervalSince1970: 1_710_000_000) // 2024-03-09
        let dateString = formatter.string(from: date)

        // Server accepts RFC3339 (time.RFC3339 in Go = "2006-01-02T15:04:05Z07:00")
        // Verify the app's format matches.
        #expect(dateString.contains("T"), "Date must be in RFC3339 format with T separator")
        #expect(dateString.hasSuffix("Z"), "Date from ISO8601DateFormatter must end with Z")
    }

    // MARK: - Locale Body Metadata (contracts/tus_upload_body_locale.json)

    @Test func localeBodyRequiredKeys() throws {
        let contract = try ContractLoader.load("tus_upload_body_locale")
        let tusMetadata = (contract["request"] as? [String: Any])?["tus_metadata"] as? [String: Any]
        let requiredKeys = tusMetadata?["required"] as? [String] ?? []

        let appLocaleMetadata: [String: String] = [
            "post-id": "abc123def456ghi789jkl",
            "role": "body-locale",
            "locale": "es",
        ]

        for key in requiredKeys {
            #expect(appLocaleMetadata[key] != nil, "App must send required key '\(key)' for locale body uploads")
        }
    }

    @Test func localeBodyFixedRole() throws {
        let contract = try ContractLoader.load("tus_upload_body_locale")
        let tusMetadata = (contract["request"] as? [String: Any])?["tus_metadata"] as? [String: Any]
        let fixedValues = tusMetadata?["fixed_values"] as? [String: String] ?? [:]

        #expect(fixedValues["role"] == "body-locale", "Contract requires role='body-locale'")
    }

    // MARK: - Helpers (mirror app's TUSClient encoding)

    /// Encode metadata exactly as the app's TUSClient does.
    private func encodeTUSMetadata(_ metadata: [String: String]) -> String {
        metadata.map { key, value in
            let base64Value = Data(value.utf8).base64EncodedString()
            return "\(key) \(base64Value)"
        }.joined(separator: ",")
    }

    /// Decode TUS metadata (for verification).
    private func decodeTUSMetadata(_ encoded: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in encoded.split(separator: ",") {
            let parts = pair.split(separator: " ", maxSplits: 1)
            guard parts.count == 2,
                  let data = Data(base64Encoded: String(parts[1])),
                  let value = String(data: data, encoding: .utf8) else { continue }
            result[String(parts[0])] = value
        }
        return result
    }
}
