// Package audit grava um log append-only com hash-chain (imutavel/detecta adulteracao).
package audit

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type Entry struct {
	TS       string         `json:"ts"`
	Action   string         `json:"action"`
	Actor    string         `json:"actor"`
	VM       string         `json:"vm,omitempty"`
	Detail   map[string]any `json:"detail,omitempty"`
	PrevHash string         `json:"prev_hash"`
	Hash     string         `json:"hash"`
}

// Logger e seguro para concorrencia (o dispatcher faz fan-out).
type Logger struct {
	mu   sync.Mutex
	path string
	now  func() time.Time
}

func New(path string) *Logger { return &Logger{path: path, now: time.Now} }

func hashEntry(e Entry) string {
	// Detail entra no hash (json.Marshal ordena chaves = determinístico). Sem isto,
	// os dados forenses mais sensíveis (branch, PR, método de merge) ficavam FORA da
	// tamper-evidence e podiam ser adulterados sem quebrar a cadeia.
	det, _ := json.Marshal(e.Detail)
	h := sha256.Sum256([]byte(e.PrevHash + e.TS + e.Action + e.Actor + e.VM + string(det)))
	return hex.EncodeToString(h[:])
}

func (l *Logger) lastHash() string {
	f, err := os.Open(l.path)
	if err != nil {
		return ""
	}
	defer f.Close()
	last := ""
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		var e Entry
		if json.Unmarshal(sc.Bytes(), &e) == nil {
			last = e.Hash
		}
	}
	return last
}

func (l *Logger) Append(action, actor, vm string, detail map[string]any) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if err := os.MkdirAll(filepath.Dir(l.path), 0o750); err != nil {
		return err
	}
	e := Entry{
		TS:       l.now().UTC().Format(time.RFC3339),
		Action:   action,
		Actor:    actor,
		VM:       vm,
		Detail:   detail,
		PrevHash: l.lastHash(),
	}
	e.Hash = hashEntry(e)
	line, err := json.Marshal(e)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(l.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o640)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintln(f, string(line))
	return err
}

// Verify confere a integridade da cadeia (detecta adulteracao/remocao).
func (l *Logger) Verify() (bool, error) {
	f, err := os.Open(l.path)
	if err != nil {
		if os.IsNotExist(err) {
			return true, nil
		}
		return false, err
	}
	defer f.Close()
	prev := ""
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		var e Entry
		if err := json.Unmarshal(sc.Bytes(), &e); err != nil {
			return false, nil
		}
		if e.PrevHash != prev || e.Hash != hashEntry(e) {
			return false, nil
		}
		prev = e.Hash
	}
	return true, nil
}
