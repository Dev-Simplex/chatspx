// almirante-control — dispatcher/control-plane.
// Segura as credenciais de transporte, fala SSH com os almiranted, e aplica o
// GATE: aprovar exige role admin + anti-self-review. O token do MCP e 'operator'.
package main

import (
	"embed"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/Dev-Simplex/almirante/internal/audit"
	"github.com/Dev-Simplex/almirante/internal/control"
	"github.com/Dev-Simplex/almirante/internal/fleet"
	sshx "github.com/Dev-Simplex/almirante/internal/ssh"
)

//go:embed web
var webFS embed.FS

// preenchidos pelo GoReleaser via -ldflags
var (
	version = "dev"
	commit  = ""
	date    = ""
)

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func main() {
	f, err := fleet.Load(env("ALMIRANTE_FLEET_FILE", "fleet.json"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERRO fleet:", err)
		os.Exit(1)
	}
	// creds por-VM: prioriza JSON inline (env, p/ Coolify) e cai pro arquivo.
	var perVM map[string]sshx.VMCred
	var cerr error
	if j := os.Getenv("ALMIRANTE_CREDS_JSON"); j != "" {
		perVM, cerr = sshx.ParseCreds([]byte(j))
	} else {
		perVM, cerr = sshx.LoadCreds(os.Getenv("ALMIRANTE_CREDS_FILE"))
	}
	if cerr != nil {
		fmt.Fprintln(os.Stderr, "aviso creds-por-VM:", cerr)
	}
	// known_hosts: se vier inline por env (Coolify), materializa em arquivo no boot.
	khPath := env("ALMIRANTE_KNOWN_HOSTS", os.Getenv("HOME")+"/.almirante/known_hosts")
	if data := os.Getenv("ALMIRANTE_KNOWN_HOSTS_DATA"); data != "" {
		khPath = filepath.Join(env("ALMIRANTE_STATE_DIR", "./state"), "known_hosts")
		_ = os.MkdirAll(filepath.Dir(khPath), 0o700)
		if werr := os.WriteFile(khPath, []byte(data), 0o600); werr != nil {
			fmt.Fprintln(os.Stderr, "aviso known_hosts:", werr)
		}
	}
	cfg := control.Config{
		Mock:          env("ALMIRANTE_MOCK", "1") == "1",
		Fleet:         f,
		ApprovalTTL:   20 * time.Minute,
		MergeCloneDir: env("ALMIRANTE_MERGE_DIR", "/home/chatwoot/almirante-merge"),
		RepoURL:       env("ALMIRANTE_REPO_URL", "https://github.com/Dev-Simplex/chatspx.git"),
		SSH: sshx.Config{
			KeyPath:        os.Getenv("ALMIRANTE_TRANSPORT_KEY_PATH"),
			Password:       os.Getenv("ALMIRANTE_TRANSPORT_PASSWORD"),
			KnownHostsPath: khPath,
			PerVM:          perVM,
		},
	}
	store := control.NewStore(env("ALMIRANTE_STATE_DIR", "./state"))
	aud := audit.New(env("ALMIRANTE_AUDIT_FILE", "./audit-log.jsonl"))
	srv := control.NewServer(cfg, store, aud, env("ALMIRANTE_DEV_TOKENS", "dev-demo-token:demo:operator"))

	sub, _ := fs.Sub(webFS, "web")
	mux := http.NewServeMux()
	mux.Handle("/api/", srv.Handler())
	mux.Handle("/", http.FileServer(http.FS(sub)))

	port := env("ALMIRANTE_CONTROL_PORT", "4100")
	fmt.Fprintf(os.Stderr, "almirante-control %s %s %s em :%s (mock=%v) — painel em /\n", version, commit, date, port, cfg.Mock)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		fmt.Fprintln(os.Stderr, "control falhou:", err)
		os.Exit(1)
	}
}
