import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// 章节归档包内的清单文件名
const String kArchiveManifestFileName = '_manifest.json';

/// 章节归档包的文件扩展名
const String kArchiveExtension = '.zip';

/// 每多少章合并为一个归档包
///
/// 坚果云对 WebDAV 请求次数有严格限制，逐章上传会迅速耗尽配额；
/// 合并归档可以成数量级地减少请求次数。分块而非整本打包，
/// 是为把「修改少量章节」的重复传输量控制在较小范围
const int kChapterChunkSize = 100;

/// 生成章节归档包的逻辑键
///
/// [chunkIndex] 为章节按顺序每 [kChapterChunkSize] 章划分后的块序号
String chapterChunkKey(String bookUuid, int chunkIndex) {
  final paddedIndex = chunkIndex.toString().padLeft(3, '0');
  return 'books/$bookUuid/chapters/$paddedIndex$kArchiveExtension';
}

/// 判断逻辑键是否为章节归档包
bool isChapterChunkKey(String key) {
  return key.contains('/chapters/') && key.endsWith(kArchiveExtension);
}

/// 章节归档清单中的一个章节项
///
/// 记录章节在归档包中的身份与内容特征，是判断章节是否变化、下载后校验完整性的依据
class ChapterManifestEntry {
  /// 章节 UUID，同时也是归档包内的文件名
  final String uuid;

  /// 章节正文的内容哈希（sha256 十六进制字符串）
  final String hash;

  /// 章节正文的字节数
  final int size;

  const ChapterManifestEntry({
    required this.uuid,
    required this.hash,
    required this.size,
  });

  /// 归档包内的文件名
  String get entryName => '$uuid.txt';

  Map<String, dynamic> toJson() => {'uuid': uuid, 'hash': hash, 'size': size};

  factory ChapterManifestEntry.fromJson(Map<String, dynamic> json) {
    return ChapterManifestEntry(
      uuid: json['uuid'] as String? ?? '',
      hash: json['hash'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

/// 章节归档清单
///
/// 章节按 UUID 升序排列，保证同一批章节无论本地顺序如何变化都能得到相同的清单，
/// 从而使「内容未变则不重传」的判断稳定可靠
class ChapterArchiveManifest {
  /// 清单格式版本
  final int version;

  /// 章节项列表（按 UUID 升序）
  final List<ChapterManifestEntry> entries;

  const ChapterArchiveManifest({this.version = 1, required this.entries});

  /// 序列化为清单文件内容
  Uint8List toBytes() {
    final jsonMap = <String, dynamic>{
      'version': version,
      'chapters': entries.map((entry) => entry.toJson()).toList(),
    };
    return utf8.encode(jsonEncode(jsonMap));
  }

  /// 从清单文件内容反序列化
  factory ChapterArchiveManifest.fromBytes(List<int> bytes) {
    final jsonMap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final rawChapters = jsonMap['chapters'];
    final entries = <ChapterManifestEntry>[];
    if (rawChapters is List) {
      for (final rawEntry in rawChapters) {
        if (rawEntry is Map<String, dynamic>) {
          entries.add(ChapterManifestEntry.fromJson(rawEntry));
        }
      }
    }
    return ChapterArchiveManifest(
      version: jsonMap['version'] as int? ?? 1,
      entries: entries,
    );
  }
}

/// 归档包的内容标识
///
/// 以清单的哈希作为整个归档包的内容标识：任一章节内容变化都会改变清单，
/// 因此无需解压或逐个比对文件即可判断归档包是否发生变化
String manifestHashOf(ChapterArchiveManifest manifest) {
  return sha256.convert(manifest.toBytes()).toString();
}

/// 待打包的章节
class ChapterArchiveSource {
  /// 章节 UUID
  final String uuid;

  /// 章节正文的本地绝对路径
  final String localPath;

  /// 章节正文的内容哈希（sha256 十六进制字符串）
  final String hash;

  /// 章节正文的字节数
  final int size;

  const ChapterArchiveSource({
    required this.uuid,
    required this.localPath,
    required this.hash,
    required this.size,
  });
}

/// 由待打包章节生成归档清单
///
/// 按 UUID 升序排列，使清单内容只取决于章节集合本身
ChapterArchiveManifest buildManifest(List<ChapterArchiveSource> sources) {
  final sorted = List<ChapterArchiveSource>.from(sources)
    ..sort((a, b) => a.uuid.compareTo(b.uuid));

  return ChapterArchiveManifest(
    entries: [
      for (final source in sorted)
        ChapterManifestEntry(
          uuid: source.uuid,
          hash: source.hash,
          size: source.size,
        ),
    ],
  );
}

/// 将章节打包为归档字节
///
/// 归档内含清单文件与各章节正文，正文以章节 UUID 命名，
/// 与本地文件名解耦，使本地重命名章节不会影响归档内容
Future<Uint8List> packArchive(
  ChapterArchiveManifest manifest,
  List<ChapterArchiveSource> sources,
) async {
  final sourceByUuid = {for (final source in sources) source.uuid: source};
  final archive = Archive();

  // 先放入清单，便于下载后无需遍历全部条目即可完成校验
  final manifestBytes = manifest.toBytes();
  archive.addFile(
    ArchiveFile(kArchiveManifestFileName, manifestBytes.length, manifestBytes),
  );

  for (final entry in manifest.entries) {
    final source = sourceByUuid[entry.uuid];
    if (source == null) continue;

    final bytes = await File(source.localPath).readAsBytes();
    archive.addFile(ArchiveFile(entry.entryName, bytes.length, bytes));
  }

  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('章节归档打包失败');
  }
  return Uint8List.fromList(encoded);
}

/// 归档包的解包结果
class ChapterArchiveContent {
  /// 归档清单
  final ChapterArchiveManifest manifest;

  /// 章节 UUID → 章节正文
  final Map<String, Uint8List> chapters;

  const ChapterArchiveContent({required this.manifest, required this.chapters});
}

/// 解包归档字节
///
/// 返回清单与各章节正文，供调用方校验后再写入本地
ChapterArchiveContent unpackArchive(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  // 读取清单
  final manifestFile = archive.findFile(kArchiveManifestFileName);
  if (manifestFile == null) {
    throw StateError('归档包缺少清单文件');
  }
  final manifest = ChapterArchiveManifest.fromBytes(
    manifestFile.content as List<int>,
  );

  // 读取各章节正文
  final chapters = <String, Uint8List>{};
  for (final entry in manifest.entries) {
    final file = archive.findFile(entry.entryName);
    if (file == null) continue;
    chapters[entry.uuid] = Uint8List.fromList(file.content as List<int>);
  }

  return ChapterArchiveContent(manifest: manifest, chapters: chapters);
}

/// 校验解包结果是否与清单一致
///
/// 逐章核对内容哈希，任一章节不一致即视为归档不完整
void verifyArchiveContent(ChapterArchiveContent content) {
  for (final entry in content.manifest.entries) {
    final bytes = content.chapters[entry.uuid];
    if (bytes == null) {
      throw StateError('归档包缺少章节内容: ${entry.uuid}');
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != entry.hash) {
      throw StateError('章节内容校验失败: ${entry.uuid}');
    }
  }
}
