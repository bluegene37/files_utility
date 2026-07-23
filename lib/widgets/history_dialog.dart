import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/run_record.dart';
import '../providers/history_provider.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';
import '../theme/app_theme.dart';

void showHistoryDialog(BuildContext context, {String initialOperation = 'All'}) {
  HistoryProvider? historyProvider;
  try {
    historyProvider = Provider.of<HistoryProvider>(context, listen: false);
  } catch (_) {}

  showDialog(
    context: context,
    builder: (dialogContext) {
      final child = HistoryDialog(initialOperation: initialOperation);
      if (historyProvider != null) {
        return ChangeNotifierProvider<HistoryProvider>.value(
          value: historyProvider,
          child: child,
        );
      } else {
        return ChangeNotifierProvider<HistoryProvider>(
          create: (_) => HistoryProvider(),
          child: child,
        );
      }
    },
  );
}

class HistoryDialog extends StatefulWidget {
  final String initialOperation;

  const HistoryDialog({
    super.key,
    this.initialOperation = 'All',
  });

  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  late String _selectedOperation;

  @override
  void initState() {
    super.initState();
    _selectedOperation = widget.initialOperation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryProvider>().refreshHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentProfileId = LocalDbService().currentProfileId;
    final currentProfile = GlobalDbService().profiles.firstWhere(
      (p) => p.id == currentProfileId,
      orElse: () => GlobalDbService().profiles.first,
    );

    final isSpecificScreen = widget.initialOperation != 'All';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.88,
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: AppDecorations.glassCard(context: context),
        child: Column(
          children: [
            // Header
            _buildHeader(context, currentProfile.name, isSpecificScreen),

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

                  final filteredRecords = _filterRecords(provider.records);

                  return Column(
                    children: [
                      // Stats Bar
                      _buildStatsBar(context, provider, filteredRecords, isSpecificScreen),
                      Divider(height: 1, color: context.border),

                      // History Table
                      Expanded(
                        child: filteredRecords.isEmpty
                            ? _buildEmptyState(context)
                            : _buildHistoryTable(context, filteredRecords),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String profileName, bool isSpecificScreen) {
    final title = isSpecificScreen
        ? '${widget.initialOperation} Run History'
        : 'Run History';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.history, color: context.primaryAccent, size: 24),
          const SizedBox(width: 10),
          Text(
            '$title ($profileName)',
            style: TextStyle(
              fontSize: 18,
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
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
            label: const Text(
              'Clear History',
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close, color: context.textMuted),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  List<RunRecord> _filterRecords(List<RunRecord> allRecords) {
    if (_selectedOperation == 'All') {
      return allRecords;
    }
    return allRecords
        .where((r) => r.operation.toLowerCase() == _selectedOperation.toLowerCase())
        .toList();
  }

  Widget _buildStatsBar(BuildContext context, HistoryProvider provider, List<RunRecord> filtered, bool isSpecificScreen) {
    final operations = ['All', 'Transfer', 'Copy', 'Delete', 'Count'];

    int totalFiles = filtered.fold(0, (sum, r) => sum + r.filesProcessed);
    int totalFolders = filtered.fold(0, (sum, r) => sum + r.foldersProcessed);
    int totalErrors = filtered.fold(0, (sum, r) => sum + r.errors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: context.containerBg,
      child: Row(
        children: [
          if (!isSpecificScreen)
            Wrap(
              spacing: 8,
              children: operations.map((op) {
                final isSelected = _selectedOperation == op;
                return ChoiceChip(
                  label: Text(op),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedOperation = op;
                      });
                    }
                  },
                  selectedColor: context.primaryAccent.withValues(alpha: 0.2),
                  backgroundColor: context.cardBg,
                  labelStyle: TextStyle(
                    color: isSelected ? context.primaryAccent : context.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: isSelected ? context.primaryAccent : context.border,
                  ),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            )
          else
            Row(
              children: [
                Icon(
                  _getOpIcon(widget.initialOperation),
                  size: 16,
                  color: _getOpColor(widget.initialOperation, context.isDarkMode),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.initialOperation} Runs Only',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _getOpColor(widget.initialOperation, context.isDarkMode),
                  ),
                ),
              ],
            ),
          const Spacer(),
          _buildSummaryBadge(context, 'Total Runs', filtered.length.toString(), context.isDarkMode ? AppColors.info : const Color(0xFF0284C7)),
          const SizedBox(width: 8),
          _buildSummaryBadge(context, 'Files Processed', NumberFormat('#,##0').format(totalFiles), context.isDarkMode ? AppColors.success : const Color(0xFF16A34A)),
          if (totalFolders > 0) ...[
            const SizedBox(width: 8),
            _buildSummaryBadge(context, 'Folders', NumberFormat('#,##0').format(totalFolders), context.primaryAccent),
          ],
          const SizedBox(width: 8),
          _buildSummaryBadge(context, 'Errors', NumberFormat('#,##0').format(totalErrors), totalErrors > 0 ? AppColors.error : context.textMuted),
        ],
      ),
    );
  }

  Widget _buildSummaryBadge(BuildContext context, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 11, color: context.textMuted),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_toggle_off, size: 48, color: context.textMuted),
          const SizedBox(height: 12),
          Text(
            'No history records found for $_selectedOperation',
            style: TextStyle(color: context.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTable(BuildContext context, List<RunRecord> records) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');
    final isDark = context.isDarkMode;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? AppColors.bgDark2 : const Color(0xFFE2E8F0),
          ),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 68,
          horizontalMargin: 16,
          columnSpacing: 20,
          columns: [
            DataColumn(
              label: Text(
                'Status / Op',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
              ),
            ),
            DataColumn(
              label: Text(
                'Start - End Time',
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
                'Source / Target Directory',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.textSecondary, fontSize: 12),
              ),
            ),
            DataColumn(
              label: Text(
                'Destination Directory',
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
                ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m ${duration.inSeconds.remainder(60)}s'
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
                // Status / Op
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(opIcon, color: opColor, size: 16),
                      const SizedBox(width: 6),
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
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Start - End Time
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateFormat.format(record.startTime),
                        style: TextStyle(fontSize: 11, color: context.textPrimary),
                      ),
                      Text(
                        'to ${DateFormat('HH:mm:ss').format(record.endTime)}',
                        style: TextStyle(fontSize: 10, color: context.textMuted),
                      ),
                    ],
                  ),
                ),
                // Duration
                DataCell(
                  Text(
                    durationStr,
                    style: TextStyle(fontSize: 11, color: context.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ),
                // Source / Target
                DataCell(
                  SizedBox(
                    width: 200,
                    child: Text(
                      record.sourcePath ?? '-',
                      style: TextStyle(fontSize: 11, fontFamily: 'Consolas', color: context.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                // Dest Path
                DataCell(
                  SizedBox(
                    width: 200,
                    child: Text(
                      record.destPath ?? '-',
                      style: TextStyle(fontSize: 11, fontFamily: 'Consolas', color: context.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                // Files Count
                DataCell(
                  Text(
                    NumberFormat('#,##0').format(record.filesProcessed),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textPrimary),
                  ),
                ),
                // Folders Count
                DataCell(
                  Text(
                    NumberFormat('#,##0').format(record.foldersProcessed),
                    style: TextStyle(fontSize: 11, color: context.textSecondary),
                  ),
                ),
                // Errors
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
          'Are you sure you want to clear history records? This cannot be undone.',
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
