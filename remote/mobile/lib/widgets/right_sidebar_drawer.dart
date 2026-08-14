import 'package:flutter/material.dart';

import '../core/protocol/daemon_api.dart';
import '../features/scheduled_tasks/scheduled_tasks_screen.dart';
import '../features/subagents/subagents_drawer.dart';
import '../features/mcp/mcp_explorer_screen.dart';
import 'artifact_viewer_modal.dart';
import '../theme/app_colors.dart';

class RightSidebarDrawer extends StatefulWidget {
  final DaemonApi? api;
  final String activeSessionId;
  final int subagentsCount;
  final int filesChangedCount;
  final int artifactsCount;
  final int uploadsCount;
  final int backgroundTasksCount;
  final int scheduledTasksCount;

  const RightSidebarDrawer({
    super.key,
    this.api,
    this.activeSessionId = '',
    this.subagentsCount = 0,
    this.filesChangedCount = 0,
    this.artifactsCount = 0,
    this.uploadsCount = 0,
    this.backgroundTasksCount = 0,
    this.scheduledTasksCount = 0,
  });

  @override
  State<RightSidebarDrawer> createState() => _RightSidebarDrawerState();
}

class _RightSidebarDrawerState extends State<RightSidebarDrawer> {
  bool _isLoadingArtifacts = false;
  List<Map<String, dynamic>> _artifacts = [];
  bool _artifactsExpanded = false;

  Future<void> _fetchArtifacts() async {
    if (widget.api == null || widget.activeSessionId.isEmpty) return;
    setState(() => _isLoadingArtifacts = true);
    try {
      // Fetch files from the brain directory
      final path = '.gemini/antigravity-ide/brain/${widget.activeSessionId}/';
      final res = await widget.api!.listFiles(path);
      final files = res['files'] as List<dynamic>? ?? [];
      
      final arts = <Map<String, dynamic>>[];
      for (final f in files) {
        if (f is Map && f['name'] != null && f['name'].toString().endsWith('.md')) {
          arts.add({'name': f['name'], 'path': f['path'] ?? '$path${f['name']}'});
        }
      }
      if (mounted) setState(() => _artifacts = arts);
    } catch (e) {
      debugPrint('Failed to fetch artifacts: $e');
    } finally {
      if (mounted) setState(() => _isLoadingArtifacts = false);
    }
  }

  void _openArtifact(Map<String, dynamic> artifact) {
    if (widget.api == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ArtifactViewerModal(
        api: widget.api!,
        artifactPath: artifact['path'],
        artifactName: artifact['name'],
        workspacePath: _brainRoot,
      ),
    );
  }

  /// Racine du brain pour la session active — le daemon confine read_file
  /// sous ce workspace (resolvePath), donc les chemins relatifs des artifacts
  /// doivent être résolus contre `~/.gemini/antigravity-ide/brain/<sessionId>/`.
  String get _brainRoot =>
      '.gemini/antigravity-ide/brain/${widget.activeSessionId}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: scheme.outlineVariant, width: 1),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drawer Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.vertical_split_outlined, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'CONTEXTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fermer le panneau',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Context Accordion List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _ContextItemRow(
                    title: 'Subagents',
                    badgeCount: widget.subagentsCount,
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => SizedBox(
                          height: MediaQuery.of(context).size.height * 0.7,
                          child: SubagentsDrawer(
                            subagents: const [],
                            onKillAgent: (_) {},
                          ),
                        ),
                      );
                    },
                  ),
                  _ContextItemRow(
                    title: 'Files Changed',
                    badgeCount: widget.filesChangedCount,
                    onTap: () {},
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ContextItemRow(
                        title: 'Artifacts',
                        badgeCount: widget.artifactsCount,
                        onTap: () {
                          setState(() {
                            _artifactsExpanded = !_artifactsExpanded;
                          });
                          if (_artifactsExpanded && _artifacts.isEmpty) {
                            _fetchArtifacts();
                          }
                        },
                        isExpanded: _artifactsExpanded,
                      ),
                      if (_artifactsExpanded)
                        AnimatedContainer(
                          duration: AppMotion.fast,
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                          child: _isLoadingArtifacts
                              ? Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(scheme.primary)))),
                                )
                              : _artifacts.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text('Aucun artefact', style: TextStyle(color: scheme.outline, fontSize: 12)),
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: _artifacts.map((art) => InkWell(
                                        onTap: () => _openArtifact(art),
                                        borderRadius: BorderRadius.circular(AppRadius.sm),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                          child: Row(
                                            children: [
                                              Icon(Icons.article_outlined, size: 14, color: scheme.primary),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  art['name'] ?? 'Document',
                                                  style: TextStyle(fontSize: 12, color: scheme.onSurface),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )).toList(),
                                    ),
                        ),
                    ],
                  ),
                  _ContextItemRow(
                    title: 'Uploads',
                    badgeCount: widget.uploadsCount,
                    onTap: () {},
                  ),
                    _ContextItemRow(
                      title: 'Scheduled Tasks',
                      badgeCount: widget.scheduledTasksCount > 0 ? widget.scheduledTasksCount : widget.backgroundTasksCount,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => ScheduledTasksScreen(
                              tasks: const [],
                              onCancelTask: (id) => widget.api?.cancelScheduledTask(id),
                              onTriggerNow: (id) => widget.api?.triggerScheduledTask(id),
                            ),
                          ),
                        );
                      },
                    ),
                    _ContextItemRow(
                      title: 'MCP Servers',
                      badgeCount: 0,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => McpExplorerScreen(api: widget.api),
                          ),
                        );
                      },
                    ),
                  _ContextItemRow(
                    title: 'Background Tasks',
                    badgeCount: widget.backgroundTasksCount,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => ScheduledTasksScreen(
                            tasks: const [],
                            onCancelTask: (id) => widget.api?.cancelScheduledTask(id),
                            onTriggerNow: (id) => widget.api?.triggerScheduledTask(id),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextItemRow extends StatelessWidget {
  final String title;
  final int badgeCount;
  final VoidCallback onTap;
  final bool isExpanded;

  const _ContextItemRow({
    required this.title,
    required this.badgeCount,
    required this.onTap,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isExpanded ? scheme.surfaceContainerHighest : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: scheme.outlineVariant, width: 0.5),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    fontSize: 11,
                    color: badgeCount > 0 ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: isExpanded ? 0.25 : 0,
                duration: AppMotion.fast,
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
