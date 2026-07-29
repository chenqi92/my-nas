import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui
    show Color, Image, ImageByteFormat, PixelFormat, decodeImageFromPixels;

import 'package:epub_plus/epub_plus.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/services/performance_mode_service.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/mobi_parser_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_pool_config.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// 用于等待图片解码完成的辅助类
class _ImageCompleter {
  final _completer = Completer<ui.Image?>();

  Future<ui.Image?> get future => _completer.future;

  void complete(ui.Image image) {
    if (!_completer.isCompleted) {
      _completer.complete(image);
    }
  }
}

/// 图书封面提取服务
///
/// 支持从 EPUB 和 PDF 文件中提取封面图片
class BookCoverService {
  static const String _boxName = 'book_covers';
  static const String _coverDir = 'book_covers';

  /// 最大并发提取数量（动态计算，支持性能模式）
  ///
  /// 普通模式：2
  /// 性能模式：桌面 8，移动 4
  static int get _maxConcurrentExtractions {
    if (PerformanceModeService.isPerformanceMode) {
      return SmbPoolConfig.isDesktop ? 8 : 4;
    }
    return 2;
  }

  Box<String>? _box;
  String? _coverDirPath;

  /// 当前正在进行的提取任务数量
  int _activeExtractions = 0;

  /// 等待队列
  final List<Completer<void>> _waitQueue = [];

  /// 初始化服务
  Future<void> init() async {
    if (_box != null) return;

    _box = await Hive.openBox<String>(_boxName);

    // 创建封面缓存目录
    final appDir = await getApplicationDocumentsDirectory();
    _coverDirPath = path.join(appDir.path, _coverDir);
    final dir = Directory(_coverDirPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// 获取封面路径（如果已缓存）
  String? getCachedCoverPath(String bookPath, String sourceId) {
    final key = _generateKey(bookPath, sourceId);
    return _box?.get(key);
  }

  /// 等待获取提取槽位（并发控制）
  Future<void> _acquireSlot() async {
    if (_activeExtractions < _maxConcurrentExtractions) {
      _activeExtractions++;
      return;
    }
    // 需要等待
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  /// 释放提取槽位
  void _releaseSlot() {
    _activeExtractions--;
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      _activeExtractions++;
      next.complete();
    }
  }

  /// 提取并缓存封面（带并发控制）
  Future<String?> extractAndCacheCover({
    required String bookPath,
    required String sourceId,
    required BookFormat format,
    required NasFileSystem fileSystem,
  }) async {
    await init();

    final key = _generateKey(bookPath, sourceId);

    // 检查是否已缓存（快速路径，不需要槽位）
    final cached = _box?.get(key);
    if (cached != null && await File(cached).exists()) {
      return cached;
    }

    // 等待获取槽位
    await _acquireSlot();

    try {
      // 再次检查缓存（可能在等待期间已被其他任务缓存）
      final cachedAgain = _box?.get(key);
      if (cachedAgain != null && await File(cachedAgain).exists()) {
        return cachedAgain;
      }

      Uint8List? coverBytes;

      switch (format) {
        case BookFormat.epub:
          coverBytes = await _extractEpubCover(bookPath, fileSystem);
        case BookFormat.pdf:
          coverBytes = await _extractPdfCover(bookPath, fileSystem);
        case BookFormat.mobi:
        case BookFormat.azw3:
          coverBytes = await _extractMobiCover(bookPath, fileSystem);
        case BookFormat.txt:
        case BookFormat.unknown:
          return null;
      }

      if (coverBytes == null || coverBytes.isEmpty) {
        return null;
      }

      // 保存封面到本地
      final coverPath = await _saveCover(key, coverBytes);
      if (coverPath != null) {
        await _box?.put(key, coverPath);
      }
      return coverPath;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '封面提取失败不影响核心功能');
      return null;
    } finally {
      _releaseSlot();
    }
  }

  /// 从 EPUB 文件提取封面
  Future<Uint8List?> _extractEpubCover(
    String bookPath,
    NasFileSystem fileSystem,
  ) async {
    try {
      final stream = await fileSystem.getFileStream(bookPath);
      final bytes = <int>[];
      await for (final chunk in stream) {
        bytes.addAll(chunk);
        if (bytes.length > 50 * 1024 * 1024) {
          logger.w('EPUB 文件过大，跳过封面提取: $bookPath');
          return null;
        }
      }

      // 使用 epub_plus 解析 EPUB
      final epubBook = await EpubReader.readBook(bytes);

      // 获取封面图片
      final coverImage = epubBook.coverImage;
      if (coverImage != null) {
        // epub_plus 返回的是 image 包的 Image 对象，需要编码为 PNG
        final pngBytes = img.encodePng(coverImage);
        if (_isValidImageData(Uint8List.fromList(pngBytes))) {
          return Uint8List.fromList(pngBytes);
        }
      }

      // 如果没有封面图片，尝试从 content.images 获取第一张图片
      final images = epubBook.content?.images;
      if (images != null && images.isNotEmpty) {
        // 优先查找名称包含 cover 的图片
        for (final entry in images.entries) {
          if (entry.key.toLowerCase().contains('cover')) {
            final imageBytes = entry.value.content;
            if (imageBytes != null) {
              final bytes = Uint8List.fromList(imageBytes);
              if (_isValidImageData(bytes)) {
                return bytes;
              }
            }
          }
        }
        // 否则使用第一张图片
        final firstImage = images.values.first;
        final imageBytes = firstImage.content;
        if (imageBytes != null) {
          final bytes = Uint8List.fromList(imageBytes);
          if (_isValidImageData(bytes)) {
            return bytes;
          }
        }
      }

      logger.d('EPUB 没有封面: $bookPath');
      return null;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'EPUB封面提取失败');
      return null;
    }
  }

