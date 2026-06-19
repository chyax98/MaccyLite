import Foundation

enum PinsPosition: String, CaseIterable, Identifiable, CustomStringConvertible {
  case top
  case bottom

  var id: Self { self }

  var description: String {
    switch self {
    case .top:
      return NSLocalizedString("PinToTop", tableName: "AppearanceSettings", comment: "")
    case .bottom:
      return NSLocalizedString("PinToBottom", tableName: "AppearanceSettings", comment: "")
    }
  }
}
