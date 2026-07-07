# Chat SPX — Follow-up por Sequência (drip) + Chat Interno entre Agentes

> Roadmap de produto + engenharia para fechar os 2 gaps reais identificados na análise dos vídeos da **Astra online / KanbanCW** (`FlowSequência` e `Chats Internos`). Tudo o mais que os vídeos mostram **já existe** na branch `nicolas` (Kanban Monday-Projeto Fases 1–8, agendamento, automações, conexões WAHA, IA no card, dashboards). Estes dois módulos são o que falta.
>
> Princípios herdados do projeto Kanban: **conversa em primeiro lugar**, **progressivo e atrás de flag**, **reaproveitar a casa** antes de criar do zero, **validar em `nicolas.chatspx.app` antes da frota**, **commit atômico ao fim de cada fase**.

---

## 0. Por que só estes dois

Cruzamento dos vídeos com o código atual (ver análise completa na conversa):

| Recurso do vídeo (KanbanCW) | Estado no Chat SPX |
|---|---|
| Kanban funis/etapas, agendamento, widget na conversa, automações+webhook, conexões WAHA, projetos, dashboards, IA no card, permissões | ✅ Já temos |
| **Follow-up por sequência configurável (drip)** | ⚠️ Parcial — só cadência HSM Tozi *hardcoded* (`Spx::Tozi::ReactivationCadenceService`), sem builder nem uso genérico |
| **Chat interno entre agentes (UI dedicada)** | ⚠️ Parcial — backend existe (`message.private`, `funnel_item_note`), sem tela própria |
| FlowBuilder visual / Cards desacoplados da conversa | ❌ Fora deste escopo (custo alto / muda arquitetura; ver decisão na conversa) |

---

## 1. Estado atual reaproveitável (inventário aterrado)

### Para Follow-up (drip)
- **`ScheduledMessage`** (`app/models/scheduled_message.rb`) — `scheduled_at`, `status` enum (pending/sent/failed/cancelled), `attachments`, coluna `template_params` (migration `20260529120000`); FK obrigatória `conversation_id`/`inbox_id`. Scopes `pending`, `upcoming`.
- **`ScheduledMessages::CreateService`** + **`ScheduledMessages::SendJob`** + **`SendService`** (`app/services/scheduled_messages/`, `app/jobs/scheduled_messages/send_job.rb`) — pipeline de criar→enviar já testado e em produção no staging.
- **`Spx::Tozi::ReactivationCadenceService`** (`app/services/spx/tozi/reactivation_cadence_service.rb`) — **é o protótipo do drip**: itera um array `CADENCE` de passos e agenda cada um via `ScheduledMessages::CreateService` em offsets (`1.day`, `3.days`, `7.days`). Também tem `cancel_pending(conversation)` (cancela ao lead responder) e dedupe (`cadence_already_scheduled?`). Generalizar isto = o módulo A.
- **`Kanban::AutomationEngineService`** (`app/services/kanban/automation_engine_service.rb`) — motor `when→se→então` com `ACTION_TYPES = %w[move assign tag webhook]`, reentrancy guard (`MAX_DEPTH=3`), best-effort. Disparado de `FunnelItems::MoveService#perform` e `Kanban::SlaMonitorJob`. **Adicionar a ação `enroll_in_sequence` aqui pluga o drip nos gatilhos que já existem** (entrou no stage, tempo no stage).
- **`config/schedule.yml`** — já há cron Sidekiq; o disparo do próximo passo do drip pode ser por job agendado (espelhando `SendJob`) sem novo cron.

### Para Chat interno
- **`message.private`** (`app/models/message.rb`) — mensagens privadas (não vão ao cliente) já existem como conceito.
- **`FunnelItemNote`** (`app/models/funnel_item_note.rb`) — nota interna por card (`content`, `user_id`, scope `recent_first`). Resolve o caso "comentar no card", **não** o caso "conversar com o colega".
- **ActionCable** já em uso no Kanban (Fase 4 real-time de moves) — base pronta para mensagens ao vivo sem polling.
- **Notificações** Chatwoot (sino) e presença de usuário já existem para reuso de @menções.

