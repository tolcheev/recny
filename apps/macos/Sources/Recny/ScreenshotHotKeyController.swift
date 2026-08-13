import Carbon.HIToolbox
import Foundation
import RecnyCore

@MainActor
final class ScreenshotHotKeyController {
    private static let signature = OSType(0x544F5242) // TORB
    private static let hotKeyID = EventHotKeyID(
        signature: signature,
        id: 2
    )

    private static nonisolated(unsafe) var captureAction: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onCapture: @MainActor () -> Void

    init(onCapture: @escaping @MainActor () -> Void) {
        self.onCapture = onCapture
    }

    func start() {
        guard hotKeyRef == nil else {
            return
        }

        Self.captureAction = { [weak self] in
            Task { @MainActor in
                self?.onCapture()
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
                      hotKeyID.signature == ScreenshotHotKeyController.hotKeyID.signature,
                      hotKeyID.id == ScreenshotHotKeyController.hotKeyID.id
                else {
                    return noErr
                }

                ScreenshotHotKeyController.captureAction?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            AppLogger.file(.warning, category: "app", "global screenshot hotkey handler registration failed status=\(handlerStatus)")
            return
        }

        let hotKeyID = Self.hotKeyID
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            AppLogger.file(.warning, category: "app", "global screenshot hotkey registration failed status=\(registerStatus)")
            stop()
            return
        }

        AppLogger.file(.info, category: "app", "global screenshot hotkey \(KeyboardShortcutCatalog.captureScreenshotGlobal.displayText)")
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

        Self.captureAction = nil
    }
}
