import Foundation

enum PinsPosition: String, CaseIterable, Identifiable, CustomStringConvertible {
  case top
  case bottom

  var id: Self { self }

  var description: String {
    switch self {
    case .top:
      return "固定在顶部"
    case .bottom:
      return "固定在底部"
    }
  }
}
