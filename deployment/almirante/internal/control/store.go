// Package control e o dispatcher: REST + gate (RBAC + anti-self-review) + audit.
// Segura as credenciais de transporte; o MCP/dev so fala REST com ele.
package control

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"sync"

	"github.com/Dev-Simplex/almirante/internal/types"
)

var idRe = regexp.MustCompile(`^req_\d+\.json$`)

// Store: estado duravel dos pedidos. Concorrencia-safe (o dispatcher faz fan-out).
type Store struct {
	mu  sync.Mutex
	dir string
	seq int
}

func NewStore(stateDir string) *Store {
	s := &Store{dir: filepath.Join(stateDir, "requests"), seq: 411}
	_ = os.MkdirAll(s.dir, 0o750)
	for _, f := range readDir(s.dir) {
		var n int
		if _, err := fmt.Sscanf(f, "req_%d.json", &n); err == nil && n > s.seq {
			s.seq = n
		}
	}
	return s
}

func readDir(dir string) []string {
	entries, _ := os.ReadDir(dir)
	var out []string
	for _, e := range entries {
		if idRe.MatchString(e.Name()) {
			out = append(out, e.Name())
		}
	}
	return out
}

// StateDir devolve o diretorio-base de estado (pai de requests/), usado por
// outros stores duraveis (ex: FreezeStore grava freeze.json ai).
func (s *Store) StateDir() string { return filepath.Dir(s.dir) }

func (s *Store) path(id string) string { return filepath.Join(s.dir, id+".json") }

func (s *Store) write(r types.DeployRequest) {
	b, _ := json.MarshalIndent(r, "", "  ")
	_ = os.WriteFile(s.path(r.ID), b, 0o640)
}

func (s *Store) Create(r types.DeployRequest) types.DeployRequest {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.seq++
	r.ID = fmt.Sprintf("req_%d", s.seq)
	s.write(r)
	return r
}

func (s *Store) Get(id string) (types.DeployRequest, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.get(id)
}

func (s *Store) get(id string) (types.DeployRequest, bool) {
	b, err := os.ReadFile(s.path(id))
	if err != nil {
		return types.DeployRequest{}, false
	}
	var r types.DeployRequest
	if json.Unmarshal(b, &r) != nil {
		return types.DeployRequest{}, false
	}
	return r, true
}

// Update aplica mutate sob lock (evita race de leitura-escrita).
func (s *Store) Update(id string, mutate func(*types.DeployRequest)) (types.DeployRequest, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, ok := s.get(id)
	if !ok {
		return types.DeployRequest{}, false
	}
	mutate(&r)
	s.write(r)
	return r, true
}

func (s *Store) List() []types.DeployRequest {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []types.DeployRequest
	for _, f := range readDir(s.dir) {
		if r, ok := s.get(f[:len(f)-len(".json")]); ok {
			out = append(out, r)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt > out[j].CreatedAt })
	return out
}
