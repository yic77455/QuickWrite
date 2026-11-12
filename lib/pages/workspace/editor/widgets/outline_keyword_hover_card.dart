import 'dart:io';
import 'package:flutter/material.dart';
import 'package:quick_write/core/models/outline_keyword.dart';
import 'package:quick_write/core/models/outline_table.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/rich_text_controller.dart';
import 'package:quick_write/core/utils/text_style_range.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_editor_widgets.dart';

/// 正文大纲关键词悬浮卡片
///
/// 参照人物卡 / 物品卡 / 设定卡的形态：以绑定节点文本为标题、设定项名称为副标题，
/// 标题栏右侧展示绑定节点的图片缩略图，内容区展示该节点的全部子孙节点
/// （按层级缩进）及其备注、图片与表格，并还原各节点自身的文字样式；
/// 内容超出最大高度时在卡片内滚动。
/// 卡片自身响应鼠标进入/离开，便于指针从关键词移入卡片时保持显示。
class OutlineKeywordHoverCard extends StatelessWidget {
  /// 卡片宽度
  static const double width = 320;

  /// 标题区域高度估算（用于判断弹出方向）
  static const double _headerHeight = 86;

  /// 标题栏图片缩略图的边长
  static const double _headerImageSize = 54;

  /// 子节点行高估算
  static const double _rowHeight = 24;

  /// 子节点基础字号（正文节点）
  static const double _childFontSize = 13;

  /// 支持的标题级别上限
  ///
  /// 与大纲编辑器一致：H1~H3 逐级缩小字号，正文无偏移。
  static const int _maxHeadingLevel = 3;

  /// 子节点图片缩略图的最大宽度
  static const double _childImageMaxWidth = 150;

  /// 子节点图片缩略图的最大高度
  static const double _childImageMaxHeight = 110;

  /// 子节点备注最大行数
  static const int _childNoteMaxLines = 3;

  /// 子节点备注行高估算
  static const double _childNoteLineHeight = 17;

  /// 表格单元格基础字号
  static const double _childTableFontSize = 12;

  /// 表格单行高度估算
  static const double _childTableRowHeight = 26;

  /// 底部提示高度估算
  static const double _hintHeight = 38;

  /// 卡片与屏幕边缘的最小留白
  static const double screenMargin = 8;

  /// 关键词绑定的节点信息
  final OutlineKeywordEntry entry;

  /// 当前悬停关键词的颜色（用于标题区渐变与子节点圆点）
  final Color accentColor;

  /// 内容区最大高度
  final double maxHeight;

  /// 点击卡片跳转到对应节点
  final VoidCallback onTap;

  /// 指针进入卡片
  final VoidCallback? onMouseEnter;

  /// 指针离开卡片
  final VoidCallback? onMouseExit;

  /// 卡片完成布局后的实际高度回调
  ///
  /// 用于在卡片内容高于估算值时修正弹出位置，保证完整显示在屏幕内。
  final ValueChanged<double>? onMeasuredHeight;

  const OutlineKeywordHoverCard({
    super.key,
    required this.entry,
    required this.accentColor,
    required this.maxHeight,
    required this.onTap,
    this.onMouseEnter,
    this.onMouseExit,
    this.onMeasuredHeight,
  });

  /// 估算卡片实际高度（用于决定向上还是向下弹出）
  static double estimateHeight(OutlineKeywordEntry entry, double maxHeight) {
    double rowsHeight = 0;
    for (final child in entry.children) {
      // 不会渲染的子节点在估算时同样跳过
      if (!_shouldRenderChild(child)) continue;
      rowsHeight += _rowHeight + _headingHeightExtra(child.headingLevel);
      // 图片按最大展示高度估算，备注按字符数折算行数
      if (child.imagePath.isNotEmpty) {
        rowsHeight += 6 + _childImageMaxHeight;
      }
      if (child.note.isNotEmpty) {
        final int noteLines =
            (child.note.length / 26).ceil().clamp(1, _childNoteMaxLines).toInt();
        rowsHeight += 4 + noteLines * _childNoteLineHeight;
      }
      // 表格按行数估算高度，单元格换行带来的额外高度由实测回调修正
      if (child.table != null) {
        rowsHeight += 8 + child.table!.rowCount * _childTableRowHeight;
      }
    }
    final double estimated = _headerHeight + rowsHeight + _hintHeight;
    return estimated.clamp(_headerHeight + _hintHeight, maxHeight).toDouble();
  }

  /// 子节点是否需要渲染
  ///
  /// 文字为空但带有备注、图片或表格的节点同样展示，避免附加内容被丢弃。
  static bool _shouldRenderChild(OutlineKeywordSubNode child) =>
      child.text.isNotEmpty ||
      child.note.isNotEmpty ||
      child.imagePath.isNotEmpty ||
      child.table != null;

