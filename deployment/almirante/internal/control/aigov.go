package control

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/Dev-Simplex/almirante/internal/aiconfig"
)

// aigov.go: governanca de IA (editar prompt/tools/credencial/FAQ dos agentes
// Captain de cada VM ChatSPX) via o receptor spx/ai_config. Modelo: admin
// ESCREVE DIRETO (sem fila de aprovacao), MAS sempre com test-gate ANTES +
// audit hash-chain + rollback. Espelha o RunWrite do noc-spxia, usando o audit
// e o AIStore do Almirante.

// ---- rotas registradas em server.go Handler() ----

// aiListAgents lista as VMs com governanca de IA habilitada (AIConfigURL setado).
func (s *Server) aiListAgents(w http.ResponseWriter, _ *http.Request, _ user) {
	type vmLite struct {
		ID        string `json:"id"`
		Name      string `json:"name"`
		Env       string `json:"env"`
		AccountID int    `json:"account_id"`
	}
	out := []vmLite{}
	for _, v := range s.fleet.VMs {
		if v.AIConfigURL != "" {
			out = append(out, vmLite{v.ID, v.Name, v.Env, v.AIConfigAccountID})
		}
	}
	writeJSON(w, 200, map[string]any{"vms": out})
}

// aiBaseline: config viva de um agente (GET /api/ai/agents/{vm}/{id}).
func (s *Server) aiBaseline(w http.ResponseWriter, r *http.Request, _ user) {
	if s.aidriver == nil || !s.aidriver.Available() {
		writeErr(w, 503, "governanca de IA nao configurada")
		return
	}
	vm := r.PathValue("vm")
	aid, err := strconv.Atoi(r.PathValue("id"))
	if err != nil || aid <= 0 {
		writeErr(w, 400, "assistant_id invalido")
		return
	}
	baseline, err := s.aidriver.GetBaseline(r.Context(), vm, aid)
	if err != nil {
		writeErr(w, 502, "baseline: "+err.Error())
		return
	}
	writeJSON(w, 200, baseline)
}

// aiCustomTools: custom tools da conta (GET /api/ai/custom-tools/{vm}).
func (s *Server) aiCustomTools(w http.ResponseWriter, r *http.Request, _ user) {
	if s.aidriver == nil || !s.aidriver.Available() {
		writeErr(w, 503, "governanca de IA nao configurada")
		return
	}
	tools, err := s.aidriver.ListCustomTools(r.Context(), r.PathValue("vm"))
	if err != nil {
		writeErr(w, 502, "custom_tools: "+err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"custom_tools": tools})
}

// aiListAssistants: agentes (id+name) de uma VM p/ o seletor de agente do
// painel (GET /api/ai/assistants?vm=). Devolve { assistants: [{id,name}] }.
func (s *Server) aiListAssistants(w http.ResponseWriter, r *http.Request, _ user) {
	if s.aidriver == nil || !s.aidriver.Available() {
		writeErr(w, 503, "governanca de IA nao configurada")
		return
	}
	vm := r.URL.Query().Get("vm")
	if vm == "" {
		writeErr(w, 400, "parametro vm obrigatorio")
		return
	}
	out, err := s.aidriver.ListAssistants(r.Context(), vm)
	if err != nil {
		writeErr(w, 502, "assistants: "+err.Error())
		return
	}
	writeJSON(w, 200, out)
}

// aiHistory: change-sets de IA da VM (GET /api/ai/history?vm=).
func (s *Server) aiHistory(w http.ResponseWriter, r *http.Request, _ user) {
	vm := r.URL.Query().Get("vm")
	limit := 100
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 {
			limit = n
		}
	}
	writeJSON(w, 200, map[string]any{"change_sets": s.aistore.ListByVM(vm, limit)})
}

// ---- escritas (Admin) ----

