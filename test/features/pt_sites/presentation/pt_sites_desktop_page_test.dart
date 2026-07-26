import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_site_detail_page.dart';

void main() {
  test('desktop can reuse the complete transfer statistics sheet', () {
    expect(
      const PTTransferStatsSheet(sourceId: 'tracker-1').sourceId,
      'tracker-1',
    );
  });
}
