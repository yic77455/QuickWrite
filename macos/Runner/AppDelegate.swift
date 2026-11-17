import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 应用退出通道名称，需与 Dart 侧保持一致
  private static let lifecycleChannelName = "quick_write/app_lifecycle"

  /// 富文本剪贴板通道名称，需与 Dart 侧保持一致
  private static let clipboardChannelName = "quick_write/rich_clipboard"

  /// 应用退出通道，用于把系统终止请求转交 Dart 处理
  private var lifecycleChannel: FlutterMethodChannel?

  /// Dart 是否已注册退出处理，未注册时直接放行系统退出
  private var isQuitHandlerReady = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // 先让父类完成默认初始化（其中会把菜单里的 APP_NAME 替换为产品名）
    super.applicationDidFinishLaunching(notification)

    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      registerLifecycleChannel(with: controller.engine.binaryMessenger)
    }
    // 富文本剪贴板通道需要在每个 engine 上注册（主窗口 + 各子窗口），
    // 故用静态方法，供 MainFlutterWindow 的子窗口回调复用。
    AppDelegate.registerClipboardChannel(with: flutterViewControllerEngineMessenger())
    configureApplicationMenu()
  }

  /// 取主窗口 engine 的 binaryMessenger，供静态通道注册使用
  private func flutterViewControllerEngineMessenger() -> FlutterBinaryMessenger? {
    return (mainFlutterWindow?.contentViewController as? FlutterViewController)?
      .engine.binaryMessenger
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // ================= 退出通道 =================

  /// 注册应用退出通道
  ///
  /// 系统菜单的退出请求先经过这里，Dart 完成窗口关闭与退出同步后再结束进程
  private func registerLifecycleChannel(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: AppDelegate.lifecycleChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      // Dart 完成注册后，系统退出请求才转交 Dart 处理
      if call.method == "ready" {
        self?.isQuitHandlerReady = true
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    lifecycleChannel = channel
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Dart 尚未接管退出流程时直接放行，避免应用无法退出
    guard isQuitHandlerReady, let channel = lifecycleChannel else {
      return .terminateNow
    }

    // 有可见窗口时把退出流程交给 Dart 逐个保存。
    // 注意：工作台子窗口是 desktop_multi_window 创建的 CustomWindow，
    // 并非 MainFlutterWindow，不能只判断 MainFlutterWindow 类型，
    // 否则主窗口隐藏到托盘、子窗口仍可见时会误判为无窗口而跳过保存。
    let hasVisibleWindow = sender.windows.contains { window in
      window.isVisible && window.contentViewController is FlutterViewController
    }
    guard hasVisibleWindow else {
      return .terminateNow
    }

    // 转交 Dart 依次关闭工作台窗口、完成退出同步后再结束进程
    channel.invokeMethod("requestQuit", arguments: nil)
    return .terminateCancel
  }

  /// 点击 Dock 图标时恢复已隐藏的主窗口
  ///
  /// 窗口隐藏到菜单栏后，系统无法直接激活窗口，需要转交 Dart 重新显示
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    // 有可见窗口时交由系统正常激活应用
    guard !flag else { return true }

    // 优先交给 Dart 显示主窗口，保证窗口与界面状态同步
    if isQuitHandlerReady, let channel = lifecycleChannel {
      channel.invokeMethod("showMainWindow", arguments: nil)
      return true
    }

    // Dart 尚未就绪时直接恢复主窗口
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    return true
  }

  // ================= 应用菜单 =================

  /// 配置应用菜单的文案与命令
  ///
  /// 模板菜单中的文案由父类替换为英文产品名，这里统一改为中文，
  /// 并把设置与关于入口转交 Dart，打开应用内的对应页面
  private func configureApplicationMenu() {
    guard let appMenu = NSApplication.shared.mainMenu?.items.first?.submenu else {
      return
    }

    for item in appMenu.items {
      if item.title.hasPrefix("About") {
        item.title = "关于 快码字"
        item.target = self
        item.action = #selector(showAboutPage(_:))
      } else if item.title.hasPrefix("Preferences") {
        item.title = "设置…"
        item.target = self
        item.action = #selector(openSettingsPage(_:))
      } else if item.title.hasPrefix("Services") {
        item.title = "服务"
      } else if item.title.hasPrefix("Hide Other") {
        item.title = "隐藏其他"
      } else if item.title.hasPrefix("Hide") {
        item.title = "隐藏 快码字"
      } else if item.title.hasPrefix("Show All") {
        item.title = "显示全部"
      } else if item.title.hasPrefix("Quit") {
        item.title = "退出 快码字"
      }
    }
  }

  /// 打开应用内的关于页
  @objc private func showAboutPage(_ sender: Any?) {
    lifecycleChannel?.invokeMethod("openAbout", arguments: nil)
  }

  /// 打开应用内的设置页
  @objc private func openSettingsPage(_ sender: Any?) {
    lifecycleChannel?.invokeMethod("openSettings", arguments: nil)
  }

  // ================= 剪贴板通道 =================

  /// 注册富文本剪贴板通道（静态方法，主窗口与子窗口共用）
  ///
  /// Dart 侧通过该通道读写剪贴板中的 HTML，用于大纲编辑器的富文本复制粘贴。
  /// MethodChannel 不跨 engine 共享，故每个子窗口都要单独注册。
  static func registerClipboardChannel(with messenger: FlutterBinaryMessenger?) {
    guard let messenger = messenger else { return }
    let channel = FlutterMethodChannel(
      name: clipboardChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "writeHtml":
        result(AppDelegate.writeHtmlClipboard(call.arguments))
      case "readHtml":
        result(AppDelegate.readHtmlClipboard())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 将纯文本与 HTML 同时写入剪贴板
  ///
  /// 返回 HTML 是否写入成功，失败时由 Dart 侧退回纯文本写入
  private static func writeHtmlClipboard(_ arguments: Any?) -> Bool {
    guard let arguments = arguments as? [String: Any],
          let text = arguments["text"] as? String,
          let html = arguments["html"] as? String else {
      return false
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    return pasteboard.setString(html, forType: .html)
  }

  /// 读取剪贴板中的 HTML 内容
  ///
  /// 剪贴板不含 HTML 时返回空，由 Dart 侧回退为纯文本
  private static func readHtmlClipboard() -> String? {
    let pasteboard = NSPasteboard.general
    guard let data = pasteboard.data(forType: .html) else {
      return pasteboard.string(forType: .html)
    }
    if let text = String(data: data, encoding: .utf8) {
      return text
    }
    return String(data: data, encoding: .isoLatin1)
  }
}
