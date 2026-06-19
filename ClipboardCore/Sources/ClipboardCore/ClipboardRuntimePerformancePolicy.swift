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

public struct ClipboardRuntimePerformancePolicy: Sendable, Equatable {
  public var pasteboardReadWarningMilliseconds: Double
  public var coreInsertWarningMilliseconds: Double
  public var totalCaptureWarningMilliseconds: Double

  public init(
    pasteboardReadWarningMilliseconds: Double = 50,
    coreInsertWarningMilliseconds: Double = 50,
    totalCaptureWarningMilliseconds: Double = 100
  ) {
    self.pasteboardReadWarningMilliseconds = pasteboardReadWarningMilliseconds
    self.coreInsertWarningMilliseconds = coreInsertWarningMilliseconds
    self.totalCaptureWarningMilliseconds = totalCaptureWarningMilliseconds
  }

  public static let `default` = ClipboardRuntimePerformancePolicy()

  public func captureExceededWarningThreshold(_ sample: ClipboardCapturePerformanceSample) -> Bool {
    sample.readMilliseconds > pasteboardReadWarningMilliseconds ||
      sample.insertMilliseconds > coreInsertWarningMilliseconds ||
      sample.totalMilliseconds > totalCaptureWarningMilliseconds
  }
}
