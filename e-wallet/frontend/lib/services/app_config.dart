import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const String _apiBaseUrlFromDefine = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String _firebaseApiKeyFromDefine = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );

  static String get apiBaseUrl {
    final fromDefine = _apiBaseUrlFromDefine.trim();
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }
    final fromDotenv = _safeDotenvGet('API_BASE_URL');
    if (fromDotenv.isNotEmpty) {
      return fromDotenv;
    }
    throw StateError(
      'API_BASE_URL is required. Provide it via --dart-define or .env.',
    );
  }

  static String get firebaseApiKey {
    final fromDefine = _firebaseApiKeyFromDefine.trim();
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }
    final fromDotenv = _safeDotenvGet('FIREBASE_API_KEY');
    if (fromDotenv.isNotEmpty) {
      return fromDotenv;
    }
    throw StateError(
      'FIREBASE_API_KEY is required. Provide it via --dart-define or .env.',
    );
  }

  static String _safeDotenvGet(String key) {
    try {
      return (dotenv.maybeGet(key) ?? '').trim();
    } catch (_) {
      // dotenv may be unavailable in release builds when no env asset is bundled.
      return '';
    }
  }
}
