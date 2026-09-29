/// PartialAddress — Incomplete address detected from GPS
///
/// When GPS detects location, we only get city/area/pincode.
/// House number, street, landmark are NOT available from GPS.
/// Those will be asked from user at checkout time.
///
/// Used in:
/// - LocationProvider (after GPS detection)
/// - ProximityProvider (for distance comparison)
/// - Home screen header ("Sector 70, Mohali")
/// - Checkout form (pre-fill detected fields)
class PartialAddress {
  /// Area or locality — e.g. "Sector 70", "Koharapeer"
  /// Comes from GPS reverse geocode (subLocality field)
  final String? area;

  /// City name — e.g. "Mohali", "Bareilly"
  /// Comes from GPS reverse geocode (locality field)
  final String? city;

  /// State name — e.g. "Punjab", "Uttar Pradesh"
  /// Comes from GPS reverse geocode (administrativeArea field)
  final String? state;

  /// Postal code — e.g. "160071", "243003"
  /// Comes from GPS reverse geocode (postalCode field)
  final String? pincode;

  /// Exact GPS latitude — e.g. 30.7046
  /// Comes directly from device GPS chip
  final double latitude;

  /// Exact GPS longitude — e.g. 76.7179
  /// Comes directly from device GPS chip
  final double longitude;

  PartialAddress({
    this.area,
    this.city,
    this.state,
    this.pincode,
    required this.latitude,
    required this.longitude,
  });

  /// Short display string for home screen header
  /// Returns: "Sector 70, Mohali" (area + city)
  /// If area is not available, returns just city
  /// If nothing available, returns "Current Location"
  String get displayName {
    final parts = <String>[];
    if (area != null && area!.isNotEmpty) parts.add(area!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (parts.isEmpty && state != null) parts.add(state!);
    return parts.isNotEmpty ? parts.join(', ') : 'Current Location';
  }

  /// Full display string with pincode for checkout form
  /// Returns: "Sector 70, Mohali, Punjab - 160071"
  /// Shows all available fields with pincode at end
  String get fullDisplay {
    final parts = <String>[];
    if (area != null && area!.isNotEmpty) parts.add(area!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (state != null && state!.isNotEmpty) parts.add(state!);
    String result = parts.join(', ');
    if (pincode != null && pincode!.isNotEmpty) {
      result += ' - $pincode';
    }
    return result.isNotEmpty ? result : 'Current Location';
  }
}
