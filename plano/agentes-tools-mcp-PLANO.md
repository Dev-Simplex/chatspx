# Plano — Agentes IA: Tools globais, Integrações editáveis, MCP real, Editabilidade total

> Status: PLANEJAMENTO (nada implementado). Base: investigação multiagente read-only (2026-06-29).
> Decisões travadas (Walisson): Tools numa **rota global `/agents/tools`**; credenciais num **novo model `account_integrations`**; **MCP real funcional** (CRUD de tools sem dev mexer no código); banco como fonte de verdade do que é editável (propagação vira dado, não código).

---

## 0. Diagnóstico (o que existe hoje)

**Dois sistemas de tools + um decorativo:**
- **Built-in** = `config/agents/tools.yml` (metadados) + classes Ruby em `enterprise/lib/captain/tools/*Tool` (lógica). Carregadas por `Concerns::CaptainToolsHelpers#load_agent_tools` (memoizado → exige restart). Propagam só por deploy.
- **Custom HTTP** = tabela `captain_custom_tools` (DB, **por conta**): `endpoint_url`, `http_method` (GET/POST), `auth_type` (none/bearer/basic/api_key) + `auth_config` jsonb, `request_template`/`response_template` (Liquid), `param_schema` jsonb, `enabled`, `copilot_only`. Motor: `enterprise/lib/captain/tools/http_tool.rb` (com guard SSRF). CRUD pronto: `custom_tools_controller` + store/api front + form completo em `components-next/captain/pageComponents/customTool/`.
- **MCP** = hoje só um snippet estático de clipboard no `ToolsTab.vue` (aponta pra um pacote inexistente). **Zero backend.**

**Tools de integração (negócio Tozi):** `buscar_imovel`, `enviar_fotos_imovel`, `enviar_localizacao_imovel`, `enviar_localizacao` (escritório hardcoded), `buscar_lugar` (Google Places). Credenciais multi-tenant em `account.custom_attributes` (`vista_api_key`, `vista_base_url`, `google_maps_key`) com fallback ENV.

**Bugs/gaps achados:**
1. Autofill: chave de API é `type=password` órfão → Chrome despeja e-mail na busca da sidebar.
2. `ToolsTab.vue` mostra catálogo **hardcoded** (`BUILTIN_META`), **não usa** o endpoint real `/captain/assistants/tools` (store `captainTools` órfão).
3. Form de criar custom tool no `ToolsTab.vue` **quebrado** (manda `name/url/method`; API quer `title/endpoint_url/http_method`) → 422.
4. `config['tools']` (armar tool por agente) **não está no strong-params** do `assistants_controller` → só via console/cenários.
5. `enviar_fotos_imovel`/`enviar_localizacao_imovel` são **ENV-only (Tozi)** — não multi-tenant.
6. Credenciais Vista/Google **não têm tela nem API** (só Rails console; `accounts_controller` só permite industry/company_size/timezone).
7. `tools.yml` tem `transferir_para_agente` duplicado.
8. Chave Vista real exposta em `.env:309`.

---

## 1. Fixes imediatos (bugs) — baixo risco

**F1. Autofill (defesa em 2 camadas):**
- `AiField.vue` (secret): `autocomplete="new-password"` + `name="api-key"` + `data-lpignore="true"` + `data-1p-ignore` + `data-form-type="other"`.
- `AiSearch.vue`: `readonly` inicial, remover no `@focus`/`@mousedown` (reaplicar no `@blur`).

**F2. ToolsTab usar dados reais + form correto:**
- Consumir `GET /captain/assistants/tools` (store `captainTools` já existe) em vez do `BUILTIN_META` hardcoded → catálogo passa a refletir o backend (tools.yml ∪ custom da conta).
- Trocar o form inline quebrado pelo form pronto `customTool/CustomToolForm.vue` (`title/endpoint_url/http_method/param_schema/auth_config`); method só GET/POST; auth none/bearer/basic/api_key.
- Adicionar editar/excluir/toggle (store já tem `update`/`delete`).

