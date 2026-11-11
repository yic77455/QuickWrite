import 'package:quick_write/core/models/outline_link.dart';
import 'package:quick_write/core/services/workspace/outline_companion_store.dart';

/// 大纲关联服务
///
/// 负责单个设定项「大纲节点文本关联到其他文件」的持久化读写：
/// 关联目标与关联文本范围保存在设定项的合并伴生 `.json` 中，
/// 与大纲 Markdown 分离，避免关联信息影响导出与备份内容。
class OutlineLinkService {
  /// 读取设定项的关联内容
  ///
  /// 文件不存在或格式非法时返回空内容。
  Future<OutlineLinkFile> read(String? settingItemFilePath) {
    return OutlineCompanionStore.instance.readLinks(settingItemFilePath);
  }

  /// 保存设定项的关联内容
  ///
  /// [links] 为关联标识到关联目标的映射，[nodes] 为节点路径到关联文本范围的映射；
  /// 两者均无内容时清空对应字段，避免残留旧关联。
  Future<bool> save({
    required String? settingItemFilePath,
    required Map<String, OutlineLinkTarget> links,
    required Map<String, List<OutlineLinkRange>> nodes,
  }) {
    return OutlineCompanionStore.instance.updateLinks(
      settingItemFilePath: settingItemFilePath,
      links: links,
      nodes: nodes,
    );
  }
}
