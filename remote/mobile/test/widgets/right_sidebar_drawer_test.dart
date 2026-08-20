import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/right_sidebar_drawer.dart';

void main() {
  testWidgets('RightSidebarDrawer renders context stats and navigates', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          endDrawer: RightSidebarDrawer(
            subagentsCount: 5,
            filesChangedCount: 3,
            artifactsCount: 2,
            backgroundTasksCount: 1,
            uploadsCount: 0,
          ),
          body: Center(child: Text('Home')),
        ),
      ),
    );

    // Open the drawer
    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
    scaffoldState.openEndDrawer();
    await tester.pumpAndSettle();

    // Verify stats are rendered
    expect(find.text('CONTEXTE'), findsOneWidget);
    expect(find.text('Subagents'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    
    expect(find.text('Scheduled Tasks'), findsOneWidget);
    expect(find.text('Background Tasks'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));

    expect(find.text('MCP Servers'), findsOneWidget);

    // Verify interaction
    await tester.tap(find.text('Subagents'));
    await tester.pumpAndSettle();
    // In unit test, this might just close the drawer or trigger navigation.
  });
}
