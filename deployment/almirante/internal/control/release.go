package control

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/Dev-Simplex/almirante/internal/types"
)

// Release: rollout SEQUENCIAL health-gated pra um conjunto de VMs. Deploya uma de
// cada vez; se qualquer uma falhar (incl. health-check), PARA o rollout (as
// restantes ficam 'skipped') — nunca contamina a frota toda de uma vez.
// O admin que dispara É a autorizacao (gate por RBAC + auditoria); pensado pro
// botao "Release pra producao".

type ReleaseResult struct {
	VM        string `json:"vm"`
	Status    string `json:"status"` // pending|executing|success|failed|skipped
	Detail    string `json:"detail,omitempty"`
	RequestID string `json:"request_id,omitempty"`
}

type Release struct {
	ID        string          `json:"id"`
	Branch    string          `json:"branch,omitempty"`
	By        string          `json:"by"`
	Status    string          `json:"status"` // running|success|failed
	Results   []ReleaseResult `json:"results"`
	CreatedAt string          `json:"created_at"`
}

type releaseStore struct {
	mu  sync.Mutex
	seq int
	m   map[string]*Release
}

func newReleaseStore() *releaseStore { return &releaseStore{seq: 700, m: map[string]*Release{}} }

func (rs *releaseStore) create(by, branch string, vms []string, now string) *Release {
	rs.mu.Lock()
	defer rs.mu.Unlock()
	rs.seq++
	rel := &Release{ID: fmt.Sprintf("rel_%d", rs.seq), Branch: branch, By: by, Status: "running", CreatedAt: now}
	for _, v := range vms {
		rel.Results = append(rel.Results, ReleaseResult{VM: v, Status: "pending"})
	}
	rs.m[rel.ID] = rel
	return rel
}
func (rs *releaseStore) get(id string) (*Release, bool) {
	rs.mu.Lock()
	defer rs.mu.Unlock()
	r, ok := rs.m[id]
	return r, ok
}
func (rs *releaseStore) list() []*Release {
	rs.mu.Lock()
	defer rs.mu.Unlock()
	out := make([]*Release, 0, len(rs.m))
	for _, r := range rs.m {
		out = append(out, r)
	}
	return out
}

// set atualiza o resultado da VM no indice i (sob lock).
func (rs *releaseStore) set(rel *Release, i int, status, detail, reqID string) {
	rs.mu.Lock()
	defer rs.mu.Unlock()
	rel.Results[i].Status = status
	if detail != "" {
		rel.Results[i].Detail = detail
	}
	if reqID != "" {
		rel.Results[i].RequestID = reqID
	}
}
func (rs *releaseStore) setStatus(rel *Release, status string) {
	rs.mu.Lock()
	defer rs.mu.Unlock()
	rel.Status = status
}

// ---- handlers ----

// POST /api/release/dryrun {vms:[...], branch} — preview read-only (sem enfileirar).
func (s *Server) releaseDryRun(w http.ResponseWriter, r *http.Request, _ user) {
	var body struct {
		VMs    []string `json:"vms"`
		Branch string   `json:"branch"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	type row struct {
		VM         string `json:"vm"`
		CurrentSHA string `json:"current_sha"`
		TargetSHA  string `json:"target_sha"`
		Behind     int    `json:"behind"`
		Migrations int    `json:"migrations"`
		Destructive bool  `json:"destructive"`
		Frozen     bool   `json:"frozen"`
	}
	var out []row
	for _, id := range body.VMs {
		if _, ok := findVM(s.fleet, id); !ok {
			continue
		}
		d, _ := s.exec.Diff(r.Context(), id)
		m, _ := s.exec.Migrations(r.Context(), id)
		_, frozen := s.freeze.IsFrozen(id)
		out = append(out, row{id, d.CurrentSHA, d.TargetSHA, d.BehindCount, len(m.Pending), m.HasDestructive, frozen})
	}
	writeJSON(w, 200, out)
}

// POST /api/release {vms:[...], branch} — dispara o rollout sequencial (admin).
func (s *Server) createRelease(w http.ResponseWriter, r *http.Request, u user) {
	var body struct {
		VMs    []string `json:"vms"`
		Branch string   `json:"branch"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	var vms []string
	for _, id := range body.VMs {
		if _, ok := findVM(s.fleet, id); ok {
			vms = append(vms, id)
		}
	}
	if len(vms) == 0 {
		writeErr(w, 400, "nenhuma VM valida selecionada")
		return
	}
	rel := s.releases.create(u.name, body.Branch, vms, s.now().UTC().Format(time.RFC3339))
	s.audit.Append("release_start", u.name, "", map[string]any{"id": rel.ID, "vms": vms, "branch": body.Branch})
	go s.runRelease(rel, vms)
	writeJSON(w, 202, rel)
}

func (s *Server) getRelease(w http.ResponseWriter, r *http.Request, _ user) {
	if rel, ok := s.releases.get(r.PathValue("id")); ok {
		writeJSON(w, 200, rel)
	} else {
		writeErr(w, 404, "release nao encontrado")
	}
}
func (s *Server) listReleases(w http.ResponseWriter, _ *http.Request, _ user) {
	writeJSON(w, 200, s.releases.list())
}

// runRelease executa o rollout sequencial. Para no 1o erro (health-gate).
func (s *Server) runRelease(rel *Release, vms []string) {
	ctx := context.Background()
	for i, vmID := range vms {
		if fz, frozen := s.freeze.IsFrozen(vmID); frozen {
			s.releases.set(rel, i, "skipped", "congelada: "+freezeReason(fz), "")
			continue
		}
		diff, _ := s.exec.Diff(ctx, vmID)
		now := s.now().UTC()
		req := s.store.Create(types.DeployRequest{
			VM: vmID, Branch: rel.Branch, TargetSHA: diff.TargetSHA, CurrentSHA: diff.CurrentSHA,
			RequestedBy: rel.By, ApprovedBy: rel.By, Status: types.StatusExecuting,
			CreatedAt: now.Format(time.RFC3339), ApprovedAt: now.Format(time.RFC3339),
		})
		s.releases.set(rel, i, "executing", "", req.ID)

		dctx, cancel := context.WithTimeout(ctx, 30*time.Minute)
		ok, detail := s.exec.ApproveAndDeploy(dctx, vmID, diff.TargetSHA, rel.By)
		cancel()

		st, rst := types.StatusSuccess, "success"
		if !ok {
			st, rst = types.StatusFailed, "failed"
		}
		s.store.Update(req.ID, func(r *types.DeployRequest) {
			r.Status = st
			r.FinishedAt = s.now().UTC().Format(time.RFC3339)
			r.ResultDetail = detail
		})
		s.releases.set(rel, i, rst, detail, req.ID)
		s.audit.Append("release_deploy", rel.By, vmID, map[string]any{"release": rel.ID, "ok": ok})

		if !ok {
			s.releases.setStatus(rel, "failed")
			for j := i + 1; j < len(vms); j++ {
				s.releases.set(rel, j, "skipped", "rollout parado: "+vmID+" falhou", "")
			}
			return
		}
	}
	s.releases.setStatus(rel, "success")
}
