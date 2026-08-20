import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the shared [ThemeData] used by all three clients — the Mobile App, the Backoffice Web
/// App and the Merchant Web Portal — so the brand cannot drift between them.
abstract final class DeliveryTheme {
  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: DeliveryColors.brand,
      primary: DeliveryColors.brand,
      onPrimary: DeliveryColors.white,
      secondary: DeliveryColors.brandDark,
      onSecondary: DeliveryColors.white,
      surface: DeliveryColors.white,
      onSurface: DeliveryColors.ink,
      outline: DeliveryColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: DeliveryColors.background,
      fontFamily: DeliveryTypography.fontFamily,
      fontFamilyFallback: DeliveryTypography.fontFamilyFallback,

      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: DeliveryColors.ink, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(color: DeliveryColors.ink, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: DeliveryColors.ink, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: DeliveryColors.ink, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: DeliveryColors.ink),
        bodyMedium: TextStyle(color: DeliveryColors.ink),
        bodySmall: TextStyle(color: DeliveryColors.muted),
        labelMedium: TextStyle(color: DeliveryColors.muted),
      ),

      // Appendix A: primary actions are solid red with white text...
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DeliveryColors.brand,
          foregroundColor: DeliveryColors.white,
          disabledBackgroundColor: DeliveryColors.brandLine,
          disabledForegroundColor: DeliveryColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.lg,
            vertical: DeliverySpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // ...and secondary actions are white with a 1.5px red border and red text. Never both solid
      // at equal visual weight on one screen, so the primary action stays unambiguous.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: DeliveryColors.white,
          foregroundColor: DeliveryColors.brand,
          side: const BorderSide(color: DeliveryColors.brand, width: 1.5),
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.lg,
            vertical: DeliverySpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
      ),

      // CardThemeData, not CardTheme: ThemeData.cardTheme takes the *Data type from Flutter 3.4x
      // onward. The same rename applies to DialogTheme, TabBarTheme and friends.
      cardTheme: CardThemeData(
        color: DeliveryColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: DeliveryColors.border),
          borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DeliveryColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.md,
          vertical: DeliverySpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: const BorderSide(color: DeliveryColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: const BorderSide(color: DeliveryColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: const BorderSide(color: DeliveryColors.brand, width: 1.5),
        ),
        hintStyle: const TextStyle(color: DeliveryColors.muted),
        labelStyle: const TextStyle(color: DeliveryColors.muted),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: DeliveryColors.brand,
        foregroundColor: DeliveryColors.white,
        elevation: 0,
        centerTitle: false,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: DeliveryColors.brandSoft,
        side: const BorderSide(color: DeliveryColors.brandLine),
        labelStyle: const TextStyle(color: DeliveryColors.brandDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        ),
      ),

      dividerTheme: const DividerThemeData(color: DeliveryColors.border, thickness: 1),

      // Tightened from Material's 80pt default. That height assumes three or four destinations;
      // the customer app carries five, and at the default sizing the bar eats a chunk of a short
      // phone screen and the longer labels start to crowd. Smaller icons, a smaller label, and a
      // shorter bar together buy back about a fifth of it without making anything hard to hit —
      // the tap target is the full width of the destination, not the size of the glyph.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DeliveryColors.white,
        indicatorColor: DeliveryColors.brandSoft,
        height: 62,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? DeliveryColors.brand
                : DeliveryColors.muted,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            height: 1.1,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 21,
            color: states.contains(WidgetState.selected)
                ? DeliveryColors.brand
                : DeliveryColors.muted,
          ),
        ),
      ),
    );
  }
}
