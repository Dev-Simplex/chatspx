# Almirante × MCP de Governança de IA — Plano

> **Objetivo:** aposentar o acesso SSH na operação de IA do ChatSPX. Toda mudança de IA em
> produção (prompt de agente, armar tools, credenciais, custom tools) passa a ser feita por uma
> porta **governada** — com controle de acesso por VM, **teste automático antes de aplicar**,
> auditoria e **rollback** — sem perder a agilidade do dev (tools na própria VM continuam livres).

Status: **planejamento** (nada implementado no Almirante ainda). Decisões abaixo foram fechadas
com o Walisson em 2026-06-29.

> **Atualização 2026-06-30 (escopo refinado):**
> - **Toda operação de IA** (prompt, armar tools, credenciais, custom tools) passa pelo **MCP do Almirante**, usado via **Claude Code**. A interface principal é o **MCP** (não a tela web) → prioridade extra: **instalação do MCP trivial** pra qualquer pessoa (script/one-liner).
> - **Exceção:** trazer **código novo do ChatSPX** (Ruby/Vue do produto) continua no fluxo de dev na VM (dev normal + deploy).
> - **Login:** próprio simples no Almirante (email+senha).
> - A tela web (CommandCenter) vira bônus posterior; o **MCP-first** manda.

---

## 1. Princípio central

Em vez de **fila de aprovação por mudança** (lento), a governança da produção se apoia em **3 redes**:

1. **RBAC leitura/escrita por VM** — só quem tem `write` numa VM consegue alterar a IA daquela VM.
2. **Test-gate automático** — antes de aplicar, a mudança é testada; se falhar, é **recusada** (nem aplica).
3. **Histórico + rollback** — toda escrita guarda `before/after` (quem/quando); dá pra reverter em 1 clique.

> Test-gate barra o erro **antes** (faz o papel do aprovador). Rollback conserta o que escapar **depois**.
> RBAC garante que cada produção só é tocada por quem deve.

---

## 2. Estado atual (o que já existe)

### 2.1 Almirante = repo `Dev-Simplex/noc-spxia`
- **Stack:** Go 1.23 (Fiber) + Next.js 16 + TimescaleDB + Redis · deploy **Coolify** · roda na **192.168.8.229 (PRODUÇÃO)**.
- **Hoje é só observabilidade:** collectors read-only (`chatspx`, `coolify`, `docker`, `proxmox`,
  `claude`/`openai`, `waha`…), `POST /api/ingest/*` (server-to-server, `NOC_INGEST_TOKEN`),
  WebSocket hub, front `apps/web/components/v3/CommandCenter.tsx`.
- **NÃO tem:** MCP, endpoints de mutação, login de usuário, aprovação.
- **Por que é o lugar certo:** já é o servidor Go central que conhece a frota (`domain/fleet|host|service`)
  e já fala com ChatSPX + Coolify; já tem DB (audit), WebSocket (notificar) e CommandCenter (UI).

### 2.2 `chatspx-tools` (já feito — modo dev)
- MCP **stdio** (Node, SDK oficial), 6 tools de custom tools, **governado** (tool nasce `disabled`,
  `enabled:true` recusado, audit no stderr). Em `mcp/chatspx-tools/` no repo `chatspx`.
- Falta: tool pra editar **prompt do agente** (hoje cobre só custom tools).

### 2.3 REST do ChatSPX (base pronta pra o Almirante consumir)
- `assistants` (prompt/config via PATCH), `custom_tools` (+ `test`), `integrations` (+ `test_connection`),
  `account_integrations` (credenciais Vista/Google). Tudo já com `api_access_token`.

---

## 3. Arquitetura — dois modos

```
┌─ MODO DEV (livre) ─────────────────────────────────────────┐
│ Dev (Claude Desktop) ──MCP stdio──> API ChatSPX da VM dele  │
│   cria/edita/testa TOOLS direto         (chatspx-tools Node) │
└──────────────────────────────────────────────────────────────┘

┌─ MODO PRODUÇÃO (governado) ────────────────────────────────┐
│ Pessoa (Claude Desktop / web) ──MCP HTTP──> ALMIRANTE /mcp  │
│   update_agent_prompt(vm, agente, …)                        │
│        │ 1. RBAC: user tem WRITE nessa VM?  não → nega       │
│        │ 2. lê before via API da VM                          │
│        │ 3. TEST-GATE (ver §5)            falhou → recusa    │
│        │ 4. aplica after via API da VM                       │
│        │ 5. grava histórico (before/after/quem/quando)       │
│        ▼ 6. WebSocket → CommandCenter                        │
│   Aprovador? NÃO. Quem tem WRITE aplica; rollback é a rede.  │
└──────────────────────────────────────────────────────────────┘
```

---

## 4. Governança — decisões fechadas

| Tema | Decisão |
|---|---|
| Implementação do MCP central | **Nativo em Go** no Almirante (`mark3labs/mcp-go`), transporte **Streamable HTTP** (`/mcp`) |
| Gate de produção | **Sem fila de aprovação.** RBAC por VM + test-gate + rollback |
| RBAC | **Leitura / Escrita por VM** (deny-by-default) |
| Eval de IA (prompt) | **Smoke + regressão com `captain_scenarios` (golden set) + LLM-juiz** |
| Rollback de credencial | **Testar antes** (`test_connection`); **não** guardar secret em claro no histórico |
| Modo dev | tools na VM do dev seguem livres (`chatspx-tools` Node stdio) |

---

## 5. Test-gate (antes de aplicar em produção)

