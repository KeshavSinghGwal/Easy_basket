import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../utils/slug_utils.dart';

class ImageNameInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final String? entityName; // Product or category name for auto-suggestion
  final int? entityId; // Product or category ID
  final String type; // 'product' or 'category'

  const ImageNameInputWidget({
    super.key,
    required this.controller,
    this.entityName,
    this.entityId,
    required this.type,
  });

  @override
  State<ImageNameInputWidget> createState() => _ImageNameInputWidgetState();
}

class _ImageNameInputWidgetState extends State<ImageNameInputWidget> {
  String _preview = '';

  @override
  void initState() {
    super.initState();
    // Listen to controller changes - always defer to avoid setState during build
    widget.controller.addListener(_onControllerChanged);
    
    // Auto-fill if empty and entity name exists
    if (widget.controller.text.isEmpty && widget.entityName != null && widget.entityName!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.controller.text = SlugUtils.generateSlug(widget.entityName!);
        }
      });
    }
    
    // Initialize preview after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updatePreview();
      }
    });
  }

  @override
  void didUpdateWidget(ImageNameInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handle controller change
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    
    // Update preview if entity name or ID changed
    if (oldWidget.entityName != widget.entityName || oldWidget.entityId != widget.entityId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updatePreview();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // Always defer update to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updatePreview();
      }
    });
  }

  void _updatePreview() {
    if (!mounted) return;
    
    final name = widget.controller.text.trim();
    String newPreview;
    if (name.isEmpty && widget.entityName != null) {
      final slug = SlugUtils.generateSlug(widget.entityName!);
      newPreview = '${widget.type}-${widget.entityId ?? 0}-$slug.jpg';
    } else if (name.isNotEmpty) {
      final slug = SlugUtils.sanitizeSlug(name);
      newPreview = '${widget.type}-${widget.entityId ?? 0}-$slug.jpg';
    } else {
      newPreview = '${widget.type}-${widget.entityId ?? 0}-image.jpg';
    }
    
    if (_preview != newPreview) {
      setState(() {
        _preview = newPreview;
      });
    }
  }

  // Generate filename preview
  String getFilenamePreview() {
    return _preview;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: 'Image Name',
            hintText: 'e.g., tomato-fresh, onion-red',
            prefixIcon: const Icon(Icons.label_outline),
            border: const OutlineInputBorder(),
            helperText: 'Used in filename (auto-filled from ${widget.type} name)',
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      widget.controller.clear();
                      // Re-fill with auto-generated slug
                      if (widget.entityName != null) {
                        widget.controller.text = SlugUtils.generateSlug(widget.entityName!);
                      }
                    },
                  )
                : null,
          ),
          validator: (value) {
            if (value != null && value.trim().isNotEmpty) {
              final slug = SlugUtils.sanitizeSlug(value);
              if (slug.isEmpty) {
                return 'Invalid characters. Use only letters, numbers, and hyphens.';
              }
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.lightGrey.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.lightGrey),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppTheme.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filename:',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      getFilenamePreview(),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.grey,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