  /// 从 MOBI/AZW3 文件提取封面
  Future<Uint8List?> _extractMobiCover(
    String bookPath,
    NasFileSystem fileSystem,
  ) async {
    try {
      final stream = await fileSystem.getFileStream(bookPath);
      final bytes = <int>[];
      await for (final chunk in stream) {
        bytes.addAll(chunk);
        if (bytes.length > 50 * 1024 * 1024) {
          logger.w('MOBI 文件过大，跳过封面提取: $bookPath');
          return null;
        }
      }

      // 使用 MobiParserService 提取封面
      final parser = MobiParserService();
      final coverBytes = await parser.extractCover(Uint8List.fromList(bytes));

      if (coverBytes != null && _isValidImageData(coverBytes)) {
        return coverBytes;
      }

      logger.d('MOBI 没有封面: $bookPath');
      return null;
    } on Exception catch (e) {
      logger.w('提取 MOBI 封面失败: $bookPath', e);
      return null;
    }
  }

  /// PDF 封面提取的最大文件大小 (30MB)
  /// 降低限制以避免大文件导致内存溢出闪退
  static const int _maxPdfSizeForCover = 30 * 1024 * 1024;

  /// 从 PDF 文件提取封面（渲染第一页）
  Future<Uint8List?> _extractPdfCover(
    String bookPath,
    NasFileSystem fileSystem,
  ) async {
    File? tempFile;
    PdfDocument? doc;

    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = path.basename(bookPath);
      tempFile = File(path.join(tempDir.path, 'cover_$fileName'));

      // 只读取前 30MB，足够提取封面
      final stream = await fileSystem.getFileStream(bookPath);
      final bytes = <int>[];
      await for (final chunk in stream) {
        bytes.addAll(chunk);
        if (bytes.length > _maxPdfSizeForCover) {
          logger.w('PDF 文件过大 (>${_maxPdfSizeForCover ~/ 1024 ~/ 1024}MB)，跳过封面提取: $bookPath');
          return null;
        }
      }

      // 文件过小可能不是有效 PDF
      if (bytes.length < 1024) {
        logger.d('PDF 文件过小，跳过封面提取: $bookPath');
        return null;
      }

      await tempFile.writeAsBytes(bytes);

      // 使用 try-catch 包装 PDF 库调用，防止 native 崩溃
      try {
        doc = await PdfDocument.openFile(tempFile.path)
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        logger.w('PDF 打开超时，跳过封面提取: $bookPath');
        return null;
      } catch (e) {
        // PDF 库可能抛出各种非 Exception 的错误
        logger.w('PDF 打开失败，跳过封面提取: $bookPath', e);
        return null;
      }

      if (doc.pages.isEmpty) {
        return null;
      }

      final page = doc.pages[0];
      final pdfImage = await page
          .render(
            width: 300,
            height: 400,
            backgroundColor: const ui.Color(0xFFFFFFFF),
          )
          .timeout(const Duration(seconds: 10));

      if (pdfImage == null || pdfImage.pixels.isEmpty) {
        return null;
      }

      // 将原始像素数据转换为 PNG 格式
      final pngBytes = await _convertRgbaToPng(
        pdfImage.pixels,
        pdfImage.width,
        pdfImage.height,
      );
      return pngBytes;
    } on TimeoutException {
      logger.w('PDF 封面提取超时: $bookPath');
      return null;
    } on Exception catch (e) {
      logger.w('提取 PDF 封面失败: $bookPath', e);
      return null;
    } finally {
      // 确保清理资源
      try {
        await doc?.dispose();
      } on Exception catch (_) {
        // ignore dispose errors
      }
      // 清理临时文件
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete().catchError((_) => tempFile!);
      }
    }
  }

  /// 将 RGBA 像素数据转换为 PNG 格式
  Future<Uint8List?> _convertRgbaToPng(
    Uint8List pixels,
    int width,
    int height,
  ) async {
    try {
      // 使用 dart:ui 创建图片并编码为 PNG
      final completer = _ImageCompleter();
      ui.decodeImageFromPixels(
        pixels,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      if (image == null) return null;

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } on Exception catch (e) {
      logger.w('转换 PDF 封面为 PNG 失败', e);
      return null;
    }
  }

  /// 保存封面到本地文件
  Future<String?> _saveCover(String key, Uint8List bytes) async {
    try {
      final fileName = '${key.hashCode.abs()}.jpg';
      final filePath = path.join(_coverDirPath!, fileName);
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } on Exception catch (e) {
      logger.w('保存封面失败: $key', e);
      return null;
    }
  }

  /// 生成缓存键
  String _generateKey(String bookPath, String sourceId) =>
      '${sourceId}_$bookPath';

  /// 清除所有缓存
  Future<void> clearCache() async {
    await init();
    await _box?.clear();

    if (_coverDirPath != null) {
      final dir = Directory(_coverDirPath!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    }
  }

  /// 删除指定源的所有封面缓存
  Future<void> deleteBySourceId(String sourceId) async {
    await init();

    final keysToDelete = <String>[];
    for (final key in _box?.keys ?? <String>[]) {
      if (key.toString().startsWith('${sourceId}_')) {
        keysToDelete.add(key.toString());
      }
    }

    for (final key in keysToDelete) {
      final coverPath = _box?.get(key);
      if (coverPath != null) {
        await File(coverPath).delete().catchError((_) => File(coverPath));
      }
      await _box?.delete(key);
    }
  }

  /// 验证是否为有效的图片数据
  ///
  /// 检查常见图片格式的魔数（文件头）
  bool _isValidImageData(Uint8List bytes) {
    if (bytes.length < 8) return false;

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }

    // GIF: 47 49 46 38
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true;
    }

    // WebP: 52 49 46 46 ... 57 45 42 50
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }

    // BMP: 42 4D
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return true;
    }

    return false;
  }
}
