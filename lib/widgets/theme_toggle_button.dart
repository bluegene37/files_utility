import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  //   @override
  //   Widget build(BuildContext context) {
  //     final isDark = Theme.of(context).brightness == Brightness.dark;
  //     return Consumer<ThemeProvider>(
  //       builder: (context, themeProvider, child) {
  //         return Container(
  //           decoration: BoxDecoration(
  //             color: isDark ? AppColors.surface : Colors.white,
  //             borderRadius: BorderRadius.circular(10),
  //             border: Border.all(
  //               color: isDark ? AppColors.cardBorder : AppColors.lightCardBorder,
  //               width: 1,
  //             ),
  //           ),
  //           child: IconButton(
  //             constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
  //             padding: EdgeInsets.zero,
  //             tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
  //             icon: Icon(
  //               isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
  //               color: isDark ? Colors.amber : AppColors.lightAccent,
  //               size: 20,
  //             ),
  //             onPressed: () => themeProvider.toggleTheme(),
  //           ),
  //         );
  //       },
  //     );
  //   }
  // Gene - Nov, 22, 2026: Styled ThemeToggleButton with raised Neumorphic container and Batterie theme icons.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(AppTheme.controlRadius),
            border: NeumorphicTheme.rimBorder(context),
            boxShadow: NeumorphicTheme.softShadows(
              context,
              distance: 2.5,
              blur: 5.0,
            ),
          ),
          child: IconButton(
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            padding: EdgeInsets.zero,
            tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: isDark ? AppColors.warningDark : context.primaryAccent,
              size: 19,
            ),
            onPressed: () => themeProvider.toggleTheme(),
          ),
        );
      },
    );
  }
}