---

## 2. Módulo A — Follow-up por Sequência (drip) configurável  🔥 *prioridade 1*

**Promessa (vídeo 1):** "criar sequências automáticas de mensagens disparadas ao associar um contato ao fluxo", em intervalos (min/horas/dias), com condições de saída. Casos: follow-up de proposta, recuperação de interesse, boas-vindas, pós-venda, reengajamento.

**Estratégia:** generalizar o que a `ReactivationCadenceService` já faz, tornando passos/tempos **configuráveis por usuário** e **inscrevíveis** manualmente ou via automação de funil.

### 2.1 Modelo de dados

```ruby
# db/migrate/XXXX_create_message_sequences.rb
create_table :message_sequences do |t|
  t.references :account, null: false
  t.string  :name, null: false
  t.boolean :active, null: false, default: true
  t.jsonb   :exit_conditions, null: false, default: {}  # ex: { on_customer_reply: true, on_status: 'resolved' }
  t.references :created_by  # User
  t.timestamps
end

# db/migrate/XXXX_create_message_sequence_steps.rb
create_table :message_sequence_steps do |t|
  t.references :message_sequence, null: false
  t.integer :position, null: false                 # ordem
  t.integer :delay_minutes, null: false, default: 0 # offset a partir do passo anterior (ou da inscrição p/ o 1º)
  t.text    :content                                # texto livre (WAHA) — suporta {{contact.name}}
  t.jsonb   :template_params                        # opcional: HSM p/ Cloud API fora da janela 24h
  t.timestamps
end

# db/migrate/XXXX_create_message_sequence_enrollments.rb
create_table :message_sequence_enrollments do |t|
  t.references :message_sequence, null: false
  t.references :conversation, null: false           # mantém "conversa em primeiro lugar"
  t.integer :status, null: false, default: 0        # active / completed / cancelled
  t.integer :current_step_position, default: 0
  t.datetime :next_run_at                           # quando o próximo passo dispara
  t.references :enrolled_by                          # User (nil = via automação)
  t.timestamps
  t.index [:message_sequence_id, :conversation_id], unique: true  # dedupe (1 inscrição ativa por conversa)
end
```

Models: `MessageSequence has_many :steps, :enrollments`; `MessageSequenceEnrollment belongs_to :conversation` (reusa a conversa real — segue o princípio do projeto, **não** cria CRM standalone).

### 2.2 Serviços / jobs (reaproveitando o pipeline existente)

- **`MessageSequences::EnrollService`** — cria a inscrição, calcula `next_run_at` do 1º passo, agenda. Idempotente (espelha `cadence_already_scheduled?`).
- **`MessageSequences::AdvanceJob`** (cron leve no `schedule.yml`, ~1min) — pega enrollments `active` com `next_run_at <= now`, envia o passo atual via **`ScheduledMessages::CreateService`** (reuso!) ou direto via SendService, avança `current_step_position`, calcula próximo `next_run_at`, ou marca `completed`.
- **Exit conditions** — `MessageSequences::CancelService` chamado de um listener `message_created` quando o cliente responde (espelha `ReactivationCadenceService.cancel_pending`), e em `conversation status changed` conforme `exit_conditions`.
- **Compatibilidade de canal** — texto livre funciona em WAHA dentro da janela 24h; fora dela, só HSM (`template_params`), igual à lógica Tozi. O builder avisa o usuário.

### 2.3 Integração com automações (ponte de 1 ação)

- Adicionar `'enroll_in_sequence'` a `FunnelAutomation::ACTION_TYPES` e um `action_enroll_in_sequence` em `Kanban::AutomationEngineService#execute_action` que chama `EnrollService`. Resultado: **"quando card entra no stage X → inscrever na sequência Y"** sai de graça, usando o motor que já existe.

### 2.4 Frontend
- **Builder** (Settings → "Sequências de follow-up"): lista de sequências; editor de passos (arrastar ordem, delay com unidade min/h/dia, texto com variáveis, anexo opcional), exit conditions com checkboxes.
- **Inscrição manual**: botão "Inscrever em sequência" no widget Kanban da conversa (`KanbanStatus.vue` / ContactPanel) e no card do board.
- **Estado**: badge "Em sequência: {nome} (passo 2/4)" no card + opção cancelar.

