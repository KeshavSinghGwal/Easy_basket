import 'api_service.dart';

class SupportService {
  final ApiService _apiService;

  SupportService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  Future<dynamic> createSupportRequest({
    required String category,
    required String description,
    int? orderId,
    required String token,
  }) async {
    final data = <String, dynamic>{
      'category': category,
      'description': description,
    };

    if (orderId != null) {
      data['orderId'] = orderId;
    }

    return _apiService.post(
      '/support',
      data,
      token: token,
    );
  }
}