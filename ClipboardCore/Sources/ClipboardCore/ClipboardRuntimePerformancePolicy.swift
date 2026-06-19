import Foundation

public struct ClipboardCapturePerformanceSample: Sendable, Equatable {
  public var typeCount: Int
  public var readMilliseconds: Double
  public var insertMilliseconds: Double
  public var totalMilliseconds: Double

  public init(
    typeCount: Int,
    readMilliseconds: Double,
    insertMilliseconds: Double,
    totalMilliseconds: Double
  ) {
    self.typeCount = typeCount
    self.readMilliseconds = readMilliseconds
    self.insertMilliseconds = insertMilliseconds
    self.totalMilliseconds = totalMilliseconds
  }
}

public struct ThumbnailPerformanceSample: Sendable, Equatable {
  public var generatedCount: Int
  public var elapsedMilliseconds: Double

  public init(generatedCount: Int, elapsedMilliseconds: Double) {
    self.generatedCount = generatedCount
    self.elapsedMilliseconds = elapsedMilliseconds
  }
}

public struct ClipboardRuntimePerformancePolicy: Sendable, Equatable {
  public var pasteboardReadWarningMilliseconds: Double
  public var coreInsertWarningMilliseconds: Double
  public var totalCaptureWarningMilliseconds: Double
  public var thumbnailWarningMilliseconds: Double

  public init(
    pasteboardReadWarningMilliseconds: Double = 50,
    coreInsertWarningMilliseconds: Double = 50,
    totalCaptureWarningMilliseconds: Double = 100,
    thumbnailWarningMilliseconds: Double = 100
  ) {
    self.pasteboardReadWarningMilliseconds = pasteboardReadWarningMilliseconds
    self.coreInsertWarningMilliseconds = coreInsertWarningMilliseconds
    self.totalCaptureWarningMilliseconds = totalCaptureWarningMilliseconds
    self.thumbnailWarningMilliseconds = thumbnailWarningMilliseconds
  }

  public static let `default` = ClipboardRuntimePerformancePolicy()

  public func captureExceededWarningThreshold(_ sample: ClipboardCapturePerformanceSample) -> Bool {
    sample.readMilliseconds > pasteboardReadWarningMilliseconds ||
      sample.insertMilliseconds > coreInsertWarningMilliseconds ||
      sample.totalMilliseconds > totalCaptureWarningMilliseconds
  }

  public func thumbnailExceededWarningThreshold(_ sample: ThumbnailPerformanceSample) -> Bool {
    sample.generatedCount > 0 && sample.elapsedMilliseconds > thumbnailWarningMilliseconds
  }
}
