# Almirante — Design Técnico Completo (Control-Plane de Governança de IA)

Documento de implementação. Sem MVP. Sintetiza os 4 mapas (NOC-GO, NOC-WEB, RECEPTOR-CHATSPX, BEST-PRACTICES). Caminhos absolutos: Almirante em `/home/chatwoot/almirante/noc-spxia/`, ChatSPX em `/home/chatwoot/chatwoot/`.

---

## 1. ARQUITETURA GERAL

O Almirante é um **control-plane** que governa a configuração de IA (prompts, FAQs, tools, credenciais, behavior, elegibilidade) de N VMs ChatSPX em produção, **sem SSH**. Ele não roda código do produto — só materializa mudanças de **config no banco** via o receptor que o Paulo já construiu (`Spx::AiConfig::ChangeSetApplier`). Código do produto continua indo por deploy normal (Coolify), nunca pelo Almirante.

Três planos:
- **Plano de identidade/política** (Almirante): login próprio, RBAC por VM deny-by-default, audit local, snapshot de change-sets.
- **Plano de validação** (Almirante): test-gate automático que roda ANTES de qualquer escrita atingir a VM.
- **Plano de execução** (ChatSPX, por VM): o `ChangeSetApplier` transacional/idempotente/reversível, exposto por um endpoint REST novo autenticado por `api_access_token`.

```
┌─────────────────┐   MCP / Streamable HTTP (POST/GET/DELETE em /mcp)
│   Claude Code   │   Authorization: Bearer <user-JWT>
│  (operador IA)  │──────────────────────┐
└─────────────────┘                      │
                                         ▼
┌──────────────────────────── ALMIRANTE (noc-spxia/apps/api, Go/Fiber) ───────────────────────────┐
│                                                                                                  │
│   /mcp  (mark3labs/mcp-go, StreamableHTTPServer montado via adaptor.HTTPHandler)                 │
│      └─ WithHTTPContextFunc: extrai Bearer → ctx                                                 │
│                                                                                                  │
│   ┌─────────────┐   ┌──────────────────────┐   ┌───────────────────┐   ┌──────────────────────┐ │
│   │ AUTH (JWT/  │──▶│ RBAC deny-by-default  │──▶│  TEST-GATE         │──▶│ AUDIT local + SNAP   │ │
│   │ bcrypt)     │   │ HasPermission(u,a,vm) │   │ cred/tool/prompt   │   │ (almirante_change_   │ │
│   └─────────────┘   └──────────────────────┘   │ reprova → 422      │   │  sets, status)       │ │
│                                                 └─────────┬─────────┘   └──────────┬───────────┘ │
│   CommandCenter web (Next 15) ── REST /api/governance/* ──┤                        │             │
│                                                           ▼                        ▼             │
│                          chatspx.Driver (doMethod: GET/POST/PUT/DELETE, header api_access_token) │
└──────────────────────────────────────────────────────────┬─────────────────────────────────────┘
              REST (api_access_token = PlatformApp), por VM │  baseURL/HMLBaseURL + token + account_id
        ┌──────────────────────────┬──────────────────────┼──────────────────────────┐
        ▼                          ▼                       ▼                          ▼
┌──────────────┐          ┌──────────────┐         ┌──────────────┐          ┌──────────────┐
│ ChatSPX VM A │          │ ChatSPX VM B │         │ ChatSPX HML  │   ...    │ ChatSPX VM N │
│ Spx::AiConfig│          │  (prod)      │         │ (dry-run 1º) │          │              │
│ ChangeSet    │          │              │         │              │          │              │
│ Applier      │          │              │         │              │          │              │
│  ─ apply!    │   POST /spx/ai_config/change_sets                                          │
│  ─ dry_run   │   POST /spx/ai_config/change_sets/dry_run                                  │
│  ─ revert!   │   POST /spx/ai_config/change_sets/:id/revert                               │
│  ─ baseline  │   GET  /spx/ai_config/accounts/:aid/assistants/:id/baseline               │
│  → AiConfigChange (audit no banco da VM, snapshot_before/result)                          │
└──────────────┘          └──────────────┘         └──────────────┘          └──────────────┘
```

**Fluxo canônico de uma escrita** (ex. `update_prompt`):
1. Claude Code chama tool MCP com Bearer do usuário.
2. `WithHTTPContextFunc` põe o token no ctx; handler resolve `user`.
3. RBAC: `HasPermission(user, "write", vm_id)` — deny-by-default.
4. Driver busca **baseline** na VM (`GET .../baseline`) e monta o change-set.
5. **Test-gate**: roda `dry_run` na VM (preview/diff sem escrita) + smoke do prompt contra `captain_scenarios` (golden set) + LLM-juiz. Reprovou → retorna erro, nada aplica.
6. Aprovou → grava `almirante_change_sets` (status `applying`, snapshot do diff) e chama `POST .../change_sets` na VM.
7. Receptor aplica transacional, grava `AiConfigChange` (snapshot_before/result) e responde.
8. Almirante atualiza audit local (`applied`, guarda `remote_change_set_id`).
9. `rollback` futuro: `POST .../change_sets/:id/revert` → `ChangeSetApplier.revert!`.

**Decisão de transporte MCP**: usar `mark3labs/mcp-go` `server.NewStreamableHTTPServer(s, WithEndpointPath("/mcp"), WithHTTPContextFunc(...))`. Como Fiber é fasthttp e o handler é `http.Handler`, montar via `github.com/gofiber/adaptor/v2`: `app.All("/mcp", adaptor.HTTPHandler(httpSrv))`. Editar CORS em `server.go:48-49` para incluir `DELETE` em `AllowMethods` e `Mcp-Session-Id` em `AllowHeaders`.

---

## 2. DECISÃO SOBRE O RECEPTOR DO PAULO: **USAR + AMPLIAR** (não redesenhar)

Justificativa baseada no código (`app/services/spx/ai_config/change_set_applier.rb`, `config_reader.rb`, `app/models/ai_config_change.rb`, `db/migrate/20260629140000_create_ai_config_changes.rb`):

