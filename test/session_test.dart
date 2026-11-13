import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/auth.dart';
import 'package:florabot_mobile/core/models.dart';

Map<String, dynamic> payload([String role = 'CUSTOMER']) => {
  'accessToken': 'access',
  'refreshToken': List.filled(64, 'a').join(),
  'user': {
    'id': 'user1',
    'name': 'Test',
    'role': role,
    if (role == 'SELLER' || role == 'SELLER_STAFF') 'sellerId': 'shop1',
  },
};
ApiClient client(Future<http.Response> Function(http.Request) handle) =>
    ApiClient(Uri.parse('https://example.test'), transport: MockClient(handle));

void main() {
  test(
    'evidence uploads raw image bytes with receipt token in header only',
    () async {
      final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final api = client((request) async {
        expect(request.method, 'POST');
        expect(request.headers['Content-Type'], 'image/png');
        expect(request.headers['X-Receipt-Token'], 'private-receipt-token');
        expect(request.url.query, isEmpty);
        expect(request.bodyBytes, bytes);
        return http.Response('{"reference":"protected-reference"}', 200);
      });
      final result = await api.upload(
        '/api/receipts/order/evidence',
        XFile.fromData(bytes, name: 'test.png'),
        receiptToken: 'private-receipt-token',
      );
      expect(result['reference'], 'protected-reference');
    },
  );
  test('confirmed refresh rejection clears revoked credentials', () async {
    final vault = MemoryTokenVault()..value = List.filled(64, 'a').join();
    final api = client((_) async => http.Response('{}', 401));
    final auth = AuthController(api, vault);
    await auth.restore();
    expect(vault.value, isNull);
    expect(auth.session, isNull);
    expect(auth.waitingForConnection, false);
  });
  test(
    'temporary network failure during refresh preserves the active session',
    () async {
      var offline = false;
      final vault = MemoryTokenVault();
      final api = client((request) async {
        if (offline) throw http.ClientException('offline');
        return http.Response(jsonEncode(payload()), 200);
      });
      final auth = AuthController(api, vault);
      await auth.login('test@example.test', 'password', AppRole.customer);
      final stored = vault.value;
      offline = true;
      await expectLater(auth.refresh(), throwsA(isA<ApiError>()));
      expect(auth.session?.role, AppRole.customer);
      expect(vault.value, stored);
      expect(api.accessToken, 'access');
      offline = false;
      await auth.refresh();
      expect(auth.session, isNotNull);
    },
  );
  test('offline cold start keeps saved refresh and offers retry', () async {
    final vault = MemoryTokenVault()..value = List.filled(64, 'a').join();
    final api = client((_) async => throw http.ClientException('offline'));
    final auth = AuthController(api, vault);
    await auth.restore();
    expect(auth.waitingForConnection, true);
    expect(vault.value, isNotNull);
    expect(auth.loading, false);
  });
  test('rejects cross-origin and non-API requests', () {
    final api = client((_) async => http.Response('{}', 200));
    for (final path in [
      'https://evil.test/api/x',
      '//evil.test/api/x',
      '/auth',
    ]) {
      expect(() => api.endpoint(path), throwsArgumentError);
    }
    expect(api.endpoint('/api/tasks?page=2').origin, 'https://example.test');
  });
  test('network failure on mutation is ambiguous and never retried', () async {
    var calls = 0;
    final api = client((_) async {
      calls++;
      throw http.ClientException('offline');
    });
    await expectLater(
      api.post('/api/tasks'),
      throwsA(isA<ApiError>().having((e) => e.ambiguous, 'ambiguous', true)),
    );
    expect(calls, 1);
  });
  test('logout rejects already in-flight authenticated results', () async {
    final response = Completer<http.Response>();
    final api = client((_) => response.future)..accessToken = 'old';
    final pending = api.get('/api/tasks');
    api.clearSession();
    final checked = expectLater(
      pending,
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
    );
    response.complete(http.Response('{}', 200));
    await checked;
  });
  test('parallel unauthorized calls rotate refresh only once', () async {
    var refreshes = 0;
    final gate = Completer<void>();
    final vault = MemoryTokenVault();
    final api = client((request) async {
      if (request.url.path.endsWith('/login')) {
        return http.Response(jsonEncode(payload()), 200);
      }
      if (request.url.path.endsWith('/refresh')) {
        refreshes++;
        await gate.future;
        return http.Response(
          jsonEncode({...payload(), 'accessToken': 'new'}),
          200,
        );
      }
      return http.Response(
        '{}',
        request.headers['Authorization'] == 'Bearer new' ? 200 : 401,
      );
    });
    final auth = AuthController(api, vault);
    await auth.login('test@example.test', 'password', AppRole.customer);
    final one = api.get('/api/one'), two = api.get('/api/two');
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([one, two]);
    expect(refreshes, 1);
    expect(auth.session?.role, AppRole.customer);
  });
  test('offline logout clears local tokens', () async {
    final vault = MemoryTokenVault();
    final api = client((r) async {
      if (r.url.path.endsWith('/login')) {
        return http.Response(jsonEncode(payload()), 200);
      }
      throw http.ClientException('offline');
    });
    final auth = AuthController(api, vault);
    await auth.login('test@example.test', 'password', AppRole.customer);
    await auth.logout();
    expect(vault.value, isNull);
    expect(api.accessToken, isNull);
    expect(auth.session, isNull);
  });
  test('rejects manager and staff without shop membership', () {
    expect(
      () => Session.fromJson({'id': '1', 'name': 'Test', 'role': 'MANAGER'}),
      throwsFormatException,
    );
    expect(
      () =>
          Session.fromJson({'id': '1', 'name': 'Test', 'role': 'SELLER_STAFF'}),
      throwsFormatException,
    );
  });
}
