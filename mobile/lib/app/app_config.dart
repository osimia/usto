import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  static const _productionApiBaseUrl =
      'https://usto-production.up.railway.app/api';

  static String get apiBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return _productionApiBaseUrl;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _productionApiBaseUrl;
      default:
        return _productionApiBaseUrl;
    }
  }
}
