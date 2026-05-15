import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/copy_files_provider.dart';

class CopyFilesScreen extends StatelessWidget {
  const CopyFilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CopyFilesProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Copy Files')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Config Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Multiple Directories toggle
                    Row(
                      children: [
                        SizedBox(
                          width: 24, height: 24,
                          child: Checkbox(
                            value: provider.useMultipleDirectories,
                            onChanged: provider.isProcessing ? null : (val) => provider.setUseMultipleDirectories(val ?? false),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('Multiple Directories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!provider.useMultipleDirectories) ...[
                      // Single pair mode
                      _buildPathRow(
                        context,
                        label: 'Source',
                        path: provider.sourcePath,
                        onPick: provider.isProcessing ? null : provider.pickSource,
                      ),
                      const SizedBox(height: 10),
                      _buildPathRow(
                        context,
                        label: 'Destination',
                        path: provider.destPath,
                        onPick: provider.isProcessing ? null : provider.pickDest,
                      ),
                    ] else ...[
                      // Multi-pair mode
                      for (int i = 0; i < provider.directoryPairs.length; i++) ...[
                        Row(
                          children: [
                            Text('Pair ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                            const Spacer(),
                            if (provider.directoryPairs.length > 1 && !provider.isProcessing)
                              SizedBox(
                                width: 28, height: 28,
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => provider.removeDirectoryPair(i),
                                ),
                              ),
                          ],
                        ),
                        _buildPathRow(
                          context,
                          label: 'Source',
                          path: provider.directoryPairs[i].sourcePath,
                          onPick: provider.isProcessing ? null : () => provider.pickPairSource(i),
                        ),
                        const SizedBox(height: 4),
                        _buildPathRow(
                          context,
                          label: 'Dest',
                          path: provider.directoryPairs[i].destPath,
                          onPick: provider.isProcessing ? null : () => provider.pickPairDest(i),
                        ),
                        if (i < provider.directoryPairs.length - 1)
                          const Divider(height: 12),
                      ],
                      if (!provider.isProcessing)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Pair', style: TextStyle(fontSize: 13)),
                            onPressed: provider.addDirectoryPair,
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    // Date range: checkbox + pickers + Today/Yesterday shortcuts
                    Row(
                      children: [
                        SizedBox(
                          width: 24, height: 24,
                          child: Checkbox(
                            value: provider.enableDateRange,
                            onChanged: provider.isProcessing ? null : (val) => provider.setEnableDateRange(val ?? false),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 140,
                          child: _buildDatePicker(
                            context,
                            label: 'From',
                            date: provider.fromDate,
                            enabled: !provider.isProcessing && provider.enableDateRange,
                            onPicked: provider.isProcessing ? (date) {} : (date) => provider.setFromDate(date),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 140,
                          child: _buildDatePicker(
                            context,
                            label: 'To',
                            date: provider.toDate,
                            enabled: !provider.isProcessing && provider.enableDateRange,
                            onPicked: provider.isProcessing ? (date) {} : (date) => provider.setToDate(date),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 24, height: 24,
                          child: Checkbox(
                            value: provider.todayOnly,
                            onChanged: provider.isProcessing ? null : (val) => provider.setTodayOnly(val ?? false),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('Today', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 24, height: 24,
                          child: Checkbox(
                            value: provider.yesterdayOnly,
                            onChanged: provider.isProcessing ? null : (val) => provider.setYesterdayOnly(val ?? false),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('Yesterday', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Run time: checkbox + time pickers + day chips all in one row
                    Row(
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
                        const Text('Run Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: _buildTimePicker(
                            context,
                            label: 'From',
                            time: provider.runFromTime,
                            enabled: !provider.isProcessing && provider.enableTimeWindow,
                            onPicked: provider.isProcessing ? (time) {} : (time) => provider.setRunFromTime(time),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: _buildTimePicker(
                            context,
                            label: 'To',
                            time: provider.runToTime,
                            enabled: !provider.isProcessing && provider.enableTimeWindow,
                            onPicked: provider.isProcessing ? (time) {} : (time) => provider.setRunToTime(time),
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
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Actions, Status, and Stats
            Row(
              children: [
                if (!provider.isProcessing)
                  ElevatedButton.icon(
                    onPressed:
                        (provider.sourcePath != null &&
                            provider.destPath != null)
                        ? provider.startProcessing
                        : null,
                    icon: const Icon(Icons.copy),
                    label: const Text('Start Copying'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: provider.stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                const SizedBox(width: 16),
                
                // Progress / Status
                Expanded(
                  child: Text(
                    provider.currentStatus,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),

                // Stats
                _buildSmallStatCard(
                  'Copied',
                  provider.filesCopied.toString(),
                  Colors.blue,
                  Icons.file_copy,
                ),
                const SizedBox(width: 8),
                _buildSmallStatCard(
                  'Errors',
                  provider.errors.toString(),
                  Colors.red,
                  Icons.error,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Logs
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  reverse: true,
                  itemCount: provider.logs.length,
                  itemBuilder: (context, index) {
                    return Text(
                      provider.logs[index],
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12,
                        color: Colors.lightBlueAccent,
                      ),
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

  Widget _buildDatePicker(
    BuildContext context, {
    required String label,
    required DateTime date,
    required bool enabled,
    required ValueChanged<DateTime> onPicked,
  }) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return InkWell(
      onTap: enabled ? () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2010),
          lastDate: DateTime(DateTime.now().year + 2),
        );
        if (picked != null) {
          onPicked(picked);
        }
      } : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            suffixIcon: const Icon(Icons.calendar_today, size: 16),
          ),
          child: Text(dateFormat.format(date)),
        ),
      ),
    );
  }

  Widget _buildTimePicker(
    BuildContext context, {
    required String label,
    required TimeOfDay time,
    required bool enabled,
    required ValueChanged<TimeOfDay> onPicked,
  }) {
    return InkWell(
      onTap: enabled
          ? () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: time,
              );
              if (picked != null) {
                onPicked(picked);
              }
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            suffixIcon: const Icon(Icons.access_time, size: 16),
          ),
          child: Text(time.format(context)),
        ),
      ),
    );
  }

  Widget _buildSmallStatCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            '$title: $value',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathRow(
    BuildContext context, {
    required String label,
    String? path,
    required VoidCallback? onPick,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              path ?? 'Not Selected',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: path == null ? Colors.grey : Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: onPick, child: const Text('Browse')),
      ],
    );
  }
}
