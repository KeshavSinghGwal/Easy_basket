import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:easy_basket/l10n/app_localizations.dart';

Future<AppLocalizations> load(String code) =>
    AppLocalizations.delegate.load(Locale(code));

void main() {
  test('all three locales are supported', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toList(),
      containsAll(<String>['en', 'hi', 'pa']),
    );
  });

  test('strings resolve per locale', () async {
    expect((await load('en')).languageTitle, 'Language');
    expect((await load('hi')).languageTitle, 'भाषा');
    expect((await load('pa')).languageTitle, 'ਭਾਸ਼ਾ');
  });

  test('cart plural inflects correctly in each language', () async {
    final en = await load('en');
    final hi = await load('hi');
    final pa = await load('pa');

    expect(en.cartItemCount(1), '1 item');
    expect(en.cartItemCount(3), '3 items');

    // Genuine plural forms, not the same string twice — this is the thing a
    // flat key->string map could not express.
    expect(hi.cartItemCount(1), '1 चीज़');
    expect(hi.cartItemCount(3), '3 चीज़ें');

    expect(pa.cartItemCount(1), '1 ਚੀਜ਼');
    expect(pa.cartItemCount(3), '3 ਚੀਜ਼ਾਂ');
  });

  test('placeholder keys interpolate', () async {
    final hi = await load('hi');
    expect(hi.commonError('boom'), contains('boom'));
    expect(hi.orderReason('late'), contains('late'));
    expect(hi.cartPerUnit('kg'), contains('kg'));
    expect(hi.paymentExternalWallet('paytm'), contains('paytm'));
    expect(hi.addressSavedCount(4), contains('4'));
  });

  test('every screen has real translations, no English leaking through',
      () async {
    final en = await load('en');
    for (final locale in ['hi', 'pa']) {
      final t = await load(locale);
      final pairs = <String, List<String>>{
        'cart': [en.cartProceedToCheckout, t.cartProceedToCheckout],
        'orders': [en.orderTrackOrder, t.orderTrackOrder],
        'payment': [en.paymentCod, t.paymentCod],
        'address': [en.addressChooseDelivery, t.addressChooseDelivery],
        'profile': [en.profileMyOrders, t.profileMyOrders],
        'auth': [en.authEnterPhone, t.authEnterPhone],
        'location': [en.locationUseCurrent, t.locationUseCurrent],
        'product': [en.productSelectQuantity, t.productSelectQuantity],
        'home': [en.homeShopNow, t.homeShopNow],
        'editProfile': [en.profileFullName, t.profileFullName],
      };
      pairs.forEach((screen, v) {
        expect(v[1], isNot(v[0]), reason: '$screen not translated in $locale');
        expect(v[1].trim(), isNotEmpty, reason: '$screen empty in $locale');
      });
    }
  });
}
