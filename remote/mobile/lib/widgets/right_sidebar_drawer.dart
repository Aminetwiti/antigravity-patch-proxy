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
      backgroundColor: AppColors.surfaceBase,
      child: SafeArea(
        child: Column(
          children: [
            // Right Sidebar Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.article_outlined, size: 20, color: AppColors.inkSecondary),
                  const SizedBox(width: 8),
                  const Icon(Icons.note_add_outlined, size: 18, color: AppColors.inkMuted),
                  const Spacer(),
                  const Icon(Icons.add, size: 18, color: AppColors.inkMuted),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.dock_outlined, size: 20, color: AppColors.inkSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fermer le panneau',
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.borderSubtle),

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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.inkPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceInput,
                borderRadius: BorderRadius.circular(10),
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
            const Spacer(),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}
