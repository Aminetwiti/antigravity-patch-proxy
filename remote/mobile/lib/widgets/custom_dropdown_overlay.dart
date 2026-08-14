import 'package:flutter/material.dart';

class CustomDropdownOverlay {
  static OverlayEntry? _currentOverlay;

  static void show({
    required BuildContext context,
    required GlobalKey targetKey,
    required Widget child,
    double? width,
    double? maxHeight,
    bool alignRight = false,
  }) {
    hide();
    
    final RenderBox renderBox = targetKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _currentOverlay = OverlayEntry(
      builder: (context) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        final screenWidth = MediaQuery.sizeOf(context).width;
        
        double top = offset.dy + size.height + 8;
        double bottom = 0.0;
        bool showAbove = top + (maxHeight ?? 300) > screenHeight;
        
        if (showAbove) {
          top = -1; // disabled
          bottom = screenHeight - offset.dy + 8;
        }

        double left = alignRight ? -1 : offset.dx;
        double right = alignRight ? (screenWidth - offset.dx - size.width) : -1;

        return Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: hide,
              child: Container(
                color: Colors.transparent,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Positioned(
              top: showAbove ? null : top,
              bottom: showAbove ? bottom : null,
              left: alignRight ? null : left,
              right: alignRight ? right : null,
              width: width ?? size.width,
              child: Material(
                color: Colors.transparent,
                child: Builder(builder: (context) {
                  final scheme = Theme.of(context).colorScheme;
                  return Container(
                    constraints: BoxConstraints(maxHeight: maxHeight ?? 300),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: scheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: child,
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_currentOverlay!);
  }

  static void hide() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }
}
