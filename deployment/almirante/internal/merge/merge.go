// Package merge faz promote de branch (ex: homologacao -> producao) num CLONE
// DEDICADO — nunca no working tree de producao. Conflito = aborta (nunca --force).
package merge

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// Allowed: fluxos de merge permitidos (from -> {to}). Travado pra evitar merge maluco.
var Allowed = map[string]map[string]bool{
	"homologacao": {"producao": true},
	"paulao":      {"producao": true, "homologacao": true},
	"nicolas":     {"homologacao": true}, // dev chega no max em homologacao (NAO producao)
}

func IsAllowed(from, to string) bool {
	tos := Allowed[from]
	return tos != nil && tos[to]
}

func Flows() []string {
	var out []string
	for from, tos := range Allowed {
		for to := range tos {
			out = append(out, from+" -> "+to)
		}
	}
	return out
}

var branchRe = regexp.MustCompile(`^[A-Za-z0-9._/-]{1,100}$`)

func git(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	if dir != "" {
		cmd.Dir = dir
	}
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	err := cmd.Run()
	return strings.TrimSpace(out.String()), err
}

// Run executa o merge from->to no cloneDir (clonando de repoURL se preciso) e
// faz push. Retorna um resumo. Em conflito, aborta e retorna erro.
func Run(cloneDir, repoURL, from, to string) (string, error) {
	if !IsAllowed(from, to) {
		return "", fmt.Errorf("merge %s -> %s nao permitido (fluxos: %s)", from, to, strings.Join(Flows(), ", "))
	}
	if !branchRe.MatchString(from) || !branchRe.MatchString(to) {
		return "", fmt.Errorf("branch invalida")
	}

	// garante o clone dedicado
	if _, err := os.Stat(filepath.Join(cloneDir, ".git")); err != nil {
		_ = os.MkdirAll(filepath.Dir(cloneDir), 0o750)
		if out, err := git("", "clone", repoURL, cloneDir); err != nil {
			return "", fmt.Errorf("clone: %s", out)
		}
	}

	if out, err := git(cloneDir, "fetch", "origin", "--prune"); err != nil {
		return "", fmt.Errorf("fetch: %s", out)
	}
	// estado limpo do alvo a partir do origin
	if out, err := git(cloneDir, "checkout", "-B", to, "origin/"+to); err != nil {
		return "", fmt.Errorf("checkout %s: %s", to, out)
	}
	if out, err := git(cloneDir, "reset", "--hard", "origin/"+to); err != nil {
		return "", fmt.Errorf("reset %s: %s", to, out)
	}

	before, _ := git(cloneDir, "rev-parse", "--short", "HEAD")
	msg := fmt.Sprintf("chore(almirante): merge %s into %s", from, to)
	if out, err := git(cloneDir, "merge", "--no-ff", "origin/"+from, "-m", msg); err != nil {
		_, _ = git(cloneDir, "merge", "--abort")
		return "", fmt.Errorf("CONFLITO ao mergear %s->%s (abortado, nada empurrado): %s", from, to, out)
	}
	after, _ := git(cloneDir, "rev-parse", "--short", "HEAD")

	if before == after {
		return fmt.Sprintf("%s ja estava em %s (nada a mergear)", to, from), nil
	}
	if out, err := git(cloneDir, "push", "origin", to); err != nil {
		return "", fmt.Errorf("push %s: %s", to, out)
	}
	return fmt.Sprintf("merge %s -> %s OK: %s -> %s (push feito)", from, to, before, after), nil
}
