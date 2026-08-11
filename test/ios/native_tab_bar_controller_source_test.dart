import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS 18 tab bar API remains availability guarded', () {
    final source = File(
      'ios/Runner/NativeTabBarController.swift',
    ).readAsStringSync();

    expect(
      source,
      contains('if #available(iOS 18.0, *), responds(to: selector)'),
    );
  });
}
