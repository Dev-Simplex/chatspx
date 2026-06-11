# Mapeamento — Ciclo de vida da conversa (SPX / fork Chatwoot)

> Área: **lifecycle-conversa** · Branch `paulao` · Gerado em 2026-06-10
> Tudo baseado em leitura do código local. Referências `arquivo:linha`. As duas árvores (`app/` e `enterprise/`) foram verificadas.

---

## 1. Estados

`Conversation` tem 4 estados (`app/models/conversation.rb:79`):

```ruby
enum status: { open: 0, resolved: 1, pending: 2, snoozed: 3 }
```

Campos correlatos do schema (conversation.rb:1-52): `snoozed_until`, `waiting_since`, `first_reply_created_at`, `last_activity_at`, `agent_last_seen_at`, `assignee_last_changed_at` (via AssignmentHandler), `campaign_id`, `assignee_agent_bot_id`.

Invariantes mantidas por callback:
- `resolved ⇒ waiting_since IS NULL` — `handle_resolved_status_change` limpa via `update_column` (conversation.rb:289-296).
- `não-snoozed ⇒ snoozed_until IS NULL` — `ensure_snooze_until_reset` em `before_save` (conversation.rb:150, 298-300).
- `assignee presente ⇒ assignee_agent_bot_id nil` — `reset_agent_bot_when_assignee_present` (conversation.rb:71, 310-314).

### 1.1 Validações fork-specific que GATEIAM transições (não existem no upstream)

1. **`pending_status_allowed_by_inbox`** (conversation.rb:77, 324-330; migração `db/migrate/20260417120000_add_pending_status_enabled_to_inboxes.rb`, commit `da2ea07ed` 17/04/2026): transição para `pending` só é válida se `inbox.pending_status_enabled?` (coluna boolean, default **false**). Erro: "cannot be Pending — feature disabled for this inbox".
2. **`team_required_for_resolution`** (conversation.rb:76, 316-322; veio no commit `a62c90318` "kanban v2", 19/02/2026): resolver exige `team_id` presente, a menos que `skip_team_required_for_resolution_validation` esteja setado (attr_accessor, conversation.rb:65).

Esses dois gates mudam o comportamento de TODO código que chama `pending!`/`resolved!` (que usam `update!` → raise `RecordInvalid`) ou `save`/`toggle_status` (falha silenciosa). Ver riscos na §10.

---

## 2. Status no NASCIMENTO da conversa

`before_create :determine_conversation_status` (conversation.rb:151, 332-338):

```ruby
self.status = :resolved and return if contact&.blocked?         # contato bloqueado nasce resolved
return handle_campaign_status if campaign.present?
self.status = :pending if inbox.active_bot? && inbox.pending_status_enabled?
```

- **Com bot ativo + pending habilitado na inbox** → nasce `pending` (o bot vai atender).
- **Campanha** (`handle_campaign_status`, conversation.rb:340-343): nasce `pending` só se `campaign.sender_id.nil?` (campanha bot-initiated) E bot ativo E pending habilitado; senão default `open`.
- Sem bot → default `open` (enum default, schema linha 17).

Caminhos de criação relevantes:
- **WhatsApp Cloud incoming** — `Whatsapp::IncomingMessageBaseService#set_conversation` (app/services/whatsapp/incoming_message_base_service.rb:131-142): com `lock_to_single_conversation` na inbox, reusa a ÚLTIMA conversa do contact_inbox (mesmo resolvida — quem reabre é o callback da Message, §3); sem lock, reusa a última não-resolvida ou cria nova.
- **ConversationBuilder** (app/builders/conversation_builder.rb:27-39): com `lock_to_single_conversation`, busca por `inbox_id + contact_id` (cobre múltiplos contact_inboxes do mesmo contato!) priorizando não-resolvida; usa lock Redis (linhas 12-25).
- **Meta Lead Ads** — `Meta::LeadAds::CreateConversationService` (app/services/meta/lead_ads/create_conversation_service.rb:111-127): nasce `pending` se `pending_status_enabled?`, senão `open` (linha 126).
- **Disparo Tozi** — `Spx::Tozi::DisparoLeadJob#find_or_create_conversation` (app/jobs/spx/tozi/disparo_lead_job.rb:121-143): reusa conversa única do contato (lock_to_single manual: não-resolvida → mais recente de qualquer status); se reusa: atribui corretor, seta `campaign_id`, **`open!` se não-open** (linha 129); se cria: nasce `status: 'open'` com assignee já setado (linha 133-142). `resolved_source_id` (linhas 112-116) reconcilia 9º dígito via `Whatsapp::PhoneNumberNormalizationService` (fix das fichas duplicadas).

---

## 3. Mensagem incoming chegando — a máquina central

`Message#after_create_commit :execute_after_create_commit_callbacks` (app/models/message.rb:145, 341-350) roda **nesta ordem**:

1. `reopen_conversation`
2. `mark_pending_conversation_as_open_for_human_response`
3. `set_conversation_activity` (touch `last_activity_at` via `update_columns` — sem callbacks, message.rb:490-494)
4. `dispatch_create_events` (MESSAGE_CREATED etc.)
5. `send_reply` (SendReplyJob — entrega no canal)
6. `execute_message_template_hooks` (→ HookExecutionService → pipeline Captain)
7. `update_contact_activity`

### 3.1 `reopen_conversation` (message.rb:443-452)

```ruby
return if conversation.muted?                  # contato bloqueado
return if conversation.contact&.blocked?
return unless incoming?                        # SÓ INCOMING reabre
return if response_to_active_nps_survey?       # NpsSurveys::ReopenGuard (message.rb:504-506)

conversation.open! if conversation.snoozed?    # snoozed + incoming → open
reopen_resolved_conversation if conversation.resolved?
```

### 3.2 `reopen_resolved_conversation` (message.rb:466-476) — **A RESPOSTA EXATA**

Quando uma incoming chega numa conversa **resolved**:

```ruby
if conversation.inbox.active_bot?
  conversation.pending!          # COM bot ativo → PENDING (bot deve assumir)
elsif conversation.inbox.api?
  Current.executed_by = sender if reopened_by_contact?   # autor da atividade = contato
  conversation.open!
else
  conversation.open!             # SEM bot → OPEN (visível na fila)
end
```

- **SEM bot na inbox**: conversa reabre **open** — aparece na aba Abertas, gera CONVERSATION_OPENED (automations), notificações etc.
- **COM bot na inbox** (`active_bot? == true`): conversa vai pra **pending** — a expectativa do design é que o bot processe e (agora) promova pra open ao assumir. `pending` NÃO aparece na aba Abertas e o `NotificationListener` **ignora conversas pending** (app/listeners/notification_listener.rb:4, 11, 26) — invisibilidade dupla.
- ⚠️ `pending!` aqui **não checa** `pending_status_enabled?` — se a inbox tem bot mas pending desabilitado, `update!` levanta `RecordInvalid` DENTRO do after_commit, abortando os callbacks 2-7 (a mensagem persiste, mas MESSAGE_CREATED/automations/webhooks/hooks Captain não rodam). Risco real, ver §10.
- `reopened_by_contact?` (message.rb:478-480): incoming público de Contact → a atividade "reaberta" sai em nome do contato.

### 3.3 `active_bot?` vs `captain_active?` — definições exatas

- **OSS `Inbox#active_bot?`** (app/models/inbox.rb:172-175): `agent_bot_inbox&.active? || hooks dialogflow enabled`.
- **Enterprise override** (enterprise/app/models/enterprise/inbox.rb:10-12): `super || captain_active?` — Captain conectado também conta como bot ativo.
- **`captain_active?`** (enterprise/app/models/enterprise/inbox.rb:14-16): `captain_assistant.present? && more_responses?` — i.e., existe `CaptainInbox` ligando a inbox a um assistant (enterprise/app/models/enterprise/concerns/inbox.rb:6) **E a conta tem cota de respostas Captain disponível** (`account.usage_limits[:captain][:responses][:current_available].positive?`, linhas 20-22).

Consequência sutil: **cota esgotada ⇒ `captain_active?` false ⇒ `active_bot?` pode virar false** ⇒ incoming em resolved passa a reabrir como `open` (não pending). Mas o `HookExecutionService` checa `captain_assistant.present?` (não a cota) para decidir processar, e com cota zerada executa `perform_handoff` (§5.3).

---

## 4. PENDING — o que coloca e o que tira

### 4.1 Entradas em pending

| # | Gatilho | Ator | Código |
|---|---------|------|--------|
| 1 | Criação de conversa com bot ativo + pending habilitado | sistema | conversation.rb:337 |
| 2 | Criação via campanha bot-initiated | sistema | conversation.rb:342 |
| 3 | Incoming em conversa resolved com `active_bot?` | contato | message.rb:469 |
| 4 | Automation rule / macro `pending_conversation` ou `change_status` | automação | app/services/action_service.rb:25-27, 29-31 |
| 5 | Copilot tool `change_status` (status=pending) | IA copilot | enterprise/app/services/captain/tools/copilot/change_status_service.rb:15 |
| 6 | API `toggle_status` com `status: pending` | humano/API | Conversations::ToggleStatusService:11-13, 40-43 |
| 7 | Meta Lead Ads (inbox com pending habilitado) | webhook | app/services/meta/lead_ads/create_conversation_service.rb:126 |

### 4.2 Saídas de pending

