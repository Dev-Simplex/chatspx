# Investigação Extra 2 — SLA Enterprise como gatilho temporal nativo

> Mapeamento da cadeia `add_sla` → `AppliedSla` → cron 5 min → `EvaluateAppliedSlaService` → `SlaEvent` → notificação, com foco em: serve de "lead sem resposta há X" com escalação nativa pra secretária/admin? Quem é notificado? Respeita business hours? `waiting_since`/`first_reply_created_at` ficam íntegros nos fluxos de disparo e da Clara? `reporting_events` serve de métrica por corretor?

**Data:** 2026-06-10 · **Branch:** paulao · **Repo:** C:/Users/paulo/Workspaces/chatspx

---

## 1. Veredito curto

**O ciclo de SLA existe, está ligado no cron e FUNCIONA no fork — a conclusão "follow-up temporal nativo é impossível" fica PARCIALMENTE invalidada.** O SLA Enterprise é um gatilho temporal nativo re-avaliado a cada 5 minutos com escalação interna (notificação a admins + assignee + participantes da conversa). Ele serve como **alerta de "lead esperando resposta humana há X"** para o cenário típico pós-consolidação da Tozi (conversa única que já teve resposta de corretor). Ele **NÃO serve** como cadência de follow-up *para o lead* (não envia nada ao cliente — só notifica internamente), **NÃO respeita business hours** (flag persistido e ignorado na avaliação), e tem uma **limitação fatal com `lock_to_single_conversation`**: o `AppliedSla` vira `hit`/`missed` terminal na primeira resolução da conversa e nunca mais pode ser re-aplicado naquela conversa.

---

## 2. A cadeia completa, arquivo por arquivo

### 2.1 Cron (5 min) → fan-out por conta

- `config/schedule.yml:13-16` — `trigger_scheduled_items_job: cron: '*/5 * * * *'`, classe `TriggerScheduledItemsJob`, fila `scheduled_jobs`.
- `app/jobs/trigger_scheduled_items_job.rb:25` — `TriggerScheduledItemsJob.prepend_mod_with('TriggerScheduledItemsJob')` (extensão Enterprise via prepend).
- `enterprise/app/jobs/enterprise/trigger_scheduled_items_job.rb:9` — o overlay chama `Sla::TriggerSlasForAccountsJob.perform_later`.
- `enterprise/app/jobs/sla/trigger_slas_for_accounts_job.rb:5-8` — `Account.joins(:sla_policies).distinct.find_each` → enfileira `Sla::ProcessAccountAppliedSlasJob` por conta. **Não checa feature flag** — basta a conta ter UMA `SlaPolicy` criada para entrar no ciclo.
- `enterprise/app/jobs/sla/process_account_applied_slas_job.rb:5-7` — itera `account.applied_slas.where(sla_status: %w[active active_with_misses])` e enfileira **1 job por AppliedSla ativo** (`Sla::ProcessAppliedSlaJob`, fila `:medium`).
- `enterprise/app/jobs/sla/process_applied_sla_job.rb:4-6` — delega pro `Sla::EvaluateAppliedSlaService`.

### 2.2 Como o SLA entra na conversa

Dois caminhos:

1. **Automação (`add_sla`)** — `enterprise/app/models/enterprise/automation_rule.rb:6-8` adiciona `add_sla` às `actions_attributes` do OSS (`app/models/automation_rule.rb:42-46`). A ação é executada por `Enterprise::ActionService#add_sla` (`enterprise/app/services/enterprise/action_service.rb:2-11`): early-return se a conversa **já tem** `sla_policy` (linha 7) — não dá pra trocar/re-aplicar via automação. Eventos de automação disponíveis (`app/listeners/automation_rule_listener.rb:2-21`): `conversation_created`, `conversation_updated`, `conversation_opened`, `message_created`. Importante: `conversation_opened` só dispara quando o status muda para `open` (`app/models/conversation.rb:382`) — o limbo `pending!` do bot **não** dispara `conversation_opened`; `message_created` dispara sempre.
2. **Direto no model** — setar `conversation.sla_policy_id` (API/console). `enterprise/app/models/enterprise/concerns/conversation.rb:9-10` tem `before_validation :validate_sla_policy` + `around_save :ensure_applied_sla_is_created` quando `sla_policy_id_changed?`. O `ensure_applied_sla_is_created` (linhas 31-38) cria o `AppliedSla` na mesma transação. O `validate_sla_policy` (linhas 15-28) **proíbe remover** (`'cannot remove sla policy from conversation'`) e **proíbe trocar** (`'conversation already has a different sla'`) a policy.