### 2.5 Fases

| Fase | Entrega | Flag |
|---|---|---|
| **A1 — Fundação** | Migrations + models + `EnrollService`/`AdvanceJob`/`CancelService` + cron; sem UI (testável por console/spec). Reusa `ScheduledMessages::CreateService`. | `message_sequences` |
| **A2 — Builder + inscrição** | CRUD de sequências (controller+policy+Vue), inscrição manual no widget/card, badge de estado, cancelar. | (mesma) |
| **A3 — Ponte automação + exit conditions ricas** | Ação `enroll_in_sequence` no motor; listeners de reply/status; relatório simples (inscritos/concluídos/saídas). | (mesma) |

---

## 3. Módulo B — Chat Interno entre Agentes  💰 *prioridade 2*

**Promessa (vídeo 2):** "espaço dedicado para comunicação entre agentes e equipes, separado do atendimento ao cliente". Não é nota no card (já temos) — é **conversa agente↔agente / por equipe**.

**Estratégia:** módulo leve novo, reusando ActionCable e o sistema de notificações; **não** reusar o pipeline de `Conversation` (acoplado a inbox/contato/canal — overhead e risco). Modelo próprio enxuto.

### 3.1 Modelo de dados

```ruby
# db/migrate/XXXX_create_internal_channels.rb
create_table :internal_channels do |t|
  t.references :account, null: false
  t.string  :name                       # nil em DMs
  t.integer :channel_type, null: false, default: 0  # direct (1:1) / group / team
  t.references :team                     # opcional: canal espelha um Team
  t.timestamps
end

# db/migrate/XXXX_create_internal_channel_members.rb
create_table :internal_channel_members do |t|
  t.references :internal_channel, null: false
  t.references :user, null: false
  t.datetime :last_read_at              # p/ badge de não-lidas
  t.timestamps
  t.index [:internal_channel_id, :user_id], unique: true
end

# db/migrate/XXXX_create_internal_messages.rb
create_table :internal_messages do |t|
  t.references :internal_channel, null: false
  t.references :user, null: false       # autor
  t.text :content, null: false
  t.timestamps
end
# anexos via has_many_attached :attachments (Active Storage, já configurado)
```

### 3.2 Backend
- **`InternalMessages::CreateService`** — cria msg, broadcast via ActionCable (`InternalChannelChannel`), dispara notificação a membros offline + @menções (reusa sino existente).
- **Policies Pundit** — membro do canal só vê/escreve no que participa; admin gerencia canais; canal `team` auto-inclui membros do Team.
- **Presença e não-lidas** — `last_read_at` por membro → contador no menu.

### 3.3 Frontend
- Nova entrada no menu lateral "Chat interno" (atrás da flag e da permissão granular já existente).
- Layout 2 colunas: lista de canais/DMs (com badge não-lidas) + thread com composer (texto, @menção, anexo, emoji).
- Real-time via ActionCable; auto-scroll; "digitando…" opcional.

### 3.4 Fases

| Fase | Entrega | Flag |
|---|---|---|
| **B1 — Fundação + DM** | Migrations + models + `CreateService` + ActionCable + tela mínima de DM 1:1 entre agentes. | `internal_chat` |
| **B2 — Canais de grupo/equipe + não-lidas + @menções** | Canais por Team, badge de não-lidas, notificação/sino em @menção, anexos. | (mesma) |

---

## 4. Flags, riscos e validação

