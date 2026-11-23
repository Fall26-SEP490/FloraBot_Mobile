import 'dart:convert';

import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/goong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'Goong autocomplete encodes the query and keeps Vietnamese readable',
    () async {
      final client = GoongPlacesClient(
        'rest-test',
        transport: MockClient((r) async {
          expect(r.url.host, 'rsapi.goong.io');
          expect(r.url.path, '/Place/AutoComplete');
          expect(r.url.queryParameters['api_key'], 'rest-test');
          expect(r.url.queryParameters['input'], 'Đại học FPT & Hòa Lạc');
          return json({
            'status': 'OK',
            'predictions': [
              {'place_id': 'p1', 'description': 'Đại học FPT, Hà Nội'},
            ],
          });
        }),
      );
      addTearDown(client.dispose);
      final result = await client.suggestions('Đại học FPT & Hòa Lạc');
      expect(result.single['description'], 'Đại học FPT, Hà Nội');
    },
  );

  test('Goong detail returns address and coordinates together', () async {
    final client = GoongPlacesClient(
      'rest-test',
      transport: MockClient((r) async {
        expect(r.url.path, '/Place/Detail');
        expect(r.url.queryParameters['place_id'], 'p1');
        return json({
          'status': 'OK',
          'result': {
            'formatted_address': 'FPT University, Hà Nội',
            'geometry': {
              'location': {'lat': 21.0285, 'lng': 105.8542},
            },
          },
        });
      }),
    );
    addTearDown(client.dispose);
    final place = await client.detail('p1');
    expect(place.latitude, 21.0285);
    expect(place.longitude, 105.8542);
    expect(place.address, 'FPT University, Hà Nội');
  });

  test('Goong detail refuses invalid coordinates', () async {
    final client = GoongPlacesClient(
      'rest-test',
      transport: MockClient(
        (r) async => json({
          'status': 'OK',
          'result': {
            'geometry': {
              'location': {'lat': 200, 'lng': 105},
            },
          },
        }),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(client.detail('p1'), throwsA(isA<ApiError>()));
  });

  test('Goong denied key is an error, not an empty search success', () async {
    final client = GoongPlacesClient(
      'rest-test',
      transport: MockClient((r) async => json({'status': 'REQUEST_DENIED'})),
    );
    addTearDown(client.dispose);
    await expectLater(client.suggestions('Hà Nội'), throwsA(isA<ApiError>()));
  });

  test('map style uses the separate Goong map tiles key', () {
    const config = GoongConfig(apiKey: 'rest-test', mapTilesKey: 'tiles-test');
    final url = Uri.parse(config.styleUrl);
    expect(url.host, 'tiles.goong.io');
    expect(url.path, '/assets/goong_map_web.json');
    expect(url.queryParameters['api_key'], 'tiles-test');
  });

  test(
    'parseGoongSuggestion extracts structured formatting and falls back to description',
    () {
      final structured = parseGoongSuggestion({
        'place_id': 'p1',
        'description': 'Đại học FPT, Khu Công nghệ cao Hòa Lạc, Hà Nội',
        'structured_formatting': {
          'main_text': 'Đại học FPT',
          'secondary_text': 'Khu Công nghệ cao Hòa Lạc, Hà Nội',
        },
      });
      expect(structured.placeId, 'p1');
      expect(structured.mainText, 'Đại học FPT');
      expect(structured.secondaryText, 'Khu Công nghệ cao Hòa Lạc, Hà Nội');

      final fallback = parseGoongSuggestion({
        'place_id': 'p2',
        'description': '12 Nguyễn Trãi, Hà Nội',
      });
      expect(fallback.placeId, 'p2');
      expect(fallback.mainText, '12 Nguyễn Trãi, Hà Nội');
      expect(fallback.secondaryText, isEmpty);
    },
  );
}
