import 'package:flutter/material.dart';
import 'package:quick_write/core/models/outline_table.dart';
import 'package:quick_write/core/utils/text_style_range.dart';

/// 移动端快捷操作栏的样式操作目标
///
/// 大纲节点与表格单元格共用同一套「文字格式 / 字体颜色 / 字底颜色」面板，
/// 各自的编辑器状态实现本接口，面板只面向接口取值与下发操作。
abstract class MobileToolbarStyleTarget {
  /// 当前统一的标题级别（0=正文，1~3=标题，不一致时为 -1）
  int get currentHeadingLevel;

  /// 当前合并后的文字样式标记
  TextStyleFlags get currentTextStyleFlags;

  /// 当前字体颜色或字底颜色
  ({bool isUniform, Color? color}) currentColor({required bool isForeground});

  /// 设置目标内容的标题级别
  void setHeadingLevel(int level);

  /// 按主导样式切换文字样式
  void toggleTextStyle(TextStyleFlags Function(TextStyleFlags) toggleFn);

  /// 设置或清除字体颜色与字底颜色
  void applyColor({
    Color? foregroundColor,
    Color? backgroundColor,
    bool clearForeground = false,
    bool clearBackground = false,
  });
}

/// 移动端表格单元格快捷操作栏的数据源
///
/// 由表格组件的状态实现，工具栏通过 [MobileTableToolbarController] 间接访问，
/// 避免把表格内部状态暴露给工具栏所在的兄弟子树。
abstract class MobileTableToolbarSource implements MobileToolbarStyleTarget {
  /// 是否处于单元格批量选择模式
  bool get isBatchMode;

  /// 当前样式操作覆盖的单元格数量
  int get selectedCellCount;

  /// 整表水平对齐方式
  OutlineTableAlignment get alignment;

  /// 是否可以删除当前行
  bool get canDeleteRow;

  /// 是否可以删除当前列
  bool get canDeleteColumn;

  /// 设置整表水平对齐方式
  void setAlignment(OutlineTableAlignment alignment);

  /// 清空选中单元格的内容
  void clearContents();

  /// 进入单元格批量选择模式
  void enterBatchMode();

  /// 退出单元格批量选择模式
  void exitBatchMode();

  /// 取消单元格选中并收起快捷栏
  void dismiss();

  /// 删除活动单元格所在行
  void deleteRow();

  /// 删除活动单元格所在列
  void deleteColumn();

  /// 删除整张表格
  void deleteTable();
}

/// 移动端表格单元格快捷操作栏控制器
///
/// 包装 [MobileTableToolbarSource] 并提供变更通知；表格状态在每次重建后调用
/// [refresh]，让底部工具栏重新读取样式点亮状态与批量模式。
class MobileTableToolbarController extends ChangeNotifier
    implements MobileTableToolbarSource {
  MobileTableToolbarController({required this.source});

  /// 工具栏操作与状态的真实实现
  final MobileTableToolbarSource source;

  /// 表格所属标签页 ID，用于标签页切走时收起工具栏
  String? tabId;

  /// 通知工具栏重新读取状态
  void refresh() => notifyListeners();

  @override
  bool get isBatchMode => source.isBatchMode;

  @override
  int get selectedCellCount => source.selectedCellCount;

  @override
  OutlineTableAlignment get alignment => source.alignment;

  @override
  bool get canDeleteRow => source.canDeleteRow;

  @override
  bool get canDeleteColumn => source.canDeleteColumn;

  @override
  int get currentHeadingLevel => source.currentHeadingLevel;

  @override
  TextStyleFlags get currentTextStyleFlags => source.currentTextStyleFlags;

  @override
  ({bool isUniform, Color? color}) currentColor({required bool isForeground}) =>
      source.currentColor(isForeground: isForeground);

  @override
  void setHeadingLevel(int level) => source.setHeadingLevel(level);

  @override
  void toggleTextStyle(TextStyleFlags Function(TextStyleFlags) toggleFn) =>
      source.toggleTextStyle(toggleFn);

  @override
  void applyColor({
    Color? foregroundColor,
    Color? backgroundColor,
    bool clearForeground = false,
    bool clearBackground = false,
  }) =>
      source.applyColor(
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
        clearForeground: clearForeground,
        clearBackground: clearBackground,
      );

  @override
  void setAlignment(OutlineTableAlignment alignment) => source.setAlignment(alignment);

  @override
  void clearContents() => source.clearContents();

  @override
  void enterBatchMode() => source.enterBatchMode();

  @override
  void exitBatchMode() => source.exitBatchMode();

  @override
  void dismiss() => source.dismiss();

  @override
  void deleteRow() => source.deleteRow();

  @override
  void deleteColumn() => source.deleteColumn();

  @override
  void deleteTable() => source.deleteTable();
}

/// 移动端表格工具栏绑定
///
/// 表格组件位于大纲列表内部，快捷操作栏位于工作台外层，两者不是父子关系，
/// 因此用一个全局「当前激活的表格工具栏」把二者连起来。同一时刻只有一个
/// 表格处于选中状态，切换标签页或选中态结束时由表格组件主动解绑。
class MobileTableToolbarBinding {
  MobileTableToolbarBinding._();

  /// 当前激活的表格工具栏控制器，null 表示没有选中的表格单元格
  static final ValueNotifier<MobileTableToolbarController?> active =
      ValueNotifier<MobileTableToolbarController?>(null);

  /// 绑定表格工具栏
  ///
  /// 同一时刻只允许一张表格处于选中态，切换到另一张表格时
  /// 先清除旧表格的选中态，避免两张表格同时显示高亮边框。
  static void attach(MobileTableToolbarController controller) {
    if (active.value == controller) return;
    final MobileTableToolbarController? previous = active.value;
    active.value = controller;
    previous?.dismiss();
  }

  /// 解绑表格工具栏
  ///
  /// 仅当当前绑定确实是该控制器时才清除，避免旧表格销毁时误清新表格的选中态。
  static void detach(MobileTableToolbarController? controller) {
    if (controller == null || active.value != controller) return;
    active.value = null;
  }
}
