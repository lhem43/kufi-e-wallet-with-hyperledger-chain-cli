import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'error_message.dart';

class AuthService {
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyCurrentUser = 'current_user';

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    try {
      final configError = _validateFirebaseConfig();
      if (configError != null) {
        return configError;
      }

      final signUpResult = await _firebaseSignUp(
        email: email,
        password: password,
      );
      if (signUpResult['success'] != true) {
        return signUpResult;
      }

      String idToken = _stringValue(signUpResult, 'idToken');
      if (idToken.isEmpty) {
        return {
          'success': false,
          'message': 'Không nhận được token đăng ký từ Firebase.',
        };
      }
      final update = await _firebaseUpdateProfile(
        idToken: idToken,
        displayName: name,
      );
      final updatedIdToken = _stringValue(update, 'idToken');
      if (updatedIdToken.isNotEmpty) {
        idToken = updatedIdToken;
      }

      final verifyResult = await _verifyFirebaseIdTokenWithProfileHints(
        idToken,
        phone: phone,
        displayName: name,
      );
      if (verifyResult['success'] != true) {
        return verifyResult;
      }

      final user = _mapValue(verifyResult['user']);
      if (user == null) {
        return {
          'success': false,
          'message': 'Phản hồi tài khoản không hợp lệ. Vui lòng thử lại.',
        };
      }

      final accessToken = _stringValue(verifyResult, 'accessToken');
      final refreshToken = _stringValue(verifyResult, 'refreshToken');
      if (accessToken.isEmpty || refreshToken.isEmpty) {
        return {
          'success': false,
          'message': 'Không thể tạo phiên đăng nhập. Vui lòng thử lại.',
        };
      }

      if ((user['displayName'] == null || '${user['displayName']}'.isEmpty) &&
          name.isNotEmpty) {
        user['displayName'] = name;
      }
      if ((user['phone'] == null || '${user['phone']}'.isEmpty) &&
          phone.isNotEmpty) {
        user['phone'] = phone;
      }

      await _saveSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      );

      return {'success': true, 'message': 'Đăng ký thành công', 'user': user};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể đăng ký lúc này. Vui lòng thử lại.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> login({
    String? email,
    String? identifier,
    required String password,
  }) async {
    try {
      final configError = _validateFirebaseConfig();
      if (configError != null) {
        return configError;
      }

      final trimmedIdentifier = (identifier ?? email ?? '').trim();
      if (trimmedIdentifier.isEmpty) {
        return {
          'success': false,
          'message': 'Vui lòng nhập email hoặc số điện thoại.',
        };
      }

      String emailForLogin = trimmedIdentifier;
      if (!_looksLikeEmail(trimmedIdentifier)) {
        final resolved = await _resolveLoginIdentifierToEmail(
          trimmedIdentifier,
        );
        if (resolved['success'] != true) {
          return resolved;
        }
        emailForLogin = '${resolved['email'] ?? ''}'.trim();
        if (emailForLogin.isEmpty) {
          return {
            'success': false,
            'message': 'Không thể xác thực tài khoản đăng nhập.',
          };
        }
      } else {
        emailForLogin = trimmedIdentifier.toLowerCase();
      }

      final signInResult = await _firebaseSignIn(
        email: emailForLogin,
        password: password,
      );
      if (signInResult['success'] != true) {
        return signInResult;
      }

      final idToken = _stringValue(signInResult, 'idToken');
      if (idToken.isEmpty) {
        return {
          'success': false,
          'message': 'Không nhận được token đăng nhập từ Firebase.',
        };
      }

      final verifyResult = await _verifyFirebaseIdTokenWithProfileHints(
        idToken,
      );
      if (verifyResult['success'] != true) {
        return verifyResult;
      }

      final user = _mapValue(verifyResult['user']);
      if (user == null) {
        return {
          'success': false,
          'message': 'Phản hồi tài khoản không hợp lệ. Vui lòng thử lại.',
        };
      }

      final accessToken = _stringValue(verifyResult, 'accessToken');
      final refreshToken = _stringValue(verifyResult, 'refreshToken');
      if (accessToken.isEmpty || refreshToken.isEmpty) {
        return {
          'success': false,
          'message': 'Không thể tạo phiên đăng nhập. Vui lòng thử lại.',
        };
      }

      await _saveSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      );

      return {'success': true, 'message': 'Đăng nhập thành công', 'user': user};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể đăng nhập lúc này. Vui lòng thử lại.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> checkSignUpAvailability({
    String? email,
    String? phone,
  }) async {
    final normalizedEmail = (email ?? '').trim().toLowerCase();
    final normalizedPhone = _normalizePhone(phone ?? '');

    try {
      final response = await _postJson(
        '${AppConfig.apiBaseUrl}/v1/auth/signup/check-availability',
        {
          if (normalizedEmail.isNotEmpty) 'email': normalizedEmail,
          if (normalizedPhone.isNotEmpty) 'phone': normalizedPhone,
        },
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể kiểm tra thông tin đăng ký lúc này.',
          ),
        };
      }

      final body = _decodeJsonMap(response.body);
      if (body == null) {
        return {
          'success': false,
          'message': 'Phản hồi kiểm tra đăng ký không hợp lệ.',
        };
      }

      final emailPayload = _mapValue(body['email']) ?? {};
      final phonePayload = _mapValue(body['phone']) ?? {};

      return {
        'success': true,
        'emailValid': emailPayload['valid'] == true,
        'emailAvailable': emailPayload['available'] == true,
        'phoneValid': phonePayload['valid'] == true,
        'phoneAvailable': phonePayload['available'] == true,
      };
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể kiểm tra thông tin đăng ký lúc này.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> sendSignUpEmailOtp(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!_looksLikeEmail(normalizedEmail)) {
      return {'success': false, 'message': 'Email không hợp lệ.'};
    }
    try {
      final response = await _postJson(
        '${AppConfig.apiBaseUrl}/v1/auth/signup/email-otp/send',
        {'email': normalizedEmail},
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể gửi OTP email lúc này.',
          ),
        };
      }

