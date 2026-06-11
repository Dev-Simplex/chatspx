# Mapa de despacho de eventos — message_created, conversation_created, conversation_opened, conversation_updated, conversation_status_changed

> Investigação extra 1 do mapeamento de arquitetura SPX (fork Chatwoot, branch `paulao`).
> Tudo baseado em leitura do código local, com referências `arquivo:linha`. Datas: 2026-06-10.

---

## 1. Anatomia do pipeline de despacho

### 1.1 O Dispatcher (singleton, carregado no boot)

- `config/initializers/event_handlers.rb:3-4` — `Rails.configuration.dispatcher = Dispatcher.instance` + `load_listeners` (a ordem de inscrição dos listeners é fixada no boot).
- `app/dispatchers/dispatcher.rb:15-18` — **TODO evento passa pelos DOIS dispatchers, sempre nesta ordem**:
  1. `@sync_dispatcher.dispatch(...)` — publica **inline, na mesma thread** que chamou `Rails.configuration.dispatcher.dispatch` (dentro do `after_commit` do model, portanto dentro do request web ou do job Sidekiq que gravou o registro).
  2. `@async_dispatcher.dispatch(...)` — **só enfileira** `EventDispatcherJob.perform_later` (`app/dispatchers/async_dispatcher.rb:2-4`).
- O parâmetro `_async` de `Dispatcher#dispatch` é **ignorado** (`dispatcher.rb:15`) — não existe modo "só sync" ou "só async".
- `app/dispatchers/base_dispatcher.rb:1-11` — `include Wisper::Publisher`; `load_listeners` faz `subscribe(listener)` na ordem do array `listeners`. Wisper 2.0.0 (`Gemfile.lock`) guarda registrations num `Set` Ruby (ordem de inserção preservada) e o broadcast chama cada listener **sequencialmente, na ordem de inscrição**, via `public_send` **sem rescue** (SendBroadcaster default).

### 1.2 SyncDispatcher — 2 listeners inline

`app/dispatchers/sync_dispatcher.rb:7-9`:
1. **ActionCableListener** (broadcast pro frontend) — handlers relevantes: `message_created` (`app/listeners/action_cable_listener.rb:41`), `conversation_created` (:69), `conversation_status_changed` (:83), `conversation_updated` (:90). **Não tem** `conversation_opened` (a UI se atualiza pelo `conversation_status_changed`).
2. **AgentBotListener** (ponte webhook p/ AgentBot — ex.: a antiga Clara n8n) — `conversation_opened` (`app/listeners/agent_bot_listener.rb:10`), `message_created` (:18), `conversation_resolved` (:2). Só age se houver `agent_bot_inbox` ativo ou `assignee_agent_bot` (:47-59); o efeito real é enfileirar `AgentBots::WebhookJob` (:70). Na inbox 91 hoje é no-op (`AgentBotInbox` destruído em 01/06).

Não há overlay Enterprise do SyncDispatcher (único arquivo em `enterprise/app/dispatchers/` é o do async). Há overlay de *listener*: `enterprise/app/listeners/enterprise/action_cable_listener.rb:3` adiciona só `copilot_message_created`.

⚠️ Como o sync roda **dentro** do `after_commit` do model e o Wisper não tem rescue, **uma exceção num listener sync aborta o resto da cadeia de callbacks do model** (ver §3.1: em `Message`, abortaria `send_reply` e o hook do Captain).

### 1.3 AsyncDispatcher — EventDispatcherJob e os 12 listeners

- `app/dispatchers/async_dispatcher.rb:2-4` — enfileira `EventDispatcherJob`.
- `app/jobs/event_dispatcher_job.rb:2-4` — `queue_as :critical`; `retry_on StandardError, wait: :polynomially_longer, attempts: 3`; `discard_on ActiveJob::DeserializationError`.
- `app/jobs/event_dispatcher_job.rb:14` — `publish_event` → `async_dispatcher.publish(...)` → Wisper broadcast em ordem de inscrição.
- Sidekiq: `config/sidekiq.yml` — fila `critical` é a primeira (prioridade estrita), `concurrency: 15` em produção. **15 threads = vários EventDispatcherJobs do mesmo objeto rodando em paralelo.**

**Ordem exata dos 12 listeners** (`app/dispatchers/async_dispatcher.rb:11-25` + overlay `enterprise/app/dispatchers/enterprise/async_dispatcher.rb:1-7`, que faz `super + [CaptainListener.instance]`; ativado por `prepend_mod_with('AsyncDispatcher')` em `async_dispatcher.rb:28`):

