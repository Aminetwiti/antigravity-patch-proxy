import 'package:flutter/material.dart';
import 'models/mcp_server_info.dart';
import '../../core/protocol/daemon_api.dart';
import 'package:mobile/theme/app_colors.dart';

class McpExplorerScreen extends StatefulWidget {
  final DaemonApi? api;
  final List<McpServerInfo> servers;

  const McpExplorerScreen({super.key, this.api, this.servers = const []});

  @override
  State<McpExplorerScreen> createState() => _McpExplorerScreenState();
}

class _McpExplorerScreenState extends State<McpExplorerScreen> {
  List<McpServerInfo> _servers = [];
  bool _loading = false;
  String? _error;
  int? _expandedIndex;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _servers = widget.servers;
    if (widget.api != null) {
      _loadServers();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadServers() async {
    setState(() { _loading = true; _error = null; });
    try {
      final servers = await widget.api!.getMcpServers();
      setState(() { _servers = servers; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Erreur lors du chargement des serveurs'; _loading = false; });
    }
  }

  List<McpServerInfo> get _filteredServers {
    if (_searchQuery.isEmpty) return _servers;
    final q = _searchQuery.toLowerCase();
    return _servers.where((s) {
      if (s.name.toLowerCase().contains(q)) return true;
      if (s.description?.toLowerCase().contains(q) == true) return true;
      return s.tools.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayedServers = _filteredServers;

    return Scaffold(
      appBar: AppBar(title: const Text('Serveurs MCP')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadServers,
              child: Column(
                children: [
                  if (_error != null)
                    Container(
                      color: scheme.errorContainer,
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                            ),
                          ),
                          TextButton(onPressed: _loadServers, child: const Text('Réessayer'))
                        ],
                      ),
                    ),
                  if (_servers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 13),
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText: 'Rechercher un serveur ou un outil...',
                          hintStyle: TextStyle(fontSize: 12.5, color: scheme.outline),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: BorderSide(color: scheme.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'MCP Servers (${_servers.length})',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                  ),
                  Expanded(
                    child: _servers.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 100),
                              Center(
                                child: Text('Aucun serveur MCP configuré', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          )
                        : displayedServers.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 80),
                                  Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.search_off, size: 36, color: scheme.outline),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Aucun serveur ou outil pour « $_searchQuery »',
                                          style: TextStyle(fontSize: 12.5, color: scheme.outline),
                                        ),
                                        const SizedBox(height: 8),
                                        TextButton(
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                          child: const Text('Effacer la recherche', style: TextStyle(fontSize: 12)),
                                        )
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: displayedServers.length,
                                itemBuilder: (context, index) {
                                  final server = displayedServers[index];
                                  final isExpanded = _expandedIndex == index;
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                  side: BorderSide(color: scheme.outlineVariant),
                                ),
                                child: Column(
                                  children: [
                                    ListTile(
                                      title: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: server.status == 'ready' ? AppColors.positive : scheme.tertiary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            server.name,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: scheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(AppRadius.sm),
                                            ),
                                            child: Text(
                                              '${server.toolCount} tools',
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: server.description != null
                                          ? Text(server.description!, style: const TextStyle(fontSize: 11))
                                          : null,
                                      onTap: () => setState(() => _expandedIndex = isExpanded ? null : index),
                                    ),
                                    if (isExpanded)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: server.tools
                                              .map((t) => Chip(
                                                    label: Text(t, style: const TextStyle(fontSize: 11)),
                                                    padding: EdgeInsets.zero,
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                  ],
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
