Conflict resolved via primary source. The base `ActionService.include_mod_with('ActionService')` (action_service.rb:113) mixes the enterprise module into the **base** class, and `enterprise/app/models/enterprise/automation_rule.rb` whitelists `%w[add_sla assign_ai_agent]`. So Relatório 2's claim that `assign_ai_agent` is macro-only is **wrong** — it's shared. I'll correct this in the dossier. Here is the consolidated dossier.

---

# DOSSIÊ — Unificar Automações + Macros no ChatSPX (fork Chatwoot, Rails 7.1 + Vue 3)

> Consolidação de 6 relatórios (3 de leitura do nosso código, 3 de pesquisa web). Mercado-alvo: BR, WhatsApp-heavy. Regra de honestidade: fatos triangulados por ≥2 relatórios são apresentados como certos; claims de fonte única ou não-confirmados vêm marcados **[1 fonte]**; conflitos entre relatórios estão sinalizados e, quando resolvíveis por leitura de código, foram verificados na fonte (marcados **[verificado]**).

---

## 1. ESTADO ATUAL DO NOSSO CÓDIGO

Existem **três** sistemas de "regra" hoje, e não dois:

| Sistema | Modelo | Arquivo | Disparo |
|---|---|---|---|
| **Automação-Conversa** | `AutomationRule` | `app/models/automation_rule.rb` | evento de conversa/mensagem (reativo) |
| **Macro** | `Macro` | `app/models/macro.rb` | manual (1 clique / bulk) |
| **Automação-Kanban** | `FunnelAutomation` | `app/models/funnel_automation.rb` | evento de card + agendado |

### 1.1 O FATO-CHAVE: Automação-Conversa e Macro compartilham `ActionService`

`Macros::ExecutionService < ActionService` (`app/services/macros/execution_service.rb:1`) e `AutomationRules::ActionService < ActionService` (`app/services/automation_rules/action_service.rb:1`) **herdam a mesma base** `app/services/action_service.rb`. Ambos executam ações via o mesmo dispatch `send(action[:action_name], action[:action_params])` (execution_service.rb:15 / automation_rules/action_service.rb:14), com `rescue` por ação. Usam **o mesmo formato de ação**: `{action_name, action_params}`, `action_params` sempre array. **[verificado]**

A **Automação-Kanban NÃO usa `ActionService`** — é um motor paralelo (`Kanban::AutomationEngineService`) que orquestra serviços de alto nível. Detalhe em §1.6.

Consequência: Macro é, na prática, **uma automação sem trigger e sem condições**, disparada manualmente. Essa é a base de toda a discussão de unificação (§5).

### 1.2 Schema da `AutomationRule` **[verificado]**

`automation_rules`: `id`, `account_id`, `name` (NOT NULL), `description` (text), `event_name` (string NOT NULL — **o gatilho, 1 evento por regra**), `conditions` (jsonb NOT NULL), `actions` (jsonb NOT NULL), `active` (bool default true), `files` (ActiveStorage `has_many_attached`, automation_rule.rb:25).

- **Item de condição:** `{ "attribute_key", "filter_operator", "values":[...], "query_operator": "and|or|null", "custom_attribute_type":"" }`. O `query_operator` encadeia com a **próxima** condição; a última é `null` (validação em automation_rule.rb:82-105 — `query_operator_presence` exige que só uma condição tenha operador nulo).
- **Item de ação:** `{ "action_name", "action_params": [<valor>] }`.
- Validações: `json_conditions_format` (automation_rule.rb:64-71) e `json_actions_format` (:73-80) rejeitam qualquer chave fora das whitelists. `after_update_commit :reauthorized!` quando conditions mudam (:33). Enterprise via `AutomationRule.prepend_mod_with('AutomationRule')` (:109).

**Schema do `Macro`** (macro.rb): `actions` (jsonb, lista **ordenada**), `name`, `visibility` (enum `personal:0`/`global:1`, :29), `created_by_id`/`updated_by_id`, `files` (:27). **Sem `event_name`, sem `conditions`.** **[verificado]**

### 1.3 Paleta de GATILHOS (triggers)

**Automação-Conversa — 5 eventos**, tratados em `app/listeners/automation_rule_listener.rb`, registrados em `app/dispatchers/async_dispatcher.rb:13` (assíncrono via Sidekiq), cacheados por `account:event` por 2 min (listener :65-71):

| `event_name` | evento de sistema (`lib/events/types.rb`) |
|---|---|
| `conversation_created` | `conversation.created` |
| `conversation_updated` | `conversation.updated` (types.rb:18) |
| `conversation_opened` | `conversation.opened` (types.rb:22) |
| `conversation_resolved` | `conversation.resolved` (types.rb:23) |
| `message_created` | `message.created` (types.rb:40) |

Guardas de reentrância (relevantes para "por que não dispara"): `performed_by_automation?` ignora eventos gerados por outra regra (listener :73-75); `conversation_created`/`opened` pulam quando `additional_attributes['auto_reply']` presente (:42-43,77-80); `message_created` ignora atividades, auto-reply e mensagens que a própria automação criou (:82-86).

**Macro — nenhum gatilho.** Disparo imperativo: `POST .../macros/:id/execute` com `conversation_ids[]` (`macros_controller.rb:48-52`) → `MacrosExecutionJob` (`app/jobs/macros_execution_job.rb:4-16`) → `Macros::ExecutionService` **por conversa**. É o caminho de **bulk** (N conversas) e do botão único (array de 1). Roda em `Current.user = user` (execution_service.rb:7) — por isso `assign_agent` suporta `'self'`.

**Automação-Kanban — 2 eventos próprios:** `item_entered_stage` e `time_in_stage` (`funnel_automation.rb:20`, `EVENTS`). O `time_in_stage` é **agendado** via `Kanban::SlaMonitorJob` (`app/jobs/kanban/sla_monitor_job.rb:39`) — é o **único gatilho time-based que existe no código**.

> **Não existe gatilho agendado/cron para Automação-Conversa nem Macro.** Todos os 5 gatilhos de conversa são reativos. (Nota: existe `OPERATOR_TYPES_5` com `days_before` em `operators.js` e `attribute_changed` em `conditions_filter_service.rb:30`, mas nenhum agendador periódico os dispara no contexto de automation — `days_before` é **órfão**. **[1 fonte: Relatório 1]**)

