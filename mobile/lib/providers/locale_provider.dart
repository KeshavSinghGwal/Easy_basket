import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

/// The languages the app ships with. Order here is the order shown in the
/// language picker.
enum AppLanguage {
  english('en', 'English', 'English'),
  hindi('hi', 'हिंदी', 'Hindi'),
  punjabi('pa', 'ਪੰਜਾਬੀ', 'Punjabi');

  const AppLanguage(this.code, this.nativeName, this.englishName);

  /// Two-letter code. Sent to the backend as `Accept-Language` and used as
  /// the Flutter [Locale] language code.
  final String code;

  /// Shown in the picker in its own script — a Punjabi speaker looking for
  /// their language should not have to read English to find it.
  final String nativeName;

  final String englishName;

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.english,
    );
  }
}

/// Holds the user's chosen language.
///
/// Language is an explicit choice, never inferred from the device locale — a
/// phone set to Hindi does not mean the owner wants this app in Hindi.
///
/// Two things depend on this provider:
///   1. `MaterialApp.locale`  — which ARB bundle renders the UI chrome.
///   2. `ApiService.language` — which language the backend resolves product
///      and category names into (see backend ResponseTranslator).
class LocaleProvider extends ChangeNotifier {
  static const _prefsKey = 'app_language';

  LocaleProvider({required SharedPreferences prefs}) : _prefs = prefs {
    _language = AppLanguage.fromCode(_prefs.getString(_prefsKey));
    // Push the restored value before the first request goes out, otherwise
    // the opening screen fetches its catalogue in English.
    ApiService.language = _language.code;
  }

  final SharedPreferences _prefs;

  AppLanguage _language = AppLanguage.english;

  AppLanguage get language => _language;

  Locale get locale => Locale(_language.code);

  bool get isEnglish => _language == AppLanguage.english;

  /// Persist and apply a new language.
  ///
  /// Returns false if the choice could not be saved, so the caller can tell
  /// the user rather than silently half-applying it.
  Future<bool> setLanguage(AppLanguage language) async {
    if (language == _language) return true;

    final previous = _language;

    _language = language;
    ApiService.language = language.code;
    notifyListeners();

    try {
      await _prefs.setString(_prefsKey, language.code);
      return true;
    } catch (_) {
      // Roll back so the UI matches what will actually be there next launch.
      _language = previous;
      ApiService.language = previous.code;
      notifyListeners();
      return false;
    }
  }
}
