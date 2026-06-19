import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageThumbnailGenerator {
  public static func pngThumbnail(from data: Data, maxPixelSize: Int = 512) -> Data? {
    let options = [
      kCGImageSourceShouldCache: false
    ] as CFDictionary

    guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
      return nil
    }

    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: false,
      kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
    ] as CFDictionary

    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return nil
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      output,
      UTType.png.identifier as CFString,
      1,
      nil
    ) else {
      return nil
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }

    return output as Data
  }
}
