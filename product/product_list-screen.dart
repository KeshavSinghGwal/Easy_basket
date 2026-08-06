import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/product_provider.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/floating_cart_bar.dart';
import '../../services/speech_service.dart';
import '../../services/keyword_extraction_service.dart';
import '../../utils/theme.dart';
import '../../utils/responsive.dart';

class ProductListScreen extends StatefulWidget {
  final int? categoryId;
  final bool startVoiceSearch;

  const ProductListScreen({super.key, this.categoryId, this.startVoiceSearch = false});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _searchController = TextEditingController();
  String? _categoryName;
  Timer? _debounce;
  bool _isSearching = false;

  // Voice search
  final SpeechService _speechService = SpeechService();
  bool _isListening = false;
  String? _voiceStatus;
  String? _liveTranscript; // Interim results shown while speaking
  List<ExtractedItem> _extractedItems = [];

  @override
  void initState() {
    super.initState();
    _categoryName = null;
    _initVoice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategoriesAndProducts();
    });
  }

  void _loadCategoriesAndProducts() {
    final provider = Provider.of<ProductProvider>(context, listen: false);
    
    if (provider.categories.isEmpty) {
      provider.fetchCategories().then((_) {
        _updateCategoryName();
        _loadProducts();
      });
    } else {
      _updateCategoryName();
      _loadProducts();
    }
  }

  void _updateCategoryName() {
    if (widget.categoryId != null) {
      final provider = Provider.of<ProductProvider>(context, listen: false);
      try {
        final category = provider.categories.firstWhere(
          (cat) => cat.id == widget.categoryId,
        );
        if (mounted) {
          setState(() {
            _categoryName = category.name;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _categoryName = null;
          });
        }
      }
    }
  }

  Future<void> _loadProducts() async {
    final provider = Provider.of<ProductProvider>(context, listen: false);
    await provider.fetchProducts(categoryId: widget.categoryId);
    
    if (widget.categoryId != null && _categoryName == null) {
      _updateCategoryName();
    }
  }

  @override
  void didUpdateWidget(ProductListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _categoryName = null;
      if (mounted) {
        setState(() {
          _categoryName = null;
        });
      }
      _updateCategoryName();
      _loadProducts();
    }
  }

  Future<void> _initVoice() async {
    final ok = await _speechService.initialize();
    debugPrint('[Voice] Init result: $ok, startVoice: ${widget.startVoiceSearch}');
    // Auto-start if navigated with voice=true
    if (widget.startVoiceSearch && ok && mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _startListening();
      });
    }
  }

  Future<void> _startListening() async {
    // Check permission first
    final permResult = await _speechService.checkAndRequestPermission();
    if (permResult == MicPermissionResult.permanentlyDenied) {
      if (mounted) _showPermissionDialog();
      return;
    }
    if (permResult == MicPermissionResult.denied) {
      _showStatus('Mic ki permission nahi mili');
      return;
    }

    // Re-initialize after permission grant (in case init failed earlier)
    if (!_speechService.isAvailable) {
      await _speechService.initialize(force: true);
    }

    if (!_speechService.isAvailable) {
      _showStatus('Mic kaam nahi kar raha');
      return;
    }

    setState(() {
      _isListening = true;
      _voiceStatus = 'Boliye...';
      _liveTranscript = null;
      _extractedItems = [];
    });

    await _speechService.startListening(
      onResult: (text, isFinal) {
        if (!mounted) return;
        debugPrint('[Voice] onResult: "$text" isFinal=$isFinal');
        if (isFinal) {
          _onSpeechDone(text);
        } else {
          // Show live transcript — translate words for display
          final words = text.split(RegExp(r'\s+'));
          final display = words
              .map((w) => KeywordExtractionService.translateToEnglish(w.toLowerCase()))
              .join(' ');
          setState(() => _liveTranscript = display);
        }
      },
      onDone: () {
        debugPrint('[Voice] onDone called, liveTranscript=$_liveTranscript');
        if (mounted && _liveTranscript == null) {
          _showStatus('Kuch nahi suna, dobara try karein');
          setState(() => _isListening = false);
        }
      },
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _onSpeechDone(String transcript) {
    debugPrint('[Voice] Speech done. Transcript: "$transcript"');

    if (transcript.isEmpty) {
      _showStatus('Kuch nahi suna, dobara try karein');
      setState(() {
        _isListening = false;
        _liveTranscript = null;
      });
      return;
    }

    // Extract keywords
    final items = KeywordExtractionService.extract(transcript);
    debugPrint('[Voice] Extracted ${items.length} items: ${items.map((e) => e.toString()).toList()}');

    setState(() {
      _isListening = false;
      _liveTranscript = null;
      _extractedItems = items;
    });

    if (items.isEmpty) {
      // No keywords extracted — search with raw transcript
      debugPrint('[Voice] No keywords extracted, searching raw: "$transcript"');
      _searchController.text = transcript;
      _searchProducts(transcript);
      return;
    }

    // Show extracted keywords in search bar
    final displayText = items.map((e) => e.displayText).join(', ');
    _searchController.text = displayText;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: displayText.length),
    );

    // Search with extracted keywords
    final searchQuery = items.map((e) => e.searchQuery).join(' ');
    debugPrint('[Voice] Search bar: "$displayText" | Search query: "$searchQuery"');
    _searchProducts(searchQuery);

    setState(() => _voiceStatus = 'Search kar rahe hain...');
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _voiceStatus = null);
    });
  }

  void _stopListening() {
    _speechService.stopListening();
    setState(() {
      _isListening = false;
      _voiceStatus = null;
      _liveTranscript = null;
    });
  }

  void _showStatus(String msg) {
    setState(() => _voiceStatus = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _voiceStatus = null);
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mic Permission Chahiye',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        content: const Text(
          'Easy Basket ko aapki awaaz sunne ke liye mic ki permission chahiye. Please settings mein jaake allow karein.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Baad Mein'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Settings Kholein'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _speechService.dispose();
    super.dispose();
  }

  void _searchProducts(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    setState(() {
      _isSearching = query.isNotEmpty;
    });

    _debounce = Timer(const Duration(milliseconds: 300), () {
      final provider = Provider.of<ProductProvider>(context, listen: false);
      
      if (query.length >= 2) {
        provider.fetchSuggestions(query);
      } else {
        provider.clearSuggestions();
      }

      provider.fetchProducts(categoryId: widget.categoryId, search: query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = Provider.of<CartProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Consumer<ProductProvider>(
          builder: (context, provider, _) {
            String displayTitle = 'All Products';
            if (widget.categoryId != null) {
               try {
                final category = provider.categories.firstWhere(
                  (cat) => cat.id == widget.categoryId,
                );
                if (category.id == widget.categoryId) {
                  displayTitle = category.name;
                }
              } catch (e) {
                if (provider.categories.isEmpty && provider.products.isNotEmpty) {
                  final matchingProducts = provider.products.where(
                    (product) => product.category != null && 
                                 product.category!.id == widget.categoryId,
                  ).toList();
                  if (matchingProducts.isNotEmpty) {
                    displayTitle = matchingProducts.first.category!.name;
                  }
                }
              }
            }
            return Text(
              displayTitle,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            );
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            // Jab user scroll karke bottom ke paas pahunche (200px pehle) → next page load karo
            // Kyun: User ko wait nahi karna chahiye — content ready mile scroll karne se pehle
            onNotification: (scrollInfo) {
              if (scrollInfo is ScrollEndNotification &&
                  scrollInfo.metrics.extentAfter < 200) {
                final provider = Provider.of<ProductProvider>(context, listen: false);
                if (provider.hasMore && !provider.isLoadingMore) {
                  provider.loadMoreProducts();
                }
              }
              return false;
            },
            child: CustomScrollView(
            slivers: [
              // 1. Search Bar (Pinned)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search products...',
                            hintStyle: TextStyle(
                              color: AppTheme.grey.withOpacity(0.6),
                              fontSize: 15,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: AppTheme.grey.withOpacity(0.7),
                              size: 22,
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searchController.text.isNotEmpty)
                                  IconButton(
                                    icon: Icon(Icons.clear_rounded,
                                        color: AppTheme.grey, size: 20),
                                    onPressed: () {
                                      _searchController.clear();
                                      _searchProducts('');
                                    },
                                  ),
                                // Mic button
                                GestureDetector(
                                  onTap: _isListening
                                      ? _stopListening
                                      : _startListening,
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _isListening
                                          ? Colors.red.withOpacity(0.1)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      _isListening
                                          ? Icons.mic_rounded
                                          : Icons.mic_none_rounded,
                                      color: _isListening
                                          ? Colors.red
                                          : AppTheme.primaryGreen,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            filled: true,
                            fillColor: AppTheme.lightGrey.withOpacity(0.6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 14),
                          ),
                          onChanged: _searchProducts,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Voice status + live transcript
              if (_voiceStatus != null || _liveTranscript != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      children: [
                        // Status row: red dot + "Boliye..."
                        if (_voiceStatus != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isListening)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              Text(
                                _voiceStatus!,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _isListening
                                      ? Colors.red
                                      : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        // Live transcript while speaking
                        if (_liveTranscript != null && _liveTranscript!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.15)),
                            ),
                            child: Text(
                              '"$_liveTranscript"',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // Spacing
              const SliverToBoxAdapter(
                child: SizedBox(height: 16),
              ),

              // 2. Suggestions List (Inline)
              Consumer<ProductProvider>(
                builder: (context, provider, _) {
                  if (provider.suggestions.isEmpty) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }
                  
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final suggestion = provider.suggestions[index];
                        final imageUrl = suggestion['imageUrl'];
                        
                        return Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: imageUrl != null && imageUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => const Center(
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          errorWidget: (context, url, error) => const Icon(Icons.search, size: 20, color: AppTheme.grey),
                                        ),
                                      )
                                    : const Icon(Icons.search, size: 20, color: AppTheme.grey),
                              ),
                              title: Text(
                                suggestion['name'],
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              onTap: () {
                                _searchController.text = suggestion['name'];
                                _searchProducts(suggestion['name']);
                                provider.clearSuggestions();
                                FocusScope.of(context).unfocus();
                              },
                            ),
                            if (index < provider.suggestions.length - 1)
                              const Divider(height: 1, indent: 76, endIndent: 20),
                          ],
                        );
                      },
                      childCount: provider.suggestions.length,
                    ),
                  );
                },
              ),

              // 3. "Showing results for..." Header
              SliverToBoxAdapter(
                child: ValueListenableBuilder(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Text(
                        'Showing results for "${value.text}"',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 4. Product Grid
              Consumer<ProductProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.products.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                          ),
                        ),
                      ),
                    );
                  }

                  // Show only in-stock items. Out-of-stock / unavailable products
                  // (including those whose every variant is out of stock) are filtered out.
                  final inStockProducts =
                      provider.products.where((p) => p.hasStock).toList();

                  if (inStockProducts.isEmpty && !provider.isLoading) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'No products found',
                              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final responsive = Responsive(context);
                  final crossAxisCount = responsive.getGridColumns();
                  final screenWidth = MediaQuery.of(context).size.width;
                  final aspectRatio = screenWidth < 360 ? 0.50 : screenWidth < 400 ? 0.52 : 0.54;

                  return SliverPadding(
                    padding: EdgeInsets.only(
                      left: responsive.padding.left,
                      right: responsive.padding.right,
                      top: responsive.padding.top,
                      bottom: 16,
                    ),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return ProductCard(product: inStockProducts[index]);
                        },
                        childCount: inStockProducts.length,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: aspectRatio,
                        crossAxisSpacing: responsive.spacing(16),
                        mainAxisSpacing: responsive.spacing(16),
                      ),
                    ),
                  );
                },
              ),

              // Load more indicator — jab user bottom pe pahunche toh next page load ho
              Consumer<ProductProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoadingMore) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                          ),
                        ),
                      ),
                    );
                  }
                  // Leave ~1/4 of the screen height empty below the last card so the
                  // floating cart bar never covers it and the last row has breathing room.
                  return SliverToBoxAdapter(
                    child: SizedBox(height: MediaQuery.of(context).size.height / 4),
                  );
                },
              ),
            ],
          ),
          ), // Close NotificationListener

          // Floating Cart Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: const FloatingCartBar(),
          ),
        ],
      ),
    );
  }
}
