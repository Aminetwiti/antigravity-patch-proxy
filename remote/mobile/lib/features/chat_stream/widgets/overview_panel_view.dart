import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/theme/app_colors.dart';

class OverviewPanelView extends StatelessWidget {
  final String sessionTitle;
  final String workspacePath;
  final List<String> modifiedFiles;
  final List<String> artifacts;
  final List<String> backgroundTasks;
  final int subagentsCount;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenPlan;
  final VoidCallback onOpenSubagents;

  const OverviewPanelView({
    super.key,
    required this.sessionTitle,
    required this.workspacePath,
    this.modifiedFiles = const [],
    this.artifacts = const [],
    this.backgroundTasks = const [],
    this.subagentsCount = 0,
    required this.onOpenReview,
    required this.onOpenPlan,
    required this.onOpenSubagents,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        // Session info card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sessionTitle.isNotEmpty ? sessionTitle : 'Nouvelle session',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              if (workspacePath.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.folder_outlined, size: 12, color: AppColors.inkFaint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        workspacePath,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkMuted,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Subagents Section
        _SectionCard(
          title: 'Subagents ($subagentsCount)',
          icon: Icons.hub_outlined,
          iconColor: AppColors.warning,
          actionText: 'Voir',
          onAction: onOpenSubagents,
          child: subagentsCount == 0
              ? const Text(
                  'Aucun sous-agent actif dans cette session.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                )
              : Text(
                  '$subagentsCount sous-agent(s) en cours ou terminés.',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                ),
        ),

        const SizedBox(height: 12),

        // Files Changed Section
        _SectionCard(
          title: 'Fichiers modifiés (${modifiedFiles.length})',
          icon: Icons.rate_review_outlined,
          iconColor: AppColors.positive,
          actionText: modifiedFiles.isNotEmpty ? 'Revoir' : null,
          onAction: onOpenReview,
          child: modifiedFiles.isEmpty
              ? const Text(
                  'Aucun fichier modifié pour le moment.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                )
              : Column(
                  children: modifiedFiles.take(5).map((f) {
                    final name = f.split(RegExp(r'[\\/]')).last;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, size: 12, color: AppColors.inkMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.inkPrimary,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),

        const SizedBox(height: 12),

        // Artifacts Section
        _SectionCard(
          title: 'Artéfacts (${artifacts.length})',
          icon: Icons.article_outlined,
          iconColor: AppColors.accentBlue,
          actionText: artifacts.isNotEmpty ? 'Plan' : null,
          onAction: onOpenPlan,
          child: artifacts.isEmpty
              ? const Text(
                  'Aucun artéfact généré.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                )
              : Column(
                  children: artifacts.take(4).map((a) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.description_outlined, size: 12, color: AppColors.accentBlueBright),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              a,
                              style: const TextStyle(fontSize: 12, color: AppColors.inkPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),

        const SizedBox(height: 12),

        // Background Tasks Section
        _SectionCard(
          title: 'Tâches d\'arrière-plan (${backgroundTasks.length})',
          icon: Icons.terminal_outlined,
          iconColor: AppColors.info,
          child: backgroundTasks.isEmpty
              ? const Text(
                  'Aucun processus ou serveur actif.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                )
              : Column(
                  children: backgroundTasks.map((t) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceInput,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accentBlue),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.inkPrimary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String? actionText;
  final VoidCallback? onAction;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    this.actionText,
    this.onAction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkPrimary,
                  ),
                ),
              ),
              if (actionText != null && onAction != null)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onAction!();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceInput,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Text(
                      actionText!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentBlueBright,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
