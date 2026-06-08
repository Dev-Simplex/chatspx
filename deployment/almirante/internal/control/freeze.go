package control

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// FreezeScopeAll congela a frota inteira (qualquer VM e considerada congelada).
const FreezeScopeAll = "all"

// Freeze e um congelamento ativo: bloqueia novos deploys no escopo (uma VM ou "all").
type Freeze struct {
	Scope     string `json:"scope"`
	Message   string `json:"message,omitempty"`
	By        string `json:"by"`
	CreatedAt string `json:"created_at"`
}

// FreezeStore: estado duravel dos congelamentos. Concorrencia-safe (o dispatcher
// faz fan-out). Persiste tudo num unico <stateDir>/freeze.json.
type FreezeStore struct {
	mu    sync.Mutex
	path  string
	items map[string]Freeze
	now   func() time.Time
}

func NewFreezeStore(stateDir string) *FreezeStore {
	_ = os.MkdirAll(stateDir, 0o750)
	fs := &FreezeStore{
		path:  filepath.Join(stateDir, "freeze.json"),
		items: map[string]Freeze{},
		now:   time.Now,
	}
	fs.load()
	return fs
}

func (fs *FreezeStore) load() {
	b, err := os.ReadFile(fs.path)
	if err != nil {
		return
	}
	var list []Freeze
	if json.Unmarshal(b, &list) != nil {
		return
	}
	for _, f := range list {
		if f.Scope != "" {
			fs.items[f.Scope] = f
		}
	}
}

// flush grava o estado atual. Chamado sob lock.
func (fs *FreezeStore) flush() {
	out := make([]Freeze, 0, len(fs.items))
	for _, f := range fs.items {
		out = append(out, f)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Scope < out[j].Scope })
	b, _ := json.MarshalIndent(out, "", "  ")
	_ = os.WriteFile(fs.path, b, 0o640)
}

// Freeze congela um escopo (VM id ou "all"). Sobrescreve um congelamento anterior.
func (fs *FreezeStore) Freeze(scope, msg, by string) Freeze {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	f := Freeze{
		Scope:     scope,
		Message:   msg,
		By:        by,
		CreatedAt: fs.now().UTC().Format(time.RFC3339),
	}
	fs.items[scope] = f
	fs.flush()
	return f
}

// Unfreeze remove o congelamento de um escopo. Retorna false se nao havia.
func (fs *FreezeStore) Unfreeze(scope string) bool {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	if _, ok := fs.items[scope]; !ok {
		return false
	}
	delete(fs.items, scope)
	fs.flush()
	return true
}

// IsFrozen diz se a VM esta congelada — diretamente pelo seu id OU pelo escopo
// global "all". Retorna o Freeze que aplica (precedencia: id especifico > all).
func (fs *FreezeStore) IsFrozen(vm string) (Freeze, bool) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	if f, ok := fs.items[vm]; ok {
		return f, true
	}
	if f, ok := fs.items[FreezeScopeAll]; ok {
		return f, true
	}
	return Freeze{}, false
}

// List devolve todos os congelamentos ativos, ordenados por escopo.
func (fs *FreezeStore) List() []Freeze {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	out := make([]Freeze, 0, len(fs.items))
	for _, f := range fs.items {
		out = append(out, f)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Scope < out[j].Scope })
	return out
}