func (s *Server) aiPrompt(w http.ResponseWriter, r *http.Request, u user) {
	var b struct {
		VM           string `json:"vm"`
		AssistantID  int    `json:"assistant_id"`
		Instructions string `json:"instructions"`
		TargetEnv    string `json:"target_env"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.VM == "" || b.AssistantID <= 0 || b.Instructions == "" {
		writeErr(w, 400, "vm, assistant_id e instructions obrigatorios")
		return
	}
	ops := []map[string]interface{}{aiconfig.OpUpdateInstructions(b.AssistantID, b.Instructions)}
	code, res := s.applyAIWrite(r.Context(), u.name, b.VM, "update_instructions", "prompt", b.TargetEnv, b.AssistantID, ops)
	writeJSON(w, code, res)
}

func (s *Server) aiTool(w http.ResponseWriter, r *http.Request, u user) {
	var b struct {
		VM          string `json:"vm"`
		AssistantID int    `json:"assistant_id"`
		ToolID      string `json:"tool_id"`
		Armed       bool   `json:"armed"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.VM == "" || b.AssistantID <= 0 || b.ToolID == "" {
		writeErr(w, 400, "vm, assistant_id e tool_id obrigatorios")
		return
	}
	op, opType := aiconfig.OpToolArming(b.AssistantID, b.ToolID, b.Armed)
	code, res := s.applyAIWrite(r.Context(), u.name, b.VM, opType, "tool", "prod", b.AssistantID, []map[string]interface{}{op})
	writeJSON(w, code, res)
}

func (s *Server) aiCredential(w http.ResponseWriter, r *http.Request, u user) {
	var b struct {
		VM       string                 `json:"vm"`
		Provider string                 `json:"provider"`
		Settings map[string]interface{} `json:"settings"`
		Enabled  *bool                  `json:"enabled"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.VM == "" || b.Provider == "" || b.Settings == nil {
		writeErr(w, 400, "vm, provider e settings obrigatorios")
		return
	}
	enabled := true
	if b.Enabled != nil {
		enabled = *b.Enabled
	}
	ops := []map[string]interface{}{aiconfig.OpSetCredential(b.Provider, b.Settings, enabled)}
	code, res := s.applyAIWrite(r.Context(), u.name, b.VM, "set_credential", "credential", "prod", 0, ops)
	writeJSON(w, code, res)
}

func (s *Server) aiBehavior(w http.ResponseWriter, r *http.Request, u user) {
	var b struct {
		VM          string                 `json:"vm"`
		AssistantID int                    `json:"assistant_id"`
		Behavior    map[string]interface{} `json:"behavior"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.VM == "" || b.AssistantID <= 0 || b.Behavior == nil {
		writeErr(w, 400, "vm, assistant_id e behavior obrigatorios")
		return
	}
	ops := []map[string]interface{}{aiconfig.OpUpdateBehavior(b.AssistantID, b.Behavior)}
	code, res := s.applyAIWrite(r.Context(), u.name, b.VM, "update_behavior", "prompt", "prod", b.AssistantID, ops)
	writeJSON(w, code, res)
}

func (s *Server) aiFaq(w http.ResponseWriter, r *http.Request, u user) {
	var b struct {
		VM          string `json:"vm"`
		AssistantID int    `json:"assistant_id"`
		Question    string `json:"question"`
		Answer      string `json:"answer"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.VM == "" || b.AssistantID <= 0 || b.Question == "" || b.Answer == "" {
		writeErr(w, 400, "vm, assistant_id, question e answer obrigatorios")
		return
	}
	ops := []map[string]interface{}{aiconfig.OpAddFAQ(b.AssistantID, b.Question, b.Answer)}
	code, res := s.applyAIWrite(r.Context(), u.name, b.VM, "add_faq", "prompt", "prod", b.AssistantID, ops)
	writeJSON(w, code, res)
}

func (s *Server) aiEligibility(w http.ResponseWriter, r *http.Request, u user) {
	var b struct {
		VM          string `json:"vm"`
		AssistantID int    `json:"assistant_id"`
		InboxIDs    []int  `json:"inbox_ids"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.VM == "" || b.AssistantID <= 0 {
		writeErr(w, 400, "vm e assistant_id obrigatorios")
		return
	}
	ops := []map[string]interface{}{aiconfig.OpSetEligibility(b.AssistantID, b.InboxIDs)}
	code, res := s.applyAIWrite(r.Context(), u.name, b.VM, "set_eligibility", "eligibility", "prod", b.AssistantID, ops)
	writeJSON(w, code, res)
}

// aiRollback reverte um change-set aplicado (restaura o snapshot na VM).
func (s *Server) aiRollback(w http.ResponseWriter, r *http.Request, u user) {
	if s.aidriver == nil || !s.aidriver.Available() {
		writeErr(w, 503, "governanca de IA nao configurada")
		return
	}
	var b struct {
		VM          string `json:"vm"`
		ChangeSetID string `json:"change_set_id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&b)
	if b.VM == "" || b.ChangeSetID == "" {
		writeErr(w, 400, "vm e change_set_id obrigatorios")
		return
	}
	resp, err := s.aidriver.Revert(r.Context(), b.VM, b.ChangeSetID)
	if err != nil {
		s.audit.Append("ai_rollback_failed", u.name, b.VM, map[string]any{"change_set_id": b.ChangeSetID, "error": err.Error()})
		writeErr(w, 502, "revert falhou: "+err.Error())
		return
	}
	if rec, ok := s.aistore.FindByChangeSetID(b.ChangeSetID); ok {
		s.aistore.Update(rec.ID, func(c *AIChange) {
			c.Status = "reverted"
			c.RevertedAt = s.now().UTC().Format(time.RFC3339)
		})
	}
	s.audit.Append("ai_reverted", u.name, b.VM, map[string]any{"change_set_id": b.ChangeSetID})
	writeJSON(w, 200, map[string]any{"change_set_id": b.ChangeSetID, "status": "reverted", "receptor": resp})
}

// ---- ciclo canonico de escrita (§1): op -> test-gate -> apply -> audit ----

func (s *Server) applyAIWrite(ctx context.Context, actor, vm, opType, gateKind, targetEnv string, assistantID int, ops []map[string]interface{}) (int, map[string]any) {
	if s.aidriver == nil || !s.aidriver.Available() {
		return 503, map[string]any{"error": "governanca de IA nao configurada"}
	}
	accountID, err := s.aidriver.AccountID(vm)
	if err != nil {
		return 404, map[string]any{"error": "vm sem governanca de IA: " + err.Error()}
	}
	if targetEnv == "" {
		targetEnv = "prod"
	}
	csID := aiconfig.NewChangeSetID(s.now())
	changeSet := aiconfig.BuildChangeSet(csID, accountID, actor, actor, ops)
	masked := aiconfig.MaskSecrets(changeSet)
	rec := s.aistore.Create(AIChange{
		ChangeSetID: csID, VM: vm, AssistantID: assistantID, OpType: opType,
		TargetEnv: targetEnv, Status: "testing", Actor: actor, RequestPayload: masked,
	})

	// TEST-GATE (fail-closed): reprova => NAO aplica.
	report, passed := s.aigate.Gate(ctx, gateKind, vm, changeSet)
	if !passed {
		s.aistore.Update(rec.ID, func(c *AIChange) { c.Status = "test_failed"; c.TestReport = report })
		s.audit.Append("ai_test_failed", actor, vm, map[string]any{"change_set_id": csID, "op": opType, "assistant_id": assistantID})
		return 409, map[string]any{"error": "test-gate reprovou", "change_set_id": csID, "status": "test_failed", "test_report": report}
	}

	// APPLY (transacional/idempotente no receptor).
	resp, err := s.aidriver.Apply(ctx, vm, changeSet)
	if err != nil {
		s.aistore.Update(rec.ID, func(c *AIChange) { c.Status = "failed"; c.Error = err.Error(); c.TestReport = report })
		s.audit.Append("ai_apply_failed", actor, vm, map[string]any{"change_set_id": csID, "op": opType, "error": err.Error()})
		return 502, map[string]any{"error": "apply falhou: " + err.Error(), "change_set_id": csID, "status": "failed", "test_report": report}
	}
	remoteID := extractRemoteID(resp, csID)
	s.aistore.Update(rec.ID, func(c *AIChange) {
		c.Status = "applied"
		c.RemoteChangeSetID = remoteID
		c.TestReport = report
		c.Diff = asMap(resp["diff"])
		c.AppliedAt = s.now().UTC().Format(time.RFC3339)
	})
	s.audit.Append("ai_applied", actor, vm, map[string]any{"change_set_id": csID, "op": opType, "assistant_id": assistantID})
	return 200, map[string]any{"change_set_id": csID, "status": "applied", "op": opType, "test_report": report, "receptor": resp}
}

func extractRemoteID(resp map[string]interface{}, fallback string) string {
	for _, k := range []string{"remote_change_set_id", "change_set_id", "id"} {
		if v, ok := resp[k].(string); ok && v != "" {
			return v
		}
	}
	return fallback
}

func asMap(v interface{}) map[string]interface{} {
	if m, ok := v.(map[string]interface{}); ok {
		return m
	}
	return nil
}
