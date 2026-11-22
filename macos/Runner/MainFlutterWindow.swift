import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Gene - Nov, 22, 2026: Explicitly enforce opaque native macOS window and title bar backing to prevent transparent header bar
  // override func awakeFromNib() {
  //   let flutterViewController = FlutterViewController()
  //   self.contentViewController = flutterViewController
  //
  //   // Set a spacious default window size that comfortably fits all forms
  //   var windowFrame = self.frame
  //   windowFrame.size = NSSize(width: 1280, height: 840)
  //   self.setFrame(windowFrame, display: true)
  //   self.center()
  //
  //   // Set a minimum window size to prevent UI overflow
  //   self.minSize = NSSize(width: 980, height: 680)
  //
  //   RegisterGeneratedPlugins(registry: flutterViewController)
  //
  //   super.awakeFromNib()
  // }
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    self.isOpaque = true
    self.titlebarAppearsTransparent = false
    self.backgroundColor = NSColor.windowBackgroundColor

    // Set a spacious default window size that comfortably fits all forms
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1280, height: 840)
    self.setFrame(windowFrame, display: true)
    self.center()

    // Set a minimum window size to prevent UI overflow
    self.minSize = NSSize(width: 980, height: 680)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
