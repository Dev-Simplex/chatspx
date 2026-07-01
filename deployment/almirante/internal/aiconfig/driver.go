// Package aiconfig fala a REST de governanca de IA do ChatSPX (receptor do Paulo,
// namespace spx/ai_config) POR VM. Portado do noc-spxia (chatspx/driver.go), mas
// resolve baseURL/token/account_id de cada VM via um Resolver (fleet + env),
// dispensando o DB/crypto do noc-spxia — o token vem em claro de AICONFIG_TOKEN_<slug>
// (secret do Coolify), no mesmo modelo dos secrets SSH do Almirante.
//
// Paths batidos (confirmados no receptor spx/ai_config):
//
//	GET  {base}/spx/ai_config/accounts/{aid}/assistants/{id}/baseline
//	POST {base}/spx/ai_config/change_sets/dry_run   body {change_set:{...}}
//	POST {base}/spx/ai_config/change_sets           body {change_set:{...}}
//	POST {base}/spx/ai_config/change_sets/{csid}/revert
//	POST {base}/spx/ai_config/test_credential        body {account_id,provider,settings,enabled}
//	POST {base}/spx/ai_config/perform_test           body {account_id,assistant_id,tool_id}
//	POST {base}/spx/ai_config/eval_prompt            body {account_id,assistant_id,instructions,scenario_ids,execute}
//	GET  {base}/api/v1/accounts/{aid}/captain/custom_tools
package aiconfig

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// JSONMap e o tipo generico das respostas do receptor.
type JSONMap = map[string]interface{}

// VMConn agrega o que o Driver precisa para um request a uma VM.
type VMConn struct {
	BaseURL   string
	Token     string // api_access_token em claro (so em memoria)
	AccountID int
}

// Resolver resolve a conexao de uma VM pelo slug (fleet + env no control).
type Resolver func(vmSlug string) (VMConn, error)

// Driver executa operacoes de governanca de IA contra o receptor ChatSPX de N VMs.
// Stateless por request: cada chamada resolve a VM.
type Driver struct {
	resolve Resolver
	http    *http.Client
}

// NewDriver cria o Driver ligado a um Resolver (fleet+env) e um timeout.
func NewDriver(resolve Resolver, timeout time.Duration) *Driver {
	if timeout <= 0 {
		timeout = 15 * time.Second
	}
	return &Driver{resolve: resolve, http: &http.Client{Timeout: timeout}}
}

// Available indica se o driver esta wired (resolver != nil).
func (d *Driver) Available() bool { return d != nil && d.resolve != nil }

// doMethod: verbo + corpo. path relativo ao baseURL. Header api_access_token
// (padrao Chatwoot, NAO Bearer). 2xx = ok; demais = *HTTPError.
func (d *Driver) doMethod(ctx context.Context, conn VMConn, method, path string, body, out any) error {
	var reqBody io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("aiconfig: marshal body: %w", err)
		}
		reqBody = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, conn.BaseURL+path, reqBody)
	if err != nil {
		return fmt.Errorf("aiconfig: build req: %w", err)
	}
	req.Header.Set("api_access_token", conn.Token)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := d.http.Do(req)
	if err != nil {
		return fmt.Errorf("aiconfig: do %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return &HTTPError{Status: resp.StatusCode, Path: path, Body: strings.TrimSpace(string(b))}
	}
	if out == nil {
		return nil
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("aiconfig: decode resp %s: %w", path, err)
	}
	return nil
}

// HTTPError carrega status + corpo de uma resposta nao-2xx do receptor.
type HTTPError struct {
	Status int
	Path   string
	Body   string
}

func (e *HTTPError) Error() string {
	return fmt.Sprintf("receptor http %d em %s: %s", e.Status, e.Path, e.Body)
}

// HTTPStatus permite ao test-gate enriquecer o report via errors.As.
func (e *HTTPError) HTTPStatus() int { return e.Status }

// ---------------------------------------------------------------------------
// Operacoes
// ---------------------------------------------------------------------------

