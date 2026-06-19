import Carbon
import Foundation

final class HotKeyManager {
  static let shared = HotKeyManager()

  var onPopup: (() -> Void)?

  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?

  private init() {}

  func start() {
    stop()

    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )

        if hotKeyID.id == 1 {
          DispatchQueue.main.async {
            HotKeyManager.shared.onPopup?()
          }
        }
        return noErr
      },
      1,
      &eventType,
      nil,
      &handlerRef
    )

    let hotKeyID = EventHotKeyID(signature: fourCharCode("MCLT"), id: 1)
    RegisterEventHotKey(
      UInt32(kVK_ANSI_C),
      UInt32(cmdKey | shiftKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
  }

  func stop() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    if let handlerRef {
      RemoveEventHandler(handlerRef)
      self.handlerRef = nil
    }
  }

  private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
  }
}
