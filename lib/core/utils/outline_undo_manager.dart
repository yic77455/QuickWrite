import 'package:flutter/material.dart';
import 'package:quick_write/core/models/outline_models.dart';

/// 大纲编辑器完整状态快照
///
/// 捕获某一时刻大纲编辑器的所有状态，用于撤销/恢复。
/// 包含树结构、焦点、选区等全部 UI 状态，确保撤销后能完整恢复。
class OutlineTreeSnapshot {
  /// 根节点列表的深拷贝
  final List<OutlineNode> roots;

  /// 当前焦点所在节点的 ID
  final String? focusedNodeId;

  /// 焦点节点的文本选区
  final TextSelection? focusedSelection;

  /// 多节点选中的节点 ID 集合
  final Set<String> selectedNodeIds;

  /// 全选级别（0=未全选，1=主题，2=文档）
  final int selectAllLevel;

  /// 选区锚点索引（Shift+click 扩展选区时的起始点）
  final int? selectionAnchorIndex;

  OutlineTreeSnapshot({
    required this.roots,
    this.focusedNodeId,
    this.focusedSelection,
    required this.selectedNodeIds,
    required this.selectAllLevel,
    this.selectionAnchorIndex,
  });
}

/// 撤销/恢复操作
///
/// 纯快照模式：每个操作只记录前后两个快照。
/// - 撤销 = 应用 before 快照
/// - 重做 = 应用 after 快照
///
/// 文本编辑的合并通过比较前后快照的文本来判断，
/// 合并时更新 after 快照，before 快照保持不变。
class OutlineUndoAction {
  /// 操作前的快照
  final OutlineTreeSnapshot before;

  /// 操作后的快照
  OutlineTreeSnapshot after;

  /// 操作描述（可用于 UI 显示）
  final String description;

  /// 操作时间戳（用于文本编辑合并判断）
  DateTime timestamp;

  /// 被编辑的节点 ID（仅文本编辑合并判断时使用，结构操作为 null）
  final String? editedNodeId;

  OutlineUndoAction({
    required this.before,
    required this.after,
    required this.description,
    required this.timestamp,
    this.editedNodeId,
  });
}

/// 大纲编辑器撤销/恢复管理器
///
/// 全局管理整个大纲编辑器的撤销/恢复栈，采用纯快照模式。
class OutlineUndoManager {
  /// 最大撤销层级
  final int maxLevels;

  /// 撤销栈
  final List<OutlineUndoAction> _undoStack = [];

  /// 重做栈
  final List<OutlineUndoAction> _redoStack = [];

  /// 是否正在执行撤销/重做
  ///
  /// 此标志为 true 时，控制器变化监听器不做任何处理，
  /// 由 [undo]/[redo] 方法在执行完毕后统一刷新 [_lastValues]。
  bool _isUndoRedoing = false;

  /// 是否正在批量操作中（结构操作期间）
  ///
  /// 此标志为 true 时，控制器变化监听器直接返回，
  /// 文本变化由结构操作的快照统一捕获。
  bool _isBatching = false;

  /// 批量操作开始前的快照
  OutlineTreeSnapshot? _batchBefore;

  /// 节点 ID 到控制器的映射（用于刷新最后值和注销）
  final Map<String, TextEditingController> _trackedControllers = {};

  /// 节点 ID 到监听器闭包的映射（用于注销时移除监听）
  final Map<String, VoidCallback> _listeners = {};

  /// 节点 ID 到上次文本值的映射（用于检测变化和合并判断）
  final Map<String, TextEditingValue> _lastValues = {};

  /// 捕获快照的回调（由编辑器状态提供）
  ///
  /// 可选参数 [focusNodeId] / [focusSelection] 用于在异步聚焦场景下
  /// 显式指定快照的焦点状态，避免 hasFocus 未及时生效导致快照记录错误焦点。
  ///
  /// 可选参数 [nodeTextOverrides] 用于文本编辑场景：
  /// 由于控制器变化监听器触发时，节点的 text 字段尚未通过 onChanged 同步，
  /// 直接深拷贝会捕获到旧文本。传入 {nodeId: text} 覆盖可确保 before/after 快照
  /// 分别记录编辑前和编辑后的正确文本。
  final OutlineTreeSnapshot Function({
    String? focusNodeId,
    TextSelection? focusSelection,
    Map<String, String>? nodeTextOverrides,
  }) _captureSnapshot;

