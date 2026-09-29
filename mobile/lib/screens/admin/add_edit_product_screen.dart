import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../utils/theme.dart';
import '../../widgets/image_picker_widget.dart';
import '../../widgets/image_name_input_widget.dart';
import '../../widgets/variant_management_dialog.dart';
import '../../services/image_upload_service.dart';

class AddEditProductScreen extends StatefulWidget {
  final ProductModel? product;
  final int? productId;

  const AddEditProductScreen({super.key, this.product, this.productId});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _imageNameController = TextEditingController();
  XFile? _selectedImage;
  bool _isUploadingImage = false;
  double _uploadProgress = 0.0;
  int? _selectedCategoryId;
  int? _selectedParentCategoryId;
  String _selectedUnit = 'piece';
  bool _isAvailable = true;
  bool _isLoading = false;
  List<CategoryModel> _categories = [];
  final ImageUploadService _imageUploadService = ImageUploadService();

  final List<String> _units = ['piece', 'kg', 'g', 'liter', 'ml', 'pack', 'dozen'];

  ProductModel? _product;
  bool _isLoadingProduct = false;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    
    // Defer async operations to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
      if (_product != null) {
        _loadProductData();
      } else if (widget.productId != null) {
        _loadProduct();
      }
    });
  }

  Future<void> _loadProduct() async {
    if (widget.productId == null) return;
    
    setState(() => _isLoadingProduct = true);
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.token == null) {
      setState(() => _isLoadingProduct = false);
      return;
    }
    
    // Fetch product directly by ID instead of fetching all products
    _product = await adminProvider.fetchProductById(
      token: authProvider.token!,
      productId: widget.productId!,
    );
    
    if (_product != null) {
      _loadProductData();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load product')),
        );
        context.pop();
      }
    }
    
    setState(() => _isLoadingProduct = false);
  }

  void _loadProductData() {
    if (_product != null) {
      _nameController.text = _product!.name;
      _descriptionController.text = _product!.description ?? '';
      _tagsController.text = _product!.tags ?? '';
      _priceController.text = _product!.price.toString();
      _stockController.text = _product!.stock.toString();
      _imageUrlController.text = _product!.imageUrl ?? '';
      _selectedCategoryId = _product!.category?.id;
      _selectedParentCategoryId = _product!.category?.parentCategoryId ?? _product!.category?.id;
      _selectedUnit = _product!.unit ?? 'piece';
      _isAvailable = _product!.isAvailable;
      
      // Auto-fill image name from product name
      if (_imageNameController.text.isEmpty) {
        _imageNameController.text = _product!.name.toLowerCase().replaceAll(' ', '-');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _imageUrlController.dispose();
    _imageNameController.dispose();
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

    // Need product ID for upload - if creating new product, save it first
    int? productId = _product?.id;
    
    if (productId == null) {
      // Create product first if it doesn't exist
      if (!_formKey.currentState!.validate() || _selectedCategoryId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill in all required fields first'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Create product first
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

      final price = double.tryParse(_priceController.text.trim());
      final stock = int.tryParse(_stockController.text.trim()) ?? 0;

      if (price == null || price <= 0) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid price')),
        );
        return;
      }

      final success = await adminProvider.createProduct(
        token: authProvider.token!,
        name: _nameController.text.trim(),
        price: price,
        categoryId: _selectedCategoryId!,
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            tags: _tagsController.text.trim().isEmpty ? null : _tagsController.text.trim(),
            imageUrl: null, // Will be set after upload
            stock: stock,
        unit: _selectedUnit,
      );

      setState(() => _isLoading = false);

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminProvider.error ?? 'Failed to create product')),
        );
        return;
      }

      // Get the newly created product ID
      await adminProvider.fetchProducts(token: authProvider.token!);
      final newProduct = adminProvider.products.firstWhere(
        (p) => p.name == _nameController.text.trim(),
        orElse: () => adminProvider.products.last,
      );
      productId = newProduct.id;
      _product = newProduct;
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
        type: 'product',
        id: productId!,
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
        
        // Update product with new image URL
        await _updateProductImageUrl(result['url'] as String);

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

  Future<void> _updateProductImageUrl(String imageUrl) async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.token == null || _product == null) return;

    try {
      await adminProvider.updateProduct(
        token: authProvider.token!,
        productId: _product!.id,
        name: _nameController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        categoryId: _selectedCategoryId,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        tags: _tagsController.text.trim().isEmpty ? null : _tagsController.text.trim(),
        imageUrl: imageUrl,
        stock: int.tryParse(_stockController.text.trim()) ?? 0,
        unit: _selectedUnit,
        isAvailable: _isAvailable,
      );
    } catch (e) {
      debugPrint('Error updating product image URL: $e');
    }
  }

  Future<void> _loadCategories() async {
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Load all categories (including subcategories)
    await productProvider.fetchCategories();
    
    // Also fetch all categories from admin provider to get subcategories
    if (authProvider.token != null) {
      await adminProvider.fetchCategories(token: authProvider.token);
    }
    
    // Combine categories: top-level + subcategories
    final allCategories = <CategoryModel>[];
    final addedIds = <int>{};
    
    // Add top-level categories from product provider
    for (var category in productProvider.categories) {
      if (!addedIds.contains(category.id)) {
        allCategories.add(category);
        addedIds.add(category.id);
      }
      // Add subcategories — patch parentCategoryId since API doesn't include it
      if (category.hasSubcategories && category.subcategories != null) {
        for (var subcategory in category.subcategories!) {
          if (!addedIds.contains(subcategory.id)) {
            allCategories.add(subcategory.copyWith(parentCategoryId: category.id));
            addedIds.add(subcategory.id);
          }
        }
      }
    }

    // Also check admin provider categories for any missing ones
    for (var category in adminProvider.categories) {
      if (!addedIds.contains(category.id)) {
        allCategories.add(category);
        addedIds.add(category.id);
      }
      if (category.hasSubcategories && category.subcategories != null) {
        for (var subcategory in category.subcategories!) {
          if (!addedIds.contains(subcategory.id)) {
            allCategories.add(subcategory.copyWith(parentCategoryId: category.id));
            addedIds.add(subcategory.id);
          }
        }
      }
    }
    
    // Sort categories: top-level first, then subcategories grouped under parents
    allCategories.sort((a, b) {
      if (a.isTopLevel && b.isSubcategory) return -1;
      if (a.isSubcategory && b.isTopLevel) return 1;
      if (a.isSubcategory && b.isSubcategory) {
        // Group subcategories by parent
        final aParentId = a.parentCategoryId ?? 0;
        final bParentId = b.parentCategoryId ?? 0;
        if (aParentId != bParentId) return aParentId.compareTo(bParentId);
      }
      return a.name.compareTo(b.name);
    });
    
    if (mounted) {
      setState(() {
        _categories = allCategories;
      });
    }
    
    debugPrint('Loaded ${allCategories.length} categories (${allCategories.where((c) => c.isTopLevel).length} top-level, ${allCategories.where((c) => c.isSubcategory).length} subcategories)');
    
    // If we still don't have subcategories, try fetching them for each parent category
    // Do this after the initial setState to avoid setState during build
    if (allCategories.where((c) => c.isSubcategory).isEmpty && authProvider.token != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        
        debugPrint('No subcategories found in loaded categories, fetching individually...');
        final newSubcategories = <CategoryModel>[];
        final newAddedIds = <int>{...addedIds};
        
        for (var category in allCategories.where((c) => c.isTopLevel)) {
          try {
            final response = await adminProvider.apiService.get(
              '/categories/${category.id}/subcategories',
              token: authProvider.token,
            );
            
            if (response is Map<String, dynamic> && response.containsKey('subcategories')) {
              final List<dynamic> data = response['subcategories'] as List? ?? [];
              for (var subJson in data) {
                try {
                  final subcategory = CategoryModel.fromJson(subJson as Map<String, dynamic>);
                  if (!newAddedIds.contains(subcategory.id)) {
                    newSubcategories.add(subcategory);
                    newAddedIds.add(subcategory.id);
                  }
                } catch (e) {
                  debugPrint('Error parsing subcategory: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('Error fetching subcategories for ${category.name}: $e');
          }
        }
        
        if (newSubcategories.isNotEmpty && mounted) {
          // Sort new subcategories
          newSubcategories.sort((a, b) {
            final aParentId = a.parentCategoryId ?? 0;
            final bParentId = b.parentCategoryId ?? 0;
            if (aParentId != bParentId) return aParentId.compareTo(bParentId);
            return a.name.compareTo(b.name);
          });
          
          // Insert subcategories after their parent categories
          final updatedCategories = <CategoryModel>[];
          for (var category in allCategories) {
            updatedCategories.add(category);
            if (category.isTopLevel) {
              // Add subcategories for this parent
              final parentSubs = newSubcategories
                  .where((sub) => sub.parentCategoryId == category.id)
                  .toList();
              updatedCategories.addAll(parentSubs);
            }
          }
          
          setState(() {
            _categories = updatedCategories;
          });
          
          debugPrint('Added ${newSubcategories.length} subcategories');
        }
      });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

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

    final price = double.tryParse(_priceController.text.trim());
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;

    if (price == null || price <= 0) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price')),
      );
      return;
    }

    final success = _product == null
        ? await adminProvider.createProduct(
            token: authProvider.token!,
            name: _nameController.text.trim(),
            price: price,
            categoryId: _selectedCategoryId!,
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            tags: _tagsController.text.trim(),
            imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
            stock: stock,
            unit: _selectedUnit,
          )
        : await adminProvider.updateProduct(
            token: authProvider.token!,
            productId: _product!.id,
            name: _nameController.text.trim(),
            price: price,
            categoryId: _selectedCategoryId,
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            tags: _tagsController.text.trim(),
            imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
            stock: stock,
            unit: _selectedUnit,
            isAvailable: _isAvailable,
          );

    setState(() => _isLoading = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_product == null ? 'Product created successfully!' : 'Product updated successfully!'),
        ),
      );
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(adminProvider.error ?? 'Failed to save product')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProduct) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_product == null ? 'Add Product' : 'Edit Product'),
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
                labelText: 'Product Name *',
                prefixIcon: Icon(Icons.shopping_bag),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Product name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Parent category dropdown
            Builder(builder: (context) {
              final parents = _categories.where((c) => c.isTopLevel).toList();
              return DropdownButtonFormField<int>(
                value: parents.any((c) => c.id == _selectedParentCategoryId)
                    ? _selectedParentCategoryId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Category *',
                  prefixIcon: Icon(Icons.category),
                  border: OutlineInputBorder(),
                ),
                items: parents.map((cat) {
                  return DropdownMenuItem<int>(
                    value: cat.id,
                    child: Text(cat.name,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedParentCategoryId = value;
                    _selectedCategoryId = null; // reset subcategory
                  });
                },
                validator: (value) =>
                    value == null ? 'Please select a category' : null,
              );
            }),
            const SizedBox(height: 16),
            // Subcategory dropdown (filtered by selected parent)
            Builder(builder: (context) {
              final subs = _selectedParentCategoryId == null
                  ? <CategoryModel>[]
                  : _categories
                      .where((c) => c.parentCategoryId == _selectedParentCategoryId)
                      .toList();
              return DropdownButtonFormField<int>(
                value: subs.any((c) => c.id == _selectedCategoryId)
                    ? _selectedCategoryId
                    : null,
                decoration: InputDecoration(
                  labelText: 'Subcategory *',
                  prefixIcon: const Icon(Icons.subdirectory_arrow_right),
                  border: const OutlineInputBorder(),
                  helperText: _selectedParentCategoryId == null
                      ? 'Select a category first'
                      : (subs.isEmpty ? 'No subcategories available' : null),
                ),
                items: subs.map((cat) {
                  return DropdownMenuItem<int>(
                    value: cat.id,
                    child: Text(cat.name,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  );
                }).toList(),
                onChanged: subs.isEmpty
                    ? null
                    : (value) => setState(() => _selectedCategoryId = value),
                validator: (value) {
                  if (_selectedParentCategoryId == null) return null;
                  if (subs.isEmpty) return null;
                  if (value == null) return 'Please select a subcategory';
                  return null;
                },
              );
            }),
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
            TextFormField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Search Tags (comma-separated)',
                prefixIcon: Icon(Icons.tag),
                border: OutlineInputBorder(),
                helperText: 'Add synonyms/keywords (e.g., "soda, cold drink" for "Coke")',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price (₹) *',
                      prefixIcon: Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Price is required';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price <= 0) {
                        return 'Please enter a valid price';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _stockController,
                    decoration: const InputDecoration(
                      labelText: 'Stock',
                      prefixIcon: Icon(Icons.inventory),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        final stock = int.tryParse(value);
                        if (stock == null || stock < 0) {
                          return 'Please enter a valid stock';
                        }
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedUnit,
              decoration: const InputDecoration(
                labelText: 'Unit',
                prefixIcon: Icon(Icons.scale),
                border: OutlineInputBorder(),
              ),
              items: _units.map((unit) {
                return DropdownMenuItem<String>(
                  value: unit,
                  child: Text(unit.toUpperCase()),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedUnit = value!),
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
                          'Product Image',
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
                      currentImageUrl: _product?.imageUrl,
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
                      entityId: _product?.id,
                      type: 'product',
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
            if (_product != null) ...[
              const SizedBox(height: 16),
              // Variant Management Section
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
                          Icon(Icons.inventory_2, color: AppTheme.primaryGreen, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Product Variants',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add quantity/weight options (e.g., 250g, 1kg, 2kg, 5kg)',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final result = await showDialog<bool>(
                              context: context,
                              builder: (context) => VariantManagementDialog(
                                productId: _product!.id,
                                productName: _product!.name,
                              ),
                            );
                            if (result == true) {
                              // Refresh product data if needed
                              _loadProduct();
                            }
                          },
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Manage Variants'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryGreen,
                            side: BorderSide(color: AppTheme.primaryGreen),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Available'),
                subtitle: const Text('Unavailable products won\'t be shown to customers'),
                value: _isAvailable,
                onChanged: (value) => setState(() => _isAvailable = value),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveProduct,
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
                      _product == null ? 'Create Product' : 'Update Product',
                      style: const TextStyle(fontSize: 16, color: AppTheme.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

