import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ErrorMessage {
  static String fromException(
    Object error, {
    String fallback = 'Đã có lỗi xảy ra. Vui lòng thử lại.',
  }) {
    if (error is TimeoutException) {
      return 'Kết nối tới máy chủ quá chậm. Vui lòng kiểm tra mạng và thử lại.';
    }
    if (error is SocketException) {
      return 'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng hoặc backend.';
    }
    if (error is HandshakeException) {
      return 'Kết nối bảo mật thất bại. Vui lòng kiểm tra cấu hình HTTPS.';
    }
    if (error is HttpException) {
      return 'Kết nối HTTP thất bại. Vui lòng thử lại sau.';
    }
    if (error is http.ClientException) {
      return 'Kết nối tới máy chủ thất bại. Vui lòng kiểm tra mạng và thử lại.';
    }
    if (error is FormatException) {
      return 'Phản hồi từ máy chủ không hợp lệ.';
    }
    if (error is TypeError) {
      return 'Phản hồi từ hệ thống không hợp lệ. Vui lòng thử lại.';
    }

    final normalizedFromText = _normalizeUnknown(error.toString());
    if (normalizedFromText != null) {
      return normalizedFromText;
    }

    return fallback;
  }

  static String fromHttpBody(
    String rawBody, {
    int? statusCode,
    String defaultMessage = 'Yêu cầu thất bại.',
  }) {
    final parsed = _extractFromBody(rawBody);
    if (parsed.isNotEmpty) {
      return _normalize(parsed);
    }

    final fromStatus = _fromStatusCode(statusCode);
    if (fromStatus != null) {
      return fromStatus;
    }

    final plain = rawBody.trim();
    if (plain.isNotEmpty && !_looksLikeHtml(plain)) {
      return _normalize(plain);
    }
    return defaultMessage;
  }

  static String _extractFromBody(String rawBody) {
    try {
      final parsed = jsonDecode(rawBody);
      final message = _extractDynamic(parsed);
      return message?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static String? _extractDynamic(dynamic data) {
    if (data == null) {
      return null;
    }
    if (data is String) {
      return data.trim().isEmpty ? null : data.trim();
    }
    if (data is List) {
      final parts = data
          .map(_extractDynamic)
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isEmpty) {
        return null;
      }
      return parts.join('\n');
    }
    if (data is Map<String, dynamic>) {
      for (final key in const [
        'message',
        'error_description',
        'error',
        'detail',
        'details',
        'reason',
      ]) {
        final value = _extractDynamic(data[key]);
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      for (final value in data.values) {
        final extracted = _extractDynamic(value);
        if (extracted != null && extracted.isNotEmpty) {
          return extracted;
        }
      }
    }
    return null;
  }

  static String? _fromStatusCode(int? code) {
    switch (code) {
      case 400:
        return 'Dữ liệu gửi lên chưa hợp lệ. Vui lòng kiểm tra lại thông tin.';
      case 401:
        return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
      case 403:
        return 'Bạn không có quyền thực hiện thao tác này.';
      case 404:
        return 'Không tìm thấy dữ liệu yêu cầu.';
      case 409:
        return 'Dữ liệu bị xung đột. Có thể thông tin đã tồn tại.';
      case 422:
        return 'Thông tin nhập chưa hợp lệ.';
      case 429:
        return 'Bạn thao tác quá nhanh. Vui lòng thử lại sau ít phút.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'Máy chủ đang gặp sự cố tạm thời. Vui lòng thử lại sau.';
      default:
        return null;
    }
  }

  static bool _looksLikeHtml(String value) {
    final lower = value.toLowerCase();
    return lower.contains('<!doctype html') ||
        lower.contains('<html') ||
        lower.contains('<body');
  }

  static String _normalize(String raw) {
    final message = raw.trim();
    if (message.isEmpty) {
      return 'Yêu cầu thất bại.';
    }

    final lower = message.toLowerCase();
    if (lower.contains('recipient must be a phone number')) {
      return 'Người nhận phải là số điện thoại hợp lệ.';
    }
    if (lower.contains('recipient phone number is incomplete')) {
      return 'Số điện thoại người nhận chưa đầy đủ.';
    }
    if (lower.contains('invalid otp') ||
        (lower.contains('otp') && lower.contains('invalid'))) {
      return 'Mã OTP không đúng hoặc đã hết hạn.';
    }
    if (lower.contains('otp') && lower.contains('expired')) {
      return 'Mã OTP đã hết hạn. Vui lòng yêu cầu mã mới.';
    }
    if (lower.contains('invalid_login_credentials')) {
      return 'Email hoặc mật khẩu không chính xác.';
    }
    if (lower.contains('relation') && lower.contains('does not exist')) {
      return 'Hệ thống đang khởi tạo dữ liệu. Vui lòng thử lại sau vài giây.';
    }
    if (lower.contains('insufficient') && lower.contains('balance')) {
      return 'Số dư không đủ để thực hiện giao dịch.';
    }
    if (lower.contains('chain') &&
        (lower.contains('unavailable') ||
            lower.contains('econnrefused') ||
            lower.contains('timeout'))) {
      return 'Hệ thống xác thực on-chain đang gián đoạn. Vui lòng thử lại sau.';
    }
    if (lower.contains('network request failed') ||
        lower.contains('failed to fetch')) {
      return 'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.';
    }
    if (lower == 'internal server error' ||
        (lower.contains('internal server error') && lower.length < 80)) {
      return 'Máy chủ đang gặp sự cố tạm thời. Vui lòng thử lại sau.';
    }
    if (lower.contains('smtp') && lower.contains('otp')) {
      return 'Hệ thống email OTP chưa được cấu hình đầy đủ. Vui lòng liên hệ quản trị.';
    }
    if (lower == 'email_exists') {
      return 'Email đã được đăng ký.';
    }
    if (lower == 'email_not_found') {
      return 'Email không tồn tại.';
    }
    if (lower == 'invalid_password') {
      return 'Mật khẩu không chính xác.';
    }
    if (lower == 'too_many_attempts_try_later') {
      return 'Bạn thử quá nhiều lần. Vui lòng thử lại sau.';
    }
    return message;
  }

  static String? _normalizeUnknown(String raw) {
    var message = raw.trim();
    if (message.isEmpty) {
      return null;
    }

    message = message
        .replaceFirst(
          RegExp(r'^(Exception|Error):\s*', caseSensitive: false),
          '',
        )
        .trim();
    if (message.isEmpty) {
      return null;
    }

    final lower = message.toLowerCase();
    if (lower.contains('type') &&
        lower.contains('is not a subtype') &&
        lower.contains('null')) {
      return 'Dữ liệu phản hồi từ hệ thống chưa đầy đủ. Vui lòng thử lại.';
    }
    if (lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection reset')) {
      return 'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng hoặc backend.';
    }
    if (lower.contains('notinitializederror') ||
        lower.contains('dotenv') && lower.contains('not initialized')) {
      return 'Ứng dụng chưa được cấu hình môi trường đầy đủ. Vui lòng cập nhật bản mới nhất.';
    }
    return _normalize(message);
  }
}