### 2.3 Avaliação — `Sla::EvaluateAppliedSlaService`

`enterprise/app/services/sla/evaluate_applied_sla_service.rb`:

- **frt** (`check_first_response_time_threshold`, linhas 28-34): `threshold = conversation.created_at + sla_policy.first_response_time_threshold`. Hit se `first_reply_created_at <= threshold` (linha 36-38); miss se o relógio passou sem first reply. **Âncora = `created_at` da CONVERSA**, não o momento do apply do SLA. Dedupe: 1 único evento `frt` por AppliedSla (meta `{}`, `already_missed?` linha 57-59).
- **nrt** (`check_next_response_time_threshold`, linhas 40-50): retorna cedo se `first_reply_created_at.blank?` (linha 42 — "ainda coberto pelo frt") **ou** se `waiting_since.blank?` (linha 44 — "esperando o cliente"). `threshold = waiting_since + next_response_time_threshold`. Miss → `SlaEvent` com `meta: {message_id: último incoming}` (linha 71) — **re-dispara a cada novo incoming do cliente sem resposta** (o `message_id` muda → o dedupe `already_missed?` deixa passar) → re-notificação recorrente. Esse é o comportamento de escalação que interessa.
- **rt** (`check_resolution_time_threshold`, linhas 61-68): `created_at + resolution_time_threshold` enquanto não resolvida. Evento único.
- **Encerramento terminal** (linhas 4-12 + 82-94): quando `conversation.resolved?`, o `AppliedSla` vira `hit` ou `missed` — e o `ProcessAccountAppliedSlasJob` só processa `active`/`active_with_misses`. **Resolveu → o SLA daquela conversa morreu para sempre.** Combinado com a proibição de trocar/remover a policy (2.2) e o `has_one :applied_sla` (`enterprise/app/models/enterprise/concerns/conversation.rb:6`), numa inbox com `lock_to_single_conversation=true` (inbox 91) **o SLA só funciona no primeiro ciclo de vida da conversa única**. Re-aplicar exigiria código novo ou cirurgia via console (`applied_sla.destroy` + `update_column(:sla_policy_id, nil)` + novo `add_sla`).
- **`only_during_business_hours` é flag morto na avaliação.** A coluna existe (`enterprise/app/models/sla_policy.rb:10`), é permitida no controller (`enterprise/app/controllers/api/v1/accounts/sla_policies_controller.rb:26`) e exibida no payload (`enterprise/app/models/applied_sla.rb:57`), mas o `EvaluateAppliedSlaService` **nunca a lê** — grep por `only_during_business_hours` em `app/` + `enterprise/` retorna só model/controller/presenter, nenhum service. Os thresholds correm em tempo-calendário 24/7. Alerta de madrugada acontece.

### 2.4 SlaEvent → quem é notificado

`enterprise/app/models/sla_event.rb`:

