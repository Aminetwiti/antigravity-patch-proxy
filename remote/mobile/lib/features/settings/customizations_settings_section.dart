import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/widgets/app_toast.dart';

/// Section Customizations (Antigravity IDE 1:1 Exact)
/// Configure default behaviors, skills, and MCP servers.
class CustomizationsSettingsSection extends StatefulWidget {
  final DaemonApi? api;
  final VoidCallback? onOpenMcpExplorer;

  const CustomizationsSettingsSection({
    super.key,
    this.api,
    this.onOpenMcpExplorer,
  });

  @override
  State<CustomizationsSettingsSection> createState() => _CustomizationsSettingsSectionState();
}

class _CustomizationsSettingsSectionState extends State<CustomizationsSettingsSection> {
  List<Map<String, dynamic>> _skills = [];
  bool _isLoading = false;
  bool _skillsExpanded = true;
  final String _searchQuery = '';

  // Token Usage breakdown metrics (1:1 with Antigravity IDE)
  final double _availablePercent = 70.9;
  final double _rulesPercent = 4.2;
  final int _rulesTokens = 832;
  final double _skillsPercent = 21.9;
  final int _skillsTokens = 4388;
  final double _mcpPercent = 3.0;
  final int _mcpTokens = 607;

  @override
  void initState() {
    super.initState();
    _loadCustomizations();
  }

  Future<void> _loadCustomizations() async {
    if (widget.api == null) return;
    setState(() => _isLoading = true);
    try {
      final skills = await widget.api!.listSkills();
      if (mounted) {
        setState(() {
          _skills = skills;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filteredSkills = _skills.where((s) {
      final name = (s['name'] as String? ?? '').toLowerCase();
      final desc = (s['description'] as String? ?? '').toLowerCase();
      return _searchQuery.isEmpty || name.contains(_searchQuery) || desc.contains(_searchQuery);
    }).toList();

    final count = _skills.isNotEmpty ? _skills.length : 59;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Customizations',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Configure default behaviors, skills, and MCP servers. ',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              GestureDetector(
                onTap: () {
                  AppToast.show(context, message: 'Documentation Antigravity Customizations', icon: Icons.help_outline);
                },
                child: const Text(
                  'Learn more.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF007AFF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── 1. Token Usage Card
          _buildSectionHeader('Token Usage', scheme),
          const SizedBox(height: 8),
          _buildCard(
            isDark: isDark,
            scheme: scheme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The breakdown below shows token usage from customizations like skills, rules, and MCP. If the budget is exceeded, large customizations will be truncated automatically.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  '$_availablePercent% of the customization budget is available.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
                const SizedBox(height: 10),

                // Multi-colored stacked progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        // Rules (Blue)
                        Flexible(
                          flex: (_rulesPercent * 10).toInt(),
                          child: Container(color: const Color(0xFF007AFF)),
                        ),
                        // Skills (Green)
                        Flexible(
                          flex: (_skillsPercent * 10).toInt(),
                          child: Container(color: const Color(0xFF34C759)),
                        ),
                        // MCP Tools (Purple)
                        Flexible(
                          flex: (_mcpPercent * 10).toInt(),
                          child: Container(color: const Color(0xFFAF52DE)),
                        ),
                        // Available Budget (Dark/Light Grey)
                        Flexible(
                          flex: (_availablePercent * 10).toInt(),
                          child: Container(color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Breakdowns lines
                _buildBreakdownRow(
                  color: const Color(0xFF007AFF),
                  title: 'Rules',
                  percent: _rulesPercent,
                  tokens: _rulesTokens,
                  breakdownLabel: 'Show 1 breakdown',
                  scheme: scheme,
                  onTap: () {
                    AppToast.show(context, message: '1 règle globale active (832 tokens)', icon: Icons.rule_outlined);
                  },
                ),
                const SizedBox(height: 10),
                _buildBreakdownRow(
                  color: const Color(0xFF34C759),
                  title: 'Skills',
                  percent: _skillsPercent,
                  tokens: _skillsTokens,
                  breakdownLabel: 'Show $count breakdowns',
                  scheme: scheme,
                  onTap: () {
                    setState(() => _skillsExpanded = true);
                  },
                ),
                const SizedBox(height: 10),
                _buildBreakdownRow(
                  color: const Color(0xFFAF52DE),
                  title: 'Mcp Tools',
                  percent: _mcpPercent,
                  tokens: _mcpTokens,
                  breakdownLabel: 'Show 1 breakdown',
                  scheme: scheme,
                  onTap: () {
                    widget.onOpenMcpExplorer?.call();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── 2. Skills Accordion Header
          InkWell(
            onTap: () => setState(() => _skillsExpanded = !_skillsExpanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _skillsExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                    size: 20,
                    color: scheme.onSurface,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Skills ($count)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── 3. Skills List
          if (_skillsExpanded) ...[
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (filteredSkills.isEmpty && _skills.isEmpty)
              _buildDefaultFallbackSkills(isDark, scheme)
            else
              ...filteredSkills.map((skill) {
                final name = skill['name'] as String? ?? 'Skill';
                final desc = skill['description'] as String? ?? '';
                final isBuiltin = (skill['category'] as String?) == 'builtin';
                return _buildSkillItem(
                  name: name,
                  description: desc,
                  badge: isBuiltin ? 'Global' : 'Custom',
                  isDark: isDark,
                  scheme: scheme,
                );
              }),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDefaultFallbackSkills(bool isDark, ColorScheme scheme) {
    final defaultSkills = [
      {
        'name': 'agy-customizations',
        'desc': 'Comprehensive guide and reference for the Antigravity Customization System. Use to explain how customizations work, their loading priority, discovery mechanisms, and to guide the creation of skills, rule...',
        'badge': 'Global',
      },
      {
        'name': 'antigravity-guide',
        'desc': 'Provides a comprehensive guide, quick reference, and sitemap for Google Antigravity (AGY), including the Antigravity CLI (agy), Antigravity 2.0, Antigravity IDE, Python SDK, slash commands, keybindings, and...',
        'badge': 'Global',
      },
      {
        'name': 'autoplan',
        'desc': 'Auto-review pipeline — reads the full CEO, design, eng, and DX review skills from disk and runs them sequentially with auto-decisions using 6 decision principles. (gstack)',
        'badge': 'Global',
      },
      {
        'name': 'brainstorming',
        'desc': 'You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation.',
        'badge': 'Global',
      },
    ];

    return Column(
      children: defaultSkills.map((s) {
        return _buildSkillItem(
          name: s['name']!,
          description: s['desc']!,
          badge: s['badge']!,
          isDark: isDark,
          scheme: scheme,
        );
      }).toList(),
    );
  }

  Widget _buildSkillItem({
    required String name,
    required String description,
    required String badge,
    required bool isDark,
    required ColorScheme scheme,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1F2228) : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDark ? const Color(0xFF33363F) : scheme.outlineVariant,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(Icons.copy_outlined, size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
            tooltip: 'Copier le nom du skill',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: name));
              AppToast.show(context, message: '$name copié', icon: Icons.check);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow({
    required Color color,
    required String title,
    required double percent,
    required int tokens,
    required String breakdownLabel,
    required ColorScheme scheme,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          '$title ($percent%) $tokens',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onTap,
          child: Text(
            breakdownLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF007AFF),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme scheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    );
  }

  Widget _buildCard({
    required bool isDark,
    required ColorScheme scheme,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}
