# Auditoria Técnica — Chat SPX (fork Chatwoot)

> **Data:** 2026-06-04 · **Branch auditada:** `paulao` · **HEAD:** `71629abe1` · **Versão:** 4.12.1 (base Chatwoot 4.x)
> **Tipo:** análise **estática**, read-only. Nenhum código foi modificado, nenhum segredo exposto.
> **Autor:** auditoria assistida (4 frentes paralelas + leitura dirigida dos arquivos de risco).
> **Produto:** SPX — multi-atendimento + IA da SimplexIA. Cliente-âncora: **Tozi Imóveis** (Account 6, AWS).

---

## Sumário executivo

O SPX é um fork maduro e **substancialmente customizado** do Chatwoot, com ~526 commits à frente do upstream. O delta proprietário concentra-se em quatro subsistemas: **(a)** redesign frontend do módulo de IA ("Agentes IA"/Copilot, ~6,4k linhas), **(b)** camada backend de IA sobre o Captain Enterprise (RAG + ~44 tools + `behavior` JSONB + 7 behavior services), **(c)** Kanban de pré-venda + cadência de follow-up (`Spx::Tozi::*`), e **(d)** integração Meta Lead Ads e o **motor de disparo em massa de HSM**.

O produto **funciona em produção** e entrega valor real (disparos de milhares de mensagens, IA atendendo, funil automatizado). Porém, do ponto de vista de **engenharia de produto vendável**, há três riscos estruturais que se reforçam:

| # | Risco estrutural | Severidade | Resumo |
|---|---|---|---|
| R1 | **Cobertura de testes ZERO no código custom** | 🔴 Crítico | Os ~25 componentes proprietários (disparo HSM, funil, cadência, Meta Lead Ads, tools, behavior services) não têm **nenhum** spec. Os 705 specs do repo são herança upstream e protegem só o código não-modificado. |
| R2 | **Migration-landmine destrutiva** `20260330120000` | 🔴 Crítico | Faz `DELETE` em cascata de `conversations`→`messages`/`scheduled_messages`/`funnel_items`. Sem nenhuma proteção em código (`disable_ddl_transaction!` remove até o rollback). Só disciplina humana evita o desastre. `db/schema.rb` versionado **diverge** do banco de produção. |
| R3 | **Controle operacional via console SSH** | 🟠 Alto | Disparo, pausa, dedup, troca de template, ativação da IA, kill-switch de auto-resolve — tudo via `rails runner`/rake manual na AWS. Nenhum painel, nenhuma trilha de auditoria, nenhum guard-rail. Acoplamento forte a `INBOX_ID=91` e IDs de corretor hardcoded. |

Além disso, o código é **mono-tenant na prática**: apesar do isolamento lógico do Chatwoot (account_id em tudo), a camada custom é **hardcoded para a Tozi** (inbox 91, corretores 125–131, ENV `TOZI_*`, funil "Pré-Venda Tozi", chave LLM global compartilhada entre contas). Vender para um 2º cliente hoje exige **edição de código**, não configuração.

**Veredito:** SPX é um **MVP de produto operando como serviço gerenciado para 1 cliente**, não ainda um SaaS multi-tenant self-service. O caminho para o 2º cliente é claro e está detalhado na §5.

---

## Metodologia e escopo

- **Lido integralmente:** `CLAUDE.md`, `AGENTS.md`, `.claude/STATE.md`, manual de marca (`/brand/manual-marca-spx.md`), e os arquivos custom de maior risco (disparo job, cadência, funil, listener, webhook Meta, signature verifier, campaign + stats, rake `spx:tozi`, tool de imóvel, async dispatcher).
- **4 frentes paralelas de exploração:** (1) cobertura de testes do custom; (2) delta frontend; (3) camada de comportamento da IA; (4) migrations + delta git.
- **Não executado:** suíte de testes, migrations, build (auditoria estática). Onde afirmo "passa/falha" sem rodar, está sinalizado.
- **Fora de escopo:** segurança do servidor AWS, configuração de DNS/proxy, e o código upstream do Chatwoot não-modificado (assumido correto).

---

## 1. Stack e Arquitetura

### 1.1 Stack técnica

