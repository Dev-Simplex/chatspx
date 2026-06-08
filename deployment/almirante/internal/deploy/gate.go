package deploy

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"time"
)

// chave de token do gate: SHA OU identificador (ex: "restart-chatwoot_target").
var keyRe = regexp.MustCompile(`^[a-zA-Z0-9_.-]{1,80}$`)

// Gate e o portao FORA do LLM: deploy/restart so rodam com um arquivo-token que
// SO 'approve' (sessao humana) cria. A chave forced-command do transporte nem
// expoe os subcomandos approve/deploy.
type Gate struct {
	dir string
	Now func() time.Time
}

func NewGate(stateDir string) *Gate {
	return &Gate{dir: stateDir, Now: time.Now}
}

type token struct {
	SHA     string `json:"sha"`
	By      string `json:"by"`
	At      string `json:"at"`
	Expires string `json:"expires"`
}

func (g *Gate) pendingPath(sha string) string  { return filepath.Join(g.dir, "pending", sha+".json") }
func (g *Gate) approvedPath(sha string) string  { return filepath.Join(g.dir, "approved", sha+".token") }

func (g *Gate) Enqueue(sha, actor string) error {
	if !keyRe.MatchString(sha) {
		return fmt.Errorf("sha invalido: %q", sha)
	}
	p := g.pendingPath(sha)
	if err := os.MkdirAll(filepath.Dir(p), 0o750); err != nil {
		return err
	}
	b, _ := json.Marshal(token{SHA: sha, By: actor, At: g.Now().UTC().Format(time.RFC3339)})
	return os.WriteFile(p, b, 0o640)
}

// Approve cria o token. TTL conta a partir da aprovacao (nao do enfileiramento).
func (g *Gate) Approve(sha, by string, ttl time.Duration) error {
	if !keyRe.MatchString(sha) {
		return fmt.Errorf("sha invalido: %q", sha)
	}
	p := g.approvedPath(sha)
	if err := os.MkdirAll(filepath.Dir(p), 0o750); err != nil {
		return err
	}
	now := g.Now().UTC()
	b, _ := json.Marshal(token{SHA: sha, By: by, At: now.Format(time.RFC3339), Expires: now.Add(ttl).Format(time.RFC3339)})
	return os.WriteFile(p, b, 0o640)
}

// RequireApproval falha se nao houver token valido e nao expirado.
func (g *Gate) RequireApproval(sha string) error {
	if !keyRe.MatchString(sha) {
		return fmt.Errorf("sha invalido: %q", sha)
	}
	b, err := os.ReadFile(g.approvedPath(sha))
	if err != nil {
		return fmt.Errorf("deploy de %s NAO aprovado: um humano precisa aprovar no painel (ou 'almiranted approve %s <nome>')", sha, sha)
	}
	var t token
	if json.Unmarshal(b, &t) != nil {
		return fmt.Errorf("token de aprovacao corrompido para %s", sha)
	}
	if t.Expires != "" {
		exp, perr := time.Parse(time.RFC3339, t.Expires)
		if perr == nil && g.Now().After(exp) {
			g.Clear(sha)
			return fmt.Errorf("aprovacao de %s EXPIROU em %s — reaprovar", sha, t.Expires)
		}
	}
	return nil
}

func (g *Gate) Clear(sha string) {
	os.Remove(g.approvedPath(sha))
	os.Remove(g.pendingPath(sha))
}