| O que muda | Como testa | Status |
|---|---|---|
| **Credencial** (Vista/Google) | `test_connection` — bate na API, exige 200 | ✅ existe |
| **Tool HTTP** (custom) | `perform_test` — chama endpoint real com params de exemplo | ✅ existe |
| **Prompt / IA** | **smoke** (não quebra, responde pt-BR, dispara a tool certa) + **regressão**: roda os `captain_scenarios` da conta como golden set e um **LLM-juiz** compara antes/depois | 🔧 a construir |
| **Código** | suíte do `chatspx` (RSpec/Vitest) antes de promover homologação→produção | ✅ existe (orquestração no deploy) |

> Eval de IA é **rede, não garantia** (LLM é probabilístico): smoke pega quebras; regressão pega
> degradação de qualidade. Se o eval reprovar, a mudança é recusada e o diff dos cenários piorados é retornado.

---

## 6. Modelo de dados (no Almirante / TimescaleDB)

```
almirante_users(id, email, nome, role, created_at)
vm_targets(id, slug, nome, ambiente['prod'], chatspx_base_url, chatspx_account_id, admin_token_ref)
vm_access(user_id, vm_id, perm['read'|'write'])                      -- RBAC, deny-by-default
ia_change_log(                                                       -- append-only (audit + rollback)
  id, ts, user_id, vm_id,
  entity_type['agent_prompt'|'tool_arming'|'custom_tool'|'credential'],
  entity_ref,                       -- ex.: assistant_id / tool slug / provider
  action['update'|'rollback'],
  before jsonb, after jsonb,        -- secrets SEMPRE mascarados
  test_result jsonb,                -- saída do test-gate
  source['mcp'|'ui'],
  reverts_change_id null            -- preenchido quando é rollback
)
```

`admin_token_ref` = referência ao `api_access_token` admin do ChatSPX daquela VM, guardado como
secret do Almirante (Coolify env / secret store) — nunca no log, nunca no front.

---

## 7. MCP tools (Go nativo, `/mcp`)

**Leitura** (exige `read` na VM):
- `list_vms()` — VMs que o usuário pode ver/escrever
- `get_agent(vm, agente)` — prompt/config atual
- `list_tools(vm[, agente])` — catálogo + armadas
- `history(vm[, entity])` — linha do tempo do `ia_change_log`

**Escrita** (exige `write` na VM → roda test-gate → grava log):
- `update_agent_prompt(vm, agente, {instructions, guardrails, guidelines, …})`
- `set_tool_arming(vm, agente, tools[])`
- `upsert_custom_tool(vm, {…})`
- `set_credential(vm, provider, settings)` — roda `test_connection`, secrets mascarados no log
- `rollback(change_id)`

---

## 8. Fluxos

**Aplicar prompt em produção**
1. user chama `update_agent_prompt` (autenticado no Almirante)
2. RBAC: tem `write` nessa VM? não → nega
3. lê `before` (GET assistant da VM)
4. **test-gate**: aplica num agente-sombra/draft e roda smoke + regressão (cenários). Falhou → recusa + diff
5. aplica `after` (PATCH assistant da VM)
6. grava `ia_change_log` (before/after/test_result/quem/quando)
7. WebSocket atualiza o CommandCenter

**Rollback**
1. user chama `rollback(change_id)` (precisa `write` na VM)
2. lê `before` do `ia_change_log`
3. reaplica `before` via API; grava nova entrada com `reverts_change_id`

---

## 9. Fases de implementação

| Fase | Entrega | Depende |
|---|---|---|
| **F1 — Identidade + RBAC** | `almirante_users`, `vm_targets`, `vm_access`, login de usuário | — |
| **F2 — Leitura via MCP** | `/mcp` Go (Streamable HTTP) + tools de leitura (`list_vms/get_agent/list_tools/history`) | F1 |
| **F3 — Escrita + audit** | `update_agent_prompt`, `set_tool_arming`, `set_credential` (com `test_connection`), `ia_change_log` | F2 |
| **F4 — Test-gate de IA** | smoke + regressão com `captain_scenarios` + LLM-juiz | F3 |
| **F5 — Rollback + UI** | `rollback` + timeline no CommandCenter (com botão reverter) | F3 |
| **F6 — (opcional)** | `update_agent_prompt` também no `chatspx-tools` Node (modo dev) | — |

> Fase 2 (acesso remoto p/ gente não-técnica) pode ganhar **VPN / Cloudflare Access** na frente do `/mcp`
> em vez de OAuth pleno — mais simples e suficiente p/ time interno (ver pesquisa no histórico).

---

## 10. Segurança / pendências

- 🔴 **Rotacionar** a chave SSH RSA privada + senha admin **hardcoded** em `deployment/panel/server.js`
  (versionado no repo `chatspx`, painel hoje **desativado**, mas a chave está no histórico do git).
- Secrets **nunca** em claro no `ia_change_log` (mascarar) nem no front.
- `admin_token_ref` por VM guardado como secret do Almirante.
- RBAC **deny-by-default**; auditoria estruturada (JSON) p/ futura ingestão em SIEM.

## 11. O que NÃO muda

- Tools em **dev** (VM do dev) seguem livres via `chatspx-tools`.
- **Built-in tools** continuam em código (replicam por deploy).
- Sem criptografia no ChatSPX (decisão do Walisson). Para credencial, optamos por **testar antes** em vez de versionar secret.

---

## 12. Próximos passos

1. Confirmar este plano com o Walisson.
2. **@devops** valida acesso ao repo `noc-spxia` e ao ambiente (Almirante = **produção/.229** → cuidado).
3. Iniciar **F1** (identidade + RBAC) no `noc-spxia`.
