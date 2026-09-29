import 'package:flutter/foundation.dart';
import '../models/store_status_model.dart';
import '../services/api_service.dart';

/// Whether the store is accepting new orders.
///
/// FAIL-OPEN by design. Before the first fetch, and after any failed fetch, we
/// report the store as OPEN. Blocking checkout because a status request timed
/// out would cost a real sale to fix a problem that may not exist — and it
/// isn't needed, because `POST /api/orders` re-checks server-side and returns
/// 409 STORE_CLOSED if the store really is shut. This provider drives UX; the
/// server is the gate.
class StoreStatusProvider with ChangeNotifier {
  StoreStatusProvider({ApiService? apiService})
      : apiService = apiService ?? ApiService();

  final ApiService apiService;

  StoreStatusModel _status = StoreStatusModel.open;
  bool _isLoading = false;
  DateTime? _lastFetchedAt;

  StoreStatusModel get status => _status;
  bool get isOpen => _status.isOpen;
  bool get isClosed => !_status.isOpen;
  bool get isLoading => _isLoading;
  DateTime? get lastFetchedAt => _lastFetchedAt;

  /// Ignore refresh requests that land within this window of the last one.
  /// App resume, home rebuild and a pull-to-refresh can otherwise fire three
  /// requests inside a second.
  static const _minInterval = Duration(seconds: 3);

  /// Past this age the cached status is too stale to gate checkout on.
  static const _staleAfter = Duration(seconds: 30);

  bool get _isStale {
    final at = _lastFetchedAt;
    return at == null || DateTime.now().difference(at) > _staleAfter;
  }

  /// Fetch current status.
  ///
  /// [force] skips the throttle — use it where correctness beats chattiness
  /// (opening checkout, retrying after a rejected order).
  Future<void> refresh({bool force = false}) async {
    if (!force && _lastFetchedAt != null) {
      if (DateTime.now().difference(_lastFetchedAt!) < _minInterval) return;
    }
    if (_isLoading) return;

    _isLoading = true;
    // No notify here — a spinner on this would flash the whole home screen on
    // every resume. Listeners only need to hear about the settled result.

    try {
      final response = await apiService.get('/store/status');
      final next = StoreStatusModel.fromJson(response as Map<String, dynamic>);
      final changed = next.isOpen != _status.isOpen ||
          next.headline != _status.headline ||
          next.expectedReopenAt != _status.expectedReopenAt;

      _status = next;
      _lastFetchedAt = DateTime.now();
      _isLoading = false;

      if (changed) {
        notifyListeners();
      }
      if (kDebugMode) {
        debugPrint('🏪 [StoreStatus] ${next.isOpen ? "OPEN" : "CLOSED (${next.reason.apiValue})"}');
      }
    } catch (e) {
      // Fail open. Deliberately does NOT reset _status to open — if we already
      // know the store is closed, a dropped request is no reason to invite the
      // user into a checkout the server will reject.
      _isLoading = false;
      if (kDebugMode) {
        debugPrint('⚠️ [StoreStatus] fetch failed, keeping last known state: $e');
      }
    }
  }

  /// Refresh only if the cached value is old enough to be untrustworthy.
  /// Call before showing checkout so the user isn't gated on a stale flag.
  Future<void> ensureFresh() async {
    if (_isStale) await refresh(force: true);
  }

  /// Admin: flip the store open/closed.
  ///
  /// Returns null on success, or an error message to surface. Unlike the read
  /// path this does NOT fail silently — an admin who thinks they closed the
  /// store but didn't is the worst possible outcome here.
  Future<String?> updateStatus({
    required String token,
    required bool isOpen,
    StoreClosedReason? closedReason,
    String? customMessage,
    DateTime? expectedReopenAt,
    bool notifyOnReopen = false,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await apiService.put(
        '/admin/store/status',
        {
          'isOpen': isOpen,
          if (!isOpen) 'closedReason': (closedReason ?? StoreClosedReason.other).apiValue,
          if (!isOpen && customMessage != null && customMessage.trim().isNotEmpty)
            'customMessage': customMessage.trim(),
          // Send UTC — the backend stores UTC and the app converts back on read.
          if (!isOpen && expectedReopenAt != null)
            'expectedReopenAt': expectedReopenAt.toUtc().toIso8601String(),
          if (isOpen) 'notifyOnReopen': notifyOnReopen,
        },
        token: token,
      );

      final map = response as Map<String, dynamic>;
      if (map['status'] != null) {
        _status = StoreStatusModel.fromJson(map['status'] as Map<String, dynamic>);
        _lastFetchedAt = DateTime.now();
      }
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return e.toString().replaceAll('Exception: ', '');
    }
  }
}
