package aiconfig

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"
	"time"
)

// ops.go monta o envelope change-set (§4 do design) + mascaramento de segredos +
// os helpers tolerantes usados pelo test-gate. Portado do noc-spxia
// (changeset.go + os helpers de testgate.go).

// NewChangeSetID gera "cs_<RFC3339>_<4 bytes hex>" (legivel + unico em rajada).
func NewChangeSetID(now time.Time) string {
	var b [4]byte
	_, _ = rand.Read(b[:])
	return "cs_" + now.UTC().Format("2006-01-02T15:04:05Z") + "_" + hex.EncodeToString(b[:])
}

// BuildChangeSet monta o envelope INTERNO (sem o wrapper "change_set", que o
// Driver adiciona).
func BuildChangeSet(changeSetID string, accountID int, author, approvedBy string, operations []map[string]interface{}) map[string]interface{} {
	return map[string]interface{}{
		"change_set_id": changeSetID,
		"account_id":    accountID,
		"author":        author,
		"approved_by":   approvedBy,
		"operations":    operations,
	}
}

// ---- builders de operations (§4.1-4.6) ----

func OpUpdateInstructions(assistantID int, instructions string) map[string]interface{} {
	return map[string]interface{}{"type": "update_instructions", "assistant_id": assistantID, "instructions": instructions}
}

// OpToolArming devolve a op e o opType ("arm_tool"/"disarm_tool").
func OpToolArming(assistantID int, toolID string, armed bool) (map[string]interface{}, string) {
	opType := "disarm_tool"
	if armed {
		opType = "arm_tool"
	}
	return map[string]interface{}{"type": opType, "assistant_id": assistantID, "tool_id": toolID}, opType
}

func OpSetCredential(provider string, settings map[string]interface{}, enabled bool) map[string]interface{} {
	return map[string]interface{}{"type": "set_credential", "provider": provider, "settings": settings, "enabled": enabled}
}

func OpUpdateBehavior(assistantID int, behavior map[string]interface{}) map[string]interface{} {
	return map[string]interface{}{"type": "update_behavior", "assistant_id": assistantID, "behavior": behavior}
}

func OpAddFAQ(assistantID int, question, answer string) map[string]interface{} {
	return map[string]interface{}{"type": "add_faq", "assistant_id": assistantID, "question": question, "answer": answer}
}

func OpSetEligibility(assistantID int, inboxIDs []int) map[string]interface{} {
	return map[string]interface{}{"type": "set_eligibility", "assistant_id": assistantID, "inbox_ids": inboxIDs}
}

// ---- mascaramento de segredos (§11) ----

var secretKeyHints = []string{"api_key", "secret", "token", "password", "maps_key", "client_secret"}

func isSecretKey(k string) bool {
	lk := strings.ToLower(k)
	for _, h := range secretKeyHints {
		if strings.Contains(lk, h) {
			return true
		}
	}
	return false
}

// MaskSecrets devolve copia com valores de chaves sensiveis mascarados (recursivo).
func MaskSecrets(in map[string]interface{}) map[string]interface{} {
	out := make(map[string]interface{}, len(in))
	for k, v := range in {
		switch val := v.(type) {
		case map[string]interface{}:
			out[k] = MaskSecrets(val)
		case []interface{}:
			arr := make([]interface{}, len(val))
			for i, item := range val {
				if m, ok := item.(map[string]interface{}); ok {
					arr[i] = MaskSecrets(m)
				} else {
					arr[i] = item
				}
			}
			out[k] = arr
		case []map[string]interface{}:
			arr := make([]map[string]interface{}, len(val))
			for i, m := range val {
				arr[i] = MaskSecrets(m)
			}
			out[k] = arr
		default:
			if isSecretKey(k) {
				out[k] = "********"
			} else {
				out[k] = v
			}
		}
	}
	return out
}

// ---- helpers tolerantes (JSON do receptor: float64/string/bool) ----

func opsFromChangeSet(cs map[string]interface{}) []map[string]interface{} {
	raw, ok := cs["operations"]
	if !ok {
		return nil
	}
	switch v := raw.(type) {
	case []map[string]interface{}:
		return v
	case []interface{}:
		out := make([]map[string]interface{}, 0, len(v))
		for _, item := range v {
			if m, ok := item.(map[string]interface{}); ok {
				out = append(out, m)
			}
		}
		return out
	default:
		return nil
	}
}

func findOp(ops []map[string]interface{}, opType string) map[string]interface{} {
	for _, op := range ops {
		if t, _ := op["type"].(string); t == opType {
			return op
		}
	}
	return nil
}

