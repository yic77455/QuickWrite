/// 拖拽排序索引转换工具
///
/// 用于在倒序显示的列表中，将 ReorderableListView 的 onReorder 回调索引
/// 从显示列表映射回原始数据列表，确保拖拽操作作用于正确的数据项。
library;

/// 将 ReorderableListView 的拖拽索引从显示列表映射到原始数据列表。
///
/// [displayOldIndex] onReorder 回调中被拖动项在显示列表中的索引。
/// [displayNewIndex] onReorder 回调中目标位置在显示列表中的索引。
/// [length] 列表长度。
/// [reversed] 当前是否处于倒序显示状态。
///
/// 返回转换后的数据列表索引 [dataOldIndex] 与 [dataNewIndex]。
///
/// 倒序时显示列表是数据列表的反转，索引映射规则为：
/// - 被拖动项：`dataOldIndex = length - 1 - displayOldIndex`
/// - 目标位置：`dataNewIndex = length - displayNewIndex`
///
/// 目标位置的公式考虑了 onReorder 回调中 newIndex 表示"插入到该位置之前"的语义，
/// 反转后该插入点对应数据列表中的 `length - displayNewIndex` 位置。
({int dataOldIndex, int dataNewIndex}) mapReorderIndices({
  required int displayOldIndex,
  required int displayNewIndex,
  required int length,
  required bool reversed,
}) {
  if (!reversed) {
    return (dataOldIndex: displayOldIndex, dataNewIndex: displayNewIndex);
  }
  return (
    dataOldIndex: length - 1 - displayOldIndex,
    dataNewIndex: length - displayNewIndex,
  );
}
