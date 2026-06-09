# ⚓ Almirante — Runbook do Time

Painel de comando da frota ChatSPX. A IA **propõe**, um humano **autoriza**, o sistema **registra**.

- **Painel:** https://painel.chatspx.app
- **Roda em:** Coolify (`192.168.8.45`), app `almirante`, container `e10kgjc0yymxgk9ldmuufy22`, branch git `feat/almirante`.
- **Modo:** real (`ALMIRANTE_MOCK=0`) — fala SSH de verdade com as VMs.

---

## 1. Acessar o painel (humano)

1. Abra **https://painel.chatspx.app** → tela de login.
2. Entre com **email + senha**.
3. Não tem conta? Um **admin** te convida (seção 2) → você recebe um email pra **definir a senha**.

Esqueceu a senha / quer reenviar: um admin te re-convida na aba **Usuários**.

## 2. Convidar um usuário (admin)

Aba **Usuários → Convidar usuário** → informe email, nome e papel:
- **viewer** — só vê (frota, métricas, histórico).
- **operator** — propõe deploys/merges (mas não aprova).
- **admin** — aprova, gerencia usuários e tokens, reinicia serviços.

A pessoa recebe um email (via SMTP do host) com link pra definir a senha (expira em 48h). Pra cortar acesso: **Remover** na lista.

## 3. Conectar um dev no Claude Code (MCP)

1. **Token:** aba **Tokens → Novo token** (admin emite). Cada dev tem o seu, revogável.
2. **`.mcp.json`** do projeto do dev (ou `~/.claude.json`):
   ```json
   {
     "mcpServers": {
       "almirante": {
         "command": "/usr/local/bin/almirante-mcp",
         "env": {
           "ALMIRANTE_MOCK": "0",
           "ALMIRANTE_CONTROL_URL": "https://painel.chatspx.app",
           "ALMIRANTE_DEV_TOKEN": "<token-do-dev>"
         }
       }
     }
   }
   ```
3. O dev **fala natural** no Claude: "status da tozi?", "atualiza a homologação", "promove homolog pra produção", "rollback da tozi".

> A tela **"Como conectar"** no painel tem esse passo-a-passo + botão copiar.

## 4. O gate humano (importante)

- **Leitura** (status, health, métricas, logs) → livre.
- **Mudança** (deploy, migrate, merge) → vira um **pedido pendente** na aba **Aprovações**. Só um **admin** aprova (e não pode aprovar o próprio pedido — *anti-self-review*).
- **Restart** (web/worker/tudo) → ação direta do admin, no card da VM (hover → botões), com confirmação + log.

## 5. A frota (8 VMs)

| VM | Onde | Branch |
|----|------|--------|
| producao | Proxmox 192.168.8.229 | producao |
| homologacao | Proxmox 192.168.8.232 | homologacao |
| paulao | Dev 192.168.8.100 | paulao |
| nicolas | Dev 192.168.8.98 | nicolas |
| catatau, sentinela, tozi, fabrica | AWS EC2 | producao |

Cada card expande no hover → uptime, CPU/RAM/disco, e botões de restart.

## 6. Adicionar uma VM nova (Fase 0)

1. A VM precisa: usuário SSH de transporte + usuário `chatwoot` dono de `/home/chatwoot/chatwoot` + systemd (`chatwoot-web.1.service`, `chatwoot-worker.1.service`).
2. Instalar o binário `almiranted` em `/usr/local/bin/` (não-disruptivo).
3. Sudoers `/etc/sudoers.d/almirante`: `<transporte> ALL=(chatwoot) NOPASSWD: ALL` + `... ALL=(root) NOPASSWD: /usr/bin/systemctl restart <units>` (validar `visudo -c`).
4. Adicionar a VM em `deployment/almirante/fleet.json`.
5. Adicionar a credencial em `ALMIRANTE_CREDS_B64` + a host key em `ALMIRANTE_KNOWN_HOSTS_B64` (env do Coolify, base64).
6. Redeploy do app no Coolify.

## 7. Secrets / config (Coolify env)

- `ALMIRANTE_MOCK=0`
- `ALMIRANTE_CREDS_B64` — senhas por-VM (Proxmox/dev), base64.
- `ALMIRANTE_TRANSPORT_KEY_B64` — chave SSH AWS, base64.
- `ALMIRANTE_KNOWN_HOSTS_B64` — host keys das VMs, base64.
- `ALMIRANTE_DEV_TOKENS` — tokens bootstrap (admin permanente).
- `ALMIRANTE_SESSION_SECRET` — segredo do cookie de sessão.
- `ALMIRANTE_SMTP_*` — SMTP do convite por email.
- `ALMIRANTE_BOOTSTRAP_ADMIN` — 1º admin semeado no boot.

> ⚠️ Sempre que mudar env no Coolify, **redeploy** (não basta restart). Valores com `$` ou multiline → use **base64** (o env_file do Coolify expande `$` e quebra `\n`).

## 8. Troubleshooting

- **Card "sem métricas":** a VM está no binário antigo (sem `metrics`) — reinstalar `almiranted`.
- **VM offline no painel:** checar SSH (cred/known_hosts) e se o `almiranted` está em `/usr/local/bin`.
- **Login não entra:** confirmar usuário `active` na aba Usuários; reenviar convite se preciso. Fallback de emergência: "acesso por token" na tela de login.
- **Deploy falhou:** o pipeline tem rollback automático; ver `deploy_logs` da VM.

---
*Almirante · Simplex Soluções · A IA propõe, o humano autoriza, o sistema registra.*