O núcleo caro de acertar já está correto:
- **Transacional tudo-ou-nada**: `ActiveRecord::Base.transaction` (`change_set_applier.rb:71`).
- **Idempotência dupla**: check `applied?` (`:66-67`) + unique index em `change_set_id` (`migrate:26`) + `validates uniqueness` (`ai_config_change.rb:7`).
- **Snapshot + rollback por op**: `snapshot_before`/`result` (`:74-75`), `revert!`/`revert_operation` (`:27-52`), revert na ordem reversa usando `snapshot_before[idx]`.
- **Multi-tenant rígido**: `find_assistant!` escopa `find_by!(id:, account_id:)` (`:136-140`); `TenantViolation` consistente em toda resolução.
- **Reader separado do writer** (`config_reader.rb` read-only) — separação correta.

O próprio cabeçalho do arquivo define o contrato: aplica "uma mudança APROVADA pelo control plane (Almirante)" (`change_set_applier.rb:1-4`). É exatamente a metade executora de um control-plane com aprovação upstream. Redesenhar jogaria fora código transacional/idempotente/reversível correto por zero ganho.

O padrão de extensão de op é limpo e as 4 ops novas (`arm_tool/disarm_tool`, `set_credential`, `update_behavior`, `set_eligibility`) encaixam sem mudança arquitetural: 3 peças por op — `apply_operation`→`[before,after]`, `revert_operation`, `diff_for`, registrar em `SUPPORTED_OPERATIONS` (`:20`).

**Ampliações obrigatórias** (não bloqueiam arquitetura, são itens de trabalho — ver §3 e §12):
1. Criar o **endpoint REST** (hoje o motor é inalcançável — prioridade 1).
2. Persistir status **`failed`** (enum existe em `ai_config_change.rb:5`, nunca é escrito; `apply!` não tem rescue → falha some sem auditoria). Envolver o loop em rescue que grava `failed` em txn separada antes de re-raise.
3. **Relaxar `validate_operation!`** (`:152-156`): hoje exige `assistant_id` em toda op; `set_credential` é account-scoped → exigência por tipo de op.
4. **Padronizar snapshot pra hash/campo inteiro** em `config`/`behavior` (revert exato mesmo quando a chave não existia antes; hoje `update_instructions` guarda parcial `:110`).
5. **Mascarar segredos no diff de `set_credential`** (`AccountIntegration::SECRET_KEYS` + `mask_secret`, `account_integration.rb:21,57-63`) — diff nunca vaza `vista_api_key`/`google_maps_key`.
6. **(Recomendado) guard de drift**: `apply!` recusa se a config viva divergiu da baseline aprovada (version-hash/`expected_before`).
7. **Testes**: zero hoje; specs de service + request specs.

---

## 3. MODELO DE DADOS COMPLETO (DDL)

### 3.1 Almirante (TimescaleDB — catálogo regular, não hypertable)

Criar migration nova `infra/timescaledb-migrations/002_governance.sql` e **espelhar o estado final** em `infra/timescaledb-init.sql` (não há migrator Go — aplicar via `psql -f` / `coolify exec noc-timescale psql ...`; ver §12).

```sql
-- 002_governance.sql  (idempotente)

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()

-- ── Usuários do Almirante ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS almirante_users (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email       TEXT NOT NULL,
  pass_hash   TEXT NOT NULL,              -- bcrypt
  name        TEXT NOT NULL DEFAULT '',
  is_admin    BOOLEAN NOT NULL DEFAULT FALSE,  -- super-admin: bypassa RBAC por VM
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_almirante_users_email
  ON almirante_users (lower(email));

-- ── VMs governadas (uma linha por instância ChatSPX) ──────────────────
CREATE TABLE IF NOT EXISTS vm_targets (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          TEXT NOT NULL,                 -- 'clara-tozi', 'chatspx-prod-1'
  display_name  TEXT NOT NULL,
  base_url      TEXT NOT NULL,                 -- prod  (ex. https://chat.cliente.com.br)
  hml_base_url  TEXT,                          -- homologação p/ dry-run primeiro (nullable)
  account_id    INTEGER NOT NULL,              -- account_id Chatwoot na VM
  token_enc     BYTEA NOT NULL,                -- api_access_token (PlatformApp) CIFRADO (§11)
  token_nonce   BYTEA NOT NULL,                -- nonce AES-GCM
  enabled       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_vm_targets_slug ON vm_targets (slug);

-- ── RBAC: grant direto user × vm × ação (associação, não role→recursos) ─
CREATE TABLE IF NOT EXISTS vm_access (
  user_id    UUID NOT NULL REFERENCES almirante_users(id) ON DELETE CASCADE,
  vm_id      UUID NOT NULL REFERENCES vm_targets(id)      ON DELETE CASCADE,
  permission TEXT NOT NULL CHECK (permission IN ('read','write')),
  granted_by UUID REFERENCES almirante_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, vm_id, permission)
);
CREATE INDEX IF NOT EXISTS ix_vm_access_user ON vm_access (user_id);
-- semântica: 'write' NÃO implica 'read'; conceder ambos explicitamente
-- (ou tratar write⊇read no código — ver §6). Ausência de linha ⇒ deny.

-- ── Change-sets / audit local do Almirante ────────────────────────────
CREATE TABLE IF NOT EXISTS almirante_change_sets (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  change_set_id      TEXT NOT NULL,             -- 'cs_2026...' enviado à VM (idempotência)
  vm_id              UUID NOT NULL REFERENCES vm_targets(id),
  user_id            UUID NOT NULL REFERENCES almirante_users(id),
  operation_type     TEXT NOT NULL,             -- update_instructions | arm_tool | ...
  assistant_id       INTEGER,                   -- nullable (set_credential é account-scoped)
  target_env         TEXT NOT NULL DEFAULT 'prod' CHECK (target_env IN ('hml','prod')),
  status             TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','testing','test_failed',
                                         'applying','applied','failed','reverted')),
  request_payload    JSONB NOT NULL,            -- change-set enviado (SEGREDOS MASCARADOS)
  diff               JSONB,                     -- diff retornado pelo dry_run (mascarado)
  test_report        JSONB,                     -- resultado do test-gate (§7)
  remote_change_set_id TEXT,                    -- id do AiConfigChange na VM
  error              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  applied_at         TIMESTAMPTZ,
  reverted_at        TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_almirante_cs_csid
  ON almirante_change_sets (change_set_id);
CREATE INDEX IF NOT EXISTS ix_almirante_cs_vm_time
  ON almirante_change_sets (vm_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_almirante_cs_status
  ON almirante_change_sets (status);

-- ── Sessões (opcional: JWT stateless dispensa; usar p/ revogação) ─────
CREATE TABLE IF NOT EXISTS almirante_sessions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES almirante_users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL,                    -- sha256 do JWT/opaque (p/ revogar)
  label       TEXT NOT NULL DEFAULT '',         -- 'claude-code-laptop'
  expires_at  TIMESTAMPTZ NOT NULL,
  revoked_at  TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_sessions_token_hash
  ON almirante_sessions (token_hash);
CREATE INDEX IF NOT EXISTS ix_sessions_user ON almirante_sessions (user_id);
```

