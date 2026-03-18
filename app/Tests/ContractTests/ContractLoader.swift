import Foundation

/// Loads and parses contract JSON files from the monorepo's contracts/ directory.
enum ContractLoader {
    /// Load a contract JSON file by name (without .json extension).
    static func load(_ name: String) throws -> [String: Any] {
        let url = contractsDirectory.appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ContractError.invalidFormat("Expected top-level dictionary in \(name).json")
        }
        return json
    }

    /// Path to the contracts/ directory at the repo root.
    /// Resolved relative to this source file's location.
    private static var contractsDirectory: URL {
        // Tests/ContractTests/ContractLoader.swift → ../../contracts/
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent() // ContractTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // app/
            .appendingPathComponent("contracts")
    }
}

enum ContractError: Error, LocalizedError {
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return msg
        }
    }
}
