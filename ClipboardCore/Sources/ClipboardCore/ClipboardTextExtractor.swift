import Foundation

public enum ClipboardTextExtractor {
  public static func plainText(from data: Data, limit: Int? = nil) -> String {
    let source = limit.map { Data(data.prefix($0)) } ?? data
    return String(data: utf8ValidPrefix(source), encoding: .utf8) ?? ""
  }

  public static func htmlText(from data: Data, limit: Int? = nil) -> String {
    stripHTML(plainText(from: data, limit: limit))
  }

  public static func stripHTML(_ html: String) -> String {
    var text = ""
    text.reserveCapacity(min(html.count, 20_000))
    var isInsideTag = false
    var previousWasWhitespace = false
    var index = html.startIndex

    while index < html.endIndex {
      let character = html[index]

      if character == "<" {
        isInsideTag = true
        appendSpace(to: &text, previousWasWhitespace: &previousWasWhitespace)
      } else if character == ">" {
        isInsideTag = false
      } else if !isInsideTag {
        if character.isWhitespace {
          appendSpace(to: &text, previousWasWhitespace: &previousWasWhitespace)
        } else {
          text.append(character)
          previousWasWhitespace = false
        }
      }

      index = html.index(after: index)
    }

    return text
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func appendSpace(to text: inout String, previousWasWhitespace: inout Bool) {
    guard !previousWasWhitespace, !text.isEmpty else {
      return
    }

    text.append(" ")
    previousWasWhitespace = true
  }

  private static func utf8ValidPrefix(_ data: Data) -> Data {
    guard String(data: data, encoding: .utf8) == nil else {
      return data
    }

    var prefix = data
    while String(data: prefix, encoding: .utf8) == nil && !prefix.isEmpty {
      prefix = prefix.dropLast()
    }
    return prefix
  }
}
