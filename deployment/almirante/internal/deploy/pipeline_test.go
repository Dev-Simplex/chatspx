package deploy

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/Dev-Simplex/almirante/internal/types"
)

// fakeOps implementa Ops sem tocar VM, registrando as chamadas.
type fakeOps struct {
	cur          string
	mig          types.MigrationStatus
	healthyAfter int // fica saudavel a partir da n-esima checagem
	checks       int
	calls        []string
	buildErr     error
}

func (f *fakeOps) CurrentSHA(context.Context) (string, error) { return f.cur, nil }
func (f *fakeOps) FetchAndCheckout(_ context.Context, sha string) error {
	f.calls = append(f.calls, "checkout:"+sha)
	f.cur = sha
	return nil
}
func (f *fakeOps) Build(context.Context) error      { f.calls = append(f.calls, "build"); return f.buildErr }
func (f *fakeOps) Precompile(context.Context) error { f.calls = append(f.calls, "precompile"); return nil }
func (f *fakeOps) Migrate(_ context.Context, v string) error {
	f.calls = append(f.calls, "migrate:"+v)
	return nil
}
func (f *fakeOps) MigrateStatus(context.Context) (types.MigrationStatus, error) { return f.mig, nil }
func (f *fakeOps) Restart(_ context.Context, u string) error {
	f.calls = append(f.calls, "restart:"+u)
	return nil
}
func (f *fakeOps) Health(context.Context) types.HealthReport {
	f.checks++
	return types.HealthReport{Healthy: f.checks >= f.healthyAfter}
}

func newPipe(t *testing.T, ops Ops) *Pipeline {
	t.Helper()
	cfg := Config{StateDir: t.TempDir(), RailsEnv: "production"}
	p := NewPipeline(cfg, ops)
	p.Sleep = func(time.Duration) {}
	p.HealthTries = 3
	p.HealthDelay = 0
	return p
}

func TestDeploy_RequiresApproval(t *testing.T) {
	p := newPipe(t, &fakeOps{cur: "aaaaaaa", healthyAfter: 1})
	err := p.Deploy(context.Background(), "bbbbbbb", false)
	if err == nil || !strings.Contains(err.Error(), "NAO aprovado") {
		t.Fatalf("esperava erro de aprovacao, veio: %v", err)
	}
}

func TestDeploy_HappyPath(t *testing.T) {
	ops := &fakeOps{cur: "aaaaaaa", healthyAfter: 1}
	p := newPipe(t, ops)
	if err := p.Gate.Approve("bbbbbbb", "tester", time.Hour); err != nil {
		t.Fatal(err)
	}
	if err := p.Deploy(context.Background(), "bbbbbbb", false); err != nil {
		t.Fatalf("deploy deveria passar: %v", err)
	}
	want := []string{"checkout:bbbbbbb", "build", "precompile", "migrate:", "restart:chatwoot.target"}
	got := strings.Join(ops.calls, ",")
	for _, w := range want {
		if !strings.Contains(got, w) {
			t.Errorf("faltou etapa %q em %q", w, got)
		}
	}
	if p.readLastGood() != "aaaaaaa" {
		t.Errorf("last_good_sha = %q, queria aaaaaaa", p.readLastGood())
	}
}

func TestDeploy_DestructiveNeedsBackup(t *testing.T) {
	ops := &fakeOps{
		cur:          "aaaaaaa",
		healthyAfter: 1,
		mig:          types.MigrationStatus{HasDestructive: true, Pending: []types.PendingMigration{{Version: "20260330120000", Destructive: true}}},
	}
	p := newPipe(t, ops)
	_ = p.Gate.Approve("bbbbbbb", "tester", time.Hour)
	err := p.Deploy(context.Background(), "bbbbbbb", false)
	if err == nil || !strings.Contains(err.Error(), "DESTRUTIVA") {
		t.Fatalf("esperava bloqueio de destrutiva, veio: %v", err)
	}
	// com backup confirmado, prossegue
	_ = p.Gate.Approve("bbbbbbb", "tester", time.Hour)
	if err := p.Deploy(context.Background(), "bbbbbbb", true); err != nil {
		t.Fatalf("com backup deveria passar: %v", err)
	}
}

func TestDeploy_HealthFailRollsBack(t *testing.T) {
	ops := &fakeOps{cur: "aaaaaaa", healthyAfter: 99} // nunca saudavel
	p := newPipe(t, ops)
	_ = p.Gate.Approve("bbbbbbb", "tester", time.Hour)
	err := p.Deploy(context.Background(), "bbbbbbb", false)
	if err == nil || !strings.Contains(err.Error(), "rollback") {
		t.Fatalf("esperava rollback, veio: %v", err)
	}
	// deve ter feito checkout de volta para o prev (aaaaaaa)
	if got := strings.Join(ops.calls, ","); !strings.Contains(got, "checkout:aaaaaaa") {
		t.Errorf("rollback nao voltou pro prev: %q", got)
	}
}

func TestRestartUnit_BlocksOnPendingMigration(t *testing.T) {
	ops := &fakeOps{cur: "aaaaaaa", mig: types.MigrationStatus{Pending: []types.PendingMigration{{Version: "x"}}}}
	p := newPipe(t, ops)
	_ = p.Gate.Approve("restart-chatwoot_target", "tester", time.Hour)
	err := p.RestartUnit(context.Background(), "chatwoot.target")
	if err == nil || !strings.Contains(err.Error(), "pendente") {
		t.Fatalf("esperava bloqueio por migration pendente, veio: %v", err)
	}
}
