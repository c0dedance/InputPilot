import Foundation

public struct InputSource: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Rule: Codable, Identifiable, Equatable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public var appName: String
    public var inputSourceID: String
    public var inputSourceName: String
    public var isEnabled: Bool

    public init(bundleID: String, appName: String, inputSourceID: String,
                inputSourceName: String, isEnabled: Bool) {
        self.bundleID = bundleID
        self.appName = appName
        self.inputSourceID = inputSourceID
        self.inputSourceName = inputSourceName
        self.isEnabled = isEnabled
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var rules: [Rule]
    public var isPaused: Bool
    public var defaultInputSource: InputSource?

    public init(rules: [Rule], isPaused: Bool, defaultInputSource: InputSource? = nil) {
        self.rules = rules
        self.isPaused = isPaused
        self.defaultInputSource = defaultInputSource
    }

    /// Only a genuinely missing file uses the first-install state.
    public static let firstInstall = Configuration(rules: [], isPaused: false)

    public func validate() throws {
        if let source = defaultInputSource {
            guard !source.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RuleError.invalidConfiguration("默认输入法的标识或名称为空。")
            }
        }
        var identifiers = Set<String>()
        for rule in rules {
            for value in [rule.bundleID, rule.appName, rule.inputSourceID, rule.inputSourceName] {
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RuleError.invalidConfiguration("规则存在空的应用或输入源标识／名称。")
                }
            }
            guard identifiers.insert(rule.bundleID).inserted else {
                throw RuleError.invalidConfiguration("应用规则重复：\(rule.bundleID)")
            }
        }
    }
}

public enum RuleError: Error, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case unavailableInputSource(String)
    case configurationNotLoaded

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "配置无效：\(reason)"
        case .unavailableInputSource(let id):
            return "指定的输入源不可用：\(id)。请在系统设置中启用它，或更改对应的输入法设置。"
        case .configurationNotLoaded:
            return "配置尚未成功读取；为保护原文件，已禁止保存。请修复配置后重新读取。"
        }
    }
}

public enum RuleTrigger: Sendable {
    case startup, applicationActivated, resumed
    case inputSourceChanged, enabledSourcesChanged
}

public enum RuleDecision: Equatable, Sendable {
    case keep
    case select(String)
}

public enum RuleEngine {
    /// frontmostBundleID must be a fresh snapshot, not the notification's stale payload.
    public static func decide(
        trigger: RuleTrigger, frontmostBundleID: String?, ownBundleID: String,
        configuration: Configuration, currentInputSourceID: String,
        availableInputSourceIDs: Set<String>
    ) throws -> RuleDecision {
        switch trigger {
        case .inputSourceChanged, .enabledSourcesChanged:
            return .keep // Observations never override a user's manual choice.
        case .startup, .applicationActivated, .resumed:
            break
        }
        guard !configuration.isPaused,
              let appID = frontmostBundleID, appID != ownBundleID else { return .keep }
        let targetID: String
        if let rule = configuration.rules.first(where: { $0.bundleID == appID }) {
            guard rule.isEnabled else { return .keep }
            targetID = rule.inputSourceID
        } else if let source = configuration.defaultInputSource {
            targetID = source.id
        } else {
            return .keep
        }
        guard availableInputSourceIDs.contains(targetID) else {
            throw RuleError.unavailableInputSource(targetID)
        }
        return targetID == currentInputSourceID ? .keep : .select(targetID)
    }
}
