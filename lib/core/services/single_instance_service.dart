import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';

// ================= Win32 API 函数签名 =================

/// CreateMutexW：创建或打开一个命名互斥体
typedef _CreateMutexWNative = IntPtr Function(
  Pointer<Void> lpMutexAttributes,
  Int32 bInitialOwner,
  Pointer<Utf16> lpName,
);
typedef _CreateMutexWDart = int Function(
  Pointer<Void> lpMutexAttributes,
  int bInitialOwner,
  Pointer<Utf16> lpName,
);

/// ReleaseMutex：释放对互斥体的所有权，返回值可用于判断调用前是否拥有该互斥体
typedef _ReleaseMutexNative = Int32 Function(IntPtr hMutex);
typedef _ReleaseMutexDart = int Function(int hMutex);

/// EnumWindows 的枚举回调：返回非零继续枚举，返回零停止
typedef _EnumWindowsProcNative = Int32 Function(IntPtr hWnd, IntPtr lParam);

/// EnumWindows：枚举系统所有顶层窗口
typedef _EnumWindowsNative = Int32 Function(
  Pointer<NativeFunction<_EnumWindowsProcNative>> lpEnumFunc,
  IntPtr lParam,
);
typedef _EnumWindowsDart = int Function(
  Pointer<NativeFunction<_EnumWindowsProcNative>> lpEnumFunc,
  int lParam,
);

/// GetWindowTextW：将窗口标题写入缓冲区，返回实际复制的字符数
typedef _GetWindowTextWNative = Int32 Function(
  IntPtr hWnd,
  Pointer<Utf16> lpString,
  Int32 nMaxCount,
);
typedef _GetWindowTextWDart = int Function(
  int hWnd,
  Pointer<Utf16> lpString,
  int nMaxCount,
);

/// GetWindowTextLengthW：获取窗口标题的字符数
typedef _GetWindowTextLengthWNative = Int32 Function(IntPtr hWnd);
typedef _GetWindowTextLengthWDart = int Function(int hWnd);

/// IsIconic：判断窗口是否处于最小化状态
typedef _IsIconicNative = Int32 Function(IntPtr hWnd);
typedef _IsIconicDart = int Function(int hWnd);

/// ShowWindow：设置窗口的显示状态
typedef _ShowWindowNative = Int32 Function(IntPtr hWnd, Int32 nCmdShow);
typedef _ShowWindowDart = int Function(int hWnd, int nCmdShow);

/// SetForegroundWindow：将窗口置于前台并激活
typedef _SetForegroundWindowNative = Int32 Function(IntPtr hWnd);
typedef _SetForegroundWindowDart = int Function(int hWnd);

/// CloseHandle：关闭内核对象句柄
typedef _CloseHandleNative = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

/// GetWindowThreadProcessId：获取窗口所属的进程 ID
typedef _GetWindowThreadProcessIdNative = Uint32 Function(
  IntPtr hWnd,
  Pointer<Uint32> lpdwProcessId,
);
typedef _GetWindowThreadProcessIdDart = int Function(
  int hWnd,
  Pointer<Uint32> lpdwProcessId,
);

/// GetCurrentProcessId：获取当前进程 ID
typedef _GetCurrentProcessIdNative = Uint32 Function();
typedef _GetCurrentProcessIdDart = int Function();

/// 单实例服务
///
/// 通过 Windows 命名互斥体限制同一时刻只运行一个程序进程：
/// - 首次启动时成功创建互斥体，正常继续运行
/// - 再次启动时检测到互斥体已存在，唤出已在运行的主窗口后退出当前进程
///
/// 互斥体句柄在进程运行期间保持持有，进程结束后由系统自动释放
class SingleInstanceService {
  // ================= 单例模式 =================

  static final SingleInstanceService instance = SingleInstanceService._internal();
  SingleInstanceService._internal();

  // ================= 常量定义 =================

