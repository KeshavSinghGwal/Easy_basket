import 'package:easy_basket/models/address_model.dart';
import 'package:easy_basket/models/partial_address_model.dart';

/// ProximityDecision — What should the app do based on GPS vs saved address distance
///
/// This enum represents the decision engine's output.
/// The app checks how far the user is from their saved addresses
/// and decides one of these 4 actions.
enum ProximityDecision {
  /// Distance < 5km — User is near a saved address
  /// Action: Auto-select that address, no UI interruption
  /// Example: User is at home, Home address auto-selected
  autoSelect,

  /// Distance 5-20km — User is somewhat far from saved address
  /// Action: Select nearest address BUT show a warning banner
  /// Example: "You're 15km away from Home address"
  /// User can choose to continue or use current location
  warn,

  /// Distance > 20km — User is in a completely different city
  /// Action: Don't auto-select any address, show mismatch screen
  /// At checkout, ask user to complete a new address
  /// Example: User in Mohali, saved address in Bareilly (500km)
  forceNew,

  /// GPS not available — Permission denied or GPS turned off
  /// Action: Fall back to default saved address (current behavior)
  /// Show subtle "Enable location for faster delivery" banner
  noGps,
}

/// ProximityResult — Complete result of distance check between GPS and saved addresses
///
/// This class holds everything the UI needs to decide what to show:
/// - Which address to select (or none)
/// - Whether to show warning banner
/// - Whether to show mismatch screen
/// - Whether user needs to fill address form at checkout
///
/// Used in:
/// - Home screen: Decides header style, warning banner, mismatch screen
/// - Checkout: Checks if address completion form is needed
class ProximityResult {
  /// The decision — what should the app do
  final ProximityDecision decision;

  /// Distance to nearest saved address in kilometers
  /// null if no saved addresses exist or GPS not available
  final double? distanceKm;

  /// The saved address closest to user's GPS location
  /// null if no saved addresses exist
  final AddressModel? nearestAddress;

  /// Partial address detected from GPS (city, area, pincode only)
  /// Available whenever GPS is working
  final PartialAddress? partialAddress;

  /// True when nearest saved address is within ~200m (spec Case A — “verified” match).
  final bool isWithinExactMatch;

  ProximityResult({
    required this.decision,
    this.distanceKm,
    this.nearestAddress,
    this.partialAddress,
    this.isWithinExactMatch = false,
  });

  /// Should we show address completion form at checkout?
  /// True when: user is in new location (forceNew) or no GPS and no saved address
  /// This means we have partial address but need house no, street, landmark from user
  bool get needsAddressCompletion =>
      decision == ProximityDecision.forceNew ||
      (decision == ProximityDecision.noGps && nearestAddress == null);

  /// Should we show warning banner on home screen?
  /// True when: user is 5-20km from nearest saved address
  bool get showWarning => decision == ProximityDecision.warn;

  /// True when user has saved address(es) and GPS is far (>20km). Home may still **skip**
  /// the mismatch route if current GPS pincode is serviceable (deliver at current location).
  bool get showMismatchScreen =>
      decision == ProximityDecision.forceNew && nearestAddress != null;

  /// Should we show "Enable location" subtle banner?
  /// True when: GPS permission denied or GPS turned off
  bool get showEnableLocationBanner => decision == ProximityDecision.noGps;

  /// Warning banner text
  /// Example: "You're 15.3km away from Home address"
  String get warningText {
    if (distanceKm == null || nearestAddress == null) return '';
    final tag = nearestAddress!.tag ?? 'saved';
    final dist = distanceKm!.toStringAsFixed(1);
    return "You're ${dist}km away from $tag address";
  }
}
