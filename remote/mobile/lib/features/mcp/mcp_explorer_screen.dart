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

  @override
  void initState() {
    super.initState();
    _servers = widget.servers;
    if (widget.api != null) {
      _loadServers();
    }
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _servers.length,
                            itemBuilder: (context, index) {
                              final server = _servers[index];
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