**F3. tools.yml:** remover `transferir_para_agente` duplicado.

---

## 2. Fase A — Mover Tools/Integrações para rota global `/agents/tools`

Custom tools são **globais por conta** → não fazem sentido por-agente.

- `agents.routes.js`: remover child `tools` de `agentDetailChildren`; criar rota irmã `{ path: 'tools', name: 'agents_tools', component: ToolsView }` (ao lado de dashboard/settings).
- `AgentDetailView.vue`: remover a aba "Ferramentas" do array `tabs`.
- Criar `pages/ToolsView.vue` (sem `assistantId`): seções **Ferramentas** (catálogo + custom CRUD) e **Integrações** (cards Vista/Google) e **MCP** (Fase D).
- `AgentsPageView.vue`: item "Ferramentas" no rodapé da sidebar (ao lado de "Conexão") → `agents_tools`.
- `AgentsDashboard.vue`: card/atalho "Ferramentas e Integrações".
- `Sidebar.vue`: incluir `agents_tools` no `activeOn`.
- i18n pt_BR/en (migrar strings hardcoded do ToolsTab pra chaves).

> "Visão Geral / Fluxo" continuam por-agente (são do agente). Só **Tools** sai.

---

## 3. Fase B — Editabilidade total ("desmistificar")

**Front (SettingsTab):** expor TODO o `config` do agente (backend já permite): `product_name`, `temperature`, `welcome_message`, `handoff_message`, `resolution_message`, `instructions`, `feature_faq/memory/citation/contact_attributes`.

**Armar tools por agente (UI):** checkboxes do catálogo real por agente, salvando `config['tools']`.
- Backend: ampliar strong-params do `assistants_controller` pra aceitar `config[:tools] => []` (e `model`, `knowledge_mode`, `contextual_chunks` se quiser editar pela UI).

**Custom tools:** editor de `param_schema` (name/type/description/required), `request_template`/`response_template`, `copilot_only`, toggle enabled (ajustar `custom_tools_controller#index` pra listar não-enabled).

**Polimento:** trocar `window.confirm` dos Scenarios por modal do kit.

---

## 4. Fase C — Integrações editáveis (novo model `account_integrations`)

**Migration/model `account_integrations`:**
```
account_id (FK), provider (string: 'vista' | 'google'), enabled (bool),
settings (jsonb, criptografado: vista_api_key, vista_base_url, google_maps_key,
          office_lat, office_lng, office_name, site_domain),
timestamps. Índice único (account_id, provider).
```
- Criptografar segredos (ActiveRecord encryption) — não deixar chave em claro.

**Controller + rota:** `Api::V1::Accounts::IntegrationsController` (ou namespace captain) CRUD por provider + ação `test_connection` (smoke `GET /imoveis/listar?key=` no Vista).

**Refactor das tools (multi-tenant real):**
- Extrair helpers `vista_api_key/base_url/account_setting` de `buscar_imovel_tool.rb` pra um concern `VistaCredentials` (ou `BasePublicTool`) lendo de `account_integrations` (fallback `custom_attributes` → ENV durante transição).
- Corrigir `enviar_fotos_imovel`/`enviar_localizacao_imovel` (hoje ENV-only) pra usar a conta.
- Parametrizar `enviar_localizacao` (coords/nome do escritório) e `site_domain` (hoje `toziimoveis.com.br` hardcoded em `buscar_imovel`).

**UI "Conectar com Vista Loft" / Google** (em `/agents/tools` → Integrações):
- Form: api_key (secret), base_url, google_maps_key (secret), dados do escritório, toggle enabled, botão **Testar conexão**.
- Migração de dados: copiar `custom_attributes` atuais (incl. Tozi do `.env`) pro novo model; depois remover a chave do `.env`.

