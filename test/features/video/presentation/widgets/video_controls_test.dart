import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/presentation/widgets/video_controls.dart';

void main() {
  testWidgets('seek slider emits only once when dragging ends', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoSeekSlider(
            progress: 0.25,
            duration: const Duration(seconds: 100),
            onSeek: seeks.add,
          ),
        ),
      ),
    );

    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    expect(seeks, isEmpty);

    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(seeks, isEmpty);

    await gesture.up();
    await tester.pump();

    expect(seeks, hasLength(1));
  });

  testWidgets('seek slider is disabled until duration is known', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoSeekSlider(
            progress: 0,
            duration: Duration.zero,
            onSeek: seeks.add,
          ),
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    expect(seeks, isEmpty);
  });
}
