/// Utility functions for generating and sanitizing slugs
class SlugUtils {
  /// Generate a slug from a string (e.g., product name)
  /// Converts to lowercase, replaces spaces with hyphens, removes special chars
  static String generateSlug(String input) {
    if (input.isEmpty) return '';

    final transformed = input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '') // Remove special characters
        .replaceAll(RegExp(r'\s+'), '-') // Replace spaces with hyphens
        .replaceAll(RegExp(r'-+'), '-') // Replace multiple hyphens with single
        .replaceAll(RegExp(r'^-|-$'), ''); // Remove leading/trailing hyphens
    
    // Safety check: if transformed is empty, return empty string
    if (transformed.isEmpty) return '';
    
    // Limit to 50 chars using the transformed string's length
    final maxLength = transformed.length > 50 ? 50 : transformed.length;
    return transformed.substring(0, maxLength);
  }

  /// Sanitize a slug (for admin-provided names)
  /// More strict - removes all special chars except hyphens
  static String sanitizeSlug(String input) {
    if (input.isEmpty) return '';

    final transformed = input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-') // Replace special chars with hyphens
        .replaceAll(RegExp(r'-+'), '-') // Replace multiple hyphens with single
        .replaceAll(RegExp(r'^-|-$'), ''); // Remove leading/trailing hyphens
    
    // Safety check: if transformed is empty, return empty string
    if (transformed.isEmpty) return '';
    
    // Limit to 50 chars using the transformed string's length
    final maxLength = transformed.length > 50 ? 50 : transformed.length;
    return transformed.substring(0, maxLength);
  }
}

