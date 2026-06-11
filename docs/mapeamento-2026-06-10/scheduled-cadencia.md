# Mapeamento — Mensagens Agendadas e Cadência de Follow-up (scheduled-cadencia)

> Gerado em 2026-06-10, branch `paulao`, leitura 100% do código local (app/ + enterprise/).
> Escopo: ScheduledMessage (model/serviços/jobs/API), ponte HSM via MessageBuilder → SendOnWhatsappService,
> cadência Tozi (ReactivationCadenceService + FunnelAutomationListener + FunnelPlacementService),
> follow-up do agente IA (ProgramarFollowupTool + Captain FollowupJob), e o que falta para multi-cliente.

---

## 1. ScheduledMessage — a infraestrutura genérica de envio agendado

### 1.1 Model — `app/models/scheduled_message.rb`

- Statuses (linha 22): `pending: 0, sent: 1, failed: 2, cancelled: 3`. O mapeamento do enum é resolvido dinamicamente conforme o tipo da coluna (`status_mapping_for_column`, linhas 25-31) — defesa contra ambientes onde a coluna virou string (migration de normalização `20260217173000_normalize_scheduled_messages_status_column.rb`).
- Associações (linhas 33-42): `belongs_to :account (optional)`, `:conversation`, `:inbox`, `:scheduled_by (User, optional)`, `:sent_message (Message via message_id, optional)` e `has_many_attached :attachments`.
- Validações (linhas 44-48): conversa/inbox obrigatórias, `message_or_attachments_present` (linhas 62-66), `scheduled_at` no futuro com tolerância de 2 min (linhas 55-60), só validado em pending novo ou quando `scheduled_at` muda (linhas 68-70).
- Scopes (linhas 52-53): `pending` e `upcoming` (`scheduled_at > now`, ordenado).
- **Coluna `template_params` (jsonb)**: adicionada pela migration `db/migrate/20260529120000_add_template_params_to_scheduled_messages.rb:5-8`. ATENÇÃO: o `db/schema.rb` local está na versão `2026_05_19_210000` (schema.rb:13) e a tabela `scheduled_messages` no schema (linhas 1310-1330) **não tem** `template_params` nem `account_id` — por isso todo o código que toca a coluna é defensivo (`ScheduledMessage.column_names.include?('template_params')`). Sem a migration aplicada, a cadência HSM vira no-op limpo (comentário explícito em `reactivation_cadence_service.rb:49-51`).
- Sem overlay Enterprise: `rg ScheduledMessage enterprise/` não retorna model/controller/service — só os usos nas tools/job do Captain (ver §3).

### 1.2 CreateService — `app/services/scheduled_messages/create_service.rb`

- Assinatura (linha 6): `initialize(conversation:, inbox:, message:, scheduled_at:, user: nil, attachments: [], template_params: nil)`.
- `template_params` só é persistido se a coluna existir (linhas 33-35).
- Anexos normalizados para signed_id String ou UploadedFile (linhas 99-105).
- Após `save!`, enfileira **um único job pontual**: `ScheduledMessages::SendJob.set(wait_until: scheduled_at_time).perform_later(scheduled_message.id)` (linha 53). **O enqueue é rescue-ado e apenas logado (linhas 52-57)** — se falhar, o registro fica `pending` para sempre, pois **não existe sweeper/cron de recuperação** (conferido em `config/schedule.yml` e `app/jobs/trigger_scheduled_items_job.rb:4-22`: o `TriggerScheduledItemsJob` cuida de campanhas/snooze/auto-resolve/sync de templates, nada de scheduled_messages).

### 1.3 SendJob — `app/jobs/scheduled_messages/send_job.rb`

- `retry_on StandardError, attempts: 3` (linha 6).
- Guards (linhas 11-12): pula se `sent?`/`cancelled?` e se `scheduled_at > Time.current` (job adiantado não dispara antes da hora).
- Delega tudo ao `ScheduledMessages::SendService` (linha 14).

### 1.4 SendService — `app/services/scheduled_messages/send_service.rb`

Dois caminhos:

1. **Mensagem pré-criada** (`message_id` presente, linhas 15-24): reaproveita o `sent_message`, limpa `scheduled_message_id` dos content_attributes, marca `skip_signature`, injeta metadados (`scheduled_at`, `scheduled_by`) e sanitiza assinatura.
2. **Criação na hora** (linhas 26-51): monta `message_params` com `content` sanitizado, `message_type: 'outgoing'` e, **se `scheduled_message.template_params` presente, repassa `message_params[:template_params]`** (linha 43 — comentário nas linhas 40-42 documenta a ponte: "o MessageBuilder os repassa pra message.additional_attributes['template_params'] e o SendOnWhatsappService envia como template (obrigatório fora da janela de 24h). WAHA ignora"). O sender é `scheduled_by || conversation.assignee || Current.user` (linha 27). Cria a Message via `Messages::MessageBuilder` (linhas 46-47).

- Depois: copia anexos para a Message (linhas 101-114, com dedup por blob), **enfileira `::SendReplyJob.perform_later(message.id)` (linha 55)** e marca `status: :sent` + `sent_at` (linhas 56-58). Falhas viram `status: :failed` + `error_message` (linhas 68-73) e re-raise (o SendJob então re-tenta até 3×).
- ⚠️ **Duplo enqueue de SendReplyJob**: a Message criada pelo MessageBuilder já dispara `send_reply` no `after_create_commit` (`app/models/message.rb:145` → `execute_after_create_commit_callbacks` linhas 341-350 → `send_reply` linhas 437-441). O SendService enfileira um segundo SendReplyJob (linha 55). O guard que evita reenvio é `Base::SendOnChannelService#invalid_message?` → `outgoing_message_originated_from_channel?` = `message.source_id.present?` (`app/services/base/send_on_channel_service.rb:35-50`): o segundo job vira no-op **se** o primeiro já gravou o `source_id`. Há janela de corrida (dois workers concorrentes) com risco baixo, porém real, de HSM duplicado.

### 1.5 Ponte MessageBuilder → SendOnWhatsappService (o "como o HSM viaja")

Cadeia completa:

1. `Messages::MessageBuilder#template_params` (`app/builders/messages/message_builder.rb:124-126`): `@params[:template_params]` → `{ additional_attributes: { template_params: ... } }`, mergeado em `message_params` (linha 148).
2. `Message` criada → `after_create_commit` → `send_reply` → `SendReplyJob` (`app/models/message.rb:341-350, 437-441`).
3. `SendReplyJob` roteia `Channel::Whatsapp` → `Whatsapp::SendOnWhatsappService` (`app/jobs/send_reply_job.rb:11`).
4. `Whatsapp::SendOnWhatsappService#perform_reply` (`app/services/whatsapp/send_on_whatsapp_service.rb:8-15`): **manda como template se `template_params` presente OU se `!conversation.can_reply?`** (fora da janela 24h). `template_params` é lido de `message.additional_attributes['template_params']` (linhas 45-47).
5. `Whatsapp::TemplateProcessorService` (`app/services/whatsapp/template_processor_service.rb`): resolve `name/namespace/language` + `processed_params`. **`find_template` (linhas 21-27) exige o template APPROVED dentro de `channel.message_templates`** (os templates SINCRONIZADOS — gotcha real de produção: sem `sync_templates` o processed retorna nil e a Meta devolve `#132000 number of parameters`). Suporta `header` com mídia (`media_url`+`media_type`, linhas 59-77 — formato usado pelo DisparoLeadJob para os templates de inquilinos com imagem), `body` (posicional ou NAMED, linhas 79-94), `footer` e `buttons`.
6. `channel.send_template(source_id, {name, namespace, lang_code, parameters}, message)` (send_on_whatsapp_service.rb:31-36); se o nome do template estiver em branco a mensagem é marcada `failed` com `external_error` (linhas 26-29).

### 1.6 API REST e policy

