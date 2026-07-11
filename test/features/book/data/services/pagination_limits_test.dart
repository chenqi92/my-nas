import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/book/data/services/epub_image_extractor.dart';
import 'package:my_nas/features/book/data/services/native_epub_paginator.dart';
import 'package:my_nas/features/book/data/services/native_online_paginator.dart';

void main() {
  test(
    'online paginator exposes an Exception for oversized chapters',
    () async {
      final content = _stringOfLength(2 * 1024 * 1024 + 1);

      await expectLater(
        NativeOnlinePaginator.instance.paginateChapter(
          content: content,
          chapterIndex: 0,
          viewportSize: const Size(800, 600),
          baseStyle: const TextStyle(fontSize: 18),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('章节内容过大'),
          ),
        ),
      );
    },
  );

  test('EPUB paginator exposes an Exception for oversized content', () async {
    final content = _stringOfLength(5 * 1024 * 1024 + 1);

    await expectLater(
      NativeEpubPaginator.instance.paginate(
        htmlContents: [content],
        viewportSize: const Size(800, 600),
        baseStyle: const TextStyle(fontSize: 18),
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('EPUB 内容过大'),
        ),
      ),
    );
  });

  test('EPUB image count propagates an oversized-file Exception', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'epub_image_limit_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final epubFile = File('${tempDirectory.path}/oversized.epub');
    final randomAccessFile = await epubFile.open(mode: FileMode.write);
    await randomAccessFile.truncate(512 * 1024 * 1024 + 1);
    await randomAccessFile.close();

    await expectLater(
      EpubImageExtractor.instance.getImageCount(epubFile),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('EPUB 文件过大'),
        ),
      ),
    );
  });
}

String _stringOfLength(int length) {
  const chunk =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final buffer = StringBuffer();
  while (buffer.length + chunk.length <= length) {
    buffer.write(chunk);
  }
  if (buffer.length < length) {
    buffer.write(chunk.substring(0, length - buffer.length));
  }
  return buffer.toString();
}
