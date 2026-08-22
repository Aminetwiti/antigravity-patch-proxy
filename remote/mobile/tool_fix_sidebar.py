# -*- coding: utf-8 -*-
"""One-shot atomic rewrite: virtualized sidebar itemBuilder + entries method."""
import io

p = 'lib/features/sessions/sessions_list.dart'
src = io.open(p, encoding='utf-8').read()

# 1) Insert entries method after _projectSessionsOf
anchor = "    _pipeResult = result;\n    return result;\n  }\n"
assert anchor in src, 'pipeline anchor missing'
entries_method = anchor + '''
  // Aplatissement virtualise : dossiers + lignes en UNE ListView.builder.
  // Avant, chaque dossier etait un Column qui construisait TOUTES ses lignes
  // de maniere avide (aucune virtualisation) ; le matching projet/dossier
  // etait en O(projects x dossiers) a chaque build. Ici la liste aplatie est
  // memoisee et seuls les items visibles sont construits par le builder.
  final Map<String, int> _folderExpansions = {};
  Map<String, List<CascadeSession>>? _flatInput;
  Set<String>? _flatCollapsed;
  Map<String, int>? _flatExpansions;
  SessionGroupBy? _flatGroup;
  List<_SidebarEntry>? _flatResult;

  List<_SidebarEntry> _entriesOf(Map<String, List<CascadeSession>> projectSessions) {
    final collapsedSnapshot = Set<String>.of(_collapsedFolders);
    final expansionsSnapshot = Map<String, int>.of(_folderExpansions);
    if (_flatResult != null &&
        identical(projectSessions, _flatInput) &&
        setEquals(collapsedSnapshot, _flatCollapsed) &&
        mapEquals(expansionsSnapshot, _flatExpansions) &&
        _groupBy == _flatGroup) {
      return _flatResult!;
    }

    final hideHeader = _groupBy == SessionGroupBy.none;
    final baseLimit = hideHeader ? 30 : 6;
    final projs = widget.projects;
    final entries = <_SidebarEntry>[];
    final matchCache = <String, ProjectItem?>{};

    ProjectItem? projectFor(String folder, List<CascadeSession> sessions) {
      return matchCache.putIfAbsent(folder, () {
        ProjectItem? m;
        if (projs != null) {
          for (final p in projs) {
            if (p.name == folder || p.path == folder || p.id == folder || WorkspacePath.isSameWorkspace(p.path, folder)) {
              m = p;
              break;
            }
          }
        }
        return m ??
            ProjectItem(
              id: '',
              name: folder,
              folderUri: sessions.isNotEmpty ? sessions.first.workspacePath : folder,
              path: sessions.isNotEmpty ? sessions.first.workspacePath : folder,
            );
      });
    }

    projectSessions.forEach((folder, sessions) {
      if (!hideHeader && folder.isNotEmpty) {
        entries.add(_SidebarEntry.header(folder, projectFor(folder, sessions)));
      }
      if (!collapsedSnapshot.contains(folder)) {
        if (sessions.isEmpty) {
          entries.add(_SidebarEntry.empty(folder));
        } else {
          final limit = baseLimit + (expansionsSnapshot[folder] ?? 0) * 25;
          entries.addAll(
            sessions.take(limit).map((s) => _SidebarEntry.row(s, folder)),
          );
          final visible = sessions.length < limit ? sessions.length : limit;
          final remaining = sessions.length - visible;
          if (remaining > 0) {
            entries.add(_SidebarEntry.showMore(folder, remaining));
          }
        }
      }
      entries.add(const _SidebarEntry.spacer());
    });

    _flatInput = projectSessions;
    _flatCollapsed = collapsedSnapshot;
    _flatExpansions = expansionsSnapshot;
    _flatGroup = _groupBy;
    _flatResult = entries;
    return entries;
  }
'''
src = src.replace(anchor, entries_method, 1)

