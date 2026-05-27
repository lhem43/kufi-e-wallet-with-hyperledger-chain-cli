/// In-memory singleton that tracks PIN verification state for the current
/// app session.  Once the user enters their PIN to reveal their balance or
/// receipt details, subsequent requests are auto-approved until the session
/// is explicitly cleared (e.g. on logout).
class PinSessionService {
  PinSessionService._();
  static final PinSessionService _instance = PinSessionService._();
  factory PinSessionService() => _instance;

  bool _balanceUnlocked = false;
  bool _receiptUnlocked = false;

  /// Whether the balance has already been PIN-unlocked this session.
  bool get isBalanceUnlocked => _balanceUnlocked;

  /// Whether receipt details have already been PIN-unlocked this session.
  bool get isReceiptUnlocked => _receiptUnlocked;

  /// Call after the user successfully verifies their PIN for balance.
  void markBalanceUnlocked() => _balanceUnlocked = true;

  /// Call after the user successfully verifies their PIN for receipts.
  void markReceiptUnlocked() => _receiptUnlocked = true;

  /// Reset all unlocks (e.g. when the user logs out).
  void clear() {
    _balanceUnlocked = false;
    _receiptUnlocked = false;
  }
}
