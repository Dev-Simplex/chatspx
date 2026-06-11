# Extra 5 — Superfície outbound pra CRM externo (webhooks de conta) + plano AgentBot por conversa + audit_log

> Mapeamento baseado 100% em leitura do código local (branch `paulao`), com referências file:linha.
> Pergunta-guia: a superfície de webhooks de conta é suficiente pra sincronizar funil→Vista? `assignee_agent_bot` serve como "dono bot desta conversa" coexistindo com Captain/`active_bot?`/pending? A API de agent bots está íntegra no fork? Bônus: o audit_log Enterprise responde à dor "operação sem trilha"?

---

## 1. Webhooks de conta — o que existe

### 1.1 Modelo e eventos assináveis

`app/models/webhook.rb`:

- Tabela `webhooks` com `subscriptions` (jsonb), `url`, `webhook_type` (enum `account_type: 0, inbox_type: 1`) — linhas 1-30.
- **Secret por webhook**: `has_secure_token :secret` + `encrypts :secret` (linhas 24-25). Veio do upstream (#13573, commit `c218eff5e` no log do fork) e sobreviveu ao upgrade v4.12.1.
- **Lista fechada de eventos assináveis** (`ALLOWED_WEBHOOK_EVENTS`, linhas 32-34):
  - `conversation_status_changed`, `conversation_updated`, `conversation_created`
  - `contact_created`, `contact_updated`
  - `message_created`, `message_updated`
  - `webwidget_triggered`, `inbox_created`, `inbox_updated`
  - `conversation_typing_on`, `conversation_typing_off`
- Validação de assinaturas em `validate_webhook_subscriptions` (linhas 38-43).
- Auditado: `Webhook.include_mod_with('Audit::Webhook')` (linha 46) → `enterprise/app/models/enterprise/audit/webhook.rb:5` (`audited associated_with: :account, except: [:secret]`).

CRUD da conta: `app/controllers/api/v1/accounts/webhooks_controller.rb` (index/create/update/destroy; permite `inbox_id`, `name`, `url`, `subscriptions: []` — linha 26). O secret é exposto na resposta da API em `app/views/api/v1/accounts/webhooks/_webhook.json.jbuilder:6` (`json.secret webhook.secret`) — é assim que o CRM externo obtém a chave pra validar o HMAC.

### 1.2 Entrega por assinatura (o coração)

`app/listeners/webhook_listener.rb:130-138` — `deliver_account_webhooks`:

```ruby
def deliver_account_webhooks(payload, account)
  account.webhooks.account_type.each do |webhook|
    next unless webhook.subscriptions.include?(payload[:event])

    WebhookJob.perform_later(webhook.url, payload, :account_webhook,
                             secret: webhook.secret,
                             delivery_id: SecureRandom.uuid)
  end
end
```

- Filtro por assinatura é literal (string do evento dentro do array `subscriptions`).
- `delivery_id` é um UUID **gerado por entrega e não persistido em lugar nenhum** (grep em todo o repo: só aparece em listener/job/trigger/specs) — vai no header `X-Chatwoot-Delivery`, mas não há tabela de deliveries, log ou replay.
- O listener roda no `AsyncDispatcher` (`app/dispatchers/async_dispatcher.rb:23`), que despacha via `EventDispatcherJob` (fila `:critical`, `retry_on StandardError attempts: 3`, `discard_on DeserializationError` — `app/jobs/event_dispatcher_job.rb:1-16`).
- Particularidade do fork: pra WAHA (`Channel::Api` com `waha_session_name`) com attachment location/contact, o fluxo desvia pro `Waha::OutboundSpecialMessageService` mas **ainda entrega os webhooks de conta** (`webhook_listener.rb:33-39` e `53-60`).

Eventos cobertos pelo listener e de onde vêm:

| Evento | Handler (webhook_listener.rb) | Origem do dispatch |
|---|---|---|
| `conversation_created` | 18-23 | `Conversation#notify_conversation_creation` (conversation.rb:345-347) |
| `conversation_status_changed` | 2-8 | `Conversation#notify_status_change` (conversation.rb:380-390) |
| `conversation_updated` | 10-16 | `notify_conversation_updation` (conversation.rb:349-357) — **exclui mudanças de status** (linha 354), que vão pelo evento dedicado |
| `message_created` / `message_updated` | 25-42 / 44-63 | callbacks de Message; gated por `webhook_sendable?` = incoming/outgoing/template (`app/models/concerns/message_filter_helpers.rb:8-10`) — **activity e private NÃO disparam** webhook de mensagem (private passa em webhook_sendable? mas chega com `private: true` no payload; activity é cortada) |
| `contact_created` / `contact_updated` | 74-87 | callbacks de Contact (updated exige changed_attributes presentes, linha 83) |
| `inbox_created` / `inbox_updated` | 89-104 | callbacks de Inbox |
| typing on/off | 106-128 | toggle_typing |

**Quais mudanças de conversa geram `conversation_updated`** — `list_of_keys` (conversation.rb:359-362): `team_id`, `assignee_id`, `assignee_agent_bot_id`, `status`(→vai pro evento dedicado), `snoozed_until`, `custom_attributes`, `label_list`, `waiting_since`, `first_reply_created_at`, `priority` (+ `conversation_language` em additional_attributes, linha 367). Ou seja: **atribuição de corretor, mudança de time, etiquetas e custom attributes chegam no CRM externo via `conversation_updated`** com `changed_attributes` no formato `[{attr => {previous_value, current_value}}]` (`app/listeners/base_listener.rb:32-43`).

⚠️ Tudo isso depende de callbacks ActiveRecord: **mudanças via `update_columns`/`delete` (como os scripts de consolidação de duplicatas usaram) não emitem NENHUM webhook** — um CRM espelhado ficaria dessincronizado e precisaria de reconciliação por poll.

### 1.3 O que vai no payload (webhook_data)

**Conversa** — `Conversation#webhook_data` = `Conversations::EventDataPresenter#push_data` (`app/models/concerns/push_data_helper.rb:12-14` → `app/presenters/conversations/event_data_presenter.rb:2-22`):

- Topo: `id` (display_id), `inbox_id`, `status`, `priority`, `snoozed_until`, `waiting_since`, `can_reply` (janela 24h via `Conversations::MessageWindowService`, conversation.rb:165-167), `channel` (ex.: `Channel::Whatsapp`), `contact_inbox` (objeto com `source_id` — o wa_id), `additional_attributes`, **`custom_attributes`**, **`labels`** (label_list), `unread_count`, `first_reply_created_at`, timestamps (40-49).
- `meta` (push_meta, linhas 30-38): **`assignee`** = `assigned_entity&.push_event_data` (User OU AgentBot — conversation.rb:244-246), **`assignee_type`** (`'User'`/`'AgentBot'`/nil — conversation.rb:237-242), **`team`** = `team&.push_event_data`, `sender` = contato completo (`Contact#push_event_data`, contact.rb:152-165, com `phone_number`, `custom_attributes`, `additional_attributes`, `identifier`), `hmac_verified`.
- `messages`: **só a última mensagem** de chat (linha 27).
- Overlay Enterprise (`enterprise/app/presenters/enterprise/conversations/event_data_presenter.rb:2-12`): adiciona `applied_sla`/`sla_events`/`sla_policy_id` se feature `sla` habilitada.

✅ **Respondendo à pergunta: assignee, team, labels e custom_attributes ESTÃO no webhook_data da conversa.**

**Mensagem** — `Message#webhook_data` (`app/models/message.rb:185-203`):

- `account`, `id`, `content` (via `webhook_content`/MessageContentPresenter, linha 211-213), `content_type`, `content_attributes`, **`additional_attributes`** (linha 188), `message_type`, `private`, `source_id` (wa message id), `sender.webhook_data`, `inbox` ({id, name} — inbox.rb:181-186), `attachments` e **`conversation` (webhook_data completo aninhado — linha 192)**.
- **`template_params` vai junto**: HSMs gravam `additional_attributes['template_params']` (schema validado em message.rb:49-64 e 77-79: `name`, `category`, `language`, `namespace`, `processed_params`), e `additional_attributes` inteiro entra no webhook_data (linha 188). `campaign_id` do motor de disparos idem (indexado em messages, linha 32 do schema do model). → **Um CRM consegue distinguir mensagem de campanha/template e qual template foi**, e correlacionar com a campanha.
- Sender pode ser `Captain::Assistant` — tem `webhook_data` próprio com `type: 'captain_assistant'` (`enterprise/app/models/captain/assistant.rb:101-110`) → o CRM consegue distinguir resposta da IA vs humano vs contato.

**Contato** — `Contact#webhook_data` (contact.rb:167-181): `account`, `id`, `name`, `phone_number`, `email`, `identifier`, `additional_attributes`, **`custom_attributes`**, `avatar`, `blocked`.

### 1.4 Garantia de entrega (WebhookJob + Trigger)

`app/jobs/webhook_job.rb:1-9`:
- Fila `:medium`, `retry_on StandardError, wait: :polynomially_longer, attempts: 5`.

`lib/webhooks/trigger.rb`:
- POST JSON com `RestClient`, **timeout 5s default** (configurável via GlobalConfig `WEBHOOK_TIMEOUT`, linhas 108-113).
- **HMAC**: se `secret` presente, headers `X-Chatwoot-Timestamp` (epoch) + `X-Chatwoot-Signature: sha256=HMAC_SHA256(secret, "ts.body")` + `X-Chatwoot-Delivery` (UUID) — linhas 44-53. Timestamp dentro do MAC permite proteção contra replay no receptor.
- **🔴 O retry do WebhookJob é letra morta pra webhooks de conta**: `execute` (linhas 16-24) faz `rescue StandardError => e; handle_failure(e)` e `handle_failure` só loga (linhas 26-29) — **a exceção é engolida, o job nunca re-levanta, `retry_on` nunca dispara**. O `raise` condicional (linha 19) só existe pra `@webhook_type == :agent_bot_webhook` em 429/500. Resultado: **entrega de webhook de conta é at-most-once, fire-and-forget, 1 tentativa, 5s de timeout, sem dead-letter, sem registro de falha além de um `Rails.logger.warn`**.
- Sem ordering garantido (Sidekiq, fila medium) — o receptor deve usar timestamps do payload, não ordem de chegada.
- `handle_error` (linhas 55-65) só tem efeitos colaterais pra `:agent_bot_webhook` (reabre pending) e `:api_inbox_webhook` (marca mensagem failed) — pra `:account_webhook`, nada.

### 1.5 Veredito: dá pra sincronizar funil→Vista?

**Payload: sim. Garantia: não sozinho.**

- O conteúdo é rico o suficiente: assinando `conversation_created` + `conversation_updated` + `conversation_status_changed` + `message_created` + `contact_created/updated`, o CRM recebe atribuição (corretor), time, labels, custom_attributes, estágio implícito (status), template/campaign de cada HSM e identidade do remetente (humano/IA/contato).
- **Gap 1 — funil/Kanban não emite webhook**: mudanças de `FunnelItem`/estágio (Kanban) não passam por nenhum listener de webhook (não há evento de funil em `ALLOWED_WEBHOOK_EVENTS` nem dispatch em `Kanban::*` services). Workaround natural: espelhar o estágio em `custom_attributes` da conversa (que dispara `conversation_updated`) — o `Spx::Tozi::FunnelPlacementService` poderia fazer isso na transição.
- **Gap 2 — entrega at-most-once**: pra sincronizar com Vista é obrigatório (a) idempotência no receptor (chave: `id` da conversa/mensagem + `event`), e (b) **reconciliação periódica via API REST** (poll) pra reparar perdas, ou consertar o `Trigger` pra re-levantar e deixar o `retry_on attempts: 5` trabalhar (mudança de 1 linha, mas com risco de retry storm — precisaria de idempotência do outro lado de qualquer forma).
- **Gap 3 — operações por script/`update_columns` não emitem nada** (consolidações, reatribuições em massa via console).

---

## 2. Plano AgentBot — `assignee_agent_bot` como "dono bot desta conversa"

### 2.1 Semântica do campo

- Coluna `conversations.assignee_agent_bot_id` (migration `db/migrate/20251022162159_add_assignee_agent_bot_id_to_conversations.rb`; index parcial `idx_conv_assignee_agent_bot_id` em `db/migrate/20260328132433:92-96`, `db/schema.rb:726,736`). Veio do upstream #12836 ("APIs to assign agent_bots as assignee").
- `belongs_to :assignee_agent_bot, class_name: 'AgentBot', optional: true` (conversation.rb:118); lado reverso `has_many :assigned_conversations` (agent_bot.rb:32-35).
- **Exclusão mútua, humano vence**: `before_validation :reset_agent_bot_when_assignee_present` (conversation.rb:71 → 310-314) zera o bot sempre que `assignee_id` está presente. O `Conversations::AssignmentService` zera explicitamente o outro lado em cada atribuição (`app/services/conversations/assignment_service.rb:16-30`).
- `assignee_type` vira `'AgentBot'` (conversation.rb:237-242) e `assigned_entity` retorna o bot (244-246) → o bot aparece como assignee no payload de webhooks/UI (`AgentBot#push_event_data` com `type: 'agent_bot'`, agent_bot.rb:45-52).
- `assignee_last_changed_at` (SLA de resposta) só conta pra humano (`app/models/concerns/assignment_handler.rb:38-42`).
- Mudança de `assignee_agent_bot_id` dispara `conversation_updated` (está em `list_of_keys`, conversation.rb:360) mas **não** dispara `ASSIGNEE_CHANGED` (assignment_handler.rb:55-62 só olha `assignee_id`/`team_id`).
- API: `POST /api/v1/accounts/:id/conversations/:id/assignments` com `assignee_type: 'AgentBot'` + `assignee_id` (`app/controllers/api/v1/accounts/conversations/assignments_controller.rb:4,15-23,42-44`). Bot deve ser `accessible_to` a conta (global `account_id: nil` ou da conta — agent_bot.rb:24-27).

### 2.2 Eventos que o bot-dono recebe (agent_bot_listener.rb:47-53)

```ruby
def agent_bots_for(inbox, conversation = nil)
  bots = []
  bots << conversation.assignee_agent_bot if conversation&.assignee_agent_bot.present?
  inbox_bot = active_inbox_agent_bot(inbox)
  bots << inbox_bot if inbox_bot.present?
  bots.compact.uniq
end
```

- **O bot atribuído à conversa recebe webhooks MESMO sem `AgentBotInbox` na inbox** — é exatamente a semântica de "dono bot desta conversa": dá pra plugar um orquestrador externo conversa-a-conversa, sem assinar a inbox inteira.
- O bot DE INBOX precisa de `AgentBotInbox.active?` (linhas 55-59; modelo em `app/models/agent_bot_inbox.rb`, enum `active/inactive`). Os dois podem coexistir e ambos recebem (uniq evita duplicar se for o mesmo).
- Eventos entregues (handlers do listener): `conversation_resolved` (2-8), `conversation_opened` (10-16), `message_created` (18-25), `message_updated` (27-34), `webwidget_triggered` (36-43). Payload = `conversation.webhook_data`/`message.webhook_data` + `event`. **Não recebe**: `conversation_updated`, typing, mudanças de atribuição.
- Dispatch é **síncrono** no request (`SyncDispatcher`, `app/dispatchers/sync_dispatcher.rb:8`), que enfileira `AgentBots::WebhookJob` (fila `:high`).

### 2.3 Garantia de entrega do canal bot

`app/jobs/agent_bots/webhook_job.rb:1-14`:
- `retry_on RestClient::TooManyRequests, RestClient::InternalServerError, wait: 3.seconds, attempts: 3` com bloco final que chama `Trigger#handle_failure`.
- O `Trigger` re-levanta 429/500 **só** pra `:agent_bot_webhook` (trigger.rb:18-19) → retry funciona pra esses dois códigos. Outros erros (timeout, DNS, 404, 4xx) caem direto no `handle_failure` sem retry.
- **Fallback anti-limbo**: em falha de `message_created/updated`, se a conversa está `pending`, ela é reaberta (`conversation.open!`) com atividade de erro (trigger.rb:67-79) — a menos que `account.keep_pending_on_bot_failure` esteja setado (account.rb:43,98). Esse é o mecanismo nativo que faltou no incidente do limbo (o Captain não usa este caminho).
- **Sem HMAC**: `AgentBots::WebhookJob` não passa `secret` nem `delivery_id` — o endpoint do bot não tem autenticação de origem (era o caso do n8n).

### 2.4 Como o bot atua de volta (API pública)

`app/controllers/concerns/access_token_auth_helper.rb:2-6` — endpoints liberados pro token de AgentBot:

```ruby
BOT_ACCESSIBLE_ENDPOINTS = {
  'api/v1/accounts/conversations' => %w[toggle_status toggle_typing_status toggle_priority create update custom_attributes],
  'api/v1/accounts/conversations/messages' => ['create'],
  'api/v1/accounts/conversations/assignments' => ['create']
}.freeze
```

- AgentBot tem `AccessTokenable` (agent_bot.rb:21) e o token autentica como `Current.user`-like (`authenticate_access_token!`, linhas 13-27).
- **Crucial pra orquestração**: o bot pode **atribuir a conversa a um corretor** (`assignments#create`), **mudar status** (`toggle_status` — tirar de pending/abrir/resolver), **setar custom_attributes** (incluindo o lock `atendimento_humano`) e **mandar mensagem**. É uma superfície suficiente pra uma IA orquestradora externa fazer triagem e atribuição.

### 2.5 Coexistência com Captain / `active_bot?` / pending

- `Inbox#active_bot?` OSS = `agent_bot_inbox&.active? || dialogflow` (`app/models/inbox.rb:172-175`); Enterprise soma o Captain: `super || captain_active?`, com `captain_active? = captain_assistant.present? && more_responses?` (`enterprise/app/models/enterprise/inbox.rb:10-16`).
- **`assignee_agent_bot` (por conversa) NÃO entra em `active_bot?`** e portanto **não** afeta: (a) status inicial pending na criação (`determine_conversation_status`, conversation.rb:332-343 — exige bot de INBOX + `pending_status_enabled?`, flag per-inbox default false, inbox.rb:22); (b) o desvio resolved→pending no reopen (`Message#reopen_resolved_conversation`, `app/models/message.rb:466-476`). Ou seja: **usar bot-dono por conversa não recria o limbo pending** — conversas continuam abrindo como `open` se a inbox não tem bot de inbox. Isso é uma vantagem do plano.
- ⚠️ Gotcha do fork: `reopen_resolved_conversation` chama `conversation.pending!` quando `inbox.active_bot?` (message.rb:468-469), mas a validação `pending_status_allowed_by_inbox` (conversation.rb:324-330) **levanta erro se `pending_status_enabled=false`** — combinação "bot de inbox ativo + pending desabilitado" explode no reopen. Hoje na inbox 91 não há bot de inbox (Clara desconectada), então não fere.
- **Captain e AgentBot são caminhos paralelos que não se enxergam**: AgentBotListener (sync) manda pro `outgoing_url`; o Captain dispara via `Enterprise::MessageTemplates::HookExecutionService#trigger_templates` (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:4-10`) quando `captain_assistant` presente + conversa pending/open + incoming + sem trava humana (`should_process_captain_response?`, linhas 129-140). Se uma inbox tiver os dois, **os dois respondem** (foi o overlap n8n+Clara na inbox 91 até destruírem o `AgentBotInbox`).
- **A arbitragem prevista está quebrada**: o router do Captain tem `skip_agent_bot?` pra se calar quando a conversa tem bot dono, mas chama `@conversation.agent_bot_id` (`enterprise/app/services/captain/behavior/router_service.rb:97-99`) — **atributo que não existe** (a coluna é `assignee_agent_bot_id`). Com `behavior.router.skip_agent_bot: true` (default sugerido no AGENTS.md e no OverviewTab.vue:71), a chamada deve levantar `NoMethodError` por mensagem. Corrigir pra `assignee_agent_bot_id` daria exatamente a semântica de arbitragem "se a conversa tem dono bot externo, Captain cala".
- O fork já usa `assignee_agent_bot_id.blank?` como sinal de "handoff pra humano de verdade" no funil Tozi (`app/listeners/spx/tozi/funnel_automation_listener.rb:42-52`): atribuição a User sem bot → estágio "qualificado" + cancela cadência HSM.

### 2.6 Integridade da API de agent bots no fork

Verificado — superfície completa e alinhada ao upstream:
- Account-level: `app/controllers/api/v1/accounts/agent_bots_controller.rb` (CRUD + avatar + `reset_access_token`); rotas `config/routes.rb:91-94`; views jbuilder completas (`app/views/api/v1/accounts/agent_bots/*`, partials `_agent_bot.json.jbuilder`/`_agent_bot_slim.json.jbuilder`).
- Platform API: `app/controllers/platform/api/v1/agent_bots_controller.rb` (rotas routes.rb:597-599).
- Super admin: rotas routes.rb:732-734.
- Vincular à inbox: `inboxes#agent_bot`/`set_agent_bot` (`app/controllers/api/v1/accounts/inboxes_controller.rb:57-70`; rotas 295-296).
- Git log dos arquivos mostra só evolução upstream (#11276 remove CSML, #11447 custom attrs, #12836 assignee bot, #13705 typing) + upgrade v4.12.1 + auditoria de fixes do fork — **nada foi removido ou desviado**. `bot_type` só tem `webhook` (agent_bot.rb:37).

---

## 3. Bônus — Audit log Enterprise (trilha de operação)

- `Enterprise::AuditLog < Audited::Audit` (`enterprise/app/models/enterprise/audit_log.rb:29-43`), tabela `audits` com `action`, `audited_changes` (jsonb), `user_id`, `username` (email), `remote_address`, `request_uuid`; associa tudo à Account pra consulta via `associated_audits`.
- Endpoint: `GET /api/v1/accounts/:id/audit_logs` (routes.rb:101 → `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb`), admin-only, paginado 15, **gateado pela feature `audit_logs`** — que é `premium: true` e `enabled: false` por default (`config/features.yml:103-106`, `enterprise/config/premium_features.yml:3`). Precisa habilitar na Account 6 pra usar.
- Cobertura (via `Model.include_mod_with('Audit::...')`): Account (update, audit/account.rb:5), AccountUser, AutomationRule, Inbox (create/update), InboxMember (create/destroy, log manual — audit/inbox_member.rb:11-30), Macro, Team, TeamMember, User (campos restritos), Webhook (exceto secret).
- **Conversation é auditada SÓ no destroy e com `only: []`** (`enterprise/app/models/enterprise/audit/conversation.rb:4-6`; include em conversation.rb:463). **Atribuições, mudanças de status, labels — nada disso entra no audit log.**
- Veredito: responde à dor "operação sem trilha" **só pra mudanças de configuração** (quem mexeu em inbox/automação/time/webhook/role). A trilha de OPERAÇÃO de conversa vive em: activity messages (`Conversations::ActivityMessageJob`, conversation.rb:404-412 + assignment_handler.rb:74-81), `ReportingEvent`, e — pro Captain — `Captain::AssistantLog` (router skips/copilot, hook_execution_service.rb:95-98). Pra uma IA orquestradora auditável, o caminho barato é padronizar activity messages + logs próprios estilo `Captain::AssistantLog`, não o `audits`.

---

## 4. Ganchos concretos pra IA orquestradora

1. **Webhook de conta assinado (HMAC)** → CRM/Vista ou serviço orquestrador: criar `Webhook` com `subscriptions: [conversation_created, conversation_updated, conversation_status_changed, message_created, contact_created, contact_updated]`. Recebe atribuição/time/labels/custom_attributes/template_params. Exige idempotência + reconciliação por poll (entrega at-most-once).
2. **Espelhar estágio do funil em `custom_attributes`** na transição do `FunnelPlacementService` → faz o Kanban "vazar" pro mundo externo via `conversation_updated` sem novo evento.
3. **AgentBot como identidade da orquestradora**: criar AgentBot (API account-level), atribuir por conversa via `POST /assignments {assignee_type: 'AgentBot'}` → recebe `message_created`/`conversation_opened`/`conversation_resolved` no `outgoing_url` mesmo sem bot de inbox; responde/atribui/trava via access_token (`BOT_ACCESSIBLE_ENDPOINTS`).
4. **`POST /assignments` com `assignee_id` (User) ou `team_id`** é o ato de triagem/atribuição que a IA executa — e o `FunnelAutomationListener.assignee_changed` (funnel_automation_listener.rb:42-52) já reage promovendo pra "qualificado".
5. **`custom_attributes.atendimento_humano`** (hook_execution_service.rb:138-140) é o kill-switch por conversa do Captain — settável pelo bot externo (`conversations#custom_attributes`).
6. **`account.keep_pending_on_bot_failure`** (account.rb:98) + fallback pending→open do Trigger (trigger.rb:67-74) é a rede anti-limbo nativa do canal AgentBot.
7. **Consertar `skip_agent_bot?`** (router_service.rb:98 → `assignee_agent_bot_id`) habilita a arbitragem Captain-cala-quando-conversa-tem-dono-bot.

## 5. Gaps e riscos

- 🔴 Account webhooks sem retry real (Trigger engole StandardError; `retry_on` do WebhookJob nunca dispara) — perda silenciosa, 1 tentativa, 5s timeout (trigger.rb:16-29, 108-113).
- 🔴 `delivery_id` não persistido: zero observabilidade/replay de entregas (sem tabela de deliveries).
- 🔴 Bug `skip_agent_bot?` → `@conversation.agent_bot_id` inexistente (router_service.rb:98) — NoMethodError com a flag ligada; arbitragem Captain×AgentBot inoperante.
- 🟡 Funil/Kanban não emite webhooks (nenhum evento de FunnelItem em ALLOWED_WEBHOOK_EVENTS).
- 🟡 Mutações via `update_columns`/console (consolidação, reatribuição em massa) não emitem eventos → CRM espelhado dessincroniza.
- 🟡 `reopen_resolved_conversation` chama `pending!` que levanta RecordInvalid se `pending_status_enabled=false` na inbox com bot ativo (message.rb:466-476 × conversation.rb:324-330).
- 🟡 Webhook do AgentBot sem HMAC/autenticação de origem (AgentBots::WebhookJob não passa secret).
- 🟡 Dois bots (AgentBot de inbox + Captain) na mesma inbox respondem em paralelo — sem arbitragem nativa funcional.
- 🟡 Audit log Enterprise não cobre operação de conversa (Conversation: `only: [], on: [:destroy]`) e a feature é premium default-off.
- ⚪ `conversation_updated` não inclui mudanças de funil nem de participantes; bot-dono não recebe `conversation_updated`.

## 6. Questões em aberto

- Habilitar a feature `audit_logs` na Account 6 vale o custo (volume de writes na tabela `audits`)?
- Pra Vista: consertar o retry do Trigger (re-raise pra account_webhook) ou aceitar at-most-once + reconciliação por poll? (Recomendação: poll de reconciliação de qualquer forma; retry é melhoria incremental.)
- A orquestradora deve ser um AgentBot (webhook externo, push) ou viver dentro do Captain v2 (tools nativas)? O campo `assignee_agent_bot` suporta o primeiro; o fork já investiu pesado no segundo.
- Persistir entregas de webhook (tabela `webhook_deliveries` com delivery_id/status/response_code) pra dar trilha e replay?
