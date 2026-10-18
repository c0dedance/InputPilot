import AppKit
import Foundation
import InputPilotCore
import XCTest
@testable import InputPilot

final class RuleTests: XCTestCase {
    private let editor = Rule(bundleID: "test.editor", appName: "Editor", inputSourceID: "source.en",
                              inputSourceName: "English", isEnabled: true)
    private let ownID = "local.inputpilot.app"

    private func decide(_ config: Configuration, app: String? = "test.editor",
                        current: String = "source.zh", sources: Set<String> = ["source.en", "source.zh"],
                        trigger: RuleTrigger = .applicationActivated) throws -> RuleDecision {
        try RuleEngine.decide(trigger: trigger, frontmostBundleID: app, ownBundleID: ownID,
                              configuration: config, currentInputSourceID: current,
                              availableInputSourceIDs: sources)
    }

    func testEntryStartupAndResumeApplyMatchingRule() throws {
        let config = Configuration(rules: [editor], isPaused: false)
        for trigger: RuleTrigger in [.applicationActivated, .startup, .resumed] {
            XCTAssertEqual(try decide(config, trigger: trigger), .select("source.en"))
        }
    }

    func testNoRuleNoForegroundAndOwnApplicationKeepCurrentSource() throws {
        XCTAssertEqual(try decide(.firstInstall), .keep)
        let config = Configuration(rules: [editor], isPaused: false)
        XCTAssertEqual(try decide(config, app: "test.unknown"), .keep)
        XCTAssertEqual(try decide(config, app: nil), .keep)
        let ownRule = Rule(bundleID: ownID, appName: "InputPilot", inputSourceID: "source.en",
                       inputSourceName: "English", isEnabled: true)
        XCTAssertEqual(try decide(Configuration(rules: [ownRule], isPaused: false), app: ownID), .keep)
    }

    func testPausedAndDisabledRulesNeverSelectEvenWhenTargetIsMissing() throws {
        XCTAssertEqual(try decide(Configuration(rules: [editor], isPaused: true), sources: []), .keep)
        var disabled = editor
        disabled.isEnabled = false
        XCTAssertEqual(try decide(Configuration(rules: [disabled], isPaused: false), sources: []), .keep)
    }

    func testAlreadySelectedSourceIsNotSelectedAgain() throws {
        XCTAssertEqual(try decide(Configuration(rules: [editor], isPaused: false), current: "source.en"), .keep)
    }

    func testDefaultSourceAppliesOnlyWithoutAnApplicationRule() throws {
        var config = Configuration(rules: [editor], isPaused: false,
                                   defaultInputSource: InputSource(id: "source.zh", name: "中文"))
        XCTAssertEqual(try decide(config, app: "test.other", current: "source.en"), .select("source.zh"))
        XCTAssertEqual(try decide(config, app: "test.other"), .keep)
        XCTAssertEqual(try decide(config), .select("source.en"))
        XCTAssertEqual(try decide(config, app: nil), .keep)
        XCTAssertEqual(try decide(config, app: ownID), .keep)
        XCTAssertEqual(try decide(config, app: "test.other", current: "source.en",
                                  trigger: .inputSourceChanged), .keep)
        config.rules[0].isEnabled = false
        XCTAssertEqual(try decide(config, current: "source.en"), .keep)
        config.isPaused = true
        XCTAssertEqual(try decide(config, app: "test.other", current: "source.en"), .keep)
    }

    func testUnavailableDefaultFailsAndInvalidDefaultIsRejected() throws {
        var config = Configuration(rules: [], isPaused: false,
                                   defaultInputSource: InputSource(id: "missing", name: "Missing"))
        XCTAssertThrowsError(try decide(config)) {
            XCTAssertEqual($0 as? RuleError, .unavailableInputSource("missing"))
        }
        config.defaultInputSource = InputSource(id: " ", name: "Invalid")
        XCTAssertThrowsError(try config.validate())
    }

    func testMissingTargetFailsWithoutChoosingAnotherSource() {
        XCTAssertThrowsError(try decide(Configuration(rules: [editor], isPaused: false), sources: ["source.zh"])) {
            XCTAssertEqual($0 as? RuleError, .unavailableInputSource("source.en"))
        }
    }

