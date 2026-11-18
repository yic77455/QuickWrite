import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 应用退出通道名称，需与 Dart 侧保持一致
  private static let lifecycleChannelName = "quick_write/app_lifecycle"

  /// 富文本剪贴板通道名称，需与 Dart 侧保持一致
  private static let clipboardChannelName = "quick_write/rich_clipboard"

  /// 应用退出通道，用于把系统终止请求转交 Dart
  private var lifecycleChannel: FlutterMethodChannel?

  /// Dart 是否已注册退出处理
  private var isQuitHandlerReady = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // 父类初始化会把菜单里的 APP_NAME 替换为产品名
    super.applicationDidFinishLaunching(notification)

    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      registerLifecycleChannel(with: controller.engine.binaryMessenger)
    }
    // 每个 engine 都要注册，故用静态方法供子窗口回调复用
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

  /// 注册退出通道，把系统退出请求转交 Dart
  private func registerLifecycleChannel(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: AppDelegate.lifecycleChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
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
    // Dart 未接管退出流程时直接放行
    guard isQuitHandlerReady, let channel = lifecycleChannel else {
      return .terminateNow
    }

    // 子窗口是 CustomWindow 而非 MainFlutterWindow，主窗口隐藏到托盘时不能漏判
    let hasVisibleWindow = sender.windows.contains { window in
      window.isVisible && window.contentViewController is FlutterViewController
    }
    guard hasVisibleWindow else {
      return .terminateNow
    }

    channel.invokeMethod("requestQuit", arguments: nil)
    return .terminateCancel
  }

  /// 点击 Dock 图标时转交 Dart 恢复已隐藏的主窗口
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    // 有可见窗口时交由系统正常激活
    guard !flag else { return true }

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

  /// 菜单标题的英文→中文映射，仅中文系统下使用
  private static let menuTitleMap: [String: String] = [
    // 顶层菜单
    "QuickWrite": "快码字",
    "Edit": "编辑",
    "View": "显示",
    "Window": "窗口",
    "Help": "帮助",
    // Edit 子菜单
    "Undo": "撤销",
    "Redo": "重做",
    "Cut": "剪切",
    "Copy": "拷贝",
    "Paste": "粘贴",
    "Paste and Match Style": "粘贴并匹配样式",
    "Delete": "删除",
    "Select All": "全选",
    "Spelling and Grammar": "拼写与语法",
    "Show Spelling and Grammar": "显示拼写与语法",
    "Check Document Now": "立即检查文稿",
    "Check Spelling While Typing": "键入时检查拼写",
    "Check Grammar With Spelling": "检查语法与拼写",
    "Correct Spelling Automatically": "自动纠正拼写",
    "Substitutions": "替换",
    "Show Substitutions": "显示替换",
    "Smart Copy/Paste": "智能拷贝/粘贴",
    "Smart Quotes": "智能引号",
    "Smart Dashes": "智能破折号",
    "Smart Links": "智能链接",
    "Data Detectors": "数据检测器",
    "Text Replacement": "文本替换",
    "Transformations": "转换",
    "Make Upper Case": "大写",
    "Make Lower Case": "小写",
    "Capitalize": "首字母大写",
    "Speech": "语音",
    "Start Speaking": "开始朗读",
    "Stop Speaking": "停止朗读",
    // View 子菜单
    "Enter Full Screen": "进入全屏",
    // Window 子菜单
    "Minimize": "最小化",
    "Zoom": "缩放",
    "Bring All to Front": "全部置于顶层",
  ]

  /// 递归汉化菜单标题，不改 action、target 和快捷键
  private func localizeMenuTitles(_ menu: NSMenu) {
    for item in menu.items {
      if let chinese = Self.menuTitleMap[item.title] {
        item.title = chinese
      }
      if let submenu = item.submenu {
        localizeMenuTitles(submenu)
      }
    }
  }

  /// 配置菜单：中文系统汉化标题，关于/设置入口转交 Dart
  private func configureApplicationMenu() {
    guard let mainMenu = NSApplication.shared.mainMenu, !mainMenu.items.isEmpty else {
      return
    }

    // 用系统首选语言判断；preferredLocalizations 只有 Base 会失效，Language API 需 macOS 13
    let preferredLanguage = Locale.preferredLanguages.first ?? ""
    let isChineseSystem = preferredLanguage.hasPrefix("zh")

    // 关于/设置的 action 始终转交 Dart，标题仅中文系统下汉化
    if let appMenu = mainMenu.items[0].submenu {
      for item in appMenu.items {
        if item.title.hasPrefix("About") {
          if isChineseSystem { item.title = "关于 快码字" }
          item.target = self
          item.action = #selector(showAboutPage(_:))
        } else if item.title.hasPrefix("Preferences") {
          if isChineseSystem { item.title = "设置…" }
          item.target = self
          item.action = #selector(openSettingsPage(_:))
        } else if isChineseSystem {
          // 其余系统项只汉化文字，action 由系统保留
          if item.title.hasPrefix("Services") {
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
    }

    // Edit 项是 NSTextView 专用、Help 为空，用 isHidden 隐藏以保留菜单结构
    if mainMenu.items.count > 4 {
      mainMenu.items[1].isHidden = true   // Edit
      mainMenu.items[4].isHidden = true   // Help
    }

    if isChineseSystem {
      localizeMenuTitles(mainMenu)
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

  /// 注册富文本剪贴板通道；MethodChannel 不跨 engine，故每个窗口单独注册
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

  /// 写入纯文本与 HTML，返回 HTML 是否写入成功
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

  /// 读取剪贴板 HTML，不含时返回空
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
