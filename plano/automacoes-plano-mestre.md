# Plano Mestre — Plataforma de Automações Unificadas (`Flow`) · ChatSPX

> **O que é este documento.** A consolidação dev-ready dos 6 relatórios de pesquisa (estudo Google Labs · motor de execução · frontend · catálogo de nós · enrollment/conformidade/analytics · design system) num único plano de construção para o módulo "fazer tudo" de automações do ChatSPX: um só motor **`Flow`** que unifica **Macro** (ação manual) e **AutomationRule** (automação por evento) sobre a base `ActionService` já existente, com canvas visual vertical (Activepieces-like), WhatsApp-first e o Captain como camada de IA.
>
> **Base não re-auditada:** dossiê `plano/automacao-macros-pesquisa.md` (fatos de código já verificados) + mockup mestre `public/mockups/automacoes-canvas.html`. Este plano **verificou pontualmente** as referências de código mais críticas antes de consolidar (ver Apêndice A).
>
> **Legenda de honestidade** (aplicada em todo o texto):
> - ✅ **EXISTE** — método/tabela/arquivo verificado no código em `arquivo:linha`.
> - 🟡 **PARCIAL** — existe em outro motor (Kanban/Sequences), precisa exposição/adaptação.
> - 🆕 **NOVO/PROPOSTA** — não existe; é design deste plano.
> - ⚠️ **INCERTEZA** — não pôde ser confirmado na verificação; marcar para checar na implementação.
>
> **Datas/autoria:** consolidado 2026-07-06. Alvo de mercado: BR / WhatsApp. Idioma de produto: **pt-BR prioritário**.

---

## 0. TL;DR — as 8 decisões de arquitetura

1. **Um motor, não três.** Macro + AutomationRule fundem-se num modelo `Flow`. O Kanban (`FunnelAutomation`) **fica separado** por ora — converge só no vocabulário de ações. (§1.1, §2.10)
2. **Reuso total do `ActionService`.** O motor não reimplementa nenhuma ação: instancia uma subclasse fina (`Flows::ActionService`) e chama `public_send(action_name, action_params)` — o **mesmo dispatch** de hoje (`app/services/action_service.rb:113`; `automation_rules/action_service.rb:14`). (§2.4)
3. **Estado e scheduler são cópia estrutural do que já roda.** `flow_runs` copia `message_sequence_enrollments` (`db/schema.rb:1430`); `Flows::ResumeJob` copia `MessageSequences::AdvanceJob` (cron `*/1`, `config/schedule.yml:37`); `schedule` copia `Kanban::SlaMonitorJob` (cron `*/15`, `config/schedule.yml:25`). (§2.6)
4. **Modelo separado do render.** `definition:jsonb` (`{nodes[], edges[]}`) é a fonte da verdade; o canvas só renderiza — lição do ProductCanvas (`document/` × `canvas/`). Isso torna a migração de Macro/AutomationRule barata (viram Flows lineares). (§1.3, §2.2)
5. **Renderer já está pago.** `@vue-flow/core@^1.48.2` (MIT) **já está no `package.json:62`** e instalado, com **zero uso atual**. Adotamos Vue Flow; falta só `@vue-flow/minimap`. (§5.2)
6. **`send_template` é o gap-BR nº1 (P0/F1).** WhatsApp fora da janela 24h só entrega template. É a assinatura visual do produto (preview de balão + var-map + nota 24h). (§3, §4.2, §6)
7. **IA como *peer*, não como nó isolado.** O Captain dirige **os mesmos comandos determinísticos** do usuário sobre o canvas (padrão ProductCanvas `commands/`), passando pelas mesmas whitelists. (§1.3, §5.6)
8. **Compliance é infra, não checkbox.** Opt-out (keyword PARAR), cap de marketing/dia, janela 24h automática e horário comercial timezone-aware entram no motor via tabelas de suppression + `Conversation#can_reply?` (`app/models/conversation.rb:187`). (§4.2)

**Bloqueadores estruturais (só caem em F2/F3):** `wait`/`schedule` (scheduler + estado entre execuções) e `router`/nós de IA (motor de nós+arestas). Tudo o mais é surfaçar o que já existe.

---

## 1. VISÃO & PRINCÍPIOS

### 1.1 A tese — um "Flow" sobre o `ActionService`

Hoje o ChatSPX tem **três** motores de automação que não se falam:

| Motor | Gatilho | Contexto | Estado no código |
|---|---|---|---|
| **Macro** | manual (usuário clica) | `Current.user` = agente | `app/services/macros/execution_service.rb` ✅ |
| **AutomationRule** | evento de conversa | `Current.executed_by` = rule | `app/services/automation_rules/action_service.rb` ✅ |
| **Kanban FunnelAutomation** | tempo/evento no funil | `funnel_item` | `app/jobs/kanban/sla_monitor_job.rb` ✅ |

**Fato-chave (dossiê §1.1, verificado):** Macro e AutomationRule **já herdam a mesma base** `ActionService` (`app/services/macros/execution_service.rb:1` e `app/services/automation_rules/action_service.rb:1` ambos `< ActionService`). A base traz os ~13 métodos de ação compartilhados (`mute/snooze/resolve/open/pending_conversation`, `change_status`, `change_priority`, `add_label`/`remove_label`, `assign_agent`/`assign_team`/`remove_assigned_team`, `send_email_transcript`) — `app/services/action_service.rb:9-91` — e o mixin enterprise (`add_sla`, `assign_ai_agent`) via `ActionService.include_mod_with('ActionService')` (`:113`).

A divergência entre os dois é **fina e localizada**: quem é o autor da mensagem e o anti-loop.
- Automação: `Current.executed_by = rule` (`automation_rules/action_service.rb:6`) + mensagem com `content_attributes.automation_rule_id` (`:46`) para o listener não re-disparar.
- Macro: `Current.user = user` (`macros/execution_service.rb:7`) + `assign_agent 'self'` resolve para `@user.id` (`:31-34`).

**Conclusão:** unificar não é reescrever — é fundir dois overrides num só (`Flows::ActionService`, §2.4) e por cima colocar um **walker de grafo** (`Flows::RunnerService`, §2.5) que decide *qual nó* rodar. O motor Kanban permanece intacto (§2.10).

### 1.2 Princípios de design (invioláveis)

1. **Task-first / precedente-first.** Toda peça nova tem um precedente citado no código. Onde não há precedente (endpoint inbound de webhook, HTTP síncrono), marca-se 🆕 e isola-se o risco.
2. **Modelo separado do render.** `definition` (jsonb) é a verdade; o canvas é descartável. (ProductCanvas `document/` × `canvas/`.)
3. **WhatsApp-first.** A janela de 24h é cidadã de primeira classe: `send_template` é P0, e todo nó de envio consulta `can_reply?` antes de decidir free-form vs template.
4. **Um vocabulário de comandos, dois consumidores.** Usuário (Cmd-K/paleta) e IA (tool-calling) mutam o canvas pelos **mesmos comandos** determinísticos, validados pelas mesmas whitelists. (§5.6)
5. **IA como peer, não como caixa-preta.** O Captain propõe blocos-fantasma e variantes; não gera JSON solto fora da whitelist. Toda ação de IA é dry-run-testável.
6. **Best-effort por nó, nunca derruba o fluxo.** Herda o padrão atual: `rescue` + log por ação (`automation_rules/action_service.rb:13-17`), agora com rastro em `flow_step_logs`.
7. **Reentrância é lei.** Anti-loop de mensagem (`flow_id`), depth-guard entre flows (`Current.flow_depth`, cópia de `funnel_automation_depth`), idempotência por índice único parcial. (§2.8)
8. **Nada hardcoded, light+dark obrigatório.** Todo texto é chave i18n (pt-BR prioritário); toda cor é token; validação Playwright em light **e** dark antes de "pronto" (memória `feedback_playwright_obrigatorio_light_dark`).

### 1.3 O que os experimentos do Google Labs nos ensinaram — e o que adotamos

Fontes (URLs preservadas):
- **ProductCanvas** (Roman Nurik + David East) — repo https://github.com/romannurik/ProductCanvas-Experiment · Labs https://labs.google/code/experiments/product-canvas · **Apache-2.0** (código reutilizável).
- **MagicModules** — https://github.com/romannurik/MagicModules-Experiment · **Apache-2.0**.
- **AtQ** — https://github.com/romannurik/AtQ-Experiment · **Apache-2.0**.
- **MoMoA** ("Mixture of Mixture of Agents") — https://github.com/retomeier/MoMoA · branch https://github.com/retomeier/MoMoA/tree/momoa-basic · **sem licença declarada** → método, não código.
- **MoMoA-Researcher** — https://github.com/retomeier/MoMoA-Researcher · **sem licença declarada** → método, não código.

**Aprendizados aplicados ao canvas (UX + modelo):**

| # | Aprendizado (origem) | O que adotamos | Onde encaixa no nosso código |
|---|---|---|---|
| **B1** | Toda mutação do canvas é um **comando nomeado** (`CommandProvider`/`CommandPalette`/`Shortcut` no ProductCanvas `commands/`) | Camada única de comandos (`addNode`, `connect`, `setNodeParams`, `addBranch`, `deleteNode`, `wrapInWait`) que **user e IA** dirigem | Paleta esquerda + `+` do mockup viram invocadores de comando; whitelists de ação (`macro.rb:33` `ACTIONS_ATTRS`; `automation_rule.rb:42` `actions_attributes`) validam ambos |
| **B2** | `miniapp-generator` gera **artefato autocontido constrangido a uma host API `$`** ("responda só com o código, nada mais" + strip de cercas + `thinkingBudget`) | "Gerar fluxo por frase" → IA emite **nosso DSL** (`{nodes[],edges[]}`), constrangida ao vocabulário verificado (triggers/ações/condições), não código livre | `definition:jsonb` (§2.2); guard: só emite `send_template` se houver inbox `whatsapp_cloud` + template `APPROVED` |
| **B3** | *"AI as peer contributor, flow-preserving"* (Labs) + variações "napkin sketch" (Nano Banana) | Co-piloto Captain **ancorado ao canvas**: blocos-fantasma aceita/rejeita + 2–3 variantes do fluxo (agressiva vs conservadora) | Nó Captain já no mockup; reusa `enterprise/app/models/captain/assistant.rb` ✅ |
| **B4** | ProductCanvas roda o artefato **live** (runtime `esbuild-wasm`) | Botão "Testar" = **dry-run real** contra conversas históricas, pintando os `142·38%` nos ramos; preview do template dentro do nó | Botão "Testar" + `.preview`/`.bpill` do mockup; **nunca dispara IA/msg real** (memória `feedback_subagents_nao_tocam_producao`) |
| **B5** | **Modelo separado do render** (`document/`) + wiki/knowledge-graph alimenta a IA | `definition` é a verdade; Vue Flow (MIT) só renderiza. Contexto de conta (templates aprovados, times, inboxes cloud, SLA, horário comercial) consolidado para o gerador nunca sugerir o que não existe | Migração barata de AutomationRule/Macro → Flow linear (§2.3) |

**Aprendizados aplicados ao método de planejamento (MoMoA — formalizar o que já fazemos):**

