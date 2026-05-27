import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/app_localizations.dart';
import '../widgets/pin_code_boxes.dart';

class PinUnlockDialog extends StatefulWidget {
  final AuthService authService;
  final String? title;
  final String? subtitle;

  const PinUnlockDialog({
    super.key,
    required this.authService,
    this.title,
    this.subtitle,
  });

  @override
  State<PinUnlockDialog> createState() => _PinUnlockDialogState();
}

class _PinUnlockDialogState extends State<PinUnlockDialog> {
  final _pinController = TextEditingController();
  bool _verifying = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_verifying) {
      return;
    }
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(
        () => _errorText = AppLocalizations.pick(
          vi: 'PIN phải gồm đúng 6 chữ số.',
          en: 'PIN must be exactly 6 digits.',
        ),
      );
      return;
    }

    setState(() {
      _verifying = true;
      _errorText = null;
    });

    final valid = await widget.authService.verifyServerPin(pin);
    if (!mounted) {
      return;
    }

    setState(() {
      _verifying = false;
    });

    if (valid) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(
      () => _errorText = AppLocalizations.pick(
        vi: 'PIN không đúng. Vui lòng thử lại.',
        en: 'Incorrect PIN. Please try again.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.title ??
        AppLocalizations.pick(vi: 'Xác nhận PIN', en: 'Confirm PIN');
    final subtitle =
        widget.subtitle ??
        AppLocalizations.pick(
          vi: 'Nhập mã PIN để hiển thị thông tin bảo mật',
          en: 'Enter PIN to show protected details',
        );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(subtitle),
              const SizedBox(height: 12),
              PinCodeBoxes(
                controller: _pinController,
                length: 6,
                autofocus: true,
                enabled: !_verifying,
                label: AppLocalizations.pick(vi: 'Mã PIN', en: 'PIN'),
                errorText: _errorText,
                onCompleted: (_) => _verify(),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _verifying
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(AppLocalizations.pick(vi: 'Hủy', en: 'Cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _verifying ? null : _verify,
                    child: _verifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            AppLocalizations.pick(
                              vi: 'Xác nhận',
                              en: 'Confirm',
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