- Rotas: `resources :scheduled_messages, only: [:index, :show, :create, :update, :destroy]` + `GET collection :inboxes` (`config/routes.rb:141-144`).
- Controller `app/controllers/api/v1/accounts/scheduled_messages_controller.rb`:
  - `index` com filtro de status (`pending/sent/failed/cancelled/all`, linhas 8, 166-175), filtro de datas (linhas 177-184), filtro `upcoming` default para pending (linhas 194-198) e **modo cursor (timeline)** gateado pela feature `kanban_ux_v2` (linhas 200-202) via `ScheduledMessages::TimelineQueryService` (paginação keyset DESC por `scheduled_at,id`, `app/services/scheduled_messages/timeline_query_service.rb:14-58`).
  - `create` resolve a conversa por `conversation_id` OU `contact_id+inbox_id` via `ScheduledMessages::ResolveConversationService` (linhas 56-61) — este service reusa a conversa não-resolvida mais recente do contato na inbox ou cria uma nova (`app/services/scheduled_messages/resolve_conversation_service.rb:29-53`).
  - **⚠️ `template_params` NÃO é permitido pela API**: `scheduled_message_params` permite só `message, scheduled_at, inbox_id, conversation_id, contact_id, attachments` (linhas 145-160) e o `create` não repassa `template_params` ao CreateService (linhas 84-91). Ou seja: **agendar HSM hoje é exclusivamente código Ruby server-side** (a cadência Tozi).
  - `update`/`destroy` só em pending (`ensure_pending_message!`, linhas 204-208); `destroy` na verdade **cancela** (`status: :cancelled`, linhas 126-131) — não apaga.
- Policy (`app/policies/scheduled_message_policy.rb`): qualquer `agent` ou `administrator` da conta; scope por conta via join na conversation (linhas 28-32). **Não há recorte por corretor/custom role** — um corretor com role restritiva enxerga (via API) scheduled messages de conversas que ele não vê na inbox.

---

## 2. Cadência Tozi — HSM fora da janela de 24h

### 2.1 `Spx::Tozi::ReactivationCadenceService` — `app/services/spx/tozi/reactivation_cadence_service.rb`

Comentário de cabeçalho (linhas 1-11) define o contrato: *"dentro de 24h → agente decide e compõe a cutucada (texto livre); fora de 24h → só HSM aprovado reabre a conversa (esta cadência)"*. Disparada quando o lead esfria; cancelada quando responde.

- **CADENCE (linhas 20-27)** — 3 passos hardcoded:
  | offset | template HSM | preview (transcrição) |
  |---|---|---|
  | 1 dia | `tozi_lead_followup` | "Oi {nome}, ainda procurando imóvel?..." |
  | 3 dias | `tozi_lead_reativacao` | "Oi {nome}! Apareceram novos imóveis em {ref}..." |
  | 7 dias | `tozi_lead_reativacao` | "Oi {nome}! Ainda dá tempo de achar o imóvel certo..." |
- `perform` (linhas 48-62), guards em ordem:
  1. coluna `template_params` existe (linha 51 — feature inerte sem a migration);
  2. `cloud_api_inbox?` (linhas 67-70): `channel_type == 'Channel::Whatsapp'` E `provider_config['business_account_id']` presente — **em WAHA é no-op** (sem HSM);
  3. **idempotência** `cadence_already_scheduled?` (linhas 72-79): existe `ScheduledMessage.pending` da conversa com `template_params != nil` → não reagenda;
  4. `system_user` = `account.administrators.first` (linhas 108-110) — **o sender da cadência é o primeiro admin da conta, não o corretor atribuído**.
  Erros são engolidos com log (linhas 59-62).
- `schedule_step` (linhas 81-90): um `ScheduledMessages::CreateService` por passo com `scheduled_at: offset.from_now` — **os 3 passos são agendados de uma vez** no momento do esfriamento (não encadeados). Não há respeito a quiet hours/horário comercial: se o esfriamento ocorrer 22h, o passo de 1d dispara 22h.
- `template_params` (linhas 94-98): shape `{'name', 'language' ('pt_BR'), 'processed_params' => {'body' => {'1' => primeiro_nome, '2' => referência (só no reativacao)}}}` — exatamente o que o `Whatsapp::TemplateProcessorService` lê.
- Personalização: `first_name` = primeiro token do nome do contato ou "tudo bem" (linhas 100-102); `product_reference` = `contact.additional_attributes['city']` ou `'Sinop'` (linhas 104-106 — o city vem do Meta Lead Ads, ver `create_conversation_service.rb:83`).
- **`cancel_pending` (linhas 32-41)**: `update_all(status: cancelled)` em **todo** `ScheduledMessage.pending` da conversa com `template_params != nil`. Não há marcador de origem ("isto é cadência") — se um dia a API permitir agendar HSM manual, o cancel-on-reply mataria esses também.