| # | Mecanismo MoMoA | Adoção |
|---|---|---|
| **C1** | **Work Phase Rooms** — personas adversariais (*Creative Developer* × *Conservative Senior Engineer*) debatem antes de fechar | Toda spec não-trivial passa por par em tensão da matriz (`.claude/rules/agent-authority.md`): `@architect` propõe × `@qa` cética; só fecha com dois assinando |
| **C2** | **Research Logger append-only** — hipótese→resultado antes de mexer no relatório | Log append-only de claims com proveniência (`[verificado em X:linha]` vs `[1 fonte]`); conflito entre fontes vira entrada explícita (como este plano fez) |
| **C3** | **Overseer** roda a cada 15 min para quebrar loop circular | Adotar como "relógio" do QA Loop (`maxIterations: 5`): detecta re-trabalho no mesmo arquivo N× sem progresso → escala a `@aiox-master` |
| **C4** | **Self-evaluation loop** + **human-in-the-loop** na ambiguidade | Após cada fase, auto-avaliar e propor próximo passo (SDC Phase 4). Decisão irreversível/ambígua (migração destrutiva, escolha de variante de template) **pausa e pergunta** — tempera o modo YOLO |

### 1.4 O que NÃO adotamos (honestidade)

- **Grafo livre estilo n8n.** Ficamos no **Activepieces-like** (linked-list vertical + Router `EXECUTE_FIRST_MATCH`). Menos poder, muito menos bug de coordenadas e de ciclo. (dossiê §5, Opção 3.)
- **Código do MoMoA/MoMoA-Researcher.** Sem licença declarada → só o método.
- **Fundir o Kanban agora.** Precisa de contexto `funnel_item` e ações `move`/`enroll_in_sequence` fora do escopo só-conversa. Converge por vocabulário, não por motor. (§2.10)
- **n8n / Typebot / Automatisch como dependência.** Licenças fair-code / FSL / **AGPL** (contamina SaaS). Só inspiração de UX. (dossiê §3.3.)

---

## 2. ARQUITETURA

### 2.1 Modelo de dados

Cinco tabelas novas (🆕 PROPOSTA). Três são o núcleo do motor (`flows`, `flow_runs`, `flow_step_logs`); duas são compliance/analytics (`contact_flow_suppressions`, `flow_node_stats`). Cada uma **espelha uma tabela que já existe**.

#### `flows` 🆕 (generaliza `automation_rules` + `macros`)

```ruby
create_table :flows do |t|
  t.references :account, null: false, index: true
  t.string  :name, null: false
  t.text    :description
  t.integer :trigger_type, null: false, default: 0    # enum abaixo
  t.jsonb   :trigger_config, null: false, default: {}  # polimórfico por trigger_type
  t.jsonb   :definition, null: false, default: { 'nodes' => [], 'edges' => [] }
  t.boolean :active, null: false, default: true
  t.integer :version, null: false, default: 1          # bump a cada publish; flow_run fixa a versão
  t.integer :visibility, null: false, default: 1       # herda macro.rb:29 (personal:0/global:1)
  t.integer :reentry_policy, null: false, default: 0   # once:0 / re_enroll:1 / re_enroll_after:2 (§4.1)
  t.jsonb   :goal_conditions, null: false, default: {} # meta de saída, avaliada por GoalListener (§4.1)
  t.bigint  :created_by_id
  t.bigint  :updated_by_id
  t.timestamps
end
add_index :flows, [:account_id, :trigger_type, :active]  # espelha o lookup do listener
```

```ruby
class Flow < ApplicationRecord
  enum trigger_type: { manual: 0, conversation_event: 1, schedule: 2, keyword: 3, external_webhook: 4 }
  enum reentry_policy: { once: 0, re_enroll: 1, re_enroll_after: 2 }
  enum visibility: { personal: 0, global: 1 }           # espelha macro.rb:29
  has_many_attached :files                              # preserva @rule.files / @macro.files p/ send_attachment
  scope :active, -> { where(active: true) }
end
Flow.include_mod_with('Flow')                           # gate enterprise/audit; espelha automation_rule.rb:108
```

**`trigger_config` por `trigger_type`** (o que hoje mora em colunas soltas vira config):

| trigger_type | `trigger_config` | precedente |
|---|---|---|
| `manual` | `{}` (disparo por `conversation_ids[]`, bulk) | macro |
| `conversation_event` | `{ "event_name": "...", "conditions": [ {attribute_key, filter_operator, values, query_operator} ] }` | `event_name` era coluna NOT NULL (`automation_rule.rb:10`) |
| `schedule` | `{ "cron": "0 9 * * *" }` **ou** `{ "relative": { "event": "conversation_created", "after_minutes": 1440 }, "conditions": [...] }` | Kanban `time_in_stage` |
| `keyword` | `{ "keywords": ["parar","stop"], "match": "exact\|contains", "inbound_only": true, "inbox_ids": [] }` | — |
| `external_webhook` | `{ "token": "<secreto>", "sample_payload": {...}, "variable_mappings": {"order_id":"$.order.id"} }` | 🆕 |

#### `flow_runs` 🆕 (cópia estrutural de `message_sequence_enrollments` — `db/schema.rb:1430`)

```ruby
create_table :flow_runs do |t|
  t.references :account, null: false, index: true
  t.bigint   :flow_id, null: false
  t.bigint   :conversation_id, null: false
  t.bigint   :contact_id, null: false          # dedupe/suppression por CONTATO (§4.1) — WhatsApp abre conversa nova por janela
  t.string   :current_node_id                  # onde parou (≡ current_step_position, schema.rb:1434)
  t.jsonb    :state, null: false, default: {}   # variáveis, payload do webhook, branch history, idempotency_key
  t.integer  :status, null: false, default: 0   # enum abaixo
  t.datetime :resume_at                          # ≡ next_run_at (schema.rb:1435)
  t.integer  :flow_version, null: false          # fixa a versão da definition no início do run
  t.timestamps
end
add_index :flow_runs, [:status, :resume_at]      # espelha schema.rb:1442 (o lookup do ResumeJob)
# Idempotência: 1 run vivo por (flow, contato) — espelha schema.rb:1440 (parcial, WHERE status=0)
add_index :flow_runs, [:flow_id, :contact_id], unique: true,
          where: 'status IN (0,1)', name: 'index_active_flow_run_per_flow_contact'
```

```ruby
class FlowRun < ApplicationRecord
  belongs_to :flow; belongs_to :conversation; belongs_to :contact
  enum status: { running: 0, waiting: 1, completed: 2, failed: 3, cancelled: 4 }
  scope :due, -> { waiting.where('resume_at <= ?', Time.current) }   # cópia literal de MessageSequenceEnrollment.due
end
```

> **Decisão-chave (Relatório 5):** dedupe por `contact_id`, **não** `conversation_id` — no WhatsApp uma nova janela abre conversa nova; a supressão/reentrada precisa seguir a pessoa. O índice único parcial usa `[flow_id, contact_id]`.

#### `flow_step_logs` 🆕 (rastro por nó — sem precedente direto, mas herda o padrão best-effort)

```ruby
create_table :flow_step_logs do |t|
  t.references :account, null: false, index: true
  t.bigint   :flow_run_id, null: false, index: true
  t.bigint   :flow_id, null: false
  t.string   :node_id, null: false
  t.string   :node_type, null: false           # action|condition|router|wait|...
  t.string   :branch_key                        # qual ramo saiu (true/false/route_1/else) — alimenta os 142·38%
  t.integer  :status, null: false, default: 0   # ok:0 / failed:1 / skipped_guard:2 / waiting:3
  t.jsonb    :input, default: {}
  t.jsonb    :output, default: {}
  t.string   :error_code                        # tipado (§4.4)
  t.integer  :duration_ms
  t.datetime :created_at, null: false
end
add_index :flow_step_logs, [:flow_id, :node_id, :status]     # agregação por nó/ramo
add_index :flow_step_logs, [:flow_id, :status, :error_code]  # painel de saúde
```

#### `contact_flow_suppressions` 🆕 (opt-out + cap de marketing — §4.2)

```ruby
create_table :contact_flow_suppressions do |t|
  t.references :account, null: false, index: true
  t.bigint   :contact_id, null: false
  t.integer  :reason, null: false               # opt_out:0 / marketing_cap:1
  t.bigint   :flow_id                            # nil = global (opt-out geral)
  t.integer  :counter, default: 0                # p/ cap: templates marketing enviados no dia
  t.datetime :expires_at                          # cap: fim-do-dia; opt-out: nil (permanente até re-opt-in)
  t.timestamps
end
add_index :contact_flow_suppressions, [:account_id, :contact_id, :reason]
```

#### `flow_node_stats` 🆕 (rollup incremental de métricas — §4.3)

```ruby
create_table :flow_node_stats do |t|
  t.bigint  :flow_id, null: false
  t.integer :flow_version, null: false
  t.string  :node_id, null: false
  t.string  :branch_key
  t.bigint  :entered_count, default: 0
  t.bigint  :completed_count, default: 0
  t.bigint  :failed_count, default: 0
  t.timestamps
end
add_index :flow_node_stats, [:flow_id, :flow_version, :node_id, :branch_key], unique: true  # UPSERT-alvo
```

> O canvas lê **pré-agregado** de `flow_node_stats` (UPSERT por um `Flows::StatsRollupJob` que reusa a infra do `AdvanceJob`), nunca `COUNT` ao vivo em `flow_step_logs`. Retenção: logs detalhados 30–90d; stats indefinido.

### 2.2 `definition` — o grafo de nós (jsonb)

Paradigma **Activepieces-like linked-list** (dossiê §5, Opção 3). Cada Macro/AutomationRule migra para uma cadeia linear (caso degenerado, sem branch).

```json
{ "nodes": [
    { "id": "n1", "type": "action",   "action_name": "add_label",    "action_params": ["vip"] },
    { "id": "n2", "type": "wait",      "params": { "for_minutes": 60, "business_hours_only": true } },
    { "id": "n3", "type": "condition", "conditions": [{ "attribute_key":"status","filter_operator":"equal_to","values":["open"],"query_operator":null }] },
    { "id": "n4", "type": "action",    "action_name": "send_template","action_params": [{ "name":"tozi_followup","language":"pt_BR","processed_params":{} }] }
  ],
  "edges": [
    { "from": "n1", "to": "n2" },
    { "from": "n2", "to": "n3" },
    { "from": "n3", "to": "n4", "branch": "true" },
    { "from": "n3", "to": null,  "branch": "false" }
  ] }
```

- `type: "action"` reusa o dispatch `{action_name, action_params}` — **contrato idêntico** ao de hoje (`automation_rules/action_service.rb:14`). `action_params` é **sempre array**, `params[0]` é o valor (invariante verificado em toda a hierarquia `ActionService`).
- `type: "condition"`/`"router"` reusa `AutomationRules::ConditionsFilterService` (`app/services/automation_rules/conditions_filter_service.rb:24`).
- `type: "wait"` suspende o run (§2.6).

### 2.3 Migração Macro / AutomationRule → Flow

| Origem | `trigger_type` | `trigger_config` | `definition.nodes` | Preserva |
|---|---|---|---|---|
| `Macro` | `manual` | `{}` | cada item de `macro.actions` (ordenado) → um nó `action` encadeado | `visibility` (`macro.rb:29`); `files`; `created_by_id`/`updated_by_id` |
| `AutomationRule` | `conversation_event` | `{ event_name, conditions }` | um nó `condition` (gate de entrada) → cadeia de nós `action` a partir de `rule.actions` | `event_name` (`automation_rule.rb:10`); `active`; `files` |

