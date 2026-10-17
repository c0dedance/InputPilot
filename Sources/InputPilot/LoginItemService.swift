import Combine
import ServiceManagement

@MainActor
final class LoginItemService: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?
    @Published private(set) var isUpdating = false

    var statusText: String {
        switch status {
        case .notRegistered: return "已关闭"
        case .enabled: return "已启用"
        case .requiresApproval: return "待批准 · 尚未启用"
        case .notFound: return "系统未找到登录项"
        @unknown default: return "未知系统状态"
        }
    }

    // A pending registration stays on so the user can cancel it; statusText names actual enablement.
    var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false; refresh() }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "登录项设置失败：\(error.localizedDescription) 本地临时签名可能不被系统接受；基础切换仍可使用。"
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
