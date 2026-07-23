import 'package:flutter/material.dart';
import '../services/local_db_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BuildContext Theme Extensions
// ─────────────────────────────────────────────────────────────────────────────

extension ThemeContextExtension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  Color get textPrimary => isDarkMode ? AppColors.textPrimary : AppColors.lightTextPrimary;
  Color get textSecondary => isDarkMode ? AppColors.textSecondary : AppColors.lightTextSecondary;
  Color get textMuted => isDarkMode ? AppColors.textMuted : AppColors.lightTextMuted;
  Color get cardBg => isDarkMode ? AppColors.surface : AppColors.lightSurface;
  Color get containerBg => isDarkMode ? AppColors.bgDark2 : const Color(0xFFF1F5F9);
  Color get border => isDarkMode ? AppColors.cardBorder : AppColors.lightCardBorder;
  Color get primaryAccent => isDarkMode ? AppColors.accent : const Color(0xFF0D9488);
}

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

  // Surface & card (Dark)
  static const Color surface = Color(0xFF1E1E36);
  static const Color surfaceLight = Color(0xFF262644);
  static const Color cardBorder = Color(0xFF2E2E50);

  // Surface & card (Light)
  static const Color lightBg1 = Color(0xFFF8FAFC);
  static const Color lightBg2 = Color(0xFFF1F5F9);
  static const Color lightBg3 = Color(0xFFE2E8F0);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0xFFCBD5E1);

  // Accent
  static const Color accent = Color(0xFF14CCCC);
  static const Color accentLight = Color(0xFF1AEAEA);
  static const Color accentMuted = Color(0xFF0F9999);

  // Semantic
  static const Color success = Color(0xFF4ADE80);
  static const Color error = Color(0xFFFF6B6B);
  static const Color warning = Color(0xFFFBBF24);
  static const Color info = Color(0xFF60A5FA);

  // Text (Dark)
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFFA0A0BE);
  static const Color textMuted = Color(0xFF6B6B8A);

  // Text (Light)
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF334155);
  static const Color lightTextMuted = Color(0xFF64748B);

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

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: AppColors.lightBg2,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0D9488),
        secondary: Color(0xFF0F766E),
        surface: AppColors.lightSurface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.lightTextPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.lightTextPrimary,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: Color(0xFF0D9488)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.lightCardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0D9488),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF0D9488),
          side: const BorderSide(color: Color(0xFF0D9488), width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return const Color(0xFF0D9488);
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: AppColors.lightTextSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF0D9488).withValues(alpha: 0.15),
        checkmarkColor: const Color(0xFF0D9488),
        labelStyle: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
        side: const BorderSide(color: AppColors.lightCardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: AppColors.lightTextPrimary, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.lightCardBorder),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightCardBorder,
        thickness: 1,
      ),
      toggleButtonsTheme: ToggleButtonsThemeData(
        selectedColor: const Color(0xFF0D9488),
        color: AppColors.lightTextSecondary,
        fillColor: const Color(0xFF0D9488).withValues(alpha: 0.15),
        selectedBorderColor: const Color(0xFF0D9488),
        borderColor: AppColors.lightCardBorder,
        borderRadius: BorderRadius.circular(8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.lightTextPrimary),
        bodyMedium: TextStyle(color: AppColors.lightTextPrimary),
        bodySmall: TextStyle(color: AppColors.lightTextSecondary),
        labelLarge: TextStyle(color: AppColors.lightTextPrimary),
        labelMedium: TextStyle(color: AppColors.lightTextSecondary),
        labelSmall: TextStyle(color: AppColors.lightTextMuted),
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
  static BoxDecoration gradientBackground([BuildContext? context]) {
    final isDark = context == null || Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [AppColors.bgDark1, AppColors.bgDark2, AppColors.bgDark3]
            : [AppColors.lightBg1, AppColors.lightBg2, AppColors.lightBg3],
      ),
    );
  }

  /// Glassmorphism card decoration.
  static BoxDecoration glassCard({BuildContext? context, Color? glowColor}) {
    final isDark = context == null || Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark
          ? AppColors.surface.withValues(alpha: 0.6)
          : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: (glowColor ?? (isDark ? AppColors.accent : const Color(0xFF0D9488)))
            .withValues(alpha: isDark ? 0.15 : 0.3),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? (glowColor ?? AppColors.accent).withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
          blurRadius: 16,
          spreadRadius: 0,
        ),
      ],
    );
  }

  /// Log console decoration.
  static BoxDecoration logConsole([BuildContext? context]) {
    final isDark = context == null || Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? const Color(0xFF0A0A18) : const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isDark
            ? AppColors.cardBorder.withValues(alpha: 0.6)
            : const Color(0xFF334155),
      ),
    );
  }

  /// Path row field decoration.
  static BoxDecoration pathField([BuildContext? context]) {
    final isDark = context == null || Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.bgDark2 : AppColors.lightSurface,
      border: Border.all(
        color: isDark ? AppColors.cardBorder : AppColors.lightCardBorder,
      ),
      borderRadius: BorderRadius.circular(8),
    );
  }
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
    final badgeBg = isDark
        ? color.withValues(alpha: 0.12)
        : color.withValues(alpha: 0.08);
    final badgeBorder = isDark
        ? color.withValues(alpha: 0.4)
        : color.withValues(alpha: 0.4);

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: badgeBg,
        border: Border.all(color: badgeBorder),
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

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
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
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Not Selected',
              hintStyle: TextStyle(
                color: context.textMuted,
              ),
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
                    style: TextStyle(
                      color: context.textMuted,
                    ),
                  ),
                )
              ];
            }
            return recent.map((path) => PopupMenuItem<String>(
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
            )).toList();
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
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