  /// 子节点字号：基础字号叠加标题级别偏移（H1 最大，正文无偏移）
  static double _childFontSizeFor(int headingLevel) {
    if (headingLevel <= 0 || headingLevel > _maxHeadingLevel) {
      return _childFontSize;
    }
    return _childFontSize + (_maxHeadingLevel - headingLevel + 1) * 2;
  }

  /// 标题级别带来的额外行高估算
  static double _headingHeightExtra(int headingLevel) =>
      (_childFontSizeFor(headingLevel) - _childFontSize) * 1.5;

  /// 表格单元格字号：与子节点一致，标题级别越高字号越大
  static double _tableCellFontSize(int headingLevel) {
    if (headingLevel <= 0 || headingLevel > _maxHeadingLevel) {
      return _childTableFontSize;
    }
    return _childTableFontSize + (_maxHeadingLevel - headingLevel + 1) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      // 卡片主体保持默认光标，仅底部跳转栏使用手型光标
      onEnter: (_) => onMouseEnter?.call(),
      onExit: (_) => onMouseExit?.call(),
      child: MeasureSize(
        // 上报实际高度，供外部按真实尺寸修正弹出位置
        onSizeChanged: (size) => onMeasuredHeight?.call(size.height),
        // 卡片整体吸收点击：点击落在卡片空白处时不会穿透到下方编辑器而收起卡片，
        // 同时保留内容区的拖动滚动与底部跳转栏的点击
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Material(
            color: colorScheme.surfaceContainerLowest,
            elevation: 12,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(colorScheme),
                  Flexible(child: _buildChildren(colorScheme)),
                  _buildHint(colorScheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建标题区：节点文本 + 所属设定项
  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          // 从左向右快速过渡：左侧保留关键词色，右侧尽早回到卡片底色
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            accentColor.withValues(alpha: 0.22),
            accentColor.withValues(alpha: 0.06),
            accentColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.32, 0.62],
        ),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 关键词色竖条，作为卡片的主色标识
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.nodeText.isEmpty ? '（空节点）' : entry.nodeText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        entry.settingItemTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 绑定节点带有图片时，在标题栏右侧空白处展示缩放后的缩略图
          if (entry.imagePath.isNotEmpty) ...[
            const SizedBox(width: 10),
            _buildHeaderImage(colorScheme),
          ],
        ],
      ),
    );
  }

  /// 构建标题栏图片缩略图
  ///
  /// 固定边长内等比填充并圆角裁剪；图片未同步到本机时显示占位图标。
  Widget _buildHeaderImage(ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _headerImageSize,
        height: _headerImageSize,
        child: Image.file(
          File(entry.imagePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(
            colorScheme,
            width: _headerImageSize,
            height: _headerImageSize,
          ),
        ),
      ),
    );
  }

  /// 构建子节点列表
  Widget _buildChildren(ColorScheme colorScheme) {
    final List<OutlineKeywordSubNode> children = entry.children
        .where(_shouldRenderChild)
        .toList();
    if (children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 24,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 8),
            Text(
              '该节点没有子节点',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final OutlineKeywordSubNode child = children[index];
        // 缩进以绑定节点为基准，子节点相对层级 1 对应一级缩进
        final double indent = (child.depth - 1).clamp(0, 8).toDouble() * 16.0;
        // 圆点与首行文字垂直居中，偏移随字号变化
        final double dotTop = _childFontSizeFor(child.headingLevel) * 0.75 - 2;
        return Padding(
          padding: EdgeInsets.only(
            left: 16 + indent,
            right: 16,
            top: 3,
            bottom: 6,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 4,
                margin: EdgeInsets.only(top: dotTop),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (child.text.isNotEmpty) _buildChildText(child, colorScheme),
                    // 子节点的图片、备注与表格顺序与大纲编辑器一致：图片在上、
                    // 备注居中、表格在下
                    if (child.imagePath.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildChildImage(child, colorScheme),
                    ],
                    if (child.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildChildNote(child, colorScheme),
                    ],
                    if (child.table != null) ...[
                      const SizedBox(height: 6),
                      _buildChildTable(child, colorScheme),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建子节点图片缩略图
  ///
  /// 在最大宽高范围内等比缩放，不裁剪图片；图片缺失时显示占位图标。
  Widget _buildChildImage(OutlineKeywordSubNode child, ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _childImageMaxWidth,
          maxHeight: _childImageMaxHeight,
        ),
        child: Image.file(
          File(child.imagePath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(
            colorScheme,
            width: 120,
            height: 70,
          ),
        ),
      ),
    );
  }

  /// 构建子节点备注
  ///
  /// 最多展示 [maxLines] 行，超出部分以省略号收尾。
  Widget _buildChildNote(OutlineKeywordSubNode child, ColorScheme colorScheme) {
    return Text(
      child.note,
      maxLines: _childNoteMaxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.45,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
      ),
    );
  }

  /// 构建子节点表格
  ///
  /// 按卡片可用宽度等分列宽，长文本自动换行；
  /// 首行作为表头带浅色底色，单元格还原自身的标题级别、对齐方式与文字样式。
  Widget _buildChildTable(OutlineKeywordSubNode child, ColorScheme colorScheme) {
    final OutlineTableData table = child.table!;
    if (table.rowCount == 0 || table.columnCount == 0) {
      return const SizedBox.shrink();
    }

    final Color gridColor = colorScheme.outlineVariant.withValues(alpha: 0.55);
    final TextAlign textAlign = switch (table.alignment) {
      OutlineTableAlignment.left => TextAlign.left,
      OutlineTableAlignment.center => TextAlign.center,
      OutlineTableAlignment.right => TextAlign.right,
    };

    // 表格圆角半径：外层裁剪与描边共用，保证圆角弧线与网格边界对齐
    const double tableRadius = 4;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tableRadius),
          // 仅绘制内部网格线；外框改由上层圆角描边绘制，
          // 避免方角外框被裁剪后圆角处出现断线
          child: Table(
            border: TableBorder.symmetric(
              inside: BorderSide(color: gridColor, width: 0.8),
            ),
            defaultColumnWidth: const FlexColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (int row = 0; row < table.rowCount; row++)
                TableRow(
                  // 首行作为表头，用浅色底与正文行区分
                  decoration: row == 0
                      ? BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        )
                      : null,
                  children: [
                    for (final OutlineTableCell cell in table.rows[row])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          cell.text,
                          textAlign: textAlign,
                          style: defaultStyleResolver(
                            TextStyle(
                              fontSize: _tableCellFontSize(cell.headingLevel),
                              height: 1.35,
                              color: colorScheme.onSurface.withValues(alpha: 0.9),
                            ),
                            cell.flags,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        // 外框绘制在表格之上，圆角四边完整可见，且压住表头底色与外层网格线
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tableRadius),
                border: Border.all(color: gridColor, width: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建图片缺失占位
  Widget _buildImagePlaceholder(
    ColorScheme colorScheme, {
    required double width,
    required double height,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
        child: Icon(
          Icons.broken_image_outlined,
          size: 24,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  /// 构建子节点文本
  ///
  /// 字号由标题级别决定，文字样式按记录的样式区间分段渲染
  /// （加粗、斜体、下划线、删除线、字体颜色、字底颜色）；
  /// 无有效样式区间时按默认文本渲染。
  Widget _buildChildText(OutlineKeywordSubNode child, ColorScheme colorScheme) {
    final TextStyle baseStyle = TextStyle(
      fontSize: _childFontSizeFor(child.headingLevel),
      height: 1.5,
      color: colorScheme.onSurface.withValues(alpha: 0.92),
    );

    final String text = child.text;
    final List<TextStyleRange> ranges = List<TextStyleRange>.of(
      child.styleRanges,
    )..sort((a, b) => a.start.compareTo(b.start));

    final List<TextSpan> spans = [];
    var currentPos = 0;
    for (final range in ranges) {
      if (range.flags.isEmpty) continue;
      final int start = range.start.clamp(0, text.length);
      final int end = range.end.clamp(0, text.length);
      // 跳过空区间与重叠区间，保证分段按文本顺序推进
      if (start >= end || start < currentPos) continue;
      if (currentPos < start) {
        spans.add(
          TextSpan(text: text.substring(currentPos, start), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: defaultStyleResolver(baseStyle, range.flags),
        ),
      );
      currentPos = end;
    }

    if (spans.isEmpty) return Text(text, style: baseStyle);

    if (currentPos < text.length) {
      spans.add(TextSpan(text: text.substring(currentPos), style: baseStyle));
    }
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }

  /// 构建底部跳转栏
  ///
  /// 仅此区域响应点击：指针进入时切换为手型光标，点击与点击关键词效果一致。
  /// 使用原始指针监听而非手势识别器，避免浮层中的点击被其它手势竞技场拦截。
  Widget _buildHint(ColorScheme colorScheme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => onTap(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              // 移动端没有键盘修饰键，仅展示跳转提示
              if (!PlatformCapabilities.isMobile) ...[
                _buildKeyCap(colorScheme),
                const SizedBox(width: 7),
              ],
              Text(
                '点击跳转到该节点',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建快捷键按键样式的小标签
  Widget _buildKeyCap(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        // 与正文编辑器的关键词修饰键保持一致：macOS 显示 Command 符号
        PlatformCapabilities.isMacOS ? '⌘' : 'Ctrl',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
