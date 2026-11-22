import 'package:flutter/material.dart';
import '../services/local_db_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BuildContext Theme Extensions
// ─────────────────────────────────────────────────────────────────────────────

// extension ThemeContextExtension on BuildContext {
//   bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
//   Color get textPrimary =>
//       isDarkMode ? AppColors.textPrimary : AppColors.lightTextPrimary;
//   Color get textSecondary =>
//       isDarkMode ? AppColors.textSecondary : AppColors.lightTextSecondary;
//   Color get textMuted =>
//       isDarkMode ? AppColors.textMuted : AppColors.lightTextMuted;
//   Color get cardBg => isDarkMode ? AppColors.surface : AppColors.lightSurface;
//   Color get containerBg => isDarkMode ? AppColors.bgDark2 : AppColors.lightBg2;
//   Color get border =>
//       isDarkMode ? AppColors.cardBorder : AppColors.lightCardBorder;
//   Color get primaryAccent =>
//       isDarkMode ? AppColors.accent : AppColors.lightAccent;
//   // Gene - Nov, 21, 2026: Add theme-aware FTP accent color getter
//   Color get ftpAccent =>
//       isDarkMode ? AppColors.ftpDark : AppColors.ftpLight;
// }
// Gene - Nov, 22, 2026: Expanded ThemeContextExtension with theme-aware semantic, operation, and neumorphic surface getters.
extension ThemeContextExtension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  Color get textPrimary =>
      isDarkMode ? AppColors.textPrimary : AppColors.lightTextPrimary;
  Color get textSecondary =>
      isDarkMode ? AppColors.textSecondary : AppColors.lightTextSecondary;
  Color get textMuted =>
      isDarkMode ? AppColors.textMuted : AppColors.lightTextMuted;
  Color get cardBg => isDarkMode ? AppColors.surface : AppColors.lightSurface;
  Color get containerBg => isDarkMode ? AppColors.bgDark2 : AppColors.lightBg2;
  Color get border =>
      isDarkMode ? AppColors.cardBorder : AppColors.lightCardBorder;
  Color get primaryAccent =>
      isDarkMode ? AppColors.accent : AppColors.lightAccent;
  Color get ftpAccent => isDarkMode ? AppColors.ftpDark : AppColors.ftpLight;
  Color get copyAccent => isDarkMode ? AppColors.copyDark : AppColors.copyLight;
  Color get successColor =>
      isDarkMode ? AppColors.successDark : AppColors.successLight;
  Color get warningColor =>
      isDarkMode ? AppColors.warningDark : AppColors.warningLight;
  Color get errorColor =>
      isDarkMode ? AppColors.errorDark : AppColors.errorLight;
  Color get infoColor => isDarkMode ? AppColors.infoDark : AppColors.infoLight;
  Color get recessBg => isDarkMode ? AppColors.bgDark3 : AppColors.lightBg3;
  Color get tableHeaderBg =>
      isDarkMode ? AppColors.bgDark2 : AppColors.lightBg2;
  Color get surfaceHover =>
      isDarkMode ? AppColors.surfaceLight : AppColors.lightSurfaceHover;
}

// ─────────────────────────────────────────────────────────────────────────────
// Color Palette (Modern Soft Slate & Electric/Royal Blue Neumorphism, matched to Batterie)
// ─────────────────────────────────────────────────────────────────────────────

