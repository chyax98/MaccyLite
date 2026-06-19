import AppKit

struct Accessibility {
  static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  @discardableResult
  static func check(prompt: Bool = false) -> Bool {
    if allowed {
      return true
    }

    guard prompt else {
      return false
    }

    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }
}