### 1.4 Paleta de CONDIÇÕES (só Automação-Conversa e Kanban têm)

Whitelist backend Automação-Conversa (`automation_rule.rb:37-40`) **[verificado]**:
`content, email, country_code, status, message_type, browser_language, assignee_id, team_id, referer, city, company, inbox_id, mail_subject, phone_number, priority, conversation_language, labels`
+ enterprise `sla_policy_id` (`enterprise/app/models/enterprise/automation_rule.rb`, `conditions_attributes` → `super + %w[sla_policy_id]`) **[verificado]**
+ qualquer `custom_attribute_definition` da conta (automation_rule.rb:69).

- **`city` e `company` estão na whitelist backend mas não têm UI no front** (constants.js) → condições mortas. **[1 fonte: Relatório 1]** (a presença na whitelist está **[verificado]**; a ausência no front é claim de fonte única.)
- Front expõe subconjunto por evento (matriz completa condição×evento em Relatório 1). Operadores: `OPERATOR_TYPES_1..6` (equal_to, not_equal_to, contains, is_present, is_greater/less_than, starts_with p/ phone_number, days_before órfão).
- Avaliação: `AutomationRules::ConditionsFilterService < FilterService` converte as condições em **uma query SQL** contra `Conversation.where(id: conv.id)` e checa `.any?` (conditions_filter_service.rb:24-43). Ou seja: "esta conversa bate no filtro?". `attribute_changed` (from→to) é processado em memória (:79-108).

Whitelist Kanban (DSL **diferente**): `{field, op, value}`, ops `eq/neq/present/blank/includes`, apenas 5 campos: `priority/status/assignee_id/inbox_id/labels` (`automation_engine_service.rb:54-75`).

**Macro não tem condições.**

### 1.5 Paleta de AÇÕES (a mais importante para unificação)

Tabela consolidada e **verificada nas whitelists reais** (`macro.rb:33-35`, `automation_rule.rb:42-45`, enterprise automation_rule.rb, base `action_service.rb`):

| `action_name` | Método (arquivo) | Macro? | Automação? | Notas |
|---|---|:-:|:-:|---|
| mute_conversation | action_service.rb:9 | ✅ | ✅ | base compartilhada |
| snooze_conversation | action_service.rb:13 | ✅ | ✅ | base |
| resolve_conversation | action_service.rb:17 | ✅ | ✅ | base |
| open_conversation | action_service.rb:21 | ❌ | ✅ | macro usa `change_status` genérico |
| pending_conversation | action_service.rb:25 | ❌ | ✅ | idem |
| change_status | action_service.rb:29 | ✅ | ✅ | base |
| change_priority | action_service.rb:33 | ✅ | ✅ | aceita `'nil'` |
| add_label | action_service.rb:37 | ✅ | ✅ | base |
| remove_label | action_service.rb:55 | ✅ | ✅ | base |
| assign_agent | action_service.rb:43 | ✅ (`'self'`) | ✅ | valida agente ∈ inbox |
| assign_team | action_service.rb:62 | ✅ | ✅ | `'nil'/'0'` desatribui |
| remove_assigned_team | action_service.rb:75 | ✅ | ❌ | **existe no método mas NÃO está na whitelist da automação** (automation_rule.rb:42-45) — usável só por macro **[verificado]** |
| send_email_transcript | action_service.rb:79 | ✅ | ✅ | rate-limited |
| send_message | override próprio | ✅ (autor=user) | ✅ (autor=nil + `automation_rule_id`) | autoria difere |
| add_private_note | override próprio | ✅ | ✅ | |
| send_attachment | override próprio | ✅ (`@macro.files`) | ✅ (`@rule.files`) | fonte do anexo difere |
| send_webhook_event | override próprio | ✅ (`macro.executed`) | ✅ (`automation_event.<event>`) | **fire-and-forget** (`WebhookJob.perform_later`) — descarta a resposta HTTP |
| send_email_to_team | automation_rules/action_service.rb:57 | ❌ | ✅ | **exclusivo automação** **[verificado]** |
| add_sla | enterprise/action_service.rb:2 | ❌ | ✅ (enterprise) | **exclusivo automação**; feature cloud `sla` **[verificado]** |
| assign_ai_agent | enterprise/action_service.rb:17 | ✅ | ✅ (enterprise) | **CORREÇÃO** — ver abaixo |

> ⚠️ **CONFLITO RESOLVIDO — `assign_ai_agent`.** O Relatório 2 afirmou que `assign_ai_agent` é **exclusivo do macro**. **Isso está errado. [verificado na fonte]**: o método vive em `Enterprise::ActionService` (`enterprise/app/services/enterprise/action_service.rb:17`), que é mixado na **base** `ActionService` via `ActionService.include_mod_with('ActionService')` (action_service.rb:113) — logo os métodos `assign_ai_agent`/`add_sla` existem para **ambas** as subclasses. A **exposição** é gated pela whitelist do modelo: `Macro::ACTIONS_ATTRS` (macro.rb:33) inclui `assign_ai_agent`; `Enterprise::AutomationRule#actions_attributes` faz `super + %w[add_sla assign_ai_agent]` — então **a automação também expõe `assign_ai_agent`** (em build enterprise). Relatórios 1 e 3 estavam corretos. Resumo verificado: `assign_ai_agent` = **ambos**; `add_sla` = **só automação**; `send_email_to_team` = **só automação**; `remove_assigned_team` = **só macro**.

`assign_ai_agent` é a lógica C5 do projeto IA-atribuível: atribui a conversa ao AgentBot-espelho de um Captain Assistant, seta `Current.executed_by = assistant` (enterprise/action_service.rb:45) e tem guardas próprias (`last_outgoing_by_human?`, `Current.skip_ai_agent_assignment`). Contexto de execução: automação credita ações como "Sistema de Automação" (`Current.executed_by = rule`); macro credita ao usuário real (`Current.user = user`).

### 1.6 Automação-Kanban — o 3º sistema, deliberadamente paralelo

