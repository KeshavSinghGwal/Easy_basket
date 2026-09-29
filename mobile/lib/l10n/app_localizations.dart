import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_pa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('pa')
  ];

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get commonTryAgain;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get commonNotNow;

  /// No description provided for @commonEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get commonEnable;

  /// No description provided for @commonLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get commonLater;

  /// No description provided for @commonOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get commonOpenSettings;

  /// No description provided for @commonLoginFirst.
  ///
  /// In en, this message translates to:
  /// **'Please login first'**
  String get commonLoginFirst;

  /// No description provided for @commonSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please login again.'**
  String get commonSessionExpired;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String commonError(String message);

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the language you want to use in the app'**
  String get languageSubtitle;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageHindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get languageHindi;

  /// No description provided for @languagePunjabi.
  ///
  /// In en, this message translates to:
  /// **'Punjabi'**
  String get languagePunjabi;

  /// No description provided for @languageUpdated.
  ///
  /// In en, this message translates to:
  /// **'Language updated'**
  String get languageUpdated;

  /// No description provided for @languageChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change language. Please try again.'**
  String get languageChangeFailed;

  /// No description provided for @homeLocationDetected.
  ///
  /// In en, this message translates to:
  /// **'Location detected! Start shopping now.'**
  String get homeLocationDetected;

  /// No description provided for @homeLowestPrices.
  ///
  /// In en, this message translates to:
  /// **'Lowest Prices, '**
  String get homeLowestPrices;

  /// No description provided for @homeShopNow.
  ///
  /// In en, this message translates to:
  /// **'Shop Now!!'**
  String get homeShopNow;

  /// No description provided for @authEnterPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get authEnterPhone;

  /// No description provided for @authOtpSent.
  ///
  /// In en, this message translates to:
  /// **'OTP sent successfully!'**
  String get authOtpSent;

  /// No description provided for @authEnterOtp.
  ///
  /// In en, this message translates to:
  /// **'Please enter 6-digit OTP'**
  String get authEnterOtp;

  /// No description provided for @authInvalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid 10-digit phone number'**
  String get authInvalidPhone;

  /// No description provided for @locationAddManually.
  ///
  /// In en, this message translates to:
  /// **'Add Address Manually'**
  String get locationAddManually;

  /// No description provided for @locationConfirmContinue.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Continue'**
  String get locationConfirmContinue;

  /// No description provided for @locationSaved.
  ///
  /// In en, this message translates to:
  /// **'Location saved! Start shopping now.'**
  String get locationSaved;

  /// No description provided for @locationRefine.
  ///
  /// In en, this message translates to:
  /// **'Refine Location'**
  String get locationRefine;

  /// No description provided for @locationGrantPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant Location Permission'**
  String get locationGrantPermission;

  /// No description provided for @locationTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on Location'**
  String get locationTurnOn;

  /// No description provided for @locationRequired.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required'**
  String get locationRequired;

  /// No description provided for @locationEnableInSettings.
  ///
  /// In en, this message translates to:
  /// **'Please enable location in phone Settings'**
  String get locationEnableInSettings;

  /// No description provided for @locationUseCurrent.
  ///
  /// In en, this message translates to:
  /// **'Use Current Location'**
  String get locationUseCurrent;

  /// No description provided for @locationSelect.
  ///
  /// In en, this message translates to:
  /// **'Select Location'**
  String get locationSelect;

  /// No description provided for @locationUnableToGet.
  ///
  /// In en, this message translates to:
  /// **'Unable to get your location. Please try again.'**
  String get locationUnableToGet;

  /// No description provided for @locationWaitAddress.
  ///
  /// In en, this message translates to:
  /// **'Please wait for address to load completely'**
  String get locationWaitAddress;

  /// No description provided for @locationWaitLocation.
  ///
  /// In en, this message translates to:
  /// **'Please wait for location to load or select a valid location'**
  String get locationWaitLocation;

  /// No description provided for @locationCouldNotDetect.
  ///
  /// In en, this message translates to:
  /// **'Could not detect location. Try map picker.'**
  String get locationCouldNotDetect;

  /// No description provided for @locationDetectedFillDetails.
  ///
  /// In en, this message translates to:
  /// **'Location detected! Fill remaining details.'**
  String get locationDetectedFillDetails;

  /// No description provided for @locationSelectedFillDetails.
  ///
  /// In en, this message translates to:
  /// **'Location selected! Fill remaining details.'**
  String get locationSelectedFillDetails;

  /// No description provided for @locationSelectFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select your location first (GPS or Map)'**
  String get locationSelectFirst;

  /// No description provided for @locationDetectViaGps.
  ///
  /// In en, this message translates to:
  /// **'Detect via GPS'**
  String get locationDetectViaGps;

  /// No description provided for @locationPickOnMap.
  ///
  /// In en, this message translates to:
  /// **'Pick on Map'**
  String get locationPickOnMap;

  /// No description provided for @locationChooseFromMap.
  ///
  /// In en, this message translates to:
  /// **'Choose from map'**
  String get locationChooseFromMap;

  /// No description provided for @serviceNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Service Not Available'**
  String get serviceNotAvailable;

  /// No description provided for @categoryViewAllProducts.
  ///
  /// In en, this message translates to:
  /// **'View All Products'**
  String get categoryViewAllProducts;

  /// No description provided for @productAboutThis.
  ///
  /// In en, this message translates to:
  /// **'About this product'**
  String get productAboutThis;

  /// No description provided for @productDeliveryTime.
  ///
  /// In en, this message translates to:
  /// **'Delivery in 5-15 mins'**
  String get productDeliveryTime;

  /// No description provided for @productImageNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Image not available'**
  String get productImageNotAvailable;

  /// No description provided for @productImageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Image unavailable'**
  String get productImageUnavailable;

  /// No description provided for @productSelectQuantity.
  ///
  /// In en, this message translates to:
  /// **'Select Quantity'**
  String get productSelectQuantity;

  /// No description provided for @productSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search products...'**
  String get productSearchHint;

  /// No description provided for @productMicPermission.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission needed'**
  String get productMicPermission;

  /// No description provided for @orderMyOrders.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get orderMyOrders;

  /// No description provided for @orderCancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel Order'**
  String get orderCancelOrder;

  /// No description provided for @orderCancelAnyway.
  ///
  /// In en, this message translates to:
  /// **'Cancel anyway'**
  String get orderCancelAnyway;

  /// No description provided for @orderCancelQuestion.
  ///
  /// In en, this message translates to:
  /// **'Cancel order?'**
  String get orderCancelQuestion;

  /// No description provided for @orderCancellationRequested.
  ///
  /// In en, this message translates to:
  /// **'Cancellation requested'**
  String get orderCancellationRequested;

  /// No description provided for @orderContactDriver.
  ///
  /// In en, this message translates to:
  /// **'Contact Driver'**
  String get orderContactDriver;

  /// No description provided for @orderDeliveringTo.
  ///
  /// In en, this message translates to:
  /// **'Delivering To'**
  String get orderDeliveringTo;

  /// No description provided for @orderDriverOnWay.
  ///
  /// In en, this message translates to:
  /// **'Driver is on the way!'**
  String get orderDriverOnWay;

  /// No description provided for @orderStoreName.
  ///
  /// In en, this message translates to:
  /// **'Easy Basket Store'**
  String get orderStoreName;

  /// No description provided for @orderKeepOrder.
  ///
  /// In en, this message translates to:
  /// **'Keep order'**
  String get orderKeepOrder;

  /// No description provided for @orderLiveTracking.
  ///
  /// In en, this message translates to:
  /// **'Live Order Tracking'**
  String get orderLiveTracking;

  /// No description provided for @orderMapNotAvailableWeb.
  ///
  /// In en, this message translates to:
  /// **'Map not available on web'**
  String get orderMapNotAvailableWeb;

  /// No description provided for @orderMapNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Map not available'**
  String get orderMapNotAvailable;

  /// No description provided for @orderDetails.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get orderDetails;

  /// No description provided for @orderPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get orderPayment;

  /// No description provided for @orderRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get orderRefund;

  /// No description provided for @orderTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get orderTotalAmount;

  /// No description provided for @orderTrackOrder.
  ///
  /// In en, this message translates to:
  /// **'Track Order'**
  String get orderTrackOrder;

  /// No description provided for @orderWhyCancelling.
  ///
  /// In en, this message translates to:
  /// **'Why are you cancelling?'**
  String get orderWhyCancelling;

  /// No description provided for @orderYourLocation.
  ///
  /// In en, this message translates to:
  /// **'Your Location'**
  String get orderYourLocation;

  /// No description provided for @orderPrevCancelDeclined.
  ///
  /// In en, this message translates to:
  /// **'Your previous cancellation request was declined.'**
  String get orderPrevCancelDeclined;

  /// No description provided for @orderReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String orderReason(String reason);

  /// No description provided for @paymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get paymentTitle;

  /// No description provided for @paymentItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} item} other{{count} items}}'**
  String paymentItemCount(int count);

  /// No description provided for @paymentNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Any special instructions... (optional)'**
  String get paymentNotesHint;

  /// No description provided for @paymentCardsUpi.
  ///
  /// In en, this message translates to:
  /// **'Cards, UPI, Wallets, Netbanking'**
  String get paymentCardsUpi;

  /// No description provided for @paymentCod.
  ///
  /// In en, this message translates to:
  /// **'Cash on Delivery'**
  String get paymentCod;

  /// No description provided for @paymentDeliveryNotes.
  ///
  /// In en, this message translates to:
  /// **'Delivery Notes'**
  String get paymentDeliveryNotes;

  /// No description provided for @paymentExternalWallet.
  ///
  /// In en, this message translates to:
  /// **'External wallet selected: {wallet}'**
  String paymentExternalWallet(String wallet);

  /// No description provided for @paymentInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to initialize payment. Please try again.'**
  String get paymentInitFailed;

  /// No description provided for @paymentInvalidMissing.
  ///
  /// In en, this message translates to:
  /// **'Invalid payment response. Missing payment details.'**
  String get paymentInvalidMissing;

  /// No description provided for @paymentInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'Invalid payment response. Please try again.'**
  String get paymentInvalidResponse;

  /// No description provided for @paymentOnline.
  ///
  /// In en, this message translates to:
  /// **'Online Payment'**
  String get paymentOnline;

  /// No description provided for @paymentPayOnReceive.
  ///
  /// In en, this message translates to:
  /// **'Pay when you receive'**
  String get paymentPayOnReceive;

  /// No description provided for @paymentWebOnlyCod.
  ///
  /// In en, this message translates to:
  /// **'Online payment is currently available on mobile app only. Please use Cash on Delivery or test on Android/iOS.'**
  String get paymentWebOnlyCod;

  /// No description provided for @paymentOrderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order Summary'**
  String get paymentOrderSummary;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethod;

  /// No description provided for @paymentLoginToContinue.
  ///
  /// In en, this message translates to:
  /// **'Please login to continue.'**
  String get paymentLoginToContinue;

  /// No description provided for @paymentSelectAddress.
  ///
  /// In en, this message translates to:
  /// **'Please select an address'**
  String get paymentSelectAddress;

  /// No description provided for @paymentTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get paymentTotal;

  /// No description provided for @paymentUnableIdentifyOrder.
  ///
  /// In en, this message translates to:
  /// **'Unable to identify order. Please check your orders.'**
  String get paymentUnableIdentifyOrder;

  /// No description provided for @paymentVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying payment...'**
  String get paymentVerifying;

  /// No description provided for @paymentTurnOnNotifications.
  ///
  /// In en, this message translates to:
  /// **'Turn On Notifications'**
  String get paymentTurnOnNotifications;

  /// No description provided for @addressDetails.
  ///
  /// In en, this message translates to:
  /// **'Address Details'**
  String get addressDetails;

  /// No description provided for @addressSaved.
  ///
  /// In en, this message translates to:
  /// **'Address saved!'**
  String get addressSaved;

  /// No description provided for @addressUpdated.
  ///
  /// In en, this message translates to:
  /// **'Address updated'**
  String get addressUpdated;

  /// No description provided for @addressSave.
  ///
  /// In en, this message translates to:
  /// **'Save Address'**
  String get addressSave;

  /// No description provided for @addressSaveAs.
  ///
  /// In en, this message translates to:
  /// **'Save as'**
  String get addressSaveAs;

  /// No description provided for @addressLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get addressLocation;

  /// No description provided for @addressAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Address'**
  String get addressAdd;

  /// No description provided for @addressAddNew.
  ///
  /// In en, this message translates to:
  /// **'Add New Address'**
  String get addressAddNew;

  /// No description provided for @addressAddToStart.
  ///
  /// In en, this message translates to:
  /// **'Add a delivery address to get started'**
  String get addressAddToStart;

  /// No description provided for @addressChooseDelivery.
  ///
  /// In en, this message translates to:
  /// **'Choose Delivery Address'**
  String get addressChooseDelivery;

  /// No description provided for @addressContinueToPayment.
  ///
  /// In en, this message translates to:
  /// **'Continue to Payment'**
  String get addressContinueToPayment;

  /// No description provided for @addressNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No addresses found'**
  String get addressNoneFound;

  /// No description provided for @addressSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search area, street, landmark...'**
  String get addressSearchHint;

  /// No description provided for @addressYourSaved.
  ///
  /// In en, this message translates to:
  /// **'Your Saved Addresses'**
  String get addressYourSaved;

  /// No description provided for @addressSavedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} saved'**
  String addressSavedCount(int count);

  /// No description provided for @addressSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default address'**
  String get addressSetDefault;

  /// No description provided for @addressSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Address'**
  String get addressSearchTitle;

  /// No description provided for @addressSearchYourArea.
  ///
  /// In en, this message translates to:
  /// **'Search your area, street, sector...'**
  String get addressSearchYourArea;

  /// No description provided for @profileCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get profileCustomer;

  /// No description provided for @profileOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get profileOrders;

  /// No description provided for @profileAddresses.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get profileAddresses;

  /// No description provided for @profileRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get profileRating;

  /// No description provided for @profileAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileAccount;

  /// No description provided for @profileEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profileEditProfile;

  /// No description provided for @profileMyOrders.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get profileMyOrders;

  /// No description provided for @profileMyAddresses.
  ///
  /// In en, this message translates to:
  /// **'My Addresses'**
  String get profileMyAddresses;

  /// No description provided for @profilePreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get profilePreferences;

  /// No description provided for @profileSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get profileSupport;

  /// No description provided for @profileHelpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get profileHelpSupport;

  /// No description provided for @profileHelpComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Help & Support coming soon'**
  String get profileHelpComingSoon;

  /// No description provided for @profileAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get profileAbout;

  /// No description provided for @profileAboutApp.
  ///
  /// In en, this message translates to:
  /// **'About Easy Basket'**
  String get profileAboutApp;

  /// No description provided for @profileLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get profileLogout;

  /// No description provided for @profileLogoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get profileLogoutConfirm;

  /// No description provided for @cartTitle.
  ///
  /// In en, this message translates to:
  /// **'My Cart'**
  String get cartTitle;

  /// Item count shown in the cart title and floating bar
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} item} other{{count} items}}'**
  String cartItemCount(int count);

  /// No description provided for @cartEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty'**
  String get cartEmpty;

  /// No description provided for @cartEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add items to your cart to get started'**
  String get cartEmptySubtitle;

  /// No description provided for @cartStartShopping.
  ///
  /// In en, this message translates to:
  /// **'Start Shopping'**
  String get cartStartShopping;

  /// No description provided for @cartRemoveItem.
  ///
  /// In en, this message translates to:
  /// **'Remove Item'**
  String get cartRemoveItem;

  /// No description provided for @cartSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get cartSubtotal;

  /// No description provided for @cartDeliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Delivery Fee'**
  String get cartDeliveryFee;

  /// No description provided for @cartTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get cartTotal;

  /// No description provided for @cartAddressRequired.
  ///
  /// In en, this message translates to:
  /// **'Delivery address required'**
  String get cartAddressRequired;

  /// No description provided for @cartAddAddressToProceed.
  ///
  /// In en, this message translates to:
  /// **'Add address to proceed'**
  String get cartAddAddressToProceed;

  /// No description provided for @cartAddAddressFirst.
  ///
  /// In en, this message translates to:
  /// **'Please add a delivery address first'**
  String get cartAddAddressFirst;

  /// No description provided for @cartStoreClosed.
  ///
  /// In en, this message translates to:
  /// **'Store Closed'**
  String get cartStoreClosed;

  /// No description provided for @cartLoginToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Login to Checkout'**
  String get cartLoginToCheckout;

  /// No description provided for @cartAddAddressToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Add Address to Checkout'**
  String get cartAddAddressToCheckout;

  /// No description provided for @cartProceedToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Proceed to Checkout'**
  String get cartProceedToCheckout;

  /// No description provided for @cartPerUnit.
  ///
  /// In en, this message translates to:
  /// **'Per {unit}'**
  String cartPerUnit(String unit);

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully!'**
  String get profileUpdated;

  /// No description provided for @profileFullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get profileFullName;

  /// No description provided for @profileFullNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name'**
  String get profileFullNameHint;

  /// No description provided for @profileEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get profileEmail;

  /// No description provided for @profilePhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get profilePhoneNumber;

  /// No description provided for @profileBirthday.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get profileBirthday;

  /// No description provided for @profileBirthdayHint.
  ///
  /// In en, this message translates to:
  /// **'Select your birthday'**
  String get profileBirthdayHint;

  /// No description provided for @homeAddAddressToOrder.
  ///
  /// In en, this message translates to:
  /// **'Add your delivery address to place orders'**
  String get homeAddAddressToOrder;

  /// No description provided for @homeChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get homeChange;

  /// No description provided for @homeCheckBackSoon.
  ///
  /// In en, this message translates to:
  /// **'Check back soon!'**
  String get homeCheckBackSoon;

  /// No description provided for @homeEnableLocationFast.
  ///
  /// In en, this message translates to:
  /// **'Enable location for faster delivery'**
  String get homeEnableLocationFast;

  /// No description provided for @homeNoProducts.
  ///
  /// In en, this message translates to:
  /// **'No products available'**
  String get homeNoProducts;

  /// No description provided for @homeShopByCategory.
  ///
  /// In en, this message translates to:
  /// **'Shop by category'**
  String get homeShopByCategory;

  /// No description provided for @homeSnackItAway.
  ///
  /// In en, this message translates to:
  /// **'Snack it away'**
  String get homeSnackItAway;

  /// No description provided for @commonViewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get commonViewAll;

  /// No description provided for @commonSeeAll.
  ///
  /// In en, this message translates to:
  /// **'see all'**
  String get commonSeeAll;

  /// No description provided for @productAddToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to cart'**
  String get productAddToCart;

  /// No description provided for @productOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get productOutOfStock;

  /// No description provided for @productUnavailableNow.
  ///
  /// In en, this message translates to:
  /// **'Product unavailable right now'**
  String get productUnavailableNow;

  /// No description provided for @productDetailsMissing.
  ///
  /// In en, this message translates to:
  /// **'Some details are missing for this product. You can still add it to cart.'**
  String get productDetailsMissing;

  /// No description provided for @productYouMayAlsoLike.
  ///
  /// In en, this message translates to:
  /// **'You may also like'**
  String get productYouMayAlsoLike;

  /// No description provided for @productNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No products found'**
  String get productNoneFound;

  /// No description provided for @productAdd.
  ///
  /// In en, this message translates to:
  /// **'ADD'**
  String get productAdd;

  /// No description provided for @productOutOfStockCaps.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get productOutOfStockCaps;

  /// No description provided for @productMicPermissionLong.
  ///
  /// In en, this message translates to:
  /// **'Easy Basket needs microphone permission to hear you. Please allow it in Settings.'**
  String get productMicPermissionLong;

  /// No description provided for @categoryAll.
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get categoryAll;

  /// No description provided for @categoryNoneAvailable.
  ///
  /// In en, this message translates to:
  /// **'No categories available'**
  String get categoryNoneAvailable;

  /// No description provided for @categoryNoSubcategories.
  ///
  /// In en, this message translates to:
  /// **'No subcategories available'**
  String get categoryNoSubcategories;

  /// No description provided for @orderLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your orders...'**
  String get orderLoading;

  /// No description provided for @orderNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get orderNoneYet;

  /// No description provided for @orderSomethingWrong.
  ///
  /// In en, this message translates to:
  /// **'Oops! Something went wrong'**
  String get orderSomethingWrong;

  /// No description provided for @orderStartShoppingHint.
  ///
  /// In en, this message translates to:
  /// **'Start shopping to see your orders here'**
  String get orderStartShoppingHint;

  /// No description provided for @orderViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get orderViewDetails;

  /// No description provided for @orderEta15.
  ///
  /// In en, this message translates to:
  /// **'ETA ~15 mins'**
  String get orderEta15;

  /// No description provided for @orderNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Need Help?'**
  String get orderNeedHelp;

  /// No description provided for @orderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Order not found'**
  String get orderNotFound;

  /// No description provided for @orderFetchingDetails.
  ///
  /// In en, this message translates to:
  /// **'Please wait while we fetch your order details'**
  String get orderFetchingDetails;

  /// No description provided for @orderTrackYourOrder.
  ///
  /// In en, this message translates to:
  /// **'Track Your Order'**
  String get orderTrackYourOrder;

  /// No description provided for @orderYourDeliveryPartner.
  ///
  /// In en, this message translates to:
  /// **'Your Delivery Partner'**
  String get orderYourDeliveryPartner;

  /// No description provided for @orderPackedNoRefund.
  ///
  /// In en, this message translates to:
  /// **'Your order is already packed. Cancelling now will NOT refund your payment. Do you want to continue?'**
  String get orderPackedNoRefund;

  /// No description provided for @profileEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profileEditTitle;

  /// No description provided for @profilePhotoComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Photo upload coming soon'**
  String get profilePhotoComingSoon;

  /// No description provided for @profilePicture.
  ///
  /// In en, this message translates to:
  /// **'Profile Picture'**
  String get profilePicture;

  /// No description provided for @profileSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get profileSaveChanges;

  /// No description provided for @profileNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get profileNotifications;

  /// No description provided for @profileEnableNotifHint.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications for Easy Basket in your phone settings to turn this on.'**
  String get profileEnableNotifHint;

  /// No description provided for @paymentMaybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe Later'**
  String get paymentMaybeLater;

  /// No description provided for @paymentStayUpdated.
  ///
  /// In en, this message translates to:
  /// **'Stay updated on your order!'**
  String get paymentStayUpdated;

  /// No description provided for @paymentNotifHint.
  ///
  /// In en, this message translates to:
  /// **'Turn on notifications to receive real-time order updates & delivery alerts.'**
  String get paymentNotifHint;

  /// No description provided for @authTerms.
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to our Terms of Service\nand Privacy Policy'**
  String get authTerms;

  /// No description provided for @authChangePhone.
  ///
  /// In en, this message translates to:
  /// **'Change phone number'**
  String get authChangePhone;

  /// No description provided for @authTagline.
  ///
  /// In en, this message translates to:
  /// **'Fresh groceries at your doorstep'**
  String get authTagline;

  /// No description provided for @authLoginSignup.
  ///
  /// In en, this message translates to:
  /// **'Login / Sign up'**
  String get authLoginSignup;

  /// No description provided for @authVerifyOtp.
  ///
  /// In en, this message translates to:
  /// **'Verify OTP'**
  String get authVerifyOtp;

  /// No description provided for @addressAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Address'**
  String get addressAddTitle;

  /// No description provided for @addressEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Address'**
  String get addressEditTitle;

  /// No description provided for @addressLabelCaps.
  ///
  /// In en, this message translates to:
  /// **'ADDRESS'**
  String get addressLabelCaps;

  /// No description provided for @addressDefaultCaps.
  ///
  /// In en, this message translates to:
  /// **'DEFAULT'**
  String get addressDefaultCaps;

  /// No description provided for @addressUseSavedAnyway.
  ///
  /// In en, this message translates to:
  /// **'Use Saved Address Anyway'**
  String get addressUseSavedAnyway;

  /// No description provided for @addressEnterManually.
  ///
  /// In en, this message translates to:
  /// **'Enter Manually'**
  String get addressEnterManually;

  /// No description provided for @addressSearchByArea.
  ///
  /// In en, this message translates to:
  /// **'Search by area, street name, sector, or landmark'**
  String get addressSearchByArea;

  /// No description provided for @addressSelectedLocation.
  ///
  /// In en, this message translates to:
  /// **'Selected Location:'**
  String get addressSelectedLocation;

  /// No description provided for @addressNotifyMe.
  ///
  /// In en, this message translates to:
  /// **'Notify Me'**
  String get addressNotifyMe;

  /// No description provided for @addressWillNotify.
  ///
  /// In en, this message translates to:
  /// **'We will notify you!'**
  String get addressWillNotify;

  /// No description provided for @locationAllowAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow location access'**
  String get locationAllowAccess;

  /// No description provided for @locationAllowForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Allow location for delivery'**
  String get locationAllowForDelivery;

  /// No description provided for @locationEnterManually.
  ///
  /// In en, this message translates to:
  /// **'Enter address manually instead'**
  String get locationEnterManually;

  /// No description provided for @locationFreshGroceries.
  ///
  /// In en, this message translates to:
  /// **'Fresh groceries in minutes'**
  String get locationFreshGroceries;

  /// No description provided for @locationGroceriesFast.
  ///
  /// In en, this message translates to:
  /// **'Groceries, delivered fast'**
  String get locationGroceriesFast;

  /// No description provided for @locationIsOff.
  ///
  /// In en, this message translates to:
  /// **'Location is off'**
  String get locationIsOff;

  /// No description provided for @locationShareOnce.
  ///
  /// In en, this message translates to:
  /// **'Share your location once so we can find your area, show accurate prices, and deliver to the right address.'**
  String get locationShareOnce;

  /// No description provided for @locationChangeAnytime.
  ///
  /// In en, this message translates to:
  /// **'You can change this anytime in settings.'**
  String get locationChangeAnytime;

  /// No description provided for @locationDetecting.
  ///
  /// In en, this message translates to:
  /// **'Detecting your location...'**
  String get locationDetecting;

  /// No description provided for @locationAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'Location Access Required'**
  String get locationAccessRequired;

  /// No description provided for @locationPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Your location is only used to find your delivery address. We never share it with anyone.'**
  String get locationPrivacyNote;

  /// No description provided for @locationMapMobileOnly.
  ///
  /// In en, this message translates to:
  /// **'Map View Available on Mobile'**
  String get locationMapMobileOnly;

  /// No description provided for @locationMapMobileHint.
  ///
  /// In en, this message translates to:
  /// **'For the best experience with interactive map and draggable pin, please use the mobile app.'**
  String get locationMapMobileHint;

  /// No description provided for @serviceGoHome.
  ///
  /// In en, this message translates to:
  /// **'Go to Home'**
  String get serviceGoHome;

  /// No description provided for @serviceSelectedLocation.
  ///
  /// In en, this message translates to:
  /// **'Selected Location'**
  String get serviceSelectedLocation;

  /// No description provided for @serviceNotifyMe.
  ///
  /// In en, this message translates to:
  /// **'Want to be notified?'**
  String get serviceNotifyMe;

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpTitle;

  /// No description provided for @helpHowCanWeHelpYou.
  ///
  /// In en, this message translates to:
  /// **'How can we help you?'**
  String get helpHowCanWeHelpYou;

  /// No description provided for @helpChooseOption.
  ///
  /// In en, this message translates to:
  /// **'Choose an option below to get help with your order.'**
  String get helpChooseOption;

  /// No description provided for @helpRaiseRequest.
  ///
  /// In en, this message translates to:
  /// **'Raise a Support Request'**
  String get helpRaiseRequest;

  /// No description provided for @helpReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report an issue with your order, payment or delivery'**
  String get helpReportIssue;

  /// No description provided for @supportCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get supportCategory;

  /// No description provided for @supportDescribeProblem.
  ///
  /// In en, this message translates to:
  /// **'Describe your problem'**
  String get supportDescribeProblem;

  /// No description provided for @supportHowCanWeHelp.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get supportHowCanWeHelp;

  /// No description provided for @supportExplainHint.
  ///
  /// In en, this message translates to:
  /// **'Please explain your issue...'**
  String get supportExplainHint;

  /// No description provided for @supportLoginAgain.
  ///
  /// In en, this message translates to:
  /// **'Please login again to submit a support request.'**
  String get supportLoginAgain;

  /// No description provided for @supportSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit Request'**
  String get supportSubmit;

  /// No description provided for @supportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Support request submitted successfully'**
  String get supportSubmitted;

  /// No description provided for @supportTellUs.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your problem and our support team will help you.'**
  String get supportTellUs;

  /// No description provided for @cartViewCart.
  ///
  /// In en, this message translates to:
  /// **'View Cart'**
  String get cartViewCart;

  /// No description provided for @orderTrackShort.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get orderTrackShort;

  /// No description provided for @commonSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get commonSwitch;

  /// No description provided for @storeClosedCaps.
  ///
  /// In en, this message translates to:
  /// **'STORE CLOSED'**
  String get storeClosedCaps;

  /// No description provided for @authOtpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a one-time password to verify'**
  String get authOtpSubtitle;

  /// No description provided for @serviceNoDeliveryHere.
  ///
  /// In en, this message translates to:
  /// **'Oops! We don\'t deliver here yet'**
  String get serviceNoDeliveryHere;

  /// No description provided for @serviceNotDeliveringNow.
  ///
  /// In en, this message translates to:
  /// **'We\'re currently not delivering to this location.'**
  String get serviceNotDeliveringNow;

  /// No description provided for @serviceExpanding.
  ///
  /// In en, this message translates to:
  /// **'Don\'t worry! We\'re expanding rapidly and will be in your area soon.'**
  String get serviceExpanding;

  /// No description provided for @serviceWillNotifyYou.
  ///
  /// In en, this message translates to:
  /// **'We\'ll notify you as soon as we start delivering to your area!'**
  String get serviceWillNotifyYou;

  /// No description provided for @productReviewCount.
  ///
  /// In en, this message translates to:
  /// **'1.2k reviews'**
  String get productReviewCount;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'pa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'pa':
      return AppLocalizationsPa();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
