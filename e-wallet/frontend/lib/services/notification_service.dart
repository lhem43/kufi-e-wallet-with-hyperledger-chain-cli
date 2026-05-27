import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_model.dart';
import 'app_config.dart';
import 'auth_service.dart';
import 'error_message.dart';
import 'session_expired_exception.dart';

class NotificationService {
  static const String _keyNotifications = 'notifications';
  static const String _keyNotificationsSeenAt = 'notifications_seen_at';
  final AuthService _authService = AuthService();

  Future<void> addNotification({
    required String userKey,
    required String title,
    required String type,
    String? amount,
    String? phoneNumber,
    String? transactionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (userKey.trim().isEmpty) {
      return;
    }
    final storageKey = '${_keyNotifications}_$userKey';
    final notificationsJson = prefs.getString(storageKey) ?? '[]';
    final List<dynamic> notificationsList = json.decode(notificationsJson);

    if (transactionId != null && transactionId.trim().isNotEmpty) {
      final duplicated = notificationsList.any((raw) {
        if (raw is! Map) {
          return false;
        }
        return '${raw['type'] ?? ''}' == type &&
            '${raw['transactionId'] ?? ''}' == transactionId;
      });
      if (duplicated) {
        return;
      }
    }

    final notification = NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      type: type,
      date: DateTime.now(),
      amount: amount,
      phoneNumber: phoneNumber,
      transactionId: transactionId,
    );

    notificationsList.insert(0, notification.toJson());
    await prefs.setString(storageKey, json.encode(notificationsList));
  }

  Future<List<NotificationModel>> getNotifications({int limit = 50}) async {
    final prefs = await SharedPreferences.getInstance();
    final local = await _getLocalNotifications(prefs);
    final remote = await _getRemoteNotifications(limit: limit);
    if (remote.isEmpty) {
      return local;
    }

    final merged = <String, NotificationModel>{};
    for (final item in remote) {
      final dedupeKey =
          item.transactionId != null && item.transactionId!.trim().isNotEmpty
          ? '${item.type}:${item.transactionId}'
          : 'remote:${item.id}';
      if (!merged.containsKey(dedupeKey)) {
        merged[dedupeKey] = item;
      }
    }
    for (final item in local) {
      final dedupeKey =
          item.transactionId != null && item.transactionId!.trim().isNotEmpty
          ? '${item.type}:${item.transactionId}'
          : 'local:${item.id}';
      if (!merged.containsKey(dedupeKey)) {
        merged[dedupeKey] = item;
      }
    }

    final list = merged.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<int> getUnreadCount({int limit = 100}) async {
    final list = await getNotifications(limit: limit);
    final seenAt = await _getSeenAt();
    if (seenAt == null) {
      return list.length;
    }
    return list.where((item) => item.date.isAfter(seenAt)).length;
  }

  Future<void> markNotificationsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = await _resolveCurrentUserKey(prefs);
    if (userKey == null || userKey.isEmpty) {
      return;
    }
    await prefs.setString(
      '${_keyNotificationsSeenAt}_$userKey',
      DateTime.now().toIso8601String(),
    );
  }

