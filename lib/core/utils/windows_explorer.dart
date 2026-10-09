import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

typedef _CoInitializeExNative = Int32 Function(Pointer<Void>, Uint32);
typedef _CoInitializeExDart = int Function(Pointer<Void>, int);
typedef _CoUninitializeNative = Void Function();
typedef _CoUninitializeDart = void Function();
typedef _ILCreateFromPathNative = Pointer<Void> Function(Pointer<Utf16>);
typedef _ILCreateFromPathDart = Pointer<Void> Function(Pointer<Utf16>);
typedef _ILFindLastIdNative = Pointer<Void> Function(Pointer<Void>);
typedef _ILFindLastIdDart = Pointer<Void> Function(Pointer<Void>);
typedef _ILFreeNative = Void Function(Pointer<Void>);
typedef _ILFreeDart = void Function(Pointer<Void>);
typedef _SHOpenFolderAndSelectItemsNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Pointer<Void>>,
  Uint32,
);
typedef _SHOpenFolderAndSelectItemsDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Pointer<Void>>,
  int,
);

/// Windows 资源管理器定位工具
///
/// 通过 shell 接口打开资源管理器并选中条目。相较 explorer 命令行的 /select 只能
/// 选中单个条目，这里可一次性选中同一目录下的多个条目，便于用户集中处理冲突副本。
class WindowsExplorer {
  WindowsExplorer._();

  /// COINIT_APARTMENTTHREADED，以单线程套间方式初始化 COM
  static const int _coinitApartmentThreaded = 0x2;

  /// HRESULT 成功值 S_OK
  static const int _sOk = 0;

  static final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
  static final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');

  static final _CoInitializeExDart _coInitializeEx =
      _ole32.lookupFunction<_CoInitializeExNative, _CoInitializeExDart>(
          'CoInitializeEx');
  static final _CoUninitializeDart _coUninitialize =
      _ole32.lookupFunction<_CoUninitializeNative, _CoUninitializeDart>(
          'CoUninitialize');
  static final _ILCreateFromPathDart _ilCreateFromPath =
      _shell32.lookupFunction<_ILCreateFromPathNative, _ILCreateFromPathDart>(
          'ILCreateFromPathW');
  static final _ILFindLastIdDart _ilFindLastId =
      _shell32.lookupFunction<_ILFindLastIdNative, _ILFindLastIdDart>(
          'ILFindLastID');
  static final _ILFreeDart _ilFree =
      _shell32.lookupFunction<_ILFreeNative, _ILFreeDart>('ILFree');
  static final _SHOpenFolderAndSelectItemsDart _shOpenFolderAndSelectItems =
      _shell32.lookupFunction<_SHOpenFolderAndSelectItemsNative,
          _SHOpenFolderAndSelectItemsDart>('SHOpenFolderAndSelectItems');

  /// 在资源管理器中定位并选中给定路径
  ///
  /// [paths] 待定位的路径列表。存在多个路径时按所在目录分组，
  /// 同一目录的条目会在同一个资源管理器窗口中被一起选中；
  /// 全部失败时返回 false
  static bool revealAll(List<String> paths) {
    try {
      // 按所在目录分组，使同目录的条目能够在同一窗口内被一起选中
      final groups = <String, List<String>>{};
      for (final path in paths) {
        if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
          continue;
        }
        groups.putIfAbsent(p.dirname(path), () => []).add(path);
      }
      if (groups.isEmpty) return false;

      var success = false;
      for (final entry in groups.entries) {
        success = _openAndSelect(entry.key, entry.value) || success;
      }
      return success;
    } catch (e) {
      debugPrint('调用 shell 接口定位失败: $e');
      return false;
    }
  }

  /// 打开 [directory] 对应的资源管理器窗口，并选中其中的 [items]
  ///
  /// 返回是否成功发起定位
  static bool _openAndSelect(String directory, List<String> items) {
    final needsUninitialize = _coInitialize();
    try {
      final folderPidl = _createPidl(directory);
      if (folderPidl == nullptr) return false;

      final itemPidls = <Pointer<Void>>[];
      try {
        for (final item in items) {
          final pidl = _createPidl(item);
          if (pidl != nullptr) itemPidls.add(pidl);
        }
        if (itemPidls.isEmpty) return false;

        // 子项数组需填写相对父目录的子项 PIDL，这里取各项完整 PIDL 的最后一段
        final childArray = calloc<Pointer<Void>>(itemPidls.length);
        try {
          for (var i = 0; i < itemPidls.length; i++) {
            childArray[i] = _ilFindLastId(itemPidls[i]);
          }
          final hr = _shOpenFolderAndSelectItems(
            folderPidl,
            itemPidls.length,
            childArray,
            0,
          );
          return hr == _sOk;
        } finally {
          calloc.free(childArray);
        }
      } finally {
        for (final pidl in itemPidls) {
          _ilFree(pidl);
        }
        _ilFree(folderPidl);
      }
    } catch (e) {
      debugPrint('定位资源管理器条目失败: $e');
      return false;
    } finally {
      // 仅当本次调用完成了 COM 初始化时才配对反初始化
      if (needsUninitialize) {
        try {
          _coUninitialize();
        } catch (_) {}
      }
    }
  }

  /// 将路径转换为 shell 的 PIDL
  ///
  /// 失败时返回空指针
  static Pointer<Void> _createPidl(String path) {
    final pathPtr = path.toNativeUtf16();
    try {
      return _ilCreateFromPath(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// 初始化 COM
  ///
  /// 返回 true 表示本次调用完成初始化，需要配对调用反初始化；
  /// 线程已初始化（S_FALSE）或处于其他套间模式时返回 false
  static bool _coInitialize() {
    try {
      return _coInitializeEx(nullptr, _coinitApartmentThreaded) == _sOk;
    } catch (e) {
      debugPrint('初始化 COM 失败: $e');
      return false;
    }
  }
}