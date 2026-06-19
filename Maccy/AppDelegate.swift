import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
  var panel: AppKitHistoryPanel?

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = AppPreferences.menuIcon.image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  private var isStatusItemDisabled: Bool {
    AppPreferences.ignoreEvents || AppPreferences.enabledPasteboardTypes.isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?
  private var transientStatusResetWorkItem: DispatchWorkItem?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    AppPreferences.migratePerformanceDefaults()

    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    Clipboard.shared.onNewCoreCopy { [weak self] item in
      History.shared.add(item)
      self?.refreshMenuIconText()
    }
    Clipboard.shared.start()
    DailyExportScheduler.shared.start()

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, AppPreferences.showInStatusBar != newValue {
        AppPreferences.showInStatusBar = newValue
      }
    }

    statusItem.isVisible = AppPreferences.showInStatusBar
    refreshMenuIconText()
    statusItem.button?.appearsDisabled = isStatusItemDisabled
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    HotKeyManager.shared.start()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    togglePopup(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    DailyExportScheduler.shared.stop()

    if AppPreferences.clearOnQuit {
      AppState.shared.history.clear()
    }
    HotKeyManager.shared.stop()
  }

  @objc
  private func performStatusItemClick() {
    if let event = NSApp.currentEvent {
      let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifierFlags.contains(.option) {
        AppPreferences.ignoreEvents.toggle()

        if modifierFlags.contains(.shift) {
          AppPreferences.ignoreOnlyNextEvent = AppPreferences.ignoreEvents
        }

        statusItem.button?.appearsDisabled = isStatusItemDisabled
        return
      }
    }

    togglePopup(height: AppState.shared.popup.height, at: .statusItem)
  }

  func openPopup(height: CGFloat, at popupPosition: PopupPosition = AppPreferences.popupPosition) {
    popupPanel().open(height: height, at: popupPosition)
  }

  func togglePopup(height: CGFloat, at popupPosition: PopupPosition = AppPreferences.popupPosition) {
    popupPanel().toggle(height: height, at: popupPosition)
  }

  func closePopup() {
    panel?.close()
  }

  func resizePopup(to height: CGFloat) {
    panel?.verticallyResize(to: height)
  }

  func isPopupPresented() -> Bool {
    panel?.isOpen() == true
  }

  func refreshMenuIconText() {
    if AppPreferences.showRecentCopyInMenuBar {
      statusItem.button?.title = AppState.shared.menuIconText
    } else {
      statusItem.button?.title = ""
    }
  }

  @MainActor
  func showTransientStatus(_ title: String, duration: TimeInterval = 3) {
    transientStatusResetWorkItem?.cancel()
    statusItem.button?.title = title

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      if AppPreferences.showRecentCopyInMenuBar {
        self.statusItem.button?.title = AppState.shared.menuIconText
      } else {
        self.statusItem.button?.title = ""
      }
    }
    transientStatusResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
  }

  private func popupPanel() -> AppKitHistoryPanel {
    if let panel {
      return panel
    }

    let panel = AppKitHistoryPanel(
      contentRect: NSRect(origin: .zero, size: AppPreferences.windowSize),
      identifier: Bundle.main.bundleIdentifier ?? "com.local.MaccyLite",
      statusBarButton: statusItem.button
    )
    self.panel = panel
    return panel
  }
}