> Nota de CAUTELA do mapa NOC-GO: o SQL Go diverge da DDL commitada em `events`/`catalog_host`. Antes de aplicar 002, **verificar o schema vivo** do TimescaleDB. As tabelas de governança são novas e isoladas, então não colidem — mas a aplicação é manual (sem goose no boot, confirmado por `grep goose|migrate` = zero em `apps/api`).

O log time-series `events` (`init.sql:211-230`, hypertable com GIN no payload) continua sendo usado para **eventos ao vivo** no dashboard via `InsertEvent` (`timescale_impl.go:168`): cada mudança de governança emite `Event{Source:"governance", Type:"changeset.applied", ...}`. O audit **autoritativo** é `almirante_change_sets`; `events` é a projeção pro CommandCenter.

### 3.2 Ampliações no receptor ChatSPX (Ruby)

Migration nova em `db/migrate/` ampliando `ai_config_changes`:

```ruby
# db/migrate/20260630000000_extend_ai_config_changes.rb
class ExtendAiConfigChanges < ActiveRecord::Migration[7.x]
  def change
    add_column    :ai_config_changes, :error_message,  :text
    add_column    :ai_config_changes, :baseline_hash,  :string   # guard de drift
    add_index     :ai_config_changes, :status
    add_index     :ai_config_changes, [:account_id, :created_at]
  end
end
```

`status` enum já tem `failed: 2` (`ai_config_change.rb:5`) — sem mudança de schema, só passar a escrevê-lo. `snapshot_before`/`result` já são colunas jsonb. As 4 ops novas não exigem tabelas novas — escrevem em estruturas existentes: `assistant.config['tools']` (`assistant.rb:151`), `account_integrations` (provider `vista|google`), `assistant.behavior` store_accessor (`assistant.rb:43-44`), `captain_inboxes` (schema `:429-437`).

---

## 4. CONTRATO CHANGE-SET (JSON) Almirante ↔ Receptor

Envelope (o hash que `ChangeSetApplier` já espera, `change_set_applier.rb:14-16,55,142-150`). O controller passa `params.require(:change_set).to_unsafe_h` — o applier só lê chaves conhecidas.

```json
{
  "change_set": {
    "change_set_id": "cs_2026-06-29T18:22:10Z_a1b2",
    "account_id": 1,
    "author": "almiral:ederson",
    "approved_by": "u_42",
    "operations": [ { "type": "...", "...": "..." } ]
  }
}
```

Regra geral de snapshot/revert: **`before` guarda o campo/hash inteiro**, `revert_operation` reatribui wholesale (resolve a remoção de chave que não existia antes). Cada op abaixo lista apply (`[before,after]`), revert e diff.

### 4.1 `update_instructions` (existente, `:108-113`/`:44-46`/`:124-126`)
```json
{ "type": "update_instructions", "assistant_id": 7,
  "instructions": "Você é a Clara, atendente da Tozi..." }
```
- apply: `before={instructions: old}`, `assistant.update!(... instructions:)`, `after={instructions:new}`.
- revert: `assistant.update!(instructions: before['instructions'])`.
- diff: `{field:'instructions', before, after}`.

### 4.2 `add_faq` (existente, `:115-119`/`:47-50`/`:127-129`)
```json
{ "type": "add_faq", "assistant_id": 7,
  "question": "Qual o horário?", "answer": "8h às 18h, seg a sex." }
```
- apply: cria FAQ/documento, `before={faq_id:nil}`, `after={faq_id:novo}`.
- revert: destrói o FAQ criado por id.
- diff: `{field:'faq', after:{question,answer}}`.

### 4.3 `arm_tool` / `disarm_tool` (novo) — `assistant.config['tools']` array de ids string
```json
{ "type": "arm_tool",    "assistant_id": 7, "tool_id": "get_vista_imoveis" }
{ "type": "disarm_tool", "assistant_id": 7, "tool_id": "get_vista_imoveis" }
```
- validar `tool_id ∈ assistant.available_tool_ids` (`assistant.rb:74-75`) senão `InvalidChangeSet` (id nil derruba a gem).
- apply: `before={'tools'=>Array(config['tools']).map(&:to_s)}`; `new = arm ? (before+[id]).uniq : (before-[id])`; `assistant.update!(config: config.merge('tools'=>new))`; `after={'tools'=>new}`.
- revert (idêntico p/ ambos): `assistant.update!(config: config.merge('tools'=>before['tools']))`.
- diff: `{field:'config.tools', before:lista, after:lista}`.

### 4.4 `set_credential` (novo) — `account_integrations`, account-scoped
```json
{ "type": "set_credential", "provider": "vista",
  "settings": { "vista_api_key": "NOVA_KEY", "vista_base_url": "https://..." },
  "enabled": true }
```
- validar `provider ∈ AccountIntegration::SUPPORTED_PROVIDERS` (`account_integration.rb:19`); `assistant_id` NÃO exigido (relaxar `validate_operation!`).
- apply: `integration = account.account_integrations.find_or_initialize_by(provider:)`; `before={'existed'=>persisted?, 'settings'=>settings&.dup, 'enabled'=>enabled}`; merge reusando `merged_settings`/skip-masked (`integrations_controller.rb:54-64`); `save!`; `after={'provider'=>provider,'integration_id'=>id}`.
- revert: se `before['existed']` → `update!(settings: before['settings'], enabled: before['enabled'])`; senão `find_by(provider:)&.destroy!`.
- diff (**mascarado**): `SECRET_KEYS`+`mask_secret`; `field:"integration.vista.settings"`, before/after com `vista_api_key`/`google_maps_key` mascarados.

