import CoreGraphics

final class Popup {
  var height: CGFloat = AppPreferences.windowSize.height

  init() {
    HotKeyManager.shared.onPopup = { [weak self] in
      self?.toggle()
    }
  }

  func toggle() {
    AppState.shared.appDelegate?.togglePopup(height: height)
  }

  func close() {
    AppState.shared.appDelegate?.closePopup()
  }

  func reset() {
  }
}