    func testManualSelectionIsPreservedUntilAnotherEntry() throws {
        let config = Configuration(rules: [editor], isPaused: false)
        XCTAssertEqual(try decide(config), .select("source.en"))
        XCTAssertEqual(try decide(config, current: "source.en", trigger: .inputSourceChanged), .keep)
        // The user selects Chinese while remaining in Editor.
        XCTAssertEqual(try decide(config, current: "source.zh", trigger: .inputSourceChanged), .keep)
        XCTAssertEqual(try decide(config, sources: [], trigger: .enabledSourcesChanged), .keep)
        XCTAssertEqual(try decide(config, app: "test.other"), .keep)
        XCTAssertEqual(try decide(config), .select("source.en"))
    }

    func testDecisionUsesTheSuppliedCurrentForegroundNotAnEarlierApp() throws {
        let chat = Rule(bundleID: "test.chat", appName: "Chat", inputSourceID: "source.zh",
                        inputSourceName: "Chinese", isEnabled: true)
        let config = Configuration(rules: [editor, chat], isPaused: false)
        XCTAssertEqual(try decide(config, app: editor.bundleID, current: "source.other"), .select("source.en"))
        XCTAssertEqual(try decide(config, app: chat.bundleID, current: "source.other"), .select("source.zh"))
    }

    func testDuplicateAppsAndEmptyRequiredValuesAreRejected() {
        XCTAssertThrowsError(try Configuration(rules: [editor, editor], isPaused: false).validate())
        var invalid = editor
        invalid.inputSourceID = " \n "
        XCTAssertThrowsError(try Configuration(rules: [invalid], isPaused: false).validate())
    }
}

final class RuleStoreTests: XCTestCase {
    private var directory: URL!
    private var settings: URL { directory.appendingPathComponent("InputPilot/settings.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("InputPilotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testMissingFileIsEmptyWithoutCreatingAFile() throws {
        XCTAssertEqual(try RuleStore(fileURL: settings).load(), .firstInstall)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settings.path))
    }

    func testRulesPauseAndDisabledStateSurviveSavingAndReloading() throws {
        let store = RuleStore(fileURL: settings)
        _ = try store.load()
        let config = Configuration(rules: [
            Rule(bundleID: "test.app", appName: "中文应用", inputSourceID: "source.zh",
                 inputSourceName: "简体拼音", isEnabled: false)
        ], isPaused: true, defaultInputSource: InputSource(id: "source.en", name: "English"))
        try store.save(config)
        XCTAssertEqual(try RuleStore(fileURL: settings).load(), config)
        try store.save(.firstInstall)
        XCTAssertEqual(try RuleStore(fileURL: settings).load(), .firstInstall)
    }

    func testCorruptOrIncompleteConfigurationCannotBeOverwritten() throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        for text in ["{not-json", "{}", #"{"rules": [], "isPaused": "false"}"#] {
            let original = Data(text.utf8)
            try original.write(to: settings)
            let store = RuleStore(fileURL: settings)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(.firstInstall)) {
                XCTAssertEqual($0 as? RuleError, .configurationNotLoaded)
            }
            XCTAssertEqual(try Data(contentsOf: settings), original)
        }
    }

    func testFailedReloadRevokesPreviousPermissionToSave() throws {
        let store = RuleStore(fileURL: settings)
        _ = try store.load()
        try store.save(.firstInstall)
        let damaged = Data("broken".utf8)
        try damaged.write(to: settings)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(.firstInstall))
        XCTAssertEqual(try Data(contentsOf: settings), damaged)
    }

    func testSaveBeforeLoadIsRejected() {
        XCTAssertThrowsError(try RuleStore(fileURL: settings).save(.firstInstall)) {
            XCTAssertEqual($0 as? RuleError, .configurationNotLoaded)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: settings.path))
    }

    func testActualFilesystemReadAndWriteFailuresAreNotHidden() throws {
        let directoryStore = RuleStore(fileURL: directory)
        XCTAssertThrowsError(try directoryStore.load())
        let store = RuleStore(fileURL: settings)
        _ = try store.load()
        // A regular file where the settings directory belongs makes saving impossible.
        let blocker = Data("not a directory".utf8)
        try blocker.write(to: settings.deletingLastPathComponent())
        XCTAssertThrowsError(try store.save(.firstInstall))
        XCTAssertEqual(try Data(contentsOf: settings.deletingLastPathComponent()), blocker)
    }

    func testInvalidSavePreservesPreviouslyValidConfiguration() throws {
        let store = RuleStore(fileURL: settings)
        _ = try store.load()
        try store.save(.firstInstall)
        let invalid = Rule(bundleID: "", appName: "App", inputSourceID: "source.en",
                           inputSourceName: "English", isEnabled: true)
        XCTAssertThrowsError(try store.save(Configuration(rules: [invalid], isPaused: false)))
        XCTAssertEqual(try RuleStore(fileURL: settings).load(), .firstInstall)
    }
}

