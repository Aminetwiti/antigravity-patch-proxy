import 'package:flutter/material.dart';
import '../core/protocol/messages.dart';

/// Barre de fil d'Ariane (Breadcrumb) élégante et compacte affichée entre
/// le Header (AppBar) et la barre d'onglets (Nav : Chat, Review, Overview...).
/// Format : `[nom-du-projet] / [titre-de-la-session-ou-contexte]`
class SessionBreadcrumb extends StatelessWidget {
  final String projectName;
  final String sessionTitle;
  final VoidCallback? onSelectProject;
  final VoidCallback? onSelectSession;
  final VoidCallback? onOpenIde;
  final List<ProjectItem>? projects;

  const SessionBreadcrumb({
    super.key,
    required this.projectName,
    this.sessionTitle = '',
    this.onSelectProject,
    this.onSelectSession,
    this.onOpenIde,
    this.projects,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final displayProject = projectName.trim().isNotEmpty
        ? projectName.trim()
        : 'antigravity-add-model-main';

    final displayTitle = sessionTitle.trim().isNotEmpty
        ? sessionTitle.trim()
        : '';

    final canSwitchProject = onSelectProject != null && (projects == null || projects!.length > 1);

    return Container(
      height: 30,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141518) : scheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF222429) : scheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Segment 1 : Nom du projet / workspace
          Flexible(
            flex: displayTitle.isNotEmpty ? 1 : 2,
            fit: FlexFit.loose,
            child: InkWell(
              onTap: canSwitchProject ? onSelectProject : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayProject,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: isDark ? const Color(0xFF9E9FA9) : scheme.onSurfaceVariant,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (canSwitchProject) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 14,
                        color: isDark ? const Color(0xFF6B6E77) : scheme.outline,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Séparateur ' / ' et Segment 2 : Titre de la session / Contexte
          if (displayTitle.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '/',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: isDark ? const Color(0xFF5A5D66) : scheme.outline,
                ),
              ),
            ),
            Flexible(
              flex: 2,
              fit: FlexFit.loose,
              child: InkWell(
                onTap: onSelectSession,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Text(
                    displayTitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: isDark ? const Color(0xFF9E9FA9) : scheme.onSurfaceVariant,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
          if (onOpenIde != null) ...[
            const Spacer(),
            InkWell(
              onTap: onOpenIde,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2430) : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2A3142) : scheme.outlineVariant.withValues(alpha: 0.4),
                    width: 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 11,
                      color: isDark ? const Color(0xFF60A5FA) : scheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Open IDE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFFD4D4D8) : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
