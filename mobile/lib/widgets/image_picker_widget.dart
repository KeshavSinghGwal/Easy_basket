import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/theme.dart';

class ImagePickerWidget extends StatefulWidget {
  final XFile? selectedImage;
  final Function(XFile?) onImageSelected;
  final String? currentImageUrl; // For editing existing products

  const ImagePickerWidget({
    super.key,
    this.selectedImage,
    required this.onImageSelected,
    this.currentImageUrl,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _loadImageBytes();
  }

  @override
  void didUpdateWidget(ImagePickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedImage != widget.selectedImage) {
      _loadImageBytes();
    }
  }

  Future<void> _loadImageBytes() async {
    if (widget.selectedImage != null) {
      try {
        final bytes = await widget.selectedImage!.readAsBytes();
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
          });
        }
      } catch (e) {
        debugPrint('Error loading image bytes: $e');
      }
    }
  }

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      
      if (image != null) {
        // Load image bytes for all platforms (simpler and web-compatible)
        final bytes = await image.readAsBytes();
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
          });
        }
        widget.onImageSelected(image);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageSourceDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(context, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(context, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showImageSourceDialog(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppTheme.lightGrey,
          ),
          child: widget.selectedImage != null
              ? Stack(
                  children: [
                    // Show selected image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildSelectedImage(),
                    ),
                    // Change image button
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                )
                  : widget.currentImageUrl != null && widget.currentImageUrl!.isNotEmpty
                  ? Stack(
                      children: [
                        // Show current image from URL
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: widget.currentImageUrl!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                              ),
                            ),
                            errorWidget: (context, url, error) => _buildPlaceholder(),
                          ),
                        ),
                        // Change image button
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    )
                  : _buildPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildSelectedImage() {
    // Always use Image.memory with bytes for all platforms (web-compatible)
    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate,
          size: 64,
          color: AppTheme.grey,
        ),
        const SizedBox(height: 8),
        Text(
          'Tap to select image',
          style: TextStyle(
            color: AppTheme.grey,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

