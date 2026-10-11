import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/constants/constants.dart';

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

/// GetLastError：获取当前线程最近一次的错误码
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

/// FindWindowW：按窗口标题查找顶层窗口
typedef _FindWindowWNative = IntPtr Function(
  Pointer<Utf16> lpClassName,
  Pointer<Utf16> lpWindowName,
);
typedef _FindWindowWDart = int Function(
  Pointer<Utf16> lpClassName,
  Pointer<Utf16> lpWindowName,
);

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

  /// ERROR_ALREADY_EXISTS：互斥体已存在，说明已有进程在运行
  static const int _errorAlreadyExists = 183;

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

  /// 获取当前线程最近一次的错误码
  static final _GetLastErrorDart _getLastError = _kernel32
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  /// 获取当前进程 ID
  static final _GetCurrentProcessIdDart _getCurrentProcessId = _kernel32
      .lookupFunction<_GetCurrentProcessIdNative, _GetCurrentProcessIdDart>(
          'GetCurrentProcessId');

  /// 关闭句柄
  static final _CloseHandleDart _closeHandle = _kernel32
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');

  /// 按窗口标题查找顶层窗口
  static final _FindWindowWDart _findWindow = _user32
      .lookupFunction<_FindWindowWNative, _FindWindowWDart>('FindWindowW');

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
    if (!Platform.isWindows) return true;

    // 已持有互斥体时直接返回成功，避免重复创建
    if (_mutexHandle != 0) return true;

    final namePtr = _mutexName.toNativeUtf16();
    try {
      final handle = _createMutex(nullptr, 0, namePtr);
      if (handle == 0) {
        // 创建互斥体失败时保守放行，避免因系统异常导致应用无法启动
        return true;
      }
      if (_getLastError() == _errorAlreadyExists) {
        // 互斥体已存在：若主窗口属于当前进程，说明只是当前进程重新执行了
        // main()（如开发时的热重启），旧句柄仍在本进程内打开导致互斥体残留，
        // 此时并非其它实例在运行，继续沿用本进程即可；
        // 否则视为已有其它实例在运行，释放多余句柄并返回失败
        if (!_isMainWindowOwnedByCurrentProcess()) {
          _closeHandle(handle);
          return false;
        }
        _mutexHandle = handle;
        return true;
      }
      _mutexHandle = handle;
      return true;
    } finally {
      calloc.free(namePtr);
    }
  }

  // ================= 主窗口查找 =================

  /// 按窗口标题查找主窗口句柄，未找到时返回 0
  int _findMainWindow() {
    final titlePtr = GlobalConstants.appTitle.toNativeUtf16();
    try {
      return _findWindow(nullptr, titlePtr);
    } finally {
      calloc.free(titlePtr);
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
    if (!Platform.isWindows) return;

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
