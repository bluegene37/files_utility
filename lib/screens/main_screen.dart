import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../providers/history_provider.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';
import '../models/run_record.dart';
import '../widgets/theme_toggle_button.dart';
import 'transfer_files_screen.dart';
import 'delete_files_screen.dart';
import 'copy_files_screen.dart';
import 'count_files_screen.dart';
import 'history_screen.dart';
import '../services/window_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {

  @override
  Widget build(BuildContext context) {
    WindowService().updateTitle('Main Dashboard');
    final currentProfileId = LocalDbService().currentProfileId;
    final currentProfile = GlobalDbService().profiles.firstWhere(
      (p) => p.id == currentProfileId,
      orElse: () => GlobalDbService().profiles.first,
    );

    return Scaffold(
      body: Container(
        decoration: AppDecorations.gradientBackground(context),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header & Active Profile Row
                _buildHeaderAndProfile(context, currentProfile),

                const SizedBox(height: 16),

                // 4 Action Buttons in a Single Line
                Row(
                  children: [
                    Expanded(
                      child: _DashboardCard(
                        icon: Icons.move_to_inbox_rounded,
                        title: 'Transfer Files',
                        subtitle: 'Move files by date & filters',
                        accentColor: context.isDarkMode ? AppColors.accent : const Color(0xFF0D9488),
                        onTap: () => _navigateTo(context, const TransferFilesScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DashboardCard(
                        icon: Icons.file_copy_rounded,
                        title: 'Copy Files',
                        subtitle: 'Mirror directories with date range',
                        accentColor: context.isDarkMode ? AppColors.info : const Color(0xFF0284C7),
                        onTap: () => _navigateTo(context, const CopyFilesScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DashboardCard(
                        icon: Icons.delete_forever_rounded,
                        title: 'Delete Files',
                        subtitle: 'Remove files matching criteria',
                        accentColor: AppColors.error,
                        onTap: () => _navigateTo(context, const DeleteFilesScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DashboardCard(
                        icon: Icons.analytics_rounded,
                        title: 'Count Files',
                        subtitle: 'Audit file & folder totals',
                        accentColor: context.isDarkMode ? AppColors.success : const Color(0xFF16A34A),
                        onTap: () => _navigateTo(context, const CountFilesScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Expanded History Dashboard at the Bottom
                Expanded(
                  child: _buildHistoryDashboard(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderAndProfile(BuildContext context, dynamic currentProfile) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: context.primaryAccent.withValues(alpha: 0.3),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/app_icon.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Files Utility',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'Manage your files and transfers',
              style: TextStyle(
                fontSize: 12,
                color: context.textMuted,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Active Profile Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_circle, color: context.primaryAccent, size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ACTIVE PROFILE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: context.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    currentProfile.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Theme Switcher Button on the FAR RIGHT side
        const ThemeToggleButton(),
      ],
    );
  }

  Widget _buildHistoryDashboard(BuildContext context) {
    return Consumer<HistoryProvider>(
      builder: (context, provider, child) {
        final records = provider.records;

        int transferFiles = records.where((r) => r.operation == 'Transfer').fold(0, (sum, r) => sum + r.filesProcessed);
        int copyFiles = records.where((r) => r.operation == 'Copy').fold(0, (sum, r) => sum + r.filesProcessed);
        int deleteFiles = records.where((r) => r.operation == 'Delete').fold(0, (sum, r) => sum + r.filesProcessed);
        int countFiles = records.where((r) => r.operation == 'Count').fold(0, (sum, r) => sum + r.filesProcessed);

        int maxFiles = [transferFiles, copyFiles, deleteFiles, countFiles]
            .reduce((max, val) => val > max ? val : max);
        if (maxFiles == 0) maxFiles = 1;

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard(context: context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dashboard Header
              Row(
                children: [
                  Icon(Icons.analytics_outlined, color: context.primaryAccent, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'History & Analytics Dashboard',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _navigateTo(context, const HistoryScreen()),
                    icon: const Icon(Icons.bar_chart_rounded, size: 16),
                    label: const Text('View Full Analytics'),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Comparative Operation Graphs
              Row(
                children: [
                  Expanded(child: _buildMiniGraphBar(context, 'Transfer', transferFiles, transferFiles / maxFiles, context.isDarkMode ? AppColors.accent : const Color(0xFF0D9488))),
                  const SizedBox(width: 10),
                  Expanded(child: _buildMiniGraphBar(context, 'Copy', copyFiles, copyFiles / maxFiles, context.isDarkMode ? AppColors.info : const Color(0xFF0284C7))),
                  const SizedBox(width: 10),
                  Expanded(child: _buildMiniGraphBar(context, 'Delete', deleteFiles, deleteFiles / maxFiles, AppColors.error)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildMiniGraphBar(context, 'Count', countFiles, countFiles / maxFiles, context.isDarkMode ? AppColors.success : const Color(0xFF16A34A))),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Recent Run Activity',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              // Recent Activity Table
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Text(
                          'No history records available.',
                          style: TextStyle(color: context.textMuted, fontSize: 13),
                        ),
                      )
                    : _buildRecentActivityTable(context, records.take(10).toList()),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniGraphBar(BuildContext context, String label, int filesCount, double ratio, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.containerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
              ),
              const Spacer(),
              Text(
                NumberFormat('#,##0').format(filesCount),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.05, 1.0),
              minHeight: 4,
              backgroundColor: context.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityTable(BuildContext context, List<RunRecord> records) {
    final dateFormat = DateFormat('MMM dd, HH:mm:ss');
    final isDark = context.isDarkMode;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? AppColors.bgDark2 : const Color(0xFFE2E8F0),
          ),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          horizontalMargin: 12,
          columnSpacing: 16,
          columns: [
            DataColumn(
              label: Text(
                'Operation',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 11),
              ),
            ),
            DataColumn(
              label: Text(
                'Status',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 11),
              ),
            ),
            DataColumn(
              label: Text(
                'Date & Time',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 11),
              ),
            ),
            DataColumn(
              label: Text(
                'Duration',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 11),
              ),
            ),
            DataColumn(
              label: Text(
                'Target / Source Directory',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 11),
              ),
            ),
            DataColumn(
              label: Text(
                'Files',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 11),
              ),
            ),
            DataColumn(
              label: Text(
                'Errors',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 11),
              ),
            ),
          ],
          rows: records.map((record) {
            final duration = record.duration;
            final durationStr = duration.inHours > 0
                ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m'
                : duration.inMinutes > 0
                    ? '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s'
                    : '${duration.inSeconds}s';

            Color opColor;
            IconData opIcon;
            switch (record.operation) {
              case 'Transfer':
                opColor = isDark ? AppColors.accent : const Color(0xFF0D9488);
                opIcon = Icons.move_up;
                break;
              case 'Copy':
                opColor = isDark ? AppColors.info : const Color(0xFF0284C7);
                opIcon = Icons.file_copy;
                break;
              case 'Delete':
                opColor = AppColors.error;
                opIcon = Icons.delete_forever;
                break;
              case 'Count':
                opColor = isDark ? AppColors.success : const Color(0xFF16A34A);
                opIcon = Icons.analytics;
                break;
              default:
                opColor = context.textMuted;
                opIcon = Icons.help_outline;
            }

            Color statusColor = record.status == 'Completed'
                ? (isDark ? AppColors.success : const Color(0xFF16A34A))
                : record.status == 'Stopped'
                    ? (isDark ? AppColors.warning : const Color(0xFFD97706))
                    : AppColors.error;

            return DataRow(
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(opIcon, color: opColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        record.operation,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: opColor,
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      record.status,
                      style: TextStyle(
                        fontSize: 10,
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    dateFormat.format(record.startTime),
                    style: TextStyle(fontSize: 11, color: context.textPrimary),
                  ),
                ),
                DataCell(
                  Text(
                    durationStr,
                    style: TextStyle(fontSize: 11, color: context.textSecondary),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 250,
                    child: Text(
                      record.sourcePath ?? '-',
                      style: TextStyle(fontSize: 11, fontFamily: 'Consolas', color: context.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    NumberFormat('#,##0').format(record.filesProcessed),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.textPrimary),
                  ),
                ),
                DataCell(
                  Text(
                    NumberFormat('#,##0').format(record.errors),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: record.errors > 0 ? AppColors.error : context.textMuted,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
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
    final isDark = context.isDarkMode;
    final cardBgColor = _isHovered
        ? (isDark ? AppColors.surfaceLight : Colors.white)
        : context.cardBg;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: _isHovered
              ? Matrix4.translationValues(0.0, -2.0, 0.0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isHovered
                  ? widget.accentColor.withValues(alpha: 0.5)
                  : context.border,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? widget.accentColor.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: isDark ? 0.0 : 0.04),
                blurRadius: _isHovered ? 16 : 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: isDark ? 0.15 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _isHovered
                        ? [
                            BoxShadow(
                              color: widget.accentColor.withValues(alpha: 0.2),
                              blurRadius: 12,
                              spreadRadius: 0,
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _isHovered ? widget.accentColor : context.textPrimary,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textMuted,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
