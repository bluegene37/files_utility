import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/copy_files_provider.dart';
import '../theme/app_theme.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';
import '../widgets/history_dialog.dart';
import '../widgets/theme_toggle_button.dart';
import '../services/window_service.dart';

class CopyFilesScreen extends StatelessWidget {
  const CopyFilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CopyFilesProvider>(context);
    WindowService().updateTitle(
      'Copy Files',
      status: provider.isProcessing ? provider.currentStatus : null,
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
                    Flexible(
                      flex: 0,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        child: SingleChildScrollView(
                          child: Container(
                            decoration: AppDecorations.glassCard(
                              glowColor: AppColors.info,
                            ),
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Multiple Directories toggle
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: provider.useMultipleDirectories,
                                        onChanged: provider.isProcessing
                                            ? null
                                            : (val) => provider
                                                  .setUseMultipleDirectories(
                                                    val ?? false,
                                                  ),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Multiple Directories',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (!provider.useMultipleDirectories) ...[
                                  PathRow(
                                    label: 'Source',
                                    path: provider.sourcePath,
                                    onPick: provider.isProcessing
                                        ? null
                                        : provider.pickSource,
                                    onChanged: provider.isProcessing
                                        ? null
                                        : provider.setSourcePath,
                                  ),
                                  const SizedBox(height: 8),
                                  PathRow(
                                    label: 'Destination',
                                    path: provider.destPath,
                                    onPick: provider.isProcessing
                                        ? null
                                        : provider.pickDest,
                                    onChanged: provider.isProcessing
                                        ? null
                                        : provider.setDestPath,
                                  ),
                                ] else ...[
                                  // Multi-pair mode
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.folder_copy,
                                        size: 18,
                                        color: AppColors.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${provider.directoryPairs.length} pair${provider.directoryPairs.length == 1 ? '' : 's'} configured',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton.icon(
                                        onPressed: provider.isProcessing
                                            ? null
                                            : () => _showDirectoryPairsDialog(
                                                context,
                                                provider,
                                              ),
                                        icon: const Icon(Icons.edit, size: 16),
                                        label: const Text(
                                          'Edit Pairs',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                // Advanced Settings & Log Interval on the same line
                                Row(
                                  children: [
                                    OutlinedButton.icon(
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
                                    const SizedBox(width: 16),
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
                                        items: [1, 5, 10, 25, 50, 100].map((
                                          int value,
                                        ) {
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
                                        onChanged: provider.isProcessing
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
                                        'Controls how often progress is logged to the console',
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
                                      onTap: () => showHistoryDialog(context, initialOperation: 'Copy'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Actions, Status, and Stats
                    Row(
                      children: [
                        if (!provider.isProcessing) ...[
                          ElevatedButton.icon(
                            onPressed: provider.useMultipleDirectories
                                ? (provider.directoryPairs.any(
                                        (p) =>
                                            p.sourcePath != null &&
                                            p.destPath != null,
                                      )
                                      ? provider.startProcessing
                                      : null)
                                : (provider.sourcePath != null &&
                                      provider.destPath != null)
                                ? provider.startProcessing
                                : null,
                            icon: const Icon(Icons.copy),
                            label: Text(
                              provider.hasSavedProgress
                                  ? 'Resume Copying'
                                  : 'Start Copying',
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Clear Progress?'),
                                  content: const Text(
                                    'This will clear saved resume progress. The next run will scan all directories from scratch.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        provider.clearProgress();
                                        Navigator.pop(ctx);
                                      },
                                      child: const Text('Clear'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Clear Progress'),
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
                        if (provider.isProcessing && !provider.isPaused)
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.only(right: 8),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.info,
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
                          title: 'Copied',
                          value: provider.filesCopied.toString(),
                          color: AppColors.info,
                          icon: Icons.file_copy,
                        ),
                        const SizedBox(width: 6),
                        StatBadge(
                          title: 'Exist',
                          value: provider.filesAlreadyExist.toString(),
                          color: AppColors.accent,
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(width: 6),
                        StatBadge(
                          title: 'Skipped',
                          value: provider.filesSkipped.toString(),
                          color: AppColors.textMuted,
                          icon: Icons.skip_next,
                        ),
                        const SizedBox(width: 6),
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
          Icon(Icons.file_copy_rounded, color: context.isDarkMode ? AppColors.info : const Color(0xFF0284C7), size: 22),
          const SizedBox(width: 10),
          Text(
            'Copy Files (${currentProfile.name})',
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

  Widget _buildDatePicker(
    BuildContext context, {
    required String label,
    required DateTime date,
    required bool enabled,
    required ValueChanged<DateTime> onPicked,
  }) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return InkWell(
      onTap: enabled
          ? () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2010),
                lastDate: DateTime(DateTime.now().year + 2),
              );
              if (picked != null) {
                onPicked(picked);
              }
            }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(
              Icons.calendar_today,
              size: 16,
              color: AppColors.textMuted,
            ),
          ),
          child: Text(
            dateFormat.format(date),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
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

  void _showDirectoryPairsDialog(
    BuildContext context,
    CopyFilesProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(
                    Icons.folder_copy,
                    size: 22,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 8),
                  const Text('Directory Pairs', style: TextStyle(fontSize: 18)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'Add Pair',
                      style: TextStyle(fontSize: 13),
                    ),
                    onPressed: () {
                      provider.addDirectoryPair();
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.7,
                height: MediaQuery.of(context).size.height * 0.5,
                child: ListView.separated(
                  itemCount: provider.directoryPairs.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 16,
                    color: AppColors.cardBorder.withValues(alpha: 0.5),
                  ),
                  itemBuilder: (context, i) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Pair ${i + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Run Order:',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 52,
                              height: 28,
                              child: DropdownButton<int>(
                                value: provider.directoryPairs[i].runOrder,
                                isDense: true,
                                dropdownColor: AppColors.bgDark2,
                                underline: Container(
                                  height: 1,
                                  color: AppColors.cardBorder,
                                ),
                                items: List.generate(10, (n) => n + 1)
                                    .map(
                                      (v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(
                                          '$v',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    provider.setPairRunOrder(i, val);
                                    setDialogState(() {});
                                  }
                                },
                              ),
                            ),
                            const Spacer(),
                            if (provider.directoryPairs.length > 1)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: AppColors.error,
                                ),
                                tooltip: 'Remove pair',
                                onPressed: () {
                                  provider.removeDirectoryPair(i);
                                  setDialogState(() {});
                                },
                              ),
                          ],
                        ),
                        PathRow(
                          label: 'Source',
                          path: provider.directoryPairs[i].sourcePath,
                          onPick: () async {
                            await provider.pickPairSource(i);
                            setDialogState(() {});
                          },
                          onChanged: (val) {
                            provider.setPairSource(i, val);
                            setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 4),
                        PathRow(
                          label: 'Dest',
                          path: provider.directoryPairs[i].destPath,
                          onPick: () async {
                            await provider.pickPairDest(i);
                            setDialogState(() {});
                          },
                          onChanged: (val) {
                            provider.setPairDest(i, val);
                            setDialogState(() {});
                          },
                        ),
                      ],
                    );
                  },
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
        );
      },
    );
  }

  void _showAdvancedSettingsDialog(
    BuildContext context,
    CopyFilesProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ChangeNotifierProvider<CopyFilesProvider>.value(
          value: provider,
          child: Consumer<CopyFilesProvider>(
            builder: (context, provider, child) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.settings, size: 22, color: AppColors.info),
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
                        // Date range and Age filter
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Date Range Section
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: provider.enableDateRange,
                                        onChanged: provider.isProcessing
                                            ? null
                                            : (val) =>
                                                  provider.setEnableDateRange(
                                                    val ?? false,
                                                  ),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Date Range',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  width: 140,
                                  child: _buildDatePicker(
                                    context,
                                    label: 'From',
                                    date: provider.fromDate,
                                    enabled:
                                        !provider.isProcessing &&
                                        provider.enableDateRange,
                                    onPicked: provider.isProcessing
                                        ? (date) {}
                                        : (date) => provider.setFromDate(date),
                                  ),
                                ),
                                SizedBox(
                                  width: 140,
                                  child: _buildDatePicker(
                                    context,
                                    label: 'To',
                                    date: provider.toDate,
                                    enabled:
                                        !provider.isProcessing &&
                                        provider.enableDateRange,
                                    onPicked: provider.isProcessing
                                        ? (date) {}
                                        : (date) => provider.setToDate(date),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: provider.todayOnly,
                                        onChanged: provider.isProcessing
                                            ? null
                                            : (val) => provider.setTodayOnly(
                                                val ?? false,
                                              ),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Today',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: provider.yesterdayOnly,
                                        onChanged: provider.isProcessing
                                            ? null
                                            : (val) =>
                                                  provider.setYesterdayOnly(
                                                    val ?? false,
                                                  ),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Yesterday',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(
                              color: AppColors.cardBorder,
                              thickness: 1,
                            ),
                            const SizedBox(height: 8),
                            // Age filter section
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: provider.enableAgeFilter,
                                        onChanged: provider.isProcessing
                                            ? null
                                            : (val) =>
                                                  provider.setEnableAgeFilter(
                                                    val ?? false,
                                                  ),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Older than',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  width: 100,
                                  child: DropdownButtonFormField<int>(
                                    isExpanded: true,
                                    initialValue: provider.ageFilterValue,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                    ),
                                    dropdownColor: AppColors.bgDark2,
                                    items:
                                        List.generate(
                                          31,
                                          (index) => index + 1,
                                        ).map((int value) {
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
                                    onChanged:
                                        (!provider.isProcessing &&
                                            provider.enableAgeFilter)
                                        ? (val) {
                                            if (val != null) {
                                              provider.setAgeFilterValue(val);
                                            }
                                          }
                                        : null,
                                  ),
                                ),
                                SizedBox(
                                  width: 130,
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: provider.ageFilterUnit,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                    ),
                                    dropdownColor: AppColors.bgDark2,
                                    items: ['Days', 'Months', 'Years'].map((
                                      String value,
                                    ) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Text(
                                          value,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged:
                                        (!provider.isProcessing &&
                                            provider.enableAgeFilter)
                                        ? (val) {
                                            if (val != null) {
                                              provider.setAgeFilterUnit(val);
                                            }
                                          }
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(
                          color: AppColors.cardBorder,
                          thickness: 1,
                        ),
                        const SizedBox(height: 8),
                        // ── Schedule ──
                        _sectionLabel('⏰ Schedule'),
                        const SizedBox(height: 8),
                        // Run time
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: provider.enableTimeWindow,
                                  onChanged: provider.isProcessing
                                      ? null
                                      : (val) => provider.setEnableTimeWindow(
                                          val ?? false,
                                        ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Run Time',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 100,
                                child: StyledTimePicker(
                                  label: 'From',
                                  time: provider.runFromTime,
                                  enabled:
                                      !provider.isProcessing &&
                                      provider.enableTimeWindow,
                                  onPicked: provider.isProcessing
                                      ? (time) {}
                                      : (time) => provider.setRunFromTime(time),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 100,
                                child: StyledTimePicker(
                                  label: 'To',
                                  time: provider.runToTime,
                                  enabled:
                                      !provider.isProcessing &&
                                      provider.enableTimeWindow,
                                  onPicked: provider.isProcessing
                                      ? (time) {}
                                      : (time) => provider.setRunToTime(time),
                                ),
                              ),
                              if (provider.enableTimeWindow) ...[
                                const SizedBox(width: 16),
                                const VerticalDivider(width: 1, thickness: 1),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children: [
                                      for (final entry in {
                                        1: 'Mon',
                                        2: 'Tue',
                                        3: 'Wed',
                                        4: 'Thu',
                                        5: 'Fri',
                                        6: 'Sat',
                                        7: 'Sun',
                                      }.entries)
                                        FilterChip(
                                          label: Text(
                                            entry.value,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                          selected:
                                              provider.runDays[entry.key] ??
                                              false,
                                          onSelected: provider.isProcessing
                                              ? null
                                              : (val) => provider.setRunDay(
                                                  entry.key,
                                                  val,
                                                ),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(
                          color: AppColors.cardBorder,
                          thickness: 1,
                        ),
                        const SizedBox(height: 8),
                        // ── Completion ──
                        _sectionLabel('✅ Completion'),
                        const SizedBox(height: 8),
                        // Completion action
                        Row(
                          children: [
                            const Text(
                              'When Complete',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            ToggleButtons(
                              isSelected: [
                                provider.onCompletionAction == 'pause',
                                provider.onCompletionAction == 'stop',
                              ],
                              onPressed: provider.isProcessing
                                  ? null
                                  : (index) {
                                      provider.setOnCompletionAction(
                                        index == 0 ? 'pause' : 'stop',
                                      );
                                    },
                              borderRadius: BorderRadius.circular(8),
                              constraints: const BoxConstraints(
                                minHeight: 30,
                                minWidth: 80,
                              ),
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.pause_circle_outline,
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text('Pause'),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.stop_circle_outlined,
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text('Stop'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                provider.onCompletionAction == 'pause'
                                    ? 'Will re-run at the next start time'
                                    : 'Will stop after completion',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                  fontStyle: FontStyle.italic,
                                ),
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
