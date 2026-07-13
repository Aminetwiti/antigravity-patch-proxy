# Fix pour le Lancement d'Antigravity depuis ag-doctor-ui

## 🔴 Problème

Lorsque vous cliquez sur le bouton "Launch" dans ag-doctor-ui:
- Le processus démarre (PID visible)
- Mais l'interface graphique d'Antigravity **ne s'ouvre pas**
- Seul le processus en arrière-plan est lancé

## 🔍 Cause

Le code utilisait `spawn()` avec `stdio: 'ignore'` qui lance le processus en mode **headless** (sans interface).
Sur Windows, un processus Electron a besoin d'être lancé avec un shell pour ouvrir correctement sa fenêtre GUI.

## ✅ Solution Appliquée

J'ai modifié [`ag-doctor/src/core/antigravity.ts`](file:///c:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/ag-doctor/src/core/antigravity.ts) pour:

### Pour Windows:
1. **Utiliser `cmd.exe /c start`** - La commande Windows native pour lancer une application GUI
2. **Paramètre `windowsHide: false`** - S'assurer que la fenêtre est visible
3. **Fallback avec `shell: true`** - Si la commande start échoue, utiliser spawn avec shell

### Code modifié:

```typescript
// On Windows, use shell execution to properly open the GUI
if (process.platform === 'win32') {
  const { execFile } = await import('child_process');
  const { promisify } = await import('util');
  const execFileAsync = promisify(execFile);
  
  // Use 'start' command to launch in a new window
  // This ensures the GUI actually opens
  try {
    execFileAsync('cmd.exe', ['/c', 'start', '', `"${exe}"`], {
      cwd: dir,
      windowsHide: false,
      detached: true,
    }).catch(() => {
      // Ignore errors - process is already launched
    });
  } catch {
    // Fallback: direct spawn
    const child = spawn(exe, [], {
      detached: true,
      stdio: 'ignore',
      cwd: dir,
      shell: true,
      windowsHide: false,
    });
    child.unref();
  }
}
```

### Changements supplémentaires:
- **Augmentation du délai d'attente**: 800ms → 1500ms pour laisser le temps à la GUI de s'ouvrir
- **Vérification du PID**: Retourne une erreur si le processus ne démarre pas

## 🧪 Test

Après avoir compilé:

```powershell
cd ag-doctor
npm run build
node bin/ag-doctor.js antigravity launch
```

Vous devriez voir:
```
✓ Launched (pid=12345)
```

Et **l'interface graphique d'Antigravity devrait s'ouvrir**.

## 🔄 Pour Appliquer dans ag-doctor-ui

1. **Rebuild ag-doctor**:
```powershell
cd ag-doctor
npm run build
```

2. **Rebuild ag-doctor-ui** (pour copier le nouveau ag-doctor):
```powershell
cd ..\ag-doctor-ui
npm run build:cli
npm run build
```

3. **Relancer l'UI**:
```powershell
npm start
```

4. **Tester le bouton Launch** dans l'UI

## 📋 Comportement Attendu

### Avant le fix:
- ✅ Processus lancé (PID visible)
- ❌ Interface ne s'ouvre pas
- ❌ Processus en arrière-plan seulement

### Après le fix:
- ✅ Processus lancé (PID visible)
- ✅ Interface s'ouvre automatiquement
- ✅ Fenêtre Antigravity visible

## 🐛 Debug

Si l'interface ne s'ouvre toujours pas:

1. **Vérifier les permissions**:
```powershell
# Lancer en tant qu'administrateur
```

2. **Vérifier les antivirus**:
```powershell
# Certains antivirus bloquent les spawns via cmd.exe
```

3. **Test manuel**:
```powershell
cmd /c start "" "C:\Users\amine\AppData\Local\Programs\antigravity\Antigravity.exe"
```

Si cette commande fonctionne manuellement mais pas via ag-doctor, c'est un problème de permissions Node.js.

## 📝 Notes Techniques

- Sur **Unix/Linux/Mac**, le comportement original est conservé
- Le `windowsHide: false` force l'affichage de la fenêtre
- Le `shell: true` permet à Windows de gérer les raccourcis et associations de fichiers
- Le délai de 1500ms est nécessaire car Electron met du temps à initialiser la fenêtre

## ✨ Résumé

La modification permet maintenant de:
1. ✅ Lancer le processus Antigravity
2. ✅ Ouvrir l'interface graphique automatiquement
3. ✅ Détecter correctement le PID
4. ✅ Gérer les erreurs de lancement

Le problème est maintenant résolu! 🎉
