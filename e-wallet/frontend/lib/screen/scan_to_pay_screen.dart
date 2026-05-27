import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/transfer_qr.dart';
import '../services/app_localizations.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import 'send_money_screen.dart';

class ScanToPayScreen extends StatefulWidget {
  final bool embedded;
  const ScanToPayScreen({super.key, this.embedded = false});

  @override
  State<ScanToPayScreen> createState() => _ScanToPayScreenState();
}

class _ScanToPayScreenState extends State<ScanToPayScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );
  final ImagePicker _imagePicker = ImagePicker();
  final UserService _userService = UserService();

  bool _isHandlingResult = false;
  bool _isPickingImage = false;

  bool get _cameraSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleScanValue(String rawValue) async {
    if (_isHandlingResult) return;
    setState(() => _isHandlingResult = true);

    var shouldResume = true;
    if (_cameraSupported) await _controller.stop();

    try {
      final raw = rawValue.trim();
      if (raw.isEmpty) {
        _showError(
          AppLocalizations.pick(vi: 'QR không hợp lệ.', en: 'Invalid QR code.'),
        );
        return;
      }

      String? recipientPhone;
      final secureToken = TransferQrPayload.extractSecureToken(raw);
      if (secureToken != null) {
        final resolved = await _userService.resolveTransferQrToken(secureToken);
        if (!mounted) return;
        if (resolved['success'] != true) {
          _showError(
            '${resolved['message'] ?? AppLocalizations.pick(vi: 'QR không hợp lệ hoặc đã hết hạn.', en: 'Invalid or expired QR code.')}',
          );
          return;
        }
        if (resolved['found'] != true) {
          _showError(
            AppLocalizations.pick(
              vi: 'Không tìm thấy người nhận hợp lệ trong mã QR.',
              en: 'No valid recipient found in this QR.',
            ),
          );
          return;
        }
        final recipient = Map<String, dynamic>.from(
          (resolved['recipient'] as Map?) ?? <String, dynamic>{},
        );
        recipientPhone = TransferQrPayload.normalizePhone(
          '${recipient['phone'] ?? ''}',
        );
        if (!TransferQrPayload.isReadyPhone(recipientPhone)) {
          _showError(
            AppLocalizations.pick(
              vi: 'QR hợp lệ nhưng thông tin người nhận chưa sẵn sàng.',
              en: 'QR is valid but recipient information is not ready.',
            ),
          );
          return;
        }
      } else {
        final payload = TransferQrPayload.decode(raw);
        if (payload == null) {
          _showError(
            AppLocalizations.pick(
              vi: 'QR không hợp lệ cho chuyển tiền.',
              en: 'QR is not valid for transfer.',
            ),
          );
          return;
        }
        recipientPhone = payload.phone;
      }

      if (!mounted) return;
      shouldResume = false;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              SendMoneyScreen(initialRecipientPhone: recipientPhone),
        ),
      );
    } finally {
      if (mounted) {
        if (shouldResume && _cameraSupported) await _controller.start();
        setState(() => _isHandlingResult = false);
      }
    }
  }

  Future<void> _pickImageAndScan() async {
    if (_isHandlingResult || _isPickingImage) return;
    setState(() => _isPickingImage = true);

    var shouldResume = false;
    try {
      if (_cameraSupported) {
        await _controller.stop();
        shouldResume = true;
      }
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (image == null) return;

      final capture = await _controller.analyzeImage(image.path);
      if (capture == null || capture.barcodes.isEmpty) {
        _showError(
          AppLocalizations.pick(
            vi: 'Không tìm thấy mã QR trong ảnh.',
            en: 'No QR code found in this image.',
          ),
        );
        return;
      }

      String? rawValue;
      for (final bc in capture.barcodes) {
        final r = bc.rawValue;
        if (r != null && r.trim().isNotEmpty) {
          rawValue = r;
          break;
        }
      }

      if (rawValue == null || rawValue.trim().isEmpty) {
        _showError(
          AppLocalizations.pick(
            vi: 'Ảnh không chứa dữ liệu QR hợp lệ.',
            en: 'Image does not contain valid QR data.',
          ),
        );
        return;
      }
      await _handleScanValue(rawValue);
    } catch (_) {
      _showError(
        AppLocalizations.pick(
          vi: 'Không thể quét QR từ ảnh này.',
          en: 'Unable to scan QR from this image.',
        ),
      );
    } finally {
      if (mounted) {
        if (shouldResume && !_isHandlingResult) await _controller.start();
        setState(() => _isPickingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final w = MediaQuery.of(context).size.width;
    final compact = w < 380;

    final content = SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 20,
        vertical: compact ? 10 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scanner / Manual fallback
          if (_cameraSupported) ...[
            _buildScanner(compact),
            SizedBox(height: compact ? 14 : 18),
          ] else ...[
            _buildManualFallback(compact),
            SizedBox(height: compact ? 14 : 18),
          ],

          // Action row
          Row(
            children: [
              Expanded(
                child: _BottomAction(
                  icon: Icons.photo_library_outlined,
                  label: tr(vi: 'Chọn từ ảnh', en: 'Pick image'),
                  loading: _isPickingImage,
                  onTap: _isHandlingResult || _isPickingImage
                      ? null
                      : _pickImageAndScan,
                  compact: compact,
                ),
              ),
              const SizedBox(width: 10),
              if (_cameraSupported)
                Expanded(
                  child: _BottomAction(
                    icon: Icons.flashlight_on_rounded,
                    label: tr(vi: 'Đèn flash', en: 'Flash'),
                    onTap: () => _controller.toggleTorch(),
                    compact: compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(vi: 'Quét QR chuyển tiền', en: 'Scan QR to pay')),
      ),
      body: content,
    );
  }

  Widget _buildScanner(bool compact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scannerHeight = width < 360
            ? 280.0
            : (width < 500 ? 320.0 : 380.0);
        final frameSize = (width * 0.62).clamp(150.0, 260.0);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink900.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: scannerHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      if (capture.barcodes.isEmpty) return;
                      final raw = capture.barcodes.first.rawValue;
                      if (raw == null || raw.isEmpty) return;
                      _handleScanValue(raw);
                    },
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _ScannerOverlayPainter(frameSize: frameSize),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        AppLocalizations.pick(
                          vi: 'Đặt mã QR vào vùng quét',
                          en: 'Align QR in frame',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_isHandlingResult)
                    Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.pick(
                                vi: 'Đang xử lý...',
                                en: 'Processing...',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildManualFallback(bool compact) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232A35) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF344763) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.transparent
                : AppColors.ink900.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.pick(
                  vi: 'Camera không khả dụng',
                  en: 'Camera unavailable',
                ),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.pick(
              vi: 'Dán QR từ clipboard hoặc chọn ảnh chứa QR để chuyển tiền.',
              en: 'Paste QR from clipboard or pick an image to continue.',
            ),
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isHandlingResult ? null : _pasteAndValidate,
              icon: _isHandlingResult
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.content_paste_rounded),
              label: Text(
                AppLocalizations.pick(
                  vi: 'Dán mã QR từ clipboard',
                  en: 'Paste QR from clipboard',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pasteAndValidate() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showError(
        AppLocalizations.pick(
          vi: 'Clipboard trống. Vui lòng sao chép mã QR trước.',
          en: 'Clipboard is empty. Copy a QR first.',
        ),
      );
      return;
    }
    // Quick validation before handling
    final secureToken = TransferQrPayload.extractSecureToken(text);
    final payload = TransferQrPayload.decode(text);
    if (secureToken == null && payload == null) {
      _showError(
        AppLocalizations.pick(
          vi: 'Nội dung clipboard không phải mã QR hợp lệ.',
          en: 'Clipboard content is not a valid QR.',
        ),
      );
      return;
    }
    await _handleScanValue(text);
  }
}

class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool compact;

  const _BottomAction({
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
    final bgColor = isDark ? const Color(0xFF2A3444) : Colors.white;
    final textColor = disabled
        ? scheme.onSurface.withValues(alpha: 0.55)
        : scheme.onSurface;
    final iconColor = disabled
        ? scheme.onSurface.withValues(alpha: 0.45)
        : (isDark ? const Color(0xFFAEC0D9) : AppColors.violet600);
    final borderColor = isDark ? const Color(0xFF3A4B63) : Colors.transparent;
    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor),
      ),
      elevation: disabled ? 0 : 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? 12 : 14,
            horizontal: 12,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              loading
                  ? SizedBox(
                      width: compact ? 16 : 18,
                      height: compact ? 16 : 18,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, size: compact ? 18 : 20, color: iconColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final double frameSize;
  const _ScannerOverlayPainter({required this.frameSize});

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: frameSize,
      height: frameSize,
    );
    final overlay = Paint()
      ..color = Colors.black.withValues(alpha: 0.34)
      ..style = PaintingStyle.fill;

    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(16)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, hole),
      overlay,
    );

    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const cl = 24.0;
    final l = frame.left, t = frame.top, r = frame.right, b = frame.bottom;

    canvas.drawLine(Offset(l, t + cl), Offset(l, t), corner);
    canvas.drawLine(Offset(l, t), Offset(l + cl, t), corner);
    canvas.drawLine(Offset(r - cl, t), Offset(r, t), corner);
    canvas.drawLine(Offset(r, t), Offset(r, t + cl), corner);
    canvas.drawLine(Offset(l, b - cl), Offset(l, b), corner);
    canvas.drawLine(Offset(l, b), Offset(l + cl, b), corner);
    canvas.drawLine(Offset(r - cl, b), Offset(r, b), corner);
    canvas.drawLine(Offset(r, b - cl), Offset(r, b), corner);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter old) =>
      old.frameSize != frameSize;
}
