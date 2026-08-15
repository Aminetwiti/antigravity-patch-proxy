package gateway

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// scheduledTasksPath : chemin du fichier JSON de persistance des tâches
// planifiées. Variable pour testabilité (les tests pointent vers t.TempDir()).
var scheduledTasksPath = func() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "scheduled_tasks.json"
	}
	return filepath.Join(home, ".gemini", "antigravity-remote", "scheduled_tasks.json")
}()

// SaveScheduledTasks écrit l'état courant des tâches planifiées sur disque.
// ponytail: écriture synchrone volontaire (mutation rare, pas en hot path) ;
// upgrade = écriture atomique + fsync si les tâches deviennent fréquentes.
func (s *Server) SaveScheduledTasks() error {
	s.mu.Lock()
	tasks := make([]*ScheduledTask, 0, len(s.scheduledTasks))
	for _, t := range s.scheduledTasks {
		tasks = append(tasks, t)
	}
	s.mu.Unlock()

	data, err := json.MarshalIndent(tasks, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(scheduledTasksPath), 0755); err != nil {
		return err
	}
	return os.WriteFile(scheduledTasksPath, data, 0600)
}

// LoadScheduledTasks relit les tâches planifiées depuis le disque au démarrage.
// Un fichier absent ou corrompu n'est pas fatal : on repart avec une liste vide.
func (s *Server) LoadScheduledTasks() error {
	data, err := os.ReadFile(scheduledTasksPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // pas encore de persistance — liste vide, pas une erreur
		}
		return err
	}
	var tasks []*ScheduledTask
	if err := json.Unmarshal(data, &tasks); err != nil {
		return err // fichier corrompu → liste vide, on ne crash pas
	}
	s.mu.Lock()
	for _, t := range tasks {
		if t == nil || t.ID == "" {
			continue
		}
		if s.scheduledTasks[t.ID] == nil {
			s.scheduledTasks[t.ID] = t
		}
	}
	s.mu.Unlock()
	return nil
}
