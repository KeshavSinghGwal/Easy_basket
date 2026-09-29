import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';
import '../models/product_variant_model.dart';
import '../utils/theme.dart';

class VariantManagementDialog extends StatefulWidget {
  final int productId;
  final String productName;

  const VariantManagementDialog({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<VariantManagementDialog> createState() => _VariantManagementDialogState();
}

class _VariantManagementDialogState extends State<VariantManagementDialog> {
  List<ProductVariantModel> _variants = [];
  bool _isLoading = false;
  bool _isLoadingVariants = true;
  final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    // Defer loading to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadVariants();
      }
    });
  }

  Future<void> _loadVariants() async {
    if (!mounted) return;
    
    setState(() => _isLoadingVariants = true);
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.token == null) {
      if (mounted) {
        setState(() => _isLoadingVariants = false);
      }
      return;
    }

    final variants = await adminProvider.fetchProductVariants(
      token: authProvider.token!,
      productId: widget.productId,
    );
    
    if (mounted) {
      setState(() {
        _variants = variants;
        _isLoadingVariants = false;
      });
    }
  }

  Future<void> _showAddEditVariantDialog({ProductVariantModel? variant}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _AddEditVariantDialog(
        productId: widget.productId,
        variant: variant,
      ),
    );
    
    if (result == true) {
      _loadVariants();
    }
  }

  Future<void> _deleteVariant(ProductVariantModel variant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Variant'),
        content: Text('Are you sure you want to delete "${variant.label}"?'),
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
      setState(() => _isLoading = true);
      final adminProvider = Provider.of<AdminProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.token == null) {
        setState(() => _isLoading = false);
        return;
      }

      final success = await adminProvider.deleteVariant(
        token: authProvider.token!,
        variantId: variant.id,
      );

      setState(() => _isLoading = false);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Variant deleted successfully!')),
        );
        _loadVariants();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(adminProvider.error ?? 'Failed to delete variant'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manage Variants',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.productName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _isLoadingVariants
                  ? const Center(child: CircularProgressIndicator())
                  : _variants.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 64, color: AppTheme.grey),
                              const SizedBox(height: 16),
                              Text(
                                'No variants found',
                                style: TextStyle(color: AppTheme.grey),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add variants to allow customers to select different quantities',
                                style: TextStyle(
                                  color: AppTheme.grey,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _variants.length,
                          itemBuilder: (context, index) {
                            final variant = _variants[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        variant.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (variant.isDefault) ...[
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryGreen.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'DEFAULT',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.primaryGreen,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            currencyFormat.format(variant.price),
                                            style: TextStyle(
                                              color: AppTheme.primaryGreen,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            '• ${variant.quantity} ${variant.unit}',
                                            style: TextStyle(
                                              color: AppTheme.grey,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          variant.isAvailable
                                              ? Icons.check_circle
                                              : Icons.cancel,
                                          size: 14,
                                          color: variant.isAvailable
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Stock: ${variant.stock}',
                                            style: TextStyle(
                                              color: AppTheme.grey,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      color: Colors.blue,
                                      onPressed: () => _showAddEditVariantDialog(variant: variant),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 20),
                                      color: Colors.red,
                                      onPressed: () => _deleteVariant(variant),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.lightGrey),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _showAddEditVariantDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Variant'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryGreen,
                        side: BorderSide(color: AppTheme.primaryGreen),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTheme.gradientButton(
                      onPressed: () => Navigator.pop(context, true),
                      height: 46,
                      child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddEditVariantDialog extends StatefulWidget {
  final int productId;
  final ProductVariantModel? variant;

  const _AddEditVariantDialog({
    required this.productId,
    this.variant,
  });

  @override
  State<_AddEditVariantDialog> createState() => _AddEditVariantDialogState();
}

class _AddEditVariantDialogState extends State<_AddEditVariantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _labelController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _minQuantityController = TextEditingController();
  final _maxQuantityController = TextEditingController();
  final _displayOrderController = TextEditingController();
  
  String _selectedUnit = 'kg';
  bool _isAvailable = true;
  bool _isDefault = false;
  bool _isLoading = false;

  final List<String> _units = ['g', 'kg', 'ml', 'liter', 'piece', 'pack', 'dozen'];

  @override
  void initState() {
    super.initState();
    if (widget.variant != null) {
      _quantityController.text = widget.variant!.quantity.toString();
      _labelController.text = widget.variant!.label;
      _priceController.text = widget.variant!.price.toString();
      _stockController.text = widget.variant!.stock.toString();
      _minQuantityController.text = widget.variant!.minQuantity?.toString() ?? '';
      _maxQuantityController.text = widget.variant!.maxQuantity?.toString() ?? '';
      _displayOrderController.text = widget.variant!.displayOrder.toString();
      _selectedUnit = widget.variant!.unit;
      _isAvailable = widget.variant!.isAvailable;
      _isDefault = widget.variant!.isDefault;
    } else {
      _displayOrderController.text = '0';
      _stockController.text = '0';
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _labelController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _minQuantityController.dispose();
    _maxQuantityController.dispose();
    _displayOrderController.dispose();
    super.dispose();
  }

  Future<void> _saveVariant() async {
    if (!_formKey.currentState!.validate()) return;

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

    final quantity = double.tryParse(_quantityController.text.trim());
    final price = double.tryParse(_priceController.text.trim());
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;
    final minQuantity = _minQuantityController.text.trim().isEmpty
        ? null
        : double.tryParse(_minQuantityController.text.trim());
    final maxQuantity = _maxQuantityController.text.trim().isEmpty
        ? null
        : double.tryParse(_maxQuantityController.text.trim());
    final displayOrder = int.tryParse(_displayOrderController.text.trim()) ?? 0;

    if (quantity == null || quantity <= 0) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid quantity')),
      );
      return;
    }

    if (price == null || price <= 0) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price')),
      );
      return;
    }

    final success = widget.variant == null
        ? await adminProvider.createVariant(
            token: authProvider.token!,
            productId: widget.productId,
            quantity: quantity,
            unit: _selectedUnit,
            label: _labelController.text.trim(),
            price: price,
            stock: stock,
            isAvailable: _isAvailable,
            minQuantity: minQuantity,
            maxQuantity: maxQuantity,
            displayOrder: displayOrder,
            isDefault: _isDefault,
          )
        : await adminProvider.updateVariant(
            token: authProvider.token!,
            variantId: widget.variant!.id,
            quantity: quantity,
            unit: _selectedUnit,
            label: _labelController.text.trim(),
            price: price,
            stock: stock,
            isAvailable: _isAvailable,
            minQuantity: minQuantity,
            maxQuantity: maxQuantity,
            displayOrder: displayOrder,
            isDefault: _isDefault,
          );

    setState(() => _isLoading = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.variant == null
                ? 'Variant created successfully!'
                : 'Variant updated successfully!',
          ),
        ),
      );
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(adminProvider.error ?? 'Failed to save variant'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.variant == null
                            ? 'Add Variant'
                            : 'Edit Variant',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _labelController,
                        decoration: InputDecoration(
                          labelText: 'Label *',
                          hintText: 'e.g., 250 g, 1 kg, 2 kg, 5 L',
                          prefixIcon: const Icon(Icons.label, size: 20),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 24),
                        ),
                        style: const TextStyle(fontSize: 14),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Label is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _quantityController,
                              decoration: InputDecoration(
                                labelText: 'Quantity *',
                                hintText: '0.25, 1, 2, 5',
                                prefixIcon: const Icon(Icons.numbers, size: 18),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 24),
                              ),
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 14),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Required';
                                }
                                final qty = double.tryParse(value);
                                if (qty == null || qty <= 0) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'Unit *',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                filled: true,
                                fillColor: Colors.transparent,
                              ),
                              isDense: true,
                              iconSize: 18,
                              items: _units.map((unit) {
                                return DropdownMenuItem<String>(
                                  value: unit,
                                  child: Text(
                                    unit.toUpperCase(),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) => setState(() => _selectedUnit = value!),
                              style: const TextStyle(fontSize: 13),
                              selectedItemBuilder: (context) {
                                return _units.map((unit) {
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      unit.toUpperCase(),
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _priceController,
                        decoration: InputDecoration(
                          labelText: 'Price (₹) *',
                          prefixIcon: const Icon(Icons.currency_rupee, size: 20),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 24),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 14),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Price is required';
                          }
                          final price = double.tryParse(value);
                          if (price == null || price <= 0) {
                            return 'Invalid price';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _stockController,
                              decoration: InputDecoration(
                                labelText: 'Stock',
                                prefixIcon: const Icon(Icons.inventory, size: 20),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 24),
                              ),
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _displayOrderController,
                              decoration: InputDecoration(
                                labelText: 'Display Order',
                                prefixIcon: const Icon(Icons.sort, size: 20),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 24),
                              ),
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _minQuantityController,
                              decoration: InputDecoration(
                                labelText: 'Min Quantity',
                                hintText: '0.25',
                                prefixIcon: const Icon(Icons.arrow_downward, size: 20),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 24),
                              ),
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _maxQuantityController,
                              decoration: InputDecoration(
                                labelText: 'Max Quantity',
                                hintText: '5.0',
                                prefixIcon: const Icon(Icons.arrow_upward, size: 20),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 24),
                              ),
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Available'),
                        value: _isAvailable,
                        onChanged: (value) => setState(() => _isAvailable = value),
                      ),
                      SwitchListTile(
                        title: const Text('Set as Default'),
                        subtitle: const Text('This variant will be selected by default'),
                        value: _isDefault,
                        onChanged: (value) => setState(() => _isDefault = value),
                      ),
                    ],
                  ),
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.lightGrey),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTheme.gradientButton(
                        onPressed: _isLoading ? null : _saveVariant,
                        height: 46,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                widget.variant == null ? 'Create' : 'Update',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
