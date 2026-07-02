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
	"strconv"
	"strings"
	"time"

	"github.com/Dev-Simplex/almirante/internal/safety"
	"github.com/Dev-Simplex/almirante/internal/types"
)

type Config struct {
	AppDir    string // ~/chatwoot
	AppUser   string // chatwoot
	StateDir  string // /var/lib/almirante
	HealthURL string // http://127.0.0.1:3000/ (raiz responde 200; /up nao existe nesta versao)
	RailsEnv  string // production
}

func DefaultConfig() Config {
	return Config{
		AppDir:    envOr("ALMIRANTE_APP_DIR", "/home/chatwoot/chatwoot"),
		AppUser:   envOr("ALMIRANTE_APP_USER", "chatwoot"),
		StateDir:  envOr("ALMIRANTE_STATE_DIR", "/var/lib/almirante"),
		HealthURL: envOr("ALMIRANTE_HEALTH_URL", "http://127.0.0.1:3000/"),
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
	// heap do node = ~75% da RAM da VM (piso 4096MB). O build do Vite estoura o teto
	// fixo de 4GB mesmo com RAM sobrando; aqui liberamos a memoria da VM toda.
	script := fmt.Sprintf("HEAP=$(free -m | awk '/^Mem:/{h=int($2*0.75); print (h<4096?4096:h)}'); RAILS_ENV=%s NODE_OPTIONS=--max-old-space-size=$HEAP bundle exec rake assets:precompile", o.Cfg.RailsEnv)
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
	// 2) HTTP servindo: aceita 2xx/3xx na raiz (redirect p/ login conta como vivo).
	cli := &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	if resp, err := cli.Get(o.Cfg.HealthURL); err == nil {
		r.HTTP200 = resp.StatusCode >= 200 && resp.StatusCode < 400
		resp.Body.Close()
	}
	// 3) PG + Redis via rails runner
	chk, _, _ := o.appShell(ctx, fmt.Sprintf(`RAILS_ENV=%s bundle exec rails runner 'print((ActiveRecord::Base.connection.execute("SELECT 1") ? "db" : "")); print(Sidekiq.redis{|c| c.ping}=="PONG" ? "redis" : "")' 2>/dev/null`, o.Cfg.RailsEnv))
	r.DB = strings.Contains(chk, "db")
	r.Redis = strings.Contains(chk, "redis")
	r.Sidekiq = r.Redis // sidekiq vivo ~ redis respondendo + processo (checado no status)
	r.Healthy = r.ServiceActive && r.HTTP200 && r.DB
	if r.Healthy {
		r.Detail = "chatwoot.target active; HTTP 2xx/3xx; PG+Redis OK"
	} else {
		r.Detail = "degradado: " + healthDetail(r)
	}
	return r
}

// SysInfo coleta metricas leves da VM (uptime/cpu/ram/disco/servicos) p/ o card expandido.
// Comandos sem sudo (uptime/free/df/systemctl is-active/pgrep); commit via sudo -u (CurrentSHA).
func (o LocalOps) SysInfo(ctx context.Context) types.HostStatus {
	s := types.HostStatus{Online: true}
	s.Commit, _ = o.CurrentSHA(ctx)
	s.Uptime = strings.TrimSpace(strings.TrimPrefix(cmdOut(ctx, "uptime", "-p"), "up "))
	if la := cmdOut(ctx, "cat", "/proc/loadavg"); la != "" {
		if f := strings.Fields(la); len(f) > 0 {
			if load, err := strconv.ParseFloat(f[0], 64); err == nil {
				if np, _ := strconv.Atoi(strings.TrimSpace(cmdOut(ctx, "nproc"))); np > 0 {
					c := int(load / float64(np) * 100)
					if c > 100 {
						c = 100
					}
					s.CPU = &c
				}
			}
		}
	}
	for _, ln := range strings.Split(cmdOut(ctx, "free", "-m"), "\n") {
		if strings.HasPrefix(ln, "Mem:") {
			if f := strings.Fields(ln); len(f) >= 7 {
				total, _ := strconv.Atoi(f[1])
				avail, _ := strconv.Atoi(f[6])
				if total > 0 {
					r := (total - avail) * 100 / total
					s.RAM = &r
				}
			}
		}
	}
	for _, ln := range strings.Split(cmdOut(ctx, "df", "-P", "/"), "\n") {
		if f := strings.Fields(ln); len(f) >= 5 && strings.HasSuffix(f[4], "%") {
			if d, err := strconv.Atoi(strings.TrimSuffix(f[4], "%")); err == nil {
				s.Disk = &d
			}
		}
	}
	s.ServiceActive = strings.TrimSpace(cmdOut(ctx, "systemctl", "is-active", "chatwoot-web.1.service")) == "active"
	// -fc: casa o cmdline completo (o comm dos processos Ruby e "ruby", nao "puma"/"sidekiq").
	s.Puma = atoiSafe(cmdOut(ctx, "pgrep", "-fc", "puma"))
	s.Sidekiq = atoiSafe(cmdOut(ctx, "pgrep", "-fc", "sidekiq"))
	return s
}

func cmdOut(ctx context.Context, name string, args ...string) string {
	out, _, _ := runCmd(ctx, name, args...)
	return out
}
func atoiSafe(s string) int { n, _ := strconv.Atoi(strings.TrimSpace(s)); return n }

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
