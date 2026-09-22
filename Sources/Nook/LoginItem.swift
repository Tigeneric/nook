import Foundation
import Observation
import ServiceManagement

/// Launching at login.
///
/// The state is held by the system (`SMAppService`) rather than by our own
/// settings: a person may switch Nook off in System Settings → General →
/// Login Items, and our checkbox has to reflect that rather than argue.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled: Bool
    /// Why toggling failed — shown next to the checkbox.
    private(set) var failure: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        refresh()
    }
}
