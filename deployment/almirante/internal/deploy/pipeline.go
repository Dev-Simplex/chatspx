package deploy

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Dev-Simplex/almirante/internal/types"
)

var AllowedUnits = map[string]bool{
	"chatwoot.target":            true,
	"chatwoot-web.1.service":     true,
	"chatwoot-worker.1.service":  true,
}

// Pipeline orquestra o deploy faseado na VM. Dependencias injetaveis (Ops/Gate/
// Now/Sleep/Log) para testar sem VM real.
type Pipeline struct {
	Ops          Ops
	Gate         *Gate
	Cfg          Config
	Now          func() time.Time
	Sleep        func(time.Duration)
	Log          func(string)
	HealthTries  int
	HealthDelay  time.Duration
}

func NewPipeline(cfg Config, ops Ops) *Pipeline {
	return &Pipeline{
		Ops: ops, Gate: NewGate(cfg.StateDir), Cfg: cfg,
		Now: time.Now, Sleep: time.Sleep, Log: func(string) {},
		HealthTries: 12, HealthDelay: 5 * time.Second,
	}
}

func (p *Pipeline) log(format string, a ...any) {
	if p.Log != nil {
		p.Log(fmt.Sprintf(format, a...))
	}
}

type Plan struct {
	Current    string                `json:"current"`
	Target     string                `json:"target"`
	Migrations types.MigrationStatus `json:"migrations"`
}

func (p *Pipeline) PlanFor(ctx context.Context, target string) (Plan, error) {
	cur, err := p.Ops.CurrentSHA(ctx)
	if err != nil {
		return Plan{}, err
	}
	mig, _ := p.Ops.MigrateStatus(ctx)
	return Plan{Current: cur, Target: target, Migrations: mig}, nil
}

// Deploy: gated -> faseado (precompile+migrate+restart SEMPRE em producao) ->
// health real -> rollback automatico se falhar. backupDone libera destrutiva.
func (p *Pipeline) Deploy(ctx context.Context, sha string, backupDone bool) error {
	if err := p.Gate.RequireApproval(sha); err != nil {
		return err
	}
	prev, err := p.Ops.CurrentSHA(ctx)
	if err != nil {
		return fmt.Errorf("nao consegui ler SHA atual: %w", err)
	}
	p.log("deploy %s (anterior %s)", sha, prev)

	// Pre-flight: bloquear destrutiva sem backup verificado.
	mig, _ := p.Ops.MigrateStatus(ctx)
	if mig.HasDestructive && !backupDone {
		return fmt.Errorf("migration DESTRUTIVA pendente — faca backup verificado e reaprove com backup_done=true")
	}

	steps := []struct {
		name string
		fn   func() error
	}{
		{"checkout", func() error { return p.Ops.FetchAndCheckout(ctx, sha) }},
		{"build", func() error { return p.Ops.Build(ctx) }},
		{"precompile", func() error { return p.Ops.Precompile(ctx) }},
		{"migrate", func() error { return p.Ops.Migrate(ctx, "") }},
		{"restart", func() error { return p.Ops.Restart(ctx, "chatwoot.target") }},
	}
	for _, s := range steps {
		p.log("etapa: %s", s.name)
		if err := s.fn(); err != nil {
			return p.rollbackOnFail(ctx, prev, sha, fmt.Sprintf("etapa %s falhou: %v", s.name, err))
		}
	}

	// Health real com retry.
	if !p.waitHealthy(ctx) {
		return p.rollbackOnFail(ctx, prev, sha, "health-check falhou")
	}

	p.writeLastGood(prev)
	p.Gate.Clear(sha)
	p.log("DEPLOY OK %s — health verde", sha)
	return nil
}

func (p *Pipeline) waitHealthy(ctx context.Context) bool {
	for i := 0; i < p.HealthTries; i++ {
		if p.Ops.Health(ctx).Healthy {
			return true
		}
		if i < p.HealthTries-1 {
			p.Sleep(p.HealthDelay)
		}
	}
	return false
}

func (p *Pipeline) rollbackOnFail(ctx context.Context, prev, sha, reason string) error {
	p.log("FALHA (%s) — rollback automatico para %s", reason, prev)
	_ = p.Ops.FetchAndCheckout(ctx, prev)
	_ = p.Ops.Restart(ctx, "chatwoot.target")
	p.Gate.Clear(sha)
	return fmt.Errorf("%s; rollback para %s aplicado", reason, prev)
}

// Rollback manual para o ultimo SHA bom (NAO reverte migrations/dados).
func (p *Pipeline) Rollback(ctx context.Context) error {
	target := p.readLastGood()
	if target == "" {
		return fmt.Errorf("sem last_good_sha registrado")
	}
	p.log("rollback para %s (ATENCAO: migrations NAO sao revertidas)", target)
	if err := p.Ops.FetchAndCheckout(ctx, target); err != nil {
		return err
	}
	if err := p.Ops.Precompile(ctx); err != nil {
		return err
	}
	if err := p.Ops.Restart(ctx, "chatwoot.target"); err != nil {
		return err
	}
	if !p.waitHealthy(ctx) {
		return fmt.Errorf("rollback para %s nao ficou saudavel", target)
	}
	return nil
}

// RestartUnit: gated (respeita "restart so o usuario faz") + pre-flight de migration.
func (p *Pipeline) RestartUnit(ctx context.Context, unit string) error {
	if !AllowedUnits[unit] {
		return fmt.Errorf("unit nao permitida: %s", unit)
	}
	if err := p.Gate.RequireApproval("restart-" + sanitizeUnit(unit)); err != nil {
		return err
	}
	mig, _ := p.Ops.MigrateStatus(ctx)
	if !mig.UpToDate {
		return fmt.Errorf("restart bloqueado: %d migration(s) pendente(s) (restart com pendente = 500 em cadeia)", len(mig.Pending))
	}
	return p.Ops.Restart(ctx, unit)
}

func sanitizeUnit(u string) string { return strings.ReplaceAll(u, ".", "_") }

func (p *Pipeline) writeLastGood(sha string) {
	_ = os.MkdirAll(p.Cfg.StateDir, 0o750)
	_ = os.WriteFile(filepath.Join(p.Cfg.StateDir, "last_good_sha"), []byte(sha), 0o640)
}

func (p *Pipeline) readLastGood() string {
	b, err := os.ReadFile(filepath.Join(p.Cfg.StateDir, "last_good_sha"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}
