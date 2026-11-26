import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/count_files_provider.dart';
import '../theme/app_theme.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';
import '../widgets/history_dialog.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/help_shortcut_wrapper.dart';
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

    return HelpShortcutWrapper(
      topicId: 'count_files',
      child: Scaffold(
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
                      //                       Container(
                      //                         decoration: AppDecorations.glassCard(
                      //                           context: context,
                      //                           glowColor: AppColors.success,
                      //                         ),
                      // Gene - Nov, 22, 2026: Use theme-aware successColor for CountFilesScreen card rim.
                      Container(
                        decoration: AppDecorations.glassCard(
                          context: context,
                          glowColor: context.successColor,
                        ),
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PathRow(
                              label: 'Target Folder',
                              path: provider.targetPath,
                              onPick: provider.isCounting
                                  ? null
                                  : provider.pickTarget,
                              onChanged: provider.isCounting
                                  ? null
                                  : provider.setTargetPath,
                            ),
                            const SizedBox(height: 10),
                            // Gene - Nov, 26, 2026: Added file-type filter checkboxes (All, Images, Documents, Videos, Audio, Archives, Others) and live inclusion/exclusion summary.
                            _buildFileTypeFilterSection(context, provider),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  'Log Every',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: context.textSecondary,
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
                                    dropdownColor: context.cardBg,
                                    items: [1, 5, 10, 25, 50, 100].map((
                                      int value,
                                    ) {
                                      return DropdownMenuItem<int>(
                                        value: value,
                                        child: Text(
                                          value.toString(),
                                          style: TextStyle(
                                            color: context.textPrimary,
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
                                Text(
                                  'files',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: context.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Controls how often progress is logged to the console (larger numbers run faster)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.textMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                //                                 StatBadge(
                                //                                   title: 'History',
                                //                                   value: 'View',
                                //                                   color: AppColors.accent,
                                //                                   icon: Icons.history,
                                //                                   onTap: () => showHistoryDialog(
                                //                                     context,
                                //                                     initialOperation: 'Count',
                                //                                   ),
                                //                                 ),
                                // Gene - Nov, 22, 2026: Use theme-aware successColor for Count History StatBadge.
                                StatBadge(
                                  title: 'History',
                                  value: 'View',
                                  color: context.successColor,
                                  icon: Icons.history,
                                  onTap: () => showHistoryDialog(
                                    context,
                                    initialOperation: 'Count',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Gene - Nov, 26, 2026: Responsive Wrap with Get Folder Size button and live Size StatBadge.
                      //                       // Actions, Status, and Stats
                      //                       Row(
                      //                         children: [
                      //                           if (!provider.isCounting) ...[
                      //                             // ElevatedButton.icon(
                      //                             //   onPressed: provider.targetPath != null
                      //                             //       ? provider.startCounting
                      //                             //       : null,
                      //                             //   icon: const Icon(Icons.analytics_rounded),
                      //                             //   label: const Text('Count Files'),
                      //                             // ),
                      //                             // Gene - Nov, 26, 2026: Require both targetPath and at least one selected category before counting.
                      //                             ElevatedButton.icon(
                      //                               onPressed: provider.canStartCounting
                      //                                   ? provider.startCounting
                      //                                   : null,
                      //                               icon: const Icon(Icons.analytics_rounded),
                      //                               label: const Text('Count Files'),
                      //                             ),
                      //                             const SizedBox(width: 10),
                      //                             OutlinedButton.icon(
                      //                               onPressed: provider.clearLogs,
                      //                               icon: const Icon(Icons.refresh),
                      //                               label: const Text('Clear'),
                      //                             ),
                      //                           ] else
                      //                             ElevatedButton.icon(
                      //                               onPressed: provider.stop,
                      //                               icon: const Icon(Icons.stop),
                      //                               label: const Text('Stop'),
                      //                               style: ElevatedButton.styleFrom(
                      //                                 backgroundColor: AppColors.error,
                      //                                 foregroundColor: Colors.white,
                      //                               ),
                      //                             ),
                      //                           const SizedBox(width: 16),
                      //
                      //                           // Gene - Nov, 22, 2026: Replaced hardcoded spinner and stat badge colors in CountFilesScreen with theme-aware getters.
                      //                           // Progress indicator
                      //                           if (provider.isCounting)
                      //                             Container(
                      //                               width: 14,
                      //                               height: 14,
                      //                               margin: const EdgeInsets.only(right: 8),
                      //                               child: CircularProgressIndicator(
                      //                                 strokeWidth: 2,
                      //                                 valueColor: AlwaysStoppedAnimation<Color>(
                      //                                   context.successColor,
                      //                                 ),
                      //                               ),
                      //                             ),
                      //
                      //                           // Status
                      //                           // Gene - Nov, 25, 2026: Wrap Count status text in Tooltip to show full live scanning counter and folder name.
                      //                           Expanded(
                      //                             child: Tooltip(
                      //                               message: provider.currentStatus,
                      //                               child: Text(
                      //                                 provider.currentStatus,
                      //                                 style: TextStyle(
                      //                                   fontWeight: FontWeight.w600,
                      //                                   color: context.textPrimary,
                      //                                   fontSize: 13,
                      //                                 ),
                      //                                 maxLines: 1,
                      //                                 overflow: TextOverflow.ellipsis,
                      //                               ),
                      //                             ),
                      //                           ),
                      //                           const SizedBox(width: 8),
                      //
                      //                           // Stats
                      //                           StatBadge(
                      //                             title: 'Files',
                      //                             value: provider.totalFiles.toString(),
                      //                             color: context.successColor,
                      //                             icon: Icons.insert_drive_file,
                      //                           ),
                      //                           // Gene - Nov, 26, 2026: Show live Excluded count badge whenever any category is unchecked or files are excluded.
                      //                           if (!provider.allCategoriesSelected ||
                      //                               provider.excludedFiles > 0) ...[
                      //                             const SizedBox(width: 8),
                      //                             StatBadge(
                      //                               title: 'Excluded',
                      //                               value: provider.excludedFiles.toString(),
                      //                               color: context.warningColor,
                      //                               icon: Icons.filter_alt_off_rounded,
                      //                             ),
                      //                           ],
                      //                           const SizedBox(width: 8),
                      //                           StatBadge(
                      //                             title: 'Folders',
                      //                             value: provider.totalFolders.toString(),
                      //                             color: context.infoColor,
                      //                             icon: Icons.folder,
                      //                           ),
                      //                           const SizedBox(width: 8),
                      //                           StatBadge(
                      //                             title: 'Errors',
                      //                             value: provider.errors.toString(),
                      //                             color: context.errorColor,
                      //                             icon: Icons.error,
                      //                           ),
                      //                         ],
                      //                       ),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!provider.isCounting) ...[
                                  ElevatedButton.icon(
                                    onPressed: provider.canStartCounting
                                        ? provider.startCounting
                                        : null,
                                    icon: const Icon(Icons.analytics_rounded),
                                    label: const Text('Count Files'),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message:
                                        'Calculate total size of the target folder (all files, skips per-file logging)',
                                    child: OutlinedButton.icon(
                                      key: const Key('count_get_folder_size_btn'),
                                      onPressed: provider.canGetFolderSize
                                          ? provider.startFolderSize
                                          : null,
                                      icon: const Icon(
                                        Icons.storage_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Get Folder Size'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
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
                                const SizedBox(width: 12),
                                if (provider.isCounting)
                                  Container(
                                    width: 14,
                                    height: 14,
                                    margin: const EdgeInsets.only(right: 8),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        context.successColor,
                                      ),
                                    ),
                                  ),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 280,
                                  ),
                                  child: Tooltip(
                                    message: provider.currentStatus,
                                    child: Text(
                                      provider.currentStatus,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: context.textPrimary,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                StatBadge(
                                  title: 'Files',
                                  value: provider.totalFiles.toString(),
                                  color: context.successColor,
                                  icon: Icons.insert_drive_file,
                                ),
                                if (!provider.isSizeOnlyRun &&
                                    (!provider.allCategoriesSelected ||
                                        provider.excludedFiles > 0))
                                  StatBadge(
                                    title: 'Excluded',
                                    value: provider.excludedFiles.toString(),
                                    color: context.warningColor,
                                    icon: Icons.filter_alt_off_rounded,
                                  ),
                                StatBadge(
                                  title: 'Folders',
                                  value: provider.totalFolders.toString(),
                                  color: context.infoColor,
                                  icon: Icons.folder,
                                ),
                                Tooltip(
                                  message: '${provider.totalBytes} bytes',
                                  child: StatBadge(
                                    key: const Key('count_size_badge'),
                                    title: 'Size',
                                    value: provider.formattedTotalSize,
                                    color: context.primaryAccent,
                                    icon: Icons.storage_rounded,
                                  ),
                                ),
                                StatBadge(
                                  title: 'Errors',
                                  value: provider.errors.toString(),
                                  color: context.errorColor,
                                  icon: Icons.error,
                                ),
                              ],
                            ),
                          ],
                        ),
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
          //           Icon(
          //             Icons.analytics_rounded,
          //             color: context.isDarkMode
          //                 ? AppColors.success
          //                 : const Color(0xFF16A34A),
          //             size: 22,
          //           ),
          // Gene - Nov, 22, 2026: Use theme-aware successColor for CountFilesScreen app bar icon.
          Icon(Icons.analytics_rounded, color: context.successColor, size: 22),
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
          const HelpManualButton(topicId: 'count_files'),
          const SizedBox(width: 4),
          const ThemeToggleButton(),
        ],
      ),
    );
  }

  // Gene - Nov, 26, 2026: Built compact file-type filter checkboxes (All + categories) and live summary line.
  Widget _buildFileTypeFilterSection(
    BuildContext context,
    CountFilesProvider provider,
  ) {
    final bool? allValue = provider.allCategoriesSelected
        ? true
        : (provider.hasAnyCategorySelected ? null : false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Count:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: context.textSecondary,
              ),
            ),
            _buildFilterCheckbox(
              context,
              checkboxKey: const Key('count_filter_all'),
              label: 'All',
              tooltip: 'Include or exclude all file types',
              value: allValue,
              tristate: true,
              enabled: !provider.isCounting,
              onChanged: () => provider.toggleAllCategories(),
            ),
            Container(width: 1, height: 18, color: context.border),
            for (final category in CountFileCategory.values)
              _buildFilterCheckbox(
                context,
                checkboxKey: Key('count_filter_${category.id}'),
                label: category.label,
                tooltip: '${category.label}: ${category.extensionsHint}',
                value: provider.isCategorySelected(category),
                enabled: !provider.isCounting,
                onChanged: () => provider.toggleCategory(category),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (provider.allCategoriesSelected)
          Text(
            'Counting all file types (nothing excluded)',
            style: TextStyle(
              fontSize: 11,
              color: context.textMuted,
              fontStyle: FontStyle.italic,
            ),
          )
        else if (!provider.hasAnyCategorySelected)
          Text(
            'Select at least one file type to count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.warningColor,
            ),
          )
        else
          Tooltip(
            message:
                'Counting: ${provider.filterSummary}  •  Excluding: ${provider.excludedSummary}',
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 11),
                children: [
                  TextSpan(
                    text: 'Counting: ${provider.filterSummary}',
                    style: TextStyle(
                      color: context.successColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: '  •  Excluding: ${provider.excludedSummary}',
                    style: TextStyle(color: context.textMuted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _buildFilterCheckbox(
    BuildContext context, {
    required Key checkboxKey,
    required String label,
    required String tooltip,
    required bool? value,
    bool tristate = false,
    required bool enabled,
    required VoidCallback onChanged,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onChanged : null,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  key: checkboxKey,
                  value: value,
                  tristate: tristate,
                  onChanged: enabled ? (_) => onChanged() : null,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: enabled ? context.textPrimary : context.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
