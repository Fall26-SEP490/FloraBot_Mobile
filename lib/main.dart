import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/api.dart';
import 'core/auth.dart';
import 'core/config.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final api = ApiClient(AppConfig.api);
    final vault = kIsWeb
        ? MemoryTokenVault()
        : SecureTokenVault(api.base.origin);
    runApp(FloraBotApp(auth: AuthController(api, vault)));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Cấu hình máy chủ chưa hợp lệ. Kiểm tra API_BASE_URL trước khi chạy ứng dụng.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
