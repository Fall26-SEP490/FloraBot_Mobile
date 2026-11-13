import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'models.dart';

class ApiError implements Exception {
  const ApiError(this.status, this.message, {this.ambiguous = false});
  final int status;
  final String message;
  final bool ambiguous;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.base, {http.Client? transport})
    : _transport = transport ?? http.Client();
  final Uri base;
  final http.Client _transport;
  String? accessToken;
  Future<void> Function()? refreshSession;
  int _generation = 0;
  void clearSession() {
    accessToken = null;
    _generation++;
  }

  Uri endpoint(String path) {
    if (!path.startsWith('/api/') ||
        path.contains('://') ||
        path.startsWith('//')) {
      throw ArgumentError('Chỉ gọi API cùng máy chủ.');
    }
    final uri = base.resolve(path);
    if (uri.origin != base.origin) {
      throw ArgumentError('Máy chủ API không hợp lệ.');
    }
    return uri;
  }

  Future<dynamic> get(String path) => request('GET', path);
  Future<dynamic> post(String path, [Json? body]) =>
      request('POST', path, body: body ?? {});
  Future<dynamic> put(String path, Json body) =>
      request('PUT', path, body: body);

  Future<Uint8List> imageBytes(String path) async {
    final generation = _generation;
    Future<http.Response> send() => _transport
        .get(
          endpoint(path),
          headers: {
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            'Accept': 'image/*',
          },
        )
        .timeout(const Duration(seconds: 25));
    var response = await send();
    if (generation != _generation) {
      throw const ApiError(401, 'Phiên đã thay đổi.');
    }
    if (response.statusCode == 401 && refreshSession != null) {
      await refreshSession!();
      if (generation != _generation) {
        throw const ApiError(401, 'Phiên đã thay đổi.');
      }
      response = await send();
    }
    if (generation != _generation) {
      throw const ApiError(401, 'Phiên đã thay đổi.');
    }
    if (response.statusCode != 200) decode(response);
    if (!(response.headers['content-type'] ?? '').startsWith('image/') ||
        response.bodyBytes.length > 10 * 1024 * 1024) {
      throw const ApiError(400, 'Không đọc được ảnh an toàn từ máy chủ.');
    }
    return response.bodyBytes;
  }

  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    bool authenticated = true,
  }) async {
    final generation = _generation;
    Future<http.Response> send() => _transport
        .send(
          http.Request(method, endpoint(path))
            ..headers.addAll({
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              if (authenticated && accessToken != null)
                'Authorization': 'Bearer $accessToken',
            })
            ..body = body == null ? '' : jsonEncode(body),
        )
        .then(http.Response.fromStream);
    try {
      var response = await send().timeout(const Duration(seconds: 25));
      if (generation != _generation) {
        throw const ApiError(401, 'Phiên đã thay đổi.');
      }
      if (response.statusCode == 401 &&
          authenticated &&
          refreshSession != null) {
        await refreshSession!();
        if (generation != _generation) {
          throw const ApiError(401, 'Vui lòng đăng nhập lại.');
        }
        response = await send().timeout(const Duration(seconds: 25));
      }
      if (generation != _generation) {
        throw const ApiError(401, 'Phiên đã thay đổi.');
      }
      return decode(response);
    } on TimeoutException {
      throw ApiError(
        0,
        method == 'GET'
            ? 'Kết nối chậm. Thử tải lại.'
            : 'Chưa xác nhận được kết quả. Tải lại trạng thái trước khi gửi lại.',
        ambiguous: method != 'GET',
      );
    } on http.ClientException {
      throw ApiError(
        0,
        'Không kết nối được máy chủ. Kiểm tra mạng và tải lại trạng thái.',
        ambiguous: method != 'GET',
      );
    }
  }

  static dynamic decode(http.Response response) {
    dynamic data;
    if (response.bodyBytes.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        data = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data is Map ? data['detail'] ?? data['message'] : null;
      final message = detail is String
          ? detail
          : switch (response.statusCode) {
              401 =>
                'Phiên đăng nhập không hợp lệ hoặc thông tin đăng nhập chưa đúng.',
              403 => 'Bạn chưa có quyền thực hiện thao tác này.',
              404 => 'Không tìm thấy dữ liệu hoặc API chưa được triển khai.',
              409 => 'Trạng thái đã thay đổi. Tải lại trước khi thao tác.',
              429 => 'Thao tác quá nhanh. Vui lòng chờ rồi thử lại.',
              _ => 'Máy chủ chưa xử lý được yêu cầu (${response.statusCode}).',
            };
      throw ApiError(response.statusCode, message);
    }
    if (response.statusCode != 204 && data == null) {
      throw const ApiError(0, 'Máy chủ trả dữ liệu không hợp lệ.');
    }
    return data;
  }

  Future<Json> upload(String path, XFile file, {String? receiptToken}) async {
    if (await file.length() > 5 * 1024 * 1024) {
      throw const ApiError(400, 'Ảnh phải nhỏ hơn 5 MB.');
    }
    final bytes = await file.readAsBytes();
    final isPng =
        bytes.length > 4 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    final isJpeg =
        bytes.length > 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!isPng && !isJpeg) throw const ApiError(400, 'Chọn ảnh JPEG hoặc PNG.');
    final generation = _generation;
    // Uploads are not automatically replayed: the server may have stored the image.
    try {
      final request = http.Request('POST', endpoint(path))
        ..headers.addAll({
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          'X-Receipt-Token': ?receiptToken,
          'Content-Type': isPng ? 'image/png' : 'image/jpeg',
          'Accept': 'application/json',
        })
        ..bodyBytes = bytes;
      final response = await http.Response.fromStream(
        await _transport.send(request).timeout(const Duration(seconds: 40)),
      );
      if (generation != _generation) {
        throw const ApiError(401, 'Phiên đã thay đổi.');
      }
      return objectOf(decode(response));
    } on TimeoutException {
      throw const ApiError(
        0,
        'Chưa xác nhận kết quả tải ảnh. Kiểm tra hồ sơ trước khi tải lại.',
        ambiguous: true,
      );
    } on http.ClientException {
      throw const ApiError(
        0,
        'Mất kết nối khi tải ảnh. Kiểm tra hồ sơ trước khi thử lại.',
        ambiguous: true,
      );
    }
  }

  void dispose() => _transport.close();
}
