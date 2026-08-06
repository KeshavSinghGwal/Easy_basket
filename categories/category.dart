import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/product_provider.dart';
import '../../models/category_model.dart';
import '../../utils/theme.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
    });
  }

  void _loadCategories() {
    if (_hasLoaded) return;
    final provider = Provider.of<ProductProvider>(context, listen: false);
    _hasLoaded = true;
    provider.fetchCategories();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'All Categories',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          // Green gradient from top — covers AppBar + fades into body
          Container(
            height: topPadding + kToolbarHeight + 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color.fromARGB(255, 123, 226, 127).withValues(alpha: 0.18),
                  const Color(0xFFF6F6F6),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 1.0],
              ),
            ),
          ),
          Consumer<ProductProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading && provider.categories.isEmpty) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                  ),
                );
              }

              if (provider.categories.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 80,
                        color: AppTheme.grey.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No categories available',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // 3 columns on mobile, consistent with home page grid
              final crossAxisCount = screenWidth < 360 ? 3 : screenWidth < 600 ? 3 : 4;
              final gridTopPadding = topPadding + kToolbarHeight + 12;

              return RefreshIndicator(
                onRefresh: () async {
                  final provider = Provider.of<ProductProvider>(context, listen: false);
                  await provider.fetchCategories();
                },
                color: AppTheme.primaryGreen,
                child: GridView.builder(
                  padding: EdgeInsets.only(
                    top: gridTopPadding,
                    left: 12,
                    right: 12,
                    bottom: 24,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.74,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: provider.categories.length,
                  itemBuilder: (context, index) {
                    final category = provider.categories[index];
                    if (category.name.isEmpty || category.id <= 0) {
                      return const SizedBox.shrink();
                    }
                    return _CategoryCard(category: category);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryModel category;

  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        debugPrint('Tapped category: ${category.name} (ID: ${category.id})');
        context.push('/categories/${category.id}/products', extra: {
          'parentCategoryName': category.name,
        });
      },
      child: Column(
        children: [
          // Square rounded image box
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: Colors.white,
                  child: InkWell(
                    onTap: () {
                      context.push('/categories/${category.id}/products', extra: {
                        'parentCategoryName': category.name,
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    splashColor: AppTheme.primaryGreen.withValues(alpha: 0.08),
                    child: category.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: category.imageUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (context, url) => Container(
                              color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                              child: const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                              child: const Icon(Icons.category_rounded, size: 28, color: AppTheme.primaryGreen),
                            ),
                            fadeInDuration: const Duration(milliseconds: 200),
                          )
                        : Container(
                            color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                            child: const Center(
                              child: Icon(Icons.category_rounded, size: 28, color: AppTheme.primaryGreen),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          // Text outside the box
          const SizedBox(height: 6),
          Text(
            category.name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.black,
              height: 1.15,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
