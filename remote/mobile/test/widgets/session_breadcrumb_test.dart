import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/messages.dart';
import 'package:mobile/widgets/session_breadcrumb.dart';

void main() {
  group('SessionBreadcrumb Widget Tests', () {
    testWidgets('renders project name and session title separated by slash', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SessionBreadcrumb(
              projectName: 'antigravity-add-model-main',
              sessionTitle: 'setting',
            ),
          ),
        ),
      );

      expect(find.text('antigravity-add-model-main'), findsOneWidget);
      expect(find.text('/'), findsOneWidget);
      expect(find.text('setting'), findsOneWidget);
    });

    testWidgets('renders only project name when sessionTitle is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SessionBreadcrumb(
              projectName: 'my-awesome-project',
              sessionTitle: '',
            ),
          ),
        ),
      );

      expect(find.text('my-awesome-project'), findsOneWidget);
      expect(find.text('/'), findsNothing);
    });

    testWidgets('triggers onSelectProject when tapped with multiple projects', (tester) async {
      bool projectTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionBreadcrumb(
              projectName: 'antigravity-add-model-main',
              sessionTitle: 'setting',
              projects: const [
                ProjectItem(id: 'p1', name: 'proj1', folderUri: 'file:///path1', path: '/path1'),
                ProjectItem(id: 'p2', name: 'proj2', folderUri: 'file:///path2', path: '/path2'),
              ],
              onSelectProject: () {
                projectTapped = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('antigravity-add-model-main'));
      await tester.pumpAndSettle();

      expect(projectTapped, isTrue);
    });

    testWidgets('triggers onSelectSession when session title is tapped', (tester) async {
      bool sessionTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionBreadcrumb(
              projectName: 'antigravity-add-model-main',
              sessionTitle: 'setting',
              onSelectSession: () {
                sessionTapped = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('setting'));
      await tester.pumpAndSettle();

      expect(sessionTapped, isTrue);
    });
  });
}
