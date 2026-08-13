import 'package:flutter/material.dart';
import '../core/protocol/daemon_api.dart';
import '../core/protocol/markdown_renderer.dart';
import '../theme/app_colors.dart';

class ArtifactViewerModal extends StatefulWidget {
  final DaemonApi api;
  final String artifactPath;
  final String artifactName;
  final String? workspacePath;

  const ArtifactViewerModal({
    super.key,
    required this.api,
    required this.artifactPath,
    required this.artifactName,
    this.workspacePath,
  });

  @override
  State<ArtifactViewerModal> createState() => _ArtifactViewerModalState();
}

class _ArtifactViewerModalState extends State<ArtifactViewerModal> {
  bool _isLoading = true;
  String _content = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchArtifactContent();
  }

  Future<void> _fetchArtifactContent() async {
    try {
      final res = await widget.api.readFile(
        widget.artifactPath,
        workspacePath: widget.workspacePath,
      );
      if (mounted) {
        setState(() {
          _content = res['content'] as String? ?? 'Contenu vide';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Impossible de charger l\'artefact: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.article_outlined, size: 20, color: AppColors.accentBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.artifactName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppColors.inkSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.accentBlue)))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.danger),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: _MarkdownBody(content: _content),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkdownBody extends StatelessWidget {
  final String content;

  const _MarkdownBody({required this.content});

  @override
  Widget build(BuildContext context) {
    final blocks = MarkdownRenderer.blocksOf(content);
    final textStyle = TextStyle(
      fontSize: 13.5,
      height: 1.5,
      color: AppColors.inkSecondary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks.map((block) {
        if (block.paragraph != null) {
          final spans = MarkdownRenderer.inlineSpans(block.paragraph!, textStyle);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (block.isListItem)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 6, color: AppColors.inkMuted),
                  ),
                Expanded(
                  child: Text.rich(TextSpan(children: spans), style: textStyle),
                ),
              ],
            ),
          );
        } else if (block.code != null) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (block.code!.language.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceHover,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
                    ),
                    child: Text(
                      block.code!.language,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkFaint,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    block.code!.code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.inkPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }
}