`Kanban::AutomationEngineService` (`app/services/kanban/automation_engine_service.rb`, comentários "Kanban v2 Fase 5") **não chama `ActionService`**. Ações próprias (`ACTION_TYPES`, funnel_automation.rb:21): `move`, `assign`, `tag`, `webhook`, `enroll_in_sequence`, formato `{type, stage_id, assignee_id, url, labels[]}`. `execute_action` (automation_engine_service.rb:83-93) delega a `FunnelItems::MoveService`, `Conversations::AssignmentService`, `conversation.add_labels`, `WebhookJob`, `MessageSequences::EnrollService`. Disparo: `item_entered_stage` → `FunnelItems::MoveService#run_automations` (move_service.rb:47-53, só em `stage_changed`); `time_in_stage` → `Kanban::SlaMonitorJob` com marcador idempotente em `custom_attributes` (`kanban_auto_#{id}`). **Guard de reentrância por profundidade `MAX_DEPTH=3`** (`Current.funnel_automation_depth`, automation_engine_service.rb:13) — necessário porque `move` re-dispara o motor. CRUD REST aninhado: `/funnels/:funnel_id/automations` (`automations_controller.rb`).

### 1.7 Como o front renderiza uma ação (para saber o custo de adicionar ações)

- Listas: `.../settings/automation/constants.js` — `AUTOMATIONS` (por evento: quais condições/ações), `AUTOMATION_ACTION_TYPES` (lista mestra `{key,label,inputType}`, fonte do dropdown), `AUTOMATION_RULE_EVENTS`. Macros: `.../settings/macros/constants.js` `MACRO_ACTION_TYPES`.
- Render: `AutomationRuleForm.vue` monta `automationActionTypes` (:176-195, filtra `add_sla` sem feature SLA e `assign_ai_agent` sem agentes IA) → `AutomationActionInput.vue`. O `inputType` decide o widget: `search_select` (SingleSelect), `multi_select`, `email`, `url`, `attachment` (`AutomationFileInput`), `team_message`, `textarea` (`WootMessageEditor`), `null` (sem input). Valores via `getActionDropdownValues`/`getActionOptions` (`automationHelper.js:97-118`). Payload por `generateAutomationPayload` (`automationHelper.js:204-210`).
- **Adicionar ação nova = 4 pontos:** (a) método em `ActionService`/subclasse/enterprise; (b) entrada na whitelist do modelo (`actions_attributes` / `ACTIONS_ATTRS`); (c) `AUTOMATION_ACTION_TYPES` + `AUTOMATIONS[*].actions` + i18n; (d) `inputType` + widget em `AutomationActionInput.vue`.

> **Incerteza honesta [1 fonte: Relatório 1]:** `add_private_note`, `change_priority` e `open_conversation` aparecem na lista mestra `AUTOMATION_ACTION_TYPES` mas o Relatório 1 não conseguiu confirmar se aparecem nas listas por-evento de `AUTOMATIONS` para todos os eventos — a lista efetiva mostrada ao usuário depende de como o componente pai combina `AUTOMATIONS[event].actions` com a lista mestra. Não verificado nesta síntese.

---

## 2. A LACUNA `send_template`

### 2.1 Por que falta

**Não existe nenhuma ação `send_template` em nenhuma das três whitelists** (verificado em macro.rb:33-35, automation_rule.rb:42-45, enterprise automation_rule.rb). A ação `send_message` (automation_rules/action_service.rb / execution_service.rb) cria uma mensagem outgoing **de texto livre** via `MessageBuilder`, **sem `template_params`**. Fora da janela de 24h do WhatsApp Cloud, isso **não entrega** (a Meta rejeita). Ou seja: **hoje não há forma confiável de reengajar por automação/macro** — é exatamente o gap.

### 2.2 A infra que JÁ EXISTE (o ponto que muda o custo do trabalho)

O envio de template já funciona **manualmente** e a ação de automação só precisa **reaproveitar o pipeline** — **não precisa falar com a Graph API**:

1. **Front (manual):** `WhatsAppTemplateParser.vue` monta `templateParams: {name, category, language, namespace, processed_params}` em `sendMessage()` (WhatsAppTemplateParser.vue:138-154). Wrapper `NewConversation/.../WhatsappTemplate.vue`. Lista de templates vem de `channel.message_templates` (jsonb).
2. **Persistência:** `Messages::MessageBuilder` grava `template_params` em `additional_attributes` (`app/builders/messages/message_builder.rb:158`).
3. **Envio (automático no pipeline):** `Whatsapp::SendOnWhatsappService` decide `should_send_template_message = template_params.present? || !message.conversation.can_reply?` (`send_on_whatsapp_service.rb:8`) → `send_template_message` (:17-38) → `Whatsapp::TemplateProcessorService` (`find_template` casa name+language+`status=='approved'`, template_processor_service.rb:21-27) → `TemplateParameterConverterService` (legacy→enhanced) → `PopulateTemplateParametersService` (header/body/footer/buttons, media em :33-40) → `channel.send_template` (`channel/whatsapp.rb:58`) → `Whatsapp::Providers::WhatsappCloudService` POST `/{phone_id}/messages` type `template` (`whatsapp_cloud_service.rb:22-40`).

**Conclusão-chave:** `send_template` só precisa **criar a mensagem outgoing com `template_params` preenchido** via `MessageBuilder`. Todo o resto (componentes + POST) já roda sozinho.

### 2.3 A regra das 24h (por que isso importa em automação, não só no manual)

Regra da Meta: fora da janela de 24h desde a **última mensagem do cliente**, mensagens de sessão (texto livre) são **bloqueadas**; **template é o único jeito de reengajar**. O código já modela: `Conversation#can_reply?` retorna `false` quando a janela expirou (canal WhatsApp). Cenários de automação que caem fora da janela: `conversation_created` fora do horário, follow-up agendado, `conversation_resolved` + nudge, campanha de reativação. `send_message` nesses casos vira `failed`; `send_template` **funciona dentro e fora** da janela (se aprovado). Isto é corroborado como **o denominador comum do mercado WhatsApp** (§3.2).

### 2.4 Spec proposta **[1 fonte: Relatório 3, não implementada]**

