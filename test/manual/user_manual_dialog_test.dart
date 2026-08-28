import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:files_utility/theme/app_theme.dart';
import 'package:files_utility/views/dialogs/user_manual_dialog.dart';
import 'package:files_utility/widgets/help_shortcut_wrapper.dart';

Widget _buildTestWrapper({String? initialTopicId, Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    home: Scaffold(
      body: Builder(
        builder: (context) {
          return Center(
            child: ElevatedButton(
              onPressed: () => UserManualDialog.show(context, initialTopicId: initialTopicId),
              child: const Text('Open Manual'),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  group('UserManualDialog Widget Tests', () {
    testWidgets('Opens UserManualDialog and displays default topic', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWrapper());
      await tester.tap(find.text('Open Manual'));
      await tester.pumpAndSettle();

      expect(find.byType(UserManualDialog), findsOneWidget);
      expect(find.text('User Manual & Knowledge Base'), findsOneWidget);
      expect(find.text('Getting Started & Overview'), findsWidgets);
      expect(find.text('Application Architecture & Philosophy'), findsOneWidget);
    });

    testWidgets('Deep links to initialTopicId when provided', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWrapper(initialTopicId: 'copy_files'));
      await tester.tap(find.text('Open Manual'));
      await tester.pumpAndSettle();

      expect(find.byType(UserManualDialog), findsOneWidget);
      expect(find.text('Single vs. Multi-Directory Copying'), findsOneWidget);
      expect(find.text('Multi-Directory Setup & Run Order'), findsOneWidget);
    });

    testWidgets('Topic category switching updates the detail panel', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWrapper());
      await tester.tap(find.text('Open Manual'));
      await tester.pumpAndSettle();

      // Tap on Delete Files in master sidebar
      final deleteTopicItem = find.text('Delete Files');
      expect(deleteTopicItem, findsWidgets);
      await tester.tap(deleteTopicItem.first);
      await tester.pumpAndSettle();

      expect(find.text('Safe Retention & Matrix Cleanup'), findsOneWidget);
      expect(find.text('Configuring Year & Month Matrices'), findsOneWidget);
    });

    testWidgets('Live search filters topics in real-time', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWrapper());
      await tester.tap(find.text('Open Manual'));
      await tester.pumpAndSettle();

      // Enter search query
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'resume');
      await tester.pumpAndSettle();

      // Should show Transfer Files (matching resume checkpoint)
      expect(find.text('Transfer Files'), findsWidgets);
      // Non-matching topic should be filtered out from sidebar
      expect(find.text('Delete Files'), findsNothing);
    });

    testWidgets('Empty search results display friendly empty state and clear button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWrapper());
      await tester.tap(find.text('Open Manual'));
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'nonexistentquery12345');
      await tester.pumpAndSettle();

      expect(find.text('No matching topics'), findsOneWidget);
      final clearBtn = find.text('Clear Search');
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // All topics restored
      expect(find.text('Getting Started & Overview'), findsWidgets);
      expect(find.text('Transfer Files'), findsWidgets);
    });

    testWidgets('Footer shortcuts button jumps to Keyboard Shortcuts topic', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWrapper());
      await tester.tap(find.text('Open Manual'));
      await tester.pumpAndSettle();

      final shortcutBtn = find.text('Keyboard Shortcuts Cheat Sheet');
      expect(shortcutBtn, findsOneWidget);
      await tester.tap(shortcutBtn);
      await tester.pumpAndSettle();

      expect(find.text('Global Hotkeys'), findsOneWidget);
      expect(find.text('Dashboard & Navigation Chords'), findsOneWidget);
    });

    testWidgets('Close button dismisses the dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWrapper());
      await tester.tap(find.text('Open Manual'));
      await tester.pumpAndSettle();

      expect(find.byType(UserManualDialog), findsOneWidget);

      final closeBtn = find.text('Close');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(find.byType(UserManualDialog), findsNothing);
    });

    testWidgets('Renders cleanly in Light Mode', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWrapper(brightness: Brightness.light));
      await tester.tap(find.text('Open Manual'));
      await tester.pumpAndSettle();

      expect(find.byType(UserManualDialog), findsOneWidget);
      expect(find.text('User Manual & Knowledge Base'), findsOneWidget);
    });
  });

  group('Help Shortcut & Button Integration Tests', () {
    testWidgets('HelpManualButton opens UserManualDialog with specific topic', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            appBar: AppBar(
              actions: const [
                HelpManualButton(topicId: 'transfer_files'),
              ],
            ),
            body: const Text('Sample Body'),
          ),
        ),
      );

      final helpBtn = find.byType(HelpManualButton);
      expect(helpBtn, findsOneWidget);
      await tester.tap(helpBtn);
      await tester.pumpAndSettle();

      expect(find.byType(UserManualDialog), findsOneWidget);
      expect(find.text('Transfer Files'), findsWidgets);
      expect(find.text('Overview & Safe Moving Mechanics'), findsOneWidget);
    });

    testWidgets('HelpShortcutWrapper triggers dialog on F1 key press', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const HelpShortcutWrapper(
            topicId: 'delete_files',
            child: Scaffold(
              body: Center(child: Text('Protected Screen')),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Press F1
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();

      expect(find.byType(UserManualDialog), findsOneWidget);
      expect(find.text('Safe Retention & Matrix Cleanup'), findsOneWidget);
    });
  });
}
