import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../providers/history_provider.dart';
import 'home_screen.dart';
import 'delete_screen.dart';
import 'copy_files_screen.dart';
import 'count_files_screen.dart';
import 'history_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppDecorations.gradientBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.3),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Files Utility',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Manage your files and transfers',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      'v1.0.0',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Card Grid
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 14,
                        childAspectRatio: 2.4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _DashboardCard(
                            icon: Icons.move_to_inbox_rounded,
                            title: 'Transfer Files',
                            subtitle: 'Move files by date, month & year filters',
                            accentColor: AppColors.accent,
                            onTap: () => _navigateTo(context, const TransferScreen()),
                          ),
                          _DashboardCard(
                            icon: Icons.file_copy_rounded,
                            title: 'Copy Files',
                            subtitle: 'Mirror directories with date range control',
                            accentColor: AppColors.info,
                            onTap: () => _navigateTo(context, const CopyFilesScreen()),
                          ),
                          _DashboardCard(
                            icon: Icons.delete_forever_rounded,
                            title: 'Delete Files',
                            subtitle: 'Remove files matching date criteria',
                            accentColor: AppColors.error,
                            onTap: () => _navigateTo(context, const DeleteScreen()),
                          ),
                          _DashboardCard(
                            icon: Icons.analytics_rounded,
                            title: 'Count Files',
                            subtitle: 'Audit file & folder totals in any path',
                            accentColor: AppColors.success,
                            onTap: () => _navigateTo(context, const CountFilesScreen()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // History Section
                _buildHistoryDashboard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryDashboard(BuildContext context) {
    return Consumer<HistoryProvider>(
      builder: (context, provider, child) {
        return Container(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.all(20),
          decoration: AppDecorations.glassCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'History Dashboard',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _navigateTo(context, const HistoryScreen()),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat('Total Runs', provider.totalRuns.toString(), AppColors.textPrimary),
                  _buildMiniStat('Files Transferred', NumberFormat('#,##0').format(provider.totalFilesTransferred), AppColors.accent),
                  _buildMiniStat('Files Copied', NumberFormat('#,##0').format(provider.totalFilesCopied), AppColors.info),
                  _buildMiniStat('Errors', NumberFormat('#,##0').format(provider.totalErrors), provider.totalErrors > 0 ? AppColors.error : AppColors.success),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Future<void> _navigateTo(BuildContext context, Widget screen) async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.02, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    // Refresh history dashboard when returning from any sub-screen
    if (context.mounted) {
      context.read<HistoryProvider>().refreshHistory();
    }
  }
}

class _DashboardCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: _isHovered
              ? Matrix4.translationValues(0.0, -3.0, 0.0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: _isHovered
                ? AppColors.surfaceLight.withValues(alpha: 0.8)
                : AppColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isHovered
                  ? widget.accentColor.withValues(alpha: 0.4)
                  : AppColors.cardBorder.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: 0.12),
                  blurRadius: 30,
                  spreadRadius: 0,
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon with glow
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _isHovered
                        ? [
                            BoxShadow(
                              color: widget.accentColor.withValues(alpha: 0.2),
                              blurRadius: 16,
                              spreadRadius: 0,
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.accentColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _isHovered ? widget.accentColor : AppColors.textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
