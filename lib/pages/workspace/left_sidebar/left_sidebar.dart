import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'panels/chapter_panel.dart';
import 'panels/setting_panel.dart';

/// 工作台左侧边栏组件
/// 
/// 包含章节目录和设定两个可切换的面板
/// 支持左右滑动切换面板
/// 支持平滑的展开/收起动画
class LeftSidebar extends StatefulWidget {
  const LeftSidebar({super.key});

  @override
  State<LeftSidebar> createState() => _LeftSidebarState();
}

class _LeftSidebarState extends State<LeftSidebar> with TickerProviderStateMixin {
  /// PageView 控制器，用于控制页面切换和监听滑动
  late PageController _pageController;
  
  /// 展开收起动画控制器
  late AnimationController _expandController;
  
  /// 展开收起动画对象
  late Animation<double> _expandAnimation;
  
  /// 当前页面索引，用于同步标签按钮和 PageView 状态
  int _currentPageIndex = 0;
  
  /// 是否正在通过程序控制切换页面（避免滑动时重复触发状态更新）
  bool _isProgrammaticPageChange = false;

  /// 上一次的展开状态，用于检测状态变化触发动画
  bool _lastExpanded = true;

  /// 上一次的标签页ID，用于检测标签页是否真正切换
  String? _lastTabId;

  @override
  void initState() {
    super.initState();
    // 初始化 PageController，初始页面为 0（章节页面）
    _pageController = PageController(initialPage: _currentPageIndex);
    
    // 初始化展开/收起动画控制器
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    // 创建动画曲线，使用 easeInOut 实现自然流畅的过渡效果
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
    
    // 默认展开状态，动画值为1.0
    _expandController.value = 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 监听 Provider 中的选中索引变化，同步更新 PageView
    final provider = context.watch<WorkspaceProvider>();
    if (provider.leftSidebarSelectedIndex != _currentPageIndex && !_isProgrammaticPageChange) {
      _syncPageFromProvider(provider.leftSidebarSelectedIndex);
    }
    
    // 根据当前标签页类型自动切换左侧边栏面板
    final currentTab = provider.currentTab;
    if (currentTab != null && currentTab.id != _lastTabId) {
      _lastTabId = currentTab.id;
      // 备份预览标签页不触发左侧边栏面板切换，保持当前状态不变
      if (currentTab.type != EditorTabType.backupPreview) {
        final isSettingTab = currentTab.type == EditorTabType.settings;
        final targetIndex = isSettingTab ? 1 : 0;
        if (targetIndex != _currentPageIndex && !_isProgrammaticPageChange) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            provider.setLeftSidebarSelectedIndex(targetIndex);
            _syncPageFromProvider(targetIndex);
          });
        }
      }
    }
    
    // 监听左侧边栏的展开/收起状态变化，只在状态改变时播放动画
    final isExpanded = provider.isLeftSidebarExpanded;
    if (isExpanded != _lastExpanded) {
      _lastExpanded = isExpanded;
      if (isExpanded) {
        _expandController.forward();  // 展开动画
      } else {
        _expandController.reverse();   // 收起动画
      }
    }
  }

  /// 从 Provider 同步页面索引到 PageView
  void _syncPageFromProvider(int index) {
    _currentPageIndex = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final isExpanded = workspaceProvider.isLeftSidebarExpanded;
    final width = workspaceProvider.leftSidebarWidth;

    // 使用 AnimatedBuilder 监听动画值变化，实时更新UI
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        // 获取当前动画进度值（0.0 - 1.0）
        final animationValue = _expandAnimation.value;
        
        // 根据展开状态和动画值计算实际宽度
        // 展开时：从 0 过渡到 width；收起时：从 width 过渡到 0
        final currentWidth = isExpanded ? width : 0.0;
        final effectiveWidth = currentWidth * animationValue;
        
        return Container(
          // 动态宽度：控制展开/收起效果
          width: effectiveWidth,
          // 边距也随动画缩放，保持视觉一致性
          margin: EdgeInsets.all(2 * animationValue),
          // 始终保留子组件在 widget 树中，通过 ClipRect 裁剪实现隐藏
          // 避免收起时 PageView 被移除导致状态丢失
          child: ClipRect(
            child: OverflowBox(
              minWidth: width,
              maxWidth: width,
              alignment: Alignment.centerLeft,
              child: child,
            ),
          ),
        );
      },
      // 子组件：构建完整的侧边栏内容（不受动画影响，避免重建）
      child: _buildSidebarContent(context, workspaceProvider),
    );
  }

  /// 构建完整的侧边栏内容
  Widget _buildSidebarContent(BuildContext context, WorkspaceProvider workspaceProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // 左侧边栏顶部切换按钮
          _buildSidebarHeader(context, workspaceProvider),
          
          // 面板内容区域
          Expanded(
            child: _buildSwipeablePanelContent(context, workspaceProvider),
          ),
        ],
      ),
    );
  }

  /// 构建侧边栏顶部切换按钮
  Widget _buildSidebarHeader(BuildContext context, WorkspaceProvider provider) {
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
      child: Row(
        children: [
          // 标签切换按钮（自适应宽度）
          Expanded(
            child: _buildTabButtons(context, provider),
          ),
        ],
      ),
    );
  }

  /// 构建标签切换按钮组（iOS 分段控制器风格）
  Widget _buildTabButtons(BuildContext context, WorkspaceProvider provider) {
    return SegmentedControl(
      labels: const ['章节', '设定'],
      selectedIndex: _currentPageIndex,
      onChanged: (index) => _onTabPressed(index, provider),
    );
  }

  /// 标签按钮点击处理
  /// 点击标签时，切换 PageView 到对应页面
  void _onTabPressed(int index, WorkspaceProvider provider) {
    if (_currentPageIndex == index) return;
    
    // 更新 Provider 状态
    provider.setLeftSidebarSelectedIndex(index);
    
    // 标记为程序控制切换，避免 didChangeDependencies 中重复触发
    setState(() {
      _isProgrammaticPageChange = true;
      _currentPageIndex = index;
    });
    
    // 使用 animateToPage 实现平滑过渡
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    ).then((_) {
      if (mounted) {
        setState(() {
          _isProgrammaticPageChange = false;
        });
      }
    });
  }

  /// 构建可滑动的面板内容区域
  /// 使用 PageView 实现左右滑动切换效果
  Widget _buildSwipeablePanelContent(BuildContext context, WorkspaceProvider provider) {
    return PageView(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (index) {
        // 滑动切换时更新状态
        if (!_isProgrammaticPageChange) {
          setState(() {
            _currentPageIndex = index;
          });
          // 同步更新 Provider 状态
          provider.setLeftSidebarSelectedIndex(index);
        }
      },
      children: const [
        ChapterPanel(),
        SettingPanel(),
      ],
    );
  }
}
