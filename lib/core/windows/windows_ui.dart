import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class WindowsUi {
  static const double desktopBreakpoint = 900;
  static const double expandedPaneBreakpoint = 1200;
  static const double wideBreakpoint = 1600;
  static const double compactPaneWidth = 72;
  static const double expandedPaneWidth = 252;
  static const double pageMaxWidth = 1480;
  static const double formMaxWidth = 1080;

  static bool get isNativeWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool isDesktop(BuildContext context) =>
      isNativeWindows && MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  static bool isExpanded(BuildContext context) =>
      isNativeWindows && MediaQuery.sizeOf(context).width >= expandedPaneBreakpoint;

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (!isNativeWindows) return const EdgeInsets.all(16);
    if (width < desktopBreakpoint) return const EdgeInsets.all(16);
    if (width < expandedPaneBreakpoint) return const EdgeInsets.fromLTRB(20, 18, 20, 24);
    return const EdgeInsets.fromLTRB(28, 22, 28, 30);
  }
}