# 2) Add entries var in build
b_anchor = "    final projectSessions = _projectSessionsOf();\n    final projectNames = projectSessions.keys.toList();"
assert b_anchor in src, 'build anchor missing'
src = src.replace(
    b_anchor,
    "    final projectSessions = _projectSessionsOf();\n"
    "    final entries = _entriesOf(projectSessions);\n"
    "    final projectNames = projectSessions.keys.toList();",
    1)

# 3) Replace the old itemBuilder block
start = src.index('                    : ListView.builder(')
end_marker = '                        },\n                      ),'
end = src.index(end_marker, start) + len(end_marker)

new_builder = '''                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        itemCount: entries.length + 1,
                        itemBuilder: (ctx, index) {
                          if (index == entries.length) {
                            return const SizedBox(height: 16);
                          }
                          final entry = entries[index];

                          // En-tete de dossier (virtualise, memoise)
                          if (entry.isHeader) {
                            final folder = entry.folderName;
                            final isCollapsed = _collapsedFolders.contains(folder);
                            return _FolderHeader(
                              key: ValueKey('folder_$folder'),
                              folderName: folder,
                              project: entry.project,
                              onToggleCollapse: () {
                                setState(() {
                                  if (isCollapsed) {
                                    _collapsedFolders.remove(folder);
                                  } else {
                                    _collapsedFolders.add(folder);
                                  }
                                });
                                _saveCollapsedFolders();
                              },
                              onNewConversation: (ProjectItem? p) {
                                if (Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                }
                                _callNewConversation(p ?? entry.project);
                              },
                              onOpenSettings: () {
                                Navigator.of(context).pop();
                                widget.onOpenSettings?.call();
                              },
                            );
                          }

                          // Dossier vide
                          if (entry.isEmptyFolder) {
                            return const Padding(
                              padding: EdgeInsets.only(left: 28, top: 4, bottom: 8),
                              child: Text(
                                'No conversations yet',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Color(0xFF5E606A),
                                ),
                              ),
                            );
                          }

                          // Ligne de session
                          final s = entry.session;
                          if (s != null) {
                            return _SessionRowItem(
                              key: ValueKey('session_${s.id}'),
                              session: s,
                              isSelected: s.id == widget.activeSessionId,
                              showSubtitle: _subtitle == SessionSubtitle.worktree,
                              isUnread: (s.hasUnread || (s.stepCount >= 1 && !s.isRunning)) && !_readSessionIds.contains(s.id) && s.id != widget.activeSessionId,
                              onTap: () {
                                _markSessionAsRead(s.id);
                                if (Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                }
                                widget.onSessionSelected(s.id);
                              },
                              onDelete: widget.onDeleteSession != null
                                  ? () => widget.onDeleteSession!(s.id)
                                  : null,
                              onArchive: widget.onArchiveSession != null
                                  ? () => widget.onArchiveSession!(s.id)
                                  : null,
                              onRename: widget.onRenameSession != null
                                  ? (newTitle) => widget.onRenameSession!(s.id, newTitle)
                                  : null,
                              onExport: widget.onExportSession != null
                                  ? () => widget.onExportSession!(s)
                                  : null,
                              isPinned: _pinnedIds.contains(s.id),
                              onTogglePin: () => _togglePin(s.id),
                            );
                          }

                          // Afficher plus
                          final remaining = entry.remainingCount;
                          if (remaining != null) {
                            final folder = entry.folderName;
                            final scheme = Theme.of(context).colorScheme;
                            return Padding(
                              padding: const EdgeInsets.only(left: 14, top: 3, bottom: 3),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _folderExpansions[folder] =
                                          (_folderExpansions[folder] ?? 0) + 1;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.expand_more_rounded, size: 14, color: scheme.primary),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Afficher plus ($remaining restantes)',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                            color: scheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          return const SizedBox(height: 4);
                        },
                      ),'''
src = src[:start] + new_builder + src[end:]

io.open(p, 'w', encoding='utf-8', newline='\n').write(src)
print('OK: builder + entries method applied')
