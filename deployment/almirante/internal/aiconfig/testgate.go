package aiconfig

import (
	"context"
	"strings"
	"time"
)

// testgate.go e o TEST-GATE (§7): roda ANTES de qualquer escrita atingir a VM.
// Portado do noc-spxia, mas SEM store (dry_run/eval nao persistem, entao o gate
// e seguro mesmo sem rotear por HML). Despacha por kind:
//   - credential  -> TestCredential
//   - tool        -> PerformTest
//   - prompt      -> dry_run + smoke + EvalPrompt + LLM-juiz
//   - eligibility -> dry_run (tenant check surge como 403/422)

type TestGate struct {
	driver       *Driver
	judge        *Judge
	avgThreshold float64
	criticalMin  float64
	logf         func(format string, args ...interface{})
}

// GateConfig parametriza o test-gate.
type GateConfig struct {
	JudgeAPIKey       string
	JudgeModel        string
	JudgeBaseURL      string
	JudgeAvgThreshold float64
	JudgeCriticalMin  float64
	Logf              func(format string, args ...interface{})
}

func NewTestGate(driver *Driver, cfg GateConfig) *TestGate {
	avg := cfg.JudgeAvgThreshold
	if avg <= 0 {
		avg = 0.8
	}
	crit := cfg.JudgeCriticalMin
	if crit <= 0 {
		crit = 0.6
	}
	logf := cfg.Logf
	if logf == nil {
		logf = func(string, ...interface{}) {}
	}
	return &TestGate{
		driver:       driver,
		judge:        NewJudge(cfg.JudgeAPIKey, cfg.JudgeModel, cfg.JudgeBaseURL, 30*time.Second),
		avgThreshold: avg,
		criticalMin:  crit,
		logf:         logf,
	}
}

// Gate roda o gate por kind e devolve (report, passed).
func (tg *TestGate) Gate(ctx context.Context, kind, vmSlug string, changeSet map[string]interface{}) (map[string]interface{}, bool) {
	started := time.Now()
	report := map[string]interface{}{
		"kind":       kind,
		"vm":         vmSlug,
		"started_at": started.UTC().Format(time.RFC3339),
	}
	ops := opsFromChangeSet(changeSet)
	if len(ops) == 0 {
		report["reason"] = "change-set sem operations"
		return tg.finish(report, started, false)
	}
	var passed bool
	switch kind {
	case "credential":
		passed = tg.gateCredential(ctx, vmSlug, ops, report)
	case "tool":
		passed = tg.gateTool(ctx, vmSlug, ops, report)
	case "prompt":
		passed = tg.gatePrompt(ctx, vmSlug, changeSet, ops, report)
	case "eligibility":
		passed = tg.gateDryRunOnly(ctx, vmSlug, changeSet, report)
	default:
		report["note"] = "kind desconhecido -> dry_run defensivo"
		passed = tg.gateDryRunOnly(ctx, vmSlug, changeSet, report)
	}
	return tg.finish(report, started, passed)
}

func (tg *TestGate) finish(report map[string]interface{}, started time.Time, passed bool) (map[string]interface{}, bool) {
	report["passed"] = passed
	report["duration_ms"] = time.Since(started).Milliseconds()
	if !passed {
		tg.logf("test-gate REPROVOU kind=%s vm=%s reason=%s", asString(report["kind"]), asString(report["vm"]), asString(report["reason"]))
	}
	return report, passed
}

