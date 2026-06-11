# Mapeamento — Atribuição e Automação (roteamento nativo do SPX)

> Área: `atribuicao-automacao` · Branch `paulao` · Gerado em 2026-06-10
> Tudo baseado em leitura do código local (app/ + enterprise/). Referências em `arquivo:linha`.

---

## 1. Auto-assignment de inbox (round-robin)

### 1.1 Onde dispara — callback no model

`Conversation` inclui dois concerns de atribuição (`app/models/conversation.rb:57-58`):

- **`AssignmentHandler`** (`app/models/concerns/assignment_handler.rb`) — consistência assignee↔team + eventos.
- **`AutoAssignmentHandler`** (`app/models/concerns/auto_assignment_handler.rb`) — o gatilho do auto-assignment.

`AutoAssignmentHandler` registra `after_save :run_auto_assignment` (auto_assignment_handler.rb:6). O método (linhas 11-26):

1. Só roda se o status mudou para `open` (`conversation_status_changed_to_open?`, conversation.rb:398-402 — cobre criação e update) — ou, **no V2**, também quando mudou para `resolved`/`snoozed` (para rebalancear capacidade, linhas 28-30).
2. `should_run_auto_assignment?` (38-46): exige `inbox.enable_auto_assignment?` (coluna boolean, default TRUE — inbox.rb schema linha 15) e que `assignee` esteja em branco **ou** o assignee atual não seja membro do inbox.
3. Bifurca:
   - **V2** (`inbox.auto_assignment_v2_enabled?` = feature flag `assignment_v2` na conta — `app/models/inbox.rb:205-207`): enfileira `AutoAssignment::AssignmentJob` (bulk por inbox).
   - **Legacy** (default): roda **inline** `AutoAssignment::AgentAssignmentService` com `allowed_agent_ids` = membros do inbox com capacidade; se a conversa tem `team_id`, restringe à interseção com membros do time **e exige `team.allow_auto_assign`** (linhas 23-24, 32-36).

### 1.2 Caminho legacy — só agentes ONLINE

`AutoAssignment::AgentAssignmentService` (`app/services/auto_assignment/agent_assignment_service.rb`):
- `find_assignee` faz round-robin **apenas sobre a interseção de agentes online** (Redis `OnlineStatusTracker`) com os permitidos (linhas 18-28). **Agente offline nunca recebe conversa pelo caminho legacy.**
- `perform` → `conversation.update(assignee: new_assignee)` (linha 13).

Fila round-robin em Redis: `AutoAssignment::InboxRoundRobinService` (`app/services/auto_assignment/inbox_round_robin_service.rb`) — lista `ROUND_ROBIN_AGENTS` por inbox; pop do candidato + push pro fim (47-52); `validate_queue?` reseta a fila se dessincronizar com `inbox_members` (54-56). A fila é mantida por callbacks de `InboxMember` (`app/models/inbox_member.rb:25-26, 35-40`) e limpa no destroy do inbox (`app/models/inbox.rb:83, 243-244`).

Capacidade (Enterprise, legacy): `Enterprise::Inbox#member_ids_with_assignment_capacity` exclui agentes acima de `auto_assignment_config['max_assignment_limit']` (`enterprise/app/models/enterprise/inbox.rb:2-8, 24-32`).

### 1.3 Caminho V2 — AssignmentService (políticas)

`AutoAssignment::AssignmentService` (`app/services/auto_assignment/assignment_service.rb`):
- `perform_bulk_assignment` (4-15): exige `auto_assignment_v2_enabled?` + `enable_auto_assignment?`; varre `inbox.conversations.unassigned.open` ordenadas por política (`longest_waiting` → `last_activity_at asc`; senão `created_at asc`, linhas 33-45).
- `find_available_agent` (47-55): `inbox.available_agents` → filtro por time da conversa (57-65, exige `team.allow_auto_assign`) → filtro de rate limit → `RoundRobinSelector`.
- Rate limiter (`app/services/auto_assignment/rate_limiter.rb`): janela Redis — default **5 atribuições por 5 min por agente/inbox**, configurável via `assignment_policy.fair_distribution_limit/window` (20-26).
- Ao atribuir, seta `Current.executed_by = inbox.assignment_policy || inbox` (74-77) — a atividade sai como "via política" (`app/models/concerns/assignee_activity_message_handler.rb:23-26`) — e despacha `ASSIGNEE_CHANGED` manualmente (88-95).
- `prepend_mod_with('AutoAssignment::AssignmentService')` (linha 106) → **override Enterprise** `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb`:
  - `find_available_agent` adiciona filtro de **capacidade** (`Enterprise::AutoAssignment::CapacityService` — limite de conversas abertas por agente/inbox via `agent_capacity_policy` + `inbox_capacity_limits`, capacity_service.rb:1-25) e **balanced selector** (agente com menos conversas abertas — balanced_selector.rb:4-11) quando `policy.balanced?` + feature `advanced_assignment` (assignment_service.rb:17-28).
  - `unassigned_conversations` aplica **exclusion rules** da capacity policy: labels excluídas e idade máxima (59-97).