- **⚠️ Orçamento de feature flags:** `feature_flags` é bitmask `bigint` (máx 63 bits) e o fork **já está no limite** — habilitar `message_sequences` e `internal_chat` exige reclamar slots de flags deprecadas (ver `[[feature-flags-bigint-limit]]`). Conferir bits livres ANTES de A1/B1; se faltar, reusar slot de flag morta + restart.
- **Conversa em primeiro lugar:** o drip enrollment referencia `conversation_id` (não criamos lead/card standalone) — coerente com a decisão de **não** desacoplar cards.
- **Best-effort no motor:** a ação `enroll_in_sequence` deve falhar de forma silenciosa/logada como as demais, nunca quebrar um move.
- **WAHA vs Cloud API:** passos de texto livre só entregam dentro da janela 24h no WAHA; fora dela exigem HSM. O builder precisa sinalizar isso (reusar a lógica `cloud_api_inbox?` da Tozi).
- **Idempotência/dedupe:** índice único impede inscrição dupla; `AdvanceJob` deve ser reentrante (vários ticks não duplicam envio).
- **Validação:** cada fase entra atrás de flag, é validada em `nicolas.chatspx.app` (build assets + `sudo /bin/systemctl restart chatwoot.target`), e só então segue. Specs request+service verdes antes do commit.
- **Não regredir:** `ScheduledMessage` e `ReactivationCadenceService` continuam funcionando (o drip reusa o serviço, não o substitui).

---

## 5. Priorização sugerida

1. **A1 → A2 → A3** (Follow-up/drip) — maior valor/menor risco; é a manchete do vídeo 1 e reaproveita 80% de código existente.
2. **B1 → B2** (Chat interno) — valor de colaboração; backend leve, maior peso no frontend.

Sugestão: fechar **A** inteiro (entrega de negócio completa) antes de abrir **B**, mantendo o padrão de commit atômico por fase.

---

## 6. Plano de implementação detalhado — Módulo A (Follow-up/drip)

> Padrões confirmados no repo: controllers herdam `Api::V1::Accounts::BaseController` + `policy_scope` + `check_authorization` (ver `Funnels::FunnelItemNotesController`); rotas aninhadas em `config/routes.rb` (bloco `accounts`); front em `app/javascript/dashboard/api/kanban.js` + store `store/modules/kanban`; listeners registrados em `app/dispatchers/async_dispatcher.rb`; a ação do motor entra em `Kanban::AutomationEngineService#execute_action`.

### Passo 0 — Flag (bloqueante, fazer antes de tudo)
- `config/features.yml`: adicionar `- name: message_sequences / display_name: Message Sequences / enabled: false`.
- ⚠️ Conferir orçamento de bits: `feature_flags` é bitmask `bigint` (máx 63) e o fork está no limite ([[feature-flags-bigint-limit]]). Se não houver bit livre, reclamar slot de flag `deprecated: true` (ex.: `channel_twitter`) e mapear `message_sequences` nesse bit. Validar com `Account.first.feature_enabled?('message_sequences')` no console após restart.

### Fase A1 — Fundação (sem UI; testável por spec/console) ✅ FEITA (2026-06-25)
> **Status:** implementada e verde. 35 specs + schedule_spec passando (test DB isolado `chatwoot_test`), RuboCop limpo. **Ainda NÃO commitada nem aplicada ao banco do staging** (migration só rodou no test DB). `features.yml` deliberadamente NÃO tocado nesta fase — A1 é inerte (nada dispara sem enrollment manual). Arquivos: migrations `20260625140000/140100/140200`, models `MessageSequence(+Step,+Enrollment)`, services `MessageSequences::{Enroll,Advance,Cancel}Service`, `MessageSequences::AdvanceJob` + cron 1min em `schedule.yml`, factories+specs.