**Backfill idempotente** (`db/migrate`): para cada `automation_rules` e `macros` da conta, criar um `flows` com `definition` derivada. **Tabelas antigas ficam read-only até o cutover:** o listener novo lê de `flows`; durante a transição o listener checa **ambas** as chaves anti-loop (`automation_rule_id` legado **e** `flow_id` novo — §2.8).

> **Decisão aberta (§8):** cutover big-bang vs conta-a-conta (feature flag `flows_v2`). Recomendação: flag por conta, com o motor antigo e o novo coexistindo (o backfill mantém paridade). Ver risco R-3.

### 2.4 `Flows::ActionService` — unifica os dois overrides existentes

Une `AutomationRules::ActionService` e `Macros::ExecutionService` numa só classe. A autoria depende do contexto: com `actor` → macro-semantics (autor = user); sem `actor` → automation-semantics (autor = nil + `flow_id` anti-loop).

```ruby
# app/services/flows/action_service.rb  🆕
class Flows::ActionService < ActionService
  def initialize(flow:, conversation:, actor: nil)
    super(conversation)
    @flow = flow; @actor = actor; @account = flow.account
    actor ? (Current.user = actor) : (Current.executed_by = flow)  # macros/execution_service.rb:7 / automation_rules/action_service.rb:6
  end

  # Executa UM nó de ação. Best-effort por nó (padrão de automation_rules/action_service.rb:13-17).
  def execute(node)
    @conversation.reload
    public_send(node['action_name'], node['action_params'])
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end

  private

  def assign_agent(agent_ids)                                      # 'self' só faz sentido no modo manual (macros/execution_service.rb:31-34)
    agent_ids = agent_ids.map { |id| id == 'self' ? @actor&.id : id }.compact
    super(agent_ids)
  end

  def send_message(message)                                        # funde os DOIS send_message: autoria condicional + flow_id anti-loop
    return if conversation_a_tweet?
    params = { content: message[0], private: false }
    params[:content_attributes] = { flow_id: @flow.id } if @actor.nil?  # generaliza automation_rules/action_service.rb:46
    Messages::MessageBuilder.new(@actor, @conversation.reload, params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?
    params = { content: message[0], private: true }
    params[:content_attributes] = { flow_id: @flow.id } if @actor.nil?
    Messages::MessageBuilder.new(@actor, @conversation.reload, params).perform
  end

  def send_attachment(blob_ids)                                    # fonte = @flow.files (era @rule/@macro.files)
    return if conversation_a_tweet? || @flow.files.blank?
    blobs = ActiveStorage::Blob.where(id: blob_ids)
    return if blobs.blank?
    Messages::MessageBuilder.new(@actor, @conversation, { content: nil, private: false, attachments: blobs }).perform
  end
  # send_email_to_team, send_webhook_event, send_email_transcript, add_sla, assign_ai_agent, send_template (§3)
  # ficam disponíveis para AMBOS os modos porque a base é herdada (action_service.rb:113).
end
```

> **Ganho:** `assign_ai_agent` (`enterprise/app/services/enterprise/action_service.rb:17`, já na whitelist do macro em `macro.rb:33`) e `add_sla` (`:2`) passam a valer para os dois modos num só ponto — resolve a assimetria histórica sem duplicar código.

### 2.5 `Flows::RunnerService` — o walker

```ruby
# app/services/flows/runner_service.rb  🆕
class Flows::RunnerService
  MAX_STEPS = 100    # guarda contra ciclo DENTRO do grafo (edge malformada)
  MAX_DEPTH = 3      # guarda entre flows — cópia de Kanban (current.rb:14)

  def initialize(flow: nil, conversation: nil, actor: nil, resume_run: nil, trigger_payload: {})
    @run  = resume_run
    @flow = resume_run&.flow || flow
    @conversation = resume_run&.conversation || conversation
    @actor = actor
    @payload = trigger_payload
    @actions = Flows::ActionService.new(flow: @flow, conversation: @conversation, actor: actor)
    @graph = @flow.definition.with_indifferent_access
  end

  def perform                                              # → :completed | :suspended
    return if depth_exceeded?
    with_depth do
      node_id = @run&.current_node_id || start_node_id
      steps = 0
      while node_id && (steps += 1) <= MAX_STEPS
        node = find_node(node_id); break if node.nil?
        result = visit(node)
        return suspend!(result[:resume_at], node_id) if result[:suspend]
        node_id = next_node_id(node, result[:branch])
      end
      finish!; :completed
    end
  end

  private

  def visit(node)
    case node['type']
    when 'action'               then @actions.execute(node); {}                        # <<< reuso total do ActionService
    when 'condition', 'router'  then { branch: evaluate_condition(node) ? 'true' : 'false' }
    when 'wait'                 then { suspend: true, resume_at: node.dig('params','for_minutes').to_i.minutes.from_now }
    end
  end

  def evaluate_condition(node)                             # reusa o motor de condição, sem reimplementar SQL
    rule = OpenStruct.new(conditions: node['conditions'], id: @flow.id, account: @flow.account)
    AutomationRules::ConditionsFilterService.new(rule, @conversation, @payload).perform  # conditions_filter_service.rb:24
  end
  # start_node_id, find_node, next_node_id, suspend!, finish!, with_depth/depth_exceeded! — §2.6/§2.8
end
```

> **Nota (duck-type):** `ConditionsFilterService` só toca `@rule.conditions` (`:29`), `@rule.authorization_error!` (`:48`), `.id`, `.account` (`:11`). Um `OpenStruct`/`Flows::RuleAdapter` basta — **sem tocar no serviço**. Se preferir zero-duck-type: extrair um `ConditionsEvaluator.new(conditions:, conversation:, options:)` (refactor **P**, sem mudança de comportamento).

### 2.6 Scheduler + estado — cópia de `MessageSequences` + `SlaMonitorJob`

`wait`/`schedule`/`drip` precisam de **estado persistido entre execuções** + **job periódico de retomada**. Isso já existe: o par `message_sequence_enrollments` + `MessageSequences::AdvanceJob`. `flow_runs` + `Flows::ResumeJob` é a cópia.

```ruby
# suspensão/retomada no Runner
def suspend!(resume_at, node_id)
  next_id = next_node_id(find_node(node_id), nil)          # o nó DEPOIS do wait
  run = @run || FlowRun.create!(account: @flow.account, flow: @flow, conversation: @conversation,
                                contact: @conversation.contact, flow_version: @flow.version, state: @payload)
  run.update!(status: :waiting, current_node_id: next_id, resume_at: resume_at)
  :suspended
end
def finish!; @run&.update!(status: :completed, current_node_id: nil, resume_at: nil); end
```

```ruby
# app/jobs/flows/resume_job.rb  🆕  (espelha MessageSequences::AdvanceJob)
class Flows::ResumeJob < ApplicationJob
  queue_as :scheduled_jobs
  def perform
    FlowRun.due.find_each do |run|
      Flows::RunnerService.new(resume_run: run).perform
    rescue StandardError => e
      Rails.logger.warn("Flows::ResumeJob run #{run.id} failed: #{e.message}")   # padrão sla_monitor_job.rb:13
    end
  end
end
```

```yaml
# config/schedule.yml — ao lado de message_sequences_advance_job (:37) e kanban_sla_monitor_job (:25)
flows_resume_job:   { cron: '*/1 * * * *',  class: 'Flows::ResumeJob',          queue: scheduled_jobs }
flows_schedule_job: { cron: '*/15 * * * *', class: 'Flows::ScheduleTriggerJob', queue: scheduled_jobs }
```

**Reentrância do resume — cópia do `with_lock` de `AdvanceService` (`advance_service.rb:14-16`):**

```ruby
def advance_locked
  @run.with_lock do
    next unless @run.waiting?                               # advance_service.rb:15
    next if @run.resume_at.nil? || @run.resume_at > Time.current  # advance_service.rb:16
    @run.update!(status: :running)
    perform_from_current_node
  end
end
```

**Drip = wait + send_template em loop.** Um drip WhatsApp é `send_template → wait(24h) → condition(can_reply?/opt-out) → send_template`. Cada `wait` cria/atualiza um `flow_run`; o `ResumeJob` retoma. Reusa o pipeline de `send_template` (§3) e o precedente `MessageSequences::AdvanceService#send_step` (`:36-46`) que já dispara template via `ScheduledMessages::CreateService` com `template_params`.

### 2.7 Mapeamento dos gatilhos

**(a) `conversation_event` (5 eventos) — reusa `AutomationRuleListener`.** O listener (`app/listeners/automation_rule_listener.rb`, registrado em `app/dispatchers/async_dispatcher.rb:13`) estende-se para, em paralelo às `AutomationRule` antigas, carregar `Flow`s com o mesmo cache de 2 min (`:67`):

```ruby
def current_account_flows(event_name, account)
  ids = Rails.cache.fetch("flows:#{account.id}:#{event_name}", expires_in: 2.minutes) do   # espelha :67
    account.flows.active.conversation_event.where("trigger_config->>'event_name' = ?", event_name).pluck(:id)
  end
  Flow.where(id: ids)
end
# após rodar as AutomationRules antigas:
current_account_flows(event_name, account).each do |flow|
  gate = OpenStruct.new(conditions: flow.trigger_config['conditions'], id: flow.id, account: account)
  next unless AutomationRules::ConditionsFilterService.new(gate, conversation, opts).perform
  Flows::RunnerService.new(flow: flow, conversation: conversation, trigger_payload: opts).perform
end
```

As guardas do listener (`performed_by_automation?` `:73`; `ignore_message_created_event?` `:82`, que checa `automation_rule_id` em `:85`) estendem-se para `flow_id` (§2.8).

**(b) `manual` (+ bulk) — copia `MacrosExecutionJob`.** `POST /api/v1/accounts/:id/flows/:id/execute { conversation_ids: [...] }` → `Flows::ExecutionJob.perform_later` → um `Flows::RunnerService` por conversa com `actor: user`.

**(c) `schedule` — copia `Kanban::SlaMonitorJob`.** Único gatilho time-based do código (`app/jobs/kanban/sla_monitor_job.rb`, cron `*/15` em `schedule.yml:25`). Cópia do padrão scan-com-marcador idempotente `custom_attributes["flow_#{id}"]` (espelha `kanban_auto_#{id}` em `:33`, marker `iso8601(6)` `:35`, `update_column` `:46`). Dois modos: cron absoluto e relativo a evento.

**(d) `keyword` — hook no `message_created`.** Após o match de flows de evento, no `message_created` (`:18`), checa keywords contra a mensagem **inbound** (cobre o opt-out "PARAR" do drip sem trigger novo no dispatcher).

**(e) `external_webhook` — endpoint inbound novo 🆕.** Único gatilho sem precedente (os webhooks atuais são **saída** fire-and-forget, `automation_rules/action_service.rb:38-41`). `POST /webhooks/flows/:token` (rota pública), resolve `flow` por token, resolve conversa por identifier do payload, `trigger_payload` entra em `flow_run.state` (variáveis `{{trigger.campo}}`). Dedupe por `state['idempotency_key']`.

### 2.8 Reentrância / loop-guard / idempotência (3 camadas, todas com precedente)

