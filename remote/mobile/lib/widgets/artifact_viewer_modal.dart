import 'package:flutter/material.dart';
import '../core/protocol/daemon_api.dart';
import '../core/protocol/markdown_renderer.dart';
import '../features/artifacts/artifact_action_bar.dart';

class ArtifactViewerModal extends StatefulWidget {
  final DaemonApi api;
  final String artifactPath;
  final String artifactName;
  final String? workspacePath;
  final bool requestFeedback;
  final VoidCallback? onProceed;
  final VoidCallback? onRequestFeedback;

  const ArtifactViewerModal({
    super.key,
    required this.api,
    required this.artifactPath,
    required this.artifactName,
    this.workspacePath,
    this.requestFeedback = false,
    this.onProceed,
    this.onRequestFeedback,
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
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
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  Icon(Icons.article_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.artifactName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: scheme.onSurfaceVariant),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(scheme.primary)))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              _error!,
                              style: TextStyle(color: scheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: _MarkdownBody(content: _content),
                        ),
            ),
            if (widget.requestFeedback)
              ArtifactActionBar(
                requestFeedback: widget.requestFeedback,
                onProceed: () => widget.onProceed?.call(),
                onRequestFeedback: () => widget.onRequestFeedback?.call(),
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
    final scheme = Theme.of(context).colorScheme;
    final blocks = MarkdownRenderer.blocksOf(content);
    final textStyle = TextStyle(
      fontSize: 13.5,
      height: 1.5,
      color: scheme.onSurface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks.map((block) {
        if (block.paragraph != null) {
          final spans = MarkdownRenderer.inlineSpans(block.paragraph!, textStyle, scheme: scheme);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (block.isListItem)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 6, color: scheme.onSurfaceVariant),
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
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (block.code!.language.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
                    ),
                    child: Text(
                      block.code!.language,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    block.code!.code,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurface,
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