// class AppColors {
//   AppColors._();
//
//   // Coffee Dark Backgrounds (Lighter Mocha Roast)
//   static const Color bgDark1 = Color(0xFF2E2721); // Warm mocha
//   static const Color bgDark2 = Color(0xFF383028); // Milk chocolate
//   static const Color bgDark3 = Color(0xFF423931); // Warm coffee blend
//   static const Color bgDark4 = Color(0xFF4C433A);
//
//   // Surface & card (Dark)
//   static const Color surface = Color(0xFF3A322B);
//   static const Color surfaceLight = Color(0xFF453C34);
//   static const Color cardBorder = Color(0xFF5C5044);
//
//   // Coffee Light (Warm Cream & Paper, synced to genexis.dev)
//   static const Color lightBg1 = Color(
//     0xFFF2EDE3,
//   ); // Warm cream cotton paper (--paper)
//   static const Color lightBg2 = Color(
//     0xFFE7E0D0,
//   ); // Soft warm latte (--paper-deep)
//   static const Color lightBg3 = Color(
//     0xFFDED6C4,
//   ); // Recessed warm paper (--paper-recess)
//   static const Color lightSurface = Color(
//     0xFFFAF7F0,
//   ); // Paper raised (--paper-raised)
//   static const Color lightCardBorder = Color(
//     0xFFCECAC2,
//   ); // Hairline border (--hairline on paper)
//
//   // Accent (Terracotta Roast / Coffee Crema)
//   static const Color accent = Color(
//     0xFFD47754,
//   ); // Cinnamon / Terracotta Crema (Dark)
//   static const Color accentLight = Color(0xFFE28D6E);
//   static const Color accentMuted = Color(0xFFA85538);
//   static const Color lightAccent = Color(
//     0xFFB4402C,
//   ); // Warm terracotta lead (--lead from genexis.dev)
//   static const Color lightAccentDeep = Color(
//     0xFF8E3122,
//   ); // Pressed terracotta (--lead-deep from genexis.dev)
//
//   // Semantic
//   static const Color success = Color(0xFF529A72); // Muted sage roast green
//   static const Color error = Color(0xFFC74838); // Terracotta error
//   static const Color warning = Color(0xFFD98A2B); // Warm honey amber
//   static const Color info = Color(0xFF6B8BA6); // Muted slate blue
//   // Gene - Nov, 21, 2026: Add muted teal accents for the FTP Upload module
//   static const Color ftpDark = Color(0xFF5FA8A0);
//   static const Color ftpLight = Color(0xFF2A7B74);
//
//   // Text (Dark)
//   static const Color textPrimary = Color(0xFFFAF7F0); // Warm cream
//   static const Color textSecondary = Color(0xFFD5CCB8); // Warm oat
//   static const Color textMuted = Color(0xFF9C9184); // Coffee muted
//
//   // Text (Light - from genexis.dev)
//   static const Color lightTextPrimary = Color(0xFF16161A); // Deep ink
//   static const Color lightTextSecondary = Color(
//     0xFF5A564E,
//   ); // Soft ink / roasted bean
//   static const Color lightTextMuted = Color(
//     0xFF66625A,
//   ); // Graphite (--graphite)
//
//   // Log console colors
//   static const Color logSuccess = Color(0xFF68C28A);
//   static const Color logError = Color(0xFFE06253);
//   static const Color logInfo = Color(0xFFE0A076);
//   static const Color logWarning = Color(0xFFEBB44E);
//   static const Color logDefault = Color(0xFFEBE5D8);
// }
// Gene - Nov, 22, 2026: Replaced Coffee & Cream palette with Batterie-matched Soft Slate / Dark Slate Neumorphism and modern semantic accents.
class AppColors {
  AppColors._();

  // Dark Neumorphism (Dark Slate & Electric Blue — matched to Batterie)
  static const Color bgDark1 = Color(0xFF1E222A);
  static const Color bgDark2 = Color(0xFF171A20);
  static const Color bgDark3 = Color(0xFF15171D);
  static const Color bgDark4 = Color(0xFF222731);

  // Surface & card (Dark)
  static const Color surface = Color(0xFF1E222A);
  static const Color surfaceLight = Color(0xFF252A34);
  static const Color cardBorder = Color(0x2E94A3B8);
  static const Color darkHighlight = Color(0xFF2C323E);
  static const Color darkShadow = Color(0xFF121419);

  // Light Neumorphism (Soft Slate & Royal Blue — matched to Batterie)
  static const Color lightBg1 = Color(0xFFE0E5EC);
  static const Color lightBg2 = Color(0xFFD6DDE6);
  static const Color lightBg3 = Color(0xFFD3DAE4);
  static const Color lightSurface = Color(0xFFE0E5EC);
  static const Color lightSurfaceHover = Color(0xFFE6EBF2);
  static const Color lightCardBorder = Color(0x3394A3B8);
  static const Color lightHighlight = Color(0xFFFFFFFF);
  static const Color lightShadow = Color(0xFFA3B1C6);

  // Primary Accent (Transfer — Royal / Electric Blue)
  static const Color accent = Color(0xFF3B82F6);
  static const Color accentLight = Color(0xFF60A5FA);
  static const Color accentMuted = Color(0xFF1D4ED8);
  static const Color lightAccent = Color(0xFF2563EB);
  static const Color lightAccentDeep = Color(0xFF1D4ED8);

  // Semantic & Operation Colors (WCAG AA tuned for #E0E5EC & #1E222A)
  static const Color success = Color(0xFF059669);
  static const Color successLight = Color(0xFF059669);
  static const Color successDark = Color(0xFF34D399);

  static const Color warning = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFD97706);
  static const Color warningDark = Color(0xFFFBBF24);

  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFF87171);

  static const Color info = Color(0xFF0284C7);
  static const Color infoLight = Color(0xFF0284C7);
  static const Color infoDark = Color(0xFF38BDF8);

  static const Color copyLight = Color(0xFF7C3AED);
  static const Color copyDark = Color(0xFFA78BFA);

  static const Color ftpLight = Color(0xFF0F766E);
  static const Color ftpDark = Color(0xFF2DD4BF);

  // Text (Dark)
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFFCBD5E1);
  static const Color textMuted = Color(0xFF94A3B8);

  // Text (Light)
  static const Color lightTextPrimary = Color(0xFF1E293B);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF64748B);

  // Log console colors (Modern Dark Slate Terminal)
  static const Color logSuccess = Color(0xFF34D399);
  static const Color logError = Color(0xFFF87171);
  static const Color logInfo = Color(0xFF60A5FA);
  static const Color logWarning = Color(0xFFFBBF24);
  static const Color logDefault = Color(0xFFE2E8F0);
}

