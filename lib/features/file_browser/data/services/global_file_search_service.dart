import 'dart:async';

import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

const _fallbackDirectoryLimit = 256;
const _fallbackTimeBudget = Duration(seconds: 20);

/// 跨 NAS 文件搜索结果，保留来源信息供命令面板切换数据源并定位目录。
class GlobalFileSearchHit {
  const GlobalFileSearchHit({
    required this.sourceId,
    required this.sourceName,
    required this.file,
  });

  final String sourceId;
  final String sourceName;
  final FileItem file;
}

/// 单个可搜索文件系统。
class GlobalFileSearchSource {
  const GlobalFileSearchSource({
    required this.id,
    required this.name,
    required this.fileSystem,
    this.rootPath = '/',
  });

  final String id;
  final String name;
  final String rootPath;
  final NasFileSystem fileSystem;
}

/// 搜索全部已连接数据源。
///
/// 优先使用适配器的服务端/原生搜索；返回空或抛出未实现错误时，再用目录遍历
/// 兜底。遍历找到足够结果会提前结束，避免为了命令面板预览扫描完整大盘。
Future<List<GlobalFileSearchHit>> searchConnectedFileSystems(
  Iterable<GlobalFileSearchSource> sources,
  String query, {
  int maxResultsPerSource = 8,
}) async {
  final normalized = query.trim();
  if (normalized.isEmpty) return const [];
  final batches = await Future.wait([
    for (final source in sources)
      _searchSource(source, normalized, maxResults: maxResultsPerSource),
  ]);
  return [for (final batch in batches) ...batch];
}

Future<List<GlobalFileSearchHit>> _searchSource(
  GlobalFileSearchSource source,
  String query, {
  required int maxResults,
}) async {
  var native = const <FileItem>[];
  try {
    native = await source.fileSystem
        .search(query, path: source.rootPath)
        .timeout(const Duration(seconds: 15));
  } on Exception {
    // 继续使用通用目录遍历兜底。
  }
  if (native.isNotEmpty) {
    return [
      for (final file in native.take(maxResults))
        GlobalFileSearchHit(
          sourceId: source.id,
          sourceName: source.name,
          file: file,
        ),
    ];
  }

  final files = await _recursiveSearch(
    source.fileSystem,
    source.rootPath,
    query,
    maxResults: maxResults,
  );
  return [
    for (final file in files)
      GlobalFileSearchHit(
        sourceId: source.id,
        sourceName: source.name,
        file: file,
      ),
  ];
}

Future<List<FileItem>> _recursiveSearch(
  NasFileSystem fileSystem,
  String root,
  String query, {
  required int maxResults,
}) async {
  final normalized = query.toLowerCase();
  final pending = <String>[root];
  final visited = <String>{};
  final hits = <FileItem>[];
  final deadline = DateTime.now().add(_fallbackTimeBudget);

  while (pending.isNotEmpty &&
      hits.length < maxResults &&
      visited.length < _fallbackDirectoryLimit &&
      DateTime.now().isBefore(deadline)) {
    final path = pending.removeAt(0);
    if (!visited.add(path)) continue;
    List<FileItem> children;
    try {
      children = await fileSystem
          .listDirectory(path)
          .timeout(const Duration(seconds: 8));
    } on Exception {
      continue;
    }
    for (final child in children) {
      if (child.name.toLowerCase().contains(normalized) ||
          child.path.toLowerCase().contains(normalized)) {
        hits.add(child);
        if (hits.length >= maxResults) break;
      }
      if (child.isDirectory && !child.isHidden) pending.add(child.path);
    }
  }
  return hits;
}

String parentDirectoryOf(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final index = normalized.lastIndexOf('/');
  if (index <= 0) return '/';
  return normalized.substring(0, index);
}