Os nomes dos templates casam com a fonte reproduzível do rake (`lib/tasks/spx_tozi.rake:64-97`, `CADENCE_TEMPLATES`): `tozi_lead_abertura`, `tozi_lead_followup`, `tozi_lead_reativacao` (MARKETING) e `tozi_followup_horario_combinado` (UTILITY), com `{{1}}`=nome, `{{2}}`=referência. O comentário do service (linhas 18-19) manda reconciliar com o WABA antes de habilitar em prod. `rake spx:tozi:create_templates` é idempotente (list-then-skip, rake linhas 100-125).

### 2.2 `Spx::Tozi::FunnelAutomationListener` — `app/listeners/spx/tozi/funnel_automation_listener.rb`

Listener Wisper registrado **globalmente** no `AsyncDispatcher#listeners` (`app/dispatchers/async_dispatcher.rb:14`, segundo da lista, logo após o AutomationRuleListener) — roda para TODA conta da instância via `EventDispatcherJob` (fila :critical). Cada handler é rescue-wrapped justamente para não derrubar a cadeia de eventos global (comentário linhas 5-7).

Escuta **2 eventos**:

1. **`message_created`** (linhas 24-37): só `incoming` não-activity. Gate: `FunnelPlacementService.current_type(conversation)` ∈ `WAITING_STAGES = %w[novo_lead aguardando_1a em_silencio frio]` (linha 18). Ação: `ReactivationCadenceService.cancel_pending` + `FunnelPlacementService.move(to: 'em_conversa')`. **Este é O cancel-on-reply da cadência HSM** — e ele é condicionado ao card estar num estágio de espera do funil Tozi. Conversa sem FunnelItem (ex.: leads de disparo em massa, que nunca são colocados no funil) → `current_type` nil → **a cadência NÃO é cancelada quando o lead responde**.
2. **`assignee_changed`** (linhas 44-52): handoff para humano = `assignee_id` presente E `assignee_agent_bot_id` em branco (coluna real em conversations, `db/schema.rb:726`). Gate: estágio atual ∈ `PRE_QUALIFIED_STAGES = %w[novo_lead aguardando_1a em_conversa em_silencio agendado frio]` (linha 20 — não sobrescreve card movido à mão para fora da pré-venda). Ação: cancela cadência + move para `'qualificado'`.

### 2.3 `Spx::Tozi::FunnelPlacementService` — `app/services/spx/tozi/funnel_placement_service.rb`

- `PREVENDA_AUTOMATION_TYPES` (linha 16): `novo_lead, aguardando_1a, em_conversa, em_silencio, agendado, qualificado, frio` — os 7 estágios criados pelo `rake spx:tozi:setup_funnel` (`lib/tasks/spx_tozi.rake:16-26`; em prod = funil "Pré-Venda Tozi" id=41, inbox 91).
- `move(conversation:, to:)` (linhas 22-24) → `perform` (linhas 48-64): acha o funil da conta que cobre a inbox E tem stage com o `automation_type` pedido (`find_funnel`, linhas 71-77 — o filtro por automation_type evita capturar funis genéricos open/resolved), faz `FunnelItem.find_or_initialize_by(conversation_id, funnel_id)` e seta o stage. Idempotente; rescue+log (linhas 61-64). **No-op para qualquer conta/inbox sem o funil de pré-venda** — é assim que o código "multi-tenant-safe" hoje.
- `current_type(conversation)` (linhas 27-32): automation_type do card atual ou nil. É **o árbitro de estado** consultado pelo listener.
- Entrada no funil: hoje só o Meta Lead Ads coloca lead em `novo_lead` (`app/services/meta/lead_ads/create_conversation_service.rb:50-54`). O `DisparoLeadJob` e o `FollowupHsmJob` **não** posicionam no funil.

---

## 3. Follow-up do agente IA (dentro da janela 24h)

### 3.1 `Captain::Tools::ProgramarFollowupTool` — `enterprise/lib/captain/tools/programar_followup_tool.rb`