**Criar:**
- `db/migrate/XXXX_create_message_sequences.rb` — `account_id`(idx), `name`(null:false), `active`(default:true), `exit_conditions`(jsonb default:{}), `created_by_id`, timestamps.
- `db/migrate/XXXX_create_message_sequence_steps.rb` — `message_sequence_id`(idx), `position`(null:false), `delay_minutes`(null:false default:0), `content`(text), `template_params`(jsonb), timestamps.
- `db/migrate/XXXX_create_message_sequence_enrollments.rb` — `message_sequence_id`, `conversation_id`, `status`(int default:0), `current_step_position`(default:0), `next_run_at`(idx), `enrolled_by_id`, timestamps; índice único `[message_sequence_id, conversation_id]`.
- `app/models/message_sequence.rb` — `belongs_to :account`; `has_many :steps (-> { order(:position) }), :enrollments, dependent: :destroy`; `enum`-free `active` scope; validações `name` presença.
- `app/models/message_sequence_step.rb` — `belongs_to :message_sequence`; validações `position`/`delay_minutes`; `validate` conteúdo OU template_params presente (espelha `ScheduledMessage#message_or_attachments_present`).
- `app/models/message_sequence_enrollment.rb` — `belongs_to :message_sequence, :conversation`; `enum status: { active:0, completed:1, cancelled:2 }`; scopes `due -> { active.where('next_run_at <= ?', Time.current) }`.
- `app/services/message_sequences/enroll_service.rb` — `initialize(sequence:, conversation:, enrolled_by: nil)`; `perform` idempotente (não duplica enrollment ativo), grava `next_run_at = first_step.delay_minutes.minutes.from_now`.
- `app/services/message_sequences/advance_service.rb` — recebe um enrollment `due`; envia o passo atual reusando **`ScheduledMessages::CreateService`** (`scheduled_at: Time.current`) — ou `SendService` direto; avança `current_step_position`; define próximo `next_run_at` ou marca `completed`. Reentrante.
- `app/services/message_sequences/cancel_service.rb` — `cancel_for(conversation, reason:)`; cancela enrollments ativos da conversa (espelha `ReactivationCadenceService.cancel_pending`).
- `app/jobs/message_sequences/advance_job.rb` — itera `MessageSequenceEnrollment.due` e chama `AdvanceService` (best-effort, rescue por item).
- `config/schedule.yml`: cron `message_sequences_advance_job` a cada 1 min.

**Specs:** `spec/models/message_sequence*_spec.rb`, `spec/services/message_sequences/{enroll,advance,cancel}_service_spec.rb`, `spec/jobs/message_sequences/advance_job_spec.rb` (factory de sequence+steps; assert envia na ordem/intervalo, idempotência, cancelamento).

**DoD:** migrations rodam, `rspec` verde, no console: criar sequência de 2 passos → `EnrollService` → rodar `AdvanceJob` 2x simula envios na ordem. **Commit** `feat(kanban): Follow-up A1 — fundação de sequências (models+services+job)`.

### Fase A2 — Builder + inscrição manual ✅ FEITA (2026-06-25)
> **Status:** implementada e verde. Flag `message_sequences` reclamou o **bit 29** (slot deprecado `response_bot`, que era default-OFF e sem referências — `channel_twitter`/bit 4 foi descartado por ser default-ON). Backend: rotas + 2 controllers + 2 policies + 6 views jbuilder + `accepts_nested_attributes_for :steps`; **10 request specs verdes**. Frontend: `featureFlags.js`, 2 API clients, página de Settings "Sequências de Follow-up" (lista + editor de passos delay min/h/dia + exit conditions), entrada no menu lateral (gated), widget `MessageSequenceWidget` no ContactPanel (inscrever + badge passo X/Y + parar, via `woot-feature-toggle`), i18n en+pt_BR. **Build vite OK (exit 0), ESLint+RuboCop limpos.** Ainda NÃO deployado no staging.

**Backend:**
- `config/routes.rb` (bloco accounts): `resources :message_sequences` (+ nested `message_sequence_steps`) e `resources :message_sequence_enrollments, only: [:index, :create, :destroy]`.
- `app/controllers/api/v1/accounts/message_sequences_controller.rb` + `.../message_sequence_enrollments_controller.rb` (padrão `BaseController`+`check_authorization`).
- `app/policies/message_sequence_policy.rb` + `message_sequence_enrollment_policy.rb` (admin gerencia; agente inscreve — espelhar `funnel_automation_policy.rb`).
- Views jbuilder em `app/views/api/v1/accounts/message_sequences/`.

**Front:**
- `app/javascript/dashboard/api/messageSequences.js` (espelha `api/kanban.js`).
- Settings: nova rota/página "Sequências de follow-up" — lista + editor de passos (ordem drag, `delay` com unidade min/h/dia, textarea com `{{contact.name}}`, anexo opcional, exit conditions por checkbox).
- Botão **"Inscrever em sequência"** no widget `KanbanStatus.vue` (ContactPanel) e no menu do card do board; badge **"Em sequência: {nome} (passo k/n)"** + cancelar (store action consumindo o enrollments endpoint).

