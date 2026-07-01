package control

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/Dev-Simplex/almirante/internal/aiconfig"
	"github.com/Dev-Simplex/almirante/internal/mock"
	"github.com/Dev-Simplex/almirante/internal/safety"
	sshx "github.com/Dev-Simplex/almirante/internal/ssh"
	"github.com/Dev-Simplex/almirante/internal/types"
)

type Config struct {
	Mock          bool
	Fleet         *types.Fleet
	SSH           sshx.Config
	ApprovalTTL   time.Duration
	MergeCloneDir string // clone dedicado p/ merges (NUNCA o working tree de prod)
	RepoURL       string // origin p/ o clone de merge
	// Governanca de IA (opcional): nil = feature off (VMs sem receptor spx/ai_config).
	AIDriver *aiconfig.Driver
	AIGate   *aiconfig.TestGate
}

// Executor faz a ponte control -> almiranted (real via SSH, ou mock local).
type Executor struct{ Cfg Config }

func (e Executor) vm(id string) (types.VM, error) {
	for _, v := range e.Cfg.Fleet.VMs {
		if v.ID == id {
			return v, nil
		}
	}
	return types.VM{}, fmt.Errorf("VM desconhecida: %s", id)
}

func (e Executor) Status(ctx context.Context, id string) (types.HostStatus, error) {
	v, err := e.vm(id)
	if err != nil {
		return types.HostStatus{}, err
	}
	if e.Cfg.Mock {
		return mock.HostStatus(id, v.Branch), nil
	}
	// Retry: o 1o `current` pode voltar vazio (login-shell `bash -lc` frio na VM).
	// Re-tenta ate 3x — a chamada aquece a VM e o SHA estabiliza.
	var out string
	var err2 error
	for try := 1; try <= 3; try++ {
		out, err2 = sshx.RunAlmiranted(ctx, e.Cfg.SSH, v, []string{"current"})
		if err2 == nil && strings.TrimSpace(out) != "" {
			break
		}
		fmt.Fprintf(os.Stderr, "[ssh %s] current tentativa %d: err=%v out=%q\n", id, try, err2, strings.TrimSpace(out))
	}
	if err2 != nil {
		return types.HostStatus{VM: id, Online: false}, nil
	}
	return types.HostStatus{VM: id, Online: true, Commit: strings.TrimSpace(out), Branch: v.Branch}, nil
}

func (e Executor) Migrations(ctx context.Context, id string) (types.MigrationStatus, error) {
	v, err := e.vm(id)
	if err != nil {
		return types.MigrationStatus{}, err
	}
	if e.Cfg.Mock {
		return mock.MigrationStatus(id), nil
	}
	out, err := sshx.RunAlmiranted(ctx, e.Cfg.SSH, v, []string{"migrate-status"})
	if err != nil {
		return types.MigrationStatus{VM: id}, err
	}
	var st types.MigrationStatus
	_ = json.Unmarshal([]byte(out), &st)
	st.VM = id
	for i := range st.Pending {
		st.Pending[i] = safety.Classify(st.Pending[i].Version, st.Pending[i].Name)
		if st.Pending[i].Destructive {
			st.HasDestructive = true
		}
	}
	st.UpToDate = len(st.Pending) == 0
	return st, nil
}

func (e Executor) Health(ctx context.Context, id string) (types.HealthReport, error) {
	v, err := e.vm(id)
	if err != nil {
		return types.HealthReport{}, err
	}
	if e.Cfg.Mock {
		return mock.Health(id), nil
	}
	out, err := sshx.RunAlmiranted(ctx, e.Cfg.SSH, v, []string{"health"})
	if err != nil {
		return types.HealthReport{VM: id}, err
	}
	var h types.HealthReport
	_ = json.Unmarshal([]byte(out), &h)
	h.VM = id
	return h, nil
}

