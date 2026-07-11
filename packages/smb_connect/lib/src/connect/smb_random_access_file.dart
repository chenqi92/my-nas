import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:smb_connect/smb_connect.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';
import 'package:smb_connect/src/smb_constants.dart';

abstract class SmbRandomAccessFileController {
  final SmbFile file;
  final SmbTree tree;
  final FileMode mode;

  SmbRandomAccessFileController(this.file, this.tree, this.mode);

  int modeToAccess() {
    switch (mode) {
      case FileMode.read:
        return SmbConstants.O_RDONLY;
      case FileMode.append:
      case FileMode.write:
        return SmbConstants.O_RDONLY | SmbConstants.FILE_WRITE_DATA;
      case FileMode.writeOnly:
      case FileMode.writeOnlyAppend:
        return SmbConstants.FILE_WRITE_DATA;
    }
    return 0;
  }

  Future<int?> open();
  Future close();

  Future<int> read(Uint8List buff, int offset, int length);
  Future<int> write(List<int> buff, int position, int offset, int length);
}

class SmbRandomAccessFile implements RandomAccessFile {
  final SmbRandomAccessFileController controller;
  final SmbFile file;
  bool _inited = false;
  int _fileSize;

  int _position;

  SmbRandomAccessFile(this.file, this.controller, [int position = 0])
      : _position = RangeError.checkNotNegative(position, 'position'),
        _fileSize = file.size;

  Future _init() async {
    if (_inited) {
      return;
    }
    var size = await controller.open();
    _inited = size != null;
    if (size != null) {
      _fileSize = size;
    }
  }

  @override
  Future<void> close() => controller.close();

  @override
  void closeSync() {
    throw UnimplementedError("Sync methods not supported");
  }

  @override
  Future<RandomAccessFile> flush() async {
    return this;
  }

  @override
  void flushSync() {}

  @override
  Future<int> length() async => _fileSize;

  @override
  int lengthSync() => _fileSize;

  @override
  String get path => file.path;

  @override
  Future<int> position() async {
    return _position;
  }

  @override
  int positionSync() => _position;

  int _bufferFilePosition = 0;
  int _bufferReadPosition = 0;
  int _bufferLength = 0;
  final Uint8List _buffer = Uint8List(0xFFFF);

  void _clearReadBuffer() {
    _bufferReadPosition = 0;
    _bufferLength = 0;
  }

  Future<int> _readToBuff(int offset) async {
    await _init();
    int remainSize = _fileSize - offset;
    int length = min(remainSize, _buffer.length);
    if (length <= 0) {
      return 0;
    }
    int res = await controller.read(_buffer, offset, length);
    if (res < 0) {
      throw FileSystemException('SMB read failed at offset $offset', file.path);
    }
    if (res > length) {
      throw FileSystemException(
          'SMB read returned $res bytes for a $length byte request', file.path);
    }
    _bufferFilePosition = offset;
    _bufferReadPosition = 0;
    _bufferLength = res;
    return res;
  }

  int readFromBuffer(List<int> dst, int start, int length) {
    int res = 0;
    while (res < length &&
        start < dst.length &&
        _bufferReadPosition < _bufferLength) {
      dst[start] = _buffer[_bufferReadPosition];
      _bufferReadPosition++;
      start++;
      res++;
    }
    return res;
  }

  bool _positionInBuffer(int offset) {
    return _bufferLength > 0 &&
        _bufferFilePosition <= offset &&
        offset < _bufferFilePosition + _bufferLength;
  }

  @override
  Future<Uint8List> read(int count) async {
    RangeError.checkNotNegative(count, 'count');
    Uint8List buff = Uint8List(count);
    final bytesRead = await readInto(buff);
    if (bytesRead == count) return buff;
    return Uint8List.sublistView(buff, 0, bytesRead);
  }

  @override
  Uint8List readSync(int count) {
    Uint8List buff = Uint8List(count);
    readIntoSync(buff);
    return buff;
  }

  final Uint8List _byteBuff = Uint8List(1);

  @override
  Future<int> readByte() async {
    await _init();
    final read = await readInto(_byteBuff);
    if (read == 0) return -1;
    return _byteBuff[0];
  }

  @override
  int readByteSync() {
    readIntoSync(_byteBuff);
    return _byteBuff[0];
  }

  @override
  Future<int> readInto(List<int> buff, [int start = 0, int? end]) async {
    end = RangeError.checkValidRange(start, end, buff.length);
    int length = end - start;
    int res = 0;

    while (length > 0) {
      if (!_positionInBuffer(_position)) {
        final read = await _readToBuff(_position);
        if (read == 0) break;
      }
      _bufferReadPosition = _position - _bufferFilePosition;
      var n = readFromBuffer(buff, start, length);
      if (n == 0) break;
      length -= n;
      start += n;
      res += n;
      _position += n;
    }
    return res;
  }

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) {
    throw UnimplementedError("Sync methods not supported");
  }

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    RangeError.checkNotNegative(position, 'position');
    _position = position;
    return this;
  }

  @override
  void setPositionSync(int position) {
    RangeError.checkNotNegative(position, 'position');
    _position = position;
  }

  @override
  Future<RandomAccessFile> truncate(int length) {
    throw UnimplementedError("Truncate methods not supported");
  }

  @override
  void truncateSync(int length) {
    throw UnimplementedError("Truncate methods not supported");
  }

  @override
  Future<RandomAccessFile> lock(
      [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) {
    throw UnimplementedError("Lock/Unlock methods not supported");
  }

  @override
  void lockSync(
      [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) {
    throw UnimplementedError("Lock/Unlock methods not supported");
  }

  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) {
    throw UnimplementedError("Lock/Unlock methods not supported");
  }

  @override
  void unlockSync([int start = 0, int end = -1]) {
    throw UnimplementedError("Lock/Unlock methods not supported");
  }

  @override
  Future<RandomAccessFile> writeByte(int value) async {
    _byteBuff[0] = value;
    await writeFrom(_byteBuff);
    return this;
  }

  @override
  int writeByteSync(int value) {
    _byteBuff[0] = value;
    writeFromSync(_byteBuff);
    return 1;
  }

  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer,
      [int start = 0, int? end]) async {
    await _init(); //await initWrite();
    end ??= buffer.length;
    int length = end - start;
    await controller.write(buffer, _position, start, length);
    _fileSize += length;
    _clearReadBuffer();
    return this;
  }

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    throw UnimplementedError("Sync methods not supported");
  }

  @override
  Future<RandomAccessFile> writeString(String string,
      {Encoding encoding = utf8}) async {
    await writeFrom(encoding.encode(string));
    return this;
  }

  @override
  void writeStringSync(String string, {Encoding encoding = utf8}) {
    writeFromSync(encoding.encode(string));
  }
}
