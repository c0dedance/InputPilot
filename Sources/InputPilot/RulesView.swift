import AppKit
import InputPilotCore
import SwiftUI
import UniformTypeIdentifiers

struct RulesView: View {
    @ObservedObject var model: AppModel
    @State private var pendingRules: [Rule] = []
    @State private var selectedRuleID: String?
    @State private var selectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasError || selectionError != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let message = model.configurationError {
                            errorText(message)
                            HStack {
                                Button("打开配置文件夹") { model.revealConfiguration() }
                                Button("重新读取配置") { model.reloadConfiguration() }
                            }
                        }
                        if let message = model.operationError { errorText(message) }
                        if let message = model.ruleError { errorText(message) }
                        if let message = model.inputError { errorText(message) }
                        if let message = selectionError { errorText(message) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 100)
            }

            if let configuration = model.configuration {
                Table(configuration.rules + pendingRules, selection: $selectedRuleID) {
                    TableColumn("") { rule in
                        ApplicationIcon(bundleID: rule.bundleID)
                            .frame(height: 28)
                    }.width(32)
                    TableColumn("程序名称") { rule in
                        Text(rule.appName).lineLimit(1)
                            .help("\(rule.appName)\n\(rule.bundleID)")
                    }.width(min: 126, ideal: 154)
                    TableColumn("输入法") { rule in
                        Picker("\(rule.appName) 的输入法", selection: Binding(
                            get: { rule.inputSourceID },
                            set: {
                                selectedRuleID = rule.id
                                setInputSource(rule, $0)
                            }
                        )) {
                            if rule.inputSourceID.isEmpty {
                                Text("请选择输入法").tag("").disabled(true)
                            } else if !model.sources.contains(where: { $0.id == rule.inputSourceID }) {
                                Text("不可用：\(rule.inputSourceName)")
                                    .tag(rule.inputSourceID).disabled(true)
                            }
                            ForEach(model.sources) { source in
                                Text(source.name).tag(source.id)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu)
                        .disabled(model.sources.isEmpty)
                        .help("\(rule.inputSourceName)\n\(rule.inputSourceID)\n更改后自动保存，下次进入此应用时生效。")
                    }.width(min: 108, ideal: 120, max: 120)
                    TableColumn("启用规则") { rule in
                        Toggle("启用 \(rule.appName) 的规则", isOn: Binding(
                            get: { rule.isEnabled },
                            set: {
                                selectedRuleID = rule.id
                                model.setRuleEnabled(rule, $0)
                            }
                        ))
                        .labelsHidden().toggleStyle(.checkbox)
                        .disabled(rule.inputSourceID.isEmpty)
                        .frame(maxWidth: .infinity)
                    }.width(72)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .onDeleteCommand(perform: deleteSelectedRule)
                .overlay {
                    if configuration.rules.isEmpty && pendingRules.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "keyboard").font(.largeTitle).foregroundStyle(.secondary)
                            Text("还没有应用规则").font(.headline)
                            Text("添加应用后，直接在表格里选择输入法。")
                                .foregroundStyle(.secondary)
                            Button("添加应用…", action: chooseApplication)
                        }.padding(24)
                    }
                }

                HStack(spacing: 8) {
                    Button(action: chooseApplication) { Image(systemName: "plus").frame(width: 20) }
                        .help("添加应用…").accessibilityLabel("添加应用")
                    Button(action: deleteSelectedRule) { Image(systemName: "minus").frame(width: 20) }
                        .disabled(selectedRule == nil)
                        .help("删除所选应用的规则").accessibilityLabel("删除所选应用的规则")
                    Spacer(minLength: 4)
                    Picker("默认输入法：", selection: Binding(
                        get: { configuration.defaultInputSource?.id },
                        set: { model.setDefaultInputSource($0) }
                    )) {
                        Text("不切换输入法").tag(Optional<String>.none)
                        if let source = configuration.defaultInputSource,
                           !model.sources.contains(where: { $0.id == source.id }) {
                            Text("不可用：\(source.name)").tag(Optional(source.id)).disabled(true)
                        }
                        ForEach(model.sources) { source in
                            Text(source.name).tag(Optional(source.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 240)
                    .help("未设置应用规则时使用；更改后自动保存，下次进入应用时生效。")
                    Button("刷新输入法") { model.refreshSources() }
                        .fixedSize()
                        .help("刷新可用输入源").accessibilityLabel("刷新可用输入源")
                }
            } else {
                Spacer()
            }
            Divider()
            SettingsFooter(model: model, service: model.login)
        }
        .padding(16)
        .frame(width: 500)
        .frame(minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshSources(); model.login.refresh() }
    }

    private var selectedRule: Rule? {
        if let pending = pendingRules.first(where: { $0.id == selectedRuleID }) { return pending }
        return model.configuration?.rules.first { $0.id == selectedRuleID }
    }

    private func deleteSelectedRule() {
        guard let rule = selectedRule else { return }
        if pendingRules.contains(where: { $0.id == rule.id }) {
            pendingRules.removeAll { $0.id == rule.id }
            selectedRuleID = nil
        } else if model.deleteRule(rule) {
            selectedRuleID = nil
        }
    }

    private func setInputSource(_ rule: Rule, _ sourceID: String) {
        model.setRuleInputSource(rule, sourceID)
        if model.configuration?.rules.contains(where: { $0.id == rule.id }) == true {
            pendingRules.removeAll { $0.id == rule.id }
        }
    }

    private func errorText(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要指定输入法的应用"
        panel.prompt = "选择应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        guard let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier, !id.isEmpty else {
            selectionError = "这个应用没有有效的 bundle ID，无法创建规则。请选择完整的 .app。"
            return
        }
        guard id != model.ownBundleID else {
            selectionError = "本应用不为自己切换输入法，请选择其他应用。"
            return
        }
        selectionError = nil
        if let existing = model.configuration?.rules.first(where: { $0.bundleID == id }) {
            selectedRuleID = existing.id
        } else if let pending = pendingRules.first(where: { $0.bundleID == id }) {
            selectedRuleID = pending.id
        } else {
            let rule = Rule(bundleID: id, appName: url.deletingPathExtension().lastPathComponent,
                           inputSourceID: "", inputSourceName: "", isEnabled: true)
            pendingRules.append(rule)
            selectedRuleID = rule.id
        }
    }
}

