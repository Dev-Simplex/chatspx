// Package mcptools registra as tools do MCP do Almirante a partir de uma Source.
// Usado por dois hosts: o binario stdio (cmd/almirante-mcp, lado do dev) e o
// MCP HTTP hospedado no control (1 comando pra plugar, sem binario).
package mcptools

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/Dev-Simplex/almirante/internal/types"
)

// Source: de onde o MCP le/propoe/gerencia. So le e so propoe — nao existe approve.
type Source interface {
	Status(vm string) (types.HostStatus, error)
	Health(vm string) (types.HealthReport, error)
	Migrations(vm string) (types.MigrationStatus, error)
	Diff(vm string) (types.GitDiff, error)
	History(vm string) ([]types.DeployHistoryEntry, error)
	Propose(vm, branch string) (types.DeployRequest, error)
	ListPending() ([]types.DeployRequest, error)
	GetRequest(id string) (types.DeployRequest, error)
	Freeze(scope, message string) error
	Unfreeze(scope string) error
	Frozen() (string, error)
	Cancel(id string) error
	ProposeMerge(from, to string) (string, error)
	// Governanca de IA (editar prompt/tools/credencial/FAQ dos agentes por VM).
	AIListAgents() (any, error)
	AIListAssistants(vm string) (any, error)
	AIBaseline(vm string, id int) (any, error)
	AICustomTools(vm string) (any, error)
	AIHistory(vm string) (any, error)
	AIPrompt(vm string, id int, instructions, targetEnv string) (any, error)
	AITool(vm string, id int, toolID string, armed bool) (any, error)
	AICredential(vm, provider string, settings map[string]any, enabled bool) (any, error)
	AIBehavior(vm string, id int, behavior map[string]any) (any, error)
	AIFaq(vm string, id int, question, answer string) (any, error)
	AIEligibility(vm string, id int, inboxIDs []int) (any, error)
	AIRollback(vm, changeSetID string) (any, error)
}

// ---------- ControlSource (REST real) ----------
// Fala com o control via REST. Usado pelo MCP stdio do dev (base=painel.chatspx.app)
// e pelo MCP HTTP hospedado no control (base=loopback, token=do dev por request).

type ControlSource struct {
	base, token string
	hc          *http.Client
}

func NewControlSource(base, token string) *ControlSource {
	return &ControlSource{base: base, token: token, hc: &http.Client{Timeout: 30 * time.Second}}
}

func (c *ControlSource) get(path string, out any) error {
	req, _ := http.NewRequest("GET", c.base+path, nil)
	return c.do(req, out)
}
func (c *ControlSource) post(path string, body any, out any) error {
	var r *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	} else {
		r = bytes.NewReader(nil)
	}
	req, _ := http.NewRequest("POST", c.base+path, r)
	req.Header.Set("Content-Type", "application/json")
	return c.do(req, out)
}

func deviceID() string {
	h, _ := os.Hostname()
	u := os.Getenv("USER")
	if u == "" {
		u = os.Getenv("USERNAME") // windows
	}
	if h == "" {
		h = "?"
	}
	if u == "" {
		u = "?"
	}
	return h + "/" + u
}

