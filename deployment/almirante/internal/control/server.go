package control

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/Dev-Simplex/almirante/internal/audit"
	"github.com/Dev-Simplex/almirante/internal/types"
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
	exec     Executor
	audit    *audit.Logger
	tokens   map[string]user
	tstore   *TokenStore
	ttl      time.Duration
	now      func() time.Time
	mergeDir string
	repoURL  string
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
		exec:     Executor{Cfg: cfg},
		audit:    aud,
		tokens:   tokens,
		tstore:   NewTokenStore(store.StateDir()),
		ttl:      ttl,
		now:      time.Now,
		mergeDir: cfg.MergeCloneDir,
		repoURL:  cfg.RepoURL,
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
	mux.HandleFunc("POST /api/unfreeze", s.auth(RoleOperator, s.doUnfreeze))
	mux.HandleFunc("GET /api/merges", s.auth(RoleViewer, s.listMerges))
	mux.HandleFunc("POST /api/merges", s.auth(RoleOperator, s.proposeMerge))
	mux.HandleFunc("POST /api/merges/{id}/approve", s.auth(RoleAdmin, s.approveMerge))
	mux.HandleFunc("GET /api/tokens", s.auth(RoleAdmin, s.listTokens))
	mux.HandleFunc("POST /api/tokens", s.auth(RoleAdmin, s.issueToken))
	mux.HandleFunc("DELETE /api/tokens/{id}", s.auth(RoleAdmin, s.revokeToken))
	return mux
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
		if !ok {
			writeErr(w, 401, "token invalido")
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
	vm, _ := findVM(s.fleet, req.VM)
	okDeploy, detail := s.exec.ApproveAndDeploy(r.Context(), req.VM, req.TargetSHA, u.name)
	updated, _ := s.store.Update(req.ID, func(r *types.DeployRequest) {
		if okDeploy {
			r.Status = types.StatusSuccess
		} else {
			r.Status = types.StatusFailed
		}
		r.FinishedAt = s.now().UTC().Format(time.RFC3339)
		r.ResultDetail = detail
	})
	_ = vm
	s.audit.Append(map[bool]string{true: "deploy_success", false: "deploy_failed"}[okDeploy], u.name, req.VM, map[string]any{"id": req.ID})
	writeJSON(w, 200, updated)
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

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}