| Camada | Tecnologia | Versão |
|---|---|---|
| Linguagem backend | Ruby | **3.4.4** (`.ruby-version`) |
| Framework | Rails | **~> 7.1** |
| Fila/jobs | Sidekiq | **>= 7.3.1** (Redis) |
| Banco | PostgreSQL + **pgvector** (0.8.2 em prod) | — |
| Frontend | Vue 3 (Composition API, `<script setup>`) + Vite | — |
| Styling | Tailwind CSS (Tailwind-only, sem CSS custom) | — |
| Runner de IA | gem `agents` (Captain v2) + OpenAI/Anthropic | — |
| WhatsApp | WAHA (não-oficial, PAULAO/dev) **e** Meta WhatsApp Cloud API (oficial, prod Tozi) | — |
| Versão do produto | `@chatwoot/chatwoot` | **4.12.1** |

**Total de migrations:** 165 (≈47 custom com timestamp 2026). **Specs:** 705 arquivos (524 OSS + 181 Enterprise) — todos upstream.

### 1.2 Topografia (OSS + Enterprise overlay + camada SPX)

O Chatwoot tem três camadas, e o SPX adiciona a sua:

```
app/, lib/            → OSS (Chatwoot aberto)
enterprise/           → Enterprise overlay (Captain, copilot, captain tools)
app/{services,jobs,listeners}/spx/   → camada proprietária SPX (Tozi)
app/services/meta/lead_ads/          → integração Meta Lead Ads (SPX)
enterprise/lib/captain/tools/*       → tools custom de IA (imóvel, follow-up, lead)
enterprise/app/services/captain/behavior/  → 7 behavior services (SPX)
```

### 1.3 Arquitetura do módulo de IA (Captain v2 "Clara")

O fluxo de uma mensagem recebida até a resposta da IA (reconstituído por leitura):

```
message_created (callback Wisper)
  └─ Enterprise::MessageTemplates::HookExecutionService#trigger_templates   ← orquestrador
       ├─ should_process_captain_response? (pending|open + incoming + assistant + !human_takeover)
       ├─ inbox.captain_active? == false → perform_handoff
       └─ process_captain_behavior(assistant)
            ├─ private? → CopilotTriggerService            (#copilot, LLM síncrona)
            ├─ RouterService#should_respond?              (whitelist/skip_labels/grupos)
            ├─ BusinessHoursChecker (gate fora-do-horário)
            └─ schedule_or_debounce
                 ├─ mark_customer_message_read (tique azul, best-effort)
                 ├─ debounce>0 → DebounceService → DebouncedResponseJob → ResponseBuilderJob
                 └─ debounce=0 → ResponseBuilderJob.perform_later

ResponseBuilderJob
  ├─ captain_can_respond? (re-checa status, query uncached)
  ├─ AgentRunnerService#generate_response → Agents::Runner (gem agents, max_turns:100)
  └─ process_response
       ├─ handoff → bot_handoff! (degrada gracioso)
       ├─ DedupService (anti-duplicata, Redis SET NX)
       └─ HumanizerService#split → loop(typing indicator + sleep + send) ← quebra estilo WhatsApp
```

A configuração de comportamento vive num **JSONB livre `behavior`** no `Captain::Assistant` (`router`, `debounce_seconds`, `humanizer`, `dedup`, `business_hours`, `copilot_trigger`, `media_pipeline`). A filosofia é **code-first**: o Claude Code configura via API e o frontend é um *viewer*.

### 1.4 Camada de automação Tozi (Kanban + cadência)

- **Funil "Pré-Venda Tozi"** (7 estágios: `novo_lead`→`qualificado`/`frio`) sobre os models nativos `Funnel`/`FunnelStage`/`FunnelItem`.
- **`Spx::Tozi::FunnelAutomationListener`** (state machine) registrado no `AsyncDispatcher#listeners` — move cards por evento.
- **`Spx::Tozi::FunnelPlacementService`** — coloca/move conversa no estágio.
- **`Spx::Tozi::ReactivationCadenceService`** — agenda HSM (1d/3d/7d) fora da janela 24h via `ScheduledMessage.template_params`.
- **`Spx::Tozi::DisparoLeadJob`** + rake `spx:tozi:disparo` — motor de disparo em massa.

---

## 2. Delta custom-vs-upstream

### 2.1 Ordem de grandeza

