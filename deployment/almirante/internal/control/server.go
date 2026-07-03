package control

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/Dev-Simplex/almirante/internal/aiconfig"
	"github.com/Dev-Simplex/almirante/internal/audit"
	"github.com/Dev-Simplex/almirante/internal/github"
	"github.com/Dev-Simplex/almirante/internal/mcptools"
	"github.com/Dev-Simplex/almirante/internal/types"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type Role int

const (
	RoleViewer Role = iota + 1
	RoleOperator
	RoleAdmin
)

func parseRole(s string) Role {
	switch s {
	case "admin":
		return RoleAdmin
	case "operator":
		return RoleOperator
	default:
		return RoleViewer
	}
}

type user struct {
	name string
	role Role
}

type Server struct {
	fleet    *types.Fleet
	store    *Store
	freeze   *FreezeStore
	merges   *mergeStore
	releases *releaseStore
	exec     Executor
	audit    *audit.Logger
	tokens     map[string]user
	tstore     *TokenStore
	users      *UserStore
	mailer     *Mailer
	sessSecret []byte
	appURL     string
	selfBase   string // base loopback p/ o MCP HTTP falar com a propria REST
	ttl        time.Duration
	now        func() time.Time
	mergeDir   string
	repoURL    string
	// governanca de IA (nil se feature off)
	aidriver *aiconfig.Driver
	aigate   *aiconfig.TestGate
	aistore  *AIStore
	// governanca de GitHub (nil se feature off)
	ghclient *github.Client
}

