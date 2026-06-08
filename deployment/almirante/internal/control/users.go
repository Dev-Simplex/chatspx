package control

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
)

// AppUser: usuario HUMANO do painel (login email+senha). Diferente do TokenStore
// (auth de maquina p/ o MCP). Convite por email -> set-password -> ativo.
type AppUser struct {
	ID        string `json:"id"`
	Email     string `json:"email"`
	Name      string `json:"name"`
	Role      string `json:"role"`
	PassHash  string `json:"pass_hash,omitempty"`
	Status    string `json:"status"` // invited | active
	SetToken  string `json:"set_token,omitempty"`
	SetExp    string `json:"set_exp,omitempty"`
	CreatedAt string `json:"created_at"`
	CreatedBy string `json:"created_by"`
	LastLogin string `json:"last_login,omitempty"`
}

type UserStore struct {
	mu      sync.Mutex
	path    string
	seq     int
	byEmail map[string]*AppUser
}

func NewUserStore(stateDir string) *UserStore {
	us := &UserStore{path: filepath.Join(stateDir, "users.json"), byEmail: map[string]*AppUser{}}
	us.load()
	return us
}

func (us *UserStore) load() {
	b, err := os.ReadFile(us.path)
	if err != nil {
		return
	}
	var list []*AppUser
	if json.Unmarshal(b, &list) != nil {
		return
	}
	for _, u := range list {
		us.byEmail[u.Email] = u
		var n int
		if _, e := fmt.Sscanf(u.ID, "usr_%d", &n); e == nil && n > us.seq {
			us.seq = n
		}
	}
}

func (us *UserStore) save() {
	list := make([]*AppUser, 0, len(us.byEmail))
	for _, u := range us.byEmail {
		list = append(list, u)
	}
	b, _ := json.MarshalIndent(list, "", "  ")
	_ = os.MkdirAll(filepath.Dir(us.path), 0o750)
	_ = os.WriteFile(us.path, b, 0o600)
}

func norm(email string) string { return strings.ToLower(strings.TrimSpace(email)) }

func (us *UserStore) Count() int { us.mu.Lock(); defer us.mu.Unlock(); return len(us.byEmail) }

// Invite cria (ou re-convida) um usuario e devolve o token de set-password (48h).
func (us *UserStore) Invite(email, name, role, by string) (*AppUser, string, error) {
	us.mu.Lock()
	defer us.mu.Unlock()
	email = norm(email)
	if email == "" || !strings.Contains(email, "@") {
		return nil, "", fmt.Errorf("email invalido")
	}
	u := us.byEmail[email]
	if u == nil {
		us.seq++
		u = &AppUser{ID: fmt.Sprintf("usr_%d", us.seq), Email: email, CreatedAt: time.Now().UTC().Format(time.RFC3339), CreatedBy: by}
		us.byEmail[email] = u
	}
	if name != "" {
		u.Name = name
	}
	u.Role = role
	u.Status = "invited"
	u.SetToken = genSecret()
	u.SetExp = time.Now().UTC().Add(48 * time.Hour).Format(time.RFC3339)
	us.save()
	return u, u.SetToken, nil
}

// SetPassword consome o token, grava o bcrypt e ativa o usuario.
func (us *UserStore) SetPassword(token, pw string) (*AppUser, error) {
	us.mu.Lock()
	defer us.mu.Unlock()
	if len(pw) < 8 {
		return nil, fmt.Errorf("senha muito curta (mínimo 8 caracteres)")
	}
	for _, u := range us.byEmail {
		if u.SetToken != "" && u.SetToken == token {
			if exp, e := time.Parse(time.RFC3339, u.SetExp); e == nil && time.Now().After(exp) {
				return nil, fmt.Errorf("link de convite expirado — peça um novo")
			}
			h, e := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.DefaultCost)
			if e != nil {
				return nil, e
			}
			u.PassHash = string(h)
			u.Status = "active"
			u.SetToken, u.SetExp = "", ""
			us.save()
			return u, nil
		}
	}
	return nil, fmt.Errorf("link inválido")
}

// Authenticate valida email+senha de um usuario ativo.
func (us *UserStore) Authenticate(email, pw string) (*AppUser, error) {
	us.mu.Lock()
	defer us.mu.Unlock()
	u := us.byEmail[norm(email)]
	if u == nil || u.Status != "active" || u.PassHash == "" {
		return nil, fmt.Errorf("credenciais inválidas")
	}
	if bcrypt.CompareHashAndPassword([]byte(u.PassHash), []byte(pw)) != nil {
		return nil, fmt.Errorf("credenciais inválidas")
	}
	u.LastLogin = time.Now().UTC().Format(time.RFC3339)
	us.save()
	return u, nil
}

// List devolve copias SEM hash/token (seguro p/ API).
func (us *UserStore) List() []AppUser {
	us.mu.Lock()
	defer us.mu.Unlock()
	out := make([]AppUser, 0, len(us.byEmail))
	for _, u := range us.byEmail {
		c := *u
		c.PassHash, c.SetToken, c.SetExp = "", "", ""
		out = append(out, c)
	}
	return out
}

func (us *UserStore) Delete(id string) bool {
	us.mu.Lock()
	defer us.mu.Unlock()
	for email, u := range us.byEmail {
		if u.ID == id {
			delete(us.byEmail, email)
			us.save()
			return true
		}
	}
	return false
}
