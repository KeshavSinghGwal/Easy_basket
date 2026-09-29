import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/category_model.dart';
import '../../utils/theme.dart';
import '../../widgets/image_picker_widget.dart';
import '../../widgets/image_name_input_widget.dart';
import '../../services/image_upload_service.dart';

class AddEditCategoryScreen extends StatefulWidget {
  final CategoryModel? category;
  final int? categoryId;
  final int? parentCategoryId;

  const AddEditCategoryScreen({
    super.key,
    this.category,
    this.categoryId,
    this.parentCategoryId,
  });

  @override
  State<AddEditCategoryScreen> createState() => _AddEditCategoryScreenState();
}

class _AddEditCategoryScreenState extends State<AddEditCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _imageNameController = TextEditingController();
  final _displayOrderController = TextEditingController();
  XFile? _selectedImage;
  bool _isUploadingImage = false;
  double _uploadProgress = 0.0;
  bool _isActive = true;
  bool _isLoading = false;
  final ImageUploadService _imageUploadService = ImageUploadService();

  CategoryModel? _category;
  bool _isLoadingCategory = false;
  int? _selectedParentCategoryId;
  List<CategoryModel> _parentCategories = [];

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    
    // Set parent category if provided
    if (widget.parentCategoryId != null) {
      _selectedParentCategoryId = widget.parentCategoryId;
    }
    
    if (_category != null) {
      _loadCategoryData();
    } else if (widget.categoryId != null) {
      _loadCategory();
    }
    _loadParentCategories();
  }

  Future<void> _loadCategory() async {
    setState(() => _isLoadingCategory = true);
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await adminProvider.fetchCategories(token: authProvider.token);

    CategoryModel? found;
    // First: check top-level categories
    for (final cat in adminProvider.categories) {
      if (cat.id == widget.categoryId) {
        found = cat;
        break;
      }
      // Then: check subcategories nested inside each parent
      if (cat.subcategories != null) {
        for (final sub in cat.subcategories!) {
          if (sub.id == widget.categoryId) {
            found = sub.copyWith(parentCategoryId: cat.id);
            break;
          }
        }
        if (found != null) break;
      }
    }

    if (found != null) {
      _category = found;
      _loadCategoryData();
    } else {
      // Category not found — show error, don't load random fallback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category not found')),
        );
        Navigator.of(context).pop();
      }
    }
    setState(() => _isLoadingCategory = false);
  }

  void _loadCategoryData() {
    if (_category != null) {
      _nameController.text = _category!.name;
      _descriptionController.text = _category!.description ?? '';
      _imageUrlController.text = _category!.imageUrl ?? '';
      _isActive = _category!.isActive;
      _selectedParentCategoryId = _category!.parentCategoryId;
      _displayOrderController.text = _category!.displayOrder.toString();
      
      // Auto-fill image name from category name
      if (_imageNameController.text.isEmpty) {
        _imageNameController.text = _category!.name.toLowerCase().replaceAll(' ', '-');
      }
    } else {
      // Set default display order for new categories
      _displayOrderController.text = '0';
    }
  }

  Future<void> _loadParentCategories() async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.token == null) return;
    
    try {
      await adminProvider.fetchCategories(token: authProvider.token);
      // Only show top-level categories as potential parents
      setState(() {
        _parentCategories = adminProvider.categories
            .where((cat) => cat.isTopLevel && (widget.categoryId == null || cat.id != widget.categoryId))
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading parent categories: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    _imageNameController.dispose();
    _displayOrderController.dispose();
    super.dispose();
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an image first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Need category ID for upload - if creating new category, save it first
    int? categoryId = _category?.id;
    
    if (categoryId == null) {
      // Create category first if it doesn't exist
      if (!_formKey.currentState!.validate()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill in all required fields first'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Create category first
      setState(() => _isLoading = true);
      
      final adminProvider = Provider.of<AdminProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      if (authProvider.token == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required')),
        );
        return;
      }

      final success = await adminProvider.createCategory(
        token: authProvider.token!,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        imageUrl: null, // Will be set after upload
      );

      setState(() => _isLoading = false);

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminProvider.error ?? 'Failed to create category')),
        );
        return;
      }

      // Get the newly created category ID
      await adminProvider.fetchCategories(token: authProvider.token!);
      final newCategory = adminProvider.categories.firstWhere(
        (c) => c.name == _nameController.text.trim(),
        orElse: () => adminProvider.categories.last,
      );
      categoryId = newCategory.id;
      _category = newCategory;
    }

    setState(() {
      _isUploadingImage = true;
      _uploadProgress = 0.0;
    });

    try {
      // Compress image
      final compressedBytes = await _imageUploadService.compressImage(_selectedImage!);
      if (compressedBytes == null) {
        throw Exception('Failed to compress image');
      }

      // Get auth token
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.token == null) {
        throw Exception('Authentication required');
      }

      // Upload to backend
      setState(() => _uploadProgress = 0.3);
      
      final result = await _imageUploadService.uploadImage(
        imageBytes: compressedBytes,
        type: 'category',
        id: categoryId!,
        adminName: _imageNameController.text.trim().isNotEmpty
            ? _imageNameController.text.trim()
            : null,
        entityName: _nameController.text.trim(),
        token: authProvider.token!,
      );

      setState(() => _uploadProgress = 1.0);

      if (result != null && result['url'] != null) {
        // Update image URL in controller
        _imageUrlController.text = result['url'] as String;
        
        // Update category with new image URL
        await _updateCategoryImageUrl(result['url'] as String);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Image uploaded successfully!'),
                ],
              ),
              backgroundColor: AppTheme.primaryGreen,
            ),
          );
        }
      } else {
        throw Exception('Upload failed: No URL returned');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading image: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isUploadingImage = false;
        _uploadProgress = 0.0;
      });
    }
  }

  Future<void> _updateCategoryImageUrl(String imageUrl) async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.token == null || _category == null) return;

    try {
      await adminProvider.updateCategory(
        token: authProvider.token!,
        categoryId: _category!.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        imageUrl: imageUrl,
      );
    } catch (e) {
      debugPrint('Error updating category image URL: $e');
    }
  }

  Future<void> _saveCategory() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.token == null) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required')),
        );
      }
      return;
    }

    final displayOrder = int.tryParse(_displayOrderController.text.trim()) ?? 0;
    
    final success = _category == null
        ? await adminProvider.createCategory(
            token: authProvider.token!,
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
            parentCategoryId: _selectedParentCategoryId,
            displayOrder: displayOrder,
          )
        : await adminProvider.updateCategory(
            token: authProvider.token!,
            categoryId: _category!.id,
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
            isActive: _isActive,
            parentCategoryId: _selectedParentCategoryId,
            displayOrder: displayOrder,
          );

    setState(() => _isLoading = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_category == null ? 'Category created successfully!' : 'Category updated successfully!'),
        ),
      );
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(adminProvider.error ?? 'Failed to save category')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingCategory) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_category == null ? 'Add Category' : 'Edit Category'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Category Name *',
                prefixIcon: Icon(Icons.category),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Category name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Parent Category Selection
            DropdownButtonFormField<int?>(
              value: _selectedParentCategoryId,
              decoration: const InputDecoration(
                labelText: 'Parent Category (Optional)',
                hintText: 'Select parent category for subcategory',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
                helperText: 'Leave empty for top-level category',
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('None (Top-level Category)'),
                ),
                ..._parentCategories.map((category) => DropdownMenuItem<int?>(
                  value: category.id,
                  child: Text(category.name),
                )),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedParentCategoryId = value;
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _displayOrderController,
              decoration: const InputDecoration(
                labelText: 'Display Order',
                hintText: 'Lower numbers appear first (0, 1, 2...)',
                prefixIcon: Icon(Icons.sort),
                border: OutlineInputBorder(),
                helperText: 'Set the order in which this category appears',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return null; // Optional field
                }
                final order = int.tryParse(value.trim());
                if (order == null || order < 0) {
                  return 'Please enter a valid number (0 or greater)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.description),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            
            // Image Upload Section
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppTheme.lightGrey),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.image, color: AppTheme.primaryGreen, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Category Image',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Image Picker
                    ImagePickerWidget(
                      selectedImage: _selectedImage,
                      currentImageUrl: _category?.imageUrl,
                      onImageSelected: (image) {
                        setState(() {
                          _selectedImage = image;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Image Name Input (for filename)
                    ImageNameInputWidget(
                      controller: _imageNameController,
                      entityName: _nameController.text.trim().isNotEmpty
                          ? _nameController.text.trim()
                          : null,
                      entityId: _category?.id,
                      type: 'category',
                    ),
                    const SizedBox(height: 16),
                    
                    // Upload Button (show if image selected)
                    if (_selectedImage != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isUploadingImage ? null : _uploadImage,
                          icon: _isUploadingImage
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.cloud_upload),
                          label: Text(_isUploadingImage ? 'Uploading...' : 'Upload Image'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_isUploadingImage) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: AppTheme.lightGrey,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                        ),
                      ],
                    ],
                    
                    // Or Manual URL Input (fallback)
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Or enter image URL manually:',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _imageUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Image URL',
                        prefixIcon: Icon(Icons.link, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                  ],
                ),
              ),
            ),
            if (_category != null) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Active'),
                subtitle: const Text('Inactive categories won\'t be shown to customers'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveCategory,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppTheme.primaryGreen,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.white),
                    )
                  : Text(
                      _category == null ? 'Create Category' : 'Update Category',
                      style: const TextStyle(fontSize: 16, color: AppTheme.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

