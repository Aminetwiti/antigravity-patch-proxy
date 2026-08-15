// lsprobe : diagnostic direct du Language Server (mêmes appels que le daemon).
// Usage : go run ./cmd/lsprobe [--port 50488] [--token <csrf>] [--cascade <id>]
// Sans --cascade : liste les sessions réelles puis envoie un prompt sur la première.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	"github.com/antigravity/remote-daemon/pkg/discovery"
)

func main() {
	port := flag.Int("port", 0, "Port RPC du Language Server (0 = découverte auto)")
	token := flag.String("token", "", "Jeton CSRF (vide = découverte auto)")
	cascade := flag.String("cascade", "", "cascadeId cible (vide = première session)")
	prompt := flag.String("prompt", "dis bonjour en un mot", "Prompt à envoyer")
	flag.Parse()

	var rpcPort int
	var csrf string
	if *port > 0 {
		rpcPort = *port
		csrf = *token
	} else {
		info, err := discovery.Discover()
		if err != nil {
			fmt.Printf("❌ discovery: %v\n", err)
			os.Exit(1)
		}
		rpcPort = info.ConnectRPCPort
		csrf = info.ExtensionCSRF
		fmt.Printf("✅ découverte : PID=%d port=%d subclient=%s\n", info.PID, rpcPort, info.SubclientType)
	}

	c := connectrpc.NewClient(rpcPort, csrf)
	// APIKey requise pour « untrusted workspace » ; on tente quand même.
	c.APIKey = "unused"

	// 1. Heartbeat
	if _, err := c.Heartbeat(); err != nil {
		fmt.Printf("❌ Heartbeat: %v\n", err)
	} else {
		fmt.Println("✅ Heartbeat OK")
	}

	// 2. Liste des sessions réelles
	raw, err := c.GetAllCascades()
	if err != nil {
		fmt.Printf("❌ GetAllCascadeTrajectories: %v\n", err)
		os.Exit(1)
	}
	summaries := connectrpc.ParseTrajectories(raw)
	fmt.Printf("📚 Sessions réelles : %d\n", len(summaries))
	for _, s := range summaries {
		fmt.Printf("   - %s | %s | %s\n", s.CascadeID, s.Title, s.Workspace)
	}

	cascadeID := *cascade
	if cascadeID == "" && len(summaries) > 0 {
		cascadeID = summaries[0].CascadeID
	}
	if cascadeID == "" {
		fmt.Println("⚠️ Aucune cascade réelle — rien à tester (créer une session dans l'IDE)")
		return
	}

	// 3. SendMessageStream sur la cascade réelle (avec modèle par défaut 190)
	fmt.Printf("🚀 SendMessageStream cascade=%s prompt=%q\n", cascadeID, *prompt)
	c.ModelEnum = 190
	frames := 0
	events := 0
	err = c.SendMessageStream(cascadeID, *prompt, func(frame []byte) error {
		frames++
		evs := connectrpc.ParseFrameEvents(frame, cascadeID)
		events += len(evs)
		for _, ev := range evs {
			txt := ev.Delta
			if len(txt) > 80 {
				txt = txt[:80] + "…"
			}
			fmt.Printf("   frame#%d kind=%s delta=%q tool=%s\n", frames, ev.Kind, txt, ev.Tool)
		}
		return nil
	})
	if err != nil {
		fmt.Printf("❌ SendMessageStream: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("✅ Terminé : frames=%d events=%d\n", frames, events)

	// 4. Diagnostic brut si aucune frame
	if frames == 0 {
		raw, err := c.SendMessage(cascadeID, *prompt)
		if err != nil {
			fmt.Printf("❌ SendMessage unary: %v\n", err)
		} else {
			fields := connectrpc.DecodeFields(raw)
			fmt.Printf("📦 Réponse unary brute : %d champs\n", len(fields))
			for _, f := range fields {
				if f.WireType == 0 {
					fmt.Printf("   #%d:%d=%d\n", f.Num, f.WireType, f.Varint)
				} else {
					s := string(f.Bytes)
					if len(s) > 60 {
						s = s[:60] + "…"
					}
					fmt.Printf("   #%d:%d=%dB text=%q\n", f.Num, f.WireType, len(f.Bytes), s)
				}
			}
		}
	}

	_ = json.Marshal
}