- **Base upstream:** `origin/master` = Chatwoot 4.x. A branch `paulao` está **~526 commits à frente** (≈430 tocando código de produção em `app/lib/db/config/enterprise`).
- `git diff --stat origin/master...paulao` (escopo source) ≈ **3.577 arquivos, +199.135 / −56.349 linhas** — mas esse número infla com i18n da comunidade e assets compilados. O sinal de **customização proprietária real** está concentrado nos namespaces abaixo, contados com precisão:

### 2.2 Inventário do código proprietário (preciso)

| Subsistema custom | Arquivos | Linhas (aprox.) | Natureza |
|---|---|---|---|
| **Frontend "Agentes IA" + Copilot** | ~50 | **~6.359** | NOVO (maior bloco) |
| **Captain backend** (RAG `document_chunks` + ~31 copilot tools + 7 behavior services + 6 real-estate/handoff tools + `behavior` JSONB + logs) | ~50 | centenas espalhadas | NOVO/overlay |
| **Kanban pré-venda (frontend)** | 3 | **~979** | NOVO |
| **`lib/tasks/spx_tozi.rake`** | 1 | **223** | NOVO |
| **`Spx::Tozi::*`** (disparo, funil, cadência, listener) | 4 | **316** | NOVO |
| **Meta Lead Ads** (controller + 5 services + job) | 7 | **~258** | NOVO |
| Frontend: campanhas WhatsApp, respostas-rápidas c/ anexo, view "Não lidas", branding | ~30 | milhares | MODIFICADO |
| **~47 migrations custom (2026)** | 47 | — | NOVO |

**Frontend custom total (estimativa de teto):** ~22k linhas, ~110 componentes `.vue` + ~36 arquivos JS de store/composables. Os 3 maiores: **(1)** Agentes IA, **(2)** Conversation views (cards/unread/unanswered), **(3)** Copilot.

### 2.3 Leitura qualitativa do delta

O fork **não é um reskin** — é uma extensão de produto. A SimplexIA construiu, sobre o Chatwoot:
1. Um **módulo de IA próprio** (Captain v2 repaginado + behavior layer + RAG + tools de domínio imobiliário).
2. Um **CRM de pré-venda** (Kanban + cadência + funil event-driven).
3. Um **motor de marketing outbound** (disparo em massa de HSM com pacing, round-robin e rotação de template).
4. Uma **ponte de aquisição** (Meta Lead Ads → conversa → IA).

Isso é valor de produto real. O problema não é *o quê* foi construído — é *como sustentar e replicar* (testes, multi-tenant, ops), tratado nas §3–§5.

---

## 3. Gaps e Riscos

### 3.1 🔴 R1 — Cobertura de testes ZERO no código custom (CONFIRMADO)

A hipótese da memória está **confirmada com evidência exaustiva**: **zero ocorrências** de `spx`, `tozi`, `meta_lead_ads`, `DisparoLead`, `FunnelPlacement`, `FunnelAutomation`, `ReactivationCadence`, `buscar_imovel`, `salvar_info_lead`, `programar_followup`, `TemplateManagementService`, `send_typing_indicator`, `campaign_stats` em **705 arquivos de spec**. Não existem os diretórios `spec/spx/`, `spec/services/spx/`, nem `spec/enterprise/**/behavior/`.

| Componente custom | Spec? |
|---|---|
| `Spx::Tozi::DisparoLeadJob` (blaster de **milhares de HSM**) | ❌ |
| `Spx::Tozi::FunnelPlacementService` / `ReactivationCadenceService` | ❌ |
| `Spx::Tozi::FunnelAutomationListener` (roda p/ toda conta) | ❌ |
| Meta Lead Ads: controller + 5 services + job | ❌ |
| Captain tools: buscar_imovel, enviar_fotos_imovel, programar_followup, salvar_info_lead | ❌ |
| 7 behavior services (router, debounce, humanizer, dedup, business_hours, media_pipeline, copilot_trigger) | ❌ |
| `AgentRunnerService` (fix custom do handoff vazio) | ⚠️ spec upstream existe, **não cobre** a linha do fork |
| `Whatsapp::TemplateManagementService` + typing indicator | ❌ |
| `campaign_stats` + `CampaignsController#stats` | ❌ |
| `ScheduledMessages` com `template_params` (jsonb) | ❌ |
| Anexo em respostas rápidas (canned response) | ❌ |