  /// 单实例互斥体名称，用于标识本应用（同一用户会话下唯一）
  static const String _mutexName = 'QuickWrite_SingleInstance_Mutex';

  /// SW_RESTORE：还原被最小化的窗口
  static const int _swRestore = 9;

  /// SW_SHOW：以窗口当前的大小和位置显示窗口
  static const int _swShow = 5;

  // ================= Win32 函数绑定 =================

  /// kernel32 动态库（首次访问时加载，非 Windows 平台不会触发）
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  /// user32 动态库（窗口相关接口均来自该库）
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

  /// 创建或打开命名互斥体
  static final _CreateMutexWDart _createMutex = _kernel32
      .lookupFunction<_CreateMutexWNative, _CreateMutexWDart>('CreateMutexW');

  /// 释放互斥体所有权；返回非零表示调用前本进程拥有该互斥体
  static final _ReleaseMutexDart _releaseMutex = _kernel32
      .lookupFunction<_ReleaseMutexNative, _ReleaseMutexDart>('ReleaseMutex');

  /// 获取当前进程 ID
  static final _GetCurrentProcessIdDart _getCurrentProcessId = _kernel32
      .lookupFunction<_GetCurrentProcessIdNative, _GetCurrentProcessIdDart>(
          'GetCurrentProcessId');

  /// 关闭句柄
  static final _CloseHandleDart _closeHandle = _kernel32
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');

  /// 枚举系统所有顶层窗口
  static final _EnumWindowsDart _enumWindows = _user32
      .lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows');

  /// 读取指定窗口的标题文本
  static final _GetWindowTextWDart _getWindowText = _user32
      .lookupFunction<_GetWindowTextWNative, _GetWindowTextWDart>(
          'GetWindowTextW');

  /// 获取指定窗口标题的字符数
  static final _GetWindowTextLengthWDart _getWindowTextLength = _user32
      .lookupFunction<_GetWindowTextLengthWNative, _GetWindowTextLengthWDart>(
          'GetWindowTextLengthW');

  /// 获取窗口所属的进程 ID
  static final _GetWindowThreadProcessIdDart _getWindowThreadProcessId = _user32
      .lookupFunction<_GetWindowThreadProcessIdNative,
          _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');

  /// 判断窗口是否最小化
  static final _IsIconicDart _isIconic = _user32
      .lookupFunction<_IsIconicNative, _IsIconicDart>('IsIconic');

  /// 设置窗口显示状态
  static final _ShowWindowDart _showWindow = _user32
      .lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow');

  /// 激活窗口并置于前台
  static final _SetForegroundWindowDart _setForegroundWindow = _user32
      .lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>(
          'SetForegroundWindow');

  // ================= 状态属性 =================

  /// 互斥体句柄，进程运行期间保持持有以维持单实例约束
  int _mutexHandle = 0;

  // ================= 单实例锁 =================

  /// 尝试获取单实例锁
  ///
  /// 返回 true 表示当前是唯一运行的进程（可继续启动）；
  /// 返回 false 表示已有进程在运行（当前进程应退出）
  bool tryAcquire() {
    if (!PlatformCapabilities.supportsSingleInstanceLock) return true;

    // 已持有互斥体时直接返回成功，避免重复创建
    if (_mutexHandle != 0) return true;

    final namePtr = _mutexName.toNativeUtf16();
    try {
      // bInitialOwner = TRUE：新建互斥体时本进程成为所有者；
      // 若互斥体已存在则本进程不会成为所有者，可据此判断是否为首个实例
      final handle = _createMutex(nullptr, 1, namePtr);
      if (handle == 0) {
        // 创建互斥体失败时保守放行，避免因系统异常导致应用无法启动
        return true;
      }
      // 释放所有权：返回非零表示此前本进程拥有该互斥体（即新建成功、当前为首个实例）；
      // 返回零表示互斥体此前已存在（已有其它实例在运行）。
      // 该判断依赖 ReleaseMutex 的直接返回值，不依赖易被 FFI 层清除的 GetLastError。
      final owned = _releaseMutex(handle) != 0;
      if (owned) {
        // 成功创建互斥体，当前进程是首个实例，保留句柄以维持互斥体存活
        _mutexHandle = handle;
        return true;
      }
      // 互斥体已存在
      if (_isMainWindowOwnedByCurrentProcess()) {
        // 主窗口属于当前进程：属于同进程内的热重启，保留句柄并继续运行
        _mutexHandle = handle;
        return true;
      }
      // 已有其它实例在运行，释放多余句柄并返回失败
      _closeHandle(handle);
      return false;
    } finally {
      calloc.free(namePtr);
    }
  }

