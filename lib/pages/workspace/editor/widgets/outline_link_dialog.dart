import 'package:flutter/material.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/outline_link.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/outline_markdown_codec.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';

/// 大纲关联目标选择弹窗
///
/// 分两步选择关联目标：先选择被关联的文件（正文文件或设定文件），
/// 再选择正文文件中的段落或设定文件中的大纲节点。
/// 选择完成后返回关联目标，由调用方写入节点文本。
class OutlineLinkDialog extends StatefulWidget {
  /// 弹窗宽度
  static const double width = 520;

  /// 弹窗高度
  static const double height = 560;

  /// 可选的正文章节列表
  final List<ChapterModel> chapters;

  /// 可选的设定项列表
  final List<SettingItemModel> settingItems;

  /// 当前设定项 UUID
  ///
  /// 当前文件自身不出现在可选列表中，避免关联到自身。
  final String currentSettingItemUuid;

  /// 读取章节正文内容
  final Future<String> Function(ChapterModel chapter) readChapterContent;

  /// 读取设定项大纲内容
  final Future<String> Function(SettingItemModel item) readSettingItemContent;

  /// 获取分卷名称（用于章节的辅助说明）
  final String Function(String volumeUuid) volumeNameOf;

  /// 获取设定分组名称（用于设定项的辅助说明）
  final String Function(String groupUuid) groupNameOf;

  const OutlineLinkDialog({
    super.key,
    required this.chapters,
    required this.settingItems,
    required this.currentSettingItemUuid,
    required this.readChapterContent,
    required this.readSettingItemContent,
    required this.volumeNameOf,
    required this.groupNameOf,
  });

  /// 弹出关联目标选择弹窗
  ///
  /// 用户取消选择时返回 null。
  static Future<OutlineLinkTarget?> show({
    required BuildContext context,
    required List<ChapterModel> chapters,
    required List<SettingItemModel> settingItems,
    required String currentSettingItemUuid,
    required Future<String> Function(ChapterModel chapter) readChapterContent,
    required Future<String> Function(SettingItemModel item) readSettingItemContent,
    required String Function(String volumeUuid) volumeNameOf,
    required String Function(String groupUuid) groupNameOf,
  }) {
    return showDialogBase<OutlineLinkTarget>(
      context: context,
      title: '添加关联',
      subtitle: '选择要关联的文件与位置',
      titleIcon: Icons.link,
      width: width,
      height: height,
      titleFontSize: 15,
      content: OutlineLinkDialog(
        chapters: chapters,
        settingItems: settingItems,
        currentSettingItemUuid: currentSettingItemUuid,
        readChapterContent: readChapterContent,
        readSettingItemContent: readSettingItemContent,
        volumeNameOf: volumeNameOf,
        groupNameOf: groupNameOf,
      ),
    );
  }

  @override
  State<OutlineLinkDialog> createState() => _OutlineLinkDialogState();
}

class _OutlineLinkDialogState extends State<OutlineLinkDialog> {
  /// 允许选择的最大大纲层级
  static const int _maxDepth = 20;

  /// 当前筛选的文件类型
  late OutlineLinkTargetType _mode;

  /// 文件或位置的搜索关键词
  String _query = '';

  /// 已选择的文件（为空时展示文件列表）
  _PickedFile? _picked;

  /// 已选择文件中的可跳转位置
  List<_TargetOption> _targets = const [];

  /// 是否正在读取已选择文件的内容
  bool _loading = false;

  /// 读取失败或没有可选项时的提示
  String? _message;

  /// 内容读取请求序号，用于丢弃切换文件后返回的过期结果
  int _requestSeq = 0;

  /// 文件列表搜索框控制器
  final TextEditingController _fileSearchController = TextEditingController();

  /// 位置列表搜索框控制器
  final TextEditingController _targetSearchController = TextEditingController();

  /// 文件列表搜索框焦点
  final FocusNode _fileSearchFocusNode = FocusNode();

