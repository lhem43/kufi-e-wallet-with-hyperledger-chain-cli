import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'app_config.dart';
import 'auth_service.dart';
import 'error_message.dart';
import 'notification_service.dart';
import 'session_expired_exception.dart';

class UserService {
  static const String _keyTransactions = 'local_transactions';
  static const String _keyDeviceId = 'device_id';
  static const String _keyFundingSourceSecrets = 'funding_source_secrets';
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  String? _deviceIdCache;

  Future<Map<String, dynamic>> getUserByPhone(String phoneNumber) async {
    try {
      final normalizedPhone = _normalizePhone(phoneNumber);
      if (!_isLookupReadyPhone(normalizedPhone)) {
        return {'success': false, 'message': 'Số điện thoại chưa đầy đủ'};
      }

      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/auth/recipients/resolve-phone',
        {'phone': normalizedPhone},
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể tra cứu người nhận lúc này.',
          ),
        };
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final found = body['found'] == true;
      if (!found) {
        return {'success': true, 'found': false};
      }
      final recipient = Map<String, dynamic>.from(
        (body['recipient'] as Map?) ?? <String, dynamic>{},
      );
      return {'success': true, 'found': true, 'recipient': recipient};
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể tra cứu người nhận lúc này.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> issueTransferQrToken() async {
    try {
      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/auth/qr-transfer/issue',
        {},
        headers: const {'Content-Type': 'application/json'},
      );
      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể tạo mã QR lúc này.',
          ),
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final token = '${body['token'] ?? ''}'.trim();
      final expiresIn = body['expiresIn'] is int
          ? body['expiresIn'] as int
          : int.tryParse('${body['expiresIn'] ?? ''}') ?? 0;
      if (token.isEmpty) {
        return {
          'success': false,
          'message': 'Không thể tạo mã QR bảo mật lúc này.',
        };
      }
      return {
        'success': true,
        'token': token,
        'expiresIn': expiresIn <= 0 ? 120 : expiresIn,
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể tạo mã QR lúc này.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> resolveTransferQrToken(String tokenRaw) async {
    try {
      final token = tokenRaw.trim();
      if (token.isEmpty) {
        return {'success': false, 'message': 'Mã QR không hợp lệ.'};
      }

      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/auth/qr-transfer/resolve',
        {'token': token},
        headers: const {'Content-Type': 'application/json'},
      );
      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'QR không hợp lệ hoặc đã hết hạn.',
          ),
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final found = body['found'] == true;
      if (!found) {
        return {'success': true, 'found': false};
      }

      final recipient = Map<String, dynamic>.from(
        (body['recipient'] as Map?) ?? <String, dynamic>{},
      );
      return {'success': true, 'found': true, 'recipient': recipient};
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể xử lý mã QR lúc này.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> getMyKycProfile() async {
    const endpoints = <String>[
      '/v1/auth/kyc/profile',
      '/v1/auth/kyc',
      '/v1/auth/profile/kyc',
    ];
    try {
      http.Response? lastResponse;
      for (final endpoint in endpoints) {
        final response = await _authorizedGet(
          '${AppConfig.apiBaseUrl}$endpoint',
        );
        lastResponse = response;
        if (response.statusCode == 404 || response.statusCode == 405) {
          continue;
        }
        if (response.statusCode >= 400) {
          return {
            'success': false,
            'message': ErrorMessage.fromHttpBody(
              response.body,
              statusCode: response.statusCode,
              defaultMessage: 'Không thể tải hồ sơ KYC.',
            ),
          };
        }

        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final profile = body['profile'] is Map
              ? Map<String, dynamic>.from(body['profile'] as Map)
              : Map<String, dynamic>.from(body);
          if (!profile.containsKey('nationalIdMasked') &&
              '${profile['nationalId'] ?? ''}'.trim().isNotEmpty) {
            final nationalId = '${profile['nationalId']}';
            if (nationalId.length > 4) {
              profile['nationalIdMasked'] =
                  '${'*' * (nationalId.length - 4)}${nationalId.substring(nationalId.length - 4)}';
            }
          }
          return {'success': true, 'profile': profile};
        }
        return {'success': false, 'message': 'Dữ liệu KYC không hợp lệ.'};
      }

      return {
        'success': false,
        'message': ErrorMessage.fromHttpBody(
          lastResponse?.body ?? '',
          statusCode: lastResponse?.statusCode,
          defaultMessage: 'KYC chưa sẵn sàng trên hệ thống.',
        ),
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể tải hồ sơ KYC.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> submitKyc({
    required String fullName,
    required String nationalId,
    required String dateOfBirth,
    String? idIssueDate,
    String? idIssuePlace,
    required String residentialAddress,
  }) async {
    const endpoints = <String>['/v1/auth/kyc/submit', '/v1/auth/kyc'];
    final payload = <String, dynamic>{
      'fullName': fullName.trim(),
      'nationalId': nationalId.trim(),
      'dateOfBirth': dateOfBirth.trim(),
      'idIssueDate': idIssueDate?.trim(),
      'idIssuePlace': idIssuePlace?.trim(),
      'residentialAddress': residentialAddress.trim(),
    }..removeWhere((key, value) => value == null || '$value'.trim().isEmpty);

    try {
      http.Response? lastResponse;
      for (final endpoint in endpoints) {
        final response = await _authorizedPostJson(
          '${AppConfig.apiBaseUrl}$endpoint',
          payload,
          headers: const {'Content-Type': 'application/json'},
        );
        lastResponse = response;
        if (response.statusCode == 404 || response.statusCode == 405) {
          continue;
        }
        if (response.statusCode >= 400) {
          return {
            'success': false,
            'message': ErrorMessage.fromHttpBody(
              response.body,
              statusCode: response.statusCode,
              defaultMessage: 'Không thể gửi hồ sơ KYC.',
            ),
          };
        }

        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final profile = body['profile'] is Map
              ? Map<String, dynamic>.from(body['profile'] as Map)
              : Map<String, dynamic>.from(body);
          if (profile.isNotEmpty) {
            await _authService.mergeCurrentUser(
              _buildSessionPatchFromProfile(profile),
            );
          }
          return {
            'success': true,
            'message': '${body['message'] ?? 'Đã gửi hồ sơ KYC.'}',
            'profile': profile,
          };
        }
        return {'success': true, 'message': 'Đã gửi hồ sơ KYC.'};
      }

      return {
        'success': false,
        'message': ErrorMessage.fromHttpBody(
          lastResponse?.body ?? '',
          statusCode: lastResponse?.statusCode,
          defaultMessage: 'KYC chưa sẵn sàng trên hệ thống.',
        ),
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể gửi hồ sơ KYC.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> getMyProfile() async {
    try {
      final response = await _authorizedGet(
        '${AppConfig.apiBaseUrl}/v1/auth/profile',
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể tải thông tin cá nhân.',
          ),
        };
      }

      final profile = jsonDecode(response.body) as Map<String, dynamic>;
      await _authService.mergeCurrentUser(
        _buildSessionPatchFromProfile(profile),
      );

      return {'success': true, 'profile': profile};
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể tải thông tin cá nhân.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> updateMyProfile({
    required String displayName,
    required String phone,
  }) async {
    try {
      final normalizedPhone = _normalizePhone(phone);
      if (!_isLookupReadyPhone(normalizedPhone)) {
        return {
          'success': false,
          'message': 'Số điện thoại chưa đầy đủ hoặc không hợp lệ.',
        };
      }

      final cleanName = displayName.trim();
      if (cleanName.length < 2) {
        return {
          'success': false,
          'message': 'Tên hiển thị phải có ít nhất 2 ký tự.',
        };
      }

      final response = await _authorizedPatchJson(
        '${AppConfig.apiBaseUrl}/v1/auth/profile',
        {'displayName': cleanName, 'phone': normalizedPhone},
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể cập nhật thông tin cá nhân.',
          ),
        };
      }

      final profile = jsonDecode(response.body) as Map<String, dynamic>;
      await _authService.mergeCurrentUser(
        _buildSessionPatchFromProfile(profile),
      );

      return {
        'success': true,
        'message': 'Cập nhật thông tin thành công.',
        'profile': profile,
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể cập nhật thông tin cá nhân.',
        ),
      };
    }
  }

  Future<double> getCurrentUserBalance() async {
    try {
      final wallet = await _getOrCreateWallet();
      if (wallet == null) {
        return 0;
      }
      return _toDouble(wallet['balance']);
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, dynamic>> issueTransferOtp() async {
    try {
      final deviceId = await _getOrCreateDeviceId();

      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/auth/otp/issue',
        {},
        headers: {'Content-Type': 'application/json', 'x-device-id': deviceId},
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể cấp OTP lúc này.',
          ),
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': true,
        'otpCode': '${body['otpCode'] ?? ''}',
        'expiresIn': body['expiresIn'] ?? 0,
        'deliveryMode': '${body['deliveryMode'] ?? ''}',
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể cấp OTP lúc này.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> assessTransferRisk({
    required String recipientUserId,
    required String recipientIdentifier,
    required int amount,
    String currency = 'VND',
    bool isExternal = false,
    String externalPartner = '',
    String externalAccountNo = '',
  }) async {
    try {
      final toUserId = recipientUserId.trim();
      if (toUserId.isEmpty) {
        return {
          'success': false,
          'message': 'Thiếu thông tin người nhận. Vui lòng tra cứu lại.',
        };
      }
      if (amount <= 0) {
        return {'success': false, 'message': 'Số tiền không hợp lệ.'};
      }

      final deviceId = await _getOrCreateDeviceId();
      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/transactions/transfers/risk-assessment',
        {
          'toUserId': toUserId,
          'recipient': recipientIdentifier.trim(),
          'amount': amount,
          'currency': currency.trim().isEmpty ? 'VND' : currency.trim(),
          'isExternal': isExternal,
          'externalPartner': externalPartner.trim(),
          'externalAccountNo': externalAccountNo.trim(),
        },
        headers: {'Content-Type': 'application/json', 'x-device-id': deviceId},
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể đánh giá rủi ro giao dịch lúc này.',
          ),
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final reasonsRaw = body['reasons'];
      final reasons = reasonsRaw is List
          ? reasonsRaw.map((e) => '$e').where((e) => e.isNotEmpty).toList()
          : <String>[];

      return {
        'success': true,
        'requiresStepUp': body['requiresStepUp'] == true,
        'reasons': reasons,
        'verdict': '${body['verdict'] ?? ''}',
        'probability': body['probability'] ?? 0,
        'threshold': body['threshold'] ?? 0,
        'modelVersion': '${body['modelVersion'] ?? ''}',
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể đánh giá rủi ro giao dịch lúc này.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> transferMoney({
    required String recipientUserId,
    required String recipientIdentifier,
    required int amount,
    required String message,
    required String otpCode,
    String? idempotencyKey,
    String? stepUpToken,
  }) async {
    try {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) {
        return {
          'success': false,
          'message': 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
        };
      }

      final resolvedIdempotencyKey = (idempotencyKey ?? '').trim().isNotEmpty
          ? idempotencyKey!.trim()
          : _buildIdempotencyKey();
      final toUserId = recipientUserId.trim();
      if (toUserId.isEmpty) {
        return {
          'success': false,
          'message': 'Thiếu thông tin người nhận. Vui lòng tra cứu lại.',
        };
      }
      final requestBody = {
        'toUserId': toUserId,
        'recipient': recipientIdentifier.trim(),
        'amount': amount,
        'currency': 'VND',
        'memo': message.trim(),
        'otpCode': otpCode.trim(),
        'idempotencyKey': resolvedIdempotencyKey,
      };
      final deviceId = await _getOrCreateDeviceId();

      final headers = {
        'Content-Type': 'application/json',
        'x-device-id': deviceId,
      };
      final normalizedStepUpToken = (stepUpToken ?? '').trim();
      if (normalizedStepUpToken.isNotEmpty) {
        headers['x-step-up-token'] = normalizedStepUpToken;
      }

      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/transactions/transfers',
        requestBody,
        headers: headers,
      );

      if (_shouldRetryWithStepUp(response)) {
        final challenge = _parseStepUpChallenge(response.body);
        return {
          'success': false,
          'requiresStepUp': true,
          'idempotencyKey': resolvedIdempotencyKey,
          'message':
              '${challenge['message'] ?? 'Giao dịch cần xác thực bổ sung.'}',
          'reasons': challenge['reasons'] ?? const <String>[],
          'risk': challenge,
        };
      }

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Chuyển tiền thất bại. Vui lòng thử lại.',
          ),
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      Map<String, dynamic>? receipt;
      final receiptJsonRaw = '${body['receiptJson'] ?? ''}';
      if (receiptJsonRaw.isNotEmpty) {
        try {
          receipt = jsonDecode(receiptJsonRaw) as Map<String, dynamic>;
        } catch (_) {
          receipt = null;
        }
      }

      await _saveLocalTransaction({
        'transactionId': '${body['transactionId'] ?? ''}',
        'recipient': recipientIdentifier.trim(),
        'recipientDisplayName':
            '${(body['recipient'] as Map?)?['displayName'] ?? ''}',
        'recipientPhone': '${(body['recipient'] as Map?)?['phone'] ?? ''}',
        'fromUserId': '${currentUser['id'] ?? currentUser['userId'] ?? ''}',
        'toUserId': '${body['toUserId'] ?? toUserId}',
        'direction': 'OUT',
        'amount': amount,
        'message': message.trim(),
        'date': '${body['createdAt'] ?? ''}'.trim().isEmpty
            ? DateTime.now().toIso8601String()
            : '${body['createdAt']}',
        'status': '${body['status'] ?? ''}',
        'settlementStatus': '${body['settlementStatus'] ?? ''}',
        'chainStatus': '${body['chainStatus'] ?? ''}',
        'onChainState': _chainUiStatus('${body['chainStatus'] ?? ''}'),
        'receipt': receipt,
        'errorCode': '${body['errorCode'] ?? ''}',
        'errorMessage': '${body['errorMessage'] ?? ''}',
        'chainCompleteNotified': _isChainComplete(
          '${body['chainStatus'] ?? ''}',
        ),
      });

      return {
        'success': true,
        'message': 'Chuyển tiền thành công',
        'data': body,
        'receipt': receipt,
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể thực hiện chuyển tiền lúc này.',
        ),
      };
    }
  }

  Future<List<Map<String, dynamic>>> getFundingSources() async {
    try {
      final response = await _authorizedGet(
        '${AppConfig.apiBaseUrl}/v1/transactions/funding-sources',
      );
      if (response.statusCode >= 400) {
        return [];
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['items'] is! List) {
        return [];
      }
      return (body['items'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> createFundingSource({
    required String provider,
    required String accountRef,
    String? displayName,
    String? providerToken,
  }) async {
    try {
      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/transactions/funding-sources',
        {
          'provider': provider.trim(),
          'accountRef': accountRef.trim(),
          'displayName': displayName?.trim() ?? '',
          'providerToken': providerToken?.trim() ?? '',
        },
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể liên kết nguồn tiền.',
          ),
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final fundingSourceId = '${body['fundingSourceId'] ?? body['id'] ?? ''}'
          .trim();
      if (fundingSourceId.isNotEmpty && accountRef.trim().isNotEmpty) {
        await saveFundingSourceSecret(
          fundingSourceId: fundingSourceId,
          accountRef: accountRef.trim(),
        );
      }
      return {'success': true, 'data': body};
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể liên kết nguồn tiền.',
        ),
      };
    }
  }

  Future<void> saveFundingSourceSecret({
    required String fundingSourceId,
    required String accountRef,
  }) async {
    final id = fundingSourceId.trim();
    final value = accountRef.trim();
    if (id.isEmpty || value.isEmpty) {
      return;
    }

    final key = await _fundingSecretsStorageKey();
    if (key.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key) ?? '{}';
    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    decoded[id] = value;
    await prefs.setString(key, jsonEncode(decoded));
  }

  Future<String?> getFundingSourceSecret(String fundingSourceId) async {
    final id = fundingSourceId.trim();
    if (id.isEmpty) {
      return null;
    }

    final key = await _fundingSecretsStorageKey();
    if (key.isEmpty) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key) ?? '{}';
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final secret = '${decoded[id] ?? ''}'.trim();
      return secret.isEmpty ? null : secret;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> topupFromFundingSource({
    required String fundingSourceId,
    required int amount,
    String memo = '',
    String? stepUpToken,
    String? idempotencyKey,
  }) async {
    try {
      final source = await _findFundingSourceById(fundingSourceId);
      final providerCode = '${source?['provider'] ?? ''}'.trim().toUpperCase();
      final providerName = _providerDisplayName(providerCode);
      final resolvedIdempotencyKey = (idempotencyKey ?? '').trim().isNotEmpty
          ? idempotencyKey!.trim()
          : _buildIdempotencyKey();
      final deviceId = await _getOrCreateDeviceId();
      final headers = {
        'Content-Type': 'application/json',
        'x-device-id': deviceId,
      };
      final normalizedStepUpToken = (stepUpToken ?? '').trim();
      if (normalizedStepUpToken.isNotEmpty) {
        headers['x-step-up-token'] = normalizedStepUpToken;
      }

      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/transactions/topups',
        {
          'fundingSourceId': fundingSourceId.trim(),
          'amount': amount,
          'currency': 'VND',
          'memo': memo.trim(),
          'idempotencyKey': resolvedIdempotencyKey,
        },
        headers: headers,
      );

      if (_shouldRetryWithStepUp(response)) {
        final challenge = _parseStepUpChallenge(response.body);
        return {
          'success': false,
          'requiresStepUp': true,
          'idempotencyKey': resolvedIdempotencyKey,
          'message':
              '${challenge['message'] ?? 'Giao dịch cần xác thực bổ sung.'}',
          'reasons': challenge['reasons'] ?? const <String>[],
          'risk': challenge,
        };
      }

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể tạo giao dịch nạp tiền.',
          ),
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final receipt = _parseReceiptJson('${body['receiptJson'] ?? ''}');
      final txId = '${body['transactionId'] ?? ''}'.trim();
      await _saveLocalTransaction({
        'transactionId': txId,
        'type': '${body['type'] ?? 'DEPOSIT'}',
        'direction': 'IN',
        'externalPartner': providerCode,
        'senderDisplayName': providerName,
        'counterpartyLabel': providerName,
        'amount': amount,
        'message': memo.trim().isEmpty
            ? 'Nạp tiền qua $providerName'
            : memo.trim(),
        'date': '${body['createdAt'] ?? DateTime.now().toIso8601String()}',
        'status': '${body['status'] ?? ''}',
        'settlementStatus': '${body['settlementStatus'] ?? ''}',
        'chainStatus': '${body['chainStatus'] ?? ''}',
        'onChainState': _chainUiStatus('${body['chainStatus'] ?? ''}'),
        'receipt': receipt,
        'errorCode': '${body['errorCode'] ?? ''}',
        'errorMessage': '${body['errorMessage'] ?? ''}',
        'chainCompleteNotified': _isChainComplete(
          '${body['chainStatus'] ?? ''}',
        ),
        'completionNotified':
            '${body['status'] ?? ''}'.trim().toUpperCase() == 'COMPLETED',
      });

      if (txId.isNotEmpty) {
        await _pushLocalCashflowNotification(
          transactionId: txId,
          amount: amount,
          providerName: providerName,
          isTopup: true,
          completed:
              '${body['status'] ?? ''}'.trim().toUpperCase() == 'COMPLETED',
        );
      }

      return {'success': true, 'data': body};
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể tạo giao dịch nạp tiền.',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> withdrawToFundingSource({
    required String fundingSourceId,
    required int amount,
    String memo = '',
    String? stepUpToken,
    String? idempotencyKey,
  }) async {
    try {
      final source = await _findFundingSourceById(fundingSourceId);
      final providerCode = '${source?['provider'] ?? ''}'.trim().toUpperCase();
      final providerName = _providerDisplayName(providerCode);
      final resolvedIdempotencyKey = (idempotencyKey ?? '').trim().isNotEmpty
          ? idempotencyKey!.trim()
          : _buildIdempotencyKey();
      final deviceId = await _getOrCreateDeviceId();
      final headers = {
        'Content-Type': 'application/json',
        'x-device-id': deviceId,
      };
      final normalizedStepUpToken = (stepUpToken ?? '').trim();
      if (normalizedStepUpToken.isNotEmpty) {
        headers['x-step-up-token'] = normalizedStepUpToken;
      }

      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/transactions/withdrawals',
        {
          'fundingSourceId': fundingSourceId.trim(),
          'amount': amount,
          'currency': 'VND',
          'memo': memo.trim(),
          'idempotencyKey': resolvedIdempotencyKey,
        },
        headers: headers,
      );

      if (_shouldRetryWithStepUp(response)) {
        final challenge = _parseStepUpChallenge(response.body);
        return {
          'success': false,
          'requiresStepUp': true,
          'idempotencyKey': resolvedIdempotencyKey,
          'message':
              '${challenge['message'] ?? 'Giao dịch cần xác thực bổ sung.'}',
          'reasons': challenge['reasons'] ?? const <String>[],
          'risk': challenge,
        };
      }

      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể tạo giao dịch rút tiền.',
          ),
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final receipt = _parseReceiptJson('${body['receiptJson'] ?? ''}');
      final txId = '${body['transactionId'] ?? ''}'.trim();
      await _saveLocalTransaction({
        'transactionId': txId,
        'type': '${body['type'] ?? 'WITHDRAWAL'}',
        'direction': 'OUT',
        'externalPartner': providerCode,
        'recipientDisplayName': providerName,
        'counterpartyLabel': providerName,
        'amount': amount,
        'message': memo.trim().isEmpty
            ? 'Rút tiền qua $providerName'
            : memo.trim(),
        'date': '${body['createdAt'] ?? DateTime.now().toIso8601String()}',
        'status': '${body['status'] ?? ''}',
        'settlementStatus': '${body['settlementStatus'] ?? ''}',
        'chainStatus': '${body['chainStatus'] ?? ''}',
        'onChainState': _chainUiStatus('${body['chainStatus'] ?? ''}'),
        'receipt': receipt,
        'errorCode': '${body['errorCode'] ?? ''}',
        'errorMessage': '${body['errorMessage'] ?? ''}',
        'chainCompleteNotified': _isChainComplete(
          '${body['chainStatus'] ?? ''}',
        ),
        'completionNotified':
            '${body['status'] ?? ''}'.trim().toUpperCase() == 'COMPLETED',
      });

      if (txId.isNotEmpty) {
        await _pushLocalCashflowNotification(
          transactionId: txId,
          amount: amount,
          providerName: providerName,
          isTopup: false,
          completed:
              '${body['status'] ?? ''}'.trim().toUpperCase() == 'COMPLETED',
        );
      }

      return {'success': true, 'data': body};
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể tạo giao dịch rút tiền.',
        ),
      };
    }
  }

  Future<List<Map<String, dynamic>>> syncLocalTransactions() async {
    try {
      final currentUser = await _authService.getCurrentUser();
      final transactions = await getUserTransactions();
      if (transactions.isEmpty) {
        return transactions;
      }

      var changed = false;
      final candidates = transactions
          .where((tx) => _shouldSyncTransaction(tx))
          .take(40)
          .toList();

      for (final tx in candidates) {
        final transactionId = '${tx['transactionId'] ?? ''}'.trim();
        if (transactionId.isEmpty) {
          continue;
        }

        try {
          final response = await _authorizedGet(
            '${AppConfig.apiBaseUrl}/v1/transactions/$transactionId',
          );
          if (response.statusCode >= 400) {
            continue;
          }

          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final previousChainStatus = '${tx['chainStatus'] ?? ''}';
          final nextChainStatus = '${body['chainStatus'] ?? ''}';
          final wasComplete = _isChainComplete(previousChainStatus);
          final isComplete = _isChainComplete(nextChainStatus);
          final alreadyNotified = tx['chainCompleteNotified'] == true;

          tx['status'] = '${body['status'] ?? tx['status'] ?? ''}';
          tx['type'] = '${body['type'] ?? tx['type'] ?? ''}';
          tx['settlementStatus'] =
              '${body['settlementStatus'] ?? tx['settlementStatus'] ?? ''}';
          tx['chainStatus'] = nextChainStatus;
          tx['onChainState'] = _chainUiStatus(nextChainStatus);
          final fromUserId = '${body['fromUserId'] ?? tx['fromUserId'] ?? ''}'
              .trim();
          final toUserId = '${body['toUserId'] ?? tx['toUserId'] ?? ''}'.trim();
          tx['fromUserId'] = fromUserId;
          tx['toUserId'] = toUserId;
          tx['direction'] = _resolveDirection(
            type: '${tx['type'] ?? ''}',
            fromUserId: fromUserId,
            toUserId: toUserId,
            currentUserId:
                '${currentUser?['id'] ?? currentUser?['userId'] ?? ''}'.trim(),
            fallback: '${tx['direction'] ?? ''}',
          );
          tx['errorCode'] = '${body['errorCode'] ?? tx['errorCode'] ?? ''}';
          tx['errorMessage'] =
              '${body['errorMessage'] ?? tx['errorMessage'] ?? ''}';
          tx['externalPartner'] =
              '${body['externalPartner'] ?? tx['externalPartner'] ?? ''}';
          tx['externalAccountNo'] =
              '${body['externalAccountNo'] ?? tx['externalAccountNo'] ?? ''}';
          tx['updatedAt'] =
              '${body['updatedAt'] ?? DateTime.now().toIso8601String()}';

          final parsedReceipt = _parseReceiptJson(
            '${body['receiptJson'] ?? ''}',
          );
          if (parsedReceipt != null) {
            tx['receipt'] = parsedReceipt;
          }

          if (isComplete) {
            tx['chainCompleteNotified'] = true;
          }
          if (!wasComplete && isComplete && !alreadyNotified) {
            tx['chainCompleteNotified'] = true;
          }

          final nowCompleted =
              '${tx['status'] ?? ''}'.trim().toUpperCase() == 'COMPLETED';
          final wasCompletionNotified = tx['completionNotified'] == true;
          if (nowCompleted && !wasCompletionNotified) {
            final amount = _toInt(tx['amount']);
            final providerName = _providerDisplayName(
              '${tx['externalPartner'] ?? ''}',
            );
            final isTopup =
                '${tx['type'] ?? ''}'.trim().toUpperCase() == 'DEPOSIT';
            await _pushLocalCashflowNotification(
              transactionId: transactionId,
              amount: amount,
              providerName: providerName,
              isTopup: isTopup,
              completed: true,
            );
            tx['completionNotified'] = true;
          }
          changed = true;
        } catch (_) {
          // Keep local state when network or decode fails.
        }
      }

      if (changed) {
        await _saveTransactions(transactions);
      }
      return transactions;
    } on SessionExpiredException {
      return getUserTransactions();
    }
  }

  Future<Map<String, dynamic>> getTransactionById(String transactionId) async {
    final txId = transactionId.trim();
    if (txId.isEmpty) {
      return {'success': false, 'message': 'transactionId is required'};
    }

    try {
      final response = await _authorizedGet(
        '${AppConfig.apiBaseUrl}/v1/transactions/$txId',
      );
      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể tải trạng thái giao dịch.',
          ),
        };
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        return {
          'success': false,
          'message': 'Dữ liệu trạng thái giao dịch không hợp lệ.',
        };
      }
      return {'success': true, 'data': body};
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể tải trạng thái giao dịch.',
        ),
      };
    }
  }

  bool _shouldRetryWithStepUp(http.Response response) {
    if (response.statusCode != 403) {
      return false;
    }
    final body = response.body.trim().toLowerCase();
    return body.contains('step-up verification required') ||
        (body.contains('step-up') && body.contains('required'));
  }

  Future<List<Map<String, dynamic>>> getUserTransactions() async {
    final currentUser = await _authService.getCurrentUser();
    final currentUserId =
        '${currentUser?['id'] ?? currentUser?['userId'] ?? ''}'.trim();
    if (currentUserId.isEmpty) {
      return [];
    }

    final stored = await _loadStoredTransactionsForCurrentUser();
    final remote = await _fetchRemoteTransactions(currentUserId);
    final merged = _mergeTransactions(
      primary: remote,
      secondary: stored,
      currentUserId: currentUserId,
    );
    if (merged.isNotEmpty) {
      await _saveTransactions(merged);
    }
    return merged;
  }

  Future<List<Map<String, dynamic>>> _fetchRemoteTransactions(
    String currentUserId,
  ) async {
    try {
      final response = await _authorizedGet(
        '${AppConfig.apiBaseUrl}/v1/transactions?limit=80&offset=0&includeFailed=false',
      );
      if (response.statusCode >= 400) {
        return [];
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['items'] is! List) {
        return [];
      }
      final items = (body['items'] as List).whereType<Map>().map((raw) {
        final item = Map<String, dynamic>.from(raw);
        final fromUserId = '${item['fromUserId'] ?? ''}'.trim();
        final toUserId = '${item['toUserId'] ?? ''}'.trim();
        final direction = _resolveDirection(
          type: '${item['type'] ?? ''}',
          fromUserId: fromUserId,
          toUserId: toUserId,
          currentUserId: currentUserId,
          fallback: '',
        );
        final amount = _toInt(item['amount']);
        final receipt = _parseReceiptJson('${item['receiptJson'] ?? ''}');
        return <String, dynamic>{
          'transactionId': '${item['transactionId'] ?? ''}',
          'type': '${item['type'] ?? ''}',
          'recipient': '${item['recipient'] ?? ''}',
          'recipientDisplayName': '${item['recipientDisplayName'] ?? ''}',
          'recipientPhone': '${item['recipientPhone'] ?? ''}',
          'senderDisplayName': '${item['senderDisplayName'] ?? ''}',
          'externalPartner': '${item['externalPartner'] ?? ''}',
          'externalAccountNo': '${item['externalAccountNo'] ?? ''}',
          'fromUserId': fromUserId,
          'toUserId': toUserId,
          'direction': direction,
          'amount': amount,
          'message': '${item['memo'] ?? ''}',
          'date':
              '${item['createdAt'] ?? item['date'] ?? DateTime.now().toIso8601String()}',
          'status': '${item['status'] ?? ''}',
          'settlementStatus': '${item['settlementStatus'] ?? ''}',
          'chainStatus': '${item['chainStatus'] ?? ''}',
          'onChainState': _chainUiStatus('${item['chainStatus'] ?? ''}'),
          'receipt': receipt,
          'errorCode': '${item['errorCode'] ?? ''}',
          'errorMessage': '${item['errorMessage'] ?? ''}',
          'chainCompleteNotified': _isChainComplete(
            '${item['chainStatus'] ?? ''}',
          ),
          'completionNotified':
              '${item['status'] ?? ''}'.trim().toUpperCase() == 'COMPLETED',
          'updatedAt':
              '${item['updatedAt'] ?? item['createdAt'] ?? DateTime.now().toIso8601String()}',
        };
      }).toList();
      return items;
    } on SessionExpiredException {
      return [];
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _mergeTransactions({
    required List<Map<String, dynamic>> primary,
    required List<Map<String, dynamic>> secondary,
    required String currentUserId,
  }) {
    final byId = <String, Map<String, dynamic>>{};

    void upsert(Map<String, dynamic> tx) {
      final txId = '${tx['transactionId'] ?? ''}'.trim();
      if (txId.isEmpty) {
        return;
      }
      final fromUserId = '${tx['fromUserId'] ?? ''}'.trim();
      final toUserId = '${tx['toUserId'] ?? ''}'.trim();
      final related = fromUserId == currentUserId || toUserId == currentUserId;
      if (!related) {
        return;
      }
      final status = '${tx['status'] ?? ''}'.toUpperCase();
      final chainStatus = '${tx['chainStatus'] ?? ''}'.toUpperCase();
      final settlementStatus = '${tx['settlementStatus'] ?? ''}'.toUpperCase();
      final isFailed =
          status.contains('FAIL') ||
          chainStatus.contains('FAIL') ||
          settlementStatus.contains('FAIL');
      if (isFailed) {
        return;
      }

      final normalized = Map<String, dynamic>.from(tx);
      normalized['fromUserId'] = fromUserId;
      normalized['toUserId'] = toUserId;
      normalized['direction'] = _resolveDirection(
        type: '${tx['type'] ?? ''}',
        fromUserId: fromUserId,
        toUserId: toUserId,
        currentUserId: currentUserId,
        fallback: '${tx['direction'] ?? ''}',
      );
      normalized['onChainState'] = _chainUiStatus('${tx['chainStatus'] ?? ''}');
      byId[txId] = normalized;
    }

    for (final tx in primary) {
      upsert(tx);
    }
    for (final tx in secondary) {
      if (!byId.containsKey('${tx['transactionId'] ?? ''}'.trim())) {
        upsert(tx);
      }
    }

    final merged = byId.values.toList();
    merged.sort((a, b) {
      final aDate =
          DateTime.tryParse('${a['date'] ?? a['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          DateTime.tryParse('${b['date'] ?? b['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return merged;
  }

  Future<Map<String, dynamic>?> _getOrCreateWallet() async {
    try {
      final getResponse = await _authorizedGet(
        '${AppConfig.apiBaseUrl}/v1/wallets/VND',
      );

      if (getResponse.statusCode == 200) {
        return jsonDecode(getResponse.body) as Map<String, dynamic>;
      }

      final createResponse = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/wallets',
        {'currency': 'VND'},
        headers: const {'Content-Type': 'application/json'},
      );
      if (createResponse.statusCode == 200 ||
          createResponse.statusCode == 201) {
        return jsonDecode(createResponse.body) as Map<String, dynamic>;
      }
      return null;
    } on SessionExpiredException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocalTransaction(Map<String, dynamic> transaction) async {
    final list = await _loadStoredTransactionsForCurrentUser();
    final txId = '${transaction['transactionId'] ?? ''}'.trim();
    if (txId.isNotEmpty) {
      list.removeWhere((item) => '${item['transactionId'] ?? ''}' == txId);
    }
    list.insert(0, transaction);
    await _saveTransactions(list);
  }

  String _buildIdempotencyKey() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(1 << 30);
    return 'mobile-$now-$rand';
  }

  double _toDouble(dynamic value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    return double.tryParse('$value') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
  }

  Future<http.Response> _authorizedPostJson(
    String url,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) {
    return _performAuthorizedRequest(
      (token) =>
          _postJson(url, body, headers: _withAuthorization(token, headers)),
    );
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

  Future<http.Response> _postJson(
    String url,
    Map<String, dynamic> body, {
    required Map<String, String> headers,
  }) async {
    return http
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
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

  Map<String, dynamic> _parseStepUpChallenge(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        final body = Map<String, dynamic>.from(decoded);
        final reasonsRaw = body['reasons'];
        final reasons = reasonsRaw is List
            ? reasonsRaw.map((e) => '$e').where((e) => e.isNotEmpty).toList()
            : <String>[];
        return {
          'message': '${body['message'] ?? 'Giao dịch cần xác thực bổ sung.'}',
          'reasons': reasons,
          'verdict': '${body['verdict'] ?? ''}',
          'probability': body['probability'] ?? 0,
          'threshold': body['threshold'] ?? 0,
        };
      }
    } catch (_) {
      // Ignore malformed challenge payload.
    }
    return {
      'message': 'Giao dịch cần xác thực bổ sung.',
      'reasons': <String>[],
      'verdict': '',
      'probability': 0,
      'threshold': 0,
    };
  }

  Future<Map<String, dynamic>> issueStepUpToken({
    required String method,
    String otpCode = '',
  }) async {
    try {
      final deviceId = await _getOrCreateDeviceId();
      final response = await _authorizedPostJson(
        '${AppConfig.apiBaseUrl}/v1/auth/step-up/token',
        {
          'method': method.trim().isEmpty ? 'otp_email' : method.trim(),
          'otpCode': otpCode.trim(),
        },
        headers: {'Content-Type': 'application/json', 'x-device-id': deviceId},
      );
      if (response.statusCode >= 400) {
        return {
          'success': false,
          'message': ErrorMessage.fromHttpBody(
            response.body,
            statusCode: response.statusCode,
            defaultMessage: 'Không thể lấy step-up token.',
          ),
        };
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['challengeIssued'] == true) {
        return {
          'success': true,
          'challengeIssued': true,
          'method': '${body['method'] ?? method}',
          'deliveryMode': '${body['deliveryMode'] ?? ''}',
          'expiresIn': body['expiresIn'] ?? 0,
        };
      }
      final token = '${body['stepUpToken'] ?? ''}';
      if (token.isEmpty) {
        return {'success': false, 'message': 'Không lấy được step-up token'};
      }
      return {
        'success': true,
        'stepUpToken': token,
        'method': '${body['method'] ?? method}',
        'expiresIn': body['expiresIn'] ?? 0,
      };
    } on SessionExpiredException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessage.fromException(
          e,
          fallback: 'Không thể lấy step-up token.',
        ),
      };
    }
  }

  Future<String> _getOrCreateDeviceId() async {
    final cached = _deviceIdCache?.trim() ?? '';
    if (cached.isNotEmpty) {
      return cached;
    }
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getString(_keyDeviceId) ?? '').trim();
    if (existing.isNotEmpty) {
      _deviceIdCache = existing;
      return existing;
    }
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final randomPart = Random.secure().nextInt(1 << 32).toRadixString(16);
    final generated = 'flutter-$now-$randomPart';
    await prefs.setString(_keyDeviceId, generated);
    _deviceIdCache = generated;
    return generated;
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

  bool _isChainComplete(String chainStatusRaw) {
    final chainStatus = chainStatusRaw.trim().toUpperCase();
    return chainStatus == 'ANCHORED' ||
        chainStatus == 'COMPLETE' ||
        chainStatus == 'COMPLETED';
  }

  bool _isSettlementPending(String settlementStatusRaw) {
    final settlementStatus = settlementStatusRaw.trim().toUpperCase();
    return settlementStatus == 'PENDING' ||
        settlementStatus == 'SUBMITTED' ||
        settlementStatus == 'PROCESSING';
  }

  bool _shouldSyncTransaction(Map<String, dynamic> tx) {
    final chainStatus = '${tx['chainStatus'] ?? ''}';
    final settlementStatus = '${tx['settlementStatus'] ?? ''}';
    final status = '${tx['status'] ?? ''}'.trim().toUpperCase();

    if (status.contains('FAIL')) {
      return false;
    }
    if (!_isChainComplete(chainStatus)) {
      return true;
    }
    return _isSettlementPending(settlementStatus);
  }

  String _chainUiStatus(String chainStatusRaw) {
    return _isChainComplete(chainStatusRaw) ? 'Complete' : 'Processing';
  }

  Future<Map<String, dynamic>?> _findFundingSourceById(
    String fundingSourceId,
  ) async {
    final id = fundingSourceId.trim();
    if (id.isEmpty) return null;
    final items = await getFundingSources();
    for (final item in items) {
      final current = '${item['fundingSourceId'] ?? item['id'] ?? ''}'.trim();
      if (current == id) {
        return item;
      }
    }
    return null;
  }

  String _providerDisplayName(String rawCode) {
    final code = rawCode.trim().toUpperCase();
    switch (code) {
      case 'MOMO':
        return 'MoMo';
      case 'ZALOPAY':
        return 'ZaloPay';
      case 'VNPAY':
        return 'VNPAY';
      case 'TECHCOMBANK':
        return 'Techcombank';
      case 'VIETCOMBANK':
        return 'Vietcombank';
      default:
        return code.isEmpty
            ? AppLocalizations.pick(
                vi: 'Nguồn tiền liên kết',
                en: 'Linked funding source',
              )
            : code;
    }
  }

  Future<void> _pushLocalCashflowNotification({
    required String transactionId,
    required int amount,
    required String providerName,
    required bool isTopup,
    required bool completed,
  }) async {
    final currentUser = await _authService.getCurrentUser();
    final userKey =
        '${currentUser?['phone'] ?? currentUser?['id'] ?? currentUser?['userId'] ?? ''}'
            .trim();
    if (userKey.isEmpty) {
      return;
    }
    final title = completed
        ? (isTopup
              ? AppLocalizations.pick(
                  vi: 'Nạp tiền thành công qua $providerName',
                  en: 'Top-up successful via $providerName',
                )
              : AppLocalizations.pick(
                  vi: 'Rút tiền thành công qua $providerName',
                  en: 'Withdrawal successful via $providerName',
                ))
        : (isTopup
              ? AppLocalizations.pick(
                  vi: 'Đã tạo yêu cầu nạp tiền qua $providerName',
                  en: 'Top-up request created via $providerName',
                )
              : AppLocalizations.pick(
                  vi: 'Đã tạo yêu cầu rút tiền qua $providerName',
                  en: 'Withdrawal request created via $providerName',
                ));
    await _notificationService.addNotification(
      userKey: userKey,
      title: title,
      type: isTopup ? 'receive' : 'transfer',
      amount: '$amount',
      transactionId: transactionId,
    );
  }

  String _resolveDirection({
    required String type,
    required String fromUserId,
    required String toUserId,
    required String currentUserId,
    String fallback = '',
  }) {
    final normalizedType = type.trim().toUpperCase();
    if (normalizedType == 'DEPOSIT') {
      return 'IN';
    }
    if (normalizedType == 'WITHDRAWAL') {
      return 'OUT';
    }

    final normalizedFallback = fallback.trim().toUpperCase();
    if (normalizedFallback == 'IN' || normalizedFallback == 'OUT') {
      return normalizedFallback;
    }
    if (currentUserId.isNotEmpty) {
      if (toUserId == currentUserId && fromUserId != currentUserId) {
        return 'IN';
      }
      if (fromUserId == currentUserId && toUserId != currentUserId) {
        return 'OUT';
      }
    }
    return 'OUT';
  }

  Map<String, dynamic>? _parseReceiptJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveTransactions(
    List<Map<String, dynamic>> transactions,
  ) async {
    final storageKey = await _transactionsStorageKey();
    if (storageKey.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(transactions));
  }

  Future<List<Map<String, dynamic>>>
  _loadStoredTransactionsForCurrentUser() async {
    final storageKey = await _transactionsStorageKey();
    if (storageKey.isEmpty) {
      return [];
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey) ?? '[]';
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return [];
    }
    if (decoded is! List) {
      return [];
    }
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<String> _transactionsStorageKey() async {
    final currentUser = await _authService.getCurrentUser();
    final userId = '${currentUser?['id'] ?? currentUser?['userId'] ?? ''}'
        .trim();
    if (userId.isEmpty) {
      return '';
    }
    return '${_keyTransactions}_$userId';
  }

  Future<String> _fundingSecretsStorageKey() async {
    final currentUser = await _authService.getCurrentUser();
    final userId = '${currentUser?['id'] ?? currentUser?['userId'] ?? ''}'
        .trim();
    if (userId.isEmpty) {
      return '';
    }
    return '${_keyFundingSourceSecrets}_$userId';
  }

  Map<String, dynamic> _buildSessionPatchFromProfile(
    Map<String, dynamic> profile,
  ) {
    final patch = <String, dynamic>{};
    final userId = '${profile['userId'] ?? ''}'.trim();
    if (userId.isNotEmpty) {
      patch['id'] = userId;
    }
    if (profile.containsKey('email')) {
      patch['email'] = '${profile['email'] ?? ''}';
    }
    if (profile.containsKey('phone')) {
      patch['phone'] = '${profile['phone'] ?? ''}';
    }
    if (profile.containsKey('displayName')) {
      patch['displayName'] = '${profile['displayName'] ?? ''}';
    }
    if (profile.containsKey('kycStatus')) {
      patch['kycStatus'] = '${profile['kycStatus'] ?? ''}';
    }
    if (profile.containsKey('accountStatus')) {
      patch['accountStatus'] = '${profile['accountStatus'] ?? ''}';
    }
    return patch;
  }
}
