# Task 6 Brief — MCP Servers & Tools Registry Explorer

Plan source: `docs/superpowers/plans/2026-08-14-antigravity-remote-full-features-master-plan.md` (Phase 5, Task 6).

## Objectif

Construire un écran Flutter qui liste les serveurs MCP configurés (côté PC) et leurs outils, en réutilisant l'API du daemon (`DaemonApi`) existante. L'écran doit respecter les tokens de design Antigravity 2.0 (« The Quiet Console », `AppColors`/`AppRadius`/`AppMotion`) et les conventions des écrans déjà intégrés (ex. `ScheduledTasksScreen`).

## Fichiers

- Créer : `remote/mobile/lib/features/mcp/models/mcp_server_info.dart`
- Créer : `remote/mobile/lib/features/mcp/mcp_explorer_screen.dart`
- Modifier : `remote/mobile/lib/widgets/right_sidebar_drawer.dart` (ajouter une ligne « MCP Servers » qui ouvre l'écran)
- Créer : `remote/mobile/test/features/mcp/mcp_explorer_test.dart`

## Interface (source de vérité pour les signatures)

Modèle — copier tel quel :

```dart
// remote/mobile/lib/features/mcp/models/mcp_server_info.dart
class McpServerInfo {
  final String name;
  final String status;
  final int toolCount;
  final List<String> tools;
  final String? description;

  const McpServerInfo({
    required this.name,
    required this.status,
    required this.toolCount,
    required this.tools,
    this.description,
  });

  factory McpServerInfo.fromJson(Map<String, dynamic> json) {
    final toolsList = (json['tools'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    return McpServerInfo(
      name: json['name'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'ready',
      toolCount: json['toolCount'] as int? ?? toolsList.length,
      tools: toolsList,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status,
        'toolCount': toolCount,
        'tools': tools,
        if (description != null) 'description': description,
      };
}
```

## Écran

`McpExplorerScreen` — StatefulWidget avec :

- `final DaemonApi? api;` (facultatif ; si null → mode statique, seules les `servers` passées en paramètre sont affichées)
- `final List<McpServerInfo> servers;` (liste initiale, peut être vide)
- Constructeur : `const McpExplorerScreen({super.key, this.api, this.servers = const []})`

Comportement :
1. **Chargement** : au `initState`, si `api != null`, appeler `api.refreshMcpServers()` (méthode à ajouter à `DaemonApi` — voir ci-dessous). En cas d'échec (exception, timeout), NE PAS planter : afficher un bandeau d'erreur discret avec bouton « Réessayer », et conserver les `servers` passées en paramètre.
2. **Affichage** : `Scaffold` + `AppBar(title: 'MCP Servers')`, corps `ListView` avec :
   - En-tête `Text('MCP Servers (N)')` (style `_SectionTitle` du pattern Settings, 11px, w700, letterSpacing 0.8, couleur `onSurfaceVariant`).
   - Une carte par serveur : `Card` avec `Padding(16)` ; Row : icône de statut (dans une pastille verte `AppColors.positive` si `status == 'ready'`, ambre `AppColors.warning` sinon), nom du serveur (13px, w600), badge `'N tools'` (ex. `'14 tools'`) en Chip/Container 11px. Sous le nom, `description` si présente (11px, `onSurfaceVariant`).
   - Expansion : tap sur la carte → `ExpansionTile`-like (ou gestion `setState` d'un index ouvert) révélant la liste des outils sous forme de `Wrap` de `Chip`s 12px. Seuls les outils de `tools` sont montrés.
   - État vide : si aucune liste (serveurs vide ET api null ou réponse vide) → `Text('Aucun serveur MCP configuré')` centré, style 12px `onSurfaceVariant`.
3. **Métriques** : le test exige `find.text('MCP Servers (1)')`, `find.text('coolify')`, `find.text('14 tools')`.

## DaemonApi — nouvelle méthode

Ajouter à `remote/mobile/lib/core/protocol/daemon_api.dart` (section MCP, à côté de `connectMcpServer`) :

```dart
/// Récupère la liste des serveurs MCP configurés côté PC (via le daemon).
Future<List<McpServerInfo>> refreshMcpServers() async {
  final res = await rpc('list_mcp_servers');
  final list = res['servers'] as List?;
  return (list ?? [])
      .whereType<Map>()
      .map((e) => McpServerInfo.fromJson(e.cast<String, dynamic>()))
      .toList();
}
```

Import requis dans `daemon_api.dart` : `import '../../features/mcp/models/mcp_server_info.dart';` (vérifier le chemin relatif réel depuis `lib/core/protocol/` → `../../features/mcp/models/mcp_server_info.dart`).

Le daemon Go relayera `list_mcp_servers` vers le proxy desktop (`POST http://127.0.0.1:50999/list_mcp_servers`) via le même chemin `handleMcpAction` que `call_mcp_tool` — ne pas dupliquer de logique d'appel HTTP dans le mobile.

## RightSidebarDrawer

Dans `remote/mobile/lib/widgets/right_sidebar_drawer.dart`, après la ligne « Scheduled Tasks » (et avant « Background Tasks »), ajouter un `_ContextItemRow` :

- `title: 'MCP Servers'`
- `badgeCount: 0` (le drawer ne reçoit pas le compte ; garder 0 — le badge affiche « 0 »)
- `onTap:` → `Navigator.of(context).push(MaterialPageRoute(builder: (_) => McpExplorerScreen(api: widget.api)))`

Imports à ajouter : `import '../features/mcp/mcp_explorer_screen.dart';`

## Test (recette exacte du plan)

`remote/mobile/test/features/mcp/mcp_explorer_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/mcp/models/mcp_server_info.dart';
import 'package:mobile/features/mcp/mcp_explorer_screen.dart';

void main() {
  testWidgets('McpExplorerScreen displays servers and tools count', (tester) async {
    final servers = [
      McpServerInfo(
        name: 'coolify',
        status: 'ready',
        toolCount: 14,
        tools: ['list_servers', 'deploy_application', 'get_logs'],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: McpExplorerScreen(servers: servers),
      ),
    );

    expect(find.text('MCP Servers (1)'), findsOneWidget);
    expect(find.text('coolify'), findsOneWidget);
    expect(find.text('14 tools'), findsOneWidget);
  });
}
```

Compléter avec au moins un test supplémentaire : état vide (`MCP Servers (0)` + « Aucun serveur MCP configuré ») et un test `fromJson` (champs par défaut quand `tools` absent → `toolCount == 0`).

## Contraintes globales du plan

- UI conforme aux tokens Antigravity 2.0 (`AppColors`, `AppRadius`, `AppMotion`).
- Aucune dépendance nouvelle. Aucune modification de l'enveloppe WebSocket v1.
- Ne pas casser les écrans existants ; `right_sidebar_drawer.dart` continue de compiler.
- Backward compat : `fromJson` doit tolérer les clés manquantes (déjà le cas ci-dessus).

## Vérification

- `flutter test test/features/mcp/mcp_explorer_test.dart` → PASS
- `flutter analyze` (ou au minimum `flutter test` complet) sans nouvelle erreur.
