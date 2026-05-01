// ignore_for_file: unused_field

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Chromaprint 原生库 FFI 绑定
///
/// 基于 chromaprint.h 定义
/// https://github.com/acoustid/chromaprint/blob/master/src/chromaprint.h
class ChromaprintBindings {
  ChromaprintBindings(DynamicLibrary library)
      : _chromaprint_get_version = library
            .lookup<NativeFunction<Pointer<Char> Function()>>('chromaprint_get_version')
            .asFunction(),
        _chromaprint_new = library
            .lookup<NativeFunction<Pointer<Void> Function(Int32)>>('chromaprint_new')
            .asFunction(),
        _chromaprint_free = library
            .lookup<NativeFunction<Void Function(Pointer<Void>)>>('chromaprint_free')
            .asFunction(),
        _chromaprint_get_algorithm = library
            .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('chromaprint_get_algorithm')
            .asFunction(),
        _chromaprint_set_option = library
            .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Char>, Int32)>>('chromaprint_set_option')
            .asFunction(),
        _chromaprint_start = library
            .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32, Int32)>>('chromaprint_start')
            .asFunction(),
        _chromaprint_feed = library
            .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Int16>, Int32)>>('chromaprint_feed')
            .asFunction(),
        _chromaprint_finish = library
            .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('chromaprint_finish')
            .asFunction(),
        _chromaprint_get_fingerprint = library
            .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>>('chromaprint_get_fingerprint')
            .asFunction(),
        _chromaprint_get_raw_fingerprint = library
            .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Uint32>>, Pointer<Int32>)>>('chromaprint_get_raw_fingerprint')
            .asFunction(),
        _chromaprint_get_fingerprint_hash = library
            .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Uint32>)>>('chromaprint_get_fingerprint_hash')
            .asFunction(),
        _chromaprint_clear_fingerprint = library
            .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('chromaprint_clear_fingerprint')
            .asFunction(),
        _chromaprint_encode_fingerprint = library
            .lookup<NativeFunction<Int32 Function(Pointer<Uint32>, Int32, Int32, Pointer<Pointer<Char>>, Pointer<Int32>, Int32)>>('chromaprint_encode_fingerprint')
            .asFunction(),
        _chromaprint_decode_fingerprint = library
            .lookup<NativeFunction<Int32 Function(Pointer<Char>, Int32, Pointer<Pointer<Uint32>>, Pointer<Int32>, Pointer<Int32>, Int32)>>('chromaprint_decode_fingerprint')
            .asFunction(),
        _chromaprint_dealloc = library
            .lookup<NativeFunction<Void Function(Pointer<Void>)>>('chromaprint_dealloc')
            .asFunction();

  // Native functions
  final Pointer<Char> Function() _chromaprint_get_version;
  final Pointer<Void> Function(int algorithm) _chromaprint_new;
  final void Function(Pointer<Void> ctx) _chromaprint_free;
  final int Function(Pointer<Void> ctx) _chromaprint_get_algorithm;
  final int Function(Pointer<Void> ctx, Pointer<Char> name, int value) _chromaprint_set_option;
  final int Function(Pointer<Void> ctx, int sampleRate, int numChannels) _chromaprint_start;
  final int Function(Pointer<Void> ctx, Pointer<Int16> data, int size) _chromaprint_feed;
  final int Function(Pointer<Void> ctx) _chromaprint_finish;
  final int Function(Pointer<Void> ctx, Pointer<Pointer<Char>> fingerprint) _chromaprint_get_fingerprint;
  final int Function(Pointer<Void> ctx, Pointer<Pointer<Uint32>> fingerprint, Pointer<Int32> size) _chromaprint_get_raw_fingerprint;
  final int Function(Pointer<Void> ctx, Pointer<Uint32> hash) _chromaprint_get_fingerprint_hash;
  final int Function(Pointer<Void> ctx) _chromaprint_clear_fingerprint;
  final int Function(Pointer<Uint32> fp, int size, int algorithm, Pointer<Pointer<Char>> encodedFp, Pointer<Int32> encodedSize, int base64) _chromaprint_encode_fingerprint;
  final int Function(Pointer<Char> encodedFp, int encodedSize, Pointer<Pointer<Uint32>> fp, Pointer<Int32> size, Pointer<Int32> algorithm, int base64) _chromaprint_decode_fingerprint;
  final void Function(Pointer<Void> ptr) _chromaprint_dealloc;

  /// 获取 Chromaprint 版本字符串
  String getVersion() => _chromaprint_get_version().cast<Utf8>().toDartString();

  /// 创建新的 Chromaprint 上下文
  Pointer<Void> createContext(int algorithm) => _chromaprint_new(algorithm);

  /// 释放 Chromaprint 上下文
  void freeContext(Pointer<Void> ctx) => _chromaprint_free(ctx);

  /// 获取上下文使用的算法
  int getAlgorithm(Pointer<Void> ctx) => _chromaprint_get_algorithm(ctx);

  /// 设置上下文选项
  bool setOption(Pointer<Void> ctx, String name, int value) {
    final namePtr = name.toNativeUtf8().cast<Char>();
    try {
      return _chromaprint_set_option(ctx, namePtr, value) == 1;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// 开始新的音频处理
  bool start(Pointer<Void> ctx, int sampleRate, int numChannels) =>
      _chromaprint_start(ctx, sampleRate, numChannels) == 1;

  /// 输入音频数据
  bool feed(Pointer<Void> ctx, Pointer<Int16> data, int size) =>
      _chromaprint_feed(ctx, data, size) == 1;

  /// 完成音频处理并计算指纹
  bool finish(Pointer<Void> ctx) => _chromaprint_finish(ctx) == 1;

  /// 获取计算的指纹（Base64 编码）
  String? getFingerprint(Pointer<Void> ctx) {
    final fingerprintPtr = calloc<Pointer<Char>>();
    try {
      if (_chromaprint_get_fingerprint(ctx, fingerprintPtr) != 1) {
        return null;
      }
      final fingerprint = fingerprintPtr.value.cast<Utf8>().toDartString();
      _chromaprint_dealloc(fingerprintPtr.value.cast<Void>());
      return fingerprint;
    } finally {
      calloc.free(fingerprintPtr);
    }
  }

  /// 获取原始指纹数据
  (List<int>?, int) getRawFingerprint(Pointer<Void> ctx) {
    final fingerprintPtr = calloc<Pointer<Uint32>>();
    final sizePtr = calloc<Int32>();
    try {
      if (_chromaprint_get_raw_fingerprint(ctx, fingerprintPtr, sizePtr) != 1) {
        return (null, 0);
      }
      final size = sizePtr.value;
      final fingerprint = List<int>.generate(size, (i) => fingerprintPtr.value[i]);
      _chromaprint_dealloc(fingerprintPtr.value.cast<Void>());
      return (fingerprint, size);
    } finally {
      calloc..free(fingerprintPtr)
      ..free(sizePtr);
    }
  }

  /// 获取指纹的哈希值
  int? getFingerprintHash(Pointer<Void> ctx) {
    final hashPtr = calloc<Uint32>();
    try {
      if (_chromaprint_get_fingerprint_hash(ctx, hashPtr) != 1) {
        return null;
      }
      return hashPtr.value;
    } finally {
      calloc.free(hashPtr);
    }
  }

  /// 清除已计算的指纹
  bool clearFingerprint(Pointer<Void> ctx) => _chromaprint_clear_fingerprint(ctx) == 1;

  /// 释放由 Chromaprint 分配的内存
  void dealloc(Pointer<Void> ptr) => _chromaprint_dealloc(ptr);
}

/// Chromaprint 算法枚举
abstract class ChromaprintAlgorithm {
  static const int test1 = 0;
  static const int test2 = 1;
  static const int test3 = 2;
  static const int test4 = 3; // 去除开头静音
  static const int test5 = 4;

  /// 默认算法 (test2)
  static const int defaultAlgorithm = test2;
}
