import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'models.dart';

abstract interface class TokenVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureTokenVault implements TokenVault {
  SecureTokenVault(String origin) : key = 'florabot.mobile.refresh.v1.$origin';
  final String key;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}

// Browser previews deliberately do not persist native session credentials.
class MemoryTokenVault implements TokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class AuthController extends ChangeNotifier {
  AuthController(this.api, this.vault) {
    api.refreshSession = refresh;
  }
  final ApiClient api;
  final TokenVault vault;
  Session? session;
  String? _refreshToken;
  bool loading = true;
  String? error;
  int _epoch = 0;
  Future<void>? _refreshing;
  bool get waitingForConnection =>
      !loading && session == null && _refreshToken != null;
  Future<void> _vaultQueue = Future<void>.value();

  Future<T> _storage<T>(Future<T> Function() operation) {
    final result = _vaultQueue.then((_) => operation());
    _vaultQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> restore() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      _refreshToken = await _storage(vault.read);
      if (_refreshToken != null) await refresh();
    } catch (e) {
      error = waitingForConnection || _refreshToken != null
          ? 'Chưa kết nối được để khôi phục phiên. Thử lại khi có mạng.'
          : 'Vui lòng đăng nhập lại. ${e is ApiError ? e.message : ''}';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password, AppRole role) async {
    final epoch = ++_epoch;
    error = null;
    final json = objectOf(
      await api.request(
        'POST',
        '/api/mobile/auth/login',
        authenticated: false,
        body: {'email': email.trim(), 'password': password, 'role': role.code},
      ),
    );
    if (epoch != _epoch) return;
    await _accept(json, epoch);
    notifyListeners();
  }

  Future<void> _accept(Json json, int epoch) async {
    final next = Session.fromJson(objectOf(json['user']));
    final refresh = json['refreshToken'] as String;
    final access = json['accessToken'] as String;
    if (refresh.length != 64 || access.isEmpty) {
      throw const FormatException('Phiên không hợp lệ.');
    }
    await _storage(() async {
      if (epoch == _epoch) await vault.write(refresh);
    });
    if (epoch != _epoch) return;
    _refreshToken = refresh;
    api.accessToken = access;
    session = next;
  }

  Future<void> refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  Future<void> _doRefresh() async {
    final epoch = _epoch;
    final token = _refreshToken;
    if (token == null) throw const ApiError(401, 'Vui lòng đăng nhập.');
    try {
      final json = objectOf(
        await api.request(
          'POST',
          '/api/mobile/auth/refresh',
          authenticated: false,
          body: {'refreshToken': token},
        ),
      );
      if (epoch != _epoch) throw const ApiError(401, 'Phiên đã kết thúc.');
      await _accept(json, epoch);
      notifyListeners();
    } catch (e) {
      // A transport/server failure is not proof that the session was revoked.
      // Preserve local credentials and the current workspace for explicit retry.
      if (epoch == _epoch &&
          e is ApiError &&
          (e.status == 401 || e.status == 403)) {
        _epoch++;
        session = null;
        _refreshToken = null;
        api.clearSession();
        await _storage(vault.clear);
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final token = _refreshToken;
    _epoch++;
    session = null;
    _refreshToken = null;
    api.clearSession();
    try {
      await _storage(vault.clear);
    } catch (_) {
      error =
          'Không xóa được phiên trên thiết bị. Hãy đóng ứng dụng và kiểm tra bộ nhớ bảo mật.';
    } finally {
      notifyListeners();
    }
    if (token != null) {
      try {
        await api.request(
          'POST',
          '/api/mobile/auth/logout',
          authenticated: false,
          body: {'refreshToken': token},
        );
      } catch (_) {
        // Local credentials have already been removed; server refresh expires in seven days.
      }
    }
  }

  Future<void> revalidate() async {
    final epoch = _epoch;
    try {
      final current = Session.fromJson(objectOf(await api.get('/api/auth/me')));
      if (epoch == _epoch && session != null) {
        session = current;
        notifyListeners();
      }
    } on ApiError catch (e) {
      if (e.status == 401 && epoch == _epoch) await logout();
      // An offline resume keeps the session shell, but server operations still fail closed.
    } catch (_) {
      /* The next explicit reload surfaces server/schema errors. */
    }
  }
}