### 1.4 Jobs/crons de atribuição

| Job | Cron | O que faz |
|---|---|---|
| `AutoAssignment::AssignmentJob` (`app/jobs/auto_assignment/assignment_job.rb`) | on-demand (enfileirado pelo after_save V2) | `perform_bulk_assignment(limit: ENV AUTO_ASSIGNMENT_BULK_LIMIT default 100)` |
| `AutoAssignment::PeriodicAssignmentJob` (`app/jobs/auto_assignment/periodic_assignment_job.rb`) | `*/30` (config/schedule.yml:61-64) | contas com feature `assignment_v2` E inbox com `assignment_policy` → AssignmentJob |
| `Inboxes::BulkAutoAssignmentJob` (`app/jobs/inboxes/bulk_auto_assignment_job.rb`) | `*/15` (schedule.yml:55-58) | contas `Account.feature_assignment_v2` → varre `unassigned.open` e atribui via **AgentAssignmentService legacy** (só online) |

**Implicação Tozi:** se a Account 6 não tem a flag `assignment_v2`, nenhum cron de atribuição roda; a única atribuição automática nativa é o `after_save` legacy no momento em que o status vira `open` — e só pega agente **online**.

### 1.5 Round-robin no handoff do Captain

`Captain::Tools::HandoffTool` (`enterprise/lib/captain/tools/handoff_tool.rb:26-64`): nota privada com o motivo → `conversation.bot_handoff!` (abre + dispara `CONVERSATION_BOT_HANDOFF`, conversation.rb:199-203) → `assign_to_available_agent` usa o **mesmo** `AgentAssignmentService` (round-robin entre membros do inbox **online**; se ninguém online, fica sem dono — comentário nas linhas 42-46 admite isso). TODO no próprio arquivo (74-84): team routing, prioridade, escalação — não implementados.

---

## 2. Times (Team) e atribuição a time

### 2.1 Model

`app/models/team.rb`: `allow_auto_assign` (default TRUE, schema linha 6) controla se o time participa de auto-assignment; `has_many :conversations, dependent: :nullify` (24); `after_create :create_default_funnel` — **fork SPX**: todo time ganha um funil Kanban (`Kanban::CreateFunnelForTeamService`, team.rb:34, 73-77). Enterprise só adiciona audit (`enterprise/app/models/enterprise/audit/team.rb`).

### 2.2 Acoplamento assignee↔team (AssignmentHandler) — fonte de surpresas

`app/models/concerns/assignment_handler.rb`:
- `before_save :ensure_assignee_is_from_team` (13-20):
  - Se `team_id` mudou: derruba o assignee que não é membro do novo time (`validate_current_assignee_team`, 44-46) e **auto-atribui um membro do time** via `AgentAssignmentService` (online, com capacidade) se `team.allow_auto_assign` (48-53).
  - Se `assignee_id` mudou: `sync_team_from_assignee` (22-36) — agente em **exatamente 1 time** → conversa herda esse time; agente que **não pertence** ao team atual da conversa → **`team_id = nil` silencioso**. ⚠️ Atribuir um corretor sem time a uma conversa com time zera o time.
- `after_commit`: `notify_assignment_change` despacha `ASSIGNEE_CHANGED`/`TEAM_CHANGED` (55-62); `mark_conversation_unread_on_assignment_change` → `mark_as_unread!` em **toda** mudança de assignee/team (68-72, conversation.rb:264-271) — o novo dono vê a bolinha de não-lida.

### 2.3 Time obrigatório para resolver (fork)

`Conversation#team_required_for_resolution` (`app/models/conversation.rb:316-322`): **resolver exige `team_id` presente** (validação custom do fork, bypassável via `skip_team_required_for_resolution_validation`, linha 65). `Conversations::ToggleStatusService` lança `TeamRequiredError` (toggle_status_service.rb:24-28, 49-53) e o controller devolve 422 (conversations_controller.rb:90-94). ⚠️ Qualquer IA/automação que resolva conversas precisa garantir time antes.

### 2.4 Notificações

`app/listeners/notification_listener.rb`:
- `conversation_created` (9-14): notifica **todos os membros do inbox** — `return if conversation.pending?`.
- `assignee_changed` (16-34): cria `conversation_assignment` pro novo assignee — `return if assignee.blank?` e **`return if conversation.pending?`** (26). ⚠️ Atribuição em conversa pending não notifica ninguém (alimenta o problema do "limbo invisível").
- `message_created` (36-41): menções + `Messages::NewMessageNotificationService` (`app/services/messages/new_message_notification_service.rb`) — notifica assignee (15-27) e participantes (29-44), com dedup (48-56).

### 2.5 Times × mensagens × funil (fork)

