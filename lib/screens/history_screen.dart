import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/history_provider.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';
import '../theme/app_theme.dart';
import '../models/run_record.dart';
import '../services/window_service.dart';
import '../widgets/theme_toggle_button.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _operations = ['All', 'Transfer', 'Copy', 'Delete', 'Count'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _operations.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryProvider>().refreshHistory();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WindowService().updateTitle('History & Analytics');
    final currentProfileId = LocalDbService().currentProfileId;
    final currentProfile = GlobalDbService().profiles.firstWhere(
      (p) => p.id == currentProfileId,
      orElse: () => GlobalDbService().profiles.first,
    );

    return Scaffold(
      body: Container(
        decoration: AppDecorations.gradientBackground(context),
        child: Column(
          children: [
            // App Bar
            _buildAppBar(context, currentProfile.name),

            // Content
            Expanded(
              child: Consumer<HistoryProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(context.primaryAccent),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Operations Visual Graphs Dashboard
                        _buildVisualGraphsDashboard(context, provider),
                        const SizedBox(height: 16),

                        // Tab Bar for each operation table
                        Container(
                          decoration: BoxDecoration(
                            color: context.containerBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.border),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicatorColor: context.primaryAccent,
                            labelColor: context.primaryAccent,
                            unselectedLabelColor: context.textSecondary,
                            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            tabs: _operations.map((op) => Tab(text: '$op History')).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tab Bar Views (Tables per operation)
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: _operations.map((op) {
                              final filtered = op == 'All'
                                  ? provider.records
                                  : provider.records.where((r) => r.operation == op).toList();
                              return _buildHistoryTable(context, filtered);
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, String profileName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: context.primaryAccent),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Icon(Icons.bar_chart_rounded, color: context.primaryAccent, size: 24),
          const SizedBox(width: 10),
          Text(
            'History & Analytics Dashboard ($profileName)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              final provider = Provider.of<HistoryProvider>(context, listen: false);
              _showClearConfirmation(context, provider);
            },
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
            label: const Text('Clear All History', style: TextStyle(color: AppColors.error)),
          ),
          const SizedBox(width: 12),
          const ThemeToggleButton(),
        ],
      ),
    );
  }

  Widget _buildVisualGraphsDashboard(BuildContext context, HistoryProvider provider) {
    final records = provider.records;

    int transferFiles = records.where((r) => r.operation == 'Transfer').fold(0, (sum, r) => sum + r.filesProcessed);
    int copyFiles = records.where((r) => r.operation == 'Copy').fold(0, (sum, r) => sum + r.filesProcessed);
    int deleteFiles = records.where((r) => r.operation == 'Delete').fold(0, (sum, r) => sum + r.filesProcessed);
    int countFiles = records.where((r) => r.operation == 'Count').fold(0, (sum, r) => sum + r.filesProcessed);

    int maxFiles = [transferFiles, copyFiles, deleteFiles, countFiles]
        .reduce((max, val) => val > max ? val : max);
    if (maxFiles == 0) maxFiles = 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.glassCard(context: context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.query_stats_rounded, color: context.primaryAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Operation Activity Summary',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Total Runs: ${records.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Bar Graph Comparison Cards
          Row(
            children: [
              Expanded(
                child: _buildOperationGraphCard(
                  context,
                  title: 'Transfer',
                  icon: Icons.move_up,
                  color: context.isDarkMode ? AppColors.accent : const Color(0xFF0D9488),
                  runsCount: records.where((r) => r.operation == 'Transfer').length,
                  filesCount: transferFiles,
                  ratio: transferFiles / maxFiles,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOperationGraphCard(
                  context,
                  title: 'Copy',
                  icon: Icons.file_copy,
                  color: context.isDarkMode ? AppColors.info : const Color(0xFF0284C7),
                  runsCount: records.where((r) => r.operation == 'Copy').length,
                  filesCount: copyFiles,
                  ratio: copyFiles / maxFiles,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOperationGraphCard(
                  context,
                  title: 'Delete',
                  icon: Icons.delete_forever,
                  color: AppColors.error,
                  runsCount: records.where((r) => r.operation == 'Delete').length,
                  filesCount: deleteFiles,
                  ratio: deleteFiles / maxFiles,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOperationGraphCard(
                  context,
                  title: 'Count',
                  icon: Icons.analytics,
                  color: context.isDarkMode ? AppColors.success : const Color(0xFF16A34A),
                  runsCount: records.where((r) => r.operation == 'Count').length,
                  filesCount: countFiles,
                  ratio: countFiles / maxFiles,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperationGraphCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required int runsCount,
    required int filesCount,
    required double ratio,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.containerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$runsCount runs',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                NumberFormat('#,##0').format(filesCount),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'files',
                style: TextStyle(
                  fontSize: 11,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar representation
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.04, 1.0),
              minHeight: 6,
              backgroundColor: context.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTable(BuildContext context, List<RunRecord> records) {
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: AppDecorations.glassCard(context: context),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_toggle_off, color: context.textMuted, size: 48),
              const SizedBox(height: 12),
              Text(
                'No history records found',
                style: TextStyle(
                  fontSize: 16,
                  color: context.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final isDark = context.isDarkMode;

    return Container(
      decoration: AppDecorations.glassCard(context: context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                isDark ? AppColors.bgDark2 : const Color(0xFFE2E8F0),
              ),
              dataRowMinHeight: 52,
              dataRowMaxHeight: 64,
              horizontalMargin: 16,
              columnSpacing: 20,
              columns: [
                DataColumn(
                  label: Text(
                    'Operation',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Status',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Date & Time',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Duration',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Source Directory',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Target / Dest',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Files',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Folders',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Errors',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
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

                Color opColor = _getOpColor(record.operation, isDark);
                IconData opIcon = _getOpIcon(record.operation);

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
                          Icon(opIcon, color: opColor, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            record.operation,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: opColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          record.status,
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        dateFormat.format(record.startTime),
                        style: TextStyle(fontSize: 12, color: context.textPrimary),
                      ),
                    ),
                    DataCell(
                      Text(
                        durationStr,
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 220,
                        child: Text(
                          record.sourcePath ?? '-',
                          style: TextStyle(fontSize: 12, fontFamily: 'Consolas', color: context.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 220,
                        child: Text(
                          record.destPath ?? '-',
                          style: TextStyle(fontSize: 12, fontFamily: 'Consolas', color: context.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        NumberFormat('#,##0').format(record.filesProcessed),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textPrimary),
                      ),
                    ),
                    DataCell(
                      Text(
                        NumberFormat('#,##0').format(record.foldersProcessed),
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                    ),
                    DataCell(
                      Text(
                        NumberFormat('#,##0').format(record.errors),
                        style: TextStyle(
                          fontSize: 12,
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
        ),
      ),
    );
  }

  Color _getOpColor(String operation, bool isDark) {
    switch (operation) {
      case 'Transfer':
        return isDark ? AppColors.accent : const Color(0xFF0D9488);
      case 'Copy':
        return isDark ? AppColors.info : const Color(0xFF0284C7);
      case 'Delete':
        return AppColors.error;
      case 'Count':
        return isDark ? AppColors.success : const Color(0xFF16A34A);
      default:
        return AppColors.textMuted;
    }
  }

  IconData _getOpIcon(String operation) {
    switch (operation) {
      case 'Transfer':
        return Icons.move_up;
      case 'Copy':
        return Icons.file_copy;
      case 'Delete':
        return Icons.delete_forever;
      case 'Count':
        return Icons.analytics;
      default:
        return Icons.help_outline;
    }
  }

  void _showClearConfirmation(BuildContext context, HistoryProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            const SizedBox(width: 8),
            const Text('Clear History'),
          ],
        ),
        content: Text(
          'Are you sure you want to clear all history records? This cannot be undone.',
          style: TextStyle(color: context.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.clearHistory();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