---

## 5. Fase D — MCP REAL e funcional (CRUD de tools sem dev)

**Objetivo:** devs (ou qualquer pessoa com token) criam/editam/apagam tools via MCP (Claude Desktop, Cursor, ou um runner) sem acessar o código-fonte.

**Arquitetura escolhida — MCP server fino sobre a API REST existente** (não precisa Rails virar servidor MCP):
- Pacote Node/TS `mcp-server-chatspx-tools` (stdio + opção HTTP) que autentica na API do ChatSPX com **`api_access_token`** (escopo por conta) e expõe ferramentas MCP:
  - `list_tools` → `GET /captain/assistants/tools` (built-in + custom).
  - `create_tool` → `POST /captain/custom_tools` (title, endpoint_url, http_method, auth_type/auth_config, param_schema, templates).
  - `update_tool` / `delete_tool` → `PATCH/DELETE /captain/custom_tools/:id`.
  - `test_tool` → executa um dry-run (endpoint novo opcional `POST /captain/custom_tools/:id/test`).
  - (futuro) `arm_tool_on_agent` → seta `config['tools']` do assistant.
- Config via env: `CHATSPX_API_URL`, `CHATSPX_API_TOKEN`, `CHATSPX_ACCOUNT_ID`.
- A UI (`/agents/tools` → MCP) deixa de ser snippet morto: gera o JSON real apontando pro pacote publicado + token do usuário (com instruções Claude Desktop/Cursor).

**Backend de apoio (pequeno):**
- Garantir que `custom_tools_controller` cobre todo o param_schema/auth (já cobre) e, se quisermos `test`, adicionar a ação.
- (Opcional) um endpoint de **execução server-side** pra `test_tool` reusar o `HttpTool` com guard SSRF.

**Resultado:** criar/editar/apagar tool = chamada MCP → grava em `captain_custom_tools` (DB). Zero deploy, zero código-fonte. As tools built-in de **lógica** continuam em código (não dá pra editar lógica Ruby por MCP), mas **toda tool HTTP nova/edição** é via MCP/UI.

---

## 6. Propagação entre VMs (resposta ao "matar o banco")

Não dá pra matar o banco se queremos edição sem dev. Modelo:
- **Built-in (lógica)** → código/git → deploy uniforme nas VMs (já é assim).
- **Custom + integrações** → banco. Propagação como **dado**, 3 opções (escolher depois):
  - (a) **Export/Import**: comando rake/endpoint que dumpa `captain_custom_tools` + `account_integrations` de uma conta e importa noutra VM (versionável em git como seed se quiser).
  - (b) **Banco compartilhado/replicado** entre VMs (mais infra).
  - (c) **Sync via MCP/API**: o mesmo MCP aponta pra várias VMs e replica as tools (simples, sob demanda).
- Recomendado começar com (a) export/import (seed por conta) — dá versionamento sem matar a edição em runtime.

---

## 7. Segurança
- Remover `TOZI_VISTA_API_KEY` do `.env` versionado (chave real exposta) após migrar pro `account_integrations` criptografado.
- Criptografar `account_integrations.settings` (ActiveRecord encryption).
- Manter guard SSRF do `HttpTool` (já existe) também no `test_tool`.
- Token do MCP = `api_access_token` por usuário/conta (revogável).

---

## 8. Ordem sugerida / esforço
1. **F1–F3 (bugs)** — pequeno, alto impacto (autofill, catálogo real, form de tool).
2. **Fase A** (mover Tools pra `/agents/tools`) — médio.
3. **Fase B** (editabilidade `config` + armar tools) — médio (front + 1 ajuste de permit).
4. **Fase C** (account_integrations + Vista/Google editável + multi-tenant) — maior (migration + model + controller + refactor tools + UI + migração de dados).
5. **Fase D** (MCP real) — médio/grande (pacote MCP novo + UI + opcional test endpoint).
6. **Propagação** (export/import) — pequeno depois de C/D.

