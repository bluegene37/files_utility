import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/count_files_provider.dart';
import '../theme/app_theme.dart';

class CountFilesScreen extends StatelessWidget {
  const CountFilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CountFilesProvider>(context);

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
                      decoration: AppDecorations.glassCard(glowColor: AppColors.success),
                      padding: const EdgeInsets.all(16.0),
                      child: PathRow(
                        label: 'Target Folder',
                        path: provider.targetPath,
                        onPick: provider.isCounting ? null : provider.pickTarget,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Actions, Status, and Stats
                    Row(
                      children: [
                        if (!provider.isCounting) ...[
                          ElevatedButton.icon(
                            onPressed: provider.targetPath != null
                                ? provider.startCounting
                                : null,
                            icon: const Icon(Icons.analytics_rounded),
                            label: const Text('Count Files'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: provider.clearLogs,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Clear'),
                          ),
                        ] else
                          ElevatedButton.icon(
                            onPressed: provider.stop,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        const SizedBox(width: 16),

                        // Progress indicator
                        if (provider.isCounting)
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.only(right: 8),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.success),
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
                          title: 'Files',
                          value: provider.totalFiles.toString(),
                          color: AppColors.success,
                          icon: Icons.insert_drive_file,
                        ),
                        const SizedBox(width: 8),
                        StatBadge(
                          title: 'Folders',
                          value: provider.totalFolders.toString(),
                          color: AppColors.info,
                          icon: Icons.folder,
                        ),
                        const SizedBox(width: 8),
                        StatBadge(
                          title: 'Errors',
                          value: provider.errors.toString(),
                          color: AppColors.error,
                          icon: Icons.error,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Logs
                    Expanded(
                      child: LogConsole(logs: provider.logs),
                    ),
                  ],
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
          const Icon(Icons.analytics_rounded, color: AppColors.success, size: 22),
          const SizedBox(width: 10),
          const Text(
            'Count Files',
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
}
