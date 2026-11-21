import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/reorder_utils.dart';

/// 目录列表中的一行
///
/// [itemUuid] 为空表示分组标题行，非空表示条目行。
class ContentsRow {
  const ContentsRow({
    required this.key,
    required this.groupUuid,
    required this.extent,
    this.itemUuid,
  });

  /// 行稳定标识（标题行为 `h:<分组UUID>`，条目行为 `i:<条目UUID>`）
  final String key;

  /// 标题行：自身分组 UUID；条目行：所属分组 UUID（空字符串表示未分组）
  final String groupUuid;

  /// 行高
  final double extent;

  /// 条目行对应的数据项 UUID（标题行为 null）
  final String? itemUuid;

  /// 是否为分组标题行
  bool get isHeader => itemUuid == null;
}

/// 计算标题行拖拽后应移动到的数据分组位置
///
/// 返回的索引为数据分组顺序，与 onReorder 语义一致，可直接交给分卷/分组排序方法。
/// 返回 null 表示该行不是可排序的分组标题。
({int oldDataIndex, int newDataIndex})? resolveHeaderReorder({
  required List<ContentsRow> rows,
  required int oldIndex,
  required int newIndex,
  required bool reversed,
}) {
  if (oldIndex < 0 || oldIndex >= rows.length) return null;

  final dragKey = rows[oldIndex].key;
  // 参与排序的仅有实际分组标题，未分组/未分卷标题固定在最末，不参与排序
  final headerKeys = rows
      .where((row) => row.isHeader && row.groupUuid.isNotEmpty)
      .map((row) => row.key)
      .toList();
  final oldDisplayIndex = headerKeys.indexOf(dragKey);
  if (oldDisplayIndex < 0) return null;

  // 插入点位于被拖拽行移除后的行序列中
  final remainingRows = <ContentsRow>[
    for (var i = 0; i < rows.length; i++)
      if (i != oldIndex) rows[i],
  ];
  final insertPos = (oldIndex < newIndex ? newIndex - 1 : newIndex).clamp(0, remainingRows.length);
  final targetDisplayIndex = remainingRows
      .take(insertPos)
      .where((row) => row.isHeader && row.groupUuid.isNotEmpty)
      .length
      .clamp(0, headerKeys.length);

  // 换算回被拖拽行仍在原位时的索引语义
  final rawNewIndex = oldDisplayIndex < targetDisplayIndex ? targetDisplayIndex + 1 : targetDisplayIndex;
  final mapped = mapReorderIndices(
    displayOldIndex: oldDisplayIndex,
    displayNewIndex: rawNewIndex,
    length: headerKeys.length,
    reversed: reversed,
  );
  return (oldDataIndex: mapped.dataOldIndex, newDataIndex: mapped.dataNewIndex);
}

/// 计算条目行拖拽后的投放目标分组与组内插入位置
///
/// [position] 为目标分组显示顺序中的插入位置，此时被拖拽行已从列表中移除。
({String groupUuid, int position})? resolveItemDropTarget({
  required List<ContentsRow> rows,
  required int oldIndex,
  required int newIndex,
}) {
  if (oldIndex < 0 || oldIndex >= rows.length) return null;

  final insertPos = (oldIndex < newIndex ? newIndex - 1 : newIndex).clamp(0, rows.length);
  // 移除被拖拽行后的行序列，用于按落点定位目标分组
  final remainingRows = <ContentsRow>[
    for (var i = 0; i < rows.length; i++)
      if (i != oldIndex) rows[i],
  ];
  if (remainingRows.isEmpty) return null;

  // 落点前一行所属的分组即目标分组；落在首行之前时归入首行所在分组
  final String groupUuid;
  if (insertPos <= 0) {
    groupUuid = remainingRows.first.groupUuid;
  } else {
    groupUuid = remainingRows[insertPos - 1].groupUuid;
  }

  final position = remainingRows
      .take(insertPos.clamp(0, remainingRows.length))
      .where((row) => !row.isHeader && row.groupUuid == groupUuid)
      .length;
  return (groupUuid: groupUuid, position: position);
}

/// 计算条目行在其所属分组显示顺序中的索引
int itemDisplayIndexInGroup(List<ContentsRow> rows, int flatIndex) {
  if (flatIndex < 0 || flatIndex >= rows.length) return 0;

  final row = rows[flatIndex];
  var index = 0;
  for (var i = 0; i < flatIndex; i++) {
    final current = rows[i];
    if (!current.isHeader && current.groupUuid == row.groupUuid) {
      index++;
    }
  }
  return index;
}

/// 将目标插入位置换算为被拖拽行仍在原位时的索引语义
int rawReorderIndex(int oldIndex, int targetIndex) {
  return oldIndex < targetIndex ? targetIndex + 1 : targetIndex;
}

/// 拖拽代理中行底色相对整行的内缩量
///
/// 目录行内容自带水平 4、垂直 1 的外边距，抬起底色需按同样边距内缩，
/// 才能贴合行自身的圆角范围，不会在四周露出多余的底色块。
const EdgeInsets _kProxyTintInset = EdgeInsets.symmetric(horizontal: 4, vertical: 1);

