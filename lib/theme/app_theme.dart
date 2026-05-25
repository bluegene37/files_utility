import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color Palette
// ─────────────────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Base dark backgrounds
  static const Color bgDark1 = Color(0xFF0D0D1A);
  static const Color bgDark2 = Color(0xFF1A1A2E);
  static const Color bgDark3 = Color(0xFF16213E);
  static const Color bgDark4 = Color(0xFF0F3460);

  // Surface & card
  static const Color surface = Color(0xFF1E1E36);
  static const Color surfaceLight = Color(0xFF262644);
  static const Color cardBorder = Color(0xFF2E2E50);

  // Accent
  static const Color accent = Color(0xFF14CCCC);
  static const Color accentLight = Color(0xFF1AEAEA);
  static const Color accentMuted = Color(0xFF0F9999);

  // Semantic
  static const Color success = Color(0xFF4ADE80);
  static const Color error = Color(0xFFFF6B6B);
  static const Color warning = Color(0xFFFBBF24);
  static const Color info = Color(0xFF60A5FA);

  // Text
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFFA0A0BE);
  static const Color textMuted = Color(0xFF6B6B8A);

  // Log console colors
  static const Color logSuccess = Color(0xFF4ADE80);
  static const Color logError = Color(0xFFFF6B6B);
  static const Color logInfo = Color(0xFF67E8F9);
  static const Color logWarning = Color(0xFFFBBF24);
  static const Color logDefault = Color(0xFFD0D0E8);
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme Data
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: AppColors.bgDark1,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accentLight,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.bgDark1,
        onSecondary: AppColors.bgDark1,
        onSurface: AppColors.textPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: AppColors.accent),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface.withValues(alpha: 0.7),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.bgDark1,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.accent, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgDark2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(AppColors.bgDark1),
        side: const BorderSide(color: AppColors.textSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgDark2,
        selectedColor: AppColors.accent.withValues(alpha: 0.2),
        checkmarkColor: AppColors.accent,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        side: const BorderSide(color: AppColors.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgDark2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.cardBorder,
        thickness: 1,
      ),
      toggleButtonsTheme: ToggleButtonsThemeData(
        selectedColor: AppColors.accent,
        color: AppColors.textSecondary,
        fillColor: AppColors.accent.withValues(alpha: 0.15),
        selectedBorderColor: AppColors.accent,
        borderColor: AppColors.cardBorder,
        borderRadius: BorderRadius.circular(8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textPrimary),
        bodySmall: TextStyle(color: AppColors.textSecondary),
        labelLarge: TextStyle(color: AppColors.textPrimary),
        labelMedium: TextStyle(color: AppColors.textSecondary),
        labelSmall: TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Decoration Factories
// ─────────────────────────────────────────────────────────────────────────────

class AppDecorations {
  AppDecorations._();

  /// Full-screen gradient background.
  static const BoxDecoration gradientBackground = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.bgDark1, AppColors.bgDark2, AppColors.bgDark3],
    ),
  );

  /// Glassmorphism card decoration.
  static BoxDecoration glassCard({Color? glowColor}) {
    return BoxDecoration(
      color: AppColors.surface.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: (glowColor ?? AppColors.accent).withValues(alpha: 0.15),
        width: 1,
      ),
      boxShadow: [
        if (glowColor != null)
          BoxShadow(
            color: glowColor.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 0,
          ),
      ],
    );
  }

  /// Log console decoration.
  static BoxDecoration logConsole = BoxDecoration(
    color: const Color(0xFF0A0A18),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
  );

  /// Path row field decoration.
  static BoxDecoration pathField = BoxDecoration(
    color: AppColors.bgDark2,
    border: Border.all(color: AppColors.cardBorder),
    borderRadius: BorderRadius.circular(8),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Log Message Coloring
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the color for a log message based on its content.
Color getLogColor(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('✗') || lower.contains('error') || lower.contains('failed') || lower.contains('critical')) {
    return AppColors.logError;
  }
  if (lower.contains('✓') || lower.contains('completed') || lower.contains('done') || lower.contains('copied:')) {
    return AppColors.logSuccess;
  }
  if (lower.contains('⚠') || lower.contains('warning') || lower.contains('skipped') || lower.contains('already exist')) {
    return AppColors.logWarning;
  }
  if (lower.contains('⏳') || lower.contains('scanning') || lower.contains('starting') || lower.contains('waiting')) {
    return AppColors.logInfo;
  }
  return AppColors.logDefault;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Stat badge used across all screens.
class StatBadge extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const StatBadge({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
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
            ),
          ),
        ],
      ),
    );
  }
}

/// Path selector row used across all screens.
class PathRow extends StatelessWidget {
  final String label;
  final String? path;
  final VoidCallback? onPick;

  const PathRow({
    super.key,
    required this.label,
    this.path,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: AppDecorations.pathField,
            child: Text(
              path ?? 'Not Selected',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: path == null ? AppColors.textMuted : AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: onPick,
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
class LogConsole extends StatelessWidget {
  final List<String> logs;

  const LogConsole({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.logConsole,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Console header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.cardBorder.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: logs.isEmpty ? AppColors.textMuted : AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Output',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${logs.length} entries',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
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
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.access_time, size: 16, color: AppColors.textMuted),
          ),
          child: Text(
            time.format(context),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