- Isolamento de mensagens por time: `Conversation#messages` filtra por `team_id` quando `inbox.team_message_isolation` está ON (conversation.rb:125-137) + `Conversations::UpdateMessagesTeamIdJob` sincroniza no team change (283-287).
- Mudança de time move o card no Kanban: `move_to_team_funnel` after_update_commit (conversation.rb:158, 450-455).

---

## 3. Engine de AutomationRules

### 3.1 Model

`app/models/automation_rule.rb`: `event_name` (string), `conditions` (jsonb), `actions` (jsonb), `active` (boolean), `has_many_attached :files` (para send_attachment).

- `conditions_attributes` (37-40): `content email country_code status message_type browser_language assignee_id team_id referer city company inbox_id mail_subject phone_number priority conversation_language labels` + custom attributes da conta (validação em 64-71).
- `actions_attributes` (42-45): `send_message add_label remove_label send_email_to_team assign_team assign_agent send_webhook_event mute_conversation send_attachment change_status resolve_conversation open_conversation pending_conversation snooze_conversation change_priority send_email_transcript add_private_note`.
- **Enterprise** (`enterprise/app/models/enterprise/automation_rule.rb`): + condição `sla_policy_id`, + ação `add_sla`.
- `Reauthorizable`: quando a validação de condição falha em runtime, `@rule.authorization_error!` é chamado (conditions_filter_service.rb:48) — contagem de erros que pode desativar/alertar a regra (view `automation_rule_disabled.liquid`).

### 3.2 Eventos suportados — TODOS

Handler: `app/listeners/automation_rule_listener.rb`. Eventos com método no listener (a lista completa e canônica):

| Evento | Listener | Origem do dispatch |
|---|---|---|
| `conversation_created` | automation_rule_listener.rb:6-8 | `after_create_commit :notify_conversation_creation` (conversation.rb:159, 345-347) |
| `conversation_updated` | :2-4 | `notify_conversation_updation` em mudanças de team/assignee/labels/priority/snoozed_until/waiting_since/first_reply/custom_attributes — **exceto status** (conversation.rb:349-369) |
| `conversation_opened` | :10-12 | `notify_status_change` quando `saved_change_to_status? && open?` (conversation.rb:380-390) — **só em UPDATE**; conversa criada já `open` NÃO dispara |
| `conversation_resolved` | :14-16 | idem, `resolved?` (conversation.rb:383) |
| `message_created` | :18-35 | `Message#dispatch_create_events` (app/models/message.rb:401-412) |

A UI expõe exatamente esses 5 (`app/javascript/dashboard/routes/dashboard/settings/automation/constants.js:613-634`). Outros eventos do sistema (`CONVERSATION_STATUS_CHANGED`, `ASSIGNEE_CHANGED`, `TEAM_CHANGED`, `CONVERSATION_BOT_HANDOFF`, `FIRST_REPLY_CREATED`, etc. — `lib/events/types.rb`) **existem no barramento mas não têm handler no engine de automação** (são consumidos por outros listeners).

**Execução é 100% assíncrona:** `AutomationRuleListener` só está no `AsyncDispatcher` (`app/dispatchers/async_dispatcher.rb:13`). O `Dispatcher` central (`app/dispatchers/dispatcher.rb:15-18`) publica todo evento no sync (`ActionCableListener`, `AgentBotListener` — sync_dispatcher.rb:8) e enfileira `EventDispatcherJob` (fila `:critical`, retry 3× polinomial — `app/jobs/event_dispatcher_job.rb:1-16`) que publica para os listeners async. Listeners async (async_dispatcher.rb:11-25): AutomationRuleListener, **Spx::Tozi::FunnelAutomationListener** (fork), Campaign, Csat, Nps, Hook, InstallationWebhook, Notification, Participation, ReportingEvent, Webhook + **CaptainListener** via Enterprise (`enterprise/app/dispatchers/enterprise/async_dispatcher.rb:1-7`).

**Guards do listener** (automation_rule_listener.rb):
- `performed_by_automation?` (73-75): evento com `performed_by` = AutomationRule é ignorado (anti-loop).
- `ignore_auto_reply_event?` (77-80): `conversation.additional_attributes['auto_reply']` pula `conversation_created`/`conversation_opened`.
- `message_created` ignora activity, auto-reply de e-mail e mensagens geradas por automação (`content_attributes['automation_rule_id']`) (82-86).
- **Cache de 2 minutos** dos ids de regras ativas por conta+evento (65-71) — criar/desativar regra demora até 2 min para valer.

### 3.3 Condições — avaliação

`AutomationRules::ConditionsFilterService` (`app/services/automation_rules/conditions_filter_service.rb`): reconstrói as condições como **SQL contra o estado ATUAL do banco** (`base_relation` = a própria conversa com joins de contacts/messages/tags, 185-203) e retorna `records.any?`. Erro em qualquer condição → rescue → `false` (39-43). Atributos válidos vêm de `lib/filters/filter_keys.yml`:

- **conversations:** status, assignee_id, inbox_id, team_id, priority, display_id, campaign_id, labels, browser_language, conversation_language, referer, created_at, last_activity_at, mail_subject (filter_keys.yml:16-122)
- **contacts:** name, phone_number, email, identifier, country_code, city, company, labels, created_at, last_activity_at, blocked (124-208)
- **messages:** message_type, content (210-217)
- **custom attributes** (conversation/contact) (conditions_filter_service.rb:73-76)
- Operador especial **`attribute_changed`** com `values: {from: [...], to: [...]}` avaliado contra `event.data[:changed_attributes]` (80-108). ⚠️ Para `conversation_opened`/`conversation_resolved` o payload `changed_attributes` é `status_change` capturado **pós-commit** (conversation.rb:388) — método Dirty que tende a estar vazio depois do save; na prática `attribute_changed` é confiável apenas em `conversation_updated` (que recebe `previous_changes`, conversation.rb:260-262, 356) — verificar antes de depender disso para distinguir "reabertura" de "primeira abertura".

Validação prévia: `AutomationRules::ConditionValidationService` (`app/services/automation_rules/condition_validation_service.rb`) — checa attribute_key/filter_operator contra o YAML; falha → regra não roda + `authorization_error!`.

### 3.4 Ações — TODAS, com implementação

Base compartilhada `ActionService` (`app/services/action_service.rb`) — usada por automações E macros:

| Ação | Implementação | Observações |
|---|---|---|
| `mute_conversation` | :9-11 `mute!` | resolve + bloqueia contato |
| `snooze_conversation` | :13-15 `snoozed!` | sem snoozed_until (indefinido) |
| `resolve_conversation` | :17-19 `resolved!` | ⚠️ sujeito à validação team_required |
| `open_conversation` | :21-23 `open!` | |
| `pending_conversation` | :25-27 `pending!` | ⚠️ sujeito a `pending_status_allowed_by_inbox` (conversation.rb:324-330, fork) |
| `change_status` | :29-31 | status arbitrário |
| `change_priority` | :33-35 | 'nil' limpa |
| `add_label` | :37-41 | `add_labels` (append) |
| `remove_label` | :55-60 | recalcula label_list |
| `assign_agent` | :43-53 | **`'nil'` → `update!(assignee_id: nil)` (desatribui)**; valida que o agente é membro do inbox ou admin (95-100) e `confirmed?` |
| `assign_team` | :62-73 | `'nil'`/`'0'`/blank → `update!(team_id: nil)`; valida time da conta (102-104); não valida membros |
| `remove_assigned_team` | :75-77 | |
| `send_email_transcript` | :79-91 | rate limit de e-mail da conta |
| `add_sla` (Enterprise) | enterprise/app/services/enterprise/action_service.rb:2-11 | só se não tem SLA |

Específicas de automação — `AutomationRules::ActionService` (`app/services/automation_rules/action_service.rb`):

| Ação | Implementação |
|---|---|
| `send_message` | :43-48 — `Messages::MessageBuilder` outgoing com `content_attributes.automation_rule_id` (marca anti-loop) |
| `add_private_note` | :50-55 — idem, private |
| `send_attachment` | :25-36 — blobs anexados na regra |
| `send_webhook_event` | :38-41 — `WebhookJob` com `conversation.webhook_data` + `event: "automation_event.<event_name>"` |
| `send_email_to_team` | :57-66 — mailer para membros dos times |

Mecânica de execução (action_service.rb:1-21): construtor seta **`Current.executed_by = rule`** (linha 6) — é assim que os eventos derivados ficam marcados como "da automação" e a atividade sai como "via automação" (`activity_message_handler.rb:81-88`, `assignee_activity_message_handler.rb:23-26`, `priority_activity_message_handler.rb:10`). `perform` itera as ações com `@conversation.reload` antes de cada uma e **rescue por ação** (exceção é engolida e trackada; as demais ações continuam). `ensure → Current.reset`.

### 3.5 Macros

- Model `app/models/macro.rb` — `ACTIONS_ATTRS` (33-35): `send_message add_label assign_team assign_agent mute_conversation change_status remove_label remove_assigned_team resolve_conversation snooze_conversation change_priority send_email_transcript send_attachment add_private_note send_webhook_event`. Visibilidade `personal`/`global` (agente só cria personal, 37-40). Sem overlay Enterprise além de audit.
- Runner: `Macros::ExecutionService < ActionService` (`app/services/macros/execution_service.rb`) — roda **como o usuário** (`Current.user = user`, linha 7; mensagens saem com o user como sender); `assign_agent` aceita `'self'` (31-34); `mark_as_unread!` se o assignee mudou (20, 27-29); `send_webhook_event` com `event: 'macro.executed'` (72-75).
- Disparo: `POST /api/v1/accounts/:id/macros/:macro_id/execute` com `conversation_ids` (display_ids) → `MacrosExecutionJob` (fila :medium) → ExecutionService por conversa (`app/jobs/macros_execution_job.rb`, rota em config/routes.rb:114-116).
- ⚠️ Macro **não** seta `Current.executed_by` → os eventos que ela gera (ex.: resolved) **podem disparar automation rules** (não há marca anti-loop; só as mensagens enviadas por automação têm a marca).