  Future<Map<String, dynamic>> getNotificationSettings() async {
    try {
      final response = await _authorizedGet(
        '${AppConfig.apiBaseUrl}/v1/notifications/settings',
      );
      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể tải cài đặt thông báo.',
          ),
        };
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': true,
        'settings': {
          'appEnabled': body['appEnabled'] == true,
          'emailEnabled': body['emailEnabled'] == true,
          'smsEnabled': body['smsEnabled'] == true,
          'updatedAt': '${body['updatedAt'] ?? ''}',
        },
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể tải cài đặt thông báo.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> updateNotificationSettings({
    bool? emailEnabled,
    bool? smsEnabled,
  }) async {
    if (emailEnabled == null && smsEnabled == null) {
      return {'success': false, 'message': 'Không có thay đổi cài đặt.'};
    }

    final body = <String, dynamic>{};
    if (emailEnabled != null) {
      body['emailEnabled'] = emailEnabled;
    }
    if (smsEnabled != null) {
      body['smsEnabled'] = smsEnabled;
    }

    try {
      final response = await _authorizedPatchJson(
        '${AppConfig.apiBaseUrl}/v1/notifications/settings',
        body,
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể cập nhật cài đặt thông báo.',
          ),
        };
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': true,
        'settings': {
          'appEnabled': payload['appEnabled'] == true,
          'emailEnabled': payload['emailEnabled'] == true,
          'smsEnabled': payload['smsEnabled'] == true,
          'updatedAt': '${payload['updatedAt'] ?? ''}',
        },
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể cập nhật cài đặt thông báo.',
        ),
      };
    }
  }

  Future<List<NotificationModel>> _getLocalNotifications(
    SharedPreferences prefs,
  ) async {
    final userKey = await _resolveCurrentUserKey(prefs);
    if (userKey == null || userKey.isEmpty) {
      return [];
    }
    final notificationsJson =
        prefs.getString('${_keyNotifications}_$userKey') ?? '[]';
    final List<dynamic> notificationsList = json.decode(notificationsJson);
    return notificationsList
        .whereType<Map>()
        .map(
          (json) => NotificationModel.fromJson(Map<String, dynamic>.from(json)),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<List<NotificationModel>> _getRemoteNotifications({
    int limit = 50,
  }) async {
    try {
      final response = await _authorizedGet(
        '${AppConfig.apiBaseUrl}/v1/notifications?limit=$limit&offset=0',
      );
      if (response.statusCode >= 400) {
        return [];
      }
      final body = jsonDecode(response.body);
      final itemsRaw = body is Map ? body['items'] : null;
      if (itemsRaw is! List) {
        return [];
      }

      final output = <NotificationModel>[];
      for (final raw in itemsRaw) {
        if (raw is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(raw);
        output.add(_fromRemote(map));
      }
      output.sort((a, b) => b.date.compareTo(a.date));
      return output;
    } on SessionExpiredException {
      return [];
    } catch (_) {
      return [];
    }
  }

  NotificationModel _fromRemote(Map<String, dynamic> raw) {
    final payloadJson = '${raw['payloadJson'] ?? ''}'.trim();
    String? transactionId;
    String? amount;
    String type = 'transfer';
    String eventType = '';

    if (payloadJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(payloadJson);
        if (parsed is Map) {
          final payload = Map<String, dynamic>.from(parsed);
          eventType = '${payload['eventType'] ?? ''}'.trim();
          final tx = '${payload['transactionId'] ?? ''}'.trim();
          if (tx.isNotEmpty) {
            transactionId = tx;
          }
          final amountValue = payload['amount'];
          if (amountValue != null) {
            amount = '$amountValue';
          }
        }
      } catch (_) {
        // Ignore invalid payloadJson and use top-level fields only.
      }
    }

    final createdAt = '${raw['createdAt'] ?? ''}'.trim();
    final date = DateTime.tryParse(createdAt) ?? DateTime.now();
    final title = '${raw['title'] ?? 'Biến động số dư'}'.trim();
    if (eventType == 'transaction.chain.completed') {
      type = 'chain_complete';
    } else if (title.toLowerCase().contains('hoa don') ||
        title.toLowerCase().contains('hóa đơn')) {
      type = 'chain_complete';
    }

    return NotificationModel(
      id: '${raw['id'] ?? DateTime.now().millisecondsSinceEpoch}',
      title: title.isEmpty ? 'Biến động số dư' : title,
      type: type,
      date: date,
      amount: amount,
      transactionId: transactionId,
    );
  }

  Future<void> clearNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = await _resolveCurrentUserKey(prefs);
    if (userKey == null || userKey.isEmpty) {
      return;
    }
    await prefs.remove('${_keyNotifications}_$userKey');
  }

  Future<String?> _resolveCurrentUserKey(SharedPreferences prefs) async {
    final raw = (prefs.getString('current_user') ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return null;
      }
      final user = Map<String, dynamic>.from(decoded);
      final phone = '${user['phone'] ?? ''}'.trim();
      if (phone.isNotEmpty) {
        return phone;
      }
      final userId = '${user['id'] ?? ''}'.trim();
      if (userId.isNotEmpty) {
        return userId;
      }
      final email = '${user['email'] ?? ''}'.trim();
      if (email.isNotEmpty) {
        return email;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> _getSeenAt() async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = await _resolveCurrentUserKey(prefs);
    if (userKey == null || userKey.isEmpty) {
      return null;
    }
    final raw = (prefs.getString('${_keyNotificationsSeenAt}_$userKey') ?? '')
        .trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  Future<http.Response> _authorizedGet(
    String url, {
    Map<String, String>? headers,
  }) {
    return _performAuthorizedRequest(
      (token) => _get(url, headers: _withAuthorization(token, headers)),
    );
  }

  Future<http.Response> _authorizedPatchJson(
    String url,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) {
    return _performAuthorizedRequest(
      (token) =>
          _patchJson(url, body, headers: _withAuthorization(token, headers)),
    );
  }

  Future<http.Response> _performAuthorizedRequest(
    Future<http.Response> Function(String accessToken) requestBuilder,
  ) async {
    final accessToken = await _authService.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      await _authService.expireSessionAndNotify();
      throw SessionExpiredException(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      );
    }

    var response = await requestBuilder(accessToken);
    if (!_isAuthExpiredStatus(response.statusCode)) {
      return response;
    }

    final refreshed = await _authService.refreshSession(
      triggerExpiredEventOnFailure: false,
    );
    if (refreshed['success'] == true) {
      final renewedAccessToken = await _authService.getAccessToken();
      if (renewedAccessToken != null && renewedAccessToken.isNotEmpty) {
        response = await requestBuilder(renewedAccessToken);
        if (!_isAuthExpiredStatus(response.statusCode)) {
          return response;
        }
      }
    }

    await _authService.expireSessionAndNotify(
      message:
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại để tiếp tục.',
    );
    throw SessionExpiredException(
      'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
    );
  }

  bool _isAuthExpiredStatus(int statusCode) {
    return statusCode == 401;
  }

  Map<String, String> _withAuthorization(
    String token,
    Map<String, String>? headers,
  ) {
    return {if (headers != null) ...headers, 'Authorization': 'Bearer $token'};
  }

  Future<http.Response> _get(
    String url, {
    required Map<String, String> headers,
  }) async {
    return http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 12));
  }

  Future<http.Response> _patchJson(
    String url,
    Map<String, dynamic> body, {
    required Map<String, String> headers,
  }) async {
    return http
        .patch(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
  }
}
