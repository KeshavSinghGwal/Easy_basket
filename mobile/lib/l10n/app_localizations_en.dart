// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonTryAgain => 'Try Again';

  @override
  String get commonOk => 'OK';

  @override
  String get commonNotNow => 'Not now';

  @override
  String get commonEnable => 'Enable';

  @override
  String get commonLater => 'Later';

  @override
  String get commonOpenSettings => 'Open Settings';

  @override
  String get commonLoginFirst => 'Please login first';

  @override
  String get commonSessionExpired => 'Session expired. Please login again.';

  @override
  String commonError(String message) {
    return 'Error: $message';
  }

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSubtitle =>
      'Choose the language you want to use in the app';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languagePunjabi => 'Punjabi';

  @override
  String get languageUpdated => 'Language updated';

  @override
  String get languageChangeFailed =>
      'Could not change language. Please try again.';

  @override
  String get homeLocationDetected => 'Location detected! Start shopping now.';

  @override
  String get homeLowestPrices => 'Lowest Prices, ';

  @override
  String get homeShopNow => 'Shop Now!!';

  @override
  String get authEnterPhone => 'Enter your phone number';

  @override
  String get authOtpSent => 'OTP sent successfully!';

  @override
  String get authEnterOtp => 'Please enter 6-digit OTP';

  @override
  String get authInvalidPhone => 'Please enter a valid 10-digit phone number';

  @override
  String get locationAddManually => 'Add Address Manually';

  @override
  String get locationConfirmContinue => 'Confirm & Continue';

  @override
  String get locationSaved => 'Location saved! Start shopping now.';

  @override
  String get locationRefine => 'Refine Location';

  @override
  String get locationGrantPermission => 'Grant Location Permission';

  @override
  String get locationTurnOn => 'Turn on Location';

  @override
  String get locationRequired => 'Location permission is required';

  @override
  String get locationEnableInSettings =>
      'Please enable location in phone Settings';

  @override
  String get locationUseCurrent => 'Use Current Location';

  @override
  String get locationSelect => 'Select Location';

  @override
  String get locationUnableToGet =>
      'Unable to get your location. Please try again.';

  @override
  String get locationWaitAddress =>
      'Please wait for address to load completely';

  @override
  String get locationWaitLocation =>
      'Please wait for location to load or select a valid location';

  @override
  String get locationCouldNotDetect =>
      'Could not detect location. Try map picker.';

  @override
  String get locationDetectedFillDetails =>
      'Location detected! Fill remaining details.';

  @override
  String get locationSelectedFillDetails =>
      'Location selected! Fill remaining details.';

  @override
  String get locationSelectFirst =>
      'Please select your location first (GPS or Map)';

  @override
  String get locationDetectViaGps => 'Detect via GPS';

  @override
  String get locationPickOnMap => 'Pick on Map';

  @override
  String get locationChooseFromMap => 'Choose from map';

  @override
  String get serviceNotAvailable => 'Service Not Available';

  @override
  String get categoryViewAllProducts => 'View All Products';

  @override
  String get productAboutThis => 'About this product';

  @override
  String get productDeliveryTime => 'Delivery in 5-15 mins';

  @override
  String get productImageNotAvailable => 'Image not available';

  @override
  String get productImageUnavailable => 'Image unavailable';

  @override
  String get productSelectQuantity => 'Select Quantity';

  @override
  String get productSearchHint => 'Search products...';

  @override
  String get productMicPermission => 'Microphone permission needed';

  @override
  String get orderMyOrders => 'My Orders';

  @override
  String get orderCancelOrder => 'Cancel Order';

  @override
  String get orderCancelAnyway => 'Cancel anyway';

  @override
  String get orderCancelQuestion => 'Cancel order?';

  @override
  String get orderCancellationRequested => 'Cancellation requested';

  @override
  String get orderContactDriver => 'Contact Driver';

  @override
  String get orderDeliveringTo => 'Delivering To';

  @override
  String get orderDriverOnWay => 'Driver is on the way!';

  @override
  String get orderStoreName => 'Easy Basket Store';

  @override
  String get orderKeepOrder => 'Keep order';

  @override
  String get orderLiveTracking => 'Live Order Tracking';

  @override
  String get orderMapNotAvailableWeb => 'Map not available on web';

  @override
  String get orderMapNotAvailable => 'Map not available';

  @override
  String get orderDetails => 'Order Details';

  @override
  String get orderPayment => 'Payment';

  @override
  String get orderRefund => 'Refund';

  @override
  String get orderTotalAmount => 'Total Amount';

  @override
  String get orderTrackOrder => 'Track Order';

  @override
  String get orderWhyCancelling => 'Why are you cancelling?';

  @override
  String get orderYourLocation => 'Your Location';

  @override
  String get orderPrevCancelDeclined =>
      'Your previous cancellation request was declined.';

  @override
  String orderReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get paymentTitle => 'Payment';

  @override
  String paymentItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get paymentNotesHint => 'Any special instructions... (optional)';

  @override
  String get paymentCardsUpi => 'Cards, UPI, Wallets, Netbanking';

  @override
  String get paymentCod => 'Cash on Delivery';

  @override
  String get paymentDeliveryNotes => 'Delivery Notes';

  @override
  String paymentExternalWallet(String wallet) {
    return 'External wallet selected: $wallet';
  }

  @override
  String get paymentInitFailed =>
      'Failed to initialize payment. Please try again.';

  @override
  String get paymentInvalidMissing =>
      'Invalid payment response. Missing payment details.';

  @override
  String get paymentInvalidResponse =>
      'Invalid payment response. Please try again.';

  @override
  String get paymentOnline => 'Online Payment';

  @override
  String get paymentPayOnReceive => 'Pay when you receive';

  @override
  String get paymentWebOnlyCod =>
      'Online payment is currently available on mobile app only. Please use Cash on Delivery or test on Android/iOS.';

  @override
  String get paymentOrderSummary => 'Order Summary';

  @override
  String get paymentMethod => 'Payment Method';

  @override
  String get paymentLoginToContinue => 'Please login to continue.';

  @override
  String get paymentSelectAddress => 'Please select an address';

  @override
  String get paymentTotal => 'Total';

  @override
  String get paymentUnableIdentifyOrder =>
      'Unable to identify order. Please check your orders.';

  @override
  String get paymentVerifying => 'Verifying payment...';

  @override
  String get paymentTurnOnNotifications => 'Turn On Notifications';

  @override
  String get addressDetails => 'Address Details';

  @override
  String get addressSaved => 'Address saved!';

  @override
  String get addressUpdated => 'Address updated';

  @override
  String get addressSave => 'Save Address';

  @override
  String get addressSaveAs => 'Save as';

  @override
  String get addressLocation => 'Location';

  @override
  String get addressAdd => 'Add Address';

  @override
  String get addressAddNew => 'Add New Address';

  @override
  String get addressAddToStart => 'Add a delivery address to get started';

  @override
  String get addressChooseDelivery => 'Choose Delivery Address';

  @override
  String get addressContinueToPayment => 'Continue to Payment';

  @override
  String get addressNoneFound => 'No addresses found';

  @override
  String get addressSearchHint => 'Search area, street, landmark...';

  @override
  String get addressYourSaved => 'Your Saved Addresses';

  @override
  String addressSavedCount(int count) {
    return '$count saved';
  }

  @override
  String get addressSetDefault => 'Set as default address';

  @override
  String get addressSearchTitle => 'Search Address';

  @override
  String get addressSearchYourArea => 'Search your area, street, sector...';

  @override
  String get profileCustomer => 'Customer';

  @override
  String get profileOrders => 'Orders';

  @override
  String get profileAddresses => 'Addresses';

  @override
  String get profileRating => 'Rating';

  @override
  String get profileAccount => 'Account';

  @override
  String get profileEditProfile => 'Edit Profile';

  @override
  String get profileMyOrders => 'My Orders';

  @override
  String get profileMyAddresses => 'My Addresses';

  @override
  String get profilePreferences => 'Preferences';

  @override
  String get profileSupport => 'Support';

  @override
  String get profileHelpSupport => 'Help & Support';

  @override
  String get profileHelpComingSoon => 'Help & Support coming soon';

  @override
  String get profileAbout => 'About';

  @override
  String get profileAboutApp => 'About Easy Basket';

  @override
  String get profileLogout => 'Logout';

  @override
  String get profileLogoutConfirm => 'Are you sure you want to logout?';

  @override
  String get cartTitle => 'My Cart';

  @override
  String cartItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get cartEmpty => 'Your cart is empty';

  @override
  String get cartEmptySubtitle => 'Add items to your cart to get started';

  @override
  String get cartStartShopping => 'Start Shopping';

  @override
  String get cartRemoveItem => 'Remove Item';

  @override
  String get cartSubtotal => 'Subtotal';

  @override
  String get cartDeliveryFee => 'Delivery Fee';

  @override
  String get cartTotal => 'Total';

  @override
  String get cartAddressRequired => 'Delivery address required';

  @override
  String get cartAddAddressToProceed => 'Add address to proceed';

  @override
  String get cartAddAddressFirst => 'Please add a delivery address first';

  @override
  String get cartStoreClosed => 'Store Closed';

  @override
  String get cartLoginToCheckout => 'Login to Checkout';

  @override
  String get cartAddAddressToCheckout => 'Add Address to Checkout';

  @override
  String get cartProceedToCheckout => 'Proceed to Checkout';

  @override
  String cartPerUnit(String unit) {
    return 'Per $unit';
  }

  @override
  String get profileUpdated => 'Profile updated successfully!';

  @override
  String get profileFullName => 'Full Name';

  @override
  String get profileFullNameHint => 'Enter your full name';

  @override
  String get profileEmail => 'Email';

  @override
  String get profilePhoneNumber => 'Phone Number';

  @override
  String get profileBirthday => 'Birthday';

  @override
  String get profileBirthdayHint => 'Select your birthday';

  @override
  String get homeAddAddressToOrder =>
      'Add your delivery address to place orders';

  @override
  String get homeChange => 'Change';

  @override
  String get homeCheckBackSoon => 'Check back soon!';

  @override
  String get homeEnableLocationFast => 'Enable location for faster delivery';

  @override
  String get homeNoProducts => 'No products available';

  @override
  String get homeShopByCategory => 'Shop by category';

  @override
  String get homeSnackItAway => 'Snack it away';

  @override
  String get commonViewAll => 'View All';

  @override
  String get commonSeeAll => 'see all';

  @override
  String get productAddToCart => 'Add to cart';

  @override
  String get productOutOfStock => 'Out of stock';

  @override
  String get productUnavailableNow => 'Product unavailable right now';

  @override
  String get productDetailsMissing =>
      'Some details are missing for this product. You can still add it to cart.';

  @override
  String get productYouMayAlsoLike => 'You may also like';

  @override
  String get productNoneFound => 'No products found';

  @override
  String get productAdd => 'ADD';

  @override
  String get productOutOfStockCaps => 'Out of Stock';

  @override
  String get productMicPermissionLong =>
      'Easy Basket needs microphone permission to hear you. Please allow it in Settings.';

  @override
  String get categoryAll => 'All Categories';

  @override
  String get categoryNoneAvailable => 'No categories available';

  @override
  String get categoryNoSubcategories => 'No subcategories available';

  @override
  String get orderLoading => 'Loading your orders...';

  @override
  String get orderNoneYet => 'No orders yet';

  @override
  String get orderSomethingWrong => 'Oops! Something went wrong';

  @override
  String get orderStartShoppingHint => 'Start shopping to see your orders here';

  @override
  String get orderViewDetails => 'View Details';

  @override
  String get orderEta15 => 'ETA ~15 mins';

  @override
  String get orderNeedHelp => 'Need Help?';

  @override
  String get orderNotFound => 'Order not found';

  @override
  String get orderFetchingDetails =>
      'Please wait while we fetch your order details';

  @override
  String get orderTrackYourOrder => 'Track Your Order';

  @override
  String get orderYourDeliveryPartner => 'Your Delivery Partner';

  @override
  String get orderPackedNoRefund =>
      'Your order is already packed. Cancelling now will NOT refund your payment. Do you want to continue?';

  @override
  String get profileEditTitle => 'Edit Profile';

  @override
  String get profilePhotoComingSoon => 'Photo upload coming soon';

  @override
  String get profilePicture => 'Profile Picture';

  @override
  String get profileSaveChanges => 'Save Changes';

  @override
  String get profileNotifications => 'Notifications';

  @override
  String get profileEnableNotifHint =>
      'Allow notifications for Easy Basket in your phone settings to turn this on.';

  @override
  String get paymentMaybeLater => 'Maybe Later';

  @override
  String get paymentStayUpdated => 'Stay updated on your order!';

  @override
  String get paymentNotifHint =>
      'Turn on notifications to receive real-time order updates & delivery alerts.';

  @override
  String get authTerms =>
      'By continuing, you agree to our Terms of Service\nand Privacy Policy';

  @override
  String get authChangePhone => 'Change phone number';

  @override
  String get authTagline => 'Fresh groceries at your doorstep';

  @override
  String get authLoginSignup => 'Login / Sign up';

  @override
  String get authVerifyOtp => 'Verify OTP';

  @override
  String get addressAddTitle => 'Add Address';

  @override
  String get addressEditTitle => 'Edit Address';

  @override
  String get addressLabelCaps => 'ADDRESS';

  @override
  String get addressDefaultCaps => 'DEFAULT';

  @override
  String get addressUseSavedAnyway => 'Use Saved Address Anyway';

  @override
  String get addressEnterManually => 'Enter Manually';

  @override
  String get addressSearchByArea =>
      'Search by area, street name, sector, or landmark';

  @override
  String get addressSelectedLocation => 'Selected Location:';

  @override
  String get addressNotifyMe => 'Notify Me';

  @override
  String get addressWillNotify => 'We will notify you!';

  @override
  String get locationAllowAccess => 'Allow location access';

  @override
  String get locationAllowForDelivery => 'Allow location for delivery';

  @override
  String get locationEnterManually => 'Enter address manually instead';

  @override
  String get locationFreshGroceries => 'Fresh groceries in minutes';

  @override
  String get locationGroceriesFast => 'Groceries, delivered fast';

  @override
  String get locationIsOff => 'Location is off';

  @override
  String get locationShareOnce =>
      'Share your location once so we can find your area, show accurate prices, and deliver to the right address.';

  @override
  String get locationChangeAnytime =>
      'You can change this anytime in settings.';

  @override
  String get locationDetecting => 'Detecting your location...';

  @override
  String get locationAccessRequired => 'Location Access Required';

  @override
  String get locationPrivacyNote =>
      'Your location is only used to find your delivery address. We never share it with anyone.';

  @override
  String get locationMapMobileOnly => 'Map View Available on Mobile';

  @override
  String get locationMapMobileHint =>
      'For the best experience with interactive map and draggable pin, please use the mobile app.';

  @override
  String get serviceGoHome => 'Go to Home';

  @override
  String get serviceSelectedLocation => 'Selected Location';

  @override
  String get serviceNotifyMe => 'Want to be notified?';

  @override
  String get helpTitle => 'Help & Support';

  @override
  String get helpHowCanWeHelpYou => 'How can we help you?';

  @override
  String get helpChooseOption =>
      'Choose an option below to get help with your order.';

  @override
  String get helpRaiseRequest => 'Raise a Support Request';

  @override
  String get helpReportIssue =>
      'Report an issue with your order, payment or delivery';

  @override
  String get supportCategory => 'Category';

  @override
  String get supportDescribeProblem => 'Describe your problem';

  @override
  String get supportHowCanWeHelp => 'How can we help?';

  @override
  String get supportExplainHint => 'Please explain your issue...';

  @override
  String get supportLoginAgain =>
      'Please login again to submit a support request.';

  @override
  String get supportSubmit => 'Submit Request';

  @override
  String get supportSubmitted => 'Support request submitted successfully';

  @override
  String get supportTellUs =>
      'Tell us about your problem and our support team will help you.';

  @override
  String get cartViewCart => 'View Cart';

  @override
  String get orderTrackShort => 'Track';

  @override
  String get commonSwitch => 'Switch';

  @override
  String get storeClosedCaps => 'STORE CLOSED';

  @override
  String get authOtpSubtitle => 'We\'ll send a one-time password to verify';

  @override
  String get serviceNoDeliveryHere => 'Oops! We don\'t deliver here yet';

  @override
  String get serviceNotDeliveringNow =>
      'We\'re currently not delivering to this location.';

  @override
  String get serviceExpanding =>
      'Don\'t worry! We\'re expanding rapidly and will be in your area soon.';

  @override
  String get serviceWillNotifyYou =>
      'We\'ll notify you as soon as we start delivering to your area!';

  @override
  String get productReviewCount => '1.2k reviews';
}