| # | Gatilho | Para | Código |
|---|---------|------|--------|
| 1 | **Captain assume (router passou)** — commit `f96ae7740` (09/06/2026) | open | enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:39, 59-71 (`ensure_conversation_open`, com `Current.executed_by = assistant` pra atividade sair como "Clara") |
| 2 | **Resposta humana pública** (não-privada, não-template-bootstrap) em inbox com CaptainInbox | open | enterprise/app/models/enterprise/message.rb:4-24 (`mark_pending_conversation_as_open_for_human_response`) + activity i18n `captain.auto_opened_after_agent_reply` (linhas 37-45) |
| 3 | Agente abre manualmente (UI/API toggle_status) | open | conversation.rb:187-192 (`toggle_status`: pending → open); Conversations::ToggleStatusService:15 |
| 4 | **AgentBot** chama toggle_status pending→open via API | open + CONVERSATION_BOT_HANDOFF | toggle_status_service.rb:9-10, 30-34 (`pending_to_open_by_bot?` → `bot_handoff!`) |
| 5 | Captain SEM cota (`!captain_active?`) recebe incoming | open + msg EN "Transferring to another agent..." | hook_execution_service.rb:7, 142-154 (`perform_handoff`, só se pending) |
| 6 | Captain decide handoff (`conversation_handoff`) ou erro de LLM em pending | open | enterprise/app/jobs/captain/conversation/response_builder_job.rb:124-137 (`process_action('handoff')` → `bot_handoff!`), 261-265 (`handle_error` → handoff se pending) |
| 7 | Tool `handoff` chamada pelo agente IA | open + auto-assign round-robin | enterprise/lib/captain/tools/handoff_tool.rb:26-64 (`bot_handoff!` + `AutoAssignment::AgentAssignmentService`) |
| 8 | **Auto-resolve do Captain** — pending inativa > 1h | resolved (legacy) ou resolved/open (evaluated) | enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb:25-47, 56-71 (cutoff fixo 1h, linha 69-71) |
| 9 | Automation/macro `open_conversation` | open | action_service.rb:21-23 |
| 10 | Jobs Tozi (disparo reusa conversa; follow-up HSM) | open | disparo_lead_job.rb:129; followup_hsm_job.rb:21 |

**O que NÃO tira de pending:** incoming do contato quando o router do Captain dá skip (whitelist/labels/grupos — `log_and_skip` retorna ANTES do `ensure_conversation_open`, hook_execution_service.rb:34); resposta privada; mensagem de template/campanha (`template_bootstrap_message?`, enterprise/message.rb:32-35 — HSM de disparo sem incoming prévio não conta como resposta humana; aliás o HSM do disparo tem `sender nil`, nem passa em `human_response?`, message.rb:385-394).

### 4.3 O bug do "pending limbo" — anatomia e estado atual

**Cadeia original do incidente (02/06):** inbox 91 com Clara conectada (`CaptainInbox` existe) ⇒ `active_bot? = true` ⇒ cliente que respondia em conversa resolvida caía em `pending!` (message.rb:469) ⇒ Clara com whitelist `behavior.router.only_contact_phones` (Captain::Behavior::RouterService:12, 23-31) dava `router_skip` ⇒ ninguém promovia a conversa ⇒ invisível na aba Abertas E sem notificações (notification_listener.rb:4,11,26) ⇒ o auto-resolve do Captain (scheduler `Enterprise::Account::ConversationsResolutionSchedulerJob:10-21` → `Captain::InboxPendingConversationsResolutionJob`) fechava as pending inativas >1h com mensagem pública.

