import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easy_basket/providers/locale_provider.dart';
import 'package:easy_basket/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiService.language = 'en';
  });

  test('defaults to English on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final p = LocaleProvider(prefs: prefs);

    expect(p.language, AppLanguage.english);
    expect(p.locale.languageCode, 'en');
    expect(ApiService.language, 'en');
  });

  test('selecting a language persists it to disk', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final p = LocaleProvider(prefs: prefs);

    await p.setLanguage(AppLanguage.punjabi);

    expect(p.language, AppLanguage.punjabi);
    expect(prefs.getString('app_language'), 'pa');
    expect(ApiService.language, 'pa');
  });

  test('language survives an app restart', () async {
    // Simulate a cold start where disk already holds a previous choice.
    SharedPreferences.setMockInitialValues({'app_language': 'hi'});
    final prefs = await SharedPreferences.getInstance();

    // A brand new provider, as main() would build on relaunch.
    final restarted = LocaleProvider(prefs: prefs);

    expect(restarted.language, AppLanguage.hindi);
    expect(restarted.locale.languageCode, 'hi');
    // Critical: the header must be right BEFORE the first request goes out,
    // otherwise the opening screen fetches its catalogue in English.
    expect(ApiService.language, 'hi');
  });

  test('an unknown stored value falls back to English, not a crash', () async {
    SharedPreferences.setMockInitialValues({'app_language': 'zz'});
    final prefs = await SharedPreferences.getInstance();
    final p = LocaleProvider(prefs: prefs);

    expect(p.language, AppLanguage.english);
  });

  test('notifies listeners so MaterialApp rebuilds', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final p = LocaleProvider(prefs: prefs);

    var notified = 0;
    p.addListener(() => notified++);

    await p.setLanguage(AppLanguage.hindi);
    expect(notified, greaterThan(0));

    // Re-selecting the same language is a no-op, not another rebuild.
    final before = notified;
    await p.setLanguage(AppLanguage.hindi);
    expect(notified, before);
  });
}
