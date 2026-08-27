import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the shared [ThemeData] used by all three clients — the Mobile App, the Backoffice Web
/// App and the Merchant Web Portal — so the brand cannot drift between them.
///
/// Retuned 2026-08 to the Figma redesign. The type scale, the button shape, the card lift and the
/// input borders below are measured off the frames rather than chosen; where the design says
/// nothing (dividers, the app bar, the Material navigation bar) the previous values stand.
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

      // The redesign's type scale, read off the frames: wizard/page titles 22 Bold, screen-header
      // and section titles 18 Bold, in-card titles 16 SemiBold, body 14, captions 12 muted,
      // nav/eyebrow labels 11. Sizes are stated explicitly because Material's defaults (headline
      // 32, title 22, body 16) are a whole step larger than anything the design draws.
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
          height: 1.25,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
          height: 1.25,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.ink,
          height: 1.3,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.ink,
          height: 1.3,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          color: DeliveryColors.ink,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: DeliveryColors.ink,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: DeliveryColors.muted,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.ink,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: DeliveryColors.muted,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.muted,
          height: 1.2,
        ),
      ),

      // Appendix A: primary actions are solid red with white text. The redesign fixes their size
      // and shape too — 52px tall and fully rounded, the customer app's CTA. (The signup wizards
      // draw the same button at radius 16; those screens shape it locally.)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DeliveryColors.brand,
          foregroundColor: DeliveryColors.white,
          disabledBackgroundColor: DeliveryColors.brandLine,
          disabledForegroundColor: DeliveryColors.white,
          elevation: 0,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.lg,
            vertical: DeliverySpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.pill),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // ...and secondary actions are white with a 1.5px red border and red text. Never both solid
      // at equal visual weight on one screen, so the primary action stays unambiguous.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: DeliveryColors.white,
          foregroundColor: DeliveryColors.brand,
          side: const BorderSide(color: DeliveryColors.brand, width: 1.5),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.lg,
            vertical: DeliverySpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.pill),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DeliveryColors.brand,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // CardThemeData, not CardTheme: ThemeData.cardTheme takes the *Data type from Flutter 3.4x
      // onward. The same rename applies to DialogTheme, TabBarTheme and friends.
      //
      // The redesign separates cards by light, not by line: the border is gone and a very soft
      // lift replaces it. Material's elevation shadow is the closest a bare [Card] can get to the
      // design's `0 4 6 rgba(15,23,42,0.03)`; `YdCard` paints that shadow exactly, and is what the
      // redesigned screens use.
      cardTheme: CardThemeData(
        color: DeliveryColors.white,
        elevation: 1,
        shadowColor: DeliveryColors.ink.withValues(alpha: 0.06),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        ),
      ),

      // Inputs: radius 12, and at rest the lighter [DeliveryColors.borderFaint] hairline the
      // design gives auth and form fields. The border only strengthens on focus.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DeliveryColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: const BorderSide(color: DeliveryColors.borderFaint),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: const BorderSide(color: DeliveryColors.borderFaint),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: const BorderSide(color: DeliveryColors.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: BorderSide(color: DeliveryAccent.critical.color),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: BorderSide(color: DeliveryAccent.critical.color, width: 1.5),
        ),
        // Placeholders are the third text tier in this design, not the second.
        hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
        labelStyle: const TextStyle(fontSize: 14, color: DeliveryColors.muted),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: DeliveryColors.brand,
        foregroundColor: DeliveryColors.white,
        elevation: 0,
        centerTitle: false,
      ),

      // Matches YdChip: white with a faint hairline at rest, solid brand when selected, fully
      // rounded, SemiBold 14 label, 16/10 padding.
      chipTheme: ChipThemeData(
        backgroundColor: DeliveryColors.white,
        selectedColor: DeliveryColors.brand,
        checkmarkColor: DeliveryColors.white,
        side: const BorderSide(color: DeliveryColors.borderFaint),
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.ink,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.white,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.md,
          vertical: 10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        ),
      ),

      // Sheets top out at the design's 24.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: DeliveryColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DeliveryRadius.sheet),
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(color: DeliveryColors.border, thickness: 1),

      // Tightened from Material's 80pt default. That height assumes three or four destinations;
      // the customer app carries five, and at the default sizing the bar eats a chunk of a short
      // phone screen and the longer labels start to crowd. Smaller icons, a smaller label, and a
      // shorter bar together buy back about a fifth of it without making anything hard to hit —
      // the tap target is the full width of the destination, not the size of the glyph.
      //
      // The redesign replaces this bar entirely with the flat `YdBottomNav`; the theme stays
      // tuned for the screens that have not been converted yet.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DeliveryColors.white,
        indicatorColor: DeliveryColors.brandSoft,
        height: 62,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? DeliveryColors.brand
                : DeliveryColors.faint,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            fontSize: 11,
            height: 1.1,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? DeliveryColors.brand
                : DeliveryColors.faint,
          ),
        ),
      ),
    );
  }
}
