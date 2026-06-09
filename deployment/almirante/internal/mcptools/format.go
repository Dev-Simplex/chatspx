package mcptools

import (
	"fmt"
	"strings"

	"github.com/Dev-Simplex/almirante/internal/types"
)

func dot(ok bool) string {
	if ok {
		return "🟢"
	}
	return "🔴"
}
func pct(p *int) string {
	if p == nil {
		return "—"
	}
	return fmt.Sprintf("%d%%", *p)
}

func fmtStatus(vm types.VM, s types.HostStatus) string {
	if !s.Online {
		return fmt.Sprintf("%s %s (%s) — OFFLINE / inacessivel.", dot(false), vm.Name, vm.Env)
	}
	return fmt.Sprintf("%s %s (%s) — %s\ncommit %s (branch %s) · %d puma / %d sidekiq\ncpu %s · ram %s · disco %s · ping %dms · up %s",
		dot(s.ServiceActive), vm.Name, vm.Env,
		map[bool]string{true: "chatwoot.target ATIVO", false: "servico INATIVO"}[s.ServiceActive],
		s.Commit, s.Branch, s.Puma, s.Sidekiq, pct(s.CPU), pct(s.RAM), pct(s.Disk), derefInt(s.PingMS), s.Uptime)
}

func derefInt(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}

func fmtHealth(vm types.VM, h types.HealthReport) string {
	return fmt.Sprintf("%s %s — %s\ndb %s · redis %s · sidekiq %s · http200 %s · migrations %s\n%s",
		dot(h.Healthy), vm.Name, map[bool]string{true: "SAUDAVEL", false: "NAO-SAUDAVEL"}[h.Healthy],
		dot(h.DB), dot(h.Redis), dot(h.Sidekiq), dot(h.HTTP200),
		map[bool]string{true: "em dia", false: "PENDENTES"}[h.MigrationsUpToDate], h.Detail)
}

func fmtMig(vm types.VM, m types.MigrationStatus) string {
	if m.UpToDate {
		return fmt.Sprintf("%s %s — migrations em dia, nada pendente.", dot(true), vm.Name)
	}
	var b strings.Builder
	head := "🟡"
	if m.HasDestructive {
		head = "⚠️"
	}
	fmt.Fprintf(&b, "%s %s — %d migration(s) pendente(s)", head, vm.Name, len(m.Pending))
	if m.HasDestructive {
		b.WriteString(" (INCLUI DESTRUTIVA — deploy sera bloqueado p/ aprovacao manual + backup)")
	}
	b.WriteString(":\n")
	for _, p := range m.Pending {
		mark := "✅ segura"
		if p.Destructive {
			mark = "⚠️ DESTRUTIVA"
		}
		fmt.Fprintf(&b, "  %s %s %s", mark, p.Version, p.Name)
		if p.Reason != "" {
			fmt.Fprintf(&b, " — %s", p.Reason)
		}
		b.WriteString("\n")
	}
	return b.String()
}

func fmtDiff(vm types.VM, d types.GitDiff) string {
	if d.BehindCount == 0 {
		return fmt.Sprintf("%s ja esta no ultimo commit (%s).", vm.Name, d.CurrentSHA)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s: %s → %s (%d commits atras)\n", vm.Name, d.CurrentSHA, d.TargetSHA, d.BehindCount)
	for _, c := range d.Commits {
		fmt.Fprintf(&b, "  %s %s\n", c.SHA, c.Subject)
	}
	if d.CompareURL != "" {
		fmt.Fprintf(&b, "diff: %s", d.CompareURL)
	}
	return b.String()
}

func fmtRequest(vm types.VM, r types.DeployRequest) string {
	var b strings.Builder
	fmt.Fprintf(&b, "📋 Pedido de deploy %s — %s\n", r.ID, vm.Name)
	fmt.Fprintf(&b, "%s → %s (branch %s) · pedido por %s\n", r.CurrentSHA, r.TargetSHA, r.Branch, r.RequestedBy)
	if len(r.Migrations) == 0 {
		b.WriteString("migrations: nenhuma\n")
	} else {
		parts := make([]string, len(r.Migrations))
		for i, m := range r.Migrations {
			mk := "✅"
			if m.Destructive {
				mk = "⚠️"
			}
			parts[i] = mk + " " + m.Version
		}
		fmt.Fprintf(&b, "migrations: %s\n", strings.Join(parts, ", "))
	}
	if r.HasDestructive {
		b.WriteString("⚠️ Contem migration DESTRUTIVA → exige aprovacao manual + backup.\n")
	}
	b.WriteString("➡️  Apenas ENFILEIRADO. Eu (a IA) NAO aprovo nem executo — um humano aprova no painel.")
	return b.String()
}
