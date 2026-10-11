/// 快捷键说明条目
///
/// 一条快捷键由功能描述与按键说明两部分组成，列表中以左右两列展示。
class ShortcutEntry {
  /// 功能描述（左列）
  final String description;

  /// 按键说明（右列，等宽字体展示）
  final String keys;

  const ShortcutEntry({required this.description, required this.keys});
}

/// 快捷键分组
///
/// 将同类快捷键归为一组，列表按组展示，组内条目以分隔线区分。
class ShortcutGroup {
  /// 分组标题
  final String title;

  /// 组内快捷键条目
  final List<ShortcutEntry> entries;

  const ShortcutGroup({required this.title, required this.entries});
}

/// 正文编辑器快捷键列表
///
/// 由 re_editor 的内置快捷键与工作台覆盖实现共同决定。
const List<ShortcutEntry> bodyEditorShortcuts = [
  ShortcutEntry(description: '全选', keys: 'Ctrl+A'),
  ShortcutEntry(description: '剪切选中/当前行', keys: 'Ctrl+X'),
  ShortcutEntry(description: '复制选中/当前行', keys: 'Ctrl+C'),
  ShortcutEntry(description: '粘贴', keys: 'Ctrl+V'),
  ShortcutEntry(description: '撤销', keys: 'Ctrl+Z'),
  ShortcutEntry(description: '重做', keys: 'Ctrl+Y / Ctrl+Shift+Z'),
  ShortcutEntry(description: '缩进', keys: 'Tab'),
  ShortcutEntry(description: '查找', keys: 'Ctrl+F'),
  ShortcutEntry(description: '替换', keys: 'Ctrl+H / Ctrl+Alt+F'),
  ShortcutEntry(description: '保存', keys: 'Ctrl+S'),
  ShortcutEntry(description: '选中当前行', keys: 'Ctrl+L'),
  ShortcutEntry(description: '删除当前行', keys: 'Ctrl+D'),
  ShortcutEntry(description: '移动当前行', keys: 'Alt+↑/↓'),
  ShortcutEntry(description: '连续选择', keys: 'Shift+↑/↓/←/→'),
  ShortcutEntry(description: '移动光标', keys: '↑/↓/←/→'),
  ShortcutEntry(description: '移动光标（单词边界）', keys: 'Alt+←/→'),
  ShortcutEntry(description: '移动到页首/页尾', keys: 'Ctrl+↑/↓'),
];

/// 大纲编辑器快捷键分组列表
///
/// 内容与大纲编辑器节点级键盘事件处理器及编辑器级键盘事件处理器中
/// 已实现的快捷键保持一致。
const List<ShortcutGroup> outlineEditorShortcutGroups = [
  ShortcutGroup(title: '基础导航', entries: [
    ShortcutEntry(description: '切换到上 / 下一节点', keys: '↑ / ↓'),
    ShortcutEntry(description: '全选主题，再次按下全选文档', keys: 'Ctrl+A'),
    ShortcutEntry(description: '清除选区 / 关闭浮窗', keys: 'Esc'),
  ]),
  ShortcutGroup(title: '节点编辑', entries: [
    ShortcutEntry(description: '新建同级节点', keys: 'Enter'),
    ShortcutEntry(description: '缩进为子节点', keys: 'Tab'),
    ShortcutEntry(description: '提升层级', keys: 'Shift+Tab'),
    ShortcutEntry(description: '空节点删除 / 合并到上一节点', keys: 'Backspace'),
  ]),
  ShortcutGroup(title: '文字样式', entries: [
    ShortcutEntry(description: '加粗', keys: 'Ctrl+B'),
    ShortcutEntry(description: '斜体', keys: 'Ctrl+I'),
    ShortcutEntry(description: '下划线', keys: 'Ctrl+U'),
    ShortcutEntry(description: '删除线', keys: 'Ctrl+Enter'),
  ]),
  ShortcutGroup(title: '标题级别', entries: [
    ShortcutEntry(description: '设为一级标题', keys: 'Alt+1'),
    ShortcutEntry(description: '设为二级标题', keys: 'Alt+2'),
    ShortcutEntry(description: '设为三级标题', keys: 'Alt+3'),
    ShortcutEntry(description: '设为正文', keys: 'Alt+4'),
    ShortcutEntry(description: '作用于全部同级节点', keys: 'Shift+Alt+数字'),
  ]),
  ShortcutGroup(title: '颜色', entries: [
    ShortcutEntry(description: '设置字体颜色（红橙黄绿青蓝紫）', keys: 'Alt+R/O/Y/G/C/B/P'),
    ShortcutEntry(description: '清除字体颜色', keys: 'Alt+D'),
    ShortcutEntry(description: '设置字底颜色', keys: 'Ctrl+Alt+字母'),
    ShortcutEntry(description: '清除字底颜色', keys: 'Ctrl+Alt+D'),
  ]),
  ShortcutGroup(title: '剪贴板', entries: [
    ShortcutEntry(description: '复制选中节点', keys: 'Ctrl+C'),
    ShortcutEntry(description: '剪切选中节点', keys: 'Ctrl+X'),
    ShortcutEntry(description: '粘贴节点 / 文本', keys: 'Ctrl+V'),
    ShortcutEntry(description: '删除选中节点', keys: 'Delete'),
  ]),
  ShortcutGroup(title: '撤销重做', entries: [
    ShortcutEntry(description: '撤销', keys: 'Ctrl+Z'),
    ShortcutEntry(description: '重做', keys: 'Ctrl+Y / Ctrl+Shift+Z'),
  ]),
  ShortcutGroup(title: '查找与保存', entries: [
    ShortcutEntry(description: '查找', keys: 'Ctrl+F'),
    ShortcutEntry(description: '查找替换', keys: 'Ctrl+H'),
    ShortcutEntry(description: '保存', keys: 'Ctrl+S'),
  ]),
];
