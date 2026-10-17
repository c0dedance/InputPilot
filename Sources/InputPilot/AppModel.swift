import AppKit
import Carbon
import Combine
import InputPilotCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var configuration: Configuration?
    @Published private(set) var sources: [InputSource] = []
    @Published private(set) var currentSource: InputSource?
    @Published private(set) var configurationError: String?
    @Published private(set) var operationError: String?
    @Published private(set) var ruleError: String?
    @Published private var sourceListError: String?
    @Published private var currentSourceError: String?

    let login = LoginItemService()
    let ownBundleID: String
    private let input: any InputSourceAccess
    private let frontmostBundleID: @MainActor () -> String?
    private var store: RuleStore?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lastApplicationPID: pid_t?

    init() {
        guard let id = Bundle.main.bundleIdentifier else {
            fatalError("请通过 scripts/run.sh 启动打包的自动切换输入法.app，而不是 swift run。")
        }
        ownBundleID = id
        input = InputSourceService()
        frontmostBundleID = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        reloadConfiguration()
        refreshSources()
        refreshCurrentSource()
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) {
            $0.handleActivation()
        }
        observe(DistributedNotificationCenter.default(),
                Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)) {
            $0.refreshCurrentSource()
        }
        observe(DistributedNotificationCenter.default(),
                Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)) {
            $0.refreshSources()
            $0.refreshCurrentSource()
        }
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification) { $0.login.refresh() }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { $0.stopObserving() }
        lastApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        applyRule(trigger: .startup)
    }

    // External I/O is supplied explicitly for tests; this initializer installs no system observers.
    init(input: any InputSourceAccess, store: RuleStore, ownBundleID: String,
         frontmostBundleID: @escaping @MainActor () -> String?) {
        self.input = input
        self.store = store
        self.ownBundleID = ownBundleID
        self.frontmostBundleID = frontmostBundleID
        reloadConfiguration()
        refreshSources()
        refreshCurrentSource()
    }

    var menuTitle: String {
        let name: String
        if let currentSource { name = currentSource.name } else { name = "输入源未知" }
        if let configuration, configuration.isPaused { return "暂停 · \(name)" }
        return name
    }

    var inputError: String? {
        let errors = [sourceListError, currentSourceError].compactMap { $0 }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    var hasError: Bool {
        configurationError != nil || operationError != nil || inputError != nil || ruleError != nil
    }

    func reloadConfiguration() {
        do {
            if store == nil { store = RuleStore(fileURL: try RuleStore.defaultURL()) }
            guard let store else { preconditionFailure("RuleStore was not created") }
            configuration = try store.load()
            configurationError = nil
            operationError = nil
        } catch {
            configuration = nil
            configurationError = "读取配置失败：\(error.localizedDescription) 原文件未被覆盖；请修复后点击“重新读取配置”。"
        }
    }

    func revealConfiguration() {
        guard let store else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: store.fileURL.deletingLastPathComponent().path)
    }

    func setPaused(_ paused: Bool) {
        guard var next = configuration else { return }
        next.isPaused = paused
        guard commit(next) else { return }
        if !paused { applyRule(trigger: .resumed) }
    }

    @discardableResult
    func saveRule(_ rule: Rule) -> Bool {
        guard var next = configuration else { return false }
        if let index = next.rules.firstIndex(where: { $0.id == rule.id }) {
            next.rules[index] = rule
        } else {
            next.rules.append(rule)
        }
        next.rules.sort { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
        return commit(next)
    }

    func setRuleEnabled(_ rule: Rule, _ enabled: Bool) {
        var next = rule
        next.isEnabled = enabled
        saveRule(next)
    }

    func setDefaultInputSource(_ sourceID: String?) {
        guard var next = configuration else { return }
        if let sourceID {
            guard let source = sources.first(where: { $0.id == sourceID }) else {
                operationError = "无法保存：默认输入法 \(sourceID) 已不可用，请刷新输入源后重新选择。"
                return
            }
            next.defaultInputSource = source
        } else {
            next.defaultInputSource = nil
        }
        commit(next)
    }

    func setRuleInputSource(_ rule: Rule, _ sourceID: String) {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            operationError = "无法保存：输入源 \(sourceID) 已不可用，请刷新输入源后重新选择。当前规则未改变。"
            return
        }
        var next = rule
        next.inputSourceID = source.id
        next.inputSourceName = source.name
        saveRule(next)
    }

    @discardableResult
    func deleteRule(_ rule: Rule) -> Bool {
        guard var next = configuration else { return false }
        next.rules.removeAll { $0.id == rule.id }
        return commit(next)
    }

    func refreshSources() {
        do {
            sources = try input.availableSources()
            sourceListError = nil
        } catch {
            sources = []
            sourceListError = error.localizedDescription
        }
    }

    private func refreshCurrentSource() {
        do {
            let current = try input.currentSource()
            currentSource = current
            currentSourceError = nil
        } catch {
            currentSource = nil
            currentSourceError = error.localizedDescription
        }
    }

    private func handleActivation() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard pid != lastApplicationPID else { return }
        lastApplicationPID = pid
        applyRule(trigger: .applicationActivated)
    }

    func applyRule(trigger: RuleTrigger) {
        guard let configuration else { return }
        ruleError = nil
        refreshCurrentSource()
        guard let current = currentSource else { return }
        do {
            let decision = try RuleEngine.decide(
                trigger: trigger, frontmostBundleID: frontmostBundleID(),
                ownBundleID: ownBundleID, configuration: configuration,
                currentInputSourceID: current.id, availableInputSourceIDs: Set(sources.map(\.id))
            )
            if case .select(let id) = decision {
                try input.select(id: id)
                refreshCurrentSource() // Show what the system reports, not what was requested.
            }
        } catch {
            ruleError = error.localizedDescription
        }
    }

    @discardableResult
    private func commit(_ next: Configuration) -> Bool {
        guard let store else { preconditionFailure("Cannot save without a RuleStore") }
        do {
            try store.save(next)
            configuration = next // Update UI only after durable write succeeds.
            operationError = nil
            return true
        } catch {
            operationError = "保存失败：\(error.localizedDescription) 当前规则未改变。"
            return false
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (AppModel) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            // The queue contract is main; do not queue a second, potentially stale activation task.
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
        observers.append((center, token))
    }

    private func stopObserving() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}
