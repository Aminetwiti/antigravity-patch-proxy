package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	"github.com/antigravity/remote-daemon/pkg/discovery"
	"github.com/antigravity/remote-daemon/pkg/gateway"
	"github.com/antigravity/remote-daemon/pkg/tunnel"
)

// maskToken affiche un préfixe du jeton sans paniquer sur les jetons courts.
func maskToken(token string) string {
	if len(token) > 10 {
		return token[:10]
	}
	return token
}

func main() {
	var listenPort int
	var host string
	var tunnelFlag string
	var authToken string
	var approvalTimeoutMin int

	flag.IntVar(&listenPort, "port", 8090, "Port for the WebSocket server")
	flag.StringVar(&host, "host", "0.0.0.0", "Host for the WebSocket server")
	flag.StringVar(&tunnelFlag, "tunnel", "", "Tunnel provider (ngrok, cloudflare, pinggy)")
	flag.StringVar(&authToken, "auth-token", "", "Authentication token for Mobile App")
	flag.IntVar(&approvalTimeoutMin, "approval-timeout", 5, "Auto-deny timeout for pending approvals in minutes (0 = disabled)")
	flag.Parse()

	fmt.Printf("🚀 Starting Antigravity Remote Daemon Bridge on %s:%d...\n", host, listenPort)
	if authToken != "" {
		fmt.Println("🔒 Authentication is ENABLED")
	}

	info, err := discovery.Discover()
	if err != nil {
		log.Fatalf("❌ Failed to discover localharness process: %v", err)
	}

	fmt.Println("✅ LocalHarness Discovered:")
	fmt.Printf("   PID: %d\n", info.PID)
	token := info.ExtensionCSRF
	if token == "" {
		token = info.CSRFToken
	}
	fmt.Printf("   CSRF Token: %s...\n", maskToken(token))

	rpcClient := connectrpc.NewClient(info.ConnectRPCPort, token)

	// Lancement du Watchdog CSRF
	watchdog := discovery.NewWatchdog(rpcClient, 10*time.Second)
	watchdog.Start()
	fmt.Println("🛡️ Watchdog CSRF démarré (vérification toutes les 10s)")

	// Lancement asynchrone du Tunnel Distant (Cloudflare / Pinggy / Ngrok)
	tunnelMgr := tunnel.NewManager(tunnelFlag)
	go func() {
		if url, err := tunnelMgr.StartAutoTunnel(listenPort); err == nil {
			log.Printf("🌐 Tunnel public actif : %s", url)
		} else {
			log.Printf("⚠️ Tunnel non démarré (accès local Wi-Fi disponible sur port %d) : %v", listenPort, err)
		}
	}()

	// Lancement du Beacon de Découverte Automatique LAN (Zero-Config UDP)
	beacon := discovery.NewLANBeacon(
		listenPort,
		authToken,
		func() string { return tunnelMgr.PublicURL },
		gateway.GetUniqueWorkspaces,
	)
	if err := beacon.Start(); err == nil {
		fmt.Printf("📡 Beacon LAN UDP actif sur le port %d (Zero-Config Auto-Discovery)\n", discovery.DiscoveryPort)
	}

	// C4 : branche le logger structuré rotatif (AG_REMOTE_LOG_FILE) ou stdout
	// (AG_REMOTE_LOG_LEVEL) — les logs du gateway partent en JSON exploitable.
	gateway.SetLogJSON(gateway.NewLogger())

	server := gateway.NewServer(rpcClient, authToken)
	server.SetApprovalTimeout(time.Duration(approvalTimeoutMin) * time.Minute)

	http.HandleFunc("/ws", server.HandleWebSocket)
	http.HandleFunc("/health", server.HTTPHandler)
	http.HandleFunc("/health/diagnostic", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		hbErr := ""
		if _, err := rpcClient.Heartbeat(); err != nil {
			hbErr = err.Error()
		}
		status := "ok"
		if hbErr != "" {
			status = "degraded"
		}
		w.WriteHeader(http.StatusOK)
		port, _ := rpcClient.Endpoint()
		fmt.Fprintf(w, `{"status":"%s","rpcPort":%d,"pid":%d,"heartbeatOk":%t,"tunnelProvider":"%s","publicUrl":"%s","error":"%s"}`, status, port, info.PID, hbErr == "", tunnelMgr.Provider, tunnelMgr.PublicURL, hbErr)
	})

	// Arrêt propre sur Ctrl+C / SIGTERM : ferme le tunnel (cloudflared/ssh) et le beacon.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		log.Println("🛑 Arrêt du daemon, fermeture du tunnel…")
		tunnelMgr.Stop()
		beacon.Stop()
		watchdog.Stop()
	}()

	fmt.Printf("🌐 Daemon listening on ws://%s:%d/ws\n", host, listenPort)
	if err := http.ListenAndServe(net.JoinHostPort(host, strconv.Itoa(listenPort)), nil); err != nil {
		log.Fatalf("❌ Server error: %v", err)
	}
}
