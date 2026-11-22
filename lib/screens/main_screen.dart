import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../providers/history_provider.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';
import '../models/run_record.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/update_check_button.dart';
import '../widgets/update_gate.dart';
import '../widgets/help_shortcut_wrapper.dart';
import 'transfer_files_screen.dart';
import 'delete_files_screen.dart';
import 'copy_files_screen.dart';
import 'count_files_screen.dart';
// Gene - Nov, 21, 2026: Import FtpFilesScreen for the 5th dashboard card
import 'ftp_files_screen.dart';
import 'history_screen.dart';
import '../services/window_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  Widget build(BuildContext context) {
    WindowService().updateTitle('Main Dashboard');
    final currentProfileId = LocalDbService().currentProfileId;
    final currentProfile = GlobalDbService().profiles.firstWhere(
      (p) => p.id == currentProfileId,
      orElse: () => GlobalDbService().profiles.first,
    );

    return HelpShortcutWrapper(
      topicId: 'getting_started',
      child: UpdateGate(
        child: Scaffold(
          body: Container(
            decoration: AppDecorations.gradientBackground(context),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header & Active Profile Row
                    _buildHeaderAndProfile(context, currentProfile),

                    const SizedBox(height: 16),

                    // // 4 Action Buttons in a Single Line
                    // Row(
                    //   children: [
                    //     Expanded(
                    //       child: _DashboardCard(
                    //         icon: Icons.move_to_inbox_rounded,
                    //         title: 'Transfer Files',
                    //         subtitle: 'Move files by date & filters',
                    //         accentColor: context.primaryAccent,
                    //         onTap: () => _navigateTo(
                    //           context,
                    //           const TransferFilesScreen(),
                    //         ),
                    //       ),
                    //     ),
                    //     const SizedBox(width: 12),
                    //     Expanded(
                    //       child: _DashboardCard(
                    //         icon: Icons.file_copy_rounded,
                    //         title: 'Copy Files',
                    //         subtitle: 'Mirror directories with date range',
                    //         accentColor: context.isDarkMode
                    //             ? const Color(0xFFE2A06E)
                    //             : const Color(0xFFA0582C),
                    //         onTap: () =>
                    //             _navigateTo(context, const CopyFilesScreen()),
                    //       ),
                    //     ),
                    //     const SizedBox(width: 12),
                    //     Expanded(
                    //       child: _DashboardCard(
                    //         icon: Icons.delete_forever_rounded,
                    //         title: 'Delete Files',
                    //         subtitle: 'Remove files matching criteria',
                    //         accentColor: AppColors.error,
                    //         onTap: () =>
                    //             _navigateTo(context, const DeleteFilesScreen()),
                    //       ),
                    //     ),
                    //     const SizedBox(width: 12),
                    //     Expanded(
                    //       child: _DashboardCard(
                    //         icon: Icons.analytics_rounded,
                    //         title: 'Count Files',
                    //         subtitle: 'Audit file & folder totals',
                    //         accentColor: AppColors.success,
                    //         onTap: () =>
                    //             _navigateTo(context, const CountFilesScreen()),
                    //       ),
                    //     ),
                    //   ],
                    // ),
                    //                     // Gene - Nov, 21, 2026: Expanded dashboard action row to 5 cards including FTP Upload
                    //                     Row(
                    //                       children: [
                    //                         Expanded(
                    //                           child: _DashboardCard(
                    //                             icon: Icons.move_to_inbox_rounded,
                    //                             title: 'Transfer Files',
                    //                             subtitle: 'Move files by date & filters',
                    //                             accentColor: context.primaryAccent,
                    //                             onTap: () => _navigateTo(
                    //                               context,
                    //                               const TransferFilesScreen(),
                    //                             ),
                    //                           ),
                    //                         ),
                    //                         const SizedBox(width: 10),
                    //                         Expanded(
                    //                           child: _DashboardCard(
                    //                             icon: Icons.file_copy_rounded,
                    //                             title: 'Copy Files',
                    //                             subtitle: 'Mirror directories with date range',
                    //                             accentColor: context.isDarkMode
                    //                                 ? const Color(0xFFE2A06E)
                    //                                 : const Color(0xFFA0582C),
                    //                             onTap: () =>
                    //                                 _navigateTo(context, const CopyFilesScreen()),
                    //                           ),
                    //                         ),
                    //                         const SizedBox(width: 10),
                    //                         Expanded(
                    //                           child: _DashboardCard(
                    //                             icon: Icons.delete_forever_rounded,
                    //                             title: 'Delete Files',
                    //                             subtitle: 'Remove files matching criteria',
                    //                             accentColor: AppColors.error,
                    //                             onTap: () =>
                    //                                 _navigateTo(context, const DeleteFilesScreen()),
                    //                           ),
                    //                         ),
                    //                         const SizedBox(width: 10),
                    //                         Expanded(
                    //                           child: _DashboardCard(
                    //                             icon: Icons.analytics_rounded,
                    //                             title: 'Count Files',
                    //                             subtitle: 'Audit file & folder totals',
                    //                             accentColor: AppColors.success,
                    //                             onTap: () =>
                    //                                 _navigateTo(context, const CountFilesScreen()),
                    //                           ),
                    //                         ),
                    //                         const SizedBox(width: 10),
                    //                         Expanded(
                    //                           child: _DashboardCard(
                    //                             icon: Icons.cloud_upload_rounded,
                    //                             title: 'FTP Upload',
                    //                             subtitle: 'Upload files to FTP / SFTP',
                    //                             accentColor: context.ftpAccent,
                    //                             onTap: () =>
                    //                                 _navigateTo(context, const FtpFilesScreen()),
                    //                           ),
                    //                         ),
                    //                       ],
                    //                     ),
                    // Gene - Nov, 22, 2026: Unified 5 dashboard card accent colors using theme-aware modern getters and Neumorphic spacing.
                    Row(
                      children: [
                        Expanded(
                          child: _DashboardCard(
                            icon: Icons.move_to_inbox_rounded,
                            title: 'Transfer Files',
                            subtitle: 'Move files by date & filters',
                            accentColor: context.primaryAccent,
                            onTap: () => _navigateTo(
                              context,
                              const TransferFilesScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DashboardCard(
                            icon: Icons.file_copy_rounded,
                            title: 'Copy Files',
                            subtitle: 'Mirror directories with date range',
                            accentColor: context.copyAccent,
                            onTap: () =>
                                _navigateTo(context, const CopyFilesScreen()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DashboardCard(
                            icon: Icons.delete_forever_rounded,
                            title: 'Delete Files',
                            subtitle: 'Remove files matching criteria',
                            accentColor: context.errorColor,
                            onTap: () =>
                                _navigateTo(context, const DeleteFilesScreen()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DashboardCard(
                            icon: Icons.analytics_rounded,
                            title: 'Count Files',
                            subtitle: 'Audit file & folder totals',
                            accentColor: context.successColor,
                            onTap: () =>
                                _navigateTo(context, const CountFilesScreen()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DashboardCard(
                            icon: Icons.cloud_upload_rounded,
                            title: 'FTP Upload',
                            subtitle: 'Upload files to FTP / SFTP',
                            accentColor: context.ftpAccent,
                            onTap: () =>
                                _navigateTo(context, const FtpFilesScreen()),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Expanded History Dashboard at the Bottom
                    Expanded(child: _buildHistoryDashboard(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  //   Widget _buildHeaderAndProfile(BuildContext context, dynamic currentProfile) {
  //     return Row(
  //       children: [
  //         Container(
  //           width: 40,
  //           height: 40,
  //           decoration: BoxDecoration(
  //             borderRadius: BorderRadius.circular(10),
  //             boxShadow: [
  //               BoxShadow(
  //                 color: context.primaryAccent.withValues(alpha: 0.3),
  //                 blurRadius: 14,
  //                 spreadRadius: 1,
  //               ),
  //             ],
  //           ),
  //           child: ClipRRect(
  //             borderRadius: BorderRadius.circular(10),
  //             child: Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
  //           ),
  //         ),
  //         const SizedBox(width: 12),
  //         Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Text(
  //               'Files Utility',
  //               style: TextStyle(
  //                 fontSize: 20,
  //                 fontWeight: FontWeight.w700,
  //                 color: context.textPrimary,
  //                 letterSpacing: 0.5,
  //               ),
  //             ),
  //             Text(
  //               'Manage your files and transfers',
  //               style: TextStyle(fontSize: 12, color: context.textMuted),
  //             ),
  //           ],
  //         ),
  //         const Spacer(),
  //         // Active Profile Badge
  //         Container(
  //           padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  //           decoration: BoxDecoration(
  //             color: context.cardBg,
  //             borderRadius: BorderRadius.circular(12),
  //             border: Border.all(color: context.border, width: 1),
  //           ),
  //           child: Row(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               Icon(
  //                 Icons.account_circle,
  //                 color: context.primaryAccent,
  //                 size: 20,
  //               ),
  //               const SizedBox(width: 8),
  //               Column(
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 mainAxisSize: MainAxisSize.min,
  //                 children: [
  //                   Text(
  //                     'ACTIVE PROFILE',
  //                     style: TextStyle(
  //                       fontSize: 9,
  //                       fontWeight: FontWeight.bold,
  //                       color: context.textMuted,
  //                       letterSpacing: 0.8,
  //                     ),
  //                   ),
  //                   Text(
  //                     currentProfile.name,
  //                     style: TextStyle(
  //                       fontSize: 13,
  //                       fontWeight: FontWeight.bold,
  //                       color: context.textPrimary,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ],
  //           ),
  //         ),
  //         const SizedBox(width: 8),
  //         const HelpManualButton(topicId: 'getting_started'),
  //         const SizedBox(width: 4),
  //         const UpdateCheckButton(),
  //         // Theme Switcher Button on the FAR RIGHT side
  //         const ThemeToggleButton(),
  //       ],
  //     );
  //   }
  // Gene - Nov, 22, 2026: Upgraded MainScreen header app icon bezel, Active Profile pill, and button spacing with Neumorphic styling.
  Widget _buildHeaderAndProfile(BuildContext context, dynamic currentProfile) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: NeumorphicTheme.rimBorder(context),
            boxShadow: NeumorphicTheme.softShadows(
              context,
              distance: 2.5,
              blur: 5.0,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Files Utility',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
                letterSpacing: 0.4,
              ),
            ),
            Text(
              'Manage your files and transfers',
              style: TextStyle(fontSize: 12, color: context.textMuted),
            ),
          ],
        ),
        const Spacer(),
        // Active Profile Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: NeumorphicTheme.rimBorder(context),
            boxShadow: NeumorphicTheme.softShadows(
              context,
              distance: 3.0,
              blur: 6.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_circle,
                color: context.primaryAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ACTIVE PROFILE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: context.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    currentProfile.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const HelpManualButton(topicId: 'getting_started'),
        const SizedBox(width: 8),
        const UpdateCheckButton(),
        const SizedBox(width: 8),
        // Theme Switcher Button on the FAR RIGHT side
        const ThemeToggleButton(),
      ],
    );
  }

  Widget _buildHistoryDashboard(BuildContext context) {
    return Consumer<HistoryProvider>(
      builder: (context, provider, child) {
        final records = provider.records;

        int transferFiles = records
            .where((r) => r.operation == 'Transfer')
            .fold(0, (sum, r) => sum + r.filesProcessed);
        int copyFiles = records
            .where((r) => r.operation == 'Copy')
            .fold(0, (sum, r) => sum + r.filesProcessed);
        int deleteFiles = records
            .where((r) => r.operation == 'Delete')
            .fold(0, (sum, r) => sum + r.filesProcessed);
        int countFiles = records
            .where((r) => r.operation == 'Count')
            .fold(0, (sum, r) => sum + r.filesProcessed);

        // int maxFiles = [
        //   transferFiles,
        //   copyFiles,
        //   deleteFiles,
        //   countFiles,
        // ].reduce((max, val) => val > max ? val : max);
        // Gene - Nov, 21, 2026: Include FTP uploads in dashboard comparative totals
        int ftpFiles = records
            .where((r) => r.operation == 'FTP')
            .fold(0, (sum, r) => sum + r.filesProcessed);

        int maxFiles = [
          transferFiles,
          copyFiles,
          deleteFiles,
          countFiles,
          ftpFiles,
        ].reduce((max, val) => val > max ? val : max);
        if (maxFiles == 0) maxFiles = 1;

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard(context: context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dashboard Header
              // Row(
              //   children: [
              //     Icon(
              //       Icons.analytics_outlined,
              //       color: context.primaryAccent,
              //       size: 22,
              //     ),
              //     const SizedBox(width: 8),
              //     Text(
              //       'History & Analytics Dashboard (All Profiles)',
              //       style: TextStyle(
              //         fontSize: 16,
              //         fontWeight: FontWeight.w600,
              //         color: context.textPrimary,
              //       ),
              //     ),
              //     const Spacer(),
              //     TextButton.icon(
              //       onPressed: () =>
              //           _navigateTo(context, const HistoryScreen()),
              //       icon: const Icon(Icons.bar_chart_rounded, size: 16),
              //       label: const Text('View Full Analytics'),
              //     ),
              //   ],
              // ),
              // Gene - Nov, 21, 2026: Wrap dashboard header title in Expanded to prevent horizontal overflow on narrow/scaled viewports
              Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    color: context.primaryAccent,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'History & Analytics Dashboard (All Profiles)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () =>
                        _navigateTo(context, const HistoryScreen()),
                    icon: const Icon(Icons.bar_chart_rounded, size: 16),
                    label: const Text('View Full Analytics'),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              //               // Comparative Operation Graphs
              //               Row(
              //                 children: [
              //                   Expanded(
              //                     child: _buildMiniGraphBar(
              //                       context,
              //                       'Transfer',
              //                       transferFiles,
              //                       transferFiles / maxFiles,
              //                       context.primaryAccent,
              //                     ),
              //                   ),
              //                   const SizedBox(width: 10),
              //                   Expanded(
              //                     child: _buildMiniGraphBar(
              //                       context,
              //                       'Copy',
              //                       copyFiles,
              //                       copyFiles / maxFiles,
              //                       context.isDarkMode
              //                           ? const Color(0xFFE2A06E)
              //                           : const Color(0xFFA0582C),
              //                     ),
              //                   ),
              //                   const SizedBox(width: 10),
              //                   Expanded(
              //                     child: _buildMiniGraphBar(
              //                       context,
              //                       'Delete',
              //                       deleteFiles,
              //                       deleteFiles / maxFiles,
              //                       AppColors.error,
              //                     ),
              //                   ),
              //                   const SizedBox(width: 10),
              //                   Expanded(
              //                     child: _buildMiniGraphBar(
              //                       context,
              //                       'Count',
              //                       countFiles,
              //                       countFiles / maxFiles,
              //                       AppColors.success,
              //                     ),
              //                   ),
              //                   // Gene - Nov, 21, 2026: Add FTP comparative bar to main dashboard
              //                   const SizedBox(width: 10),
              //                   Expanded(
              //                     child: _buildMiniGraphBar(
              //                       context,
              //                       'FTP',
              //                       ftpFiles,
              //                       ftpFiles / maxFiles,
              //                       context.ftpAccent,
              //                     ),
              //                   ),
              //                 ],
              //               ),
              // Gene - Nov, 22, 2026: Unified comparative graph colors with theme-aware semantic & operation getters.
              // Comparative Operation Graphs
              Row(
                children: [
                  Expanded(
                    child: _buildMiniGraphBar(
                      context,
                      'Transfer',
                      transferFiles,
                      transferFiles / maxFiles,
                      context.primaryAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMiniGraphBar(
                      context,
                      'Copy',
                      copyFiles,
                      copyFiles / maxFiles,
                      context.copyAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMiniGraphBar(
                      context,
                      'Delete',
                      deleteFiles,
                      deleteFiles / maxFiles,
                      context.errorColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMiniGraphBar(
                      context,
                      'Count',
                      countFiles,
                      countFiles / maxFiles,
                      context.successColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMiniGraphBar(
                      context,
                      'FTP',
                      ftpFiles,
                      ftpFiles / maxFiles,
                      context.ftpAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Recent Run Activity',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              // Recent Activity Table
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Text(
                          'No history records available.',
                          style: TextStyle(
                            color: context.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : _buildRecentActivityTable(
                        context,
                        records.take(10).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  //   Widget _buildMiniGraphBar(
  //     BuildContext context,
  //     String label,
  //     int filesCount,
  //     double ratio,
  //     Color color,
  //   ) {
  //     return Container(
  //       padding: const EdgeInsets.all(10),
  //       decoration: BoxDecoration(
  //         color: context.containerBg,
  //         borderRadius: BorderRadius.circular(8),
  //         border: Border.all(color: context.border),
  //       ),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(
  //             children: [
  //               Text(
  //                 label,
  //                 style: TextStyle(
  //                   fontSize: 11,
  //                   fontWeight: FontWeight.bold,
  //                   color: color,
  //                 ),
  //               ),
  //               const Spacer(),
  //               Text(
  //                 NumberFormat('#,##0').format(filesCount),
  //                 style: TextStyle(
  //                   fontSize: 11,
  //                   fontWeight: FontWeight.bold,
  //                   color: context.textPrimary,
  //                 ),
  //               ),
  //             ],
  //           ),
  //           const SizedBox(height: 6),
  //           ClipRRect(
  //             borderRadius: BorderRadius.circular(3),
  //             child: LinearProgressIndicator(
  //               value: ratio.clamp(0.05, 1.0),
  //               minHeight: 4,
  //               backgroundColor: context.border,
  //               valueColor: AlwaysStoppedAnimation<Color>(color),
  //             ),
  //           ),
  //         ],
  //       ),
  //     );
  //   }
  //
  //   Widget _buildRecentActivityTable(
  //     BuildContext context,
  //     List<RunRecord> records,
  //   ) {
  //     final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');
  //     final isDark = context.isDarkMode;
  //
  //     return LayoutBuilder(
  //       builder: (context, constraints) {
  //         return SingleChildScrollView(
  //           scrollDirection: Axis.vertical,
  //           child: SingleChildScrollView(
  //             scrollDirection: Axis.horizontal,
  //             child: ConstrainedBox(
  //               constraints: BoxConstraints(minWidth: constraints.maxWidth),
  //               child: DataTable(
  //                 headingRowColor: WidgetStateProperty.all(
  //                   isDark ? AppColors.bgDark2 : const Color(0xFFE2E8F0),
  //                 ),
  // Gene - Nov, 22, 2026: Upgraded mini graph tiles to soft Neumorphic cards with sunken progress grooves and wrapped recent activity table in a clean recessed frame.
  Widget _buildMiniGraphBar(
    BuildContext context,
    String label,
    int filesCount,
    double ratio,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: NeumorphicTheme.rimBorder(context),
        boxShadow: NeumorphicTheme.softShadows(
          context,
          distance: 2.5,
          blur: 5.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                NumberFormat('#,##0').format(filesCount),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          NeumorphicTheme.progressTrack(
            context,
            value: ratio.clamp(0.05, 1.0),
            color: color,
            height: 7.0,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityTable(
    BuildContext context,
    List<RunRecord> records,
  ) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      context.tableHeaderBg,
                    ),
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 56,
                    horizontalMargin: 12,
                    columnSpacing: 16,
                    columns: [
                      DataColumn(
                        label: Text(
                          'Operation',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Status',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Start Date/Time',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'End Date/Time',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Duration',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Source / Target Directory',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Destination Directory',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Files',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Folders',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Errors',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
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

                      Color opColor;
                      IconData opIcon;
                      //                   switch (record.operation) {
                      //                     case 'Transfer':
                      //                       opColor = context.primaryAccent;
                      //                       opIcon = Icons.move_up;
                      //                       break;
                      //                     case 'Copy':
                      //                       opColor = isDark
                      //                           ? const Color(0xFFE2A06E)
                      //                           : const Color(0xFFA0582C);
                      //                       opIcon = Icons.file_copy;
                      //                       break;
                      //                     case 'Delete':
                      //                       opColor = AppColors.error;
                      //                       opIcon = Icons.delete_forever;
                      //                       break;
                      //                     case 'Count':
                      //                       opColor = AppColors.success;
                      //                       opIcon = Icons.analytics;
                      //                       break;
                      //                     // Gene - Nov, 21, 2026: Style FTP entries in main dashboard recent activity table
                      //                     case 'FTP':
                      //                       opColor = context.ftpAccent;
                      //                       opIcon = Icons.cloud_upload;
                      //                       break;
                      //                     default:
                      //                       opColor = context.textMuted;
                      //                       opIcon = Icons.help_outline;
                      //                   }
                      //
                      //                   Color statusColor = record.status == 'Completed'
                      //                       ? AppColors.success
                      //                       : record.status == 'Stopped'
                      //                       ? AppColors.warning
                      //                       : AppColors.error;
                      // Gene - Nov, 22, 2026: Unified recent activity operation and status colors using theme-aware getters.
                      switch (record.operation) {
                        case 'Transfer':
                          opColor = context.primaryAccent;
                          opIcon = Icons.move_up;
                          break;
                        case 'Copy':
                          opColor = context.copyAccent;
                          opIcon = Icons.file_copy;
                          break;
                        case 'Delete':
                          opColor = context.errorColor;
                          opIcon = Icons.delete_forever;
                          break;
                        case 'Count':
                          opColor = context.successColor;
                          opIcon = Icons.analytics;
                          break;
                        case 'FTP':
                          opColor = context.ftpAccent;
                          opIcon = Icons.cloud_upload;
                          break;
                        default:
                          opColor = context.textMuted;
                          opIcon = Icons.help_outline;
                      }

                      Color statusColor = record.status == 'Completed'
                          ? context.successColor
                          : record.status == 'Stopped'
                          ? context.warningColor
                          : context.errorColor;

                      return DataRow(
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(opIcon, color: opColor, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  record.operation,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: opColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.5),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                record.status,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              dateFormat.format(record.startTime),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              dateFormat.format(record.endTime),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              durationStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 200,
                              child: Text(
                                record.sourcePath ?? '-',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Consolas',
                                  color: context.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 200,
                              child: Text(
                                record.destPath ?? '-',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Consolas',
                                  color: context.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              NumberFormat(
                                '#,##0',
                              ).format(record.filesProcessed),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              NumberFormat(
                                '#,##0',
                              ).format(record.foldersProcessed),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                            ),
                          ),
                          //                       DataCell(
                          //                         Text(
                          //                           NumberFormat('#,##0').format(record.errors),
                          //                           style: TextStyle(
                          //                             fontSize: 11,
                          //                             fontWeight: FontWeight.bold,
                          //                             color: record.errors > 0
                          //                                 ? AppColors.error
                          //                                 : context.textMuted,
                          //                           ),
                          //                         ),
                          //                       ),
                          //                     ],
                          //                   );
                          //                 }).toList(),
                          //               ),
                          //             ),
                          //           ),
                          //         );
                          //       },
                          //     );
                          //   }
                          // Gene - Nov, 22, 2026: Closed recessed table frame wrapper and used theme-aware errorColor in recent activity table.
                          DataCell(
                            Text(
                              NumberFormat('#,##0').format(record.errors),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: record.errors > 0
                                    ? context.errorColor
                                    : context.textMuted,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _navigateTo(BuildContext context, Widget screen) async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0.02, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    if (context.mounted) {
      context.read<HistoryProvider>().refreshHistory();
    }
  }
}

class _DashboardCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  bool _isHovered = false;

  //   @override
  //   Widget build(BuildContext context) {
  //     final isDark = context.isDarkMode;
  //     final cardBgColor = _isHovered
  //         ? (isDark ? AppColors.surfaceLight : Colors.white)
  //         : context.cardBg;
  //
  //     return MouseRegion(
  //       onEnter: (_) => setState(() => _isHovered = true),
  //       onExit: (_) => setState(() => _isHovered = false),
  //       child: GestureDetector(
  //         onTap: widget.onTap,
  //         child: AnimatedContainer(
  //           duration: const Duration(milliseconds: 200),
  //           curve: Curves.easeOut,
  //           transform: _isHovered
  //               ? Matrix4.translationValues(0.0, -2.0, 0.0)
  //               : Matrix4.identity(),
  //           decoration: BoxDecoration(
  //             color: cardBgColor,
  //             borderRadius: BorderRadius.circular(14),
  //             border: Border.all(
  //               color: _isHovered
  //                   ? widget.accentColor.withValues(alpha: 0.5)
  //                   : context.border,
  //               width: 1,
  //             ),
  //             boxShadow: [
  //               BoxShadow(
  //                 color: _isHovered
  //                     ? widget.accentColor.withValues(alpha: 0.15)
  //                     : Colors.black.withValues(alpha: isDark ? 0.0 : 0.04),
  //                 blurRadius: _isHovered ? 16 : 8,
  //                 spreadRadius: 0,
  //               ),
  //             ],
  //           ),
  //           child: Padding(
  //             padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  //             child: Row(
  //               crossAxisAlignment: CrossAxisAlignment.center,
  //               children: [
  //                 Container(
  //                   width: 36,
  //                   height: 36,
  //                   decoration: BoxDecoration(
  //                     color: widget.accentColor.withValues(
  //                       alpha: isDark ? 0.15 : 0.1,
  //                     ),
  //                     borderRadius: BorderRadius.circular(10),
  //                     boxShadow: _isHovered
  //                         ? [
  //                             BoxShadow(
  //                               color: widget.accentColor.withValues(alpha: 0.2),
  //                               blurRadius: 12,
  //                               spreadRadius: 0,
  //                             ),
  //                           ]
  //                         : [],
  //                   ),
  //                   child: Icon(widget.icon, color: widget.accentColor, size: 20),
  //                 ),
  //                 const SizedBox(width: 12),
  //                 Expanded(
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     mainAxisAlignment: MainAxisAlignment.center,
  //                     children: [
  //                       Text(
  //                         widget.title,
  //                         style: TextStyle(
  //                           fontSize: 14,
  //                           fontWeight: FontWeight.w600,
  //                           color: _isHovered
  //                               ? widget.accentColor
  //                               : context.textPrimary,
  //                           letterSpacing: 0.2,
  //                         ),
  //                         maxLines: 1,
  //                         overflow: TextOverflow.ellipsis,
  //                       ),
  //                       const SizedBox(height: 2),
  //                       Text(
  //                         widget.subtitle,
  //                         style: TextStyle(
  //                           fontSize: 11,
  //                           color: context.textMuted,
  //                           height: 1.2,
  //                         ),
  //                         maxLines: 1,
  //                         overflow: TextOverflow.ellipsis,
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
  //         ),
  //       ),
  //     );
  //   }
  // Gene - Nov, 22, 2026: Upgraded _DashboardCard with authentic Neumorphic dual shadows and embossed icon tile matching Batterie.
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final cardBgColor = _isHovered ? context.surfaceHover : context.cardBg;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: _isHovered
              ? Matrix4.translationValues(0.0, -2.0, 0.0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: _isHovered
                ? Border.all(
                    color: widget.accentColor.withValues(alpha: 0.5),
                    width: 1.2,
                  )
                : NeumorphicTheme.rimBorder(context),
            boxShadow: NeumorphicTheme.raisedShadows(
              context,
              distance: _isHovered ? 6.0 : 4.5,
              blur: _isHovered ? 12.0 : 9.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.accentColor.withValues(
                        alpha: isDark ? 0.3 : 0.25,
                      ),
                      width: 1.0,
                    ),
                    boxShadow: NeumorphicTheme.softShadows(
                      context,
                      distance: 2.0,
                      blur: 4.0,
                    ),
                  ),
                  child: Icon(widget.icon, color: widget.accentColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _isHovered
                              ? widget.accentColor
                              : context.textPrimary,
                          letterSpacing: 0.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textMuted,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
