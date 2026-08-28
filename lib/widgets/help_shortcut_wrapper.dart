import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../views/dialogs/user_manual_dialog.dart';

/// Wraps a screen or widget tree with keyboard shortcut listeners (`F1`, `Cmd+?`, `Ctrl+?`)
/// that contextually launch the [UserManualDialog] focused on [topicId].
class HelpShortcutWrapper extends StatelessWidget {
  final String? topicId;
  final Widget child;

  const HelpShortcutWrapper({
    super.key,
    this.topicId,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () {
          UserManualDialog.show(context, initialTopicId: topicId);
        },
        const SingleActivator(LogicalKeyboardKey.slash, meta: true): () {
          UserManualDialog.show(context, initialTopicId: topicId);
        },
        const SingleActivator(LogicalKeyboardKey.slash, control: true): () {
          UserManualDialog.show(context, initialTopicId: topicId);
        },
        const SingleActivator(LogicalKeyboardKey.slash, meta: true, shift: true): () {
          UserManualDialog.show(context, initialTopicId: topicId);
        },
        const SingleActivator(LogicalKeyboardKey.slash, control: true, shift: true): () {
          UserManualDialog.show(context, initialTopicId: topicId);
        },
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}

/// App bar / header button to open the In-App User Manual and Help Center.
class HelpManualButton extends StatelessWidget {
  final String? topicId;

  const HelpManualButton({
    super.key,
    this.topicId,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.menu_book_rounded, color: context.primaryAccent),
      tooltip: 'User Guide & Manual (F1)',
      onPressed: () => UserManualDialog.show(context, initialTopicId: topicId),
    );
  }
}
