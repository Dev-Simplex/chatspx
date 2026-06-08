package main

import (
	"context"
	"strings"
	"testing"

	"github.com/Dev-Simplex/almirante/internal/fleet"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func textOf(r *mcp.CallToolResult) string {
	var b strings.Builder
	for _, c := range r.Content {
		if t, ok := c.(*mcp.TextContent); ok {
			b.WriteString(t.Text)
		}
	}
	return b.String()
}

func TestMCPServer(t *testing.T) {
	f, err := fleet.Load("../../fleet.json")
	if err != nil {
		t.Fatalf("fleet: %v", err)
	}
	fl = f
	src = newMockSource(fl.GitHubRepo)

	ctx := context.Background()
	srv := mcp.NewServer(&mcp.Implementation{Name: "almirante", Version: "test"}, nil)
	registerTools(srv)

	st, ct := mcp.NewInMemoryTransports()
	if _, err := srv.Connect(ctx, st, nil); err != nil {
		t.Fatalf("server connect: %v", err)
	}
	cli := mcp.NewClient(&mcp.Implementation{Name: "selftest", Version: "0"}, nil)
	cs, err := cli.Connect(ctx, ct, nil)
	if err != nil {
		t.Fatalf("client connect: %v", err)
	}
	defer cs.Close()

	tools, err := cs.ListTools(ctx, nil)
	if err != nil {
		t.Fatalf("list tools: %v", err)
	}
	if len(tools.Tools) < 8 {
		t.Fatalf("esperava >=8 tools, veio %d", len(tools.Tools))
	}
	t.Logf("%d tools registradas", len(tools.Tools))

	call := func(name string, args any) *mcp.CallToolResult {
		r, err := cs.CallTool(ctx, &mcp.CallToolParams{Name: name, Arguments: args})
		if err != nil {
			t.Fatalf("call %s: %v", name, err)
		}
		return r
	}

	if r := call("almirante_fleet_status", map[string]any{}); !strings.Contains(textOf(r), "PRODUCAO") {
		t.Errorf("fleet_status sem PRODUCAO: %s", textOf(r))
	}
	if r := call("almirante_vm_status", map[string]any{"vm": "tozi"}); !strings.Contains(textOf(r), "TOZI") {
		t.Errorf("vm_status tozi inesperado: %s", textOf(r))
	}
	if r := call("almirante_migration_status", map[string]any{"vm": "tozi"}); !strings.Contains(textOf(r), "DESTRUTIVA") {
		t.Errorf("tozi deveria marcar DESTRUTIVA: %s", textOf(r))
	}
	if r := call("almirante_propose_deploy_vm", map[string]any{"vm": "tozi"}); !strings.Contains(textOf(r), "NAO aprovo") {
		t.Errorf("propose_deploy_vm deveria deixar claro que so enfileira: %s", textOf(r))
	}
	// VM inexistente: erro limpo
	if r := call("almirante_vm_status", map[string]any{"vm": "naoexiste"}); !r.IsError {
		t.Errorf("vm inexistente deveria ser erro")
	}
	t.Log("MCP server OK — tools respondem, destrutiva detectada, propose so enfileira")
}
