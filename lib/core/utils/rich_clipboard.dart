import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/utils/android_native.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:win32/win32.dart';

/// 剪贴板内容快照
class RichClipboardContent {
  const RichClipboardContent({this.text, this.html});

  /// 纯文本内容
  final String? text;

  /// HTML 片段（null 表示剪贴板不含富文本）
  final String? html;

  /// 是否没有任何内容
  bool get isEmpty =>
      (text == null || text!.isEmpty) && (html == null || html!.isEmpty);
}

/// 富文本剪贴板服务
///
/// Windows 下通过系统 "HTML Format" 格式读写，
/// 安卓下通过原生剪贴板的 `text/html` 读写，
/// macOS 下通过原生通道读写剪贴板的 `public.html` 类型，
/// 其他平台退回 [Clipboard] 的纯文本能力。
class RichClipboard {
  RichClipboard._();

  /// macOS 富文本剪贴板通道，与原生层保持一致
  static const MethodChannel _macOSChannel = MethodChannel(
    'quick_write/rich_clipboard',
  );

  /// 纯文本剪贴板格式标识
  static const int _cfUnicodeText = 13;

  /// 可移动全局内存标志
  static const int _gmemMovable = 0x0002;

  /// Windows HTML 剪贴板格式名
  static const String _htmlFormatName = 'HTML Format';

  /// 缓存的 HTML 剪贴板格式 ID（0 表示尚未注册）
  static int _htmlFormatId = 0;

  /// 写入剪贴板
  ///
  /// [htmlFragment] 非空时优先写入纯文本与 HTML，
  /// 写入失败或平台不支持时仅写入纯文本。
  static Future<void> write({
    required String plainText,
    String? htmlFragment,
  }) async {
    if (htmlFragment != null && htmlFragment.isNotEmpty) {
      if (PlatformCapabilities.isWindows &&
          await _writeWithHtml(plainText, htmlFragment)) {
        return;
      }
      if (PlatformCapabilities.isAndroid &&
          await AndroidNative.writeClipboardHtml(
            text: plainText,
            html: htmlFragment,
          )) {
        return;
      }
      if (PlatformCapabilities.isMacOS &&
          await _writeWithHtmlMacOS(plainText, htmlFragment)) {
        return;
      }
    }
    await Clipboard.setData(ClipboardData(text: plainText));
  }