| # | Listener | Handlers p/ os 5 eventos mapeados |
|---|----------|-----------------------------------|
| 1 | `AutomationRuleListener` | `conversation_updated` (:2), `conversation_created` (:6), `conversation_opened` (:10), `message_created` (:18) — `app/listeners/automation_rule_listener.rb` |
| 2 | `Spx::Tozi::FunnelAutomationListener` | `message_created` (`app/listeners/spx/tozi/funnel_automation_listener.rb:24`), `assignee_changed` (:42). **Customização do fork** — não existe no upstream; rescue-wrapped por handler (:35-36, :50-51) |
| 3 | `CampaignListener` | nenhum dos 5 (só `campaign_triggered`, `app/listeners/campaign_listener.rb:2`) |
| 4 | `CsatSurveyListener` | `conversation_status_changed` (`app/listeners/csat_survey_listener.rb:2`) |
| 5 | `NpsSurveyListener` | `conversation_status_changed` (:2), `message_created` (:18) — `app/listeners/nps_survey_listener.rb` |
| 6 | `HookListener` | `message_created` (:2), `conversation_created` (:24) — `app/listeners/hook_listener.rb`; despacha `HookJob` p/ integrações (slack/dialogflow/google_translate/leadsquared, :70-75) |
| 7 | `InstallationWebhookListener` | nenhum dos 5 (eventos de account/users) |
| 8 | `NotificationListener` | `conversation_created` (:9 — **return se pending!** :11), `message_created` (:36 — menções + NewMessageNotificationService) — `app/listeners/notification_listener.rb` |
| 9 | `ParticipationListener` | nenhum dos 5 (`assignee_changed` apenas, `app/listeners/participation_listener.rb:4`) |
| 10 | `ReportingEventListener` | `conversation_opened` (`app/listeners/reporting_event_listener.rb:132` — calcula tempo desde o último resolved) |
| 11 | `WebhookListener` | `conversation_status_changed` (:2), `conversation_updated` (:10), `conversation_created` (:18), `message_created` (:25 — com desvio WAHA `waha_direct_case?` :34-39) — `app/listeners/webhook_listener.rb` |
| 12 | `CaptainListener` (Enterprise) | nenhum dos 5 (`conversation_resolved` apenas, `enterprise/app/listeners/captain_listener.rb:4` — memória/FAQ pós-resolução) |

Confirmado: **AutomationRuleListener é o 1º e NotificationListener o 8º**. O FunnelAutomationListener do fork foi espetado na posição 2, logo depois das automações — dentro do MESMO evento ele sempre vê o estado já mutado pelas rules.

---

## 2. O que cada um dos 5 eventos dispara, e de onde

### 2.1 Origem dos eventos no model

**`Message`** (`app/models/message.rb`):
- `after_create_commit :execute_after_create_commit_callbacks` (:145) → (:341-350), **nesta ordem inline**:
  1. `reopen_conversation` (:343 → :443-452) — snoozed→`open!`; resolved→`reopen_resolved_conversation` (:466-476): **inbox com bot ativo → `pending!`** (sem evento opened!), API → `open!`, senão `open!`. ⚠️ Esses `open!`/`pending!` commitam uma transação própria e rodam TODA a cadeia de after_commit da Conversation **antes** do MESSAGE_CREATED ser despachado.
  2. `mark_pending_conversation_as_open_for_human_response` (:344) — OSS stub `captain_pending_conversation? => false` (:462-464), **mas o overlay Enterprise implementa de verdade**: `enterprise/app/models/enterprise/message.rb:4-30` — resposta humana (não-privada, não-bootstrap de template) em conversa `pending` de inbox com `CaptainInbox` → `open!` + activity message (:37-45). *O STATE.md dizia "stubbado false" — está desatualizado: o branch paulao tem a implementação Enterprise ativa via `Message.prepend_mod_with('Message')` (message.rb:515).*
  3. `set_conversation_activity` (:345 → :490-494) — `update_columns` (sem callbacks/eventos).
  4. `dispatch_create_events` (:346 → :401-412) — **dispara `MESSAGE_CREATED`** (:402) → sync inline + enfileira async; depois `FIRST_REPLY_CREATED` ou `update_waiting_since`; depois `trigger_assignee_first_reply`.
  5. `send_reply` (:347 → :437-441) — enfileira `SendReplyJob` (espera 2s se houver anexo).
  6. `execute_message_template_hooks` (:348 → :482-484) — **`MessageTemplates::HookExecutionService` INLINE** (ver §2.2).
  7. `update_contact_activity` (:349).
