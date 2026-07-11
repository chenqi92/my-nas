import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as path;

const _epubImageExtensions = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
};

const _maxEpubBytes = 512 * 1024 * 1024;
const _maxSingleImageBytes = 80 * 1024 * 1024;
const _maxFullExtractBytes = 192 * 1024 * 1024;

/// EPUB 图片页面
class EpubImagePage {
  const EpubImagePage({
    required this.index,
    required this.name,
    required this.data,
    required this.mimeType,
  });

  final int index;
  final String name;
  final Uint8List data;
  final String mimeType;
}

/// EPUB 图片提取器
///
/// 从 EPUB 文件中提取图片，用于漫画阅读器
class EpubImageExtractor {
  EpubImageExtractor._();
  static final EpubImageExtractor instance = EpubImageExtractor._();
  Future<void> _archiveOperationTail = Future<void>.value();

  Future<T> _runArchiveOperation<T>(Future<T> Function() operation) {
    final result = _archiveOperationTail.then<T>((_) => operation());
    _archiveOperationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// 从 EPUB 文件提取所有图片
  Future<List<EpubImagePage>> extractImages(File epubFile) async {
    try {
      logger.d('EpubImageExtractor: 开始提取图片 ${epubFile.path}');

      await _checkEpubSize(epubFile);
      final images = await _runArchiveOperation(
        () => compute(_extractAllEpubImages, epubFile.path),
      );

      logger.i('EpubImageExtractor: 提取完成，共 ${images.length} 张图片');
      return images;
    } on Exception catch (e, st) {
      logger.e('EpubImageExtractor: 提取图片失败', e, st);
      rethrow;
    }
  }

  /// 分批提取图片（用于大文件）
  ///
  /// [startIndex] 起始索引
  /// [count] 提取数量
  Future<List<EpubImagePage>> extractImagesBatch(
    File epubFile, {
    required int startIndex,
    required int count,
  }) async {
    try {
      await _checkEpubSize(epubFile);
      return _runArchiveOperation(
        () => compute(_extractEpubImagesBatch, {
          'path': epubFile.path,
          'startIndex': startIndex,
          'count': count,
        }),
      );
    } on Exception catch (e, st) {
      logger.e('EpubImageExtractor: 分批提取图片失败', e, st);
      rethrow;
    }
  }

  /// 获取 EPUB 中的图片总数
  Future<int> getImageCount(File epubFile) async {
    try {
      await _checkEpubSize(epubFile);
      return _runArchiveOperation(
        () => compute(_countEpubImages, epubFile.path),
      );
    } catch (e) {
      logger.w('EpubImageExtractor: 获取图片数量失败: $e');
      rethrow;
    }
  }

  /// 获取单张图片
  Future<EpubImagePage?> getImage(File epubFile, int index) async {
    try {
      if (index < 0) return null;
      await _checkEpubSize(epubFile);
      final pages = await extractImagesBatch(
        epubFile,
        startIndex: index,
        count: 1,
      );
      return pages.isEmpty ? null : pages.first;
    } on Exception catch (e) {
      logger.w('EpubImageExtractor: 获取图片失败: $e');
      return null;
    }
  }

  Future<void> _checkEpubSize(File epubFile) async {
    final size = await epubFile.length();
    if (size > _maxEpubBytes) {
      throw Exception('EPUB 文件过大，已拒绝一次性解析: $size bytes');
    }
  }
}

List<EpubImagePage> _extractAllEpubImages(String epubPath) {
  final imageFiles = _readSortedEpubImageFiles(epubPath);
  final images = <EpubImagePage>[];
  var totalBytes = 0;

  for (var index = 0; index < imageFiles.length; index++) {
    final file = imageFiles[index];
    final size = file.size;
    totalBytes += size;
    if (size > _maxSingleImageBytes || totalBytes > _maxFullExtractBytes) {
      throw Exception('EPUB 图片总量过大，请使用分批加载');
    }
    images.add(_toEpubImagePage(file, index));
  }

  return images;
}

List<EpubImagePage> _extractEpubImagesBatch(Map<String, Object?> args) {
  final epubPath = args['path']! as String;
  final startIndex = args['startIndex']! as int;
  final count = args['count']! as int;
  final imageFiles = _readSortedEpubImageFiles(epubPath);
  final images = <EpubImagePage>[];
  final endIndex = (startIndex + count).clamp(0, imageFiles.length);

  for (var index = startIndex; index < endIndex; index++) {
    final file = imageFiles[index];
    if (file.size > _maxSingleImageBytes) {
      throw Exception('EPUB 单张图片过大: ${file.name}');
    }
    images.add(_toEpubImagePage(file, index));
  }

  return images;
}

int _countEpubImages(String epubPath) =>
    _readSortedEpubImageFiles(epubPath).length;

List<ArchiveFile> _readSortedEpubImageFiles(String epubPath) {
  final file = File(epubPath);
  final bytes = file.readAsBytesSync();
  if (bytes.length > _maxEpubBytes) {
    throw Exception('EPUB 文件过大，已拒绝解析: ${bytes.length} bytes');
  }

  final archive = ZipDecoder().decodeBytes(bytes);
  return archive.files
      .where((f) => f.isFile && _isEpubImageFile(f.name))
      .toList()
    ..sort((a, b) => _naturalSortEpubImage(a.name, b.name));
}

EpubImagePage _toEpubImagePage(ArchiveFile file, int index) {
  final ext = path.extension(file.name).toLowerCase();
  final mimeType = _epubImageExtensions[ext] ?? 'image/jpeg';
  final content = file.content as List<int>;

  return EpubImagePage(
    index: index,
    name: path.basename(file.name),
    data: Uint8List.fromList(content),
    mimeType: mimeType,
  );
}

bool _isEpubImageFile(String filename) {
  final ext = path.extension(filename).toLowerCase();
  return _epubImageExtensions.containsKey(ext);
}

int _naturalSortEpubImage(String a, String b) {
  final regExp = RegExp(r'(\d+)');
  final aMatches = regExp.allMatches(a).toList();
  final bMatches = regExp.allMatches(b).toList();

  if (aMatches.isEmpty && bMatches.isEmpty) {
    return a.compareTo(b);
  }

  if (aMatches.isNotEmpty && bMatches.isNotEmpty) {
    final aNum = int.tryParse(aMatches.last.group(0)!) ?? 0;
    final bNum = int.tryParse(bMatches.last.group(0)!) ?? 0;
    if (aNum != bNum) return aNum.compareTo(bNum);
  }

  return a.compareTo(b);
}
