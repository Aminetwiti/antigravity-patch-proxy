# -*- coding: utf-8 -*-
"""Remove _WorkspaceFolderSection; insert _SidebarEntry + _FolderHeader."""
import io

p = 'lib/features/sessions/sessions_list.dart'
lines = io.open(p, encoding='utf-8').read().split('\n')

start = None
end = None
for i, l in enumerate(lines):
    if '// ── Workspace Folder Section (Grouping & Sessions under a folder)' in l:
        start = i
    if start is not None and '// ── Individual Session Row Item' in l:
        end = i
        break
assert start is not None and end is not None, (start, end)

new_classes = '''// ── Entrée aplatie de la sidebar (virtualisation ListView.builder) ─────────
class _SidebarEntry {
  final String folderName;
  final ProjectItem? project;
  final CascadeSession? session;
  final bool isHeader;
  final bool isEmptyFolder;
  final int? remainingCount;

  const _SidebarEntry.header(this.folderName, this.project)
      : session = null,
        isHeader = true,
        isEmptyFolder = false,
        remainingCount = null;

  const _SidebarEntry.empty(this.folderName)
      : project = null,
        session = null,
        isHeader = false,
        isEmptyFolder = true,
        remainingCount = null;

  const _SidebarEntry.row(this.session, this.folderName)
      : project = null,
        isHeader = false,
        isEmptyFolder = false,
        remainingCount = null;

  const _SidebarEntry.showMore(this.folderName, this.remainingCount)
      : project = null,
        session = null,
        isHeader = false,
        isEmptyFolder = false;

  const _SidebarEntry.spacer()
      : folderName = '',
        project = null,
        session = null,
        isHeader = false,
        isEmptyFolder = false,
        remainingCount = null;
}

// ── Workspace Folder Header (séparé pour virtualisation) ───────────────────
class _FolderHeader extends StatelessWidget {
  final String folderName;
  final ProjectItem? project;
  final VoidCallback onToggleCollapse;
  final void Function(ProjectItem? project)? onNewConversation;
  final VoidCallback? onOpenSettings;

  const _FolderHeader({
    super.key,
    required this.folderName,
    this.project,
    required this.onToggleCollapse,
    this.onNewConversation,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onToggleCollapse,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                folderName,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: scheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // ── Project Options Context Menu (:)
            PopupMenuButton<String>(
              tooltip: 'Options du projet',
              color: isDark ? const Color(0xFF1B1D22) : scheme.surfaceContainer,
              surfaceTintColor: Colors.transparent,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: BorderSide(color: isDark ? const Color(0xFF2C2F36) : scheme.outlineVariant, width: 1),
              ),
              icon: Icon(
                Icons.more_vert_rounded,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              padding: EdgeInsets.zero,
              onSelected: (val) {
                if (val == 'copy_name') {
                  Clipboard.setData(ClipboardData(text: folderName));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Nom du projet "$folderName" copié'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else if (val == 'settings') {
                  onOpenSettings?.call();
                }
              },
              itemBuilder: (ctx) {
                final itemScheme = Theme.of(ctx).colorScheme;
                return [
                  PopupMenuItem<String>(
                    value: 'copy_name',
                    height: 32,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.copy_rounded, size: 14, color: itemScheme.onSurface),
                        const SizedBox(width: 8),
                        Text('Copy Project Name', style: TextStyle(fontSize: 12.5, color: itemScheme.onSurface)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'settings',
                    height: 32,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.settings_outlined, size: 14, color: itemScheme.onSurface),
                        const SizedBox(width: 8),
                        Text('Project Settings', style: TextStyle(fontSize: 12.5, color: itemScheme.onSurface)),
                      ],
                    ),
                  ),
                ];
              },
            ),
            const SizedBox(width: 2),
            // ── New Session in Project (+)
            Tooltip(
              message: 'New Conversation in Project',
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onNewConversation?.call(project);
                },
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: Color(0xFF8F909A),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

'''
lines[start:end] = [new_classes]
io.open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
print('OK: classes swapped')
