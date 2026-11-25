import Carbon
import Foundation

/// Global keyboard shortcut (Control-Option-S) that toggles snowball mode.
/// Uses the Carbon hot key API, which needs no special permissions.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            NotificationCenter.default.post(name: .snowdriftToggleSnowballMode, object: nil)
            return noErr
        }, 1, &spec, nil, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x534E_4F57), id: 1) // 'SNOW'
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