---

## 4. AutomationRule #53 "iniciar zerado" — anatomia completa da execução

Regra em produção: `event_name='conversation_opened'`, condição `inbox_id IN (61,62,91)`, ações `assign_agent ['nil']` + `assign_team ['nil']`.

### 4.1 Sequência exata quando um lead responde a uma conversa resolvida (inbox 91, sem bot ativo)

1. **Incoming persiste** → `Message#execute_after_create_commit_callbacks` (`app/models/message.rb:341-350`) chama `reopen_conversation` (343) **antes** de `dispatch_create_events` (346).
2. **`reopen_conversation`** (443-452): incoming + resolved → `reopen_resolved_conversation` (466-476):
   - `inbox.active_bot?` → **`pending!`** (o limbo conhecido). `active_bot?` = AgentBot/dialogflow (inbox.rb:172-175) **OU** Captain conectado com cota (`Enterprise::Inbox#active_bot?/captain_active?`, enterprise/app/models/enterprise/inbox.rb:10-16).
   - inbox `api?` → `open!` com `Current.executed_by = sender` (atividade "system_auto_open").
   - senão (caso WhatsApp Cloud sem bot) → **`open!`**.
3. **Dentro do próprio `open!`** (after_save, ainda síncrono): `AutoAssignmentHandler#run_auto_assignment` — se a conversa está sem assignee e `enable_auto_assignment`, o round-robin legacy pode atribuir um agente **online** na hora. Se já tem assignee (ex.: o corretor do disparo), não roda (auto_assignment_handler.rb:45).
4. **after_update_commit** → `notify_status_change` (conversation.rb:380-390) despacha **`CONVERSATION_OPENED`** com `performed_by: Current.executed_by` (392-396) — aqui `executed_by` não é AutomationRule, então a regra vai rodar.
5. **Dispatcher** (dispatcher.rb:15-18): sync listeners primeiro (ActionCable/AgentBot — nenhum mexe em atribuição) e **`EventDispatcherJob.perform_later`** (fila :critical) para o resto.
6. **No worker Sidekiq** (segundos depois): `AutomationRuleListener#conversation_opened` (automation_rule_listener.rb:10-12) → `process_conversation_event` (39-57): busca regras ativas (cache 2 min), `ConditionsFilterService` reavalia **contra o estado atual do banco** (`inbox_id=91` ✓) → `AutomationRules::ActionService#perform`.
7. **Ações**: `Current.executed_by = #53`; `assign_agent(['nil'])` → `update!(assignee_id: nil)` (action_service.rb:43-44); `assign_team(['nil'])` → `update!(team_id: nil)` (62-73). Cada uma com `reload` antes.
8. **Efeitos colaterais dos updates**: `AssignmentHandler` after_commit despacha `ASSIGNEE_CHANGED`/`TEAM_CHANGED` + `CONVERSATION_UPDATED` — todos com `performed_by=#53`, então o AutomationRuleListener **ignora** o `conversation_updated` derivado (anti-loop, 73-75). Atividade registrada como automação. `mark_as_unread!` roda.
9. **`NotificationListener#assignee_changed`**: `assignee.blank?` → return (notification_listener.rb:24). **Ninguém é notificado da desatribuição.**

**Resultado:** conversa aberta, sem dono, sem time, sem notificação — exatamente o sintoma "Não atribuída". Com a custom role restritiva (corretor só vê o que está atribuído a ele) e a secretária fora da fila certa, a conversa fica órfã.

### 4.2 Ordem relativa — por que a regra SEMPRE ganha

- Tudo que atribui **no fluxo síncrono da reabertura** acontece primeiro: o `run_auto_assignment` do after_save (passo 3), a atribuição do `Spx::Tozi::DisparoLeadJob#find_or_create_conversation` (`app/jobs/spx/tozi/disparo_lead_job.rb:121-131` — `update!(assignee_id:)` e depois `open!`), e o auto-assign do `ToggleStatusService` (agente que abre vira assignee — toggle_status_service.rb:36-47).
- A regra #53 roda **depois, assíncrona** (EventDispatcherJob), e zera — **last-write-wins**. Sob fila carregada ou retry (3×, polynomially_longer), o zerar pode chegar **minutos** depois, desfazendo até atribuição manual feita nesse meio-tempo.
- Depois do zerar **não há re-atribuição**: o update de assignee não muda status, então `run_auto_assignment` retorna logo (auto_assignment_handler.rb:14).
- Nuances: `conversation_opened` **não** dispara em conversa criada já `open` (notify_status_change é after_update; criação só emite `conversation_created`) — então a regra não pegava as conversas novas do disparo, só as **reabertas**. E como `pending!`→`open!` também emite `conversation_opened`, a regra zera igualmente conversas saindo do limbo do bot (inclusive o `ensure_conversation_open` do Captain, ver §6).

