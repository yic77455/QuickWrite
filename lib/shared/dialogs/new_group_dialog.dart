import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/bookshelf_provider.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示新建分组对话框
Future<void> showNewGroupDialog({
  required BuildContext context,
  VoidCallback? onCreated,
}) async {
  bool created = false;
  
  await showInputDialog(
    context: context,
    title: '新建分组',
    hintText: '请输入分组名称',
    confirmText: '创建',
    cancelText: '取消',
    onConfirm: (name) async {
      final result = await context.read<BookshelfProvider>().addGroup(name: name);
      if (result == 1) {
        return '分组名已存在';
      }
      created = true;
      onCreated?.call();
      return null;
    },
  );
  
  // 创建成功后显示提示
  if (created && context.mounted) {
    SnackBarService.show(context, '分组创建成功');
  }
}
