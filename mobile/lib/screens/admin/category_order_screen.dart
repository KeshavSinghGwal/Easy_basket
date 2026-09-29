import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/category_model.dart';
import '../../utils/theme.dart';

class CategoryOrderScreen extends StatefulWidget {
  const CategoryOrderScreen({super.key});

  @override
  State<CategoryOrderScreen> createState() => _CategoryOrderScreenState();
}

class _CategoryOrderScreenState extends State<CategoryOrderScreen> {
  List<CategoryModel> _orderedCategories = [];
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    await adminProvider.fetchCategories(token: authProvider.token);
    
    // Only show top-level active categories (as they appear on user home page)
    setState(() {
      _orderedCategories = adminProvider.categories
          .where((c) => c.isActive && c.isTopLevel)
          .toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      _hasChanges = false;
    });
    
    setState(() => _isLoading = false);
  }

  Future<void> _saveOrder() async {
    if (!_hasChanges) return;

    setState(() => _isLoading = true);
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.token == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Update display order for each category based on its position
    bool allSuccess = true;
    for (int i = 0; i < _orderedCategories.length; i++) {
      final category = _orderedCategories[i];
      final success = await adminProvider.updateCategory(
        token: authProvider.token!,
        categoryId: category.id,
        displayOrder: i,
      );
      if (!success) {
        allSuccess = false;
      }
    }

    setState(() => _isLoading = false);

    if (allSuccess && mounted) {
      setState(() => _hasChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Category order saved! Changes will appear on user app home page.'),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
      _loadCategories(); // Reload to get updated order
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(adminProvider.error ?? 'Failed to save category order'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    setState(() {
      final category = _orderedCategories.removeAt(oldIndex);
      _orderedCategories.insert(newIndex, category);
      _hasChanges = true;
    });
  }

  void _updateCategoryOrder(int index, int newOrder) {
    if (newOrder < 1 || newOrder > _orderedCategories.length) return;
    
    setState(() {
      final category = _orderedCategories[index];
      final oldIndex = _orderedCategories.indexWhere((c) => c.id == category.id);
      
      // Remove from current position
      _orderedCategories.removeAt(oldIndex);
      
      // Insert at new position (newOrder is 1-based, index is 0-based)
      _orderedCategories.insert(newOrder - 1, category);
      
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Order'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_hasChanges) {
              _showUnsavedChangesDialog();
            } else {
              context.pop();
            }
          },
        ),
        actions: [
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isLoading ? null : _saveOrder,
              tooltip: 'Save Order',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadCategories,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading && _orderedCategories.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _orderedCategories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.category_outlined, size: 64, color: AppTheme.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No categories found',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.grey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadCategories,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Info Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: AppTheme.primaryGreen),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Enter order numbers (1, 2, 3...) to control how categories appear on the user app home page.',
                              style: TextStyle(
                                color: AppTheme.primaryGreen,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Category List with Number Input
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _orderedCategories.length,
                        itemBuilder: (context, index) {
                          final category = _orderedCategories[index];
                          return _CategoryOrderCard(
                            key: ValueKey(category.id),
                            category: category,
                            position: index + 1,
                            totalCategories: _orderedCategories.length,
                            onOrderChanged: (newOrder) => _updateCategoryOrder(index, newOrder),
                          );
                        },
                      ),
                    ),
                    // Save Button
                    if (_hasChanges)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _saveOrder,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(_isLoading ? 'Saving...' : 'Save Category Order'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Future<void> _showUnsavedChangesDialog() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Do you want to discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (shouldDiscard == true && mounted) {
      context.pop();
    }
  }
}

class _CategoryOrderCard extends StatefulWidget {
  final CategoryModel category;
  final int position;
  final int totalCategories;
  final ValueChanged<int>? onOrderChanged;

  const _CategoryOrderCard({
    required Key key,
    required this.category,
    required this.position,
    required this.totalCategories,
    this.onOrderChanged,
  }) : super(key: key);

  @override
  State<_CategoryOrderCard> createState() => _CategoryOrderCardState();
}

class _CategoryOrderCardState extends State<_CategoryOrderCard> {
  late TextEditingController _orderController;
  int _currentPosition = 0;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.position;
    _orderController = TextEditingController(text: widget.position.toString());
  }

  @override
  void didUpdateWidget(_CategoryOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != _currentPosition) {
      _currentPosition = widget.position;
      _orderController.text = widget.position.toString();
    }
  }

  @override
  void dispose() {
    _orderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    
    return Card(
      key: widget.key,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Order Number Input
            Container(
              width: 70,
              child: TextField(
                controller: _orderController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGreen,
                ),
                decoration: InputDecoration(
                  labelText: 'Order',
                  labelStyle: TextStyle(fontSize: 11, color: AppTheme.grey),
                  hintText: '1',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.primaryGreen),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.primaryGreen),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.primaryGreen, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  isDense: true,
                ),
                onChanged: (value) {
                  final newOrder = int.tryParse(value);
                  if (newOrder != null && newOrder >= 1 && newOrder <= widget.totalCategories) {
                    widget.onOrderChanged?.call(newOrder);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            // Category Image
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: widget.category.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: widget.category.imageUrl!,
                        fit: BoxFit.cover,
                        width: 60,
                        height: 60,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.category,
                          size: 28,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.category,
                      size: 28,
                      color: AppTheme.primaryGreen,
                    ),
            ),
            const SizedBox(width: 12),
            // Category Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.category.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.category.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.category.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (widget.category.hasSubcategories) ...[
                    const SizedBox(height: 4),
                    Chip(
                      label: Text(
                        '${widget.category.subcategories!.length} subcategories',
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
