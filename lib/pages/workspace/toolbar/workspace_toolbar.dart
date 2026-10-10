import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/app_settings.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/font_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/code_line_selection_utils.dart';
import 'package:quick_write/core/utils/paragraph_formatter.dart';
import 'package:quick_write/pages/workspace/editor/novel_editor.dart';
import 'package:quick_write/pages/workspace/toolbar/widgets/chapter_title_format_panel.dart';
import 'package:quick_write/shared/dialogs/color_picker_dialog.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 工作台顶部工具栏
///
/// 包含字体格式区、功能区、设置图标区三个部分
class WorkspaceToolbar extends StatefulWidget {
  const WorkspaceToolbar({super.key});

  @override
  State<WorkspaceToolbar> createState() => _WorkspaceToolbarState();
}

class _WorkspaceToolbarState extends State<WorkspaceToolbar> {
  /// 更多格式菜单的控制器
  final MenuController _formatMenuController = MenuController();

  /// 获取字体列表（从全局 FontService 获取）
  List<DropdownItem> get _fontList {
    final fonts = FontService().systemFonts;
    if (fonts.isEmpty) {
      // 字体服务未加载时使用默认字体列表
      return [
        DropdownItem(displayText: '微软雅黑', value: '微软雅黑'),
        DropdownItem(displayText: '宋体', value: '宋体'),
        DropdownItem(displayText: '黑体', value: '黑体'),
        DropdownItem(displayText: '楷体', value: '楷体'),
      ];
    }

    // 从 FontService 获取字体列表并转换为 DropdownItem
    return fonts.map((font) => DropdownItem(displayText: font.displayName, value: font.fontFamily)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 监听标签页切换，根据当前标签页类型切换格式区的设置源
    final currentTab = context.watch<WorkspaceProvider>().currentTab;
    // 判断当前标签页是否是大纲编辑器（设定项或设定项的备份预览）
    final bool isOutlineTab = currentTab != null &&
        (currentTab.type == EditorTabType.settings ||
            (currentTab.type == EditorTabType.backupPreview && currentTab.originalIsSetting));

    // 使用与标题栏相同的背景色，视觉上一体
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: colorScheme.surface),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 字体格式区
          _buildFontFormatSection(context, isOutline: isOutlineTab),

          const SizedBox(width: 16),

          // 分隔线
          _buildVerticalDivider(context),

          const SizedBox(width: 16),

          // 功能区
          _buildFunctionSection(context),

          const SizedBox(width: 16),

          // 分隔线
          _buildVerticalDivider(context),

          const SizedBox(width: 16),

          // 设置图标区
          _buildSettingsSection(context),

          const SizedBox(width: 16),

          // 分隔线
          _buildVerticalDivider(context),

          const SizedBox(width: 16),

          // 工具区
          _buildToolsSection(context),
        ],
      ),
    );
  }

  /// 构建垂直分隔线
  Widget _buildVerticalDivider(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(width: 1, height: 56, color: colorScheme.outlineVariant.withValues(alpha: 0.5));
  }

  /// 构建字体格式区（两行布局）
  ///
  /// [isOutline] 为 true 时表示当前标签页是大纲编辑器，
  /// 字体和字号下拉框读写大纲编辑器设置，
  /// 颜色、加粗、斜体、下划线、更多格式按钮锁定为不可用状态
  Widget _buildFontFormatSection(BuildContext context, {required bool isOutline}) {
    final colorScheme = Theme.of(context).colorScheme;
    // 第一行总宽度：字体下拉框(130) + 间距(8) + 字号下拉框(64) = 202
    const double firstRowWidth = 202.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 第一行：字体选择、字号选择
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 字体选择下拉框
            _buildFontDropdown(context, isOutline: isOutline),
            const SizedBox(width: 8),
            // 字号选择下拉框
            _buildFontSizeDropdown(context, isOutline: isOutline),
          ],
        ),
        const SizedBox(height: 6),
        // 第二行：颜色、加粗、斜体、下划线、更多（两端对齐）
        SizedBox(
          width: firstRowWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 颜色选择图标
              _wrapDisabled(_buildColorButton(context), isOutline),
              _wrapDisabled(
                ToggleToolButton(
                  icon: Icons.format_bold_rounded,
                  tooltip: '加粗',
                  initialValue: SettingsService.instance.isBold,
                  onChanged: (value) {
                    SettingsService.instance.updateIsBold(value);
                  },
                ),
                isOutline,
              ),
              _wrapDisabled(
                ToggleToolButton(
                  icon: Icons.format_italic_rounded,
                  tooltip: '斜体',
                  initialValue: SettingsService.instance.isItalic,
                  onChanged: (value) {
                    SettingsService.instance.updateIsItalic(value);
                  },
                ),
                isOutline,
              ),
              _wrapDisabled(
                ToggleToolButton(
                  icon: Icons.format_underlined_rounded,
                  tooltip: '下划线',
                  initialValue: SettingsService.instance.isUnderline,
                  onChanged: (value) {
                    SettingsService.instance.updateIsUnderline(value);
                  },
                ),
                isOutline,
              ),
              _wrapDisabled(
                MenuAnchor(
                  controller: _formatMenuController,
                  alignmentOffset: const Offset(0, 4),
                  style: MenuStyle(
                    backgroundColor: WidgetStateProperty.all(colorScheme.surface),
                    elevation: WidgetStateProperty.all(3),
                    padding: WidgetStateProperty.all(EdgeInsets.zero),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                  ),
                  menuChildren: [
                    ChapterTitleFormatPanel(
                      onCloseMenu: () => _formatMenuController.close(),
                    ),
                  ],
                  builder: (context, controller, child) {
                    return SmallToolbarButton(
                      icon: Icons.more_horiz_rounded,
                      tooltip: '更多格式',
                      height: 32,
                      isMenuOpen: controller.isOpen,
                      onPressed: () {
                        if (controller.isOpen) {
                          controller.close();
                        } else {
                          controller.open();
                        }
                      },
                    );
                  },
                ),
                isOutline,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 根据禁用状态包装组件
  ///
  /// 禁用时拦截指针事件并降低不透明度
  Widget _wrapDisabled(Widget child, bool disabled) {
    if (!disabled) return child;
    return IgnorePointer(
      child: Opacity(opacity: 0.38, child: child),
    );
  }

  /// 构建字体选择下拉框
  ///
  /// [isOutline] 为 true 时读写大纲编辑器字体设置
  /// 顶部置顶一个"默认"选项，选择后恢复为系统默认字体
  Widget _buildFontDropdown(BuildContext context, {required bool isOutline}) {
    // 在字体列表顶部插入"默认"选项，作为恢复默认字体的入口
    final fontItems = <DropdownItem>[
      DropdownItem(displayText: '默认', value: '__default_font__'),
      ..._fontList,
    ];

    return CustomDropdown(
      width: 130,
      value: isOutline ? SettingsService.instance.outlineFontFamily : SettingsService.instance.fontFamily,
      items: fontItems,
      onChanged: (value) {
        if (value == '__default_font__') {
          // 选择"默认"项：重置为系统默认字体
          final defaultFont = SettingsService.instance.defaultFontFamily;
          if (isOutline) {
            SettingsService.instance.updateOutlineFontFamily(defaultFont);
          } else {
            SettingsService.instance.updateFontFamily(defaultFont);
          }
        } else {
          if (isOutline) {
            SettingsService.instance.updateOutlineFontFamily(value);
          } else {
            SettingsService.instance.updateFontFamily(value);
          }
        }
        // 触发重建，使下拉框显示实际默认字体的名称而非"默认"
        setState(() {});
      },
    );
  }

  /// 构建字号选择下拉框
  ///
  /// [isOutline] 为 true 时读写大纲编辑器字号设置
  /// 顶部置顶一个"默认"选项，选择后恢复为默认字号
  Widget _buildFontSizeDropdown(BuildContext context, {required bool isOutline}) {
    // 生成字号列表，并在顶部插入"默认"选项
    // 大纲编辑器最小字号为10，主编辑器最小字号为5，最大字号均为72
    final minSize = isOutline ? 10 : 5;
    final fontSizeItems = <DropdownItem>[
      DropdownItem(displayText: '默认', value: '__default_size__'),
      ...List.generate(72 - minSize + 1, (index) {
        final size = (index + minSize).toString();
        return DropdownItem(displayText: size, value: size);
      }),
    ];
    final currentSize = isOutline ? SettingsService.instance.outlineFontSize : SettingsService.instance.fontSize;
    return CustomDropdown(
      width: 64,
      value: currentSize.toStringAsFixed(0),
      items: fontSizeItems,
      onChanged: (value) {
        if (value == '__default_size__') {
          // 选择"默认"项：重置为默认字号
          if (isOutline) {
            SettingsService.instance.updateOutlineFontSize(AppSettings.defaults.outlineFontSize);
          } else {
            SettingsService.instance.updateFontSize(AppSettings.defaults.fontSize);
          }
        } else {
          final fontSize = double.tryParse(value);
          if (fontSize != null) {
            if (isOutline) {
              SettingsService.instance.updateOutlineFontSize(fontSize);
            } else {
              SettingsService.instance.updateFontSize(fontSize);
            }
          }
        }
        // 触发重建，使下拉框显示实际默认字号而非"默认"
        setState(() {});
      },
    );
  }

  /// 构建颜色选择按钮
  Widget _buildColorButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 读取当前正文字体颜色，用于显示颜色指示条
    final currentColor = ColorUtils.getFontColorForTheme(context);

    return CursorTooltipTarget(
      tooltipContent: const Text('字体颜色'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showFontColorPicker(context),
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.format_color_text_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                // 颜色指示条（显示当前选中的字体颜色）
                Positioned(
                  bottom: 7,
                  child: Container(
                    width: 16,
                    height: 3,
                    decoration: BoxDecoration(color: currentColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建功能区（大图标）
  Widget _buildFunctionSection(BuildContext context) {
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final rightSidebarType = workspaceProvider.rightSidebarType;
    final isRightSidebarExpanded = workspaceProvider.isRightSidebarExpanded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LargeToolbarButton(
          icon: Icons.find_replace_rounded,
          label: '查找替换',
          tooltip: '查找替换 (Ctrl+H)',
          onPressed: () {
            context.read<WorkspaceProvider>().toggleFindReplace();
          },
        ),
        const SizedBox(width: 8),
        ToggleLargeToolbarButton(
          icon: Icons.search_rounded,
          label: '全文搜索',
          tooltip: '全文搜索',
          // 当前侧边栏打开且类型为搜索时显示选中状态
          isSelected: isRightSidebarExpanded && rightSidebarType == RightSidebarType.search,
          onPressed: () {
            context.read<WorkspaceProvider>().toggleRightSidebar(RightSidebarType.search);
          },
        ),
        const SizedBox(width: 8),
        LargeToolbarButton(
          icon: Icons.format_align_left_rounded,
          label: '段落整理',
          tooltip: '根据排版设置一键整理段落',
          onPressed: () {
            _handleFormatParagraph(context);
          },
        ),
        const SizedBox(width: 8),
        ToggleLargeToolbarButton(
          icon: Icons.history_rounded,
          label: '历史版本',
          tooltip: '查看历史版本',
          // 当前侧边栏打开且类型为历史版本时显示选中状态
          isSelected: isRightSidebarExpanded && rightSidebarType == RightSidebarType.history,
          onPressed: () {
            context.read<WorkspaceProvider>().toggleRightSidebar(RightSidebarType.history);
          },
        ),
      ],
    );
  }

  /// 构建设置图标区（开关式大图标，点击切换右侧边栏）
  Widget _buildSettingsSection(BuildContext context) {
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final rightSidebarType = workspaceProvider.rightSidebarType;
    final isRightSidebarExpanded = workspaceProvider.isRightSidebarExpanded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToggleLargeToolbarButton(
          icon: Icons.space_dashboard_outlined,
          label: '布局',
          tooltip: '布局设置',
          // 当前侧边栏打开且类型为布局时显示选中状态
          isSelected: isRightSidebarExpanded && rightSidebarType == RightSidebarType.layout,
          onPressed: () {
            context.read<WorkspaceProvider>().toggleRightSidebar(RightSidebarType.layout);
          },
        ),
        const SizedBox(width: 8),
        ToggleLargeToolbarButton(
          icon: Icons.format_line_spacing,
          label: '排版',
          tooltip: '排版设置',
          // 当前侧边栏打开且类型为排版时显示选中状态
          isSelected: isRightSidebarExpanded && rightSidebarType == RightSidebarType.typeset,
          onPressed: () {
            context.read<WorkspaceProvider>().toggleRightSidebar(RightSidebarType.typeset);
          },
        ),
        const SizedBox(width: 8),
        ToggleLargeToolbarButton(
          icon: Icons.tune_rounded,
          label: '其他',
          tooltip: '其他设置',
          // 当前侧边栏打开且类型为其他时显示选中状态
          isSelected: isRightSidebarExpanded && rightSidebarType == RightSidebarType.other,
          onPressed: () {
            context.read<WorkspaceProvider>().toggleRightSidebar(RightSidebarType.other);
          },
        ),
      ],
    );
  }

  /// 构建工具区
  Widget _buildToolsSection(BuildContext context) {
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final rightSidebarType = workspaceProvider.rightSidebarType;
    final isRightSidebarExpanded = workspaceProvider.isRightSidebarExpanded;

    return ToggleLargeToolbarButton(
      icon: Icons.build_circle_outlined,
      label: '工具',
      tooltip: '工具',
      // 当前侧边栏打开且类型为工具时显示选中状态
      isSelected: isRightSidebarExpanded && rightSidebarType == RightSidebarType.tools,
      onPressed: () {
        context.read<WorkspaceProvider>().toggleRightSidebar(RightSidebarType.tools);
      },
    );
  }

  /// 处理段落整理操作
  ///
  /// 对当前编辑器中的文本进行格式化
  void _handleFormatParagraph(BuildContext context) {
    final workspaceProvider = context.read<WorkspaceProvider>();
    final currentTab = workspaceProvider.currentTab;
    if (currentTab == null || currentTab.textController == null) return;

    final textController = currentTab.textController!;
    final String currentText = textController.text;
    if (currentText.isEmpty) return;

    final String formattedText = ParagraphFormatter.formatText(currentText);
    if (formattedText == currentText) return;

    // 程序化改写全文，不产生编辑事件
    NovelEditorState.runSilently(() {
      textController.text = formattedText;
      textController.selection = CodeLineSelectionUtils.collapsedSelection(formattedText, 0);
    });

    // 标记为已修改
    if (!currentTab.isModified) {
      currentTab.isModified = true;
      workspaceProvider.notifyTabModified(currentTab.id);
    }

    // 更新字数统计
    currentTab.updateWordCount();
    workspaceProvider.notifyWordCountUpdated();
  }

  /// 显示正文字体颜色选择器对话框
  void _showFontColorPicker(BuildContext context) {
    ColorPickerDialog.show(
      context: context,
      title: '选择正文字体颜色',
      initialColorHex: ColorUtils.getFontColorHexForTheme(context),
      onColorSelected: (colorHex) {
        ColorUtils.updateFontColorForTheme(context, colorHex);
        setState(() {});
      },
    );
  }
}
