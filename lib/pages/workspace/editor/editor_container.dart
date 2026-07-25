import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/backup_service.dart';
import 'package:quick_write/core/services/cache_services/chapter_cursor_cache_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/dialogue_highlight_controller.dart';
import 'package:quick_write/core/utils/editor_undo_manager.dart';
import 'package:quick_write/pages/workspace/editor/widgets/find_replace_bar.dart';
import 'package:quick_write/pages/workspace/editor/widgets/outline_editor_widgets.dart';
import 'package:quick_write/pages/workspace/editor/novel_editor.dart';
import 'package:quick_write/pages/workspace/editor/outline_editor.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 工作区容器
/// 
/// 管理文本编辑器和标签页的容器组件
class EditorContainer extends StatefulWidget {
  const EditorContainer({super.key});

  @override
  State<EditorContainer> createState() => _EditorContainerState();
}

class _EditorContainerState extends State<EditorContainer> {
  /// 选区删除不计入码字统计的字数阈值
  ///
  /// 一次性删除（如选中一段文本后删除/剪切）字数超过此阈值时，视为清理操作而非创作过程的修改，
  /// 不参与今日码字与码字速度统计，但仍同步基线以保持后续统计正确。
  static const int _largeDeletionThreshold = 10;

  /// 是否正在加载内容
  bool _isLoading = false;
  
  /// 当前加载的标签页ID（用于避免重复加载）
  String? _loadingTabId;

  /// 确保当前标签页的控制器和内容已加载
  void _ensureCurrentTabLoaded(WorkspaceProvider workspaceProvider) {
    final currentTab = workspaceProvider.currentTab;

    if (currentTab == null) {
      _loadingTabId = null;
      return;
    }

    // 设定项标签页使用大纲编辑器，无需加载文本内容
    if (currentTab.type == EditorTabType.settings) {
      return;
    }

    // 大纲备份预览标签页使用大纲编辑器只读模式，无需加载文本内容
    if (currentTab.type == EditorTabType.backupPreview && currentTab.originalIsSetting) {
      return;
    }

    // 如果标签页还没有控制器，需要创建并加载内容
    if (currentTab.textController == null) {
      // 立即标记为加载中，防止编辑器在内容加载前显示hintText
      _loadingTabId = currentTab.id;
      _isLoading = true;

      currentTab.textController = DialogueHighlightController();
      // 备份预览标签页不需要章节标题控制器
      if (currentTab.type != EditorTabType.backupPreview) {
        currentTab.chapterTitleController = TextEditingController();
      }
      currentTab.undoManager = EditorUndoManager(controller: currentTab.textController!);
      
      // 异步加载内容
      _loadTabContent(currentTab, workspaceProvider);
    }
  }
  