---

## 5. Superfície REST de orquestração (api/v1/accounts/:account_id)

Rotas em `config/routes.rb:150-195` (conversations) e controllers em `app/controllers/api/v1/accounts/`:

| Endpoint | Controller | O que faz |
|---|---|---|
| `POST /conversations/:conversation_id/assignments` | `conversations/assignments_controller.rb:3-44` | `assignee_id` (User; `assignee_type='AgentBot'` para bot) **ou** `team_id`. Usa `Conversations::AssignmentService` (`app/services/conversations/assignment_service.rb` — assignee zera agent_bot e vice-versa) |
| `POST /conversations/:id/toggle_status` | conversations_controller.rb:90-94 → `Conversations::ToggleStatusService` | `status` open/resolved/pending/snoozed + `snoozed_until`. AgentBot pending→open = `bot_handoff!`; **agente que abre se auto-atribui** (toggle_status_service.rb:36-47); resolver sem team → 422 |
| `POST /conversations/:id/toggle_priority` | :96-99 | prioridade |
| `POST /conversations/:conversation_id/labels` · `GET` idem | `conversations/labels_controller.rb` | substitui o conjunto de labels |
| `POST /conversations/:id/custom_attributes` | :126-129 | ex.: `atendimento_humano=true` trava o Captain (hook_execution_service.rb:138-140) |
| `PATCH /conversations/:id` | :54-56, 143-146 | hoje só `priority` |
| `POST /conversations` | :47-52 | cria conversa (inbox_id/contact_id/source_id, pode incluir 1ª mensagem) |
| `GET/POST/PATCH/DELETE /conversations/:id/participants` | `conversations/participants_controller.rb` | observadores (recebem notificação de msg nova) |
| `POST /conversations/:id/mute|unmute|unread|update_last_seen|transcript` | conversations_controller.rb:70-124 | |
| `POST /bulk_actions` | `bulk_actions_controller.rb:46-67` | type=Conversation; `fields {status, assignee_id, team_id}`, `labels {add:[], remove:[]}`, `snoozed_until` → `BulkActionsJob` |
| `GET/POST/PATCH/DELETE /automation_rules` (+`POST :id/clone`) | `automation_rules_controller.rb` (rotas 111-113) | a IA pode criar/editar/ativar/desativar regras programaticamente |
| `GET/POST/PATCH/DELETE /macros` + `POST /macros/:id/execute` | `macros_controller.rb` (rotas 114-116) | executar pacote de ações em lote de conversas |
| `resources :teams` + `team_members` | rotas 343-350 | CRUD de times e membros |

Guard de acesso por time no controller: `authorize_team_access` (conversations_controller.rb:231-256) — não-admin precisa ser membro do time da conversa. O controller tem `prepend_mod_with` (linha 259) — verificar overlay Enterprise para filtros de role custom (PermissionFilterService atua nos finders).

---

## 6. Interações com o Captain (contexto pra orquestração)

