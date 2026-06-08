package control

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

// proposeID propoe um deploy e devolve o id criado (helper de teste).
func proposeID(t *testing.T, h http.Handler, vm string) (int, string, string) {
	t.Helper()
	code, body := req(t, h, "POST", "/api/deploys", "op-tok", `{"vm":"`+vm+`"}`)
	if code != 200 {
		return code, "", body
	}
	var created struct {
		ID string `json:"id"`
	}
	_ = json.Unmarshal([]byte(body), &created)
	return code, created.ID, body
}

// fluxo completo: freeze (VM) -> createDeploy bloqueado -> unfreeze -> ok.
func TestFreezeBlocksDeployThenUnfreeze(t *testing.T) {
	h := newTestServer(t)

	// viewer NAO pode congelar -> 403 (mas o teste so tem operator+/admin; usa role)
	// operator congela a tozi
	if code, body := req(t, h, "POST", "/api/freeze", "op-tok", `{"scope":"tozi","message":"manutencao"}`); code != 200 {
		t.Fatalf("freeze deveria 200, veio %d: %s", code, body)
	}

	// GET /api/freeze lista o congelamento (viewer+, usa operator)
	code, body := req(t, h, "GET", "/api/freeze", "op-tok", "")
	if code != 200 || !strings.Contains(body, `"scope":"tozi"`) || !strings.Contains(body, "manutencao") {
		t.Fatalf("list freeze deveria conter tozi/manutencao, veio %d: %s", code, body)
	}

	// createDeploy na tozi -> 409 congelada
	code, _, body = proposeID(t, h, "tozi")
	if code != 409 || !strings.Contains(body, "congelada") {
		t.Fatalf("deploy em VM congelada deveria 409, veio %d: %s", code, body)
	}

	// outra VM NAO congelada -> 200
	if code, id, body := proposeID(t, h, "fabrica"); code != 200 || id == "" {
		t.Fatalf("deploy em VM nao congelada deveria 200, veio %d: %s", code, body)
	}

	// unfreeze tozi
	if code, body := req(t, h, "POST", "/api/unfreeze", "op-tok", `{"scope":"tozi"}`); code != 200 {
		t.Fatalf("unfreeze deveria 200, veio %d: %s", code, body)
	}

	// agora deploy na tozi -> 200
	code, id, body := proposeID(t, h, "tozi")
	if code != 200 || id == "" {
		t.Fatalf("deploy apos unfreeze deveria 200, veio %d: %s", code, body)
	}
}

// escopo 'all' congela a frota inteira.
func TestFreezeAllScope(t *testing.T) {
	h := newTestServer(t)

	if code, body := req(t, h, "POST", "/api/freeze", "op-tok", `{"scope":"all"}`); code != 200 {
		t.Fatalf("freeze all deveria 200, veio %d: %s", code, body)
	}

	// qualquer VM bloqueada
	for _, vm := range []string{"tozi", "fabrica", "producao"} {
		if code, _, body := proposeID(t, h, vm); code != 409 {
			t.Fatalf("com freeze all, deploy em %s deveria 409, veio %d: %s", vm, code, body)
		}
	}

	// unfreeze all libera
	if code, body := req(t, h, "POST", "/api/unfreeze", "op-tok", `{"scope":"all"}`); code != 200 {
		t.Fatalf("unfreeze all deveria 200, veio %d: %s", code, body)
	}
	if code, id, body := proposeID(t, h, "tozi"); code != 200 || id == "" {
		t.Fatalf("deploy apos unfreeze all deveria 200, veio %d: %s", code, body)
	}
}

// freeze exige RBAC operator+ e scope valido.
func TestFreezeValidation(t *testing.T) {
	h := newTestServer(t)

	// sem token -> 401
	if code, _ := req(t, h, "POST", "/api/freeze", "", `{"scope":"tozi"}`); code != 401 {
		t.Fatalf("freeze sem token deveria 401, veio %d", code)
	}
	// scope vazio -> 400
	if code, _ := req(t, h, "POST", "/api/freeze", "op-tok", `{"scope":""}`); code != 400 {
		t.Fatalf("scope vazio deveria 400, veio %d", code)
	}
	// scope de VM inexistente -> 404
	if code, _ := req(t, h, "POST", "/api/freeze", "op-tok", `{"scope":"naoexiste"}`); code != 404 {
		t.Fatalf("scope invalido deveria 404, veio %d", code)
	}
	// unfreeze de escopo que nao estava congelado -> 404
	if code, _ := req(t, h, "POST", "/api/unfreeze", "op-tok", `{"scope":"tozi"}`); code != 404 {
		t.Fatalf("unfreeze de nao-congelado deveria 404, veio %d", code)
	}
}