| Camada | Defesa | Precedente |
|---|---|---|
| **Anti-loop de mensagem** | mensagens do motor levam `content_attributes.flow_id`; listener ignora | generaliza `automation_rule_id` (`automation_rules/action_service.rb:46`, lido em `automation_rule_listener.rb:85`) |
| **Depth-guard entre flows** | `Current.flow_depth` + `MAX_DEPTH=3` (uma ação emite evento que dispara outro flow…) | cópia de `Current.funnel_automation_depth` (`lib/current.rb:14`) — adicionar `thread_mattr_accessor :flow_depth` e resetar em `Current.reset` (`:16-24`) |
| **Ciclo dentro do grafo** | `MAX_STEPS=100` no walker | novo, independente |
| **Dois ticks do ResumeJob no mesmo run** | `with_lock` + re-check `waiting?`/`resume_at` | `advance_service.rb:14-16` |
| **Runs duplicados (schedule/webhook) p/ mesmo contato** | índice único parcial `[flow_id, contact_id] WHERE status IN (0,1)` + rescue `RecordNotUnique` → no-op | `index_active_enrollment_per_sequence_conversation` (`schema.rb:1440`) + `EnrollService` rescue (`enroll_service.rb:30`) |
| **Schedule re-dispara a cada tick de 15 min** | marcador `flow_#{id}` em `custom_attributes` | `sla_monitor_job.rb:33-37` |
| **Nó de ação falha** | rescue+log por nó, nunca levanta + `flow_step_logs` | `automation_rules/action_service.rb:13-17` |

### 2.9 Diagrama textual (fluxo de execução)

```
                                  ┌─────────────────────────────────────────────┐
   GATILHOS                       │                MOTOR Flow                    │
 ─────────────                    │                                             │
 conversation.* ──► AutomationRuleListener (async_dispatcher.rb:13)             │
 message.created    │  cache 2min (:67) · performed_by_automation? (:73)        │
                    │  ignore_message_created_event? (:85 → +flow_id)           │
                    └──► ConditionsFilterService (:24)  ─┐                       │
                                                          │                      │
 manual/bulk ──► Flows::ExecutionJob (actor:user) ────────┤                      │
 schedule   ──► Flows::ScheduleTriggerJob (cron */15) ────┤   ┌──────────────────▼─────────────────┐
 keyword    ──► message_created hook ─────────────────────┼──►│      Flows::RunnerService          │
 webhook    ──► Webhooks::FlowsController (POST /:token) ──┘   │  walker: start → visit → next      │
                                                              │  depth-guard (Current.flow_depth)   │
                                                              │  MAX_STEPS=100                       │
                                                              └───┬───────────────┬────────────┬─────┘
                                                                  │ action        │ condition  │ wait
                                                                  ▼               ▼            ▼
                                              ┌─────────────────────────┐  branch      suspend!
                                              │  Flows::ActionService    │  true/false   │
                                              │  < ActionService         │  → next edge  ▼
                                              │  public_send(name,params)│           FlowRun(waiting,
                                              │  (action_service.rb:113) │            resume_at, state)
                                              └───────────┬──────────────┘               │
                                                          │ send_message/template/label/… │
                                                          ▼                               ▼
                                              Messages::MessageBuilder        Flows::ResumeJob (cron */1)
                                              (+content_attributes.flow_id)   with_lock (advance_service.rb:14)
                                                          │                               │
                                                          ▼                               ▼
                                              flow_step_logs (rastro)  ──►  Flows::StatsRollupJob ──► flow_node_stats
                                                                                                       (canvas lê 142·38%)
   COMPLIANCE (transversal): can_reply? (conversation.rb:187) · contact_flow_suppressions · WorkingHour#open_now? (:58)
```

### 2.10 O que fica separado de propósito: o Kanban

O motor Kanban (`FunnelAutomation` / `Kanban::SlaMonitorJob`) **permanece separado** — precisa de contexto `funnel_item` e das ações `move`/`enroll_in_sequence` que operam fora do escopo só-conversa. A convergência recomendada é **vocabulário de ações comum**: expor `move_funnel_stage` (via `app/services/funnel_items/move_service.rb` ✅) e `enroll_in_sequence` (via `MessageSequences::EnrollService` ✅) como nós `action` no Flow (F2), **mantendo o motor de trigger do Kanban intacto** e preservando seu `MAX_DEPTH` guard.

---

## 3. CATÁLOGO DE NÓS COMPLETO

**Convenção:** ✅ EXISTE (método+whitelist no código) · 🟡 PARCIAL (existe noutro motor, precisa exposição) · 🆕 NOVO. **Payload invariante:** `{ "action_name": String, "action_params": [ … ] }` (`action_params` sempre array; `params[0]` = valor). **Fases:** F1 (fusão + `send_template` + `set_attribute` na base) · F2 (gatilhos novos + vocabulário Kanban + scheduler/drip) · F3 (canvas/branching/IA/analytics).

### 3.1 Tabela mestra

| Nó | família | action/event_name | status | backend (arquivo:linha / serviço) | frontend inputType/widget | fase |
|---|---|---|:--:|---|---|:--:|
| Conversa criada | trigger | `conversation_created` | ✅ | `automation_rule_listener.rb` ← `conversation.created` | seletor evento + condições | F1 |
| Mensagem recebida | trigger | `message_created` | ✅ | listener `:18` | idem | F1 |
| Conversa atualizada | trigger | `conversation_updated` | ✅ | listener `:39` | idem | F1 |
| Conversa aberta | trigger | `conversation_opened` | ✅ | listener | idem | F1 |
| Conversa resolvida | trigger | `conversation_resolved` | ✅ | listener | idem | F1 |
| Agendado (cron/relativo) | trigger | `schedule` | 🆕 | `Flows::ScheduleTriggerJob` (molde: `sla_monitor_job.rb`) | `schedule_config` 🆕 | F3¹ |
| Palavra-chave | trigger | `keyword` | 🟡 | `message_created` + matcher | `keyword_list` 🆕 | F2 |
| Webhook externo | trigger | `external_webhook` | 🆕 | `Webhooks::FlowsController` (novo) | `webhook_endpoint` 🆕 | F3 |
| Condição (gate) | logic | `conditions` (no modelo) | ✅ | `conditions_filter_service.rb:24` | editor condições AND/OR | F1 |
| Roteador / branch | logic | `router` | 🆕 | motor nós+arestas (Runner §2.5) | `router` 🆕 (first-match) | F3 |
| Esperar / delay | logic | `wait` | 🆕 | scheduler + `flow_runs` (§2.6) | `wait_config` 🆕 | F3 |
| Enviar mensagem | msg | `send_message` | ✅ | override `Flows::ActionService` (§2.4) | `textarea` (WootMessageEditor) | F1 |
| **Enviar template** | msg | `send_template` | 🆕² | `Whatsapp::TemplateActionService` (novo) + método base; reusa `send_on_whatsapp_service.rb` / `template_processor_service.rb` ✅ | `whatsapp_template` 🆕 | **F1 (P0)** |
| WhatsApp Flow nativo | msg | `send_whatsapp_flow` | 🆕 | `MessageBuilder` interactive `flow` | `whatsapp_flow` 🆕 | F3 |
| Sequência / drip | msg | `enroll_in_sequence` | 🟡 | `MessageSequences::EnrollService` ✅ | `sequence_select` 🆕 | F2/F3³ |
| Nota interna | msg | `add_private_note` | ✅ | override (§2.4) | `textarea` | F1 |
| Enviar anexo | msg | `send_attachment` | ✅ | override (`@flow.files`) | `attachment` (AutomationFileInput) | F1 |
| CSAT / NPS | msg | `send_csat` | 🆕 | `MessageBuilder` content_type `input_csat` | `csat_config` 🆕 | F2 |
| Transferir p/ Captain | ai | `assign_ai_agent` | ✅ | `enterprise/action_service.rb:17` | `search_select` (assistants) | F1 |
| Classificar intenção | ai | `ai_classify` | 🆕 | `Captain::ClassifyService` (novo) → saída p/ router | `ai_classify` 🆕 | F3 |
| Gerar resposta | ai | `ai_generate` | 🆕 | Captain LLM → `MessageBuilder` (send/draft) | `ai_generate` 🆕 | F3 |
| Decidir rota | ai | `ai_decide_route` | 🆕 | LLM → escolhe branch | `ai_route` 🆕 | F3 |
| Atribuir agente | action | `assign_agent` | ✅ | `action_service.rb:43` | `search_select` | F1 |
| Atribuir time | action | `assign_team` | ✅ | `action_service.rb:62` | `search_select` | F1 |
| Remover time | action | `remove_assigned_team` | ✅⁴ | `action_service.rb:75` | `null` | F1 |
| Etiqueta (add) | action | `add_label` | ✅ | `action_service.rb:37` | `multi_select` | F1 |
| Etiqueta (remove) | action | `remove_label` | ✅ | `action_service.rb:55` | `multi_select` | F1 |
| Prioridade | action | `change_priority` | ✅ | `action_service.rb:33` (aceita `'nil'`) | `search_select` | F1 |
| Status (change/open/pending/resolve) | action | `change_status` / `*_conversation` | ✅ | `action_service.rb:17-31` (change_status `:29`) | `null`/`search_select` | F1 |
| Adiar (snooze) | action | `snooze_conversation` | ✅ | `action_service.rb:13` | `null` → duração 🆕 | F1 |
| Silenciar | action | `mute_conversation` | ✅ | `action_service.rb:9` | `null` | F1 |
| Aplicar SLA | action | `add_sla` | ✅ | `enterprise/action_service.rb:2` | `search_select` | F1 |
| Adicionar participante | action | `add_participant` | 🆕 | `conversation.conversation_participants.create` | `multi_select` (agents) | F2 |
| Mover no funil | action | `move_funnel_stage` | 🟡 | `funnel_items/move_service.rb` ✅ (injetar `funnel_item`) | `funnel_stage_select` 🆕 | F2 |
| Chamar Ação rápida (macro) | action | `call_macro` | 🆕 | invoca `Macros::ExecutionService` reentrante | `search_select` (macros) | F2 |
| Webhook (fire-and-forget) | action | `send_webhook_event` | ✅ | override (`WebhookJob`) | `url` | F1 |
| Webhook request-response | action | `http_request` | 🆕 | HTTP síncrono → mapeia resposta | `http_request` 🆕 | F3 |
| Definir/atualizar atributo | data | `set_attribute` | 🆕 | grava `additional_attributes`/`custom_attributes` | `attribute_kv` 🆕 | **F1** |
| Enviar transcript | data | `send_email_transcript` | ✅ | `action_service.rb:79` (rate-limited) | `email` | F1 |

¹ `schedule` cai em F3 pois depende do scheduler + estado (que também habilita `wait`). ² `send_template`: a **infra de envio existe**; falta o método na base + widget — por isso é F1 apesar do 🆕. ³ `enroll_in_sequence` existe no Kanban; full-feature WhatsApp depende de `send_template` (F1) + `wait`/`schedule` (F3). ⁴ `remove_assigned_team` só está na whitelist do macro hoje; normalizar para a automação fecha assimetria (F1).

### 3.2 Specs por família (o que muda de nível)

**Gatilhos.** Os 5 reativos: **nenhuma mudança de backend** — só surfaçar no seletor de gatilho. `schedule` precisa scheduler + marcador idempotente. `keyword`: matcher dedicado (lowercase/acentos, exact vs contains) antes das condições. `external_webhook`: endpoint + secret + `variable_mappings`.

