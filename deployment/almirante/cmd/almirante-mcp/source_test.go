package main

import (
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Dev-Simplex/almirante/internal/audit"
	"github.com/Dev-Simplex/almirante/internal/control"
	"github.com/Dev-Simplex/almirante/internal/fleet"
)

// Prova o modo REAL: controlSource (o que o MCP usa com ALMIRANTE_MOCK=0)
// falando HTTP com o dispatcher control de verdade (em mock interno).
func TestRealModeWiring(t *testing.T) {
	f, err := fleet.Load("../../fleet.json")
	if err != nil {
		t.Fatal(err)
	}
	cfg := control.Config{Mock: true, Fleet: f, ApprovalTTL: time.Hour}
	store := control.NewStore(t.TempDir())
	aud := audit.New(t.TempDir() + "/a.jsonl")
	h := control.NewServer(cfg, store, aud, "op:dev:operator").Handler()
	ts := httptest.NewServer(h)
	defer ts.Close()

	cs := newControlSource(ts.URL, "op")

	if st, err := cs.Status("tozi"); err != nil || st.VM != "tozi" {
		t.Fatalf("Status via control: %v / %+v", err, st)
	}
	m, err := cs.Migrations("tozi")
	if err != nil || !m.HasDestructive {
		t.Fatalf("Migrations via control deveria marcar destrutiva: %v / %+v", err, m)
	}
	r, err := cs.Propose("tozi", "")
	if err != nil {
		t.Fatalf("Propose via control: %v", err)
	}
	if r.RequestedBy != "dev" { // veio do token, nao do body
		t.Fatalf("requested_by deveria ser 'dev' (token), veio %q", r.RequestedBy)
	}
	if pend, err := cs.ListPending(); err != nil || len(pend) < 1 {
		t.Fatalf("ListPending via control: %v / %d", err, len(pend))
	}

	// freeze bloqueia propose; unfreeze libera
	if err := cs.Freeze("catatau", "manutencao"); err != nil {
		t.Fatalf("Freeze via control: %v", err)
	}
	if _, err := cs.Propose("catatau", ""); err == nil {
		t.Fatalf("Propose deveria falhar com catatau congelada")
	}
	if err := cs.Unfreeze("catatau"); err != nil {
		t.Fatalf("Unfreeze via control: %v", err)
	}
	if _, err := cs.Propose("catatau", ""); err != nil {
		t.Fatalf("Propose deveria voltar a funcionar apos unfreeze: %v", err)
	}

	// cancel de pendente
	if err := cs.Cancel(r.ID); err != nil {
		t.Fatalf("Cancel via control: %v", err)
	}
	if got, _ := cs.GetRequest(r.ID); got.Status != "rejected" {
		t.Fatalf("apos cancel, status deveria ser rejected, veio %q", got.Status)
	}

	t.Log("wiring MCP->control->mock OK: status, migrations destrutiva, propose (requested_by do token), list_pending, freeze/unfreeze, cancel")
}