- `after_create_commit :create_notifications` (linha 34).
- `create_notifications` (linhas 64-86): notifica a união de **(a) participantes da conversa** (`conversation.conversation_participants.map(&:user)`), **(b) TODOS os administradores da conta** (`account.administrators`, linha 67), **(c) o assignee** (linha 69). Tipos: `frt → sla_missed_first_response`, `nrt → sla_missed_next_response`, `rt → sla_missed_resolution` (linhas 71-75), todos existentes em `Notification::NOTIFICATION_TYPES` (`app/models/notification.rb:44-46`).
- `NotificationBuilder` (`app/builders/notification_builder.rb:25-38`): para tipos SLA a notificação **in-app é criada incondicionalmente** (a checagem de subscription só vale pra `conversation_creation`, linha 27). Só pula se o contato está bloqueado.
- **Entrega push/email é opt-in**: `Notification#process_notification_delivery` (`app/models/notification.rb:200-209`) só enfileira `PushNotificationJob`/`EmailNotificationJob` se o flag do usuário estiver ligado. O default ao entrar na conta é APENAS `email_conversation_assignment` + `push_conversation_assignment` (`app/models/account_user.rb:46-51`) — **ninguém recebe push/email de SLA por padrão**; cada usuário (Guilherme, secretária) precisa ligar `*_sla_missed_*` no perfil. A notificação do sino (in-app) sempre aparece.
- **Mailer já em PT no fork**: `enterprise/app/mailers/enterprise/agent_notifications/conversation_notifications_mailer.rb:8,20,30` — "Conversa [ID - X] perdeu SLA para primeira resposta / próxima resposta / tempo de resolução" (upstream é inglês; o fork traduziu).
- **Dedup engole histórico**: `Notification::RemoveDuplicateNotificationJob` (`app/jobs/notification/remove_duplicate_notification_job.rb:12-16`) mantém só a notificação mais recente por (user, primary_actor=conversa). Uma notificação SLA substitui a anterior da mesma conversa pro mesmo usuário (e vice-versa com assignment).
- **Escalação pra secretária**: ela só recebe se for **administrator** ou **participante da conversa**. Com a custom role "Corretor"/secretária-agent restritiva, o caminho natural é a IA (ou automação) **adicioná-la como `conversation_participant`** — aí ela entra na lista do `create_notifications`. Risco: notificação in-app de conversa que o `Enterprise::Conversations::PermissionFilterService` não deixa ela abrir → clique morto (403/404).

### 2.5 Visibilidade extra pro front e pra webhooks

- `AppliedSla#push_conversation_event` (`enterprise/app/models/applied_sla.rb:44,64-72`): quando `sla_status` muda (ex.: `active → active_with_misses`), dispara `conversation.dispatch_conversation_updated_event` → evento `CONVERSATION_UPDATED` → **webhooks de conta inscritos em `conversation_updated` recebem o update**, e o payload Enterprise inclui `applied_sla`, `sla_events` e `sla_policy_id` **se a feature `sla` estiver ligada na conta** (`enterprise/app/presenters/enterprise/conversations/event_data_presenter.rb:3-8`). Esse é um hook externo de orquestração: SLA estourou → webhook → IA reage. Limitação: o status só muda UMA vez pra `active_with_misses`; misses subsequentes (novos SlaEvents nrt) não mudam `sla_status` → não re-disparam esse evento.
- Feature flag `sla` (`config/features.yml:123-127`): `enabled: false`, `premium: true`. Gateia **UI/finder/presenter** (`enterprise/app/finders/enterprise/conversation_finder.rb:3`), mas **NÃO gateia o motor** — `TriggerSlasForAccountsJob` roda pra qualquer conta com policy, e o `SlaPoliciesController` (`enterprise/app/controllers/api/v1/accounts/sla_policies_controller.rb`) herda de `EnterpriseAccountsController` que é **vazio** (`enterprise/app/controllers/api/v1/accounts/enterprise_accounts_controller.rb:1-2`) — sem checagem de flag no create. Política de acesso: admin/agent podem listar; ver `enterprise/app/policies/sla_policy_policy.rb`.

---

## 3. Integridade de `waiting_since` / `first_reply_created_at` nos fluxos reais

### 3.1 Mecânica base (fork)

