import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/category_model.dart';
import '../../utils/theme.dart';

class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      final adminProvider = Provider.of<AdminProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (adminProvider.hasMore && !adminProvider.isLoadingMore) {
        adminProvider.fetchCategories(token: authProvider.token, loadMore: true);
      }
    }
  }

  void _loadCategories() {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    adminProvider.fetchCategories(token: authProvider.token);
  }

  Future<void> _deleteCategory(CategoryModel category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete "${category.name}"? This will affect all products in this category.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final adminProvider = Provider.of<AdminProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.token == null) return;

      final success = await adminProvider.deleteCategory(
        token: authProvider.token!,
        categoryId: category.id,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category deleted successfully!')),
        );
        _loadCategories();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminProvider.error ?? 'Failed to delete category')),
        );
      }
    }
  }

  Future<void> _editCategory(CategoryModel category) async {
    final result = await context.push('/admin/categories/${category.id}/edit');
    if (result == true) {
      _loadCategories();
    }
  }

  Future<void> _toggleCategoryStatus(CategoryModel category) async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.token == null) return;

    final success = await adminProvider.updateCategory(
      token: authProvider.token!,
      categoryId: category.id,
      isActive: !category.isActive,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Category ${!category.isActive ? 'activated' : 'deactivated'} successfully!'),
        ),
      );
      _loadCategories();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(adminProvider.error ?? 'Failed to update category')),
      );
    }
  }

  Future<void> _moveCategory(CategoryModel category, int direction) async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.token == null) return;

    // Find current index
    final currentIndex = adminProvider.categories.indexWhere((c) => c.id == category.id);
    if (currentIndex == -1) return;

    // Calculate new index
    final newIndex = currentIndex + direction;
    if (newIndex < 0 || newIndex >= adminProvider.categories.length) return;

    // Get the category we're swapping with
    final swapCategory = adminProvider.categories[newIndex];
    
    // Swap display orders
    final tempOrder = category.displayOrder;
    final newOrder = swapCategory.displayOrder;

    // Update both categories
    final success1 = await adminProvider.updateCategory(
      token: authProvider.token!,
      categoryId: category.id,
      displayOrder: newOrder,
    );

    final success2 = await adminProvider.updateCategory(
      token: authProvider.token!,
      categoryId: swapCategory.id,
      displayOrder: tempOrder,
    );

    if (success1 && success2 && mounted) {
      _loadCategories();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(adminProvider.error ?? 'Failed to reorder category')),
      );
    }
  }

  Future<void> _viewSubcategories(CategoryModel category) async {
    // If category has subcategories, show them in a dialog or navigate
    if (category.hasSubcategories) {
      await showDialog(
        context: context,
        builder: (context) => _SubcategoriesDialog(
          parentCategory: category,
          onEdit: _editCategory,
          onDelete: _deleteCategory,
          onToggleStatus: _toggleCategoryStatus,
        ),
      );
      // Refresh categories after dialog closes
      _loadCategories();
    } else {
      // If no subcategories, show a message or allow adding one
      final addSubcategory = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${category.name}'),
          content: const Text('This category has no subcategories. Would you like to add one?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add Subcategory'),
            ),
          ],
        ),
      );

      if (addSubcategory == true && mounted) {
        // Navigate to add category screen with parent pre-selected
        final result = await context.push('/admin/categories/add', extra: {
          'parentCategoryId': category.id,
        });
        if (result == true) {
          _loadCategories();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final adminProvider = Provider.of<AdminProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => context.push('/admin/categories/order'),
            tooltip: 'Manage Category Order',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCategories,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _loadCategories(),
        child: adminProvider.isLoading && adminProvider.categories.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : adminProvider.categories.isEmpty
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
                          onPressed: () => context.push('/admin/categories/add'),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Category'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: adminProvider.categories.length + (adminProvider.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == adminProvider.categories.length) {
                        // Load more indicator
                        if (adminProvider.isLoadingMore) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                      final category = adminProvider.categories[index];
                      final canMoveUp = index > 0;
                      final canMoveDown = index < adminProvider.categories.length - 1;
                      return _CategoryCard(
                        category: category,
                        canMoveUp: canMoveUp,
                        canMoveDown: canMoveDown,
                        onEdit: () => _editCategory(category),
                        onDelete: () => _deleteCategory(category),
                        onToggleStatus: () => _toggleCategoryStatus(category),
                        onTap: () => _viewSubcategories(category),
                        onMoveUp: canMoveUp ? () => _moveCategory(category, -1) : null,
                        onMoveDown: canMoveDown ? () => _moveCategory(category, 1) : null,
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await context.push('/admin/categories/add');
          if (result == true) {
            _loadCategories();
          }
        },
        backgroundColor: AppTheme.primaryGreen,
        child: const Icon(Icons.add, color: AppTheme.white),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleStatus;
  final VoidCallback? onTap;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleStatus,
    this.onTap,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
            // Category Image/Icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: category.isActive ? AppTheme.primaryGreen.withOpacity(0.1) : AppTheme.lightGrey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: category.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: category.imageUrl!,
                        fit: BoxFit.cover,
                        width: 60,
                        height: 60,
                        placeholder: (context, url) => Container(
                          color: AppTheme.primaryGreen.withOpacity(0.1),
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (_, __, ___) => Icon(
                          Icons.category,
                          size: 32,
                          color: category.isActive ? AppTheme.primaryGreen : AppTheme.grey,
                        ),
                        fadeInDuration: const Duration(milliseconds: 300),
                      ),
                    )
                  : Icon(
                      Icons.category,
                      size: 32,
                      color: category.isActive ? AppTheme.primaryGreen : AppTheme.grey,
                    ),
            ),
            const SizedBox(width: 16),
            // Category Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: category.isActive ? AppTheme.black : AppTheme.grey,
                            decoration: category.isActive ? null : TextDecoration.lineThrough,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: category.isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          category.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: category.isActive ? Colors.green : Colors.red,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (category.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      category.description!,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.grey,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (category.hasSubcategories) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right,
                          size: 14,
                          color: AppTheme.primaryGreen,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${category.subcategories!.length} subcategor${category.subcategories!.length == 1 ? 'y' : 'ies'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.primaryGreen,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (category.isSubcategory && category.parentCategory != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 12,
                          color: AppTheme.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Parent: ${category.parentCategory!.name}',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Actions - Use Column with mainAxisSize.min
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reorder buttons
                if (onMoveUp != null || onMoveDown != null) ...[
                  IconButton(
                    icon: Icon(
                      Icons.arrow_upward,
                      color: canMoveUp ? AppTheme.primaryGreen : AppTheme.grey,
                      size: 18,
                    ),
                    onPressed: canMoveUp ? onMoveUp : null,
                    tooltip: 'Move Up',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.arrow_downward,
                      color: canMoveDown ? AppTheme.primaryGreen : AppTheme.grey,
                      size: 18,
                    ),
                    onPressed: canMoveDown ? onMoveDown : null,
                    tooltip: 'Move Down',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(height: 4),
                ],
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                  onPressed: onEdit,
                  tooltip: 'Edit Category',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                    category.isActive ? Icons.visibility_off : Icons.visibility,
                    color: Colors.orange,
                    size: 20,
                  ),
                  onPressed: onToggleStatus,
                  tooltip: category.isActive ? 'Deactivate' : 'Activate',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _SubcategoriesDialog extends StatefulWidget {
  final CategoryModel parentCategory;
  final Function(CategoryModel) onEdit;
  final Function(CategoryModel) onDelete;
  final Function(CategoryModel) onToggleStatus;

  const _SubcategoriesDialog({
    required this.parentCategory,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleStatus,
  });

  @override
  State<_SubcategoriesDialog> createState() => _SubcategoriesDialogState();
}

class _SubcategoriesDialogState extends State<_SubcategoriesDialog> {
  List<CategoryModel> _subcategories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubcategories();
  }

  Future<void> _loadSubcategories() async {
    setState(() => _isLoading = true);
    
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.token == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Fetch subcategories using the API
      if (authProvider.token == null) {
        setState(() {
          _subcategories = [];
          _isLoading = false;
        });
        return;
      }
      
      // Include inactive subcategories for admin dashboard
      final response = await adminProvider.apiService.get(
        '/categories/${widget.parentCategory.id}/subcategories?includeInactive=true',
        token: authProvider.token!,
      );
      
      if (response is Map<String, dynamic> && response.containsKey('subcategories')) {
        final List<dynamic> data = response['subcategories'] as List? ?? [];
        setState(() {
          _subcategories = data
              .map((json) => CategoryModel.fromJson(json as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _subcategories = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading subcategories: $e');
      setState(() {
        _subcategories = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(
                'Subcategories: ${widget.parentCategory.name}',
                style: const TextStyle(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    final result = await context.push('/admin/categories/add', extra: {
                      'parentCategoryId': widget.parentCategory.id,
                    });
                    if (result == true) {
                      _loadSubcategories();
                    }
                  },
                  tooltip: 'Add Subcategory',
                ),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _subcategories.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.category_outlined, size: 64, color: AppTheme.grey),
                              const SizedBox(height: 16),
                              Text(
                                'No subcategories',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.grey,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final result = await context.push('/admin/categories/add', extra: {
                                    'parentCategoryId': widget.parentCategory.id,
                                  });
                                  if (result == true) {
                                    _loadSubcategories();
                                  }
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Add Subcategory'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _subcategories.length,
                          itemBuilder: (context, index) {
                            final subcategory = _subcategories[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: subcategory.imageUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: subcategory.imageUrl!,
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => Icon(
                                            Icons.category,
                                            size: 24,
                                            color: AppTheme.primaryGreen,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.category,
                                        size: 24,
                                        color: AppTheme.primaryGreen,
                                      ),
                                title: Text(subcategory.name),
                                subtitle: subcategory.description != null
                                    ? Text(subcategory.description!)
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      color: Colors.blue,
                                      onPressed: () {
                                        widget.onEdit(subcategory);
                                        Navigator.pop(context);
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        subcategory.isActive ? Icons.visibility_off : Icons.visibility,
                                        size: 20,
                                      ),
                                      color: Colors.orange,
                                      onPressed: () {
                                        widget.onToggleStatus(subcategory);
                                        _loadSubcategories();
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 20),
                                      color: Colors.red,
                                      onPressed: () {
                                        widget.onDelete(subcategory);
                                        _loadSubcategories();
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