**Por que é crítico:** o `DisparoLeadJob` envia HSM **pagos** para milhares de leads reais; um bug silencioso (e ele tem `rescue StandardError` que engole falhas para o log — ver §3.4) custa dinheiro e reputação do número WABA. O incidente real documentado no STATE ("Oi Adriana!" cortado por falta de entrada no `PREVIEWS`) é exatamente o tipo de regressão que **um único spec teria pego**. O `campaign_stats`, o normalizador de telefone BR e o `template_params` são lógica determinística — barata de testar, cara de quebrar em produção.

**Mitigação recomendada (ROI máximo, esforço baixo):** começar por **3 specs de alto valor** — (1) `DisparoLeadJob` (normalização de telefone + montagem de `template_params` + idempotência), (2) `Meta::LeadAds::SignatureVerifier`/`FetchLeadService` (segurança + parsing), (3) `ReactivationCadenceService` (idempotência + no-op fora de Cloud API). Esses três cobrem o caminho do dinheiro e da aquisição. Depois, behavior services (puros, fáceis).

### 3.2 🔴 R2 — A migration-landmine destrutiva `20260330120000_add_foreign_key_constraints`

**O que faz:** adiciona ~26 foreign keys a tabelas core que nasceram sem FK. Antes de criar cada FK, executa um **`DELETE` de órfãos**:

```sql
-- nullable: false (apaga TODA linha sem pai)
DELETE FROM <from> WHERE NOT EXISTS (SELECT 1 FROM <to> WHERE <to>.id = <from>.<col>)
```

A lista é ordenada **de propósito** para que os FKs `on_delete: :cascade` em filhos de `conversations` existam **antes** de limpar `conversations`. Resultado: apagar uma conversation órfã **cascateia** para `messages`, `mentions`, `scheduled_messages`, `funnel_items`, `csat/nps`, `reporting_events`. `messages` e `conversations` são as duas maiores tabelas do produto.

**Por que não há rede de proteção:**
- `disable_ddl_transaction!` está presente — o que **piora**: os `DELETE` rodam **fora de transação**, então **não há rollback automático** se falhar no meio.
- **Não há** guard de ambiente, dry-run, contagem-de-linhas ("aborte se for apagar > N"), nem flag de confirmação. O `safety_execute` só **loga** o SQL — não previne nada.
- O `down` só remove as FKs; **os dados deletados não voltam**.
- A única proteção é **disciplina humana documentada**: "NUNCA rodar `db:migrate` puro na AWS; usar `db:migrate:up VERSION=<ts>` alvo". Nada no código impede `db:migrate` puro de disparar a landmine + todas as pendentes em cascata.

**Agravante — divergência schema↔produção:** o `db/schema.rb` versionado (`version: 2026_05_19_210000`) **já contém as FKs da landmine E a coluna `template_params`** (migration de 29/mai, posterior à versão declarada). Ou seja, o schema foi dumpado de um dev DB **onde a landmine já rodou**, enquanto produção a mantém `down` de propósito há semanas. **O `version:` do schema.rb não é confiável** como registro do que foi aplicado. Qualquer `db:schema:load` ou comparação automática schema↔DB em produção sinaliza drift — e um `schema:load` acidental reconstruiria o banco com as FKs cascade ativas.

**Outras 3 migrations destrutivas/irreversíveis** (todas com `down` no-op/vazio): `20260203180000` (`FunnelItem.delete_all` na stage Resolvido), `20260317204605` (DELETE de notifications/participants/mentions), `20260317214100` (UPDATE em massa dedup de conversations).

**Mitigação:** **resolver a landmine de vez.** Opções: (a) rodar a limpeza de órfãos como um **script idempotente revisado e auditado** (com contagem prévia e backup), aplicar as FKs, e então **remover a migration do caminho de `db:migrate`**; (b) reescrever a migration para **abortar se a contagem de órfãos exceder um teto** e exigir `ENV['CONFIRM_DESTRUCTIVE']`. Em qualquer caso, **regenerar `db/schema.rb` a partir do banco de produção real** para acabar com a divergência. Enquanto a landmine viver como pendente, um deploy distraído = perda de dados massiva.

### 3.3 🟠 R3 — Controle operacional via console SSH (frágil e não-replicável)

Toda a operação crítica é **comando manual no console de produção**:

- **Disparo:** `rails 'spx:tozi:disparo[csv,limit,dry_run,spread,template]'` na AWS.
- **Pausar disparo:** script ad-hoc que deleta `DisparoLeadJob` do `Sidekiq::ScheduledSet`.
- **Dedup/redistribuição/retomada:** scripts de console one-off (vários em `Temp/`).
- **Ativar/desligar a IA:** criar/destruir `CaptainInbox` via console; trocar `behavior.router.only_contact_phones`.
- **Kill-switch auto-resolve:** `Account.find(6).update!(captain_auto_resolve_mode: 'disabled')`.
- **Criar templates HSM:** `rails 'spx:tozi:create_templates'` ou scripts Net::HTTP→Graph API.

**Problemas:**
1. **Hardcode Tozi:** `DisparoLeadJob::INBOX_ID = 91`; `DISPARO_BROKERS = [128,126,127,131,125]` (corretores do Account 6); funil "Pré-Venda Tozi"; ENV `TOZI_VISTA_API_KEY`, `TOZI_EVAL_ACCOUNT_ID` (default `'1'`). Um 2º cliente não roda sem editar código.
2. **Sem trilha de auditoria:** quem disparou, quando, para quantos, com qual cópia — vive em logs e na cabeça do operador. Nenhuma tabela de "campanhas de disparo" com estado.
3. **Sem guard-rails no console:** um `perform_now` errado, um CSV trocado, um `update_all` sem `where` — e não há nada além de atenção humana. O próprio STATE registra sustos ("mensagens estranhas", esvaziar conversa de teste com `update_columns` que não reabriu).
4. **`FunnelAutomationListener` roda para TODA conta** (está no `AsyncDispatcher#listeners` global). É no-op para contas sem o funil, mas executa uma query (`current_type`) em **todo** `message_created`/`assignee_changed` da instância — acoplamento multi-tenant + imposto de performance por evento (ver §4).

**Mitigação:** mover o disparo para uma **entidade de primeira classe** (model `BulkDispatch`/`Campaign` estendida) com estado (`draft/running/paused/done`), parametrização por conta/inbox/brokers (sem hardcode), e uma **UI mínima de operação** (iniciar/pausar/retomar + dashboard — já existe o `campaign_stats`, falta a ação). Isso elimina os scripts de console e dá auditoria.

### 3.4 Outros riscos relevantes (priorizados)

| # | Risco | Sev. | Local |
|---|---|---|---|
| 1 | **Exceção em service de gating sobe pelo callback `message_created`** sem rescue → pode quebrar o recebimento de mensagem da inbox | 🔴 Alto | `hook_execution_service#process_captain_behavior` |
| 2 | `BusinessHoursChecker.parse_time` sem validação: `schedule` JSONB malformado (`"25:00"`, `nil`) levanta exceção; o call-site de gating **não tem rescue** (só o de prompt tem) | 🟠 Alto | `business_hours_checker.rb` |
| 3 | **`rescue StandardError` no `DisparoLeadJob` engole falhas para o log** — em escala de milhares, falha sistemática é invisível sem tail de log; sem métrica, sem dead-letter, sem retry | 🟠 Alto | `disparo_lead_job.rb:73` |
| 4 | `DisparoLeadJob` sempre manda `processed_params {'1','2'}` — template de 1 variável pode dar `#132000 number of parameters` (gotcha já vivido no STATE) | 🟠 Médio-Alto | `disparo_lead_job.rb:107` |
| 5 | **`sleep` do humanizer (até 7s/chunk) dentro do worker Sidekiq** prende workers sob carga multi-cliente | 🟠 Médio-Alto | `response_builder_job#send_humanized_response` |
| 6 | **Chave LLM global compartilhada entre contas** no runtime v2 (gem `agents` configurada no boot com `CAPTAIN_ANTHROPIC_API_KEY` global) — sem isolamento de billing/rate-limit por cliente | 🟠 Médio-Alto | `ai_agents.rb` / `AgentRunnerService` |
| 7 | **Gap Meta Lead Ads → Cloud API:** `create_initial_message` manda **texto livre**; numa inbox Cloud API fora da janela 24h a Meta **bloqueia** (só HSM passa). Leads de formulário entram no funil mas **não recebem abertura** | 🟠 Médio-Alto | `create_conversation_service.rb:129` |
| 8 | `store_accessor :behavior, :*_config` = **dead code** (chaves divergem das lidas pelos services); sem schema/validação do JSONB → typo vira silenciosamente "feature off" | 🟡 Médio | `assistant.rb` |
| 9 | **`MediaPipelineService` órfão** — sem call-site no backend; a UI sugere controle que não existe; transcrição de áudio roda sempre, fora do toggle | 🟡 Médio | `media_pipeline_service.rb` |
| 10 | `perform_handoff` de cota estourada usa string **EN hardcoded** ("Transferring to another agent…") sem i18n, enquanto o handoff normal é i18n-aware → cliente PT vê EN | 🟡 Baixo-Médio | `hook_execution_service` |
| 11 | `RouterService` com heurística **BR/WAHA-específica** (DDI 55, "9 a mais", JID `@g.us`) → falso-negativo/positivo em cliente não-BR ou não-WAHA | 🟡 Baixo (hoje) | `router_service.rb` |
| 12 | `max_turns: 100` no runner → loop de tool-calls pode consumir muitos tokens/tempo por request | 🟡 Baixo | `agent_runner_service.rb` |

