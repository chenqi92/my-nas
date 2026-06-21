import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive_lib;
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 压缩文件类型
enum ArchiveType { zip, rar, sevenZip, unknown }

/// 解压结果
class ExtractResult {
  const ExtractResult({
    required this.success,
    this.files = const [],
    this.error,
  });

  factory ExtractResult.failure(String error) =>
      ExtractResult(success: false, error: error);

  factory ExtractResult.fromFiles(List<ExtractedFile> files) =>
      ExtractResult(success: true, files: files);

  final bool success;
  final List<ExtractedFile> files;
  final String? error;
}

/// 解压出的文件
class ExtractedFile {
  const ExtractedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// 跨平台压缩文件解压服务
///
/// 支持的格式：
/// - ZIP: 使用 archive 包（纯 Dart，全平台）
/// - RAR: 桌面平台使用系统命令，移动平台使用 rar 包
/// - 7z: 桌面平台使用系统命令
class ArchiveExtractService {
  factory ArchiveExtractService() => _instance ??= ArchiveExtractService._();

  ArchiveExtractService._();

  static ArchiveExtractService? _instance;

  /// 支持的图片扩展名
  static const _imageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  ];

  /// 从文件名获取压缩类型
  static ArchiveType getArchiveType(String fileName) {
    final ext = fileName.toLowerCase();
    if (ext.endsWith('.zip') || ext.endsWith('.cbz')) {
      return ArchiveType.zip;
    } else if (ext.endsWith('.rar') || ext.endsWith('.cbr')) {
      return ArchiveType.rar;
    } else if (ext.endsWith('.7z') || ext.endsWith('.cb7')) {
      return ArchiveType.sevenZip;
    }
    return ArchiveType.unknown;
  }

  /// 解压压缩文件并提取图片
  ///
  /// [archiveBytes] 压缩文件的字节数据
  /// [archiveType] 压缩类型
  /// [fileName] 文件名（用于创建临时文件）
  Future<ExtractResult> extractImages({
    required Uint8List archiveBytes,
    required ArchiveType archiveType,
    required String fileName,
  }) async {
    switch (archiveType) {
      case ArchiveType.zip:
        return _extractZip(archiveBytes);
      case ArchiveType.rar:
        return _extractRar(archiveBytes, fileName);
      case ArchiveType.sevenZip:
        return _extract7z(archiveBytes, fileName);
      case ArchiveType.unknown:
        return ExtractResult.failure(appL10n.archiveExtractUnknownFormat);
    }
  }

