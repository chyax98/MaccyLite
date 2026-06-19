import AppKit
import SwiftHEXColors

class ColorImage {
  private static let cache = NSCache<NSString, NSImage>()

  static func from(_ colorHex: String) -> NSImage? {
    if let cached = cache.object(forKey: colorHex as NSString) {
      return cached
    }

    guard let color = NSColor(hexString: colorHex) else {
      return nil
    }

    let image = NSImage(size: NSSize(width: 12, height: 12))
    image.lockFocus()
    color.drawSwatch(in: NSRect(x: 0, y: 0, width: 12, height: 12))
    image.unlockFocus()
    cache.setObject(image, forKey: colorHex as NSString)

    return image
  }
}
