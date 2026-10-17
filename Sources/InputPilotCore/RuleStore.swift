import Foundation

public final class RuleStore {
    public let fileURL: URL
    private var hasLoaded = false

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func defaultURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: false)
            .appendingPathComponent("InputPilot", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public func load() throws -> Configuration {
        hasLoaded = false
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            hasLoaded = true
            return .firstInstall
        }
        let configuration = try JSONDecoder().decode(Configuration.self, from: data)
        try configuration.validate()
        hasLoaded = true
        return configuration
    }

    public func save(_ configuration: Configuration) throws {
        guard hasLoaded else { throw RuleError.configurationNotLoaded }
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
