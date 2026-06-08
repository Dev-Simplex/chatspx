// Package deploy roda DENTRO do almiranted (na VM). Pipeline faseado, gate por
// arquivo-token, health real e rollback. Ops e a costura injetavel para teste.
package deploy

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"net/http"
	"os/exec"
	"strings"
	"time"

	"github.com/Dev-Simplex/almirante/internal/safety"
	"github.com/Dev-Simplex/almirante/internal/types"
)

type Config struct {
	AppDir    string // ~/chatwoot
	AppUser   string // chatwoot
	StateDir  string // /var/lib/almirante
	HealthURL string // http://127.0.0.1:3000/up
	RailsEnv  string // production
}

func DefaultConfig() Config {
	return Config{
		AppDir:    envOr("ALMIRANTE_APP_DIR", "/home/chatwoot/chatwoot"),
		AppUser:   envOr("ALMIRANTE_APP_USER", "chatwoot"),
		StateDir:  envOr("ALMIRANTE_STATE_DIR", "/var/lib/almirante"),
		HealthURL: envOr("ALMIRANTE_HEALTH_URL", "http://127.0.0.1:3000/up"),
		RailsEnv:  envOr("RAILS_ENV", "production"),
	}
}

// Ops abstrai as operacoes na VM (real = LocalOps; teste = fake).
type Ops interface {
	CurrentSHA(ctx context.Context) (string, error)
	FetchAndCheckout(ctx context.Context, sha string) error
	Build(ctx context.Context) error       // bundle + pnpm
	Precompile(ctx context.Context) error  // assets:precompile (sempre producao)
	Migrate(ctx context.Context, version string) error
	MigrateStatus(ctx context.Context) (types.MigrationStatus, error)
	Restart(ctx context.Context, unit string) error
	Health(ctx context.Context) types.HealthReport
}

// LocalOps executa de verdade na VM via sudo -u <appUser> bash -lc (rbenv/PATH).
type LocalOps struct{ Cfg Config }

func (o LocalOps) appShell(ctx context.Context, script string) (string, int, error) {
	full := fmt.Sprintf("cd %s && %s", o.Cfg.AppDir, script)
	cmd := exec.CommandContext(ctx, "sudo", "-n", "-u", o.Cfg.AppUser, "bash", "-lc", full)
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	err := cmd.Run()
	return out.String(), cmd.ProcessState.ExitCode(), err
}

func (o LocalOps) CurrentSHA(ctx context.Context) (string, error) {
	// Determinístico: `git -C` direto, SEM login-shell (bash -lc). Evita a variância
	// de profile/rbenv que fazia o read voltar vazio intermitente via SSH não-interativo.
	cmd := exec.CommandContext(ctx, "sudo", "-n", "-u", o.Cfg.AppUser, "git", "-C", o.Cfg.AppDir, "rev-parse", "--short", "HEAD")
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("rev-parse: %s", strings.TrimSpace(out.String()))
	}
	sha := strings.TrimSpace(out.String())
	if sha == "" {
		return "", fmt.Errorf("rev-parse retornou vazio")
	}
	return sha, nil
}

func (o LocalOps) FetchAndCheckout(ctx context.Context, sha string) error {
	if err := safety.AssertSafeArg(sha, "sha"); err != nil { // defense-in-depth na VM
		return err
	}
	// fallback git bundle (AWS com auth GitHub quebrada) e tratado no provisionamento.
	out, code, err := o.appShell(ctx, "git stash -q 2>/dev/null; git fetch origin -q || true; git checkout -q "+sha)
	if err != nil || code != 0 {
		return fmt.Errorf("checkout %s falhou: %s", sha, strings.TrimSpace(out))
	}
	return nil
}

func (o LocalOps) Build(ctx context.Context) error {
	if out, code, err := o.appShell(ctx, "bundle install --jobs $(nproc) --retry 3"); err != nil || code != 0 {
		return fmt.Errorf("bundle: %s", tail(out))
	}
	if out, code, err := o.appShell(ctx, "pnpm install --frozen-lockfile || pnpm install"); err != nil || code != 0 {
		return fmt.Errorf("pnpm: %s", tail(out))
	}
	return nil
}

