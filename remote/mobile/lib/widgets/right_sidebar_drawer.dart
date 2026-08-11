import 'package:flutter/material.dart';

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
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drawer Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.vertical_split_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'CONTEXT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                    IconButton(
                      icon: Icon(Icons.dock_outlined, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Fermer le panneau',
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