Tool registrada em `config/agents/tools.yml:63-66` (id `programar_followup` → classe resolvida por convenção `Captain::Tools::ProgramarFollowupTool`). Herda `Captain::Tools::BasePublicTool` (`enterprise/lib/captain/tools/base_public_tool.rb` — `find_conversation` lê `state[:conversation][:id]` escopado por conta, linhas 26-31).

- O **agente decide** quando e quanto esperar: params `minutos` (clamp 2..2880, linha 17) e `motivo` (texto livre do ponto onde a conversa parou).
- Grava na conversa (linhas 19-23): `custom_attributes['followup_token']` (token random — substitui follow-up anterior), `followup_motivo`, `followup_status`.
- **Hook do funil (linha 25)**: `FunnelPlacementService.move(to: 'em_silencio')`.
- Agenda `Captain::Conversation::FollowupJob.set(wait: minutes.minutes).perform_later(conversation, token)` (linha 26).
- Programar de novo substitui o anterior: o token muda e o job antigo, ao acordar, vê token diferente e desiste.

### 3.2 `Captain::Conversation::FollowupJob` — `enterprise/app/jobs/captain/conversation/followup_job.rb`

Constantes (linhas 4-6): `MAX_FOLLOWUPS = 4`, quiet hours `21h → 8h`.

Guards no `perform` (linhas 11-21), em ordem:
1. `followup_token` ≠ token do job → substituído, sai (linha 16);
2. `custom_attributes['atendimento_humano']` truthy → humano travou o bot, sai (linha 17);
3. conversa `resolved?` → sai (linha 18);
4. `lead_replied?` (linhas 53-56: última mensagem pública incoming/outgoing é `incoming`) → cliente respondeu, não cutuca;
5. `reschedule_if_quiet_hours` (linhas 58-66): fora de 8h-21h **America/Cuiaba hardcoded** → remarca para as 8h (mesmo dia ou amanhã) e sai.

Fluxo (linhas 23-41):
- **`followup_count >= 4` → esfriou**: seta `tozi_status_lead='esfriado'`, `followup_status`, zera token (linhas 25-29) e dispara a dupla Bloco 3+4: `FunnelPlacementService.move(to: 'frio')` + **`ReactivationCadenceService.new(conversation:).perform`** (linhas 32-33). **É AQUI que a via in-window entrega o bastão pra via HSM.**
- Senão: incrementa `followup_count`, zera o token (linha 37) e roda `Captain::Conversation::ResponseBuilderJob.perform_now(conversation, assistant, directive: ...)` (linha 41). A `directive` (linhas 46-51) é uma "[NOTA INTERNA — não é mensagem do cliente]" pedindo cutucada curta retomando o `motivo`, com saída de escape: *"Se já não fizer sentido insistir, responda apenas [IGNORAR]"*.

### 3.3 Como a directive vira mensagem — `enterprise/app/jobs/captain/conversation/response_builder_job.rb`

- `perform(conversation, assistant, directive: nil)` (linha 6). A directive entra como **último turno role 'user'** no histórico (linhas 79-83) — o agente compõe a cutucada com o contexto inteiro da conversa.
- **Reset-on-reply da via in-window** (linhas 14, 87-94): quando o cliente responde de verdade (`directive.nil?`), `reset_followup_state` zera `followup_token`, `followup_count` e `followup_status` — lead reengajado recomeça a contagem do zero. (O cancelamento da via in-window é, na prática, este reset + o guard `lead_replied?` do job; nenhum job Sidekiq é deletado, ele acorda e desiste.)
- `[IGNORAR]`/vazio → não envia nada (`no_reply?`, linhas 163-167).
- Demais comportamentos (dedup, humanizer com typing proporcional, sanitize WhatsApp) nas linhas 169-241.
- O agente responde em `pending` E `open` (linhas 297-302); a cutucada sai como Message outgoing com `sender: @assistant` (linhas 247-259) → mesma cadeia SendReplyJob → SendOnWhatsappService → **mensagem de sessão** (`send_session_message`), válida só dentro da janela de 24h. Se a janela já fechou quando a cutucada sai, `can_reply?` é false e o SendOnWhatsappService tentaria template **sem template_params** → falha (borda não tratada: o FollowupJob não checa a janela).

