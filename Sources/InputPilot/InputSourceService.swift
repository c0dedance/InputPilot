import Carbon
import Foundation
import InputPilotCore

enum InputSourceError: Error, LocalizedError {
    case invalidSystemData(String)
    case selectionFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidSystemData(let detail):
            return "无法读取系统输入源：\(detail)"
        case .selectionFailed(let id, let status):
            return "系统拒绝切换到 \(id)（OSStatus \(status)）。请检查系统输入源设置。"
        }
    }
}

@MainActor
protocol InputSourceAccess {
    func availableSources() throws -> [InputSource]
    func currentSource() throws -> InputSource
    func select(id: String) throws
}

@MainActor
final class InputSourceService: InputSourceAccess {
    func availableSources() throws -> [InputSource] {
        try selectableSources().map(describe).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func currentSource() throws -> InputSource {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            throw InputSourceError.invalidSystemData("当前输入源为空。")
        }
        return try describe(source)
    }

    func select(id: String) throws {
        // Resolve a new snapshot at the last possible moment; never enable a source implicitly.
        let sources = try selectableSources()
        guard let source = try sources.first(where: { try string($0, kTISPropertyInputSourceID) == id }) else {
            throw RuleError.unavailableInputSource(id)
        }
        let status = TISSelectInputSource(source)
        guard status == noErr else { throw InputSourceError.selectionFailed(id, status) }
    }

    private func selectableSources() throws -> [TISInputSource] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue(),
              let sources = list as? [TISInputSource] else {
            throw InputSourceError.invalidSystemData("已启用输入源列表格式无效。")
        }
        return sources
    }

    private func describe(_ source: TISInputSource) throws -> InputSource {
        try InputSource(id: string(source, kTISPropertyInputSourceID),
                        name: string(source, kTISPropertyLocalizedName))
    }

    private func string(_ source: TISInputSource, _ key: CFString) throws -> String {
        guard let pointer = TISGetInputSourceProperty(source, key),
              let value = Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue() as? String,
              !value.isEmpty else {
            throw InputSourceError.invalidSystemData("缺少属性 \(key)。")
        }
        return value
    }
}
