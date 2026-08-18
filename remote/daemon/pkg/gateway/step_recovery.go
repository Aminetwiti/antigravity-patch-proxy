package gateway

import (
	"sync"
	"time"
)

// BufferedEvent stocke une frame ou un delta émis avec son index séquentiel.
type BufferedEvent struct {
	StepIndex int64           `json:"stepIndex"`
	Timestamp time.Time       `json:"timestamp"`
	Message   OutgoingMessage `json:"message"`
}

// SessionStreamBuffer conserve un tampon circulaire des N derniers événements
// par session (cascadeId) pour permettre la reprise rapide lors d'une reconnexion mobile.
type SessionStreamBuffer struct {
	mu          sync.RWMutex
	maxCapacity int
	buffers     map[string][]*BufferedEvent
	seqCounters map[string]int64
}

// NewSessionStreamBuffer instancie un gestionnaire de buffer avec une capacité par défaut.
func NewSessionStreamBuffer(maxCapacity int) *SessionStreamBuffer {
	if maxCapacity <= 0 {
		maxCapacity = 100
	}
	return &SessionStreamBuffer{
		maxCapacity: maxCapacity,
		buffers:     make(map[string][]*BufferedEvent),
		seqCounters: make(map[string]int64),
	}
}

// RecordEvent ajoute un événement au buffer circulaire de la cascade et lui assigne un StepIndex.
func (b *SessionStreamBuffer) RecordEvent(cascadeID string, msg OutgoingMessage) int64 {
	if cascadeID == "" {
		return 0
	}
	b.mu.Lock()
	defer b.mu.Unlock()

	b.seqCounters[cascadeID]++
	stepIndex := b.seqCounters[cascadeID]

	ev := &BufferedEvent{
		StepIndex: stepIndex,
		Timestamp: time.Now(),
		Message:   msg,
	}

	buf := b.buffers[cascadeID]
	if len(buf) >= b.maxCapacity {
		// Éviction FIFO : retire le plus ancien
		buf = buf[1:]
	}
	buf = append(buf, ev)
	b.buffers[cascadeID] = buf

	return stepIndex
}

// GetEventsSince renvoie tous les événements d'une cascade dont le StepIndex est strictement supérieur à lastStepIndex.
func (b *SessionStreamBuffer) GetEventsSince(cascadeID string, lastStepIndex int64) ([]OutgoingMessage, int64) {
	b.mu.RLock()
	defer b.mu.RUnlock()

	currentSeq := b.seqCounters[cascadeID]
	buf, exists := b.buffers[cascadeID]
	if !exists || len(buf) == 0 {
		return nil, currentSeq
	}

	var missed []OutgoingMessage
	for _, ev := range buf {
		if ev.StepIndex > lastStepIndex {
			missed = append(missed, ev.Message)
		}
	}

	return missed, currentSeq
}

// ClearCascade purge les événements d'une session terminée.
func (b *SessionStreamBuffer) ClearCascade(cascadeID string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	delete(b.buffers, cascadeID)
	delete(b.seqCounters, cascadeID)
}

// LastStepIndex renvoie le dernier StepIndex enregistré pour une cascade.
func (b *SessionStreamBuffer) LastStepIndex(cascadeID string) int64 {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.seqCounters[cascadeID]
}