      final body = _decodeJsonMap(response.body) ?? {};
      return {
        'success': true,
        'expiresIn': int.tryParse('${body['expiresIn'] ?? ''}') ?? 300,
        'deliveryMode': '${body['deliveryMode'] ?? 'email'}',
      };
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể gửi OTP email lúc này.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> verifySignUpEmailOtp({
    required String email,
    required String otpCode,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedOtp = otpCode.trim();
    if (!_looksLikeEmail(normalizedEmail) ||
        !RegExp(r'^\d{6}$').hasMatch(normalizedOtp)) {
      return {'success': false, 'valid': false};
    }
    try {
      final response = await _postJson(
        '${AppConfig.apiBaseUrl}/v1/auth/signup/email-otp/verify',
        {'email': normalizedEmail, 'otpCode': normalizedOtp},
        headers: const {'Content-Type': 'application/json'},
      );
      if (response.statusCode >= 400) {
        return {'success': false, 'valid': false};
      }
      final body = _decodeJsonMap(response.body);
      return {'success': true, 'valid': body?['valid'] == true};
    } catch (_) {
      return {'success': false, 'valid': false};
    }
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_keyAccessToken);
    if (accessToken == null || accessToken.isEmpty) {
      return false;
    }
    final user = await getCurrentUser();
    return user != null;
  }

  /// Check if the current user has a server-side PIN set.
  Future<bool> hasDevicePinForCurrentUser() async {
    final user = await getCurrentUser();
    if (user == null) return false;
    return user['hasPin'] == true;
  }

