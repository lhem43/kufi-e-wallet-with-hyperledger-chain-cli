import 'dart:async';
import 'dart:ui' show VoidCallback;

/// Singleton service that tracks user inactivity and triggers a callback
/// when the idle timeout expires — similar to banking apps like Techcombank.
class IdleTimeoutService {
  IdleTimeoutService._();
  static final IdleTimeoutService _instance = IdleTimeoutService._();
  factory IdleTimeoutService() => _instance;

  /// Default idle timeout duration (5 minutes, matching JWT access TTL).
  static const Duration defaultTimeout = Duration(minutes: 5);

  Timer? _timer;
  Duration _timeout = defaultTimeout;
  VoidCallback? _onTimeout;
  bool _active = false;

  /// Whether the idle timer is currently running.
  bool get isActive => _active;

  /// Current timeout duration.
  Duration get timeout => _timeout;

  /// Start tracking idle time with the given [onTimeout] callback.
  /// Call this once when the user is authenticated.
  void start({
    required VoidCallback onTimeout,
    Duration? timeout,
  }) {
    _onTimeout = onTimeout;
    _timeout = timeout ?? defaultTimeout;
    _active = true;
    _resetTimer();
  }

  /// Reset the idle timer. Call this on every user interaction.
  void resetTimer() {
    if (!_active) return;
    _resetTimer();
  }

  /// Stop tracking and cancel the timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _active = false;
    _onTimeout = null;
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(_timeout, () {
      if (_active) {
        _active = false;
        _onTimeout?.call();
      }
    });
  }
}
