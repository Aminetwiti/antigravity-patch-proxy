import 'package:flutter/material.dart';
import '../../core/protocol/messages.dart';
import '../../core/protocol/workspace_path.dart';
import '../../theme/app_colors.dart';

enum SessionGroupBy {
  project,
  workspace,
  status,
  none,
}

extension SessionGroupByX on SessionGroupBy {
  String get label {
    switch (this) {
      case SessionGroupBy.project:
        return 'Project';
      case SessionGroupBy.workspace:
        return 'Workspace';
      case SessionGroupBy.status:
        return 'Status';
      case SessionGroupBy.none:
        return 'None';
    }
  }
}

enum SessionSortBy {
  lastUpdated,
  lastPrompt,
  alphabetical,
  dateAdded,
}

extension SessionSortByX on SessionSortBy {
  String get label {
    switch (this) {
      case SessionSortBy.lastUpdated:
        return 'Last Updated';
      case SessionSortBy.lastPrompt:
        return 'Last Prompt';
      case SessionSortBy.alphabetical:
        return 'Alphabetical (A-Z)';
      case SessionSortBy.dateAdded:
        return 'Date Added';
    }
  }
}

enum SessionSubtitle {
  worktree,
  none,
}

extension SessionSubtitleX on SessionSubtitle {
  String get label {
    switch (this) {
      case SessionSubtitle.worktree:
        return 'Worktree';
      case SessionSubtitle.none:
        return 'No Subtitle';
    }
  }
}

/// Utility helper for grouping sessions
Map<String, List<CascadeSession>> groupSessions({
  required List<CascadeSession> sessions,
  required SessionGroupBy groupBy,
  List<ProjectItem>? projects,
}) {
  final Map<String, List<CascadeSession>> grouped = {};

  if (groupBy == SessionGroupBy.none) {
    grouped['All Conversations'] = List.from(sessions);
    return grouped;
  }

  if (groupBy == SessionGroupBy.status) {
    for (final s in sessions) {
      String statusGroup = 'Other';
      if (s.isRunning) {
        statusGroup = 'Active';
      } else if (s.status.toUpperCase().contains('READY')) {
        statusGroup = 'Ready';
      } else {
        statusGroup = 'Idle';
      }
      grouped.putIfAbsent(statusGroup, () => []).add(s);
    }
    return grouped;
  }

  if (groupBy == SessionGroupBy.workspace) {
    for (final s in sessions) {
      final ws = WorkspacePath.displayName(s.workspacePath);
      grouped.putIfAbsent(ws, () => []).add(s);
    }
    return grouped;
  }

  // SessionGroupBy.project
  final officialProjects = projects ?? [];
  if (officialProjects.isNotEmpty) {
    for (final p in officialProjects) {
      grouped[p.name] = [];
    }

    for (final s in sessions) {
      bool matched = false;
      final cleanSPath = s.workspacePath.replaceAll('\\', '/').toLowerCase();

      for (final p in officialProjects) {
        final cleanPPath = p.path.replaceAll('\\', '/').toLowerCase();
        final cleanName = p.name.toLowerCase();

        if ((cleanPPath.isNotEmpty && cleanSPath.contains(cleanPPath)) ||
            (cleanPPath.isNotEmpty && cleanPPath.contains(cleanSPath)) ||
            (cleanName.isNotEmpty && cleanSPath.contains(cleanName)) ||
            (cleanName.isNotEmpty && cleanName.contains(cleanSPath))) {
          grouped[p.name]?.add(s);
          matched = true;
          break;
        }
      }

      if (!matched) {
        final fallbackName = WorkspacePath.displayName(
          s.workspacePath,
          fallback: 'antigravity-workspace',
        );
        grouped.putIfAbsent(fallbackName, () => []).add(s);
      }
    }

    // Supprimer les dossiers de projet vides sans sessions
    grouped.removeWhere((key, value) => value.isEmpty);
  } else {
    for (final s in sessions) {
      final folderName = WorkspacePath.displayName(
        s.workspacePath,
        fallback: 'antigravity-workspace',
      );
      grouped.putIfAbsent(folderName, () => []).add(s);
    }
  }

  return grouped;
}

