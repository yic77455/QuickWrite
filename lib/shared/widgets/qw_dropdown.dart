import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 下拉框选项数据结构
class DropdownItem {
  /// 选项显示的文本
  final String displayText;
  
  /// 选项的值
  final String value;

  const DropdownItem({
    required this.displayText,
    required this.value,
  });
}

/// 下拉框容器
class CustomDropdown extends StatefulWidget {
  /// 下拉框触发器的宽度
  final double width;
  
  /// 当前选中的值
  final String value;
  
  /// 下拉菜单的选项列表
  final List<DropdownItem> items;
  
  /// 选择后的回调
  final ValueChanged<String> onChanged;

  const CustomDropdown({
    super.key, 
    required this.width,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  State<CustomDropdown> createState() => _CustomDropdownState();
}

class _CustomDropdownState extends State<CustomDropdown> {
  bool _isHovered = false;

  // 增加内部状态，用于UI的实时更新响应
  late String _currentValue;

  // 用来跟踪当前选中项位置的 Key
  final GlobalKey _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  // 当外部配置改变时，同步更新内部状态
  @override
  void didUpdateWidget(CustomDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _currentValue = widget.value;
    }
  }

  // 获取当前选中项的显示文本
  String _getCurrentDisplayText() {
    final item = widget.items.firstWhere(
      (item) => item.value == _currentValue,
      orElse: () => DropdownItem(
        displayText: _currentValue,
        value: _currentValue,
      ),
    );
    return item.displayText;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = context.bodySmall?.copyWith(color: colorScheme.onSurface);
    
    // 使用 LayoutBuilder 获取父容器的实际宽度
    // 当 width 为 double.infinity 时，用实际约束宽度来设置菜单尺寸，避免定位错误
    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算实际可用宽度：如果传入的是 double.infinity，则使用约束宽度
        final double actualWidth = widget.width.isInfinite 
            ? constraints.maxWidth 
            : widget.width;
        
        return MenuAnchor(
          // 修正对齐
          alignmentOffset: const Offset(2, 2),
          // 监听下拉菜单展开事件，自动滚动定位
          onOpen: () {
            // 延迟 50 毫秒，等待弹窗彻底构建完成并挂载到渲染树上
            Future.delayed(const Duration(milliseconds: 50), () {
              if (_selectedKey.currentContext != null) {
                Scrollable.ensureVisible(
                  _selectedKey.currentContext!,
                  alignment: 0.5, // 0.5 代表将该元素滚动到可视区域的正中间
                  // duration: const Duration(milliseconds: 100),
                  curve: Curves.easeInOut,
                );
              }
            });
          },
          // 设置下拉菜单弹窗的样式
          style: MenuStyle(
            // 限制弹窗的最大高度，防止选项过多时占满全屏
            maximumSize: WidgetStateProperty.all(const Size(double.infinity, 250)),
            // 让下拉弹窗的最小宽度使用实际测量宽度，确保定位正确
            minimumSize: WidgetStateProperty.all(Size(actualWidth, 0)),
            padding: WidgetStateProperty.all(EdgeInsets.zero),
            elevation: WidgetStateProperty.all(3), // 稍微减弱一点阴影让边缘看起来更清晰
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          
          // 将 AnimatedContainer 作为触发器
          builder: (BuildContext context, MenuController controller, Widget? child) {
            return MouseRegion(
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: GestureDetector(
                // 点击控制下拉框的开闭
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: AnimatedContainer(
                  width: widget.width,
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  duration: const Duration(milliseconds: 100),
                  decoration: BoxDecoration(
                    color: (_isHovered || controller.isOpen) // 展开时也保持高亮背景色
                        ? colorScheme.surfaceContainerHighest
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(width: 4),
                      // 左侧文字
                      Expanded(
                        child: Text(
                          _getCurrentDisplayText(), // 使用内部状态
                          style: textStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 右侧箭头
                      AnimatedRotation(
                        turns: controller.isOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 50),
                        child: Icon(
                          Icons.arrow_drop_down,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          
          // 构建下拉菜单的选项
          menuChildren: widget.items.map((DropdownItem item) {
            // 判断当前项是否被选中
            final bool isSelected = item.value == _currentValue;
            return MenuItemButton(
              // 如果当前项是选中项，就把 Key 挂在它身上
              key: isSelected ? _selectedKey : null,
              style: ButtonStyle(
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16), // 下拉菜单项的内边距
                ),
                minimumSize: WidgetStateProperty.all(
                  Size(actualWidth, 36), // 下拉菜单项使用实际宽度
                ),
                // 高亮当前选中项的背景色
                backgroundColor: WidgetStateProperty.all(
                  isSelected 
                      ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.7) 
                      : Colors.transparent,
                ),
              ),
              onPressed: () {
                setState(() {
                  _currentValue = item.value;
                });
                widget.onChanged(item.value);
              },
              child: Text(
                item.displayText,
                style: context.bodySmall?.copyWith(
                  // 如果选中，字体颜色给予高亮强调
                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}