@MainActor
private final class TestInputSourceAccess: InputSourceAccess {
    let english = InputSource(id: "source.en", name: "English")
    let chinese = InputSource(id: "source.zh", name: "Chinese")
    var available: [InputSource] = []
    var current = InputSource(id: "source.zh", name: "Chinese")
    var readError: Error?
    var selectionError: Error?
    var selected: [String] = []
    var foreground: String? = "test.editor"

    func availableSources() throws -> [InputSource] { available }
    func currentSource() throws -> InputSource {
        if let readError { throw readError }
        return current
    }
    func select(id: String) throws {
        if let selectionError { throw selectionError }
        guard let source = available.first(where: { $0.id == id }) else {
            throw RuleError.unavailableInputSource(id)
        }
        selected.append(id)
        current = source
    }
}

final class AppModelTests: XCTestCase {
    @MainActor
    func testReopenBeforeSettingsHaveEverAppearedShowsAWindow() throws {
        let app = NSApplication.shared
        let input = TestInputSourceAccess()
        input.available = [input.english, input.chinese]
        let (model, _) = try makeModel(input)
        let delegate = PilotAppDelegate(model: model)
        XCTAssertFalse(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false))
        let settings = app.windows.filter { $0.title == "自动切换输入法设置" && $0.isVisible }
        XCTAssertEqual(settings.count, 1)
        let window = try XCTUnwrap(settings.first)
        defer { window.close() }
        window.close()
        XCTAssertFalse(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false))
        XCTAssertTrue(window.isVisible)
        delegate.showSettings()
        XCTAssertEqual(app.windows.filter { $0.title == window.title && $0.isVisible }.count, 1)
        XCTAssertTrue(input.selected.isEmpty)
    }

    @MainActor
    func testDefaultSelectionPersistsWithoutSwitchingAndRejectsUnavailableSource() throws {
        let input = TestInputSourceAccess()
        input.available = [input.english, input.chinese]
        let (model, url) = try makeModel(input, foreground: { "test.other" })
        model.setDefaultInputSource(input.english.id)
        XCTAssertEqual(try RuleStore(fileURL: url).load().defaultInputSource, input.english)
        XCTAssertTrue(input.selected.isEmpty)
        model.setDefaultInputSource("missing")
        XCTAssertNotNil(model.operationError)
        XCTAssertEqual(model.configuration?.defaultInputSource, input.english)
        model.applyRule(trigger: .applicationActivated)
        XCTAssertEqual(input.current, input.english)
        model.setDefaultInputSource(nil)
        XCTAssertNil(try RuleStore(fileURL: url).load().defaultInputSource)
    }

    @MainActor
    func testDefaultSaveFailurePreservesPreviousSelection() throws {
        let input = TestInputSourceAccess()
        input.available = [input.english, input.chinese]
        let (model, url) = try makeModel(input)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        model.setDefaultInputSource(input.english.id)
        XCTAssertNil(model.configuration?.defaultInputSource)
        XCTAssertNotNil(model.operationError)
    }

    @MainActor
    private func makeModel(_ input: TestInputSourceAccess,
                           foreground: @escaping @MainActor () -> String? = { "test.editor" }) throws -> (AppModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InputPilotModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let store = RuleStore(fileURL: url)
        _ = try store.load()
        try store.save(Configuration(rules: [
            Rule(bundleID: "test.editor", appName: "Editor", inputSourceID: "source.en",
                 inputSourceName: "English", isEnabled: true)
        ], isPaused: false))
        return (AppModel(input: input, store: store, ownBundleID: "local.inputpilot.app",
                         frontmostBundleID: foreground), url)
    }

    @MainActor
    func testUnavailableRuleErrorClearsOnSuccessfulNoOpReentry() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese]
        let (model, _) = try makeModel(input)
        model.applyRule(trigger: .applicationActivated)
        XCTAssertNotNil(model.ruleError)
        input.available = [input.chinese, input.english]
        input.current = input.english // User restored and manually selected the target.
        model.refreshSources()
        model.applyRule(trigger: .applicationActivated)
        XCTAssertNil(model.ruleError)
        XCTAssertFalse(model.hasError)
        XCTAssertEqual(model.currentSource, input.english)
        XCTAssertTrue(input.selected.isEmpty)
    }

    @MainActor
    func testFailedCurrentReadInvalidatesOldDisplayAndThenRecovers() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese, input.english]
        let (model, _) = try makeModel(input)
        XCTAssertEqual(model.currentSource, input.chinese)
        input.readError = InputSourceError.invalidSystemData("read failed")
        model.applyRule(trigger: .applicationActivated)
        XCTAssertNil(model.currentSource)
        XCTAssertNotNil(model.inputError)
        XCTAssertTrue(input.selected.isEmpty)
        input.readError = nil
        model.applyRule(trigger: .applicationActivated)
        XCTAssertEqual(model.currentSource, input.english)
        XCTAssertNil(model.inputError)
        XCTAssertFalse(model.hasError)
    }

    @MainActor
    func testSelectionFailureKeepsTheValidActualSource() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese, input.english]
        input.selectionError = InputSourceError.selectionFailed("source.en", -50)
        let (model, _) = try makeModel(input)
        model.applyRule(trigger: .applicationActivated)
        XCTAssertEqual(model.currentSource, input.chinese)
        XCTAssertNotNil(model.ruleError)
        XCTAssertNil(model.inputError)
    }

    @MainActor
    func testRuleSuccessDoesNotHideAConfigurationWriteFailure() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese, input.english]
        let (model, url) = try makeModel(input)
        // Replace only this test's temporary file with a directory to force an atomic-write failure.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        model.setPaused(true)
        XCTAssertNotNil(model.operationError)
        XCTAssertEqual(model.configuration?.isPaused, false)
        model.applyRule(trigger: .applicationActivated)
        XCTAssertNil(model.ruleError)
        XCTAssertNotNil(model.operationError)
        XCTAssertEqual(input.selected, ["source.en"])
    }

    @MainActor
    func testPausePersistsAndResumeAppliesTheCurrentApplicationRule() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese, input.english]
        let (model, url) = try makeModel(input)
        model.setPaused(true)
        XCTAssertEqual(model.configuration?.isPaused, true)
        XCTAssertTrue(try RuleStore(fileURL: url).load().isPaused)
        model.applyRule(trigger: .applicationActivated)
        XCTAssertTrue(input.selected.isEmpty)

        model.setPaused(false)
        XCTAssertEqual(model.configuration?.isPaused, false)
        XCTAssertFalse(try RuleStore(fileURL: url).load().isPaused)
        XCTAssertEqual(input.selected, [input.english.id])
        XCTAssertEqual(model.currentSource, input.english)
    }

    @MainActor
    func testFailedResumeKeepsPausedAndDoesNotSwitch() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese, input.english]
        let (model, url) = try makeModel(input)
        model.setPaused(true)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        model.setPaused(false)
        XCTAssertEqual(model.configuration?.isPaused, true)
        XCTAssertNotNil(model.operationError)
        model.applyRule(trigger: .applicationActivated)
        XCTAssertTrue(input.selected.isEmpty)
        XCTAssertNotNil(model.operationError)
    }

    @MainActor
    func testEachActivationReadsTheLatestForegroundAndObservationNeverSwitches() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese, input.english]
        let (model, _) = try makeModel(input, foreground: { input.foreground })
        input.foreground = "test.other" // Changes before the queued activation is handled.
        model.applyRule(trigger: .applicationActivated)
        XCTAssertTrue(input.selected.isEmpty)
        input.foreground = "test.editor"
        model.applyRule(trigger: .applicationActivated)
        XCTAssertEqual(input.selected, ["source.en"])
        input.current = input.chinese
        model.applyRule(trigger: .inputSourceChanged)
        XCTAssertEqual(model.currentSource, input.chinese)
        XCTAssertEqual(input.selected, ["source.en"])
        model.applyRule(trigger: .applicationActivated)
        XCTAssertEqual(input.selected, ["source.en", "source.en"])
    }

    @MainActor
    func testPendingApplicationIsSavedOnlyAfterValidInlineSelection() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese, input.english]
        let (model, url) = try makeModel(input)
        let pending = Rule(bundleID: "test.new", appName: "New App",
                           inputSourceID: "", inputSourceName: "", isEnabled: true)
        let before = try RuleStore(fileURL: url).load()
        model.setRuleInputSource(pending, "missing")
        XCTAssertNotNil(model.operationError)
        XCTAssertEqual(try RuleStore(fileURL: url).load(), before)

        model.setRuleInputSource(pending, input.chinese.id)
        let saved = try XCTUnwrap(try RuleStore(fileURL: url).load().rules.first { $0.id == pending.id })
        XCTAssertEqual(saved.inputSourceID, input.chinese.id)
        XCTAssertEqual(saved.inputSourceName, input.chinese.name)
        XCTAssertTrue(saved.isEnabled)
        XCTAssertNil(model.operationError)
        XCTAssertTrue(input.selected.isEmpty)
    }

    @MainActor
    func testInlineSourceAndEnabledEditsPersistWithoutSwitchingImmediately() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese, input.english]
        let (model, url) = try makeModel(input)
        let original = try XCTUnwrap(model.configuration?.rules.first)
        model.setRuleEnabled(original, false)
        let disabled = try XCTUnwrap(model.configuration?.rules.first)
        model.setRuleInputSource(disabled, input.chinese.id)
        var expected = original
        expected.inputSourceID = input.chinese.id
        expected.inputSourceName = input.chinese.name
        expected.isEnabled = false
        XCTAssertEqual(model.configuration?.rules, [expected])
        XCTAssertEqual(try RuleStore(fileURL: url).load().rules, [expected])
        XCTAssertTrue(input.selected.isEmpty)

        model.setRuleEnabled(expected, true)
        XCTAssertTrue(input.selected.isEmpty)
        input.current = input.english
        model.applyRule(trigger: .applicationActivated)
        XCTAssertEqual(input.selected, [input.chinese.id])
    }

    @MainActor
    func testUnavailableInlineSelectionPreservesTheSavedRuleAndReportsError() throws {
        let input = TestInputSourceAccess()
        input.available = [input.english]
        let (model, url) = try makeModel(input)
        let original = try XCTUnwrap(model.configuration?.rules.first)
        let originalData = try Data(contentsOf: url)
        model.setRuleInputSource(original, input.chinese.id)
        XCTAssertEqual(model.configuration?.rules, [original])
        XCTAssertEqual(try Data(contentsOf: url), originalData)
        XCTAssertTrue(try XCTUnwrap(model.operationError).contains(input.chinese.id))
        XCTAssertTrue(input.selected.isEmpty)
    }

    @MainActor
    func testFailedInlineEditAndDeletionKeepTheCommittedRow() throws {
        let input = TestInputSourceAccess()
        input.available = [input.chinese, input.english]
        let (model, url) = try makeModel(input)
        let original = try XCTUnwrap(model.configuration?.rules.first)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        model.setRuleInputSource(original, input.chinese.id)
        XCTAssertEqual(model.configuration?.rules, [original])
        XCTAssertNotNil(model.operationError)
        XCTAssertFalse(model.deleteRule(original))
        XCTAssertEqual(model.configuration?.rules, [original])
        XCTAssertNotNil(model.operationError)
        XCTAssertTrue(input.selected.isEmpty)

        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(model.deleteRule(original))
        XCTAssertEqual(model.configuration?.rules, [])
        XCTAssertEqual(try RuleStore(fileURL: url).load().rules, [])
        XCTAssertNil(model.operationError)
    }
}
