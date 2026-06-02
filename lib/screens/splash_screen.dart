import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'profile_selection_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const ProfileSelectionScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppDecorations.gradientBackground,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeIn.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App icon
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.3),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // App name
                const Text(
                  'Files Utility',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Manage your files and transfers with ease',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'v1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 48),
                // Loading indicator
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.accent.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
