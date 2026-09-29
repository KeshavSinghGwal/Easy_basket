import 'package:flutter/material.dart';

/// Responsive utility class for handling different screen sizes
class Responsive {
  final BuildContext context;
  
  Responsive(this.context);
  
  // Screen size breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;
  
  // Get screen width
  double get width => MediaQuery.of(context).size.width;
  
  // Get screen height
  double get height => MediaQuery.of(context).size.height;
  
  // Check if mobile
  bool get isMobile => width < mobileBreakpoint;
  
  // Check if tablet
  bool get isTablet => width >= mobileBreakpoint && width < tabletBreakpoint;
  
  // Check if desktop
  bool get isDesktop => width >= tabletBreakpoint;
  
  // Get responsive padding
  EdgeInsets get padding => EdgeInsets.symmetric(
    horizontal: isMobile ? 16.0 : isTablet ? 24.0 : 32.0,
    vertical: isMobile ? 8.0 : 12.0,
  );
  
  // Get responsive font size
  double fontSize(double baseSize) {
    if (isMobile) return baseSize;
    if (isTablet) return baseSize * 1.1;
    return baseSize * 1.2;
  }
  
  // Get responsive icon size
  double iconSize(double baseSize) {
    if (isMobile) return baseSize;
    if (isTablet) return baseSize * 1.2;
    return baseSize * 1.4;
  }
  
  // Get responsive grid columns
  int getGridColumns() {
    if (isMobile) return 2;
    if (isTablet) return 3;
    return 4;
  }
  
  // Get responsive category grid columns
  int getCategoryGridColumns() {
    if (isMobile) return 3;
    if (isTablet) return 5;
    return 6;
  }
  
  // Get responsive spacing
  double spacing(double baseSpacing) {
    if (isMobile) return baseSpacing;
    if (isTablet) return baseSpacing * 1.2;
    return baseSpacing * 1.5;
  }
}

/// Extension for easy access to Responsive
extension ResponsiveExtension on BuildContext {
  Responsive get responsive => Responsive(this);
  
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  
  bool get isMobile => screenWidth < Responsive.mobileBreakpoint;
  bool get isTablet => screenWidth >= Responsive.mobileBreakpoint && screenWidth < Responsive.tabletBreakpoint;
  bool get isDesktop => screenWidth >= Responsive.tabletBreakpoint;
}