### 4.5 `update_behavior` (novo) — `assistant.behavior` store_accessor
```json
{ "type": "update_behavior", "assistant_id": 7,
  "behavior": { "debounce_seconds": 8,
                "humanizer_config": { "enabled": true, "max_bubbles": 3 } } }
```
- whitelist de chaves contra o store_accessor (`debounce_seconds, business_hours_config, humanizer_config, media_pipeline_config, router_config, copilot_trigger_config, dedup_config`) senão `InvalidChangeSet`.
- apply: `before={'behavior'=>assistant.behavior.dup}` (**hash inteiro**); `assistant.update!(behavior: assistant.behavior.merge(op['behavior']))`; `after={'behavior'=>op['behavior']}`.
- revert: `assistant.update!(behavior: before['behavior'])`.
- diff: `{field:"behavior.<key>", before, after}` por chave.

### 4.6 `set_eligibility` (novo) — `captain_inboxes` (join `captain_assistant_id`+`inbox_id`)
```json
{ "type": "set_eligibility", "assistant_id": 7, "inbox_ids": [3, 5, 9] }
```
- tenant check: `account.inboxes.where(id: desired).pluck(:id)`; se tamanho != desired → `TenantViolation`.
- apply: `desired=Array(...).map(&:to_i).uniq`; `before={'inbox_ids'=>assistant.captain_inboxes.pluck(:inbox_id)}`; reconciliar: `CaptainInbox.where(captain_assistant_id:, inbox_id: before-desired).delete_all`; `(desired-before).each { CaptainInbox.create!(...) }`; `after={'inbox_ids'=>desired}`.
- revert: reconciliar de volta pra `before['inbox_ids']`.
- diff: `{field:'eligibility.inbox_ids', before, after}`.

**Multi-op**: `operations` é array — Almirante pode enviar várias numa única transação (ex. `update_instructions` + `arm_tool`). O applier já itera; revert na ordem reversa.

---

## 5. MCP TOOLS (Go, mark3labs/mcp-go) — specs completas

Convenções: handler `func(ctx, mcp.CallToolRequest)(*mcp.CallToolResult,error)`; `vm` sempre é o `slug` de `vm_targets`; RBAC chamado no topo de cada handler com identidade do ctx (`WithHTTPContextFunc`). Test-gate só em escritas. Erros de validação → `mcp.NewToolResultError`. Definição com `mcp.NewTool(... WithString/WithNumber/WithBoolean, Required, Enum, Description)`.

### LEITURA (RBAC: `read`, sem test-gate)

| Tool | Params | Descrição | RBAC | Implementação |
|---|---|---|---|---|
| **`list_vms`** | — | Lista VMs que o usuário pode ver. | `read` (filtra por grants) | `SELECT` em `vm_targets ⋈ vm_access` p/ `user`. |
| **`get_agent`** | `vm:string!`, `assistant_id:number!` | Baseline completo do agente (instructions, faqs, tools, behavior, eligibility). | `read` na vm | `Driver.GetBaseline` → `GET .../baseline` (`ConfigReader.export`). |
| **`list_tools`** | `vm:string!`, `assistant_id:number!` | Tools built-in disponíveis + armadas (`available_tool_ids` vs `config['tools']`). | `read` na vm | `GET` config do assistant. |
| **`list_custom_tools`** | `vm:string!` | Custom tools da conta (`captain_custom_tools`). | `read` na vm | `GET /api/v1/accounts/:id/captain/custom_tools` (ou eq.). |
| **`history`** | `vm:string!`, `assistant_id?:number`, `limit?:number` | Histórico de change-sets (audit local + status). | `read` na vm | `SELECT ... FROM almirante_change_sets WHERE vm_id ORDER BY created_at DESC`. |

### ESCRITA (RBAC: `write`, com test-gate por tipo)

| Tool | Params | Descrição | RBAC | Test-gate |
|---|---|---|---|---|
| **`update_prompt`** | `vm:string!`, `assistant_id:number!`, `instructions:string!`, `target_env?:enum(hml,prod)` | Reescreve as instructions do agente. | `write` | **prompt**: dry_run + smoke + regressão `captain_scenarios` + LLM-juiz (§7). |
| **`set_tool_arming`** | `vm:string!`, `assistant_id:number!`, `tool_id:string!`, `armed:boolean!` | Arma/desarma tool built-in (gera `arm_tool`/`disarm_tool`). | `write` | **tool**: valida `tool_id∈available`; `perform_test` HTTP da tool se armando. |
| **`set_credential`** | `vm:string!`, `provider:enum(vista,google)!`, `settings:object!`, `enabled?:boolean` | Define credencial de integração da conta. | `write` | **credencial**: `test_connection` antes de aplicar (§7); diff mascarado. |
| **`upsert_custom_tool`** | `vm:string!`, `tool:object!` (name, description, http_method, url, auth, schema) | Cria/edita custom tool (`captain_custom_tools`). | `write` | **tool**: `perform_test` HTTP (request real ao endpoint). |
| **`update_behavior`** | `vm:string!`, `assistant_id:number!`, `behavior:object!` | Ajusta debounce/humanizer/router/etc. | `write` | **prompt-lite**: dry_run + smoke (não quebra) + regressão se afeta roteamento. |
| **`set_eligibility`** | `vm:string!`, `assistant_id:number!`, `inbox_ids:number[]!` | Define em quais inboxes o agente atua. | `write` | dry_run + tenant check (TenantViolation→422). |
| **`add_faq`** | `vm:string!`, `assistant_id:number!`, `question:string!`, `answer:string!` | Adiciona FAQ ao agente. | `write` | dry_run + smoke (FAQ não contradiz). |
| **`rollback`** | `vm:string!`, `change_set_id:string!` | Reverte um change-set aplicado (chama `revert!`). | `write` | sem gate (restaura snapshot); valida que `change_set_id` está `applied`. |

Toda tool de escrita: resolve baseline → monta change-set (§4) → grava `almirante_change_sets` (`pending`→`testing`→`applying`→`applied`/`failed`) → chama Driver. `add_faq` listada por completude (o receptor já tem a op).

Registro: instanciar o MCP server em helper chamado por `server.New()` (`server.go:31`), injetando `store.Store` + `chatspx.Driver` + RBAC. `s.AddTool(tool, handler)` para cada uma.

---

## 6. RBAC — DDL + middleware Go (deny-by-default)

