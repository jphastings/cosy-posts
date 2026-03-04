import Foundation

/// Generates nanoid strings using a lowercase alphanumeric alphabet.
enum Nanoid {
    /// The alphabet used for ID generation: 0-9, a-z.
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    /// Default nanoid length.
    static let defaultLength = 21

    /// Generate a nanoid string.
    /// - Parameter length: The length of the ID to generate (default: 21).
    /// - Returns: A random nanoid string.
    static func generate(length: Int = defaultLength) -> String {
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            let index = Int.random(in: 0..<alphabet.count)
            result.append(alphabet[index])
        }
        return result
    }
}
