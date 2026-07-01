package main

import (
	"fmt"
	"sort"
	"strings"
	"sync"

	"github.com/Dev-Simplex/almirante/internal/merge"
	"github.com/Dev-Simplex/almirante/internal/mock"
	"github.com/Dev-Simplex/almirante/internal/types"
)

// mockSource: fonte standalone (ALMIRANTE_MOCK=1) para o dev brincar sem control.
// Implementa mcptools.Source. A fonte real (REST) vive em internal/mcptools.ControlSource.

type mockSource struct {
	repo   string
	mu     sync.Mutex
	seq    int
	reqs   map[string]types.DeployRequest
	frozen map[string]string // scope -> message
}

func newMockSource(repo string) *mockSource {
	return &mockSource{repo: repo, seq: 411, reqs: map[string]types.DeployRequest{}, frozen: map[string]string{}}
}

func (m *mockSource) Status(vm string) (types.HostStatus, error) {
	return mock.HostStatus(vm, vmBranch(vm)), nil
}
func (m *mockSource) Health(vm string) (types.HealthReport, error)        { return mock.Health(vm), nil }
func (m *mockSource) Migrations(vm string) (types.MigrationStatus, error) { return mock.MigrationStatus(vm), nil }
func (m *mockSource) Diff(vm string) (types.GitDiff, error)               { return mock.GitDiff(vm, m.repo), nil }
func (m *mockSource) History(vm string) ([]types.DeployHistoryEntry, error) {
	return mock.History(vm), nil
}
func (m *mockSource) Propose(vm, branch string) (types.DeployRequest, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if msg, ok := m.frozen[vm]; ok {
		return types.DeployRequest{}, fmt.Errorf("VM congelada: %s", msg)
	}
	if msg, ok := m.frozen["all"]; ok {
		return types.DeployRequest{}, fmt.Errorf("frota congelada: %s", msg)
	}
	m.seq++
	mig := mock.MigrationStatus(vm)
	d := mock.GitDiff(vm, m.repo)
	r := types.DeployRequest{
		ID: fmt.Sprintf("req_%d", m.seq), VM: vm, Branch: branch, TargetSHA: d.TargetSHA, CurrentSHA: d.CurrentSHA,
		RequestedBy: "claude-code", Status: types.StatusPending, Migrations: mig.Pending, HasDestructive: mig.HasDestructive,
	}
	m.reqs[r.ID] = r
	return r, nil
}
func (m *mockSource) ListPending() ([]types.DeployRequest, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []types.DeployRequest
	for _, r := range m.reqs {
		if r.Status == types.StatusPending {
			out = append(out, r)
		}
	}
	return out, nil
}
func (m *mockSource) GetRequest(id string) (types.DeployRequest, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if r, ok := m.reqs[id]; ok {
		return r, nil
	}
	return types.DeployRequest{}, fmt.Errorf("pedido %s nao encontrado", id)
}
func (m *mockSource) Freeze(scope, message string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.frozen[scope] = message
	return nil
}
func (m *mockSource) Unfreeze(scope string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.frozen[scope]; !ok {
		return fmt.Errorf("%s nao estava congelado", scope)
	}
	delete(m.frozen, scope)
	return nil
}
func (m *mockSource) Frozen() (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.frozen) == 0 {
		return "Nada congelado.", nil
	}
	keys := make([]string, 0, len(m.frozen))
	for k := range m.frozen {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	b.WriteString("Congelados:\n")
	for _, k := range keys {
		fmt.Fprintf(&b, "• %s — %s\n", k, m.frozen[k])
	}
	return b.String(), nil
}
func (m *mockSource) Cancel(id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.reqs[id]
	if !ok {
		return fmt.Errorf("pedido %s nao encontrado", id)
	}
	if r.Status != types.StatusPending {
		return fmt.Errorf("pedido %s ja esta %s (so cancela pendente)", id, r.Status)
	}
	r.Status = types.StatusRejected
	m.reqs[id] = r
	return nil
}
func (m *mockSource) ProposeMerge(from, to string) (string, error) {
	if !merge.IsAllowed(from, to) {
		return "", fmt.Errorf("merge %s -> %s nao permitido (fluxos: %s)", from, to, strings.Join(merge.Flows(), ", "))
	}
	return fmt.Sprintf("[mock] merge %s -> %s enfileirado, aguardando aprovacao humana.", from, to), nil
}

// ---- Governanca de IA (mock — respostas deterministicas p/ demo) ----
func (m *mockSource) AIListAgents() (any, error) {
	return map[string]any{"vms": []map[string]any{{"id": "tozi", "name": "Clara Tozi", "env": "producao", "account_id": 6}}}, nil
}
func (m *mockSource) AIBaseline(vm string, id int) (any, error) {
	return map[string]any{"vm": vm, "assistant_id": id, "config": map[string]any{"instructions": "[mock] prompt do agente", "tools": []string{}}, "faqs": []any{}}, nil
}
func (m *mockSource) AICustomTools(vm string) (any, error) {
	return map[string]any{"custom_tools": []any{}}, nil
}
func (m *mockSource) AIHistory(vm string) (any, error) {
	return map[string]any{"change_sets": []any{}}, nil
}
func (m *mockSource) AIPrompt(vm string, id int, instructions, targetEnv string) (any, error) {
	return map[string]any{"status": "applied", "change_set_id": "cs_mock", "op": "update_instructions", "vm": vm, "assistant_id": id}, nil
}
func (m *mockSource) AITool(vm string, id int, toolID string, armed bool) (any, error) {
	return map[string]any{"status": "applied", "change_set_id": "cs_mock", "tool_id": toolID, "armed": armed}, nil
}
func (m *mockSource) AICredential(vm, provider string, settings map[string]any, enabled bool) (any, error) {
	return map[string]any{"status": "applied", "change_set_id": "cs_mock", "provider": provider}, nil
}
func (m *mockSource) AIBehavior(vm string, id int, behavior map[string]any) (any, error) {
	return map[string]any{"status": "applied", "change_set_id": "cs_mock"}, nil
}
func (m *mockSource) AIFaq(vm string, id int, question, answer string) (any, error) {
	return map[string]any{"status": "applied", "change_set_id": "cs_mock"}, nil
}
func (m *mockSource) AIEligibility(vm string, id int, inboxIDs []int) (any, error) {
	return map[string]any{"status": "applied", "change_set_id": "cs_mock"}, nil
}
func (m *mockSource) AIRollback(vm, changeSetID string) (any, error) {
	return map[string]any{"status": "reverted", "change_set_id": changeSetID}, nil
}