**Pontos fortes (registrar o que está bem-feito):** higiene de segredos OK (`.env`/`master.key` gitignored, só `.env.example` versionado, segredos Tozi via ENV); `SignatureVerifier` usa `secure_compare` timing-safe; `BuscarImovelTool` tem `timeout: 15` + rescue; `AgentRunnerService` degrada gracioso (erro → handoff); `ResponseBuilderJob` é defensivo (retry_on + re-checagem de status uncached); dedup atômico via Redis `SET NX`; debounce com TTL-buffer anti-race; rake de disparo com **`dry_run` default true** (boa rede de segurança); listeners e services custom todos `rescue`-wrapped no nível do handler.

---

## 4. Performance

### 4.1 `campaign_stats` — N+1 e full-scan por request

`CampaignsController#campaign_stats` (computado a cada request, sem cache):
- `@campaign.conversations.pluck(:id)` carrega **todos** os IDs em memória (campanha #1 = 1.529 convs; passa array gigante para os `WHERE conversation_id IN (...)` seguintes — funciona em milhares, degrada em dezenas de milhares).
- `outgoing.where(status: :failed).find_each { ... }` itera **cada** mensagem falha para extrair o código de erro.
- Bloco `recent`: para cada uma das 15 conversas, **uma query separada** da última mensagem incoming (**15 N+1**).
- 8+ queries de agregação por chamada, sem índice dedicado para o filtro `additional_attributes -> 'template_params' ->> 'name'` (JSONB sem índice GIN → seq scan parcial em `messages`).

**Impacto:** aceitável na escala Tozi atual; **não escala** para campanhas de 10k+ ou múltiplos clientes consultando simultaneamente. **Mitigar:** materializar stats (rollup), cachear com TTL curto, ou índice parcial GIN no `template_params`.

### 4.2 Humanizer `sleep` dentro do worker

Cada resposta da IA quebrada em N chunks faz `sleep(1.5s–7s)` **por chunk dentro do job Sidekiq**. Uma resposta de 5 partes segura um worker ~35s. Sob carga multi-cliente, **prende workers** e derruba throughput. **Mitigar:** reagendar cada chunk como job separado (`perform_in`) em vez de bloquear o worker.

### 4.3 Listener Tozi no caminho quente global

`Spx::Tozi::FunnelAutomationListener` roda em **todo** `message_created`/`assignee_changed` de **toda conta** (registro global no `AsyncDispatcher`). Mesmo sendo no-op fora da Tozi, executa `FunnelPlacementService.current_type` (1 query com joins) por evento. Imposto pequeno mas multiplicado por volume × tenants. **Mitigar:** gate por account/feature-flag antes de tocar o banco.

### 4.4 Investimentos de performance já presentes (positivo)

O fork **já fez** trabalho sério de performance: ~10 migrations de índices em 2026 (keyset/cursor para listas e Kanban, trigram em `contacts` e `messages.content`, BRIN, índice de scroll pagination, `reporting_events_rollup`). A base de leitura de conversas está bem indexada. O débito está concentrado nas features custom recentes (stats, humanizer, listener), não no core.

### 4.5 RAG / embeddings

`captain_document_chunks` usa `vector(1536)` com **HNSW** (fallback ivfflat) + `tsvector` GIN para busca híbrida — arquitetura correta e moderna. pgvector 0.8.2 em prod suporta HNSW direto. Sem ressalvas de performance aqui além do custo de embedding na ingestão (esperado).

---

## 5. Checklist de Produtização — vender o SPX para um 2º cliente

> Hoje o SPX é um **serviço gerenciado para a Tozi**. Para virar **produto vendável** (2º, 3º cliente), o trabalho não é mais features — é **desacoplamento, isolamento e operação self-service**. Organizado por bloqueio.

### 5.1 🔴 Multi-tenancy real (de-hardcode da Tozi) — **bloqueador absoluto**

- [ ] **Remover hardcodes Tozi do código.** `DisparoLeadJob::INBOX_ID=91`, `DISPARO_BROKERS=[125..131]`, funil "Pré-Venda Tozi", `TOZI_*` ENV → mover para **config por conta** (tabela/JSONB de settings do account, ou um model `SpxAccountConfig`).
- [ ] **Generalizar `Spx::Tozi::*` → `Spx::*` parametrizável.** O funil, a cadência e o disparo devem receber `account`/`inbox`/`brokers`/`templates` como parâmetro, não constante.
- [ ] **Isolar a chave LLM por conta.** Hoje o runtime v2 usa a chave Anthropic **global** de instalação — billing e rate-limit não são isolados entre clientes. Cada conta precisa de sua própria chave (ou um esquema de billing por uso medido).
- [ ] **Gate do `FunnelAutomationListener` por feature-flag/conta** antes de tocar o banco.
- [ ] **Tools de domínio plugáveis.** `BuscarImovelTool`/`EnviarFotosImovelTool` são imobiliário-específicas (Vista API). Um 2º cliente de outro vertical precisa de outras tools — extrair um **registro de tools por conta** (já existe `ToolRegistryService`; falta a configuração por conta sem deploy).

### 5.2 🔴 Operação self-service (matar o console SSH)

- [ ] **Model `BulkDispatch` de primeira classe** com estado (`draft/running/paused/completed`), audiência, template, pacing, brokers — substituindo os scripts de console e o `Temp/`.
- [ ] **UI de disparo:** iniciar / pausar / retomar / dedup, em cima do `campaign_stats` que já existe. Hoje o card só lista/exclui.
- [ ] **UI de ativação da IA** (conectar/desconectar `CaptainInbox`, editar whitelist/skip, kill-switch auto-resolve) — hoje tudo via console. O `RouterConfig.vue` precisa editar `only_contact_phones`/`skip_groups`; o `captain_auto_resolve_mode` precisa de toggle.
- [ ] **Trilha de auditoria** de operações sensíveis (quem disparou, ativou IA, mudou template).

### 5.3 🔴 Confiabilidade (R1 + R2)

- [ ] **Resolver a migration-landmine** (§3.2): script idempotente auditado + remover do caminho de `db:migrate` + **regenerar `schema.rb` do banco de produção**.
- [ ] **Suíte de testes mínima do custom** (§3.1): começar pelos 3 caminhos do dinheiro (disparo, Meta Lead Ads, cadência) + behavior services puros.
- [ ] **Observabilidade do disparo:** métrica de enviados/entregues/falhas em tempo real (não só log), dead-letter para falhas, alerta de degradação de tier WABA (YELLOW→RED).
- [ ] **Fechar o gap Meta Lead Ads → Cloud API** (1ª mensagem como HSM quando `inbox.whatsapp?`).

### 5.4 🟠 Onboarding de novo cliente

- [ ] **Roteiro reproduzível** (hoje é tribal/console). Idealmente um wizard ou rake `spx:onboard[account]` que: cria a conta, configura inbox WhatsApp (WAHA ou Cloud API), cria o assistant com behavior default, conecta knowledge, configura funil e brokers.
- [ ] **Provisionamento de WABA/Cloud API** documentado e/ou semi-automatizado (o `TemplateManagementService` já cria templates via API — falta o fluxo de ponta a ponta).
- [ ] **Branding por tenant.** O manual de marca SPX existe (`/brand/manual-marca-spx.md`: verde `#2dc46f`, Inter, dark-mode obrigatório) e o fork usa `replaceInstallationName`/`useBranding`. Mas um cliente white-label seu precisa de **logo/cores por conta** — verificar se o branding é por instância (global) ou por account. Hoje parece por instância (SPX), não por tenant.

### 5.5 🟠 Billing / comercial

- [ ] **Medição de uso por conta:** mensagens IA, tokens LLM, HSM disparados (custo Meta), storage de knowledge. Sem isso não há como precificar nem cobrar.
- [ ] **Limites/cotas por plano** (o Chatwoot tem `Account` limits; o Captain tem `captain.responses` quota — verificar se está por conta e se alimenta cobrança).
- [ ] **Isolamento de custo LLM** (decorre de 5.1) — sem chave por conta, o custo de IA de todos os clientes cai no mesmo balde.

### 5.6 🟡 Documentação

- [ ] **Runbook de operação** (disparo, pausa, ativação IA, incidentes) — hoje o conhecimento está no STATE.md e no vault, ótimo para o Paulo, intransferível para um operador novo.
- [ ] **Doc de arquitetura da camada SPX** (este relatório é um ponto de partida; falta um `docs/adr/` formal das decisões: code-first, behavior JSONB, disparo próprio vs nativo, landmine).
- [ ] **Onboarding técnico** de um 2º dev (o AGENTS.md já é excelente para isso; estender com a camada `Spx::`).

### 5.7 Resumo do caminho crítico para o 2º cliente

```
1. De-hardcode Tozi → config por conta          (§5.1) ─┐
2. Isolar chave/billing LLM por conta            (§5.5) ─┼─ sem isso, 2º cliente = fork do fork
3. Resolver landmine + schema drift              (§3.2) ─┘
4. UI mínima de disparo + ativação IA            (§5.2) ── mata o console SSH
5. Specs dos 3 caminhos do dinheiro              (§3.1) ── confiança pra cobrar
6. Runbook + onboarding reproduzível             (§5.4) ── escala sem o Paulo no console
```

---

## Apêndice A — Inventário de arquivos custom auditados

**Backend `Spx::`:** `app/jobs/spx/tozi/disparo_lead_job.rb`, `app/services/spx/tozi/{funnel_placement,reactivation_cadence}_service.rb`, `app/listeners/spx/tozi/funnel_automation_listener.rb`, `lib/tasks/spx_tozi.rake`.

**Meta Lead Ads:** `app/controllers/webhooks/meta_lead_ads_controller.rb`, `app/services/meta/lead_ads/{signature_verifier,token_verifier,hook_finder,fetch_lead_service,create_conversation_service}.rb`, `app/jobs/webhooks/meta_lead_ads_job.rb`.

**Captain custom (Enterprise overlay):** `enterprise/lib/captain/tools/{buscar_imovel,enviar_fotos_imovel,programar_followup,salvar_info_lead}_tool.rb`; `enterprise/app/services/captain/behavior/{router,debounce,humanizer,dedup,business_hours_checker,media_pipeline,copilot_trigger}_service.rb`; `enterprise/app/services/captain/assistant/agent_runner_service.rb`.

**Modificações OSS:** `app/models/campaign.rb`, `app/controllers/api/v1/accounts/campaigns_controller.rb` (+`campaign_stats`/`stats`), `app/policies/campaign_policy.rb`, `app/dispatchers/async_dispatcher.rb`.

**Migration-landmine:** `db/migrate/20260330120000_add_foreign_key_constraints.rb` (+ destrutivas `20260203180000`, `20260317204605`, `20260317214100`).

**Frontend:** `app/javascript/dashboard/routes/dashboard/agents/`, `components-next/agents/`, `components-next/copilot/`, `routes/dashboard/kanban/`, campanhas WhatsApp, respostas-rápidas c/ anexo, view "Não lidas".

## Apêndice B — O que NÃO foi verificado (limites desta auditoria)

- Suíte de testes não foi executada (não há confirmação de pass/fail em runtime).
- Migrations não foram rodadas; o estado real do banco de produção não foi inspecionado (apenas o `schema.rb` versionado e o que o STATE.md documenta).
- Segurança de infra (AWS, proxy, TLS, firewall) fora de escopo.
- Não foi medido o consumo real de tokens/custo LLM nem o throughput do Sidekiq sob carga.
- O frontend custom foi mapeado e quantificado, mas não auditado linha-a-linha quanto a bugs de UI.

---

*Relatório gerado por auditoria estática em 2026-06-04. Para dúvidas sobre qualquer achado, os caminhos de arquivo e linhas estão citados ao longo do texto.*