  // ================= 主窗口查找 =================

  /// 查找主窗口句柄，未找到时返回 0
  ///
  /// 主窗口标题会随打开的作品变化（如「《书名》 - 快码字」），
  /// 因此不能按固定标题精确匹配。这里枚举所有顶层窗口，
  /// 优先返回标题与应用标题完全一致的窗口，其次返回标题中包含应用标题的窗口
  int _findMainWindow() {
    // 精确匹配的窗口句柄（标题即为应用标题）
    int exactMatch = 0;
    // 包含匹配的窗口句柄（标题中含有应用标题，如带作品名的主窗口）
    int partialMatch = 0;

    final callback = NativeCallable<_EnumWindowsProcNative>.isolateLocal(
      (int hWnd, int _) {
        final title = _getWindowTitle(hWnd);
        // 跳过没有标题的窗口（如各类系统隐藏窗口）
        if (title.isEmpty) return 1;

        if (title == GlobalConstants.appTitle) {
          exactMatch = hWnd;
          return 0; // 已找到精确匹配，无需继续枚举
        }
        if (partialMatch == 0 && title.contains(GlobalConstants.appTitle)) {
          partialMatch = hWnd;
        }
        return 1;
      },
      exceptionalReturn: 0,
    );

    try {
      _enumWindows(callback.nativeFunction, 0);
    } finally {
      callback.close();
    }

    return exactMatch != 0 ? exactMatch : partialMatch;
  }

  /// 读取指定窗口的标题文本，无标题或读取失败时返回空字符串
  String _getWindowTitle(int hWnd) {
    final length = _getWindowTextLength(hWnd);
    if (length <= 0) return '';

    final buffer = calloc<Uint16>(length + 1).cast<Utf16>();
    try {
      final copied = _getWindowText(hWnd, buffer, length + 1);
      return copied <= 0 ? '' : buffer.toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  /// 判断已存在的主窗口是否属于当前进程
  ///
  /// 主窗口属于当前进程说明并非其它实例在运行，而是当前进程自身（如开发时的热重启）
  bool _isMainWindowOwnedByCurrentProcess() {
    final hWnd = _findMainWindow();
    if (hWnd == 0) return false;

    final pidPtr = calloc<Uint32>();
    try {
      _getWindowThreadProcessId(hWnd, pidPtr);
      return pidPtr.value == _getCurrentProcessId();
    } finally {
      calloc.free(pidPtr);
    }
  }

  // ================= 唤出已有窗口 =================

  /// 唤出已在运行的主窗口
  ///
  /// 按窗口标题查找主窗口，若已最小化则还原，并将其置于前台
  void activateExistingMainWindow() {
    if (!PlatformCapabilities.supportsSingleInstanceLock) return;

    try {
      final hWnd = _findMainWindow();
      if (hWnd == 0) return;

      // 最小化的窗口需要先还原，其余情况直接显示
      _showWindow(hWnd, _isIconic(hWnd) != 0 ? _swRestore : _swShow);
      _setForegroundWindow(hWnd);
    } catch (e) {
      debugPrint('唤出已有主窗口失败: $e');
    }
  }
}
