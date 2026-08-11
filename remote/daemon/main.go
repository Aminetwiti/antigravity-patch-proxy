package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	"github.com/antigravity/remote-daemon/pkg/discovery"
	"github.com/antigravity/remote-daemon/pkg/gateway"
)

func main() {
	fmt.Println("🚀 Starting Antigravity Remote Daemon Bridge...")

	info, err := discovery.Discover()
	if err != nil {
		log.Fatalf("❌ Failed to discover localharness process: %v", err)
	}

	fmt.Println("✅ LocalHarness Discovered:")
	fmt.Printf("   PID: %d\n", info.PID)
	fmt.Printf("   CSRF Token: %s...\n", info.CSRFToken[:10])
	fmt.Printf("   ConnectRPC Port: %d\n", info.ConnectRPCPort)

	rpcClient := connectrpc.NewClient(info.ConnectRPCPort, info.CSRFToken)
	server := gateway.NewServer(rpcClient)

	http.HandleFunc("/ws", server.HandleWebSocket)
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	})

	listenPort := 8089
	fmt.Printf("🌐 Daemon listening on ws://localhost:%d/ws\n", listenPort)
	if err := http.ListenAndServe(fmt.Sprintf(":%d", listenPort), nil); err != nil {
		log.Fatalf("❌ Server error: %v", err)
	}
}
