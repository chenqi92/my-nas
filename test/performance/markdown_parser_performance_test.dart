import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/note/data/services/markdown_parser.dart';

void main() {
  test('parses a 10,000-line task note within the baseline budget', () {
    final content = List.generate(
      10000,
      (index) => index.isEven
          ? '- [ ] Task $index #benchmark'
          : 'Regular note line $index',
    ).join('\n');

    final stopwatch = Stopwatch()..start();
    final tasks = MarkdownParser.parseTasks(content);
    stopwatch.stop();

    expect(tasks, hasLength(5000));
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason:
          'Keep a generous cross-platform ceiling while catching major regressions.',
    );
  });
}
