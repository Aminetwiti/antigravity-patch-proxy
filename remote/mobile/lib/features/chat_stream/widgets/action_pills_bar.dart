import 'package:flutter/material.dart';

class SlashAction {
  final String command;
  final String label;
  final IconData icon;

  const SlashAction({
    required this.command,
    required this.label,
    required this.icon,
  });
}

class ActionPillsBar extends StatelessWidget {
  const ActionPillsBar({
    super.key,
    required this.onActionSelected,
    this.actions = const [
      SlashAction(command: '/btw', label: 'BTW (Side Question)', icon: Icons.help_outline),
      SlashAction(command: '/grill-me', label: 'Grill Me (Plan Interview)', icon: Icons.psychology_outlined),
      SlashAction(command: '/teamwork-preview', label: 'Teamwork (Multi-Agent)', icon: Icons.group_work_outlined),
      SlashAction(command: '/goal', label: 'Goal (Long Task)', icon: Icons.flag_outlined),
      SlashAction(command: '/learn', label: 'Learn (Save Habit)', icon: Icons.school_outlined),
    ],
  });

  final ValueChanged<String> onActionSelected;
  final List<SlashAction> actions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionChip(
            avatar: Icon(action.icon, size: 16),
            label: Text(action.command, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            tooltip: action.label,
            onPressed: () => onActionSelected(action.command),
          );
        },
      ),
    );
  }
}
