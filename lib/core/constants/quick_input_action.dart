import 'package:flutter/material.dart';

/// 移动端快捷输入栏右侧可选的操作图标
///
/// 每个动作同时提供图标、显示名称与持久化标识，
/// 供快捷输入栏渲染按钮、供设置面板生成选项列表。
enum QuickInputAction {
  /// 关键词高亮开关
  keywordToggle('keywordToggle', Icons.sell_outlined, '关键词高亮'),

  /// 其他设置入口
  settings('settings', Icons.settings_rounded, '其他设置'),

  /// 查找替换
  findReplace('findReplace', Icons.find_replace_rounded, '查找替换'),

  /// 全文搜索
  fullTextSearch('fullTextSearch', Icons.search_rounded, '全文搜索'),

  /// 随机取名
  randomName('randomName', Icons.casino_rounded, '随机取名');

  /// 持久化到配置文件的标识
  final String id;

  /// 按钮图标
  final IconData icon;

  /// 显示名称，同时用作按钮的悬浮提示
  final String label;

  const QuickInputAction(this.id, this.icon, this.label);

  /// 默认显示在左侧的动作
  static const QuickInputAction defaultLeft = QuickInputAction.keywordToggle;

  /// 默认显示在右侧的动作
  static const QuickInputAction defaultRight = QuickInputAction.settings;

  /// 按持久化标识解析动作
  ///
  /// 标识为空或无法识别时回退到 [fallback]，兼容配置文件缺失该字段的情况
  static QuickInputAction fromId(String? id, {required QuickInputAction fallback}) {
    for (final action in QuickInputAction.values) {
      if (action.id == id) return action;
    }
    return fallback;
  }
}
