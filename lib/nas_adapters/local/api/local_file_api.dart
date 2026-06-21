import 'dart:io';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 本地文件 API
class LocalFileApi {
  LocalFileApi();

  /// 是否为移动端平台
  static bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  /// 是否为桌面端平台
  static bool get isDesktopPlatform =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 获取根目录列表
  ///
  /// 不同平台返回不同的根目录：
  /// - Windows: 所有可用驱动器 (C:\, D:\, etc.)
  /// - macOS: /Users, /Volumes
  /// - Linux: /, /home
  /// - Android: 用户选择的目录（移动端无法直接浏览文件系统）
  /// - iOS: 用户选择的目录（沙盒限制）
  Future<List<LocalRootDirectory>> getRootDirectories() async {
    // 移动端：返回用户选择的目录
    if (isMobilePlatform) {
      return _getMobileRoots();
    }

    // 桌面端：返回系统根目录
    if (Platform.isWindows) {
      return _getWindowsDrives();
    } else if (Platform.isMacOS) {
      return _getMacOSRoots();
    } else if (Platform.isLinux) {
      return _getLinuxRoots();
    }

    return [
      LocalRootDirectory(
        name: appL10n.localFileApiRootDirectoryName,
        path: '/',
        type: RootDirectoryType.system,
      ),
    ];
  }

  /// 获取移动端根目录（Android/iOS）
  ///
  /// 移动端返回应用沙盒目录。
  /// 注意：照片、音乐等媒体内容应通过各自的系统 API 访问，
  /// 而不是通过文件系统浏览。
  Future<List<LocalRootDirectory>> _getMobileRoots() async {
    if (Platform.isAndroid) {
      return _getAndroidRoots();
    } else if (Platform.isIOS) {
      return _getIOSRoots();
    }
    return [];
  }

