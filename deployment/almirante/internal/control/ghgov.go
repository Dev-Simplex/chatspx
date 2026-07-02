package control

// Handlers REST /api/gh/* — "GitHub de verdade" pelo Almirante (Toolset G).
// Leitura=Viewer; escrita=Operator (criar issue/PR/comentar) e Admin (merge).
// Toda escrita e auditada. O client (internal/github) faz allowlist de repos fail-closed.

import (
	"encoding/json"
	"net/http"
	"strconv"
)

// ghReady valida o client + extrai o repo obrigatorio da querystring.
func (s *Server) ghReady(w http.ResponseWriter, r *http.Request) (string, bool) {
	if s.ghclient == nil || !s.ghclient.Available() {
		writeErr(w, 503, "governanca de GitHub nao configurada (sem GITHUB_TOKEN)")
		return "", false
	}
	repo := r.URL.Query().Get("repo")
	if repo == "" {
		writeErr(w, 400, "parametro repo obrigatorio (owner/repo)")
		return "", false
	}
	return repo, true
}

func ghNum(r *http.Request) int { n, _ := strconv.Atoi(r.URL.Query().Get("number")); return n }

// ---------- LEITURA (RoleViewer) ----------

func (s *Server) ghListPRs(w http.ResponseWriter, r *http.Request, _ user) {
	repo, ok := s.ghReady(w, r)
	if !ok {
		return
	}
	v, err := s.ghclient.ListPRs(r.Context(), repo, r.URL.Query().Get("state"))
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	writeJSON(w, 200, v)
}

func (s *Server) ghGetPR(w http.ResponseWriter, r *http.Request, _ user) {
	repo, ok := s.ghReady(w, r)
	if !ok {
		return
	}
	v, err := s.ghclient.GetPR(r.Context(), repo, ghNum(r))
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	writeJSON(w, 200, v)
}

func (s *Server) ghListIssues(w http.ResponseWriter, r *http.Request, _ user) {
	repo, ok := s.ghReady(w, r)
	if !ok {
		return
	}
	v, err := s.ghclient.ListIssues(r.Context(), repo, r.URL.Query().Get("state"))
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	writeJSON(w, 200, v)
}

func (s *Server) ghGetIssue(w http.ResponseWriter, r *http.Request, _ user) {
	repo, ok := s.ghReady(w, r)
	if !ok {
		return
	}
	v, err := s.ghclient.GetIssue(r.Context(), repo, ghNum(r))
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	writeJSON(w, 200, v)
}

func (s *Server) ghListBranches(w http.ResponseWriter, r *http.Request, _ user) {
	repo, ok := s.ghReady(w, r)
	if !ok {
		return
	}
	v, err := s.ghclient.ListBranches(r.Context(), repo)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	writeJSON(w, 200, v)
}

func (s *Server) ghReadFile(w http.ResponseWriter, r *http.Request, _ user) {
	repo, ok := s.ghReady(w, r)
	if !ok {
		return
	}
	path := r.URL.Query().Get("path")
	if path == "" {
		writeErr(w, 400, "parametro path obrigatorio")
		return
	}
	v, err := s.ghclient.ReadFile(r.Context(), repo, path, r.URL.Query().Get("ref"))
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	writeJSON(w, 200, v)
}

// ---------- ESCRITA (Operator; merge=Admin) — auditada ----------

func (s *Server) ghCreateIssue(w http.ResponseWriter, r *http.Request, u user) {
	if s.ghclient == nil || !s.ghclient.Available() {
		writeErr(w, 503, "governanca de GitHub nao configurada")
		return
	}
	var b struct {
		Repo  string `json:"repo"`
		Title string `json:"title"`
		Body  string `json:"body"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.Repo == "" || b.Title == "" {
		writeErr(w, 400, "repo e title obrigatorios")
		return
	}
	v, err := s.ghclient.CreateIssue(r.Context(), b.Repo, b.Title, b.Body)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	s.audit.Append("gh_issue_created", u.name, b.Repo, map[string]any{"title": b.Title})
	writeJSON(w, 200, v)
}

func (s *Server) ghComment(w http.ResponseWriter, r *http.Request, u user) {
	if s.ghclient == nil || !s.ghclient.Available() {
		writeErr(w, 503, "governanca de GitHub nao configurada")
		return
	}
	var b struct {
		Repo   string `json:"repo"`
		Number int    `json:"number"`
		Body   string `json:"body"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.Repo == "" || b.Number == 0 || b.Body == "" {
		writeErr(w, 400, "repo, number e body obrigatorios")
		return
	}
	v, err := s.ghclient.Comment(r.Context(), b.Repo, b.Number, b.Body)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	s.audit.Append("gh_comment", u.name, b.Repo, map[string]any{"number": b.Number})
	writeJSON(w, 200, v)
}

func (s *Server) ghCreatePR(w http.ResponseWriter, r *http.Request, u user) {
	if s.ghclient == nil || !s.ghclient.Available() {
		writeErr(w, 503, "governanca de GitHub nao configurada")
		return
	}
	var b struct {
		Repo  string `json:"repo"`
		Head  string `json:"head"`
		Base  string `json:"base"`
		Title string `json:"title"`
		Body  string `json:"body"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.Repo == "" || b.Head == "" || b.Base == "" || b.Title == "" {
		writeErr(w, 400, "repo, head, base e title obrigatorios")
		return
	}
	v, err := s.ghclient.CreatePR(r.Context(), b.Repo, b.Head, b.Base, b.Title, b.Body)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	s.audit.Append("gh_pr_created", u.name, b.Repo, map[string]any{"head": b.Head, "base": b.Base, "title": b.Title})
	writeJSON(w, 200, v)
}

func (s *Server) ghMergePR(w http.ResponseWriter, r *http.Request, u user) {
	if s.ghclient == nil || !s.ghclient.Available() {
		writeErr(w, 503, "governanca de GitHub nao configurada")
		return
	}
	var b struct {
		Repo   string `json:"repo"`
		Number int    `json:"number"`
		Method string `json:"method"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.Repo == "" || b.Number == 0 {
		writeErr(w, 400, "repo e number obrigatorios")
		return
	}
	v, err := s.ghclient.MergePR(r.Context(), b.Repo, b.Number, b.Method)
	if err != nil {
		writeErr(w, 502, err.Error())
		return
	}
	s.audit.Append("gh_pr_merged", u.name, b.Repo, map[string]any{"number": b.Number, "method": b.Method})
	writeJSON(w, 200, v)
}
