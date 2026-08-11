import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../core/protocol/daemon_api.dart';

class WorkspaceScreen extends StatefulWidget {
  final DaemonApi? api;
  final String workspacePath;

  const WorkspaceScreen({super.key, this.api, this.workspacePath = '.'});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String _selectedFilePath = '';
  bool _isLoadingTree = true;
  bool _isLoadingCode = false;
  List<Map<String, dynamic>> _files = [];
  String _codeContent = '// Sélectionnez un fichier';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    if (widget.api == null) {
      if (mounted) setState(() => _isLoadingTree = false);
      return;
    }
    try {
      final res = await widget.api!.listFiles(widget.workspacePath);
      if (mounted) {
        setState(() {
          _files = List<Map<String, dynamic>>.from(res['files'] ?? []);
          _isLoadingTree = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingTree = false);
    }
  }

  Future<void> _loadFile(String path) async {
    if (widget.api == null) return;
    setState(() {
      _selectedFilePath = path;
      _isLoadingCode = true;
    });
    try {
      final res = await widget.api!.readFile(path, workspacePath: widget.workspacePath);
      if (mounted) {
        setState(() {
          _codeContent = res['content'] as String? ?? '';
          _isLoadingCode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _codeContent = 'Erreur: $e';
          _isLoadingCode = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        
        final fileTree = Container(
          width: isMobile ? double.infinity : 280,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.folder_open, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'antigravity-add-model-main',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: _isLoadingTree 
                  ? _buildSkeletonTree()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: _files.length,
                      itemBuilder: (context, index) {
                        final file = _files[index];
                        final isDir = file['isDir'] == true;
                        final name = file['name'] as String;
                        final depth = file['depth'] as int;
                        final fullPath = file['fullPath'] as String;

                        if (isDir) {
                          return _TreeFolder(title: name, depth: depth);
                        } else {
                          return _TreeFile(
                            title: name,
                            depth: depth,
                            onTap: () => _loadFile(fullPath),
                          );
                        }
                      },
                    ),
              ),
            ],
          ),
        );

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            title: const Text('Explorateur de Fichiers'),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          ),
          drawer: isMobile ? Drawer(child: SafeArea(child: fileTree)) : null,
          body: Row(
            children: [
              if (!isMobile) fileTree,
              // ── Right Code View
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedFilePath,
                          style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.copy_all_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        tooltip: 'Copier le contenu',
                        onPressed: _selectedFilePath.isEmpty || _isLoadingCode
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await Clipboard.setData(ClipboardData(text: _codeContent));
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Contenu copié : ${_selectedFilePath.split('/').last}'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: _isLoadingCode
                        ? _buildSkeletonCode()
                        : SingleChildScrollView(
                            child: Text(
                              _codeContent,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.5,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _buildSkeletonTree() {
    return ListView.builder(
      itemCount: 8,
      padding: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 100 + (index % 3) * 40.0,
                height: 14,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeletonCode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(10, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: index % 2 == 0 ? 200 : 300,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}

class _TreeFolder extends StatelessWidget {
  final String title;
  final int depth;

  const _TreeFolder({required this.title, required this.depth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 8.0 + depth * 14, top: 4, bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 16, color: AppColors.warning),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}

class _TreeFile extends StatelessWidget {
  final String title;
  final int depth;
  final VoidCallback onTap;

  const _TreeFile({required this.title, required this.depth, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: 8.0 + depth * 14, top: 2, bottom: 2),
        child: Row(
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
