// Package ssh e o transporte usado SOMENTE pelo dispatcher (nunca pelo MCP/dev).
// A chave deve ser forced-command limitada ao almiranted na VM.
// HostKeyCallback via knownhosts: FALHA FECHADO em host desconhecido/MITM —
// NUNCA InsecureIgnoreHostKey (fix do bug #3 da versao TS).
package ssh

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/Dev-Simplex/almirante/internal/safety"
	"github.com/Dev-Simplex/almirante/internal/types"
	gossh "golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/knownhosts"
)

// VMCred: credencial especifica de uma VM (override do global). A frota tem
// senhas/chaves DIFERENTES, entao cada VM pode ter a sua.
type VMCred struct {
	Password string `json:"password,omitempty"`
	KeyPath  string `json:"key_path,omitempty"`
}

type Config struct {
	KeyPath        string            // chave global (fallback p/ VMs auth=key)
	Password       string            // senha global (fallback p/ VMs auth=password)
	KnownHostsPath string            // arquivo gerenciado de known_hosts
	PerVM          map[string]VMCred // credencial POR-VM (tem prioridade sobre o global)
}

// LoadCreds le um JSON {"<vmid>":{"password":"..."|"key_path":"..."}} (nunca commitado).
func LoadCreds(path string) (map[string]VMCred, error) {
	if path == "" {
		return nil, nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	m := map[string]VMCred{}
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, fmt.Errorf("parse creds %s: %w", path, err)
	}
	return m, nil
}

func auth(cfg Config, vm types.VM) ([]gossh.AuthMethod, error) {
	c := cfg.PerVM[vm.ID] // credencial especifica da VM (se houver)
	if vm.Auth == types.AuthKey {
		kp := c.KeyPath
		if kp == "" {
			kp = cfg.KeyPath
		}
		if kp == "" {
			return nil, fmt.Errorf("sem chave de transporte para %s (defina creds por-VM ou ALMIRANTE_TRANSPORT_KEY_PATH)", vm.ID)
		}
		key, err := os.ReadFile(kp)
		if err != nil {
			return nil, fmt.Errorf("lendo chave de %s: %w", vm.ID, err)
		}
		signer, err := gossh.ParsePrivateKey(key)
		if err != nil {
			return nil, fmt.Errorf("parse chave de %s: %w", vm.ID, err)
		}
		return []gossh.AuthMethod{gossh.PublicKeys(signer)}, nil
	}
	pw := c.Password
	if pw == "" {
		pw = cfg.Password
	}
	if pw == "" {
		return nil, fmt.Errorf("sem senha de transporte para %s", vm.ID)
	}
	return []gossh.AuthMethod{gossh.Password(pw)}, nil
}

// RunAlmiranted roda `almiranted <args...>` na VM via SSH. Cada arg e validado
// contra metacaracteres (defense-in-depth, alem da validacao no agente).
func RunAlmiranted(ctx context.Context, cfg Config, vm types.VM, args []string) (string, error) {
	for i, a := range args {
		if err := safety.AssertSafeArg(a, fmt.Sprintf("arg[%d]", i)); err != nil {
			return "", err
		}
	}
	hostKey, err := knownhosts.New(cfg.KnownHostsPath)
	if err != nil {
		return "", fmt.Errorf("known_hosts (%s): %w — host nao confiado, abortando (sem InsecureIgnoreHostKey)", cfg.KnownHostsPath, err)
	}
	methods, err := auth(cfg, vm)
	if err != nil {
		return "", err
	}
	cc := &gossh.ClientConfig{
		User:            vm.TransportUser,
		Auth:            methods,
		HostKeyCallback: hostKey,
		Timeout:         12 * time.Second,
	}
	client, err := gossh.Dial("tcp", vm.IP+":22", cc)
	if err != nil {
		return "", fmt.Errorf("ssh dial %s: %w", vm.ID, err)
	}
	defer client.Close()

	sess, err := client.NewSession()
	if err != nil {
		return "", err
	}
	defer sess.Close()

	var out bytes.Buffer
	sess.Stdout, sess.Stderr = &out, &out
	// forced-command na VM mapeia para "sudo -u chatwoot /usr/local/bin/almiranted"
	cmd := "almiranted"
	for _, a := range args {
		cmd += " " + a
	}
	done := make(chan error, 1)
	go func() { done <- sess.Run(cmd) }()
	select {
	case <-ctx.Done():
		_ = sess.Signal(gossh.SIGKILL)
		return out.String(), ctx.Err()
	case err := <-done:
		if err != nil {
			return out.String(), fmt.Errorf("almiranted %s: %v: %s", args[0], err, out.String())
		}
		return out.String(), nil
	}
}