DDL: `vm_access` (§3.1). Padrão Aserto: `Authorizer` interface + deny-by-default.

```go
// internal/governance/rbac.go
type Authorizer interface {
    HasPermission(ctx context.Context, userID, action, vmSlug string) bool
}

type DBAuthorizer struct {
    db    store.Store
    cache *ttlcache.Cache[string, bool] // chave "user|action|vm", TTL 30s
}

func ActionFromMethod(method string) string {
    switch method {
    case http.MethodGet:                          return "read"
    case http.MethodPost, http.MethodPut,
         http.MethodPatch, http.MethodDelete:     return "write"
    default:                                       return "" // verbo desconhecido ⇒ deny
    }
}

func (a *DBAuthorizer) HasPermission(ctx context.Context, userID, action, vmSlug string) bool {
    if action == "" || userID == "" || vmSlug == "" {
        return false // DENY BY DEFAULT
    }
    key := userID + "|" + action + "|" + vmSlug
    if v, ok := a.cache.GetOrNil(key); ok { return *v }

    // super-admin bypassa grants por VM
    if a.db.UserIsAdmin(ctx, userID) { a.cache.Set(key, true); return true }

    // write ⊇ read: para 'read', aceita grant read OU write
    perms := []string{action}
    if action == "read" { perms = []string{"read", "write"} }

    ok := a.db.HasVMAccess(ctx, userID, vmSlug, perms) // SELECT 1 ... LIMIT 1
    a.cache.Set(key, ok)                                // cachear (roda a cada tool call)
    return ok // ausência de linha ⇒ false ⇒ deny
}
```

`HasVMAccess` (impl em `timescale_impl.go`, interface em `queries.go`):
```sql
SELECT 1 FROM vm_access va
  JOIN vm_targets vt ON vt.id = va.vm_id
 WHERE va.user_id = $1 AND vt.slug = $2
   AND va.permission = ANY($3) AND vt.enabled = TRUE
 LIMIT 1;
```

**Dois pontos de enforcement, mesma política:**

1. **REST (CommandCenter)** — middleware Fiber no grupo `/api/governance` (após JWT, antes do handler), derivando `vm` do path/body:
```go
func RBACMiddleware(a Authorizer) fiber.Handler {
    return func(c *fiber.Ctx) error {
        user := userFromLocals(c)                  // do JWT (§9)
        vm   := c.Params("vm") // ou parse do body
        if !a.HasPermission(c.UserContext(), user, ActionFromMethod(c.Method()), vm) {
            return c.SendStatus(fiber.StatusForbidden) // 403
        }
        return c.Next()
    }
}
```

2. **MCP** — no topo de **cada tool handler** (a ação vem do tipo da tool, não do verbo HTTP — todas as chamadas MCP são POST):
```go
func (h *Tools) updatePrompt(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    user := userFromCtx(ctx)                           // set por WithHTTPContextFunc
    vm, _ := req.RequireString("vm")
    if !h.authz.HasPermission(ctx, user, "write", vm) {
        return mcp.NewToolResultError("forbidden: no write on "+vm), nil
    }
    // ... baseline → test-gate → apply
}
```
Leituras (`list_vms`, `get_agent`, ...) usam `"read"`; escritas usam `"write"`. `list_vms` filtra a saída pelos grants do usuário em vez de negar.

---

## 7. TEST-GATE — fluxo por tipo (ANTES de aplicar)

O gate roda no Almirante após RBAC e antes do `POST .../change_sets`. Status `testing`; se reprova → `test_failed`, grava `test_report`, **nada chega à VM em modo apply**. Toda escrita primeiro faz **`dry_run` na VM** (preview/diff sem escrita, `change_set_applier.rb:60-62`) e, se houver `hml_base_url`, **aplica em HML antes de prod** (`cfg.ChatSPX.HMLBaseURL`, ocioso hoje, `config.go:229`).

### 7.1 Credencial (`set_credential`)
1. `dry_run` na VM → valida shape e que `provider∈SUPPORTED_PROVIDERS`.
2. **`test_connection`**: Almirante chama um endpoint de teste no ChatSPX (novo, `POST .../change_sets/test_credential`) que faz request real à API do provider (Vista/Google) com as `settings` propostas, **sem persistir**. Para Vista: GET autenticado de baixo custo (ex. metadados). Para Google: ping à Geocoding/Places.
3. **Reprova se**: provider não suportado, auth falha (401/403 no provider), timeout, settings incompletas.
4. Aprova → aplica; diff **mascarado** no audit.

### 7.2 Tool (`set_tool_arming` armando, `upsert_custom_tool`)
1. `dry_run` valida `tool_id∈available_tool_ids` (built-in) ou shape da custom tool.
2. **`perform_test`**: dispara a tool de verdade contra um payload sintético (custom tool: HTTP request real ao `url` com `auth`/`schema`; built-in: dry-call). Endpoint novo `POST .../tools/perform_test`.
3. **Reprova se**: endpoint retorna 4xx/5xx, timeout, schema de resposta inválido, tool_id inexistente.
4. Aprova → arma/persiste.

### 7.3 Prompt (`update_prompt`, `update_behavior`, `add_faq`)
Pipeline de 4 etapas (golden set = `captain_scenarios` da conta):
1. **dry_run** na VM (diff, sem escrita).
2. **Smoke** (heurístico, barato): roda o novo prompt contra 2-3 mensagens canônicas e checa:
   - não quebra / não retorna vazio / não estoura;
   - **responde em pt-BR** (detector de idioma);
   - **dispara a tool certa** quando o cenário exige (ex. pergunta de imóvel → `get_vista_imoveis`).
3. **Regressão (golden set)**: para cada `captain_scenario` da conta, roda o agente com o prompt novo e compara o comportamento (resposta/tool calls) ao baseline esperado do cenário. Os `captain_scenarios` são o conjunto golden — divergência marcada.
4. **LLM-juiz**: um modelo avalia, por cenário, se a resposta nova é >= baseline em fidelidade/segurança/tom (rubrica: não inventou, chamou pessoa pelo nome, IGNORAR só pra espera de humano — alinhado aos commits `ddd9450df`/`80e2a9c9c`). Saída: score 0-1 + veredito por cenário.

