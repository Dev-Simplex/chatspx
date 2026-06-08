package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/Dev-Simplex/almirante/internal/merge"
	"github.com/Dev-Simplex/almirante/internal/mock"
	"github.com/Dev-Simplex/almirante/internal/types"
)

// source: de onde o MCP le/propoe/gerencia. mock (standalone) ou control (REST real).
type source interface {
	Status(vm string) (types.HostStatus, error)
	Health(vm string) (types.HealthReport, error)
	Migrations(vm string) (types.MigrationStatus, error)
	Diff(vm string) (types.GitDiff, error)
	History(vm string) ([]types.DeployHistoryEntry, error)
	Propose(vm, branch string) (types.DeployRequest, error)
	ListPending() ([]types.DeployRequest, error)
	GetRequest(id string) (types.DeployRequest, error)
	Freeze(scope, message string) error
	Unfreeze(scope string) error
	Frozen() (string, error)
	Cancel(id string) error
	ProposeMerge(from, to string) (string, error)
}

// ---------- mock ----------

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

// ---------- control (REST real) ----------

type controlSource struct {
	base, token string
	hc          *http.Client
}

func newControlSource(base, token string) *controlSource {
	return &controlSource{base: base, token: token, hc: &http.Client{Timeout: 20 * time.Second}}
}

func (c *controlSource) get(path string, out any) error {
	req, _ := http.NewRequest("GET", c.base+path, nil)
	return c.do(req, out)
}
func (c *controlSource) post(path string, body any, out any) error {
	var r *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	} else {
		r = bytes.NewReader(nil)
	}
	req, _ := http.NewRequest("POST", c.base+path, r)
	req.Header.Set("Content-Type", "application/json")
	return c.do(req, out)
}
func deviceID() string {
	h, _ := os.Hostname()
	u := os.Getenv("USER")
	if u == "" {
		u = os.Getenv("USERNAME") // windows
	}
	if h == "" {
		h = "?"
	}
	if u == "" {
		u = "?"
	}
	return h + "/" + u
}

func (c *controlSource) do(req *http.Request, out any) error {
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("X-Almirante-Host", deviceID()) // audita o dispositivo do dev
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		var e struct {
			Error string `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&e)
		if e.Error != "" {
			return fmt.Errorf("%s", e.Error)
		}
		return fmt.Errorf("control %d em %s", resp.StatusCode, req.URL.Path)
	}
	if out == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (c *controlSource) Status(vm string) (types.HostStatus, error) {
	var v types.HostStatus
	return v, c.get("/api/vms/"+vm+"/status", &v)
}
func (c *controlSource) Health(vm string) (types.HealthReport, error) {
	var v types.HealthReport
	return v, c.get("/api/vms/"+vm+"/health", &v)
}
func (c *controlSource) Migrations(vm string) (types.MigrationStatus, error) {
	var v types.MigrationStatus
	return v, c.get("/api/vms/"+vm+"/migrations", &v)
}
func (c *controlSource) Diff(vm string) (types.GitDiff, error) {
	var v types.GitDiff
	return v, c.get("/api/vms/"+vm+"/diff", &v)
}
func (c *controlSource) History(vm string) ([]types.DeployHistoryEntry, error) {
	var v []types.DeployHistoryEntry
	return v, c.get("/api/vms/"+vm+"/history", &v)
}
func (c *controlSource) Propose(vm, branch string) (types.DeployRequest, error) {
	var v types.DeployRequest
	return v, c.post("/api/deploys", map[string]string{"vm": vm, "branch": branch}, &v)
}
func (c *controlSource) ListPending() ([]types.DeployRequest, error) {
	var all []types.DeployRequest
	if err := c.get("/api/deploys", &all); err != nil {
		return nil, err
	}
	var out []types.DeployRequest
	for _, r := range all {
		if r.Status == types.StatusPending {
			out = append(out, r)
		}
	}
	return out, nil
}
func (c *controlSource) GetRequest(id string) (types.DeployRequest, error) {
	var v types.DeployRequest
	return v, c.get("/api/deploys/"+id, &v)
}
func (c *controlSource) Freeze(scope, message string) error {
	return c.post("/api/freeze", map[string]string{"scope": scope, "message": message}, nil)
}
func (c *controlSource) Unfreeze(scope string) error {
	return c.post("/api/unfreeze", map[string]string{"scope": scope}, nil)
}
func (c *controlSource) Frozen() (string, error) {
	var list []map[string]any
	if err := c.get("/api/freeze", &list); err != nil {
		return "", err
	}
	if len(list) == 0 {
		return "Nada congelado.", nil
	}
	var b strings.Builder
	b.WriteString("Congelados:\n")
	for _, f := range list {
		fmt.Fprintf(&b, "• %v — %v (por %v)\n", f["scope"], f["message"], f["by"])
	}
	return b.String(), nil
}
func (c *controlSource) Cancel(id string) error {
	return c.post("/api/deploys/"+id+"/cancel", nil, nil)
}
func (c *controlSource) ProposeMerge(from, to string) (string, error) {
	var v struct {
		ID, From, To, Status string
	}
	if err := c.post("/api/merges", map[string]string{"from": from, "to": to}, &v); err != nil {
		return "", err
	}
	return fmt.Sprintf("merge %s -> %s enfileirado (%s, %s) — aprovacao humana (admin) no painel.", v.From, v.To, v.ID, v.Status), nil
}