func (tg *TestGate) gateCredential(ctx context.Context, vmSlug string, ops []map[string]interface{}, report map[string]interface{}) bool {
	op := findOp(ops, "set_credential")
	if op == nil {
		report["reason"] = "op set_credential ausente no change-set"
		return false
	}
	provider, _ := op["provider"].(string)
	settings, _ := op["settings"].(map[string]interface{})
	enabled := true
	if v, ok := op["enabled"].(bool); ok {
		enabled = v
	}
	step := map[string]interface{}{"provider": provider}
	if provider == "" || settings == nil {
		report["credential"] = step
		report["reason"] = "provider/settings obrigatorios ausentes"
		return false
	}
	resp, err := tg.driver.TestCredential(ctx, vmSlug, provider, settings, enabled)
	if err != nil {
		step["error"] = err.Error()
		if st, ok := httpStatusOf(err); ok {
			step["http_status"] = st
		}
		report["credential"] = step
		report["reason"] = "test_connection falhou: " + err.Error()
		return false
	}
	if !receptorOK(resp) {
		step["receptor"] = resp
		report["credential"] = step
		report["reason"] = "receptor reportou credencial invalida"
		return false
	}
	step["ok"] = true
	step["receptor"] = resp
	report["credential"] = step
	return true
}

func (tg *TestGate) gateTool(ctx context.Context, vmSlug string, ops []map[string]interface{}, report map[string]interface{}) bool {
	results := make([]map[string]interface{}, 0, len(ops))
	allPass := true
	for _, op := range ops {
		t, _ := op["type"].(string)
		switch t {
		case "disarm_tool":
			results = append(results, map[string]interface{}{
				"type": t, "tool_id": op["tool_id"], "skipped": true,
				"note": "desarmar nao exige perform_test",
			})
		case "arm_tool":
			aid := toInt(op["assistant_id"])
			toolID, _ := op["tool_id"].(string)
			r := map[string]interface{}{"type": t, "tool_id": toolID}
			resp, err := tg.driver.PerformTest(ctx, vmSlug, aid, toolID)
			if err != nil {
				r["error"] = err.Error()
				if st, ok := httpStatusOf(err); ok {
					r["http_status"] = st
				}
				allPass = false
				report["reason"] = "perform_test reprovou tool " + toolID
			} else if !receptorOK(resp) {
				r["receptor"] = resp
				allPass = false
				report["reason"] = "receptor: tool invalida " + toolID
			} else {
				r["ok"] = true
				r["receptor"] = resp
			}
			results = append(results, r)
		default:
			results = append(results, map[string]interface{}{"type": t, "skipped": true})
		}
	}
	report["tool"] = results
	return allPass
}

func (tg *TestGate) gatePrompt(ctx context.Context, vmSlug string, changeSet map[string]interface{}, ops []map[string]interface{}, report map[string]interface{}) bool {
	dr, err := tg.driver.DryRun(ctx, vmSlug, changeSet)
	drStep := map[string]interface{}{}
	if err != nil {
		drStep["error"] = err.Error()
		if st, ok := httpStatusOf(err); ok {
			drStep["http_status"] = st
		}
		report["dry_run"] = drStep
		report["reason"] = "dry_run falhou: " + err.Error()
		return false
	}
	drStep["ok"] = true
	drStep["diff"] = dr
	report["dry_run"] = drStep

	aid := 0
	instructions := ""
	for _, op := range ops {
		if v := toInt(op["assistant_id"]); v > 0 {
			aid = v
		}
		if s, ok := op["instructions"].(string); ok && s != "" {
			instructions = s
		}
	}
	if aid == 0 {
		report["smoke"] = map[string]interface{}{"skipped": true, "reason": "sem assistant_id no change-set"}
		report["note"] = "prompt sem assistant_id: aprovado so por dry_run"
		return true
	}
	eval, err := tg.driver.EvalPrompt(ctx, vmSlug, aid, instructions, nil, true)
	if err != nil {
		report["eval"] = map[string]interface{}{"error": err.Error()}
		if st, ok := httpStatusOf(err); ok {
			report["eval"].(map[string]interface{})["http_status"] = st
		}
		report["reason"] = "eval_prompt falhou: " + err.Error()
		return false
	}
	scenarios := scenariosFromEval(eval)
	report["eval"] = map[string]interface{}{"scenario_count": len(scenarios), "raw_keys": evalKeys(eval)}

	smokePassed, smoke := tg.smoke(scenarios)
	report["smoke"] = smoke
	if !smokePassed {
		report["reason"] = "smoke reprovou (resposta vazia / nao-pt-BR / tool errada)"
		return false
	}
	if !tg.judge.Available() {
		report["judge"] = map[string]interface{}{"skipped": true, "reason": "sem OPENAI key; juiz desabilitado"}
		report["note"] = "aprovado por dry_run + smoke (juiz indisponivel)"
		return true
	}
	judgePassed, judgeReport := tg.runJudge(ctx, scenarios)
	report["judge"] = judgeReport
	report["thresholds"] = map[string]interface{}{"avg": tg.avgThreshold, "critical_min": tg.criticalMin}
	if !judgePassed {
		report["reason"] = "LLM-juiz abaixo do threshold"
		return false
	}
	return true
}