**Lógica.** Condição: whitelist verificada em `conditions_filter_service.rb` (content, status, assignee_id, team_id, inbox_id, priority, labels, custom_attrs, +`sla_policy_id` enterprise). Dívida conhecida (dossiê §6): `city`/`company` na whitelist sem UI; `days_before` órfão. `router`: estratégia explícita `EXECUTE_FIRST_MATCH`. `wait`: **bloqueador estrutural nº1** — hoje `perform` roda tudo síncrono e imediato (`automation_rules/action_service.rb:9-18`, sem `perform_in`); precisa scheduler + checkpoint (`flow_runs`).

**Mensagens.** `send_message` **não entrega fora da janela 24h** → daí `send_template` (P0). Spec do `send_template` (dossiê §2.4):
```json
{ "action_name":"send_template", "action_params":[{
  "name":"tozi_lead_inicial", "language":"pt_BR",
  "processed_params":{ "body":{"1":"{{contact.name}}"},
    "header":{"media_url":"https://...","media_type":"image"},
    "buttons":[{"type":"url","parameter":"{{contact.id}}"}] } }] }
```
Guards: `whatsapp_cloud_inbox?`, `find_approved_template` (no-op silencioso, padrão `add_sla`); reusa `SendOnWhatsappService` → `TemplateProcessorService` (ambos ✅), **não fala com a Graph API**. Riscos: template desaprovado, variável vazia (fail-fast pré-Graph), MARKETING/spam, 360dialog vs Cloud (MVP só **Cloud**).

**IA / Captain.** `assign_ai_agent` ✅ (`enterprise/action_service.rb:17`) com guards próprias (`Current.skip_ai_agent_assignment` `:21`; `last_outgoing_by_human?` `:25/:51`; `mirror_agent_bot` `:32`; `Current.executed_by = assistant` `:45`). `ai_classify`/`ai_generate`/`ai_decide_route` 🆕: sem branching (F3) a saída da IA não tem para onde ir — por isso são F3.

**Ações.** Todas as ✅ da tabela herdam a base `ActionService`. `call_macro` 🆕 precisa guard de recursão (macro que chama macro) — espelhar depth. `move_funnel_stage` 🟡: `MoveService` existe mas o Kanban usa DSL própria; expor no `ActionService` comum exige injetar `funnel_item` (risco: rodar sem funil).

**Dados.** `set_attribute` 🆕 mas **sem infra nova** (grava `conversation.additional_attributes`/`custom_attributes`) → cabe em F1; habilita segmentar/ramificar/alimentar Kanban.

### 3.3 Custo de um nó novo (dossiê §1.7)

4 pontos: (a) método em `ActionService`/subclasse/enterprise; (b) whitelist do modelo (`macro.rb:33` `ACTIONS_ATTRS` / `automation_rule.rb:42` `actions_attributes`); (c) `AUTOMATION_ACTION_TYPES` + `AUTOMATIONS` (`constants.js:8`) + i18n; (d) `inputType` + widget em `AutomationActionInput.vue`. **Nós que herdam da base cobrem macro E automação num só método** (ex.: `send_template`, `set_attribute`).

---

## 4. ENROLLMENT / CONFORMIDADE / ANALYTICS

> **Descoberta que moldou a arquitetura (Relatório 5):** o motor de enrollment **já existe** — `MessageSequences::*` (migrations `20260625140000..140200`). Já modela instância-de-contato-no-fluxo, scheduler de 1 min, enrollment idempotente com índice único parcial + `rescue RecordNotUnique` (`enroll_service.rb:30`), `with_lock` anti-duplo-envio (`advance_service.rb:14`), e exit por reply/status (`ExitListener`). O design **generaliza** isso.

### 4.1 Entrada / reentrada / meta

- **Instância = `flow_runs`** (§2.1), generaliza `message_sequence_enrollments`.
- **Dedupe/suppression por `contact_id`** (não `conversation_id`) via índice único parcial `[flow_id, contact_id] WHERE status IN (0,1)`.
- **`reentry_policy`** ∈ `{ once, re_enroll, re_enroll_after(cooldown) }` (coluna em `flows`).
- **Meta de saída** = `goal_conditions` jsonb, avaliada por `Flows::GoalListener` 🆕 (cópia de `MessageSequences::ExitListener` ✅): respondeu / status / label / "comprou". Ao atingir a meta, o run vai a `completed` e para de reagendar.

### 4.2 Conformidade WhatsApp (§ crítico BR)

- **Opt-out** — keyword PARAR/STOP (gatilho `keyword`, §2.7) grava `contact_flow_suppressions(reason: opt_out, flow_id: nil)` → cancela todas as runs do contato + bloqueia admissão futura.
- **Cap diário de marketing** — contador materializado em `contact_flow_suppressions(reason: marketing_cap, expires_at: fim-do-dia)`, **só conta `category=MARKETING`**. Utility/authentication não contam.
- **Janela 24h automática** — no nó de envio: `Conversation#can_reply?` (`app/models/conversation.rb:187` → `Conversations::MessageWindowService#can_reply?` `:188`) decide **free-form vs template**. Não recalcula nada; 24h desde o último inbound.
- **Horário comercial** — timezone-aware via `WorkingHour#open_now?` (`app/models/working_hour.rb:58`) e o concern `app/models/concerns/out_of_offisable.rb` (incluído no Inbox) ⚠️ *(o método exato `Inbox#working_now?` citado no Relatório 5 não foi confirmado na verificação; `WorkingHour#open_now?` está confirmado)*. Aplica-se tanto na **admissão** quanto ao re-agendar `resume_at` no nó `wait` (se cair fora do horário, empurra para a próxima janela útil).

### 4.3 Logs & métricas

- **`flow_step_logs`** (§2.1): um registro por nó percorrido, com `branch_key`, `status`, `input`/`output`, `error_code`, `duration_ms`.
- **Métricas por ramo** (os `142·38%` do mockup): rollup incremental `flow_node_stats` via `Flows::StatsRollupJob` (UPSERT, reusa infra do `AdvanceJob`). **O canvas lê pré-agregado**, nunca `COUNT` ao vivo.
- **Retenção:** logs detalhados 30–90d; stats indefinido.

### 4.4 Observabilidade — `error_code` tipado

`template_not_approved` (`find_template` nil) · `empty_variable` (fail-fast pré-Graph) · `outside_window_no_template` · `cap_reached` · `unsupported_channel` · `guard_skipped` (`performed_by_automation`/depth). Best-effort herdado (`rescue` não derruba o fluxo) **mas agora deixa rastro**. Painel de saúde = `flow_step_logs WHERE status=failed GROUP BY error_code`.

---

## 5. FRONTEND (Vue 3)

### 5.1 O que JÁ existe e reusar (~70% da config de um nó)

| Arquivo | reuso |
|---|---|
| `.../settings/automation/Index.vue` | shell da listagem + CTA "Abrir no canvas" |
| `.../automation/AutomationRuleRow.vue` | linha (toggle/clone/delete) quase intacta |
| `.../automation/{Add,Edit}AutomationRule.vue` | padrão open/close/save a espelhar no `CanvasView` |
| `.../automation/AutomationRuleForm.vue` | **canibalizar** os blocos internos (Condições/Ações) para o `NodeConfigPanel` |
| `.../automation/constants.js` | `AUTOMATIONS` (`:8`), `AUTOMATION_ACTION_TYPES` → base do `NODE_CATALOG` |
| `.../automation/operators.js` | operadores das condições/roteador |
| `.../automation/automation.routes.js` | rota sob `SettingsWrapper`, `featureFlag: AUTOMATIONS` (`:23`), `permissions:['administrator']` (`:24`) |
| `composables/useAutomation.js`, `useAutomationValues.js` | motor de estado de UMA regra + fontes de dropdown |
| `helper/{automationHelper,actionQueryGenerator,filterQueryGenerator}.js` | serialização modelo↔payload (por-nó na F3) |
| `store/modules/automations.js` | coleção publicada (base do módulo novo) |
| `api/automation.js` | `ApiClient('automation_rules')` + clone |
| `components/widgets/AutomationActionInput.vue` ⚠️ | resolve `inputType`→widget; **é o corpo de cada nó de ação** |
| `components-next/filter/ConditionRow.vue` | corpo do nó Roteador/Condição |
| `components-next/whatsapp/WhatsAppTemplateParser.vue` | corpo do nó "Enviar template" |
| `.../settings/macros/{MacroEditor,MacroNodes,MacroNode}.vue` | **precedente de editor de nós verticais** — modelo mental do `FlowNode` |

> ⚠️ **Correções de honestidade na verificação:**
> - `AutomationActionInput.vue` está em `app/javascript/dashboard/components/widgets/AutomationActionInput.vue` (widget **compartilhado**), **não** sob `settings/automation/components/widgets/` como um relatório sugeriu.
> - A prop **`isMacro`** (citada como estando em `AutomationActionInput.vue:45-48`) **não foi encontrada** por grep em `settings/`. Tratar como não-confirmada: ler o componente na implementação para achar o mecanismo real de "modo embutido em nó".
> - `inputType` reais em `constants.js` incluem `search_select`, `multi_select`, `comma_separated_plain_text`, `plain_text` (não exatamente a lista `email/url/textarea/team_message` de um relatório). Ler `AUTOMATION_ACTION_TYPES` + `AutomationActionInput.vue` como fonte da verdade do mapeamento widget×inputType.

### 5.2 Renderer — Vue Flow (MIT), já pago

**Verificado:** `@vue-flow/core@^1.48.2` (`package.json:62`), `@vue-flow/background@^1.3.2` (`:60`), `@vue-flow/controls@^1.1.3` (`:61`) **já instalados** em `node_modules/@vue-flow/` (só core/background/controls), com **zero uso** no código. Construir do zero reintroduziria — com bugs — o que já está pago.

| Requisito | Vue Flow | como |
|---|---|---|
| Nós Vue custom | ✅ | `<template #node-{type}>` → 1 SFC por família |
| Arestas + branching | ✅ | `edges[]` + `sourceHandle`/`targetHandle`; aresta custom p/ o "+" e pills Sim/Senão |
| Zoom/pan/controles/fundo | ✅ | `useVueFlow()` + `@vue-flow/background` + `@vue-flow/controls` |
| **Minimapa** | ⚠️ falta | `@vue-flow/minimap` (MIT) **não instalado** → **@devops** `pnpm add @vue-flow/minimap` (ou minimapa custom do mockup) |
| **Auto-layout** | ⚠️ manual | começar **determinístico** (`y = depth*GAP`, `x = branch*COL`, zero deps); migrar p/ `@dagrejs/dagre` (MIT) só se ramos ficarem densos |

**Licenças:** Vue Flow + dagre = **MIT** ✅. Rejeitadas: n8n (fair-code), Typebot (FSL), Automatisch (**AGPL**).

### 5.3 Arquitetura de componentes

Diretório novo `.../settings/automation/canvas/` (convive com a listagem atual). Layout 3-painéis `252px | 1fr | 350px`.