**Reprova se**: smoke falha em qualquer item; regressão quebra > limiar de cenários; LLM-juiz dá veredito abaixo do threshold (ex. média < 0.8 ou qualquer cenário crítico < 0.6). `test_report` (JSONB) guarda smoke + tabela por cenário + score do juiz.

Onde roda o eval: o Almirante orquestra, mas a execução do agente contra cenários acontece **na VM** (tem o engine Captain + `captain_scenarios`), via endpoint de eval novo no ChatSPX (`POST .../change_sets/eval_prompt` recebendo o prompt candidato + ids de cenários) que retorna respostas/tool-calls; o LLM-juiz roda no Almirante (chave OpenAI já em config). Aplicar em HML primeiro quando `hml_base_url` existe reduz risco a zero em prod.

---

## 8. AUDIT + ROLLBACK

**Dois níveis de audit, encadeados por `change_set_id`:**

| Nível | Onde | Conteúdo |
|---|---|---|
| Almirante (autoritativo do control-plane) | `almirante_change_sets` (§3.1) | quem (user), qual VM, tipo, env, status, payload mascarado, diff, **test_report**, `remote_change_set_id`, timestamps. |
| ChatSPX (executor por VM) | `AiConfigChange` (`ai_config_change.rb`) | `snapshot_before`/`result` por op, author/approved_by/applied_at/reverted_at, status (`applied`/`reverted`/`failed`). |
| Projeção ao vivo | `events` hypertable | `InsertEvent(Source:"governance", Type:"changeset.applied|reverted|test_failed")` p/ o CommandCenter. |

**Relação**: o `change_set_id` gerado pelo Almirante é o mesmo enviado à VM e gravado em `AiConfigChange.change_set_id` (unique). O Almirante guarda o `remote_change_set_id` (id PK do `AiConfigChange`) na resposta. Idempotência ponta-a-ponta: reenvio do mesmo `change_set_id` → applier retorna o existente (`:66-67`), Almirante não duplica.

**Rollback (tool `rollback` / botão no CommandCenter):**
1. Almirante valida que o `almirante_change_sets` alvo está `applied` e RBAC `write` na VM.
2. `POST .../change_sets/:change_set_id/revert` → `ChangeSetApplier.revert!` reverte na ordem reversa usando `snapshot_before` (`:27-52`).
3. Receptor marca `AiConfigChange` como `reverted` (`reverted_at`).
4. Almirante marca o registro local `reverted`, emite `Event{Type:"changeset.reverted"}`.

Re-apply após revert é permitido pelo applier (flip `reverted→applied`, novo snapshot) — Almirante expõe isso como "reaplicar" e documenta a semântica.

**Persistência de `failed`** (ampliação §2): se `apply!` lança, o receptor (após o rescue novo) grava `AiConfigChange status:failed` em txn separada com `error_message`; o Almirante recebe erro, marca local `failed` com `error`. Falha deixa rastro nos dois lados.

---

## 9. LOGIN/AUTH (Go/Fiber)

Identidade única HS256 para CommandCenter **e** MCP. Greenfield (não há auth de usuário hoje, confirmado: `grep jwt|session|login|bcrypt` em `internal/` = nada; `golang.org/x/crypto v0.31.0` já no `go.sum` → bcrypt disponível).

**Config nova** (`config.go`, sub-struct): `JWT_SECRET` (obrigatório, validar em `validate()` `:273`), `JWT_TTL` (default 24h ou 30d para tokens de MCP).

**Tabelas**: `almirante_users`, `almirante_sessions` (§3.1).

**Hash** (`golang.org/x/crypto/bcrypt`):
```go
hash, _ := bcrypt.GenerateFromPassword([]byte(plain), bcrypt.DefaultCost) // criar user
err := bcrypt.CompareHashAndPassword(user.PassHash, []byte(plain))         // login
```

**Login handler** (`internal/api/auth.go`, registrar em `server.go:61-68`) — emite JWT:
```go
claims := jwt.MapClaims{"sub": user.ID, "email": user.Email,
                        "admin": user.IsAdmin,
                        "exp": time.Now().Add(cfg.JWTTTL).Unix(), "jti": uuid}
tok, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(secret))
// CommandCenter: cookie HTTP-only; sha256(tok) gravado em almirante_sessions p/ revogação
c.Cookie(&fiber.Cookie{Name:"jwt", Value:tok, HTTPOnly:true, Secure:true, SameSite:"Lax",
                       Expires: time.Now().Add(cfg.JWTTTL)})
```

**Middleware** (`github.com/gofiber/contrib/jwt`, mesma família do `gofiber/contrib/websocket` já usado):
```go
app.Use(jwtware.New(jwtware.Config{
    SigningKey:   jwtware.SigningKey{Key: []byte(secret)},
    TokenLookup:  "cookie:jwt,header:Authorization", // cookie (web) OU Bearer (MCP/CLI)
    ErrorHandler: func(c *fiber.Ctx, err error) error { return c.SendStatus(401) },
}))
```
Aplicar a `app.Group("/api/governance", jwtware..., RBACMiddleware...)`. Claims em `c.Locals("user")`.

**Tokens de MCP por usuário**: endpoint `POST /api/governance/tokens` (autenticado) que emite um JWT de longa duração (label "claude-code-laptop"), grava `sha256` em `almirante_sessions` (revogável). O usuário cola esse Bearer no `claude mcp add`. Revogação: `DELETE /api/governance/tokens/:id` marca `revoked_at`; middleware checa `almirante_sessions` quando o JWT tem `jti` de sessão.

**MCP autentica o mesmo Bearer**: `server.WithHTTPContextFunc(func(ctx, r){ return context.WithValue(ctx,"authz", r.Header.Get("Authorization")) })` lifta o header pro ctx; um helper valida o JWT (mesmo secret), resolve `user`, e os handlers chamam RBAC. `/mcp` **nunca** é aberto (hoje GET/WS são abertos — `server.go:78`; o grupo MCP precisa do guard).

---

## 10. INSTALAÇÃO FÁCIL DO MCP (Claude Code)

**Comando único** (o que se entrega à pessoa):
```bash
claude mcp add --transport http almirante https://api.dashboard.simplexsolucoes.com.br/mcp \
  --header "Authorization: Bearer <TOKEN_DO_USUARIO>"
```
`--transport http` = Streamable HTTP remoto (em JSON `type` aceita `"streamable-http"` como alias de `"http"`).

