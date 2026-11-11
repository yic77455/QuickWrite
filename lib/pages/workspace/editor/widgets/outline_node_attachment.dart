import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/persistent_selection.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 大纲节点的附加备注区
///
/// 图片在备注上方显示缩略图，备注未编辑时只显示首行并以省略号收尾；
/// 图片点击后进入选中态，选中蒙版中央提供放大按钮，右下角按钮或删除键
/// 可移除图片。备注与图片均不存在且未处于编辑状态时不显示本区域。
class OutlineNodeAttachment extends StatefulWidget {
  /// 备注文本
  final String note;

  /// 图片文件的绝对路径（空字符串表示没有图片）
  final String imagePath;

  /// 颜色方案
  final ColorScheme colorScheme;

  /// 备注文字字号
  final double noteFontSize;

  /// 节点文字相对输入框左边缘的水平偏移
  ///
  /// 附加备注区据此与节点文字左边缘对齐，而不是与输入框边缘对齐。
  final double textLeftInset;

  /// 是否只读
  final bool readOnly;

  /// 是否正在编辑备注
  ///
  /// 为 true 时备注区显示完整的多行输入框并自动获取焦点。
  final bool isEditingNote;

  /// 备注内容变化回调
  final ValueChanged<String> onNoteChanged;

  /// 开始编辑备注回调
  final VoidCallback onStartNoteEdit;

  /// 结束编辑备注回调
  final VoidCallback onStopNoteEdit;

  /// 删除图片回调
  final VoidCallback onDeleteImage;

  const OutlineNodeAttachment({
    super.key,
    required this.note,
    required this.imagePath,
    required this.colorScheme,
    required this.noteFontSize,
    required this.textLeftInset,
    required this.readOnly,
    required this.isEditingNote,
    required this.onNoteChanged,
    required this.onStartNoteEdit,
    required this.onStopNoteEdit,
    required this.onDeleteImage,
  });

  @override
  State<OutlineNodeAttachment> createState() => _OutlineNodeAttachmentState();
}

class _OutlineNodeAttachmentState extends State<OutlineNodeAttachment> {
  /// 图片缩略图的最大宽度
  static const double _thumbnailMaxWidth = 200.0;

  /// 图片缩略图的最大高度
  static const double _thumbnailMaxHeight = 200.0;

  /// 图片缩略图向左补偿的像素
  static const double _thumbnailBorderInset = 4.0;

  /// 放大按钮的尺寸
  static const double _zoomButtonSize = 56.0;

  /// 删除按钮的尺寸
  static const double _deleteButtonSize = 28.0;

  /// 图片原始像素尺寸（null 表示尚未解析完成）
  Size? _imagePixelSize;

  /// 正在监听的图片流
  ImageStream? _imageStream;

  /// 图片流监听器
  ImageStreamListener? _imageStreamListener;

  /// 备注输入框控制器
  final TextEditingController _noteController = TextEditingController();

  /// 备注输入框的全局键
  ///
  /// 用于在进入编辑状态后把点击位置换算成文字偏移量。
  final GlobalKey _noteFieldKey = GlobalKey();

  /// 备注输入框焦点节点
  final FocusNode _noteFocusNode = FocusNode();

  /// 图片区域焦点节点
  ///
  /// 图片被选中时获取焦点，从而接收删除键与退格键。
  final FocusNode _imageFocusNode = FocusNode();

  /// 图片是否处于选中状态
  bool _isImageSelected = false;

  /// 点击备注文字时的全局坐标
  ///
  /// 进入编辑状态后据此把光标放到点击位置，而不是固定放在文末。
  Offset? _pendingCaretGlobalPosition;

  /// 备注文字样式
  TextStyle get _noteTextStyle => TextStyle(
        fontFamily: SettingsService.instance.outlineFontFamily,
        fontSize: widget.noteFontSize,
        height: 1.45,
        color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
      );

  @override
  void initState() {
    super.initState();
    _noteController.text = widget.note;
    _noteFocusNode.addListener(_handleNoteFocusChanged);
    _imageFocusNode.addListener(_handleImageFocusChanged);
    // 备注区可能因进入编辑状态才首次创建，需要在挂载后主动获取焦点
    if (widget.isEditingNote) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNoteEditor());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant OutlineNodeAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 外部内容变化（如撤销恢复）时同步输入框，编辑中的输入不被覆盖
    if (!_noteFocusNode.hasFocus &&
        widget.note != oldWidget.note &&
        _noteController.text != widget.note) {
      _noteController.text = widget.note;
    }