- **Toda conversa nasce com `waiting_since = created_at`**: `before_create :ensure_waiting_since` (`app/models/conversation.rb:152` + `302-304`).
- **Resolução zera**: `handle_resolved_status_change` → `update_column(:waiting_since, nil)` (`app/models/conversation.rb:290-294`), invariante "resolved ⇒ waiting_since IS NULL" (comentário em `app/models/message.rb:374-377`).
- **Incoming seta** (se blank e não-resolvida): `set_waiting_since_on_incoming_message` (`app/models/message.rb:378-383`). Ordem de callbacks garante reabertura ANTES (`execute_after_create_commit_callbacks`, `app/models/message.rb:341-350`: `reopen_conversation` na frente de `dispatch_create_events`) — o incoming numa resolvida reabre (`open!`/`pending!`, linhas 443-472) e depois seta `waiting_since` corretamente.
- **Resposta humana zera + gera métrica**: `clear_waiting_since_on_outgoing_response` (`app/models/message.rb:361-372`) — se `human_response?` dispara `REPLY_CREATED` (com o `waiting_since` antigo) e zera; **resposta de bot (Clara) também zera** (`bot_response?`, linha 371), mas SEM `REPLY_CREATED` (sem métrica), salvo `preserve_waiting_since` (flag usada só pelo auto-resolve do Captain, `enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb:136`).
- **`human_response?`** (`app/models/message.rb:385-394`): outgoing + sem `automation_rule_id` + **sem `campaign_id` na mensagem** + sender `User` (ou `external_echo`). **`bot_response?`** (linhas 396-399): sender_type `AgentBot` ou `Captain::Assistant`.
- **`first_reply_created_at` só nasce de resposta humana**: `valid_first_reply?` (`app/models/message.rb:229-240`) exige `human_response?`, e a contagem de respostas prévias ignora bots e campanhas (linhas 234-237). Setado em `dispatch_create_events` (linha 404-406) junto com `waiting_since: nil`.
- **`bot_handoff!`** (`app/models/conversation.rb:199-203`): **seta `waiting_since = Time.current` se blank** e abre a conversa — ou seja, o handoff da Clara ARMA o relógio nrt do SLA.

### 3.2 Fluxo de disparo (`Spx::Tozi::DisparoLeadJob`)

`app/jobs/spx/tozi/disparo_lead_job.rb`:

- O HSM é criado via `Messages::MessageBuilder.new(nil, conversation, params)` (linha 163) → **sender = nil** (`app/builders/messages/message_builder.rb:108-110`: `message_sender || @user`, ambos nil). Logo a mensagem do disparo **não é** `human_response?` nem `bot_response?` → **não seta `first_reply_created_at`, não zera `waiting_since`, não gera `REPLY_CREATED`**. Mesma coisa pro `FollowupHsmJob` (`app/jobs/spx/tozi/followup_hsm_job.rb:34`, também `MessageBuilder.new(nil, ...)`).
- Conversa NOVA de disparo (`find_or_create_conversation`, linhas 121-143) nasce com `waiting_since = created_at` (ensure_waiting_since) e `first_reply_created_at = nil` — **estado semanticamente sujo**: `waiting_since` diz "cliente esperando" mas foi a empresa quem falou primeiro. Consequências:
  - O incoming do lead dias depois **não atualiza** `waiting_since` (já estava setado desde a criação — `set_waiting_since_on_incoming_message` só seta se blank).
  - Quando o corretor finalmente responde (primeira resposta humana): `REPLY_CREATED` carrega `waiting_since = criação da conversa` → `reporting_event 'reply_time'` **gigante e espúrio** (mede desde o disparo, não desde a pergunta do lead). Idem `first_response` (ver §5). Distorção só no primeiro ciclo; depois `waiting_since` passa a ser setado pelo incoming real.
  - Conversa REUSADA pelo disparo (pós-fix `11b913531`): se estava resolvida, `waiting_since` era nil; `conversation.open!` (linha 129) não mexe; o HSM não mexe → o relógio só liga no próximo incoming do lead. **Íntegro.**

