import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Global atmospheric canvas providing a subtle top-centered studio glow
/// over deep dark zinc background, adhering to Antigravity 2.0 aesthetics.
class ZenithalCanvas extends StatelessWidget {
  final Widget child;

  const ZenithalCanvas({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        child: child,
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceBase,
        gradient: AppGradients.zenithal,
      ),
      child: child,
    );
  }
}
