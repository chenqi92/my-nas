// MOBI 到 EPUB 转换器
//
// 将 MOBI/AZW3 转换为多章节 EPUB，保留目录结构
// 用于漫画阅读器等需要 EPUB 格式的场景

// ignore_for_file: unnecessary_null_comparison, dead_code

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_header.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_index.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_record.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_text.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// EPUB 转换结果
class EpubConversionResult {
  const EpubConversionResult({
    required this.success,
    this.epubPath,
    this.title,
    this.author,
    this.chapterCount = 0,
    this.error,
  });

  factory EpubConversionResult.failure(String error) => EpubConversionResult(
        success: false,
        error: error,
      );

  factory EpubConversionResult.success({
    required String epubPath,
    String? title,
    String? author,
    int chapterCount = 0,
  }) =>
      EpubConversionResult(
        success: true,
        epubPath: epubPath,
        title: title,
        author: author,
        chapterCount: chapterCount,
      );

  final bool success;
  final String? epubPath;
  final String? title;
  final String? author;
  final int chapterCount;
  final String? error;
}

/// MOBI 到 EPUB 转换器
class MobiToEpubConverter {
  /// 将 MOBI 字节数据转换为 EPUB 文件
  static Future<EpubConversionResult> convert(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      // 1. 解析 MOBI 头部
      final header = MobiHeaderParser.parse(bytes);
      if (header == null) {
        return EpubConversionResult.failure('无法解析 MOBI 文件');
      }

      logger..i('MOBI 解析成功: ${header.title}')
      ..d('压缩: ${header.compression.label}, '
          '编码: ${header.encoding.label}, '
          'NCX: ${header.hasNcx}');

      // 2. 提取文本内容
      final htmlContent = await MobiTextExtractor.extractText(header);
      if (htmlContent.isEmpty) {
        return EpubConversionResult.failure('无法提取文本内容');
      }

      logger.d('提取文本: ${htmlContent.length} 字符');

      // 3. 解析章节（优先使用 NCX，否则从 HTML 提取）
      var chapters = MobiIndexParser.parseChapters(header);
      if (chapters.isEmpty) {
        logger.d('使用 HTML 标题提取章节');
        chapters = MobiChapterExtractor.extractFromHtml(htmlContent);
      }

      logger.i('提取章节: ${chapters.length} 个');

      // 4. 提取封面和图片
      final images = _extractImages(header);
      logger.d('提取图片: ${images.length} 张');

      // 5. 生成 EPUB
      final epubPath = await _generateEpub(
        header: header,
        htmlContent: htmlContent,
        chapters: chapters,
        images: images,
        fileName: fileName,
      );

      return EpubConversionResult.success(
        epubPath: epubPath,
        title: header.title,
        author: header.author,
        chapterCount: chapters.length,
      );
    } on Exception catch (e, st) {
      logger.e('MOBI 转换失败', e, st);
      return EpubConversionResult.failure('转换失败: $e');
    }
  }

  /// 提取图片
  static Map<String, Uint8List> _extractImages(MobiHeader header) {
    final images = <String, Uint8List>{};

    if (header.firstImageRecord == null) return images;

    final firstImage = header.firstImageRecord!;
    final lastRecord = header.firstNonBookRecord ?? header.records.length;

    for (var i = firstImage; i < lastRecord && i < header.records.length; i++) {
      final data = header.records[i].data;
      if (data.isEmpty) continue;

      // 检测图片类型
      String? extension;
      if (data.length >= 3 && data[0] == 0xFF && data[1] == 0xD8) {
        extension = 'jpg';
      } else if (data.length >= 4 &&
          data[0] == 0x89 &&
          data[1] == 0x50 &&
          data[2] == 0x4E &&
          data[3] == 0x47) {
        extension = 'png';
      } else if (data.length >= 3 &&
          data[0] == 0x47 &&
          data[1] == 0x49 &&
          data[2] == 0x46) {
        extension = 'gif';
      }

      if (extension != null) {
        final imageId = i - firstImage + 1;
        final filename = 'image_$imageId.$extension';
        images[filename] = data;
      }
    }

    return images;
  }

  /// 生成 EPUB 文件
  static Future<String> _generateEpub({
    required MobiHeader header,
    required String htmlContent,
    required List<MobiChapter> chapters,
    required Map<String, Uint8List> images,
    required String fileName,
  }) async {
    final archive = Archive();
    final uuid = const Uuid().v4();
    final timestamp = DateTime.now().toUtc().toIso8601String();

    final title = header.title.isNotEmpty
        ? header.title
        : path.basenameWithoutExtension(fileName);
    final author = header.author ?? '未知作者';

    // 1. mimetype (必须是第一个文件，不压缩)
    _addFileToArchive(archive, 'mimetype', 'application/epub+zip');

    // 2. META-INF/container.xml
    _addFileToArchive(archive, 'META-INF/container.xml', '''
    <?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

    // 3. 分割内容为章节
    final chapterFiles = _splitIntoChapters(htmlContent, chapters, title);

    // 4. 生成 manifest 和 spine
    final manifestItems = StringBuffer();
    final spineItems = StringBuffer();

    for (var i = 0; i < chapterFiles.length; i++) {
      final chapterId = 'chapter_${i + 1}';
      manifestItems.writeln(
        '    <item id="$chapterId" href="$chapterId.xhtml" '
        'media-type="application/xhtml+xml"/>',
      );
      spineItems.writeln('    <itemref idref="$chapterId"/>');
    }

    // 添加图片到 manifest
    for (final imageName in images.keys) {
      final mediaType = imageName.endsWith('.png')
          ? 'image/png'
          : imageName.endsWith('.gif')
              ? 'image/gif'
              : 'image/jpeg';
      manifestItems.writeln(
        '    <item id="$imageName" href="images/$imageName" '
        'media-type="$mediaType"/>',
      );
    }

    // 5. OEBPS/content.opf
    _addFileToArchive(archive, 'OEBPS/content.opf', '''
    <?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:$uuid</dc:identifier>
    <dc:title>${_escapeXml(title)}</dc:title>
    <dc:creator>${_escapeXml(author)}</dc:creator>
    <dc:language>zh-CN</dc:language>
    <meta property="dcterms:modified">$timestamp</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
$manifestItems  </manifest>
  <spine>
$spineItems  </spine>
</package>''');

    // 6. OEBPS/nav.xhtml (导航文档)
    final navItems = StringBuffer();
    for (var i = 0; i < chapterFiles.length; i++) {
      final chapterTitle = i < chapters.length
          ? _escapeXml(chapters[i].title)
          : '第 ${i + 1} 章';
      navItems.writeln(
        '      <li><a href="chapter_${i + 1}.xhtml">$chapterTitle</a></li>',
      );
    }

    _addFileToArchive(archive, 'OEBPS/nav.xhtml', '''
    <?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN">
<head>
  <meta charset="UTF-8"/>
  <title>目录</title>
</head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>目录</h1>
    <ol>
$navItems    </ol>
  </nav>
</body>
</html>''');

    // 7. 添加章节文件
    for (var i = 0; i < chapterFiles.length; i++) {
      final chapterTitle = i < chapters.length
          ? _escapeXml(chapters[i].title)
          : '第 ${i + 1} 章';
      final chapterContent = chapterFiles[i];

      _addFileToArchive(
        archive,
        'OEBPS/chapter_${i + 1}.xhtml',
        '''
        <?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN">
<head>
  <meta charset="UTF-8"/>
  <title>$chapterTitle</title>
  <style type="text/css">
    body { font-family: sans-serif; line-height: 1.6; padding: 1em; }
    p { text-indent: 2em; margin: 0.5em 0; }
    h1, h2, h3 { text-indent: 0; margin: 1em 0 0.5em 0; }
  </style>
</head>
<body>
$chapterContent
</body>
</html>''',
      );
    }

    // 8. 添加图片
    for (final entry in images.entries) {
      archive.addFile(ArchiveFile(
        'OEBPS/images/${entry.key}',
        entry.value.length,
        entry.value,
      ));
    }

    // 9. 写入文件
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(path.join(tempDir.path, 'mobi_epub_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final epubFileName =
        '${title.hashCode.abs()}_${DateTime.now().millisecondsSinceEpoch}.epub';
    final epubPath = path.join(cacheDir.path, epubFileName);

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw StateError('EPUB ZIP 编码失败');
    }

    await File(epubPath).writeAsBytes(zipData);

    logger.i('EPUB 生成成功: $epubPath (${chapterFiles.length} 章)');
    return epubPath;
  }

  /// 分割 HTML 内容为章节
  static List<String> _splitIntoChapters(
    String html,
    List<MobiChapter> chapters,
    String title,
  ) {
    // 清理 HTML
    final cleanedHtml = _sanitizeHtml(html);

    if (chapters.isEmpty) {
      // 没有章节，返回整个内容
      return [cleanedHtml];
    }

    final result = <String>[];

    // 按章节偏移量分割
    for (var i = 0; i < chapters.length; i++) {
      final start = chapters[i].startOffset;
      final end = i + 1 < chapters.length
          ? chapters[i + 1].startOffset
          : cleanedHtml.length;

      // 确保范围有效
      final safeStart = start.clamp(0, cleanedHtml.length);
      final safeEnd = end.clamp(safeStart, cleanedHtml.length);

      if (safeEnd > safeStart) {
        final chapterContent = cleanedHtml.substring(safeStart, safeEnd);
        // 确保章节不为空
        if (chapterContent.trim().isNotEmpty) {
          result.add(chapterContent);
        }
      }
    }

    // 如果分割失败，返回整个内容
    if (result.isEmpty) {
      return [cleanedHtml];
    }

    return result;
  }

  /// 清理 HTML 内容
  static String _sanitizeHtml(String html) {
    var cleaned = html;

    // 移除可能存在的 DOCTYPE、html、head、body 标签
    cleaned = cleaned.replaceAll(
      RegExp('<!DOCTYPE[^>]*>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp('</?html[^>]*>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp('<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp('</?body[^>]*>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp('<meta[^>]*/?>',caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<\?xml[^>]*\?>', caseSensitive: false),
      '',
    );

    // 转义 XHTML 中不允许的 & 字符
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'&(?!(amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)'),
      (match) => '&amp;',
    );

    // 自闭合标签需要加斜杠
    cleaned = cleaned.replaceAllMapped(
      RegExp('<(br|hr|img|input|meta|link)([^/>]*)(?<!/)>',
          caseSensitive: false),
      (match) => '<${match.group(1)}${match.group(2) ?? ''}/>',
    );

    // 替换 MOBI 特殊标签
    cleaned = cleaned.replaceAll(
      RegExp(r'<mbp:pagebreak\s*/?>',caseSensitive: false),
      '<hr/>',
    );

    // 修复图片路径（recindex:xxx 格式）
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'src="?recindex:(\d+)"?', caseSensitive: false),
      (match) {
        final index = match.group(1);
        return 'src="images/image_$index.jpg"';
      },
    );

    return cleaned.trim();
  }

  /// 添加文件到 archive
  static void _addFileToArchive(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  /// XML 特殊字符转义
  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
