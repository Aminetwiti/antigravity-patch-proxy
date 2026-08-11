# Objectif — Antigravity Remote Control OS

## La Vision

Construire un **système de contrôle total à distance** pour Google Antigravity 2.0 qui dépasse radicalement ce qui existe dans la communauté open-source.

Aujourd'hui, 5 projets communautaires permettent de "voir" Antigravity depuis un smartphone. **Aucun ne permet de le piloter.**

---

## Le Problème

Antigravity 2.0 est un environnement d'agents autonomes. Ces agents exécutent des tâches de longue durée (refactoring, tests, migrations) mais se bloquent régulièrement pour demander une validation humaine (`ask_user`). Le développeur est **enchaîné à son écran de bureau** pour débloquer ses agents.

Les 5 solutions communautaires existantes tentent de résoudre ce problème, mais elles partagent toutes la même faiblesse architecturale :

| Outil | Méthode | Limite Fondamentale |
|:---|:---|:---|
| AntiBridge | CDP + Puppeteer | Simule des clics sur l'interface → casse à chaque mise à jour CSS |
| OmniAntigravityRemoteChat | CDP + WebSocket | Miroir visuel du DOM → lourd en bande passante, fragile |
| antigravity-ide-mobile | SQLite (state.vscdb) | Lecture seule → ne peut pas envoyer de commandes |
| antigravity-telegram-suite | CDP + Telegram Bot | Simule des frappes clavier → bugs de double-soumission |
| antigravity_phone_chat | CDP + PWA | Même fragilité DOM que les autres |

**Tous passent par le CDP (Chrome DevTools Protocol)** — ils automatisent l'interface graphique comme un robot qui appuie sur des boutons. C'est du bricolage.

---

## La Solution

Passer du **CDP (scraping d'écran)** au **ConnectRPC (communication directe avec le moteur Go)**. 

Au lieu de simuler des clics sur l'interface Electron, notre système parlera directement au binaire `localharness` — le vrai cerveau d'Antigravity — via son protocole natif ConnectRPC (gRPC-Web).

```
Ce que fait la communauté :            Ce que NOUS faisons :

  Smartphone                             Smartphone
      │                                      │
      ▼                                      ▼
  CDP / DOM Scraping                    WebSocket / Protobuf
      │                                      │
      ▼                                      ▼
  Interface Electron (UI)               Daemon Bridge (Go)
      │                                      │
      ▼                                      ▼
  localharness (Go)                     localharness (Go)
  
  → On passe par l'interface             → On parle directement au moteur
  → Fragile, lent, limité               → Stable, rapide, contrôle total
```

---

## Ce que "Contrôle Total" signifie concrètement

### Ce qu'on peut FAIRE (et que personne d'autre ne fait) :

1. **Créer des sessions à distance** — Instancier une nouvelle Cascade sur n'importe quel workspace depuis le téléphone
2. **Gérer les workspaces** — Basculer d'un projet à un autre, naviguer dans l'arborescence des fichiers
3. **Envoyer des prompts** — Donner des instructions à l'agent directement via RPC (pas en simulant le clavier)
4. **Approuver les outils via RPC** — Valider ou refuser les commandes `run_command` par une vraie requête `SubmitToolApproval` (pas un clic automatique)
5. **Visualiser les diffs de code** — Voir exactement ce que l'agent a modifié dans les fichiers
6. **Superviser les multi-agents** — Suivre simultanément le Planning Agent, l'Execution Agent et le Review Agent
7. **Recevoir des notifications push système** — Être alerté instantanément quand un agent attend une validation
8. **Travailler hors-ligne** — Consulter l'historique et l'état des projets même sans réseau (Offline-First)

### Ce que ça change pour le développeur :

- **Avant :** Bloqué devant son écran de bureau pour valider les demandes des agents
- **Après :** Valide depuis n'importe où (transports, terrasse, réunion) en 1 tap sur le téléphone

---

## Les Choix Techniques Fondamentaux

| Composant | Choix | Justification |
|:---|:---|:---|
| **Daemon Bridge (PC)** | **Go** | Même langage que le `localharness`, binaire unique sans dépendances, ultra-léger |
| **Client Mobile** | **APK Android natif** (Kotlin + Jetpack Compose) | Notifications FCM, service arrière-plan, Room DB, 120Hz, vrai contrôle système |
| **Protocole de transport** | **WebSocket + Protobuf** | Typage strict, deltas binaires ultra-légers, streaming temps réel |
| **Stockage local mobile** | **Room / SQLite** | Mode hors-ligne natif, synchronisation au retour du réseau |
| **Accès réseau distant** | **Cloudflare Tunnel / Tailscale** | Zero Trust, pas de port ouvert sur le routeur |

---

## Le Principe Directeur

> **Ne pas coder l'APK Android en premier.**
> 
> D'abord prouver que la connexion au `localharness` fonctionne avec un simple script CLI.
> Ensuite construire le Daemon Go par-dessus.
> Et seulement alors construire l'APK Android.
>
> Chaque marche doit fonctionner à 100% avant de monter à la suivante.