**Specs:** request specs dos 2 controllers; component spec do badge/inscrição.

**DoD:** criar sequência pela UI, inscrever a partir de uma conversa, ver badge, cancelar. Build vite OK. **Commit** `feat(kanban): Follow-up A2 — builder de sequências + inscrição no card`.

### Fase A3 — Ponte automação + exit conditions + relatório ✅ FEITA (2026-06-25)
> **Status:** implementada e verde. Ação `enroll_in_sequence` no motor (`ACTION_TYPES` + `action_enroll_in_sequence`), listener `MessageSequences::ExitListener` (registrado no `async_dispatcher`) que cancela por-enrollment ao cliente responder (`on_customer_reply`) ou ao status casar (`on_status`), e relatório simples (contadores active/completed/cancelled no payload + na lista de Settings). 7 specs A3 + 6 do motor existente (sem regressão) = parte dos 52 verdes do módulo. RuboCop limpo.

- `app/models/funnel_automation.rb`: adicionar `'enroll_in_sequence'` a `ACTION_TYPES`.
- `app/services/kanban/automation_engine_service.rb`: `when 'enroll_in_sequence' then action_enroll_in_sequence(action)` → `MessageSequences::EnrollService.new(sequence: find(action['sequence_id']), conversation:, enrolled_by: moved_by).perform` (best-effort, dentro do rescue existente).
- UI de automação do funil: opção de ação "Inscrever em sequência" com seletor de sequência.
- **Exit conditions:** novo listener `app/listeners/message_sequences/exit_listener.rb` (registrar em `async_dispatcher.rb`) com `message_created` (incoming do cliente → `CancelService.cancel_for(conv, reason: :customer_reply)` se `exit_conditions['on_customer_reply']`) e `conversation_status_changed` (→ cancela se status casa). Espelha `Spx::Tozi::FunnelAutomationListener`, cada handler rescue-wrapped.
- Relatório simples: contador inscritos/concluídos/cancelados por sequência (reusar dashboards Fase 6).

**Specs:** engine spec cobrindo a nova ação; listener spec de cancelamento por reply/status.

**DoD:** "card entra no stage X → inscreve na sequência Y" funciona ponta-a-ponta; cliente responde → sequência cancela. **Commit** `feat(kanban): Follow-up A3 — ação enroll_in_sequence + exit conditions + relatório`.

---

## 7. Plano de implementação detalhado — Módulo B (Chat interno)

### Passo 0 — Flag
- `config/features.yml`: `internal_chat` (mesma checagem de orçamento de bits do A).

### Fase B1 — Fundação + DM 1:1 ✅ FEITA (2026-06-25)
> **Status:** implementada, verde e DEPLOYADA no staging. Flag `internal_chat` reclamou o **bit 30** (slot deprecado `message_reply_to`, sem refs em app/). Decisão-chave: **reusa o `RoomChannel` existente** (cada user já faz `stream_from pubsub_token`) + `ActionCableBroadcastJob` para empurrar `internal.message.created` aos tokens dos membros, e um handler novo no `ActionCableConnector` — sem channel/conector novo. Backend: 3 migrations + 3 models (`InternalChannel`/`Member`/`Message`; enum `group_chat` p/ não colidir com `.group`), `FindOrCreateDmService` (idempotente), `InternalMessages::CreateService` (cria+broadcast+marca lido), 3 controllers + policy membro-only + views jbuilder; **31 specs verdes**. Frontend: área primária na sidebar (gated, com badge de não-lidas), rota `internal-chat`, store module, `InternalChatIndex.vue` (lista de DMs + thread + composer + novo DM), API client, i18n en+pt_BR. Migration aplicada no staging, `chatwoot.target` reiniciado, flag ligada na conta #1. Build vite OK; RuboCop limpo.