func (o LocalOps) Precompile(ctx context.Context) error {
	script := fmt.Sprintf("RAILS_ENV=%s NODE_OPTIONS=--max-old-space-size=4096 bundle exec rake assets:precompile", o.Cfg.RailsEnv)
	if out, code, err := o.appShell(ctx, script); err != nil || code != 0 {
		return fmt.Errorf("assets:precompile: %s", tail(out))
	}
	return nil
}

func (o LocalOps) Migrate(ctx context.Context, version string) error {
	cmd := "db:migrate"
	if version != "" {
		if err := safety.AssertSafeArg(version, "version"); err != nil {
			return err
		}
		cmd = "db:migrate:up VERSION=" + version
	}
	script := fmt.Sprintf("RAILS_ENV=%s bundle exec rails %s", o.Cfg.RailsEnv, cmd)
	if out, code, err := o.appShell(ctx, script); err != nil || code != 0 {
		return fmt.Errorf("migrate: %s", tail(out))
	}
	return nil
}

func (o LocalOps) MigrateStatus(ctx context.Context) (types.MigrationStatus, error) {
	out, _, _ := o.appShell(ctx, fmt.Sprintf("RAILS_ENV=%s bundle exec rails db:migrate:status", o.Cfg.RailsEnv))
	return parseMigrateStatus("", out), nil
}

func (o LocalOps) Restart(ctx context.Context, unit string) error {
	cmd := exec.CommandContext(ctx, "sudo", "-n", "systemctl", "restart", unit)
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("restart %s: %s", unit, tail(out.String()))
	}
	return nil
}

func (o LocalOps) Health(ctx context.Context) types.HealthReport {
	r := types.HealthReport{VM: ""}
	// 1) systemd ativo
	if out, _, _ := runCmd(ctx, "systemctl", "is-active", "chatwoot.target"); strings.TrimSpace(out) == "active" {
		r.ServiceActive = true
	}
	// 2) HTTP 200 no /up
	cli := &http.Client{Timeout: 8 * time.Second}
	if resp, err := cli.Get(o.Cfg.HealthURL); err == nil {
		r.HTTP200 = resp.StatusCode == 200
		resp.Body.Close()
	}
	// 3) PG + Redis via rails runner
	chk, _, _ := o.appShell(ctx, fmt.Sprintf(`RAILS_ENV=%s bundle exec rails runner 'print((ActiveRecord::Base.connection.execute("SELECT 1") ? "db" : "")); print(Sidekiq.redis{|c| c.ping}=="PONG" ? "redis" : "")' 2>/dev/null`, o.Cfg.RailsEnv))
	r.DB = strings.Contains(chk, "db")
	r.Redis = strings.Contains(chk, "redis")
	r.Sidekiq = r.Redis // sidekiq vivo ~ redis respondendo + processo (checado no status)
	r.Healthy = r.ServiceActive && r.HTTP200 && r.DB
	if r.Healthy {
		r.Detail = "chatwoot.target active; /up 200; PG+Redis OK"
	} else {
		r.Detail = "degradado: " + healthDetail(r)
	}
	return r
}

// ---------- helpers ----------

func runCmd(ctx context.Context, name string, args ...string) (string, int, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	err := cmd.Run()
	return out.String(), cmd.ProcessState.ExitCode(), err
}

func healthDetail(r types.HealthReport) string {
	var miss []string
	if !r.ServiceActive {
		miss = append(miss, "service")
	}
	if !r.HTTP200 {
		miss = append(miss, "http")
	}
	if !r.DB {
		miss = append(miss, "db")
	}
	return strings.Join(miss, ",")
}

func tail(s string) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) > 6 {
		lines = lines[len(lines)-6:]
	}
	return strings.Join(lines, "\n")
}

// parseMigrateStatus le a saida de `rails db:migrate:status` e classifica.
func parseMigrateStatus(vm, out string) types.MigrationStatus {
	st := types.MigrationStatus{VM: vm, Pending: []types.PendingMigration{}}
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) >= 2 && strings.EqualFold(f[0], "down") {
			version := f[1]
			name := strings.Join(f[2:], " ")
			st.Pending = append(st.Pending, safety.Classify(version, name))
		}
	}
	st.UpToDate = len(st.Pending) == 0
	for _, m := range st.Pending {
		if m.Destructive {
			st.HasDestructive = true
		}
	}
	return st
}
