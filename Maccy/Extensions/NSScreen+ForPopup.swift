import AppKit.NSScreen

extension NSScreen {
  static var forPopup: NSScreen? {
    let desiredScreen = AppPreferences.popupScreen
    if desiredScreen == 0 || desiredScreen > NSScreen.screens.count {
      return NSScreen.main
    } else {
      return NSScreen.screens[desiredScreen - 1]
    }
  }
}
