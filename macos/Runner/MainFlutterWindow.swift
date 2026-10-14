import Cocoa
import FlutterMacOS

// Borderless blurred panel that drops down from a menu bar icon.
class MainFlutterWindow: NSWindow {
  private var statusItem: NSStatusItem!
  private var flutterViewController: FlutterViewController!
  private var clickOutsideMonitor: Any?

  override var canBecomeKey: Bool { true }

  override func awakeFromNib() {
    flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    RegisterGeneratedPlugins(registry: flutterViewController)

    styleMask = [.borderless]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = .popUpMenu
    setContentSize(NSSize(width: 360, height: 520))
    contentView = makeBackground(around: flutterViewController.view)

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Climate")
    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePanel)

    super.awakeFromNib()
  }

  // Real Liquid Glass on macOS 26 (needs the Xcode 26 SDK / Swift 6.2), native blur otherwise.
  private func makeBackground(around content: NSView) -> NSView {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.cornerRadius = 14
      glass.contentView = content
      return glass
    }
    #endif
    let blur = NSVisualEffectView()
    blur.material = .popover
    blur.blendingMode = .behindWindow
    blur.state = .active
    blur.wantsLayer = true
    blur.layer?.cornerRadius = 14
    blur.layer?.masksToBounds = true
    content.frame = blur.bounds
    content.autoresizingMask = [.width, .height]
    blur.addSubview(content)
    return blur
  }

  @objc private func togglePanel() {
    if isVisible { hidePanel(); return }
    guard let icon = statusItem.button?.window?.frame else { return }
    setFrameOrigin(NSPoint(x: icon.midX - frame.width / 2, y: icon.minY - frame.height - 6))
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
    // Clicks in other apps / the desktop close the panel, like a native menu bar extra.
    clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      self?.hidePanel()
    }
  }

  private func hidePanel() {
    orderOut(nil)
    if let monitor = clickOutsideMonitor {
      NSEvent.removeMonitor(monitor)
      clickOutsideMonitor = nil
    }
  }
}