// Metrics: status rico (uptime/cpu/ram/disco/servicos) p/ o card expandido.
func (e Executor) Metrics(ctx context.Context, id string) (types.HostStatus, error) {
	v, err := e.vm(id)
	if err != nil {
		return types.HostStatus{}, err
	}
	if e.Cfg.Mock {
		return mock.HostStatus(id, v.Branch), nil
	}
	out, err := sshx.RunAlmiranted(ctx, e.Cfg.SSH, v, []string{"metrics"})
	if err != nil {
		return types.HostStatus{VM: id, Online: false}, nil
	}
	var s types.HostStatus
	_ = json.Unmarshal([]byte(out), &s)
	s.VM, s.Branch = id, v.Branch
	return s, nil
}

var restartAllowed = map[string]bool{
	"chatwoot.target": true, "chatwoot-web.1.service": true, "chatwoot-worker.1.service": true,
	"chatwoot-worker.bulk.service": true, "chatwoot-worker.realtime.service": true,
}

// Restart: acao direta (admin) — reinicia uma unit permitida via almiranted.
func (e Executor) Restart(ctx context.Context, id, unit string) error {
	v, err := e.vm(id)
	if err != nil {
		return err
	}
	if !restartAllowed[unit] {
		return fmt.Errorf("unit nao permitida: %s", unit)
	}
	if e.Cfg.Mock {
		return nil
	}
	_, err = sshx.RunAlmiranted(ctx, e.Cfg.SSH, v, []string{"restart", unit})
	return err
}

func (e Executor) Diff(ctx context.Context, id string) (types.GitDiff, error) {
	if e.Cfg.Mock {
		return mock.GitDiff(id, e.Cfg.Fleet.GitHubRepo), nil
	}
	st, _ := e.Status(ctx, id)
	gd := types.GitDiff{VM: id, CurrentSHA: st.Commit}
	// resolve o alvo (HEAD de origin/<branch>) via ls-remote no control — usa o PAT no RepoURL.
	// sem isso, o TargetSHA fica vazio e o checkout do deploy falha.
	if v, err := e.vm(id); err == nil {
		if target := e.remoteSHA(ctx, v.Branch); target != "" {
			gd.TargetSHA = target
			if st.Commit != "" && !strings.HasPrefix(target, st.Commit) {
				gd.BehindCount = 1 // tem atualizacao (contagem exata exigiria clone)
			}
		}
	}
	return gd, nil
}

// remoteSHA devolve o HEAD curto de origin/<branch> via `git ls-remote` (no container do control).
func (e Executor) remoteSHA(ctx context.Context, branch string) string {
	if branch == "" || e.Cfg.RepoURL == "" {
		return ""
	}
	out, err := exec.CommandContext(ctx, "git", "ls-remote", e.Cfg.RepoURL, "refs/heads/"+branch).Output()
	if err != nil {
		return ""
	}
	fields := strings.Fields(string(out))
	if len(fields) == 0 {
		return ""
	}
	sha := fields[0]
	if len(sha) > 9 {
		sha = sha[:9]
	}
	return sha
}

func (e Executor) History(_ context.Context, id string) ([]types.DeployHistoryEntry, error) {
	if e.Cfg.Mock {
		return mock.History(id), nil
	}
	return []types.DeployHistoryEntry{}, nil
}

// ApproveAndDeploy: chamado SO pelo endpoint /approve (apos RBAC admin + anti-self-review).
func (e Executor) ApproveAndDeploy(ctx context.Context, id, sha, approver string) (bool, string) {
	v, err := e.vm(id)
	if err != nil {
		return false, err.Error()
	}
	if e.Cfg.Mock {
		return true, fmt.Sprintf("[MOCK] approve+deploy %s em %s por %s", sha, id, approver)
	}
	if _, err := sshx.RunAlmiranted(ctx, e.Cfg.SSH, v, []string{"approve", sha, approver}); err != nil {
		return false, "approve falhou: " + err.Error()
	}
	if _, err := sshx.RunAlmiranted(ctx, e.Cfg.SSH, v, []string{"deploy", sha}); err != nil {
		return false, "deploy falhou: " + err.Error()
	}
	return true, "deploy OK, health verde"
}