### 3.4 `Captain::Tools::SalvarInfoLeadTool` — segundo gatilho da cadência

`enterprise/lib/captain/tools/salvar_info_lead_tool.rb:34-43` (`move_funnel_by_status`):
- status `qualificado`/`convertido` → `cancel_pending` + move `'qualificado'`;
- status `esfriado`/`perdido` → move `'frio'` + **`ReactivationCadenceService.perform`** (o agente pode esfriar o lead explicitamente, sem esperar as 4 cutucadas).
Também grava `tozi_status_lead`/`sobre_cliente` em custom_attributes e label `followup-ativo` (linhas 45-49).

---

## 4. Como as duas vias se complementam (e quem arbitra)

```
                    lead ativo (janela 24h aberta)
                              │
            agente conversa; cliente silencia
                              │
              ProgramarFollowupTool (agente decide minutos+motivo)
                  └─ move card → EM SILÊNCIO
                              │ wait N min
              Captain::Conversation::FollowupJob
                  ├─ cliente respondeu? → desiste (ResponseBuilderJob já zerou contagem)
                  ├─ quiet hours? → remarca p/ 8h
                  ├─ count < 4 → ResponseBuilderJob(directive) → cutucada TEXTO LIVRE do agente
                  │      (o agente pode programar a próxima → loop)
                  └─ count ≥ 4 → tozi_status_lead=esfriado
                         ├─ move card → FRIO
                         └─ ReactivationCadenceService.perform   ←── também chamável por salvar_info_lead(esfriado/perdido)
                                │  (só Cloud API; idempotente)
                                ├─ ScheduledMessage +1d  HSM tozi_lead_followup
                                ├─ ScheduledMessage +3d  HSM tozi_lead_reativacao
                                └─ ScheduledMessage +7d  HSM tozi_lead_reativacao
                                       │ SendJob(wait_until) → SendService → MessageBuilder(template_params)
                                       │ → Message.additional_attributes['template_params']
                                       │ → SendReplyJob → SendOnWhatsappService → send_template (HSM)
                              │
            lead responde (a qualquer momento)
                              │
        FunnelAutomationListener#message_created (incoming, card em novo_lead/aguardando_1a/em_silencio/frio)
                  ├─ ReactivationCadenceService.cancel_pending  (mata os HSM 1d/3d/7d pendentes)
                  └─ move card → EM CONVERSA
                              │
        handoff p/ humano (assignee User, sem agent_bot)
                  └─ FunnelAutomationListener#assignee_changed → cancel_pending + card → QUALIFICADO
```

- **Dentro da janela** = cutucada de **texto livre composta pelo agente** (contextual, com motivo), limitada a 4 tentativas, em horário civilizado.
- **Fora da janela** = **HSM determinístico** (3 passos fixos, templates aprovados), porque a Meta só aceita template aprovado fora de 24h.
- **Quem arbitra é o estágio do funil**: as transições escrevem o estágio (`em_silencio`/`frio`/`qualificado`/`em_conversa`) e o listener **lê** o estágio para decidir se cancela/reativa. `FunnelPlacementService.current_type` é o ponto único de leitura (funnel = state store da orquestração).
- **Cancelamento quando o lead responde**, por via:
  - HSM (fora da janela): `FunnelAutomationListener#message_created` → `cancel_pending` (update_all → cancelled). Gateado pelo estágio do funil.
  - In-window: `ResponseBuilderJob#reset_followup_state` zera token/count (resposta normal) + `FollowupJob#lead_replied?` como cinto de segurança quando o job acorda.
  - Handoff humano: `assignee_changed` cancela HSM e qualifica.
  - `salvar_info_lead(qualificado/convertido)`: cancela HSM.

---

## 5. Vias paralelas operacionais (contexto)

