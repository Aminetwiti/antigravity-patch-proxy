# SDD ledger — plan: docs/superpowers/plans/2026-08-14-antigravity-remote-full-features-master-plan.md

NOTE (repo): `git rev-parse HEAD` échoue — le dépôt n'a aucun commit (arborescence vierge, `.git` sans HEAD). Les « commits » du plan sont donc des changements locaux sur disque ; le suivi se fait par fichiers, pas par SHAs git. Les scripts review-package basés sur git sont inutilisables → revues par lecture directe des fichiers.

- Task 1: complete (@ Mentions — mention_item.dart, mention_autocomplete_overlay.dart, chat_input_bar.dart, test OK) — antérieur à ce ledger, vérifié sur disque.
- Task 2: complete (upload_media pipeline — daemon_api.dart, websocket.go, chat_input_bar.dart, test OK) — antérieur, vérifié sur disque.
- Task 3: complete (Proceed/Feedback action bar — artifact_action_bar.dart, artifact_viewer_modal.dart, test OK) — antérieur, vérifié sur disque.
- Task 4: complete (code review comments — code_comment.dart, add_comment_dialog.dart, unified_diff_viewer.dart, test OK) — antérieur, vérifié sur disque.
- Task 5: complete (scheduled tasks — scheduled_task_item.dart, scheduled_tasks_screen.dart, daemon_api.dart, right_sidebar_drawer.dart, test OK) — antérieur, vérifié sur disque.
- Task 6: complete (MCP explorer — mcp_server_info.dart, mcp_explorer_screen.dart, daemon_api.refreshMcpServers, right_sidebar_drawer row, tests OK ; revue APPOVED) — 2026-08-14.
  - Task 6: minor (deferred): bandeau d'erreur utilise Colors.amber au lieu d'AppColors.warning (mcp_explorer_screen.dart) — à trier en revue finale.
  - Task 6: minor (deferred): pas d'affichage du compte dans l'AppBar (le compte est dans le corps, conforme brief) — observation, rien à corriger.
- Task 7: complete (GitWorktreeSelector + politique d'exécution — git_worktree_selector.dart, settings_screen.dart, tests OK ; revue APPROVED) — 2026-08-14.
  - Task 7: deviation acceptée: la politique d'exécution a été intégrée DANS la Card existante « POLITIQUES D'ADMINISTRATION D'ENTREPRISE » au lieu d'une nouvelle Card + _SectionTitle « EXÉCUTION DES OUTILS » (brief). Plus simple (moins de widgets), revue approuvée, comportement identique.
