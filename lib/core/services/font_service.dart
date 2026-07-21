import 'dart:async';
import 'package:quick_write/core/utils/font_parser.dart';

class FontService {
  static final FontService _instance = FontService._internal();
  factory FontService() => _instance;
  
  FontService._internal();
  
  List<FontInfo> _systemFonts = [];
  bool _isLoading = false;
  Completer<void>? _loadCompleter;
  
  /// 系统字体列表
  List<FontInfo> get systemFonts => _systemFonts;
  
  /// 是否正在加载字体
  bool get isLoading => _isLoading;
  
  /// 初始化字体服务
  Future<void> initialize() async {
    if (_isLoading) {
      // 如果正在加载，等待加载完成
      return _loadCompleter?.future;
    }
    
    if (_systemFonts.isNotEmpty) {
      // 已经加载过，直接返回
      return;
    }
    
    _isLoading = true;
    _loadCompleter = Completer<void>();
    
    try {
      // 加载系统字体
      _systemFonts = await SystemFontParser.getSystemFonts();
      _loadCompleter?.complete();
    } catch (e) {
      // 加载失败，使用空列表
      _systemFonts = [];
      _loadCompleter?.complete();
    } finally {
      _isLoading = false;
      _loadCompleter = null;
    }
  }
  
  /// 刷新字体列表
  Future<void> refreshFonts() async {
    _isLoading = true;
    _loadCompleter = Completer<void>();
    
    try {
      // 重新加载系统字体
      _systemFonts = await SystemFontParser.getSystemFonts();
      _loadCompleter?.complete();
    } catch (e) {
      // 加载失败，保持原有列表
      _loadCompleter?.complete();
    } finally {
      _isLoading = false;
      _loadCompleter = null;
    }
  }
  
  /// 根据字体家族名称获取字体信息
  FontInfo? getFontByFamily(String fontFamily) {
    try {
      return _systemFonts.firstWhere(
        (font) => font.fontFamily == fontFamily,
      );
    } catch (e) {
      return null;
    }
  }
  
  /// 根据显示名称获取字体信息
  List<FontInfo> getFontsByDisplayName(String displayName) {
    return _systemFonts.where(
      (font) => font.displayName == displayName,
    ).toList();
  }
}