func (c *ControlSource) do(req *http.Request, out any) error {
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("X-Almirante-Host", deviceID()) // audita o dispositivo do dev
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		var e struct {
			Error string `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&e)
		if e.Error != "" {
			return fmt.Errorf("%s", e.Error)
		}
		return fmt.Errorf("control %d em %s", resp.StatusCode, req.URL.Path)
	}
	if out == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (c *ControlSource) Status(vm string) (types.HostStatus, error) {
	var v types.HostStatus
	return v, c.get("/api/vms/"+vm+"/status", &v)
}
func (c *ControlSource) Health(vm string) (types.HealthReport, error) {
	var v types.HealthReport
	return v, c.get("/api/vms/"+vm+"/health", &v)
}
func (c *ControlSource) Migrations(vm string) (types.MigrationStatus, error) {
	var v types.MigrationStatus
	return v, c.get("/api/vms/"+vm+"/migrations", &v)
}
func (c *ControlSource) Diff(vm string) (types.GitDiff, error) {
	var v types.GitDiff
	return v, c.get("/api/vms/"+vm+"/diff", &v)
}
func (c *ControlSource) History(vm string) ([]types.DeployHistoryEntry, error) {
	var v []types.DeployHistoryEntry
	return v, c.get("/api/vms/"+vm+"/history", &v)
}
func (c *ControlSource) Propose(vm, branch string) (types.DeployRequest, error) {
	var v types.DeployRequest
	return v, c.post("/api/deploys", map[string]string{"vm": vm, "branch": branch}, &v)
}
func (c *ControlSource) ListPending() ([]types.DeployRequest, error) {
	var all []types.DeployRequest
	if err := c.get("/api/deploys", &all); err != nil {
		return nil, err
	}
	var out []types.DeployRequest
	for _, r := range all {
		if r.Status == types.StatusPending {
			out = append(out, r)
		}
	}
	return out, nil
}
func (c *ControlSource) GetRequest(id string) (types.DeployRequest, error) {
	var v types.DeployRequest
	return v, c.get("/api/deploys/"+id, &v)
}
func (c *ControlSource) Freeze(scope, message string) error {
	return c.post("/api/freeze", map[string]string{"scope": scope, "message": message}, nil)
}
func (c *ControlSource) Unfreeze(scope string) error {
	return c.post("/api/unfreeze", map[string]string{"scope": scope}, nil)
}
func (c *ControlSource) Frozen() (string, error) {
	var list []map[string]any
	if err := c.get("/api/freeze", &list); err != nil {
		return "", err
	}
	if len(list) == 0 {
		return "Nada congelado.", nil
	}
	var b strings.Builder
	b.WriteString("Congelados:\n")
	for _, f := range list {
		fmt.Fprintf(&b, "• %v — %v (por %v)\n", f["scope"], f["message"], f["by"])
	}
	return b.String(), nil
}
func (c *ControlSource) Cancel(id string) error {
	return c.post("/api/deploys/"+id+"/cancel", nil, nil)
}
func (c *ControlSource) ProposeMerge(from, to string) (string, error) {
	var v struct {
		ID, From, To, Status string
	}
	if err := c.post("/api/merges", map[string]string{"from": from, "to": to}, &v); err != nil {
		return "", err
	}
	return fmt.Sprintf("merge %s -> %s enfileirado (%s, %s) — aprovacao humana (admin) no painel.", v.From, v.To, v.ID, v.Status), nil
}

// ---------- Governanca de IA (REST /api/ai/*) ----------

func (c *ControlSource) AIListAgents() (any, error) {
	var v any
	return v, c.get("/api/ai/agents", &v)
}
func (c *ControlSource) AIListAssistants(vm string) (any, error) {
	var v any
	return v, c.get("/api/ai/assistants?vm="+vm, &v)
}
func (c *ControlSource) AIBaseline(vm string, id int) (any, error) {
	var v any
	return v, c.get(fmt.Sprintf("/api/ai/agents/%s/%d", vm, id), &v)
}
func (c *ControlSource) AICustomTools(vm string) (any, error) {
	var v any
	return v, c.get("/api/ai/custom-tools/"+vm, &v)
}
func (c *ControlSource) AIHistory(vm string) (any, error) {
	var v any
	return v, c.get("/api/ai/history?vm="+vm, &v)
}
func (c *ControlSource) AIPrompt(vm string, id int, instructions, targetEnv string) (any, error) {
	var v any
	return v, c.post("/api/ai/prompt", map[string]any{"vm": vm, "assistant_id": id, "instructions": instructions, "target_env": targetEnv}, &v)
}
func (c *ControlSource) AITool(vm string, id int, toolID string, armed bool) (any, error) {
	var v any
	return v, c.post("/api/ai/tool", map[string]any{"vm": vm, "assistant_id": id, "tool_id": toolID, "armed": armed}, &v)
}
func (c *ControlSource) AICredential(vm, provider string, settings map[string]any, enabled bool) (any, error) {
	var v any
	return v, c.post("/api/ai/credential", map[string]any{"vm": vm, "provider": provider, "settings": settings, "enabled": enabled}, &v)
}
func (c *ControlSource) AIBehavior(vm string, id int, behavior map[string]any) (any, error) {
	var v any
	return v, c.post("/api/ai/behavior", map[string]any{"vm": vm, "assistant_id": id, "behavior": behavior}, &v)
}
func (c *ControlSource) AIFaq(vm string, id int, question, answer string) (any, error) {
	var v any
	return v, c.post("/api/ai/faq", map[string]any{"vm": vm, "assistant_id": id, "question": question, "answer": answer}, &v)
}
func (c *ControlSource) AIEligibility(vm string, id int, inboxIDs []int) (any, error) {
	var v any
	return v, c.post("/api/ai/eligibility", map[string]any{"vm": vm, "assistant_id": id, "inbox_ids": inboxIDs}, &v)
}
func (c *ControlSource) AIRollback(vm, changeSetID string) (any, error) {
	var v any
	return v, c.post("/api/ai/rollback", map[string]any{"vm": vm, "change_set_id": changeSetID}, &v)
}
