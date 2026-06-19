import AppKit.NSEvent
import Foundation

enum PopupPosition: String, CaseIterable, Identifiable, CustomStringConvertible {
  case cursor
  case statusItem
  case window
  case center
  case lastPosition

  var id: Self { self }

  var description: String {
    switch self {
    case .cursor:
      return "鼠标位置"
    case .statusItem:
      return "菜单栏图标"
    case .window:
      return "当前窗口中心"
    case .center:
      return "屏幕中心"
    case .lastPosition:
      return "上次位置"
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func origin(size: NSSize, statusBarButton: NSStatusBarButton?) -> NSPoint {
    switch self {
    case .center:
      if let frame = NSScreen.forPopup?.visibleFrame {
        return clamp(NSRect.centered(ofSize: size, in: frame).origin, size: size, visibleFrame: frame)
      }
    case .window:
      if let frame = NSWorkspace.shared.frontmostApplication?.windowFrame {
        let origin = NSRect.centered(ofSize: size, in: frame).origin
        return clamp(origin, size: size, visibleFrame: visibleFrame(containing: origin))
      }
    case .statusItem:
      if let statusBarButton {
        let rectInWindow = statusBarButton.convert(statusBarButton.bounds, to: nil)
        if let screenRect = statusBarButton.window?.convertToScreen(rectInWindow) {
          let origin = NSPoint(x: screenRect.minX, y: screenRect.minY - size.height)
          return clamp(origin, size: size, visibleFrame: statusBarButton.window?.screen?.visibleFrame)
        }
      }
    case .lastPosition:
      if let frame = NSScreen.forPopup?.visibleFrame {
        let relativePos = AppPreferences.windowPosition
        let anchorX = frame.minX + frame.width * relativePos.x
        let anchorY = frame.minY + frame.height * relativePos.y
        // Anchor is top middle of frame
        return clamp(NSPoint(x: anchorX - size.width / 2, y: anchorY - size.height), size: size, visibleFrame: frame)
      }
    default:
      break
    }

    var point = NSEvent.mouseLocation
    point.y -= size.height
    return clamp(point, size: size, visibleFrame: visibleFrame(containing: NSEvent.mouseLocation))
  }

  private func visibleFrame(containing point: NSPoint) -> NSRect? {
    NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.forPopup?.visibleFrame
  }

  private func clamp(_ origin: NSPoint, size: NSSize, visibleFrame: NSRect?) -> NSPoint {
    guard let visibleFrame else {
      return origin
    }

    let maxX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
    let maxY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
    return NSPoint(
      x: min(max(origin.x, visibleFrame.minX), maxX),
      y: min(max(origin.y, visibleFrame.minY), maxY)
    )
  }
}
