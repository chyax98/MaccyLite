import AppKit
import Carbon.HIToolbox

final class HotKeyRecorderField: NSTextField {
  var onChange: ((UInt32, UInt32) -> Bool)?
  private var keyCode: UInt32 = UInt32(kVK_ANSI_C)
  private var modifiers: UInt32 = UInt32(optionKey)
  private var keyMonitor: Any?
  private var isRecording = false

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 28))
    isEditable = false
    isSelectable = false
    isBezeled = true
    drawsBackground = true
    alignment = .center
    focusRingType = .default
    font = .monospacedSystemFont(ofSize: 13, weight: .medium)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  deinit {
    stopRecording(restartHotKey: false)
  }

  override func becomeFirstResponder() -> Bool {
    startRecording()
    return true
  }

  override func resignFirstResponder() -> Bool {
    stopRecording(restartHotKey: true)
    return true
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    startRecording()
  }

  override func keyDown(with event: NSEvent) {
    record(event)
  }

  func setHotKey(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    stringValue = "\(Self.modifierDescription(modifiers))\(Self.keyName(Int(keyCode)))"
  }

  private func startRecording() {
    guard !isRecording else {
      return
    }

    isRecording = true
    HotKeyManager.shared.stop()
    stringValue = "按新的快捷键"
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.window?.firstResponder === self else {
        return event
      }

      self.record(event)
      return nil
    }
  }

  private func stopRecording(restartHotKey: Bool) {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
    isRecording = false
    stringValue = "\(Self.modifierDescription(modifiers))\(Self.keyName(Int(keyCode)))"
    if restartHotKey, !HotKeyManager.shared.start() {
      NSSound.beep()
    }
  }

  private func record(_ event: NSEvent) {
    let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
    guard carbonModifiers != 0, !Self.modifierOnlyKeyCodes.contains(Int(event.keyCode)) else {
      NSSound.beep()
      return
    }

    let nextKeyCode = UInt32(event.keyCode)
    guard onChange?(nextKeyCode, carbonModifiers) == true else {
      NSSound.beep()
      window?.makeFirstResponder(nil)
      return
    }

    setHotKey(keyCode: nextKeyCode, modifiers: carbonModifiers)
    window?.makeFirstResponder(nil)
  }

  private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    let flags = flags.intersection(.deviceIndependentFlagsMask)
    var modifiers: UInt32 = 0
    if flags.contains(.command) {
      modifiers |= UInt32(cmdKey)
    }
    if flags.contains(.option) {
      modifiers |= UInt32(optionKey)
    }
    if flags.contains(.control) {
      modifiers |= UInt32(controlKey)
    }
    if flags.contains(.shift) {
      modifiers |= UInt32(shiftKey)
    }
    return modifiers
  }

  private static func modifierDescription(_ modifiers: UInt32) -> String {
    var description = ""
    if modifiers & UInt32(controlKey) != 0 {
      description += "⌃"
    }
    if modifiers & UInt32(optionKey) != 0 {
      description += "⌥"
    }
    if modifiers & UInt32(shiftKey) != 0 {
      description += "⇧"
    }
    if modifiers & UInt32(cmdKey) != 0 {
      description += "⌘"
    }
    return description
  }

  private static func keyName(_ keyCode: Int) -> String {
    keyNames[keyCode] ?? "Key \(keyCode)"
  }

  private static let modifierOnlyKeyCodes: Set<Int> = Set([
    Int(kVK_Command),
    Int(kVK_RightCommand),
    Int(kVK_Shift),
    Int(kVK_RightShift),
    Int(kVK_Option),
    Int(kVK_RightOption),
    Int(kVK_Control),
    Int(kVK_RightControl),
    Int(kVK_Function)
  ])

  private static let keyNames: [Int: String] = [
    kVK_ANSI_A: "A",
    kVK_ANSI_B: "B",
    kVK_ANSI_C: "C",
    kVK_ANSI_D: "D",
    kVK_ANSI_E: "E",
    kVK_ANSI_F: "F",
    kVK_ANSI_G: "G",
    kVK_ANSI_H: "H",
    kVK_ANSI_I: "I",
    kVK_ANSI_J: "J",
    kVK_ANSI_K: "K",
    kVK_ANSI_L: "L",
    kVK_ANSI_M: "M",
    kVK_ANSI_N: "N",
    kVK_ANSI_O: "O",
    kVK_ANSI_P: "P",
    kVK_ANSI_Q: "Q",
    kVK_ANSI_R: "R",
    kVK_ANSI_S: "S",
    kVK_ANSI_T: "T",
    kVK_ANSI_U: "U",
    kVK_ANSI_V: "V",
    kVK_ANSI_W: "W",
    kVK_ANSI_X: "X",
    kVK_ANSI_Y: "Y",
    kVK_ANSI_Z: "Z",
    kVK_ANSI_0: "0",
    kVK_ANSI_1: "1",
    kVK_ANSI_2: "2",
    kVK_ANSI_3: "3",
    kVK_ANSI_4: "4",
    kVK_ANSI_5: "5",
    kVK_ANSI_6: "6",
    kVK_ANSI_7: "7",
    kVK_ANSI_8: "8",
    kVK_ANSI_9: "9",
    kVK_Space: "Space",
    kVK_Return: "Return",
    kVK_Escape: "Esc",
    kVK_Tab: "Tab",
    kVK_Delete: "Delete",
    kVK_ForwardDelete: "Forward Delete",
    kVK_LeftArrow: "←",
    kVK_RightArrow: "→",
    kVK_UpArrow: "↑",
    kVK_DownArrow: "↓"
  ].reduce(into: [Int: String]()) { result, entry in
    result[Int(entry.key)] = entry.value
  }
}
