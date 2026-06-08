package control

import (
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"net/smtp"
	"os"
	"strings"
)

// Mailer: envia emails via o SMTP do host (Mailgrid). Config por env; a senha
// aceita BASE64 (env_file do Coolify expande $).
type Mailer struct{ host, port, user, pass, from string }

func envOr2(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func NewMailerFromEnv() *Mailer {
	pass := os.Getenv("ALMIRANTE_SMTP_PASS")
	if b := os.Getenv("ALMIRANTE_SMTP_PASS_B64"); b != "" {
		if dec, err := base64.StdEncoding.DecodeString(b); err == nil {
			pass = string(dec)
		}
	}
	return &Mailer{
		host: os.Getenv("ALMIRANTE_SMTP_HOST"), port: envOr2("ALMIRANTE_SMTP_PORT", "587"),
		user: os.Getenv("ALMIRANTE_SMTP_USER"), pass: pass,
		from: envOr2("ALMIRANTE_SMTP_FROM", "Almirante <contato@chatspx.app>"),
	}
}

func (m *Mailer) Enabled() bool { return m.host != "" && m.user != "" }

func senderAddr(from string) string {
	if i := strings.LastIndex(from, "<"); i >= 0 {
		return strings.TrimSuffix(strings.TrimSpace(from[i+1:]), ">")
	}
	return strings.TrimSpace(from)
}

func (m *Mailer) Send(to, subject, html string) error {
	if !m.Enabled() {
		return fmt.Errorf("SMTP nao configurado (ALMIRANTE_SMTP_HOST/USER)")
	}
	msg := "From: " + m.from + "\r\n" +
		"To: " + to + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"MIME-Version: 1.0\r\n" +
		"Content-Type: text/html; charset=UTF-8\r\n\r\n" + html
	c, err := smtp.Dial(m.host + ":" + m.port)
	if err != nil {
		return err
	}
	defer c.Close()
	if err := c.StartTLS(&tls.Config{ServerName: m.host}); err != nil {
		return err
	}
	if err := c.Auth(loginAuth(m.user, m.pass)); err != nil {
		return err
	}
	if err := c.Mail(senderAddr(m.from)); err != nil {
		return err
	}
	if err := c.Rcpt(to); err != nil {
		return err
	}
	wc, err := c.Data()
	if err != nil {
		return err
	}
	if _, err := wc.Write([]byte(msg)); err != nil {
		return err
	}
	if err := wc.Close(); err != nil {
		return err
	}
	return c.Quit()
}

// loginAuth: AUTH LOGIN (Mailgrid usa LOGIN, net/smtp so traz PLAIN).
type loginAuthT struct{ user, pass string }

func loginAuth(u, p string) smtp.Auth { return &loginAuthT{u, p} }
func (a *loginAuthT) Start(*smtp.ServerInfo) (string, []byte, error) {
	return "LOGIN", nil, nil
}
func (a *loginAuthT) Next(fromServer []byte, more bool) ([]byte, error) {
	if more {
		switch strings.ToLower(strings.TrimSpace(string(fromServer))) {
		case "username:":
			return []byte(a.user), nil
		case "password:":
			return []byte(a.pass), nil
		}
	}
	return nil, nil
}

// inviteHTML: template de convite (navy + ciano, casa com o painel).
func inviteHTML(name, link string) string {
	if name == "" {
		name = "comandante"
	}
	return `<!doctype html><html><body style="margin:0;background:#080C14;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#080C14;padding:32px 0"><tr><td align="center">
  <table width="520" cellpadding="0" cellspacing="0" style="background:linear-gradient(180deg,#0F172A,#0B1220);border:1px solid #1E2A44;border-radius:20px;overflow:hidden">
    <tr><td style="background:linear-gradient(120deg,#22D3EE,#4F46E5);padding:28px 32px">
      <div style="font-size:13px;letter-spacing:3px;text-transform:uppercase;color:rgba(8,12,20,.7);font-weight:700">⚓ Almirante</div>
      <div style="font-size:24px;color:#06141f;font-weight:800;margin-top:6px">Comando da Frota</div>
    </td></tr>
    <tr><td style="padding:32px">
      <p style="color:#E6EDF6;font-size:17px;margin:0 0 8px;font-weight:600">Olá, ` + name + ` 👋</p>
      <p style="color:#94A3B8;font-size:15px;line-height:1.6;margin:0 0 24px">Você foi convidado para o <b style="color:#E6EDF6">Almirante</b> — o painel de comando da frota ChatSPX. Clique abaixo para <b style="color:#67E8F9">definir sua senha</b> e acessar.</p>
      <a href="` + link + `" style="display:inline-block;background:linear-gradient(120deg,#22D3EE,#4F46E5);color:#06141f;font-weight:800;font-size:15px;text-decoration:none;padding:14px 28px;border-radius:9999px">Definir minha senha →</a>
      <p style="color:#64748B;font-size:12px;line-height:1.6;margin:24px 0 0">O link expira em 48 horas. Se não foi você, ignore este email.<br>Ou copie: <span style="color:#94A3B8">` + link + `</span></p>
    </td></tr>
  </table>
  <div style="color:#3A4660;font-size:11px;margin-top:16px">Almirante · Simplex Soluções</div>
</td></tr></table></body></html>`
}
