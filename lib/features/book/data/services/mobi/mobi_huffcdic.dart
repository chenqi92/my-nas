// MOBI HUFF/CDIC 解压缩
//
// 实现 MOBI 高压缩模式（compression type 17480 / 0x4448）的解压。
// 算法参考公开实现（calibre huffcdic.py / KindleUnpack mobi_huff.py）：
//   - HUFF 记录：提供 Huffman 码表（dict1 256 项）与 mincode/maxcode（dict2 64 longwords）
//   - CDIC 记录：提供字典短语（phrases），每项带 flag 标记是否已是终结字面量
//   - 文本记录：位级 Huffman 解码 + 字典短语展开（短语可递归再解码）
//
// 参考:
//   https://github.com/kovidgoyal/calibre/blob/master/src/calibre/ebooks/mobi/huffcdic.py
//   https://wiki.mobileread.com/wiki/MOBI

import 'dart:typed_data';

/// HUFF/CDIC 解码异常（内部使用，调用方应捕获后回退）
class HuffCdicException implements Exception {
  HuffCdicException(this.message);
  final String message;
  @override
  String toString() => 'HuffCdicException: $message';
}

/// 字典项：解码出的字节片段 + 是否已终结（无需再递归解码）
class _DictEntry {
  _DictEntry(this.slice, this.terminal);
  final Uint8List slice;
  final bool terminal;
  // 非终结短语递归解码后的缓存（首次展开后回填，避免重复解码）
  Uint8List? decoded;
}

/// dict1 项：码长、是否终结、最大码
class _Dict1Entry {
  const _Dict1Entry(this.codelen, this.term, this.maxcode);
  final int codelen;
  final bool term;
  final int maxcode;
}

/// MOBI HUFF/CDIC 解码器
///
/// 用法：
///   final reader = MobiHuffCdicReader();
///   reader.loadHuff(huffRecordData);
///   for (final cdic in cdicRecords) reader.loadCdic(cdic);
///   final out = reader.unpack(textRecordData);
class MobiHuffCdicReader {
  final List<_Dict1Entry> _dict1 = [];

  // mincode/maxcode 按码长索引（索引 0..32）
  final List<int> _minCode = [];
  final List<int> _maxCode = [];

  final List<_DictEntry> _dictionary = [];

  /// 32 位掩码
  static const int _mask32 = 0xFFFFFFFF;

  bool get isReady => _dict1.isNotEmpty && _dictionary.isNotEmpty;

  /// 读取大端序 32 位无符号整数
  static int _u32(Uint8List b, int off) {
    if (off + 4 > b.length) {
      throw HuffCdicException('u32 越界 off=$off len=${b.length}');
    }
    return (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];
  }

  /// 读取大端序 16 位无符号整数
  static int _u16(Uint8List b, int off) {
    if (off + 2 > b.length) {
      throw HuffCdicException('u16 越界 off=$off len=${b.length}');
    }
    return (b[off] << 8) | b[off + 1];
  }

  /// 解析 HUFF 记录头与两张码表
  void loadHuff(Uint8List huff) {
    if (huff.length < 24) {
      throw HuffCdicException('HUFF 记录过短: ${huff.length}');
    }
    // magic 'HUFF' + 0x00000018
    if (huff[0] != 0x48 ||
        huff[1] != 0x55 ||
        huff[2] != 0x46 ||
        huff[3] != 0x46) {
      throw HuffCdicException('无效的 HUFF magic');
    }
    if (_u32(huff, 4) != 0x18) {
      throw HuffCdicException('无效的 HUFF 头长度');
    }

    final off1 = _u32(huff, 8);
    final off2 = _u32(huff, 12);

    // dict1: off1 起 256 个大端 32 位
    if (off1 + 256 * 4 > huff.length) {
      throw HuffCdicException('HUFF dict1 越界');
    }
    _dict1.clear();
    for (var i = 0; i < 256; i++) {
      final v = _u32(huff, off1 + i * 4);
      final codelen = v & 0x1F;
      final term = (v & 0x80) != 0;
      var maxcode = v >> 8;
      if (codelen == 0) {
        throw HuffCdicException('HUFF dict1 codelen=0');
      }
      if (codelen <= 8 && !term) {
        throw HuffCdicException('HUFF dict1 非终结但 codelen<=8');
      }
      // maxcode 归一化为 32 位空间的上界
      maxcode = (((maxcode + 1) << (32 - codelen)) - 1) & _mask32;
      _dict1.add(_Dict1Entry(codelen, term, maxcode));
    }

    // dict2: off2 起 64 个大端 32 位（32 对 mincode/maxcode）
    if (off2 + 64 * 4 > huff.length) {
      throw HuffCdicException('HUFF dict2 越界');
    }
    final dict2 = List<int>.generate(64, (i) => _u32(huff, off2 + i * 4));

    // mincode[codelen] / maxcode[codelen]，codelen 从 1 开始，索引 0 占位
    _minCode
      ..clear()
      ..add(0);
    _maxCode
      ..clear()
      ..add(0);
    // 偶数项 -> mincode，奇数项 -> maxcode；codelen 从 1 递增
    for (var codelen = 1; codelen <= 32; codelen++) {
      final mincode = dict2[(codelen - 1) * 2];
      final maxcode = dict2[(codelen - 1) * 2 + 1];
      _minCode.add((mincode << (32 - codelen)) & _mask32);
      _maxCode.add((((maxcode + 1) << (32 - codelen)) - 1) & _mask32);
    }
  }