// Gene - Nov, 22, 2026: Added NeumorphicTheme helper ported from Batterie for consistent dual-shadow surfaces, rim borders, and sunken grooves.
class NeumorphicTheme {
  NeumorphicTheme._();

  static List<BoxShadow> raisedShadows(
    BuildContext context, {
    double distance = 5.0,
    double blur = 10.0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return [
        BoxShadow(
          color: AppColors.darkHighlight.withValues(alpha: 0.65),
          offset: Offset(-distance, -distance),
          blurRadius: blur,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.8),
          offset: Offset(distance, distance),
          blurRadius: blur,
        ),
      ];
    } else {
      return [
        BoxShadow(
          color: AppColors.lightHighlight.withValues(alpha: 0.95),
          offset: Offset(-distance, -distance),
          blurRadius: blur,
        ),
        BoxShadow(
          color: AppColors.lightShadow.withValues(alpha: 0.55),
          offset: Offset(distance, distance),
          blurRadius: blur,
        ),
      ];
    }
  }

  static List<BoxShadow> softShadows(
    BuildContext context, {
    double distance = 2.5,
    double blur = 5.0,
  }) {
    return raisedShadows(context, distance: distance, blur: blur);
  }

  static Border rimBorder(
    BuildContext context, {
    Color? accentColor,
    double width = 1.0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseRim = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.68);
    return Border.all(
      color: accentColor != null
          ? accentColor.withValues(alpha: isDark ? 0.35 : 0.3)
          : baseRim,
      width: width,
    );
  }

  static BoxDecoration recessedDecoration(
    BuildContext context, {
    double radius = 10.0,
    Color? color,
    Color? borderColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: color ?? (isDark ? AppColors.bgDark2 : AppColors.lightBg2),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color:
            borderColor ??
            (isDark
                ? Colors.black.withValues(alpha: 0.4)
                : AppColors.lightShadow.withValues(alpha: 0.4)),
        width: 0.9,
      ),
    );
  }

  static Widget progressTrack(
    BuildContext context, {
    required double value,
    required Color color,
    double height = 8.0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark3 : AppColors.lightBg3,
        borderRadius: BorderRadius.circular(height / 2 + 1),
        border: Border.all(
          color: isDark
              ? Colors.black.withValues(alpha: 0.4)
              : AppColors.lightShadow.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme Data
// ─────────────────────────────────────────────────────────────────────────────

// class AppTheme {
//   AppTheme._();
//
//   static ThemeData get darkTheme {
//     return ThemeData(
//       brightness: Brightness.dark,
//       useMaterial3: true,
//       fontFamily: 'Segoe UI',
//       scaffoldBackgroundColor: AppColors.bgDark1,
//       colorScheme: const ColorScheme.dark(
//         primary: AppColors.accent,
//         secondary: AppColors.accentLight,
//         surface: AppColors.surface,
//         error: AppColors.error,
//         onPrimary: AppColors.bgDark1,
//         onSecondary: AppColors.bgDark1,
//         onSurface: AppColors.textPrimary,
//         onError: Colors.white,
//       ),
//       appBarTheme: const AppBarTheme(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         centerTitle: false,
//         titleTextStyle: TextStyle(
//           fontSize: 20,
//           fontWeight: FontWeight.w600,
//           color: AppColors.textPrimary,
//           letterSpacing: 0.5,
//         ),
//         iconTheme: IconThemeData(color: AppColors.accent),
//       ),
//       cardTheme: CardThemeData(
//         color: AppColors.surface.withValues(alpha: 0.9),
//         elevation: 0,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(16),
//           side: const BorderSide(color: AppColors.cardBorder, width: 1),
//         ),
//         margin: EdgeInsets.zero,
//       ),
//       elevatedButtonTheme: ElevatedButtonThemeData(
//         style: ElevatedButton.styleFrom(
//           backgroundColor: AppColors.accent,
//           foregroundColor: AppColors.bgDark1,
//           elevation: 0,
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(10),
//           ),
//           textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
//         ),
//       ),
//       outlinedButtonTheme: OutlinedButtonThemeData(
//         style: OutlinedButton.styleFrom(
//           foregroundColor: AppColors.accent,
//           side: const BorderSide(color: AppColors.accent, width: 1),
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(10),
//           ),
//           textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
//         ),
//       ),
//       inputDecorationTheme: InputDecorationTheme(
//         filled: true,
//         fillColor: AppColors.bgDark2,
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: const BorderSide(color: AppColors.cardBorder),
//         ),
//         enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: const BorderSide(color: AppColors.cardBorder),
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
//         ),
//         labelStyle: const TextStyle(
//           color: AppColors.textSecondary,
//           fontSize: 13,
//         ),
//         contentPadding: const EdgeInsets.symmetric(
//           horizontal: 12,
//           vertical: 10,
//         ),
//         isDense: true,
//       ),
//       checkboxTheme: CheckboxThemeData(
//         fillColor: WidgetStateProperty.resolveWith((states) {
//           if (states.contains(WidgetState.selected)) return AppColors.accent;
//           return Colors.transparent;
//         }),
//         checkColor: WidgetStateProperty.all(AppColors.bgDark1),
//         side: const BorderSide(color: AppColors.textSecondary, width: 1.5),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
//       ),
//       chipTheme: ChipThemeData(
//         backgroundColor: AppColors.bgDark2,
//         selectedColor: AppColors.accent.withValues(alpha: 0.25),
//         checkmarkColor: AppColors.accent,
//         labelStyle: const TextStyle(
//           color: AppColors.textSecondary,
//           fontSize: 12,
//         ),
//         side: const BorderSide(color: AppColors.cardBorder),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//         padding: const EdgeInsets.symmetric(horizontal: 4),
//       ),
//       dropdownMenuTheme: const DropdownMenuThemeData(
//         textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
//       ),
//       dialogTheme: DialogThemeData(
//         backgroundColor: AppColors.bgDark2,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(16),
//           side: const BorderSide(color: AppColors.cardBorder),
//         ),
//         titleTextStyle: const TextStyle(
//           color: AppColors.textPrimary,
//           fontSize: 18,
//           fontWeight: FontWeight.w600,
//         ),
//       ),
//       dividerTheme: const DividerThemeData(
//         color: AppColors.cardBorder,
//         thickness: 1,
//       ),
//       popupMenuTheme: PopupMenuThemeData(
//         color: AppColors.bgDark2,
//         textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(10),
//           side: const BorderSide(color: AppColors.cardBorder),
//         ),
//       ),
//       toggleButtonsTheme: ToggleButtonsThemeData(
//         selectedColor: AppColors.accent,
//         color: AppColors.textSecondary,
//         fillColor: AppColors.accent.withValues(alpha: 0.18),
//         selectedBorderColor: AppColors.accent,
//         borderColor: AppColors.cardBorder,
//         borderRadius: BorderRadius.circular(8),
//         textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
//       ),
//       textTheme: const TextTheme(
//         bodyLarge: TextStyle(color: AppColors.textPrimary),
//         bodyMedium: TextStyle(color: AppColors.textPrimary),
//         bodySmall: TextStyle(color: AppColors.textSecondary),
//         labelLarge: TextStyle(color: AppColors.textPrimary),
//         labelMedium: TextStyle(color: AppColors.textSecondary),
//         labelSmall: TextStyle(color: AppColors.textMuted),
//       ),
//     );
//   }
//
//   static ThemeData get lightTheme {
//     return ThemeData(
//       brightness: Brightness.light,
//       useMaterial3: true,
//       fontFamily: 'Segoe UI',
//       scaffoldBackgroundColor: AppColors.lightBg1,
//       colorScheme: const ColorScheme.light(
//         primary: AppColors.lightAccent,
//         secondary: AppColors.lightAccentDeep,
//         surface: AppColors.lightSurface,
//         error: AppColors.error,
//         onPrimary: Colors.white,
//         onSecondary: Colors.white,
//         onSurface: AppColors.lightTextPrimary,
//         onError: Colors.white,
//       ),
//       appBarTheme: const AppBarTheme(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         centerTitle: false,
//         titleTextStyle: TextStyle(
//           fontSize: 20,
//           fontWeight: FontWeight.w600,
//           color: AppColors.lightTextPrimary,
//           letterSpacing: 0.5,
//         ),
//         iconTheme: IconThemeData(color: AppColors.lightAccent),
//       ),
//       cardTheme: CardThemeData(
//         color: AppColors.lightSurface,
//         elevation: 0,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(16),
//           side: const BorderSide(color: AppColors.lightCardBorder, width: 1),
//         ),
//         margin: EdgeInsets.zero,
//       ),
//       elevatedButtonTheme: ElevatedButtonThemeData(
//         style: ElevatedButton.styleFrom(
//           backgroundColor: AppColors.lightAccent,
//           foregroundColor: AppColors.lightSurface,
//           elevation: 0,
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(10),
//           ),
//           textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
//         ),
//       ),
//       outlinedButtonTheme: OutlinedButtonThemeData(
//         style: OutlinedButton.styleFrom(
//           foregroundColor: AppColors.lightAccent,
//           side: const BorderSide(color: AppColors.lightAccent, width: 1),
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(10),
//           ),
//           textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
//         ),
//       ),
//       inputDecorationTheme: InputDecorationTheme(
//         filled: true,
//         fillColor: AppColors.lightSurface,
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: const BorderSide(color: AppColors.lightCardBorder),
//         ),
//         enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: const BorderSide(color: AppColors.lightCardBorder),
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: const BorderSide(
//             color: AppColors.lightAccent,
//             width: 1.5,
//           ),
//         ),
//         labelStyle: const TextStyle(
//           color: AppColors.lightTextSecondary,
//           fontSize: 13,
//         ),
//         contentPadding: const EdgeInsets.symmetric(
//           horizontal: 12,
//           vertical: 10,
//         ),
//         isDense: true,
//       ),
//       checkboxTheme: CheckboxThemeData(
//         fillColor: WidgetStateProperty.resolveWith((states) {
//           if (states.contains(WidgetState.selected)) {
//             return AppColors.lightAccent;
//           }
//           return Colors.transparent;
//         }),
//         checkColor: WidgetStateProperty.all(Colors.white),
//         side: const BorderSide(color: AppColors.lightTextSecondary, width: 1.5),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
//       ),
//       chipTheme: ChipThemeData(
//         backgroundColor: AppColors.lightSurface,
//         selectedColor: AppColors.lightAccent.withValues(alpha: 0.15),
//         checkmarkColor: AppColors.lightAccent,
//         labelStyle: const TextStyle(
//           color: AppColors.lightTextSecondary,
//           fontSize: 12,
//         ),
//         side: const BorderSide(color: AppColors.lightCardBorder),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//         padding: const EdgeInsets.symmetric(horizontal: 4),
//       ),
//       dropdownMenuTheme: const DropdownMenuThemeData(
//         textStyle: TextStyle(color: AppColors.lightTextPrimary, fontSize: 14),
//       ),
//       dialogTheme: DialogThemeData(
//         backgroundColor: AppColors.lightSurface,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(16),
//           side: const BorderSide(color: AppColors.lightCardBorder),
//         ),
//         titleTextStyle: const TextStyle(
//           color: AppColors.lightTextPrimary,
//           fontSize: 18,
//           fontWeight: FontWeight.w600,
//         ),
//       ),
//       dividerTheme: const DividerThemeData(
//         color: AppColors.lightCardBorder,
//         thickness: 1,
//       ),
//       popupMenuTheme: PopupMenuThemeData(
//         color: AppColors.lightSurface,
//         textStyle: const TextStyle(
//           color: AppColors.lightTextPrimary,
//           fontSize: 13,
//         ),
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(10),
//           side: const BorderSide(color: AppColors.lightCardBorder),
//         ),
//       ),
//       toggleButtonsTheme: ToggleButtonsThemeData(
//         selectedColor: AppColors.lightAccent,
//         color: AppColors.lightTextSecondary,
//         fillColor: AppColors.lightAccent.withValues(alpha: 0.12),
//         selectedBorderColor: AppColors.lightAccent,
//         borderColor: AppColors.lightCardBorder,
//         borderRadius: BorderRadius.circular(8),
//         textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
//       ),
//       textTheme: const TextTheme(
//         bodyLarge: TextStyle(color: AppColors.lightTextPrimary),
//         bodyMedium: TextStyle(color: AppColors.lightTextPrimary),
//         bodySmall: TextStyle(color: AppColors.lightTextSecondary),
//         labelLarge: TextStyle(color: AppColors.lightTextPrimary),
//         labelMedium: TextStyle(color: AppColors.lightTextSecondary),
//         labelSmall: TextStyle(color: AppColors.lightTextMuted),
//       ),
//     );
//   }
// }
// Gene - Nov, 22, 2026: Refactored AppTheme to build Batterie-matched soft slate Neumorphism themes for light and dark modes.
class AppTheme {
  AppTheme._();

  static const double cardRadius = 16.0;
  static const double controlRadius = 10.0;

  static ThemeData get darkTheme => buildTheme(brightness: Brightness.dark);
  static ThemeData get lightTheme => buildTheme(brightness: Brightness.light);

  static ThemeData buildTheme({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? AppColors.bgDark1 : AppColors.lightBg1;
    final surface = isDark ? AppColors.surface : AppColors.lightSurface;
    final deep = isDark ? AppColors.bgDark2 : AppColors.lightBg2;
    final recess = isDark ? AppColors.bgDark3 : AppColors.lightBg3;
    final border = isDark ? AppColors.cardBorder : AppColors.lightCardBorder;
    final accent = isDark ? AppColors.accent : AppColors.lightAccent;
    final onAccent = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textPrimary = isDark
        ? AppColors.textPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;
    final success = isDark ? AppColors.successDark : AppColors.successLight;
    final rimColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.65);

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: success,
      onSecondary: onAccent,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: deep,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border,
      error: AppColors.error,
      onError: Colors.white,
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.4,
        ),
        iconTheme: IconThemeData(color: accent),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: rimColor, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.45), width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: recess,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: TextStyle(color: textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: textMuted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(onAccent),
        side: BorderSide(color: textSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: deep,
        selectedColor: accent.withValues(alpha: isDark ? 0.24 : 0.15),
        checkmarkColor: accent,
        labelStyle: TextStyle(color: textSecondary, fontSize: 12),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: textPrimary, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: rimColor, width: 1.0),
        ),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        textStyle: TextStyle(color: textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          side: BorderSide(color: border),
        ),
      ),
      toggleButtonsTheme: ToggleButtonsThemeData(
        selectedColor: accent,
        color: textSecondary,
        fillColor: accent.withValues(alpha: isDark ? 0.2 : 0.14),
        selectedBorderColor: accent,
        borderColor: border,
        borderRadius: BorderRadius.circular(8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        labelLarge: TextStyle(color: textPrimary),
        labelMedium: TextStyle(color: textSecondary),
        labelSmall: TextStyle(color: textMuted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Decoration Factories
// ─────────────────────────────────────────────────────────────────────────────

// class AppDecorations {
//   AppDecorations._();
//
//   /// Full-screen gradient background.
//   static BoxDecoration gradientBackground([BuildContext? context]) {
//     final isDark =
//         context == null || Theme.of(context).brightness == Brightness.dark;
//     return BoxDecoration(
//       gradient: LinearGradient(
//         begin: Alignment.topLeft,
//         end: Alignment.bottomRight,
//         colors: isDark
//             ? [AppColors.bgDark1, AppColors.bgDark2, AppColors.bgDark3]
//             : [AppColors.lightBg1, AppColors.lightBg2, AppColors.lightBg3],
//       ),
//     );
//   }
//
//   /// Glassmorphism card decoration.
//   static BoxDecoration glassCard({BuildContext? context, Color? glowColor}) {
//     final isDark =
//         context == null || Theme.of(context).brightness == Brightness.dark;
//     return BoxDecoration(
//       color: isDark
//           ? AppColors.surface.withValues(alpha: 0.95)
//           : AppColors.lightSurface,
//       borderRadius: BorderRadius.circular(16),
//       border: Border.all(
//         color:
//             (glowColor ?? (isDark ? AppColors.accent : AppColors.lightAccent))
//                 .withValues(alpha: isDark ? 0.15 : 0.3),
//         width: 1,
//       ),
//       boxShadow: [
//         BoxShadow(
//           color: isDark
//               ? (glowColor ?? AppColors.accent).withValues(alpha: 0.08)
//               : Colors.black.withValues(alpha: 0.05),
//           blurRadius: 16,
//           spreadRadius: 0,
//         ),
//       ],
//     );
//   }
//
//   /// Solid card decoration for popups/dialogs to prevent background bleed-through.
//   static BoxDecoration dialogCard({BuildContext? context, Color? glowColor}) {
//     final isDark =
//         context == null || Theme.of(context).brightness == Brightness.dark;
//     return BoxDecoration(
//       color: isDark ? AppColors.bgDark2 : AppColors.lightSurface,
//       borderRadius: BorderRadius.circular(16),
//       border: Border.all(
//         color:
//             (glowColor ?? (isDark ? AppColors.accent : AppColors.lightAccent))
//                 .withValues(alpha: isDark ? 0.3 : 0.4),
//         width: 1.5,
//       ),
//       boxShadow: [
//         BoxShadow(
//           color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
//           blurRadius: 24,
//           spreadRadius: 2,
//         ),
//       ],
//     );
//   }
//
//   /// Log console decoration.
//   static BoxDecoration logConsole([BuildContext? context]) {
//     final isDark =
//         context == null || Theme.of(context).brightness == Brightness.dark;
//     return BoxDecoration(
//       color: isDark ? const Color(0xFF241E19) : const Color(0xFF2B2B2E),
//       borderRadius: BorderRadius.circular(12),
//       border: Border.all(
//         color: isDark
//             ? AppColors.cardBorder.withValues(alpha: 0.6)
//             : const Color(0xFF4A453D),
//       ),
//     );
//   }
//
//   /// Path row field decoration.
//   static BoxDecoration pathField([BuildContext? context]) {
//     final isDark =
//         context == null || Theme.of(context).brightness == Brightness.dark;
//     return BoxDecoration(
//       color: isDark ? AppColors.bgDark2 : AppColors.lightSurface,
//       border: Border.all(
//         color: isDark ? AppColors.cardBorder : AppColors.lightCardBorder,
//       ),
//       borderRadius: BorderRadius.circular(8),
//     );
//   }
// }
// Gene - Nov, 22, 2026: Upgraded AppDecorations to uniform Neumorphic base canvas, dual-shadow extruded cards, crisp dialogs, and modern slate console.
class AppDecorations {
  AppDecorations._();

  /// Uniform neumorphic canvas so extruded dual shadows blend cleanly.
  static BoxDecoration gradientBackground([BuildContext? context]) {
    final isDark =
        context == null || Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.bgDark1 : AppColors.lightBg1,
    );
  }

  /// Raised neumorphic card decoration.
  static BoxDecoration glassCard({BuildContext? context, Color? glowColor}) {
    final isDark =
        context == null || Theme.of(context).brightness == Brightness.dark;
    final Border cardBorder = context != null
        ? NeumorphicTheme.rimBorder(
            context,
            accentColor: glowColor,
            width: 0.95,
          )
        : Border.all(
            color: (glowColor ?? AppColors.accent).withValues(alpha: 0.2),
            width: 1,
          );
    final List<BoxShadow> cardShadows = context != null
        ? NeumorphicTheme.raisedShadows(
            context,
            distance: isDark ? 5.0 : 6.0,
            blur: isDark ? 10.0 : 12.0,
          )
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(4, 4),
            ),
          ];

    return BoxDecoration(
      color: isDark ? AppColors.surface : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      border: cardBorder,
      boxShadow: cardShadows,
    );
  }

  /// Solid neumorphic surface for popups/dialogs to prevent background bleed-through.
  static BoxDecoration dialogCard({BuildContext? context, Color? glowColor}) {
    final isDark =
        context == null || Theme.of(context).brightness == Brightness.dark;
    final Border dialogBorder = context != null
        ? NeumorphicTheme.rimBorder(context, accentColor: glowColor, width: 1.1)
        : Border.all(
            color: (glowColor ?? AppColors.accent).withValues(alpha: 0.3),
            width: 1.1,
          );
    return BoxDecoration(
      color: isDark ? AppColors.surface : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(18),
      border: dialogBorder,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.22),
          blurRadius: 28,
          spreadRadius: 1,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  /// Modern dark slate log console decoration.
  static BoxDecoration logConsole([BuildContext? context]) {
    final isDark =
        context == null || Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? const Color(0xFF13161C) : const Color(0xFF1E2430),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.lightShadow.withValues(alpha: 0.45),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// Recessed path row field decoration.
  static BoxDecoration pathField([BuildContext? context]) {
    final isDark =
        context == null || Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.bgDark3 : AppColors.lightBg3,
      border: Border.all(
        color: isDark ? AppColors.cardBorder : AppColors.lightCardBorder,
      ),
      borderRadius: BorderRadius.circular(AppTheme.controlRadius),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Log Message Coloring
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the color for a log message based on its content.
Color getLogColor(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('✗') ||
      lower.contains('error') ||
      lower.contains('failed') ||
      lower.contains('critical')) {
    return AppColors.logError;
  }
  if (lower.contains('✓') ||
      lower.contains('completed') ||
      lower.contains('done') ||
      lower.contains('copied:')) {
    return AppColors.logSuccess;
  }
  if (lower.contains('⚠') ||
      lower.contains('warning') ||
      lower.contains('skipped') ||
      lower.contains('already exist')) {
    return AppColors.logWarning;
  }
  if (lower.contains('⏳') ||
      lower.contains('scanning') ||
      lower.contains('starting') ||
      lower.contains('waiting')) {
    return AppColors.logInfo;
  }
  return AppColors.logDefault;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Stat badge used across all screens.
// class StatBadge extends StatelessWidget {
//   final String title;
//   final String value;
//   final Color color;
//   final IconData icon;
//   final VoidCallback? onTap;
//
//   const StatBadge({
//     super.key,
//     required this.title,
//     required this.value,
//     required this.color,
//     required this.icon,
//     this.onTap,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     final isDark = context.isDarkMode;
//     final badgeBg = isDark
//         ? color.withValues(alpha: 0.12)
//         : color.withValues(alpha: 0.08);
//     final badgeBorder = isDark
//         ? color.withValues(alpha: 0.4)
//         : color.withValues(alpha: 0.4);
//
//     final content = Container(
//       padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
//       decoration: BoxDecoration(
//         color: badgeBg,
//         border: Border.all(color: badgeBorder),
//         borderRadius: BorderRadius.circular(10),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Icon(icon, color: color, size: 16),
//           const SizedBox(width: 6),
//           Text(
//             '$title: $value',
//             style: TextStyle(
//               fontSize: 13,
//               fontWeight: FontWeight.w600,
//               color: color,
//             ),
//           ),
//         ],
//       ),
//     );
//
//     if (onTap != null) {
//       return Material(
//         color: Colors.transparent,
//         child: InkWell(
//           onTap: onTap,
//           borderRadius: BorderRadius.circular(10),
//           child: content,
//         ),
//       );
//     }
//     return content;
//   }
// }
// Gene - Nov, 22, 2026: Styled StatBadge as a tactile raised Neumorphic pill matching Batterie status badges.
class StatBadge extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  const StatBadge({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: context.cardBg,
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.35 : 0.32),
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        boxShadow: NeumorphicTheme.softShadows(
          context,
          distance: 2.0,
          blur: 4.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$title: $value',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          child: content,
        ),
      );
    }
    return content;
  }
}

class PathRow extends StatefulWidget {
  final String label;
  final String? path;
  final VoidCallback? onPick;
  final ValueChanged<String>? onChanged;

  const PathRow({
    super.key,
    required this.label,
    this.path,
    this.onPick,
    this.onChanged,
  });

  @override
  State<PathRow> createState() => _PathRowState();
}

class _PathRowState extends State<PathRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.path ?? '');
  }

  @override
  void didUpdateWidget(PathRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path && widget.path != _controller.text) {
      _controller.text = widget.path ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '${widget.label}:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            onChanged: widget.onChanged,
            style: TextStyle(color: context.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Not Selected',
              hintStyle: TextStyle(color: context.textMuted),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: Icon(Icons.history, color: context.primaryAccent),
          tooltip: 'Recent Directories',
          color: context.cardBg,
          constraints: const BoxConstraints(minWidth: 400, maxWidth: 600),
          itemBuilder: (context) {
            final recent = LocalDbService().getRecentDirectories();
            if (recent.isEmpty) {
              return [
                PopupMenuItem<String>(
                  value: '',
                  enabled: false,
                  child: Text(
                    'No recent directories',
                    style: TextStyle(color: context.textMuted),
                  ),
                ),
              ];
            }
            return recent
                .map(
                  (path) => PopupMenuItem<String>(
                    value: path,
                    child: Text(
                      path,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList();
          },
          onSelected: (path) {
            if (path.isNotEmpty && widget.onChanged != null) {
              _controller.text = path;
              widget.onChanged!(path);
            }
          },
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: widget.onPick,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Browse'),
        ),
      ],
    );
  }
}

/// Log console widget used across all screens.
// class LogConsole extends StatelessWidget {
//   final List<String> logs;
//
//   const LogConsole({super.key, required this.logs});
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: AppDecorations.logConsole(context),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Console header
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
//             decoration: BoxDecoration(
//               border: Border(
//                 bottom: BorderSide(
//                   color: AppColors.cardBorder.withValues(alpha: 0.4),
//                 ),
//               ),
//             ),
//             child: Row(
//               children: [
//                 Container(
//                   width: 8,
//                   height: 8,
//                   decoration: BoxDecoration(
//                     color: logs.isEmpty
//                         ? AppColors.textMuted
//                         : AppColors.success,
//                     shape: BoxShape.circle,
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 const Text(
//                   'Output',
//                   style: TextStyle(
//                     fontSize: 11,
//                     color: AppColors.textMuted,
//                     fontWeight: FontWeight.w500,
//                     letterSpacing: 0.5,
//                   ),
//                 ),
//                 const Spacer(),
//                 Text(
//                   '${logs.length} entries',
//                   style: const TextStyle(
//                     fontSize: 11,
//                     color: AppColors.textMuted,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           // Log entries
//           Expanded(
//             child: ListView.builder(
//               padding: const EdgeInsets.all(10),
//               reverse: true,
//               itemCount: logs.length,
//               itemBuilder: (context, index) {
//                 final message = logs[index];
//                 return Padding(
//                   padding: const EdgeInsets.symmetric(vertical: 1),
//                   child: Text(
//                     message,
//                     style: TextStyle(
//                       fontFamily: 'Consolas',
//                       fontSize: 12,
//                       color: getLogColor(message),
//                       height: 1.4,
//                     ),
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// /// Time picker widget used in transfer and copy screens.
// class StyledTimePicker extends StatelessWidget {
//   final String label;
//   final TimeOfDay time;
//   final bool enabled;
//   final ValueChanged<TimeOfDay> onPicked;
//
//   const StyledTimePicker({
//     super.key,
//     required this.label,
//     required this.time,
//     required this.enabled,
//     required this.onPicked,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: enabled
//           ? () async {
//               final picked = await showTimePicker(
//                 context: context,
//                 initialTime: time,
//               );
//               if (picked != null) {
//                 onPicked(picked);
//               }
//             }
//           : null,
//       borderRadius: BorderRadius.circular(8),
//       child: Opacity(
//         opacity: enabled ? 1.0 : 0.4,
//         child: InputDecorator(
//           decoration: InputDecoration(
//             labelText: label,
//             suffixIcon: const Icon(
//               Icons.access_time,
//               size: 16,
//               color: AppColors.textMuted,
//             ),
//           ),
//           child: Text(
//             time.format(context),
//             style: TextStyle(color: context.textPrimary, fontSize: 13),
//           ),
//         ),
//       ),
//     );
//   }
// }
// Gene - Nov, 22, 2026: Updated LogConsole header tokens for modern dark slate terminal and made StyledTimePicker theme-aware.
class LogConsole extends StatelessWidget {
  final List<String> logs;

  const LogConsole({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.logConsole(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Console header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2D3544))),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: logs.isEmpty
                        ? const Color(0xFF94A3B8)
                        : AppColors.logSuccess,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Output',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${logs.length} entries',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          // Log entries
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              reverse: true,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final message = logs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    message,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      color: getLogColor(message),
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Time picker widget used in transfer and copy screens.
class StyledTimePicker extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final bool enabled;
  final ValueChanged<TimeOfDay> onPicked;

  const StyledTimePicker({
    super.key,
    required this.label,
    required this.time,
    required this.enabled,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: time,
              );
              if (picked != null) {
                onPicked(picked);
              }
            }
          : null,
      borderRadius: BorderRadius.circular(AppTheme.controlRadius),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: Icon(
              Icons.access_time,
              size: 16,
              color: context.textMuted,
            ),
          ),
          child: Text(
            time.format(context),
            style: TextStyle(color: context.textPrimary, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