Tudo working-tree → build hml → validar Playwright light/dark, sem commit/push até "TUDO pronto".

---

# 9. REVISÃO CRÍTICA vs. melhores práticas (pesquisa 2025-2026)

Fontes: spec/roadmap MCP (modelcontextprotocol.io), Google Cloud "Secure agent interactions with MCP", Stack Overflow Blog (auth MCP), arxiv 2603.22489 (tool poisoning), CVE-2025-54136, Rails Guides (Active Record Encryption).

## ✅ Alinhado (manter)
- **`account_integrations` + Active Record Encryption (`encrypts`)** + tirar chave do `.env`: bate com Rails Guides (criptografia na camada de app, chave por tenant, nada commitado).
- **Custom tools = HTTP parametrizado (não código arbitrário) + guard SSRF**: bate com "action-selector / funções pré-definidas seguras" (NÃO um `execute` genérico).
- **DB pra config editável + lógica complexa em código** (híbrido): razoável.
- **Tools account-scoped**: bate com isolamento por tenant.

## ⚠️ Desalinhado / risco — PRECISA mudar (o ponto do MCP)
1. **"Criar/editar tools dinamicamente" é o caminho de MAIOR risco.** Fontes são unânimes: *"o agente NÃO pode registrar tools dinamicamente nem mudar permissões"* (Google Cloud); *"dynamic registration is the high-risk path"*; **tool poisoning (CVE-2025-54136)** = instruções maliciosas escondidas na **descrição/metadata** da tool (injection indireta no contexto do agente). 
   - **Distinção que salva o pedido:** o **AGENTE (LLM em runtime) nunca** cria/edita tool. Quem cria é **admin humano em config-time** (via UI ou MCP com token de admin). É preciso **separar 100%** o "MCP de GESTÃO de tools" do "toolset de runtime do agente" — senão um agente com o token poderia se auto-modificar (rug-pull).
   - **Governança obrigatória a adicionar à Fase D:** (a) **admin-only** (não usuário comum); (b) tool nasce **desabilitada** + **revisão/aprovação humana** antes de ser armada num agente; (c) **audit log** de todo CRUD de tool/credencial; (d) **integridade**: hash/pin da definição pra detectar edição silenciosa (anti rug-pull); (e) **sanitização/validação da `description`** (vetor de injection); (f) **allowlist de domínios** no `endpoint_url` (além do SSRF); (g) least-privilege: default GET/read-only.
2. **Auth do MCP:** meu plano usou **token estático** — ok pra **MCP local (stdio)** rodando no Claude Desktop/Cursor de um admin, mas o **padrão 2026 pra MCP remoto** é **OAuth 2.1 (Authorization Code + PKCE) + Streamable HTTP** (não o SSE legado), servidor como **Resource Server** com `.well-known`, **escopos por tool (read vs write)** e tokens audience-restricted (RFC 8707). 
   - **Revisão:** começar **local stdio + token** (uso interno/admin), com **caminho de upgrade documentado** pra **remoto + OAuth 2.1 + Streamable HTTP + escopos por tool** se virar multi-cliente/SaaS.
3. **Prompt injection / dados não confiáveis:** tratar input de usuário e **dados externos (retorno do Vista/Google)** como não confiáveis (eles entram no contexto). Avaliar **padrão dual-LLM/guardrail** (uma LLM de screening) + manter action-selector (tools fixas). 
4. **Isolamento multi-tenant reforçado:** a identidade/escopo da conta deve ser fixada **fora do controle do LLM** (já fazemos via `@assistant.account` + headers `X-Chatwoot-*`); garantir que parâmetros controlados pelo modelo não permitam cross-account; endpoint allowlist por conta.
5. **Observabilidade:** já há `captain_assistant_logs` pra execução; **falta audit log dedicado** do CRUD de tools e de credenciais (quem criou/editou/armou, quando).

