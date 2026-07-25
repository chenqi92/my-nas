import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/file_browser/domain/file_open_target.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

void main() {
  FileItem file(String name, {bool isDirectory = false, String? mimeType}) =>
      FileItem(
        name: name,
        path: '/media/$name',
        isDirectory: isDirectory,
        size: 1,
        extension: name.contains('.') ? name.split('.').last : null,
        mimeType: mimeType,
      );

  test('directories keep directory navigation behavior', () {
    expect(
      preferredFileOpenTarget(file('Movies', isDirectory: true)),
      FileOpenTarget.directory,
    );
  });

  test('common and mime-detected video files open the video player', () {
    expect(preferredFileOpenTarget(file('movie.mkv')), FileOpenTarget.video);
    expect(preferredFileOpenTarget(file('clip.mp4')), FileOpenTarget.video);
    expect(
      preferredFileOpenTarget(file('stream', mimeType: 'video/webm')),
      FileOpenTarget.video,
    );
  });

  test('common and lossless audio files open the music player', () {
    expect(preferredFileOpenTarget(file('song.mp3')), FileOpenTarget.audio);
    expect(preferredFileOpenTarget(file('album.flac')), FileOpenTarget.audio);
    expect(preferredFileOpenTarget(file('audio.m4a')), FileOpenTarget.audio);
    expect(
      preferredFileOpenTarget(file('stream', mimeType: 'audio/ogg')),
      FileOpenTarget.audio,
    );
  });

  test('non-media files retain the options sheet', () {
    expect(preferredFileOpenTarget(file('readme.txt')), FileOpenTarget.options);
    expect(
      preferredFileOpenTarget(file('archive.zip')),
      FileOpenTarget.options,
    );
  });
}