// cancel de um pedido pending: operator+ cancela; nao re-cancela.
func TestCancelPending(t *testing.T) {
	h := newTestServer(t)

	code, id, body := proposeID(t, h, "fabrica")
	if code != 200 || id == "" {
		t.Fatalf("propose deveria 200, veio %d: %s", code, body)
	}

	// cancel -> 200, fica rejected
	code, body = req(t, h, "POST", "/api/deploys/"+id+"/cancel", "op-tok", "")
	if code != 200 || !strings.Contains(body, `"status":"rejected"`) {
		t.Fatalf("cancel deveria 200/rejected, veio %d: %s", code, body)
	}

	// cancel de novo (ja nao pending) -> 409
	if code, _ := req(t, h, "POST", "/api/deploys/"+id+"/cancel", "op-tok", ""); code != 409 {
		t.Fatalf("cancel de nao-pendente deveria 409, veio %d", code)
	}

	// cancel de id inexistente -> 404
	if code, _ := req(t, h, "POST", "/api/deploys/req_999999/cancel", "op-tok", ""); code != 404 {
		t.Fatalf("cancel de id inexistente deveria 404, veio %d", code)
	}
}

// cancel NAO fere anti-self-review: quem propos pode cancelar o proprio pedido.
func TestCancelOwnDeployAllowed(t *testing.T) {
	h := newTestServer(t)
	code, id, body := proposeID(t, h, "fabrica") // requested_by = ederson (do op-tok)
	if code != 200 {
		t.Fatalf("propose deveria 200, veio %d: %s", code, body)
	}
	// op-tok (ederson) e o proprio solicitante e mesmo assim cancela -> 200
	if code, body := req(t, h, "POST", "/api/deploys/"+id+"/cancel", "op-tok", ""); code != 200 {
		t.Fatalf("solicitante cancelando o proprio pedido deveria 200, veio %d: %s", code, body)
	}
}

// FreezeStore: testes de unidade (persistencia + precedencia + List).
func TestFreezeStoreUnit(t *testing.T) {
	dir := t.TempDir()
	fs := NewFreezeStore(dir)

	if _, ok := fs.IsFrozen("tozi"); ok {
		t.Fatal("nada deveria estar congelado no inicio")
	}

	fs.Freeze("tozi", "deploy quebrado", "ederson")
	if f, ok := fs.IsFrozen("tozi"); !ok || f.By != "ederson" || f.Message != "deploy quebrado" {
		t.Fatalf("tozi deveria estar congelada com metadados, veio %+v ok=%v", f, ok)
	}
	// outra VM nao afetada
	if _, ok := fs.IsFrozen("fabrica"); ok {
		t.Fatal("fabrica nao deveria estar congelada")
	}

	// escopo 'all' congela todas
	fs.Freeze(FreezeScopeAll, "freeze geral", "paulo")
	if _, ok := fs.IsFrozen("fabrica"); !ok {
		t.Fatal("com 'all', fabrica deveria estar congelada")
	}
	// precedencia: id especifico ganha do 'all'
	if f, _ := fs.IsFrozen("tozi"); f.Scope != "tozi" {
		t.Fatalf("id especifico deveria ter precedencia sobre 'all', veio scope=%q", f.Scope)
	}

	if got := len(fs.List()); got != 2 {
		t.Fatalf("List deveria ter 2 congelamentos, veio %d", got)
	}

	// persistencia: novo store le do disco
	fs2 := NewFreezeStore(dir)
	if _, ok := fs2.IsFrozen("tozi"); !ok {
		t.Fatal("congelamento deveria persistir entre instancias")
	}

	// unfreeze remove
	if !fs2.Unfreeze("tozi") {
		t.Fatal("unfreeze de congelado deveria retornar true")
	}
	if fs2.Unfreeze("tozi") {
		t.Fatal("unfreeze repetido deveria retornar false")
	}
	if f, _ := fs2.IsFrozen("tozi"); f.Scope != FreezeScopeAll {
		t.Fatalf("apos remover id, tozi deveria cair no 'all', veio scope=%q", f.Scope)
	}
}