- **Serviço compartilhado novo:** `app/services/whatsapp/template_action_service.rb` — resolve variáveis Liquid (`{{contact.name}}`) dentro de `processed_params`, cria a mensagem via `MessageBuilder`. Guards: `whatsapp_cloud_inbox?` (só `Channel::Whatsapp` provider `whatsapp_cloud`), `find_approved_template` (no-op silencioso se ausente, padrão `add_sla`).
- **Métodos `send_template`** em `automation_rules/action_service.rb` (sender=nil, executed_by=@rule) e `macros/execution_service.rb` (sender=@user, executed_by=@macro); `params[0]` (schema em array).
- **Schema da ação:**
  ```json
  { "action_name": "send_template",
    "action_params": [{ "name": "tozi_lead_inicial", "language": "pt_BR",
      "processed_params": {
        "body": {"1":"{{contact.name}}","2":"{{conversation.id}}"},
        "header": {"media_url":"https://...","media_type":"image"},
        "buttons": [{"type":"url","parameter":"{{contact.id}}"}] } }] }
  ```
  Reaproveita o shape que o front já produz (WhatsAppTemplateParser.vue:144-153), embrulhado em array (como `send_email_to_team` já faz).
- **UI:** registrar em automation `constants.js` + macros `MACRO_ACTION_TYPES`; novo `inputType: 'whatsapp_template'` + componente `AutomationTemplateInput.vue` (seletor de template `status==APPROVED` + preenchimento de variáveis com "variable picker"); `showActionInput` retorna true; `actionQueryGenerator` faz passthrough do objeto. Guard de disponibilidade: só aparece com ≥1 inbox `whatsapp_cloud` (espelha `assign_ai_agent` em AutomationRuleForm.vue:184).
- **Esforço: M (~3-5 dias).** Maior custo é a UI do input.
- **Riscos:** (1) template desaprovado/excluído → `find_template` nil → falha silenciosa (send_on_whatsapp_service.rb:26), precisa observabilidade; (2) variável que resolve para `""` → Graph API rejeita; (3) custo/spam de templates MARKETING → risco de rebaixamento de qualidade do número, recomendar UTILITY ou rate-limit; (4) inbox não-WhatsApp → guard obrigatório; (5) 360dialog vs Cloud (shapes divergem) → MVP restringir a `whatsapp_cloud`; (6) header de mídia com URL dinâmica raramente faz sentido; (7) emitir só formato **enhanced** (não legacy).

> Nota de arquitetura: WhatsApp templates são **core** → recomendação do Relatório 3 é pôr `send_template` no `ActionService` base (community), não no módulo enterprise. Como o método na base é herdado por macro **e** automação, uma única implementação cobre os dois — alinhado com o fato-chave de §1.1.

---

## 3. COMO O MERCADO FAZ

> **Framing de honestidade:** cada família de mercado vem de **um único relatório** — big SaaS = Relatório 4, WhatsApp tools = Relatório 5, OSS builders = Relatório 6. Portanto os claims desta seção são, por natureza, de fonte única (com URLs preservadas ao final). Marco explicitamente **[1 fonte]** apenas os claims mais surpreendentes/numéricos.

### 3.1 Big SaaS de atendimento (Relatório 4) — eles unificam?

**Resposta:** não formalmente, mas a fronteira está desaparecendo. Todas mantêm **dois planos** (motor de automação event/time-triggered + macros manuais), com as macros **reutilizáveis dentro** do motor. A unificação real de 2025/26 acontece numa **terceira camada agêntica** (Fin AI, Zendesk AI Agents/Copilot, Salesforce Agentforce, HubSpot Breeze) que consome macros e workflows como "ferramentas/ações".

| Plataforma | Motor | Gatilhos | Branching/Delay/Wait | Construtor | Macro separada? |
|---|---|---|---|---|---|
| **Intercom** | Workflows + Procedures/Fin AI | início/durante conversa, ação do cliente, evento de ticket, outro workflow | **Sim, todos**; Wait com durações fixas (3/5/7/10/15 min); branches por condição | **Canvas visual** drag-and-drop | Separado; Procedures descrevem lógica em linguagem natural com if/else |
| **Zendesk** | Triggers (evento) + Automations (tempo, ~1×/h) + Macros | event-based instantâneo vs baseado em tempo | **Sem branching visual nem delay nativo**; delay = automation por tempo | **Formulário** (condições→ações) | **Separado por design**: "macros=manual, triggers=eventos, automations=o relógio"; macros só têm ações, nunca condições |
| **HubSpot** | Workflows + Sequences | evento/propriedade/comportamento; agendado | **O mais rico**: if/then (até 20 branches) + value-equals (até 250 branches); delays até data/condição | **Flow builder visual** | Não tem "macros"; equivalente = Snippets/Templates |
| **Freshdesk** | Automation Rules (3 tipos) + Scenario Automations | criação, atualização, time-triggered | AND/OR; **sem canvas**; delay via regra de tempo | **Formulário** | **Semi-unificado explícito**: Scenario Automations **são macros** com o mesmo vocabulário de ações, disparadas manualmente |
| **Salesforce** | Flow Builder | record-triggered, scheduled, platform event, invocado | **O mais poderoso**: Decision, Wait, Scheduled Paths, Loops; Winter '26 tem Decisions com **IA generativa** para rotear dados não-estruturados | **Canvas visual** | Separado: Macros + Quick Text no Service Console |

### 3.2 WhatsApp-first (Relatório 5) — o padrão é "template como nó de 1ª classe"

respond.io, WATI, ManyChat, Twilio Studio, 360dialog, Gupshup, Zoko, Sleekflow. Padrão dominante: **"enviar template aprovado" é um nó/step de primeira classe** num **builder visual de fluxo**, com a **janela de 24h** como restrição central.

- **Template como step:** respond.io Workflows step "Send a Message" seleciona template; ManyChat nó WhatsApp com opção **"Send outside 24-hour window"**; Twilio Studio usa `ContentSid`+`ContentVariables`; WATI "send message (template)" nas Rules; 360dialog/Gupshup/Zoko/Sleekflow idem.
- **Ramificação a partir dos botões do template:** ManyChat conecta cada botão do template a steps seguintes. **[1 fonte]** — padrão a copiar.
- **Gestão automática da janela 24h = diferencial de maturidade:** as boas plataformas **detectam** o estado da janela e trocam free-form↔template sozinhas. Twilio tem erro dedicado **63016** "Outside messaging window… use a Message Template instead". **[1 fonte]** Qualquer inbound (msg/call) reinicia o timer (360dialog).
- **Drip no WhatsApp ≠ drip de e-mail:** como cada follow-up costuma cair **fora da janela**, cada passo do drip normalmente precisa ser um **template aprovado** + opt-out por keyword (Sleekflow "STOP"). Drip = **sequência de templates agendados**.
- **Gatilhos ricos:** keyword inbound (WATI/Gupshup/Sleekflow), evento de conversa/contato, Click-to-WhatsApp ad (abre janela grátis), evento externo/e-commerce (Zoko: carrinho, COD, pós-compra via Shopify).
- **Distinção terminológica importante:** "**WhatsApp Flows**" (formulários interativos nativos do Meta — booking/survey/lead dentro do chat) é **diferente** do "flow builder de automação" da plataforma; quase todos suportam os dois e encaixam um no outro.