  /// 解析 CDIC 记录，追加字典短语
  void loadCdic(Uint8List cdic) {
    if (cdic.length < 16) {
      throw HuffCdicException('CDIC 记录过短: ${cdic.length}');
    }
    // magic 'CDIC' + 0x00000010
    if (cdic[0] != 0x43 ||
        cdic[1] != 0x44 ||
        cdic[2] != 0x49 ||
        cdic[3] != 0x43) {
      throw HuffCdicException('无效的 CDIC magic');
    }
    if (_u32(cdic, 4) != 0x10) {
      throw HuffCdicException('无效的 CDIC 头长度');
    }

    final phrases = _u32(cdic, 8);
    final bits = _u32(cdic, 12);

    // 本记录贡献的短语数：受 (1<<bits) 与剩余总数限制
    final remaining = phrases - _dictionary.length;
    if (remaining <= 0) return;
    final n = (1 << bits) < remaining ? (1 << bits) : remaining;

    // 偏移表：自 16 起 n 个大端 16 位
    if (16 + n * 2 > cdic.length) {
      throw HuffCdicException('CDIC 偏移表越界');
    }
    for (var i = 0; i < n; i++) {
      final off = _u16(cdic, 16 + i * 2);
      // blen 位于 16+off，短语数据位于 18+off
      final blen = _u16(cdic, 16 + off);
      final len = blen & 0x7FFF;
      final flag = (blen & 0x8000) != 0;
      final start = 18 + off;
      final end = start + len;
      if (end > cdic.length) {
        throw HuffCdicException('CDIC 短语越界 off=$off len=$len');
      }
      _dictionary.add(_DictEntry(
        Uint8List.sublistView(cdic, start, end),
        flag,
      ));
    }
  }

  /// 解压一个文本记录
  ///
  /// 失败时抛出 [HuffCdicException]，调用方应捕获并回退。
  Uint8List unpack(Uint8List input) {
    if (!isReady) {
      throw HuffCdicException('码表/字典未就绪');
    }
    return _unpack(input, 0);
  }

  Uint8List _unpack(Uint8List data, int depth) {
    if (depth > 32) {
      // 防御递归过深（异常字典导致的环）
      throw HuffCdicException('HUFF/CDIC 递归过深');
    }

    final out = BytesBuilder(copy: false);
    var bitsleft = data.length * 8;

    // 在尾部补 8 字节 0，便于读取 64 位窗口
    final buf = Uint8List(data.length + 8)..setRange(0, data.length, data);

    var pos = 0;
    // x 为当前 64 位窗口（用两个 32 位半部表示，规避 Dart 有符号 64 位移位问题）
    var hi = _read32(buf, pos); // 高 32 位
    var lo = _read32(buf, pos + 4); // 低 32 位
    var n = 32;

    while (true) {
      if (n <= 0) {
        pos += 4;
        hi = _read32(buf, pos);
        lo = _read32(buf, pos + 4);
        n += 32;
      }

      // code = (x >> n) & 0xFFFFFFFF，x 为 64 位 [hi:lo]
      // 取从位偏移 n 起的高 32 位
      final code = _extract32(hi, lo, n);

      final entry = _dict1[code >> 24];
      var codelen = entry.codelen;
      final term = entry.term;
      var maxcode = entry.maxcode;

      if (!term) {
        // 逐步增大码长，直到 code >= mincode[codelen]
        while (codelen < _minCode.length && code < _minCode[codelen]) {
          codelen++;
        }
        if (codelen >= _maxCode.length) {
          throw HuffCdicException('codelen 越界 $codelen');
        }
        maxcode = _maxCode[codelen];
      }

      n -= codelen;
      bitsleft -= codelen;
      if (bitsleft < 0) {
        break;
      }

      // r = (maxcode - code) >> (32 - codelen)
      final r = ((maxcode - code) & _mask32) >> (32 - codelen);
      if (r < 0 || r >= _dictionary.length) {
        throw HuffCdicException('字典索引越界 r=$r');
      }

      final dictEntry = _dictionary[r];
      Uint8List slice;
      if (dictEntry.terminal) {
        // 终结短语：字面量字节，直接使用
        slice = dictEntry.slice;
      } else {
        // 非终结短语：递归解码（结果缓存到 decoded，不修改 terminal/slice）
        slice = dictEntry.decoded ??= _unpack(dictEntry.slice, depth + 1);
      }
      out.add(slice);
    }

    return out.toBytes();
  }

  /// 读取大端 32 位，结果保证为非负 32 位整数
  static int _read32(Uint8List b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

  /// 从 64 位窗口 [hi:lo]（各 32 位非负）中提取从位偏移 [n] 起的高 32 位
  ///
  /// 等价于 ((hi<<32 | lo) >> n) & 0xFFFFFFFF，n ∈ [0,32]
  static int _extract32(int hi, int lo, int n) {
    if (n >= 32) {
      // 仅取 hi 的对应区间
      final shift = n - 32; // 0..(>0 时已无意义，循环保证 n<=32)
      return (hi >> shift) & _mask32;
    }
    if (n == 0) {
      return hi & _mask32;
    }
    // 高位来自 hi 的低 (32-n) 位，低位来自 lo 的高 n 位
    final high = (hi << (32 - n)) & _mask32;
    final low = lo >> n;
    return (high | low) & _mask32;
  }
}
