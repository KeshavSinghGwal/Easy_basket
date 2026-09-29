import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/address_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/location_provider.dart';
import '../providers/order_provider.dart';
import '../providers/proximity_provider.dart';
import '../services/notification_service.dart';

/// Ends the current session and clears everything scoped to the user who was
/// signed in.
///
/// This exists as ONE function because teardown used to be spread across call
/// sites, and only one of them was complete. The profile screen reset Location,
/// Address and Proximity but neither the cart nor the order list; the admin and
/// delivery dashboards reset nothing at all and just called `logout()`.
/// `AuthProvider.logout()` itself only clears tokens and `user_data` — the
/// `cart_items` key in SharedPreferences survived, as did `OrderProvider._orders`
/// in memory.
///
/// On a shared, borrowed or resold device that meant the next person to sign in
/// inherited the previous user's basket, and — until the first refetch — their
/// order list, which carries names, phone numbers and full delivery addresses.
/// Beyond the privacy exposure it produced genuinely wrong orders: user B
/// checking out with the items user A chose, priced against A's stale snapshot.
///
/// Every logout button must call this and nothing else. Adding a new
/// user-scoped provider means adding one line here, not auditing three screens.
Future<void> endSession(BuildContext context) async {
  // Resolve every provider BEFORE the first await. Reading them off `context`
  // afterwards would be a use-across-async-gap, and this runs while the screen
  // is on its way out.
  final auth = Provider.of<AuthProvider>(context, listen: false);
  final cart = Provider.of<CartProvider>(context, listen: false);
  final orders = Provider.of<OrderProvider>(context, listen: false);
  final addresses = Provider.of<AddressProvider>(context, listen: false);
  final location = Provider.of<LocationProvider>(context, listen: false);
  final proximity = Provider.of<ProximityProvider>(context, listen: false);

  // Unsubscribe first, so a push aimed at the outgoing user cannot land
  // mid-teardown and deep-link the incoming one into their order.
  NotificationService().unsubscribeCurrentTopic();

  location.reset();
  addresses.reset();
  proximity.reset();
  orders.reset();
  await cart.clear();

  // Last: revokes the refresh token server-side and clears stored credentials.
  // Also notifies AuthRefreshNotifier, which makes the router re-evaluate its
  // guards and push any gated screen back to /login.
  await auth.logout();
}