  /// 应用快照的回调（由编辑器状态提供）
  final void Function(OutlineTreeSnapshot snapshot) _applySnapshot;

  OutlineUndoManager({
    required OutlineTreeSnapshot Function({
      String? focusNodeId,
      TextSelection? focusSelection,
      Map<String, String>? nodeTextOverrides,
    }) captureSnapshot,
    required void Function(OutlineTreeSnapshot) applySnapshot,
    this.maxLevels = 100,
  })  : _captureSnapshot = captureSnapshot,
        _applySnapshot = applySnapshot;

  /// 是否可以撤销
  bool get canUndo => _undoStack.isNotEmpty;

  /// 是否可以重做
  bool get canRedo => _redoStack.isNotEmpty;

  /// 是否正在批量操作中
  bool get isBatching => _isBatching;

  /// 注册控制器到管理器
  ///
  /// 注册后，管理器会监听该控制器的文本变化并自动记录撤销项。
  /// 重复注册同一节点 ID 会被忽略。
  void registerController(String nodeId, TextEditingController controller) {
    if (_trackedControllers.containsKey(nodeId)) return;
    _trackedControllers[nodeId] = controller;
    _lastValues[nodeId] = controller.value;

    void listener() => _onControllerChanged(nodeId, controller);
    _listeners[nodeId] = listener;
    controller.addListener(listener);
  }

  /// 注销控制器
  ///
  /// 在节点被删除时调用，移除监听器并清理追踪状态。
  void unregisterController(String nodeId, TextEditingController controller) {
    final listener = _listeners.remove(nodeId);
    if (listener != null) {
      controller.removeListener(listener);
    }
    _trackedControllers.remove(nodeId);
    _lastValues.remove(nodeId);
  }

  /// 清空所有历史记录
  ///
  /// 在加载新文档或重置编辑器时调用。
  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  /// 开始批量操作
  ///
  /// 在结构操作（增删节点、移动节点等）开始前调用，
  /// 捕获操作前的快照并抑制文本变化监听。
  /// 必须与 [endBatch] 配对使用。
  void beginBatch() {
    if (_isBatching) return;
    _isBatching = true;
    _batchBefore = _captureSnapshot();
  }

  /// 结束批量操作并记录
  ///
  /// 在结构操作完成后调用，捕获操作后的快照，
  /// 将前后快照作为一条撤销记录推入撤销栈。
  ///
  /// [focusNodeId] / [focusSelection] 用于异步聚焦场景：
  /// 当 endBatch 调用时焦点可能尚未通过 hasFocus 生效，
  /// 此时显式传入期望的焦点节点和选区，保证快照记录正确的焦点状态。
  void endBatch({
    required String description,
    String? focusNodeId,
    TextSelection? focusSelection,
  }) {
    if (!_isBatching) return;
    final before = _batchBefore;
    _batchBefore = null;
    _isBatching = false;

    if (before == null) return;

    final after = _captureSnapshot(focusNodeId: focusNodeId, focusSelection: focusSelection);
    _undoStack.add(OutlineUndoAction(
      before: before,
      after: after,
      description: description,
      timestamp: DateTime.now(),
    ));
    _redoStack.clear();
    if (_undoStack.length > maxLevels) {
      _undoStack.removeAt(0);
    }

    // 刷新所有控制器的最后值，确保后续文本编辑的 before 状态正确
    _refreshLastValues();
  }

  /// 撤销
  ///
  /// 返回值：true 表示成功执行了撤销；false 表示撤销栈为空
  bool undo() {
    if (_undoStack.isEmpty) return false;

    _isUndoRedoing = true;
    final action = _undoStack.removeLast();
    _redoStack.add(action);
    // 撤销 = 应用 before 快照
    _applySnapshot(action.before);
    _refreshLastValues();
    _isUndoRedoing = false;
    return true;
  }

