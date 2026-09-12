import Foundation

/// Where the ledger lives on disk. Shared with the widget through the App
/// Group container; falls back to Application Support when the entitlement
/// isn't present (unit tests, a build without the group).
enum LedgerFile {
    static let appGroup = "group.me.colinwatson.beerdebt"
    static let fileName = "ledger.json"

    static var sharedDirectory: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BeerDebt", isDirectory: true)
    }

    /// The pre-widget location, migrated from on first launch.
    static var legacyDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeerDebt", isDirectory: true)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Reads the ledger, or nil if there isn't one (or it can't be parsed).
    static func load(from directory: URL = sharedDirectory) -> Ledger? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? decoder.decode(Ledger.self, from: data)
    }
}