type evalScenario struct {
	ID           int
	Input        string
	Response     string
	Expected     string
	ExpectedTool string
	ToolCalls    []string
	Critical     bool
}

func scenariosFromEval(eval map[string]interface{}) []evalScenario {
	var list []interface{}
	for _, key := range []string{"scenarios", "results", "evaluations", "cases"} {
		if v, ok := eval[key].([]interface{}); ok {
			list = v
			break
		}
	}
	out := make([]evalScenario, 0, len(list))
	for i, item := range list {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		s := evalScenario{
			ID:           toInt(firstVal(m, "id", "scenario_id")),
			Input:        getStr(m, "input", "message", "question", "prompt"),
			Response:     getStr(m, "response", "output", "text", "answer", "reply"),
			Expected:     getStr(m, "expected", "expected_response", "baseline", "golden"),
			ExpectedTool: getStr(m, "expected_tool", "expects_tool", "required_tool"),
			ToolCalls:    getStrSlice(m, "tool_calls", "tools_called", "tools"),
			Critical:     getBool(m, "critical", "is_critical"),
		}
		if s.ID == 0 {
			s.ID = i + 1
		}
		out = append(out, s)
	}
	return out
}

func evalKeys(eval map[string]interface{}) []string {
	keys := make([]string, 0, len(eval))
	for k := range eval {
		keys = append(keys, k)
	}
	return keys
}

func looksPortuguese(s string) bool {
	t := strings.ToLower(s)
	if strings.TrimSpace(t) == "" {
		return false
	}
	for _, r := range t {
		switch r {
		case 'ã', 'õ', 'ç', 'á', 'é', 'í', 'ó', 'ú', 'â', 'ê', 'ô', 'à':
			return true
		}
	}
	markers := []string{
		" de ", " que ", " nao ", " não ", " você ", " voce ", " com ", " para ",
		" uma ", " um ", " e ", " o ", " a ", " os ", " as ", " do ", " da ",
		"olá", "ola ", "obrigad", "bom dia", "boa tarde", "boa noite", " está ", " esta ",
	}
	hits := 0
	padded := " " + t + " "
	for _, m := range markers {
		if strings.Contains(padded, m) {
			hits++
			if hits >= 2 {
				return true
			}
		}
	}
	return false
}

func containsStr(arr []string, target string) bool {
	for _, a := range arr {
		if strings.EqualFold(strings.TrimSpace(a), strings.TrimSpace(target)) {
			return true
		}
	}
	return false
}

func receptorOK(resp map[string]interface{}) bool {
	if resp == nil {
		return true
	}
	for _, k := range []string{"ok", "success", "valid", "passed"} {
		if v, ok := resp[k].(bool); ok && !v {
			return false
		}
	}
	if st, ok := resp["status"].(string); ok {
		switch strings.ToLower(st) {
		case "error", "failed", "failure", "invalid", "unauthorized":
			return false
		}
	}
	return true
}

type httpStatuser interface{ HTTPStatus() int }

func httpStatusOf(err error) (int, bool) {
	var hs httpStatuser
	if errors.As(err, &hs) {
		return hs.HTTPStatus(), true
	}
	return 0, false
}

func toInt(v interface{}) int {
	switch t := v.(type) {
	case int:
		return t
	case int64:
		return int(t)
	case float64:
		return int(t)
	case float32:
		return int(t)
	default:
		return 0
	}
}

func firstVal(m map[string]interface{}, keys ...string) interface{} {
	for _, k := range keys {
		if v, ok := m[k]; ok {
			return v
		}
	}
	return nil
}

func getStr(m map[string]interface{}, keys ...string) string {
	for _, k := range keys {
		if v, ok := m[k].(string); ok && v != "" {
			return v
		}
	}
	return ""
}

func getBool(m map[string]interface{}, keys ...string) bool {
	for _, k := range keys {
		if v, ok := m[k].(bool); ok {
			return v
		}
	}
	return false
}

func getStrSlice(m map[string]interface{}, keys ...string) []string {
	for _, k := range keys {
		raw, ok := m[k]
		if !ok {
			continue
		}
		switch v := raw.(type) {
		case []string:
			return v
		case []interface{}:
			out := make([]string, 0, len(v))
			for _, item := range v {
				if s, ok := item.(string); ok {
					out = append(out, s)
				} else if mm, ok := item.(map[string]interface{}); ok {
					if name := getStr(mm, "name", "tool", "tool_id", "function"); name != "" {
						out = append(out, name)
					}
				}
			}
			return out
		case string:
			if v != "" {
				return []string{v}
			}
		}
	}
	return nil
}

func asString(v interface{}) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}
