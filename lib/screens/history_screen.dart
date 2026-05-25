import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';
import '../models/run_record.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppDecorations.gradientBackground,
        child: Column(
          children: [
            // App Bar
            _buildAppBar(context),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Consumer<HistoryProvider>(
                  builder: (context, provider, child) {
                    if (provider.isLoading) {
                      return const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                        ),
                      );
                    }

                    if (provider.records.isEmpty) {
                      return const Center(
                        child: Text(
                          'No history available.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 16),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        // Summary Stats Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatItem('Total Runs', provider.totalRuns.toString(), Icons.history, AppColors.info),
                            _buildStatItem('Transferred', NumberFormat('#,##0').format(provider.totalFilesTransferred), Icons.move_up, AppColors.accent),
                            _buildStatItem('Copied', NumberFormat('#,##0').format(provider.totalFilesCopied), Icons.file_copy, AppColors.info),
                            _buildStatItem('Errors', NumberFormat('#,##0').format(provider.totalErrors), Icons.error_outline, AppColors.error),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // History List
                        Expanded(
                          child: Container(
                            decoration: AppDecorations.glassCard(),
                            child: ListView.separated(
                              itemCount: provider.records.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final record = provider.records[index];
                                return _buildRecordItem(record);
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.accent),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.history, color: AppColors.accent, size: 22),
          const SizedBox(width: 10),
          const Text(
            'Run History',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              final provider = Provider.of<HistoryProvider>(context, listen: false);
              _showClearConfirmation(context, provider);
            },
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
            label: const Text('Clear History', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgDark2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
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
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordItem(RunRecord record) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');
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
        opColor = AppColors.accent;
        opIcon = Icons.move_up;
        break;
      case 'Copy':
        opColor = AppColors.info;
        opIcon = Icons.file_copy;
        break;
      case 'Delete':
        opColor = AppColors.error;
        opIcon = Icons.delete_forever;
        break;
      case 'Count':
        opColor = AppColors.success;
        opIcon = Icons.analytics;
        break;
      default:
        opColor = AppColors.textMuted;
        opIcon = Icons.help_outline;
    }

    Color statusColor = record.status == 'Completed'
        ? AppColors.success
        : record.status == 'Stopped'
            ? AppColors.warning
            : AppColors.error;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: opColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(opIcon, color: opColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      record.operation,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        record.status,
                        style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      dateFormat.format(record.startTime),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  record.configSummary,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMiniStat(Icons.insert_drive_file, '${NumberFormat('#,##0').format(record.filesProcessed)} Files'),
                    if (record.foldersProcessed > 0) ...[
                      const SizedBox(width: 16),
                      _buildMiniStat(Icons.folder, '${NumberFormat('#,##0').format(record.foldersProcessed)} Folders'),
                    ],
                    if (record.errors > 0) ...[
                      const SizedBox(width: 16),
                      _buildMiniStat(Icons.error_outline, '${NumberFormat('#,##0').format(record.errors)} Errors', color: AppColors.error),
                    ],
                    const Spacer(),
                    _buildMiniStat(Icons.timer, durationStr),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String text, {Color color = AppColors.textMuted}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
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
        content: const Text(
          'Are you sure you want to clear all history records? This cannot be undone.',
          style: TextStyle(color: AppColors.textPrimary),
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
