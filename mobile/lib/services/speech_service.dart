import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

/// Callback types for speech events
typedef OnTranscriptUpdate = void Function(String text, bool isFinal);
typedef OnStatusChange = void Function(SpeechStatus status);

enum SpeechStatus { idle, listening, processing, error, permissionDenied }

/// Handles on-device speech-to-text with auto language detection.
///
/// Uses 'hi-IN' as primary locale — Google's Hindi STT naturally handles
/// Hinglish (Hindi + English mixed), outputting Hindi in Devanagari and
/// common English words as-is. No language selection needed from user.
class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;
  bool get isAvailable => _isInitialized;

  /// Initialize the speech engine.
  /// Set [force] to re-initialize (e.g. after permission was just granted).
  Future<bool> initialize({bool force = false}) async {
    if (_isInitialized && !force) return true;

    try {
      _isInitialized = await _speech.initialize(
        onError: (error) {
          debugPrint('[Speech] Error: ${error.errorMsg}');
          _isListening = false;
        },
        onStatus: (status) {
          debugPrint('[Speech] Status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
        },
      );
    } catch (e) {
      debugPrint('[Speech] Init exception: $e');
      _isInitialized = false;
    }

    debugPrint('[Speech] Initialized: $_isInitialized');
    return _isInitialized;
  }

  /// Check and request microphone permission.
  /// Returns true if granted.
  Future<MicPermissionResult> checkAndRequestPermission() async {
    var status = await Permission.microphone.status;

    if (status.isGranted) return MicPermissionResult.granted;

    if (status.isPermanentlyDenied) {
      return MicPermissionResult.permanentlyDenied;
    }

    // Request permission
    status = await Permission.microphone.request();

    if (status.isGranted) return MicPermissionResult.granted;
    if (status.isPermanentlyDenied) {
      return MicPermissionResult.permanentlyDenied;
    }
    return MicPermissionResult.denied;
  }

  /// Start listening. Calls [onResult] with interim and final results.
  ///
  /// Uses 'hi-IN' locale which handles:
  /// - Pure Hindi: "मुझे आलू चाहिए"
  /// - Hinglish: "mujhe aloo chahiye"
  /// - English words mixed in: "milk aur bread lao"
  ///
  /// Auto-stops after [pauseFor] seconds of silence.
  Future<void> startListening({
    required OnTranscriptUpdate onResult,
    VoidCallback? onDone,
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    _isListening = true;

    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
        if (result.finalResult) {
          _isListening = false;
          onDone?.call();
        }
      },
      // Follows the app language instead of assuming Hindi. Punjabi STT is
      // not available on every device, so 'pa' falls back to Hindi, which
      // recognises Punjabi grocery words far better than English does.
      localeId: _sttLocaleId(ApiService.language),
      listenFor: const Duration(seconds: 30),
      pauseFor: pauseFor,
    );
  }

  /// Map the app language onto a speech-recognition locale.
  ///
  /// Punjabi ('pa') deliberately resolves to Hindi: Android STT support for
  /// pa-IN is patchy, and Hindi recognition handles Punjabi product names
  /// much better than falling back to English would.
  static String _sttLocaleId(String languageCode) {
    switch (languageCode) {
      case 'en':
        return 'en_IN';
      case 'pa':
      case 'hi':
      default:
        return 'hi_IN';
    }
  }

  /// Stop listening manually.
  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
  }

  /// Cancel listening (discard results).
  Future<void> cancel() async {
    await _speech.cancel();
    _isListening = false;
  }

  void dispose() {
    _speech.stop();
  }
}

enum MicPermissionResult { granted, denied, permanentlyDenied }