/// 构建目录列表的拖拽代理装饰器
///
/// 代理渲染在 Overlay 中，目录行自身没有底色，
/// 因此由代理在行范围内绘制与桌面端悬停态一致的底色，
/// 并按抬起进度叠加阴影与轻微缩放，双端拖拽呈现同样的抬升效果。
/// [scrollController] 用于在代理上接收滚轮事件并驱动列表滚动：
/// 代理已脱离列表，无法再触发列表自身的滚动。
Widget buildContentsReorderProxyDecorator({
  required ScrollController scrollController,
  required Widget child,
  required Animation<double> animation,
}) {
  return Listener(
    onPointerSignal: (PointerSignalEvent event) {
      // 在代理元素上捕获滚轮事件并手动驱动滚动
      if (event is PointerScrollEvent && scrollController.hasClients) {
        final double maxScroll = scrollController.position.maxScrollExtent;
        final double newOffset = (scrollController.offset + event.scrollDelta.dy)
            .clamp(0.0, maxScroll);
        scrollController.jumpTo(newOffset);
      }
    },
    child: AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final theme = Theme.of(context);
        // 根据动画进度计算曲线插值
        final double animValue = Curves.easeInOut.transform(animation.value);
        // 拖拽时增加阴影高度
        final double elevation = lerpDouble(0, 6, animValue)!;
        // 拖拽时略微放大元素
        final double scale = lerpDouble(1, 1.02, animValue)!;
        // 底色随抬起进度淡入，与桌面端悬停时的行底色完全一致
        final Color tintColor = theme.hoverColor.withValues(alpha: animValue);

        return Transform.scale(
          scale: scale,
          child: Material(
            elevation: elevation,
            color: Colors.transparent,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.3),
            child: Stack(
              children: [
                // 底色垫在行内容之下，并按行外边距内缩，避免在行四周多出一圈背景
                Positioned.fill(
                  child: Padding(
                    padding: _kProxyTintInset,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tintColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                child!,
              ],
            ),
          ),
        );
      },
      child: child,
    ),
  );
}

/// 目录拖拽排序的状态管理与提交分发
///
/// 拖拽标题期间列表统一折叠所有分组（见 [isHeaderSorting]），
/// 拖拽结束后由 [handleContentsReorderCompleted] 恢复。
mixin ContentsSortMixin<T extends StatefulWidget> on State<T> {
  /// 正在拖拽的行标识（null 表示没有拖拽进行中）
  String? draggingContentsRowKey;

  /// 正在拖拽的分组标题的分组 UUID（非空表示当前拖拽的是标题行）
  String? draggingHeaderGroupUuid;

  /// 是否正在拖拽分组标题，此期间列表应折叠所有分组
  bool get isHeaderSorting => draggingHeaderGroupUuid != null;

  /// 是否正在拖拽任意行
  bool get isContentsSorting => draggingContentsRowKey != null;

  /// 构建当前显示的行
  List<ContentsRow> buildContentsRows();

  /// 是否倒序显示
  bool get contentsReversed;

  /// 提交标题行排序，索引为数据分组顺序
  void applyContentsHeaderReorder({required int oldDataIndex, required int newDataIndex});

  /// 提交条目行的组内排序或跨组移动
  ///
  /// [position] 为目标分组显示顺序中的插入位置；
  /// [oldIndexInGroup] 为条目在原分组显示顺序中的索引。
  void applyContentsItemReorder({
    required ContentsRow row,
    required String targetGroupUuid,
    required int position,
    required int oldIndexInGroup,
    required bool sameGroup,
  });

  /// 拖拽开始：记录被拖拽行，标题行拖拽期间折叠所有分组
  void handleContentsReorderStart(int index) {
    final rows = buildContentsRows();
    if (index < 0 || index >= rows.length) return;

    final row = rows[index];
    setState(() {
      draggingContentsRowKey = row.key;
      draggingHeaderGroupUuid = row.isHeader ? row.groupUuid : null;
    });
  }

  /// 拖拽排序提交：按行类型分发到标题排序或条目移动
  void handleContentsReorder(int oldIndex, int newIndex) {
    final rows = buildContentsRows();
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    if (newIndex < 0 || newIndex > rows.length) return;

    final row = rows[oldIndex];
    if (row.isHeader) {
      final resolved = resolveHeaderReorder(
        rows: rows,
        oldIndex: oldIndex,
        newIndex: newIndex,
        reversed: contentsReversed,
      );
      if (resolved == null) return;
      applyContentsHeaderReorder(
        oldDataIndex: resolved.oldDataIndex,
        newDataIndex: resolved.newDataIndex,
      );
      return;
    }

    final target = resolveItemDropTarget(rows: rows, oldIndex: oldIndex, newIndex: newIndex);
    if (target == null) return;

    applyContentsItemReorder(
      row: row,
      targetGroupUuid: target.groupUuid,
      position: target.position,
      oldIndexInGroup: itemDisplayIndexInGroup(rows, oldIndex),
      sameGroup: row.groupUuid == target.groupUuid,
    );
  }

  /// 拖拽彻底结束：恢复拖拽期间折叠的分组
  void handleContentsReorderCompleted() {
    if (draggingContentsRowKey == null) return;

    setState(() {
      draggingContentsRowKey = null;
      draggingHeaderGroupUuid = null;
    });
  }
}
