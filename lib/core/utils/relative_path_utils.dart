import 'dart:io';

/// 跨平台同步的相对路径统一使用的分隔符
///
/// 章节、设定项等会参与云同步的实体，在数据库中保存的是相对于书籍文件夹的相对路径。
/// 统一使用该分隔符可保证同一份数据在 Windows、Android 等平台间保持一致，
/// 避免某个平台特有的路径分隔符随元数据同步到其他平台。
/// 由于文件名本身不允许包含 `/`，因此可以安全地用它来切分路径片段
const String kRelativePathSeparator = '/';

/// 以统一的相对路径分隔符拼接路径片段，得到数据库中保存的相对路径
String joinRelativePath(List<String> parts) =>
    parts.join(kRelativePathSeparator);

/// 将数据库中保存的相对路径转换为当前平台的本地路径
///
/// 例如 Windows 上会把 "分卷名/章节名.txt" 转换为 "分卷名\章节名.txt"
String relativePathToPlatform(String relativePath) {
  if (Platform.pathSeparator == kRelativePathSeparator) return relativePath;
  return relativePath
      .split(kRelativePathSeparator)
      .join(Platform.pathSeparator);
}
