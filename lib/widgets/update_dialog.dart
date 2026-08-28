import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/update_provider.dart';
import '../services/update/update_info.dart';
import '../theme/app_theme.dart';

/// Modal shown when a newer release is available. Offers install/download,
/// a session-only "Later", and a persistent "Skip this version".
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateProvider>(
      builder: (context, provider, _) {
        final update = provider.availableUpdate;
        if (update == null) {
          // Update dismissed while the dialog was open (e.g. install handoff).
          return const SizedBox.shrink();
        }
        final silentInstall =
            provider.platform == UpdatePlatform.windows && update.asset != null;

        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                color: context.primaryAccent,
              ),
              const SizedBox(width: 12),
              const Text('Update Available'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Files Utility ${update.version} is available. '
                'You are on ${provider.currentVersion}.',
                style: TextStyle(color: context.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                silentInstall
                    ? 'The update installs in the background and the app '
                          'restarts automatically.'
                    : 'The download page opens in your browser.',
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
              if (provider.isDownloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: provider.downloadProgress),
                const SizedBox(height: 4),
                Text(
                  'Downloading… '
                  '${(provider.downloadProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
              ],
              if (provider.installError != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Update failed: ${provider.installError}. '
                  'Use Download to get it manually.',
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: provider.isDownloading
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      await provider.skipAvailableVersion();
                      navigator.pop();
                    },
              child: const Text('Skip this version'),
            ),
            TextButton(
              onPressed: provider.isDownloading
                  ? null
                  : () {
                      provider.dismiss();
                      Navigator.of(context).pop();
                    },
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: provider.isDownloading
                  ? null
                  : () => provider.applyUpdate(),
              child: Text(silentInstall ? 'Install & Restart' : 'Download'),
            ),
          ],
        );
      },
    );
  }
}
