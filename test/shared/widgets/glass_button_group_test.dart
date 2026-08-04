import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';

/// GlassButtonGroup 与原生侧（ios/macos Runner/GlassButtonGroup.swift）之间
/// 有两个必须对齐的契约：
///   1. 宽度公式 —— Dart 给 SizedBox 的宽度要等于原生 StackView 实际需要的宽度，
///      否则按钮会被挤压。
///   2. SF Symbol 映射 —— 映射不到的图标必须能被识别出来，好让调用方回退到
///      Flutter 渲染，而不是让原生画一个语义不符的占位符号。
/// 这两条都无法靠 flutter analyze 发现，用测试锁住。
void main() {
  group('GlassButtonGroup 布局常量', () {
    test('常量与原生侧保持一致', () {
      // 这些值同时出现在 Swift 的 creationParams 默认值里。
      // 改动此处必须同步改 ios/ 与 macos/ 两个 GlassButtonGroup.swift。
      expect(GlassButtonGroup.buttonSize, 40);
      expect(GlassButtonGroup.minButtonSpacing, 8);
      expect(GlassButtonGroup.horizontalInset, 10);
      expect(GlassButtonGroup.groupCornerRadius, 22);
      expect(GlassButtonGroup.groupHeight, 44);
      expect(GlassButtonGroup.chevronExtraWidth, 12);
    });

    test('两个按钮的宽度与原生布局需求相符', () {
      // 原生: 2 个按钮 40pt + 1 段间距 8pt + 左右各 10pt = 108pt
      const buttonCount = 2;
      final width = buttonCount * GlassButtonGroup.buttonSize +
          (buttonCount - 1) * GlassButtonGroup.minButtonSpacing +
          GlassButtonGroup.horizontalInset * 2;

      expect(width, 108);
      // 回归防护：旧公式是 count*40 + (count-1)*0.5 + 20 = 100.5，
      // 比原生实际需要的少 7.5pt，按钮因此被挤压。
      expect(width, isNot(100.5));
    });

    test('单个按钮不含间距', () {
      const buttonCount = 1;
      final width = buttonCount * GlassButtonGroup.buttonSize +
          (buttonCount - 1) * GlassButtonGroup.minButtonSpacing +
          GlassButtonGroup.horizontalInset * 2;

      expect(width, 60);
    });
  });

  group('glassIconToSFSymbol', () {
    test('实际用到的按钮图标都有映射', () {
      // 这些图标出现在 GlassGroupIconButton / GlassGroupDynamicButton /
      // GlassGroupPopupMenuButton 的调用点上。任何一个映射不到，
      // 对应页面的按钮组就会整体退回 Flutter 渲染。
      const usedInButtonGroups = <IconData>[
        Icons.search_rounded,
        Icons.tune_rounded,
        Icons.more_vert_rounded,
        Icons.swap_vert_rounded,
        Icons.sort_rounded,
        Icons.filter_alt_rounded,
        Icons.filter_alt,
        Icons.list_rounded,
        Icons.grid_view_rounded,
        Icons.view_timeline_rounded,
        Icons.check_circle_outline_rounded,
        Icons.queue_music_rounded,
        Icons.cloud_rounded,
        Icons.folder_rounded,
        Icons.settings_rounded,
        // ReadingContentType.icon 的三个取值
        Icons.menu_book_rounded,
        Icons.collections_bookmark_rounded,
        Icons.note_alt_rounded,
      ];

      for (final icon in usedInButtonGroups) {
        expect(
          glassIconToSFSymbol(icon),
          isNotNull,
          reason: '图标 codePoint 0x${icon.codePoint.toRadixString(16)} 缺少 SF Symbol 映射',
        );
      }
    });

    test('未映射的图标返回 null 而不是占位符号', () {
      // 关键契约：返回 null 让调用方知道"映射不到"。
      // 旧实现返回 'circle'，调用方无从分辨，iOS 上直接画成一个实心圆。
      expect(glassIconToSFSymbol(Icons.rocket_launch_rounded), isNull);
      expect(glassIconToSFSymbol(null), isNull);
    });

    test('映射结果不含空字符串', () {
      for (final icon in [Icons.search_rounded, Icons.more_vert_rounded]) {
        expect(glassIconToSFSymbol(icon), isNotEmpty);
      }
    });
  });
}
