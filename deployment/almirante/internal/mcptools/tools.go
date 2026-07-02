package mcptools

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/Dev-Simplex/almirante/internal/fleet"
	"github.com/Dev-Simplex/almirante/internal/safety"
	"github.com/Dev-Simplex/almirante/internal/types"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type vmInput struct {
	VM string `json:"vm"`
}
type proposeInput struct {
	VM     string `json:"vm"`
	Branch string `json:"branch,omitempty"`
}
type groupInput struct {
	Group  string `json:"group"`
	Branch string `json:"branch,omitempty"`
}
type serviceInput struct {
	VM      string `json:"vm"`
	Service string `json:"service"`
}
type migrateInput struct {
	VM      string `json:"vm"`
	Version string `json:"version,omitempty"`
}
type reqInput struct {
	RequestID string `json:"request_id"`
}
type freezeInput struct {
	Scope   string `json:"scope"`
	Message string `json:"message,omitempty"`
}
type unfreezeInput struct {
	Scope string `json:"scope"`
}
type mergeInput struct {
	From string `json:"from"`
	To   string `json:"to"`
}
type empty struct{}

// --- inputs das tools de governanca de IA ---
type aiVMInput struct {
	VM string `json:"vm"`
}
type aiAgentInput struct {
	VM          string `json:"vm"`
	AssistantID int    `json:"assistant_id"`
}
type aiPromptInput struct {
	VM           string `json:"vm"`
	AssistantID  int    `json:"assistant_id"`
	Instructions string `json:"instructions"`
	TargetEnv    string `json:"target_env,omitempty"`
}
type aiToolInput struct {
	VM          string `json:"vm"`
	AssistantID int    `json:"assistant_id"`
	ToolID      string `json:"tool_id"`
	Armed       bool   `json:"armed"`
}
type aiCredInput struct {
	VM       string         `json:"vm"`
	Provider string         `json:"provider"`
	Settings map[string]any `json:"settings"`
	Enabled  bool           `json:"enabled"`
}
type aiBehaviorInput struct {
	VM          string         `json:"vm"`
	AssistantID int            `json:"assistant_id"`
	Behavior    map[string]any `json:"behavior"`
}
type aiFaqInput struct {
	VM          string `json:"vm"`
	AssistantID int    `json:"assistant_id"`
	Question    string `json:"question"`
	Answer      string `json:"answer"`
}
type aiRollbackInput struct {
	VM          string `json:"vm"`
	ChangeSetID string `json:"change_set_id"`
}

func bp(v bool) *bool { return &v }

// jsonTxt formata a resposta JSON do control como texto pro Claude Code.
func jsonTxt(v any) *mcp.CallToolResult {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return errtxt("erro ao formatar resposta: " + err.Error())
	}
	return txt(string(b))
}
func txt(s string) *mcp.CallToolResult {
	return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: s}}}
}
func errtxt(s string) *mcp.CallToolResult {
	return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: s}}, IsError: true}
}
func derefIntSafe(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}

// addRead: acucar para registrar tools read-only com annotations padrao.
func addRead(s *mcp.Server, name, desc string, h func(context.Context, *mcp.CallToolRequest, vmInput) (*mcp.CallToolResult, any, error)) {
	mcp.AddTool(s, &mcp.Tool{Name: name, Description: desc, Annotations: &mcp.ToolAnnotations{ReadOnlyHint: true, IdempotentHint: true}}, h)
}

