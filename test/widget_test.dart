import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AppChip', () {
    testWidgets('renders its label', (tester) async {
      await tester.pumpWidget(_host(const AppChip(label: 'Action')));
      expect(find.text('Action'), findsOneWidget);
    });

    testWidgets('fires onTap when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(AppChip(label: 'Drama', onTap: () => taps++)),
      );
      await tester.tap(find.text('Drama'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('AppSegmented', () {
    testWidgets('reports the tapped option value', (tester) async {
      String? picked;
      await tester.pumpWidget(
        _host(
          AppSegmented<String>(
            value: 'a',
            onChanged: (v) => picked = v,
            options: const [
              AppSegmentedOption(value: 'a', label: 'Alpha'),
              AppSegmentedOption(value: 'b', label: 'Beta'),
            ],
          ),
        ),
      );
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      await tester.tap(find.text('Beta'));
      await tester.pump();
      expect(picked, 'b');
    });
  });
}
