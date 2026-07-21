import 'package:flutter/material.dart';

/// 撤销/恢复记录
class UndoRecord {
  /// 变化前的状态
  final TextEditingValue before;
  
  /// 变化后的状态
  final TextEditingValue after;

  UndoRecord(this.before, this.after);
}

/// 自定义编辑器撤销/恢复管理器
/// 
/// 解决 Flutter 默认 UndoHistory 的几个痛点：
/// 1. 默认撤销会将光标恢复到上一个编辑块的末尾，导致跨行时光标/滚动条乱跳
/// 2. 默认撤销不支持恢复选区状态（比如替换选中文本后撤销，希望能重新选中那段文本）
class EditorUndoManager {
  final TextEditingController controller;
  
  /// 最大撤销层级
  final int maxUndoLevels;
  
  final List<UndoRecord> _undoStack = [];
  final List<UndoRecord> _redoStack = [];
  
  late TextEditingValue _lastValue;
  bool _isUndoRedoing = false;
  
  DateTime? _lastEditTime;

  EditorUndoManager({
    required this.controller,
    this.maxUndoLevels = 100,
  }) {
    _lastValue = controller.value;
    controller.addListener(_onChanged);
  }

  /// 外部调用此方法可清空历史记录（如刚加载完文件内容时调用）
  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _lastValue = controller.value;
    _lastEditTime = null;
  }

  void dispose() {
    controller.removeListener(_onChanged);
  }

  void _onChanged() {
    if (_isUndoRedoing) return;

    final currentValue = controller.value;
    
    // 仅在文本真正发生变化时才记录（光标移动不产生新的撤销记录）
    if (currentValue.text != _lastValue.text) {
      final now = DateTime.now();
      bool merged = false;
      
      // 尝试与上一次的编辑合并，以实现“连续输入只产生一次撤销”的效果
      if (_undoStack.isNotEmpty && _lastEditTime != null) {
        final timeDiff = now.difference(_lastEditTime!);
        
        // 合并条件：
        // 1. 两次编辑时间间隔小于 1 秒
        // 2. 光标没有被手动移动过（当前修改前的位置 == 上次修改后的位置）
        // 3. 修改前没有选中文本（即不是文本替换操作，替换操作应该单独记录以便撤销时恢复选中状态）
        if (timeDiff.inMilliseconds < 1000) {
          final lastRecord = _undoStack.last;
          
          if (_lastValue.selection == lastRecord.after.selection &&
              _lastValue.selection.isCollapsed) {
            
            // 修复 BUG：只允许同向操作合并（同为连续输入，或同为连续删除）
            // 如果刚输入（长度增加）就立即删除（长度减少），不能合并，否则会导致撤销记录被抵消，无法恢复被删的字。
            final int lastDelta = lastRecord.after.text.length - lastRecord.before.text.length;
            final int currentDelta = currentValue.text.length - _lastValue.text.length;
            
            if ((lastDelta > 0 && currentDelta > 0) || (lastDelta < 0 && currentDelta < 0)) {
              // 满足条件，合并记录（更新最后一条记录的 after 状态）
              _undoStack.last = UndoRecord(lastRecord.before, currentValue);
              merged = true;
            }
          }
        }
      }

      if (!merged) {
        // 新增一条撤销记录
        _undoStack.add(UndoRecord(_lastValue, currentValue));
        if (_undoStack.length > maxUndoLevels) {
          _undoStack.removeAt(0);
        }
      }
      
      // 一旦有新的修改，清空重做栈
      _redoStack.clear();
      _lastEditTime = now;
    }
    
    // 始终更新 _lastValue（包含了光标的移动），这样当下一次输入时，
    // before 状态就能准确记录输入前光标真正所在的位置！
    _lastValue = currentValue;
  }

  /// 撤销
  ///
  /// 返回值：true 表示成功执行了撤销操作；false 表示撤销栈为空，未执行任何操作
  bool undo() {
    if (_undoStack.isEmpty) return false;
    
    _isUndoRedoing = true;
    final record = _undoStack.removeLast();
    _redoStack.add(record);
    
    // 恢复到变化前的状态（包括文本和选区）
    TextSelection newSelection = record.before.selection;
    if (!newSelection.isValid) {
      newSelection = TextSelection.collapsed(offset: record.before.text.length);
    }
    
    // 关键修复：清除 composing 状态，防止输入法产生下划线残留
    controller.value = record.before.copyWith(
      composing: TextRange.empty,
      selection: newSelection,
    );
    _lastValue = controller.value;
    _isUndoRedoing = false;
    return true;
  }

  /// 重做
  ///
  /// 返回值：true 表示成功执行了重做操作；false 表示重做栈为空，未执行任何操作
  bool redo() {
    if (_redoStack.isEmpty) return false;
    
    _isUndoRedoing = true;
    final record = _redoStack.removeLast();
    _undoStack.add(record);
    
    // 恢复到变化后的状态
    TextSelection newSelection = record.after.selection;
    
    // 修复输入法（如中文）导致恢复时光标偏左的问题
    if (newSelection.isCollapsed) {
      newSelection = _calculateRedoCursorPosition(
        record.before.text, 
        record.after.text, 
        newSelection,
      );
    }

    if (!newSelection.isValid) {
      newSelection = TextSelection.collapsed(offset: record.after.text.length);
    }

    // 清除 composing 状态，防止输入法产生下划线残留
    controller.value = record.after.copyWith(
      composing: TextRange.empty,
      selection: newSelection,
    );
    _lastValue = controller.value;
    _isUndoRedoing = false;
    return true;
  }
  
  /// 计算 Redo 时的准确光标位置
  ///
  /// 中文输入法在 composing（带下划线状态）时，光标可能停在新增文字的前面或中间。
  /// 为了彻底解决这个问题，如果不处于多选状态（isCollapsed），就强制把光标推到这部分“新增/替换文字”的末尾。
  TextSelection _calculateRedoCursorPosition(String beforeText, String afterText, TextSelection currentSelection) {
    // 找到 before 和 after 的差异点，算出新增的那段文本有多长
    int commonPrefixLength = 0;
    final int minLength = beforeText.length < afterText.length ? beforeText.length : afterText.length;
    
    while (commonPrefixLength < minLength && 
           beforeText[commonPrefixLength] == afterText[commonPrefixLength]) {
      commonPrefixLength++;
    }
    
    // 如果发生了文本插入、追加或替换，强制将光标移到差异段的末尾
    if (afterText.length != beforeText.length || beforeText != afterText) {
      int commonSuffixLength = 0;
      final int maxSuffix = minLength - commonPrefixLength;
      while (commonSuffixLength < maxSuffix && 
             beforeText[beforeText.length - 1 - commonSuffixLength] == afterText[afterText.length - 1 - commonSuffixLength]) {
        commonSuffixLength++;
      }
      
      final int changeEndIndex = afterText.length - commonSuffixLength;
      
      // 为了防止破坏正常的光标逻辑，只在“历史光标落后于新增文字末尾”时，才将它往前推（修复左侧偏移）
      final String insertedText = afterText.substring(commonPrefixLength, changeEndIndex);
      
      // 修复 BUG：如果没有新增文本（即纯删除操作），不需要修复光标，保持原样即可。
      // 这修复了在空行按 delete 删除时，由于贪婪匹配导致光标错误跳到下一行开头的问题。
      if (insertedText.isEmpty) {
        return currentSelection;
      }
      
      // 并且，如果新增的仅仅是由空白字符（换行符、空格等）组成的纯空白串，且不是替换操作（即单纯的插入空白），
      // 或许系统原本的记录就是正确的，不进行干预。
      // 这修复了：1. 单个回车时光标乱跳；2. 粘贴或恢复多个空行时光标跑到下一行开头的问题。
      final bool isPureWhitespaceInsert = insertedText.trim().isEmpty && afterText.length == beforeText.length + insertedText.length;
      
      if (!isPureWhitespaceInsert && currentSelection.baseOffset < changeEndIndex) {
         return TextSelection.collapsed(offset: changeEndIndex);
      }
    }
    
    return currentSelection;
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
}