- `after_update_commit :dispatch_update_event` (:147) → `MESSAGE_UPDATED` (:254).

**`Conversation`** (`app/models/conversation.rb`):
- `after_update_commit :execute_after_update_commit_callbacks` (:156 → :275-281): `handle_resolved_status_change` (zera waiting_since), **`notify_status_change`** (:380-390 — na ordem do hash: `CONVERSATION_OPENED` se mudou status e está open, `CONVERSATION_RESOLVED`, `CONVERSATION_STATUS_CHANGED` (sempre que status muda — ou seja, um reopen emite **opened E status_changed**, nessa ordem), `CONVERSATION_READ`, `CONVERSATION_CONTACT_CHANGED`), `create_activity`, **`notify_conversation_updation`** (:349-357 — `CONVERSATION_UPDATED` só p/ chaves permitidas :359-369 e **NUNCA quando o status mudou** :354), `update_messages_team_id`.
- `after_update_commit :move_to_automated_stage, if: :saved_change_to_status?` (:157 → :443-448) — Kanban INLINE.
- `after_update_commit :move_to_team_funnel, if: :saved_change_to_team_id?` (:158 → :450-455) — Kanban INLINE.
- `after_create_commit :notify_conversation_creation` (:159 → :345-347) — **`CONVERSATION_CREATED`**.
- `after_create_commit :add_to_appropriate_funnel` (:161 → :420-441) — coloca o card no funil INLINE no commit da criação (FunnelLookupService + FunnelItem.find_or_create_by), rescue-wrapped (:438).
- Concern `AssignmentHandler` (incluído em conversation.rb:57): `after_commit :notify_assignment_change, :process_assignment_changes, :mark_conversation_unread_on_assignment_change` (`app/models/concerns/assignment_handler.rb:8`) — `ASSIGNEE_CHANGED`/`TEAM_CHANGED` (:55-62); `mark_as_unread!` em troca de assignee dispara `CONVERSATION_UPDATED` manual (conversation.rb:268).
- Concern `AutoAssignmentHandler` (conversation.rb:58): `after_save :run_auto_assignment` (`app/models/concerns/auto_assignment_handler.rb:6`) — roda **dentro da transação** quando status vira open; legacy chama `AgentAssignmentService` inline, v2 enfileira `AutoAssignment::AssignmentJob`.
- Overlay Enterprise (`enterprise/app/models/enterprise/conversation.rb`) não adiciona callback de commit (só eventos captain-inference :4-10 e SLA em `enterprise/app/models/enterprise/concerns/conversation.rb`).

⚠️ **Ordem REVERSA dos after_commit.** O app roda Rails **7.1.5.2** (Gemfile.lock) com `config.load_defaults 7.0` (`config/application.rb:39`) e **nenhuma** ocorrência de `run_after_transaction_callbacks_in_order_defined` em `config/` (verificado por grep). Pelo default documentado do Rails (a flag só vira `true` com `load_defaults 7.1`), os `after_commit` executam em **ordem reversa à definição**. Consequências práticas na Conversation:
- **No CREATE**: `add_to_appropriate_funnel` (161) → `load_attributes_created_by_db_triggers` (160) → `notify_conversation_creation` (159) → callbacks do `AssignmentHandler` por último. Ou seja: o card entra no funil ANTES do `CONVERSATION_CREATED` ser despachado, e `ASSIGNEE_CHANGED` (criação já atribuída, caso do disparo) é o ÚLTIMO evento enfileirado.
- **No UPDATE (reopen)**: `move_to_team_funnel` → `move_to_automated_stage` (Kanban inline ANTES dos eventos) → `execute_after_update_commit_callbacks` (despacha opened/status_changed/updated) → callbacks do AssignmentHandler.
(Não foi possível executar Ruby localmente para provar a flag em runtime; é o único ponto deste relatório baseado em default documentado e não em código do repo.)

### 2.2 HookExecutionService — o "13º listener", mas inline e fora do dispatcher

