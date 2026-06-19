import AppKit.NSEvent

enum HistoryItemAction {
  case unknown
  case copy
  case paste
  case pasteWithoutFormatting

  init(_ modifierFlags: NSEvent.ModifierFlags) {  // swiftlint:disable:this cyclomatic_complexity
    switch modifierFlags {
    case .command where !AppPreferences.pasteByDefault:
      self = .copy
    case .command where AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      self = .paste
    case .command where AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      self = .pasteWithoutFormatting
    case .option where !AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      self = .paste
    case .option where !AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      self = .pasteWithoutFormatting
    case .option where AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      self = .copy
    case .option where AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      self = .copy
    case [.option, .shift] where !AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      self = .pasteWithoutFormatting
    case [.option, .shift] where !AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      self = .paste
    case [.command, .shift] where AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      self = .pasteWithoutFormatting
    case [.command, .shift] where AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      self = .paste
    default:
      self = .unknown
    }
  }

  var modifierFlags: NSEvent.ModifierFlags {
    switch self {
    case .copy where !AppPreferences.pasteByDefault:
      return .command
    case .paste where AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      return .command
    case .pasteWithoutFormatting where AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      return .command
    case .paste where !AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      return .option
    case .pasteWithoutFormatting where !AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      return .option
    case .copy where AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      return .option
    case .copy where AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      return .option
    case .pasteWithoutFormatting where !AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      return [.option, .shift]
    case .paste where !AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      return [.option, .shift]
    case .pasteWithoutFormatting where AppPreferences.pasteByDefault && !AppPreferences.removeFormattingByDefault:
      return [.command, .shift]
    case .paste where AppPreferences.pasteByDefault && AppPreferences.removeFormattingByDefault:
      return [.command, .shift]
    default:
      return []
    }
  }
}
