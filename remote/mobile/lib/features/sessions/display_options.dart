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
  project,
  none,
}

extension SessionSubtitleX on SessionSubtitle {
  String get label {
    switch (this) {
      case SessionSubtitle.worktree:
        return 'Worktree / Branch';
      case SessionSubtitle.project:
        return 'Project';
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
      ProjectItem? matchedProject;

      // 1. Priorité 1 : correspondance projectId explicite
      if (s.projectId != null && s.projectId!.isNotEmpty) {
        for (final p in officialProjects) {
          if (s.projectId == p.id) {
            matchedProject = p;
            break;
          }
        }
      }

      // 2. Priorité 2 : correspondance exacte de chemin ou d'URI canonique
      if (matchedProject == null && s.workspacePath.isNotEmpty) {
        for (final p in officialProjects) {
          if (WorkspacePath.isSameWorkspace(s.workspacePath, p.path) ||
              WorkspacePath.isSameWorkspace(s.workspacePath, p.folderUri)) {
            matchedProject = p;
            break;
          }
        }
      }

      // 3. Priorité 3 : parent le plus spécifique (le plus profond) pour les sous-projets / monorepos
      if (matchedProject == null && s.workspacePath.isNotEmpty) {
        ProjectItem? mostSpecificParent;
        int longestParentPathLength = -1;

        for (final p in officialProjects) {
          final pPath = WorkspacePath.canonicalPath(p.path);
          final pUri = WorkspacePath.canonicalPath(p.folderUri);
          final effectiveP = pPath.isNotEmpty ? pPath : pUri;

          if (effectiveP.isNotEmpty && WorkspacePath.isSubdirOf(s.workspacePath, effectiveP)) {
            if (effectiveP.length > longestParentPathLength) {
              longestParentPathLength = effectiveP.length;
              mostSpecificParent = p;
            }
          }
        }
        matchedProject = mostSpecificParent;
      }

      // 4. Priorité 4 : nom de projet exact correspondant au nom de dossier
      if (matchedProject == null && s.workspacePath.isNotEmpty) {
        final sessionFolder = WorkspacePath.displayName(s.workspacePath).toLowerCase();
        for (final p in officialProjects) {
          if (p.name.trim().toLowerCase() == sessionFolder) {
            matchedProject = p;
            break;
          }
        }
      }

      if (matchedProject != null) {
        grouped[matchedProject.name]?.add(s);
      } else {
        const fallbackName = 'Outside of Project';
        grouped.putIfAbsent(fallbackName, () => []).add(s);
      }
    }

    if (grouped['Outside of Project']?.isEmpty ?? false) {
      grouped.remove('Outside of Project');
    }
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopupMenuButton<String>(
      tooltip: 'Display Options',
      color: isDark ? const Color(0xFF1B1D22) : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      offset: const Offset(0, 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: isDark ? const Color(0xFF2C2F36) : scheme.outlineVariant, width: 1),
      ),
      icon: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: isFilterOpen ? (isDark ? const Color(0xFF26282E) : scheme.surfaceContainerHighest) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(
          Icons.tune_rounded,
          size: 16,
          color: isFilterOpen ? scheme.primary : scheme.onSurfaceVariant,
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
        _buildSectionHeader('Group By', scheme, isDark),
        ...SessionGroupBy.values.map(
          (opt) => _buildCheckItem(
            value: 'group_${opt.name}',
            label: opt.label,
            isSelected: selectedGroupBy == opt,
            scheme: scheme,
            isDark: isDark,
          ),
        ),

        const PopupMenuDivider(height: 12),

        // ── Sort Conversations Header
        _buildSectionHeader('Sort Conversations', scheme, isDark),
        ...SessionSortBy.values.map(
          (opt) => _buildCheckItem(
            value: 'sort_${opt.name}',
            label: opt.label,
            isSelected: selectedSortBy == opt,
            scheme: scheme,
            isDark: isDark,
          ),
        ),

        const PopupMenuDivider(height: 12),

        // ── Subtitles Header
        _buildSectionHeader('Subtitles', scheme, isDark),
        ...SessionSubtitle.values.map(
          (opt) => _buildCheckItem(
            value: 'sub_${opt.name}',
            label: opt.label,
            isSelected: selectedSubtitle == opt,
            scheme: scheme,
            isDark: isDark,
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
                color: isFilterOpen ? scheme.primary : scheme.onSurface,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isFilterOpen ? 'Hide Filter Bar' : 'Filter',
                  style: TextStyle(
                    fontSize: 13,
                    color: isFilterOpen ? scheme.primary : scheme.onSurface,
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

  PopupMenuItem<String> _buildSectionHeader(String title, ColorScheme scheme, bool isDark) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 26,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF6E707A) : scheme.onSurfaceVariant,
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
    required ColorScheme scheme,
    required bool isDark,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 32,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF26282E) : scheme.primary.withValues(alpha: 0.08))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 11,
                  color: isDark ? Colors.black : Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
