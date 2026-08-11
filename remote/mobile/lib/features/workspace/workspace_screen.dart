import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final String _selectedFilePath = 'lib/main.dart';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Explorateur de Fichiers'),
        backgroundColor: AppColors.surfaceRaised,
      ),
      body: Row(
        children: [
          // ── Left File Tree
          Container(
            width: MediaQuery.of(context).size.width * 0.55,
            decoration: BoxDecoration(
              color: AppColors.surfaceBase,
              border: Border(right: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: const [
                      Icon(Icons.folder_open, size: 16, color: AppColors.inkSecondary),
                      SizedBox(width: 8),
                      Text(
                        'antigravity-add-model-main',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkPrimary),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.borderSubtle),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: const [
                      _TreeFolder(title: 'lib', depth: 0),
                      _TreeFile(title: 'main.dart', depth: 1),
                      _TreeFile(title: 'config/env_config.dart', depth: 1),
                      _TreeFile(title: 'core/framing.dart', depth: 1),
                      _TreeFile(title: 'core/network/websocket_client.dart', depth: 1),
                      _TreeFile(title: 'features/settings/settings_screen.dart', depth: 1),
                      _TreeFile(title: 'theme/app_colors.dart', depth: 1),
                      _TreeFolder(title: 'config', depth: 0),
                      _TreeFile(title: 'env_dev.json', depth: 1),
                      _TreeFile(title: 'env_emulator.json', depth: 1),
                      _TreeFile(title: 'env_prod.json', depth: 1),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Right Code View
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: AppColors.surfaceRaised,
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 16, color: AppColors.inkSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedFilePath,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.inkPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        icon: const Icon(Icons.download_outlined, size: 16, color: AppColors.inkMuted),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.borderSubtle, height: 1),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: AppColors.surfaceInput,
                    child: const SingleChildScrollView(
                      child: Text(
                        '''// lib/main.dart
import 'package:flutter/material.dart';

void main() {
  runApp(const AntigravityRemoteApp());
}

class AntigravityRemoteApp extends StatelessWidget {
  const AntigravityRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Antigravity Mobile',
      theme: AppTheme.darkTheme,
      home: const AntigravityMainScreen(),
    );
  }
}''',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                          color: AppColors.inkPrimary,
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
          Text(title, style: const TextStyle(fontSize: 12.5, color: AppColors.inkPrimary)),
        ],
      ),
    );
  }
}

class _TreeFile extends StatelessWidget {
  final String title;
  final int depth;

  const _TreeFile({required this.title, required this.depth});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: EdgeInsets.only(left: 8.0 + depth * 14, top: 2, bottom: 2),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 15, color: AppColors.inkSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