  /// 位置列表搜索框焦点
  final FocusNode _targetSearchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 正文文件优先，没有正文章节时默认展示设定文件
    _mode = widget.chapters.isEmpty
        ? OutlineLinkTargetType.setting
        : OutlineLinkTargetType.chapter;
    // 打开弹窗后直接聚焦搜索框，便于快速筛选文件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fileSearchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _fileSearchController.dispose();
    _targetSearchController.dispose();
    _fileSearchFocusNode.dispose();
    _targetSearchFocusNode.dispose();
    super.dispose();
  }

  /// 可选的设定项（排除当前文件自身）
  List<SettingItemModel> get _selectableSettingItems => widget.settingItems
      .where((item) => item.uuid != widget.currentSettingItemUuid)
      .toList();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: _picked == null
              ? _buildFileSearch(colorScheme)
              : _buildTargetSearch(colorScheme),
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        Expanded(
          child: _picked == null ? _buildFileList(colorScheme) : _buildTargetList(colorScheme),
        ),
      ],
    );
  }

  /// 构建文件列表阶段的搜索框与类型筛选
  Widget _buildFileSearch(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchField(
          controller: _fileSearchController,
          focusNode: _fileSearchFocusNode,
          hintText: '搜索文件',
          onChanged: (value) => setState(() => _query = value),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildModeChip(
              type: OutlineLinkTargetType.chapter,
              label: '正文文件',
              icon: Icons.article_outlined,
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 8),
            _buildModeChip(
              type: OutlineLinkTargetType.setting,
              label: '设定文件',
              icon: Icons.account_tree_outlined,
              colorScheme: colorScheme,
            ),
          ],
        ),
      ],
    );
  }

  /// 构建位置列表阶段的搜索框与已选文件标题
  Widget _buildTargetSearch(ColorScheme colorScheme) {
    final _PickedFile picked = _picked!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _backToFileList,
              icon: const Icon(Icons.arrow_back, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: colorScheme.onSurfaceVariant,
              tooltip: '返回文件列表',
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                picked.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSearchField(
          controller: _targetSearchController,
          focusNode: _targetSearchFocusNode,
          hintText: picked.type == OutlineLinkTargetType.chapter ? '搜索段落' : '搜索节点',
          onChanged: (value) => setState(() => _query = value),
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  /// 构建通用搜索框
  Widget _buildSearchField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required ValueChanged<String> onChanged,
    required ColorScheme colorScheme,
  }) {
    return ImeCursorFixerWrapper(
      controller: controller,
      focusNode: focusNode,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(Icons.search, size: 18, color: colorScheme.onSurfaceVariant),
          prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  /// 构建文件类型筛选标签
  Widget _buildModeChip({
    required OutlineLinkTargetType type,
    required String label,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    final bool selected = _mode == type;
    return InkWell(
      onTap: () => setState(() => _mode = type),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建文件列表
  Widget _buildFileList(ColorScheme colorScheme) {
    final List<_FileOption> files = _filteredFiles();
    if (files.isEmpty) {
      return _buildEmptyHint(
        _query.isEmpty ? '没有可关联的文件' : '没有匹配的文件',
        colorScheme,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: files.length,
      itemBuilder: (context, index) => _buildFileItem(files[index], colorScheme),
    );
  }

  /// 构建单个文件条目
  Widget _buildFileItem(_FileOption file, ColorScheme colorScheme) {
    return InkWell(
      onTap: () => _selectFile(file),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 9),
        child: Row(
          children: [
            Icon(
              file.type == OutlineLinkTargetType.chapter
                  ? Icons.article_outlined
                  : Icons.account_tree_outlined,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                  ),
                  if (file.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        file.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  /// 构建位置列表
  Widget _buildTargetList(ColorScheme colorScheme) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
        ),
      );
    }

    if (_message != null) {
      return _buildEmptyHint(_message!, colorScheme);
    }

    final List<_TargetOption> targets = _filteredTargets();
    if (targets.isEmpty) {
      return _buildEmptyHint(_query.isEmpty ? '没有可关联的位置' : '没有匹配的位置', colorScheme);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: targets.length,
      itemBuilder: (context, index) => _buildTargetItem(targets[index], colorScheme),
    );
  }

  /// 构建单个位置条目
  Widget _buildTargetItem(_TargetOption target, ColorScheme colorScheme) {
    final bool isChapter = _picked?.type == OutlineLinkTargetType.chapter;
    return InkWell(
      onTap: () => _confirmTarget(target),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20 + (isChapter ? 0 : target.depth * 14.0), 8, 20, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isChapter)
              Container(
                margin: const EdgeInsets.only(top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${target.paragraphIndex + 1}',
                  style: TextStyle(fontSize: 10, color: colorScheme.primary, fontWeight: FontWeight.w600),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                target.text.isEmpty ? '（空节点）' : target.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: target.text.isEmpty
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyHint(String text, ColorScheme colorScheme) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  /// 计算当前类型与关键词筛选后的文件列表
  List<_FileOption> _filteredFiles() {
    final String query = _query.trim().toLowerCase();
    if (_mode == OutlineLinkTargetType.chapter) {
      return [
        for (final ChapterModel chapter in widget.chapters)
          if (query.isEmpty ||
              chapter.title.toLowerCase().contains(query) ||
              widget.volumeNameOf(chapter.volumeUuid).toLowerCase().contains(query))
            _FileOption(
              type: OutlineLinkTargetType.chapter,
              uuid: chapter.uuid,
              title: chapter.title,
              subtitle: widget.volumeNameOf(chapter.volumeUuid),
              chapter: chapter,
            ),
      ];
    }

    return [
      for (final SettingItemModel item in _selectableSettingItems)
        if (query.isEmpty ||
            item.title.toLowerCase().contains(query) ||
            widget.groupNameOf(item.groupUuid).toLowerCase().contains(query))
          _FileOption(
            type: OutlineLinkTargetType.setting,
            uuid: item.uuid,
            title: item.title,
            subtitle: widget.groupNameOf(item.groupUuid),
            settingItem: item,
          ),
    ];
  }

  /// 计算位置列表按关键词筛选后的结果
  List<_TargetOption> _filteredTargets() {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return _targets;
    return [
      for (final _TargetOption target in _targets)
        if (target.text.toLowerCase().contains(query)) target,
    ];
  }

  /// 返回文件列表并清空已选文件状态
  void _backToFileList() {
    _requestSeq++;
    _targetSearchController.clear();
    setState(() {
      _picked = null;
      _targets = const [];
      _loading = false;
      _message = null;
      _query = '';
      _fileSearchController.clear();
    });
  }

  /// 选择文件并读取其可跳转的位置
  Future<void> _selectFile(_FileOption file) async {
    final int seq = ++_requestSeq;
    _targetSearchController.clear();
    setState(() {
      _picked = _PickedFile(type: file.type, uuid: file.uuid, title: file.title);
      _targets = const [];
      _loading = true;
      _message = null;
      _query = '';
    });

    List<_TargetOption> targets;
    try {
      if (file.type == OutlineLinkTargetType.chapter) {
        final String content = await widget.readChapterContent(file.chapter!);
        targets = _parseParagraphs(content);
      } else {
        final String content = await widget.readSettingItemContent(file.settingItem!);
        targets = _parseOutlineNodes(content);
      }
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _message = '内容读取失败';
      });
      return;
    }

    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _loading = false;
      _targets = targets;
      _message = targets.isEmpty ? '没有可关联的位置' : null;
    });
  }

  /// 确认选择位置并返回关联目标
  void _confirmTarget(_TargetOption target) {
    final _PickedFile picked = _picked!;
    final bool isChapter = picked.type == OutlineLinkTargetType.chapter;
    Navigator.of(context).pop(OutlineLinkTarget(
      type: picked.type,
      targetUuid: picked.uuid,
      targetTitle: picked.title,
      nodePath: isChapter ? '' : target.nodePath,
      paragraphIndex: isChapter ? target.paragraphIndex : 0,
      // 记录当前段落总数，供跳转时判断段落序号是否仍然可信
      paragraphCount: isChapter ? _targets.length : 0,
      anchorText: target.text,
    ));
  }

  /// 将章节正文解析为段落列表
  ///
  /// 仅保留非空行，段落序号以非空段落为基准，与跳转时的定位规则保持一致。
  List<_TargetOption> _parseParagraphs(String content) {
    final List<_TargetOption> targets = [];
    for (final String line in content.split('\n')) {
      final String text = line.trim();
      if (text.isEmpty) continue;
      targets.add(_TargetOption(
        paragraphIndex: targets.length,
        text: text,
      ));
    }
    return targets;
  }

  /// 将大纲 Markdown 解析为节点列表
  ///
  /// 与大纲编辑器的解析规则保持一致：每行对应一个节点（文件末尾换行
  /// 产生的空行除外），即使节点文本为空也保留，
  /// 否则后续节点的层级路径会与编辑器错位。
  /// 节点路径由各级索引拼接而成，用于跳转时精确定位节点。
  List<_TargetOption> _parseOutlineNodes(String content) {
    final List<_TargetOption> targets = [];
    // 每个树层级当前已使用的同级索引
    final List<int> counters = [];
    // 每个树层级对应的原始缩进深度，用于把缩进映射到实际的树层级
    final List<int> levelDepths = [];

    final List<String> rawLines = content.split('\n');
    // 文件以换行结尾时最后一项为空字符串，不代表任何节点，需剔除
    if (rawLines.isNotEmpty && rawLines.last.isEmpty) {
      rawLines.removeLast();
    }
    for (final String rawLine in rawLines) {
      String line = rawLine;
      int depth = 0;
      while (line.startsWith('\t')) {
        if (depth < _maxDepth) depth++;
        line = line.substring(1);
      }
      while (line.startsWith('    ')) {
        if (depth < _maxDepth) depth++;
        line = line.substring(4);
      }

      // 弹出深度不小于当前深度的层级，得到本节点在树中的层级
      while (levelDepths.isNotEmpty && levelDepths.last >= depth) {
        levelDepths.removeLast();
      }
      final int treeDepth = levelDepths.length;

      while (counters.length <= treeDepth) {
        counters.add(-1);
      }
      if (counters.length > treeDepth + 1) {
        counters.removeRange(treeDepth + 1, counters.length);
      }
      counters[treeDepth]++;

      targets.add(_TargetOption(
        nodePath: counters.join('.'),
        depth: treeDepth,
        text: OutlineMarkdownCodec.deserialize(line).text.trim(),
      ));

      levelDepths.add(depth);
    }
    return targets;
  }
}

/// 文件列表中的可选项
class _FileOption {
  final OutlineLinkTargetType type;
  final String uuid;
  final String title;
  final String subtitle;
  final ChapterModel? chapter;
  final SettingItemModel? settingItem;

  const _FileOption({
    required this.type,
    required this.uuid,
    required this.title,
    required this.subtitle,
    this.chapter,
    this.settingItem,
  });
}

/// 已选择的文件
class _PickedFile {
  final OutlineLinkTargetType type;
  final String uuid;
  final String title;

  const _PickedFile({
    required this.type,
    required this.uuid,
    required this.title,
  });
}

/// 文件中的可跳转位置
class _TargetOption {
  /// 段落序号（仅正文文件使用）
  final int paragraphIndex;

  /// 节点路径（仅设定文件使用）
  final String nodePath;

  /// 节点层级深度（仅设定文件使用）
  final int depth;

  /// 位置文本
  final String text;

  const _TargetOption({
    this.paragraphIndex = 0,
    this.nodePath = '',
    this.depth = 0,
    required this.text,
  });
}
