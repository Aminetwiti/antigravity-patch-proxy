import 'package:flutter/material.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/widgets/app_toast.dart';

/// Section Customizations (Antigravity IDE 1:1)
/// Permet d'explorer et de prévisualiser les Skills, Rules, et Serveurs MCP.
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

class _CustomizationsSettingsSectionState extends State<CustomizationsSettingsSection>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _skills = [];
  List<Map<String, dynamic>> _rules = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCustomizations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomizations() async {
    if (widget.api == null) return;
    setState(() => _isLoading = true);
    try {
      final skills = await widget.api!.listSkills();
      final rules = await widget.api!.getRules();
      if (mounted) {
        setState(() {
          _skills = skills;
          _rules = rules;
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

    return Padding(
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
          Text(
            'Explore active Skills, Rules, and Model Context Protocol (MCP) servers.',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Tabs
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
                width: 1,
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF007AFF),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: const Color(0xFF007AFF),
              unselectedLabelColor: scheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: 'Skills (${_skills.isNotEmpty ? _skills.length : 42})'),
                Tab(text: 'Rules (${_rules.length})'),
                const Tab(text: 'MCP Servers'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. SKILLS
                _buildSkillsTab(filteredSkills, isDark, scheme),

                // 2. RULES
                _buildRulesTab(isDark, scheme),

                // 3. MCP SERVERS
                _buildMcpTab(isDark, scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillsTab(List<Map<String, dynamic>> skills, bool isDark, ColorScheme scheme) {
    if (_isLoading && skills.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return Column(
      children: [
        // Search bar
        TextField(
          style: TextStyle(fontSize: 13, color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Rechercher un skill (ex: ponytail, diagram, browse)...',
            hintStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            prefixIcon: Icon(Icons.search, size: 16, color: scheme.onSurfaceVariant),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
        ),
        const SizedBox(height: 10),

        Expanded(
          child: skills.isEmpty
              ? Center(
                  child: Text(
                    'Aucun skill trouvé.',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  itemCount: skills.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final s = skills[i];
                    final name = s['name'] as String? ?? 'Skill';
                    final desc = s['description'] as String? ?? '';
                    final cat = s['category'] as String? ?? 'builtin';

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.extension_outlined, size: 16, color: const Color(0xFF007AFF)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: scheme.onSurface),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cat == 'builtin'
                                      ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                                      : Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  cat.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: cat == 'builtin' ? const Color(0xFF007AFF) : Colors.amber,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              desc,
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRulesTab(bool isDark, ColorScheme scheme) {
    if (_rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.rule_outlined, size: 36, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'Règles Antigravity Actives',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Les règles globales et de workspace sont chargées depuis ~/.gemini/antigravity/rules et AGENTS.md.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _rules.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final r = _rules[i];
        final name = r['name'] as String? ?? 'Rule';
        final content = r['content'] as String? ?? '';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
              if (content.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(content, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant), maxLines: 3),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMcpTab(bool isDark, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, size: 40, color: const Color(0xFF007AFF)),
            const SizedBox(height: 12),
            Text(
              'Serveurs Model Context Protocol (MCP)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              'Gérez vos serveurs MCP connectés (Coolify, filesystem, GitHub sidecars) et découvrez les outils disponibles pour l\'agent.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () {
                if (widget.onOpenMcpExplorer != null) {
                  widget.onOpenMcpExplorer!();
                } else {
                  AppToast.show(context, message: 'Ouvrir l\'explorateur MCP depuis le menu latéral.', icon: Icons.hub_outlined);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Ouvrir l\'explorateur MCP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
