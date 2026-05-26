import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/file_process_provider.dart';
import '../theme/app_theme.dart';

class TransferScreen extends StatelessWidget {
  const TransferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<FileProcessProvider>(context);

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
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    // Config Section
                    Container(
                      decoration: AppDecorations.glassCard(glowColor: AppColors.accent),
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 250,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Client Name',
                                  ),
                                  child: Text(
                                    provider.clientName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
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
                                        style: const TextStyle(color: AppColors.textPrimary),
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
                                        final isSelected = provider.validMonths.contains(m);
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
                          const SizedBox(height: 10),
                          // Run Time row
                          IntrinsicHeight(
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24, height: 24,
                                  child: Checkbox(
                                    value: provider.enableTimeWindow,
                                    onChanged: provider.isProcessing ? null : (val) => provider.setEnableTimeWindow(val ?? false),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text('Run Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary)),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 100,
                                  child: StyledTimePicker(
                                    label: 'From',
                                    time: provider.runFromTime,
                                    enabled: !provider.isProcessing && provider.enableTimeWindow,
                                    onPicked: provider.isProcessing ? (time) {} : (time) => provider.setRunFromTime(time),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 100,
                                  child: StyledTimePicker(
                                    label: 'To',
                                    time: provider.runToTime,
                                    enabled: !provider.isProcessing && provider.enableTimeWindow,
                                    onPicked: provider.isProcessing ? (time) {} : (time) => provider.setRunToTime(time),
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
                                      for (final entry in {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'}.entries)
                                        FilterChip(
                                          label: Text(entry.value, style: const TextStyle(fontSize: 11)),
                                          selected: provider.runDays[entry.key] ?? false,
                                          onSelected: provider.isProcessing
                                              ? null
                                              : (val) => provider.setRunDay(entry.key, val),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // When Complete row
                          Row(
                            children: [
                              const SizedBox(width: 30),
                              const Text('When Complete', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary)),
                              const SizedBox(width: 12),
                              ToggleButtons(
                                isSelected: [
                                  provider.onCompletionAction == 'pause',
                                  provider.onCompletionAction == 'stop',
                                ],
                                onPressed: provider.isProcessing ? null : (index) {
                                  provider.setOnCompletionAction(index == 0 ? 'pause' : 'stop');
                                },
                                borderRadius: BorderRadius.circular(8),
                                constraints: const BoxConstraints(minHeight: 30, minWidth: 80),
                                children: const [
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.pause_circle_outline, size: 16),
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
                                        Icon(Icons.stop_circle_outlined, size: 16),
                                        SizedBox(width: 4),
                                        Text('Stop'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Text(
                                provider.onCompletionAction == 'pause'
                                    ? 'Will re-run at the next start time'
                                    : 'Will stop after completion',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ],
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
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
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
          const Icon(Icons.move_to_inbox_rounded, color: AppColors.accent, size: 22),
          const SizedBox(width: 10),
          const Text(
            'Transfer Files',
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
