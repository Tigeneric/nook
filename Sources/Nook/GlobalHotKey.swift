import AppKit
import Carbon.HIToolbox

/// A global hot key that works on top of any application.
///
/// Carbon’s `RegisterEventHotKey` rather than
/// `NSEvent.addGlobalMonitorForEvents`: a monitor needs the Accessibility
/// permission and does not intercept the press — it hands a copy to the active
/// app. The overlay has to come up without permissions and without dropping a
/// space character into someone else’s window.
@MainActor
final class GlobalHotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handler: EventHandlerRef?

    private let id: UInt32
    private var ref: EventHotKeyRef?

    init?(_ combo: HotKeyCombo, action: @escaping () -> Void) {
        self.id = Self.nextID
        Self.nextID += 1

        Self.installHandlerIfNeeded()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F_4F4B), id: id)  // 'NOOK'
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else { return nil }

        self.ref = hotKeyRef
        Self.actions[id] = action
    }

    /// Unregisters the hot key. It lives for as long as the app runs, so this
    /// is only needed when the combination changes; `deinit` will not do —
    /// it is not isolated to the `MainActor`.
    func invalidate() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        Self.actions[id] = nil
    }

    fileprivate static func fire(id: UInt32) {
        actions[id]?()
    }

    private static func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &handler)
    }
}

/// The Carbon C callback: it captures no context, so the hot key identifier
/// comes out of the event rather than out of `userData`.
private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    // Carbon delivers the event on the app’s main event loop thread.
    MainActor.assumeIsolated {
        GlobalHotKey.fire(id: hotKeyID.id)
    }
    return noErr
}