// GetBaseline le a config viva de um assistant.
func (d *Driver) GetBaseline(ctx context.Context, vmSlug string, assistantID int) (JSONMap, error) {
	conn, err := d.resolve(vmSlug)
	if err != nil {
		return nil, err
	}
	path := fmt.Sprintf("/spx/ai_config/accounts/%d/assistants/%d/baseline", conn.AccountID, assistantID)
	var out JSONMap
	if err := d.doMethod(ctx, conn, http.MethodGet, path, nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// DryRun envia o change-set para preview/diff sem escrita.
func (d *Driver) DryRun(ctx context.Context, vmSlug string, changeSet JSONMap) (JSONMap, error) {
	conn, err := d.resolve(vmSlug)
	if err != nil {
		return nil, err
	}
	var out JSONMap
	if err := d.doMethod(ctx, conn, http.MethodPost, "/spx/ai_config/change_sets/dry_run",
		JSONMap{"change_set": changeSet}, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// Apply aplica o change-set (transacional/idempotente/auditado no receptor).
func (d *Driver) Apply(ctx context.Context, vmSlug string, changeSet JSONMap) (JSONMap, error) {
	conn, err := d.resolve(vmSlug)
	if err != nil {
		return nil, err
	}
	var out JSONMap
	if err := d.doMethod(ctx, conn, http.MethodPost, "/spx/ai_config/change_sets",
		JSONMap{"change_set": changeSet}, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// Revert restaura o snapshot de um change-set aplicado.
func (d *Driver) Revert(ctx context.Context, vmSlug, changeSetID string) (JSONMap, error) {
	conn, err := d.resolve(vmSlug)
	if err != nil {
		return nil, err
	}
	path := fmt.Sprintf("/spx/ai_config/change_sets/%s/revert", changeSetID)
	var out JSONMap
	if err := d.doMethod(ctx, conn, http.MethodPost, path, JSONMap{}, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// TestCredential testa as settings propostas contra o provider real, sem salvar.
func (d *Driver) TestCredential(ctx context.Context, vmSlug, provider string, settings JSONMap, enabled bool) (JSONMap, error) {
	conn, err := d.resolve(vmSlug)
	if err != nil {
		return nil, err
	}
	body := JSONMap{"account_id": conn.AccountID, "provider": provider, "settings": settings, "enabled": enabled}
	var out JSONMap
	if err := d.doMethod(ctx, conn, http.MethodPost, "/spx/ai_config/test_credential", body, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// PerformTest valida que a tool existe/esta disponivel pro assistant.
func (d *Driver) PerformTest(ctx context.Context, vmSlug string, assistantID int, toolID string) (JSONMap, error) {
	conn, err := d.resolve(vmSlug)
	if err != nil {
		return nil, err
	}
	body := JSONMap{"account_id": conn.AccountID, "assistant_id": assistantID, "tool_id": toolID}
	var out JSONMap
	if err := d.doMethod(ctx, conn, http.MethodPost, "/spx/ai_config/perform_test", body, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// EvalPrompt roda o agente contra captain_scenarios com o prompt candidato.
func (d *Driver) EvalPrompt(ctx context.Context, vmSlug string, assistantID int, instructions string, scenarioIDs []int, execute bool) (JSONMap, error) {
	conn, err := d.resolve(vmSlug)
	if err != nil {
		return nil, err
	}
	body := JSONMap{
		"account_id":   conn.AccountID,
		"assistant_id": assistantID,
		"instructions": instructions,
		"scenario_ids": scenarioIDs,
		"execute":      execute,
	}
	var out JSONMap
	if err := d.doMethod(ctx, conn, http.MethodPost, "/spx/ai_config/eval_prompt", body, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// ListCustomTools lista as custom tools da conta via a REST padrao do Chatwoot.
func (d *Driver) ListCustomTools(ctx context.Context, vmSlug string) (interface{}, error) {
	conn, err := d.resolve(vmSlug)
	if err != nil {
		return nil, err
	}
	path := fmt.Sprintf("/api/v1/accounts/%d/captain/custom_tools", conn.AccountID)
	var out interface{}
	if err := d.doMethod(ctx, conn, http.MethodGet, path, nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// AccountID resolve o account_id Chatwoot de uma VM.
func (d *Driver) AccountID(vmSlug string) (int, error) {
	conn, err := d.resolve(vmSlug)
	if err != nil {
		return 0, err
	}
	return conn.AccountID, nil
}