- **`Spx::Tozi::DisparoLeadJob`** (`app/jobs/spx/tozi/disparo_lead_job.rb`): motor de disparo em massa. `INBOX_ID = 91` hardcoded (linha 12), `PREVIEWS` com 17 templates (linhas 17-54), suporte a header de imagem (`NO_BODY_VAR`/`INQ_IMAGE_URL`, linhas 56-62, 166-175). Pós-fix de duplicatas: `resolved_source_id` usa `Whatsapp::PhoneNumberNormalizationService` para reconciliar variantes do 9º dígito (linhas 112-116) e `find_or_create_conversation` honra o lock_to_single da inbox 91 (linhas 121-143). Envia HSM pelo mesmo trilho `MessageBuilder(template_params)` (linhas 149-164). **Não coloca o lead no funil nem agenda cadência.**
- **`Spx::Tozi::FollowupHsmJob`** (`app/jobs/spx/tozi/followup_hsm_job.rb`): re-engajamento de não-respondentes de campanha — HSM `tozi_followup_lanc` ({{1}}=nome) **na conversa existente** (linhas 16-34), `INBOX_ID = 91` e template hardcoded (linhas 9-11), reabre conversa resolvida (`conversation.open!`, linha 21), mantém assignee. Disparado por scripts (`scripts/spx/tozi/followup_schedule.rb` etc.), não por evento. Também não toca funil/cadência.
- **Rake `spx:tozi:disparo`** (`lib/tasks/spx_tozi.rake:142-212`): enfileira DisparoLeadJob espalhado; broker IDs hardcoded (linha 131).

Essas vias usam a mesma ponte HSM, mas **vivem fora da state machine** — um lead de disparo só entra no funil se uma tool do Captain mover (e a Clara está desconectada da inbox 91 hoje).

---

## 6. O que falta para virar cadência multi-cliente configurável

Hoje é **hardcoded Tozi em camadas**:

1. **Namespace e acoplamento direto**: `Spx::Tozi::*` chamado por código genérico — `FunnelAutomationListener` registrado global (`async_dispatcher.rb:14`), `Meta::LeadAds::CreateConversationService:50-54`, e pior: as tools genéricas do Captain (`programar_followup_tool.rb:25`, `salvar_info_lead_tool.rb:37-41`) e o `FollowupJob` enterprise (linhas 32-33) invocam `Spx::Tozi::` diretamente — qualquer tenant que use essas tools passa pela lógica Tozi (mitigado só pelo no-op do funil).
2. **Constantes de produto no código**: passos da cadência (offsets/templates/previews — `reactivation_cadence_service.rb:20-27`), `LANGUAGE='pt_BR'`, `DEFAULT_REFERENCE='Sinop'`, `MAX_FOLLOWUPS=4`, quiet hours 21-8 e TZ `America/Cuiaba` (`followup_job.rb:4-6, 59`), `INBOX_ID=91` (disparo/followup HSM), broker IDs (rake), nomes de custom_attributes (`tozi_status_lead`).
3. **Config natural já existe e não é usada**: o `Captain::Assistant#behavior` (JSONB livre, já com `debounce/router/humanizer/...`) seria o lugar óbvio para `cadence: {steps: [{offset, template, params_map}], quiet_hours, max_followups, timezone, reference_attr}` por assistant/inbox.
4. **API não expõe `template_params`**: o controller não permite o campo (`scheduled_messages_controller.rb:145-160`), então nenhum orquestrador externo (nem a UI) consegue agendar HSM — só código.
5. **Cancel-on-reply acoplado ao funil Tozi**: conversa fora do funil não cancela cadência ao responder (listener gateia por `current_type`). Generalizar = cancelar por marcador na própria ScheduledMessage (ex.: `source: 'cadence'`) em qualquer incoming.
6. **Sem marcador de origem na ScheduledMessage**: `cancel_pending` mata qualquer pending com `template_params` — precisa de coluna/atributo `origin`/`cadence_id` para coexistir com HSM agendado manualmente.
7. **Sem sweeper**: entrega depende 100% do Sidekiq scheduled set; job perdido = pending eterno (CreateService até rescua falha de enqueue e segue, linhas 52-57).
8. **Migration `template_params` não consolidada**: schema.rb em 2026_05_19; STATE.md relata prod com deploys que dropam código off-git — risco da coluna existir e o código não (ou vice-versa). Os guards `column_names.include?` mantêm o sistema de pé, mas em silêncio (cadência simplesmente não roda).
9. **Quiet hours só na via in-window**: a cadência HSM dispara no horário em que o lead esfriou ± offsets exatos — sem business hours.
10. **Sender da cadência** = primeiro admin da conta (`system_user`), não o corretor dono do lead — inconsistente com o modelo de atribuição por corretor.
11. **Janela 24h não checada na cutucada in-window**: se a cutucada de 2880 min (2 dias) acordar com janela fechada, sai como mensagem de sessão e falha na Meta.

