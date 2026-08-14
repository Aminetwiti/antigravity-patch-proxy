# Task 7 Brief — Git Worktree Switcher & Execution Policy Settings

Plan source: `docs/superpowers/plans/2026-08-14-antigravity-remote-full-features-master-plan.md` (Phase 6, Task 7).

## Objectif

Ajouter un sélecteur de worktree/branche Git (widget `GitWorktreeSelector`) et un sélecteur de politique d'exécution d'outils (`strict` / `request-review` / `always-proceed`) dans l'écran Réglages (`settings_screen.dart`). Réutiliser les tokens Antigravity 2.0 (`AppColors`/`AppRadius`/`AppMotion`) et les patterns `_SectionTitle` + `Card` déjà présents.

## Fichiers

- Créer : `remote/mobile/lib/features/workspace/git_worktree_selector.dart`
- Modifier : `remote/mobile/lib/features/settings/settings_screen.dart`
- Créer : `remote/mobile/test/features/workspace/git_worktree_selector_test.dart`

## Widget GitWorktreeSelector — copier tel quel (source de vérité du plan)

```dart
// remote/mobile/lib/features/workspace/git_worktree_selector.dart
import 'package:flutter/material.dart';

class GitWorktreeSelector extends StatelessWidget {
  final String currentBranch;
  final List<String> branches;
  final ValueChanged<String> onBranchSelected;

  const GitWorktreeSelector({
    super.key,
    required this.currentBranch,
    required this.branches,
    required this.onBranchSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Active Git Worktree / Branch', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ...branches.map((b) {
          final isSelected = b == currentBranch;
          return ListTile(
            leading: Icon(isSelected ? Icons.check_circle : Icons.alt_route, size: 20),
            title: Text(b),
            trailing: isSelected ? const Chip(label: Text('Active', style: TextStyle(fontSize: 11))) : null,
            onTap: () => onBranchSelected(b),
          );
        }),
      ],
    );
  }
}
```

Respecter ce code à la lettre (le test du plan le vérifie). Vous POUVEZ améliorer le style visuel (couleurs de la `ListTile` via `Theme.of(context)`, chip Active avec `AppColors.positive`/`AppRadius.pill`) tant que les textes exacts restent : « Active Git Worktree / Branch », le nom de la branche, « Active », et l'icône `check_circle`/`alt_route`. Ne pas renommer les champs.

## Test — recette exacte du plan

`remote/mobile/test/features/workspace/git_worktree_selector_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/workspace/git_worktree_selector.dart';

void main() {
  testWidgets('GitWorktreeSelector shows branches and switches worktree', (tester) async {
    String? selectedBranch;
    final branches = ['main', 'feature/remote-v2', 'fix/websocket-reconnect'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitWorktreeSelector(
            currentBranch: 'main',
            branches: branches,
            onBranchSelected: (b) => selectedBranch = b,
          ),
        ),
      ),
    );

    expect(find.text('main'), findsOneWidget);
    expect(find.text('feature/remote-v2'), findsOneWidget);

    await tester.tap(find.text('feature/remote-v2'));
    await tester.pumpAndSettle();

    expect(selectedBranch, equals('feature/remote-v2'));
  });
}
```

Compléter avec : un test « current branch marked Active » (`find.text('Active')` → findsOneWidget quand une seule branche est courante) et un test « empty branches → no crash » (branches `[]` → rendu sans erreur, `find.text('Active Git Worktree / Branch')` présent).

## SettingsScreen — politique d'exécution

Dans `remote/mobile/lib/features/settings/settings_screen.dart` :

1. **État** : ajouter un champ privé dans `_SettingsScreenState` :
   ```dart
   String _executionPolicy = 'request-review'; // strict | request-review | always-proceed
   ```
   Initialisé depuis `widget.initialSettings['executionPolicy'] as String? ?? 'request-review'` dans `initState` (copier le pattern de `_mcpAllowlistStrict` lignes 97-100).

2. **UI** — nouvelle `Card` dans le `ListView` (après la Card « POLITIQUES D'ADMINISTRATION D'ENTREPRISE », avant « PARAMÈTRES ET SUPPRESSION DU PROJET »), avec une section `_SectionTitle(title: 'EXÉCUTION DES OUTILS')` au-dessus (pattern lignes 370-372) :

   - Titre : `Text('Politique d'exécution des outils')` (13px, onSurface).
   - Sous-titre : `Text('Définit quand l'agent peut exécuter des commandes sur le workspace')` (11px, onSurfaceVariant).
   - `SegmentedButton<String>` (Material 3, déjà dispo dans la version Flutter du projet — vérifier avec les autres usages) avec 3 segments :
     - `strict` → label « Strict » + tooltip « Chaque commande exige approbation »
     - `request-review` → label « Révision » + tooltip « Approbation pour commandes sensibles »
     - `always-proceed` → label « Auto » + tooltip « Exécution automatique sans approbation »
   - `onSelectionChanged`: `setState` + `SettingsStore.save({'executionPolicy': val.first})` (pattern lignes 392-395).
   - Si `SegmentedButton` pose problème de thème, repli : `DropdownButtonFormField<String>` (pattern existant lignes 590-603) avec les 3 valeurs. Choisir UNE implémentation ; la plus simple qui compile.

3. **GitWorktreeSelector** — dans la même nouvelle Card, sous le sélecteur de politique, un `Divider()` puis `GitWorktreeSelector` :
   - `currentBranch: 'main'` (pas d'API daemon pour ça dans le brief — valeur statique, voir note ci-dessous)
   - `branches: const ['main', 'feature/remote-v2', 'fix/websocket-reconnect']` (liste statique de démo)
   - `onBranchSelected: (b) => setState(() {})` + `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Branche active : $b')))`

   > **Note (acceptée)** : le daemon expose `listGitBranches`/`listGitWorktrees` dans `daemon_api.dart`, mais l'écran Réglages ne charge pas de workspace et le plan ne fournit pas de flux de données pour ça. Les listes statiques sont le comportement attendu par le plan (« Consumes: Worktrees/branches list + Tool execution policy state » — le daemon reste hors périmètre). NE PAS appeler `listGitBranches` depuis SettingsScreen : pas de workspace fiable, exception au runtime. Marquer d'un commentaire `ponytail:` expliquant le plafond (liste statique → futur branchement daemon).

4. **Imports** : ajouter `import '../workspace/git_worktree_selector.dart';` (vérifier le chemin réel depuis `lib/features/settings/`).

## Contraintes globales

- UI conforme aux tokens Antigravity 2.0 (`AppColors`, `AppRadius`, `AppMotion`).
- Aucune dépendance nouvelle. Aucune modification du daemon Go (hors périmètre).
- Backward compat : `initialSettings` sans `executionPolicy` → défaut `'request-review'`.
- NE PAS casser les tests existants de SettingsScreen s'il y en a ; au minimum `flutter test` sur le nouveau fichier + `flutter analyze`.

## Vérification

- `flutter test test/features/workspace/git_worktree_selector_test.dart` → PASS
- `flutter analyze` (ou `flutter test` complet) sans nouvelle erreur.
