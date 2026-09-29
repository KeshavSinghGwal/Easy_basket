import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../config/app_config.dart';
import '../utils/slug_utils.dart';

class ImageUploadService {
  static String get baseUrl => AppConfig.apiBaseUrl;
  final ImagePicker _picker = ImagePicker();

  /// Pick image from gallery or camera
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 90, // Higher quality for better display
        maxWidth: 2048, // Higher resolution for better quality
        maxHeight: 2048, // Higher resolution for better quality
      );
      return image;
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  /// Compress and resize image
  Future<Uint8List?> compressImage(XFile imageFile) async {
    try {
      // Read image bytes
      final Uint8List imageBytes = await imageFile.readAsBytes();
      
      // Decode image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        return null;
      }

      // Resize if too large (max 1600x1600 for better quality)
      int maxDimension = 1600;
      if (image.width > maxDimension || image.height > maxDimension) {
        // Maintain aspect ratio
        double aspectRatio = image.width / image.height;
        if (image.width > image.height) {
          image = img.copyResize(
            image,
            width: maxDimension,
            maintainAspect: true,
          );
        } else {
          image = img.copyResize(
            image,
            height: maxDimension,
            maintainAspect: true,
          );
        }
      }

      // Compress to JPEG with better quality (85% for good balance)
      final compressedBytes = img.encodeJpg(image, quality: 85);

      // Check if compressed size is acceptable (max 800KB for better quality)
      if (compressedBytes.length > 800 * 1024) {
        // Further compress if still too large, but maintain better quality
        double scaleFactor = 0.85; // Reduce by 15% instead of 20%
        image = img.copyResize(
          image,
          width: (image.width * scaleFactor).round(),
          height: (image.height * scaleFactor).round(),
          maintainAspect: true,
        );
        return img.encodeJpg(image, quality: 80); // Still decent quality
      }

      return Uint8List.fromList(compressedBytes);
    } catch (e) {
      debugPrint('Error compressing image: $e');
      return null;
    }
  }

  /// Upload image to backend
  Future<Map<String, dynamic>?> uploadImage({
    required Uint8List imageBytes,
    required String type, // 'product' or 'category'
    required int id,
    String? adminName,
    String? entityName,
    required String token,
  }) async {
    try {
      // Generate filename preview (for logging)
      String slug = adminName != null && adminName.isNotEmpty
          ? SlugUtils.sanitizeSlug(adminName)
          : (entityName != null && entityName.isNotEmpty
              ? SlugUtils.generateSlug(entityName)
              : 'image-${DateTime.now().millisecondsSinceEpoch}');
      
      final filename = '$type-$id-$slug.jpg';
      debugPrint('📤 Uploading image: $filename');

      // Create multipart request
      final uri = Uri.parse('$baseUrl/admin/upload-image');
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      request.headers['Authorization'] = 'Bearer $token';

      // Add file with explicit content type (required for backend validation)
      // Since we compress to JPEG, always use image/jpeg
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      // Add form fields
      request.fields['type'] = type;
      request.fields['id'] = id.toString();
      if (adminName != null && adminName.isNotEmpty) {
        request.fields['name'] = adminName;
      }

      // Send request
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Upload timeout. Please check your connection.');
        },
      );

      // Get response
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = response.body;
        // Parse JSON response
        final Map<String, dynamic> result = jsonDecode(responseData) as Map<String, dynamic>;
        
        debugPrint('✅ Image uploaded successfully: ${result['url']}');
        return result;
      } else {
        final errorMessage = response.body.isNotEmpty
            ? response.body
            : 'Upload failed with status ${response.statusCode}';
        debugPrint('❌ Upload failed: $errorMessage');
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('❌ Error uploading image: $e');
      rethrow;
    }
  }

}