  /// 重做
  ///
  /// 返回值：true 表示成功执行了重做；false 表示重做栈为空
  bool redo() {
    if (_redoStack.isEmpty) return false;

    _isUndoRedoing = true;
    final action = _redoStack.removeLast();
    _undoStack.add(action);
    // 重做 = 应用 after 快照
    // 修正光标位置：中文输入法 composing 结束时光标可能停在新增文字前面，这里将其推到新增文字末尾
    final correctedAfter = _correctRedoCursorPosition(action.before, action.after);
    _applySnapshot(correctedAfter);
    _refreshLastValues();
    _isUndoRedoing = false;
    return true;
  }

  /// 修正重做时的光标位置
  ///
  /// 中文输入法在 composing（候选框输入）结束时，光标可能停在新增文字的前面或中间，
  /// 导致 after 快照记录的选区位于新增文字起点而非终点。
  /// 此方法比较 before/after 快照中焦点节点的文本差异，若光标落后于新增文字末尾，
  /// 强制将其推到差异段末尾。逻辑与 [EditorUndoManager._calculateRedoCursorPosition] 一致。
  ///
  /// 仅对折叠选区进行修正，多选区状态保持原样以完整恢复选中范围。
  OutlineTreeSnapshot _correctRedoCursorPosition(
    OutlineTreeSnapshot before,
    OutlineTreeSnapshot after,
  ) {
    final focusedId = after.focusedNodeId;
    final selection = after.focusedSelection;
    // 无焦点节点或选区无效时不修正
    if (focusedId == null || selection == null || !selection.isValid) {
      return after;
    }
    // 非折叠选区保持原样（多选区状态需要完整恢复选中范围）
    if (!selection.isCollapsed) {
      return after;
    }

    final beforeText = _getNodeText(before, focusedId);
    final afterText = _getNodeText(after, focusedId);

    // 找到 before 和 after 文本的公共前缀长度
    int commonPrefixLength = 0;
    final int minLength = beforeText.length < afterText.length
        ? beforeText.length
        : afterText.length;
    while (commonPrefixLength < minLength &&
        beforeText[commonPrefixLength] == afterText[commonPrefixLength]) {
      commonPrefixLength++;
    }

    // 文本完全相同，无需修正
    if (afterText.length == beforeText.length && beforeText == afterText) {
      return after;
    }

    // 计算公共后缀长度，确定差异段的结束位置
    int commonSuffixLength = 0;
    final int maxSuffix = minLength - commonPrefixLength;
    while (commonSuffixLength < maxSuffix &&
        beforeText[beforeText.length - 1 - commonSuffixLength] ==
            afterText[afterText.length - 1 - commonSuffixLength]) {
      commonSuffixLength++;
    }

    final int changeEndIndex = afterText.length - commonSuffixLength;
    final String insertedText =
        afterText.substring(commonPrefixLength, changeEndIndex);

    // 纯删除操作（没有新增文本），不修正光标
    if (insertedText.isEmpty) {
      return after;
    }

    // 纯空白字符插入（回车、空格等），保持系统原本的光标逻辑
    final bool isPureWhitespaceInsert = insertedText.trim().isEmpty &&
        afterText.length == beforeText.length + insertedText.length;
    if (isPureWhitespaceInsert) {
      return after;
    }

    // 光标落后于新增文字末尾时，将其推到末尾
    if (selection.baseOffset < changeEndIndex) {
      return OutlineTreeSnapshot(
        roots: after.roots,
        focusedNodeId: after.focusedNodeId,
        focusedSelection: TextSelection.collapsed(offset: changeEndIndex),
        selectedNodeIds: after.selectedNodeIds,
        selectAllLevel: after.selectAllLevel,
        selectionAnchorIndex: after.selectionAnchorIndex,
      );
    }

    return after;
  }

  /// 刷新所有控制器的最后值
  ///
  /// 在撤销/重做或批量操作结束后调用，
  /// 确保后续文本编辑的 before 状态与当前控制器值一致。
  void _refreshLastValues() {
    for (final entry in _trackedControllers.entries) {
      _lastValues[entry.key] = entry.value.value;
    }
  }