  /// 异步加载标签页内容
  Future<void> _loadTabContent(EditorTab tab, WorkspaceProvider provider) async {
    // 确保异步执行，避免无 await 时在 build 阶段调用 setState/notifyListeners
    await Future.microtask(() {});

    // 如果用户在等待期间切换了标签页，放弃加载
    if (_loadingTabId != tab.id) return;
    
    try {
      String content = '';
      
      if (tab.type == EditorTabType.backupPreview) {
        // 从备份文件读取内容
        if (tab.backupFilePath != null) {
          final backupContent = await BackupService.instance.readBackupContent(tab.backupFilePath!);
          if (backupContent != null) {
            content = backupContent;
          }
        }
      } else if (tab.type == EditorTabType.chapter) {
        // 从文件系统读取章节内容
        final chapter = _findChapterByUuid(provider.chapters, tab.id);
        if (chapter != null) {
          content = await provider.readChapterContent(chapter);
        }
      } else if (tab.type == EditorTabType.settings) {
        // 从文件系统读取设定项内容
        final item = _findSettingItemByUuid(provider.settingItems, tab.id);
        if (item != null) {
          content = await provider.readSettingItemContent(item);
        }
      }
      
      // 如果内容为空，使用默认模板
      if (content.isEmpty) {
        content = _getDefaultContent(tab);
      }
      
      // 更新控制器内容（如果标签页还是当前的）
      if (mounted && tab.textController != null) {
        tab.textController!.text = content;
        
        // 备份预览标签页：光标置于开头
        if (tab.type == EditorTabType.backupPreview) {
          tab.textController!.selection = const TextSelection.collapsed(offset: 0);
        } else {
          // 根据用户设置的「打开章节时」模式决定光标位置
          final cursorMode = SettingsService.instance.openChapterCursorMode;
          if (cursorMode == 'end') {
            // 定位至章末
            final textLength = tab.textController!.text.length;
            tab.textController!.selection = TextSelection.collapsed(offset: textLength);
          } else if (cursorMode == 'lastEdit') {
            // 上一次编辑位置：从缓存中读取光标位置
            final bookUuid = provider.currentBook?.uuid;
            if (bookUuid != null) {
              final cachedPosition = ChapterCursorCacheService.instance.getCursorPosition(
                bookUuid: bookUuid,
                chapterUuid: tab.id,
              );
              
              if (cachedPosition != null) {
                final textLength = tab.textController!.text.length;
                final offset = cachedPosition.offset.clamp(0, textLength);
                tab.textController!.selection = TextSelection.collapsed(offset: offset);
                debugPrint('恢复章节光标位置: ${tab.title}, offset: $offset');
              } else {
                // 无缓存，定位至章节开头，跳过首行缩进
                tab.textController!.selection = TextSelection.collapsed(
                  offset: _skipFirstLineIndent(content),
                );
              }
            } else {
              // 无书籍信息，定位至章节开头，跳过首行缩进
              tab.textController!.selection = TextSelection.collapsed(
                offset: _skipFirstLineIndent(content),
              );
            }
          } else {
            // 默认模式：定位至章节开头，跳过首行缩进
            tab.textController!.selection = TextSelection.collapsed(
              offset: _skipFirstLineIndent(content),
            );
          }
        }
        tab.cursorPosition = tab.textController!.selection;
        
        // 设置章节标题（备份预览标签页不需要）
        if (tab.chapterTitleController != null) {
          tab.chapterTitleController!.text = tab.title;
        }
        
        // 清空撤销栈，防止把"加载初始内容"当作第一次输入可以被撤销
        tab.undoManager?.clearHistory();

        // 加载完成后更新字数统计
        tab.updateWordCount();
        // 初始化码字统计基线：以当前字数为基线，recorded 归零
        // 后续编辑事件基于此基线计算 currentNet，避免删除旧内容被错误计入今日码字
        tab.sessionBaselineWordCount = tab.wordCount;
        tab.recordedSessionWords = 0;
        // 通知 UI 刷新
        provider.notifyWordCountUpdated();

        // 内容加载完成后，如果查找替换栏处于打开状态，刷新查找结果
        provider.refreshFindIfVisible(resetIndex: true);
      }
    } catch (e) {
      debugPrint('加载内容失败: $e');
      // 加载失败时使用默认内容
      if (tab.textController != null) {
        tab.textController!.text = _getDefaultContent(tab);
        tab.textController!.selection = const TextSelection.collapsed(offset: 0);
        tab.cursorPosition = tab.textController!.selection;
        // 加载失败同样需要初始化基线，避免后续编辑统计错乱
        tab.updateWordCount();
        tab.sessionBaselineWordCount = tab.wordCount;
        tab.recordedSessionWords = 0;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _loadingTabId = null;
    }
  }
  
  /// 根据 UUID 查找章节
  ChapterModel? _findChapterByUuid(List<ChapterModel> chapters, String uuid) {
    try {
      return chapters.firstWhere((c) => c.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  /// 根据 UUID 查找设定项
  SettingItemModel? _findSettingItemByUuid(List<SettingItemModel> items, String uuid) {
    try {
      return items.firstWhere((i) => i.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  /// 跳过首行缩进，返回第一个非缩进字符的偏移量
  ///
  /// 检测文本第一段第一行开头的全角空格（\u{3000}），跳过缩进定位到第一个文字前方
  int _skipFirstLineIndent(String content) {
    if (content.isEmpty) return 0;
    int offset = 0;
    // 跳过第一段第一行开头的全角空格
    while (offset < content.length && content[offset] == '\u{3000}') {
      offset++;
    }
    // 如果遇到换行符，说明第一行只有缩进没有正文，回到开头
    if (offset < content.length && content[offset] == '\n') {
      return 0;
    }
    return offset;
  }

  /// 获取默认内容模板
  /// 
  /// 根据标签页类型返回不同的初始内容模板
  String _getDefaultContent(EditorTab tab) {
    switch (tab.type) {
      case EditorTabType.chapter:
        return '';
      case EditorTabType.settings:
        return '';
      case EditorTabType.backupPreview:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 从上下文获取工作区提供者，这个提供者负责管理所有标签页的状态和操作
    final workspaceProvider = context.watch<WorkspaceProvider>();

    // 确保当前标签页加载
    _ensureCurrentTabLoaded(workspaceProvider);

    // 如果没有打开的标签页，显示空状态
    if (!workspaceProvider.hasOpenedTabs) {
      return _buildEmptyState(context);
    }

    // 当前标签页是否支持替换
    final currentTab = workspaceProvider.currentTab;
    final canReplace = currentTab?.canReplace ?? true;

    // 查找替换浮窗的顶部偏移量
    // 大纲编辑器模式下需下移至顶部工具栏下方，避免遮挡操作按钮
    final double findReplaceTop = (currentTab?.usesOutlineEditor ?? false)
        ? OutlineEditorTopBar.height + 6.0
        : 6.0;

    return Column(
      children: [
        // 标签栏
        TabBarWidget(provider: workspaceProvider),
        // 编辑器内容区域
        Expanded(
          child: Stack(
            children: [
              // 编辑器内容
              _buildEditorContent(context, workspaceProvider),
              // 查找替换栏（浮动在编辑区域右上角）
              if (workspaceProvider.isFindReplaceVisible)
                Positioned(
                  right: 16,
                  top: findReplaceTop,
                  child: FindReplaceBar(
                    key: const ValueKey('find_replace_bar'),
                    initialFindText: workspaceProvider.findText,
                    initialReplaceText: workspaceProvider.replaceText,
                    caseSensitive: workspaceProvider.findCaseSensitive,
                    showReplace: canReplace && workspaceProvider.showReplace,
                    canReplace: canReplace,
                    currentMatchIndex: workspaceProvider.currentMatchDisplayIndex,
                    totalMatchCount: workspaceProvider.totalMatchCount,
                    onFindTextChanged: (text) {
                      workspaceProvider.updateFindText(text);
                    },
                    onFindNext: () => workspaceProvider.findNext(),
                    onFindPrevious: () => workspaceProvider.findPrevious(),
                    onReplaceCurrent: () => workspaceProvider.replaceCurrentMatch(),
                    onReplaceAll: () => workspaceProvider.replaceAllMatches(),
                    onReplaceTextChanged: (text) => workspaceProvider.updateReplaceText(text),
                    onClose: () => workspaceProvider.closeFindReplace(),
                    onCaseSensitiveChanged: (value) => workspaceProvider.setFindCaseSensitive(value),
                    onShowReplaceChanged: (value) => workspaceProvider.setShowReplace(value),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建编辑器内容区域
  Widget _buildEditorContent(BuildContext context, WorkspaceProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;

    // 用 ColoredBox 包裹整个编辑器区域，确保内容为空时不会露出灰色底层
    return ColoredBox(
      color: colorScheme.surfaceContainer,
      child: IndexedStack(
        index: provider.currentTabIndex,
        children: provider.openedTabs.asMap().entries.map((entry) {
        final index = entry.key;
        final tab = entry.value;
        
        // 如果当前标签页正在加载，显示加载状态
        if (tab.id == _loadingTabId && _isLoading) {
          return Center(
            key: ValueKey('${tab.id}_loading'),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  tab.type == EditorTabType.backupPreview ? '正在加载备份内容...' : '正在加载章节内容...',
                  style: context.bodyLarge?.copyWith(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        // 设定项标签页使用大纲编辑器
        if (tab.type == EditorTabType.settings) {
          return OutlineEditor(
            key: tab.editorKey,
            colorScheme: colorScheme,
            filePath: provider.getTabFilePath(tab),
            // 查找替换栏可见时为编辑器预留顶边距，避免内容被遮挡
            extraTopPadding: provider.findReplaceBarPadding,
            // 大纲内容异步加载完成后，若查找替换栏处于打开状态则刷新查找结果
            onContentLoaded: () => provider.refreshFindIfVisible(resetIndex: true),
            onContentChanged: () {
              // 编辑预览模式下内容时，退出预览模式
              if (tab.isPreview) {
                provider.pinTab(tab.id);
              }
              // 标记为已修改
              if (!tab.isModified) {
                tab.isModified = true;
                provider.notifyTabModified(tab.id);
              }
              // 触发自动保存
              provider.triggerAutoSave();
            },
            onSave: () => provider.saveCurrentTab(),
            onStatsChanged: (topicCount, wordCount) {
              tab.topicCount = topicCount;
              tab.wordCount = wordCount;
              provider.notifyWordCountUpdated();
            },
          );
        }

        // 大纲备份预览标签页使用大纲编辑器只读模式
        if (tab.type == EditorTabType.backupPreview && tab.originalIsSetting) {
          return OutlineEditor(
            key: tab.editorKey,
            colorScheme: colorScheme,
            filePath: tab.backupFilePath,
            readOnly: true,
            // 查找替换栏可见时为编辑器预留顶边距，避免内容被遮挡
            extraTopPadding: provider.findReplaceBarPadding,
            // 大纲内容异步加载完成后，若查找替换栏处于打开状态则刷新查找结果
            onContentLoaded: () => provider.refreshFindIfVisible(resetIndex: true),
            onStatsChanged: (topicCount, wordCount) {
              tab.topicCount = topicCount;
              tab.wordCount = wordCount;
              provider.notifyWordCountUpdated();
            },
          );
        }

        // 如果控制器为空，返回空占位
        if (tab.textController == null) {
          return const SizedBox.shrink();
        }

        return NovelEditor(
          key: tab.editorKey,
          isActive: provider.currentTabIndex == index,
          controller: tab.textController!,
          chapterTitleController: tab.chapterTitleController,
          undoManager: tab.undoManager,
          colorScheme: colorScheme,
          initialSelection: tab.cursorPosition,
          readOnly: tab.isReadOnly,
          // 备份预览标签页不需要跳转到光标位置
          initialScrollToCursor: tab.type != EditorTabType.backupPreview &&
              (SettingsService.instance.openChapterCursorMode == 'end' ||
              SettingsService.instance.openChapterCursorMode == 'lastEdit'),
          onScrollOffsetChanged: (offset) {
            tab.scrollOffset = offset;
          },
          onSelectionChanged: (selection) {
            tab.cursorPosition = selection;
            // 防抖更新选中字数（通过 ValueNotifier 局部通知，不触发全局 Provider 重建）
            tab.updateSelectedWordCountDebounced();
          },
          onEditEvent: tab.isReadOnly ? null : (NovelEditType type) {
            // 编辑预览模式下内容时，退出预览模式
            if (tab.isPreview) {
              provider.pinTab(tab.id);
            }
            // 标记为已修改
            if (!tab.isModified) {
              tab.isModified = true;
              provider.notifyTabModified(tab.id);
            }
            // 计算字数与基线 delta
            // currentNet = max(0, 当前字数 - 基线字数)，避免删除旧内容让今日码字为负
            tab.updateWordCount();
            final currentNet = tab.wordCount > tab.sessionBaselineWordCount
                ? tab.wordCount - tab.sessionBaselineWordCount
                : 0;
            final delta = currentNet - tab.recordedSessionWords;

            if (type == NovelEditType.undo || type == NovelEditType.redo) {
              // 撤销/恢复不影响今日码字与码字速度，仅同步基线以保持后续操作正确
              tab.recordedSessionWords = currentNet;
            } else if (delta != 0) {
              // 判断是否为大规模删除：选区一次性删除/剪切字数超过阈值时，视为清理操作而非创作过程的修改
              // 此时跳过码字统计上报，避免今日码字因清理操作而回退；但仍同步 recordedSessionWords，
              // 否则下次输入时会把这次删除的字数错误计入统计
              final bool isLargeDeletion = delta < -_largeDeletionThreshold &&
                  (type == NovelEditType.keyboard ||
                   type == NovelEditType.cut ||
                   type == NovelEditType.delete);

              if (!isLargeDeletion) {
                // 按 事件类型分发到统计追踪器
                switch (type) {
                  case NovelEditType.keyboard:
                  case NovelEditType.cut:
                  case NovelEditType.delete:
                    // 键盘输入、剪切、删除均按键盘输入语义计入统计
                    provider.sessionTracker?.onWordsChanged(typedDelta: delta, pastedDelta: 0);
                    break;
                  case NovelEditType.paste:
                    // 粘贴单独计入 pastedDelta，用于开关控制与码字速度排除
                    provider.sessionTracker?.onWordsChanged(typedDelta: 0, pastedDelta: delta);
                    break;
                  case NovelEditType.undo:
                  case NovelEditType.redo:
                    // 不会到达：上方分支已处理
                    break;
                }
              }
              tab.recordedSessionWords = currentNet;
            }
            // 通知 UI 刷新（更新底部状态栏字数显示）
            provider.notifyWordCountUpdated();
            // 文本内容变化时，如果查找替换栏处于打开状态，刷新查找结果以防止匹配位置错位
            provider.refreshFindIfVisible();
            // 触发自动保存
            provider.triggerAutoSave();
          },
          onChapterTitleChanged: tab.isReadOnly ? null : (title) {
            // 编辑预览模式下章节标题时，退出预览模式
            if (tab.isPreview) {
              provider.pinTab(tab.id);
            }
            // 更新标签页标题
            tab.title = title;
            // 标记为已修改
            if (!tab.isModified) {
              tab.isModified = true;
              provider.notifyTabModified(tab.id);
            }
            // 触发自动保存
            provider.triggerAutoSave();
          },
          onSave: tab.isReadOnly ? null : () => provider.saveCurrentTab(),
          extraTopPadding: provider.findReplaceBarPadding,
        );
      }).toList(),
      ),
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.edit_document,
            size: 64,
            color: colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            '选择一个章节或设定开始创作',
            style: context.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '从左侧边栏选择章节或设定',
            style: context.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