// tokensCSV: "token:name:role,token2:name2:role2"
func NewServer(cfg Config, store *Store, aud *audit.Logger, tokensCSV string) *Server {
	tokens := map[string]user{}
	for _, e := range strings.Split(tokensCSV, ",") {
		e = strings.TrimSpace(e)
		if e == "" {
			continue
		}
		p := strings.Split(e, ":")
		if len(p) >= 1 && p[0] != "" {
			name, role := "anon", "viewer"
			if len(p) > 1 {
				name = p[1]
			}
			if len(p) > 2 {
				role = p[2]
			}
			tokens[p[0]] = user{name: name, role: parseRole(role)}
		}
	}
	ttl := cfg.ApprovalTTL
	if ttl == 0 {
		ttl = 20 * time.Minute
	}
	return &Server{
		fleet:    cfg.Fleet,
		store:    store,
		freeze:   NewFreezeStore(store.StateDir()),
		merges:   newMergeStore(),
		releases: newReleaseStore(),
		exec:     Executor{Cfg: cfg},
		audit:    aud,
		tokens:   tokens,
		tstore:     NewTokenStore(store.StateDir()),
		users:      NewUserStore(store.StateDir()),
		mailer:     NewMailerFromEnv(),
		sessSecret: sessionSecretFromEnv(),
		appURL:     envOr2("ALMIRANTE_APP_URL", "https://painel.chatspx.app"),
		selfBase:   envOr2("ALMIRANTE_SELF_URL", "http://127.0.0.1:"+envOr2("ALMIRANTE_CONTROL_PORT", "4100")),
		ttl:        ttl,
		now:      time.Now,
		mergeDir: cfg.MergeCloneDir,
		repoURL:  cfg.RepoURL,
		aidriver: cfg.AIDriver,
		aigate:   cfg.AIGate,
		aistore:  NewAIStore(store.StateDir()),
		ghclient: cfg.GHClient,
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, map[string]any{"status": "ok"}) })
	mux.HandleFunc("GET /api/fleet", s.auth(RoleViewer, s.getFleet))
	mux.HandleFunc("GET /api/vms/{id}/status", s.auth(RoleViewer, s.vmStatus))
	mux.HandleFunc("GET /api/vms/{id}/health", s.auth(RoleViewer, s.vmHealth))
	mux.HandleFunc("GET /api/vms/{id}/migrations", s.auth(RoleViewer, s.vmMigrations))
	mux.HandleFunc("GET /api/vms/{id}/diff", s.auth(RoleViewer, s.vmDiff))
	mux.HandleFunc("GET /api/vms/{id}/history", s.auth(RoleViewer, s.vmHistory))
	mux.HandleFunc("GET /api/vms/{id}/metrics", s.auth(RoleViewer, s.vmMetrics))
	mux.HandleFunc("POST /api/vms/{id}/restart", s.auth(RoleAdmin, s.vmRestart))
	mux.HandleFunc("POST /api/deploys", s.auth(RoleOperator, s.createDeploy))
	mux.HandleFunc("GET /api/deploys", s.auth(RoleViewer, s.listDeploys))
	mux.HandleFunc("GET /api/deploys/{id}", s.auth(RoleViewer, s.getDeploy))
	mux.HandleFunc("POST /api/deploys/{id}/approve", s.auth(RoleAdmin, s.approve))
	mux.HandleFunc("POST /api/deploys/{id}/reject", s.auth(RoleAdmin, s.reject))
	mux.HandleFunc("POST /api/deploys/{id}/cancel", s.auth(RoleOperator, s.cancel))
	mux.HandleFunc("GET /api/freeze", s.auth(RoleViewer, s.listFreeze))
	mux.HandleFunc("POST /api/freeze", s.auth(RoleOperator, s.doFreeze))
	mux.HandleFunc("POST /api/unfreeze", s.auth(RoleAdmin, s.doUnfreeze))
	mux.HandleFunc("GET /api/merges", s.auth(RoleViewer, s.listMerges))
	mux.HandleFunc("POST /api/merges", s.auth(RoleOperator, s.proposeMerge))
	mux.HandleFunc("POST /api/merges/{id}/approve", s.auth(RoleAdmin, s.approveMerge))
	// Release: rollout sequencial health-gated (botao "Release pra producao")
	mux.HandleFunc("POST /api/release/dryrun", s.auth(RoleOperator, s.releaseDryRun))
	mux.HandleFunc("POST /api/release", s.auth(RoleAdmin, s.createRelease))
	mux.HandleFunc("GET /api/releases", s.auth(RoleViewer, s.listReleases))
	mux.HandleFunc("GET /api/release/{id}", s.auth(RoleViewer, s.getRelease))
	mux.HandleFunc("GET /api/tokens", s.auth(RoleAdmin, s.listTokens))
	mux.HandleFunc("POST /api/tokens", s.auth(RoleAdmin, s.issueToken))
	mux.HandleFunc("DELETE /api/tokens/{id}", s.auth(RoleAdmin, s.revokeToken))
	// auth de humano (login email+senha + convite) — login/set-password sao publicos
	mux.HandleFunc("POST /api/login", s.login)
	mux.HandleFunc("POST /api/logout", s.logout)
	mux.HandleFunc("POST /api/set-password", s.setPassword)
	mux.HandleFunc("GET /api/me", s.me)
	mux.HandleFunc("GET /api/users", s.auth(RoleAdmin, s.listUsers))
	mux.HandleFunc("POST /api/users", s.auth(RoleAdmin, s.inviteUser))
	mux.HandleFunc("DELETE /api/users/{id}", s.auth(RoleAdmin, s.revokeUser))
	mux.HandleFunc("PUT /api/users/{id}/vms", s.auth(RoleAdmin, s.setUserVMs))
	// Governanca de IA (editar prompt/tools/credencial/FAQ dos agentes por VM).
	// Leitura=Viewer; escrita=Operator + vm_access (canEditVM: admin=todas, operator só
	// as VMs concedidas) — sempre com test-gate + audit + rollback.
	mux.HandleFunc("GET /api/ai/agents", s.auth(RoleViewer, s.aiListAgents))
	mux.HandleFunc("GET /api/ai/assistants", s.auth(RoleViewer, s.aiListAssistants))
	mux.HandleFunc("GET /api/ai/agents/{vm}/{id}", s.auth(RoleViewer, s.aiBaseline))
	mux.HandleFunc("GET /api/ai/custom-tools/{vm}", s.auth(RoleViewer, s.aiCustomTools))
	mux.HandleFunc("GET /api/ai/history", s.auth(RoleViewer, s.aiHistory))
	mux.HandleFunc("POST /api/ai/prompt", s.auth(RoleOperator, s.aiPrompt))
	mux.HandleFunc("POST /api/ai/tool", s.auth(RoleOperator, s.aiTool))
	mux.HandleFunc("POST /api/ai/credential", s.auth(RoleOperator, s.aiCredential))
	mux.HandleFunc("POST /api/ai/behavior", s.auth(RoleOperator, s.aiBehavior))
	mux.HandleFunc("POST /api/ai/faq", s.auth(RoleOperator, s.aiFaq))
	mux.HandleFunc("POST /api/ai/eligibility", s.auth(RoleOperator, s.aiEligibility))
	mux.HandleFunc("POST /api/ai/rollback", s.auth(RoleOperator, s.aiRollback))

	// ===== Toolset G — GitHub de verdade (leitura=Viewer; escrita=Operator; merge=Admin) =====
	mux.HandleFunc("GET /api/gh/repos", s.auth(RoleViewer, s.ghListRepos))
	mux.HandleFunc("GET /api/gh/prs", s.auth(RoleViewer, s.ghListPRs))
	mux.HandleFunc("GET /api/gh/pr", s.auth(RoleViewer, s.ghGetPR))
	mux.HandleFunc("GET /api/gh/issues", s.auth(RoleViewer, s.ghListIssues))
	mux.HandleFunc("GET /api/gh/issue", s.auth(RoleViewer, s.ghGetIssue))
	mux.HandleFunc("GET /api/gh/branches", s.auth(RoleViewer, s.ghListBranches))
	mux.HandleFunc("GET /api/gh/file", s.auth(RoleViewer, s.ghReadFile))
	mux.HandleFunc("POST /api/gh/issue", s.auth(RoleOperator, s.ghCreateIssue))
	mux.HandleFunc("POST /api/gh/comment", s.auth(RoleOperator, s.ghComment))
	mux.HandleFunc("POST /api/gh/pr", s.auth(RoleOperator, s.ghCreatePR))
	mux.HandleFunc("POST /api/gh/merge", s.auth(RoleAdmin, s.ghMergePR))
	return mux
}

