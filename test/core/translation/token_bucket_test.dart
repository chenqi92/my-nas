import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/translation/token_bucket.dart';

void main() {
  group('TokenBucket', () {
    test('立即放行不超过 capacity 的请求', () async {
      final bucket = TokenBucket(capacity: 5, refillPerSecond: 1);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        await bucket.acquire();
      }
      sw.stop();
      // 5 个初始 token，应该几乎瞬间完成
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('超过 capacity 后按 refill 速率排队', () async {
      // capacity=2，refill 10/s（每个 token 约 100ms）
      final bucket = TokenBucket(capacity: 2, refillPerSecond: 10);
      await bucket.acquire();
      await bucket.acquire();
      final sw = Stopwatch()..start();
      // 第三个需要等约 100ms
      await bucket.acquire();
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(50));
      expect(sw.elapsedMilliseconds, lessThan(400));
    });

    test('多并发请求按顺序释放', () async {
      final bucket = TokenBucket(capacity: 1, refillPerSecond: 20);
      final order = <int>[];
      final futures = <Future<void>>[];
      for (var i = 0; i < 5; i++) {
        futures.add(bucket.acquire().then((_) => order.add(i)));
      }
      await Future.wait(futures);
      // FIFO 顺序
      expect(order, equals([0, 1, 2, 3, 4]));
    });
  });
}
