import Defaults
import KeyboardShortcuts
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  var panel: FloatingPanel<ContentView>?

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = Defaults[.menuIcon].image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?
  private var transientStatusResetWorkItem: DispatchWorkItem?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    Clipboard.shared.onNewCoreCopy { History.shared.add($0) }
    Clipboard.shared.start()
    DailyExportScheduler.shared.start()
    DispatchQueue.global(qos: .utility).async {
      _ = ClipboardCoreStore.shared.generatePendingThumbnails(limit: 4)
    }

    Task {
      for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
        Clipboard.shared.restart()
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    Task {
      for await value in Defaults.updates(.menuIcon, initial: false) {
        statusItem.button?.image = value.image
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    disableUnusedGlobalHotkeys()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    togglePopup(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    DailyExportScheduler.shared.stop()

    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  @objc
  private func performStatusItemClick() {
    if let event = NSApp.currentEvent {
      let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifierFlags.contains(.option) {
        Defaults[.ignoreEvents].toggle()

        if modifierFlags.contains(.shift) {
          Defaults[.ignoreOnlyNextEvent] = Defaults[.ignoreEvents]
        }

        return
      }
    }

    togglePopup(height: AppState.shared.popup.height, at: .statusItem)
  }

  func openPopup(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    popupPanel().open(height: height, at: popupPosition)
  }

  func togglePopup(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    popupPanel().toggle(height: height, at: popupPosition)
  }

  func closePopup() {
    panel?.close()
  }

  func resizePopup(to height: CGFloat) {
    panel?.verticallyResize(to: height)
  }

  func isPopupPresented() -> Bool {
    panel?.isPresented == true
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      DispatchQueue.main.async {
        AppState.shared.appDelegate?.refreshMenuIconTextObservation()
      }
    }
  }

  private func refreshMenuIconTextObservation() {
    if Defaults[.showRecentCopyInMenuBar] {
      statusItem.button?.title = AppState.shared.menuIconText
    }
    synchronizeMenuIconText()
  }

  @MainActor
  func showTransientStatus(_ title: String, duration: TimeInterval = 3) {
    transientStatusResetWorkItem?.cancel()
    statusItem.button?.title = title

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      if Defaults[.showRecentCopyInMenuBar] {
        self.statusItem.button?.title = AppState.shared.menuIconText
      } else {
        self.statusItem.button?.title = ""
      }
    }
    transientStatusResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }

  private func popupPanel() -> FloatingPanel<ContentView> {
    if let panel {
      return panel
    }

    let panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "com.local.MaccyLite",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }
    self.panel = panel
    return panel
  }
}
