import 'api_service.dart';
import '../models/user_model.dart';

class AuthService {
  final ApiService apiService;

  AuthService({required this.apiService});

  Future<void> sendOTP(String phoneNumber) async {
    await apiService.post('/auth/login', {
      'phoneNumber': phoneNumber,
    });
  }

  Future<Map<String, dynamic>> verifyOTP(
    String phoneNumber,
    String otp, {
    String? fcmToken,
  }) async {
    final response = await apiService.post('/auth/verify', {
      'phoneNumber': phoneNumber,
      'otp': otp,
      if (fcmToken != null) 'fcmToken': fcmToken,
    });

    // Check if response is valid
    if (response == null) {
      throw Exception('Invalid response from server');
    }

    // Backend returns accessToken and refreshToken
    final accessToken = response['accessToken'] as String?;
    final refreshToken = response['refreshToken'] as String?;
    final userData = response['user'] as Map<String, dynamic>?;

    if (accessToken == null || refreshToken == null || userData == null) {
      throw Exception('Missing required fields in response: ${response.keys}');
    }

    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'user': UserModel.fromJson(userData),
    };
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final response = await apiService.post('/auth/refresh', {
      'refreshToken': refreshToken,
    });

    return {
      'accessToken': response['accessToken'] as String,
      'user': UserModel.fromJson(response['user'] as Map<String, dynamic>),
    };
  }

  Future<void> logout(String? refreshToken, String? accessToken) async {
    try {
      if (refreshToken != null) {
        // Revoke refresh token on server
        await apiService.post(
          '/auth/logout',
          {'refreshToken': refreshToken},
          token: accessToken,
        );
      }
    } catch (e) {
      // Continue logout even if API call fails
      print('Error revoking token: $e');
    }
  }

  Future<UserModel> updateProfile({
    required String token,
    String? name,
    String? email,
    String? birthday,
    String? fcmToken,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (email != null) data['email'] = email;
    if (birthday != null) data['birthday'] = birthday;
    if (fcmToken != null) data['fcmToken'] = fcmToken;

    final response = await apiService.put('/auth/profile', data, token: token);
    return UserModel.fromJson(response['user'] as Map<String, dynamic>);
  }
}

