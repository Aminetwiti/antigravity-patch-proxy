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

// maskToken affiche un pr├®fixe du jeton sans paniquer sur les jetons courts.
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

	defaultPort := 8090
	if envPort := os.Getenv("AG_DAEMON_PORT"); envPort != "" {
		if p, err := strconv.Atoi(envPort); err == nil {
			defaultPort = p
		}
	}
	defaultHost := "0.0.0.0"
	if envHost := os.Getenv("AG_DAEMON_HOST"); envHost != "" {
		defaultHost = envHost
	}
	defaultAuthToken := os.Getenv("AG_DAEMON_AUTH_TOKEN")

	flag.IntVar(&listenPort, "port", defaultPort, "Port for the WebSocket server")
	flag.StringVar(&host, "host", defaultHost, "Host for the WebSocket server")
	flag.StringVar(&tunnelFlag, "tunnel", "", "Tunnel provider (ngrok, cloudflare, pinggy)")
	flag.StringVar(&authToken, "auth-token", defaultAuthToken, "Authentication token for Mobile App")
	flag.IntVar(&approvalTimeoutMin, "approval-timeout", 5, "Auto-deny timeout for pending approvals in minutes (0 = disabled)")
	flag.Parse()

	fmt.Printf("­ƒÜÇ Starting Antigravity Remote Daemon Bridge on %s:%d...\n", host, listenPort)
	if authToken != "" {
		fmt.Println("­ƒöÆ Authentication is ENABLED")
	}

	info, err := discovery.Discover()
	if err != nil {
		log.Fatalf("ÔØî Failed to discover localharness process: %v", err)
	}

	fmt.Println("Ô£à LocalHarness Discovered:")
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
	fmt.Println("­ƒøí´©Å Watchdog CSRF d├®marr├® (v├®rification toutes les 10s)")

	// Lancement asynchrone du Tunnel Distant (Cloudflare / Pinggy / Ngrok)
	tunnelMgr := tunnel.NewManager(tunnelFlag)
	go func() {
		if url, err := tunnelMgr.StartAutoTunnel(listenPort); err == nil {
			log.Printf("­ƒîÉ Tunnel public actif : %s", url)
		} else {
			log.Printf("ÔÜá´©Å Tunnel non d├®marr├® (acc├¿s local Wi-Fi disponible sur port %d) : %v", listenPort, err)
		}
	}()

	// Lancement du Beacon de D├®couverte Automatique LAN (Zero-Config UDP).
	// Aucun jeton n'y est pass├® : le beacon ne diffuse JAMAIS le token sur le
	// LAN (broadcast lisible par tout h├┤te) ÔÇö pairing par QR ou saisie manuelle.
	beacon := discovery.NewLANBeacon(
		listenPort,
		func() string { return tunnelMgr.PublicURL },
		gateway.GetUniqueWorkspaces,
	)
	if err := beacon.Start(); err == nil {
		fmt.Printf("­ƒôí Beacon LAN UDP actif sur le port %d (Zero-Config Auto-Discovery)\n", discovery.DiscoveryPort)
	}

	// C4 : branche le logger structur├® rotatif (AG_REMOTE_LOG_FILE) ou stdout
	// (AG_REMOTE_LOG_LEVEL) ÔÇö les logs du gateway partent en JSON exploitable.
	gateway.SetLogJSON(gateway.NewLogger())

	// P4 : Pairing PIN ├®ph├®m├¿re + anti-brute-force
	pairingMgr := discovery.NewPairingManager()
	pin, _ := pairingMgr.CurrentPIN()
	fmt.Printf("­ƒöæ Code PIN d'appairage mobile : %s (valable 60s ÔÇö saisissez ce code sur votre t├®l├®phone)\n", pin)

	server := gateway.NewServer(rpcClient, authToken)
	server.SetTokenValidator(pairingMgr.ValidateToken)
	// Variante enrichie (3.3) : le gateway r├®cup├¿re deviceId + allowedProjects
	// au handshake pour le filtrage par projet (send_prompt / list_sessions).
	server.SetSessionValidator(pairingMgr.ValidateSession)
	// 3.4 : branche le PairingManager pour list_devices / revoke_device
	// (gestion administrative des appareils pairÃ©s depuis le mobile admin).
	server.SetPairingManager(pairingMgr)
	server.SetApprovalTimeout(time.Duration(approvalTimeoutMin) * time.Minute)
	// Flux temps r├®el Jetbox : la sidebar mobile est aliment├®e par le stream
	// JetboxSubscribeToSummaries (snapshot initial + updates incr├®mentaux) au
	// lieu de GetAllCascades (~9,5 s). Reconnecte automatiquement en boucle.
	server.RunJetboxSubscription(rpcClient)
	// Flux r├®actif StreamReactiveUpdates : source secondaire de fiabilit├®
	// (approbations + d├®tection instantan├®e "waiting for input") — le parsing
	// des frames de r├®ponse reste le chemin principal. Goroutine autonome.
	server.RunReactiveSubscription(rpcClient)
	sched := gateway.NewScheduler(server)
	sched.Start()

	http.HandleFunc("/ws", server.HandleWebSocket)
	http.HandleFunc("/pair", pairingMgr.HTTPHandler())
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

	// Arr├¬t propre sur Ctrl+C / SIGTERM : ferme le tunnel (cloudflared/ssh) et le beacon.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		log.Println("­ƒøæ Arr├¬t du daemon, fermeture du tunnelÔÇª")
		tunnelMgr.Stop()
		beacon.Stop()
		watchdog.Stop()
		sched.Stop()
	}()

	fmt.Printf("­ƒîÉ Daemon listening on ws://%s:%d/ws\n", host, listenPort)
	if err := http.ListenAndServe(net.JoinHostPort(host, strconv.Itoa(listenPort)), nil); err != nil {
		log.Fatalf("ÔØî Server error: %v", err)
	}
}