/// Utility helper for sorting sessions
List<CascadeSession> sortSessions({
  required List<CascadeSession> sessions,
  required SessionSortBy sortBy,
}) {
  final copy = List<CascadeSession>.from(sessions);

  switch (sortBy) {
    case SessionSortBy.alphabetical:
      copy.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      break;
    case SessionSortBy.lastPrompt:
      copy.sort((a, b) {
        final aPrompt = (a.lastPrompt ?? a.title).toLowerCase();
        final bPrompt = (b.lastPrompt ?? b.title).toLowerCase();
        return aPrompt.compareTo(bPrompt);
      });
      break;
    case SessionSortBy.dateAdded:
      copy.sort((a, b) => a.id.compareTo(b.id));
      break;
    case SessionSortBy.lastUpdated:
    default:
      // Preserves original dynamic order
      break;
  }

  return copy;
}

/// Display Options Menu Button matching Antigravity 2.0 Desktop IDE menu
class DisplayOptionsMenuButton extends StatelessWidget {
  final SessionGroupBy selectedGroupBy;
  final SessionSortBy selectedSortBy;
  final SessionSubtitle selectedSubtitle;
  final bool isFilterOpen;
  final ValueChanged<SessionGroupBy> onGroupByChanged;
  final ValueChanged<SessionSortBy> onSortByChanged;
  final ValueChanged<SessionSubtitle> onSubtitleChanged;
  final VoidCallback onToggleFilter;

  const DisplayOptionsMenuButton({
    super.key,
    required this.selectedGroupBy,
    required this.selectedSortBy,
    required this.selectedSubtitle,
    required this.isFilterOpen,
    required this.onGroupByChanged,
    required this.onSortByChanged,
    required this.onSubtitleChanged,
    required this.onToggleFilter,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Display Options',
      color: const Color(0xFF1B1D22),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      offset: const Offset(0, 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: Color(0xFF2C2F36), width: 1),
      ),
      icon: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: isFilterOpen ? const Color(0xFF26282E) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Icon(
          Icons.tune_rounded,
          size: 16,
          color: Color(0xFF8F909A),
        ),
      ),
      onSelected: (value) {
        if (value.startsWith('group_')) {
          final groupName = value.substring(6);
          final match = SessionGroupBy.values.firstWhere(
            (e) => e.name == groupName,
            orElse: () => SessionGroupBy.project,
          );
          onGroupByChanged(match);
        } else if (value.startsWith('sort_')) {
          final sortName = value.substring(5);
          final match = SessionSortBy.values.firstWhere(
            (e) => e.name == sortName,
            orElse: () => SessionSortBy.lastUpdated,
          );
          onSortByChanged(match);
        } else if (value.startsWith('sub_')) {
          final subName = value.substring(4);
          final match = SessionSubtitle.values.firstWhere(
            (e) => e.name == subName,
            orElse: () => SessionSubtitle.worktree,
          );
          onSubtitleChanged(match);
        } else if (value == 'toggle_filter') {
          onToggleFilter();
        }
      },
      itemBuilder: (context) => [
        // ── Group By Header
        _buildSectionHeader('Group By'),
        ...SessionGroupBy.values.map(
          (opt) => _buildCheckItem(
            value: 'group_${opt.name}',
            label: opt.label,
            isSelected: selectedGroupBy == opt,
          ),
        ),

        const PopupMenuDivider(height: 12),

        // ── Sort Conversations Header
        _buildSectionHeader('Sort Conversations'),
        ...SessionSortBy.values.map(
          (opt) => _buildCheckItem(
            value: 'sort_${opt.name}',
            label: opt.label,
            isSelected: selectedSortBy == opt,
          ),
        ),

        const PopupMenuDivider(height: 12),

        // ── Subtitles Header
        _buildSectionHeader('Subtitles'),
        ...SessionSubtitle.values.map(
          (opt) => _buildCheckItem(
            value: 'sub_${opt.name}',
            label: opt.label,
            isSelected: selectedSubtitle == opt,
          ),
        ),

        const PopupMenuDivider(height: 12),

        // ── Filter Sub-menu toggle
        PopupMenuItem<String>(
          value: 'toggle_filter',
          height: 32,
          child: Row(
            children: [
              Icon(
                isFilterOpen ? Icons.filter_list_off_rounded : Icons.filter_list_rounded,
                size: 15,
                color: isFilterOpen ? AppColors.accentBlue : AppColors.inkPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isFilterOpen ? 'Hide Filter Bar' : 'Filter',
                  style: TextStyle(
                    fontSize: 13,
                    color: isFilterOpen ? AppColors.accentBlue : AppColors.inkPrimary,
                    fontWeight: isFilterOpen ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildSectionHeader(String title) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 26,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6E707A),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildCheckItem({
    required String value,
    required String label,
    required bool isSelected,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? Colors.white : AppColors.inkPrimary,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.accentBlue,
            ),
        ],
      ),
    );
  }
}