  /// 解压 ZIP 文件
  Future<ExtractResult> _extractZip(Uint8List bytes) async {
    try {
      final archive = archive_lib.ZipDecoder().decodeBytes(bytes);
      final files = <ExtractedFile>[];

      for (final file in archive.files) {
        if (file.isFile && _isImageFile(file.name)) {
          final content = file.content as List<int>?;
          if (content != null) {
            files.add(
              ExtractedFile(
                name: file.name,
                bytes: Uint8List.fromList(content),
              ),
            );
          }
        }
      }

      files.sort((a, b) => a.name.compareTo(b.name));
      return ExtractResult.fromFiles(files);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'extractZip');
      return ExtractResult.failure(appL10n.archiveExtractZipFailed(e));
    }
  }

  /// 解压 RAR 文件
  Future<ExtractResult> _extractRar(Uint8List bytes, String fileName) async {
    // 桌面平台使用系统命令
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return _extractWithSystemCommand(
        bytes: bytes,
        fileName: fileName,
        commands: _getRarCommands(),
        formatName: 'RAR',
      );
    }

    // 移动平台：尝试当作 ZIP 解压（有些 .cbr 实际是 ZIP）
    try {
      return await _extractZip(bytes);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'RAR格式在移动平台不支持，尝试ZIP解压失败');
      return ExtractResult.failure(appL10n.archiveExtractRarUnsupported);
    }
  }

  /// 解压 7z 文件
  Future<ExtractResult> _extract7z(Uint8List bytes, String fileName) async {
    // 桌面平台使用系统命令
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return _extractWithSystemCommand(
        bytes: bytes,
        fileName: fileName,
        commands: _get7zCommands(),
        formatName: '7z',
      );
    }

    return ExtractResult.failure(appL10n.archiveExtract7zUnsupported);
  }

  /// 使用系统命令解压
  Future<ExtractResult> _extractWithSystemCommand({
    required Uint8List bytes,
    required String fileName,
    required List<String> commands,
    required String formatName,
  }) async {
    // 查找可用的解压命令
    String? availableCommand;
    for (final cmd in commands) {
      if (await _isCommandAvailable(cmd)) {
        availableCommand = cmd;
        break;
      }
    }

    if (availableCommand == null) {
      return ExtractResult.failure(
        appL10n.archiveExtractToolNotInstalled(
          formatName,
          commands.join(', '),
          _getInstallHint(formatName),
        ),
      );
    }

    // 创建临时目录
    final tempDir = await getTemporaryDirectory();
    final workDir = Directory(
      path.join(
        tempDir.path,
        'comic_extract_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await workDir.create(recursive: true);

    try {
      // 写入临时文件
      final archiveFile = File(path.join(workDir.path, fileName));
      await archiveFile.writeAsBytes(bytes);

      // 创建解压目录
      final extractDir = Directory(path.join(workDir.path, 'extracted'));
      await extractDir.create();

      // 执行解压命令
      final result = await _runExtractCommand(
        command: availableCommand,
        archivePath: archiveFile.path,
        extractPath: extractDir.path,
      );

      if (!result) {
        return ExtractResult.failure(appL10n.archiveExtractFormatFailed(formatName));
      }

      // 读取解压出的图片文件
      final files = <ExtractedFile>[];
      await _collectImageFiles(extractDir, files);
      files.sort((a, b) => a.name.compareTo(b.name));

      return ExtractResult.fromFiles(files);
    } finally {
      // 清理临时目录
      try {
        await workDir.delete(recursive: true);
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '清理临时目录失败');
      }
    }
  }

  /// 递归收集图片文件
  Future<void> _collectImageFiles(
    Directory dir,
    List<ExtractedFile> files,
  ) async {
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && _isImageFile(entity.path)) {
        final bytes = await entity.readAsBytes();
        files.add(
          ExtractedFile(name: path.basename(entity.path), bytes: bytes),
        );
      }
    }
  }

  /// 检查命令是否可用
  Future<bool> _isCommandAvailable(String command) async {
    try {
      final whichCmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(whichCmd, [command]);
      return result.exitCode == 0;
    } on Exception catch (_) {
      return false;
    }
  }

  /// 执行解压命令
  Future<bool> _runExtractCommand({
    required String command,
    required String archivePath,
    required String extractPath,
  }) async {
    try {
      List<String> args;

      if (command == 'unrar') {
        args = ['x', '-y', archivePath, extractPath];
      } else if (command == '7z' || command == '7za' || command == '7zz') {
        args = ['x', '-y', '-o$extractPath', archivePath];
      } else if (command == 'unar') {
        args = ['-o', extractPath, archivePath];
      } else {
        return false;
      }

      final result = await Process.run(command, args);
      return result.exitCode == 0;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'runExtractCommand');
      return false;
    }
  }

  /// 获取 RAR 解压命令列表
  List<String> _getRarCommands() {
    if (Platform.isMacOS) {
      return ['unrar', 'unar', '7z', '7zz'];
    } else if (Platform.isWindows) {
      return ['unrar', '7z', '7za'];
    } else {
      return ['unrar', 'unar', '7z', '7za'];
    }
  }

  /// 获取 7z 解压命令列表
  List<String> _get7zCommands() {
    if (Platform.isMacOS) {
      return ['7z', '7zz', 'unar'];
    } else if (Platform.isWindows) {
      return ['7z', '7za'];
    } else {
      return ['7z', '7za', '7zr'];
    }
  }

  /// 获取安装提示
  String _getInstallHint(String formatName) {
    if (Platform.isMacOS) {
      return appL10n.archiveExtractInstallHintMacOS;
    } else if (Platform.isWindows) {
      return appL10n.archiveExtractInstallHintWindows;
    } else {
      return appL10n.archiveExtractInstallHintLinux;
    }
  }

  /// 检查是否是图片文件
  bool _isImageFile(String fileName) {
    final lower = fileName.toLowerCase();
    return _imageExtensions.any(lower.endsWith);
  }
}