  /// Set PIN on the server (primary storage) and also cache locally.
  Future<Map<String, dynamic>> setServerPin({required String pin}) async {
    final normalizedPin = pin.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedPin)) {
      return {'success': false, 'message': 'PIN phải gồm đúng 6 chữ số.'};
    }

    final accessToken = await getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      return {'success': false, 'message': 'Chưa đăng nhập.'};
    }

    try {
      final response = await _postJson(
        '${AppConfig.apiBaseUrl}/v1/auth/pin/set',
        {'pin': normalizedPin},
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể thiết lập PIN.',
          ),
        };
      }

      // Update user data with hasPin = true
      await mergeCurrentUser({'hasPin': true});

      return {'success': true, 'message': 'PIN đã được thiết lập thành công.'};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể thiết lập PIN lúc này.',
        ),
      };
    }
  }

  /// Verify PIN against the server.
  Future<bool> verifyServerPin(String pin) async {
    final normalizedPin = pin.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedPin)) {
      return false;
    }

    final accessToken = await getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      return false;
    }

    try {
      final response = await _postJson(
        '${AppConfig.apiBaseUrl}/v1/auth/pin/verify',
        {'pin': normalizedPin},
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode >= 400) {
        return false;
      }

      final body = _decodeJsonMap(response.body);
      return body?['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_keyCurrentUser);
    if (userJson == null || userJson.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(userJson);
    if (decoded is! Map) {
      await clearLocalSession();
      return null;
    }

    final user = Map<String, dynamic>.from(decoded);
    return user;
  }

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessToken);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRefreshToken);
  }

  Future<Map<String, dynamic>> refreshSession({
    bool triggerExpiredEventOnFailure = false,
  }) async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        if (triggerExpiredEventOnFailure) {
          await expireSessionAndNotify();
        }
        return {
          'success': false,
          'message': 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
        };
      }

      final response = await _postJson(
        '${AppConfig.apiBaseUrl}/v1/auth/refresh',
        {'refreshToken': refreshToken},
        headers: const {'Content-Type': 'application/json'},
      );
      if (response.statusCode >= 400) {
        if (triggerExpiredEventOnFailure) {
          await expireSessionAndNotify(
            message: ErrorMessage.fromHttpBody(
              response.body,
              statusCode: response.statusCode,
              defaultMessage:
                  'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
            ),
          );
        } else {
          await clearLocalSession();
        }
        return {
          'success': false,
          'message': 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
        };
      }

      final body = _decodeJsonMap(response.body);
      if (body == null) {
        if (triggerExpiredEventOnFailure) {
          await expireSessionAndNotify();
        } else {
          await clearLocalSession();
        }
        return {
          'success': false,
          'message':
              'Không thể làm mới phiên đăng nhập. Vui lòng đăng nhập lại.',
        };
      }

      final accessToken = '${body['accessToken'] ?? ''}';
      final nextRefreshToken = '${body['refreshToken'] ?? ''}';
      final user = _mapValue(body['user']);
      if (accessToken.isEmpty || nextRefreshToken.isEmpty || user == null) {
        if (triggerExpiredEventOnFailure) {
          await expireSessionAndNotify();
        } else {
          await clearLocalSession();
        }
        return {
          'success': false,
          'message':
              'Phiên đăng nhập không còn hiệu lực. Vui lòng đăng nhập lại.',
        };
      }

      await _saveSession(
        accessToken: accessToken,
        refreshToken: nextRefreshToken,
        user: user,
      );
      return {
        'success': true,
        'message': 'Làm mới phiên đăng nhập thành công.',
      };
    } catch (_) {
      if (triggerExpiredEventOnFailure) {
        await expireSessionAndNotify();
      }
      return {
        'success': false,
        'message': 'Không thể làm mới phiên đăng nhập. Vui lòng đăng nhập lại.',
      };
    }
  }

  Future<void> clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyCurrentUser);
  }

  Future<void> expireSessionAndNotify({
    String message =
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại để tiếp tục.',
  }) async {
    await clearLocalSession();
  }

  Future<void> logout() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _postJson(
          '${AppConfig.apiBaseUrl}/v1/auth/logout',
          {'refreshToken': refreshToken},
          headers: const {'Content-Type': 'application/json'},
        );
      } catch (_) {
        // no-op for local logout
      }
    }
    await clearLocalSession();
  }

  Future<Map<String, dynamic>> _firebaseSignUp({
    required String email,
    required String password,
  }) async {
    final response = await _postJson(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${AppConfig.firebaseApiKey}',
      {'email': email, 'password': password, 'returnSecureToken': true},
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode >= 400) {
      return {
        'success': false,
        'message': _mapFirebaseError(
          ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Đăng ký Firebase thất bại.',
          ),
        ),
      };
    }

    final body = _decodeJsonMap(response.body);
    if (body == null) {
      return {'success': false, 'message': 'Phản hồi Firebase không hợp lệ.'};
    }
    final idToken = '${body['idToken'] ?? ''}';
    if (idToken.isEmpty) {
      return {
        'success': false,
        'message': 'Không nhận được token từ Firebase.',
      };
    }
    return {'success': true, 'idToken': idToken};
  }

  Future<Map<String, dynamic>> _firebaseSignIn({
    required String email,
    required String password,
  }) async {
    final response = await _postJson(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${AppConfig.firebaseApiKey}',
      {'email': email, 'password': password, 'returnSecureToken': true},
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode >= 400) {
      return {
        'success': false,
        'message': _mapFirebaseError(
          ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Đăng nhập Firebase thất bại.',
          ),
        ),
      };
    }

    final body = _decodeJsonMap(response.body);
    if (body == null) {
      return {'success': false, 'message': 'Phản hồi Firebase không hợp lệ.'};
    }
    final idToken = '${body['idToken'] ?? ''}';
    if (idToken.isEmpty) {
      return {
        'success': false,
        'message': 'Không nhận được token từ Firebase.',
      };
    }
    return {'success': true, 'idToken': idToken};
  }

  Future<Map<String, dynamic>> _firebaseUpdateProfile({
    required String idToken,
    required String displayName,
  }) async {
    if (displayName.trim().isEmpty) {
      return {};
    }

    final response = await _postJson(
      'https://identitytoolkit.googleapis.com/v1/accounts:update?key=${AppConfig.firebaseApiKey}',
      {
        'idToken': idToken,
        'displayName': displayName.trim(),
        'returnSecureToken': true,
      },
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode >= 400) {
      return {};
    }
    return _decodeJsonMap(response.body) ?? {};
  }

  Future<Map<String, dynamic>> _verifyFirebaseIdTokenWithProfileHints(
    String idToken, {
    String? phone,
    String? displayName,
  }) async {
    final response = await _postJson(
      '${AppConfig.apiBaseUrl}/v1/auth/firebase/verify',
      {
        'idToken': idToken,
        if ((phone ?? '').trim().isNotEmpty) 'phone': phone!.trim(),
        if ((displayName ?? '').trim().isNotEmpty)
          'displayName': displayName!.trim(),
      },
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode >= 400) {
      return {
        'success': false,
        'message': ErrorMessage.fromHttpBody(
          response.body,
          statusCode: response.statusCode,
          defaultMessage: 'Xác thực tài khoản thất bại.',
        ),
      };
    }

    final body = _decodeJsonMap(response.body);
    if (body == null) {
      return {'success': false, 'message': 'Phản hồi xác thực không hợp lệ.'};
    }
    final accessToken = '${body['accessToken'] ?? ''}';
    final refreshToken = '${body['refreshToken'] ?? ''}';
    if (accessToken.isEmpty || refreshToken.isEmpty || body['user'] == null) {
      return {'success': false, 'message': 'Phản hồi xác thực không hợp lệ.'};
    }

    return {
      'success': true,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'user': body['user'],
    };
  }

  Future<void> mergeCurrentUser(Map<String, dynamic> patch) async {
    if (patch.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_keyCurrentUser);
    if (current == null || current.isEmpty) {
      return;
    }
    final decoded = jsonDecode(current);
    if (decoded is! Map) {
      return;
    }
    final user = Map<String, dynamic>.from(decoded);
    user.addAll(patch);
    await prefs.setString(_keyCurrentUser, jsonEncode(user));
  }

  Future<void> _saveSession({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> user,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, accessToken);
    await prefs.setString(_keyRefreshToken, refreshToken);
    await prefs.setString(_keyCurrentUser, jsonEncode(user));
  }

  Future<http.Response> _postJson(
    String url,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    return http
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'EMAIL_EXISTS':
        return 'Email đã được đăng ký.';
      case 'EMAIL_NOT_FOUND':
        return 'Email không tồn tại.';
      case 'INVALID_PASSWORD':
        return 'Mật khẩu không chính xác.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Bạn thử quá nhiều lần. Vui lòng thử lại sau.';
      default:
        if (code.trim().isEmpty) {
          return 'Xác thực Firebase thất bại.';
        }
        return code;
    }
  }

  Map<String, dynamic>? _decodeJsonMap(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _stringValue(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value == null) {
      return '';
    }
    return '$value'.trim();
  }

  Map<String, dynamic>? _mapValue(dynamic value) {
    if (value is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(value);
  }

  Map<String, dynamic>? _validateFirebaseConfig() {
    if (AppConfig.firebaseApiKey.trim().isEmpty) {
      return {
        'success': false,
        'message':
            'Thiếu FIREBASE_API_KEY. Chạy app với --dart-define=FIREBASE_API_KEY=...',
      };
    }
    return null;
  }

  Future<Map<String, dynamic>> _resolveLoginIdentifierToEmail(
    String identifierRaw,
  ) async {
    final normalizedPhone = _normalizePhone(identifierRaw);
    if (!_isLookupReadyPhone(normalizedPhone)) {
      return {
        'success': false,
        'message': 'Số điện thoại chưa đầy đủ hoặc không hợp lệ.',
      };
    }

    final response = await _postJson(
      '${AppConfig.apiBaseUrl}/v1/auth/login/resolve-identifier',
      {'identifier': normalizedPhone},
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode >= 400) {
      return {
        'success': false,
        'message': ErrorMessage.fromHttpBody(
          response.body,
          statusCode: response.statusCode,
          defaultMessage: 'Không thể xác thực tài khoản lúc này.',
        ),
      };
    }

    final body = _decodeJsonMap(response.body);
    if (body == null) {
      return {
        'success': false,
        'message': 'Không thể xác thực tài khoản lúc này.',
      };
    }
    if (body['found'] != true) {
      return {
        'success': false,
        'message': 'Thông tin đăng nhập không chính xác.',
      };
    }

    final email = '${body['email'] ?? ''}'.trim();
    if (email.isEmpty) {
      return {
        'success': false,
        'message': 'Không thể xác thực tài khoản đăng nhập.',
      };
    }
    return {'success': true, 'email': email};
  }

  String _normalizePhone(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.startsWith('84') && digitsOnly.length == 11) {
      return '0${digitsOnly.substring(2)}';
    }
    return digitsOnly;
  }

  bool _isLookupReadyPhone(String phone) {
    return RegExp(r'^(0\d{9,10}|84\d{8,10})$').hasMatch(phone);
  }

  bool _looksLikeEmail(String raw) {
    final value = raw.trim();
    return value.contains('@') && value.contains('.');
  }
}
