// Package github: client da API REST do GitHub (api.github.com) pro Toolset G do
// Almirante — "GitHub de verdade" via MCP: ler/abrir PRs, issues, arquivos, branches.
// Estilo enxuto (net/http), espelhando aiconfig/driver.go. Auth: PAT em GITHUB_TOKEN.
//
// GUARDRAILS:
//   - allowlist de repos (GITHUB_REPOS) — fail-closed: só opera no que for permitido.
//   - o gating de ESCRITA (quem pode criar PR/mergear) é no control (RBAC), nao aqui.
package github

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"
)

// Client fala com a API REST do GitHub com um PAT.
type Client struct {
	token string
	http  *http.Client
	base  string          // https://api.github.com
	allow map[string]bool // repos permitidos ("owner/repo"); vazio = nega tudo
}

// New monta o client. allowRepos = lista "owner/repo" (fail-closed se vazia).
func New(token string, allowRepos []string, timeout time.Duration) *Client {
	if timeout <= 0 {
		timeout = 20 * time.Second
	}
	allow := map[string]bool{}
	for _, r := range allowRepos {
		if r = strings.TrimSpace(r); r != "" {
			allow[r] = true
		}
	}
	return &Client{token: strings.TrimSpace(token), http: &http.Client{Timeout: timeout}, base: "https://api.github.com", allow: allow}
}

// Available indica se ha token configurado (governanca GitHub ligada).
func (c *Client) Available() bool { return c != nil && c.token != "" }

// Repos devolve a allowlist ordenada (pro seletor de repo do painel).
func (c *Client) Repos() []string {
	out := make([]string, 0, len(c.allow))
	for r := range c.allow {
		out = append(out, r)
	}
	sort.Strings(out)
	return out
}

// checkRepo valida o repo contra a allowlist (fail-closed).
func (c *Client) checkRepo(repo string) error {
	if !c.allow[repo] {
		return fmt.Errorf("github: repo %q fora da allowlist (GITHUB_REPOS)", repo)
	}
	return nil
}

// do: verbo + path (relativo ao base) + body + out. Header Bearer + api-version.
func (c *Client) do(ctx context.Context, method, path string, body, out any) error {
	var reqBody io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("github: marshal body: %w", err)
		}
		reqBody = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.base+path, reqBody)
	if err != nil {
		return fmt.Errorf("github: build req: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("github: do %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return fmt.Errorf("github: %s %s -> %d: %s", method, path, resp.StatusCode, strings.TrimSpace(string(b)))
	}
	if out == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// ---------- LEITURA (RBAC: viewer) ----------

func (c *Client) ListPRs(ctx context.Context, repo, state string) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	if state == "" {
		state = "open"
	}
	var v any
	return v, c.do(ctx, http.MethodGet, fmt.Sprintf("/repos/%s/pulls?state=%s&per_page=30", repo, state), nil, &v)
}

func (c *Client) GetPR(ctx context.Context, repo string, number int) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	var v any
	return v, c.do(ctx, http.MethodGet, fmt.Sprintf("/repos/%s/pulls/%d", repo, number), nil, &v)
}

func (c *Client) ListIssues(ctx context.Context, repo, state string) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	if state == "" {
		state = "open"
	}
	var v any
	return v, c.do(ctx, http.MethodGet, fmt.Sprintf("/repos/%s/issues?state=%s&per_page=30", repo, state), nil, &v)
}

func (c *Client) GetIssue(ctx context.Context, repo string, number int) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	var v any
	return v, c.do(ctx, http.MethodGet, fmt.Sprintf("/repos/%s/issues/%d", repo, number), nil, &v)
}

func (c *Client) ListBranches(ctx context.Context, repo string) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	var v any
	return v, c.do(ctx, http.MethodGet, fmt.Sprintf("/repos/%s/branches?per_page=50", repo), nil, &v)
}

// ReadFile devolve o conteudo de um arquivo (decodifica base64 da API contents).
func (c *Client) ReadFile(ctx context.Context, repo, path, ref string) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	q := ""
	if ref != "" {
		q = "?ref=" + ref
	}
	var v any
	return v, c.do(ctx, http.MethodGet, fmt.Sprintf("/repos/%s/contents/%s%s", repo, path, q), nil, &v)
}

// ---------- ESCRITA (RBAC: operator/admin no control) ----------

func (c *Client) CreateIssue(ctx context.Context, repo, title, body string) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	var v any
	return v, c.do(ctx, http.MethodPost, fmt.Sprintf("/repos/%s/issues", repo), map[string]any{"title": title, "body": body}, &v)
}

func (c *Client) Comment(ctx context.Context, repo string, number int, body string) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	var v any
	return v, c.do(ctx, http.MethodPost, fmt.Sprintf("/repos/%s/issues/%d/comments", repo, number), map[string]any{"body": body}, &v)
}

func (c *Client) CreatePR(ctx context.Context, repo, head, base, title, body string) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	var v any
	return v, c.do(ctx, http.MethodPost, fmt.Sprintf("/repos/%s/pulls", repo), map[string]any{"head": head, "base": base, "title": title, "body": body}, &v)
}

func (c *Client) MergePR(ctx context.Context, repo string, number int, method string) (any, error) {
	if err := c.checkRepo(repo); err != nil {
		return nil, err
	}
	if method == "" {
		method = "squash"
	}
	var v any
	return v, c.do(ctx, http.MethodPut, fmt.Sprintf("/repos/%s/pulls/%d/merge", repo, number), map[string]any{"merge_method": method}, &v)
}
