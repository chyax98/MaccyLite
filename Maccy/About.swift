import Cocoa

class About {
  private var links: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "MaccyLite│上游 Maccy",
                                           attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: "https://github.com/p0deje/Maccy", range: NSRange(location: 10, length: 8))
    return string
  }

  private var credits: NSMutableAttributedString {
    let credits = NSMutableAttributedString(string: "",
                                            attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    credits.append(links)
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }

  @objc
  func openAbout(_ sender: NSMenuItem?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
