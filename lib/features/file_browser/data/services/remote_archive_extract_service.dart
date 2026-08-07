import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive_lib;
import 'package:my_nas/core/utils/file_name_sanitizer.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum RemoteArchiveKind { zip, tar, tarGzip }

class RemoteArchiveExtractResult {
  const RemoteArchiveExtractResult({
    required this.destinationPath,
    required this.fileCount,
    required this.directoryCount,
  });

  final String destinationPath;
  final int fileCount;
  final int directoryCount;
}

class RemoteArchiveExtractService {
  const RemoteArchiveExtractService({this.workingRoot});

  /// 测试可注入；生产环境默认使用系统临时目录。
  final Directory? workingRoot;

  static const int maxArchiveBytes = 256 * 1024 * 1024;

  Future<RemoteArchiveExtractResult> extract({
    required NasFileSystem fileSystem,
    required FileItem archive,
    required String destinationDirectory,
  }) async {
    if (!fileSystem.supportsWriteOperations) {
      throw UnsupportedError('The selected file system is read-only.');
    }
    final kind = remoteArchiveKindForName(archive.name);
    if (kind == null) {
      throw UnsupportedError('Unsupported archive format: ${archive.name}');
    }
    if (archive.size > maxArchiveBytes) {
      throw StateError('Archive exceeds the 256 MB extraction limit.');
    }

    final base = workingRoot ?? await getTemporaryDirectory();
    final work = await Directory(
      p.join(
        base.path,
        'mynas_extract_${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    try {
      final localArchive = File(p.join(work.path, archive.name));
      final sink = localArchive.openWrite();
      try {
        final stream = await fileSystem.getFileStream(archive.path);
        await stream.pipe(sink);
      } finally {
        await sink.close();
      }
      if (await localArchive.length() > maxArchiveBytes) {
        throw StateError('Archive exceeds the 256 MB extraction limit.');
      }

      final extracted = await Directory(
        p.join(work.path, 'extracted'),
      ).create(recursive: true);
      final decoded = _decode(await localArchive.readAsBytes(), kind);
      var fileCount = 0;
      final localDirectories = <String>{};
      for (final entry in decoded.files) {
        final relative = safeArchiveRelativePath(entry.name);
        if (relative == null) continue;
        final localPath = p.joinAll([extracted.path, ...relative.split('/')]);
        if (!entry.isFile) {
          await Directory(localPath).create(recursive: true);
          localDirectories.add(relative);
          continue;
        }
        final output = File(localPath);
        await output.parent.create(recursive: true);
        final content = entry.content as List<int>?;
        if (content == null) continue;
        await output.writeAsBytes(content, flush: true);
        fileCount++;
        var parent = p.posix.dirname(relative);
        while (parent != '.' && parent.isNotEmpty) {
          localDirectories.add(parent);
          parent = p.posix.dirname(parent);
        }
      }
      if (fileCount == 0) {
        throw StateError('The archive contains no extractable files.');
      }

      final destinationName = await _availableDestinationName(
        fileSystem,
        destinationDirectory,
        archiveBaseName(archive.name),
      );
      final destinationPath = remotePathJoin(
        destinationDirectory,
        destinationName,
      );
      await fileSystem.createDirectory(destinationPath);

      final directories = localDirectories.toList()
        ..sort((a, b) => a.split('/').length.compareTo(b.split('/').length));
      for (final relative in directories) {
        await fileSystem.createDirectory(
          remotePathJoin(destinationPath, relative),
        );
      }

      await for (final entity in extracted.list(recursive: true)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: extracted.path);
        final normalized = relative.replaceAll(r'\', '/');
        final parent = p.posix.dirname(normalized);
        await fileSystem.upload(
          entity.path,
          parent == '.'
              ? destinationPath
              : remotePathJoin(destinationPath, parent),
          fileName: p.posix.basename(normalized),
        );
      }

      return RemoteArchiveExtractResult(
        destinationPath: destinationPath,
        fileCount: fileCount,
        directoryCount: directories.length + 1,
      );
    } finally {
      try {
        await work.delete(recursive: true);
      } on Exception {
        // 临时目录清理失败不改变已经成功写入 NAS 的结果。
      }
    }
  }

  archive_lib.Archive _decode(Uint8List bytes, RemoteArchiveKind kind) =>
      switch (kind) {
        RemoteArchiveKind.zip => archive_lib.ZipDecoder().decodeBytes(bytes),
        RemoteArchiveKind.tar => archive_lib.TarDecoder().decodeBytes(bytes),
        RemoteArchiveKind.tarGzip => archive_lib.TarDecoder().decodeBytes(
          archive_lib.GZipDecoder().decodeBytes(bytes),
        ),
      };

  Future<String> _availableDestinationName(
    NasFileSystem fileSystem,
    String directory,
    String preferred,
  ) async {
    final used = <String>{};
    try {
      used.addAll(
        (await fileSystem.listDirectory(directory)).map((e) => e.name),
      );
    } on Exception {
      // 某些适配器不允许重复列目录；直接使用首选名称并让创建操作给出真实错误。
    }
    if (!used.contains(preferred)) return preferred;
    var suffix = 2;
    while (used.contains('$preferred ($suffix)')) {
      suffix++;
    }
    return '$preferred ($suffix)';
  }
}

RemoteArchiveKind? remoteArchiveKindForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    return RemoteArchiveKind.tarGzip;
  }
  if (lower.endsWith('.tar')) return RemoteArchiveKind.tar;
  if (lower.endsWith('.zip') || lower.endsWith('.cbz')) {
    return RemoteArchiveKind.zip;
  }
  return null;
}

String archiveBaseName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.tar.gz')) return name.substring(0, name.length - 7);
  if (lower.endsWith('.tgz')) return name.substring(0, name.length - 4);
  final extension = p.extension(name);
  return extension.isEmpty
      ? name
      : name.substring(0, name.length - extension.length);
}

String? safeArchiveRelativePath(String entryName) {
  final normalized = entryName.replaceAll(r'\', '/');
  if (normalized.startsWith('/') || RegExp('^[A-Za-z]:').hasMatch(normalized)) {
    return null;
  }
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty || parts.any((part) => part == '..')) return null;
  // 压缩包条目名可能含 `:` 等 Windows 非法字符，落到本地临时目录时
  // `File()` 会抛异常。这里统一清洗，保证本地落地与远端上传路径一致。
  final safe = parts
      .where((part) => part != '.')
      .map((part) => sanitizeFileName(part, fallback: 'unnamed_entry'))
      .join('/');
  return safe.isEmpty ? null : safe;
}

String remotePathJoin(String base, String child) {
  final cleanBase = base == '/' ? '' : base.replaceAll(RegExp(r'/+$'), '');
  final cleanChild = child.replaceAll(RegExp('^/+'), '');
  return '$cleanBase/$cleanChild';
}
