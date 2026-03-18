import PactSwift

/// Single shared MockService instance used by all contract test classes.
///
/// PactSwift's MockService manages an underlying pact handle keyed by
/// consumer-provider pair. Having multiple MockService instances with the
/// same pair can cause race conditions during pact file finalization.
/// Sharing one instance eliminates that risk.
enum SharedPact {
    static let mockService = MockService(
        consumer: "CosyPostsApp",
        provider: "CosyPostsAPI"
    )
}
