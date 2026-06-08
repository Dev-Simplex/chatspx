package control

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/Dev-Simplex/almirante/internal/audit"
	"github.com/Dev-Simplex/almirante/internal/fleet"
)

func newTestServer(t *testing.T) http.Handler {
	t.Helper()
	f, err := fleet.Load("../../fleet.json")
	if err != nil {
		t.Fatalf("fleet: %v", err)
	}
	cfg := Config{Mock: true, Fleet: f, ApprovalTTL: time.Hour}
	store := NewStore(t.TempDir())
	aud := audit.New(t.TempDir() + "/audit.jsonl")
	tokens := "op-tok:ederson:operator,admin-paulo:paulo:admin,admin-ederson:ederson:admin"
	return NewServer(cfg, store, aud, tokens).Handler()
}

func req(t *testing.T, h http.Handler, method, path, token, body string) (int, string) {
	t.Helper()
	var r *http.Request
	if body != "" {
		r = httptest.NewRequest(method, path, strings.NewReader(body))
	} else {
		r = httptest.NewRequest(method, path, nil)
	}
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w.Code, w.Body.String()
}

func TestControlGate(t *testing.T) {
	h := newTestServer(t)

	// sem token -> 401
	if code, _ := req(t, h, "GET", "/api/fleet", "", ""); code != 401 {
		t.Fatalf("sem token deveria 401, veio %d", code)
	}

	// operator propoe (requested_by vem do TOKEN, ignora body spoof)
	code, body := req(t, h, "POST", "/api/deploys", "op-tok", `{"vm":"tozi","requested_by":"hacker"}`)
	if code != 200 {
		t.Fatalf("propose deveria 200, veio %d: %s", code, body)
	}
	var created struct {
		ID          string `json:"id"`
		RequestedBy string `json:"requested_by"`
	}
	_ = json.Unmarshal([]byte(body), &created)
	if created.RequestedBy != "ederson" {
		t.Fatalf("requested_by deveria ser 'ederson' (do token), veio %q — body spoof nao bloqueado", created.RequestedBy)
	}
	id := created.ID

	// operator NAO pode aprovar (role) -> 403
	if code, _ := req(t, h, "POST", "/api/deploys/"+id+"/approve", "op-tok", ""); code != 403 {
		t.Fatalf("operator aprovando deveria 403, veio %d", code)
	}

	// admin que e o PROPRIO solicitante (ederson) -> 403 anti self-review
	code, body = req(t, h, "POST", "/api/deploys/"+id+"/approve", "admin-ederson", "")
	if code != 403 || !strings.Contains(body, "self-review") {
		t.Fatalf("self-review deveria 403, veio %d: %s", code, body)
	}

	// admin diferente (paulo) -> 200 + success
	code, body = req(t, h, "POST", "/api/deploys/"+id+"/approve", "admin-paulo", "")
	if code != 200 || !strings.Contains(body, "success") {
		t.Fatalf("admin diferente deveria 200 success, veio %d: %s", code, body)
	}

	// migration_status da tozi marca destrutiva
	if _, b := req(t, h, "GET", "/api/vms/tozi/migrations", "op-tok", ""); !strings.Contains(b, `"destructive":true`) {
		t.Errorf("tozi deveria ter migration destrutiva: %s", b)
	}
}
