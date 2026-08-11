import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/utils/tv_capabilities.dart';

/// [TvCapabilities.resolveTvMode] 是 override 与硬件探测的唯一合并处（A1）。
///
/// 这个纯函数同时被静态 getter（`isTvMode`）和 Riverpod 侧（`isTvModeProvider`）
/// 引用；两边若各写一份判定，会出现「设置里切了但 Shell 没换」的不一致。
void main() {
  group('resolveTvMode', () {
    test('auto 跟随硬件探测结果', () {
      expect(
        TvCapabilities.resolveTvMode(TvModeOverride.auto, isTvDevice: true),
        isTrue,
      );
      expect(
        TvCapabilities.resolveTvMode(TvModeOverride.auto, isTvDevice: false),
        isFalse,
      );
    });

    test('forceOn 在非电视硬件上也为真（桌面 / 手机验证用）', () {
      expect(
        TvCapabilities.resolveTvMode(TvModeOverride.forceOn, isTvDevice: false),
        isTrue,
      );
    });

    test('forceOff 在电视硬件上也为假（电视上临时切回手机布局）', () {
      expect(
        TvCapabilities.resolveTvMode(TvModeOverride.forceOff, isTvDevice: true),
        isFalse,
      );
    });

    test('override 完全覆盖硬件探测，与 isTvDevice 无关', () {
      for (final isTv in [true, false]) {
        expect(
          TvCapabilities.resolveTvMode(
            TvModeOverride.forceOn,
            isTvDevice: isTv,
          ),
          isTrue,
        );
        expect(
          TvCapabilities.resolveTvMode(
            TvModeOverride.forceOff,
            isTvDevice: isTv,
          ),
          isFalse,
        );
      }
    });
  });

  group('debugSetForTest / isTvMode', () {
    tearDown(TvCapabilities.resetForTest);

    test('注入 forceOn 后 isTvMode 为真', () {
      TvCapabilities.debugSetForTest(override: TvModeOverride.forceOn);
      expect(TvCapabilities.isTvMode, isTrue);
    });

    test('注入探测结果后 auto 档 isTvMode 跟随硬件', () {
      TvCapabilities.debugSetForTest(isTvDevice: true);
      expect(TvCapabilities.override, TvModeOverride.auto);
      expect(TvCapabilities.isTvMode, isTrue);
    });

    test('resetForTest 清回默认（非 TV）', () {
      TvCapabilities.debugSetForTest(
        isTvDevice: true,
        override: TvModeOverride.forceOn,
      );
      TvCapabilities.resetForTest();

      expect(TvCapabilities.isTvDevice, isFalse);
      expect(TvCapabilities.override, TvModeOverride.auto);
      expect(TvCapabilities.isTvMode, isFalse);
    });

    test('isTvDevice 不受 override 影响（设置页要显示「自动检测结果」）', () {
      TvCapabilities.debugSetForTest(
        isTvDevice: false,
        override: TvModeOverride.forceOn,
      );
      expect(TvCapabilities.isTvMode, isTrue);
      expect(TvCapabilities.isTvDevice, isFalse);
    });
  });
}
