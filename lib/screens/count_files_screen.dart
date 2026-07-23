import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/count_files_provider.dart';
import '../theme/app_theme.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';
import '../widgets/history_dialog.dart';
import '../widgets/theme_toggle_button.dart';
import '../services/window_service.dart';

class CountFilesScreen extends StatelessWidget {
  const CountFilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CountFilesProvider>(context);
    WindowService().updateTitle(
      'Count Files',
      status: provider.isCounting ? provider.currentStatus : null,
    );

    return Scaffold(
      body: Container(
        decoration: AppDecorations.gradientBackground(context),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PathRow(
                            label: 'Target Folder',
                            path: provider.targetPath,
                            onPick: provider.isCounting ? null : provider.pickTarget,
                            onChanged: provider.isCounting ? null : provider.setTargetPath,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                'Log Every',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 80,
                                child: DropdownButtonFormField<int>(
                                  isExpanded: true,
                                  initialValue: provider.logInterval,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                  ),
                                  dropdownColor: AppColors.bgDark2,
                                  items: [1, 5, 10, 25, 50, 100].map((int value) {
                                    return DropdownMenuItem<int>(
                                      value: value,
                                      child: Text(
                                        value.toString(),
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: provider.isCounting
                                      ? null
                                      : (val) {
                                          if (val != null) {
                                            provider.setLogInterval(val);
                                          }
                                        },
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'files',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(
                                Icons.info_outline,
                                size: 14,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Text(
                                  'Controls how often progress is logged to the console (larger numbers run faster)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                              StatBadge(
                                title: 'History',
                                value: 'View',
                                color: AppColors.accent,
                                icon: Icons.history,
                                onTap: () => showHistoryDialog(context, initialOperation: 'Count'),
                              ),
                            ],
                          ),
                        ],
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
            icon: Icon(Icons.arrow_back_rounded, color: context.primaryAccent),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Icon(Icons.analytics_rounded, color: context.isDarkMode ? AppColors.success : const Color(0xFF16A34A), size: 22),
          const SizedBox(width: 10),
          Text(
            'Count Files (${currentProfile.name})',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const Spacer(),
          const ThemeToggleButton(),
        ],
      ),
    );
  }
}
