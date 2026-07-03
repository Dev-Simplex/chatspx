package control

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Token: credencial de dev emitida pelo painel (admin). Captura o DISPOSITIVO
// (host+IP) que a usa, pra o admin ver "qual PC pegou o token".
type Token struct {
	ID        string `json:"id"`
	Secret    string `json:"secret"`
	Name      string `json:"name"`
	Role      string `json:"role"`
	CreatedAt string `json:"created_at"`
	CreatedBy string `json:"created_by"`
	LastHost  string `json:"last_host,omitempty"`
	LastIP    string `json:"last_ip,omitempty"`
	LastSeen  string `json:"last_seen,omitempty"`
	Revoked   bool   `json:"revoked"`
}

type TokenStore struct {
	mu   sync.Mutex
	path string
	seq  int
	toks map[string]*Token // keyed by secret
}

func NewTokenStore(stateDir string) *TokenStore {
	ts := &TokenStore{path: filepath.Join(stateDir, "tokens.json"), seq: 0, toks: map[string]*Token{}}
	ts.load()
	return ts
}

func (ts *TokenStore) load() {
	b, err := os.ReadFile(ts.path)
	if err != nil {
		return
	}
	var list []*Token
	if json.Unmarshal(b, &list) != nil {
		return
	}
	for _, t := range list {
		ts.toks[t.Secret] = t
		var n int
		if _, e := fmt.Sscanf(t.ID, "tok_%d", &n); e == nil && n > ts.seq {
			ts.seq = n
		}
	}
}

func (ts *TokenStore) save() {
	list := make([]*Token, 0, len(ts.toks))
	for _, t := range ts.toks {
		list = append(list, t)
	}
	b, _ := json.MarshalIndent(list, "", "  ")
	_ = os.MkdirAll(filepath.Dir(ts.path), 0o750)
	_ = os.WriteFile(ts.path, b, 0o600) // 0600: contem segredos
}

func genSecret() string {
	b := make([]byte, 24)
	_, _ = rand.Read(b)
	return "alm_" + hex.EncodeToString(b)
}

func (ts *TokenStore) Issue(name, role, by string) *Token {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	ts.seq++
	t := &Token{
		ID: fmt.Sprintf("tok_%d", ts.seq), Secret: genSecret(), Name: name, Role: role,
		CreatedAt: time.Now().UTC().Format(time.RFC3339), CreatedBy: by,
	}
	ts.toks[t.Secret] = t
	ts.save()
	return t
}

// Lookup resolve um segredo (nao revogado). Usado pelo auth.
func (ts *TokenStore) Lookup(secret string) (*Token, bool) {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, ok := ts.toks[secret]
	if !ok || t.Revoked {
		return nil, false
	}
	return t, true
}

// Touch grava o dispositivo (host+IP) que usou o token, no maximo 1x/min por token.
func (ts *TokenStore) Touch(secret, host, ip string) {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, ok := ts.toks[secret]
	if !ok {
		return
	}
	now := time.Now().UTC()
	if t.LastSeen != "" {
		if last, err := time.Parse(time.RFC3339, t.LastSeen); err == nil && now.Sub(last) < time.Minute && t.LastHost == host {
			return
		}
	}
	t.LastHost, t.LastIP, t.LastSeen = host, ip, now.Format(time.RFC3339)
	ts.save()
}

// List devolve copias com o segredo MASCARADO (so prefixo + ultimos 4).
func (ts *TokenStore) List() []Token {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	out := make([]Token, 0, len(ts.toks))
	for _, t := range ts.toks {
		c := *t
		if len(c.Secret) > 8 {
			c.Secret = c.Secret[:4] + "…" + c.Secret[len(c.Secret)-4:]
		}
		out = append(out, c)
	}
	return out
}

func (ts *TokenStore) Revoke(id string) bool {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	for _, t := range ts.toks {
		if t.ID == id {
			t.Revoked = true
			ts.save()
			return true
		}
	}
	return false
}

// ---- handlers HTTP (admin) ----

// POST /api/tokens {name,role} -> emite e devolve o segredo UMA vez.
func (s *Server) issueToken(w http.ResponseWriter, r *http.Request, u user) {
	var body struct{ Name, Role string }
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields() // strict: tokens NÃO aceitam escopo por VM em silêncio (foot-gun)
	if err := dec.Decode(&body); err != nil {
		writeErr(w, 400, "corpo inválido — tokens de máquina não têm escopo por VM (são all-VM); pra restringir por VM, crie um USUÁRIO humano e use vm_access: "+err.Error())
		return
	}
	if body.Name == "" {
		writeErr(w, 400, "informe 'name' (nome do dev)")
		return
	}
	role := body.Role
	if role == "" {
		role = "operator"
	}
	t := s.tstore.Issue(body.Name, role, u.name)
	s.audit.Append("issue_token", u.name, "", map[string]any{"id": t.ID, "for": body.Name, "role": role})
	writeJSON(w, 200, map[string]string{"id": t.ID, "token": t.Secret, "name": t.Name, "role": t.Role})
}

// GET /api/tokens -> lista (segredo mascarado + dispositivo que usou).
func (s *Server) listTokens(w http.ResponseWriter, _ *http.Request, _ user) {
	writeJSON(w, 200, s.tstore.List())
}

// DELETE /api/tokens/{id} -> revoga.
func (s *Server) revokeToken(w http.ResponseWriter, r *http.Request, u user) {
	if s.tstore.Revoke(r.PathValue("id")) {
		s.audit.Append("revoke_token", u.name, "", map[string]any{"id": r.PathValue("id")})
		writeJSON(w, 200, map[string]string{"status": "revoked"})
		return
	}
	writeErr(w, 404, "token nao encontrado")
}
