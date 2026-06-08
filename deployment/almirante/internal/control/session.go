package control

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// sessionSecretFromEnv: usa ALMIRANTE_SESSION_SECRET; se ausente, gera efemero (sessoes caem no restart).
func sessionSecretFromEnv() []byte {
	if s := os.Getenv("ALMIRANTE_SESSION_SECRET"); s != "" {
		return []byte(s)
	}
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	fmt.Fprintln(os.Stderr, "aviso: ALMIRANTE_SESSION_SECRET nao definido — segredo efemero (sessoes caem no restart)")
	return b
}

// Sessao do painel: cookie assinado (HMAC-SHA256). Sem estado no servidor.
// Formato: base64(email|role|exp) "." base64(hmac).
const sessionTTL = 12 * time.Hour

func (s *Server) issueSession(email, role string) string {
	exp := time.Now().Add(sessionTTL).Unix()
	payload := fmt.Sprintf("%s|%s|%d", email, role, exp)
	mac := hmac.New(sha256.New, s.sessSecret)
	mac.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString([]byte(payload)) + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (s *Server) verifySession(cookie string) (user, bool) {
	parts := strings.SplitN(cookie, ".", 2)
	if len(parts) != 2 {
		return user{}, false
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return user{}, false
	}
	mac := hmac.New(sha256.New, s.sessSecret)
	mac.Write(raw)
	want := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(want), []byte(parts[1])) {
		return user{}, false
	}
	f := strings.Split(string(raw), "|")
	if len(f) != 3 {
		return user{}, false
	}
	if exp, _ := strconv.ParseInt(f[2], 10, 64); time.Now().Unix() > exp {
		return user{}, false
	}
	return user{name: f[0], role: parseRole(f[1])}, true
}