```
CanvasView.vue                 # shell; topbar (nome/versão/toggle/Testar/Publicar); orquestra store editor
├─ NodePalette.vue             # 6 grupos-família + busca + drag-source
│   └─ PaletteChip.vue
├─ FlowCanvas.vue              # <VueFlow> + Background + Controls + MiniMap
│   ├─ FlowNode.vue            # base: moldura + faixa família + título/subtítulo + badge
│   │   ├─ TriggerNode.vue     # verde, 1/fluxo, sem entrada
│   │   ├─ MessageNode.vue     # send_message/template/whatsapp_flow/drip/note/csat
│   │   ├─ LogicNode.vue       # Router (multi-saída)/Wait
│   │   ├─ AiNode.vue          # classify/generate/route/handoff Captain
│   │   ├─ ActionNode.vue      # assign/label/priority/status/snooze/sla/move-funnel/call-macro/webhook
│   │   └─ DataNode.vue        # set-attribute/transcript
│   ├─ FlowEdge.vue            # aresta com "+" no meio + pill de rótulo (Sim/Senão/rota)
│   └─ CanvasControls.vue      # zoom/fit + MiniMap
├─ ConfigPanel.vue             # abas "Bloco" | "Fluxo"
│   ├─ NodeConfigPanel.vue     # <component :is> por tipo → config/*.vue (compõe widgets existentes)
│   │   ├─ config/TemplateConfig.vue  # reusa WhatsAppTemplateParser
│   │   ├─ config/MessageConfig.vue   # reusa WootMessageEditor
│   │   ├─ config/RouterConfig.vue    # reusa ConditionRow (first-match)
│   │   ├─ config/AiConfig.vue        # assistant + instrução + saídas→ramos
│   │   ├─ config/WaitConfig.vue      # duração / até responder / horário comercial
│   │   ├─ config/AssignConfig.vue    # reusa AutomationActionInput
│   │   └─ config/AttributeConfig.vue # where/attr/value
│   └─ FlowConfigPanel.vue     # enrollment/reentrada, meta, opt-out PARAR, cap/dia, janela comercial
├─ TemplatesGallery.vue        # modal "▦ Modelos"
├─ SimulationOverlay.vue       # "▶ Testar": 142·38% nos ramos (dry-run)
└─ RunLogs.vue                 # drawer: execuções recentes
```

`NODE_CATALOG` (novo `canvas/nodeCatalog.js`) estende `AUTOMATION_ACTION_TYPES` com metadados de nó: `{ type, family, icon, labelKey, inputType, handles, availability(ctx), configComponent }`. Famílias = `trigger/msg/logic/ai/action/data`. Cada nó só aparece na paleta conforme `availability` (mesmo padrão de filtro de `AutomationRuleForm.vue` para `add_sla`/`assign_ai_agent`).

### 5.4 Store — `store/modules/automationEditor.js` 🆕 (namespaced, ao lado de `automations.js`)

```js
state = {
  draft: null,        // { id, name, active, definition:{nodes,edges}, version, base_version }
  published: null,    // snapshot p/ diff/reverter
  versions: [],       // histórico
  selectedNodeId: null,
  history: { past: [], future: [] },   // undo/redo (structuredClone; fluxos são pequenos)
  simulation: null, runLogs: [],
  uiFlags: { isLoading, isSaving, isPublishing, isDirty },
}
```

- **Rascunho vs publicado** (padrão Intercom/HubSpot + badge "Rascunho·v3" do mockup): `definition` autocontido; autosave debounced (`PATCH .../draft`); "Publicar" cria nova `version` e copia draft→published.
- **Undo/redo** no módulo (Vue Flow só gere viewport): `commitChange(patch)` empilha snapshot; atalhos `Ctrl+Z`/`Ctrl+Shift+Z`.
- **Versões**: `base_version` grava para detecção de conflito (edição concorrente) — encaixa no **Almirante** (audit/rollback por VM, memória `project_almirante_mcp_ia`).
- **Compat retroativa**: `flatToDefinition(rule)` (regra plana → nós lineares) e o inverso `definitionToFlat` mantêm o backend atual na F1 antes do jsonb novo.
- **API** (estender `api/automation.js`): `getDraft/saveDraft/publish/getVersions/restoreVersion/simulate/getRunLogs`.

### 5.5 Rotas + i18n

- **Rotas** filhas de `settings/automation`, preservando `featureFlag: FEATURE_FLAGS.AUTOMATIONS` + `permissions:['administrator']` (`automation.routes.js:23-24`): `canvas/new` (`automation_canvas_new`), `canvas/:id` (`automation_canvas_edit`). ⚠️ **Verificar** como `SettingsWrapper.vue` restringe largura — o canvas é full-bleed; provavelmente rota irmã fora do wrapper estreito, mesmo grupo de permissão. Guard `beforeRouteLeave` quando `isDirty`.
- **i18n** (`i18n/locale/{en,pt_BR}/automation.json` ✅, **pt-BR prioritário**): reusar `AUTOMATION.*` e adicionar `AUTOMATION.CANVAS.*` (`PALETTE`, `NODES.{type}`, `CONFIG`, `FLOW`, `SIMULATION`, `VERSIONS`, `PUBLISH/DRAFT/TEST`). Ações herdam tradução via `AUTOMATION.ACTIONS.*`; só tipos novos precisam de chaves novas. **Nada hardcoded** — validar i18n leaks + light/dark com Playwright.

### 5.6 Camada de comandos nomeados (B1) — user e IA no mesmo trilho

Definir um conjunto fechado de comandos de canvas (`addNode(type, afterId)`, `connect(a,b)`, `setNodeParams(id,params)`, `addBranch(routerId, condition)`, `deleteNode(id)`, `wrapInWait(id, duration)`). **Humano** invoca via Cmd-K/paleta/`+`; **IA** invoca **os mesmos** via tool-calling. Toda edição da IA passa pelas mesmas whitelists (`macro.rb:33` / `automation_rule.rb:42`) → determinística e validável, em vez de regenerar JSON solto.

---

## 6. DESIGN SYSTEM + LISTA DE TELAS

> **O mockup atual `public/mockups/automacoes-canvas.html` é o design system canônico.** Todo HTML novo copia o bloco `:root` / `@media` / `[data-theme]` **verbatim**. Novos arquivos em `public/mockups/automacoes/`.

### 6.1 Tokens

**Neutros/superfície** (light → dark): `--bg` `#e9ecf7`/`#080a12` · `--surface` `#fff`/`#12141f` · `--surface-2` `#f6f7fc`/`#171a28` · `--glass` `rgba(255,255,255,.72)`/`rgba(20,23,37,.66)` · `--border` `#e2e5f1`/`#252a3d` · `--border-2` `#ccd1e6`/`#343a52`.

**Tinta:** `--ink` `#1a1d2e`/`#eaecf6` · `--ink-2` `#585d78`/`#a7acc7` · `--ink-3` `#8b90ab`/`#6d7291`.

**Marca (indigo):** `--accent` `#6366f1`/`#8286ff` · `--accent-2` `#4f46e5`/`#9a9dff` · `--accent-soft` `rgba(99,102,241,.12)`/`rgba(130,134,255,.14)` · `--wire` `#c6cbe0`/`#333952`.

**As 6 FAMÍLIAS** (espinha semântica — cada nó pertence a exatamente uma; cor entra em 5 pontos: barra lateral `::before` 3px, ícone `color-mix 15%`, tag `nf`, tick da paleta, note contextual):

| Família | token | light | dark |
|---|---|---|---|
| Gatilho | `--trigger` | `#0e9f6e` | `#34d399` |
| Mensagem | `--msg` | `#0f8a6f` | `#25d366` (**verde WhatsApp deliberado**) |
| Lógica | `--logic` | `#c77a06` | `#fbbf24` |
| IA · Captain | `--ai` | `#6f63e6` | `#a99bff` |
| Ação | `--action` | `#5b6478` | `#8b93aa` |
| Dados | `--data` | `#2563c9` | `#5b9bff` |

**Semânticos:** `--ok` `#15803d`/`#4ade80` (aprovado/meta/opt-out) · `--warn` `#c2410c`/`#fb923c` (rascunho/wait/remover). **Sombras:** `--shadow` (flutuantes), `--shadow-node` (cards) — sempre difusa e curta; dark com alfas mais fortes.

### 6.2 Tipografia

System fonts (`ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto…`), mono para variáveis/métricas (`tabular-nums`). Base **14px**/1.45. Título de painel 14.5px/680/-.01em; node title 13.5px/640; corpo 13px; subtítulo/meta 12–12.5px; **label 10.5–11px/700 UPPERCASE +.05–.09em**; tag família 9.5px/700. Padrão: label = uppercase + tracking positivo + `--ink-3`; título = tracking negativo + peso 640–680.

### 6.3 Componentes (reutilizar classes do mockup)

`.node` (272px, barra família, ícone 32px, `nf`; estados hover/`.selected`/`:focus-visible`; variante `.node.sm`) · `.chip` (paleta arrastável + badge `cx`) · `.link`+`.plus` / `.tree`/`.branch`/`.arrow` (conectores) · `.bpill` (`.yes`/`.wait` + `.bm` mono `142·38%`) · `.props` (`.ptabs` Bloco/Fluxo, `.ph`, `.pbody` `.field`s, `.pfoot`) · `.field`>`.flabel`+`.control` (`.control.pick`) · `.tag.ok` / `.ver` / `.cx` · `.toggle` / `.mini-toggle` · `.radio`>`.ropt` · **`.preview`>`.bubble`** (balão WhatsApp + `.var` + `.rbtn` — **widget-assinatura do template**) · `.vmap`>`.vrow` (`{{1}}→Nome`) · `.note` (colorida pela família) · overlays `.zoom`/`.minimap`/`.legend`/`.hint` · `.btn`(`.primary`/`.ghost`).

**Light/dark:** estratégia tripla obrigatória (`@media (prefers-color-scheme:dark)` + `:root[data-theme="dark"]` + `:root[data-theme="light"]`). Nunca cor fora de token (lição registrada: fallback escuro mascara bug). **Motion:** aurora 3 blobs blur(80px) `@keyframes d1/d2` (22–30s); node 140ms; respeitar `prefers-reduced-motion`. **Shell:** grid `252|1fr|350` × `58px topbar|1fr`; `≤1240px` colunas encolhem + minimap some; `≤720px` colunas viram sheets.

### 6.4 Lista de telas a desenhar (brief por tela)

**GRUPO A — núcleo (P0):**
- **A1 · `index.html`** — hub/listagem de todos os `Flow` (automação+macro unificados). Full-width: topbar glass + header ("Automações" + "＋ Nova automação" + ghost "▦ Modelos") + toolbar (tabs Todas·Ativas·Rascunhos·Manuais·Modelos + busca + filtro por gatilho/inbox) + linhas estilo `.node` (ícone família do gatilho, nome, subtítulo legível, pills status, mini-métricas mono 7d, `.mini-toggle`, menu `⋯`), coluna "tipo" (Evento/Manual/Agendado = `trigger_type`). Estados: populada (~8, incl. macro/agendada/rascunho), hover, vazio (E1).
- **A2 · `canvas.html`** — **o mockup atual (pronto)**, referência-mestre. Ajustes: estados extras como variações — nó com erro (borda `--warn` + "!"), nó desabilitado, conector "+" hover (menu inserção), drag de chip (drop-zone), "publicando".
- **A3 · `modelos.html`** — galeria de templates BR. Sidebar de categorias (Reengajamento·Boas-vindas·Triagem·CSAT·Cobrança·Drip·IA·Kanban) + grid de cards (miniatura do fluxo em mini-nodes, chips de família/canal, badge "oficial"/"popular", "Usar modelo"). Popular com: "Reengajar leads do anúncio", "Boas-vindas+catálogo", "Triagem por IA→time", "CSAT pós-resolução", "Drip 3 templates c/ opt-out", "Recuperação fora da janela 24h".