### 3.3 Fluxo Clara (Captain v2)

- Clara responde → sender `Captain::Assistant` → `bot_response?` → **zera `waiting_since`** (`app/models/message.rb:371`) sem gerar `reply_time`. Pro SLA nrt: o relógio para quando a Clara responde — "alguém respondeu" — comportamento desejável (se a IA atende, não escala).
- Clara **não** seta `first_reply_created_at` (não é human_response). Um SLA frt continua correndo mesmo com a Clara atendendo bem → frt mede "tempo até resposta HUMANA". Para conversa 100% IA isso é ruído; para "exigir toque humano em X" é feature.
- Handoff: `bot_handoff!` arma `waiting_since` (conversation.rb:199-203) → **SLA nrt passa a contar a partir do handoff** → se nenhum humano responder em X → SlaEvent nrt → notificação. **Esse é o encaixe mais limpo de escalação temporal nativa pós-handoff** — desde que a conversa já tenha `first_reply_created_at` (senão o nrt fica mudo, ver §4-gap 2).

---

## 4. Responde "lead sem resposta há X"? — análise por cenário

| Cenário Tozi | O SLA nativo cobre? | Detalhe |
|---|---|---|
| Conversa única consolidada, corretor JÁ respondeu antes (first_reply presente), lead responde de novo e ninguém vê | **SIM — caso ideal do nrt.** | Incoming → `waiting_since` setado → `waiting_since + nrt_threshold` → miss → notificação a admins+assignee+participantes, re-disparando a cada novo incoming sem resposta (meta `message_id`). |
| Lead respondeu ao disparo e **nunca** houve resposta humana na conversa | **PARCIAL/NÃO pelo nrt; frt distorcido.** | nrt retorna cedo (`first_reply_created_at.blank?`, evaluate:42). O frt dispararia, mas ancorado no `created_at` da conversa (que é o dia do disparo) — aplicado via automação `message_created` no incoming, o frt já chega estourado → alerta "imediato" (~5-10 min após o reply), nunca "X min após o reply". Hack funcional, timing não-configurável. |
| Lead recebeu disparo e **nunca respondeu** (follow-up de reativação) | **NÃO.** | Não há gatilho que envie mensagem ao lead. O frt geraria um miss interno por conversa (ruído em massa: milhares de disparos sem resposta = milhares de notificações pra admins). Follow-up ao cliente continua sendo `ScheduledMessages`/`FollowupHsmJob`/`ReactivationCadenceService`. |
| Clara faz handoff e o corretor não pega em X | **SIM, se first_reply existe** (conversa reciclada da Tozi normalmente tem). | `bot_handoff!` arma `waiting_since`; nrt conta. |
| Conversa única que foi resolvida e o lead volta semanas depois | **NÃO (gap fatal).** | O `AppliedSla` virou `hit`/`missed` terminal na resolução (evaluate:8-11 + process_account:5) e não pode ser re-aplicado (validate em concerns/conversation.rb:15-28; add_sla early-return action_service.rb:7; `has_one :applied_sla`). |

**Conclusão:** invalida parcialmente o "impossível". Existe gatilho temporal nativo com escalação interna que cobre bem o caso "lead esperando resposta humana em conversa viva com first reply" — exatamente o incidente real da secretária. Não cobre re-aplicação pós-resolve (fatal com conversa única), não fala com o lead, não respeita business hours.

---

## 5. `reporting_events` como métrica por corretor

`app/listeners/reporting_event_listener.rb`:

