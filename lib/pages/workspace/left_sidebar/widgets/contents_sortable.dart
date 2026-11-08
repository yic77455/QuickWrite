import 'package:flutter/widgets.dart';
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