**Camadas de correção presentes HOJE no código local:**
1. `account.captain_auto_resolve_mode` com kill-switch `'disabled'` checado em DOIS pontos (scheduler enterprise linha 15 e job linha 8). Default do modo: `evaluated` se feature `captain_tasks`, senão `legacy` (app/models/concerns/account_captain_auto_resolve.rb:14-20).
2. Commit `f96ae7740`: `ensure_conversation_open` promove pending→open **quando o router PASSA** (a IA vai atender). Roda ANTES do gate de business hours (hook linha 39 vs 41) — conversa fora de horário com `outside_hours_action=ignore` ainda fica visível, só não é respondida.
3. Override Enterprise `mark_pending_conversation_as_open_for_human_response` (enterprise/app/models/enterprise/message.rb, upstream PRs #13673/#13802): resposta humana pública abre a pending + cria atividade. O stub OSS `captain_pending_conversation? → false` (app/models/message.rb:462-464) **é sobrescrito** pelo prepend (`Message.prepend_mod_with('Message')`, message.rb:515) — a nota do STATE.md de que estava "stubbado false" só vale para a árvore OSS isolada; neste build com `enterprise/` carregado, o auto-open por resposta humana está ATIVO no código local (estado do deploy em prod pode divergir).

**Residual NÃO corrigido:** incoming que cai em `router_skip` (whitelist, skip_labels, grupo, `skip_after_human_response`) continua deixando a conversa **pending invisível** até alguém (humano respondendo, agente abrindo, automação) promovê-la. Por design o commit f96ae7740 considera isso "ruído", mas whitelist em piloto = TODOS os leads reais são ruído.

---

## 5. Pipeline Captain no pós-mensagem (HookExecutionService)

OSS (app/services/message_templates/hook_execution_service.rb:1-62): só dispara templates Out-of-office / Greeting / EmailCollect. `prepend_mod_with` na linha 62.

Enterprise (enterprise/app/services/enterprise/message_templates/hook_execution_service.rb):

1. `trigger_templates` → `super` → `should_process_captain_response?` (linha 129-135): `(pending? || open?) && incoming? && captain_assistant.present? && !human_takeover_locked?`. O Captain responde em **pending E open** (continua após handoff até humano de fato responder).
2. `human_takeover_locked?` (137-140): custom attribute **`atendimento_humano`** truthy trava o bot — o checkbox do painel. **Gancho-chave de orquestração.**
3. Sem cota → `perform_handoff` (142-154): mensagem hardcoded EM INGLÊS + `bot_handoff!` + OOO.
4. Com cota → `process_captain_behavior` (32-44): privada → copilot trigger; `router_allows?` (RouterService, §5.1) senão loga `router_skip` em `Captain::AssistantLog` (95-98); `ensure_conversation_open`; business hours (`outside_hours_ignore?` → loga `business_hours_skip`); `schedule_or_debounce` (73-81): tique azul (`mark_customer_message_read`, 86-93, só WhatsApp Cloud) + debounce ou `Captain::Conversation::ResponseBuilderJob` (com espera extra se anexos, 109-127).

### 5.1 RouterService (enterprise/app/services/captain/behavior/router_service.rb)

`should_respond?` (9-19) bloqueia: activity, mensagem vazia, **whitelist `only_contact_phones`** (com variações de 9º dígito/DDI, 47-63), `skip_labels`, `skip_groups` (detecta grupo por additional_attributes.type, identifier `@g.us`, custom attrs WAHA, 82-95), `skip_agent_bot`, **`skip_after_human_response`** (105-117: olha a última outgoing pública não-NPS; se foi User, bot cala; se foi o próprio assistant, continua).

⚠️ Bug latente: `skip_agent_bot?` chama `@conversation.agent_bot_id` (linha 98) — **Conversation não tem esse atributo/método** (a coluna é `assignee_agent_bot_id`). Ligar `router.skip_agent_bot: true` deve estourar `NoMethodError` a cada mensagem. Verificar antes de habilitar essa flag.

### 5.2 ResponseBuilderJob (enterprise/app/jobs/captain/conversation/response_builder_job.rb)

- `captain_can_respond?` (299-302): re-checa status **uncached** (pending|open) antes E depois de gerar (12, 51) — humano resolvendo no meio aborta o envio.
- Handoff: `@response['response'] == 'conversation_handoff'` → `bot_handoff!` (124-137). Erro → handoff só se ainda pending (261-265, 292-295).
- Não muda status em caso de resposta normal; cria messages com `sender: assistant` (247-259) — que NÃO disparam reopen (são outgoing).
- `reset_followup_state` (87-94): incoming do cliente zera a cadência de cutucadas (custom_attributes `followup_token/count/status`).

### 5.3 `bot_handoff!` (app/models/conversation.rb:199-203)

```ruby
update(waiting_since: Time.current) if waiting_since.blank?
open!
dispatcher_dispatch(CONVERSATION_BOT_HANDOFF)
```

Consumidores do evento: `ReportingEventListener#conversation_bot_handoff` (app/listeners/reporting_event_listener.rb:97-110, dedup 1 por conversa) e `NotificationListener#conversation_bot_handoff` (notifica membros da inbox, exceto se pending). A `HandoffTool` complementa com atribuição round-robin a membro da inbox (handoff_tool.rb:52-64) — hoje sem filtro de "online por nicho" (TODO nas linhas 74-85).

---

## 6. SNOOZE

**Entrar:** `toggle_status` API com `status=snoozed` (+ `snoozed_until` opcional, toggle_status_service.rb:40-43); automation/macro `snooze_conversation` (action_service.rb:13-15 — **sem** snoozed_until = soneca indefinida); Copilot tool `snooze_conversation` (snooze_conversation_service.rb:14 — `snoozed_until = hours.from_now`); BulkActionsJob (app/jobs/bulk_actions_job.rb:35, 63-65).

**Sair (reabrir):**
1. **Incoming do contato** → `open!` imediato (message.rb:449).
2. **`Conversations::ReopenSnoozedConversationsJob`** (app/jobs/conversations/reopen_snoozed_conversations_job.rb:5): `where(status: :snoozed, snoozed_until: 3.days.ago..Time.current).find_each(&:open!)` — enfileirado pelo `TriggerScheduledItemsJob` que roda por cron `*/5 * * * *` (config/schedule.yml:13-16; app/jobs/trigger_scheduled_items_job.rb:12).
3. Manual (`toggle_status`: snoozed → open, conversation.rb:190).

Soneca **indefinida** (snoozed_until nil) só sai por incoming ou manual. `snoozed_until` mais velho que 3 dias fora da janela do job também (edge raro). Reabertura via job dispara CONVERSATION_OPENED → automations (mesma exposição à regra #53).

---

## 7. RESOLVED

**Entradas:**
- Humano: UI/API toggle_status (`Api::V1::Accounts::ConversationsController#toggle_status:90` → ToggleStatusService). Exige team (validate_team_requirement!, toggle_status_service.rb:24-28 + validação do model).
- Contato (widget): `Api::V1::Widget::ConversationsController#toggle_status:57-65` (`save!` — sujeita ao gate de team!).
- **Auto-resolve da conta** (não-Captain): `Account::ConversationsResolutionSchedulerJob` (app/jobs/account/conversations_resolution_scheduler_job.rb, a cada 5min) → `Conversations::ResolutionJob` (app/jobs/conversations/resolution_job.rb:6-30): conversas `open` paradas além de `auto_resolve_after` (scopes `resolvable_not_waiting`/`resolvable_all`, conversation.rb:97-106) → mensagem `AutoResolve` opcional + label + **`toggle_status`** (save sem bang — falha silenciosa se sem team).
- **Auto-resolve do Captain** (pending >1h): §4.2 item 8. Modo `legacy` = resolve direto com `resolution_message`; modo `evaluated` (feature `captain_tasks`) = LLM avalia (`ConversationCompletionService`) e resolve (nota privada "Auto-resolved:" + mensagem pública + `resolved!` com contexto de atividade, linhas 73-81) ou faz handoff (83-92).
- IA: `Captain::Tools::ResolveConversationTool` (enterprise/lib/captain/tools/resolve_conversation_tool.rb:13 — bloqueada se `captain_auto_resolve_disabled?`, linha 9) e Copilot `resolve_conversation`/`change_status`.
- Automation/macro `resolve_conversation` (action_service.rb:17-19).
- `mute!` resolve a conversa + bloqueia contato + resolve TODAS as abertas do contato (app/models/concerns/conversation_mute_helpers.rb:4-11, 26-33 — as outras com skip do gate de team; a própria SEM skip).
- Contato bloqueado: nova conversa nasce resolved (conversation.rb:333).

**Saídas:** incoming → §3.2; jobs Tozi `open!`; manual; automation.

**Efeitos colaterais de resolver:** CONVERSATION_RESOLVED + CONVERSATION_STATUS_CHANGED (conversation.rb:380-390); `waiting_since` limpo (289-296); CSAT (`CsatSurveyListener`), NPS, SLA, reporting; `CaptainListener#conversation_resolved` (enterprise/app/listeners/captain_listener.rb:4-12) gera memória de contato/FAQ se `feature_memory`/`feature_faq` e `captain_active?`; Kanban `move_to_automated_stage` (conversation.rb:157, 443-448).

---

## 8. Eventos e ganchos — inventário completo

### 8.1 Callbacks do model Conversation

| Callback | O quê | Ref |
|---|---|---|
| before_validation | validate_additional_attributes; reset_agent_bot_when_assignee_present | conversation.rb:70-71 |
| before_save | ensure_snooze_until_reset; (AssignmentHandler) ensure_assignee_is_from_team (sincroniza team↔assignee!), set_assignee_last_changed_at | conversation.rb:150; assignment_handler.rb:6-7 |
| before_create | determine_conversation_status; ensure_waiting_since | conversation.rb:151-152 |
| after_create_commit | CONVERSATION_CREATED; load display_id/uuid; **add_to_appropriate_funnel** (Kanban) | conversation.rb:159-161, 345-347, 420-441 |
| after_update_commit | handle_resolved_status_change; **notify_status_change** (CONVERSATION_OPENED/RESOLVED/STATUS_CHANGED/READ/CONTACT_CHANGED); create_activity (mensagens de atividade, ActivityMessageHandler + override Enterprise p/ Captain); notify_conversation_updation (CONVERSATION_UPDATED — pulado se mudou status); update_messages_team_id | conversation.rb:156, 275-296, 349-357, 380-390 |
| after_update_commit (status mudou) | **move_to_automated_stage** (Kanban::MoveConversationToAutomatedStageService) | conversation.rb:157, 443-448 |
| after_update_commit (team mudou) | move_to_team_funnel | conversation.rb:158, 450-455 |
| after_save | **run_auto_assignment** (AutoAssignmentHandler — quando vira open e sem assignee; v2 também em resolved/snoozed p/ rebalancear) | auto_assignment_handler.rb:5-26 |
| after_commit (AssignmentHandler) | ASSIGNEE_CHANGED / TEAM_CHANGED; atividades; **mark_conversation_unread_on_assignment_change** (`mark_as_unread!`) | assignment_handler.rb:8, 55-72 |

Todos os dispatches carregam `performed_by: Current.executed_by` (conversation.rb:392-396) — é assim que atividade/relatório sabem se foi humano, AutomationRule, Contact ou Captain::Assistant (enterprise/app/models/enterprise/activity_message_handler.rb:1-34).

### 8.2 Callbacks do model Message (pós-criação)

Ordem em message.rb:341-350 (§3). `dispatch_create_events` (401-412): **MESSAGE_CREATED** sempre; **FIRST_REPLY_CREATED** + seta `first_reply_created_at` quando `valid_first_reply?` (229-240 — outgoing humano público, exclui Captain/AgentBot/campanha); senão `update_waiting_since` (356-383: resposta humana limpa waiting_since + **REPLY_CREATED**; resposta de bot também limpa, salvo `preserve_waiting_since`; incoming repõe — exceto em resolved); **FIRST_REPLY_AFTER_ASSIGNMENT_CREATED** (422-435). after_update_commit → MESSAGE_UPDATED (147, 414-420).

### 8.3 Dispatcher e listeners

`Rails.configuration.dispatcher` = `Dispatcher` singleton (app/dispatchers/dispatcher.rb) → **SyncDispatcher** (inline): `ActionCableListener`, `AgentBotListener` → **AsyncDispatcher** (via `EventDispatcherJob`): `AutomationRuleListener`, **`Spx::Tozi::FunnelAutomationListener`** (fork), `CampaignListener`, `CsatSurveyListener`, `NpsSurveyListener`, `HookListener`, `InstallationWebhookListener`, `NotificationListener`, `ParticipationListener`, `ReportingEventListener`, `WebhookListener` (async_dispatcher.rb:11-25) + Enterprise adiciona `CaptainListener` (enterprise/app/dispatchers/enterprise/async_dispatcher.rb).

Tipos de evento: `lib/events/types.rb` (inclui CONVERSATION_BOT_HANDOFF, CONVERSATION_CAPTAIN_INFERENCE_RESOLVED/HANDOFF — disparados em enterprise/app/models/enterprise/conversation.rb:4-11).

- `AgentBotListener` (app/listeners/agent_bot_listener.rb): manda webhook pro AgentBot em conversation_resolved/opened, message_created/updated (era o canal do n8n).
- `AutomationRuleListener` (app/listeners/automation_rule_listener.rb): eventos conversation_created/updated/opened/resolved + message_created → `ConditionsFilterService` + `ActionService`. **É aqui que a regra #53 "iniciar zerado" (event conversation_opened) zera assignee+team** — qualquer `open!` programático (Captain assume, disparo reabre, snooze reabre) passa por ela.
- `Spx::Tozi::FunnelAutomationListener` (app/listeners/spx/tozi/funnel_automation_listener.rb): `message_created` incoming em estágio de espera → cancela cadência HSM + move card "Em Conversa" (24-37); `assignee_changed` para User real → move "Qualificado" + cancela cadência (42-52). Modelo de listener custom rescue-wrapped — template pronto pra orquestração.

### 8.4 Jobs com efeito em status

| Job | Efeito | Agendamento |
|---|---|---|
| TriggerScheduledItemsJob | dispara os 3 abaixo | cron `*/5` (config/schedule.yml:13-16) |
| Conversations::ReopenSnoozedConversationsJob | snoozed→open | via acima |
| Account::ConversationsResolutionSchedulerJob (+ override Enterprise) | open inativas→resolved; agenda Captain auto-resolve por CaptainInbox | via acima |
| Captain::InboxPendingConversationsResolutionJob | pending>1h→resolved/handoff | via scheduler |
| Captain::Conversation::ResponseBuilderJob | handoff→open | on-demand |
| Captain::Conversation::FollowupJob (cutucada, enterprise) | não muda status; respeita resolved/trava humana/quiet hours 21h-8h Cuiabá; MAX 4 → move funil "frio" + agenda cadência HSM | agendado pela ProgramarFollowupTool |
| Spx::Tozi::DisparoLeadJob / FollowupHsmJob | open! + assignee | rake/console |
| ScheduledMessages::SendService/SendJob | **não muda status** (envia outgoing em conversa possivelmente resolvida sem reabri-la) | ScheduledMessage |
| BulkActionsJob | status em massa | UI |

---

## 9. Quadro-resumo das transições

| De → Para | Quem dispara |
|---|---|
| (novo) → open | default; disparo Tozi; lead ads sem pending habilitado |
| (novo) → pending | bot ativo + pending habilitado (criação, campanha bot, lead ads) |
| (novo) → resolved | contato bloqueado |
| resolved → pending | incoming + `active_bot?` (message.rb:469) |
| resolved → open | incoming sem bot (message.rb:472-474); jobs Tozi; manual; automation |
| pending → open | Captain assume (f96ae7740); resposta humana (enterprise/message.rb); manual; bot_handoff! (quota/handoff/tool/erro); automation; jobs Tozi |
| pending → resolved | Captain auto-resolve (>1h, se não-disabled); manual; automation; copilot |
| open → resolved | humano; widget (contato); auto-resolve da conta; automation; mute!; IA (tools) |
| open → snoozed | humano; automation (indefinido!); copilot (com horas) |
| snoozed → open | incoming (message.rb:449); job */5min (janela snoozed_until ≤ 3 dias); manual |
| qualquer → open via `toggle_status` | conversation.rb:187-192 (resolved→open; pending/snoozed→open) |

---

## 10. Gaps e riscos identificados

1. **Pending limbo residual**: `router_skip` (whitelist/labels/grupos/`skip_after_human_response`) acontece ANTES do `ensure_conversation_open` (hook:34 vs 39) — conversa segue pending, invisível na fila e sem notificações (notification_listener.rb:4,11,26). Em piloto com whitelist, todo lead real é "ruído". O go-live precisa de uma política explícita pro skip (ex.: abrir mesmo assim, ou rotear pra humano).
2. **`reopen_resolved_conversation` não checa `pending_status_enabled?`**: bot ativo + pending desabilitado na inbox → `pending!` levanta `RecordInvalid` dentro de after_commit, abortando dispatch de MESSAGE_CREATED, webhooks, hooks Captain e SendReply daquela mensagem (message.rb:341-350 interrompido). Hoje inbox 91 tem pending habilitado, mas é mina pra outras inboxes/clientes.
3. **CONVERSATION_OPENED dispara automations em TODA promoção programática**: o fix f96ae7740, o reopen de snooze, o `open!` do DisparoLeadJob e o `bot_handoff!` passam pela AutomationRule #53 (zera assignee/team em conversation_opened, inboxes 61/62/91) — exatamente a regra que desatribuiu os replies de disparo. No DisparoLeadJob a ordem é `update!(assignee)` → `open!` (disparo_lead_job.rb:127-129): a automation roda DEPOIS (async) e pode zerar o corretor recém-atribuído. Orquestração de atribuição precisa coexistir com (ou substituir) essa regra.
4. **`team_required_for_resolution` (fork) quebra resoluções sem team**: `Conversations::ResolutionJob` usa `toggle_status` (save sem bang) → falha silenciosa; `mute!` chama `resolved!` na própria conversa SEM o skip flag → raise; auto-resolve do Captain (`resolved!`) → raise e retry do job; widget `save!` → 500 pro contato. Conversas de inbox 91 frequentemente não têm team.
5. **`perform_handoff` com cota esgotada manda string hardcoded em inglês** "Transferring to another agent for further assistance." pro cliente (hook:150) — sem i18n, sem branding.
6. **Bug latente `router.skip_agent_bot`**: `@conversation.agent_bot_id` não existe (router_service.rb:98) → NoMethodError se a flag for ligada.
7. **Snooze indefinido via automation** (action_service.rb:13-15 sem snoozed_until): só sai com incoming. E o reopen job ignora snoozed_until mais antigo que 3 dias.
8. **Cadência HSM (ScheduledMessages) não reabre a conversa**: outgoing não passa por `reopen_conversation` (incoming-only, message.rb:446) e `SendService` não toca status — HSM de reativação pode ser enviado numa conversa resolved que permanece resolved (estado inconsistente até o lead responder).
9. **Cota Captain muda a semântica do reopen**: cota zerada pode derrubar `active_bot?` → resolved+incoming vira open (não pending). Comportamento correto por acaso, mas acopla billing a roteamento.
10. **Auto-resolve do Captain tem cutoff fixo de 1h** (inbox_pending_conversations_resolution_job.rb:69-71) — não configurável por conta/inbox; ao reativar o modo `evaluated`, mensagens de resolução vêm de `assistant.config['resolution_message']` (fallback i18n).
11. **`skip_after_human_response` olha só a ÚLTIMA outgoing pública**: se o bot respondeu depois do humano, volta a responder (por design, mas vale documentar pro time).

---

## 11. Ganchos concretos para a IA orquestradora

1. **Listener custom no AsyncDispatcher** — padrão `Spx::Tozi::FunnelAutomationListener` (async_dispatcher.rb:14): assinar `message_created`, `conversation_created/opened/resolved`, `assignee_changed`, `team_changed`, `conversation_bot_handoff`, `conversation_status_changed`. Payload inclui `performed_by` (distinguir humano/bot/automação) e `changed_attributes`.
2. **`Enterprise::MessageTemplates::HookExecutionService#process_captain_behavior`** (hook:32-44) — o ponto de decisão "a IA assume?". É ONDE plugar triagem/atribuição: já tem router (whitelist, labels, grupos), trava humana (`atendimento_humano`), business hours, debounce. `ensure_conversation_open` mostra o padrão de transição com autoria (`Current.executed_by = assistant`).
3. **`behavior` JSONB do `Captain::Assistant`** — configuração code-first por API (router/debounce/business_hours/humanizer/dedup) lida a cada mensagem; orquestrador externo pode reconfigurar sem deploy.
4. **`conversation.bot_handoff!` + evento `CONVERSATION_BOT_HANDOFF`** (conversation.rb:199-203) — handoff canônico, com reporting dedupado e notificação a membros. `HandoffTool` (handoff_tool.rb) é o lugar pra evoluir a roleta por nicho/time (TODO já anotado nas linhas 74-85 com assinatura sugerida `team_id`/`priority`/`escalation_level`).
5. **Tools LLM-callable** que mudam estado: `ResolveConversationTool` (gateada por `captain_auto_resolve_mode`), `HandoffTool`, `ProgramarFollowupTool`→`FollowupJob`, `SalvarInfoLeadTool` (move funil); Copilot: `change_status`, `snooze_conversation`, `resolve_conversation`, `assign_conversation` (enterprise/app/services/captain/tools/copilot/).
6. **`custom_attributes` como contrato de orquestração**: `atendimento_humano` (trava o bot, hook:137-140 e followup_job:17), `followup_token/count/status`, `tozi_status_lead` — legíveis/graváveis por API e por automation.
7. **Follow-up em duas camadas já implementado**: dentro da janela 24h = `Captain::Conversation::FollowupJob` (cutucada gerada pelo agente, MAX 4, quiet hours); fora = `Spx::Tozi::ReactivationCadenceService` sobre `ScheduledMessages` com `template_params` HSM (1d/3d/7d), cancelável por incoming (`cancel_pending`). A IA orquestradora pode reusar o mecanismo genérico `ScheduledMessages::CreateService` com `template_params`.
8. **`Current.executed_by`** — setar o assistant antes de transições faz as atividades saírem em nome da IA (enterprise/activity_message_handler.rb) e alimenta relatórios; é o mecanismo de auditoria de quem-fez-o-quê.
9. **Kanban/funil**: `Spx::Tozi::FunnelPlacementService.move/current_type` + `Kanban::MoveConversationToAutomatedStageService` (disparado automaticamente em mudança de status, conversation.rb:157) — estado do lead visível pro time e consultável pela IA.
10. **AutomationRules engine** (`AutomationRuleListener` + `ActionService`): a IA pode criar/ajustar regras via API; mas QUALQUER orquestração via `open!` precisa conviver com regras `conversation_opened` existentes (risco #3).
11. **`AutoAssignment::AgentAssignmentService` / `AssignmentJob` (v2)** — atribuição round-robin com capacidade (auto_assignment_handler.rb:17-25; enterprise/inbox.rb:2-8 limite de carga por agente) — bloco pronto pra "atribuir ao corretor certo".
12. **`waiting_since` + evento `REPLY_CREATED`** (message.rb:356-383) — sinal canônico de "cliente esperando resposta" para SLA/triagem da IA; `Conversation.unread` scope (conversation.rb:89-96) para fila de não-lidas.

---

## 12. Arquivos-chave

| Arquivo | Papel |
|---|---|
| app/models/conversation.rb | Estados, validações-gate, callbacks e eventos de status |
| app/models/message.rb | reopen_conversation / reopen_resolved_conversation / dispatch pós-criação |
| enterprise/app/models/enterprise/message.rb | Auto-open de pending em resposta humana (override real do stub) |
| app/services/message_templates/hook_execution_service.rb | Gancho pós-mensagem OSS (templates) |
| enterprise/app/services/enterprise/message_templates/hook_execution_service.rb | Pipeline Captain: router, ensure_conversation_open (f96ae7740), debounce, handoff por cota, trava humana |
| enterprise/app/models/enterprise/inbox.rb + app/models/inbox.rb:172 | active_bot? / captain_active? |
| enterprise/app/services/captain/behavior/router_service.rb | Whitelist/skips do bot |
| enterprise/app/jobs/captain/conversation/response_builder_job.rb | Resposta do agente, handoff, guards de status |
| enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb | Auto-resolve do Captain (pending>1h) |
| enterprise/app/jobs/enterprise/account/conversations_resolution_scheduler_job.rb | Scheduler do auto-resolve Captain |
| app/jobs/conversations/resolution_job.rb | Auto-resolve da conta (open inativas) |
| app/jobs/conversations/reopen_snoozed_conversations_job.rb + app/jobs/trigger_scheduled_items_job.rb + config/schedule.yml | Reabertura de snooze (cron */5) |
| app/services/conversations/toggle_status_service.rb | Transições manuais/API; bot_handoff de AgentBot |
| app/services/action_service.rb | Ações de automation/macro (status, assign, team) |
| app/dispatchers/*.rb + enterprise/app/dispatchers/enterprise/async_dispatcher.rb | Barramento de eventos sync/async |
| app/listeners/automation_rule_listener.rb | Automations (regra #53 conversation_opened) |
| app/listeners/spx/tozi/funnel_automation_listener.rb | State machine do funil Tozi (modelo de listener custom) |
| enterprise/lib/captain/tools/handoff_tool.rb / resolve_conversation_tool.rb | Tools de transição chamáveis pela IA |
| app/jobs/spx/tozi/disparo_lead_job.rb / followup_hsm_job.rb | Motor de disparo (open! + assignee + conversa única) |
| app/services/spx/tozi/reactivation_cadence_service.rb + app/services/scheduled_messages/send_service.rb | Cadência HSM fora da janela 24h |
| app/models/concerns/{assignment_handler,auto_assignment_handler,activity_message_handler,conversation_mute_helpers,account_captain_auto_resolve}.rb | Atribuição, atividades, mute, modos de auto-resolve |