- `reply_time` (linhas 72-95): gerado no `REPLY_CREATED` (somente `human_response?` — bots/campanhas ficam de fora por construção, message.rb:361-368), `user_id = conversation.assignee_id` (linha 88), `value = resposta - waiting_since`, com `value_in_business_hours` calculado contra working hours da inbox (`app/helpers/reporting_event_helper.rb:2-14`, gem working_hours + timezone da inbox).
- `first_response` (linhas 27-47): no `FIRST_REPLY_CREATED`, `user_id = message.sender_id` (o corretor que respondeu, linha 39), `value = resposta - last_non_human_activity(conversation)` (handoff/reopen mais recente, senão criação — `app/helpers/reporting_event_helper.rb:16-28`).
- `conversation_resolved` (linhas 4-25): `user_id = assignee_id`, tempo total.
- `conversation_bot_handoff` (linhas 97-122): tempo até a IA passar pro humano — métrica direta da orquestração Clara→corretor (única por conversa, guard linha 104).
- Agregação nativa por corretor: `V2::Reports::AgentSummaryBuilder` (`app/builders/v2/reports/agent_summary_builder.rb`, `group_by_key :user_id` linha 37-39) sobre `V2::Reports::BaseSummaryBuilder` (`app/builders/v2/reports/base_summary_builder.rb:16-37`) — `resolved_count`, `avg_resolution_time`, `avg_first_response_time`, `avg_reply_time` por usuário, com opção `business_hours` (linha 55-57). Exposto via API v2 de reports.
- SLA por corretor: `AppliedSla.filter_by_assigned_agent_id` (`enterprise/app/models/applied_sla.rb:39-41`) + scope `missed` (linha 42) — dá "taxa de SLA estourado por corretor".

**Serve pra balanceamento? Sim, com 2 ressalvas:** (1) o primeiro ciclo de conversas de disparo gera `reply_time`/`first_response` inflados (âncora na criação da conversa — §3.2); (2) as métricas medem só respostas humanas (bom: a Clara e os HSM não poluem), mas conversas 100% resolvidas pela IA não aparecem na régua do corretor — usar `conversation_bot_handoff` + `conversation_resolved` em conjunto.

---

## 6. Gaps e riscos consolidados

1. **AppliedSla terminal pós-resolução + proibição de re-aplicar** = incompatível com a conversa única eterna da inbox 91 (`lock_to_single_conversation`). Workarounds: nunca resolver conversa de lead em cadência (usar snooze — snooze não encerra o AppliedSla, só `resolved?` encerra); ou serviço próprio de re-arm (destroy AppliedSla + `update_column(:sla_policy_id, nil)` + re-add).
2. **nrt mudo sem first reply humano** (`evaluate_applied_sla_service.rb:42`) — o caso "disparo respondido, nunca atendido por humano" não gera nrt; só o frt distorcido.
3. **frt ancorado em `conversation.created_at`** (`evaluate_applied_sla_service.rb:29`) — espúrio em conversa reciclada/antiga: aplicar SLA hoje numa conversa de semanas → miss instantâneo + notificação espúria (one-shot, dedupada).
4. **Business hours ignorado na avaliação** — `only_during_business_hours` nunca é lido pelo service; alertas 24/7. (O cálculo business-hours existe pronto em `ReportingEventHelper#business_hours` — implementar no service seria mudança pequena.)
5. **Entrega push/email default OFF** (`account_user.rb:48-49`) — sem ação manual de cada usuário, o alerta fica só no sino.
6. **Escalação fixa** (admins + assignee + participantes, `sla_event.rb:65-69`) — secretária não-admin precisa virar participante; notificação pode apontar pra conversa que a role dela não enxerga (PermissionFilterService) → clique morto.
7. **`RemoveDuplicateNotificationJob`** mantém 1 notificação por (user, conversa) — escalações repetidas sobrescrevem o histórico no sino.
8. **Volume**: 1 `ProcessAppliedSlaJob` por AppliedSla ativo a cada 5 min — aplicar SLA em milhares de conversas de disparo = milhares de jobs/5 min na fila `:medium` + possível tempestade de notificações pra TODOS os admins.
9. **`waiting_since` sujo no disparo** (nasce na criação da conversa outbound) — distorce `reply_time`/`first_response` do primeiro ciclo e a ordenação "esperando há mais tempo" (`app/finders/conversation_finder.rb:12-13`).
10. **Feature flag `sla` desligado por default** (`config/features.yml:123-127`) — precisa ligar na conta 6 pra UI e payloads de webhook incluírem SLA; o motor roda mesmo sem o flag (inconsistência: dá pra ter SLA "invisível").

