import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/delete_files_provider.dart';
import '../theme/app_theme.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';

class DeleteFilesScreen extends StatelessWidget {
  const DeleteFilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DeleteFilesProvider>(context);

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
                child: Column(
                  children: [
                    // Config Section
                    Container(
                      decoration: AppDecorations.glassCard(
                        glowColor: AppColors.error,
                      ),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PathRow(
                            label: 'Target Folder',
                            path: provider.targetPath,
                            onPick: provider.pickTarget,
                            onChanged: provider.setTargetPath,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => _showAdvancedSettingsDialog(
                                context,
                                provider,
                              ),
                              icon: const Icon(
                                Icons.settings,
                                size: 16,
                                color: AppColors.accent,
                              ),
                              label: const Text(
                                'Advanced Settings',
                                style: TextStyle(color: AppColors.accent),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: AppColors.cardBorder,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Actions, Status, and Stats
                    Row(
                      children: [
                        if (!provider.isProcessing) ...[
                          ElevatedButton.icon(
                            onPressed: provider.targetPath != null
                                ? () =>
                                      _showDeleteConfirmation(context, provider)
                                : null,
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Delete All'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: provider.clearLogs,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Clear Logs'),
                          ),
                        ] else
                          ElevatedButton.icon(
                            onPressed: provider.stop,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        const SizedBox(width: 16),

                        // Progress indicator
                        if (provider.isProcessing)
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.only(right: 8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.error.withValues(alpha: 0.8),
                              ),
                            ),
                          ),

                        // Status
                        Expanded(
                          child: Text(
                            provider.currentStatus,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Stats
                        StatBadge(
                          title: 'Deleted',
                          value: provider.deletedCount.toString(),
                          color: AppColors.error,
                          icon: Icons.delete,
                        ),
                        const SizedBox(width: 8),
                        StatBadge(
                          title: 'Errors',
                          value: provider.errorCount.toString(),
                          color: AppColors.warning,
                          icon: Icons.error_outline,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Logs
                    Expanded(child: LogConsole(logs: provider.logs)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final currentProfileId = LocalDbService().currentProfileId;
    final currentProfile = GlobalDbService().profiles.firstWhere(
      (p) => p.id == currentProfileId,
      orElse: () => GlobalDbService().profiles.first,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.accent),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.delete_forever_rounded,
            color: AppColors.error,
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(
            'Delete Files (${currentProfile.name})',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    DeleteFilesProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            const SizedBox(width: 8),
            const Text('Confirm Deletion'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to delete EVERYTHING inside:',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgDark1,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Text(
                provider.targetPath ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  fontFamily: 'Consolas',
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Filter: Year ${provider.selectedYear}, Months: ${provider.validMonths.join(', ')}',
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: AppColors.error, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'This action cannot be undone!',
                    style: TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.deleteFiles();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _showAdvancedSettingsDialog(
    BuildContext context,
    DeleteFilesProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ChangeNotifierProvider<DeleteFilesProvider>.value(
          value: provider,
          child: Consumer<DeleteFilesProvider>(
            builder: (context, provider, child) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.settings, size: 22, color: AppColors.error),
                    const SizedBox(width: 8),
                    const Text(
                      'Advanced Settings',
                      style: TextStyle(fontSize: 18),
                    ),
                  ],
                ),
                contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                content: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.7,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── File Date Filter ──
                        _sectionLabel('📅 File Date Filter'),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 100,
                              child: DropdownButtonFormField<int>(
                                initialValue: provider.selectedYear,
                                decoration: const InputDecoration(
                                  labelText: 'Year',
                                ),
                                dropdownColor: AppColors.bgDark2,
                                items: provider.availableYears.map((int value) {
                                  return DropdownMenuItem<int>(
                                    value: value,
                                    child: Text(
                                      value.toString(),
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) provider.setYear(val);
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Months:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6.0,
                                    runSpacing: 4.0,
                                    children: provider.allMonths.map((m) {
                                      final isSelected = provider.validMonths
                                          .contains(m);
                                      return FilterChip(
                                        label: Text(m),
                                        selected: isSelected,
                                        onSelected: (bool selected) {
                                          provider.toggleMonth(m);
                                        },
                                        visualDensity: VisualDensity.compact,
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