**Backend:**
- Migrations: `internal_channels` (`account_id`, `name`, `channel_type` int, `team_id` opcional), `internal_channel_members` (`internal_channel_id`, `user_id`, `last_read_at`; único `[channel,user]`), `internal_messages` (`internal_channel_id`, `user_id`, `content`); anexos via `has_many_attached :attachments`.
- Models `InternalChannel` / `InternalChannelMember` / `InternalMessage`.
- `app/services/internal_messages/create_service.rb` — cria msg + broadcast ActionCable.
- Canal ActionCable `app/channels/internal_channel_channel.rb` (autorizar por membership).
- Rotas + controllers `internal_channels_controller.rb` / `internal_messages_controller.rb` + policies (membro-only).

**Front:**
- `app/javascript/dashboard/api/internalChat.js` + store module.
- Entrada de menu lateral "Chat interno" (atrás da flag + permissão).
- Tela mínima: lista de DMs + thread + composer (texto/anexo), real-time via ActionCable.

**Specs:** model + create_service + request specs; component spec da thread.

**DoD:** dois agentes trocam DMs em tempo real no staging. **Commit** `feat(internal-chat): B1 — fundação + DM 1:1 em tempo real`.

### Fase B2 — Canais de grupo/equipe + não-lidas + @menções ✅ FEITA (2026-06-25)
> **Status:** implementada, verde e DEPLOYADA no staging. Não-lidas já vieram na B1. Backend: `InternalChannels::CreateService` (grupo com membros escolhidos; canal de equipe **find-or-create** com auto-inclusão de `team.members`); `InternalMessage.mentioned_user_ids` (jsonb, migration `20260625160000`); `CreateService` de mensagem aceita `mentioned_user_ids` (filtra p/ membros, exclui autor) + persiste + broadcast `internal.mention.created`; anexos no payload; controller de canais ramifica DM/grupo/equipe. **39 specs verdes.** Frontend: menu "+" (DM/Grupo/Equipe), form de grupo, seletor de equipe (reusa store `teams`), composer com emoji (`EmojiInput`), anexo (FormData), @menção (picker de membros + destaque das msgs que me citam) e **toast de menção em tempo real disparado pela Sidebar**. **Decisão de segurança:** @menção NÃO usa o sino global (hardwired a Conversation — enum fechado + navegação `/conversations`); entrega em tempo real via o mesmo ActionCable. Build vite OK; RuboCop limpo.

### Fase B2 (referência original) — Canais de grupo/equipe + não-lidas + @menções
- `channel_type` group/team; canal `team` auto-inclui membros do `Team`.
- `last_read_at` → contador de não-lidas no menu (badge).
- @menção dispara notificação/sino (reusar sistema de notificações existente).
- Anexos + emoji no composer.

**DoD:** canal de equipe com badge de não-lidas e @menção notificando. **Commit** `feat(internal-chat): B2 — canais de equipe, não-lidas e @menções`.

---

## 8. Sequenciamento e Definition of Done global

**Ordem recomendada:** `A1 → A2 → A3` (entrega de negócio completa) e só então `B1 → B2`.

**DoD por fase (regra dura do usuário):**
1. `bundle exec rspec` dos specs novos/afetados verde + `yarn lint`/build vite verde.
2. Deploy no staging: `assets:precompile` + `sudo /bin/systemctl restart chatwoot.target` ([[nicolas-staging-build-restart]]).
3. Validação visual/funcional do usuário em `nicolas.chatspx.app` ([[test-in-staging-not-production]]) — **nunca** na frota/produção.
4. Migrations: aplicar primeiro no staging; só ir à frota após aprovação ([[safety-do-no-harm]]).
5. Commit atômico ao fim da fase com a mensagem sugerida acima.

**Riscos a vigiar:** orçamento de bits de flag (passo 0 de cada módulo); `AdvanceJob` reentrante (não duplicar envio); WAHA fora da janela 24h (só HSM); listeners rodam para toda conta da instância → cada handler rescue-wrapped e no-op quando a feature não está habilitada na conta.

**Estimativa grosseira:** A1 ~2–3d · A2 ~3–4d · A3 ~2d · B1 ~3–4d · B2 ~3d (esforço honesto, sem contar validação).
