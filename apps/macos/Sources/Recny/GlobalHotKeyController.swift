import Carbon.HIToolbox
import Foundation
import RecnyCore

@MainActor
final class GlobalHotKeyController {
    private static let signature = OSType(0x544F5242) // TORB
    private static let hotKeyID = EventHotKeyID(
        signature: signature,
        id: 1
    )

    private static nonisolated(unsafe) var showWindowAction: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onShowWindow: @MainActor () -> Void

    init(onShowWindow: @escaping @MainActor () -> Void) {
        self.onShowWindow = onShowWindow
    }

    func start() {
        guard hotKeyRef == nil else {
            return
        }

        Self.showWindowAction = { [weak self] in
            Task { @MainActor in
                self?.onShowWindow()
            }
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard parameterStatus == noErr,
                      hotKeyID.signature == GlobalHotKeyController.hotKeyID.signature,
                      hotKeyID.id == GlobalHotKeyController.hotKeyID.id
                else {
                    return noErr
                }

                GlobalHotKeyController.showWindowAction?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            AppLogger.file(.warning, category: "app", "global show-window hotkey handler registration failed status=\(handlerStatus)")
            return
        }

        let hotKeyID = Self.hotKeyID
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            AppLogger.file(.warning, category: "app", "global show-window hotkey registration failed status=\(registerStatus)")
            stop()
            return
        }

        AppLogger.file(.info, category: "app", "global show-window hotkey \(KeyboardShortcutCatalog.showWindowGlobal.displayText)")
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        Self.showWindowAction = nil
    }
}
