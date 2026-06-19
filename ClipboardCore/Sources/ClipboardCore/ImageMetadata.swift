import Foundation
import ImageIO

public struct ImageMetadata: Sendable, Equatable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }
}

public enum ImageMetadataReader {
  public static func read(from data: Data) -> ImageMetadata? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
      return nil
    }

    return ImageMetadata(width: width, height: height)
  }
}
