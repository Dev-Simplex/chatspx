// almiranted — agente por-VM da plataforma Almirante.
// Roda NA VM. Executa o pipeline faseado de deploy; o gate (approve) so e criado
// por sessao humana. A chave forced-command do transporte expoe apenas os
// subcomandos de leitura + enqueue — nunca approve/deploy.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/Dev-Simplex/almirante/internal/deploy"
	"github.com/Dev-Simplex/almirante/internal/safety"
)

// preenchidos pelo GoReleaser via -ldflags -X main.version/commit/date
var (
	version = "dev"
	commit  = ""
	date    = ""
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	if os.Args[1] == "version" {
		fmt.Printf("almiranted %s %s %s\n", version, commit, date)
		return
	}
	cfg := deploy.DefaultConfig()
	ops := deploy.LocalOps{Cfg: cfg}
	p := deploy.NewPipeline(cfg, ops)
	p.Log = func(s string) { fmt.Fprintln(os.Stderr, "["+time.Now().Format("15:04:05")+"] "+s) }
	ctx := context.Background()

	args := os.Args[2:]
	switch os.Args[1] {
	case "current":
		sha, err := ops.CurrentSHA(ctx)
		fail(err)
		fmt.Println(sha)
	case "health":
		printJSON(ops.Health(ctx))
	case "metrics":
		printJSON(ops.SysInfo(ctx))
	case "migrate-status":
		st, err := ops.MigrateStatus(ctx)
		fail(err)
		printJSON(st)
	case "plan":
		plan, err := p.PlanFor(ctx, arg(args, 0))
		fail(err)
		printJSON(plan)
	case "enqueue":
		needSHA(arg(args, 0))
		fail(p.Gate.Enqueue(arg(args, 0), argOr(args, 1, "unknown")))
		fmt.Println("ENQUEUED", arg(args, 0))
	case "approve": // HUMANO apenas
		needSHA(arg(args, 0))
		ttl := time.Duration(envInt("ALMIRANTE_APPROVAL_TTL_MIN", 20)) * time.Minute
		fail(p.Gate.Approve(arg(args, 0), argOr(args, 1, "human"), ttl))
		fmt.Println("APROVADO", arg(args, 0))
	case "deploy":
		needSHA(arg(args, 0))
		backup := hasFlag(args, "--backup-done")
		fail(p.Deploy(ctx, arg(args, 0), backup))
		fmt.Println("DEPLOY OK", arg(args, 0))
	case "restart":
		unit := argOr(args, 0, "chatwoot.target")
		fail(p.RestartUnit(ctx, unit))
		fmt.Println("RESTART OK", unit)
	case "rollback":
		fail(p.Rollback(ctx))
		fmt.Println("ROLLBACK OK")
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "uso: almiranted {current|health|migrate-status|plan <sha>|enqueue <sha> <actor>|approve <sha> <by>|deploy <sha> [--backup-done]|restart <unit>|rollback}")
}

func arg(a []string, i int) string {
	if i < len(a) && !strings.HasPrefix(a[i], "--") {
		return a[i]
	}
	return ""
}
func argOr(a []string, i int, def string) string {
	if v := arg(a, i); v != "" {
		return v
	}
	return def
}
func hasFlag(a []string, f string) bool {
	for _, x := range a {
		if x == f {
			return true
		}
	}
	return false
}
func needSHA(s string) {
	if !safety.IsValidSHA(s) {
		fmt.Fprintln(os.Stderr, "ERRO: sha invalido:", s)
		os.Exit(2)
	}
}
func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		var n int
		if _, err := fmt.Sscanf(v, "%d", &n); err == nil {
			return n
		}
	}
	return def
}
func printJSON(v any) {
	b, _ := json.Marshal(v)
	fmt.Println(string(b))
}
func fail(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERRO:", err)
		os.Exit(1)
	}
}
