// almirante-control — dispatcher/control-plane.
// Segura as credenciais de transporte, fala SSH com os almiranted, e aplica o
// GATE: aprovar exige role admin + anti-self-review. O token do MCP e 'operator'.
package main

import (
	"embed"
	"encoding/base64"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Dev-Simplex/almirante/internal/aiconfig"
	"github.com/Dev-Simplex/almirante/internal/audit"
	"github.com/Dev-Simplex/almirante/internal/control"
	"github.com/Dev-Simplex/almirante/internal/fleet"
	sshx "github.com/Dev-Simplex/almirante/internal/ssh"
	"github.com/Dev-Simplex/almirante/internal/types"
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

// knownHostsData devolve o conteudo do known_hosts vindo por env. Prefere BASE64
// (linha unica, sobrevive ao env_file do Coolify); cai pro texto cru (_DATA) p/ uso local.
func knownHostsData() string {
	if b64 := os.Getenv("ALMIRANTE_KNOWN_HOSTS_B64"); b64 != "" {
		if dec, err := base64.StdEncoding.DecodeString(b64); err == nil {
			return string(dec)
		}
		fmt.Fprintln(os.Stderr, "aviso: ALMIRANTE_KNOWN_HOSTS_B64 invalido")
	}
	return os.Getenv("ALMIRANTE_KNOWN_HOSTS_DATA")
}

func main() {
	f, err := fleet.Load(env("ALMIRANTE_FLEET_FILE", "fleet.json"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERRO fleet:", err)
		os.Exit(1)
	}
	// creds por-VM: prioriza BASE64 (env_file do Coolify nao expande $ em senhas),
	// depois JSON inline, depois arquivo.
	var perVM map[string]sshx.VMCred
	var cerr error
	if b64 := os.Getenv("ALMIRANTE_CREDS_B64"); b64 != "" {
		if dec, e := base64.StdEncoding.DecodeString(b64); e == nil {
			perVM, cerr = sshx.ParseCreds(dec)
		} else {
			cerr = fmt.Errorf("ALMIRANTE_CREDS_B64 invalido: %w", e)
		}
	} else if j := os.Getenv("ALMIRANTE_CREDS_JSON"); j != "" {
		perVM, cerr = sshx.ParseCreds([]byte(j))
	} else {
		perVM, cerr = sshx.LoadCreds(os.Getenv("ALMIRANTE_CREDS_FILE"))
	}
	if cerr != nil {
		fmt.Fprintln(os.Stderr, "aviso creds-por-VM:", cerr)
	}
	// known_hosts: se vier inline por env (Coolify), materializa em arquivo no boot.
	khPath := env("ALMIRANTE_KNOWN_HOSTS", os.Getenv("HOME")+"/.almirante/known_hosts")
	if data := knownHostsData(); data != "" {
		khPath = filepath.Join(env("ALMIRANTE_STATE_DIR", "./state"), "known_hosts")
		_ = os.MkdirAll(filepath.Dir(khPath), 0o700)
		if werr := os.WriteFile(khPath, []byte(data), 0o600); werr != nil {
			fmt.Fprintln(os.Stderr, "aviso known_hosts:", werr)
		}
		fmt.Fprintf(os.Stderr, "known_hosts materializado: %d bytes em %s\n", len(data), khPath)
	}
	// chave de transporte (AWS, auth=key) via base64: env_file expande $; base64 e seguro.
	keyPath := os.Getenv("ALMIRANTE_TRANSPORT_KEY_PATH")
	if kb64 := os.Getenv("ALMIRANTE_TRANSPORT_KEY_B64"); kb64 != "" {
		if dec, e := base64.StdEncoding.DecodeString(kb64); e == nil {
			keyPath = filepath.Join(env("ALMIRANTE_STATE_DIR", "./state"), "transport_key")
			_ = os.MkdirAll(filepath.Dir(keyPath), 0o700)
			if werr := os.WriteFile(keyPath, dec, 0o600); werr != nil {
				fmt.Fprintln(os.Stderr, "aviso transport_key:", werr)
			} else {
				fmt.Fprintf(os.Stderr, "transport_key materializada: %d bytes em %s\n", len(dec), keyPath)
			}
		} else {
			fmt.Fprintln(os.Stderr, "aviso: ALMIRANTE_TRANSPORT_KEY_B64 invalido")
		}
	}
	// Governanca de IA (opcional): monta o driver se ALGUMA VM tem aiconfig_url.
	// Resolve baseURL/account_id da fleet; o token vem de AICONFIG_TOKEN_<SLUG> (secret).
	aiDriver, aiGate := buildAIGovernance(f)

	cfg := control.Config{
		Mock:          env("ALMIRANTE_MOCK", "1") == "1",
		Fleet:         f,
		ApprovalTTL:   20 * time.Minute,
		MergeCloneDir: env("ALMIRANTE_MERGE_DIR", "/home/chatwoot/almirante-merge"),
		RepoURL:       env("ALMIRANTE_REPO_URL", "https://github.com/Dev-Simplex/chatspx.git"),
		SSH: sshx.Config{
			KeyPath:        keyPath,
			Password:       os.Getenv("ALMIRANTE_TRANSPORT_PASSWORD"),
			KnownHostsPath: khPath,
			PerVM:          perVM,
		},
		AIDriver: aiDriver,
		AIGate:   aiGate,
	}
	store := control.NewStore(env("ALMIRANTE_STATE_DIR", "./state"))
	aud := audit.New(env("ALMIRANTE_AUDIT_FILE", "./audit-log.jsonl"))
	srv := control.NewServer(cfg, store, aud, env("ALMIRANTE_DEV_TOKENS", "dev-demo-token:demo:operator"))

	// 1o admin: sem usuarios + ALMIRANTE_BOOTSTRAP_ADMIN definido -> convida + email.
	if admin := os.Getenv("ALMIRANTE_BOOTSTRAP_ADMIN"); admin != "" && srv.UsersCount() == 0 {
		srv.BootstrapAdmin(admin)
	}

	sub, _ := fs.Sub(webFS, "web")
	mux := http.NewServeMux()
	mux.Handle("/api/", srv.Handler())
	mux.Handle("/mcp", srv.MCPHandler()) // MCP remoto (1 comando pra plugar, sem binario)
	mux.Handle("/", http.FileServer(http.FS(sub)))

	port := env("ALMIRANTE_CONTROL_PORT", "4100")
	fmt.Fprintf(os.Stderr, "almirante-control %s %s %s em :%s (mock=%v) — painel em /\n", version, commit, date, port, cfg.Mock)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		fmt.Fprintln(os.Stderr, "control falhou:", err)
		os.Exit(1)
	}
}

// buildAIGovernance monta o driver + test-gate de governanca de IA se ao menos
// uma VM da fleet tiver aiconfig_url. Retorna (nil, nil) se nenhuma tiver — a
// feature fica OFF e as rotas /api/ai/* respondem 503.
func buildAIGovernance(f *types.Fleet) (*aiconfig.Driver, *aiconfig.TestGate) {
	has := false
	for _, v := range f.VMs {
		if v.AIConfigURL != "" {
			has = true
			break
		}
	}
	if !has {
		fmt.Fprintln(os.Stderr, "governanca de IA: inativa (nenhuma VM com aiconfig_url na fleet)")
		return nil, nil
	}
	resolve := func(slug string) (aiconfig.VMConn, error) {
		for _, v := range f.VMs {
			if v.ID != slug {
				continue
			}
			if v.AIConfigURL == "" {
				return aiconfig.VMConn{}, fmt.Errorf("VM %q sem aiconfig_url", slug)
			}
			envKey := "AICONFIG_TOKEN_" + strings.ToUpper(strings.ReplaceAll(slug, "-", "_"))
			tok := os.Getenv(envKey)
			if tok == "" {
				return aiconfig.VMConn{}, fmt.Errorf("%s ausente (secret do token do receptor)", envKey)
			}
			return aiconfig.VMConn{
				BaseURL:   strings.TrimRight(v.AIConfigURL, "/"),
				Token:     tok,
				AccountID: v.AIConfigAccountID,
			}, nil
		}
		return aiconfig.VMConn{}, fmt.Errorf("VM %q nao existe na fleet", slug)
	}
	driver := aiconfig.NewDriver(resolve, 20*time.Second)
	gate := aiconfig.NewTestGate(driver, aiconfig.GateConfig{
		JudgeAPIKey:  firstEnv("OPENAI_JUDGE_KEY", "OPENAI_API_KEY", "OPENAI_KEY_SIMPLEX"),
		JudgeModel:   os.Getenv("OPENAI_JUDGE_MODEL"),
		JudgeBaseURL: os.Getenv("OPENAI_JUDGE_BASE_URL"),
		Logf:         func(format string, args ...interface{}) { fmt.Fprintf(os.Stderr, "[aigate] "+format+"\n", args...) },
	})
	fmt.Fprintln(os.Stderr, "governanca de IA: ATIVA (driver aiconfig montado)")
	return driver, gate
}

func firstEnv(keys ...string) string {
	for _, k := range keys {
		if v := os.Getenv(k); v != "" {
			return v
		}
	}
	return ""
}