O pipeline pós-mensagem do Captain vive em `Enterprise::MessageTemplates::HookExecutionService` (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb`):
- `trigger_templates` → `should_process_captain_response?` (129-135): responde em **pending E open**, exige incoming + `captain_assistant` + **não** travado por `custom_attributes['atendimento_humano']` (138-140).
- `process_captain_behavior` (32-44): copilot p/ notas privadas → `RouterService.should_respond?` (whitelist `only_contact_phones`, `skip_labels`, `skip_after_human_response` — `enterprise/app/services/captain/behavior/router_service.rb:12-16`) → **`ensure_conversation_open`** (59-71): tira a conversa de pending assim que a IA assume, com `Current.executed_by = assistant` — ⚠️ esse `open!` também emite `conversation_opened` e **aciona a regra #53** (o executed_by é assistant, não AutomationRule, então não há skip).
- handoff por cota: `perform_handoff` (142-154).
- Reabertura por resposta humana em pending: `Enterprise::Message#mark_pending_conversation_as_open_for_human_response` (`enterprise/app/models/enterprise/message.rb:4-35`) — o stub OSS `captain_pending_conversation? → false` (message.rb:462-464) é **sobrescrito** no overlay: pending + `CaptainInbox.exists?(inbox_id:)` → resposta humana (não-template) reabre. *Nota: o STATE.md descreve isso como "stubbado false"; no branch atual o overlay Enterprise implementa o comportamento — a verificação que vale é se o código em produção tem esse overlay.*
- Ferramentas de atribuição da IA: `Captain::Tools::Copilot::AssignConversationService` (`enterprise/app/services/captain/tools/copilot/assign_conversation_service.rb` — assign agente/time por display_id, exige permissão `conversation_manage`) e `HandoffTool` (§1.5).
- Listener fork de funil: `Spx::Tozi::FunnelAutomationListener` (`app/listeners/spx/tozi/funnel_automation_listener.rb`) — `message_created` (incoming em estágio de espera → "Em Conversa" + cancela cadência) e `assignee_changed` (humano assumiu → "Qualificado"). É o template de como plugar lógica orquestradora no barramento.

---

## 7. Gaps e riscos

1. **#53 é estruturalmente perigosa**: `conversation_opened` não distingue origem da abertura (primeira vez × reabertura × saída de pending × IA assumindo). O payload `changed_attributes` do evento opened (`status_change` pós-commit, conversation.rb:388) aparenta chegar vazio — o filtro `attribute_changed` from/to provavelmente não funciona para esse evento (funciona no `conversation_updated`, que recebe `previous_changes`). Resultado: não há como, com o engine atual, escrever "zerar só na primeira abertura".
2. **Execução assíncrona + retry** = corrida garantida contra qualquer atribuição síncrona (disparo, toggle_status, auto-assignment) e até manual. Last-write-wins sem arbitragem.
3. **Desatribuição é silenciosa**: NotificationListener ignora assignee nil (notification_listener.rb:24) e ignora conversas pending (26) — duplo silêncio no fluxo problemático da Tozi.
4. **Auto-assignment legacy só online** (agent_assignment_service.rb:23-28) — em operação com corretores que ficam offline, conversas reabertas ficam sem dono mesmo com `enable_auto_assignment` ligado.
5. **Sem evento temporal**: o engine não tem trigger "sem resposta há X" / inatividade — follow-up nativo via automation rule é impossível; é por isso que a cadência Tozi vive em jobs próprios (`ScheduledMessages`, `FollowupHsmJob`).
6. **`sync_team_from_assignee`** (assignment_handler.rb:22-36) muda/zera o team como efeito colateral de atribuir agente — interage mal com `team_required_for_resolution` e com regras que setam team.
7. **Cache de 2 min** das regras (automation_rule_listener.rb:65-71): janela de inconsistência ao ativar/desativar regra em incidente.
8. **Exceções engolidas por ação** (automation_rules/action_service.rb:13-17): regra meio-aplicada (ex.: zerou agente mas falhou no team) sem visibilidade.
9. **Macro sem `executed_by`**: ações de macro re-disparam automações (sem marca anti-loop fora de mensagens).
10. **`ensure_conversation_open` do Captain × #53**: a IA tira do pending → regra zera atribuição — qualquer estratégia de "IA atribui ao assumir" precisa considerar essa ordem.
11. **V2 desligado por flag**: toda a infra de assignment policy/capacidade/balanceamento (que resolveria distribuição entre corretores) existe no código mas depende de `assignment_v2` + `assignment_policy` configurados.

---

## 8. Pontos de plugue para a IA orquestradora

1. **Listener custom no AsyncDispatcher** (padrão já provado pelo fork): registrar um `Spx::*Listener` em `AsyncDispatcher#listeners` (async_dispatcher.rb:11-25) ouvindo `message_created`, `conversation_opened`, `assignee_changed`, `team_changed`, `conversation_bot_handoff` — com rescue por handler (ver comentário em funnel_automation_listener.rb:5-7).
2. **`send_webhook_event` de automation rule** (automation_rules/action_service.rb:38-41): payload `conversation.webhook_data` + `automation_event.<event_name>` para um endpoint da IA — regra nativa vira trigger de orquestração externa sem código.
3. **Webhooks de conta** (`WebhookListener` no async dispatcher) para os eventos padrão (message_created, conversation_status_changed etc.).
4. **REST**: `POST /conversations/:id/assignments` (agente/time), `toggle_status`, `labels`, `custom_attributes`, `bulk_actions`, `macros/:id/execute`, CRUD de `automation_rules` — superfície completa para uma IA decidir e aplicar triagem/atribuição (§5).
5. **Pipeline do Captain**: `Enterprise::MessageTemplates::HookExecutionService#trigger_templates` é o ponto de injeção determinístico pós-mensagem (router → open → debounce → `ResponseBuilderJob`); o `behavior` JSONB do assistant (RouterService) é a config code-first.
6. **Tools do Captain**: `assign_conversation` (copilot) e `HandoffTool` — a IA conversacional já consegue atribuir; falta roteamento por time/nicho (TODO documentado em handoff_tool.rb:74-84).
7. **`Current.executed_by`** (lib/current.rb): qualquer serviço orquestrador server-side deve setar `executed_by` para (a) autoria correta nas atividades e (b) participar do anti-loop do engine.
8. **`custom_attributes['atendimento_humano']`** como kill-switch já honrado pelo pipeline (hook_execution_service.rb:138-140) — a IA pode se auto-travar por conversa via endpoint de custom_attributes.
9. **Infra V2 de assignment** (policies/capacity/balanced): ligar `assignment_v2` + criar `AssignmentPolicy` dá round-robin com rate-limit e balanceamento nativos por inbox — candidata a substituir o "round-robin manual" dos scripts de disparo.

---

## 9. Arquivos-chave (índice)

| Path | Papel |
|---|---|
| `app/models/concerns/auto_assignment_handler.rb` | Gatilho after_save do auto-assignment (legacy × V2) |
| `app/models/concerns/assignment_handler.rb` | Consistência assignee↔team, eventos ASSIGNEE/TEAM_CHANGED, mark_as_unread |
| `app/services/auto_assignment/agent_assignment_service.rb` | Round-robin legacy (só online) |
| `app/services/auto_assignment/inbox_round_robin_service.rb` | Fila round-robin em Redis |
| `app/services/auto_assignment/assignment_service.rb` | Assignment V2 (bulk, policy, rate limit) |
| `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb` | Override: capacidade, balanced, exclusões |
| `enterprise/app/services/enterprise/auto_assignment/capacity_service.rb` | Limite de conversas por agente/inbox |
| `enterprise/app/services/enterprise/auto_assignment/balanced_selector.rb` | Seleção por menor carga |
| `app/jobs/auto_assignment/{assignment_job,periodic_assignment_job}.rb` · `app/jobs/inboxes/bulk_auto_assignment_job.rb` | Jobs/crons de atribuição (schedule.yml:53-64) |
| `app/models/team.rb` | Team (allow_auto_assign, funil default do fork) |
| `app/models/automation_rule.rb` · `enterprise/app/models/enterprise/automation_rule.rb` | Model do engine + overlay SLA |
| `app/listeners/automation_rule_listener.rb` | Os 5 eventos do engine, guards, cache 2min |
| `app/services/automation_rules/{conditions_filter_service,condition_validation_service,action_service}.rb` | Condições (SQL) e ações |
| `app/services/action_service.rb` · `enterprise/app/services/enterprise/action_service.rb` | Catálogo base de ações (+add_sla) |
| `app/models/macro.rb` · `app/services/macros/execution_service.rb` · `app/jobs/macros_execution_job.rb` | Macros (model/runner/job) |
| `app/dispatchers/{dispatcher,sync_dispatcher,async_dispatcher}.rb` · `app/jobs/event_dispatcher_job.rb` | Barramento de eventos (sync × async) |
| `app/models/conversation.rb` | Dispatch de CONVERSATION_* (notify_status_change:380-390), validações fork (team p/ resolver:316-322, pending gateado:324-330) |
| `app/models/message.rb` | reopen_conversation:443-452 / reopen_resolved_conversation:466-476 (origem do pending-limbo e da reabertura) |
| `enterprise/app/models/enterprise/message.rb` | Reabertura de pending por resposta humana (overlay) |
| `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb` | Pipeline Captain pós-mensagem (router/open/debounce/kill-switch) |
| `enterprise/lib/captain/tools/handoff_tool.rb` · `enterprise/app/services/captain/tools/copilot/assign_conversation_service.rb` | Atribuição feita pela IA |
| `app/listeners/notification_listener.rb` | Notificações (silêncio em pending/assignee nil) |
| `app/listeners/spx/tozi/funnel_automation_listener.rb` | Listener fork (padrão de plugue) |
| `app/controllers/api/v1/accounts/conversations_controller.rb` + `conversations/{assignments,labels,participants}_controller.rb` + `bulk_actions_controller.rb` + `automation_rules_controller.rb` + `macros_controller.rb` | Superfície REST |
| `config/routes.rb:150-195, 111-116, 343-350` | Rotas |
| `lib/filters/filter_keys.yml` | Atributos válidos de condição |

## 10. Questões em aberto

1. O payload `changed_attributes` do `conversation_opened` (`status_change` pós-commit, conversation.rb:388) chega vazio em produção? Se sim, confirmado que não dá para condicionar a regra #53 a from/to de status; se não, dá para reescrevê-la como "zerar só quando from=pending".
2. A Account 6 tem a flag `assignment_v2`? (Determina se os crons de 15/30 min atuam e se a infra de AssignmentPolicy está disponível para distribuir entre corretores.)
3. `enable_auto_assignment` está ligado na inbox 91? (Default é true — se sim, o round-robin legacy pode estar atribuindo a quem estiver online no momento da reabertura, antes da #53 zerar — ruído no diagnóstico.)
4. Existem outras automation rules ativas na conta 6 além da #53 (ordem de execução entre regras do mesmo evento é por id, sem prioridade explícita)?
5. O overlay `Enterprise::Message#mark_pending_conversation_as_open_for_human_response` está no código rodando em produção (deploy AWS diverge do repo)? Determina se resposta humana hoje já tira conversa do limbo pending.
