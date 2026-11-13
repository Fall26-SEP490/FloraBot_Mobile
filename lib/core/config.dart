import 'package:flutter/foundation.dart';

class AppConfig {
  static const apiUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.florabot.site',
  );
  static const portalUrl = String.fromEnvironment(
    'PORTAL_URL',
    defaultValue: 'https://florabot-fe.vercel.app',
  );
  static Uri get api {
    final uri = Uri.parse(apiUrl);
    final localDebug =
        kDebugMode && const bool.fromEnvironment('ALLOW_LOCAL_HTTP');
    if ((!uri.isScheme('https') && !(localDebug && uri.isScheme('http'))) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw StateError(
        'API_BASE_URL phải là HTTPS origin, không chứa key, đường dẫn hay query.',
      );
    }
    return uri;
  }
}