// validToken: o token (env bootstrap ou emitido no painel) existe?
func (s *Server) validToken(tok string) bool {
	if tok == "" {
		return false
	}
	if _, ok := s.tokens[tok]; ok {
		return true
	}
	_, ok := s.tstore.Lookup(tok)
	return ok
}

// MCPHandler hospeda o MCP do Almirante por HTTP (streamable). Assim o dev pluga
// com UM comando, sem binario nem editar .mcp.json:
//
//	claude mcp add --transport http almirante https://painel.chatspx.app/mcp \
//	  --header "Authorization: Bearer <token>" --scope user
//
// O token do dev (header) e validado aqui e repassado a uma Source loopback que
// fala a propria REST — preservando requested_by e reusando todo o gate/freeze.
func (s *Server) MCPHandler() http.Handler {
	streamable := mcp.NewStreamableHTTPHandler(func(r *http.Request) *mcp.Server {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		srv := mcp.NewServer(&mcp.Implementation{Name: "almirante", Version: "control", Title: "Almirante — deploy da frota ChatSPX"}, nil)
		mcptools.Register(srv, s.fleet, mcptools.NewControlSource(s.selfBase, tok))
		return srv
	}, nil)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !s.validToken(tok) {
			writeErr(w, 401, "token invalido ou ausente — emita um na aba Tokens do painel")
			return
		}
		streamable.ServeHTTP(w, r)
	})
}

func (s *Server) auth(min Role, h func(http.ResponseWriter, *http.Request, user)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		u, ok := s.tokens[tok] // tokens estaticos da ENV (bootstrap)
		if !ok {
			if t, found := s.tstore.Lookup(tok); found { // tokens emitidos no painel
				u, ok = user{name: t.Name, role: parseRole(t.Role)}, true
				ip := r.RemoteAddr
				if i := strings.LastIndex(ip, ":"); i > 0 {
					ip = ip[:i]
				}
				s.tstore.Touch(tok, r.Header.Get("X-Almirante-Host"), ip) // audita o dispositivo
			}
		}
		if !ok { // sessao de humano (cookie assinado) — login email+senha
			if c, e := r.Cookie("alm_session"); e == nil {
				if su, valid := s.verifySession(c.Value); valid {
					u, ok = su, true
				}
			}
		}
		if !ok {
			writeErr(w, 401, "nao autenticado")
			return
		}
		if u.role < min {
			writeErr(w, 403, "requer role mais alta")
			return
		}
		h(w, r, u)
	}
}