  /// 控制器变化监听器
  ///
  /// 自动检测文本变化并记录撤销项，支持连续输入合并。
  void _onControllerChanged(String nodeId, TextEditingController controller) {
    // 撤销/重做或批量操作期间，不做任何记录
    if (_isUndoRedoing || _isBatching) return;

    final currentValue = controller.value;
    final lastValue = _lastValues[nodeId];
    if (lastValue == null) {
      _lastValues[nodeId] = currentValue;
      return;
    }

    // 仅在文本真正变化时才记录（光标移动不产生新的撤销记录）
    if (currentValue.text != lastValue.text) {
      final now = DateTime.now();
      bool merged = false;

      // 尝试与上一次的编辑合并，以实现"连续输入只产生一次撤销"的效果
      if (_undoStack.isNotEmpty) {
        final lastAction = _undoStack.last;
        // 仅对同一节点的文本编辑进行合并
        if (lastAction.editedNodeId == nodeId) {
          final timeDiff = now.difference(lastAction.timestamp);

          // 合并条件：
          // 1. 两次编辑时间间隔小于 1 秒
          // 2. 光标没有被手动移动过（当前修改前的位置 == 上次修改后的位置）
          // 3. 修改前没有选中文本（即不是文本替换操作）
          if (timeDiff.inMilliseconds < 1000) {
            final lastAfterSelection = lastAction.after.focusedSelection;
            // 比较选区：上次编辑后的选区应与当前编辑前的选区一致
            if (lastAfterSelection != null &&
                lastValue.selection == lastAfterSelection &&
                lastValue.selection.isCollapsed) {
              // 只允许同向操作合并（同为连续输入，或同为连续删除）
              final lastBeforeText = _getNodeText(lastAction.before, nodeId);
              final lastAfterText = _getNodeText(lastAction.after, nodeId);
              final int lastDelta = lastAfterText.length - lastBeforeText.length;
              final int currentDelta =
                  currentValue.text.length - lastValue.text.length;

              if ((lastDelta > 0 && currentDelta > 0) ||
                  (lastDelta < 0 && currentDelta < 0)) {
                // 满足条件，合并记录：更新 after 快照为当前状态
                // 传入 nodeTextOverrides 确保快照中的节点文本是当前控制器的文本，
                // 而不是尚未通过 onChanged 同步的旧 node.text
                lastAction.after = _captureSnapshot(
                  focusNodeId: nodeId,
                  focusSelection: currentValue.selection,
                  nodeTextOverrides: {nodeId: currentValue.text},
                );
                lastAction.timestamp = now;
                merged = true;
              }
            }
          }
        }
      }

      if (!merged) {
        // 新增一条撤销记录：before 为上次值对应的快照，after 为当前快照
        // 传入 nodeTextOverrides 确保快照中的节点文本与控制器的文本一致，
        // 而不是尚未通过 onChanged 同步的旧 node.text
        _undoStack.add(OutlineUndoAction(
          before: _captureSnapshot(
            focusNodeId: nodeId,
            focusSelection: lastValue.selection,
            nodeTextOverrides: {nodeId: lastValue.text},
          ),
          after: _captureSnapshot(
            focusNodeId: nodeId,
            focusSelection: currentValue.selection,
            nodeTextOverrides: {nodeId: currentValue.text},
          ),
          description: '编辑文本',
          timestamp: now,
          editedNodeId: nodeId,
        ));
        if (_undoStack.length > maxLevels) {
          _undoStack.removeAt(0);
        }
      }

      // 一旦有新的修改，清空重做栈
      _redoStack.clear();
    }

    // 始终更新 _lastValue（包含了光标的移动），这样当下一次输入时，
    // before 状态就能准确记录输入前光标真正所在的位置
    _lastValues[nodeId] = currentValue;
  }

  /// 从快照中获取指定节点的文本
  ///
  /// 用于文本编辑合并时比较文本长度变化。
  String _getNodeText(OutlineTreeSnapshot snapshot, String nodeId) {
    OutlineNode? findNode(List<OutlineNode> nodes) {
      for (final node in nodes) {
        if (node.id == nodeId) return node;
        final found = findNode(node.children);
        if (found != null) return found;
      }
      return null;
    }

    final node = findNode(snapshot.roots);
    return node?.text ?? '';
  }

  /// 释放资源
  ///
  /// 移除所有控制器监听器并清空栈。
  void dispose() {
    for (final entry in _trackedControllers.entries) {
      final listener = _listeners[entry.key];
      if (listener != null) {
        entry.value.removeListener(listener);
      }
    }
    _trackedControllers.clear();
    _listeners.clear();
    _lastValues.clear();
    _undoStack.clear();
    _redoStack.clear();
  }
}