    // 进入编辑状态时补全输入框内容并把焦点交给输入框
    if (widget.isEditingNote && !oldWidget.isEditingNote) {
      _noteController.text = widget.note;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNoteEditor());
    }

    // 退出编辑状态时收起输入法焦点
    if (!widget.isEditingNote && oldWidget.isEditingNote) {
      _pendingCaretGlobalPosition = null;
      if (_noteFocusNode.hasFocus) _noteFocusNode.unfocus();
    }

    // 图片被替换或移除后不再保持选中态
    if (widget.imagePath != oldWidget.imagePath) {
      if (_isImageSelected) _isImageSelected = false;
      _imagePixelSize = null;
      _disposeImageStream();
      _resolveImageSize();
    }
  }

  @override
  void dispose() {
    _disposeImageStream();
    _noteFocusNode.removeListener(_handleNoteFocusChanged);
    _imageFocusNode.removeListener(_handleImageFocusChanged);
    _noteController.dispose();
    _noteFocusNode.dispose();
    _imageFocusNode.dispose();
    super.dispose();
  }

  /// 解析图片原始尺寸
  ///
  /// 用于判断缩略图是否被缩放、是否需要展示放大入口。
  void _resolveImageSize() {
    final String path = widget.imagePath;
    if (path.isEmpty || _imagePixelSize != null || _imageStream != null) return;

    final ImageStream stream = FileImage(File(path)).resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        _disposeImageStream();
        if (!mounted || widget.imagePath != path) return;
        final Size size = Size(info.image.width.toDouble(), info.image.height.toDouble());
        if (synchronousCall) {
          // 同步回调发生在构建之前，直接记录尺寸即可
          _imagePixelSize = size;
        } else {
          setState(() => _imagePixelSize = size);
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        _disposeImageStream();
      },
    );
    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  /// 移除图片流监听
  void _disposeImageStream() {
    final ImageStream? stream = _imageStream;
    final ImageStreamListener? listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  /// 备注输入框失焦时结束编辑
  ///
  /// 焦点事件中直接通知父级重建可能触发重复布局，延后到帧末处理。
  void _handleNoteFocusChanged() {
    if (_noteFocusNode.hasFocus || !widget.isEditingNote) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStopNoteEdit();
    });
  }

  /// 把焦点交给备注输入框，并把光标放到点击位置
  ///
  /// 从收起状态点击进入编辑时，优先按点击坐标换算文字偏移量；
  /// 通过右键菜单进入编辑等没有点击位置的情况，光标落在文本末尾。
  void _focusNoteEditor() {
    if (!mounted || !widget.isEditingNote) return;
    _noteFocusNode.requestFocus();

    int offset = _noteController.text.length;
    final Offset? caretPosition = _pendingCaretGlobalPosition;
    _pendingCaretGlobalPosition = null;
    if (caretPosition != null) {
      final RenderEditable? renderEditable = findPersistentRenderEditable(_noteFieldKey);
      if (renderEditable != null && renderEditable.attached) {
        offset = renderEditable.getPositionForPoint(caretPosition).offset;
      }
    }

    offset = offset.clamp(0, _noteController.text.length);
    _noteController.selection = TextSelection.collapsed(offset: offset);
  }

  /// 图片区域失焦时取消选中
  void _handleImageFocusChanged() {
    if (_imageFocusNode.hasFocus || !_isImageSelected) return;
    setState(() => _isImageSelected = false);
  }

  /// 处理图片区域的键盘事件
  ///
  /// 选中态下删除键与退格键移除图片，Esc 取消选中。
  KeyEventResult _handleImageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _isImageSelected = false);
      return KeyEventResult.handled;
    }

    final bool isDeleteKey = event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace;
    if (isDeleteKey && !widget.readOnly) {
      _deleteImage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 点击图片：未选中时进入选中态，已选中时由蒙版按钮负责预览
  void _handleImageTap() {
    if (widget.readOnly || _isImageSelected) return;
    setState(() => _isImageSelected = true);
    _imageFocusNode.requestFocus();
  }

  /// 删除当前节点的图片
  void _deleteImage() {
    if (widget.readOnly) return;
    setState(() => _isImageSelected = false);
    widget.onDeleteImage();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasImage = widget.imagePath.isNotEmpty;
    final bool hasNote = widget.note.isNotEmpty;
    // 备注与图片都不存在且未在编辑备注时不占用任何空间
    if (!hasImage && !hasNote && !widget.isEditingNote) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(top: 6, left: widget.textLeftInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage) _buildImageArea(),
          if (hasImage && (hasNote || widget.isEditingNote)) const SizedBox(height: 6),
          if (hasNote || widget.isEditingNote) _buildNoteArea(),
        ],
      ),
    );
  }

  /// 构建图片区域：缩略图、选中边框与删除按钮
  Widget _buildImageArea() {
    final ColorScheme colorScheme = widget.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 缩略图在窄屏或深层缩进下按可用宽度收缩，避免横向溢出
        final double availableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : _thumbnailMaxWidth;
        final double maxWidth =
            (availableWidth - 8).clamp(24.0, _thumbnailMaxWidth).toDouble();

        // 按原始尺寸计算等比缩放后的展示尺寸，用于判断按钮是否放得下
        final Size? pixelSize = _imagePixelSize;
        Size? displayedSize;
        bool scaled = false;
        if (pixelSize != null && pixelSize.width > 0 && pixelSize.height > 0) {
          double scale = 1.0;
          final double widthScale = maxWidth / pixelSize.width;
          final double heightScale = _thumbnailMaxHeight / pixelSize.height;
          if (widthScale < scale) scale = widthScale;
          if (heightScale < scale) scale = heightScale;
          displayedSize = Size(pixelSize.width * scale, pixelSize.height * scale);
          scaled = scale < 0.999;
        }

        // 图片未被缩放时不需要放大查看；展示区域放不下放大按钮时同样不显示
        final bool showZoom = displayedSize != null &&
            scaled &&
            displayedSize.width >= _zoomButtonSize &&
            displayedSize.height >= _zoomButtonSize;
        // 图片小于删除按钮时把删除按钮居中，避免按钮超出图片难以点击
        final bool centerDelete = displayedSize != null &&
            (displayedSize.width < _deleteButtonSize || displayedSize.height < _deleteButtonSize);

        return Transform.translate(
          // 向左补偿边框与内边距的宽度，让图片本体与节点文字左对齐
          offset: const Offset(-_thumbnailBorderInset, 0),
          child: Focus(
            focusNode: _imageFocusNode,
            onKeyEvent: _handleImageKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleImageTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 选中时显示主题色描边，未选中时描边透明，尺寸保持一致避免跳动
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isImageSelected ? colorScheme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: _buildThumbnail(maxWidth),
                  ),
                  if (_isImageSelected) ...[
                    // 选中蒙版：压暗图片，突出居中的放大入口
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    if (showZoom)
                      Positioned.fill(child: Center(child: _buildZoomButton())),
                    if (centerDelete)
                      Positioned.fill(child: Center(child: _buildDeleteButton()))
                    else
                      Positioned(right: 8, bottom: 8, child: _buildDeleteButton()),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建放大按钮
  ///
  /// 选中图片后覆盖在图片中央，点击打开大图预览。
  Widget _buildZoomButton() {
    return CursorTooltipTarget(
      tooltipContent: const Text('查看大图'),
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          canRequestFocus: false,
          hoverColor: Colors.white.withValues(alpha: 0.18),
          splashColor: Colors.white.withValues(alpha: 0.2),
          onTap: () => showOutlineImagePreview(context, widget.imagePath),
          child: const SizedBox(
            width: _zoomButtonSize,
            height: _zoomButtonSize,
            child: Icon(Icons.zoom_in_rounded, color: Colors.white, size: 38),
          ),
        ),
      ),
    );
  }

  /// 构建删除按钮
  Widget _buildDeleteButton() {
    return CursorTooltipTarget(
      tooltipContent: const Text('删除图片'),
      child: Material(
        color: Colors.black.withValues(alpha: 0.62),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          // 删除按钮不参与焦点争夺，避免点击时图片区域失焦导致按钮提前消失
          canRequestFocus: false,
          hoverColor: Colors.white.withValues(alpha: 0.12),
          splashColor: Colors.white.withValues(alpha: 0.2),
          onTap: _deleteImage,
          child: const SizedBox(
            width: _deleteButtonSize,
            height: _deleteButtonSize,
            child: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// 构建图片缩略图
  ///
  /// 只在最大宽高范围内等比缩放，不裁剪图片；
  /// 图片文件可能尚未同步到本机或已被外部删除，读取失败时显示占位图标。
  Widget _buildThumbnail(double maxWidth) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: _thumbnailMaxHeight),
        child: Image.file(
          File(widget.imagePath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return SizedBox(
              width: maxWidth,
              height: 90,
              child: ColoredBox(
                color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 28,
                  color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建备注区域
  ///
  /// 编辑状态下显示多行输入框，非编辑状态下只显示首行内容。
  Widget _buildNoteArea() {
    if (widget.isEditingNote) {
      return SizedBox(
        width: double.infinity,
        child: ImeCursorFixerWrapper(
          controller: _noteController,
          focusNode: _noteFocusNode,
          child: TextField(
            key: _noteFieldKey,
            controller: _noteController,
            focusNode: _noteFocusNode,
            readOnly: widget.readOnly,
            maxLines: null,
            minLines: 1,
            style: _noteTextStyle,
            cursorColor: widget.colorScheme.primary,
            decoration: InputDecoration(
              isCollapsed: true,
              isDense: true,
              // 关闭主题继承的填充底色，避免输入框额外增加内部间距
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              // 清除主题继承的内边距，保证进入编辑状态时文字不向右跳
              contentPadding: EdgeInsets.zero,
              hintText: '输入备注…',
              hintStyle: _noteTextStyle.copyWith(
                color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            onChanged: widget.onNoteChanged,
          ),
        ),
      );
    }

    return MouseRegion(
      // 备注可点击进入编辑，使用文本输入光标而不是手型
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 记录点击位置，进入编辑状态后据此定位光标
        onTapDown: widget.readOnly
            ? null
            : (details) => _pendingCaretGlobalPosition = details.globalPosition,
        // 手势被取消时丢弃点击位置，避免后续从菜单进入编辑时误用旧坐标
        onTapCancel: () => _pendingCaretGlobalPosition = null,
        onTap: widget.readOnly ? null : widget.onStartNoteEdit,
        child: SizedBox(
          width: double.infinity,
          child: Text(
            _collapsedNoteText(widget.note),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _noteTextStyle,
          ),
        ),
      ),
    );
  }

  /// 生成收起状态下的备注文字
  ///
  /// 多行备注只保留首行，并在末尾追加省略号提示仍有内容。
  String _collapsedNoteText(String note) {
    final int lineBreakIndex = note.indexOf('\n');
    if (lineBreakIndex < 0) return note;
    return '${note.substring(0, lineBreakIndex)}…';
  }
}

/// 打开图片大图预览
///
/// 深色遮罩上居中展示原图，支持滚轮缩放与拖动查看；
/// 点击图片外的空白区域、关闭按钮或按 Esc 均可关闭。
Future<void> showOutlineImagePreview(BuildContext context, String imagePath) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭图片预览',
    barrierColor: Colors.black.withValues(alpha: 0.9),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _ImagePreviewDialog(imagePath: imagePath);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final CurvedAnimation curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 图片大图预览弹窗
class _ImagePreviewDialog extends StatelessWidget {
  /// 图片文件路径
  final String imagePath;

  const _ImagePreviewDialog({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 点击图片外的空白区域关闭预览
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                // 缩放区域占满整个弹窗，放大后图片可以扩散到原图之外的区域
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  clipBehavior: Clip.none,
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 36,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        // 吸收图片上的点击，避免触发遮罩的关闭手势
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: Image.file(
                            File(imagePath),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: _buildCloseButton(context),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: const Text(
                    '滚轮缩放 · 拖动查看',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建关闭按钮
  Widget _buildCloseButton(BuildContext context) {
    return CursorTooltipTarget(
      tooltipContent: const Text('关闭 (Esc)'),
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          hoverColor: Colors.white.withValues(alpha: 0.18),
          onTap: () => Navigator.of(context).maybePop(),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  /// 构建图片缺失占位
  Widget _buildErrorPlaceholder() {
    return Container(
      width: 320,
      height: 200,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 36, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          const Text('图片文件缺失', style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}