// Register registra todas as tools no server, ligadas a uma frota e a uma Source.
// fl e src sao capturados pelos handlers — cada server HTTP no control tem a sua
// Source (token do dev por request), entao nada de estado global compartilhado.
func Register(s *mcp.Server, fl *types.Fleet, src Source) {
	ro := &mcp.ToolAnnotations{ReadOnlyHint: true, IdempotentHint: true}
	prop := &mcp.ToolAnnotations{ReadOnlyHint: false, DestructiveHint: bp(false), OpenWorldHint: bp(true)}
	gated := &mcp.ToolAnnotations{ReadOnlyHint: false, DestructiveHint: bp(true), OpenWorldHint: bp(true)}

	vmOK := func(id string) (types.VM, string) {
		if !safety.IsValidVMID(id) {
			return types.VM{}, fmt.Sprintf("id de VM invalido: %q", id)
		}
		if v, ok := fleet.FindVM(fl, id); ok {
			return v, ""
		}
		ids := make([]string, len(fl.VMs))
		for i, v := range fl.VMs {
			ids[i] = v.ID
		}
		return types.VM{}, fmt.Sprintf("VM %q nao existe. Disponiveis: %s", id, strings.Join(ids, ", "))
	}
	proposeMany := func(ids []string, branch string) string {
		var b strings.Builder
		b.WriteString("Enfileirados — 1 pedido por VM, cada um aguardando aprovacao humana:\n")
		for _, id := range ids {
			vm, _ := fleet.FindVM(fl, id)
			r, err := src.Propose(id, branch)
			if err != nil {
				fmt.Fprintf(&b, "• %s — ERRO: %v\n", vm.Name, err)
				continue
			}
			flag := "✅"
			if r.HasDestructive {
				flag = "⚠️ destrutiva"
			}
			fmt.Fprintf(&b, "• %s %s → %s (%s) [%s]\n", vm.Name, r.CurrentSHA, r.TargetSHA, flag, r.ID)
		}
		return b.String()
	}

	// ===== Toolset A — Observabilidade =====
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_fleet_status", Description: "Lista as VMs da frota (ambiente, branch, criticidade). Use para 'como ta a frota?'.", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, any, error) {
			var b strings.Builder
			fmt.Fprintf(&b, "Frota ChatSPX (%d VMs):\n", len(fl.VMs))
			for _, v := range fl.VMs {
				crit := ""
				if v.Critical {
					crit = " · CRITICA"
				}
				fmt.Fprintf(&b, "• %s — %s (%s) branch %s%s\n", v.ID, v.Name, v.Env, v.Branch, crit)
			}
			return txt(b.String()), nil, nil
		})

	addRead(s, "almirante_vm_status", "Status operacional de uma VM (online, servico, puma/sidekiq, cpu/ram/disco, commit).",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			st, err := src.Status(vm.ID)
			if err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt(fmtStatus(vm, st)), nil, nil
		})

	addRead(s, "almirante_vm_health", "Health-check composto REAL (db+redis+sidekiq+HTTP200+migrations). Nunca 'exit 0'.",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			h, err := src.Health(vm.ID)
			if err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt(fmtHealth(vm, h)), nil, nil
		})

	addRead(s, "almirante_migration_status", "Migrations pendentes, marcando DESTRUTIVAS (denylist + heuristica). Pre-flight antes de restart/deploy.",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			m, err := src.Migrations(vm.ID)
			if err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt(fmtMig(vm, m)), nil, nil
		})

	addRead(s, "almirante_git_diff", "Commit atual vs origin/branch + commits a aplicar + link compare.",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			d, err := src.Diff(vm.ID)
			if err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt(fmtDiff(vm, d)), nil, nil
		})

	addRead(s, "almirante_deploy_history", "Historico de deploys da VM (autor, de->para SHA, status, quem aprovou).",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			h, err := src.History(vm.ID)
			if err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			if len(h) == 0 {
				return txt("Sem historico para " + vm.Name), nil, nil
			}
			var b strings.Builder
			fmt.Fprintf(&b, "Historico de %s:\n", vm.Name)
			for _, e := range h {
				fmt.Fprintf(&b, "• %s %s→%s por %s (aprovou: %s) · %s\n", e.FinishedAt, e.FromSHA, e.ToSHA, e.Actor, e.ApprovedBy, e.Status)
			}
			return txt(b.String()), nil, nil
		})

	addRead(s, "almirante_sidekiq_status", "Estado do Sidekiq (worker) da VM — processos vivos.",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			st, _ := src.Status(vm.ID)
			return txt(fmt.Sprintf("%s %s — sidekiq: %d processo(s) %s", dot(st.Sidekiq > 0), vm.Name, st.Sidekiq, map[bool]string{true: "ativo", false: "PARADO"}[st.Sidekiq > 0])), nil, nil
		})

	addRead(s, "almirante_disk_usage", "Uso de disco da VM.",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			st, _ := src.Status(vm.ID)
			warn := ""
			if st.Disk != nil && *st.Disk >= 85 {
				warn = " ⚠️ ALTO"
			}
			return txt(fmt.Sprintf("%s — disco %s%s", vm.Name, pct(st.Disk), warn)), nil, nil
		})

	addRead(s, "almirante_service_status", "Estado dos servicos systemd (web/worker) da VM.",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			st, _ := src.Status(vm.ID)
			return txt(fmt.Sprintf("%s %s — chatwoot.target %s · %d puma / %d sidekiq", dot(st.ServiceActive), vm.Name, map[bool]string{true: "ativo", false: "INATIVO"}[st.ServiceActive], st.Puma, st.Sidekiq)), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_version_matrix", Description: "Matriz de versoes: qual commit cada VM esta rodando. Responde 'ta tudo na mesma versao?'.", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, any, error) {
			var b strings.Builder
			b.WriteString("Matriz de versoes:\n")
			for _, v := range fl.VMs {
				st, _ := src.Status(v.ID)
				commit := st.Commit
				if !st.Online {
					commit = "(offline)"
				}
				fmt.Fprintf(&b, "• %-16s %s (branch %s)\n", v.Name, commit, st.Branch)
			}
			return txt(b.String()), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_drift_check", Description: "Quem precisa de deploy? Lista as VMs atras do origin/branch e se ha destrutiva no caminho.", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, any, error) {
			var b strings.Builder
			b.WriteString("Drift (VMs defasadas):\n")
			any := false
			for _, v := range fl.VMs {
				d, _ := src.Diff(v.ID)
				if d.BehindCount > 0 {
					any = true
					m, _ := src.Migrations(v.ID)
					flag := ""
					if m.HasDestructive {
						flag = " ⚠️ destrutiva no caminho"
					}
					fmt.Fprintf(&b, "• %s: %d commits atras (%s→%s)%s\n", v.Name, d.BehindCount, d.CurrentSHA, d.TargetSHA, flag)
				}
			}
			if !any {
				b.WriteString("✅ tudo em dia.")
			}
			return txt(b.String()), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_list_pending", Description: "Lista os pedidos de deploy aguardando aprovacao humana (a fila do gate).", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, any, error) {
			ps, err := src.ListPending()
			if err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			if len(ps) == 0 {
				return txt("Nenhum pedido pendente."), nil, nil
			}
			var b strings.Builder
			b.WriteString("Pedidos pendentes (aguardando aprovacao humana):\n")
			for _, r := range ps {
				fmt.Fprintf(&b, "• %s — %s → %s por %s%s\n", r.ID, r.VM, r.TargetSHA, r.RequestedBy, map[bool]string{true: " ⚠️", false: ""}[r.HasDestructive])
			}
			return txt(b.String()), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_request_status", Description: "Estado de um pedido de deploy (pending/approved/executing/success/failed).", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, in reqInput) (*mcp.CallToolResult, any, error) {
			r, err := src.GetRequest(in.RequestID)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			vm, _ := fleet.FindVM(fl, r.VM)
			return txt(fmtRequest(vm, r) + "\nSTATUS: " + string(r.Status)), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_whoami", Description: "Mostra seu papel e limites: voce propoe, NAO aprova (gate fora do LLM).", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, any, error) {
			return txt("Voce e OPERATOR: propoe e le. NAO aprova nem executa — aprovar exige um humano admin no painel (anti self-review). A tool 'approve' nem existe aqui."), nil, nil
		})

	// ===== Toolset C — Deploy (propor) =====
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_propose_deploy_vm", Description: "Propoe deploy de UMA VM (precompile+migrate+restart em producao). So ENFILEIRA; requer aprovacao humana. Use para 'atualiza/sobe a <vm>'.", Annotations: prop},
		func(_ context.Context, _ *mcp.CallToolRequest, in proposeInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			branch := in.Branch
			if branch == "" {
				branch = vm.Branch
			}
			r, err := src.Propose(vm.ID, branch)
			if err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt(fmtRequest(vm, r)), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_propose_deploy_group", Description: "Propoe deploy de um GRUPO (aws|proxmox|critical|sandbox|all). 1 pedido por VM. Use para 'sobe nas AWS'.", Annotations: prop},
		func(_ context.Context, _ *mcp.CallToolRequest, in groupInput) (*mcp.CallToolResult, any, error) {
			ids, ok := fleet.Group(fl, in.Group)
			if !ok {
				return errtxt("grupo invalido. Use: all, aws, proxmox, critical, sandbox"), nil, nil
			}
			return txt(proposeMany(ids, in.Branch)), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_propose_deploy_all", Description: "Propoe deploy de TODAS as VMs (1 pedido por VM). Use para 'sobe em todas'.", Annotations: prop},
		func(_ context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, any, error) {
			ids, _ := fleet.Group(fl, "all")
			return txt(proposeMany(ids, "")), nil, nil
		})

	addRead(s, "almirante_dry_run", "Pre-flight de deploy SEM enfileirar (de->para SHA + migrations + risco). O 'kamal deploy --dry-run'.",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			d, _ := src.Diff(vm.ID)
			m, _ := src.Migrations(vm.ID)
			return txt("DRY-RUN " + vm.Name + " (nada enfileirado):\n" + fmtDiff(vm, d) + "\n" + fmtMig(vm, m)), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_propose_merge", Description: "Propoe MERGE/promote de branch. Fluxos permitidos: homologacao->producao, paulao->producao, paulao->homologacao. So ENFILEIRA; o merge+push so roda apos aprovacao HUMANA (admin). Use para 'mergeia/promove a homologacao pra producao'.", Annotations: prop},
		func(_ context.Context, _ *mcp.CallToolRequest, in mergeInput) (*mcp.CallToolResult, any, error) {
			if in.From == "" || in.To == "" {
				return errtxt("informe 'from' e 'to' (ex: from=homologacao, to=producao)"), nil, nil
			}
			msg, err := src.ProposeMerge(in.From, in.To)
			if err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt("📋 " + msg + "\n⚠️ Muda a branch de producao — a IA NAO mergeia nem da push sozinha; um humano admin aprova (anti self-review)."), nil, nil
		})

	// ===== Toolset D — Ciclo-de-vida (gated; so propoe a acao) =====
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_propose_restart_vm", Description: "Propoe REINICIAR uma VM (gated; pre-flight bloqueia se houver migration pendente). 'reinicia a <vm>'.", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			m, _ := src.Migrations(vm.ID)
			if !m.UpToDate {
				return errtxt(fmt.Sprintf("⚠️ %s tem %d migration(s) pendente(s) — restart bloqueado (evita 500 em cadeia). Resolva antes.", vm.Name, len(m.Pending))), nil, nil
			}
			return txt(fmt.Sprintf("📋 Restart de %s enfileirado. Gated — requer aprovacao humana. Eu NAO reinicio sozinho.", vm.Name)), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_propose_restart_service", Description: "Propoe reiniciar SO um servico (web|worker) da VM — ex: worker sidekiq travado. Gated.", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in serviceInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			if in.Service != "web" && in.Service != "worker" {
				return errtxt("service deve ser 'web' ou 'worker'"), nil, nil
			}
			return txt(fmt.Sprintf("📋 Restart do %s de %s enfileirado. Gated — requer aprovacao humana.", in.Service, vm.Name)), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_propose_migrate", Description: "Propoe rodar migrations isoladas (sem tocar codigo/restart). version? aplica SO aquela (db:migrate:up VERSION=). Gated; destrutiva exige backup.", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in migrateInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			m, _ := src.Migrations(vm.ID)
			warn := ""
			if m.HasDestructive {
				warn = " ⚠️ contem DESTRUTIVA — exige backup verificado antes."
			}
			return txt(fmt.Sprintf("📋 Migrate de %s enfileirado (%d pendente(s)).%s Gated — requer aprovacao humana.", vm.Name, len(m.Pending), warn)), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_propose_precompile", Description: "Propoe recompilar assets (sem migrate/restart). Gated.", Annotations: &mcp.ToolAnnotations{ReadOnlyHint: false, DestructiveHint: bp(false)}},
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			return txt(fmt.Sprintf("📋 Precompile de assets de %s enfileirado. Gated.", vm.Name)), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_propose_rollback", Description: "Propoe ROLLBACK ao ultimo SHA bom. AVISO: reverte CODIGO, NAO reverte migrations/dados. Gated.", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			return txt(fmt.Sprintf("📋 Rollback de %s enfileirado.\n⚠️ Reverte CODIGO, NAO reverte migrations/dados. Gated — requer aprovacao humana + confirmacao.", vm.Name)), nil, nil
		})

	// ===== Toolset E — Manutencao =====
	light := &mcp.ToolAnnotations{ReadOnlyHint: false, DestructiveHint: bp(false)}

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_freeze_deploys", Description: "Congela deploys de uma VM (id) ou da frota toda ('all') — janela de manutencao. Enquanto congelado, propostas sao recusadas.", Annotations: light},
		func(_ context.Context, _ *mcp.CallToolRequest, in freezeInput) (*mcp.CallToolResult, any, error) {
			if in.Scope == "" {
				return errtxt("informe scope: um id de VM ou 'all'"), nil, nil
			}
			if err := src.Freeze(in.Scope, in.Message); err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt("🧊 Deploys congelados para " + in.Scope + ". Propostas serao recusadas ate o unfreeze."), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_unfreeze_deploys", Description: "Descongela deploys de uma VM (id) ou 'all'.", Annotations: light},
		func(_ context.Context, _ *mcp.CallToolRequest, in unfreezeInput) (*mcp.CallToolResult, any, error) {
			if err := src.Unfreeze(in.Scope); err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt("✅ Descongelado: " + in.Scope), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_freeze_status", Description: "Lista o que esta congelado (janelas de manutencao ativas).", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, any, error) {
			out, err := src.Frozen()
			if err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt(out), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_cancel_request", Description: "Cancela um pedido de deploy PENDENTE (antes de aprovado). Quem pediu pode cancelar o proprio (cancelar != aprovar).", Annotations: light},
		func(_ context.Context, _ *mcp.CallToolRequest, in reqInput) (*mcp.CallToolResult, any, error) {
			if err := src.Cancel(in.RequestID); err != nil {
				return errtxt("erro: " + err.Error()), nil, nil
			}
			return txt("🗑️ Pedido " + in.RequestID + " cancelado."), nil, nil
		})

	addRead(s, "almirante_deploy_logs", "Log do ultimo deploy de uma VM (etapas + resultado).",
		func(_ context.Context, _ *mcp.CallToolRequest, in vmInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			h, _ := src.History(vm.ID)
			if len(h) == 0 {
				return txt("Sem deploy registrado para " + vm.Name), nil, nil
			}
			return txt(fmt.Sprintf("Ultimo deploy de %s: %s→%s por %s · %s · %ds\n(log completo via painel/journalctl no modo real)", vm.Name, h[0].FromSHA, h[0].ToSHA, h[0].Actor, h[0].Status, derefIntSafe(h[0].DurationS))), nil, nil
		})

	mcp.AddTool(s, &mcp.Tool{Name: "almirante_service_logs", Description: "Logs recentes do servico (web|worker) de uma VM. No modo real, journalctl via agente.", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, in serviceInput) (*mcp.CallToolResult, any, error) {
			vm, e := vmOK(in.VM)
			if e != "" {
				return errtxt(e), nil, nil
			}
			if in.Service != "web" && in.Service != "worker" {
				return errtxt("service deve ser 'web' ou 'worker'"), nil, nil
			}
			return txt(fmt.Sprintf("[%s/%s] logs recentes disponiveis via painel/journalctl no modo real (agente: journalctl -u chatwoot-%s.1.service).", vm.Name, in.Service, in.Service)), nil, nil
		})

	// ===== Toolset F — Governanca de IA (editar os agentes por VM) =====
	// Leitura (ro) + escrita (gated: test-gate + audit + rollback no control).
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_list_agents", Description: "Lista as VMs com governanca de IA (onde da pra editar prompt/tools/credencial dos agentes).", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, any, error) {
			v, err := src.AIListAgents()
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_list_assistants", Description: "Lista os agentes (id+name) de uma VM — pro seletor de agente, evita adivinhar o assistant_id.", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, in aiVMInput) (*mcp.CallToolResult, any, error) {
			v, err := src.AIListAssistants(in.VM)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_get_agent", Description: "Baseline de um agente (instructions, faqs, tools, behavior) por vm + assistant_id.", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, in aiAgentInput) (*mcp.CallToolResult, any, error) {
			v, err := src.AIBaseline(in.VM, in.AssistantID)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_history", Description: "Historico de mudancas de IA de uma VM (change-sets aplicados/revertidos, com change_set_id p/ rollback).", Annotations: ro},
		func(_ context.Context, _ *mcp.CallToolRequest, in aiVMInput) (*mcp.CallToolResult, any, error) {
			v, err := src.AIHistory(in.VM)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_update_prompt", Description: "Reescreve as instructions de um agente. Passa por test-gate (dry-run+smoke+juiz) ANTES de aplicar; auditado; reversivel. Requer admin.", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in aiPromptInput) (*mcp.CallToolResult, any, error) {
			v, err := src.AIPrompt(in.VM, in.AssistantID, in.Instructions, in.TargetEnv)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_set_tool", Description: "Arma/desarma uma tool built-in de um agente (armed=true arma e testa via perform_test; false desarma).", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in aiToolInput) (*mcp.CallToolResult, any, error) {
			v, err := src.AITool(in.VM, in.AssistantID, in.ToolID, in.Armed)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_set_credential", Description: "Define credencial de integracao da conta (provider vista|google) — testa a conexao real ANTES de salvar.", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in aiCredInput) (*mcp.CallToolResult, any, error) {
			v, err := src.AICredential(in.VM, in.Provider, in.Settings, in.Enabled)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_update_behavior", Description: "Ajusta o behavior do agente (debounce/humanizer/router/etc.) via merge de chaves.", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in aiBehaviorInput) (*mcp.CallToolResult, any, error) {
			v, err := src.AIBehavior(in.VM, in.AssistantID, in.Behavior)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_add_faq", Description: "Adiciona um FAQ (pergunta+resposta) a um agente.", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in aiFaqInput) (*mcp.CallToolResult, any, error) {
			v, err := src.AIFaq(in.VM, in.AssistantID, in.Question, in.Answer)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
	mcp.AddTool(s, &mcp.Tool{Name: "almirante_ai_rollback", Description: "Reverte um change-set de IA aplicado (restaura o snapshot na VM) pelo change_set_id (veja em almirante_ai_history).", Annotations: gated},
		func(_ context.Context, _ *mcp.CallToolRequest, in aiRollbackInput) (*mcp.CallToolResult, any, error) {
			v, err := src.AIRollback(in.VM, in.ChangeSetID)
			if err != nil {
				return errtxt(err.Error()), nil, nil
			}
			return jsonTxt(v), nil, nil
		})
}