### 3.3 OSS builders (Relatório 6) — dois paradigmas de modelo de dados

| Ferramenta | Estrutura | Branch/condição | Delay/Loop | Canvas | Licença → pode copiar? |
|---|---|---|---|---|---|
| Chatwoot atual | trigger + filtro plano + ações | ❌ (só gate de entrada) | ❌ | formulário | — |
| **n8n** | `nodes[]` + `connections{}` (grafo livre) | IF / **Switch** / Merge | Wait / Loop | 2D livre, 3 painéis | Sustainable Use (fair-code) → **❌ só inspiração de UX** |
| **Node-RED** | array de nós + `wires` | switch node | delay node | 2D livre (fios) | **Apache 2.0 → ✅ copiar OK** |
| **Activepieces** | trigger + `nextAction` (linked-list vertical) | **Router** (`EXECUTE_FIRST_MATCH`/`EXECUTE_ALL_MATCH`) **[1 fonte]** | Loop / Delay | **vertical top-down** | **MIT → ✅ copiar OK** (evitar pastas Enterprise) |
| **Typebot** | Groups→Blocks→Edges (4 famílias: Bubble/Input/Logic/Integration) | Logic/Condition block | — | canvas + grupos | FSL-1.1-Apache-2.0 → ⚠️ Apache após 2 anos |
| **Automatisch** | trigger→steps linear | ❌ | ❌ | lista vertical | **AGPLv3 → ⚠️ evitar** (contamina SaaS hospedado) |