**GRUPO B — painéis de config de nó (P0/P1, variações do shell `.props`; 1 arquivo `paineis.html` via `data-panel`):**
- **B1 · Enviar template** (msg) — inbox `whatsapp_cloud` → template (+`.tag.ok` Aprovado) → **`.preview` balão** → **`.vmap`** → `.note` ok "entrega dentro e fora da janela 24h". *(nó-assinatura)*
- **B2 · IA·Captain** (ai) — assistente + instrução (textarea) + **saídas→ramos** (`.outs`) + toggle "usar saída da IA como condição".
- **B3 · Roteador/Condição** (logic) — avaliar (atributo OU saída IA) + rotas first-match + "＋ rota".
- **B4 · Wait** (logic) — duração / "até responder" / "respeitar horário comercial" + `.note` âmbar "pausa e retoma sozinha".
- **B5 · Definir atributo** (data) — onde (Conversa/Contato) + atributo + valor (`{{var}}`) + `.note` azul.
- **B6 · CSAT/NPS** (msg) — tipo + canal + momento + agradecimento + preview rating.
- **B7 · Sequência/drip** (msg) — passos ordenados (template+delay) + opt-out + `.note` "cada passo fora da janela = template aprovado".
- **B8 · Mover no funil** (action) — funil + estágio + "atribuir ao mover" + badge "kanban".
- **B9 · Chamar macro** (action) — macro + preview read-only das ações.
- **+** ações simples (assign/label/priority/status/snooze/sla/participante/webhook/transcript) — 1–2 `.control.pick`, sem preview.
- Estados por painel: preenchido / vazio / erro (`--warn`) / template desaprovado (tag "Pendente") / guard bloqueado (CTA "conectar WhatsApp").

**GRUPO C — config/observabilidade/simulação (P1):**
- **C1 · Config do fluxo** (aba "Fluxo", já no mockup) — entrada/reentrada (`.ropt`), meta de saída, conformidade (opt-out PARAR + cap marketing/dia), janela comercial, `.note` "protege o quality rating".
- **C2 · `logs.html`** — auditoria "por que disparou/não". Tabela (timestamp mono, contato, gatilho, status ✓/⏱/✗/⊘, duração, nó onde parou) + detalhe lateral (timeline `.spine` em miniatura, payload por nó, motivo da falha: "template não aprovado→find_template nil", "fora da janela 24h", "guard performed_by_automation"). Estados: populada, filtro vazio, vazio (E2), em andamento (spinner).
- **C3 · `simulacao.html`** — "▶ Testar" **dry-run, nunca dispara IA/msg real**. Canvas em modo simulação: escolher conversa-amostra → "Executar passo"; nó acende (ring pulsante), painel vira console (entrada→saída, variáveis resolvidas `{{contact.name}}→Maria`), `.bpill` ganham número, roteador destaca rota, wait mostra "pularia 2h (simulado)", badge "modo simulação · nada foi enviado".

**GRUPO D — responsivo (P2):** D1 index mobile (cards 1col, filtros bottom-sheet, FAB); D2 canvas mobile (visualização pan/zoom, paleta/props viram sheets, editar 1 nó/vez; edição pesada = desktop).

**GRUPO E — vazios (P1, 1 arquivo `vazios.html`):** E1 sem automações (2 CTAs + 3 chips-sugestão) · E2 sem execuções (link p/ C3) · E3 paleta/busca sem resultado · E4 canvas em branco (só "Escolher gatilho" + "+" pulsante) · E5 guard/indisponível (CTA configurar).

**Invariantes de build:** (1) tokens verbatim; (2) toda cor via token, validar light+dark; (3) cada bloco = 1 das 6 famílias nos 5 pontos; (4) `send_template` sempre com `.preview`+`.vmap`+`.note` 24h; (5) self-contained (sem web-font/asset externo).

**Agrupamento de arquivos** (`public/mockups/automacoes/`): `index.html`, `canvas.html`, `modelos.html`, `paineis.html`, `logs.html`, `simulacao.html`, `vazios.html`. Responsivo = media queries, não arquivos novos.

---

## 7. BACKLOG FASEADO

Esforço: **P** (≤1 dia) · **M** (2–4 dias) · **G** (1–2 semanas). Cada história cita dependências e riscos.

### FASE 1 — Fusão + fundamentos (baixo risco, sem canvas 2D)

> **Meta:** um só motor `Flow` executando o que hoje Macro+AutomationRule fazem, + `send_template` + `set_attribute`, + normalizar assimetrias. Canvas abre regras como **fluxo linear** (read+edit) reusando composables/inputs atuais. **Sem** wait/router/IA-nós.

**Épico F1.1 — Modelo + fusão de motor**
| História | esforço | dep | risco |
|---|---|---|---|
| Migration `flows` + `Flow` model (enums, `include_mod_with`, `has_many_attached :files`) | M | — | baixo |
| `Flows::ActionService` (funde os 2 overrides §2.4) + testes de paridade (autoria/anti-loop) | M | model | **médio** (autoria condicional) |
| `Flows::RunnerService` walker linear (sem wait) + `MAX_STEPS` | M | ActionService | baixo |
| Backfill idempotente `automation_rules`+`macros` → `flows` (read-only nas antigas) | G | model | **alto** (paridade de dados — R-3) |
| Estender `AutomationRuleListener` p/ carregar `Flow`s (cache 2min) + guards `flow_id` | M | Runner | **médio** (dupla-execução durante transição — R-1) |
| `Flows::ExecutionJob` (manual/bulk) + controller `execute` | P | Runner | baixo |
| `Current.flow_depth` (cópia de `funnel_automation_depth`) + reset | P | — | baixo |

**Épico F1.2 — `send_template` (P0, gap-BR)**
| História | esforço | dep | risco |
|---|---|---|---|
| Método `send_template` na base `ActionService` + `Whatsapp::TemplateActionService` (reusa `send_on_whatsapp_service.rb`/`template_processor_service.rb`) | G | — | **alto** (Graph/janela) |
| Guards: `whatsapp_cloud_inbox?`, `find_approved_template` (no-op silencioso), `empty_variable` fail-fast | M | método | médio |
| Whitelist nos modelos (`ACTIONS_ATTRS`/`actions_attributes`) + i18n | P | método | baixo |
| Widget `whatsapp_template` (reusa `WhatsAppTemplateParser.vue`) + guard de disponibilidade | M | — | médio |

**Épico F1.3 — `set_attribute` + normalizar assimetrias**
| História | esforço | dep | risco |
|---|---|---|---|
| `set_attribute` (grava `additional_attributes`/`custom_attributes`, aceita Liquid) + widget `attribute_kv` | M | — | baixo |
| Normalizar `remove_assigned_team`/`open_conversation`/`pending_conversation` na automação (fechar assimetria macro×automação) | P | — | baixo |
| `snooze` com duração opcional | P | — | baixo |

**Épico F1.4 — Canvas MVP (linear, read+edit)**
| História | esforço | dep | risco |
|---|---|---|---|
| `CanvasView` shell 3-painéis + Vue Flow (`@vue-flow/*`) + Background/Controls | M | — | baixo (lib pronta) |
| `flatToDefinition`/`definitionToFlat` (regra plana ↔ nós lineares) | M | — | médio |
| `FlowNode` base + 6 variantes de família + `NodePalette` | G | shell | médio |
| `NodeConfigPanel` dinâmico (compõe widgets existentes) | G | FlowNode | médio |
| `store/modules/automationEditor.js` (draft/undo/dirty) + rotas canvas + i18n `CANVAS.*` | M | shell | médio |
| `@vue-flow/minimap` add (**@devops**) OU minimapa custom | P | — | baixo |

**Riscos F1:** R-1 (dupla-execução na transição), R-3 (paridade do backfill), R-5 (`send_template` janela/aprovação). Mitigação: feature flag `flows_v2` por conta; dry-run do backfill com diff.

### FASE 2 — Gatilhos novos + scheduler/drip + vocabulário Kanban + logs

> **Meta:** trazer os gatilhos que não dependem de branching, o estado entre execuções (habilita drip), o vocabulário compartilhado com Kanban, e a observabilidade.

**Épico F2.1 — Estado + scheduler**
| História | esforço | dep | risco |
|---|---|---|---|
| Migration `flow_runs` (cópia de `message_sequence_enrollments`) + `FlowRun` (`due`, índice único parcial) | M | F1 | baixo (precedente exato) |
| `wait` no Runner (`suspend!`/`finish!`) + `Flows::ResumeJob` (cron `*/1`) + `with_lock` reentrante | G | flow_runs | **médio** (reentrância) |
| Nó `wait` + widget `wait_config` (duração/até responder/horário comercial) | M | ResumeJob | médio |

**Épico F2.2 — Gatilhos**
| História | esforço | dep | risco |
|---|---|---|---|
| `keyword` (matcher no `message_created` + widget `keyword_list`) | M | F1 | baixo |
| `schedule` (`Flows::ScheduleTriggerJob`, cópia `SlaMonitorJob`, marcador idempotente) + widget | G | scheduler | médio |
| `external_webhook` (`Webhooks::FlowsController` público + token + dedupe) + widget `webhook_endpoint` | G | — | **alto** (endpoint público) |

**Épico F2.3 — Vocabulário Kanban + macro-como-ação**
| História | esforço | dep | risco |
|---|---|---|---|
| `move_funnel_stage` (expor `funnel_items/move_service.rb`, injetar `funnel_item`) | M | — | **alto** (rodar sem funil) |
| `enroll_in_sequence` (expor `MessageSequences::EnrollService`) | M | — | médio |
| `call_macro` (invoca `Macros::ExecutionService` reentrante) + guard recursão | M | depth-guard | médio |
| `add_participant` · `send_csat` (content_type `input_csat`) | M | — | baixo |

**Épico F2.4 — Enrollment/compliance/logs**
| História | esforço | dep | risco |
|---|---|---|---|
| `reentry_policy` + `goal_conditions` + `Flows::GoalListener` (cópia `ExitListener`) | M | flow_runs | médio |
| `contact_flow_suppressions` (opt-out PARAR + cap marketing/dia) | G | keyword | **alto** (compliance) |
| Janela 24h no nó de envio (`can_reply?`) + horário comercial no `wait` (`WorkingHour#open_now?`) | M | wait | médio |
| `flow_step_logs` + tela `logs.html` (C2) | G | Runner | médio |
| Drip = wait+send_template (loop) usando o pipeline de F1.2 | M | wait+template | médio |

**Riscos F2:** R-2 (endpoint público de webhook — abuso/DoS/auth), R-4 (`move_funnel_stage` sem contexto de funil), R-6 (compliance: cap/opt-out corretos por categoria de template).

### FASE 3 — Canvas completo: branching + IA + simulação + analytics

> **Meta:** o mockup `automacoes-canvas.html` vira produto real — Router, nós de IA, simulação dry-run, WhatsApp Flow, analytics por ramo.

**Épico F3.1 — Branching**
| História | esforço | dep | risco |
|---|---|---|---|
| Modelo nós+arestas com branch no `definition` + Router no Runner (`EXECUTE_FIRST_MATCH`) | G | F2 | **médio** |
| `RouterConfig.vue` (rotas ordenadas + fallback) + `FlowEdge` com pills | M | Router | médio |
| Undo/redo + versões + conflito (`base_version`) no editor | M | store | médio |

