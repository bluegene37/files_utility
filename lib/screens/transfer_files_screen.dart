import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/transfer_files_provider.dart';
import '../theme/app_theme.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';

class TransferFilesScreen extends StatelessWidget {
  const TransferFilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransferFilesProvider>(context);

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
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
                              glowColor: AppColors.accent,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 12.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PathRow(
                                  label: 'Source',
                                  path: provider.sourcePath,
                                  onPick: provider.pickSource,
                                  onChanged: provider.setSourcePath,
                                ),
                                const SizedBox(height: 8),
                                PathRow(
                                  label: 'Destination',
                                  path: provider.destPath,
                                  onPick: provider.pickDest,
                                  onChanged: provider.setDestPath,
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _showAdvancedSettingsDialog(
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
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Actions, Status, and Stats
                    Row(
                      children: [
                        if (!provider.isProcessing) ...[
                          ElevatedButton.icon(
                            onPressed:
                                (provider.sourcePath != null &&
                                    provider.destPath != null)
                                ? provider.startProcessing
                                : null,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Start'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Clear Progress?'),
                                  content: const Text(
                                    'This will reset the resume checkpoint. Are you sure?',
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
                            icon: const Icon(Icons.stop, size: 18),
                            label: const Text('Stop'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        const SizedBox(width: 16),
                        // Status
                        if (provider.isProcessing && !provider.isPaused)
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.only(right: 8),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.accent,
                              ),
                            ),
                          ),
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
                        StatBadge(
                          title: 'Moved',
                          value: provider.filesMoved.toString(),
                          color: AppColors.success,
                          icon: Icons.check_circle,
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
                    const SizedBox(height: 8),

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
            Icons.move_to_inbox_rounded,
            color: AppColors.accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(
            'Transfer Files (${currentProfile.name})',
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

  void _showAdvancedSettingsDialog(
    BuildContext context,
    TransferFilesProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ChangeNotifierProvider<TransferFilesProvider>.value(
          value: provider,
          child: Consumer<TransferFilesProvider>(
            builder: (context, provider, child) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.settings, size: 22, color: AppColors.accent),
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
                        // ── Scan Options ──
                        _sectionLabel('📁 Scan Options'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: provider.excludeSubfolders,
                                onChanged: provider.isProcessing
                                    ? null
                                    : (val) => provider.setExcludeSubfolders(
                                          val ?? false,
                                        ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Source folder only',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                provider.excludeSubfolders
                                    ? 'Only files directly in the source folder will be scanned'
                                    : 'All files including subfolders will be scanned',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(
                          color: AppColors.cardBorder,
                          thickness: 1,
                        ),
                        const SizedBox(height: 8),
                        // ── File Date Filter ──
                        _sectionLabel('📅 File Date Filter'),
                        const SizedBox(height: 8),
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
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(
                          color: AppColors.cardBorder,
                          thickness: 1,
                        ),
                        const SizedBox(height: 8),
                        // Age filter
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
                                        : (val) => provider.setEnableAgeFilter(
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
                                items: List.generate(31, (index) => index + 1)
                                    .map((int value) {
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
                                    })
                                    .toList(),
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
                        const SizedBox(height: 12),
                        const Divider(
                          color: AppColors.cardBorder,
                          thickness: 1,
                        ),
                        const SizedBox(height: 8),
                        // ── Schedule ──
                        _sectionLabel('⏰ Schedule'),
                        const SizedBox(height: 8),
                        // Run Time row
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
                                          style: const TextStyle(fontSize: 11),
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
                        // When Complete row
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
