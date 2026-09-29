class AppConfig {
  // Backend API Configuration

  // Production API URL
  static const String apiBaseUrl = 'https://api-v2.easybasket.in/api';

  // Alternative URLs (uncomment if needed):
  // For local development (web only):

  //static const String apiBaseUrl = 'http://localhost:3000/api';

  // For Android emulator:
  // static const String apiBaseUrl = 'http://10.0.2.2:3000/api';

  // For physical device on same WiFi (replace with your Mac's IP):
  // static const String apiBaseUrl = 'http://192.168.1.29:3000/api';

  // App Configuration (version is for Play Store / release, not tied to backend API)
  static const String appName = 'Easy Basket';
  static const String appVersion = '10.0.0';

  // Development OTP (for testing)
  static const String devOTP = '1234';

  // Store location (hardcoded for now — Nurpur Bedi, Mohali, Punjab)
  static const double storeLat = 31.1250;
  static const double storeLng = 76.4351;
}
