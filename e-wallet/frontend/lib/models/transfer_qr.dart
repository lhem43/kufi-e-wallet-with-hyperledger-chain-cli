import 'dart:convert';

class TransferQrPayload {
  static const String securePrefix = 'EWQR1:';
  static const String secureDeepLinkScheme = 'ewallet';
  static const String secureDeepLinkHost = 'pay';
  static const String offlineTokenPrefix = 'OFFLINE:';

  final String phone;
  final String displayName;
  final String type;
  final int version;

  const TransferQrPayload({
    required this.phone,
    required this.displayName,
    this.type = 'ewallet_transfer',
    this.version = 1,
  });

  Map<String, dynamic> toJson() {
    return {'type': type, 'v': version, 'phone': phone, 'name': displayName};
  }

  String encode() => jsonEncode(toJson());

  static String wrapSecureToken(String tokenRaw) {
    final token = tokenRaw.trim();
    return '$securePrefix$token';
  }

  static String buildOfflineSecureToken({
    required String phone,
    required String displayName,
  }) {
    final normalizedPhone = normalizePhone(phone);
    final safeName = displayName.trim().isEmpty
        ? 'Người nhận'
        : displayName.trim();
    final payload = TransferQrPayload(
      phone: normalizedPhone,
      displayName: safeName,
    ).toJson();
    final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
    return '$offlineTokenPrefix$encoded';
  }

  static TransferQrPayload? decodeOfflineSecureToken(String tokenRaw) {
    final token = tokenRaw.trim();
    if (!token.startsWith(offlineTokenPrefix)) {
      return null;
    }
    final encoded = token.substring(offlineTokenPrefix.length).trim();
    if (encoded.isEmpty) {
      return null;
    }
    try {
      final normalized = base64Url.normalize(encoded);
      final rawJson = utf8.decode(base64Url.decode(normalized));
      return decode(rawJson);
    } catch (_) {
      return null;
    }
  }

  static String? extractSecureToken(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) {
      return null;
    }

    if (raw.startsWith(securePrefix)) {
      final token = raw.substring(securePrefix.length).trim();
      return token.isEmpty ? null : token;
    }

    final parsedUri = Uri.tryParse(raw);
    if (parsedUri != null &&
        parsedUri.scheme == secureDeepLinkScheme &&
        parsedUri.host == secureDeepLinkHost) {
      final token = (parsedUri.queryParameters['t'] ?? '').trim();
      if (token.isNotEmpty) {
        return token;
      }
    }

    return null;
  }

  static String normalizePhone(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.startsWith('84') && digitsOnly.length == 11) {
      return '0${digitsOnly.substring(2)}';
    }
    return digitsOnly;
  }

  static bool isReadyPhone(String phone) {
    return RegExp(r'^(0\d{9,10}|84\d{8,10})$').hasMatch(phone);
  }

  static TransferQrPayload? decode(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) {
      return null;
    }

    final plainPhone = normalizePhone(raw);
    if (isReadyPhone(plainPhone)) {
      return TransferQrPayload(phone: plainPhone, displayName: 'Người nhận');
    }

    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) {
        return null;
      }
      final type = '${parsed['type'] ?? ''}'.trim();
      if (type != 'ewallet_transfer') {
        return null;
      }
      final phone = normalizePhone('${parsed['phone'] ?? ''}');
      if (!isReadyPhone(phone)) {
        return null;
      }
      final name = '${parsed['name'] ?? 'Người nhận'}'.trim();
      return TransferQrPayload(
        phone: phone,
        displayName: name.isEmpty ? 'Người nhận' : name,
      );
    } catch (_) {
      return null;
    }
  }
}
