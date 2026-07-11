import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/pt_sites/data/services/pt_site_api.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

void main() {
  group('PTSiteApi transfer statistics capability', () {
    test('generic trackers do not advertise transfer statistics', () {
      final api = PTSiteApiFactory.create(_source(host: 'tracker.example.com'));
      addTearDown(api.dispose);

      expect(api, isA<GenericPTSiteApi>());
      expect(api.supportsTransferStats, isFalse);
    });

    test('M-Team advertises its implemented transfer statistics API', () {
      final api = PTSiteApiFactory.create(_source(host: 'api.m-team.cc'));
      addTearDown(api.dispose);

      expect(api, isA<MTeamApi>());
      expect(api.supportsTransferStats, isTrue);
    });
  });
}

SourceEntity _source({required String host}) => SourceEntity(
  name: 'Test tracker',
  type: SourceType.ptSite,
  host: host,
  username: 'tester',
);
