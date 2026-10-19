import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

bool isBitmapSubtitleCodec(String? codec) => const {
  'hdmv_pgs_subtitle',
  'pgs',
  'dvd_subtitle',
  'dvdsub',
  'dvb_subtitle',
  'dvbsub',
  'xsub',
}.contains(codec?.toLowerCase());

/// mpv cannot authenticate NAS subtitle URLs or open the app's virtual SMB URLs.
Future<String> loadSubtitleFile(
  SubtitleItem subtitle, {
  required String sourceId,
  required NasFileSystem fileSystem,
  Directory? directory,
}) async {
  final uri = Uri.tryParse(subtitle.url);
  if (uri?.scheme == 'file' && await File.fromUri(uri!).exists()) {
    return subtitle.url;
  }
  final stream = await fileSystem
      .getFileStream(subtitle.path)
      .timeout(const Duration(seconds: 15));
  final bytes = <int>[];
  await for (final chunk in stream.timeout(const Duration(seconds: 15))) {
    bytes.addAll(chunk);
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Subtitle file exceeds 20 MiB');
    }
  }
  final root = directory ?? await getTemporaryDirectory();
  final cache = Directory(p.join(root.path, 'video_subtitles'));
  await cache.create(recursive: true);
  final key = sha256.convert(utf8.encode('$sourceId:${subtitle.path}'));
  final extension = p.extension(subtitle.path).toLowerCase();
  final file = File(p.join(cache.path, '$key$extension'));
  await file.writeAsBytes(bytes, flush: true);
  return file.uri.toString();
}
