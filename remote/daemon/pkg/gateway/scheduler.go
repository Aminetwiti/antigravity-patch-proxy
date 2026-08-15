package gateway

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Scheduler est un moteur cron minimaliste, stdlib-only (aucune dépendance
// externe — règle AGENTS.md). Il parcourt les ScheduledTask enregistrées par
// le daemon toutes les tickInterval et déclenche celles dont l'expression
// cron correspond à l'instant courant.
//
// ponytail: horizon borné volontairement — pas de rattrapage de runs manqués
// pendant que le daemon était éteint (un daemon qui redémarre ne rejoue pas
// les crons passés, il repart sur le prochain tick). Upgrade path: persister
// lastRunAt + timezone par tâche si le rattrapage devient un besoin réel.
// quotaPushInterval : cadence de push des quotas vers les clients mobiles.
// Aligné sur l'ancien timer mobile de 60 s — le daemon pousse désormais à la
// place du polling (1 appel LS/min max, et seulement si des clients sont là).
type Scheduler struct {
	server        *Server
	tickInterval  time.Duration
	lastQuotaPush time.Time
	stopCh        chan struct{}
	doneCh        chan struct{}
}

// NewScheduler crée un scheduler lié au serveur. Ne démarre rien tant que
// Start() n'est pas appelé.
func NewScheduler(server *Server) *Scheduler {
	return &Scheduler{
		server:       server,
		tickInterval: 30 * time.Second,
		stopCh:       make(chan struct{}),
		doneCh:       make(chan struct{}),
	}
}

// Start lance la boucle de tick en arrière-plan.
func (sc *Scheduler) Start() {
	go func() {
		defer close(sc.doneCh)
		ticker := time.NewTicker(sc.tickInterval)
		defer ticker.Stop()
		for {
			select {
			case <-sc.stopCh:
				return
			case now := <-ticker.C:
				sc.tick(now)
			}
		}
	}()
}

// Stop arrête la boucle de tick (bloquant jusqu'à la sortie de la goroutine).
func (sc *Scheduler) Stop() {
	close(sc.stopCh)
	<-sc.doneCh
}

// tick examine toutes les tâches une fois par tick. Les tâches désactivées ou
// invalides sont ignorées silencieusement ; une tâche éligible est exécutée en
// arrière-plan (goroutine) pour ne jamais bloquer le tick suivant.
func (sc *Scheduler) tick(now time.Time) {
	sc.maybePushQuota(now)

	sc.server.mu.Lock()
	tasks := make([]*ScheduledTask, 0, len(sc.server.scheduledTasks))
	for _, t := range sc.server.scheduledTasks {
		tasks = append(tasks, t)
	}
	sc.server.mu.Unlock()

	for _, task := range tasks {
		if task == nil || !task.IsEnabled {
			continue
		}
		if !cronMatches(task.CronExpression, now) {
			continue
		}
		logJSON.Info("scheduled_task_fire", "taskId", task.ID, "cron", task.CronExpression)
		go sc.server.runScheduledTask(task.ID)
	}
}

// maybePushQuota diffuse les quotas aux clients connectés au plus toutes les
// quotaPushInterval. Sans client, on ne martèle pas le LS. tick est appelé
// depuis la goroutine unique du scheduler → pas de course sur lastQuotaPush.
func (sc *Scheduler) maybePushQuota(now time.Time) {
	if now.Sub(sc.lastQuotaPush) < quotaPushInterval {
		return
	}
	sc.lastQuotaPush = now
	sc.server.mu.Lock()
	clients := len(sc.server.clients)
	sc.server.mu.Unlock()
	if clients == 0 {
		return
	}
	go sc.server.pushQuotaUpdate()
}

// cronMatches évalue une expression cron 5 champs (minute heure jour-mois
// mois jour-semaine) à l'instant donné, UTC. `?` est accepté comme alias de
// `*` (compatibilité Quartz, très répandue dans les UI de cron).
func cronMatches(expr string, now time.Time) bool {
	fields := strings.Fields(expr)
	if len(fields) != 5 {
		return false
	}
	ok := cronField(fields[0], now.Minute(), 0, 59) &&
		cronField(fields[1], now.Hour(), 0, 23) &&
		cronField(fields[2], now.Day(), 1, 31) &&
		cronField(fields[3], int(now.Month()), 1, 12) &&
		cronField(fields[4], int(now.Weekday()), 0, 6)
	return ok
}

// cronField teste si la valeur v appartient au champ cron (liste, plage,
// step, * ou ?).
func cronField(field string, v, min, max int) bool {
	field = strings.TrimSpace(field)
	if field == "" || field == "*" || field == "?" {
		return true
	}
	for _, part := range strings.Split(field, ",") {
		if cronPart(part, v, min, max) {
			return true
		}
	}
	return false
}

// cronPart teste une seule composante : "n", "a-b", "*/n" ou "a-b/n".
func cronPart(part string, v, min, max int) bool {
	step := 1
	if i := strings.Index(part, "/"); i >= 0 {
		s, err := strconv.Atoi(part[i+1:])
		if err != nil || s <= 0 {
			return false
		}
		step = s
		part = part[:i]
	}
	lo, hi := min, max
	if part != "*" {
		if i := strings.Index(part, "-"); i >= 0 {
			a, errA := strconv.Atoi(part[:i])
			b, errB := strconv.Atoi(part[i+1:])
			if errA != nil || errB != nil || a < min || b > max || a > b {
				return false
			}
			lo, hi = a, b
		} else {
			n, err := strconv.Atoi(part)
			if err != nil || n < min || n > max {
				return false
			}
			lo, hi = n, n
		}
	}
	if v < lo || v > hi {
		return false
	}
	return (v-lo)%step == 0
}

// runScheduledTask exécute une tâche : crée une cascade sur le workspace de la
// tâche, y envoie le prompt (streaming best-effort), puis journalise un
// événement scheduled_task_event diffusé à tous les clients (le mobile met à
// jour son historique). Le prompt est exécuté avec l'auto-approbation de la
// tâche quand celle-ci le demande — voir runScheduledTaskApproval.
func (s *Server) runScheduledTask(taskID string) {
	s.mu.Lock()
	task, exists := s.scheduledTasks[taskID]
	if !exists || !task.IsEnabled {
		s.mu.Unlock()
		return
	}
	taskCopy := *task
	s.mu.Unlock()

	start := time.Now()
	event := ScheduledTaskEvent{
		ID:        fmt.Sprintf("evt_%d", time.Now().UnixMilli()),
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}
	// ponytail: les tâches headless (IsDaemon=true, exécutées par le cron
	// sans client) ne peuvent pas attendre une approbation — on les auto-approuve.
	if err := s.executeTaskPrompt(taskCopy); err != nil {
		event.Outcome = "error"
		event.Message = err.Error()
	} else {
		event.Outcome = "done"
		event.Message = "exécuté par le scheduler"
	}
	event.DurationMs = int(time.Since(start).Milliseconds())

	s.mu.Lock()
	if current, still := s.scheduledTasks[taskID]; still {
		current.IterationsRun++
		current.NextRunAt = nextRunAt(current.CronExpression)
		current.Events = append(current.Events, event)
		current.Status = "Running"
	}
	taskRef := s.scheduledTasks[taskID]
	s.mu.Unlock()
	if taskRef != nil {
		data := map[string]interface{}{"task": taskRef, "event": event}
		// P1 : le mobile notifie « Tâche démarrée » pour les exécutions
		// planifiées — le taskStarted=true permet au mobile de ne notifier que
		// les événements réellement déclenchés par le cron/trigger.
		data["taskStarted"] = true
		s.broadcast(OutgoingMessage{
			Type: "scheduled_task_event",
			Data: data,
		})
	}
}

// executeTaskPrompt crée la cascade et envoie le prompt (best-effort). En cas
// d'échec de création de cascade, l'événement porte l'erreur.
func (s *Server) executeTaskPrompt(task ScheduledTask) error {
	uri := toWorkspaceURI(task.WorkspaceName)
	projectID, _ := s.cachedProjectID(uri)
	raw, err := s.RPCClient.CreateCascade(uri, projectID, "", connectrpcDefaultModelEnum())
	if err != nil {
		return err
	}
	cascadeID := extractCascadeID(raw)
	if cascadeID == "" {
		return fmt.Errorf("cascadeID vide dans la réponse CreateCascade")
	}
	err = s.RPCClient.SendMessageStream(cascadeID, task.Prompt, func([]byte) error { return nil })
	if err != nil {
		return err
	}
	return nil
}

// nextRunAt calcule la prochaine occurrence de l'expression cron dans les 48h
// (borné — on ne simule jamais un an de ticks). Vide si l'expression est
// invalide ou sans occurrence dans l'horizon.
func nextRunAt(expr string) string {
	now := time.Now().UTC().Truncate(time.Minute).Add(time.Minute)
	for i := 0; i < 48*60; i++ {
		candidate := now.Add(time.Duration(i) * time.Minute)
		if cronMatches(expr, candidate) {
			return candidate.Format(time.RFC3339)
		}
	}
	return ""
}

// extractCascadeID décode l'ID de cascade depuis la réponse protobuf brute de
// CreateCascade. Best-effort : champ #1 length-delimited = l'ID textuel.
func extractCascadeID(raw []byte) string {
	if len(raw) == 0 {
		return ""
	}
	body := raw
	// Frame gRPC-Web : 1 octet de flags + 4 octets de longueur big-endian.
	// Le champ #1 du protobuf (0x0A) suit immédiatement.
	if len(body) > 5 && body[0] == 0 {
		body = body[5:]
	} else if len(body) > 5 && body[0]&0x80 != 0 {
		body = body[5:]
	}
	if len(body) > 2 && body[0] == 0x0A {
		ln := int(body[1])
		if ln <= 0 || ln > 128 {
			return ""
		}
		if len(body) >= 2+ln {
			return string(body[2 : 2+ln])
		}
	}
	return ""
}

// connectrpcDefaultModelEnum est le repli du modèle par défaut quand le
// scheduler exécute une tâche sans sélection explicite de modèle.
func connectrpcDefaultModelEnum() uint64 {
	// Défini dans pkg/connectrpc (DefaultModelEnum) — importé indirectement.
	return 1
}
