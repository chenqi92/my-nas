import 'dart:async';

/// 简易 token bucket：按 [refillPerSecond] 速率补充令牌，最多 [capacity] 个。
/// 用于给翻译 provider 限速，避免 Google 免费接口被封。
class TokenBucket {
  TokenBucket({required this.capacity, required this.refillPerSecond})
      : _tokens = capacity.toDouble(),
        _lastRefillMicros = DateTime.now().microsecondsSinceEpoch;

  final int capacity;
  final double refillPerSecond;

  double _tokens;
  int _lastRefillMicros;
  final _waiters = <Completer<void>>[];

  Future<void> acquire() async {
    _refill();
    if (_tokens >= 1) {
      _tokens -= 1;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    _scheduleNext();
    return completer.future;
  }

  void _refill() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final elapsedSec = (now - _lastRefillMicros) / 1e6;
    _lastRefillMicros = now;
    _tokens = (_tokens + elapsedSec * refillPerSecond).clamp(0, capacity.toDouble());
  }

  void _scheduleNext() {
    if (_waiters.isEmpty) return;
    final needed = 1 - _tokens;
    final delayMs = needed <= 0 ? 0 : (needed / refillPerSecond * 1000).ceil();
    Timer(Duration(milliseconds: delayMs.clamp(1, 5000)), () {
      _refill();
      while (_waiters.isNotEmpty && _tokens >= 1) {
        _tokens -= 1;
        _waiters.removeAt(0).complete();
      }
      if (_waiters.isNotEmpty) _scheduleNext();
    });
  }
}