  /// 获取 Android 根目录
  ///
  /// 返回应用可访问的目录
  Future<List<LocalRootDirectory>> _getAndroidRoots() async {
    final roots = <LocalRootDirectory>[];

    try {
      // 应用文档目录
      final docDir = await getApplicationDocumentsDirectory();
      roots.add(LocalRootDirectory(
        name: appL10n.localFileApiDocumentsName,
        path: docDir.path,
        type: RootDirectoryType.documents,
      ));

      // 外部存储应用目录
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        roots.add(LocalRootDirectory(
          name: appL10n.localFileApiAppDataName,
          path: extDir.path,
          type: RootDirectoryType.storage,
        ));
      }

      // 下载目录
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir != null) {
        roots.add(LocalRootDirectory(
          name: appL10n.localFileApiDownloadsName,
          path: downloadDir.path,
          type: RootDirectoryType.downloads,
        ));
      }
    } on Exception catch (e) {
      logger.e('LocalFileApi: 获取 Android 目录失败', e);
    }

    return roots;
  }

  /// 获取 Windows 驱动器列表
  Future<List<LocalRootDirectory>> _getWindowsDrives() async {
    final drives = <LocalRootDirectory>[];

    // 检查所有可能的驱动器字母
    for (var i = 65; i <= 90; i++) {
      // A-Z
      final letter = String.fromCharCode(i);
      final path = '$letter:\\';
      final dir = Directory(path);

      try {
        if (await dir.exists()) {
          drives.add(LocalRootDirectory(
            name: appL10n.localFileApiLocalDiskName(letter),
            path: path,
            type: RootDirectoryType.drive,
          ));
        }
      } on Exception catch (_) {
        // 忽略无法访问的驱动器
      }
    }

    return drives;
  }

  /// 获取 macOS 根目录
  Future<List<LocalRootDirectory>> _getMacOSRoots() async {
    final roots = <LocalRootDirectory>[];

    // 用户目录
    final homeDir = Platform.environment['HOME'];
    if (homeDir != null) {
      roots.add(LocalRootDirectory(
        name: appL10n.localFileApiPersonalName,
        path: homeDir,
        type: RootDirectoryType.home,
      ));
    }

    // 外接卷宗
    final volumesDir = Directory('/Volumes');
    try {
      if (await volumesDir.exists()) {
        await for (final entity in volumesDir.list()) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            // 排除 Macintosh HD，因为根目录已经包含
            if (name != 'Macintosh HD') {
              roots.add(LocalRootDirectory(
                name: name,
                path: entity.path,
                type: RootDirectoryType.volume,
              ));
            }
          }
        }
      }
    } on Exception catch (e) {
      logger.w('LocalFileApi: 无法列出 /Volumes', e);
    }

    return roots;
  }

  /// 获取 Linux 根目录
  Future<List<LocalRootDirectory>> _getLinuxRoots() async {
    final roots = <LocalRootDirectory>[];

    // 用户目录
    final homeDir = Platform.environment['HOME'];
    if (homeDir != null) {
      roots.add(LocalRootDirectory(
        name: appL10n.localFileApiHomeName,
        path: homeDir,
        type: RootDirectoryType.home,
      ));
    }

    // 根目录
    roots.add(LocalRootDirectory(
      name: '根目录',
      path: '/',
      type: RootDirectoryType.system,
    ));

    // 挂载的媒体
    final mediaDir = Directory('/media');
    try {
      if (await mediaDir.exists()) {
        // /media/username/ 目录
        await for (final userDir in mediaDir.list()) {
          if (userDir is Directory) {
            await for (final mount in userDir.list()) {
              if (mount is Directory) {
                roots.add(LocalRootDirectory(
                  name: p.basename(mount.path),
                  path: mount.path,
                  type: RootDirectoryType.volume,
                ));
              }
            }
          }
        }
      }
    } on Exception catch (e) {
      logger.w('LocalFileApi: 无法列出 /media', e);
    }

    return roots;
  }

  /// 获取 iOS 根目录
  Future<List<LocalRootDirectory>> _getIOSRoots() async {
    final roots = <LocalRootDirectory>[];

    try {
      // 应用文档目录
      final docDir = await getApplicationDocumentsDirectory();
      roots.add(LocalRootDirectory(
        name: appL10n.localFileApiDocumentsName,
        path: docDir.path,
        type: RootDirectoryType.documents,
      ));

      // 下载目录（iOS 11+）
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir != null) {
        roots.add(LocalRootDirectory(
          name: appL10n.localFileApiDownloadsName,
          path: downloadDir.path,
          type: RootDirectoryType.downloads,
        ));
      }
    } on Exception catch (e) {
      logger.e('LocalFileApi: 获取 iOS 目录失败', e);
    }

    return roots;
  }

  /// 列出目录内容
  Future<List<LocalFileInfo>> listDirectory(String path) async {
    final dir = Directory(path);
    final files = <LocalFileInfo>[];

    try {
      await for (final entity in dir.list()) {
        try {
          final stat = await entity.stat();
          final name = p.basename(entity.path);

          // 跳过隐藏文件（以 . 开头）
          // 但在某些情况下可能需要显示，所以这里只是标记
          final isHidden = name.startsWith('.');

          files.add(LocalFileInfo(
            name: name,
            path: entity.path,
            isDirectory: entity is Directory,
            size: stat.size,
            modifiedTime: stat.modified,
            accessedTime: stat.accessed,
            isHidden: isHidden,
            isReadOnly: stat.mode & 0x80 == 0, // 简化的只读检查
          ));
        } on Exception catch (e) {
          // 跳过无法访问的文件
          logger.w('LocalFileApi: 无法获取文件信息 ${entity.path}', e);
        }
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'LocalFileApi.listDirectory');
      rethrow;
    }

    // 排序：文件夹在前，然后按名称排序
    files.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return files;
  }

  /// 获取文件信息
  Future<LocalFileInfo> getFileInfo(String path) async {
    final entity = FileSystemEntity.typeSync(path) == FileSystemEntityType.directory
        ? Directory(path)
        : File(path);

    final stat = await entity.stat();
    final name = p.basename(path);

    return LocalFileInfo(
      name: name,
      path: path,
      isDirectory: entity is Directory,
      size: stat.size,
      modifiedTime: stat.modified,
      accessedTime: stat.accessed,
      isHidden: name.startsWith('.'),
    );
  }

  /// 创建目录
  Future<void> createDirectory(String path) async {
    final dir = Directory(path);
    await dir.create(recursive: true);
  }

  /// 删除文件或目录
  Future<void> delete(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(path).delete();
    }
  }

  /// 重命名
  Future<void> rename(String oldPath, String newPath) async {
    final type = await FileSystemEntity.type(oldPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(oldPath).rename(newPath);
    } else if (type == FileSystemEntityType.file) {
      await File(oldPath).rename(newPath);
    }
  }

  /// 复制文件
  Future<void> copyFile(String sourcePath, String destPath) async {
    final sourceType = await FileSystemEntity.type(sourcePath);

    if (sourceType == FileSystemEntityType.file) {
      await File(sourcePath).copy(destPath);
    } else if (sourceType == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(sourcePath), Directory(destPath));
    }
  }

  /// 递归复制目录
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);

    await for (final entity in source.list()) {
      final newPath = p.join(destination.path, p.basename(entity.path));

      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  /// 移动文件
  Future<void> moveFile(String sourcePath, String destPath) async {
    final type = await FileSystemEntity.type(sourcePath);

    if (type == FileSystemEntityType.file) {
      await File(sourcePath).rename(destPath);
    } else if (type == FileSystemEntityType.directory) {
      await Directory(sourcePath).rename(destPath);
    }
  }

  /// 搜索文件
  Future<List<LocalFileInfo>> searchFiles({
    required String basePath,
    required String pattern,
    bool recursive = true,
    int maxResults = 100,
  }) async {
    final results = <LocalFileInfo>[];
    final patternLower = pattern.toLowerCase();
    final dir = Directory(basePath);

    try {
      await for (final entity in dir.list(recursive: recursive)) {
        final name = p.basename(entity.path).toLowerCase();
        if (name.contains(patternLower)) {
          try {
            final stat = await entity.stat();
            results.add(LocalFileInfo(
              name: p.basename(entity.path),
              path: entity.path,
              isDirectory: entity is Directory,
              size: stat.size,
              modifiedTime: stat.modified,
              accessedTime: stat.accessed,
              isHidden: name.startsWith('.'),
            ));

            if (results.length >= maxResults) break;
          } on Exception catch (_) {
            // 跳过无法访问的文件
          }
        }
      }
    } on Exception catch (e) {
      logger.e('LocalFileApi: 搜索失败', e);
    }

    return results;
  }

  /// 获取文件的 URI
  String getFileUri(String path) => Uri.file(path).toString();
}

/// 根目录类型
enum RootDirectoryType {
  drive, // Windows 驱动器
  home, // 用户主目录
  system, // 系统根目录
  volume, // 外接卷宗
  storage, // 存储目录
  sdcard, // SD 卡
  documents, // 文档目录
  downloads, // 下载目录
}

/// 本地根目录
class LocalRootDirectory {
  const LocalRootDirectory({
    required this.name,
    required this.path,
    required this.type,
  });

  final String name;
  final String path;
  final RootDirectoryType type;
}

/// 本地文件信息
class LocalFileInfo {
  const LocalFileInfo({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modifiedTime,
    this.accessedTime,
    this.isHidden = false,
    this.isReadOnly = false,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modifiedTime;
  final DateTime? accessedTime;
  final bool isHidden;
  final bool isReadOnly;
}
