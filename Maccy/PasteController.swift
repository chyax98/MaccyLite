import AppKit
import Logging
import Sauce

final class PasteController {
  static let shared = PasteController()

  private let logger = Logger(label: "com.local.MaccyLite.paste")

  private init() {}

  // Based on https://github.com/Clipy/Clipy/blob/develop/Clipy/Sources/Services/PasteService.swift.
  @discardableResult
  func paste() -> Bool {
    guard Accessibility.check() else {
      logger.warning("Automatic paste skipped because Accessibility permission is not granted.")
      return false
    }

    // Add flag that left/right modifier key has been pressed.
    // See https://github.com/TermiT/Flycut/pull/18 for details.
    let cmdFlag = CGEventFlags(rawValue: UInt64(KeyChord.pasteKeyModifiers.rawValue) | 0x000008)
    var vCode = Sauce.shared.keyCode(for: KeyChord.pasteKey)

    // Force QWERTY keycode when keyboard layout switches to
    // QWERTY upon pressing command key.
    if KeyboardLayout.current.commandSwitchesToQWERTY && cmdFlag.contains(.maskCommand) {
      vCode = KeyChord.pasteKey.QWERTYKeyCode
    }

    let source = CGEventSource(stateID: .combinedSessionState)
    source?.setLocalEventsFilterDuringSuppressionState(
      [.permitLocalMouseEvents, .permitSystemDefinedEvents],
      state: .eventSuppressionStateSuppressionInterval
    )

    let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true)
    let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false)
    keyVDown?.flags = cmdFlag
    keyVUp?.flags = cmdFlag
    keyVDown?.post(tap: .cgSessionEventTap)
    keyVUp?.post(tap: .cgSessionEventTap)
    return true
  }
}
