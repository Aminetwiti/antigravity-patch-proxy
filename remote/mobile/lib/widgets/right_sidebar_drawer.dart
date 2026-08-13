import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class RightSidebarDrawer extends StatelessWidget {
  final int subagentsCount;
  final int filesChangedCount;
  final int artifactsCount;
  final int uploadsCount;
  final int backgroundTasksCount;

  const RightSidebarDrawer({
    super.key,
    this.subagentsCount = 0,
    this.filesChangedCount = 10,
    this.artifactsCount = 1,
    this.uploadsCount = 0,
    this.backgroundTasksCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      // Rail PC : canvas Zinc-950 + bordure gauche
      backgroundColor: AppColors.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AppColors.borderSubtle, width: 1),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drawer Header — PC .nav-group-label : 10px uppercase espacé
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.vertical_split_outlined, size: 16, color: AppColors.inkFaint),
                  const SizedBox(width: 8),
                  const Text(
                    'CONTEXT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.inkFaint,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: AppColors.inkSecondary),
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
                    badgeCount: subagentsCount,
                    onTap: () {},
                  ),
                  _ContextItemRow(
                    title: 'Files Changed',
                    badgeCount: filesChangedCount,
                    onTap: () {},
                  ),
                  _ContextItemRow(
                    title: 'Artifacts',
                    badgeCount: artifactsCount,
                    onTap: () {},
                  ),
                  _ContextItemRow(
                    title: 'Uploads',
                    badgeCount: uploadsCount,
                    onTap: () {},
                  ),
                  _ContextItemRow(
                    title: 'Background Tasks',
                    badgeCount: backgroundTasksCount,
                    onTap: () {},
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

  const _ContextItemRow({
    required this.title,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          // PC .nav-item : hover surfaceHover
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.inkPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Badge pill — PC --r-pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
