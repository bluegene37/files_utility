// Gene - Nov, 21, 2026: FTP Upload screen with collapsible connection settings, single/multi-source config, dry-run/retry options, and weekday+time scheduler.
// Gene - Nov, 24, 2026: Import dart:async for unawaited Run Selected execution from dialog confirmation.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/ftp_upload_source.dart';
import '../providers/ftp_files_provider.dart';
import '../services/ftp_transfer_service.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';
import '../services/window_service.dart';
import '../theme/app_theme.dart';
import '../widgets/help_shortcut_wrapper.dart';
import '../widgets/history_dialog.dart';
import '../widgets/theme_toggle_button.dart';

class FtpFilesScreen extends StatefulWidget {
  const FtpFilesScreen({super.key});

  @override
  State<FtpFilesScreen> createState() => _FtpFilesScreenState();
}

class _FtpFilesScreenState extends State<FtpFilesScreen> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _remoteDirController;
  late final TextEditingController _subfoldersController;

  bool _connectionExpanded = true;
  bool _obscurePassword = true;
  int _lastSettingsVersion = -1;
  bool _initializedExpansion = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController();
    _portController = TextEditingController();
    _userController = TextEditingController();
    _passController = TextEditingController();
    _remoteDirController = TextEditingController();
    _subfoldersController = TextEditingController();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passController.dispose();
    _remoteDirController.dispose();
    _subfoldersController.dispose();
    super.dispose();
  }

  void _syncControllersIfNeeded(FtpFilesProvider provider) {
    if (_lastSettingsVersion == provider.settingsVersion) return;
    _lastSettingsVersion = provider.settingsVersion;

    _setControllerText(_hostController, provider.host);
    _setControllerText(_portController, provider.port.toString());
    _setControllerText(_userController, provider.username);
    _setControllerText(_passController, provider.password);
    _setControllerText(_remoteDirController, provider.remoteDirectory);
    _setControllerText(_subfoldersController, provider.subfolders);

    if (!_initializedExpansion) {
      _connectionExpanded = provider.host.trim().isEmpty;
      _initializedExpansion = true;
    }
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.text = value;
    }
  }

  Future<void> _handleTestConnection(FtpFilesProvider provider) async {
    final result = await provider.testConnection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? AppColors.success : AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  //   // Gene - Nov, 23, 2026: Import INI / .env settings from disk.
  //   Future<void> _handleImportConfig(FtpFilesProvider provider) async {
  //     final message = await provider.importConfigFromDisk();
  //     if (!mounted || message == null) return;
  //     final isError =
  //         message.startsWith('Failed') || message.startsWith('No recognizable');
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text(message),
  //         backgroundColor: isError ? AppColors.error : AppColors.success,
  //         duration: const Duration(seconds: 4),
  //       ),
  //     );
  //   }
  // Gene - Nov, 23, 2026: Import/Export handlers for FTP settings (.json / config.ini / .env).
  Future<void> _handleImportConfig(FtpFilesProvider provider) async {
    final message = await provider.importConfigFromDisk();
    if (!mounted || message == null) return;
    _showFtpActionSnackBar(context, message);
  }

  Future<void> _handleExportSettings(FtpFilesProvider provider) async {
    final message = await provider.exportSettingsToDisk();
    if (!mounted || message == null) return;
    _showFtpActionSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<FtpFilesProvider>(context);
    _syncControllersIfNeeded(provider);

    WindowService().updateTitle(
      'FTP Upload',
      status: provider.isProcessing ? provider.currentStatus : null,
    );

    final accentColor = context.ftpAccent;

    return HelpShortcutWrapper(
      topicId: 'ftp_files',
      child: Scaffold(
        body: Container(
          decoration: AppDecorations.gradientBackground(context),
          child: Column(
            children: [
              //               _buildAppBar(context, accentColor),
              // Gene - Nov, 23, 2026: Pass provider into _buildAppBar for Import Config and Open Logs Folder actions.
              _buildAppBar(context, provider, accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    children: [
                      Flexible(
                        flex: 0,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.52,
                          ),
                          child: SingleChildScrollView(
                            child: Container(
                              decoration: AppDecorations.glassCard(
                                context: context,
                                glowColor: accentColor,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 12.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSourceSection(context, provider),
                                  const SizedBox(height: 10),
                                  _buildConnectionCard(
                                    context,
                                    provider,
                                    accentColor,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildSettingsStrip(
                                    context,
                                    provider,
                                    accentColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildActionAndStatsRow(context, provider, accentColor),
                      // Gene - Nov, 23, 2026: Render live per-file upload progress bar while transferring.
                      if (provider.isUploading &&
                          provider.activeUploadProgress != null) ...[
                        const SizedBox(height: 8),
                        _buildUploadProgressBar(context, provider, accentColor),
                      ],
                      const SizedBox(height: 8),
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

  //   Widget _buildAppBar(BuildContext context, Color accentColor) {
  //     final currentProfileId = LocalDbService().currentProfileId;
  //     final currentProfile = GlobalDbService().profiles.firstWhere(
  //       (p) => p.id == currentProfileId,
  //       orElse: () => GlobalDbService().profiles.first,
  //     );
  //
  //     return Container(
  //       padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
  //       child: Row(
  //         children: [
  //           IconButton(
  //             icon: Icon(Icons.arrow_back_rounded, color: accentColor),
  //             onPressed: () => Navigator.of(context).pop(),
  //           ),
  //           const SizedBox(width: 4),
  //           Icon(Icons.cloud_upload_rounded, color: accentColor, size: 22),
  //           const SizedBox(width: 10),
  //           Text(
  //             'FTP Upload (${currentProfile.name})',
  //             style: TextStyle(
  //               fontSize: 20,
  //               fontWeight: FontWeight.w600,
  //               color: context.textPrimary,
  //             ),
  //           ),
  //           const Spacer(),
  //           const HelpManualButton(topicId: 'ftp_files'),
  //           const SizedBox(width: 4),
  //           const ThemeToggleButton(),
  //         ],
  //       ),
  //     );
  //   }
  // Gene - Nov, 23, 2026: Add Import config.ini/.env and Open Logs Folder buttons to FTP app bar.
  Widget _buildAppBar(
    BuildContext context,
    FtpFilesProvider provider,
    Color accentColor,
  ) {
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
            icon: Icon(Icons.arrow_back_rounded, color: accentColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Icon(Icons.cloud_upload_rounded, color: accentColor, size: 22),
          const SizedBox(width: 10),
          Text(
            'FTP Upload (${currentProfile.name})',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const Spacer(),
          //           IconButton(
          //             key: const Key('ftp_import_ini_btn'),
          //             icon: Icon(
          //               Icons.file_upload_outlined,
          //               color: accentColor,
          //               size: 20,
          //             ),
          //             tooltip: 'Import config.ini / .env',
          //             onPressed: provider.isProcessing
          //                 ? null
          //                 : () => _handleImportConfig(provider),
          //           ),
          // Gene - Nov, 23, 2026: Support JSON/.ini/.env import and credential-free JSON settings export in FTP app bar.
          IconButton(
            key: const Key('ftp_import_ini_btn'),
            icon: Icon(
              Icons.file_upload_outlined,
              color: accentColor,
              size: 20,
            ),
            tooltip: 'Import Settings (.json / config.ini / .env)',
            onPressed: provider.isProcessing
                ? null
                : () => _handleImportConfig(provider),
          ),
          IconButton(
            key: const Key('ftp_export_settings_btn'),
            icon: Icon(
              Icons.file_download_outlined,
              color: accentColor,
              size: 20,
            ),
            tooltip: 'Export FTP Settings (.json, without credentials)',
            onPressed: provider.isProcessing
                ? null
                : () => _handleExportSettings(provider),
          ),
          IconButton(
            key: const Key('ftp_open_logs_btn'),
            icon: Icon(Icons.folder_open_rounded, color: accentColor, size: 20),
            tooltip: 'Open Logs Folder',
            onPressed: () => provider.openLogsFolder(),
          ),
          const HelpManualButton(topicId: 'ftp_files'),
          const SizedBox(width: 4),
          const ThemeToggleButton(),
        ],
      ),
    );
  }

  Widget _buildSourceSection(BuildContext context, FtpFilesProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                key: const Key('ftp_multiple_sources_checkbox'),
                value: provider.useMultipleSources,
                onChanged: provider.isProcessing
                    ? null
                    : (val) => provider.setUseMultipleSources(val ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: provider.isProcessing
                  ? null
                  : () => provider.setUseMultipleSources(
                      !provider.useMultipleSources,
                    ),
              child: Text(
                'Multiple Sources',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: context.textSecondary,
                ),
              ),
            ),
            if (provider.useMultipleSources) ...[
              const SizedBox(width: 16),
              Icon(Icons.folder_copy, size: 16, color: context.textMuted),
              const SizedBox(width: 6),
              //               Text(
              //                 '${provider.uploadSources.length} source${provider.uploadSources.length == 1 ? '' : 's'} configured',
              //                 style: TextStyle(fontSize: 13, color: context.textSecondary),
              //               ),
              //               // Gene - Nov, 23, 2026: Show active vs total source counts when some sources are disabled.
              //               Builder(
              //                 builder: (_) {
              //                   final total = provider.uploadSources.length;
              //                   final active = provider.uploadSources
              //                       .where((s) => s.enabled)
              //                       .length;
              //                   final label = active == total
              //                       ? '$total source${total == 1 ? '' : 's'} configured'
              //                       : '$active/$total sources active';
              //                   return Text(
              //                     label,
              //                     style: TextStyle(
              //                       fontSize: 13,
              //                       color: context.textSecondary,
              //                     ),
              //                   );
              //                 },
              //               ),
              // Gene - Nov, 24, 2026: Summarize active source count alongside non-default schedule cadence counts.
              Builder(
                builder: (_) {
                  final total = provider.uploadSources.length;
                  final enabledSources = provider.uploadSources
                      .where((s) => s.enabled)
                      .toList();
                  final active = enabledSources.length;
                  final baseLabel = active == total
                      ? '$total source${total == 1 ? '' : 's'} configured'
                      : '$active/$total sources active';
                  final monthlyCount = enabledSources
                      .where(
                        (s) => s.scheduleMode == FtpSourceScheduleMode.monthly,
                      )
                      .length;
                  final weeklyCount = enabledSources
                      .where(
                        (s) => s.scheduleMode == FtpSourceScheduleMode.weekly,
                      )
                      .length;
                  final manualCount = enabledSources
                      .where(
                        (s) =>
                            s.scheduleMode == FtpSourceScheduleMode.manualOnly,
                      )
                      .length;
                  final tags = <String>[
                    if (monthlyCount > 0) '$monthlyCount monthly',
                    if (weeklyCount > 0) '$weeklyCount weekly',
                    if (manualCount > 0) '$manualCount manual',
                  ];
                  final label = tags.isEmpty
                      ? baseLabel
                      : '$baseLabel (${tags.join(', ')})';
                  return Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: provider.isProcessing
                    ? null
                    : () => _showUploadSourcesDialog(context, provider),
                icon: const Icon(Icons.edit, size: 15),
                label: const Text(
                  'Edit Sources',
                  style: TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
        if (!provider.useMultipleSources) ...[
          const SizedBox(height: 8),
          PathRow(
            label: 'Local Source',
            path: provider.sourcePath,
            onPick: provider.isProcessing ? null : provider.pickSource,
            onChanged: provider.isProcessing ? null : provider.setSourcePath,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  'Subfolders:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                //                 child: TextField(
                //                   controller: _subfoldersController,
                //                   enabled: !provider.isProcessing,
                //                   onChanged: provider.setSubfolders,
                //                   style: TextStyle(color: context.textPrimary, fontSize: 13),
                //                   decoration: InputDecoration(
                //                     hintText: 'Optional: FolderA, FolderB',
                //                     hintStyle: TextStyle(color: context.textMuted),
                //                     isDense: true,
                //                     contentPadding: const EdgeInsets.symmetric(
                //                       horizontal: 12,
                //                       vertical: 10,
                //                     ),
                //                   ),
                //                 ),
                // Gene - Nov, 23, 2026: Clarify blank Subfolders behavior with hint and Tooltip.
                child: Tooltip(
                  message:
                      'Comma-separated subfolder names to upload. Leave blank to upload root files (or all subfolders when "Include nested subfolders" is enabled).',
                  child: TextField(
                    controller: _subfoldersController,
                    enabled: !provider.isProcessing,
                    onChanged: provider.setSubfolders,
                    style: TextStyle(color: context.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Blank = root (or all if nested on)',
                      hintStyle: TextStyle(color: context.textMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Remote Folder:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _remoteDirController,
                  enabled: !provider.isProcessing,
                  onChanged: provider.setRemoteDirectory,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Optional (blank = FTP root)',
                    hintStyle: TextStyle(color: context.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildConnectionCard(
    BuildContext context,
    FtpFilesProvider provider,
    Color accentColor,
  ) {
    final hostDisplay = provider.host.trim().isEmpty
        ? 'Not configured'
        : '${provider.host.trim()}:${provider.port}';

    //     return Container(
    //       decoration: BoxDecoration(
    //         color: context.containerBg,
    //         borderRadius: BorderRadius.circular(10),
    //         border: Border.all(color: context.border),
    //       ),
    // Gene - Nov, 22, 2026: Styled FTP Connection collapsible card as a recessed Neumorphic panel inside the config card.
    return Container(
      decoration: NeumorphicTheme.recessedDecoration(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          //           InkWell(
          //             key: const Key('ftp_connection_header'),
          //             borderRadius: BorderRadius.circular(10),
          //             onTap: () =>
          //                 setState(() => _connectionExpanded = !_connectionExpanded),
          //             child: Padding(
          //               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          //               child: Row(
          //                 children: [
          //                   Icon(Icons.dns_rounded, size: 17, color: accentColor),
          //                   const SizedBox(width: 8),
          //                   Text(
          //                     'FTP Connection',
          //                     style: TextStyle(
          //                       fontSize: 13,
          //                       fontWeight: FontWeight.w600,
          //                       color: context.textPrimary,
          //                     ),
          //                   ),
          //                   const SizedBox(width: 10),
          //                   Expanded(
          //                     child: Text(
          //                       '${provider.protocol.shortLabel} • $hostDisplay',
          //                       style: TextStyle(fontSize: 12, color: context.textMuted),
          //                       maxLines: 1,
          //                       overflow: TextOverflow.ellipsis,
          //                     ),
          //                   ),
          //                   const SizedBox(width: 8),
          //                   OutlinedButton.icon(
          //                     key: const Key('ftp_test_connection_btn'),
          //                     onPressed:
          //                         (provider.hasValidConnection &&
          //                             !provider.isTestingConnection &&
          //                             !provider.isUploading)
          //                         ? () => _handleTestConnection(provider)
          //                         : null,
          //                     icon: provider.isTestingConnection
          //                         ? SizedBox(
          //                             width: 13,
          //                             height: 13,
          //                             child: CircularProgressIndicator(
          //                               strokeWidth: 2,
          //                               color: accentColor,
          //                             ),
          //                           )
          //                         : Icon(
          //                             Icons.wifi_tethering,
          //                             size: 15,
          //                             color: accentColor,
          //                           ),
          //                     label: Text(
          //                       provider.isTestingConnection
          //                           ? 'Testing...'
          //                           : 'Test Connection',
          //                       style: TextStyle(fontSize: 12, color: accentColor),
          //                     ),
          //                     //                     style: OutlinedButton.styleFrom(
          //                     //                       side: BorderSide(color: context.border),
          //                     //                       padding: const EdgeInsets.symmetric(
          //                     //                         horizontal: 10,
          //                     //                         vertical: 6,
          //                     //                       ),
          //                     //                       visualDensity: VisualDensity.compact,
          //                     //                     ),
          //                     // Gene - Nov, 22, 2026: Tinted Test Connection outline with accentColor.
          //                     style: OutlinedButton.styleFrom(
          //                       side: BorderSide(
          //                         color: accentColor.withValues(alpha: 0.45),
          //                       ),
          //                       padding: const EdgeInsets.symmetric(
          //                         horizontal: 10,
          //                         vertical: 6,
          //                       ),
          //                       visualDensity: VisualDensity.compact,
          //                     ),
          //                   ),
          //                   const SizedBox(width: 6),
          //                   Icon(
          //                     _connectionExpanded
          //                         ? Icons.expand_less_rounded
          //                         : Icons.expand_more_rounded,
          //                     color: context.textMuted,
          //                   ),
          //                 ],
          //               ),
          //             ),
          //           ),
          // Gene - Nov, 23, 2026: Move Test Connection button outside the collapsible header InkWell so clicking it never toggles card expansion.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const Key('ftp_connection_header'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(
                      () => _connectionExpanded = !_connectionExpanded,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.dns_rounded, size: 17, color: accentColor),
                          const SizedBox(width: 8),
                          Text(
                            'FTP Connection',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${provider.protocol.shortLabel} • $hostDisplay',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('ftp_test_connection_btn'),
                  onPressed:
                      (provider.hasValidConnection &&
                          !provider.isTestingConnection &&
                          !provider.isUploading)
                      ? () => _handleTestConnection(provider)
                      : null,
                  icon: provider.isTestingConnection
                      ? SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentColor,
                          ),
                        )
                      : Icon(
                          Icons.wifi_tethering,
                          size: 15,
                          color: accentColor,
                        ),
                  label: Text(
                    provider.isTestingConnection
                        ? 'Testing...'
                        : 'Test Connection',
                    style: TextStyle(fontSize: 12, color: accentColor),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: accentColor.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  key: const Key('ftp_connection_expand_btn'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(
                    () => _connectionExpanded = !_connectionExpanded,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _connectionExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: context.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_connectionExpanded) ...[
            Divider(height: 1, color: context.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<FtpProtocol>(
                          isExpanded: true,
                          initialValue: provider.protocol,
                          decoration: const InputDecoration(
                            labelText: 'Protocol',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          dropdownColor: context.cardBg,
                          items: FtpProtocol.values
                              .map(
                                (p) => DropdownMenuItem<FtpProtocol>(
                                  value: p,
                                  child: Text(
                                    p.label,
                                    style: TextStyle(
                                      color: context.textPrimary,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: provider.isProcessing
                              ? null
                              : (val) {
                                  if (val != null) {
                                    provider.setProtocol(val);
                                    _setControllerText(
                                      _portController,
                                      provider.port.toString(),
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: TextField(
                          key: const Key('ftp_host_field'),
                          controller: _hostController,
                          enabled: !provider.isProcessing,
                          onChanged: provider.setHost,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Host / IP Address',
                            hintText: 'ftp.example.com',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          key: const Key('ftp_port_field'),
                          controller: _portController,
                          enabled: !provider.isProcessing,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null &&
                                parsed >= 1 &&
                                parsed <= 65535) {
                              provider.setPort(parsed);
                            }
                          },
                          onEditingComplete: () {
                            _setControllerText(
                              _portController,
                              provider.port.toString(),
                            );
                          },
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Tooltip(
                          message: provider.protocol.supportsTransferMode
                              ? 'Passive mode is used for firewall-friendly transfers'
                              : 'Transfer mode does not apply to SFTP',
                          child: DropdownButtonFormField<FtpTransferMode>(
                            isExpanded: true,
                            initialValue: FtpTransferMode.passive,
                            decoration: const InputDecoration(
                              labelText: 'Transfer Mode',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            dropdownColor: context.cardBg,
                            items: [
                              DropdownMenuItem<FtpTransferMode>(
                                value: FtpTransferMode.passive,
                                child: Text(
                                  FtpTransferMode.passive.label,
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                            onChanged:
                                (!provider.isProcessing &&
                                    provider.protocol.supportsTransferMode)
                                ? (val) {
                                    if (val != null) {
                                      provider.setTransferMode(val);
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('ftp_username_field'),
                          controller: _userController,
                          enabled: !provider.isProcessing,
                          onChanged: provider.setUsername,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            hintText: 'anonymous if blank',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('ftp_password_field'),
                          controller: _passController,
                          enabled: !provider.isProcessing,
                          obscureText: _obscurePassword,
                          onChanged: provider.setPassword,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            suffixIcon: IconButton(
                              key: const Key('ftp_password_visibility_btn'),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 17,
                                color: context.textMuted,
                              ),
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsStrip(
    BuildContext context,
    FtpFilesProvider provider,
    Color accentColor,
  ) {
    final dateTypeShort = provider.dateType == FtpDateType.creation
        ? 'Created'
        : 'Modified';
    final dateChipText = provider.dateMode == FtpDateMode.daysAgo
        ? '${provider.daysAgo}d ago ($dateTypeShort)'
        : '${provider.dateMode.label} ($dateTypeShort)';

    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('ftp_advanced_settings_btn'),
                onPressed: () =>
                    _showAdvancedSettingsDialog(context, provider, accentColor),
                icon: Icon(Icons.settings, size: 16, color: accentColor),
                label: Text(
                  'Advanced Settings',
                  style: TextStyle(color: accentColor),
                ),
                //                 style: OutlinedButton.styleFrom(
                //                   side: BorderSide(color: context.border),
                //                   padding: const EdgeInsets.symmetric(
                //                     horizontal: 14,
                //                     vertical: 8,
                //                   ),
                //                   visualDensity: VisualDensity.compact,
                //                 ),
                //               ),
                //               _infoPill(
                //                 context,
                //                 icon: Icons.calendar_today,
                //                 label: dateChipText,
                //                 color: context.textSecondary,
                //               ),
                //               if (provider.enableSchedule)
                //                 _infoPill(
                //                   context,
                //                   icon: Icons.schedule,
                //                   label:
                //                       '${provider.runTime.format(context)} (${provider.onCompletionAction == 'repeat' ? 'Repeat' : 'Once'})',
                //                   color: accentColor,
                //                 ),
                //               if (provider.dryRun)
                //                 _infoPill(
                //                   context,
                //                   icon: Icons.science_outlined,
                //                   label: 'DRY RUN',
                //                   color: AppColors.warning,
                //                   emphasized: true,
                //                 ),
                // Gene - Nov, 22, 2026: Matched FTP Advanced Settings outline and DRY RUN pill to theme-aware Neumorphic tokens.
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: accentColor.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              _infoPill(
                context,
                icon: Icons.calendar_today,
                label: dateChipText,
                color: context.textSecondary,
              ),
              //               if (provider.enableSchedule)
              //                 _infoPill(
              //                   context,
              //                   icon: Icons.schedule,
              //                   label:
              //                       '${provider.runTime.format(context)} (${provider.onCompletionAction == 'repeat' ? 'Repeat' : 'Once'})',
              //                   color: accentColor,
              //                 ),
              // Gene - Nov, 24, 2026: Display schedule start and end window in main screen pill when an end time is set.
              if (provider.enableSchedule)
                _infoPill(
                  context,
                  icon: Icons.schedule,
                  label: provider.hasEndTimeLimit
                      ? '${provider.runTime.format(context)} – ${provider.runEndTime.format(context)} (${provider.onCompletionAction == 'repeat' ? 'Repeat' : 'Once'})'
                      : '${provider.runTime.format(context)} (${provider.onCompletionAction == 'repeat' ? 'Repeat' : 'Once'})',
                  color: accentColor,
                ),
              if (provider.dryRun)
                _infoPill(
                  context,
                  icon: Icons.science_outlined,
                  label: 'DRY RUN',
                  color: context.warningColor,
                  emphasized: true,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Log Every',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 74,
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: provider.logInterval,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            dropdownColor: context.cardBg,
            items: [1, 5, 10, 25, 50, 100].map((int value) {
              return DropdownMenuItem<int>(
                value: value,
                child: Text(
                  value.toString(),
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                ),
              );
            }).toList(),
            onChanged: provider.isProcessing
                ? null
                : (val) {
                    if (val != null) provider.setLogInterval(val);
                  },
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'files',
          style: TextStyle(fontSize: 13, color: context.textSecondary),
        ),
        const SizedBox(width: 12),
        StatBadge(
          title: 'History',
          value: 'View',
          color: accentColor,
          icon: Icons.history,
          onTap: () => showHistoryDialog(context, initialOperation: 'FTP'),
        ),
      ],
    );
  }

  //   Widget _infoPill(
  //     BuildContext context, {
  //     required IconData icon,
  //     required String label,
  //     required Color color,
  //     bool emphasized = false,
  //   }) {
  //     return Container(
  //       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  //       decoration: BoxDecoration(
  //         color: emphasized
  //             ? color.withValues(alpha: 0.16)
  //             : context.containerBg,
  //         borderRadius: BorderRadius.circular(8),
  //         border: Border.all(
  //           color: emphasized ? color.withValues(alpha: 0.6) : context.border,
  //         ),
  //       ),
  // Gene - Nov, 22, 2026: Upgraded FTP _infoPill to soft Neumorphic raised pill.
  Widget _infoPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    bool emphasized = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: emphasized ? color.withValues(alpha: 0.5) : context.border,
        ),
        boxShadow: NeumorphicTheme.softShadows(
          context,
          distance: 1.5,
          blur: 3.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: emphasized ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionAndStatsRow(
    BuildContext context,
    FtpFilesProvider provider,
    Color accentColor,
  ) {
    //     return Row(
    //       children: [
    //         if (!provider.isProcessing) ...[
    //           if (!provider.enableSchedule)
    //             ElevatedButton.icon(
    //               key: const Key('ftp_start_upload_btn'),
    //               onPressed: provider.canRunNow ? provider.runNow : null,
    //               icon: const Icon(Icons.cloud_upload_rounded, size: 18),
    //               label: const Text('Start Upload'),
    //             )
    //           else ...[
    //             ElevatedButton.icon(
    //               key: const Key('ftp_start_schedule_btn'),
    //               onPressed: provider.canArmSchedule
    //                   ? provider.startSchedule
    //                   : null,
    //               icon: const Icon(Icons.schedule_rounded, size: 18),
    //               label: const Text('Start Schedule'),
    //             ),
    //             const SizedBox(width: 8),
    //             OutlinedButton.icon(
    //               key: const Key('ftp_run_now_btn'),
    //               onPressed: provider.canRunNow ? provider.runNow : null,
    //               icon: const Icon(Icons.play_arrow_rounded, size: 18),
    //               label: const Text('Run Now'),
    //             ),
    //           ],
    //         ] else ...[
    //           ElevatedButton.icon(
    //             key: const Key('ftp_stop_btn'),
    //             onPressed: provider.stop,
    //             icon: const Icon(Icons.stop, size: 18),
    //             label: const Text('Stop'),
    //             style: ElevatedButton.styleFrom(
    //               backgroundColor: AppColors.error,
    //               foregroundColor: Colors.white,
    //             ),
    //           ),
    //           if (provider.isScheduleArmed && !provider.isUploading) ...[
    //             const SizedBox(width: 8),
    //             OutlinedButton.icon(
    //               key: const Key('ftp_run_now_btn'),
    //               onPressed: provider.canRunNow ? provider.runNow : null,
    //               icon: const Icon(Icons.play_arrow_rounded, size: 18),
    //               label: const Text('Run Now'),
    //             ),
    //           ],
    //         ],
    //         const SizedBox(width: 14),
    //         if (provider.isUploading || provider.isTestingConnection)
    //           Container(
    //             width: 14,
    //             height: 14,
    //             margin: const EdgeInsets.only(right: 8),
    //             child: CircularProgressIndicator(
    //               strokeWidth: 2,
    //               valueColor: AlwaysStoppedAnimation<Color>(accentColor),
    //             ),
    //           ),
    //         Expanded(
    //           child: Text(
    //             provider.currentStatus,
    //             style: TextStyle(
    //               fontWeight: FontWeight.w600,
    //               color: context.textPrimary,
    //               fontSize: 13,
    //             ),
    //             maxLines: 1,
    //             overflow: TextOverflow.ellipsis,
    //           ),
    //         ),
    //         const SizedBox(width: 8),
    //         StatBadge(
    //           title: 'Uploaded',
    //           value: provider.filesUploaded.toString(),
    //           color: context.successColor,
    //           icon: Icons.cloud_done_rounded,
    //         ),
    //         const SizedBox(width: 8),
    //         StatBadge(
    //           title: 'Skipped',
    //           value: provider.filesSkipped.toString(),
    //           color: context.warningColor,
    //           icon: Icons.fast_forward_rounded,
    //         ),
    //         const SizedBox(width: 8),
    //         StatBadge(
    //           title: 'Errors',
    //           value: provider.errors.toString(),
    //           color: context.errorColor,
    //           icon: Icons.error,
    //         ),
    //       ],
    //     );
    //     // Gene - Nov, 24, 2026: Wrap action controls and stat badges on narrower desktop viewports (980x680) when schedule buttons are visible.
    //     final actionButtons = <Widget>[
    //       if (!provider.isProcessing) ...[
    //         if (!provider.enableSchedule)
    //           ElevatedButton.icon(
    //             key: const Key('ftp_start_upload_btn'),
    //             onPressed: provider.canRunNow ? provider.runNow : null,
    //             icon: const Icon(Icons.cloud_upload_rounded, size: 18),
    //             label: const Text('Start Upload'),
    //           )
    //         else ...[
    //           ElevatedButton.icon(
    //             key: const Key('ftp_start_schedule_btn'),
    //             onPressed: provider.canArmSchedule ? provider.startSchedule : null,
    //             icon: const Icon(Icons.schedule_rounded, size: 18),
    //             label: const Text('Start Schedule'),
    //           ),
    //           const SizedBox(width: 8),
    //           OutlinedButton.icon(
    //             key: const Key('ftp_run_now_btn'),
    //             onPressed: provider.canRunNow ? provider.runNow : null,
    //             icon: const Icon(Icons.play_arrow_rounded, size: 18),
    //             label: const Text('Run Now'),
    //           ),
    //         ],
    //       ] else ...[
    //         ElevatedButton.icon(
    //           key: const Key('ftp_stop_btn'),
    //           onPressed: provider.stop,
    //           icon: const Icon(Icons.stop, size: 18),
    //           label: const Text('Stop'),
    //           style: ElevatedButton.styleFrom(
    //             backgroundColor: AppColors.error,
    //             foregroundColor: Colors.white,
    //           ),
    //         ),
    //         if (provider.isScheduleArmed && !provider.isUploading) ...[
    //           const SizedBox(width: 8),
    //           OutlinedButton.icon(
    //             key: const Key('ftp_run_now_btn'),
    //             onPressed: provider.canRunNow ? provider.runNow : null,
    //             icon: const Icon(Icons.play_arrow_rounded, size: 18),
    //             label: const Text('Run Now'),
    //           ),
    //         ],
    //       ],
    //     ];
    //
    //     final spinner = (provider.isUploading || provider.isTestingConnection)
    //         ? Container(
    //             width: 14,
    //             height: 14,
    //             margin: const EdgeInsets.only(right: 8),
    //             child: CircularProgressIndicator(
    //               strokeWidth: 2,
    //               valueColor: AlwaysStoppedAnimation<Color>(accentColor),
    //             ),
    //           )
    //         : null;
    //
    //     final statusText = Text(
    //       provider.currentStatus,
    //       style: TextStyle(
    //         fontWeight: FontWeight.w600,
    //         color: context.textPrimary,
    //         fontSize: 13,
    //       ),
    //       maxLines: 1,
    //       overflow: TextOverflow.ellipsis,
    //     );
    //
    //     final statBadges = [
    //       StatBadge(
    //         title: 'Uploaded',
    //         value: provider.filesUploaded.toString(),
    //         color: context.successColor,
    //         icon: Icons.cloud_done_rounded,
    //       ),
    //       StatBadge(
    //         title: 'Skipped',
    //         value: provider.filesSkipped.toString(),
    //         color: context.warningColor,
    //         icon: Icons.fast_forward_rounded,
    //       ),
    //       StatBadge(
    //         title: 'Errors',
    //         value: provider.errors.toString(),
    //         color: context.errorColor,
    //         icon: Icons.error,
    //       ),
    //     ];
    //
    //     return LayoutBuilder(
    //       builder: (context, constraints) {
    //         if (constraints.maxWidth >= 1060) {
    //           return Row(
    //             children: [
    //               ...actionButtons,
    //               const SizedBox(width: 14),
    //               ?spinner,
    //               Expanded(child: statusText),
    //               const SizedBox(width: 8),
    //               statBadges[0],
    //               const SizedBox(width: 8),
    //               statBadges[1],
    //               const SizedBox(width: 8),
    //               statBadges[2],
    //             ],
    //           );
    //         }
    //
    //         return SizedBox(
    //           width: double.infinity,
    //           child: Wrap(
    //             spacing: 12,
    //             runSpacing: 8,
    //             alignment: WrapAlignment.spaceBetween,
    //             crossAxisAlignment: WrapCrossAlignment.center,
    //             children: [
    //               Row(
    //                 mainAxisSize: MainAxisSize.min,
    //                 children: [
    //                   ...actionButtons,
    //                   const SizedBox(width: 12),
    //                   ?spinner,
    //                   ConstrainedBox(
    //                     constraints: BoxConstraints(
    //                       maxWidth: (constraints.maxWidth - 360).clamp(
    //                         160.0,
    //                         420.0,
    //                       ),
    //                     ),
    //                     child: statusText,
    //                   ),
    //                 ],
    //               ),
    //               Wrap(spacing: 8, runSpacing: 6, children: statBadges),
    //             ],
    //           ),
    //         );
    //       },
    //     );
    // Gene - Nov, 24, 2026: Add Run Selected... button for Multiple Sources and wrap action buttons cleanly to prevent 980x680 overflow.
    final actionButtons = <Widget>[
      if (!provider.isProcessing) ...[
        if (!provider.enableSchedule)
          ElevatedButton.icon(
            key: const Key('ftp_start_upload_btn'),
            onPressed: provider.canRunNow ? provider.runNow : null,
            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
            label: const Text('Start Upload'),
          )
        else ...[
          ElevatedButton.icon(
            key: const Key('ftp_start_schedule_btn'),
            onPressed: provider.canArmSchedule ? provider.startSchedule : null,
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: const Text('Start Schedule'),
          ),
          OutlinedButton.icon(
            key: const Key('ftp_run_now_btn'),
            onPressed: provider.canRunNow ? provider.runNow : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Run Now'),
          ),
        ],
      ] else ...[
        ElevatedButton.icon(
          key: const Key('ftp_stop_btn'),
          onPressed: provider.stop,
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('Stop'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
        ),
        if (provider.isScheduleArmed && !provider.isUploading)
          OutlinedButton.icon(
            key: const Key('ftp_run_now_btn'),
            onPressed: provider.canRunNow ? provider.runNow : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Run Now'),
          ),
      ],
      if (provider.useMultipleSources && !provider.isUploading)
        OutlinedButton.icon(
          key: const Key('ftp_run_selected_btn'),
          onPressed: provider.canRunSelected
              ? () => _showRunSelectedSourcesDialog(context, provider)
              : null,
          icon: const Icon(Icons.checklist_rounded, size: 18),
          label: const Text('Run Selected...'),
        ),
    ];

    final actionButtonsWrap = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actionButtons,
    );

    final spinner = (provider.isUploading || provider.isTestingConnection)
        ? Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 8),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          )
        : null;

    final statusText = Text(
      provider.currentStatus,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: context.textPrimary,
        fontSize: 13,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final statBadges = [
      StatBadge(
        title: 'Uploaded',
        value: provider.filesUploaded.toString(),
        color: context.successColor,
        icon: Icons.cloud_done_rounded,
      ),
      StatBadge(
        title: 'Skipped',
        value: provider.filesSkipped.toString(),
        color: context.warningColor,
        icon: Icons.fast_forward_rounded,
      ),
      StatBadge(
        title: 'Errors',
        value: provider.errors.toString(),
        color: context.errorColor,
        icon: Icons.error,
      ),
    ];

    //     final singleRowBreakpoint =
    //         (provider.useMultipleSources && provider.enableSchedule)
    //         ? 1220.0
    //         : 1060.0;
    // Gene - Nov, 24, 2026: Raise single-row breakpoint when Run Selected... is paired with schedule or single-source buttons so 1280px viewports never overflow.
    final singleRowBreakpoint = provider.useMultipleSources
        ? (provider.enableSchedule ? 1380.0 : 1140.0)
        : 1060.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= singleRowBreakpoint) {
          return Row(
            children: [
              actionButtonsWrap,
              const SizedBox(width: 14),
              ?spinner,
              Expanded(child: statusText),
              const SizedBox(width: 8),
              statBadges[0],
              const SizedBox(width: 8),
              statBadges[1],
              const SizedBox(width: 8),
              statBadges[2],
            ],
          );
        }

        return SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              actionButtonsWrap,
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (constraints.maxWidth - 280).clamp(160.0, 440.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?spinner,
                    Flexible(child: statusText),
                  ],
                ),
              ),
              Wrap(spacing: 8, runSpacing: 6, children: statBadges),
            ],
          ),
        );
      },
    );
  }

  // Gene - Nov, 23, 2026: Compact live transfer progress bar for active uploads (UI-only).
  Widget _buildUploadProgressBar(
    BuildContext context,
    FtpFilesProvider provider,
    Color accentColor,
  ) {
    final progress = (provider.activeUploadProgress ?? 0.0).clamp(0.0, 1.0);
    final pct = (progress * 100).toStringAsFixed(1);
    final fileName = provider.activeUploadFileName ?? '';
    final sentStr = FtpFilesProvider.formatByteSize(
      provider.activeUploadSentBytes,
    );
    final totalStr = FtpFilesProvider.formatByteSize(
      provider.activeUploadTotalBytes,
    );
    final speedStr = provider.activeUploadBytesPerSecond > 0
        ? ' • ${FtpFilesProvider.formatByteSize(provider.activeUploadBytesPerSecond.round())}/s'
        : '';

    return Container(
      key: const Key('ftp_upload_progress_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: NeumorphicTheme.recessedDecoration(context, radius: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_upload_outlined, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct% ($sentStr / $totalStr$speedStr)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: context.border.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showUploadSourcesDialog(
    BuildContext context,
    FtpFilesProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (_) => _FtpUploadSourcesDialog(provider: provider),
    );
  }

  // Gene - Nov, 24, 2026: Show one-off Run Selected Sources picker dialog.
  void _showRunSelectedSourcesDialog(
    BuildContext context,
    FtpFilesProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (_) => _RunSelectedSourcesDialog(provider: provider),
    );
  }

  void _showAdvancedSettingsDialog(
    BuildContext context,
    FtpFilesProvider provider,
    Color accentColor,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ChangeNotifierProvider<FtpFilesProvider>.value(
          value: provider,
          child: Consumer<FtpFilesProvider>(
            builder: (context, provider, child) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.settings, size: 22, color: accentColor),
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
                        _sectionLabel(context, '📅 File Date Filter'),
                        const SizedBox(height: 8),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: 170,
                              child: DropdownButtonFormField<FtpDateMode>(
                                key: const Key('ftp_date_mode_dropdown'),
                                isExpanded: true,
                                initialValue: provider.dateMode,
                                decoration: const InputDecoration(
                                  labelText: 'Date Filter Mode',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                ),
                                dropdownColor: context.cardBg,
                                items: FtpDateMode.values
                                    .map(
                                      (mode) => DropdownMenuItem<FtpDateMode>(
                                        value: mode,
                                        child: Text(
                                          mode.label,
                                          style: TextStyle(
                                            color: context.textPrimary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: provider.isProcessing
                                    ? null
                                    : (val) {
                                        if (val != null) {
                                          provider.setDateMode(val);
                                        }
                                      },
                              ),
                            ),
                            if (provider.dateMode == FtpDateMode.daysAgo)
                              SizedBox(
                                width: 110,
                                child: TextFormField(
                                  initialValue: provider.daysAgo.toString(),
                                  enabled: !provider.isProcessing,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (val) {
                                    final parsed = int.tryParse(val);
                                    if (parsed != null) {
                                      provider.setDaysAgo(parsed);
                                    }
                                  },
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontSize: 13,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Days Ago',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            if (provider.dateMode == FtpDateMode.specificDate)
                              SizedBox(
                                width: 150,
                                child: _buildDatePicker(
                                  context,
                                  label: 'Target Date',
                                  date: provider.specificDate,
                                  enabled: !provider.isProcessing,
                                  onPicked: provider.setSpecificDate,
                                ),
                              ),
                            if (provider.dateMode == FtpDateMode.dateRange) ...[
                              SizedBox(
                                width: 145,
                                child: _buildDatePicker(
                                  context,
                                  label: 'From',
                                  date: provider.fromDate,
                                  enabled: !provider.isProcessing,
                                  onPicked: provider.setFromDate,
                                ),
                              ),
                              SizedBox(
                                width: 145,
                                child: _buildDatePicker(
                                  context,
                                  label: 'To',
                                  date: provider.toDate,
                                  enabled: !provider.isProcessing,
                                  onPicked: provider.setToDate,
                                ),
                              ),
                            ],
                            ToggleButtons(
                              isSelected: [
                                provider.dateType == FtpDateType.creation,
                                provider.dateType == FtpDateType.modified,
                              ],
                              onPressed: provider.isProcessing
                                  ? null
                                  : (index) {
                                      provider.setDateType(
                                        index == 0
                                            ? FtpDateType.creation
                                            : FtpDateType.modified,
                                      );
                                    },
                              borderRadius: BorderRadius.circular(8),
                              constraints: const BoxConstraints(
                                minHeight: 34,
                                minWidth: 110,
                              ),
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('Creation Date'),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('Modified Date'),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Divider(color: context.border, thickness: 1),
                        const SizedBox(height: 8),

                        // ── Upload & Reliability ──
                        _sectionLabel(context, '📁 Upload & Reliability'),
                        const SizedBox(height: 6),
                        //                         _buildOptionCheckbox(
                        //                           context,
                        //                           value: provider.includeSubfolders,
                        //                           enabled: !provider.isProcessing,
                        //                           label: 'Include nested subfolders',
                        //                           subtitle:
                        //                               'Recursively scan subdirectories and mirror relative folders remotely',
                        //                           onChanged: provider.setIncludeSubfolders,
                        //                         ),
                        // Gene - Nov, 23, 2026: Clarify Include nested subfolders behavior when Subfolders filter is blank.
                        _buildOptionCheckbox(
                          context,
                          value: provider.includeSubfolders,
                          enabled: !provider.isProcessing,
                          label: 'Include nested subfolders',
                          subtitle:
                              'When Subfolders is blank, scans and mirrors all subfolders remotely',
                          onChanged: provider.setIncludeSubfolders,
                        ),
                        _buildOptionCheckbox(
                          context,
                          value: provider.skipIfExists,
                          enabled: !provider.isProcessing,
                          label: 'Skip if already on FTP (matching size)',
                          subtitle:
                              'Skips identical files and re-uploads partial size mismatches',
                          onChanged: provider.setSkipIfExists,
                        ),
                        _buildOptionCheckbox(
                          context,
                          value: provider.verifySizeAfterUpload,
                          enabled: !provider.isProcessing,
                          label: 'Verify file size after upload',
                          subtitle:
                              'Confirms remote byte count matches local file size',
                          onChanged: provider.setVerifySizeAfterUpload,
                        ),
                        _buildOptionCheckbox(
                          context,
                          key: const Key('ftp_dry_run_checkbox'),
                          value: provider.dryRun,
                          enabled: !provider.isProcessing,
                          label: 'Dry-Run mode (simulate without uploading)',
                          subtitle:
                              'Scans files and logs what would upload or skip without transferring data',
                          onChanged: provider.setDryRun,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _intDropdown(
                              context,
                              label: 'Timeout (s)',
                              value: provider.timeoutSeconds,
                              options: const [15, 30, 60, 120, 300],
                              enabled: !provider.isProcessing,
                              onChanged: provider.setTimeoutSeconds,
                            ),
                            _intDropdown(
                              context,
                              label: 'Retry Count',
                              value: provider.retryCount,
                              options: const [1, 2, 3, 5, 10],
                              enabled: !provider.isProcessing,
                              onChanged: provider.setRetryCount,
                            ),
                            _intDropdown(
                              context,
                              label: 'Retry Delay (s)',
                              value: provider.retryDelaySeconds,
                              options: const [1, 3, 5, 10, 15, 30],
                              enabled: !provider.isProcessing,
                              onChanged: provider.setRetryDelaySeconds,
                            ),
                            // Gene - Nov, 23, 2026: Add Log Retention dropdown matching LOG_KEEP_DAYS behavior.
                            _intDropdown(
                              context,
                              key: const Key('ftp_log_retention_dropdown'),
                              label: 'Log Retention',
                              value: provider.logKeepDays,
                              options: const [0, 7, 14, 30, 60, 90, 180, 365],
                              enabled: !provider.isProcessing,
                              width: 145,
                              itemLabel: (v) => v == 0 ? 'Forever' : '$v days',
                              onChanged: provider.setLogKeepDays,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Divider(color: context.border, thickness: 1),
                        const SizedBox(height: 8),

                        // ── Schedule ──
                        _sectionLabel(context, '⏰ Schedule'),
                        const SizedBox(height: 8),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  key: const Key(
                                    'ftp_enable_schedule_checkbox',
                                  ),
                                  value: provider.enableSchedule,
                                  onChanged: provider.isProcessing
                                      ? null
                                      : (val) => provider.setEnableSchedule(
                                          val ?? false,
                                        ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Enable Schedule',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: context.textSecondary,
                                ),
                              ),
                              //                               const SizedBox(width: 12),
                              //                               SizedBox(
                              //                                 width: 115,
                              //                                 child: StyledTimePicker(
                              //                                   label: 'Run At',
                              //                                   time: provider.runTime,
                              //                                   enabled:
                              //                                       !provider.isProcessing &&
                              //                                       provider.enableSchedule,
                              //                                   onPicked: provider.setRunTime,
                              //                                 ),
                              //                               ),
                              //                               const SizedBox(width: 14),
                              //                               const VerticalDivider(width: 1, thickness: 1),
                              //                               const SizedBox(width: 10),
                              // Gene - Nov, 24, 2026: Replace single Run At picker with Start and End time window pickers.
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 110,
                                child: StyledTimePicker(
                                  key: const Key(
                                    'ftp_schedule_start_time_picker',
                                  ),
                                  label: 'Start',
                                  time: provider.runTime,
                                  enabled:
                                      !provider.isProcessing &&
                                      provider.enableSchedule,
                                  onPicked: provider.setRunTime,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 110,
                                child: StyledTimePicker(
                                  key: const Key(
                                    'ftp_schedule_end_time_picker',
                                  ),
                                  label: 'End',
                                  time: provider.runEndTime,
                                  enabled:
                                      !provider.isProcessing &&
                                      provider.enableSchedule,
                                  onPicked: provider.setRunEndTime,
                                ),
                              ),
                              const SizedBox(width: 12),
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
                                            provider.runDays[entry.key] ?? true,
                                        onSelected:
                                            (!provider.isProcessing &&
                                                provider.enableSchedule)
                                            ? (val) => provider.setRunDay(
                                                entry.key,
                                                val,
                                              )
                                            : null,
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
                        if (provider.enableSchedule &&
                            !provider.hasCheckedScheduleDays) ...[
                          const SizedBox(height: 6),
                          //                           const Text(
                          //                             'Select at least one day to arm the schedule.',
                          //                             style: TextStyle(
                          //                               fontSize: 12,
                          //                               color: AppColors.error,
                          //                               fontWeight: FontWeight.w500,
                          //                             ),
                          //                           ),
                          // Gene - Nov, 22, 2026: Use theme-aware errorColor on schedule validation message.
                          Text(
                            'Select at least one day to arm the schedule.',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.errorColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ] else if (provider.enableSchedule &&
                            provider.hasCheckedScheduleDays &&
                            provider.useMultipleSources &&
                            !provider.hasSchedulableSources) ...[
                          // Gene - Nov, 24, 2026: Warn user when all active sources are Manual Only and cannot arm schedule.
                          const SizedBox(height: 6),
                          Text(
                            'All active upload sources are set to Manual Only. Change at least one source schedule to arm.',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.errorColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ] else if (provider.enableSchedule &&
                            provider.hasCheckedScheduleDays) ...[
                          // Gene - Nov, 24, 2026: Explain active Start/End runtime window behavior (same-day, overnight, or no end cutoff).
                          const SizedBox(height: 6),
                          Builder(
                            builder: (context) {
                              final startMin =
                                  provider.runTime.hour * 60 +
                                  provider.runTime.minute;
                              final endMin =
                                  provider.runEndTime.hour * 60 +
                                  provider.runEndTime.minute;
                              final startStr = provider.runTime.format(context);
                              final endStr = provider.runEndTime.format(
                                context,
                              );
                              final String helperText;
                              if (!provider.hasEndTimeLimit) {
                                helperText =
                                    'Start and End match — scheduled runs will run until completion (no end cutoff).';
                              } else if (endMin < startMin) {
                                helperText =
                                    'Overnight window — runs from $startStr until $endStr the next day.';
                              } else {
                                helperText =
                                    'Runs from $startStr until $endStr on selected days; stops cleanly at End time.';
                              }
                              return Text(
                                helperText,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: context.textMuted,
                                  fontStyle: FontStyle.italic,
                                ),
                              );
                            },
                          ),
                        ],

                        const SizedBox(height: 12),
                        Divider(color: context.border, thickness: 1),
                        const SizedBox(height: 8),

                        // ── Completion ──
                        _sectionLabel(context, '✅ Completion'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'When Complete',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: context.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            ToggleButtons(
                              isSelected: [
                                provider.onCompletionAction == 'repeat',
                                provider.onCompletionAction == 'stop',
                              ],
                              onPressed: provider.isProcessing
                                  ? null
                                  : (index) {
                                      provider.setOnCompletionAction(
                                        index == 0 ? 'repeat' : 'stop',
                                      );
                                    },
                              borderRadius: BorderRadius.circular(8),
                              constraints: const BoxConstraints(
                                minHeight: 30,
                                minWidth: 85,
                              ),
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.repeat, size: 16),
                                      SizedBox(width: 4),
                                      Text('Repeat'),
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
                                provider.onCompletionAction == 'repeat'
                                    ? 'Will wait and re-run on the next scheduled day & time'
                                    : 'Will stop after 1 scheduled run',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.textMuted,
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

  Widget _buildOptionCheckbox(
    BuildContext context, {
    Key? key,
    required bool value,
    required bool enabled,
    required String label,
    required String subtitle,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              key: key,
              value: value,
              onChanged: enabled ? (val) => onChanged(val ?? false) : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: context.textMuted,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  //   Widget _intDropdown(
  //     BuildContext context, {
  //     required String label,
  //     required int value,
  //     required List<int> options,
  //     required bool enabled,
  //     required ValueChanged<int> onChanged,
  //   }) {
  //     final effectiveOptions = options.contains(value)
  //         ? options
  //         : ([...options, value]..sort());
  //
  //     return SizedBox(
  //       width: 130,
  //       child: DropdownButtonFormField<int>(
  //         isExpanded: true,
  //         initialValue: value,
  //         decoration: InputDecoration(
  //           labelText: label,
  //           isDense: true,
  //           contentPadding: const EdgeInsets.symmetric(
  //             horizontal: 10,
  //             vertical: 8,
  //           ),
  //         ),
  //         dropdownColor: context.cardBg,
  //         items: effectiveOptions
  //             .map(
  //               (v) => DropdownMenuItem<int>(
  //                 value: v,
  //                 child: Text(
  //                   v.toString(),
  //                   style: TextStyle(color: context.textPrimary, fontSize: 13),
  //                 ),
  //               ),
  //             )
  //             .toList(),
  //         onChanged: enabled
  //             ? (val) {
  //                 if (val != null) onChanged(val);
  //               }
  //             : null,
  //       ),
  //     );
  //   }
  // Gene - Nov, 23, 2026: Support optional key, width, and custom itemLabel formatting on _intDropdown.
  Widget _intDropdown(
    BuildContext context, {
    Key? key,
    required String label,
    required int value,
    required List<int> options,
    required bool enabled,
    required ValueChanged<int> onChanged,
    double width = 130,
    String Function(int)? itemLabel,
  }) {
    final effectiveOptions = options.contains(value)
        ? options
        : ([...options, value]..sort());

    return SizedBox(
      width: width,
      child: DropdownButtonFormField<int>(
        key: key,
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        dropdownColor: context.cardBg,
        items: effectiveOptions
            .map(
              (v) => DropdownMenuItem<int>(
                value: v,
                child: Text(
                  itemLabel != null ? itemLabel(v) : v.toString(),
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                ),
              ),
            )
            .toList(),
        onChanged: enabled
            ? (val) {
                if (val != null) onChanged(val);
              }
            : null,
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
              if (picked != null) onPicked(picked);
            }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            suffixIcon: Icon(
              Icons.calendar_today,
              size: 15,
              color: context.textMuted,
            ),
          ),
          child: Text(
            dateFormat.format(date),
            style: TextStyle(color: context.textPrimary, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}

// Gene - Nov, 23, 2026: Shared SnackBar helper for FTP import/export notifications.
void _showFtpActionSnackBar(BuildContext context, String message) {
  final isError = message.startsWith('Failed') || message.startsWith('No ');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      duration: const Duration(seconds: 4),
    ),
  );
}

class _FtpUploadSourcesDialog extends StatefulWidget {
  final FtpFilesProvider provider;

  const _FtpUploadSourcesDialog({required this.provider});

  @override
  State<_FtpUploadSourcesDialog> createState() =>
      _FtpUploadSourcesDialogState();
}

// class _FtpUploadSourcesDialogState extends State<_FtpUploadSourcesDialog> {
//   final List<TextEditingController> _nameControllers = [];
//   final List<TextEditingController> _subfoldersControllers = [];
//   final List<TextEditingController> _destControllers = [];
// 
//   @override
//   void initState() {
//     super.initState();
//     _rebuildControllers();
//   }
// 
//   @override
//   void dispose() {
//     _disposeControllers();
//     super.dispose();
//   }
// 
//   void _disposeControllers() {
//     for (final c in _nameControllers) {
//       c.dispose();
//     }
//     for (final c in _subfoldersControllers) {
//       c.dispose();
//     }
//     for (final c in _destControllers) {
//       c.dispose();
//     }
//     _nameControllers.clear();
//     _subfoldersControllers.clear();
//     _destControllers.clear();
//   }
// 
//   void _rebuildControllers() {
//     _disposeControllers();
//     for (final source in widget.provider.uploadSources) {
//       _nameControllers.add(TextEditingController(text: source.name));
//       _subfoldersControllers.add(
//         TextEditingController(text: source.subfolders),
//       );
//       _destControllers.add(TextEditingController(text: source.ftpDest));
//     }
//   }
// 
//   @override
//   Widget build(BuildContext context) {
//     final sources = widget.provider.uploadSources;
//     final accentColor = context.ftpAccent;
// 
//     return AlertDialog(
//       // Gene - Nov, 23, 2026: Add Import and Export Upload Sources actions to Upload Sources dialog title bar.
//       title: Row(
//         children: [
//           Icon(Icons.folder_copy, size: 22, color: accentColor),
//           const SizedBox(width: 8),
//           const Text('Upload Sources', style: TextStyle(fontSize: 18)),
//           const Spacer(),
//           TextButton.icon(
//             key: const Key('ftp_sources_import_btn'),
//             icon: const Icon(Icons.file_upload_outlined, size: 17),
//             label: const Text('Import', style: TextStyle(fontSize: 12)),
//             style: TextButton.styleFrom(
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//               visualDensity: VisualDensity.compact,
//             ),
//             onPressed: () async {
//               final message = await widget.provider
//                   .importUploadSourcesFromDisk();
//               if (!context.mounted || message == null) return;
//               setState(_rebuildControllers);
//               _showFtpActionSnackBar(context, message);
//             },
//           ),
//           TextButton.icon(
//             key: const Key('ftp_sources_export_btn'),
//             icon: const Icon(Icons.file_download_outlined, size: 17),
//             label: const Text('Export', style: TextStyle(fontSize: 12)),
//             style: TextButton.styleFrom(
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//               visualDensity: VisualDensity.compact,
//             ),
//             onPressed: () async {
//               final message = await widget.provider.exportUploadSourcesToDisk();
//               if (!context.mounted || message == null) return;
//               _showFtpActionSnackBar(context, message);
//             },
//           ),
//           TextButton.icon(
//             icon: const Icon(Icons.add, size: 18),
//             label: const Text('Add Source', style: TextStyle(fontSize: 13)),
//             onPressed: () {
//               widget.provider.addUploadSource();
//               setState(_rebuildControllers);
//             },
//           ),
//         ],
//       ),
//       contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
//       content: SizedBox(
//         width: MediaQuery.of(context).size.width * 0.72,
//         height: MediaQuery.of(context).size.height * 0.54,
//         child: ListView.separated(
//           itemCount: sources.length,
//           // Gene - Nov, 22, 2026: Use theme-aware context.border in Upload Sources divider.
//           separatorBuilder: (_, _) =>
//               Divider(height: 18, color: context.border.withValues(alpha: 0.5)),
//           itemBuilder: (context, i) {
//             final FtpUploadSource src = sources[i];
//             return Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     // Gene - Nov, 23, 2026: Per-source enable/disable checkbox to pause a source without deleting it.
//                     SizedBox(
//                       width: 24,
//                       height: 24,
//                       child: Checkbox(
//                         key: Key('ftp_source_enabled_$i'),
//                         value: src.enabled,
//                         onChanged: (val) {
//                           widget.provider.setSourceEnabledAt(i, val ?? true);
//                           setState(() {});
//                         },
//                         visualDensity: VisualDensity.compact,
//                         materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
//                       ),
//                     ),
//                     const SizedBox(width: 6),
//                     Text(
//                       'Source ${i + 1}',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         fontSize: 13,
//                         color: src.enabled
//                             ? context.textMuted
//                             : context.textMuted.withValues(alpha: 0.6),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     SizedBox(
//                       width: 170,
//                       child: TextField(
//                         controller: _nameControllers[i],
//                         onChanged: (val) =>
//                             widget.provider.setSourceNameAt(i, val),
//                         style: TextStyle(
//                           fontSize: 12,
//                           color: context.textPrimary,
//                         ),
//                         decoration: const InputDecoration(
//                           labelText: 'Label',
//                           hintText: 'e.g. Backups',
//                           isDense: true,
//                           contentPadding: EdgeInsets.symmetric(
//                             horizontal: 8,
//                             vertical: 6,
//                           ),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     Text(
//                       'Run Order:',
//                       style: TextStyle(
//                         fontSize: 12,
//                         color: context.textSecondary,
//                       ),
//                     ),
//                     const SizedBox(width: 4),
//                     SizedBox(
//                       width: 52,
//                       height: 28,
//                       child: DropdownButton<int>(
//                         value: src.runOrder.clamp(1, 20),
//                         isDense: true,
//                         dropdownColor: context.cardBg,
//                         underline: Container(height: 1, color: context.border),
//                         items: List.generate(20, (n) => n + 1)
//                             .map(
//                               (v) => DropdownMenuItem<int>(
//                                 value: v,
//                                 child: Text(
//                                   '$v',
//                                   style: TextStyle(
//                                     fontSize: 13,
//                                     color: context.textPrimary,
//                                   ),
//                                 ),
//                               ),
//                             )
//                             .toList(),
//                         onChanged: (val) {
//                           if (val != null) {
//                             widget.provider.setSourceRunOrderAt(i, val);
//                             setState(() {});
//                           }
//                         },
//                       ),
//                     ),
//                     const Spacer(),
//                     // Gene - Nov, 22, 2026: Use theme-aware errorColor for remove upload source icon.
//                     if (sources.length > 1)
//                       IconButton(
//                         icon: Icon(
//                           Icons.delete_outline,
//                           size: 18,
//                           color: context.errorColor,
//                         ),
//                         tooltip: 'Remove source',
//                         onPressed: () {
//                           widget.provider.removeUploadSource(i);
//                           setState(_rebuildControllers);
//                         },
//                       ),
//                   ],
//                 ),
//                 const SizedBox(height: 6),
//                 // Gene - Nov, 23, 2026: Dim disabled upload sources visually and clarify blank Subfolders hint.
//                 Opacity(
//                   opacity: src.enabled ? 1.0 : 0.55,
//                   child: Column(
//                     children: [
//                       PathRow(
//                         label: 'Local Path',
//                         path: src.localPath,
//                         onPick: () async {
//                           await widget.provider.pickSourceAt(i);
//                           if (mounted) setState(() {});
//                         },
//                         onChanged: (val) {
//                           widget.provider.setSourcePathAt(i, val);
//                         },
//                       ),
//                       const SizedBox(height: 6),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: TextField(
//                               controller: _subfoldersControllers[i],
//                               onChanged: (val) =>
//                                   widget.provider.setSourceSubfoldersAt(i, val),
//                               style: TextStyle(
//                                 fontSize: 12,
//                                 color: context.textPrimary,
//                               ),
//                               decoration: const InputDecoration(
//                                 labelText:
//                                     'Subfolders (optional, comma-separated)',
//                                 hintText: 'Blank = root (or all if nested on)',
//                                 isDense: true,
//                                 contentPadding: EdgeInsets.symmetric(
//                                   horizontal: 10,
//                                   vertical: 8,
//                                 ),
//                               ),
//                             ),
//                           ),
//                           const SizedBox(width: 8),
//                           Expanded(
//                             child: TextField(
//                               controller: _destControllers[i],
//                               onChanged: (val) =>
//                                   widget.provider.setSourceFtpDestAt(i, val),
//                               style: TextStyle(
//                                 fontSize: 12,
//                                 color: context.textPrimary,
//                               ),
//                               decoration: const InputDecoration(
//                                 labelText: 'FTP Dest Folder (optional)',
//                                 hintText: 'Leave blank for FTP root',
//                                 isDense: true,
//                                 contentPadding: EdgeInsets.symmetric(
//                                   horizontal: 10,
//                                   vertical: 8,
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             );
//           },
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.of(context).pop(),
//           child: const Text('Done'),
//         ),
//       ],
//     );
//   }
// }
// Gene - Nov, 24, 2026: Add per-source schedule cadence, weekly/monthly pickers, monthly reset, and date filter override controls in Upload Sources dialog, plus _RunSelectedSourcesDialog.
class _FtpUploadSourcesDialogState extends State<_FtpUploadSourcesDialog> {
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _subfoldersControllers = [];
  final List<TextEditingController> _destControllers = [];
  final List<TextEditingController> _dateDaysControllers = [];

  @override
  void initState() {
    super.initState();
    _rebuildControllers();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _nameControllers) {
      c.dispose();
    }
    for (final c in _subfoldersControllers) {
      c.dispose();
    }
    for (final c in _destControllers) {
      c.dispose();
    }
    for (final c in _dateDaysControllers) {
      c.dispose();
    }
    _nameControllers.clear();
    _subfoldersControllers.clear();
    _destControllers.clear();
    _dateDaysControllers.clear();
  }

  void _rebuildControllers() {
    _disposeControllers();
    for (final source in widget.provider.uploadSources) {
      _nameControllers.add(TextEditingController(text: source.name));
      _subfoldersControllers.add(
        TextEditingController(text: source.subfolders),
      );
      _destControllers.add(TextEditingController(text: source.ftpDest));
      _dateDaysControllers.add(
        TextEditingController(text: source.dateFilterDays.toString()),
      );
    }
  }

  Widget _statusChip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.provider.uploadSources;
    final accentColor = context.ftpAccent;
    //     final now = DateTime.now();
    // Gene - Nov, 24, 2026: Use provider.currentNow for deterministic monthly status evaluation.
    final now = widget.provider.currentNow;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.folder_copy, size: 22, color: accentColor),
          const SizedBox(width: 8),
          const Text('Upload Sources', style: TextStyle(fontSize: 18)),
          const Spacer(),
          TextButton.icon(
            key: const Key('ftp_sources_import_btn'),
            icon: const Icon(Icons.file_upload_outlined, size: 17),
            label: const Text('Import', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              final message = await widget.provider
                  .importUploadSourcesFromDisk();
              if (!context.mounted || message == null) return;
              setState(_rebuildControllers);
              _showFtpActionSnackBar(context, message);
            },
          ),
          TextButton.icon(
            key: const Key('ftp_sources_export_btn'),
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: const Text('Export', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              final message = await widget.provider.exportUploadSourcesToDisk();
              if (!context.mounted || message == null) return;
              _showFtpActionSnackBar(context, message);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Source', style: TextStyle(fontSize: 13)),
            onPressed: () {
              widget.provider.addUploadSource();
              setState(_rebuildControllers);
            },
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.76,
        height: MediaQuery.of(context).size.height * 0.62,
        child: ListView.separated(
          itemCount: sources.length,
          separatorBuilder: (_, _) =>
              Divider(height: 18, color: context.border.withValues(alpha: 0.5)),
          itemBuilder: (context, i) {
            final FtpUploadSource src = sources[i];
            final hasWeeklyOverlap = src.weeklyDays.any(
              (d) => widget.provider.runDays[d] == true,
            );
            final targetDay = src.resolveMonthlyTargetDay(now.year, now.month);
            final isDoneThisMonth = src.isCompletedForMonth(now);

            return Column(
              key: ValueKey(
                'ftp_source_item_${i}_${widget.provider.settingsVersion}',
              ),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        key: Key('ftp_source_enabled_$i'),
                        value: src.enabled,
                        onChanged: (val) {
                          widget.provider.setSourceEnabledAt(i, val ?? true);
                          setState(() {});
                        },
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Source ${i + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: src.enabled
                            ? context.textMuted
                            : context.textMuted.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 170,
                      child: TextField(
                        controller: _nameControllers[i],
                        onChanged: (val) =>
                            widget.provider.setSourceNameAt(i, val),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Label',
                          hintText: 'e.g. Backups',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Run Order:',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 52,
                      height: 28,
                      child: DropdownButton<int>(
                        value: src.runOrder.clamp(1, 20),
                        isDense: true,
                        dropdownColor: context.cardBg,
                        underline: Container(height: 1, color: context.border),
                        items: List.generate(20, (n) => n + 1)
                            .map(
                              (v) => DropdownMenuItem<int>(
                                value: v,
                                child: Text(
                                  '$v',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.textPrimary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            widget.provider.setSourceRunOrderAt(i, val);
                            setState(() {});
                          }
                        },
                      ),
                    ),
                    const Spacer(),
                    if (sources.length > 1)
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: context.errorColor,
                        ),
                        tooltip: 'Remove source',
                        onPressed: () {
                          widget.provider.removeUploadSource(i);
                          setState(_rebuildControllers);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: src.enabled ? 1.0 : 0.55,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PathRow(
                        label: 'Local Path',
                        path: src.localPath,
                        onPick: () async {
                          await widget.provider.pickSourceAt(i);
                          if (mounted) setState(() {});
                        },
                        onChanged: (val) {
                          widget.provider.setSourcePathAt(i, val);
                        },
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _subfoldersControllers[i],
                              onChanged: (val) =>
                                  widget.provider.setSourceSubfoldersAt(i, val),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                labelText:
                                    'Subfolders (optional, comma-separated)',
                                hintText: 'Blank = root (or all if nested on)',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _destControllers[i],
                              onChanged: (val) =>
                                  widget.provider.setSourceFtpDestAt(i, val),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'FTP Dest Folder (optional)',
                                hintText: 'Leave blank for FTP root',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 138,
                            child:
                                DropdownButtonFormField<FtpSourceScheduleMode>(
                              key: Key('ftp_source_schedule_$i'),
                              isExpanded: true,
                              initialValue: src.scheduleMode,
                              decoration: const InputDecoration(
                                labelText: 'Schedule',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              dropdownColor: context.cardBg,
                              items: FtpSourceScheduleMode.values
                                  .map(
                                    (mode) =>
                                        DropdownMenuItem<FtpSourceScheduleMode>(
                                      value: mode,
                                      child: Text(
                                        mode.label,
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  widget.provider.setSourceScheduleModeAt(
                                    i,
                                    val,
                                  );
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                          if (src.scheduleMode ==
                              FtpSourceScheduleMode.weekly) ...[
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
                                key: Key(
                                  'ftp_source_weekly_day_${i}_${entry.key}',
                                ),
                                label: Text(
                                  entry.value,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                selected: src.weeklyDays.contains(entry.key),
                                onSelected: (val) {
                                  widget.provider.setSourceWeeklyDayAt(
                                    i,
                                    entry.key,
                                    val,
                                  );
                                  setState(() {});
                                },
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                              ),
                            if (widget.provider.enableSchedule &&
                                !hasWeeklyOverlap)
                              Text(
                                'No overlap with global schedule days',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.warningColor,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                          if (src.scheduleMode ==
                              FtpSourceScheduleMode.monthly) ...[
                            SizedBox(
                              width: 116,
                              child: DropdownButtonFormField<int>(
                                key: Key('ftp_source_monthly_day_$i'),
                                isExpanded: true,
                                initialValue: src.monthlyDay.clamp(0, 31),
                                decoration: const InputDecoration(
                                  labelText: 'Month Day',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                ),
                                dropdownColor: context.cardBg,
                                items: [
                                  DropdownMenuItem<int>(
                                    value: 0,
                                    child: Text(
                                      'Last day',
                                      style: TextStyle(
                                        color: context.textPrimary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  for (int d = 1; d <= 31; d++)
                                    DropdownMenuItem<int>(
                                      value: d,
                                      child: Text(
                                        'Day $d',
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    widget.provider.setSourceMonthlyDayAt(
                                      i,
                                      val,
                                    );
                                    setState(() {});
                                  }
                                },
                              ),
                            ),
                            if (isDoneThisMonth) ...[
                              _statusChip(
                                context,
                                'Done ${DateFormat('MMM yyyy').format(now)}',
                                context.successColor,
                              ),
                              TextButton.icon(
                                key: Key('ftp_source_monthly_reset_$i'),
                                onPressed: () {
                                  widget.provider
                                      .resetSourceMonthlyCompletionAt(i);
                                  setState(() {});
                                },
                                icon: const Icon(Icons.refresh, size: 15),
                                label: const Text(
                                  'Reset',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ] else if (now.day >= targetDay)
                              _statusChip(
                                context,
                                'Due now (catch-up)',
                                context.warningColor,
                              )
                            else
                              _statusChip(
                                context,
                                'Due Day $targetDay',
                                context.textMuted,
                              ),
                          ],
                          SizedBox(
                            width: 138,
                            child: DropdownButtonFormField<
                                FtpSourceDateFilterMode>(
                              key: Key('ftp_source_date_filter_$i'),
                              isExpanded: true,
                              initialValue: src.dateFilterMode,
                              decoration: const InputDecoration(
                                labelText: 'Date Filter',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              dropdownColor: context.cardBg,
                              items: FtpSourceDateFilterMode.values
                                  .map(
                                    (mode) => DropdownMenuItem<
                                        FtpSourceDateFilterMode>(
                                      value: mode,
                                      child: Text(
                                        mode.label,
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  widget.provider.setSourceDateFilterModeAt(
                                    i,
                                    val,
                                  );
                                  _dateDaysControllers[i].text = widget
                                      .provider
                                      .uploadSources[i]
                                      .dateFilterDays
                                      .toString();
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                          if (src.dateFilterMode ==
                                  FtpSourceDateFilterMode.daysAgo ||
                              src.dateFilterMode ==
                                  FtpSourceDateFilterMode.lastNDays)
                            SizedBox(
                              width: 78,
                              child: TextField(
                                key: Key('ftp_source_date_days_$i'),
                                controller: _dateDaysControllers[i],
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (val) {
                                  final parsed = int.tryParse(val);
                                  if (parsed != null) {
                                    widget.provider.setSourceDateFilterDaysAt(
                                      i,
                                      parsed,
                                    );
                                  }
                                },
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Days',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _RunSelectedSourcesDialog extends StatefulWidget {
  final FtpFilesProvider provider;

  const _RunSelectedSourcesDialog({required this.provider});

  @override
  State<_RunSelectedSourcesDialog> createState() =>
      _RunSelectedSourcesDialogState();
}

class _RunSelectedSourcesDialogState extends State<_RunSelectedSourcesDialog> {
  late final List<({int index, FtpUploadSource source})> _orderedValidSources;
  late final Set<int> _selected;
  bool _markMonthlyCompleted = false;

  @override
  void initState() {
    super.initState();
    final entries = <({int index, FtpUploadSource source})>[];
    for (int i = 0; i < widget.provider.uploadSources.length; i++) {
      final src = widget.provider.uploadSources[i];
      if (src.isValid) {
        entries.add((index: i, source: src));
      }
    }
    entries.sort((a, b) {
      final cmp = a.source.runOrder.compareTo(b.source.runOrder);
      return cmp != 0 ? cmp : a.index.compareTo(b.index);
    });
    _orderedValidSources = entries;
    _selected = {
      for (final e in entries)
        if (e.source.enabled) e.index,
    };
  }

  Widget _tagPill(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = context.ftpAccent;
    //     final now = DateTime.now();
    // Gene - Nov, 24, 2026: Use provider.currentNow for deterministic monthly status pills in Run Selected dialog.
    final now = widget.provider.currentNow;
    final hasSelectedMonthly = _orderedValidSources.any(
      (e) =>
          _selected.contains(e.index) &&
          e.source.scheduleMode == FtpSourceScheduleMode.monthly,
    );

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.checklist_rounded, size: 22, color: accentColor),
          const SizedBox(width: 8),
          const Text('Run Selected Sources', style: TextStyle(fontSize: 18)),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      content: SizedBox(
        width: (MediaQuery.of(context).size.width * 0.62).clamp(420.0, 720.0),
        height: (MediaQuery.of(context).size.height * 0.56).clamp(240.0, 460.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pick sources for an immediate one-off upload without changing saved settings.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selected
                        ..clear()
                        ..addAll(_orderedValidSources.map((e) => e.index));
                    });
                  },
                  child: const Text('Select All', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () {
                    setState(_selected.clear);
                  },
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                itemCount: _orderedValidSources.length,
                separatorBuilder: (_, _) => Divider(
                  height: 8,
                  color: context.border.withValues(alpha: 0.45),
                ),
                itemBuilder: (context, pos) {
                  final entry = _orderedValidSources[pos];
                  final idx = entry.index;
                  final src = entry.source;
                  final isChecked = _selected.contains(idx);
                  final destText = src.ftpDest.trim().isEmpty
                      ? '/'
                      : src.ftpDest.trim();

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        if (isChecked) {
                          _selected.remove(idx);
                        } else {
                          _selected.add(idx);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            key: Key('ftp_select_source_$idx'),
                            value: isChecked,
                            onChanged: (val) {
                              setState(() {
                                if (val ?? false) {
                                  _selected.add(idx);
                                } else {
                                  _selected.remove(idx);
                                }
                              });
                            },
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      src.displayName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                    _tagPill(
                                      context,
                                      'Order #${src.runOrder}',
                                      context.textSecondary,
                                    ),
                                    _tagPill(
                                      context,
                                      src.scheduleSummary,
                                      accentColor,
                                    ),
                                    _tagPill(
                                      context,
                                      src.dateFilterSummary,
                                      context.textMuted,
                                    ),
                                    if (!src.enabled)
                                      _tagPill(
                                        context,
                                        'Disabled',
                                        context.warningColor,
                                      ),
                                    if (src.scheduleMode ==
                                            FtpSourceScheduleMode.monthly &&
                                        src.isCompletedForMonth(now))
                                      _tagPill(
                                        context,
                                        'Done ${DateFormat('MMM yyyy').format(now)}',
                                        context.successColor,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${src.localPath} -> $destText',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: context.textMuted,
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
                  );
                },
              ),
            ),
            if (hasSelectedMonthly) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: context.border.withValues(alpha: 0.6)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Checkbox(
                    key: const Key('ftp_select_mark_monthly_checkbox'),
                    value: !widget.provider.dryRun && _markMonthlyCompleted,
                    onChanged: widget.provider.dryRun
                        ? null
                        : (val) {
                            setState(() {
                              _markMonthlyCompleted = val ?? false;
                            });
                          },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Also mark selected Monthly source(s) as completed for this month',
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.provider.dryRun
                                ? context.textMuted
                                : context.textPrimary,
                          ),
                        ),
                        if (widget.provider.dryRun)
                          Text(
                            'Disabled in Dry-Run mode',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          key: const Key('ftp_run_selected_confirm_btn'),
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final picked = Set<int>.from(_selected);
                  final mark =
                      !widget.provider.dryRun && _markMonthlyCompleted;
                  Navigator.of(context).pop();
                  unawaited(
                    widget.provider.runSelectedSources(
                      picked,
                      markMonthlyCompleted: mark,
                    ),
                  );
                },
          icon: const Icon(Icons.cloud_upload_rounded, size: 17),
          label: Text('Upload Selected (${_selected.length})'),
        ),
      ],
    );
  }
}