  /// 读取剪贴板内容
  ///
  /// 同时返回纯文本与（Windows / 安卓 / macOS 下的）HTML 片段。
  static Future<RichClipboardContent> read() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);

    String? html;
    if (PlatformCapabilities.isWindows) {
      html = await _readHtml();
    } else if (PlatformCapabilities.isAndroid) {
      html = await AndroidNative.readClipboardHtml();
    } else if (PlatformCapabilities.isMacOS) {
      html = await _readHtmlMacOS();
    }

    return RichClipboardContent(text: data?.text, html: html);
  }

  // ================= Windows 实现 =================

  /// 获取 HTML 剪贴板格式 ID
  static int get _htmlFormat {
    if (_htmlFormatId == 0) {
      final Pointer<Utf16> name = _htmlFormatName.toNativeUtf16();
      try {
        _htmlFormatId = RegisterClipboardFormat(name);
      } finally {
        malloc.free(name);
      }
    }
    return _htmlFormatId;
  }

  /// 同时写入纯文本与 HTML，失败时重试以避开剪贴板被其他程序占用的情况
  static Future<bool> _writeWithHtml(
    String plainText,
    String htmlFragment,
  ) async {
    final List<int> htmlBytes = utf8.encode(_buildCfHtml(htmlFragment));
    for (var attempt = 0; attempt < 5; attempt++) {
      if (_writeFormats(plainText, htmlBytes)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  }

  /// 在已打开的剪贴板中写入两种格式
  static bool _writeFormats(String plainText, List<int> htmlBytes) {
    if (OpenClipboard(0) == 0) return false;
    try {
      if (EmptyClipboard() == 0) return false;

      // 纯文本：UTF-16LE，末尾补空字符
      final Pointer textMemory = GlobalAlloc(
        _gmemMovable,
        (plainText.length + 1) * 2,
      );
      if (textMemory.address == 0) return false;
      final Pointer<Uint16> textPointer = GlobalLock(textMemory).cast<Uint16>();
      if (textPointer.address == 0) {
        GlobalFree(textMemory);
        return false;
      }
      for (var i = 0; i < plainText.length; i++) {
        textPointer[i] = plainText.codeUnitAt(i);
      }
      textPointer[plainText.length] = 0;
      GlobalUnlock(textMemory);
      if (SetClipboardData(_cfUnicodeText, textMemory.address) == 0) {
        GlobalFree(textMemory);
        return false;
      }

      // HTML：UTF-8 编码的 CF_HTML 数据
      final Pointer htmlMemory = GlobalAlloc(_gmemMovable, htmlBytes.length);
      if (htmlMemory.address == 0) return false;
      final Pointer<Uint8> htmlPointer = GlobalLock(htmlMemory).cast<Uint8>();
      if (htmlPointer.address == 0) {
        GlobalFree(htmlMemory);
        return false;
      }
      for (var i = 0; i < htmlBytes.length; i++) {
        htmlPointer[i] = htmlBytes[i];
      }
      GlobalUnlock(htmlMemory);
      if (SetClipboardData(_htmlFormat, htmlMemory.address) == 0) {
        GlobalFree(htmlMemory);
        return false;
      }
      return true;
    } finally {
      CloseClipboard();
    }
  }

  /// 读取 HTML 剪贴板内容并提取片段部分
  static Future<String?> _readHtml() async {
    final int format = _htmlFormat;
    if (format == 0 || IsClipboardFormatAvailable(format) == 0) return null;

    for (var attempt = 0; attempt < 5; attempt++) {
      final String? html = _readHtmlOnce(format);
      if (html != null) return html;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return null;
  }

  /// 单次读取 HTML 剪贴板数据
  static String? _readHtmlOnce(int format) {
    if (OpenClipboard(0) == 0) return null;
    try {
      final int handle = GetClipboardData(format);
      if (handle == 0) return null;

      final Pointer<Uint8> pointer = Pointer<Uint8>.fromAddress(handle);
      final int size = GlobalSize(pointer);
      if (size <= 0) return null;

      final Pointer locked = GlobalLock(pointer);
      if (locked.address == 0) return null;
      try {
        // 在解锁前复制数据，避免指针失效
        final List<int> bytes = locked.cast<Uint8>().asTypedList(size).toList();
        return _extractFragment(bytes);
      } finally {
        GlobalUnlock(pointer);
      }
    } finally {
      CloseClipboard();
    }
  }

  /// 从 CF_HTML 数据中提取 HTML 片段
  ///
  /// 头部偏移量按字节计算，需在原始字节上截取后再解码。
  static String? _extractFragment(List<int> bytes) {
    if (bytes.isEmpty) return null;

    final int headerLength = bytes.length > 1024 ? 1024 : bytes.length;
    final String header = latin1.decode(bytes.sublist(0, headerLength));
    final RegExpMatch? startMatch = RegExp(
      r'StartFragment:\s*(\d+)',
    ).firstMatch(header);
    final RegExpMatch? endMatch = RegExp(
      r'EndFragment:\s*(\d+)',
    ).firstMatch(header);

    if (startMatch != null && endMatch != null) {
      final int start = int.parse(startMatch.group(1)!);
      final int end = int.parse(endMatch.group(1)!);
      if (start < end && end <= bytes.length) {
        return utf8.decode(bytes.sublist(start, end), allowMalformed: true);
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 构造 Windows CF_HTML 数据
  ///
  /// 头部各偏移量使用固定宽度，保证头部字节长度可预先确定。
  static String _buildCfHtml(String fragment) {
    const String prefix = '<html><body>\r\n<!--StartFragment-->';
    const String suffix = '<!--EndFragment-->\r\n</body></html>';

    // 所有偏移量固定为 10 位，占位头部的长度即最终头部长度
    const String placeholderHeader =
        'Version:0.9\r\n'
        'StartHTML:0000000000\r\n'
        'EndHTML:0000000000\r\n'
        'StartFragment:0000000000\r\n'
        'EndFragment:0000000000\r\n';

    final int headerLength = placeholderHeader.length;
    final int startFragment = headerLength + utf8.encode(prefix).length;
    final int endFragment = startFragment + utf8.encode(fragment).length;
    final int endHtml = endFragment + utf8.encode(suffix).length;

    final String header =
        'Version:0.9\r\n'
        'StartHTML:${_formatOffset(headerLength)}\r\n'
        'EndHTML:${_formatOffset(endHtml)}\r\n'
        'StartFragment:${_formatOffset(startFragment)}\r\n'
        'EndFragment:${_formatOffset(endFragment)}\r\n';

    return '$header$prefix$fragment$suffix';
  }

  /// 将偏移量格式化为 10 位数字
  static String _formatOffset(int offset) => offset.toString().padLeft(10, '0');

  // ================= macOS 实现 =================

  /// 同时写入纯文本与 HTML
  ///
  /// 把片段包装为完整 HTML 文档并声明 UTF-8 编码，
  /// 便于其他应用正确识别中文与文字样式
  static Future<bool> _writeWithHtmlMacOS(
    String plainText,
    String htmlFragment,
  ) async {
    final String html =
        '<html><head><meta charset="utf-8"></head>'
        '<body>$htmlFragment</body></html>';

    try {
      final bool? success = await _macOSChannel.invokeMethod<bool>(
        'writeHtml',
        {'text': plainText, 'html': html},
      );
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('写入 macOS HTML 剪贴板失败: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 读取剪贴板中的 HTML 内容
  ///
  /// 剪贴板不含 HTML 时返回 null，由调用方回退为纯文本
  static Future<String?> _readHtmlMacOS() async {
    try {
      return await _macOSChannel.invokeMethod<String>('readHtml');
    } on PlatformException catch (e) {
      debugPrint('读取 macOS HTML 剪贴板失败: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
