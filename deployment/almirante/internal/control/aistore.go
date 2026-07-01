package control

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"sync"
	"time"
)

// aistore.go: audit local dos change-sets de governanca de IA (1 arquivo
// aichg_N.json por change-set), pra history + rollback. Espelha store.go.
// O audit hash-chain (audit.Logger) continua sendo a fonte imutavel de eventos;
// este store guarda o ESTADO estruturado (payload mascarado, test_report,
// remote_change_set_id) pra listar/reverter.

var aiIDRe = regexp.MustCompile(`^aichg_\d+\.json$`)

// AIChange e o registro estruturado de um change-set de IA.
type AIChange struct {
	ID                string                 `json:"id"`
	ChangeSetID       string                 `json:"change_set_id"`
	VM                string                 `json:"vm"`
	AssistantID       int                    `json:"assistant_id,omitempty"`
	OpType            string                 `json:"op_type"`
	TargetEnv         string                 `json:"target_env"`
	Status            string                 `json:"status"` // test_failed|applied|failed|reverted
	Actor             string                 `json:"actor"`
	RequestPayload    map[string]interface{} `json:"request_payload,omitempty"`
	TestReport        map[string]interface{} `json:"test_report,omitempty"`
	RemoteChangeSetID string                 `json:"remote_change_set_id,omitempty"`
	Diff              map[string]interface{} `json:"diff,omitempty"`
	Error             string                 `json:"error,omitempty"`
	CreatedAt         string                 `json:"created_at"`
	AppliedAt         string                 `json:"applied_at,omitempty"`
	RevertedAt        string                 `json:"reverted_at,omitempty"`
}

type AIStore struct {
	mu  sync.Mutex
	dir string
	seq int
	now func() time.Time
}

func NewAIStore(stateDir string) *AIStore {
	s := &AIStore{dir: filepath.Join(stateDir, "aichanges"), seq: 0, now: time.Now}
	_ = os.MkdirAll(s.dir, 0o750)
	for _, f := range s.readDir() {
		var n int
		if _, err := fmt.Sscanf(f, "aichg_%d.json", &n); err == nil && n > s.seq {
			s.seq = n
		}
	}
	return s
}

func (s *AIStore) readDir() []string {
	entries, _ := os.ReadDir(s.dir)
	var out []string
	for _, e := range entries {
		if aiIDRe.MatchString(e.Name()) {
			out = append(out, e.Name())
		}
	}
	return out
}

func (s *AIStore) path(id string) string { return filepath.Join(s.dir, id+".json") }

func (s *AIStore) write(c AIChange) {
	b, _ := json.MarshalIndent(c, "", "  ")
	_ = os.WriteFile(s.path(c.ID), b, 0o640)
}

// Create grava um novo registro (id sequencial + created_at).
func (s *AIStore) Create(c AIChange) AIChange {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.seq++
	c.ID = fmt.Sprintf("aichg_%d", s.seq)
	if c.CreatedAt == "" {
		c.CreatedAt = s.now().UTC().Format(time.RFC3339)
	}
	s.write(c)
	return c
}

func (s *AIStore) get(id string) (AIChange, bool) {
	b, err := os.ReadFile(s.path(id))
	if err != nil {
		return AIChange{}, false
	}
	var c AIChange
	if json.Unmarshal(b, &c) != nil {
		return AIChange{}, false
	}
	return c, true
}

// FindByChangeSetID acha um registro pelo cs_... (para rollback).
func (s *AIStore) FindByChangeSetID(csID string) (AIChange, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, f := range s.readDir() {
		if c, ok := s.get(f[:len(f)-len(".json")]); ok && c.ChangeSetID == csID {
			return c, true
		}
	}
	return AIChange{}, false
}

// Update aplica mutate sob lock (por id interno).
func (s *AIStore) Update(id string, mutate func(*AIChange)) (AIChange, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.get(id)
	if !ok {
		return AIChange{}, false
	}
	mutate(&c)
	s.write(c)
	return c, true
}

// ListByVM lista os change-sets de uma VM (mais recentes primeiro). vm vazio = todos.
func (s *AIStore) ListByVM(vm string, limit int) []AIChange {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []AIChange
	for _, f := range s.readDir() {
		if c, ok := s.get(f[:len(f)-len(".json")]); ok {
			if vm == "" || c.VM == vm {
				out = append(out, c)
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt > out[j].CreatedAt })
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out
}
