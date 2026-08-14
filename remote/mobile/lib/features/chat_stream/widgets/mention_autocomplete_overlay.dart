import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/mention_item.dart';

class MentionAutocompleteOverlay extends StatelessWidget {
  final String query;
  final List<MentionItem> items;
  final ValueChanged<MentionItem> onSelected;
  final double maxHeight;

  const MentionAutocompleteOverlay({
    super.key,
    required this.query,
    required this.items,
    required this.onSelected,
    this.maxHeight = 260.0,
  });

  List<MentionItem> get _filteredItems {
    final clean = query.startsWith('@') ? query.substring(1).trim().toLowerCase() : query.trim().toLowerCase();
    if (clean.isEmpty) return items;
    return items.where((item) {
      return item.label.toLowerCase().contains(clean) ||
          item.detail.toLowerCase().contains(clean) ||
          item.type.name.toLowerCase().contains(clean) ||
          item.tag.toLowerCase().contains(clean);
    }).toList();
  }

  IconData _iconForType(MentionType type) {
    switch (type) {
      case MentionType.file:
        return Icons.insert_drive_file_outlined;
      case MentionType.rule:
        return Icons.rule_outlined;
      case MentionType.mcp:
        return Icons.extension_outlined;
      case MentionType.conversation:
        return Icons.chat_bubble_outline_rounded;
      case MentionType.terminal:
        return Icons.terminal_outlined;
    }
  }

  Color _badgeColorForType(MentionType type) {
    switch (type) {
      case MentionType.file:
        return AppColors.accentBlue;
      case MentionType.rule:
        return AppColors.warning;
      case MentionType.mcp:
        return AppColors.positive;
      case MentionType.conversation:
        return AppColors.providerCustom;
      case MentionType.terminal:
        return AppColors.inkMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowNeutral,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.alternate_email, size: 14, color: AppColors.accentBlue),
                  const SizedBox(width: 6),
                  Text(
                    'Mentions (${filtered.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.borderSubtle, height: 1),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  'No matching mentions for "$query"',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const Divider(
                    color: AppColors.borderSubtle,
                    height: 1,
                    indent: 40,
                  ),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return InkWell(
                      onTap: () => onSelected(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _badgeColorForType(item.type).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Icon(
                                _iconForType(item.type),
                                size: 16,
                                color: _badgeColorForType(item.type),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.label,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.inkPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceInput,
                                          borderRadius: BorderRadius.circular(AppRadius.sm),
                                        ),
                                        child: Text(
                                          item.type.name,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: _badgeColorForType(item.type),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.detail.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.detail,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.inkMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
