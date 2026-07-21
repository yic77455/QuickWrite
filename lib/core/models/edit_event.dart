/// 编辑器文本变化事件类型
///
/// 用于在编辑器拦截层（粘贴、撤销、恢复、剪切、删除、键盘输入）
/// 明确区分事件来源，供码字统计模块按类型分别处理：
/// - keyboard/paste/cut/delete 参与码字统计
/// - undo/redo 不参与码字统计（仅同步基线，避免影响今日码字与码字速度）
enum NovelEditType {
  /// 键盘输入（含 Backspace/Delete 键删除）
  keyboard,

  /// 粘贴
  paste,

  /// 剪切
  cut,

  /// 删除选中文本（右键菜单触发）
  delete,

  /// 撤销（不参与码字统计）
  undo,

  /// 恢复（不参与码字统计）
  redo,
}

/// 编辑事件回调签名
///
/// 由 [NovelEditor] 在文本变化时触发，参数为事件类型。
/// 字数增量由调用方根据控制器字数变化计算，避免编辑器耦合字数逻辑。
typedef OnEditEvent = void Function(NovelEditType type);
