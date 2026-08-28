import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/update_provider.dart';
import '../services/update/update_service.dart';
import '../theme/app_theme.dart';

/// Header icon that runs a user-triggered update check. When an update is
/// found the [UpdateGate] listener opens the dialog; this button only gives
/// feedback for the quiet outcomes (up to date, offline).
class UpdateCheckButton extends StatelessWidget {
  const UpdateCheckButton({super.key});

  Future<void> _check(BuildContext context) async {
    final provider = context.read<UpdateProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await provider.checkManually();

    final status = provider.lastResult?.status;
    if (status == UpdateStatus.upToDate) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Files Utility ${provider.currentVersion} is up to date.',
          ),
        ),
      );
    } else if (status == UpdateStatus.failed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not check for updates. Are you online?'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isChecking = context.select<UpdateProvider, bool>(
      (p) => p.isChecking,
    );
    return IconButton(
      tooltip: 'Check for updates',
      onPressed: isChecking ? null : () => _check(context),
      icon: isChecking
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.primaryAccent,
              ),
            )
          : Icon(Icons.system_update_alt_rounded, color: context.textSecondary),
    );
  }
}
