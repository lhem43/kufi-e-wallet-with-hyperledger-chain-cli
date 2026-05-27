import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import '../services/auth_service.dart';
import '../services/app_localizations.dart';
import '../services/error_message.dart';
import '../services/pin_session_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/gradient_button.dart';
import '../widgets/pin_code_boxes.dart';
import 'home_screen.dart';

class ReceiptScreen extends StatefulWidget {
  final String recipient;
  final int amount;
  final DateTime transactionDate;
  final String transactionId;
  final String transactionStatus;
  final String settlementStatus;
  final String chainStatus;
  final String chainTxId;
  final dynamic blockNumber;
  final String blockHash;
  final String merkleRoot;
  final String commitmentHash;
  final String errorCode;
  final String errorMessage;
  final String senderNote;

  const ReceiptScreen({
    super.key,
    required this.recipient,
    required this.amount,
    required this.transactionDate,
    required this.transactionId,
    required this.transactionStatus,
    required this.settlementStatus,
    required this.chainStatus,
    required this.chainTxId,
    required this.blockNumber,
    required this.blockHash,
    required this.merkleRoot,
    required this.commitmentHash,
    this.errorCode = '',
    this.errorMessage = '',
    this.senderNote = '',
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _userService = UserService();
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  bool _revealed = false;
  bool _hasPinProtection = false;
  bool _isWaitingForFinalState = false;
  bool _waitTimeoutReached = false;
  bool _allowLiveUpdateOnScreen = true;
  bool _isDownloadingReceipt = false;

  late String _transactionStatus;
  late String _settlementStatus;
  late String _chainStatus;
  late String _chainTxId;
  late dynamic _blockNumber;
  late String _blockHash;
  late String _merkleRoot;
  late String _commitmentHash;
  late String _commitmentAlgorithm;
  late String _observationType;
  late String _observationRef;
  late String _observationAt;
  late Map<String, dynamic> _commitmentOpening;
  late String _originMspId;
  late List<Map<String, String>> _peerSignatures;
  late String _errorCode;
  late String _errorMessage;
  late String _receiptJsonRaw;

  String get _formattedDate =>
      DateFormat('dd/MM/yyyy HH:mm:ss').format(widget.transactionDate);

  String get _formattedAmount => widget.amount.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );

  String get _displayErrorMessage {
    final raw = _errorMessage.trim();
    if (raw.isEmpty) return '';
    return ErrorMessage.fromHttpBody(raw, defaultMessage: raw);
  }

  String _mask(String value) {
    if (value.isEmpty) return '—';
    if (value.length <= 8) return '•' * value.length;
    return '${value.substring(0, 4)}${'•' * (value.length - 8).clamp(4, 20)}${value.substring(value.length - 4)}';
  }

  String _short(String value, {int keep = 10}) {
    if (value.length <= keep * 2 + 3) return value;
    return '${value.substring(0, keep)}...${value.substring(value.length - keep)}';
  }

  bool get _onChainComplete {
    final n = _chainStatus.trim().toUpperCase();
    return n == 'ANCHORED' || n == 'COMPLETE' || n == 'COMPLETED';
  }

  bool get _onChainFailed {
    final n = _chainStatus.trim().toUpperCase();
    return n == 'FAILED' || n == 'ERROR';
  }

  String get _onChainLabel {
    if (_onChainComplete) {
      return AppLocalizations.pick(vi: 'Đã xác thực', en: 'Verified');
    }
    if (_onChainFailed) {
      return AppLocalizations.pick(
        vi: 'Lỗi xác thực',
        en: 'Verification failed',
      );
    }
    if (_isInternalProcessingCompletedForDisplay()) {
      return AppLocalizations.pick(
        vi: 'Đang xác thực',
        en: 'Verification in progress',
      );
    }
    return AppLocalizations.pick(vi: 'Đang cập nhật', en: 'Updating');
  }

  @override
  void initState() {
    super.initState();
    _transactionStatus = widget.transactionStatus;
    _settlementStatus = widget.settlementStatus;
    _chainStatus = widget.chainStatus;
    _chainTxId = widget.chainTxId;
    _blockNumber = widget.blockNumber;
    _blockHash = widget.blockHash;
    _merkleRoot = widget.merkleRoot;
    _commitmentHash = widget.commitmentHash;
    _commitmentAlgorithm = '';
    _observationType = '';
    _observationRef = '';
    _observationAt = '';
    _commitmentOpening = const {};
    _originMspId = '';
    _peerSignatures = const [];
    _errorCode = widget.errorCode;
    _errorMessage = widget.errorMessage;
    _receiptJsonRaw = '';

    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
    _loadPinState();
    _refreshReceiptDetailsOnce();

    if (_shouldContinuePolling()) {
      _startFinalStateWaitingWindow();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPinState() async {
    final hasPin = await _authService.hasDevicePinForCurrentUser();
    if (!mounted) return;
    setState(() {
      _hasPinProtection = hasPin;
      if (!hasPin || PinSessionService().isReceiptUnlocked) _revealed = true;
    });
  }

  Future<void> _requestReveal() async {
    if (_revealed) return;
    if (!_hasPinProtection) {
      setState(() => _revealed = true);
      return;
    }

    // If already unlocked this session, skip PIN prompt
    if (PinSessionService().isReceiptUnlocked) {
      setState(() => _revealed = true);
      return;
    }

    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PinRevealDialog(authService: _authService),
    );
    if (unlocked == true && mounted) {
      PinSessionService().markReceiptUnlocked();
      setState(() => _revealed = true);
    }
  }

  Future<void> _copy(String value, String label) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.pick(vi: 'Đã copy $label', en: 'Copied $label'),
        ),
      ),
    );
  }

  Future<Directory> _resolveReceiptDownloadDir() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {
      // ignore and fallback to app documents directory
    }
    return getApplicationDocumentsDirectory();
  }

  Map<String, dynamic> _buildReceiptExportPayload() {
    final receiptId = _chainTxId.trim().isNotEmpty
        ? _chainTxId.trim()
        : widget.transactionId.trim();
    final securityNotice = <String>[
      'Secured by Kufi and timestamped by FreeTSA',
      'Any modification will be detected',
    ];

    final raw = _receiptJsonRaw.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return {
            'exported_at': DateTime.now().toIso8601String(),
            'receipt_id': receiptId,
            'transaction_id': widget.transactionId,
            'security_notice': securityNotice,
            'receipt': decoded,
          };
        }
      } catch (_) {
        // fallback below
      }
    }

    return {
      'exported_at': DateTime.now().toIso8601String(),
      'receipt_id': receiptId,
      'transaction_id': widget.transactionId,
      'security_notice': securityNotice,
      'receipt': {
        'tx_id': _chainTxId,
        'block_number': _blockNumber,
        'block_hash': _blockHash,
        'receipt_hash': _merkleRoot,
        'commitment_hash': _commitmentHash,
        'commitment_algorithm': _commitmentAlgorithm,
        'origin_msp_id': _originMspId,
        'observation': {
          'anchor_type': _observationType,
          'anchor_ref': _observationRef,
          'observed_at': _observationAt,
        },
        'commitment_opening': _commitmentOpening,
        'observer_confirmations': _peerSignatures,
      },
    };
  }

  Future<void> _downloadReceipt() async {
    if (_isDownloadingReceipt) return;
    setState(() => _isDownloadingReceipt = true);
    try {
      final dir = await _resolveReceiptDownloadDir();
      await dir.create(recursive: true);
      final receiptId = _chainTxId.trim().isNotEmpty
          ? _chainTxId.trim()
          : widget.transactionId.trim();
      final safeReceiptId = receiptId.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final name = 'receipt_$safeReceiptId.json';
      final file = File('${dir.path}/$name');
      final payload = _buildReceiptExportPayload();
      final pretty = const JsonEncoder.withIndent('  ').convert(payload);
      await file.writeAsString(pretty, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Đã tải biên nhận: ${file.path}',
              en: 'Receipt downloaded: ${file.path}',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.pick(
              vi: 'Không thể tải biên nhận. Vui lòng thử lại.',
              en: 'Unable to download receipt. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isDownloadingReceipt = false);
    }
  }

  bool _isCompletedStatus(String statusRaw) {
    return statusRaw.trim().toUpperCase() == 'COMPLETED';
  }

  bool _isFailedStatus(String statusRaw) {
    final status = statusRaw.trim().toUpperCase();
    return status.contains('FAIL') || status.contains('ERROR');
  }

  bool _isFinalTransactionState(String statusRaw) {
    return _isCompletedStatus(statusRaw) || _isFailedStatus(statusRaw);
  }

  bool _isInternalProcessingCompletedForDisplay() {
    return !_isFailedStatus(_transactionStatus);
  }

  bool _isVerificationPendingAfterSuccess() {
    return _isInternalProcessingCompletedForDisplay() &&
        !_isFailedStatus(_transactionStatus) &&
        !_onChainComplete &&
        !_onChainFailed;
  }

  bool _shouldContinuePolling() {
    if (!_allowLiveUpdateOnScreen) {
      return false;
    }
    if (!_isFinalTransactionState(_transactionStatus)) {
      return true;
    }
    if (_isVerificationPendingAfterSuccess()) {
      return true;
    }
    return false;
  }

  String _transactionStatusLabel() {
    if (_isInternalProcessingCompletedForDisplay()) {
      return AppLocalizations.pick(vi: 'Thành công', en: 'Success');
    }
    if (_isFailedStatus(_transactionStatus)) {
      return AppLocalizations.pick(vi: 'Thất bại', en: 'Failed');
    }
    return AppLocalizations.pick(vi: 'Đang xử lý', en: 'Processing');
  }

  Future<void> _startFinalStateWaitingWindow() async {
    if (_isWaitingForFinalState) return;
    setState(() {
      _isWaitingForFinalState = true;
      _waitTimeoutReached = false;
    });

    final deadline = DateTime.now().add(const Duration(seconds: 8));

    while (mounted && _shouldContinuePolling()) {
      final reachedTimeout = DateTime.now().isAfter(deadline);
      if (reachedTimeout) {
        break;
      }

      final response = await _userService.getTransactionById(
        widget.transactionId,
      );
      if (!mounted || !_allowLiveUpdateOnScreen) {
        return;
      }
      if (response['success'] == true &&
          response['data'] is Map<String, dynamic>) {
        _applyRemoteTransaction(
          Map<String, dynamic>.from(response['data'] as Map<String, dynamic>),
        );
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    if (_shouldContinuePolling()) {
      setState(() {
        _isWaitingForFinalState = false;
        _waitTimeoutReached = true;
        _allowLiveUpdateOnScreen = false;
      });
      return;
    }

    setState(() {
      _isWaitingForFinalState = false;
      _waitTimeoutReached = false;
    });
  }

  bool _applyRemoteTransaction(Map<String, dynamic> tx) {
    final nextStatus = '${tx['status'] ?? _transactionStatus}';
    final nextSettlementStatus =
        '${tx['settlementStatus'] ?? _settlementStatus}';
    final nextChainStatus = '${tx['chainStatus'] ?? _chainStatus}';
    final nextErrorCode = '${tx['errorCode'] ?? _errorCode}';
    final nextErrorMessage = '${tx['errorMessage'] ?? _errorMessage}';

    String nextChainTxId = _chainTxId;
    dynamic nextBlockNumber = _blockNumber;
    String nextBlockHash = _blockHash;
    String nextMerkleRoot = _merkleRoot;
    String nextCommitmentHash = _commitmentHash;
    String nextCommitmentAlgorithm = _commitmentAlgorithm;
    String nextObservationType = _observationType;
    String nextObservationRef = _observationRef;
    String nextObservationAt = _observationAt;
    Map<String, dynamic> nextCommitmentOpening = _commitmentOpening;
    String nextOriginMspId = _originMspId;
    List<Map<String, String>> nextPeerSignatures = _peerSignatures;
    String nextReceiptJsonRaw = _receiptJsonRaw;

    final receiptRaw = '${tx['receiptJson'] ?? ''}'.trim();
    if (receiptRaw.isNotEmpty) {
      nextReceiptJsonRaw = receiptRaw;
    }

    final receipt = _extractReceiptMap(tx);
    if (receipt != null) {
      if (nextReceiptJsonRaw.isEmpty) {
        nextReceiptJsonRaw = jsonEncode(receipt);
      }
      nextChainTxId = '${receipt['tx_id'] ?? nextChainTxId}';
      nextBlockNumber = receipt['block_number'] ?? nextBlockNumber;
      nextBlockHash = '${receipt['block_hash'] ?? nextBlockHash}';
      nextMerkleRoot = '${receipt['receipt_hash'] ?? nextMerkleRoot}';
      nextCommitmentHash =
          '${receipt['commitment_hash'] ?? nextCommitmentHash}';
      nextCommitmentAlgorithm =
          '${receipt['commitment_algorithm'] ?? nextCommitmentAlgorithm}';
      nextOriginMspId = '${receipt['origin_msp_id'] ?? nextOriginMspId}';
      final observation = receipt['observation'];
      if (observation is Map) {
        nextObservationType =
            '${observation['anchor_type'] ?? nextObservationType}';
        nextObservationRef =
            '${observation['anchor_ref'] ?? nextObservationRef}';
        nextObservationAt = _formatEpochMillis(observation['observed_at']);
      }
      final opening = receipt['commitment_opening'];
      if (opening is Map) {
        nextCommitmentOpening = Map<String, dynamic>.from(opening);
      }
      nextPeerSignatures = _buildPeerSignatures(
        receipt: receipt,
        originMspId: nextOriginMspId,
      );
    }

    final changed =
        nextStatus != _transactionStatus ||
        nextSettlementStatus != _settlementStatus ||
        nextChainStatus != _chainStatus ||
        nextErrorCode != _errorCode ||
        nextErrorMessage != _errorMessage ||
        nextChainTxId != _chainTxId ||
        nextBlockNumber != _blockNumber ||
        nextBlockHash != _blockHash ||
        nextMerkleRoot != _merkleRoot ||
        nextCommitmentHash != _commitmentHash ||
        nextCommitmentAlgorithm != _commitmentAlgorithm ||
        nextObservationType != _observationType ||
        nextObservationRef != _observationRef ||
        nextObservationAt != _observationAt ||
        !_sameCommitmentOpening(nextCommitmentOpening, _commitmentOpening) ||
        nextOriginMspId != _originMspId ||
        !_samePeerSignatures(nextPeerSignatures, _peerSignatures) ||
        nextReceiptJsonRaw != _receiptJsonRaw;

    if (!changed) {
      return false;
    }

    if (!mounted) {
      return false;
    }

    setState(() {
      _transactionStatus = nextStatus;
      _settlementStatus = nextSettlementStatus;
      _chainStatus = nextChainStatus;
      _errorCode = nextErrorCode;
      _errorMessage = nextErrorMessage;
      _chainTxId = nextChainTxId;
      _blockNumber = nextBlockNumber;
      _blockHash = nextBlockHash;
      _merkleRoot = nextMerkleRoot;
      _commitmentHash = nextCommitmentHash;
      _commitmentAlgorithm = nextCommitmentAlgorithm;
      _observationType = nextObservationType;
      _observationRef = nextObservationRef;
      _observationAt = nextObservationAt;
      _commitmentOpening = nextCommitmentOpening;
      _originMspId = nextOriginMspId;
      _peerSignatures = nextPeerSignatures;
      _receiptJsonRaw = nextReceiptJsonRaw;
    });
    return true;
  }

  Future<void> _refreshReceiptDetailsOnce() async {
    final response = await _userService.getTransactionById(
      widget.transactionId,
    );
    if (!mounted) return;
    if (response['success'] == true &&
        response['data'] is Map<String, dynamic>) {
      _applyRemoteTransaction(
        Map<String, dynamic>.from(response['data'] as Map<String, dynamic>),
      );
    }
  }

  Map<String, dynamic>? _extractReceiptMap(Map<String, dynamic> tx) {
    final embedded = tx['receipt'];
    if (embedded is Map) {
      return Map<String, dynamic>.from(embedded);
    }

    final receiptRaw = '${tx['receiptJson'] ?? ''}'.trim();
    if (receiptRaw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(receiptRaw);
      if (decoded is Map) {
        final receipt = Map<String, dynamic>.from(decoded);
        final nested = receipt['receipt'];
        if (nested is Map) {
          return Map<String, dynamic>.from(nested);
        }
        return receipt;
      }
    } catch (_) {
      // Ignore malformed receipt payload from polling update.
    }
    return null;
  }

  String _formatEpochMillis(dynamic raw) {
    if (raw == null) return '';
    final ms = int.tryParse('$raw');
    if (ms == null || ms <= 0) return '';
    try {
      return DateFormat(
        'dd/MM/yyyy HH:mm:ss',
      ).format(DateTime.fromMillisecondsSinceEpoch(ms));
    } catch (_) {
      return '';
    }
  }

  bool _sameCommitmentOpening(Map<String, dynamic> a, Map<String, dynamic> b) {
    return jsonEncode(a) == jsonEncode(b);
  }

  String _normalizeAmount(dynamic raw) {
    final n = int.tryParse('$raw');
    if (n == null) return '$raw';
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
  }

  String _formatObservationType(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'fabric_block_header_hash') {
      return AppLocalizations.pick(
        vi: 'Băm header block Fabric',
        en: 'Fabric block header hash',
      );
    }
    return raw.trim();
  }

  bool _samePeerSignatures(
    List<Map<String, String>> a,
    List<Map<String, String>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['mspId'] != b[i]['mspId'] ||
          a[i]['label'] != b[i]['label'] ||
          a[i]['signatureHex'] != b[i]['signatureHex'] ||
          a[i]['fingerprint'] != b[i]['fingerprint'] ||
          a[i]['confirmedAt'] != b[i]['confirmedAt']) {
        return false;
      }
    }
    return true;
  }

  List<Map<String, String>> _buildPeerSignatures({
    required Map<String, dynamic> receipt,
    required String originMspId,
  }) {
    final origin = originMspId.trim().toUpperCase();
    final list = <Map<String, String>>[];
    final observerRaw = receipt['observer_confirmations'];
    if (observerRaw is List) {
      for (final item in observerRaw) {
        if (item is! Map) continue;
        final obs = Map<String, dynamic>.from(item);
        final mspId = '${obs['msp_id'] ?? ''}'.trim();
        if (mspId.isEmpty) continue;
        if (origin.isNotEmpty && mspId.toUpperCase() == origin) continue;
        final signatureHex = '${obs['signature_hex'] ?? ''}'.trim();
        final fingerprint = '${obs['cert_fingerprint'] ?? ''}'.trim();
        if (signatureHex.isEmpty && fingerprint.isEmpty) continue;
        list.add({
          'mspId': mspId,
          'label': _toOrgDisplayName(mspId),
          'signatureHex': signatureHex,
          'fingerprint': fingerprint,
          'confirmedAt': _formatEpochMillis(obs['observed_at']),
        });
        if (list.length >= 5) break;
      }
      if (list.isNotEmpty) {
        return list;
      }
    }

    final endorsementsRaw = receipt['endorsements'];
    if (endorsementsRaw is! List) {
      return list;
    }

    for (final item in endorsementsRaw) {
      if (item is! Map) continue;
      final e = Map<String, dynamic>.from(item);
      final mspId = '${e['msp_id'] ?? ''}'.trim();
      if (mspId.isEmpty) continue;
      if (origin.isNotEmpty && mspId.toUpperCase() == origin) {
        continue;
      }
      final signatureHex = '${e['signature_hex'] ?? ''}'.trim();
      final fingerprint = '${e['cert_fingerprint'] ?? ''}'.trim();
      if (signatureHex.isEmpty && fingerprint.isEmpty) {
        continue;
      }
      list.add({
        'mspId': mspId,
        'label': _toOrgDisplayName(mspId),
        'signatureHex': signatureHex,
        'fingerprint': fingerprint,
        'confirmedAt': '',
      });
      if (list.length >= 5) break;
    }
    return list;
  }

  String _toOrgDisplayName(String mspId) {
    final raw = mspId.trim();
    if (raw.isEmpty) {
      return AppLocalizations.pick(
        vi: 'Node không xác định',
        en: 'Unknown node',
      );
    }
    final noSuffix = raw.replaceAll(RegExp(r'MSP$', caseSensitive: false), '');
    return noSuffix;
  }

  void _backHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    final scheme = Theme.of(context).colorScheme;
    final success = _isInternalProcessingCompletedForDisplay();
    final failed = _isFailedStatus(_transactionStatus);
    final stillProcessing = !success && !failed;
    final verificationPendingAfterSuccess =
        _isVerificationPendingAfterSuccess();
    final errMsg = _displayErrorMessage;
    final w = MediaQuery.of(context).size.width;
    final compact = w < 380;
    final pad = compact ? 14.0 : 18.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(vi: 'Biên nhận', en: 'Receipt')),
      ),
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, _) => ListView(
              padding: EdgeInsets.all(pad),
              children: [
                // ── Hero card ──
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 14 : 18),
                      child: Column(
                        children: [
                          Container(
                            width: compact ? 70 : 86,
                            height: compact ? 70 : 86,
                            decoration: BoxDecoration(
                              color: _isWaitingForFinalState
                                  ? AppColors.violet100
                                  : success
                                  ? AppColors.success.withValues(alpha: 0.13)
                                  : _waitTimeoutReached
                                  ? AppColors.vanilla100
                                  : AppColors.danger.withValues(alpha: 0.13),
                              shape: BoxShape.circle,
                            ),
                            child: _isWaitingForFinalState
                                ? Padding(
                                    padding: EdgeInsets.all(compact ? 20 : 24),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: AppColors.violet700,
                                    ),
                                  )
                                : Icon(
                                    success
                                        ? Icons.check_circle_rounded
                                        : Icons.info_outline_rounded,
                                    size: compact ? 42 : 56,
                                    color: success
                                        ? AppColors.success
                                        : _waitTimeoutReached
                                        ? AppColors.vanilla700
                                        : AppColors.danger,
                                  ),
                          ),
                          const SizedBox(height: 12),
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Text(
                              _isWaitingForFinalState
                                  ? (verificationPendingAfterSuccess
                                        ? tr(
                                            vi: 'Đang xác thực biên nhận',
                                            en: 'Verifying receipt',
                                          )
                                        : tr(
                                            vi: 'Đang xác nhận giao dịch',
                                            en: 'Confirming transaction',
                                          ))
                                  : success
                                  ? (verificationPendingAfterSuccess &&
                                            _waitTimeoutReached
                                        ? tr(
                                            vi: 'Giao dịch thành công, chờ xác thực',
                                            en: 'Transaction succeeded, waiting for verification',
                                          )
                                        : tr(
                                            vi: 'Giao dịch thành công',
                                            en: 'Transaction succeeded',
                                          ))
                                  : _waitTimeoutReached
                                  ? tr(
                                      vi: 'Giao dịch vẫn đang xử lý',
                                      en: 'Transaction is still processing',
                                    )
                                  : tr(
                                      vi: 'Kết quả giao dịch',
                                      en: 'Transaction result',
                                    ),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontSize: compact ? 18 : 22),
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            child: Text(
                              '$_formattedAmountđ',
                              style: TextStyle(
                                fontSize: compact ? 24 : 28,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Transaction details ──
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 12 : 16),
                    child: Column(
                      children: [
                        _DetailRow(
                          tr(vi: 'Người nhận', en: 'Recipient'),
                          widget.recipient,
                          compact,
                        ),
                        const SizedBox(height: 10),
                        _DetailRow(
                          tr(vi: 'Thời gian', en: 'Time'),
                          _formattedDate,
                          compact,
                        ),
                        const SizedBox(height: 10),
                        _DetailRow(
                          tr(vi: 'Mã giao dịch', en: 'Transaction ID'),
                          widget.transactionId,
                          compact,
                          copyable: true,
                          onCopy: () => _copy(
                            widget.transactionId,
                            tr(vi: 'mã giao dịch', en: 'transaction ID'),
                          ),
                        ),
                        if (widget.senderNote.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _DetailRow(
                            tr(vi: 'Ghi chú', en: 'Note'),
                            widget.senderNote.trim(),
                            compact,
                          ),
                        ],
                        const SizedBox(height: 10),
                        _DetailRow(
                          tr(
                            vi: 'Trạng thái giao dịch',
                            en: 'Transaction status',
                          ),
                          _transactionStatusLabel(),
                          compact,
                        ),
                        if (!_isWaitingForFinalState &&
                            failed &&
                            errMsg.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _MultilineRow(
                            tr(vi: 'Lý do lỗi', en: 'Error reason'),
                            errMsg,
                            compact,
                          ),
                        ],
                        if (!_isWaitingForFinalState &&
                            failed &&
                            _errorCode.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _DetailRow(
                            tr(vi: 'Mã lỗi', en: 'Error code'),
                            _errorCode.trim(),
                            compact,
                          ),
                        ],
                        if (stillProcessing && _waitTimeoutReached) ...[
                          const SizedBox(height: 10),
                          _ProcessingHint(
                            message: tr(
                              vi: 'Giao dịch đang được xử lý. Bạn có thể quay lại, ứng dụng sẽ báo khi hoàn tất.',
                              en: 'Transaction is being processed. You can go back and wait for completion notification.',
                            ),
                          ),
                        ],
                        if (verificationPendingAfterSuccess &&
                            _waitTimeoutReached) ...[
                          const SizedBox(height: 10),
                          _ProcessingHint(
                            message: tr(
                              vi: 'Giao dịch đã thành công, biên nhận đang được xác thực. Ứng dụng sẽ báo khi hoàn tất.',
                              en: 'Transaction is successful. Receipt verification is in progress.',
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _DetailRow(
                          tr(
                            vi: 'Trạng thái xác thực',
                            en: 'Verification status',
                          ),
                          _onChainLabel,
                          compact,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Verifiable receipt ──
                if (_onChainComplete) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 12 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.verified_user_rounded,
                                size: 18,
                                color: AppColors.success,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr(
                                    vi: 'Biên nhận xác thực',
                                    en: 'Verifiable receipt',
                                  ),
                                  style: TextStyle(
                                    fontSize: compact ? 13 : 14,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'BeVietnamPro',
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                              _DownloadBadge(
                                loading: _isDownloadingReceipt,
                                onTap: _downloadReceipt,
                              ),
                              const SizedBox(width: 8),
                              _RevealBadge(
                                revealed: _revealed,
                                hasPinProtection: _hasPinProtection,
                                onTap: _requestReveal,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _ReceiptField(
                            label: tr(
                              vi: 'Mã giao dịch trên chuỗi',
                              en: 'On-chain transaction ID',
                            ),
                            value: _chainTxId,
                            revealed: _revealed,
                            masked: _mask(_chainTxId),
                            display: _short(_chainTxId),
                            onCopy: () => _copy(
                              _chainTxId,
                              tr(
                                vi: 'Mã giao dịch trên chuỗi',
                                en: 'on-chain transaction ID',
                              ),
                            ),
                            compact: compact,
                          ),
                          const SizedBox(height: 10),
                          _ReceiptField(
                            label: tr(vi: 'Số khối', en: 'Block number'),
                            value: '${_blockNumber ?? ''}',
                            revealed: _revealed,
                            masked: _mask('${_blockNumber ?? ''}'),
                            display: '${_blockNumber ?? ''}',
                            compact: compact,
                          ),
                          const SizedBox(height: 10),
                          _ReceiptField(
                            label: tr(vi: 'Mã băm khối', en: 'Block hash'),
                            value: _blockHash,
                            revealed: _revealed,
                            masked: _mask(_blockHash),
                            display: _short(_blockHash),
                            onCopy: () => _copy(
                              _blockHash,
                              tr(vi: 'Mã băm khối', en: 'block hash'),
                            ),
                            compact: compact,
                          ),
                          const SizedBox(height: 10),
                          _ReceiptField(
                            label: tr(
                              vi: 'Mã băm chứng từ',
                              en: 'Receipt hash',
                            ),
                            value: _merkleRoot,
                            revealed: _revealed,
                            masked: _mask(_merkleRoot),
                            display: _short(_merkleRoot),
                            onCopy: () => _copy(
                              _merkleRoot,
                              tr(vi: 'Mã băm chứng từ', en: 'receipt hash'),
                            ),
                            compact: compact,
                          ),
                          const SizedBox(height: 10),
                          _ReceiptField(
                            label: tr(vi: 'Mã cam kết', en: 'Commitment hash'),
                            value: _commitmentHash,
                            revealed: _revealed,
                            masked: _mask(_commitmentHash),
                            display: _short(_commitmentHash),
                            onCopy: () => _copy(
                              _commitmentHash,
                              tr(vi: 'Mã cam kết', en: 'commitment hash'),
                            ),
                            compact: compact,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr(
                              vi: 'Chữ ký xác nhận từ tổ chức độc lập',
                              en: 'Independent organization signatures',
                            ),
                            style: TextStyle(
                              fontSize: compact ? 12 : 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_peerSignatures.isEmpty)
                            Text(
                              _originMspId.trim().isEmpty
                                  ? tr(
                                      vi: 'Biên nhận này chưa có chữ ký xác nhận độc lập.',
                                      en: 'No independent confirmation signature yet.',
                                    )
                                  : tr(
                                      vi: 'Đang chờ chữ ký xác nhận từ các tổ chức độc lập (ngoài ${_toOrgDisplayName(_originMspId)}).',
                                      en: 'Waiting for signatures from independent organizations (excluding ${_toOrgDisplayName(_originMspId)}).',
                                    ),
                              style: TextStyle(
                                fontSize: compact ? 11 : 12,
                                color: scheme.onSurface.withValues(alpha: 0.72),
                              ),
                            )
                          else
                            for (final sig in _peerSignatures) ...[
                              _PeerSignatureRow(
                                compact: compact,
                                label:
                                    '${sig['label'] ?? tr(vi: 'Tổ chức', en: 'Organization')} ${tr(vi: 'xác nhận giao dịch này', en: 'confirmed this transaction')}',
                                signatureHex: sig['signatureHex'] ?? '',
                                fingerprint: sig['fingerprint'] ?? '',
                                confirmedAt: sig['confirmedAt'] ?? '',
                                revealed: _revealed,
                                onCopySignature: () => _copy(
                                  sig['signatureHex'] ?? '',
                                  '${tr(vi: 'chữ ký', en: 'signature')} ${sig['label'] ?? ''}',
                                ),
                                onCopyFingerprint: () => _copy(
                                  sig['fingerprint'] ?? '',
                                  'fingerprint ${sig['label'] ?? ''}',
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          const SizedBox(height: 8),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(bottom: 6),
                            title: Text(
                              tr(
                                vi: 'Chi tiết kiểm chứng',
                                en: 'Verification details',
                              ),
                              style: TextStyle(
                                fontSize: compact ? 12 : 13,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                            children: [
                              if (_commitmentAlgorithm.trim().isNotEmpty) ...[
                                _ReceiptField(
                                  label: tr(
                                    vi: 'Thuật toán băm',
                                    en: 'Hash algorithm',
                                  ),
                                  value: _commitmentAlgorithm,
                                  revealed: _revealed,
                                  masked: _mask(_commitmentAlgorithm),
                                  display: _commitmentAlgorithm,
                                  onCopy: () => _copy(
                                    _commitmentAlgorithm,
                                    tr(
                                      vi: 'Thuật toán băm',
                                      en: 'hash algorithm',
                                    ),
                                  ),
                                  compact: compact,
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (_observationType.trim().isNotEmpty) ...[
                                _ReceiptField(
                                  label: tr(
                                    vi: 'Cơ chế neo',
                                    en: 'Anchoring method',
                                  ),
                                  value: _observationType,
                                  revealed: _revealed,
                                  masked: _mask(_observationType),
                                  display: _formatObservationType(
                                    _observationType,
                                  ),
                                  compact: compact,
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (_observationAt.trim().isNotEmpty) ...[
                                _ReceiptField(
                                  label: tr(
                                    vi: 'Thời điểm ghi nhận',
                                    en: 'Observed at',
                                  ),
                                  value: _observationAt,
                                  revealed: _revealed,
                                  masked: _mask(_observationAt),
                                  display: _observationAt,
                                  compact: compact,
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (_observationRef.trim().isNotEmpty) ...[
                                _ReceiptField(
                                  label: tr(vi: 'Băm neo', en: 'Anchor hash'),
                                  value: _observationRef,
                                  revealed: _revealed,
                                  masked: _mask(_observationRef),
                                  display: _short(_observationRef),
                                  onCopy: () => _copy(
                                    _observationRef,
                                    tr(vi: 'Băm neo', en: 'anchor hash'),
                                  ),
                                  compact: compact,
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (_commitmentOpening.isNotEmpty)
                                _CommitmentOpeningView(
                                  compact: compact,
                                  revealed: _revealed,
                                  opening: _commitmentOpening,
                                  formatEpochMillis: _formatEpochMillis,
                                  formatAmount: _normalizeAmount,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    label: tr(vi: 'Về trang chủ', en: 'Back to home'),
                    icon: Icons.home_rounded,
                    onPressed: _backHome,
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

// ═══════════════════════════════════════════════
//  Widgets
// ═══════════════════════════════════════════════

class _RevealBadge extends StatelessWidget {
  final bool revealed;
  final bool hasPinProtection;
  final VoidCallback onTap;

  const _RevealBadge({
    required this.revealed,
    required this.hasPinProtection,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (revealed) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.lock_open_rounded,
          size: 18,
          color: AppColors.success,
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark
                ? scheme.primary.withValues(alpha: 0.2)
                : AppColors.violet100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            hasPinProtection ? Icons.lock_rounded : Icons.visibility_rounded,
            size: 18,
            color: isDark ? scheme.primaryContainer : AppColors.violet600,
          ),
        ),
      ),
    );
  }
}

class _DownloadBadge extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const _DownloadBadge({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (loading) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? scheme.primary.withValues(alpha: 0.2)
              : AppColors.violet100,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: EdgeInsets.all(9),
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: isDark ? scheme.primaryContainer : AppColors.violet600,
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark
                ? scheme.primary.withValues(alpha: 0.2)
                : AppColors.violet100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.download_rounded,
            size: 18,
            color: isDark ? scheme.primaryContainer : AppColors.violet600,
          ),
        ),
      ),
    );
  }
}

class _ReceiptField extends StatelessWidget {
  final String label;
  final String value;
  final bool revealed;
  final String masked;
  final String display;
  final VoidCallback? onCopy;
  final bool compact;

  const _ReceiptField({
    required this.label,
    required this.value,
    required this.revealed,
    required this.masked,
    required this.display,
    this.onCopy,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = revealed ? display : masked;
    final empty = value.trim().isEmpty;

    return Row(
      children: [
        SizedBox(
          width: compact ? 110 : 140,
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: scheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            empty ? '—' : shown,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w700,
              color: revealed
                  ? scheme.onSurface
                  : scheme.onSurface.withValues(alpha: 0.62),
              fontFamily: revealed ? null : 'monospace',
            ),
          ),
        ),
        SizedBox(
          width: 32,
          height: 24,
          child: (revealed && onCopy != null && !empty)
              ? IconButton(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CommitmentOpeningView extends StatelessWidget {
  final bool compact;
  final bool revealed;
  final Map<String, dynamic> opening;
  final String Function(dynamic) formatEpochMillis;
  final String Function(dynamic) formatAmount;

  const _CommitmentOpeningView({
    required this.compact,
    required this.revealed,
    required this.opening,
    required this.formatEpochMillis,
    required this.formatAmount,
  });

  String _mask(String value) {
    if (value.isEmpty) return '—';
    if (value.length <= 8) return '•' * value.length;
    return '${value.substring(0, 4)}${'•' * (value.length - 8).clamp(4, 20)}${value.substring(value.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tr = AppLocalizations.pick;
    final fromId = '${opening['from_id'] ?? ''}';
    final toId = '${opening['to_id'] ?? ''}';
    final amount = '${formatAmount(opening['amount_vnd'])}đ';
    final ref = '${opening['internal_ref'] ?? ''}';
    final timestamp = formatEpochMillis(opening['timestamp']);
    final nonce = '${opening['nonce'] ?? ''}';

    final rows = <MapEntry<String, String>>[
      MapEntry(tr(vi: 'Dữ liệu đối chiếu', en: 'Reference data'), ''),
      MapEntry(tr(vi: 'Người gửi', en: 'Sender'), fromId),
      MapEntry(tr(vi: 'Người nhận', en: 'Recipient'), toId),
      MapEntry(tr(vi: 'Số tiền', en: 'Amount'), amount),
      MapEntry(tr(vi: 'Mã tham chiếu', en: 'Reference ID'), ref),
      MapEntry(tr(vi: 'Thời điểm gửi', en: 'Submitted at'), timestamp),
      MapEntry('Nonce', nonce),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surface.withValues(alpha: 0.82)
            : AppColors.violet50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i == 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  rows[i].key,
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              _DetailRow(
                rows[i].key,
                revealed ? rows[i].value : _mask(rows[i].value),
                compact,
              ),
            if (i != rows.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _PeerSignatureRow extends StatelessWidget {
  final bool compact;
  final String label;
  final String signatureHex;
  final String fingerprint;
  final String confirmedAt;
  final bool revealed;
  final VoidCallback onCopySignature;
  final VoidCallback onCopyFingerprint;

  const _PeerSignatureRow({
    required this.compact,
    required this.label,
    required this.signatureHex,
    required this.fingerprint,
    required this.confirmedAt,
    required this.revealed,
    required this.onCopySignature,
    required this.onCopyFingerprint,
  });

  String _short(String v, {int keep = 8}) {
    if (v.length <= keep * 2 + 3) return v;
    return '${v.substring(0, keep)}...${v.substring(v.length - keep)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tr = AppLocalizations.pick;
    final styleLabel = TextStyle(
      fontSize: compact ? 12 : 13,
      color: scheme.onSurface.withValues(alpha: 0.82),
      fontWeight: FontWeight.w600,
    );
    final styleValue = TextStyle(
      fontSize: compact ? 11 : 12,
      color: scheme.onSurface.withValues(alpha: 0.68),
      fontFamily: revealed ? null : 'monospace',
    );
    final shownSignature = revealed ? _short(signatureHex) : '••••••••';
    final shownFingerprint = revealed ? _short(fingerprint) : '••••••••';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surface.withValues(alpha: 0.82)
            : AppColors.violet50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: styleLabel),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${tr(vi: 'Chữ ký', en: 'Signature')}: ${signatureHex.isEmpty ? "—" : shownSignature}',
                  style: styleValue,
                ),
              ),
              if (revealed && signatureHex.isNotEmpty)
                IconButton(
                  onPressed: onCopySignature,
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  splashRadius: 14,
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Fingerprint: ${fingerprint.isEmpty ? "—" : shownFingerprint}',
                  style: styleValue,
                ),
              ),
              if (revealed && fingerprint.isNotEmpty)
                IconButton(
                  onPressed: onCopyFingerprint,
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  splashRadius: 14,
                ),
            ],
          ),
          Text(
            '${tr(vi: 'Thời điểm xác nhận', en: 'Confirmed at')}: ${confirmedAt.trim().isEmpty ? "—" : confirmedAt.trim()}',
            style: styleValue,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;
  final bool copyable;
  final VoidCallback? onCopy;

  const _DetailRow(
    this.label,
    this.value,
    this.compact, {
    this.copyable = false,
    this.onCopy,
  });

  String _truncate(String v, {int keep = 10}) {
    if (v.length <= keep * 2 + 3) return v;
    return '${v.substring(0, keep)}...${v.substring(v.length - keep)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayValue = copyable ? _truncate(value) : value;
    return Row(
      children: [
        SizedBox(
          width: compact ? 110 : 140,
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: scheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            displayValue,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ),
        if (copyable && onCopy != null) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: 28,
            height: 24,
            child: IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 14,
              color: scheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ],
      ],
    );
  }
}

class _MultilineRow extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;

  const _MultilineRow(this.label, this.value, this.compact);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            color: scheme.onSurface.withValues(alpha: 0.68),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? scheme.surface.withValues(alpha: 0.84)
                : AppColors.violet50.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProcessingHint extends StatelessWidget {
  final String message;

  const _ProcessingHint({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? scheme.primary.withValues(alpha: 0.16)
            : AppColors.vanilla100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isDark
              ? scheme.onSurface.withValues(alpha: 0.84)
              : AppColors.ink700,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}

// ── PIN dialog ──
class _PinRevealDialog extends StatefulWidget {
  final AuthService authService;
  const _PinRevealDialog({required this.authService});

  @override
  State<_PinRevealDialog> createState() => _PinRevealDialogState();
}

class _PinRevealDialogState extends State<_PinRevealDialog> {
  final _pinController = TextEditingController();
  bool _verifying = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verifyPin() async {
    if (_verifying) return;
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(
        () => _errorText = AppLocalizations.pick(
          vi: 'PIN gồm đúng 6 chữ số.',
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
    if (!mounted) return;
    if (!valid) {
      setState(() {
        _verifying = false;
        _errorText = AppLocalizations.pick(
          vi: 'PIN không chính xác.',
          en: 'Incorrect PIN.',
        );
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.pick;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(vi: 'Xác thực PIN', en: 'Verify PIN'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'BeVietnamPro',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  vi: 'Nhập PIN để xem chi tiết biên nhận xác minh.',
                  en: 'Enter PIN to view verified receipt details.',
                ),
              ),
              const SizedBox(height: 12),
              PinCodeBoxes(
                controller: _pinController,
                enabled: !_verifying,
                autofocus: true,
                label: tr(vi: 'PIN bảo mật', en: 'Security PIN'),
                helperText: tr(
                  vi: 'Nhập đủ 6 chữ số.',
                  en: 'Enter all 6 digits.',
                ),
                errorText: _errorText,
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
                onCompleted: (_) => _verifyPin(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _verifying
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(tr(vi: 'Hủy', en: 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _verifying ? null : _verifyPin,
                      child: _verifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(tr(vi: 'Xác nhận', en: 'Confirm')),
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
