import 'package:flutter/material.dart';
import '../../models/manual_topic.dart';

/// Centralized repository containing all offline-first user manual documentation,
/// feature guides, shortcut cheat sheets, and troubleshooting references.
class UserManualData {
  UserManualData._();

  /// Retrieve a topic by its unique identifier.
  static ManualTopic? getTopicById(String id) {
    try {
      return topics.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// All documentation topics in logical reading order.
  static final List<ManualTopic> topics = [
    // 1. Getting Started & Overview
    const ManualTopic(
      id: 'getting_started',
      title: 'Getting Started & Overview',
      subtitle: 'Core concepts, navigation, workspace profiles, and workflows',
      icon: Icons.rocket_launch_rounded,
      badge: 'Basics',
      keywords: [
        'overview',
        'start',
        'intro',
        'profile',
        'navigation',
        'workflow',
        'quickstart',
        'dashboard',
        'offline',
      ],
      sections: [
        ManualSection(
          title: 'Application Architecture & Philosophy',
          description:
              'Files Utility is a native, offline-first desktop application designed for high-throughput file transfers, directory mirroring, automated cleanups, and file audits across local disks, network shares (SMB/UNC), and NAS devices. It requires zero cloud connectivity to function and securely stores all configuration and run statistics locally using embedded SQLite databases.',
          tags: ['architecture', 'offline-first', 'sqlite', 'local-storage'],
        ),
        ManualSection(
          title: 'Profiles & Workspaces',
          description:
              'Profiles allow you to maintain isolated configurations, recent directory histories, and execution logs for different operational environments (e.g. "Production NAS", "Office Server", "Local Backup"). You can switch active profiles from the profile selector at any time.',
          steps: [
            'Click the Active Profile badge in the top header bar to open the Profile Selector.',
            'Create a new profile with a descriptive name, or select an existing profile.',
            'All subsequent directory choices, run histories, and advanced parameters will be saved to the selected profile.',
          ],
          tip:
              'Use separate profiles for mission-critical production servers to prevent accidental cross-folder operations.',
          tags: ['profiles', 'workspaces', 'multi-environment'],
        ),
        ManualSection(
          title: 'Core Navigation & Tools',
          description:
              'The main dashboard provides rapid access to the 4 primary file management modules, an aggregate comparative analytics overview, and the recent run history table.',
          steps: [
            'Transfer Files: Move files matching date and extension filters while automatically pruning successfully moved source files.',
            'Copy Files: Mirror single or multiple directories with customizable run sequence orders.',
            'Delete Files: Purge obsolete archives and files based on year and month matrix filters.',
            'Count Files: Rapidly audit directory file counts, subfolder totals, and compute operational throughput.',
          ],
          shortcuts: ['Cmd+1', 'Cmd+2', 'Cmd+3', 'Cmd+4'],
          tags: ['navigation', 'tools', 'dashboard'],
        ),
        ManualSection(
          title: 'Light & Dark Theme Support',
          description:
              'The application features a tailored "Coffee & Cream" aesthetic designed to optimize contrast and reduce eye fatigue during extended server management sessions.',
          shortcuts: ['F1', 'Cmd+Shift+T', 'Ctrl+Shift+T'],
          tip:
              'Toggle between Dark Mocha and Warm Cream themes anytime using the theme button in the top-right corner.',
          tags: ['theme', 'appearance', 'dark-mode'],
        ),
      ],
    ),

    // 2. Transfer Files
    const ManualTopic(
      id: 'transfer_files',
      title: 'Transfer Files',
      subtitle: 'Move files by date, filter criteria, and resume checkpoints',
      icon: Icons.move_to_inbox_rounded,
      badge: 'Core Tool',
      keywords: [
        'transfer',
        'move',
        'date filter',
        'resume',
        'checkpoint',
        'extensions',
        'source',
        'destination',
      ],
      sections: [
        ManualSection(
          title: 'Overview & Safe Moving Mechanics',
          description:
              'The Transfer module relocates files from a Source directory to a Destination directory while preserving subfolder structures and file creation/modification timestamps. Files are deleted from the source only after the destination file is verified.',
          tags: ['transfer', 'file-move', 'data-integrity'],
        ),
        ManualSection(
          title: 'Step-by-Step File Transfer Workflow',
          description:
              'Follow these steps to execute a reliable file transfer:',
          steps: [
            'Select the Source directory by clicking Browse or choosing from Recent Directories.',
            'Select the Destination directory.',
            'Click Advanced Settings if you wish to apply Date Range filters or target specific extensions.',
            'Click the Start button to begin the transfer process.',
            'Monitor real-time progress via the status banner, processed file counters, and live log console.',
          ],
          shortcuts: ['Space', 'Enter'],
          tags: ['workflow', 'guide'],
        ),
        ManualSection(
          title: 'Date Range & Extension Filtering',
          description:
              'Filter files based on when they were modified. Specify start and end dates to move only archival batches or recent outputs. You can also filter specific extensions (e.g. .log, .csv, .dcm) to isolate targeted payloads.',
          tip:
              'Leave the date range blank if you wish to transfer all files regardless of modification timestamp.',
          tags: ['filtering', 'date-range', 'extensions'],
        ),
        ManualSection(
          title: 'Resume Checkpoints & Interrupt Safety',
          description:
              'If a transfer is interrupted by a network disconnect, machine reboot, or manual stop, Files Utility saves a resume checkpoint. When restarted, it skips already completed files and resumes exactly where it left off.',
          tip:
              'Use the "Clear Progress" button if you want to invalidate the checkpoint and restart a fresh scan from the beginning.',
          tags: ['checkpoint', 'recovery', 'resume'],
        ),
      ],
    ),

    // 3. Copy Files
    const ManualTopic(
      id: 'copy_files',
      title: 'Copy Files',
      subtitle: 'Mirror directories, batch multi-folder sync, and date ranges',
      icon: Icons.file_copy_rounded,
      badge: 'Core Tool',
      keywords: [
        'copy',
        'mirror',
        'sync',
        'multi-directory',
        'batch',
        'backup',
        'run order',
      ],
      sections: [
        ManualSection(
          title: 'Single vs. Multi-Directory Copying',
          description:
              'Files Utility supports two copy paradigms:\n• Single Directory: A standard 1-to-1 folder mirroring process.\n• Multiple Directories: A batch orchestration pipeline allowing you to define multiple source/destination pairs and execute them sequentially in a designated run order.',
          tags: ['copy', 'multi-directory', 'batch-sync'],
        ),
        ManualSection(
          title: 'Multi-Directory Setup & Run Order',
          description:
              'In Multi-Directory mode, you can map multiple folder pairs and customize their execution sequence:',
          steps: [
            'Check the "Use Multiple Directories" option in the configuration card.',
            'Click "Add Pair" to add a new Source and Destination mapping.',
            'Use the up/down arrows or order selector to assign execution priority (e.g., Run 1, Run 2, Run 3).',
            'Click Start to process all configured pairs in sequence.',
          ],
          tip:
              'Multi-directory pairs are saved automatically to your active profile for repeated daily or weekly executions.',
          tags: ['multi-directory', 'run-order', 'automation'],
        ),
        ManualSection(
          title: 'Date Range & Metadata Preservation',
          description:
              'Files copied retain their original modification timestamps, permissions, and directory hierarchies. Applying a date range ensures only assets modified within that window are replicated.',
          tags: ['timestamps', 'metadata', 'date-filter'],
        ),
      ],
    ),

    // 4. Delete Files
    const ManualTopic(
      id: 'delete_files',
      title: 'Delete Files',
      subtitle:
          'Targeted cleanup by year, month, extension, and retention criteria',
      icon: Icons.delete_forever_rounded,
      badge: 'Maintenance',
      keywords: [
        'delete',
        'cleanup',
        'purge',
        'retention',
        'year',
        'month',
        'filter',
        'archive',
      ],
      sections: [
        ManualSection(
          title: 'Safe Retention & Matrix Cleanup',
          description:
              'The Delete module is built for structured data retention policies and storage reclamation. Instead of risky manual deletions, it provides an interactive Year and Month matrix selector.',
          tags: ['delete', 'retention', 'storage-cleanup'],
        ),
        ManualSection(
          title: 'Configuring Year & Month Matrices',
          description:
              'Easily target specific historical quarters or fiscal years for purging:',
          steps: [
            'Select the Target Directory containing the files to be purged.',
            'Choose the target Year from the available dropdown.',
            'Toggle individual Months (Jan - Dec) or use "Select All" / "Deselect All".',
            'Click Start to begin scanning and deleting matched items.',
          ],
          tip:
              'Always verify the selected root path before initiating a delete operation. Deleted files bypass the system trash bin for speed on high-volume network shares.',
          tags: ['matrix', 'months', 'year-selector'],
        ),
        ManualSection(
          title: 'Extension Filtering on Deletions',
          description:
              'Combine date/month matrix filtering with specific file extension exclusions to remove temporary artifacts (like .tmp, .bak, .cache) while keeping critical documentation intact.',
          tags: ['extensions', 'safety'],
        ),
      ],
    ),

    // 5. Count Files
    const ManualTopic(
      id: 'count_files',
      title: 'Count & Audit Files',
      subtitle:
          'Fast inventory auditing, size tallying, and directory tree inspection',
      icon: Icons.analytics_rounded,
      badge: 'Audit',
      keywords: [
        'count',
        'audit',
        'inventory',
        'file count',
        'folder count',
        'speed',
        'interval',
      ],
      sections: [
        ManualSection(
          title: 'High-Throughput File Tree Traversal',
          description:
              'The Count Files module performs asynchronous non-blocking traversal of complex file trees with millions of files. It provides precise metrics on total file count, total folders, error counts, and elapsed scan duration.',
          tags: ['audit', 'inventory', 'traversal'],
        ),
        ManualSection(
          title: 'Logging Interval Optimization',
          description:
              'For directories with hundreds of thousands or millions of files, rendering every file to the log console can introduce UI latency. The Log Interval setting lets you adjust reporting frequency.',
          steps: [
            'Set Log Interval to 100 or 500 for normal auditing.',
            'Set Log Interval to 1,000 or 5,000 for ultra-fast multi-million file network share audits.',
            'Total statistics remain 100% accurate regardless of the logging sample rate.',
          ],
          tip:
              'Increasing the log interval dramatically speeds up directory audits over high-latency WAN and SMB links.',
          tags: ['performance', 'log-interval', 'optimization'],
        ),
      ],
    ),

    // 6. Advanced Features & Integrations
    const ManualTopic(
      id: 'advanced_features',
      title: 'Advanced Features & Integrations',
      subtitle:
          'SQLite history, network shares (UNC/NAS), and automation controls',
      icon: Icons.tune_rounded,
      badge: 'Power User',
      keywords: [
        'advanced',
        'sqlite',
        'history',
        'analytics',
        'unc',
        'nas',
        'smb',
        'completion',
        'pause',
        'stop',
      ],
      sections: [
        ManualSection(
          title: 'Embedded SQLite Run History & Analytics',
          description:
              'Every execution across all tools is automatically logged to an embedded SQLite database. The History & Analytics Dashboard computes operation distributions, transfer speeds, error tallies, and run durations.',
          steps: [
            'Access the History Dashboard directly on the main screen or click "View Full Analytics".',
            'Filter past runs by Operation Type (Transfer, Copy, Delete, Count) or Status (Completed, Stopped, Failed).',
            'Inspect detailed per-run telemetry including start/end timestamps, source/destination paths, and errors.',
          ],
          shortcuts: ['Cmd+H', 'Ctrl+H'],
          tags: ['sqlite', 'analytics', 'audit-trail'],
        ),
        ManualSection(
          title: 'Network Shares (SMB, UNC & NAS)',
          description:
              'Files Utility supports direct UNC network paths (e.g. \\\\nas-server\\share\\data on Windows or smb:// mounted volumes on macOS/Linux).',
          tip:
              'Ensure that the network connection has read/write permissions on both the source and target shares before launching high-volume transfers.',
          tags: ['network', 'unc', 'nas', 'smb'],
        ),
        ManualSection(
          title: 'On-Completion Automation Actions',
          description:
              'In the Advanced Settings dialog of Transfer and Copy modules, configure the "When Complete" trigger:',
          steps: [
            'Stop: Terminates processing upon completion and marks the run status as Completed.',
            'Pause: Keeps the active session suspended and ready for scheduled re-execution intervals.',
          ],
          tags: ['automation', 'completion-triggers'],
        ),
      ],
    ),

    // 7. Keyboard Shortcuts Cheat Sheet
    const ManualTopic(
      id: 'shortcuts_cheat_sheet',
      title: 'Keyboard Shortcuts Cheat Sheet',
      subtitle: 'Global hotkeys, navigation chords, and execution controls',
      icon: Icons.keyboard_rounded,
      badge: 'Productivity',
      keywords: [
        'shortcuts',
        'hotkeys',
        'keyboard',
        'cheat sheet',
        'f1',
        'ctrl',
        'cmd',
        'escape',
      ],
      sections: [
        ManualSection(
          title: 'Global Hotkeys',
          description:
              'These hotkeys are available from anywhere within the application:',
          shortcuts: [
            'F1 : Open In-App User Manual & Help Center',
            'Cmd+? / Ctrl+? : Open In-App User Manual & Help Center',
            'Esc : Close open dialog / Return to dashboard',
            'Cmd+Shift+T / Ctrl+Shift+T : Toggle Light & Dark theme',
          ],
          tags: ['global', 'hotkeys'],
        ),
        ManualSection(
          title: 'Dashboard & Navigation Chords',
          description: 'Jump directly to different tools and screens:',
          shortcuts: [
            'Cmd+1 / Ctrl+1 : Open Transfer Files tool',
            'Cmd+2 / Ctrl+2 : Open Copy Files tool',
            'Cmd+3 / Ctrl+3 : Open Delete Files tool',
            'Cmd+4 / Ctrl+4 : Open Count Files tool',
            'Cmd+H / Ctrl+H : Open History & Analytics screen',
          ],
          tags: ['navigation', 'chords'],
        ),
        ManualSection(
          title: 'Operation & Console Execution',
          description:
              'Control operations and logging without using the mouse:',
          shortcuts: [
            'Space / Enter : Start or resume pending operation',
            'Cmd+L / Ctrl+L : Clear active log console entries',
          ],
          tags: ['execution', 'console'],
        ),
      ],
    ),

    // 8. Settings, Permissions & Troubleshooting
    const ManualTopic(
      id: 'troubleshooting',
      title: 'Settings, Permissions & Troubleshooting',
      subtitle:
          'OS permissions, storage locations, update manager, and diagnostics',
      icon: Icons.build_circle_rounded,
      badge: 'Support',
      keywords: [
        'troubleshooting',
        'permissions',
        'full disk access',
        'admin',
        'sqlite',
        'updates',
        'errors',
        'faq',
      ],
      sections: [
        ManualSection(
          title: 'macOS & Windows Storage Permissions',
          description:
              'When accessing protected external drives, network shares, or system folders, operating system permissions must be granted:',
          steps: [
            'macOS: Open System Settings > Privacy & Security > Full Disk Access, and ensure Files Utility is toggled ON.',
            'Windows: If operating on protected server directories or UNC shares requiring elevated privileges, launch the application as Administrator.',
            'Ensure the target network credentials are saved in your OS Credential Manager for persistent share access.',
          ],
          tip:
              'If directory browsing shows "Permission Denied" errors, verify Full Disk Access in macOS settings.',
          tags: ['permissions', 'macos', 'windows', 'security'],
        ),
        ManualSection(
          title: 'Local Database & Storage Locations',
          description:
              'Files Utility stores all user data locally on your system in the Application Support directory (under standard OS path conventions). No telemetry or file paths are ever transmitted over the network.',
          tags: ['storage-paths', 'privacy', 'sqlite'],
        ),
        ManualSection(
          title: 'In-App Update Manager',
          description:
              'Files Utility features a built-in semantic versioning update checker. Click the update check button in the header bar or configure automatic checks on startup. When an update is available, you can review the release notes and update directly.',
          tags: ['updates', 'semver', 'maintenance'],
        ),
      ],
    ),
  ];
}