**Épico F3.2 — IA como nó (Captain)**
| História | esforço | dep | risco |
|---|---|---|---|
| `ai_classify` (`Captain::ClassifyService`) → saída p/ router | G | Router | **alto** (LLM) |
| `ai_generate` (send/draft) · `ai_decide_route` | G | Router | alto |
| Camada de comandos nomeados (B1) + co-piloto peer + variantes ghost (B3) | G | canvas | alto |
| "Gerar fluxo por frase" (B2, emite DSL constrangido) | G | comandos | **alto** |

**Épico F3.3 — Simulação + analytics + WhatsApp Flow**
| História | esforço | dep | risco |
|---|---|---|---|
| `SimulationOverlay` dry-run (nunca dispara real) + console lateral | G | branching | **alto** (fidelidade dry-run) |
| `flow_node_stats` + `Flows::StatsRollupJob` + pills `142·38%` lendo pré-agregado | M | logs | médio |
| `send_whatsapp_flow` (interactive `flow`) + widget | M | — | médio |
| `http_request` síncrono (mapeia resposta→variáveis) | M | — | médio |
| Galeria `modelos.html` (A3) + telas vazias (E) + responsivo (D) | M | — | baixo |

**Riscos F3:** R-7 (IA emite fluxo fora da whitelist — mitigado por comandos nomeados), R-8 (dry-run que "vaza" para produção — mitigado por dry_run estrito, memória `feedback_subagents_nao_tocam_producao`), R-9 (custo/latência LLM em nós de IA).

---

## 8. RISCOS & DECISÕES ABERTAS

### 8.1 Registro de riscos

| ID | Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|---|
| **R-1** | Dupla-execução na transição (motor antigo + novo rodam a mesma regra) | Alta | Alto | Feature flag `flows_v2` por conta; durante backfill, **desligar** a regra antiga ao ligar o Flow equivalente; guards checam `automation_rule_id` **e** `flow_id` |
| **R-2** | Endpoint público `POST /webhooks/flows/:token` — abuso/DoS/replay | Média | Alto | Token secreto forte + rate-limit + dedupe por `idempotency_key` + payload size cap; sem precedente no código → revisão de segurança dedicada |
| **R-3** | Backfill Macro/AutomationRule → Flow perde paridade (files, visibility, ordem de ações) | Média | Alto | Dry-run com diff nó-a-nó; manter tabelas antigas read-only; rollback = desligar flag |
| **R-4** | `move_funnel_stage` roda sem `funnel_item` (conversa fora de qualquer funil) | Média | Médio | No-op silencioso se sem funil; injetar contexto explícito; preservar `MAX_DEPTH` |
| **R-5** | `send_template`: template desaprovado / variável vazia / MARKETING como spam | Alta | Alto | `find_approved_template` no-op; `empty_variable` fail-fast pré-Graph; cap marketing/dia; MVP só Cloud (não 360dialog) |
| **R-6** | Cap de marketing / opt-out contam categoria errada → bloqueia utility ou deixa passar marketing | Média | Alto | Contador só `category=MARKETING`; opt-out global bloqueia admissão; testes por categoria |
| **R-7** | IA gera fluxo com ação fora da whitelist | Baixa | Médio | Camada de comandos nomeados (B1) — IA usa os mesmos comandos validados do usuário |
| **R-8** | Dry-run da simulação dispara IA/mensagem real | Baixa | Alto | `dry_run` estrito; simulação nunca instancia `MessageBuilder` real (memória incidente Clara 30/jun) |
| **R-9** | Reentrância: `wait`/`ResumeJob` duplo-envio; ciclo no grafo | Média | Médio | `with_lock`+re-check (`advance_service.rb:14`); índice único parcial; `MAX_STEPS`/`MAX_DEPTH` |
| **R-10** | `SettingsWrapper` estreito quebra o canvas full-bleed | Baixa | Baixo | Rota irmã fora do wrapper / `meta.fullWidth` — **verificar antes** |
| **R-11** | Vite/OOM ao buildar o canvas (memória `reference_vite_precompile_oom`) | Média | Médio | `NODE_OPTIONS=--max-old-space-size=8192`; checar manifest mtime |

### 8.2 Decisões abertas (precisam de humano — C4 human-in-the-loop)

1. **Cutover:** big-bang vs conta-a-conta com flag `flows_v2`? → **Recomendação:** flag por conta, coexistência. *(Impacto: R-1, R-3.)*
2. **`conversation_id` vs `contact_id` para dedupe/suppression:** o Relatório 5 recomenda `contact_id` (WhatsApp abre conversa nova por janela). `flow_runs` carrega ambos; **confirmar** que o índice único usa `contact_id`. → **Recomendação:** `contact_id`.
3. **Minimapa:** `@vue-flow/minimap` (dep MIT nova, **@devops**) vs custom do mockup? → **Recomendação:** instalar a lib.
4. **Auto-layout:** determinístico próprio vs `@dagrejs/dagre`? → **Recomendação:** determinístico no MVP.
5. **Duck-type vs refactor** do `ConditionsFilterService` (`OpenStruct` vs extrair `ConditionsEvaluator`)? → **Recomendação:** duck-type agora, refactor P quando estabilizar.
6. **Kanban:** manter separado (só vocabulário comum) — **confirmado** neste plano; reavaliar em F3+.
7. **Provedor WhatsApp:** MVP só **Cloud API**; 360dialog fica para depois. **Confirmar** com produto.
8. **Nós de IA — modelo/custo/latência:** qual assistant/limite por conta? Precisa política (R-9). Governança no **Almirante** (memória `project_almirante_mcp_ia`).

---

## Apêndice A — Precedentes reutilizados (verificados na consolidação)

| Precedente | arquivo:linha | usado em |
|---|---|---|
| Dispatch `send(action_name, action_params)` + base herdada | `app/services/action_service.rb:113`; `automation_rules/action_service.rb:14`; `macros/execution_service.rb:15` | §2.4/§2.5 |
| Métodos de ação base | `action_service.rb` mute:9 snooze:13 resolve:17 open:21 pending:25 change_status:29 change_priority:33 add_label:37 assign_agent:43 remove_label:55 assign_team:62 remove_assigned_team:75 send_email_transcript:79 | §3.1 |
| Contexto de execução | `automation_rules/action_service.rb:6` (`executed_by`); `macros/execution_service.rb:7` (`user`) | §2.4 |
| `assign_agent 'self'` | `macros/execution_service.rb:31-34` | §2.4 |
| Anti-loop `automation_rule_id` | `automation_rules/action_service.rb:46`; lido em `automation_rule_listener.rb:85` | §2.8 |
| Listener + cache 2min + guards | `automation_rule_listener.rb` message_created:18 process_conversation_event:39 performed_by_automation?:73 cache:67 ignore_message_created_event?:82; dispatch `async_dispatcher.rb:13` | §2.7 |
| Avaliação de condição | `automation_rules/conditions_filter_service.rb:24` (perform), `:29` (conditions), `:48` (authorization_error!) | §2.5 |
| Enterprise actions | `enterprise/app/services/enterprise/action_service.rb:2` (add_sla), `:17` (assign_ai_agent, guards :21/:25/:32/:45) | §3.2 |
| Drip state-machine (molde de `flow_runs`) | `db/schema.rb:1430` (enrollments), `:1440` (índice único parcial), `:1442` ([status,next_run_at]); `advance_service.rb:14-16` (with_lock); `enroll_service.rb:30` (RecordNotUnique); `AdvanceJob` cron `*/1` `schedule.yml:37` | §2.6/§4 |
| Scheduler time-based (molde de `ScheduleTriggerJob`) | `kanban/sla_monitor_job.rb` perform:10 marcador:33 marker:35 update_column:46; cron `*/15` `schedule.yml:25` | §2.7 |
| Depth-guard | `lib/current.rb:14` (`funnel_automation_depth`), reset `:16-24` | §2.8 |
| Modelos + whitelists | `macro.rb:33` (ACTIONS_ATTRS, inclui `assign_ai_agent`), `:29` (visibility), `:78` (include_mod_with); `automation_rule.rb:10` (event_name), `:42` (actions_attributes), `:108` (include_mod_with) | §2.1/§3.3 |
| Janela 24h + horário comercial | `conversation.rb:187-188` (`can_reply?`→`MessageWindowService`); `working_hour.rb:58` (`open_now?`); `concerns/out_of_offisable.rb` | §4.2 |
| Pipeline template (envio) | `whatsapp/send_on_whatsapp_service.rb`; `whatsapp/template_processor_service.rb` | §3.2 |
| Funil / Captain / sequences | `funnel_items/move_service.rb`; `enterprise/app/models/captain/assistant.rb`; `message_sequences/{enroll,advance,cancel}_service.rb`, `exit_listener.rb` | §2.10/§3 |
| Frontend renderer | `package.json:60-62` (`@vue-flow/*` MIT, instalado, zero uso) | §5.2 |
| Frontend anchors | `.../settings/automation/{Index,AddAutomationRule,EditAutomationRule,AutomationRuleForm,AutomationRuleRow}.vue`, `{constants(AUTOMATIONS:8),operators,automation.routes(featureFlag:23,permissions:24)}.js`; `components/widgets/AutomationActionInput.vue`; `components-next/{filter/ConditionRow,whatsapp/WhatsAppTemplateParser}.vue`; `store/modules/automations.js`; `api/automation.js`; `settings/macros/{MacroEditor,MacroNodes,MacroNode}.vue`; `i18n/locale/{en,pt_BR}/automation.json` | §5 |

## Apêndice B — Honesty ledger (incertezas marcadas)

- ⚠️ **`isMacro` prop** em `AutomationActionInput.vue` — grep em `settings/` **não encontrou** `isMacro`. Ler o componente na implementação para o mecanismo real de "modo embutido em nó".
- ⚠️ **`inputType` vocabulary** — `constants.js` mostra `search_select`/`multi_select`/`comma_separated_plain_text`/`plain_text` (diverge da lista `email/url/textarea/team_message` de um relatório). Fonte da verdade = `AUTOMATION_ACTION_TYPES` + `AutomationActionInput.vue`.
- ⚠️ **`Inbox#working_now?`** — não confirmado; `WorkingHour#open_now?` (`:58`) e o concern `out_of_offisable.rb` **confirmados**. Ler a cadeia de horário comercial do Inbox na implementação.
- ⚠️ **`SettingsWrapper` largura** — verificar se restringe o canvas full-bleed antes de decidir a rota (R-10).
- 🆕 **Sem precedente direto:** `external_webhook`/`http_request` (endpoints/HTTP síncrono) e o `flow_step_logs` (rastro). São os gaps que exigem construção nova + revisão de segurança.
- **Licenças:** ProductCanvas/MagicModules/AtQ = **Apache-2.0** (código reutilizável); Vue Flow + dagre = **MIT**; **MoMoA/MoMoA-Researcher sem licença** → só método, nunca copiar código.
- **Drift de linha corrigido:** referências que divergiram dos relatórios foram substituídas pelos números **verificados** (ex.: `change_status` em `:29`; `funnel_automation_depth` em `:14`).

---

*Fim do Plano Mestre. Fontes Google preservadas em §1.3. Documento aterrado em `arquivo:linha` verificados; incertezas marcadas ⚠️; nada inventado sem o marcador 🆕.*
