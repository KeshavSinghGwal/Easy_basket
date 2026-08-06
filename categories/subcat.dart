import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/category_model.dart';
import '../../providers/product_provider.dart';
import '../../utils/theme.dart';
import '../../utils/responsive.dart';

class SubcategorySelectionScreen extends StatefulWidget {
  final int parentCategoryId;
  final String parentCategoryName;

  const SubcategorySelectionScreen({
    super.key,
    required this.parentCategoryId,
    required this.parentCategoryName,
  });

  @override
  State<SubcategorySelectionScreen> createState() => _SubcategorySelectionScreenState();
}

class _SubcategorySelectionScreenState extends State<SubcategorySelectionScreen> {
  List<CategoryModel> _subcategories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubcategories();
  }

  Future<void> _loadSubcategories() async {
    setState(() => _isLoading = true);
    
    final provider = Provider.of<ProductProvider>(context, listen: false);
    
    try {
      // Fetch subcategories using the API
      final response = await provider.apiService.get('/categories/${widget.parentCategoryId}/subcategories');
      
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
      setState(() {
        _subcategories = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = Responsive(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = responsive.getCategoryGridColumns();
    final aspectRatio = screenWidth < 360 ? 1.15 : 1.1;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          widget.parentCategoryName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
              ),
            )
          : _subcategories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 80,
                        color: AppTheme.grey.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No subcategories available',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.grey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppTheme.gradientButton(
                        onPressed: () => context.push('/products?categoryId=${widget.parentCategoryId}'),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_bag, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('View All Products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSubcategories,
                  color: AppTheme.primaryGreen,
                  child: GridView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth < 360 ? 8 : 12,
                      vertical: screenWidth < 360 ? 8 : 12,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: aspectRatio,
                      crossAxisSpacing: screenWidth < 360 ? 8 : 12,
                      mainAxisSpacing: screenWidth < 360 ? 8 : 12,
                    ),
                    itemCount: _subcategories.length + 1, // +1 for "View All" option
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // "View All Products" card
                        return _ViewAllCard(
                          parentCategoryId: widget.parentCategoryId,
                          parentCategoryName: widget.parentCategoryName,
                        );
                      }
                      final subcategory = _subcategories[index - 1];
                      return _SubcategoryCard(
                        subcategory: subcategory,
                        parentCategoryId: widget.parentCategoryId,
                      );
                    },
                  ),
                ),
    );
  }
}

class _ViewAllCard extends StatelessWidget {
  final int parentCategoryId;
  final String parentCategoryName;

  const _ViewAllCard({
    required this.parentCategoryId,
    required this.parentCategoryName,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = Responsive(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = screenWidth < 360 ? 42.0 : 45.0;

    return GestureDetector(
      onTap: () => context.push('/products?categoryId=$parentCategoryId'),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryGreen,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryGreen.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth < 360 ? 4 : 6,
            vertical: screenWidth < 360 ? 6 : 8,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.shopping_bag,
                  size: responsive.iconSize(22),
                  color: Colors.white,
                ),
              ),
              SizedBox(height: screenWidth < 360 ? 2 : 3),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    'View All',
                    style: TextStyle(
                      fontSize: responsive.fontSize(11),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryGreen,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubcategoryCard extends StatelessWidget {
  final CategoryModel subcategory;
  final int parentCategoryId;

  const _SubcategoryCard({
    required this.subcategory,
    required this.parentCategoryId,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = Responsive(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = screenWidth < 360 ? 42.0 : 45.0;

    return GestureDetector(
      onTap: () {
        // Navigate to products in this subcategory
        context.push('/products?categoryId=${subcategory.id}');
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth < 360 ? 4 : 6,
            vertical: screenWidth < 360 ? 6 : 8,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: subcategory.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: subcategory.imageUrl!,
                          width: iconSize,
                          height: iconSize,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: AppTheme.primaryGreen.withOpacity(0.1),
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Icon(
                            Icons.category_rounded,
                            size: responsive.iconSize(22),
                            color: AppTheme.primaryGreen,
                          ),
                          fadeInDuration: const Duration(milliseconds: 300),
                        ),
                      )
                    : Icon(
                        Icons.category_rounded,
                        size: responsive.iconSize(22),
                        color: AppTheme.primaryGreen,
                      ),
              ),
              SizedBox(height: screenWidth < 360 ? 2 : 3),
              Flexible(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: screenWidth < 360 ? 1 : 2),
                  child: Text(
                    subcategory.name.isNotEmpty ? subcategory.name : 'Category',
                    style: TextStyle(
                      fontSize: responsive.fontSize(11),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.black,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

