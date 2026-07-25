import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 文件浏览器默认点击行为。
enum FileOpenTarget { directory, video, audio, options }

/// 将可直接消费的媒体文件送到对应播放器，其余文件保留操作菜单。
FileOpenTarget preferredFileOpenTarget(FileItem file) {
  if (file.isDirectory) return FileOpenTarget.directory;

  return switch (file.type) {
    FileType.video => FileOpenTarget.video,
    FileType.audio => FileOpenTarget.audio,
    _ => FileOpenTarget.options,
  };
}
