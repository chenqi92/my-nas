import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/shared/services/download_service.dart';

/// localhost HttpServer fixture：真实 DownloadService cancel 任务生命周期。
/// ≠真实 NAS；不改产品代码（Dio 为服务内置，客户端用本地慢流代替）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late Directory tmpDir;
  late Uri baseUri;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('qa-r4-dl-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      // 慢流：每块间隔，便于 cancel 命中 downloading
      request.response.headers.contentType = ContentType.binary;
      request.response.contentLength = 256 * 1024;
      final chunk = Uint8List(4096);
      for (var i = 0; i < 64; i++) {
        if (request.response.connectionInfo == null) break;
        try {
          request.response.add(chunk);
          await request.response.flush();
        } on Object {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      try {
        await request.response.close();
      } on Object {
        // cancelled by client
      }
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('cancelDownload 将 downloading 置为 cancelled 并清理 partial', () async {
    final svc = DownloadService();
    final savePath = '${tmpDir.path}/fixture.bin';
    final task = await svc.addTask(
      url: baseUri.replace(path: '/slow.bin').toString(),
      fileName: 'fixture.bin',
      customPath: savePath,
    );

    // 不等待完成；后台下载
    unawaited(svc.startDownload(task.id));

    // 等到进入 downloading
    DownloadTask? live;
    for (var i = 0; i < 50; i++) {
      live = svc.tasks.firstWhere((t) => t.id == task.id);
      if (live.status == DownloadStatus.downloading ||
          live.downloadedBytes > 0) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(live, isNotNull);
    expect(
      live!.status == DownloadStatus.downloading || live.downloadedBytes > 0,
      isTrue,
      reason: '应进入下载中，实际 status=${live.status}',
    );

    final partial = File(task.partialPath);
    svc.cancelDownload(task.id);

    final after = svc.tasks.firstWhere((t) => t.id == task.id);
    expect(after.status, DownloadStatus.cancelled);

    // 等待异步删 partial
    for (var i = 0; i < 40; i++) {
      if (!await partial.exists()) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(await partial.exists(), isFalse,
        reason: 'cancel 后应删除 partial 临时文件');
    expect(await File(savePath).exists(), isFalse,
        reason: 'cancel 不应留下成品文件');
  });
}
