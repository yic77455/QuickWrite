import 'package:flutter/material.dart';

/// 移动端页面切换动画时长
const Duration mobilePageTransitionDuration = Duration(milliseconds: 260);

/// 移动端页面进入时的缓动曲线：快起慢停
const Curve mobilePageTransitionCurve = Curves.easeOutCubic;

/// 移动端页面退出时的缓动曲线：慢起快离，与进入曲线互为时间镜像
const Curve mobilePageTransitionReverseCurve = Curves.easeInCubic;

/// 构建移动端页面滑入/滑出动画
///
/// 页面从右侧滑入，返回时向右侧滑出，供路由页面统一使用
Widget buildMobileSlideTransition(Animation<double> animation, Widget child) {
  return SlideTransition(
    position: Tween(begin: const Offset(1, 0), end: Offset.zero)
        .chain(CurveTween(curve: mobilePageTransitionCurve))
        .animate(animation),
    child: child,
  );
}

/// 移动端页面容器
///
/// 与 IndexedStack 一样始终保留全部页面的状态，但在主页面与子页面之间切换时
/// 播放滑动动效：进入子页面时子页面从右侧滑入，返回主页面时子页面向右侧滑出；
/// 主页面之间的切换（如底部导航切换）不带动效，直接替换显示。
class MobilePageStack extends StatefulWidget {
  const MobilePageStack({
    super.key,
    required this.index,
    required this.subPageIndices,
    required this.children,
  });

  /// 当前显示的页面索引
  final int index;

  /// 子页面在 [children] 中的索引集合
  final Set<int> subPageIndices;

  /// 全部页面，下标与 [index] 对应
  final List<Widget> children;

  @override
  State<MobilePageStack> createState() => _MobilePageStackState();
}

class _MobilePageStackState extends State<MobilePageStack> with SingleTickerProviderStateMixin {
  /// 切换进度控制器：0 为切换起始，1 为切换结束
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: mobilePageTransitionDuration,
  );

  /// 当前显示的页面索引
  late int _currentIndex;

  /// 上一页面的索引，仅在动效播放期间有值
  int? _previousIndex;

  /// 当前动效是否为进入子页面（子页面滑入），否则为返回主页面（子页面滑出）
  bool _isEntering = true;

  /// 各页面的绘制顺序：主页面在下、子页面在上，
  /// 使子页面滑动时始终覆盖在主页面之上；顺序固定，保证页面组件在重建中被复用
  late final List<int> _paintOrder = [
    for (var i = 0; i < widget.children.length; i++)
      if (!widget.subPageIndices.contains(i)) i,
    for (var i = 0; i < widget.children.length; i++)
      if (widget.subPageIndices.contains(i)) i,
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _controller.addStatusListener(_handleStatusChanged);
  }

  @override
  void didUpdateWidget(covariant MobilePageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == _currentIndex) return;

    // 仅主页面与子页面之间切换时播放动效
    final bool isSubPageSwitch =
        widget.subPageIndices.contains(_currentIndex) != widget.subPageIndices.contains(widget.index);
    if (!isSubPageSwitch) {
      _previousIndex = null;
      _currentIndex = widget.index;
      _controller.value = 1;
      return;
    }

    // 目标页面为子页面时子页面滑入，否则为子页面向右滑出
    _isEntering = !widget.subPageIndices.contains(_currentIndex);
    _previousIndex = _currentIndex;
    _currentIndex = widget.index;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 动效播放结束后移除已滑出的页面
  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && _previousIndex != null) {
      setState(() => _previousIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 各页面自身不绘制背景，统一取页面底色为每层铺底
    final Color pageBackground = Theme.of(context).scaffoldBackgroundColor;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => IgnorePointer(
        // 动效播放期间屏蔽触摸，避免误触背后正在滑动或已就位的页面
        ignoring: _previousIndex != null,
        child: Stack(
          children: [
            for (final index in _paintOrder) _buildLayer(index, pageBackground),
          ],
        ),
      ),
    );
  }

  /// 构建单个页面层
  ///
  /// 隐藏的页面同样保留在组件树中，避免丢失滚动位置等页面状态；
  /// 各层结构保持一致，仅在动效播放期间平移滑动页。
  Widget _buildLayer(int index, Color background) {
    final int? previousIndex = _previousIndex;

    // 动效播放期间参与滑动的页面：进入子页面时为当前页，返回主页面时为上一页
    final bool isSliding =
        previousIndex != null && index == (_isEntering ? _currentIndex : previousIndex);

    // 动效播放期间静止页与滑动页同时可见，其余情况仅显示当前页
    final bool isVisible = previousIndex != null
        ? index == _currentIndex || index == previousIndex
        : index == _currentIndex;

    double dx = 0;
    if (isSliding) {
      // 进度 0 时滑动页停在滑动起点，进度 1 时到达终点
      final double progress = _controller.value;
      dx = _isEntering
          ? 1 - mobilePageTransitionCurve.transform(progress)
          : mobilePageTransitionReverseCurve.transform(progress);
    }

    return Offstage(
      offstage: !isVisible,
      // 仅当前显示的页面可获得焦点：切换页面时立即释放旧页面内输入框的焦点，
      // 避免离屏页面的输入框仍持有焦点，在焦点恢复时重新弹出键盘
      child: ExcludeFocus(
        excluding: index != _currentIndex,
        child: FractionalTranslation(
          // 平移量按页面宽度计算，dx 为 1 时页面刚好移出屏幕右侧
          translation: Offset(dx, 0),
          // 页面内容加绘制隔离：平移只改变图层位置，滑动期间可直接复用已缓存的图层
          child: RepaintBoundary(
            // 为页面铺上底色，避免动效期间滑动页透出下层页面，
            // 同时作为页面内水波纹的绘制载体
            child: Material(color: background, child: widget.children[index]),
          ),
        ),
      ),
    );
  }
}
