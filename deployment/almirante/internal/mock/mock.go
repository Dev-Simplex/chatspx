// Package mock fornece dados deterministicos para demo (ALMIRANTE_MOCK=1) — sem SSH.
package mock

import (
	"fmt"

	"github.com/Dev-Simplex/almirante/internal/safety"
	"github.com/Dev-Simplex/almirante/internal/types"
)

const head = "d4e5f6a"

type profile struct {
	online, service       bool
	puma, sidekiq         int
	cpu, ram, disk, ping  int
	commit, uptime        string
	pending               [][2]string // {version, name}
	target                string
	behind                int
}

var profiles = map[string]profile{
	"producao":    {true, true, 4, 2, 38, 61, 52, 12, "c052f22", "8 dias", nil, head, 6},
	"catatau":     {true, true, 3, 2, 22, 48, 40, 89, "c052f22", "5 dias", nil, head, 6},
	"sentinela":   {true, true, 3, 1, 31, 55, 44, 94, "9909fe4", "2 dias", [][2]string{{"20260520100000", "add_index_to_conversations"}}, head, 9},
	"tozi":        {true, true, 3, 2, 27, 58, 49, 91, "88da75b", "12 dias", [][2]string{{"20260330120000", "add_foreign_key_constraints"}, {"20260521090000", "add_column_last_seen_to_contacts"}}, head, 14},
	"fabrica":     {true, true, 2, 1, 18, 41, 37, 87, "c052f22", "1 dia", nil, head, 6},
	"alternativo": {false, false, 0, 0, 0, 0, 0, 0, "9909fe4", "", nil, head, 9},
	"paulao":      {true, true, 2, 1, 12, 35, 28, 9, "a1b2c3d", "4h", [][2]string{{"20260522110000", "add_settings_to_accounts"}}, "b9c8d7e", 3},
}

func get(vm string) profile {
	if p, ok := profiles[vm]; ok {
		return p
	}
	return profiles["producao"]
}

func ip(n int) *int { return &n }

func HostStatus(vm, branch string) types.HostStatus {
	p := get(vm)
	s := types.HostStatus{VM: vm, Online: p.online, ServiceActive: p.service, Puma: p.puma, Sidekiq: p.sidekiq, Commit: p.commit, Branch: branch, Uptime: p.uptime}
	if p.online {
		s.CPU, s.RAM, s.Disk, s.PingMS = ip(p.cpu), ip(p.ram), ip(p.disk), ip(p.ping)
	}
	return s
}

func MigrationStatus(vm string) types.MigrationStatus {
	p := get(vm)
	st := types.MigrationStatus{VM: vm, Pending: []types.PendingMigration{}}
	for _, m := range p.pending {
		st.Pending = append(st.Pending, safety.Classify(m[0], m[1]))
	}
	st.UpToDate = len(st.Pending) == 0
	for _, m := range st.Pending {
		if m.Destructive {
			st.HasDestructive = true
		}
	}
	return st
}

func Health(vm string) types.HealthReport {
	p := get(vm)
	mig := MigrationStatus(vm)
	healthy := p.online && p.service && p.puma > 0
	return types.HealthReport{
		VM: vm, Healthy: healthy, ServiceActive: p.service, DB: p.online, Redis: p.online,
		Sidekiq: p.sidekiq > 0, HTTP200: healthy, MigrationsUpToDate: mig.UpToDate,
		Detail: map[bool]string{true: "chatwoot.target active; /up 200; PG+Redis OK", false: "VM offline/degradada"}[p.online],
	}
}

func GitDiff(vm, repo string) types.GitDiff {
	p := get(vm)
	d := types.GitDiff{VM: vm, CurrentSHA: p.commit, TargetSHA: p.target, BehindCount: p.behind,
		CompareURL: fmt.Sprintf("https://github.com/%s/compare/%s...%s", repo, p.commit, p.target)}
	d.Commits = append(d.Commits, struct {
		SHA     string `json:"sha"`
		Subject string `json:"subject"`
	}{head, "feat(waha): fallback de tempo real"})
	return d
}

func History(vm string) []types.DeployHistoryEntry {
	dur := 47
	return []types.DeployHistoryEntry{
		{ID: "dep_0481", VM: vm, FromSHA: "88da75b", ToSHA: get(vm).commit, Actor: "ederson", ApprovedBy: "ederson", Status: types.StatusSuccess, DurationS: &dur, FinishedAt: "2026-05-29T14:32:00Z"},
	}
}
