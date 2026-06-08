package control

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/Dev-Simplex/almirante/internal/merge"
)

type MergeReq struct {
	ID          string `json:"id"`
	From        string `json:"from"`
	To          string `json:"to"`
	RequestedBy string `json:"requested_by"`
	Status      string `json:"status"` // pending | success | failed
	ApprovedBy  string `json:"approved_by,omitempty"`
	Result      string `json:"result,omitempty"`
	CreatedAt   string `json:"created_at"`
}

type mergeStore struct {
	mu  sync.Mutex
	seq int
	m   map[string]*MergeReq
}

func newMergeStore() *mergeStore { return &mergeStore{seq: 900, m: map[string]*MergeReq{}} }

func (ms *mergeStore) create(from, to, by string) *MergeReq {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	ms.seq++
	r := &MergeReq{ID: fmt.Sprintf("mrg_%d", ms.seq), From: from, To: to, RequestedBy: by, Status: "pending", CreatedAt: time.Now().UTC().Format(time.RFC3339)}
	ms.m[r.ID] = r
	return r
}
func (ms *mergeStore) get(id string) (*MergeReq, bool) {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	r, ok := ms.m[id]
	return r, ok
}
func (ms *mergeStore) list() []*MergeReq {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	out := make([]*MergeReq, 0, len(ms.m))
	for _, r := range ms.m {
		out = append(out, r)
	}
	return out
}

// POST /api/merges {from,to} — propoe (operator+). So enfileira; nao executa.
func (s *Server) proposeMerge(w http.ResponseWriter, r *http.Request, u user) {
	var body struct{ From, To string }
	_ = json.NewDecoder(r.Body).Decode(&body)
	if !merge.IsAllowed(body.From, body.To) {
		writeErr(w, 400, "merge nao permitido. Fluxos: "+fmt.Sprint(merge.Flows()))
		return
	}
	req := s.merges.create(body.From, body.To, u.name)
	s.audit.Append("propose_merge", u.name, "", map[string]any{"id": req.ID, "from": body.From, "to": body.To})
	writeJSON(w, 200, req)
}

// POST /api/merges/{id}/approve — admin+ e NAO o solicitante -> executa o merge+push.
func (s *Server) approveMerge(w http.ResponseWriter, r *http.Request, u user) {
	req, ok := s.merges.get(r.PathValue("id"))
	if !ok {
		writeErr(w, 404, "merge nao encontrado")
		return
	}
	if req.Status != "pending" {
		writeErr(w, 409, "merge ja esta "+req.Status)
		return
	}
	if req.RequestedBy == u.name {
		writeErr(w, 403, "anti self-review: quem pede nao pode aprovar o proprio merge")
		return
	}
	s.audit.Append("approve_merge", u.name, "", map[string]any{"id": req.ID})

	var result string
	var err error
	if s.exec.Cfg.Mock {
		result = fmt.Sprintf("[MOCK] merge %s -> %s aprovado por %s", req.From, req.To, u.name)
	} else {
		result, err = merge.Run(s.mergeDir, s.repoURL, req.From, req.To)
	}
	ms := s.merges
	ms.mu.Lock()
	if err != nil {
		req.Status, req.Result = "failed", err.Error()
	} else {
		req.Status, req.Result, req.ApprovedBy = "success", result, u.name
	}
	ms.mu.Unlock()
	s.audit.Append(map[bool]string{true: "merge_failed", false: "merge_success"}[err != nil], u.name, "", map[string]any{"id": req.ID})
	writeJSON(w, 200, req)
}

// GET /api/merges — lista (viewer+).
func (s *Server) listMerges(w http.ResponseWriter, _ *http.Request, _ user) {
	writeJSON(w, 200, s.merges.list())
}