func (s *Server) getFleet(w http.ResponseWriter, _ *http.Request, _ user) { writeJSON(w, 200, s.fleet) }

func (s *Server) vmStatus(w http.ResponseWriter, r *http.Request, _ user) {
	v, err := s.exec.Status(r.Context(), r.PathValue("id"))
	respond(w, v, err)
}
func (s *Server) vmMetrics(w http.ResponseWriter, r *http.Request, _ user) {
	v, err := s.exec.Metrics(r.Context(), r.PathValue("id"))
	respond(w, v, err)
}
func (s *Server) vmRestart(w http.ResponseWriter, r *http.Request, u user) {
	var b struct {
		Unit string `json:"unit"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	id := r.PathValue("id")
	if err := s.exec.Restart(r.Context(), id, b.Unit); err != nil {
		writeErr(w, 400, err.Error())
		return
	}
	s.audit.Append("restart", u.name, id, map[string]any{"unit": b.Unit})
	writeJSON(w, 200, map[string]string{"status": "restarted", "unit": b.Unit})
}
func (s *Server) vmHealth(w http.ResponseWriter, r *http.Request, _ user) {
	v, err := s.exec.Health(r.Context(), r.PathValue("id"))
	respond(w, v, err)
}
func (s *Server) vmMigrations(w http.ResponseWriter, r *http.Request, _ user) {
	v, err := s.exec.Migrations(r.Context(), r.PathValue("id"))
	respond(w, v, err)
}
func (s *Server) vmDiff(w http.ResponseWriter, r *http.Request, _ user) {
	v, err := s.exec.Diff(r.Context(), r.PathValue("id"))
	respond(w, v, err)
}
func (s *Server) vmHistory(w http.ResponseWriter, r *http.Request, _ user) {
	v, err := s.exec.History(r.Context(), r.PathValue("id"))
	respond(w, v, err)
}

func (s *Server) listDeploys(w http.ResponseWriter, _ *http.Request, _ user) { writeJSON(w, 200, s.store.List()) }
func (s *Server) getDeploy(w http.ResponseWriter, r *http.Request, _ user) {
	if req, ok := s.store.Get(r.PathValue("id")); ok {
		writeJSON(w, 200, req)
	} else {
		writeErr(w, 404, "pedido nao encontrado")
	}
}

func (s *Server) createDeploy(w http.ResponseWriter, r *http.Request, u user) {
	var body struct{ VM, Branch string }
	_ = json.NewDecoder(r.Body).Decode(&body)
	vm, ok := findVM(s.fleet, body.VM)
	if !ok {
		writeErr(w, 404, "VM nao existe")
		return
	}
	if fz, frozen := s.freeze.IsFrozen(vm.ID); frozen {
		s.audit.Append("deploy_blocked_frozen", u.name, vm.ID, map[string]any{"scope": fz.Scope, "message": fz.Message})
		writeErr(w, 409, "VM congelada ("+fz.Scope+"): "+freezeReason(fz))
		return
	}
	branch := body.Branch
	if branch == "" {
		branch = vm.Branch
	}
	mig, _ := s.exec.Migrations(r.Context(), vm.ID)
	diff, _ := s.exec.Diff(r.Context(), vm.ID)
	now := s.now().UTC()
	req := s.store.Create(types.DeployRequest{
		VM: vm.ID, Branch: branch, TargetSHA: diff.TargetSHA, CurrentSHA: diff.CurrentSHA,
		RequestedBy: u.name, // FIX bug #1: vem do usuario autenticado, NUNCA do body
		Status:      types.StatusPending, Migrations: mig.Pending, HasDestructive: mig.HasDestructive,
		CreatedAt: now.Format(time.RFC3339), ExpiresAt: now.Add(s.ttl).Format(time.RFC3339),
	})
	s.audit.Append("propose_deploy", u.name, vm.ID, map[string]any{"id": req.ID, "branch": branch})
	writeJSON(w, 200, req)
}

func (s *Server) approve(w http.ResponseWriter, r *http.Request, u user) {
	req, ok := s.store.Get(r.PathValue("id"))
	if !ok {
		writeErr(w, 404, "pedido nao encontrado")
		return
	}
	if req.Status != types.StatusPending {
		writeErr(w, 409, "pedido ja esta "+string(req.Status))
		return
	}
	if exp, err := time.Parse(time.RFC3339, req.ExpiresAt); err == nil && s.now().After(exp) {
		s.store.Update(req.ID, func(r *types.DeployRequest) { r.Status = types.StatusExpired })
		writeErr(w, 409, "pedido expirou")
		return
	}
	if req.RequestedBy == u.name { // anti self-review (fix bug #1)
		writeErr(w, 403, "anti self-review: quem pede nao pode aprovar o proprio deploy")
		return
	}
	s.store.Update(req.ID, func(r *types.DeployRequest) {
		r.Status = types.StatusExecuting
		r.ApprovedBy = u.name
		r.ApprovedAt = s.now().UTC().Format(time.RFC3339)
	})
	s.audit.Append("approve_deploy", u.name, req.VM, map[string]any{"id": req.ID})
	// Deploy ASSÍNCRONO: o pipeline (precompile/migrate) leva minutos; rodar síncrono
	// estouraria o timeout HTTP e o cancelamento mataria o deploy no meio. Roda em
	// background com contexto próprio; o painel acompanha pelo status do pedido.
	go func(id, vmID, sha, approver string) {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
		defer cancel()
		okDeploy, detail := s.exec.ApproveAndDeploy(ctx, vmID, sha, approver)
		s.store.Update(id, func(r *types.DeployRequest) {
			if okDeploy {
				r.Status = types.StatusSuccess
			} else {
				r.Status = types.StatusFailed
			}
			r.FinishedAt = s.now().UTC().Format(time.RFC3339)
			r.ResultDetail = detail
		})
		s.audit.Append(map[bool]string{true: "deploy_success", false: "deploy_failed"}[okDeploy], approver, vmID, map[string]any{"id": id})
	}(req.ID, req.VM, req.TargetSHA, u.name)
	executing, _ := s.store.Get(req.ID)
	writeJSON(w, 202, executing) // 202 Accepted — em execução; acompanhe pelo status
}

func (s *Server) reject(w http.ResponseWriter, r *http.Request, u user) {
	updated, ok := s.store.Update(r.PathValue("id"), func(rq *types.DeployRequest) {
		rq.Status = types.StatusRejected
		rq.FinishedAt = s.now().UTC().Format(time.RFC3339)
	})
	if !ok {
		writeErr(w, 404, "pedido nao encontrado")
		return
	}
	s.audit.Append("reject_deploy", u.name, updated.VM, map[string]any{"id": updated.ID})
	writeJSON(w, 200, updated)
}

// cancel cancela um pedido AINDA pending. Diferente de reject (admin): cancel e
// operator+, e o proprio solicitante pode cancelar o seu pedido — isso NAO fere
// anti-self-review (anti-self-review veta aprovar o proprio deploy, nao cancelar).
func (s *Server) cancel(w http.ResponseWriter, r *http.Request, u user) {
	req, ok := s.store.Get(r.PathValue("id"))
	if !ok {
		writeErr(w, 404, "pedido nao encontrado")
		return
	}
	if req.Status != types.StatusPending {
		writeErr(w, 409, "so cancela pendente; pedido ja esta "+string(req.Status))
		return
	}
	// separação de deveres: só o solicitante (ou um admin) cancela o pedido.
	if req.RequestedBy != u.name && u.role < RoleAdmin {
		writeErr(w, 403, "só o solicitante do pedido (ou um admin) pode cancelá-lo")
		return
	}
	updated, _ := s.store.Update(req.ID, func(rq *types.DeployRequest) {
		rq.Status = types.StatusRejected
		rq.FinishedAt = s.now().UTC().Format(time.RFC3339)
		rq.ResultDetail = "cancelado por " + u.name
	})
	s.audit.Append("cancel_deploy", u.name, updated.VM, map[string]any{"id": updated.ID})
	writeJSON(w, 200, updated)
}

func (s *Server) listFreeze(w http.ResponseWriter, _ *http.Request, _ user) {
	writeJSON(w, 200, s.freeze.List())
}

func (s *Server) doFreeze(w http.ResponseWriter, r *http.Request, u user) {
	var body struct{ Scope, Message string }
	_ = json.NewDecoder(r.Body).Decode(&body)
	scope := strings.TrimSpace(body.Scope)
	if scope == "" {
		writeErr(w, 400, "scope obrigatorio (id de VM ou 'all')")
		return
	}
	if scope != FreezeScopeAll {
		if _, ok := findVM(s.fleet, scope); !ok {
			writeErr(w, 404, "scope invalido: VM nao existe (use um id de VM ou 'all')")
			return
		}
	}
	fz := s.freeze.Freeze(scope, body.Message, u.name)
	s.audit.Append("freeze", u.name, scope, map[string]any{"message": body.Message})
	writeJSON(w, 200, fz)
}

func (s *Server) doUnfreeze(w http.ResponseWriter, r *http.Request, u user) {
	var body struct{ Scope string }
	_ = json.NewDecoder(r.Body).Decode(&body)
	scope := strings.TrimSpace(body.Scope)
	if scope == "" {
		writeErr(w, 400, "scope obrigatorio (id de VM ou 'all')")
		return
	}
	if !s.freeze.Unfreeze(scope) {
		writeErr(w, 404, "escopo nao estava congelado")
		return
	}
	s.audit.Append("unfreeze", u.name, scope, nil)
	writeJSON(w, 200, map[string]any{"scope": scope, "frozen": false})
}

// ---- helpers ----

func freezeReason(f Freeze) string {
	if f.Message != "" {
		return f.Message
	}
	return "deploys suspensos"
}

func findVM(f *types.Fleet, id string) (types.VM, bool) {
	for _, v := range f.VMs {
		if v.ID == id {
			return v, true
		}
	}
	return types.VM{}, false
}

func respond(w http.ResponseWriter, v any, err error) {
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, v)
}

// ---------- auth de humano (login email+senha + convite por email) ----------

func roleName(r Role) string {
	switch r {
	case RoleAdmin:
		return "admin"
	case RoleOperator:
		return "operator"
	default:
		return "viewer"
	}
}

func (s *Server) setSessionCookie(w http.ResponseWriter, email, role string) {
	http.SetCookie(w, &http.Cookie{Name: "alm_session", Value: s.issueSession(email, role), Path: "/", HttpOnly: true, Secure: true, SameSite: http.SameSiteLaxMode, MaxAge: int(sessionTTL.Seconds())})
}

// loginLimiter: trava simples por IP contra brute-force (janela deslizante 5min).
type loginLimiter struct {
	mu   sync.Mutex
	hits map[string][]int64
}

var loginThrottle = &loginLimiter{hits: map[string][]int64{}}

func clientIP(r *http.Request) string {
	if ip := r.Header.Get("CF-Connecting-IP"); ip != "" {
		return ip
	}
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.Split(xff, ",")[0])
	}
	ip := r.RemoteAddr
	if i := strings.LastIndex(ip, ":"); i > 0 {
		ip = ip[:i]
	}
	return ip
}

func (l *loginLimiter) blocked(ip string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	cutoff := now.Add(-5 * time.Minute).Unix()
	kept := l.hits[ip][:0]
	for _, t := range l.hits[ip] {
		if t >= cutoff {
			kept = append(kept, t)
		}
	}
	l.hits[ip] = kept
	return len(kept) >= 8 // 8 falhas em 5min -> 429
}

func (l *loginLimiter) fail(ip string, now time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.hits[ip] = append(l.hits[ip], now.Unix())
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	ip := clientIP(r)
	if loginThrottle.blocked(ip, s.now()) {
		writeErr(w, 429, "muitas tentativas de login — aguarde alguns minutos")
		return
	}
	var b struct{ Email, Password string }
	_ = json.NewDecoder(r.Body).Decode(&b)
	u, err := s.users.Authenticate(b.Email, b.Password)
	if err != nil {
		loginThrottle.fail(ip, s.now())
		writeErr(w, 401, "email ou senha inválidos")
		return
	}
	s.setSessionCookie(w, u.Email, u.Role)
	s.audit.Append("login", u.Email, "", nil)
	writeJSON(w, 200, map[string]string{"email": u.Email, "name": u.Name, "role": u.Role})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{Name: "alm_session", Value: "", Path: "/", HttpOnly: true, Secure: true, MaxAge: -1})
	writeJSON(w, 200, map[string]string{"status": "ok"})
}

func (s *Server) setPassword(w http.ResponseWriter, r *http.Request) {
	var b struct{ Token, Password string }
	_ = json.NewDecoder(r.Body).Decode(&b)
	u, err := s.users.SetPassword(b.Token, b.Password)
	if err != nil {
		writeErr(w, 400, err.Error())
		return
	}
	s.setSessionCookie(w, u.Email, u.Role)
	writeJSON(w, 200, map[string]string{"email": u.Email, "name": u.Name, "role": u.Role})
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	if c, e := r.Cookie("alm_session"); e == nil {
		if su, ok := s.verifySession(c.Value); ok {
			vms, _ := s.users.VMsOf(su.name)
			writeJSON(w, 200, map[string]any{"name": su.name, "role": roleName(su.role), "auth": "session", "vms": vms})
			return
		}
	}
	tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if u, ok := s.tokens[tok]; ok {
		vms, _ := s.users.VMsOf(u.name)
		writeJSON(w, 200, map[string]any{"name": u.name, "role": roleName(u.role), "auth": "token", "vms": vms})
		return
	}
	if t, ok := s.tstore.Lookup(tok); ok {
		vms, _ := s.users.VMsOf(t.Name)
		writeJSON(w, 200, map[string]any{"name": t.Name, "role": t.Role, "auth": "token", "vms": vms})
		return
	}
	writeErr(w, 401, "nao autenticado")
}

func (s *Server) listUsers(w http.ResponseWriter, _ *http.Request, _ user) { writeJSON(w, 200, s.users.List()) }

func (s *Server) inviteUser(w http.ResponseWriter, r *http.Request, u user) {
	var b struct{ Email, Name, Role string }
	_ = json.NewDecoder(r.Body).Decode(&b)
	role := b.Role
	if role == "" {
		role = "operator"
	}
	au, tok, err := s.users.Invite(b.Email, b.Name, role, u.name)
	if err != nil {
		writeErr(w, 400, err.Error())
		return
	}
	link := s.appURL + "/?setpw=" + tok
	s.audit.Append("invite_user", u.name, au.Email, map[string]any{"role": role})
	if err := s.mailer.Send(au.Email, "Almirante — defina sua senha", inviteHTML(au.Name, link)); err != nil {
		writeJSON(w, 200, map[string]any{"email": au.Email, "status": "invited", "email_error": err.Error(), "link": link})
		return
	}
	writeJSON(w, 200, map[string]string{"email": au.Email, "status": "invited"})
}

func (s *Server) revokeUser(w http.ResponseWriter, r *http.Request, u user) {
	if s.users.Delete(r.PathValue("id")) {
		s.audit.Append("delete_user", u.name, r.PathValue("id"), nil)
		writeJSON(w, 200, map[string]string{"status": "deleted"})
		return
	}
	writeErr(w, 404, "usuario nao encontrado")
}

// setUserVMs define quais VMs um usuario pode gerenciar IA (vm_access). Vazio =
// por role (admin=todas, operator=nenhuma). So admin concede.
func (s *Server) setUserVMs(w http.ResponseWriter, r *http.Request, u user) {
	var b struct {
		VMs []string `json:"vms"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	id := r.PathValue("id")
	if !s.users.SetVMs(id, b.VMs) {
		writeErr(w, 404, "usuario nao encontrado")
		return
	}
	s.audit.Append("user_vms_set", u.name, id, map[string]any{"vms": b.VMs})
	writeJSON(w, 200, map[string]any{"id": id, "vms": b.VMs})
}

// UsersCount/BootstrapAdmin: usados pelo main p/ semear o 1o admin no boot.
func (s *Server) UsersCount() int { return s.users.Count() }
func (s *Server) BootstrapAdmin(email string) {
	au, tok, err := s.users.Invite(email, "Admin", "admin", "bootstrap")
	if err != nil {
		fmt.Fprintln(os.Stderr, "bootstrap admin:", err)
		return
	}
	link := s.appURL + "/?setpw=" + tok
	if err := s.mailer.Send(au.Email, "Almirante — defina sua senha (admin)", inviteHTML(au.Name, link)); err != nil {
		fmt.Fprintf(os.Stderr, "bootstrap admin %s: email falhou (%v) — link manual: %s\n", email, err, link)
	} else {
		fmt.Fprintf(os.Stderr, "bootstrap admin %s: convite enviado por email\n", email)
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}
