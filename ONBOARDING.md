# Onboarding — chatspx / branch `paulao`

Guia operacional pra outra sessão Claude Code retomar o trabalho.

## O que é

Fork **Dev-Simplex/chatspx** do Chatwoot (Rails 7.1 + Vue 3 + Sidekiq + Postgres). Branch `paulao` é a trunk de produção da Simplex, **452 commits à frente do `master` Chatwoot vanilla**. O usuário (Paulo Seze) está migrando o agente de IA **Clara** (atendimento Tozi imobiliária) do n8n pro Captain V2 nativo do Chatwoot.

## Antes de tudo: leia as memórias

`C:\Users\paulo\.claude\projects\C--Users-paulo-Workspaces-chatspx\memory\` tem:

- **MEMORY.md** — índice
- **feedback-decidir-com-conviccao.md** — Paulo é operador, não consultor; nada de dicotomias A/B/C
- **project-clara-tozi-spx.md** — estado atual da Clara + backlog técnico
- **reference-spx-prod-vm.md** — VM produção, SSH, pipeline de deploy
- **reference-captain-v2-gotchas.md** — **10 armadilhas operacionais** que vão te economizar 4-6h se ler antes

Essas memórias são carregadas automaticamente em qualquer sessão Claude Code aberta neste working dir. Outra sessão em **outra máquina** precisa abrir o link de share (ver no fim deste arquivo).

## Acesso ao servidor de produção

- Host: `192.168.8.100` (VM "SENTINELA", **rede interna da empresa** — Wi-Fi/VPN obrigatória; o domínio público `paulo.chatspx.app` resolve pra Cloudflare HTTP/HTTPS, não pra SSH)
- User SSH: `paulo` (a senha está com o Paulo, não em arquivo)
- App dir: `/home/chatwoot/chatwoot` (owner `chatwoot`, requer `sudo -u chatwoot bash -lc "..."` — flag `-l` mandatória pro PATH rbenv)
- Serviços: `chatwoot.target` → `chatwoot-web.1.service` (Puma) + `chatwoot-worker.1.service` (Sidekiq)

**SSH no Windows Git Bash** — sem `sshpass`, usa hack `SSH_ASKPASS`. Receita completa em `reference-spx-prod-vm.md`.

**Rails runner com script complexo** — usar base64 pra escapar quoting:
```bash
B64=$(printf '%s' "$RUBY_SCRIPT" | base64 -w0)
ssh ... "echo '<senha>' | sudo -S -u chatwoot bash -lc 'echo $B64 | base64 -d > /tmp/_ec.rb && cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner /tmp/_ec.rb; rm -f /tmp/_ec.rb'"
```

## Estado em produção (17/mai/2026)

**Commit deployado:** `d787b4621` (paulao)

**Account 1 (`simplexia`)** — conta de teste do telefone do Paulo:
- `captain_integration` e `captain_integration_v2` ligados
- `captain_assistant_model = "gpt-5-mini"`
- `captain_auto_resolve_mode = "disabled"` (parado pra fase de teste)
- Chave OpenAI em `InstallationConfig['CAPTAIN_OPEN_AI_API_KEY']`

**Inbox 1 (`Paulo`, Channel::Api WAHA)** — WhatsApp `+556696350491`:
- `pending_status_enabled = true`
- Captain Assistant 1 (Clara) vinculado via `CaptainInbox(id=1)`

**Captain::Assistant 1 (`Clara`)**:
- `behavior.router.only_contact_phones = ["+5566996247866"]` (whitelist do telefone secundário do Paulo — quem manda mensagens nos testes)
- `behavior.router.skip_groups = true` (com detecção robusta via JID `@g.us`)

**O que está funcionando:** Clara responde 1-a-1 do `+5566996247866`, ignora grupos, ignora outros números, não faz auto-resolve em inglês.

## Commits recentes da sessão (16-17/mai)

| Commit | Descrição |
|---|---|
| `a60067665` | merge `feature/agentes-ia → paulao` (Anthropic hook, AssistantLog, +20 tools Copilot) |
| `d3b6c4c25` | feat: whitelist por telefone no RouterService |
| `f33f2ee9c` | fix: `Captain::AssistantLog#conversation` precisava `class_name: '::Conversation'` |
| `7e1bdb054` | feat: normalização BR (com/sem 9) e JID WAHA |
| `bbe4a61c4` | feat: aceitar telefone BR sem DDI nas variações |
| `d787b4621` | fix: detectar grupo via JID WAHA, não só `additional_attributes` |

## Backlog técnico (não resolvidos)

1. **UI no `RouterConfig.vue`** pra editar `only_contact_phones` e `skip_groups` — hoje só seta via console
2. **UI pra `captain_auto_resolve_mode`** — hoje só via console
3. **Camada `app/services/spx/tozi/`** (debounce, humanizer, media Whisper/Vision) — ainda não implementada
4. **Reconciliar chave OpenAI**: UI salva em `Account.hooks.openai`, engine lê de `InstallationConfig['CAPTAIN_OPEN_AI_API_KEY']` → divergência. Fix proper: patchar `config/initializers/ai_agents.rb` pra checar Account.hooks também
5. **`feature_ai_assistant_v2` bigint overflow**: bit `2^250` excede coluna; workaround é localStorage `chatspx_ai_panel_v2=on`
6. **Botão Salvar só na aba Behavior** do detalhe do Assistant — investigar outras abas (Settings, Knowledge, Tools)
7. **Reativar Captain auto-resolve com mensagem em PT** quando fluxo maduro (setar `Clara.config.resolution_message` em pt_BR + `captain_auto_resolve_mode = 'evaluated'` ou `'legacy'`)
8. **Configurar chave SSH** `paulo@dev → paulo@spx-prod` (elimina dependência da senha)

## Pipeline de deploy (resumo)

```bash
# 1) limpar artefato esperado
sudo -u chatwoot bash -lc "cd /home/chatwoot/chatwoot && git checkout -- public/version.json"
# 2) pull
sudo -u chatwoot bash -lc "cd /home/chatwoot/chatwoot && git pull --ff-only origin paulao"
# 3) bundle install — apenas se Gemfile.lock mudou
# 4) migrate:status (HARD RULE — sempre antes do restart)
sudo -u chatwoot bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate:status"
# 5) migrate — apenas se há migrations pendentes
# 6) precompile — apenas se mexeu em JS/CSS/Vue
# 7) restart
sudo systemctl restart chatwoot.target
```

Detalhes em `reference-spx-prod-vm.md`.

## Padrão de trabalho com o Paulo

- Decisão técnica é responsabilidade da sessão (Paulo não conhece a stack Ruby/Rails/Vue). Recomenda UM caminho com justificativa em 2 linhas, executa, comunica progresso enquanto trabalha.
- Confirmação curta apenas pra ações **irreversíveis**: `git push`, `rails db:migrate` em produção, `systemctl restart` (downtime).
- Cockpit pessoal (Obsidian) NÃO se aplica ao chatspx — esse projeto é técnico puro, sem assunto pessoal/operacional do Paulo.

## Conventional Commits

- Padrão: `tipo(escopo): descrição` em pt_BR
- Tipos: `feat`, `fix`, `chore`, `docs`, `refactor`
- Co-author trailer: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

## Como compartilhar este guia entre máquinas

`ShareOnboardingGuide` (tool do Claude Code) sobe este arquivo pra um link curto que outra sessão (em outra máquina, outro usuário) abre pra puxar contexto. Veja "Conversational link" ao fim da sessão atual que gerou este arquivo.
