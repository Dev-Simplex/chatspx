// almirante-mcp — servidor MCP (lado do dev, stdio).
// SO le e SO propoe: nao existe tool que execute/aprove. O dev fala natural
// ("atualiza a tozi"); o LLM casa com a tool. Aprovar vive fora do LLM (control + humano).
// Fonte de dados: mock (ALMIRANTE_MOCK=1) ou control REST (modo real).
// As tools vivem em internal/mcptools (compartilhadas com o MCP HTTP do control).
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/Dev-Simplex/almirante/internal/fleet"
	"github.com/Dev-Simplex/almirante/internal/mcptools"
	"github.com/Dev-Simplex/almirante/internal/types"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

var (
	fl  *types.Fleet
	src mcptools.Source
)

// preenchidos pelo GoReleaser via -ldflags
var (
	version = "dev"
	commit  = ""
	date    = ""
)

func main() {
	f, err := fleet.Load(envOr("ALMIRANTE_FLEET_FILE", "fleet.json"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERRO carregando fleet:", err)
		os.Exit(1)
	}
	fl = f
	mockMode := envOr("ALMIRANTE_MOCK", "1") == "1"
	if mockMode {
		src = newMockSource(fl.GitHubRepo)
	} else {
		src = mcptools.NewControlSource(envOr("ALMIRANTE_CONTROL_URL", "http://127.0.0.1:4100"), os.Getenv("ALMIRANTE_DEV_TOKEN"))
	}

	s := mcp.NewServer(&mcp.Implementation{Name: "almirante", Version: version, Title: "Almirante — deploy da frota ChatSPX"}, nil)
	mcptools.Register(s, fl, src)
	fmt.Fprintf(os.Stderr, "almirante-mcp %s (commit %s, %s) pronto (mock=%v, %d VMs)\n", version, commit, date, mockMode, len(fl.VMs))
	if err := s.Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		fmt.Fprintln(os.Stderr, "almirante-mcp falhou:", err)
		os.Exit(1)
	}
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
func vmBranch(id string) string {
	if v, ok := fleet.FindVM(fl, id); ok {
		return v.Branch
	}
	return ""
}