Insight OSS-chave: n8n usa "regra visual = regra de execução" (branches de cima→baixo, esquerda→direita pela posição no canvas) **[1 fonte]**. UX n8n = 3 zonas (paleta categorizada à esquerda + canvas + painel de propriedades contextual). A comunidade Chatwoot já pede branching por conteúdo: [discussion #8128](https://github.com/orgs/chatwoot/discussions/8128) (áudio no WhatsApp → auto-resposta "não conseguimos ouvir, escreva") **[1 fonte]**.

### 3.4 O que é uma automação "COMPLETA" em 2025/26 (consolidado dos 3 relatórios web)

7 componentes recorrentes (Relatório 4) + specifics WhatsApp (Relatório 5): (1) gatilho multi-fonte (evento **e** tempo); (2) condições AND/OR ricas; (3) **branching visual** if/then; (4) **delay/wait** (tempo/data/condição); (5) paleta ampla (campos, atribuir/rotear, notificar, **enviar mensagem/template**, webhooks, criar registros); (6) **ações de IA embutidas** (resumir/classificar/redigir/decidir rota); (7) **macros chamáveis como ações** pelo motor/IA; +WhatsApp: (8) **gestão automática da janela 24h**; (9) **drip/sequências** de templates agendados; (10) **WhatsApp Flows nativos** como step; (11) **opt-out/compliance** (keyword STOP).

### 3.5 Tendências 2025/2026

- **De copilot para agêntico.** Gartner projeta **80% dos tickets comuns resolvidos autonomamente por IA agêntica até 2029**. **[1 fonte]**
- **Convergência via camada de IA, não via builder.** Ninguém fundiu formalmente "macro"+"workflow"; a unificação vem do **AI Agent orquestrando ambos** como tools. Intercom formaliza: **Procedures** (linguagem natural) substituem Tasks; **Tasks descontinuadas — sem criação nova a partir de 12/mar/2026**. **[1 fonte]**
- **Macro deixando de ser "burra"** (Freshdesk Scenarios = macros no mesmo motor; Salesforce Flow absorvendo casos de macro).
- **Branching visual = padrão-ouro** (HubSpot 250 ramos, Salesforce Decision+GenAI puxam a régua; Zendesk/Freshdesk ficam para trás por serem formulário).
- **No-code/low-code dominante:** ~70% das novas apps corporativas em builders no/low-code. **[1 fonte]**

### 3.6 Implicação direta para o ChatSPX

O Chatwoot já é o "modelo clássico não-unificado": Automation Rules (event-based estilo Zendesk trigger, em **formulário**) + Macros separadas. Os gaps frente ao mercado: (1) branching visual em canvas; (2) delay/wait nativo; (3) macros chamáveis dentro de automações; (4) camada agêntica (Captain) orquestrando macros/automações como tools; e — específico do mercado BR — (5) `send_template` + **gestão automática da janela 24h** no nó de envio.

---

## 4. MATRIZ DE SOBREPOSIÇÃO — Automação-Conversa × Macro × Automação-Kanban

(Corrigida com a verificação de §1.5 sobre `assign_ai_agent`.)

| Dimensão | Automação-Conversa (`AutomationRule`) | Macro (`Macro`) | Automação-Kanban (`FunnelAutomation`) |
|---|---|---|---|
| **Trigger** | 5 eventos de conversa: created/updated/opened/resolved, message_created (automation_rule_listener.rb) | **Nenhum** — manual (macros_controller.rb:48) | item_entered_stage, time_in_stage (funnel_automation.rb:20) |
| **Condições** | `{attribute_key, filter_operator, values, query_operator}` AND/OR, ~17 attrs (+custom, +sla enterprise) | **Nenhuma** | `{field, op, value}`, ops eq/neq/present/blank/includes, 5 campos |
| **Ações** | `ActionService` + `send_email_to_team` + (enterprise) `add_sla`, `assign_ai_agent` | `ActionService` + `assign_ai_agent` + `'self'`; **não** send_email_to_team/add_sla/open/pending | Próprias: move/assign/tag/webhook/enroll_in_sequence — **não** ActionService |
| **Formato da ação** | `{action_name, action_params}` | `{action_name, action_params}` (**idêntico**) | `{type, stage_id, assignee_id, url, labels[]}` (**diferente**) |
| **Executor** | `AutomationRules::ActionService < ActionService` | `Macros::ExecutionService < ActionService` | `Kanban::AutomationEngineService` (standalone) |
| **Contexto exec.** | Sistema (`Current.executed_by=rule`) | Usuário real (`Current.user=user`) | Sistema (`moved_by` opcional) |
| **Agendamento** | ❌ | ❌ | ✅ `time_in_stage` via `SlaMonitorJob` |
| **Escopo** | Conta | Conta + visibility personal/global | Funil (opcional por stage) |
| **Loop guard** | `performed_by_automation?` (listener:73) | N/A | `MAX_DEPTH=3` + marcador em custom_attributes |
| **Bulk** | N/A (por evento) | ✅ `conversation_ids[]` | N/A (por card) |
| **Anexos** | `@rule.files` | `@macro.files` | ❌ |
| **UI** | Settings→Automation (builder condições+ações) | Settings→Macros (editor de nós: MacroEditor.vue) | Aninhada no funil (`/funnels/:id/automations`) |

**Leitura da matriz:**
- **Macro ↔ Automação-Conversa: sobreposição ALTA / quase gêmeos.** Mesma base, mesmo formato, whitelists quase idênticas. Diferenças reais e pequenas: (a) autoria da mensagem (macro=user; automação=nil + `content_attributes.automation_rule_id`, usado para **não re-disparar** o listener — automation_rule_listener.rb:85); (b) `assign_agent 'self'` só no modo manual; (c) 4 ações não-simétricas (`send_email_to_team`/`add_sla` só automação; `remove_assigned_team` só macro; `open`/`pending_conversation` só automação); (d) `visibility` só macro; (e) **bulk** só macro.
- **Automação-Kanban: sobreposição BAIXA.** DSL de condição diferente, ações incompatíveis com `ActionService` (opera em `funnel_item`+conversa, não só conversa), loop-guard por profundidade e trigger agendado que os outros não têm.

---

## 5. OPÇÕES DE UNIFICAÇÃO (do mínimo ao ambicioso)

### Opção 0 — Só compartilhar a paleta de ações (mínimo)
Não unifica modelos; apenas garante que **toda ação nova nasça na base `ActionService`** e entre nas duas whitelists (macro + automação), fechando assimetrias. Inclui adicionar `send_template` (§2) e, por consistência, `send_email_to_team`/`open_conversation`/`pending_conversation` no macro e `remove_assigned_team` na automação, se fizer sentido de produto.
- **Prós:** risco quase zero; ganho imediato (send_template nos dois lados); sem migração de dados.
- **Contras:** não resolve a duplicação de código (dois `send_message`/`add_private_note`/`send_attachment`), nem entrega branching/delay/canvas; não mexe no gap de mercado.
- **Esforço: P.** (send_template = M isolado.)

### Opção 1 — Fundir Macro + Automação-Conversa num modelo único (recomendada como Fase 1)
Uma entidade `Flow`/`Playbook` com `trigger_type ∈ {manual, conversation_created, …}` e `conditions` opcional. Macro = `trigger_type: manual`; Automação = `trigger_type: event`. Executor único = `ActionService` com flag de contexto (`Current.user` para manual vs `Current.executed_by=rule` para automático).
- **Prós:** reaproveita `ActionService` inteiro; elimina duplicação de whitelist e dos overrides; abre caminho de graça para `schedule`/`webhook` como novos `trigger_type` (Relatório 6). É a convergência "natural" dado o fato-chave de §1.1.
- **Contras / o que quebra:** precisa **preservar a marcação `automation_rule_id`** na autoria da mensagem (senão cria loop no listener); tratar `assign_agent 'self'` só no modo manual; mesclar as 4 ações não-simétricas; decidir o que fazer com `visibility` (conceito só de macro); **manter o bulk** (`conversation_ids[]`) como modo de disparo manual. Migração de dados de `macros`+`automation_rules` para a tabela unificada.
- **Esforço: M-G.** Sem branching/canvas ainda.

### Opção 2 — Unificar o VOCABULÁRIO de ações incluindo Kanban, mantendo motores separados
Expor as ações do motor Kanban (`move`, `tag`, `assign`, `enroll_in_sequence`) como ações no `ActionService` unificado, **mas** manter `Kanban::AutomationEngineService` como a camada própria de trigger/condição/guard que as chama. Ou seja: unificar o **vocabulário**, não o motor.
- **Prós:** preserva o loop-guard `MAX_DEPTH` e o agendamento Kanban; dá acesso a `enroll_in_sequence`/`move` para os outros contextos; um único catálogo de ações no front.
- **Contras:** `move`/`enroll_in_sequence` precisam de contexto de `funnel_item` — teria que ser injetado; risco de ação Kanban rodar em contexto sem funil.
- **Esforço: M-G.**

### Opção 3 — Motor único + builder visual (ambicioso)
Modelo `Flow` com `definition:jsonb` autocontido (nós + arestas), `trigger_type [event|manual|schedule|webhook]`, taxonomia de nós Typebot-like (Trigger / Action-Integration / Logic-Router / Wait-Delay), Router com estratégia explícita (Activepieces), versionamento da definição (rollback/audit — encaixa no Almirante). **Recomendação dos relatórios: paradigma Activepieces-like (vertical linked-list + Router/Loop), NÃO grafo livre n8n** (mais determinístico, menor superfície de bug, migração trivial do modelo plano atual — cada regra/macro vira um Flow linear = caso degenerado sem branch). UX n8n-like (3 painéis + propriedades contextuais + "+" entre steps). Reuso de código seguro: **Node-RED (Apache 2.0) e Activepieces (MIT)**; n8n/Typebot só inspiração; **evitar Automatisch (AGPL)**.
- **Prós:** fecha os gaps de mercado (branching visual, wait, macros-como-ação, IA-como-nó); paridade com respond.io/ManyChat; base para a camada agêntica (Captain como orquestrador).
- **Contras:** **reescrita do modelo de dados** (nós/arestas em vez de listas planas jsonb); exige **scheduler** (para delay/schedule) e **estado entre execuções** (para drip/enrollment) que hoje não existem; branching/canvas é frontend pesado; risco alto; precisa gestão da janela 24h embutida no nó de envio.
- **Esforço: G-XG.**

### Recomendação faseada consolidada (Relatórios 2 e 6, convergentes)
1. **Fase 1 (baixo risco, alto ganho):** Opção 1 (fundir Macro + Automação-Conversa) + Opção 0 (`send_template` na base). Resolve duplicação e o gap BR imediato.
2. **Fase 2 (opcional):** Opção 2 (vocabulário de ações Kanban compartilhado), mantendo os **motores de trigger separados** (listener de conversa, execução manual/bulk, motor Kanban).
3. **Fase 3 (visão):** Opção 3 (canvas + branching + wait + nós de IA), estilo Activepieces/vertical, com a janela 24h e o Captain no centro.
- **NÃO unificar os três num único motor:** o Kanban precisa de contexto `funnel_item`, depth-guard e trigger agendado que os outros não têm — forçar isso no `AutomationRuleListener`/`ActionService` traria acoplamento e risco de loop. A convergência correta é **um modelo de dados + vocabulário de ações comuns, com motores de trigger separados**.

---

## 6. LACUNAS DE AÇÕES para uma automação "COMPLETA" (priorizado)

Baseado no que **não existe** no código (verificado nas whitelists e no dispatch) cruzado com o "kit completo" de mercado (§3.4).

### P0 — Bloqueadores para o mercado BR (fazer primeiro)
- **`send_template` (WhatsApp oficial)** — AUSENTE nas 3 whitelists. Infra de envio **já existe** (§2.2); é o **denominador comum** do mercado WhatsApp (§3.2). Sem ele **não há reengajamento confiável** por automação/macro. Esforço **M** (§2.4). Fontes: código (verificado) + Relatórios 3, 5.
- **Gestão automática da janela 24h no nó de envio** — o produto deve detectar `can_reply?` e escolher/avisar free-form vs template, evitando o equivalente ao erro Twilio **63016**. É o "diferencial de maturidade" onde tools amadoras falham. **[1 fonte: Relatório 5]** (conceito), mas `can_reply?` já existe no código.

### P1 — Estruturais para "automação de verdade" (exigem mudança de modelo/infra)
- **wait / delay entre passos** — AUSENTE. `perform` roda todas as ações síncronas em sequência imediata (automation_rules/action_service.rb:9-18), sem `sleep`/`perform_in`/passo "aguardar N min/h". Requer scheduler. (Mercado: universal — HubSpot/Salesforce/Intercom; OSS Wait node.)
- **Branching if/then/else** — AUSENTE. Modelo linear: condições AND/OR num único bloco de entrada → lista plana de ações. Sem ramificação condicional entre ações nem grupos aninhados. Pedido concreto da comunidade: [discussion #8128](https://github.com/orgs/chatwoot/discussions/8128). (Mercado: padrão-ouro; Activepieces Router resolve.)
- **Gatilho agendado / time-based para conversa** — AUSENTE para Automação-Conversa e Macro (os 5 gatilhos são reativos). **Mas o Kanban já tem** `time_in_stage` via `Kanban::SlaMonitorJob` — padrão reutilizável ("X horas após criação", "conversa parada há N horas").
- **Sequências / drip / multi-step** — AUSENTE em automação/macro (stateless, sem enrollment). **Mas o Kanban já tem** `enroll_in_sequence` + `MessageSequences::EnrollService`. No WhatsApp, drip = **sequência de templates agendados** + opt-out (§3.2), então depende de send_template (P0) + wait/schedule (P1).

### P2 — Ampliação / maturidade agêntica e dívidas menores
- **Nó de IA (classificar/extrair/gerar-e-ramificar)** — PARCIAL. Hoje só `assign_ai_agent` (**transfere** a conversa ao espelho Captain, enterprise/action_service.rb:17). Não há passo "classificar com IA e ramificar", "extrair dado", "gerar resposta e enviar", nem saída da IA como condição. (Mercado: Salesforce Decision+GenAI, HubSpot AI actions, Fin steps.)
- **Webhook request-response** — PARCIAL. `send_webhook_event` é **fire-and-forget** (`WebhookJob.perform_later`, descarta a resposta HTTP). Não dá para condicionar passos seguintes com o retorno nem mapear resposta→variáveis.
- **Gatilho keyword inbound** — AUSENTE. (Mercado WhatsApp: WATI/Gupshup/Sleekflow.) Parcialmente aproximável hoje via `message_created` + condição `content contains`, mas não é um trigger de keyword de 1ª classe.
- **Gatilho de evento externo / e-commerce** (webhook/CRM/Shopify: carrinho, pedido) — AUSENTE. (Mercado: Zoko/FlowHippo.)
- **Expor ações Kanban (`move`/`tag`/`enroll_in_sequence`) na paleta comum** — hoje presas ao motor Kanban (Opção 2 de §5).
- **WhatsApp Flows nativos (Meta) como step** — AUSENTE. **[1 fonte: Relatório 5]** — distinguir de "flow builder de automação".
- **Opt-out / compliance (keyword STOP → remover de marketing)** — AUSENTE; obrigatório para não queimar quality rating em drip. **[1 fonte: Relatório 5]**
- **Dívidas técnicas menores (limpeza):** `city`/`company` na whitelist de condições sem UI (condições mortas, **[1 fonte]** p/ ausência no front); `remove_assigned_team` fora da whitelist da automação **[verificado]**; operador `days_before` órfão **[1 fonte]**; incerteza sobre listas de ação por-evento no front **[1 fonte]** (§1.7).

---

## Fontes Web (preservadas)

**Big SaaS (Relatório 4):** Intercom [Workflows](https://www.intercom.com/help/en/articles/7836459-workflows-explained) · [Procedures vs Tasks vs Workflows](https://www.intercom.com/help/en/articles/14077835-procedures-vs-tasks-vs-workflows) · [Fin in Workflows](https://www.intercom.com/help/en/articles/10032299-use-fin-ai-agent-in-workflows) · Zendesk [Business Rules explained](https://www.getmacha.com/blog/zendesk-business-rules-explained) · [Triggers & automations](https://support.zendesk.com/hc/en-us/sections/5322740495642-Triggers-and-automations) · [Salto: Triggers vs Automations](https://www.salto.io/blog-posts/zendesk-triggers-vs-automations) · HubSpot [if/then branches](https://knowledge.hubspot.com/workflows/use-if-then-branches-in-workflows) · [workflow actions](https://knowledge.hubspot.com/workflows/choose-your-workflow-actions) · [delays](https://knowledge.hubspot.com/workflows/use-delays) · [Snippets vs Templates](https://mpiresolutions.com/blog/what-are-snippets-in-hubspot/) · Freshdesk [Automation Rules](https://support.freshdesk.com/support/solutions/articles/207276-overview-of-automation-rules) · [Scenarios = macros](https://support.freshdesk.com/support/solutions/articles/37616-perform-macro-actions-with-scenarios) · Salesforce [Record-Triggered Flows](https://trailhead.salesforce.com/content/learn/modules/record-triggered-flows/build-a-record-triggered-flow) · [Winter '26 Flow](https://salesforcebreak.com/2025/09/02/salesforce-winter-26-new-flow-features/) · [Service Cloud Macros](https://www.salesforceben.com/service-cloud-macros/) · [Macros & Quick Text](https://trailhead.salesforce.com/content/learn/modules/service-cloud-agent-productivity/create-a-macro-and-quick-text) · Tendências: [Viewpoint 2026](https://www.viewpointanalysis.com/post/customer-service-ai-software-options-2026) · [Crescendo 2026](https://www.crescendo.ai/blog/emerging-trends-in-customer-service)

**WhatsApp tools (Relatório 5):** respond.io [automation](https://respond.io/blog/whatsapp-automation) · [workflows](https://respond.io/help/workflows/workflows-overview) · [templates](https://respond.io/help/whatsapp/whatsapp-message-templates) · [v8.0 changelog](https://respond.canny.io/changelog/v80-workflows-aka-automation-20-whatsapp-message-template-api-and-more) · WATI [flowbuilder](https://www.wati.io/flowbuilder/) · [actions in rules](https://support.wati.io/en/articles/11463197-how-to-set-up-actions-in-rules) · [triggers](https://support.wati.io/en/articles/12321649-how-to-set-up-triggers-in-rules) · [WhatsApp Flows](https://support.wati.io/en/articles/11463180-how-to-create-and-use-whatsapp-flows-in-wati) · ManyChat [templates no flow](https://help.manychat.com/hc/en-us/articles/14281326740124-How-to-use-WhatsApp-Messages-Templates-in-Manychat) · Twilio [templates fora da janela](https://www.twilio.com/docs/whatsapp/tutorial/send-whatsapp-notification-messages-templates) · [erro 63016](https://www.twilio.com/docs/api/errors/63016) · [key concepts](https://www.twilio.com/docs/whatsapp/key-concepts) · [Studio menu](https://www.twilio.com/docs/studio/tutorials/customer-support-menu) · [content/whatsapp-flows](https://www.twilio.com/docs/content/whatsapp-flows) · 360dialog [messaging](https://docs.360dialog.com/docs/messaging/overview) · [templates](https://docs.360dialog.com/docs/resources/templates) · Gupshup [flow builder](https://www.gupshup.io/developer/docs/bot-platform/guide/intro-flow-builder) · [structured messages](https://www.gupshup.io/developer/docs/bot-platform/guide/structured-messages-flow-builder) · Zoko [FlowHippo](https://www.zoko.io/learning-topic/flows) · [flow cards](https://www.zoko.io/learning-micro-lessons/flow-cards-in-flowhippo) · [drip 2026](https://www.zoko.io/post/mastering-whatsapp-drip-marketing-campaigns) · Sleekflow [flow builder](https://sleekflow.io/en-us/blog/flow-builder) · [drip template](https://docs.sleekflow.io/using-the-platform/automation/templates/9.-send-drip-campaign-messages-when-customers-sign-up) · [schedule](https://sleekflow.io/blog/whatsapp-schedule-message)

**OSS builders (Relatório 6):** Chatwoot [Automations](https://www.chatwoot.com/features/automations) · [Discussion #8128](https://github.com/orgs/chatwoot/discussions/8128) · [Issue #3195](https://github.com/chatwoot/chatwoot/issues/3195) · [DeepWiki Automation & Macros](https://deepwiki.com/chatwoot/chatwoot) · [v2.11 Macros blog](https://www.chatwoot.com/blog/v2-11-0-macros-and-more/) · n8n [data structure](https://docs.n8n.io/data/data-structure/) · [execution order](https://docs.n8n.io/flow-logic/execution-order/) · [Merge/IF/Switch](https://n8n.io/workflows/5996-learn-workflow-logic-with-merge-if-and-switch-operations/) · [node UI design](https://docs.n8n.io/integrations/creating-nodes/plan/node-ui-design/) · Activepieces [repo MIT](https://github.com/activepieces/activepieces) · [Action/Trigger types](https://deepwiki.com/activepieces/activepieces) · [Loops & Branches/Router](https://activepieces-activepieces.mintlify.app/workflows/loops-branches) · [routing #4633](https://github.com/activepieces/activepieces/issues/4633) · Typebot [blocks](https://docs.typebot.io/editor/blocks/overview) · [repo FSL](https://github.com/baptisteArno/typebot.io) · Node-RED [messages/flow](https://nodered.org/docs/user-guide/messages) · Licenças: [n8n vs Automatisch vs Node-RED](https://www.pkgpulse.com/guides/n8n-vs-automatisch-vs-node-red-workflow-automation-2026) · [OSS por licença](https://alternativeto.net/software/n8n-io/?license=opensource)

## Arquivos-chave do nosso código (referência rápida)
`app/models/automation_rule.rb` · `app/models/macro.rb` · `app/models/funnel_automation.rb` · `app/services/action_service.rb` (base compartilhada, `include_mod_with` na :113) · `app/services/automation_rules/action_service.rb` · `app/services/macros/execution_service.rb` · `enterprise/app/services/enterprise/action_service.rb` (add_sla, assign_ai_agent) · `enterprise/app/models/enterprise/automation_rule.rb` (whitelist enterprise) · `app/listeners/automation_rule_listener.rb` · `app/services/automation_rules/conditions_filter_service.rb` · `app/services/kanban/automation_engine_service.rb` · `app/jobs/kanban/sla_monitor_job.rb` · `app/jobs/macros_execution_job.rb` · Envio template: `app/services/whatsapp/send_on_whatsapp_service.rb:8` · `app/services/whatsapp/template_processor_service.rb:22` · `app/services/whatsapp/providers/whatsapp_cloud_service.rb:22` · `app/builders/messages/message_builder.rb:158` · `app/models/channel/whatsapp.rb:58` · Front: `.../settings/automation/constants.js` · `.../settings/macros/constants.js` · `AutomationRuleForm.vue` · `AutomationActionInput.vue` · `automationHelper.js` · `components-next/whatsapp/WhatsAppTemplateParser.vue:138-154`