## Deltas concretos no plano
- **Fase D (MCP):** virou "MCP de **gestão** admin-gated + governado" (não "registro dinâmico aberto"). Add: aprovação/disabled-by-default, audit, hash de integridade, allowlist de domínio, sanitização de description, escopos read/write. Auth: stdio+token agora → OAuth 2.1/Streamable HTTP depois.
- **Fase C:** confirmar `encrypts` nos segredos + audit log + "testar conexão".
- **Cross-cutting novo (Fase E — Segurança/Governança):** integridade de definição de tool (hash), audit log (CRUD tools+credenciais), allowlist de domínios, opção de guardrail-LLM, princípio explícito "agente nunca se auto-registra".

## Conclusão
O núcleo (integrações com `account_integrations`+criptografia, custom tools HTTP com SSRF, DB+código híbrido) está alinhado. O **MCP precisa nascer governado** (admin-only, aprovação, audit, integridade, allowlist) e com auth evoluível (stdio→OAuth2.1/Streamable HTTP) — senão a feature "tools sem dev" abre a porta exata do tool-poisoning. Com a governança, o pedido é viável e seguro.

---

# 10. PLANO END-TO-END PARALELO + GATE DE VALIDAÇÃO

## Princípio de execução
- **Paralelismo por dono de arquivo** (lanes não se cruzam → multiagentes simultâneos sem conflito).
- **Gate de validação OBRIGATÓRIO em CADA lane e no final**: build (heap 8GB, conferir manifest) → restart → **Playwright em LIGHT + DARK** → **clicar TODAS as interações** da tela → 0 erros de console, 0 i18n leak, 0 import legado, comportamento correto. Backend: `rails runner` comparando endpoint vs recontagem independente (como foi feito no /stats).
- Working tree only; sem commit/push até "TUDO pronto".

## Grafo de dependência
```
Lane 0 (backend enablers) ─┬─► Lane C (editabilidade front)
                           ├─► Lane D (UI integrações)
                           └─► Lane E (MCP governado)
Lane A (bugs)  ──────────────► (independente, começa já)
Lane B (rota global tools) ──► depende de A/F2
Lane F (segurança/governança) ─► cross-cutting (entra junto de E)
```

## Lanes (paralelizáveis)

### Lane 0 — Backend enablers (libera o front)  [agente backend]
Arquivos: `enterprise/app/controllers/.../captain/assistants_controller.rb` (permit `config: full + tools:[]`), `.../custom_tools_controller.rb` (index lista não-enabled p/ toggle; ação `test`), **novo** `account_integrations` (migration+model+`encrypts`+controller+rota+`test_connection`), refactor tools Vista multi-tenant (`buscar_imovel`/`enviar_fotos`/`enviar_localizacao*`/`buscar_lugar` → concern `VistaCredentials` lendo de account_integrations), `config/agents/tools.yml` (dedup), audit log (CRUD tools/credenciais).
Validação: `rails runner` (CRUD integrações + custom_tools + permit) + specs.

### Lane A — Bugs F1–F3  [agente front-1]
Arquivos: `agents-ui/AiField.vue` (autocomplete new-password + name + data-lpignore), `agents-ui/AiSearch.vue` (readonly-até-focar), `tabs/ToolsTab.vue` (usar endpoint real + form correto + edit/delete/toggle).
Validação Playwright: abrir /agents/settings (busca NÃO preenche e-mail), criar/editar/excluir custom tool (funciona), light+dark.

### Lane B — Tools/Integrações → rota global `/agents/tools`  [agente front-2]
Arquivos: `agents.routes.js` (remove child tools, add `agents_tools`), `AgentDetailView.vue` (remove aba), **novo** `pages/ToolsView.vue` (Ferramentas + Integrações + MCP), `AgentsPageView.vue` (nav), `AgentsDashboard.vue` (atalho), `Sidebar.vue` (activeOn), i18n.
Validação: navegar pra /agents/tools por sidebar e landing; aba some do agente; light+dark + cliques.

