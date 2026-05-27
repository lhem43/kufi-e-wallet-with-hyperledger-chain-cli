import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/transfer_qr.dart';
import '../services/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';

class ReceiveQrScreen extends StatefulWidget {
  final bool embedded;
  const ReceiveQrScreen({super.key, this.embedded = false});

  @override
  State<ReceiveQrScreen> createState() => _ReceiveQrScreenState();
}

class _ReceiveQrScreenState extends State<ReceiveQrScreen> {
  final _authService = AuthService();
  final _userService = UserService();
  final _shareCardKey = GlobalKey();

  bool _loading = true;
  bool _issuingToken = false;
  bool _sharing = false;
  String _displayName = 'User';
  String _phone = '';
  String _secureToken = '';
  String _qrHint = '';

  String get _qrData {
    if (_secureToken.trim().isEmpty) return '';
    return TransferQrPayload.wrapSecureToken(_secureToken);
  }

  bool get _hasValidPhone => TransferQrPayload.isReadyPhone(_phone);

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _authService.getCurrentUser();
    if (!mounted) return;
    final displayName =
        '${user?['displayName'] ?? user?['email'] ?? AppLocalizations.pick(vi: 'Người dùng', en: 'User')}'
            .trim();
    final phone = TransferQrPayload.normalizePhone('${user?['phone'] ?? ''}');
    setState(() {
      _displayName = displayName.isEmpty
          ? AppLocalizations.pick(vi: 'Người dùng', en: 'User')
          : displayName;
      _phone = phone;
      _loading = false;
    });
    await _refreshQrToken(showErrorSnack: false);
  }

  Future<void> _refreshQrToken({bool showErrorSnack = true}) async {
    if (!_hasValidPhone) {
      if (mounted) {
        setState(() {
          _secureToken = '';
          _qrHint = AppLocalizations.pick(
            vi: 'Không thể tạo QR cho tài khoản này.',
            en: 'Unable to generate QR for this account.',
          );
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _issuingToken = true;
        _qrHint = '';
      });
    }

    try {
      final result = await _userService.issueTransferQrToken();
      if (!mounted) return;
      if (result['success'] == true) {
        final token = '${result['token'] ?? ''}'.trim();
        if (token.isNotEmpty) {
          setState(() {
            _secureToken = token;
            _qrHint = '';
          });
          return;
        }
      }
      setState(() {
        _secureToken = '';
        _qrHint = AppLocalizations.pick(
          vi: 'Không thể tạo mã QR.',
          en: 'Unable to generate QR code.',
        );
      });
      if (showErrorSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.pick(
                vi: 'Không thể tạo mã QR.',
                en: 'Unable to generate QR code.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _secureToken = '';
        _qrHint = AppLocalizations.pick(
          vi: 'Không kết nối được máy chủ.',
          en: 'Unable to connect to server.',
        );
      });
    } finally {
      if (mounted) setState(() => _issuingToken = false);
    }
  }

  Future<void> _copyValue(String value, String label) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.pick(vi: 'Đã sao chép $label', en: 'Copied $label'),
        ),
      ),
    );
  }

  Future<void> _shareQrCard() async {
    if (_sharing || _qrData.isEmpty) return;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio.clamp(2.0, 3.0);
    setState(() => _sharing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!mounted) return;
      final ro = _shareCardKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) throw StateError('Not ready');
      final image = await ro.toImage(pixelRatio: pixelRatio);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) throw StateError('Cannot create PNG');
      await _shareBytesAsImage(bd.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Không thể tạo ảnh chia sẻ.',
              en: 'Unable to create share image.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareBytesAsImage(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/ewallet_qr_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: AppLocalizations.pick(
          vi: 'QR nhận tiền của $_displayName - $_phone',
          en: 'Receive QR for $_displayName - $_phone',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final w = MediaQuery.of(context).size.width;
    final compact = w < 380;
    final qrSize = (w * 0.52).clamp(160.0, 240.0);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF232A35) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF344763) : Colors.transparent;
    final titleColor = scheme.onSurface;
    final subColor = scheme.onSurface.withValues(alpha: 0.72);

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 20,
              vertical: compact ? 10 : 16,
            ),
            child: Column(
              children: [
                // QR Card
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(compact ? 16 : 24),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.transparent
                            : AppColors.ink900.withValues(alpha: 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // User info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.momoPink,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _displayName.isNotEmpty
                                    ? _displayName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: compact ? 15 : 16,
                                    color: titleColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_phone.isNotEmpty)
                                  Text(
                                    _phone,
                                    style: TextStyle(
                                      fontSize: compact ? 12 : 13,
                                      color: subColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 16 : 20),

                      // QR code
                      if (_qrData.isNotEmpty)
                        RepaintBoundary(
                          key: _shareCardKey,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.violet100,
                                width: 2,
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                QrImageView(
                                  data: _qrData,
                                  version: QrVersions.auto,
                                  size: qrSize,
                                  backgroundColor: Colors.white,
                                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Color(0xFF6D1128),
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Color(0xFF8C1E37),
                                  ),
                                ),
                                Container(
                                  width: qrSize * 0.2,
                                  height: qrSize * 0.2,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: Image.asset(
                                      'assets/images/sleepy_cat.png',
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          width: qrSize,
                          height: qrSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E2736)
                                : AppColors.vanilla50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF324761)
                                  : AppColors.vanilla200,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              tr(
                                vi: 'Chưa thể tạo mã QR',
                                en: 'QR unavailable',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                      if (_qrHint.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _qrHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: subColor,
                              fontSize: compact ? 11 : 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 14 : 20),

                // Action buttons row
                LayoutBuilder(
                  builder: (context, constraints) {
                    final btnWidth =
                        (constraints.maxWidth - 10 * 3) / 4; // 4 buttons
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        _ActionButton(
                          width: btnWidth.clamp(70, 90),
                          icon: Icons.copy_all_outlined,
                          label: tr(vi: 'Sao chép SĐT', en: 'Copy phone'),
                          onTap: _phone.isEmpty
                              ? null
                              : () => _copyValue(
                                  _phone,
                                  tr(vi: 'số điện thoại', en: 'phone number'),
                                ),
                          compact: compact,
                        ),
                        _ActionButton(
                          width: btnWidth.clamp(70, 90),
                          icon: Icons.qr_code_2,
                          label: tr(vi: 'Sao chép QR', en: 'Copy QR'),
                          onTap: _qrData.isEmpty
                              ? null
                              : () => _copyValue(
                                  _qrData,
                                  tr(vi: 'mã QR', en: 'QR code'),
                                ),
                          compact: compact,
                        ),
                        _ActionButton(
                          width: btnWidth.clamp(70, 90),
                          icon: Icons.share_rounded,
                          label: tr(vi: 'Chia sẻ', en: 'Share'),
                          loading: _sharing,
                          onTap: _qrData.isEmpty || _sharing
                              ? null
                              : _shareQrCard,
                          compact: compact,
                        ),
                        _ActionButton(
                          width: btnWidth.clamp(70, 90),
                          icon: Icons.refresh_rounded,
                          label: tr(vi: 'Làm mới', en: 'Refresh'),
                          loading: _issuingToken,
                          onTap: _issuingToken ? null : _refreshQrToken,
                          compact: compact,
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: compact ? 14 : 20),
                const SizedBox(height: 4),
              ],
            ),
          );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(vi: 'Nhận tiền bằng QR', en: 'Receive via QR')),
      ),
      body: content,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool compact;

  const _ActionButton({
    required this.width,
    required this.icon,
    required this.label,
    this.onTap,
    this.loading = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bgColor = disabled
        ? (isDark ? const Color(0xFF1F2734) : AppColors.vanilla50)
        : (isDark ? const Color(0xFF2A3444) : Colors.white);
    final iconColor = disabled
        ? scheme.onSurface.withValues(alpha: 0.45)
        : (isDark ? const Color(0xFFAEC0D9) : AppColors.violet600);
    final textColor = disabled
        ? scheme.onSurface.withValues(alpha: 0.55)
        : scheme.onSurface;
    final borderColor = isDark ? const Color(0xFF3A4B63) : Colors.transparent;

    return SizedBox(
      width: width,
      child: Material(
        color: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor),
        ),
        elevation: disabled ? 0 : 0.5,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: compact ? 10 : 12,
              horizontal: 4,
            ),
            child: Column(
              children: [
                loading
                    ? SizedBox(
                        width: compact ? 18 : 20,
                        height: compact ? 18 : 20,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, size: compact ? 20 : 22, color: iconColor),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
