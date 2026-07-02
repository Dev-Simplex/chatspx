# ROADMAP — Governança de IA (Almirante)

> Executado pelo Claude Code na máquina de PRODUÇÃO (.229) do ChatSPX — tem
> `./deployment/deploy.sh`, SSH às VMs e a API do Coolify (token no vault).
> Ordem obrigatória; **ok humano antes de cada deploy**.

## CONTEXTO — o que JÁ está no ar (NÃO refazer)

- **Almirante** = `deployment/almirante` (repo chatspx, branch `feat/almirante`) em
  `painel.chatspx.app` · Coolify app "almirante" uuid `e10kgjc0yymxgk9ldmuufy22`. É o MCP de
  deploy da frota + **agora com governança de IA integrada** (commit `d759970`):
  - **Backend:** `internal/aiconfig/{driver,testgate,judge,ops}.go` (driver→receptor `spx/ai_config`
    por VM, header `api_access_token`; test-gate fail-closed; LLM-juiz),
    `internal/control/{aigov,aistore}.go` (11 rotas `/api/ai/*`, RBAC admin, audit hash-chain,
    rollback), 9 tools MCP `almirante_ai_*`.
  - **Front:** `cmd/almirante-control/web/index.html` refeito iOS/glass + seção "IA · Agentes".
  - **Token do receptor por VM:** env `AICONFIG_TOKEN_<SLUG>` no Coolify (hoje só `AICONFIG_TOKEN_TOZI`).
  - **Go** em `~/go-sdk/go/bin`.
- **Receptor (ChatSPX):** `app/services/spx/ai_config/` + `app/controllers/spx/ai_config/` — já em produção.
- **noc-spxia** (`dashboard.chatspx.app`): revertido pra branch `producao` (só dashboard NOC — **NÃO mexer**).

## ⭐ T1 — SELETOR DE AGENTES (listar assistants) — O PRINCIPAL

Hoje o front pede o `assistant_id` na mão; o receptor não tem "listar agentes de uma conta". Adicionar:

**a) RECEPTOR (ChatSPX):**
- `app/controllers/spx/ai_config/config_controller.rb`: action `assistants` →
  `render json: { assistants: Account.find(params[:account_id]).captain_assistants.map { |a| {id:a.id,name:a.name} } }`
- `config/routes.rb` (namespace spx/ai_config): `get 'accounts/:account_id/assistants', to: 'config#assistants'`
- spec em `spec/.../spx/ai_config/` (RAILS_ENV=test + factories — **NUNCA dados reais**).

**b) ALMIRANTE (`deployment/almirante`):**
- `internal/aiconfig/driver.go`: `ListAssistants(ctx, vmSlug)` → `GET /spx/ai_config/accounts/{aid}/assistants` (padrão do `GetBaseline`).
- `internal/control/aigov.go`: rota `GET /api/ai/assistants?vm=` (RoleViewer) → `driver.ListAssistants`; registrar em `server.go` `Handler()`.
- `internal/mcptools/{source.go,tools.go}` + `cmd/almirante-mcp/source.go`: método `ListAssistants` na interface `Source` + `ControlSource` (REST) + `mockSource` (fake) + tool `almirante_ai_list_assistants`.
- `cmd/almirante-control/web/index.html`: trocar o `<input assistant_id>` por um `<select>` populado via `GET /api/ai/assistants?vm=` (manter fallback manual).

**c) VALIDAR + DEPLOYAR:**
- Almirante: `cd deployment/almirante && export PATH=~/go-sdk/go/bin:$PATH && go build ./... && go vet ./...` ; front via Playwright light+dark.
- Receptor: deploy em CADA VM governada (Tozi) → `./deployment/deploy.sh producao` (Ruby, sem migration).
- Almirante: commit na `feat/almirante` → deploy Coolify (`GET .../api/v1/deploy?uuid=e10kgjc0yymxgk9ldmuufy22`).

## T2 — Deploy dos commits do Paulo (conferir)

Os 7 commits do Paulo já estão na branch `producao` do chatspx. Se o deploy nas VMs não rodou:
pré-flight `RAILS_ENV=production bundle exec rails db:migrate:status | grep '^ *down'` (vazio) → `./deployment/deploy.sh producao`.

## T3 — Espelhar prompts novos da IA → Tozi

Artefatos na .232: `/home/chatwoot/almirante/ia_export_conta3.json` + `import_tozi.rb` (faz BACKUP + dry-run).
Transfira pra a VM da Tozi → dry-run → revise → `MODE=apply SYNC_EXTRAS=1`. ⚠️ IA de cliente: dry-run + backup obrigatórios.

## T4 — Rotacionar secrets

Token PlatformApp da Tozi (`AICONFIG_TOKEN_TOZI`), token MCP do Almirante, secrets do noc-spxia (inertes).
Gere novos: novo PlatformApp na Tozi → atualiza `AICONFIG_TOKEN_TOZI` no Coolify; revoga o token MCP antigo no painel.

## T5 — Governar mais VMs

Por VM: `api_access_token` PlatformApp na VM → `fleet.json` (`AIConfigURL` + `AIConfigAccountID`) → env
`AICONFIG_TOKEN_<SLUG>` no Coolify → redeploy do Almirante. (O receptor já está em todas as VMs.)

## CUIDADOS (inegociáveis)

- Governança de IA: escrita SEMPRE via test-gate ANTES (fail-closed) + audit + rollback (já é no código — **não burle**).
- Nunca editar prompt de IA de produção sem dry-run/backup (incidente Clara).
- Subagents/testes: só `RAILS_ENV=test` / `go test` / mocks — **nunca dados reais**.
- Não commitar secret; não tocar o noc-spxia.
