import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:files_utility/models/manual_topic.dart';
import 'package:files_utility/views/dialogs/user_manual_data.dart';

void main() {
  group('ManualSection Unit Tests', () {
    test('ManualSection default values and matching', () {
      const section = ManualSection(
        title: 'Source & Destination Setup',
        description: 'Choose local folders or network UNC paths.',
        steps: ['Click browse', 'Select target folder'],
        tip: 'Ensure write access.',
        shortcuts: ['Cmd+O', 'Ctrl+O'],
        tags: ['storage', 'unc'],
      );

      expect(section.title, 'Source & Destination Setup');
      expect(section.steps.length, 2);
      expect(section.shortcuts.length, 2);
      expect(section.tags.length, 2);
      expect(section.tip, 'Ensure write access.');

      // Search matching across different fields
      expect(section.matches('Source'), isTrue);
      expect(section.matches('unc paths'), isTrue);
      expect(section.matches('browse'), isTrue);
      expect(section.matches('write access'), isTrue);
      expect(section.matches('cmd+o'), isTrue);
      expect(section.matches('storage'), isTrue);
      expect(section.matches('nonexistentquery123'), isFalse);
      expect(section.matches(''), isTrue); // Empty query matches all
    });
  });

  group('ManualTopic Unit Tests', () {
    test(
      'ManualTopic matches on title, subtitle, badge, keywords and sections',
      () {
        const topic = ManualTopic(
          id: 'test_topic',
          title: 'File Transfers',
          subtitle: 'Move files across drives',
          icon: Icons.folder,
          badge: 'Core',
          keywords: ['transfer', 'move', 'payload'],
          sections: [
            ManualSection(
              title: 'Section One',
              description: 'Explaining resume checkpoints.',
              steps: ['Step 1'],
              tip: 'Tip text',
              shortcuts: ['F1'],
              tags: ['checkpoint'],
            ),
          ],
        );

        expect(topic.matches('test_topic'), isTrue);
        expect(topic.matches('file transfers'), isTrue);
        expect(topic.matches('drives'), isTrue);
        expect(topic.matches('core'), isTrue);
        expect(topic.matches('payload'), isTrue);
        expect(topic.matches('checkpoints'), isTrue);
        expect(topic.matches('step 1'), isTrue);
        expect(topic.matches('f1'), isTrue);
        expect(topic.matches('unrelatedxyz'), isFalse);
        expect(topic.matches(''), isTrue);
      },
    );
  });

  group('UserManualData Repository Tests', () {
    test('UserManualData contains all required topics and sections', () {
      final topics = UserManualData.topics;
      expect(topics.isNotEmpty, isTrue);

      final expectedTopicIds = [
        'getting_started',
        'transfer_files',
        'copy_files',
        'delete_files',
        'count_files',
        'advanced_features',
        'shortcuts_cheat_sheet',
        'troubleshooting',
      ];

      for (final id in expectedTopicIds) {
        final topic = UserManualData.getTopicById(id);
        expect(topic, isNotNull, reason: 'Topic $id should exist');
        expect(topic!.title.isNotEmpty, isTrue);
        expect(topic.subtitle.isNotEmpty, isTrue);
        expect(topic.sections.isNotEmpty, isTrue);
        expect(topic.keywords.isNotEmpty, isTrue);
      }
    });

    test('getTopicById returns null for invalid id', () {
      expect(UserManualData.getTopicById('invalid_id_999'), isNull);
    });

    test('Search filters topics correctly across all data', () {
      final query = 'resume';
      final matching = UserManualData.topics
          .where((t) => t.matches(query))
          .toList();
      expect(matching.isNotEmpty, isTrue);
      expect(matching.any((t) => t.id == 'transfer_files'), isTrue);
    });
  });
}
