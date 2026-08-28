import 'dart:math';
import 'package:flutter/material.dart';
import '../../app_info.dart';
import '../../models/manual_topic.dart';
import '../../theme/app_theme.dart';
import 'user_manual_data.dart';

/// Interactive In-App User Manual, Knowledge Base, and Contextual Help Dialog.
///
/// Features a Master-Detail layout with real-time search filtering, deep linking,
/// numbered step cards, tip callouts, and keyboard shortcut pills.
class UserManualDialog extends StatefulWidget {
  final String? initialTopicId;

  const UserManualDialog({
    super.key,
    this.initialTopicId,
  });

  /// Displays the User Manual dialog with optional deep linking to [initialTopicId].
  static Future<void> show(BuildContext context, {String? initialTopicId}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => UserManualDialog(initialTopicId: initialTopicId),
    );
  }

  @override
  State<UserManualDialog> createState() => _UserManualDialogState();
}

class _UserManualDialogState extends State<UserManualDialog> {
  late final TextEditingController _searchController;
  late String _selectedTopicId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();

    // Default to initialTopicId if found, otherwise the first topic
    final initialId = widget.initialTopicId;
    if (initialId != null && UserManualData.getTopicById(initialId) != null) {
      _selectedTopicId = initialId;
    } else {
      _selectedTopicId = UserManualData.topics.first.id;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ManualTopic> get _filteredTopics {
    if (_searchQuery.trim().isEmpty) {
      return UserManualData.topics;
    }
    return UserManualData.topics
        .where((topic) => topic.matches(_searchQuery))
        .toList();
  }

  ManualTopic get _selectedTopic {
    final match = UserManualData.getTopicById(_selectedTopicId);
    if (match != null) return match;
    final filtered = _filteredTopics;
    if (filtered.isNotEmpty) return filtered.first;
    return UserManualData.topics.first;
  }

  void _selectTopic(String topicId) {
    setState(() {
      _selectedTopicId = topicId;
    });
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = min(1000.0, max(600.0, screenSize.width * 0.88));
    final dialogHeight = min(720.0, max(450.0, screenSize.height * 0.88));
    final isDark = context.isDarkMode;

    final filteredList = _filteredTopics;
    final selectedTopic = _selectedTopic;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: AppDecorations.dialogCard(context: context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              // ── Header Bar ──
              _buildHeaderBar(context, isDark),

              // ── Master - Detail Content ──
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Master Sidebar (Left)
                    SizedBox(
                      width: 290,
                      child: _buildMasterSidebar(
                        context,
                        filteredList,
                        selectedTopic,
                        isDark,
                      ),
                    ),

                    // Vertical Divider
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: context.border.withValues(alpha: 0.6),
                    ),

                    // Detail Panel (Right)
                    Expanded(
                      child: _buildDetailPanel(
                        context,
                        selectedTopic,
                        isDark,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Footer Bar ──
              _buildFooterBar(context, isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header Bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeaderBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark3 : AppColors.lightBg2,
        border: Border(
          bottom: BorderSide(
            color: context.border.withValues(alpha: 0.8),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: context.primaryAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.menu_book_rounded,
              color: context.primaryAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'User Manual & Knowledge Base',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.primaryAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: context.primaryAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'v${AppInfo.appVersion}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: context.primaryAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Offline-first documentation, feature guides, and shortcut cheat sheets',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Close (Esc)',
            color: context.textSecondary,
            hoverColor: AppColors.error.withValues(alpha: 0.15),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Master Sidebar (Left)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMasterSidebar(
    BuildContext context,
    List<ManualTopic> filteredList,
    ManualTopic selectedTopic,
    bool isDark,
  ) {
    return Container(
      color: isDark
          ? AppColors.bgDark1.withValues(alpha: 0.5)
          : AppColors.lightBg1.withValues(alpha: 0.7),
      child: Column(
        children: [
          // Search Field Box
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: TextStyle(fontSize: 13, color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search documentation...',
                hintStyle: TextStyle(fontSize: 12, color: context.textMuted),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: context.primaryAccent,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: _clearSearch,
                        tooltip: 'Clear search',
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                isDense: true,
                filled: true,
                fillColor: isDark ? AppColors.bgDark2 : AppColors.lightSurface,
              ),
            ),
          ),

          // Categories / Topics List
          Expanded(
            child: filteredList.isEmpty
                ? _buildEmptySearchResults(context)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final topic = filteredList[index];
                      final isSelected = topic.id == selectedTopic.id;
                      return _buildTopicListItem(
                        context,
                        topic,
                        isSelected,
                        isDark,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySearchResults(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 40,
            color: context.textMuted.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'No matching topics',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try searching with different keywords like "transfer", "copy", or "shortcuts".',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _clearSearch,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Clear Search', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicListItem(
    BuildContext context,
    ManualTopic topic,
    bool isSelected,
    bool isDark,
  ) {
    final activeColor = context.primaryAccent;
    final itemBg = isSelected
        ? activeColor.withValues(alpha: isDark ? 0.18 : 0.12)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: itemBg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _selectTopic(topic.id),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? activeColor.withValues(alpha: 0.5)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? activeColor.withValues(alpha: 0.25)
                        : (isDark ? AppColors.bgDark3 : AppColors.lightBg2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    topic.icon,
                    size: 17,
                    color: isSelected ? activeColor : context.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              topic.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: isSelected
                                    ? activeColor
                                    : context.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (topic.badge != null) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? activeColor.withValues(alpha: 0.2)
                                    : context.border.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                topic.badge!,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? activeColor
                                      : context.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        topic.subtitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.textMuted,
                          height: 1.15,
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

  // ─────────────────────────────────────────────────────────────────────────
  // Detail Panel (Right)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDetailPanel(
    BuildContext context,
    ManualTopic topic,
    bool isDark,
  ) {
    return Container(
      color: isDark ? AppColors.surface : AppColors.lightSurface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Topic Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.primaryAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    topic.icon,
                    color: context.primaryAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              topic.title,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          if (topic.badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: context.primaryAccent.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: context.primaryAccent.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Text(
                                topic.badge!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: context.primaryAccent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        topic.subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (topic.keywords.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: topic.keywords.map((kw) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.bgDark3 : AppColors.lightBg2,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: context.border.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      '#$kw',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 18),
            Divider(color: context.border.withValues(alpha: 0.6), height: 1),
            const SizedBox(height: 18),

            // Sections
            ...topic.sections.map((section) {
              return _buildSectionCard(context, section, isDark);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context,
    ManualSection section,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark2 : AppColors.lightBg1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.border.withValues(alpha: 0.8),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Text(
            section.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),

          // Section Description
          Text(
            section.description,
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondary,
              height: 1.45,
            ),
          ),

          // Numbered Steps
          if (section.steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...section.steps.asMap().entries.map((entry) {
              final stepIndex = entry.key + 1;
              final stepText = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.primaryAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$stepIndex',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.bgDark1 : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        stepText,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: context.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          // Tip Callout Banner
          if (section.tip != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.primaryAccent.withValues(
                  alpha: isDark ? 0.12 : 0.08,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: context.primaryAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: context.primaryAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section.tip!,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textPrimary,
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Shortcuts Section
          if (section.shortcuts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: section.shortcuts.map((sc) {
                return _buildShortcutRow(context, sc, isDark);
              }).toList(),
            ),
          ],

          // Tags Row
          if (section.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: section.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgDark3 : AppColors.lightBg2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.textMuted,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShortcutRow(BuildContext context, String shortcut, bool isDark) {
    final parts = shortcut.split(' : ');
    final keyCombos = parts[0].split(' / ');
    final description = parts.length > 1 ? parts[1].trim() : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          ...keyCombos.asMap().entries.expand((entry) {
            final idx = entry.key;
            final keyStr = entry.value.trim();
            return [
              if (idx > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '/',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: context.textMuted,
                    ),
                  ),
                ),
              _buildSingleKbdBadge(context, keyStr, isDark),
            ];
          }),
          if (description != null) ...[
            const SizedBox(width: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleKbdBadge(BuildContext context, String keyText, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF241E19) : const Color(0xFFEFECE5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: context.border.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.keyboard_outlined,
            size: 12,
            color: context.primaryAccent,
          ),
          const SizedBox(width: 5),
          Text(
            keyText,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Footer Bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFooterBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark3 : AppColors.lightBg2,
        border: Border(
          top: BorderSide(
            color: context.border.withValues(alpha: 0.8),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => _selectTopic('shortcuts_cheat_sheet'),
            icon: const Icon(Icons.keyboard_rounded, size: 16),
            label: const Text('Keyboard Shortcuts Cheat Sheet'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
