import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_connection_pool.dart';
import 'package:my_nas/nas_adapters/smb/smb_pool_config.dart';
import 'package:path/path.dart' as p;
import 'package:smb_connect/smb_connect.dart';

/// SMB 文件系统实现
///
/// 使用 smb_connect 库实现文件操作
/// 使用连接池管理所有连接，支持并发操作和心跳保活
class SmbFileSystem implements NasFileSystem {
  SmbFileSystem({required SmbConnectionPool connectionPool})
    : _connectionPool = connectionPool;

  /// 连接池（统一管理所有连接）
  final SmbConnectionPool _connectionPool;

  @override
  bool get supportsWriteOperations => true;

  @override
  bool get supportsServerSideCopy => false;

  @override
  bool get supportsDirectFileUrl => false;

  /// 缓存的共享列表
  List<SmbFile>? _cachedShares;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    // logger.d('SmbFileSystem: listDirectory => $path'); // 减少日志输出

    // 根目录显示共享列表
    if (path == '/' || path.isEmpty) {
      return listShares();
    }

    // 使用连接池获取连接
    return _connectionPool.withConnection(
      (client) => _listDirectoryWithClient(client, path),
      type: SmbConnectionType.general,
    );
  }

  /// 使用指定连接列出目录
  Future<List<FileItem>> _listDirectoryWithClient(
    SmbConnect smbClient,
    String path,
  ) async {
    try {
      final folder = await smbClient.file(path);
      final files = await smbClient.listFiles(folder);
      return files.map(_toFileItem).toList();
    } catch (e, st) {
      AppError.handle(e, st, 'SmbFileSystem.listDirectory');
      rethrow;
    }
  }

  /// 并行列出多个目录
  ///
  /// 利用连接池同时列出多个目录，大幅提升扫描速度
  ///
  /// [paths] 要列出的目录路径列表
  /// [concurrency] 最大并发数（默认根据连接池配置自动调整）
  ///
  /// 返回 Map<路径, 文件列表>，失败的目录会被跳过并记录日志
  Future<Map<String, List<FileItem>>> listDirectoriesParallel(
    List<String> paths, {
    int? concurrency,
  }) async {
    if (paths.isEmpty) return {};

    final results = <String, List<FileItem>>{};

    // 使用连接池并行执行
    final maxConcurrency = concurrency ?? _connectionPool.maxConnections;
    final actualConcurrency = maxConcurrency < paths.length
        ? maxConcurrency
        : paths.length;

    // logger.d('SmbFileSystem: 并行列出 ${paths.length} 个目录，并发数: $actualConcurrency'); // 减少日志输出

    // 分批处理，每批使用连接池并行执行
    for (var i = 0; i < paths.length; i += actualConcurrency) {
      final batch = paths.skip(i).take(actualConcurrency).toList();

      final futures = batch.map((path) async {
        try {
          final files = await _connectionPool.withConnection(
            (client) => _listDirectoryWithClient(client, path),
            type: SmbConnectionType.general,
          );
          return MapEntry(path, files);
        } catch (e) {
          logger.w('SmbFileSystem: 并行列出目录失败: $path - $e');
          return MapEntry(path, <FileItem>[]);
        }
      });

      final batchResults = await Future.wait(futures);
      for (final entry in batchResults) {
        if (entry.value.isNotEmpty || !results.containsKey(entry.key)) {
          results[entry.key] = entry.value;
        }
      }
    }

    // logger.d('SmbFileSystem: 并行列出完成，成功 ${results.length}/${paths.length} 个目录'); // 减少日志输出
    return results;
  }

  /// 并行获取多个目录的修改时间（用于增量同步）
  ///
  /// [paths] 要获取信息的目录路径列表
  ///
  /// 返回 Map<路径, 修改时间>，失败的目录返回 null
  Future<Map<String, DateTime?>> getDirectoriesModifiedTime(
    List<String> paths,
  ) async {
    if (paths.isEmpty) return {};

    final results = <String, DateTime?>{};

    // 使用连接池并行执行
    final maxConcurrency = _connectionPool.maxConnections < paths.length
        ? _connectionPool.maxConnections
        : paths.length;

    // 分批处理
    for (var i = 0; i < paths.length; i += maxConcurrency) {
      final batch = paths.skip(i).take(maxConcurrency).toList();
      final futures = batch.map((path) async {
        try {
          return await _connectionPool.withConnection((conn) async {
            final smbFile = await conn.file(path);
            // SmbFile.lastModified 是毫秒时间戳
            final mtime = smbFile.lastModified > 0
                ? DateTime.fromMillisecondsSinceEpoch(smbFile.lastModified)
                : null;
            return MapEntry(path, mtime);
          }, type: SmbConnectionType.general);
        } catch (e) {
          return MapEntry<String, DateTime?>(path, null);
        }
      });

      final batchResults = await Future.wait(futures);
      for (final entry in batchResults) {
        results[entry.key] = entry.value;
      }
    }

    return results;
  }

  /// 递归发现所有子目录（用于扫描阶段1）
  ///
  /// 从根目录开始，并行遍历发现所有子目录
  /// 返回所有目录路径（包括根目录）
  ///
  /// [rootPath] 根目录路径
  /// [onProgress] 进度回调，参数为当前发现的目录数
  Future<List<String>> discoverAllDirectories(
    String rootPath, {
    void Function(int count)? onProgress,
  }) async {
    final allDirectories = <String>[rootPath];
    final pendingDirectories = <String>[rootPath];

    while (pendingDirectories.isNotEmpty) {
      // 取出一批待处理的目录
      final batch = pendingDirectories.take(10).toList();
      pendingDirectories.removeRange(0, batch.length);

      // 并行列出这批目录
      final results = await listDirectoriesParallel(batch);

      // 收集发现的子目录
      for (final entry in results.entries) {
        final subDirs = entry.value
            .where((f) => f.isDirectory && !f.isHidden)
            .map((f) => f.path)
            .toList();
        allDirectories.addAll(subDirs);
        pendingDirectories.addAll(subDirs);
      }

      onProgress?.call(allDirectories.length);
    }

    logger.i('SmbFileSystem: 发现 ${allDirectories.length} 个目录');
    return allDirectories;
  }

  /// 列出共享文件夹
  Future<List<FileItem>> listShares() async {
    // logger.d('SmbFileSystem: 获取共享列表'); // 减少日志输出

    // 使用缓存
    if (_cachedShares != null && _cachedShares!.isNotEmpty) {
      return _cachedShares!.map(_toFileItem).toList();
    }

    final shares = await _connectionPool.withConnection(
      (client) => client.listShares(),
      type: SmbConnectionType.general,
    );
    _cachedShares = shares;

    logger.i('SmbFileSystem: 获取到 ${shares.length} 个共享');

    return shares.map(_toFileItem).toList();
  }

  /// 清除共享缓存
  void clearSharesCache() {
    _cachedShares = null;
  }

  FileItem _toFileItem(SmbFile file) {
    final name = file.name;
    final isDir = file.isDirectory(); // isDirectory 是方法

    return FileItem(
      name: name,
      path: file.path,
      isDirectory: isDir,
      size: file.size,
      // lastModified 和 createTime 是 int (Unix 时间戳毫秒)
      modifiedTime: file.lastModified > 0
          ? DateTime.fromMillisecondsSinceEpoch(file.lastModified)
          : null,
      createdTime: file.createTime > 0
          ? DateTime.fromMillisecondsSinceEpoch(file.createTime)
          : null,
      extension: isDir ? null : _getExtension(name),
      isHidden: name.startsWith('.') || file.isHidden(),
    );
  }

  String? _getExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return null;
    return fileName.substring(dotIndex + 1);
  }

  @override
  Future<FileItem> getFileInfo(String path) async =>
      _connectionPool.withConnection((client) async {
        final file = await client.file(path);
        // smb_connect 对不存在的路径返回 SmbFile.notExists，并不会抛异常。
        // 若继续转为 FileItem，会让调用方误判文件存在，直到真正 openRead
        // 时才收到该库抛出的 String 错误。
        if (!file.isExists) {
          throw FileSystemException('SMB file does not exist', path);
        }
        return _toFileItem(file);
      }, type: SmbConnectionType.general);

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) async {
    // 连接策略：
    // - 有 range 参数 = 视频播放（需要长时间占用）-> 使用专用连接（带心跳）
    // - 无 range 参数 = 普通文件下载 -> 使用连接池（支持并发）
    SmbConnect streamClient;
    DedicatedConnection? dedicatedConnection;
    void Function()? releasePoolConnection;

    final needsDedicatedConnection = range != null;

    if (needsDedicatedConnection) {
      // 视频播放：使用专用连接（带心跳保活），避免阻塞其他操作
      dedicatedConnection = await _connectionPool
          .createDedicatedConnectionWithHeartbeat(
            onDisconnect: () {
              logger.w('SmbFileSystem: 流传输连接断开');
            },
          );
      streamClient = dedicatedConnection.client;
      // 开始传输时停止心跳（有数据流动不需要心跳）
      dedicatedConnection.stopHeartbeat();
    } else {
      // 普通文件下载：使用连接池分配连接（支持并发读取多个文件）
      streamClient = await _connectionPool.acquire(
        type: SmbConnectionType.background,
      );
      releasePoolConnection = () => _connectionPool.release(streamClient);
    }

    /// 清理连接资源（确保只执行一次）
    var cleanupCalled = false;
    Future<void> cleanup() async {
      if (cleanupCalled) return; // 防止重复调用
      cleanupCalled = true;

      if (dedicatedConnection != null) {
        // 专用连接：使用 DedicatedConnection.close() 统一处理
        await dedicatedConnection.close();
      } else if (releasePoolConnection != null) {
        // 连接池连接：只释放不关闭
        releasePoolConnection();
      }
    }

    try {
      final file = await streamClient.file(path);
      if (!file.isExists) {
        throw FileSystemException('SMB file does not exist', path);
      }
      final fileSize = file.size;

      if (range != null) {
        // 使用 RandomAccessFile 实现范围读取
        final raf = await streamClient.open(file);

        try {
          await raf.setPosition(range.start);
          final length = range.end != null
              ? range.end! - range.start
              : fileSize - range.start;

          // 分块读取 - 使用平台特定的块大小以平衡性能和内存
          final controller = StreamController<List<int>>();
          final chunkSize = SmbPoolConfig.streamChunkSize;
          var remaining = length;

          // 使用暂停/恢复机制控制内存使用
          var isPaused = false;

          controller.onPause = () {
            isPaused = true;
            // 流暂停时启动心跳保活（如视频暂停）
            dedicatedConnection?.startHeartbeat();
          };
          // ignore: cascade_invocations
          controller.onResume = () {
            isPaused = false;
            // 流恢复时停止心跳（有数据传输不需要心跳）
            dedicatedConnection?.stopHeartbeat();
          };
          // ignore: cascade_invocations
          controller.onCancel = () async {
            // 客户端取消，清理资源
            // 使用 try-catch 防止连接已断开时的错误
            try {
              await raf.close();
            } catch (_) {
              // 忽略关闭时的错误，连接可能已经断开
            }
            await cleanup();
          };

          AppError.fireAndForget(() async {
            var chunksRead = 0;
            try {
              while (remaining > 0 && !controller.isClosed) {
                // 如果流被暂停，等待恢复（带超时以防止死锁）
                var waitCount = 0;
                while (isPaused && !controller.isClosed && waitCount < 1000) {
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                  waitCount++;
                }

                if (controller.isClosed) break;

                final toRead = remaining > chunkSize ? chunkSize : remaining;
                final chunk = await raf.read(toRead);

                if (chunk.isEmpty) break;

                controller.add(chunk);
                remaining -= chunk.length;
                chunksRead++;

                // 每读取 2 块后让出执行权，减少内存压力
                if (chunksRead.isEven) {
                  await Future<void>.delayed(Duration.zero);
                }
              }
              await controller.close();
            } catch (e, st) {
              // 上报流读取错误
              AppError.handle(e, st, 'SmbFileSystem.streamRead', {
                'path': path,
                'rangeStart': range.start,
                'rangeEnd': range.end,
                'remaining': remaining,
                'chunksRead': chunksRead,
              });
              if (!controller.isClosed) {
                controller.addError(e);
              }
              await controller.close();
            } finally {
              try {
                await raf.close();
              } catch (_) {
                // 忽略关闭时的错误，连接可能已经断开
              }
              await cleanup();
            }
          }(), action: 'SmbFileSystem.getFileStream');

          return controller.stream;
        } catch (_) {
          try {
            await raf.close();
          } catch (_) {
            // 忽略关闭时的错误
          }
          rethrow;
        }
      } else {
        // 完整文件流 - 包装以便在完成时关闭连接
        final rawStream = await streamClient.openRead(file);

        if (releasePoolConnection != null) {
          // 包装流，在完成时关闭专用连接
          final controller = StreamController<List<int>>();
          late final StreamSubscription<List<int>> rawSubscription;
          controller
            ..onPause = () {
              rawSubscription.pause();
            }
            ..onResume = () {
              rawSubscription.resume();
            }
            ..onCancel = () async {
              await rawSubscription.cancel();
              await cleanup();
            };
          rawSubscription = rawStream.listen(
            controller.add,
            onError: (Object error, StackTrace stackTrace) async {
              controller.addError(error, stackTrace);
              await controller.close();
              await cleanup();
            },
            onDone: () async {
              await controller.close();
              await cleanup();
            },
            cancelOnError: true,
          );
          return controller.stream;
        }

        return rawStream;
      }
    } catch (_) {
      // smb_connect 的部分底层错误是 String；无论错误对象类型为何都必须
      // 释放专用/池化连接，否则重复探测缺失文件会耗尽连接池。
      await cleanup();
      rethrow;
    }
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) {
    // SMB 没有真正的 HTTP URL，通过 smb:// 占位符还原路径再走 getFileStream。
    // [getFileUrl] 返回 'smb://smb-local<path>'，这里反向解析。
    if (url.startsWith('smb://')) {
      final withoutScheme = url.substring('smb://'.length);
      // 形如 'smb-local/foo/bar'
      final firstSlash = withoutScheme.indexOf('/');
      final path = firstSlash >= 0 ? withoutScheme.substring(firstSlash) : '/';
      return getFileStream(path);
    }
    throw UnsupportedError(appL10n.smbFileSystemUnsupportedUrlScheme(url));
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async =>
      // SMB 不支持直接 URL 访问，需要通过流来访问
      // 返回一个特殊的 smb:// URL 格式，应用层需要处理
      'smb://smb-local$path';

  @override
  Future<void> createDirectory(String path) async {
    await _connectionPool.withConnection(
      (client) => client.createFolder(path),
      type: SmbConnectionType.general,
    );
  }

  @override
  Future<void> delete(String path) async {
    await _connectionPool.withConnection((client) async {
      final file = await client.file(path);
      await client.delete(file);
    }, type: SmbConnectionType.general);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    await _connectionPool.withConnection((client) async {
      final file = await client.file(oldPath);
      await client.rename(file, newPath);
    }, type: SmbConnectionType.general);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    // SMB 原生不支持服务端复制（除非走 SMB3 FSCTL_SRV_COPYCHUNK，smb_connect 不暴露），
    // 这里以"下载-上传"客户端 fallback 实现：
    // 1. 从源路径流式读
    // 2. 写入到目标路径（先确保目标父目录存在）
    final stream = await getFileStream(sourcePath);

    await _connectionPool.withConnection((client) async {
      // 删除已存在的目标文件，避免覆盖冲突
      try {
        final existing = await client.file(destPath);
        await client.delete(existing);
      } catch (e, st) {
        AppError.ignore(e, st, 'SMB copy: 目标不存在或无法删除，继续创建');
      }

      await client.createFile(destPath);
      final remoteFile = await client.file(destPath);
      final writer = await client.openWrite(remoteFile);

      try {
        await for (final chunk in stream) {
          writer.add(chunk);
        }
        await writer.flush();
        await writer.close();
      } catch (_) {
        await writer.close();
        rethrow;
      }
    }, type: SmbConnectionType.background);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    await rename(sourcePath, destPath);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException(
        appL10n.smbFileSystemLocalFileNotExists,
        localPath,
      );
    }

    final name = fileName ?? p.basename(localPath);
    final targetPath = remotePath.endsWith('/')
        ? '$remotePath$name'
        : '$remotePath/$name';

    await _connectionPool.withConnection((client) async {
      // 创建远程文件
      await client.createFile(targetPath);
      final remoteFile = await client.file(targetPath);

      // 获取写入流
      final writer = await client.openWrite(remoteFile);

      try {
        final total = await file.length();
        var sent = 0;

        await for (final chunk in file.openRead()) {
          writer.add(chunk);
          sent += chunk.length;
          onProgress?.call(sent, total);
        }

        await writer.flush();
        await writer.close();
      } on Exception {
        await writer.close();
        rethrow;
      }
    }, type: SmbConnectionType.background);
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    await _connectionPool.withConnection((client) async {
      // 先尝试删除已存在的文件（如果存在）
      // 使用通用 catch 捕获所有类型的异常（包括 String 异常）
      try {
        final existingFile = await client.file(remotePath);
        await client.delete(existingFile);
      } catch (_) {
        // 文件不存在或删除失败，忽略错误继续写入
      }

      // 创建远程文件
      await client.createFile(remotePath);
      final remoteFile = await client.file(remotePath);

      // 获取写入流
      final writer = await client.openWrite(remoteFile);

      try {
        writer.add(data);
        await writer.flush();
        await writer.close();
      } catch (e) {
        await writer.close();
        rethrow;
      }
    }, type: SmbConnectionType.general);
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    // SMB 不支持服务端搜索，使用客户端 BFS 递归遍历，限深度和数量避免遍历过深
    if (query.trim().isEmpty) return const [];
    return _clientSideSearch(query, root: path ?? '/');
  }

  /// 客户端 BFS 搜索，文件名包含 [query] 即视为命中
  Future<List<FileItem>> _clientSideSearch(
    String query, {
    required String root,
    int maxDepth = 4,
    int maxResults = 200,
  }) async {
    final lower = query.toLowerCase();
    final results = <FileItem>[];
    final queue = <({String path, int depth})>[(path: root, depth: 0)];

    while (queue.isNotEmpty && results.length < maxResults) {
      final entry = queue.removeAt(0);
      try {
        final children = await listDirectory(entry.path);
        for (final child in children) {
          if (child.name.toLowerCase().contains(lower)) {
            results.add(child);
            if (results.length >= maxResults) break;
          }
          if (child.isDirectory && entry.depth < maxDepth) {
            queue.add((path: child.path, depth: entry.depth + 1));
          }
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, 'SMB 搜索：跳过无法访问的目录 ${entry.path}');
      }
    }
    return results;
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async =>
      null;

  @override
  Future<Uint8List?> getThumbnailData(
    String path, {
    ThumbnailSize? size,
  }) async => null;
}