---

## 7. Ganchos para a IA orquestradora

1. **Eventos Wisper/AsyncDispatcher** (`app/dispatchers/async_dispatcher.rb:11-25`): padrão já provado pelo `FunnelAutomationListener` — um `Spx::OrchestratorListener` pode escutar `message_created`, `assignee_changed`, `conversation_created/resolved/opened` e decidir triagem/atribuição/cadência. (Recomendação da auditoria: gatear por conta/feature-flag antes de tocar o banco.)
2. **`ScheduledMessages::CreateService` com `template_params`** (`create_service.rb:6`): primitivo pronto para a IA agendar HSM determinístico em qualquer conversa Cloud API. Expor na API = permitir o campo no controller (1 linha de permit) + validação de shape.
3. **API REST de scheduled_messages** (`config/routes.rb:141-144`): criar (texto/anexo), listar com cursor, cancelar (`DELETE` → cancelled) — superfície de controle externa já existente.
4. **Registry de tools do Captain** (`config/agents/tools.yml` + `Captain::Tools::*Tool` em `enterprise/lib/captain/tools/`): adicionar tools de orquestração (atribuir corretor, mover estágio, agendar/cancelar cadência) é plug-and-play — `programar_followup`/`salvar_info_lead` são o template.
5. **`ResponseBuilderJob(directive:)`** (`response_builder_job.rb:6, 79-83`): mecanismo genérico de "injetar nota interna e deixar o agente agir" — hoje usado pela cutucada; serve para qualquer ação proativa da IA (ex.: "secretária pediu para retomar", "lead voltou de campanha X").
6. **`FunnelPlacementService.move/current_type`** (`funnel_placement_service.rb:22-32`): API interna do Kanban como máquina de estados da orquestração — a IA lê o estágio para decidir e escreve o estágio como efeito.
7. **`ReactivationCadenceService.cancel_pending`** (`reactivation_cadence_service.rb:32-41`): primitivo de cancelamento de cadência.
8. **`custom_attributes` da Conversation** (`followup_token/count/status`, `tozi_status_lead`, `atendimento_humano`, `sobre_cliente`): canal de estado compartilhado IA ↔ humanos ↔ jobs (a trava `atendimento_humano` já é respeitada pelo FollowupJob:17).
9. **`Whatsapp::TemplateManagementService` + `sync_templates`**: gestão programática do ciclo de vida de HSM (criar/listar/status) — pré-requisito de qualquer cadência HSM multi-cliente.
10. **`ScheduledMessages::ResolveConversationService`** (`resolve_conversation_service.rb:29-53`): resolve contato→conversa única (reusa não-resolvida mais recente) — útil para a IA agendar follow-up "por contato" sem duplicar conversa (alinhado ao lock_to_single).

---

## 8. Questões em aberto

1. A migration `20260529120000` (template_params) está de fato aplicada em prod AWS? O `migrate:status` de 08/06 dizia 0 down, mas o schema.rb local parou em 2026_05_19 e os deploys da `rollout` já droparam código off-git — conferir coluna E código juntos.
2. Quem deve assinar as mensagens da cadência: o corretor atribuído ou o admin (comportamento atual via `system_user`)?
3. A cadência HSM deve respeitar quiet hours/horário comercial (hoje só a via in-window respeita)?
4. O `DisparoLeadJob`/`FollowupHsmJob` deveriam posicionar leads no funil (hoje só Meta Lead Ads entra em `novo_lead`) para que o cancel-on-reply e a visão Kanban cubram leads de disparo?
5. Generalização: a config da cadência vai para `Captain::Assistant#behavior` (JSONB) ou para um model próprio (ex.: `CadencePolicy` por inbox)?
6. O cancel-on-reply deve continuar gateado pelo estágio do funil ou migrar para marcador na ScheduledMessage (cancelar sempre que houver incoming)?