func (tg *TestGate) smoke(scenarios []evalScenario) (bool, map[string]interface{}) {
	if len(scenarios) == 0 {
		return true, map[string]interface{}{"skipped": true, "reason": "eval nao retornou cenarios"}
	}
	n := len(scenarios)
	if n > 3 {
		n = 3
	}
	checks := make([]map[string]interface{}, 0, n)
	pass := true
	for i := 0; i < n; i++ {
		s := scenarios[i]
		nonEmpty := strings.TrimSpace(s.Response) != ""
		ptbr := looksPortuguese(s.Response)
		toolOK := s.ExpectedTool == "" || containsStr(s.ToolCalls, s.ExpectedTool)
		c := map[string]interface{}{"scenario_id": s.ID, "non_empty": nonEmpty, "pt_br": ptbr, "tool_ok": toolOK}
		if s.ExpectedTool != "" {
			c["expected_tool"] = s.ExpectedTool
		}
		if !(nonEmpty && ptbr && toolOK) {
			pass = false
		}
		checks = append(checks, c)
	}
	return pass, map[string]interface{}{"passed": pass, "checks": checks}
}

func (tg *TestGate) runJudge(ctx context.Context, scenarios []evalScenario) (bool, map[string]interface{}) {
	perScenario := make([]map[string]interface{}, 0, len(scenarios))
	var sum float64
	var count int
	minScore := 1.0
	criticalFail := false
	for _, s := range scenarios {
		row := map[string]interface{}{"scenario_id": s.ID}
		v, err := tg.judge.ScoreScenario(ctx, s.ID, s.Input, s.Response, s.Expected, s.ExpectedTool, s.ToolCalls)
		if err != nil {
			row["error"] = err.Error()
			perScenario = append(perScenario, row)
			continue
		}
		row["score"] = v.Score
		row["verdict"] = v.Verdict
		row["reasons"] = v.Reasons
		if s.Critical {
			row["critical"] = true
		}
		sum += v.Score
		count++
		if v.Score < minScore {
			minScore = v.Score
		}
		if s.Critical && v.Score < tg.criticalMin {
			criticalFail = true
		}
		perScenario = append(perScenario, row)
	}
	if count == 0 {
		return true, map[string]interface{}{"per_scenario": perScenario, "avg": nil, "note": "nenhum cenario avaliavel; aprovado por dry_run+smoke", "model": tg.judge.model}
	}
	avg := sum / float64(count)
	passed := avg >= tg.avgThreshold && !criticalFail
	return passed, map[string]interface{}{
		"per_scenario": perScenario, "avg": avg, "min": minScore,
		"evaluated": count, "critical_fail": criticalFail, "model": tg.judge.model,
	}
}

func (tg *TestGate) gateDryRunOnly(ctx context.Context, vmSlug string, changeSet map[string]interface{}, report map[string]interface{}) bool {
	resp, err := tg.driver.DryRun(ctx, vmSlug, changeSet)
	step := map[string]interface{}{}
	if err != nil {
		step["error"] = err.Error()
		if st, ok := httpStatusOf(err); ok {
			step["http_status"] = st
		}
		report["dry_run"] = step
		report["reason"] = "dry_run falhou: " + err.Error()
		return false
	}
	step["ok"] = true
	step["diff"] = resp
	report["dry_run"] = step
	return true
}