**`.mcp.json` project-scope** (commitado no repo de operação, com expansão de env para não hard-codar token):
```json
{
  "mcpServers": {
    "almirante": {
      "type": "http",
      "url": "${ALMIRANTE_URL:-https://api.dashboard.simplexsolucoes.com.br}/mcp",
      "headers": { "Authorization": "Bearer ${ALMIRANTE_TOKEN}" }
    }
  }
}
```
Onboarding de novo operador: (1) admin cria o user no CommandCenter e concede grants `read`/`write` por VM; (2) operador faz login e gera um token de MCP (label); (3) `export ALMIRANTE_TOKEN=...` e o `.mcp.json` já committado conecta; Claude Code aprova o project server uma vez.

**Token curto/rotativo** (governança-friendly) — `headersHelper` em vez de header estático (Claude Code re-roda e tenta de novo em 401/403):
```json
{ "mcpServers": { "almirante": {
  "type": "http", "url": "https://api.dashboard.simplexsolucoes.com.br/mcp",
  "headersHelper": "/opt/bin/get-almirante-token.sh" }}}
```
Nota: com Bearer estático, o token tem que ser válido no install (servidor rejeita → Claude Code reporta falha, não cai em OAuth). Por isso o token de sessão de longa duração + revogação por `almirante_sessions`.

---

## 11. SEGURANÇA

- **Token admin por VM**: `api_access_token` (owner `PlatformApp`, máquina-a-máquina, espelhando `platform_controller.rb:18-26`) guardado **cifrado** em `vm_targets.token_enc` (AES-GCM, `token_nonce`). Chave de cifragem (`ALMIRANTE_ENC_KEY`, 32 bytes) só em env/secret do Coolify (`api.coolify.yml`), nunca no banco nem no repo. Decifra em memória só na hora do request ao receptor. Nunca exposto por nenhuma tool/endpoint.
- **Secrets nunca em claro no audit**: o diff de `set_credential` passa por `SECRET_KEYS`+`mask_secret` (`account_integration.rb:21,57-63`) **no receptor** antes de virar `result`/`diff`, e o Almirante grava `request_payload`/`diff` já mascarados em `almirante_change_sets`. `events` idem. Regra: nenhum `vista_api_key`/`google_maps_key`/`pass_hash` em coluna jsonb legível.
- **Deny-by-default em toda superfície**: RBAC nega sem linha em `vm_access`; verbo HTTP desconhecido → ação vazia → deny; `/mcp` e `/api/governance/*` exigem JWT válido; CORS allowlist (`server.go:45-53`) limita browser. Os GET telemetria existentes seguem abertos (TV), mas governança é isolada atrás de auth.
- **Audit estruturado (JSON)**: zerolog já é o logger (`server.go:100-113`); cada ação de governança emite log estruturado `{user, vm, op, change_set_id, status, duration}` + `events` jsonb + `almirante_change_sets`. Trilha completa: quem mudou o quê, em qual VM, quando, aprovado por teste X.
- **Guard-rail "MCP não vira SSH"**: o conjunto de tools é **fechado e tipado** — só operações de config de IA (prompt/faq/tool/credencial/behavior/eligibility/rollback). **Não existe** tool de shell, exec, query SQL arbitrária, file write, nem deploy. O Driver só fala a REST `/api/v1/accounts/:id/...` do Chatwoot (métodos parametrizados em `doMethod`, `client.go:80-108`), nunca um canal genérico. Distinção dura reforçada no design: IA = change-set via Almirante; código do produto = Coolify/deploy, fora do Almirante. Qualquer operação que não seja uma das tools do §5 é, por construção, impossível.
- **Pré-prod obrigatório**: quando `vm_targets.hml_base_url` existe, escritas passam por HML antes de prod (test-gate §7) — alinha à regra "testar antes de mergear".

---

## 12. FASES DE IMPLEMENTAÇÃO

Dependência geral: **F1 (receptor alcançável) e F2 (auth/RBAC) podem ir em paralelo**; F3 depende de F1+F2; F4 (test-gate) depende de F3; F5 (web) depende de F2/F3; F6 (hardening) fecha.

### F1 — Receptor ChatSPX alcançável + ampliado (Ruby, `/home/chatwoot/chatwoot/`) — *sem dependências*
Criar:
- `app/controllers/spx/ai_config/base_controller.rb` — `authenticate_almiral!` (header `api_access_token` → `AccessToken.find_by` → owner `PlatformApp`), `rescue_from` (InvalidChangeSet/Unsupported→422, TenantViolation→403, RecordNotFound→404).
- `app/controllers/spx/ai_config/config_controller.rb` — `#baseline` → `ConfigReader.export`.
- `app/controllers/spx/ai_config/change_sets_controller.rb` — `#dry_run`, `#apply`, `#revert`, `#show`.
- Rotas em `config/routes.rb` (namespace `spx/ai_config`, ver §3 RECEPTOR-CHATSPX).
- `db/migrate/20260630000000_extend_ai_config_changes.rb` (error_message, baseline_hash, índices).

Editar `app/services/spx/ai_config/change_set_applier.rb`:
- `SUPPORTED_OPERATIONS` (`:20`) += `arm_tool, disarm_tool, set_credential, update_behavior, set_eligibility`.
- `validate_operation!` (`:152-156`) — `assistant_id` por tipo de op.
- Novos `apply_operation`/`revert_operation`/`diff_for` das 5 ops (§4.3-4.6).
- rescue em `apply!` que grava `failed` em txn separada.
- snapshot wholesale em `config`/`behavior`.
- mascarar segredos no diff de `set_credential`.
- (opcional) guard de drift via `baseline_hash`.

Endpoints de test-gate (consumidos pelo Almirante): `#test_credential`, `#perform_test` (tool), `#eval_prompt` (roda agente contra `captain_scenarios`).

Specs: service (apply/revert/idempotência/tenant/failed) + request specs do endpoint.

