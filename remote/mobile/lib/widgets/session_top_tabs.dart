import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/theme/app_colors.dart';

enum SessionTabType {
  chat,
  overview,
  review,
  plan,
  tasks,
}

class SessionTopTabs extends StatelessWidget {
  final SessionTabType activeTab;
  final Function(SessionTabType tab) onTabChanged;
  final int filesChangedCount;
  final bool hasPlan;
  final bool hasTasks;
  final int runningTasksCount;

  const SessionTopTabs({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    this.filesChangedCount = 0,
    this.hasPlan = false,
    this.hasTasks = false,
    this.runningTasksCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceRaised : scheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.borderSubtle : scheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          _TabPill(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            isSelected: activeTab == SessionTabType.chat,
            onTap: () => onTabChanged(SessionTabType.chat),
          ),
          const SizedBox(width: 6),
          _TabPill(
            icon: Icons.dashboard_outlined,
            label: 'Overview',
            isSelected: activeTab == SessionTabType.overview,
            badge: runningTasksCount > 0 ? '$runningTasksCount active' : null,
            badgeColor: isDark ? AppColors.accentBlue : scheme.primary,
            onTap: () => onTabChanged(SessionTabType.overview),
          ),
          if (filesChangedCount > 0) ...[
            const SizedBox(width: 6),
            _TabPill(
              icon: Icons.rate_review_outlined,
              label: 'Review',
              badge: '+$filesChangedCount',
              badgeColor: isDark ? AppColors.positive : const Color(0xFF1A7F37),
              isSelected: activeTab == SessionTabType.review,
              onTap: () => onTabChanged(SessionTabType.review),
            ),
          ],
          if (hasPlan) ...[
            const SizedBox(width: 6),
            _TabPill(
              icon: Icons.description_outlined,
              label: 'Plan',
              badge: 'Proceed ⌘↵',
              badgeColor: isDark ? AppColors.accentBlue : scheme.primary,
              isSelected: activeTab == SessionTabType.plan,
              onTap: () => onTabChanged(SessionTabType.plan),
            ),
          ],
          if (hasTasks) ...[
            const SizedBox(width: 6),
            _TabPill(
              icon: Icons.checklist_rtl_outlined,
              label: 'Tasks',
              isSelected: activeTab == SessionTabType.tasks,
              onTap: () => onTabChanged(SessionTabType.tasks),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabPill extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  const _TabPill({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  @override
  State<_TabPill> createState() => _TabPillState();
}

class _TabPillState extends State<_TabPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = widget.isSelected;

    final Color fgColor;
    final Color bgColor;
    final Color borderColor;

    if (isDark) {
      fgColor = isSelected
          ? AppColors.inkPrimary
          : (_hovered ? AppColors.inkSecondary : AppColors.inkMuted);
      bgColor = isSelected
          ? AppColors.listSelectionBg
          : (_hovered ? AppColors.surfaceHover.withValues(alpha: 0.5) : Colors.transparent);
      borderColor = isSelected ? AppColors.borderStrong : Colors.transparent;
    } else {
      fgColor = isSelected
          ? scheme.primary
          : (_hovered ? scheme.onSurface : scheme.onSurfaceVariant);
      bgColor = isSelected
          ? scheme.primary.withValues(alpha: 0.12)
          : (_hovered ? scheme.surfaceContainerHighest : Colors.transparent);
      borderColor = isSelected
          ? scheme.primary.withValues(alpha: 0.35)
          : Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: fgColor),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: fgColor,
                  letterSpacing: -0.1,
                ),
              ),
              if (widget.badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: (widget.badgeColor ?? (isDark ? AppColors.accentBlue : scheme.primary))
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: (widget.badgeColor ?? (isDark ? AppColors.accentBlue : scheme.primary))
                          .withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    widget.badge!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: widget.badgeColor ?? (isDark ? AppColors.accentBlue : scheme.primary),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