`MessageTemplates::HookExecutionService` (`app/services/message_templates/hook_execution_service.rb`) roda **inline no after_create_commit do Message** (message.rb:348), NÃO via evento:
- OSS: out-of-office / greeting / email-collect (:16-20).
- Enterprise (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb`, via `prepend_mod_with` em hook_execution_service.rb:62): `trigger_templates` (:4-10) → `should_process_captain_response?` (:129-135 — conversa **pending OU open**, incoming, `captain_assistant` presente, sem trava `atendimento_humano` :138-140) → `process_captain_behavior` (:32-44): copilot p/ privadas (:33), `router_allows?` (:46-48, RouterService = whitelist/skip_labels/skip_after_human_response), **`ensure_conversation_open`** (:59-71 — tira do pending com `Current.executed_by = assistant` e `conversation.open!`), business hours (:50-53), debounce ou `ResponseBuilderJob` (:73-81, :109-118). Sem cota → `perform_handoff` (:142-154).

Implicação de ordem: quando o Captain assume uma pending, o `open!` do `ensure_conversation_open` acontece **depois** do MESSAGE_CREATED já ter sido enfileirado (passo 4 vs passo 6 do §2.1) — então o EventDispatcherJob do `conversation.opened` pode executar **antes ou depois** do EventDispatcherJob do `message.created` da mesma mensagem.

### 2.3 Tabela-resumo: evento × execução

| Evento | Disparado de | Inline no commit (mesma thread) | Sync listeners | Async listeners (ordem 1→12) |
|---|---|---|---|---|
| `message.created` | message.rb:402 | reopen (343), auto-open Enterprise (344), activity (345), SendReplyJob enq. (347), **HookExecutionService/Captain (348)**, contact activity (349) | ActionCable:41, AgentBot:18 | Automation(1):18 → **FunnelTozi(2):24** → Nps(5):18 → Hook(6):2 → Notification(8):36 → Webhook(11):25 |
| `conversation.created` | conversation.rb:346 | funil `add_to_appropriate_funnel` (161/420), auto-assignment (`after_save`, dentro da transação) | ActionCable:69 | Automation(1):6 → Hook(6):24 → Notification(8):9 (**skip se pending**) → Webhook(11):18 |
| `conversation.opened` | conversation.rb:382 (só em UPDATE com `saved_change_to_status?` — criação já-open NÃO emite) | Kanban `move_to_automated_stage` (157) roda antes do despacho (ordem reversa) | AgentBot:10 | **Automation(1):10 (rule #53 vive aqui)** → Reporting(10):132 |
| `conversation.updated` | conversation.rb:260-261/356 (e mark_as_unread :268) | — | ActionCable:90 | Automation(1):2 → Webhook(11):10 |
| `conversation.status_changed` | conversation.rb:384 (sempre que status muda, JUNTO com opened/resolved) | — | ActionCable:83 | Csat(4):2 → Nps(5):2 → Webhook(11):2 |

(`Events::Base#method_name` traduz `'conversation.opened'` → `conversation_opened` — `lib/events/base.rb`.)

---

## 3. Garantias de ordem — o que vale e o que não vale

### 3.1 DENTRO do mesmo evento (mesmo EventDispatcherJob)
- **Garantia forte de sequência**: Wisper chama os 12 listeners um a um, na ordem da tabela, na mesma thread. O FunnelAutomationListener(2) sempre vê o resultado das automation rules(1) do MESMO evento; o WebhookListener(11) sempre fotografa o estado pós-automação.
- **Snapshot é mentira**: o `data` é serializado por GlobalID — no `perform`, `conversation`/`message` são **recarregados frescos do banco**. E o `AutomationRules::ActionService#perform` faz `@conversation.reload` antes de CADA ação (`app/services/automation_rules/action_service.rb:11`). Ou seja: a rule age sobre o estado ATUAL no momento da execução do job, não sobre o estado da hora do evento.
- **`changed_attributes` dos eventos de status é (quase sempre) nil**: `notify_status_change` passa `status_change` (conversation.rb:388) — método do ActiveModel::Dirty que, em contexto after_commit (mudança já salva), retorna nil. Condições de automação que dependem de `changed_attributes` em `conversation_opened` não têm o diff real.
- **Falha = replay parcial**: sem rescue no Wisper, exceção no listener N aborta N+1..12 e o `retry_on StandardError` (event_dispatcher_job.rb:3) re-executa o job — **listeners 1..N-1 rodam DE NOVO** (até 3 tentativas, com espera polinomial → o replay pode chegar minutos depois, totalmente fora de ordem com eventos posteriores). É exatamente o risco que o comentário do FunnelAutomationListener documenta (funnel_automation_listener.rb:5-7) — mas só ELE é rescue-wrapped; os outros 11 não são idempotentes por design.
- **Eventos de registro deletado somem em silêncio**: `discard_on ActiveJob::DeserializationError` (event_dispatcher_job.rb:4).

### 3.2 ENTRE eventos
- **Nenhuma garantia.** Cada evento é um EventDispatcherJob independente na fila `critical`, processada por 15 threads (sidekiq.yml). Enfileirar A antes de B não implica executar A antes de B; A e B podem rodar **simultaneamente** em threads distintas, e um retry empurra A para minutos depois de B.
- A única ordem "real" é a do **enfileiramento**, que segue a cadeia inline do §2.1. Ex.: numa resposta de cliente que reabre conversa resolvida (sem bot): `conversation.opened` + `conversation.status_changed` são enfileirados (passo 1, reopen) **antes** de `message.created` (passo 4) — mas podem executar em qualquer ordem.
- **Sync sempre antecede o async do mesmo evento** (dispatcher.rb:16-17): ActionCable/AgentBot rodam inline antes do EventDispatcherJob existir.
- Mutações feitas por listeners async disparam **novas cascatas** (ex.: rule que troca assignee → `ASSIGNEE_CHANGED` → FunnelAutomationListener.assignee_changed + NotificationListener.assignee_changed), com a mesma ausência de garantia. Anti-loop só existe para a própria automação: `performed_by_automation?` (automation_rule_listener.rb:73-75) ignora eventos com `performed_by` = AutomationRule; `Current.executed_by = rule` (action_service.rb:6).

### 3.3 Reposicionando as corridas já mapeadas

**(a) Rule #53 "iniciar zerado" (conversation_opened → zera assignee+team) vs atribuição do disparo — NÃO é corrida, é derrota determinística.**
`Spx::Tozi::DisparoLeadJob#find_or_create_conversation` (`app/jobs/spx/tozi/disparo_lead_job.rb:121-133`) atribui primeiro (`update!(assignee_id:)`, :127) e reabre depois (`open!`, :129). O `open!` enfileira `conversation.opened`; quando o EventDispatcherJob roda (segundos depois), o AutomationRuleListener(1º) **recarrega a conversa** (action_service.rb:11) e zera o assignee ATUAL — apagando a atribuição feita antes, sempre que as condições da rule #53 casarem. Não depende de timing: enquanto a rule executar depois do commit da atribuição (sempre, pois é async), ela ganha. O mesmo vale para reaberturas por resposta do lead em inbox sem bot (reopen_resolved_conversation → `open!`, message.rb:474). **Corolário pro go-live da Clara**: o `ensure_conversation_open` do Captain (enterprise hook_execution_service.rb:59-71) também emite `conversation.opened`; `performed_by` será `Captain::Assistant`, que NÃO é AutomationRule → `performed_by_automation?` = false → **a rule #53 rodaria e desatribuiria também as conversas que a IA acabou de assumir/abrir**. Já a criação NOVA já-atribuída (Conversation.create! com status open, disparo_lead_job.rb:133-139) **não** emite `conversation.opened` (notify_status_change é `after_update_commit`) — por isso conversas novas de disparo mantinham corretor e só as reabertas eram zeradas.

**(b) Funil vs automação — sequência em degraus, com janela de corrida só entre jobs.**
Posicionamento do funil é inline no commit da criação (`add_to_appropriate_funnel`, conversation.rb:161/420-441; com a ordem reversa, roda antes até do `CONVERSATION_CREATED`). As automation rules de `conversation_created` rodam async DEPOIS; se uma rule setar team, o `move_to_team_funnel` (conversation.rb:158/450-455) roda inline naquele segundo commit e re-posiciona o card. Isso é determinístico em si. A corrida real está **entre EventDispatcherJobs concorrentes** da mesma conversa (ex.: `conversation_created` + `message_created` da primeira mensagem + `conversation_opened` de um auto-open do Captain, três jobs em três threads): cada ActionService faz reload+write sem lock, então last-writer-wins em assignee/team/labels, e o FunnelAutomationListener pode ler um estágio que outro thread está trocando. O Kanban tem ainda dois escritores inline (`move_to_automated_stage` por status, `move_to_team_funnel` por team) + um assíncrono (FunnelAutomationListener via FunnelPlacementService) — sem arbitragem entre eles além do "quem commitou por último".

**(c) Pending limbo — explicado pela topologia de eventos.**
`reopen_resolved_conversation` (message.rb:466-476): inbox com bot → `pending!`, que emite apenas `conversation.status_changed` (+`conversation.updated` suprimido por :354) — **nunca `conversation.opened`**, e `NotificationListener.conversation_created/assignee_changed` retornam cedo em pending (notification_listener.rb:11, :26). Ou seja: pending não notifica ninguém, não dispara rules de opened — invisível por construção. A saída do limbo existe hoje em DOIS lugares inline: o auto-open do Captain quando o router deixa passar (enterprise hook_execution_service.rb:59-71) e o auto-open por resposta humana (enterprise/app/models/enterprise/message.rb:4-24). Quem não passa no router (whitelist) e não recebe resposta humana fica em pending até o auto-resolve do Captain varrer — o incidente de 02/06 por inteiro.

---

## 4. Ganchos para a IA orquestradora

1. **Posição 2 do AsyncDispatcher** (`async_dispatcher.rb:14`) — o fork já provou o padrão: um listener próprio logo após as automações, vendo o estado pós-rules do mesmo evento. Um `OrchestratorListener` ali recebe `message_created`/`conversation_created`/`assignee_changed` com sequência garantida intra-evento. Obrigatório: rescue por handler (modelo: funnel_automation_listener.rb:35-36) e idempotência (retry faz replay).
2. **HookExecutionService Enterprise** (`enterprise/.../hook_execution_service.rb:32-44`) — único ponto INLINE e síncrono no caminho da mensagem incoming, antes de qualquer listener async; é onde triagem/roteamento determinístico deve viver (o router/debounce/business-hours do Captain já estão aqui). É também o único lugar que enxerga a mensagem ANTES do `conversation.opened` que ela mesma causará.
3. **`bot_handoff!`** (conversation.rb:199-203) — evento dedicado `CONVERSATION_BOT_HANDOFF` consumido por NotificationListener(:2) e ReportingEventListener(:97); canal natural p/ IA→humano com notificação embutida (mas atenção: o `open!` interno emite `conversation.opened` → rule #53 de novo).
4. **Webhooks de account** (webhook_listener.rb) — espelho externo fiel (pós-automação) dos 5 eventos para orquestração fora do processo, com `changed_attributes` normalizado (base_listener.rb:32-43).
5. **`Current.executed_by`** — moeda de autoria que atravessa todos os eventos (conversation.rb:393, message.rb:402). Uma IA orquestradora deve se identificar nela (como o Captain faz em ensure_conversation_open) E as rules precisam aprender a respeitá-la (hoje só AutomationRule é ignorada — automation_rule_listener.rb:73-75).
6. **Kanban inline hooks** (conversation.rb:157-158) + `FunnelAutomationListener` — três escritores de funil já existentes que a IA pode reutilizar via `Spx::Tozi::FunnelPlacementService.move` em vez de inventar um quarto.

## 5. Gaps e riscos (resumo)

- Rule #53 desfaz QUALQUER atribuição anterior ao seu turno async, inclusive futuras atribuições da IA via `conversation.opened` (§3.3a). Ou a rule ganha condição/escopo, ou morre, ou aprende a respeitar `performed_by`.
- Retry do EventDispatcherJob re-executa listeners não-idempotentes (notificações duplicadas, HookJobs duplicados, rules reaplicadas) e re-ordena eventos no tempo (§3.1).
- 15 threads na `critical` = automações da mesma conversa em paralelo com last-writer-wins, sem lock (§3.3b).
- Exceção em listener SYNC aborta `send_reply`/Captain hook do Message (§1.2 + §2.1) — mensagem incoming ficaria sem resposta e sem bot, silenciosamente.
- `changed_attributes` nil em eventos de status (§3.1) limita condições finas de automação em `conversation_opened`.
- Ordem reversa de after_commit (load_defaults 7.0 em Rails 7.1) é não-óbvia e muda o enfileiramento relativo (`ASSIGNEE_CHANGED` por último no create; Kanban antes dos eventos no update) — upgrade futuro para `load_defaults 7.1` INVERTE isso silenciosamente (§2.1).
- `discard_on DeserializationError` engole eventos de registros deletados — relevante após scripts de consolidação que apagam conversas.
- STATE.md desatualizado num ponto: `mark_pending_conversation_as_open_for_human_response` NÃO está mais stubbado — o overlay Enterprise (enterprise/app/models/enterprise/message.rb:4-30) implementa o auto-open por resposta humana no branch paulao.
