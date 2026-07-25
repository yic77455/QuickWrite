import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 大纲编辑器快捷键说明条目
///
/// 一条快捷键由功能描述与按键说明两部分组成，对应面板中的左右两列。
class _ShortcutEntry {
  /// 功能描述（左列）
  final String description;

  /// 按键说明（右列，等宽字体展示）
  final String keys;

  const _ShortcutEntry({required this.description, required this.keys});
}

/// 大纲编辑器快捷键分组
///
/// 将同类快捷键归为一组，面板按组展示，组内条目以分隔线区分。
class _ShortcutGroup {
  /// 分组标题
  final String title;

  /// 组内快捷键条目
  final List<_ShortcutEntry> entries;

  const _ShortcutGroup({required this.title, required this.entries});
}

/// 大纲编辑器快捷键列表面板
///
/// 浮动在编辑器右侧的快捷键查阅面板，按功能分组展示全部快捷键。
/// 面板以侧边栏样式呈现：贴右、近全高、左侧投影，作为浮层覆盖在编辑器之上，
/// 不挤压左侧编辑器宽度，也不随内容滚动。
class OutlineShortcutPanel extends StatelessWidget {
  /// 颜色方案
  final ColorScheme colorScheme;

  /// 关闭面板回调
  final VoidCallback onClose;

  const OutlineShortcutPanel({
    super.key,
    required this.colorScheme,
    required this.onClose,
  });

  /// 全部快捷键分组数据
  ///
  /// 内容与节点级键盘事件处理器 [_onKeyEvent] 及编辑器级键盘事件处理器
  /// [_onEditorKeyEvent] 中已实现的快捷键保持一致。
  static const List<_ShortcutGroup> _groups = [
    _ShortcutGroup(title: '基础导航', entries: [
      _ShortcutEntry(description: '切换到上 / 下一节点', keys: '↑ / ↓'),
      _ShortcutEntry(description: '全选主题，再次按下全选文档', keys: 'Ctrl+A'),
      _ShortcutEntry(description: '清除选区 / 关闭浮窗', keys: 'Esc'),
    ]),
    _ShortcutGroup(title: '节点编辑', entries: [
      _ShortcutEntry(description: '新建同级节点', keys: 'Enter'),
      _ShortcutEntry(description: '缩进为子节点', keys: 'Tab'),
      _ShortcutEntry(description: '提升层级', keys: 'Shift+Tab'),
      _ShortcutEntry(description: '空节点删除 / 合并到上一节点', keys: 'Backspace'),
      
    ]),
    _ShortcutGroup(title: '文字样式', entries: [
      _ShortcutEntry(description: '加粗', keys: 'Ctrl+B'),
      _ShortcutEntry(description: '斜体', keys: 'Ctrl+I'),
      _ShortcutEntry(description: '下划线', keys: 'Ctrl+U'),
      _ShortcutEntry(description: '删除线', keys: 'Ctrl+Enter'),
    ]),
    _ShortcutGroup(title: '标题级别', entries: [
      _ShortcutEntry(description: '设为一级标题', keys: 'Alt+1'),
      _ShortcutEntry(description: '设为二级标题', keys: 'Alt+2'),
      _ShortcutEntry(description: '设为三级标题', keys: 'Alt+3'),
      _ShortcutEntry(description: '设为正文', keys: 'Alt+4'),
      _ShortcutEntry(description: '作用于全部同级节点', keys: 'Shift+Alt+数字'),
    ]),
    _ShortcutGroup(title: '颜色', entries: [
      _ShortcutEntry(description: '设置字体颜色（红橙黄绿青蓝紫）', keys: 'Alt+R/O/Y/G/C/B/P'),
      _ShortcutEntry(description: '清除字体颜色', keys: 'Alt+D'),
      _ShortcutEntry(description: '设置字底颜色', keys: 'Ctrl+Alt+字母'),
      _ShortcutEntry(description: '清除字底颜色', keys: 'Ctrl+Alt+D'),
    ]),
    _ShortcutGroup(title: '剪贴板', entries: [
      _ShortcutEntry(description: '复制选中节点', keys: 'Ctrl+C'),
      _ShortcutEntry(description: '剪切选中节点', keys: 'Ctrl+X'),
      _ShortcutEntry(description: '粘贴节点 / 文本', keys: 'Ctrl+V'),
      _ShortcutEntry(description: '删除选中节点', keys: 'Delete'),
    ]),
    _ShortcutGroup(title: '撤销重做', entries: [
      _ShortcutEntry(description: '撤销', keys: 'Ctrl+Z'),
      _ShortcutEntry(description: '重做', keys: 'Ctrl+Y / Ctrl+Shift+Z'),
    ]),
    _ShortcutGroup(title: '查找与保存', entries: [
      _ShortcutEntry(description: '查找', keys: 'Ctrl+F'),
      _ShortcutEntry(description: '查找替换', keys: 'Ctrl+H'),
      _ShortcutEntry(description: '保存', keys: 'Ctrl+S'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      // 左侧分隔线与投影，营造浮层侧边栏的视觉层次
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildGroupList()),
        ],
      ),
    );
  }

  /// 构建面板头部：图标、标题与关闭按钮
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.keyboard_outlined, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('快捷键', style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          _buildCloseButton(),
        ],
      ),
    );
  }

  /// 构建关闭按钮
  Widget _buildCloseButton() {
    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onClose,
          borderRadius: BorderRadius.circular(6),
          hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
          child: Icon(Icons.close_rounded, size: 16, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  /// 构建分组列表
  Widget _buildGroupList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: _groups.length,
      itemBuilder: (context, index) => _buildGroup(context, _groups[index]),
    );
  }

  /// 构建单个分组：标题 + 卡片化的条目列表
  Widget _buildGroup(BuildContext context, _ShortcutGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              group.title,
              style: context.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < group.entries.length; i++) ...[
                  _buildEntry(context, group.entries[i]),
                  if (i < group.entries.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单条快捷键条目：左列功能描述，右列按键徽标
  Widget _buildEntry(BuildContext context, _ShortcutEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左列：功能描述
          Expanded(
            child: Text(
              entry.description,
              style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          // 右列：快捷键徽标
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Text(
              entry.keys,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