### Lane C — Editabilidade total  [agente front-3]  (após Lane 0)
Arquivos: `tabs/SettingsTab.vue` (todo o config editável), UI de **armar tools por agente** (checkbox lendo /tools, salva config['tools']), editor `param_schema` nas custom tools.
Validação: editar cada campo → salvar → recarregar → persistiu; light+dark + todos os cliques.

### Lane D — UI Integrações (Vista/Google)  [agente front-4]  (após Lane 0)
Arquivos: seção Integrações no `ToolsView.vue` + form (api_key secret, base_url, google_key, escritório, enabled) + **Testar conexão** + store/api.
Validação: salvar credencial → testar conexão (ok/erro) → tool Vista usa a conta; light+dark + cliques.

### Lane E — MCP real GOVERNADO  [agente mcp]  (após Lane 0)
Pacote Node/TS `mcp-server-chatspx-tools` (stdio agora; upgrade path OAuth2.1/Streamable HTTP): `list/create/update/delete/test_tool`, **admin-only**, tool nasce **disabled**, **audit**, **hash de integridade**, **allowlist de domínio**, sanitização de description, escopos read/write. UI MCP gera JSON real.
Validação: criar tool via MCP → aparece disabled → aprovar → arma no agente; testes do pacote.

### Lane F — Segurança/Governança  [junto da Lane E/0]
Aprovação humana (disabled→enabled), audit log (quem/quando), integridade (hash da definição), allowlist de domínios, opção guardrail-LLM. Princípio: **agente nunca se auto-registra**.

## Gate final (integrado)
Playwright varre TODAS as telas de IA (dashboard, /agents/tools, conexão, e as 8 abas do agente) em **light+dark**, clicando **todas** as interações (criar/editar/excluir tool, conectar+testar integração, armar tool, editar+salvar config, cenários, knowledge, inboxes) → relatório 0 erros. Build fresco confirmado (manifest mtime).

---

# 11. EXECUÇÃO CONCLUÍDA (2026-06-29) — todas as fases aplicadas e validadas

- **Fase 1** (bugs + Tools global): autofill corrigido (AiField new-password + AiSearch readonly-até-focar); Ferramentas → rota global `/agents/tools` com catálogo REAL (endpoint /tools) + form de custom tool correto no kit. ✓ Playwright light+dark, 0 erros.
- **Fase 2** (backend): strong-params (config completo + tools[]); custom_tools index lista todas + ação `test`; **account_integrations** (model+migration+controller, segredos mascarados, `encrypts` quando AR keys no ENV). Migration aplicada no hml. ✓ verificado via HTTP.
- **Fase 3** (editabilidade + integrações): SettingsTab 100% editável + armar tools por toggle; UI Integrações Vista/Google com form + Testar conexão (corrigido 406 → header Accept). ✓ Playwright light+dark.
- **Fase 4** (MCP + Vista): pacote MCP `mcp/chatspx-tools/` (stdio, 6 tools, governado: cria desabilitada, ativação só na UI, audit) — compila + smoke-test OK. Refactor Vista/Google → concern `IntegrationCredentials` lendo `account_integrations`→custom_attributes→ENV (Tozi preservada); Zeitwerk collapse no application.rb. ✓ boot 200, Clara lê chave do account_integrations.
- **Gate final**: todas as telas (dashboard, /agents/tools, conexão, 8 abas) × light+dark + cliques → **0 console errors, 0 i18n leak, 0 dark mismatch**.

Pendência conhecida (não-bloqueante): setar as 3 ENV `ACTIVE_RECORD_ENCRYPTION_*` no hml/produção pra criptografar os segredos de integração em repouso (hoje plaintext JSON no hml). Tudo working tree — sem commit/push.
