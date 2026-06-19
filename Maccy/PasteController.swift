import AppKit
import Carbon.HIToolbox
import Logging

final class PasteController {
  static let shared = PasteController()

  private let logger = Logger(label: "com.local.MaccyLite.paste")

  private init() {}

  private var pasteKeyModifiers: NSEvent.ModifierFlags { pasteMenuItem?.keyEquivalentModifierMask ?? .command }
  private var pasteMenuItem: NSMenuItem? {
    NSApp.mainMenu?.items
      .flatMap { $0.submenu?.items ?? [] }
      .first { $0.action == #selector(NSText.paste) }
  }

  // Based on https://github.com/Clipy/Clipy/blob/develop/Clipy/Sources/Services/PasteService.swift.
  @discardableResult
  func paste() -> Bool {
    guard Accessibility.check() else {
      logger.warning("Automatic paste skipped because Accessibility permission is not granted.")
      return false
    }

    // Add flag that left/right modifier key has been pressed.
    // See https://github.com/TermiT/Flycut/pull/18 for details.
    let cmdFlag = CGEventFlags(rawValue: UInt64(pasteKeyModifiers.rawValue) | 0x000008)
    let vCode = CGKeyCode(kVK_ANSI_V)

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
