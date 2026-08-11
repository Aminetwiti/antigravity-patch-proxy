package discovery

import (
	"log"
	"time"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
)

type Watchdog struct {
	Client    *connectrpc.Client
	Interval  time.Duration
	stopChan  chan struct{}
	discover  func() (*LocalHarnessInfo, error)
}

func NewWatchdog(client *connectrpc.Client, interval time.Duration) *Watchdog {
	if interval <= 0 {
		interval = 10 * time.Second
	}
	return &Watchdog{
		Client:    client,
		Interval:  interval,
		stopChan:  make(chan struct{}),
		discover:  Discover,
	}
}

func (w *Watchdog) Start() {
	ticker := time.NewTicker(w.Interval)
	go func() {
		for {
			select {
			case <-ticker.C:
				info, err := w.discover()
				if err != nil {
					log.Printf("[Watchdog] Avertissement découverte hub: %v", err)
					continue
				}
				if info.ConnectRPCPort != w.Client.Port || info.ExtensionCSRF != w.Client.CSRFToken {
					log.Printf("[Watchdog] Hub redémarré détecté ! Mise à jour du port (%d -> %d) et du jeton CSRF", w.Client.Port, info.ConnectRPCPort)
					w.Client.Port = info.ConnectRPCPort
					w.Client.CSRFToken = info.ExtensionCSRF
				}
			case <-w.stopChan:
				ticker.Stop()
				return
			}
		}
	}()
}

func (w *Watchdog) Stop() {
	close(w.stopChan)
}