### F2 — Auth + RBAC no Almirante (Go, `noc-spxia/apps/api`) — *sem dependências*
- `infra/timescaledb-migrations/002_governance.sql` + espelhar em `infra/timescaledb-init.sql`; aplicar via `psql`/`coolify exec` (não há goose).
- `internal/config/config.go` — `JWT_SECRET`, `JWT_TTL`, `ALMIRANTE_ENC_KEY` (+ `.env.example`, `validate()`).
- `internal/store/queries.go` + `timescale_impl.go` + `nopStore` — métodos: `CreateUser`, `GetUserByEmail`, `UserIsAdmin`, `HasVMAccess`, `ListVMsForUser`, `UpsertVMTarget`, `GrantAccess`, `Insert/UpdateChangeSet`, `ListChangeSets`, sessões.
- `internal/governance/rbac.go` — `Authorizer`/`DBAuthorizer` + cache TTL (§6).
- `internal/api/auth.go` — login, criação de user (admin), emissão/revogação de token MCP.
- `internal/server/server.go` — `app.Group("/api/governance", jwtware.New(...), RBACMiddleware(...))`; threadar deps novas em `server.New` (`:31`) ← `main.go:271`. `go get github.com/gofiber/contrib/jwt`.

### F3 — Driver ChatSPX de escrita + MCP server (Go) — *depende de F1, F2*
- Promover `internal/collectors/chatspx/client.go` → `internal/chatspx/driver.go`: generalizar `do()` (`:80`) em `doMethod(ctx, method, path, body, out)` (trocar o hardcode `http.MethodGet` `:87`; manter header `api_access_token` `:91` e prefixo `/api/v1/accounts/{id}` `:83`). Resolver baseURL/token/account_id por **VM** (de `vm_targets`, decifrando token).
- `Driver`: `GetBaseline`, `DryRun`, `Apply`, `Revert`, `TestCredential`, `PerformTest`, `EvalPrompt`.
- `internal/governance/mcp.go` — `server.NewMCPServer` + as 11 tools (§5); montar via `adaptor.HTTPHandler(server.NewStreamableHTTPServer(s, WithEndpointPath("/mcp"), WithHTTPContextFunc(...)))` em `app.All("/mcp", ...)`. `go get github.com/mark3labs/mcp-go github.com/gofiber/adaptor/v2`.
- CORS: editar `server.go:48` (+`DELETE`) e `:49` (+`Mcp-Session-Id`).
- `internal/api/governance.go` — handlers REST espelho das tools (CommandCenter): `ApplyChangeset`, `Rollback`, `GetAgent`, `History`, `ListVMs`; cada um emite `InsertEvent` (`timescale_impl.go:168`).
- Shutdown: sessões SSE cobertas por `app.ShutdownWithTimeout(10s)` (`server.go:96`).

### F4 — Test-gate (Go orquestra, ChatSPX executa) — *depende de F3*
- `internal/governance/testgate.go` — dispatcher por tipo: `gateCredential` (→ `Driver.TestCredential`), `gateTool` (→ `Driver.PerformTest`), `gatePrompt` (dry_run + smoke + `Driver.EvalPrompt` contra `captain_scenarios` + LLM-juiz).
- LLM-juiz: cliente OpenAI (chave já em config) com rubrica de fidelidade/pt-BR/tool-certa/não-inventar; thresholds configuráveis.
- Toda tool de escrita do §5 chama o gate antes do `Apply`; grava `test_report` e seta `test_failed` em reprovação. Aplicar em HML antes de prod quando `hml_base_url` presente.

### F5 — CommandCenter / Governança (Next 15, `noc-spxia/apps/web`) — *depende de F2, F3*
- Rota nova `app/governanca/page.tsx` (+`layout.tsx` próprio) — **sem** `StageFit` (é admin interativo, não TV).
- Login: `app/login/page.tsx` + guard (criar `middleware.ts`, inexistente hoje).
- `components/governance/` — tabela de VMs, editor de prompt, diff viewer, painel de histórico/rollback, modal de credencial. `pnpm dlx shadcn@latest add table dialog textarea button select` (`components.json` já configurado).
- `lib/governance.ts` — client REST (padrão `lib/api.ts`, `NEXT_PUBLIC_API_URL`), SWR p/ leitura, POST p/ mutação.
- Slice Zustand novo (`lib/store.ts`) p/ estado de governança.

### F6 — Segurança, deploy, hardening — *depende de F1–F5*
- Cifragem AES-GCM do token por VM (`ALMIRANTE_ENC_KEY` como Secret no Coolify).
- Revisão de mascaramento de segredos ponta-a-ponta (audit local + `events` + `AiConfigChange`).
- Coolify: adicionar envs (`JWT_SECRET`, `ALMIRANTE_ENC_KEY`, providers) em `infra/coolify/api.coolify.yml` + `.env.example`. Rebuild web se mudar `NEXT_PUBLIC_*` (build-arg, bakeado).
- Seed: criar primeiro admin (`almirante_users`) + cadastrar VMs (`vm_targets`) + grants iniciais.
- Validação UI (light+dark, Playwright) da tela de governança antes de reportar pronto.
- Testes Go (rbac, testgate, driver) + specs Ruby (F1).

**Caminho crítico**: F1 → F3 → F4 (executor → driver/MCP → gate). F2 destrava F3 e F5. Entregar F1+F2+F3 já dá MCP funcional com RBAC e audit; F4 adiciona a rede de segurança 2; F5 é o complemento web; F6 fecha segurança/deploy.

---

### Arquivos a criar/editar (resumo)

**noc-spxia (Go)** — criar: `internal/governance/{rbac,mcp,testgate}.go`, `internal/chatspx/driver.go`, `internal/api/{auth,governance}.go`, `infra/timescaledb-migrations/002_governance.sql`. Editar: `internal/server/server.go` (`:31,48-49,56-68`), `cmd/server/main.go` (`:271`), `internal/config/config.go`, `internal/store/{queries.go,timescale_impl.go}`, `infra/timescaledb-init.sql`, `.env.example`, `go.mod` (mcp-go, adaptor/v2, contrib/jwt).

**noc-spxia (Next)** — criar: `apps/web/app/{governanca,login}/page.tsx`, `middleware.ts`, `components/governance/*`, `lib/governance.ts`. Editar: `lib/store.ts`, `infra/coolify/api.coolify.yml`.

**ChatSPX (Ruby)** — criar: `app/controllers/spx/ai_config/{base,config,change_sets}_controller.rb`, `db/migrate/20260630000000_extend_ai_config_changes.rb`, specs. Editar: `config/routes.rb`, `app/services/spx/ai_config/change_set_applier.rb`, `app/models/ai_config_change.rb`.
