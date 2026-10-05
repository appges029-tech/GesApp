import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get windowsLight => _build(Brightness.light, windows: true);
  static ThemeData get windowsDark => _build(Brightness.dark, windows: true);

  static ThemeData _build(Brightness brightness, {bool windows = false}) {
    final dark = brightness == Brightness.dark;
    final radius = windows ? 8.0 : 16.0;
    final controlRadius = windows ? 6.0 : 14.0;
    final controlHeight = windows ? 40.0 : 50.0;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      surface: dark ? AppColors.darkSurface : AppColors.surface,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      error: AppColors.danger,
      surface: dark ? AppColors.darkSurface : AppColors.surface,
      onSurface: dark ? AppColors.darkText : AppColors.textPrimary,
      outline: dark ? AppColors.darkDivider : AppColors.divider,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? AppColors.darkBackground : AppColors.background,
      fontFamily: null,
      visualDensity: windows ? VisualDensity.compact : VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );

    final text = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(fontWeight: windows ? FontWeight.w600 : FontWeight.w800, letterSpacing: windows ? -0.25 : -0.8),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: windows ? FontWeight.w600 : FontWeight.w800, letterSpacing: windows ? -0.2 : -0.6),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: windows ? FontWeight.w600 : FontWeight.w800, letterSpacing: windows ? -0.1 : -0.35),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: windows ? FontWeight.w600 : FontWeight.w800, letterSpacing: windows ? 0 : -0.2),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: windows ? FontWeight.w600 : FontWeight.w700),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: windows ? 1.3 : 1.35),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: windows ? 1.3 : 1.35),
    );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: dark ? AppColors.darkBackground : AppColors.background,
        foregroundColor: dark ? AppColors.darkText : AppColors.textPrimary,
        titleTextStyle: text.titleLarge?.copyWith(color: dark ? AppColors.darkText : AppColors.textPrimary),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: windows ? 0 : (dark ? 0 : 1.5),
        shadowColor: AppColors.navy.withValues(alpha: .10),
        margin: EdgeInsets.zero,
        color: dark ? AppColors.darkSurface : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: dark ? AppColors.darkDivider : AppColors.divider),
        ),
      ),
      dividerTheme: DividerThemeData(color: dark ? AppColors.darkDivider : AppColors.divider, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.darkSurfaceMuted : AppColors.surface,
        isDense: windows,
        contentPadding: EdgeInsets.symmetric(horizontal: windows ? 12 : 16, vertical: windows ? 11 : 15),
        labelStyle: TextStyle(color: dark ? AppColors.darkTextSecondary : AppColors.textSecondary),
        hintStyle: TextStyle(color: dark ? AppColors.darkTextSecondary : AppColors.textSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(controlRadius), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: dark ? AppColors.darkDivider : AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(44, controlHeight),
          padding: EdgeInsets.symmetric(horizontal: windows ? 14 : 18, vertical: windows ? 10 : 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius)),
          textStyle: TextStyle(fontWeight: windows ? FontWeight.w600 : FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(44, controlHeight),
          padding: EdgeInsets.symmetric(horizontal: windows ? 14 : 18, vertical: windows ? 10 : 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius)),
          side: BorderSide(color: dark ? AppColors.darkDivider : AppColors.divider),
          textStyle: TextStyle(fontWeight: windows ? FontWeight.w600 : FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(windows ? 6 : 12)),
          textStyle: TextStyle(fontWeight: windows ? FontWeight.w600 : FontWeight.w700),
        ),
      ),
      iconButtonTheme: windows
          ? IconButtonThemeData(
              style: IconButton.styleFrom(
                minimumSize: const Size(36, 36),
                padding: const EdgeInsets.all(8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            )
          : null,
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(windows ? 8 : 18)),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: dark ? AppColors.darkDivider : AppColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(windows ? 6 : 12)),
        labelStyle: TextStyle(fontWeight: windows ? FontWeight.w600 : FontWeight.w700),
      ),
      listTileTheme: ListTileThemeData(
        dense: windows,
        contentPadding: EdgeInsets.symmetric(horizontal: windows ? 12 : 16, vertical: windows ? 1 : 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(windows ? 6 : 16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: dark ? AppColors.darkSurface : AppColors.surface,
        indicatorColor: dark ? const Color(0xFF253361) : AppColors.primarySoft,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 11.5,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          color: states.contains(WidgetState.selected) ? AppColors.primary : (dark ? AppColors.darkTextSecondary : AppColors.textSecondary),
        )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: dark ? AppColors.darkSurface : AppColors.surface,
        indicatorColor: dark ? const Color(0xFF253361) : AppColors.primarySoft,
        selectedIconTheme: const IconThemeData(color: AppColors.primary),
        selectedLabelTextStyle: TextStyle(color: AppColors.primary, fontWeight: windows ? FontWeight.w600 : FontWeight.w800),
        unselectedLabelTextStyle: TextStyle(color: dark ? AppColors.darkTextSecondary : AppColors.textSecondary, fontWeight: FontWeight.w600),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? AppColors.darkSurface : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(windows ? 10 : 28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: dark ? AppColors.darkSurface : AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(windows ? 10 : 24)),
      ),
      menuTheme: windows
          ? MenuThemeData(
              style: MenuStyle(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
            )
          : null,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(windows ? 8 : 14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    );
  }
}