---

## 7. Hooks para a IA orquestradora

1. **Criar policies e automações via API**: `POST /api/v1/accounts/:id/sla_policies` (`enterprise/app/controllers/api/v1/accounts/sla_policies_controller.rb:11-13`) + automação com ação `add_sla` em `message_created`/`conversation_opened` (`enterprise/app/models/enterprise/automation_rule.rb:7`; executor `enterprise/app/services/enterprise/action_service.rb:2-11`). Receita anti-ruído: **policy nrt-only** (sem frt/rt) aplicada por automação no primeiro incoming — só alerta quando lead real espera resposta após first reply humano.
2. **Aplicar SLA cirúrgico por conversa**: setar `sla_policy_id` na conversa (API de update) → `ensure_applied_sla_is_created` (`enterprise/app/models/enterprise/concerns/conversation.rb:31-38`) cria o AppliedSla transacionalmente.
3. **Observar misses**: (a) tabela `sla_events` (com `conversation_id`, `inbox_id`, `event_type`, `meta.message_id`) é polling-friendly; (b) webhook `conversation_updated` quando `sla_status` muda (`enterprise/app/models/applied_sla.rb:64-72`) com `applied_sla`/`sla_events` no payload se feature `sla` ligada (`enterprise/app/presenters/enterprise/conversations/event_data_presenter.rb:3-8`) — dispara UMA vez (active→active_with_misses); (c) notificações (`sla_event.rb:64-86`).
4. **Escalar pra secretária**: IA adiciona a secretária como `conversation_participant` (API de participants) → ela entra automaticamente na lista de notificados do SlaEvent (`sla_event.rb:65`). Alternativa: promovê-la a administrator (recebe TUDO da conta).
5. **Armar relógio no handoff**: `Conversation#bot_handoff!` (`app/models/conversation.rb:199-203`) seta `waiting_since` — a Clara que faz handoff liga o timer nrt sozinha. A IA pode também setar `waiting_since` diretamente quando quiser armar um timer "responder até X" (campo permitido em `list_of_keys` p/ eventos, `conversation.rb:360`).
6. **Métricas pra balanceamento**: API v2 reports summary por agente (`V2::Reports::AgentSummaryBuilder`, group por `user_id`) + `AppliedSla.filter_by_assigned_agent_id.missed` pra taxa de estouro por corretor + `conversation_bot_handoff` events pra medir o funil IA→humano.
7. **Mensagem ao lead continua fora do SLA**: pra cadência ativa ao cliente, combinar o alerta SLA (interno) com `ScheduledMessages`/`Spx::Tozi::ReactivationCadenceService` (já mapeados em outras frentes) — o SLA é o "despertador", não o "mensageiro".

---

## 8. Perguntas em aberto

1. A conta 6 em produção tem alguma `SlaPolicy` criada hoje? (Se não, o `TriggerSlasForAccountsJob` nem itera a conta — custo zero até criar a primeira.)
2. Ligar a feature `sla` na conta 6 muda o payload de webhooks `conversation_updated` consumidos por integrações existentes — algum consumidor quebraria com os campos novos `applied_sla`/`sla_events`?
3. Vale implementar o respeito a `only_during_business_hours` no `EvaluateAppliedSlaService` (o helper de working hours já existe) ou aceitar alerta 24/7 dado que corretor de imobiliária trabalha fim de semana?
4. Para a conversa única da Tozi: a estratégia será "nunca resolver, só snooze" (preserva o AppliedSla ativo) ou construir um serviço de re-arm do SLA no reopen?
5. A secretária será admin (recebe tudo, inclusive ruído) ou participante seletiva via IA (precisa garantir que a role dela enxerga a conversa — hoje o PermissionFilterService pode bloquear)?