private struct ApplicationIcon: View {
    let bundleID: String
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "questionmark.app").resizable().scaledToFit()
                    .foregroundStyle(.secondary).help("未找到已安装的应用：\(bundleID)")
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
        .task(id: bundleID) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                icon = nil
            }
        }
    }
}

private struct SettingsFooter: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @ObservedObject var model: AppModel
    @ObservedObject var service: LoginItemService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                if let configuration = model.configuration {
                    Toggle("启用切换", isOn: Binding(
                        get: { !configuration.isPaused },
                        set: { model.setPaused(!$0) }
                    ))
                    .fixedSize()
                } else {
                    Text("配置错误，已停止").foregroundStyle(.red)
                }
                Toggle("开机自启", isOn: Binding(
                    get: { service.isRegistered },
                    set: { enabled in Task { await service.setEnabled(enabled) } }
                ))
                .fixedSize()
                .disabled(service.isUpdating)
                .accessibilityValue(service.statusText)
                Toggle("隐藏菜单栏图标", isOn: Binding(
                    get: { !showMenuBarIcon },
                    set: { showMenuBarIcon = !$0 }
                ))
                .fixedSize()
                Spacer()
            }
            .toggleStyle(.checkbox)
            if !showMenuBarIcon {
                Text("重新打开应用可返回此设置，取消勾选即可恢复菜单栏图标。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if service.isUpdating {
                Text("正在更新…").foregroundStyle(.secondary)
            } else if service.status != .enabled && service.status != .notRegistered {
                Text(service.statusText).foregroundStyle(.secondary)
            }
            if service.status == .requiresApproval {
                Button("打开系统登录项设置…") { service.openSystemSettings() }
            }
            if let message = service.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
