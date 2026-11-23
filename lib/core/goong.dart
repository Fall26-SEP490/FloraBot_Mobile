import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'models.dart';

class GoongConfig {
  const GoongConfig({required this.apiKey, required this.mapTilesKey});
  final String apiKey, mapTilesKey;

  static Future<GoongConfig> load() async {
    var api = const String.fromEnvironment('GOONG_API_KEY');
    var tiles = const String.fromEnvironment('GOONG_MAPTILES_KEY');
    if (api.isEmpty || tiles.isEmpty) {
      try {
        final local = objectOf(
          jsonDecode(
            await rootBundle.loadString('assets/config/goong.local.json'),
          ),
        );
        if (api.isEmpty) api = '${local['GOONG_API_KEY'] ?? ''}';
        if (tiles.isEmpty) tiles = '${local['GOONG_MAPTILES_KEY'] ?? ''}';
      } catch (_) {
        /* Build-time defines are preferred outside local development. */
      }
    }
    return GoongConfig(apiKey: api.trim(), mapTilesKey: tiles.trim());
  }

  String get styleUrl => Uri.https(
    'tiles.goong.io',
    '/assets/goong_map_web.json',
    {'api_key': mapTilesKey},
  ).toString();
}

class GoongPlace {
  const GoongPlace({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
  final String address;
  final double latitude, longitude;
}

class GoongSuggestion {
  const GoongSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
  final String placeId, description, mainText, secondaryText;
}

GoongSuggestion parseGoongSuggestion(Json prediction) {
  final description = valueOf(prediction, 'description', '');
  final formatting = prediction['structured_formatting'];
  final mainRaw = formatting is Map<String, dynamic>
      ? valueOf(formatting, 'main_text', '')
      : '';
  final secondaryRaw = formatting is Map<String, dynamic>
      ? valueOf(formatting, 'secondary_text', '')
      : '';
  return GoongSuggestion(
    placeId: valueOf(prediction, 'place_id', ''),
    description: description,
    mainText: mainRaw.isNotEmpty ? mainRaw : description,
    secondaryText: secondaryRaw,
  );
}

class GoongPlacesClient {
  GoongPlacesClient(this.apiKey, {http.Client? transport})
    : _client = transport ?? http.Client();
  final String apiKey;
  final http.Client _client;

  void dispose() => _client.close();

  Future<Json> _get(String path, Map<String, String> parameters) async {
    if (apiKey.isEmpty) {
      throw const ApiError(400, 'Chưa cấu hình tìm địa chỉ Goong.');
    }
    try {
      final response = await _client
          .get(
            Uri.https('rsapi.goong.io', path, {
              ...parameters,
              'api_key': apiKey,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const ApiError(
          502,
          'Không tải được địa chỉ Goong. Vui lòng thử lại.',
        );
      }
      final data = objectOf(jsonDecode(utf8.decode(response.bodyBytes)));
      if (data['status'] == 'ZERO_RESULTS') return data;
      if (data['status'] != 'OK') {
        throw const ApiError(502, 'Goong chưa trả về địa chỉ hợp lệ.');
      }
      return data;
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(502, 'Không kết nối được Goong. Vui lòng thử lại.');
    }
  }

  Future<List<Json>> suggestions(String query) async {
    if (query.trim().length < 3) return [];
    final data = await _get('/Place/AutoComplete', {
      'input': query.trim(),
      'limit': '6',
    });
    return itemsOf(data['predictions'] ?? []);
  }

  Future<GoongPlace> detail(String id) async {
    final data = await _get('/Place/Detail', {'place_id': id});
    final result = objectOf(data['result']);
    final location = objectOf(objectOf(result['geometry'])['location']);
    final latitude = (location['lat'] as num?)?.toDouble();
    final longitude = (location['lng'] as num?)?.toDouble();
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const ApiError(
        502,
        'Tọa độ Goong chưa hợp lệ. Vui lòng chọn địa chỉ khác.',
      );
    }
    return GoongPlace(
      address: valueOf(
        result,
        'formatted_address',
        valueOf(result, 'name', ''),
      ),
      latitude: latitude,
      longitude: longitude,
    );
  }
}
