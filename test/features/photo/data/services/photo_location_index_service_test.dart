import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_location_index_service.dart';

void main() {
  test('decodes EXIF coordinates and hemisphere references', () {
    final exif = img.ExifData();
    exif.gpsIfd.setGpsLocation(latitude: -37.775, longitude: -122.4191667);
    final jpeg = img.encodeJpg(img.Image(width: 2, height: 2));
    final withExif = img.injectJpgExif(Uint8List.fromList(jpeg), exif);

    final coordinate = PhotoLocationIndexService.decodeJpegCoordinate(
      withExif!,
    );

    expect(coordinate, isNotNull);
    expect(coordinate!.latitude, closeTo(-37.775, 0.000001));
    expect(coordinate.longitude, closeTo(-122.4191667, 0.000001));
  });

  test('invalid or non-JPEG headers safely return no coordinate', () {
    expect(
      PhotoLocationIndexService.decodeJpegCoordinate(
        Uint8List.fromList([0, 1, 2, 3]),
      ),
      isNull,
    );
  });

  test('photo entities expose persisted location metadata', () {
    const photo = PhotoEntity(
      sourceId: 'source',
      filePath: '/photo.jpg',
      fileName: 'photo.jpg',
    );

    final located = photo.copyWith(
      latitude: 31.2304,
      longitude: 121.4737,
      locationScanned: true,
    );

    expect(photo.hasLocation, isFalse);
    expect(located.hasLocation, isTrue);
    expect(located.locationScanned, isTrue);
  });
}
