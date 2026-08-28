import 'package:flutter/material.dart';

/// Represents an individual section or subsection within a manual topic.
class ManualSection {
  final String title;
  final String description;
  final List<String> steps;
  final String? tip;
  final List<String> shortcuts;
  final List<String> tags;

  const ManualSection({
    required this.title,
    required this.description,
    this.steps = const [],
    this.tip,
    this.shortcuts = const [],
    this.tags = const [],
  });

  /// Checks if any content in this section matches [query].
  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();

    if (title.toLowerCase().contains(q)) return true;
    if (description.toLowerCase().contains(q)) return true;
    if (tip != null && tip!.toLowerCase().contains(q)) return true;
    if (tags.any((tag) => tag.toLowerCase().contains(q))) return true;
    if (shortcuts.any((sc) => sc.toLowerCase().contains(q))) return true;
    if (steps.any((step) => step.toLowerCase().contains(q))) return true;

    return false;
  }
}

/// Represents a top-level user manual and knowledge base topic.
class ManualTopic {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final List<String> keywords;
  final List<ManualSection> sections;

  const ManualTopic({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badge,
    this.keywords = const [],
    required this.sections,
  });

  /// Checks if this topic or any of its sections match the search [query].
  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();

    if (id.toLowerCase().contains(q)) return true;
    if (title.toLowerCase().contains(q)) return true;
    if (subtitle.toLowerCase().contains(q)) return true;
    if (badge != null && badge!.toLowerCase().contains(q)) return true;
    if (keywords.any((kw) => kw.toLowerCase().contains(q))) return true;

    // Check inner sections
    for (final section in sections) {
      if (section.matches(q)) return true;
    }

    return false;
  }
}
