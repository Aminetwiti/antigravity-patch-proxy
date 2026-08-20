# Task 6 Review Package — MCP Servers & Tools Registry Explorer

NOTE (repo): pas de commits git (`git rev-parse HEAD` échoue — dépôt vierge). Le « diff » est la lecture directe des fichiers listés ci-dessous, comparés au brief `task-6-brief.md` et au plan `docs/superpowers/plans/2026-08-14-antigravity-remote-full-features-master-plan.md` (Task 6, lignes 519-611).

## Fichiers dans le périmètre de la revue

- `remote/mobile/lib/features/mcp/models/mcp_server_info.dart` (nouveau)
- `remote/mobile/lib/features/mcp/mcp_explorer_screen.dart` (nouveau)
- `remote/mobile/lib/core/protocol/daemon_api.dart` (méthode `refreshMcpServers` ajoutée)
- `remote/mobile/lib/widgets/right_sidebar_drawer.dart` (ligne « MCP Servers »)
- `remote/mobile/test/features/mcp/mcp_explorer_test.dart` (nouveau)

## Base de référence

- Brief : `.superpowers/sdd/2026-08-14-antigravity-remote-full-features-master-plan/task-6-brief.md`
- Rapport implémenteur : `.superpowers/sdd/2026-08-14-antigravity-remote-full-features-master-plan/task-6-report.md`
- Plan : Task 6 (modèle `McpServerInfo`, constructeur `McpExplorerScreen(servers:)`, test exact avec `MCP Servers (1)` / `coolify` / `14 tools`)
- Global constraints du plan : UI conforme aux tokens Antigravity 2.0 (`AppColors`/`AppRadius`/`AppMotion`) ; aucune dépendance nouvelle ; pas de modification de l'enveloppe WebSocket v1 ; backward compat `fromJson` tolérant ; `right_sidebar_drawer.dart` continue de compiler.
