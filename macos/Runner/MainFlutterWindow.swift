import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // desktop_multi_window 的每个子窗口都有独立的 Flutter engine，
    // MethodChannel 不共享，必须为每个新窗口单独注册插件，
    // 否则子窗口内的 isar / path_provider / window_manager 等会抛 MissingPluginException。
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      // 富文本剪贴板通道不跨 engine 共享，子窗口需单独注册，
      // 否则工作台里的大纲富文本复制粘贴会失效。
      AppDelegate.registerClipboardChannel(with: controller.engine.binaryMessenger)
    }

    super.awakeFromNib()
  }
}
