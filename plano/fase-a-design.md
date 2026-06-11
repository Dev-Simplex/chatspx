# Fase A — Desenho Executável (revisão @architect, 2026-06-11 — **rev2 pós-crítica**)

> Revisão do §4 Fase A de `plano/ia-consolidado.md` CONTRA o código real (todas as
> citações arquivo:linha conferidas em 11/06). Decisões de produto respeitadas:
> D-1 (trilho AgentBot-espelho), D-3 (atribuição manual admin-only, 403; macro/automação
> passam), D-6 (IA só responde conversa atribuída a ela; RouterService aposentado,
> sobram guards técnicos activity/vazio/grupos).
>
> **Regras do fork:** working tree only (sem commit); i18n pt_BR + en; mensagem de cota
> em PT re-keyada pra conversa (A8); components-next/tokens não se aplicam (fase só backend).

---

## 0. Drift plano × código (verificado)

| Afirmação do plano | Realidade no código | Resolução |
|---|---|---|
| "Pipeline recebe assistant como argumento (selector é o único ponto inbox-keyed)" (§3 linha 73) | FALSO em parte: `schedule_captain_response` RE-deriva `conversation.inbox.captain_assistant` (`hook_execution_service.rb:110`), e gate (`:134`), quota (`:7`), supressão greeting/OOO (`:165`) e o handoff de cota (`:142-154`) são todos inbox-keyed | A2 re-keya os 5 pontos e passa o assistant resolvido adiante |
| Precedente "bot da conversa vence bot da inbox" | CONFIRMADO: `agent_bot_listener.rb:47-53` (`assignee_agent_bot` primeiro, `compact.uniq`) | usar como está; adicionar guard `webhook?` (ver A1) |
| A8 = "traduzir mensagem" | Insuficiente: `perform_handoff` só age em `conversation.pending?` (`:143`) — no modelo novo viraria **no-op silencioso** OU, sem guard novo, **spam da mensagem a cada incoming** | A8 re-keya a condição pra atribuição + desatribui o espelho após o handoff (ver A8) |
| A7 em "AssignmentService/policy" | Service é o lugar ERRADO: `Macros::ExecutionService` seta `Current.user = agente executor` (`macros/execution_service.rb:7`) — guard no service bloquearia macro de agente comum, contradizendo D-3 | Guard SÓ no controller (`assignments_controller#set_agent`) |
| "403" via policy | `Pundit::NotAuthorizedError` renderiza **401** (`request_exception_handler.rb:15-17`) | `render ... status: :forbidden` explícito (precedente: `conversations_controller.rb:244`) |
| A5 "remover uniqueness de inbox_id" | O índice DB único é no PAR (`captain_assistant_id, inbox_id` — schema:388); a 1-por-inbox é só validação de model (`captain_inbox.rb:21`) | **Zero migration**; trocar validação por uniqueness composta espelhando o índice |
| Debounce protege contra troca de dono | NÃO: token Redis é keyado por `conversation_id+assistant_id` (`redis_keys.rb:39`) — troca IA-1→IA-2 não invalida token da IA-1 | Aceite "debounce em voo descartado" garantido pelo re-check do A3, não pelo token |
| — (ausente no plano) | `scope :unassigned = where(assignee_id: nil)` (`conversation.rb:82`) + auto-assignment round-robin consome `inbox.conversations.unassigned.open` → **humano "rouba" conversa da IA** e o callback mata o bot | Tarefa nova **A2b** (obrigatória pro aceite da fase) |
| — (ausente no plano) | Scheduler do auto-resolve itera `CaptainInbox.all.find_each` (`conversations_resolution_scheduler_job.rb:11`) → com has_many enfileira a mesma inbox N× | Corrigido em A4 (distinct por inbox) |
| — (ausente no plano) | `router_service.rb:98` chama `@conversation.agent_bot_id` que NÃO existe (coluna é `assignee_agent_bot_id`) — bug latente | Guard morre em A6; **não portar** |

Call-sites completos de `inbox.captain_assistant` (singular) a migrar — grep verificado, 17 hits:
`hook_execution_service.rb:9,110,134,165` (A2) · `followup_job.rb:38` (A3) ·
`captain_listener.rb:6` · `inbox_pending_conversations_resolution_job.rb:26,35,106,115,121,127,132` ·
`enterprise/.../conversations_controller.rb:5` · `reply_suggestion_service.rb:21` (A4) ·
`enterprise/inbox.rb:15` `captain_active?` (A5/A9) · associação `enterprise/concerns/inbox.rb:5-8` (A5).

---

## Adendo pós-crítica (rev2, 2026-06-11)

> O design rev1 passou por crítica adversarial; **5 majors, 2 minors e 2 nits** sobreviveram
> à verificação contra o código (citações conferidas). Esta rev2 incorpora os fixes.
> **Status: A1 JÁ IMPLEMENTADO E NO AR** (migration aplicada, 12 espelhos sincronizados,
> specs 148/0) — o restante do design assume A1 existente (enum `captain`,
> `captain_assistant_id`, `mirror_agent_bot`, `AssistantMirrorService`).

Resumo das mudanças desta revisão:

| # | Achado (verificado) | Resolução | Onde |
|---|---|---|---|
| 1 | major | A2b cobria só o caminho V2: **4 caminhos** de auto-assignment roubam conversa da IA — legado round-robin (DEFAULT, `assignment_v2` é flag off), `BulkAutoAssignmentJob`, `ensure_assignee_is_from_team` no team-change (caminho da TRIAGEM D-6, quebra a **invariante de exclusividade** por ordem de callbacks), e o V2 | **A2b-expandida** (4 guards + spec de invariante) |
| 2 | major | Humano que responde **sem se atribuir** não cala mais a IA (`skip_after_human_response` morria sem sucessor; `reset_agent_bot` só dispara em SET de assignee) | **A2c** (nova): outgoing público de humano desatribui o espelho — sucessor estrutural transitório, no MESMO change-set do A6; revisar na Fase D |
| 3 | major | Re-check único pré-envio não cobre a **rajada de chunks** do humanizer (sleep 1,5–7s/chunk) | **A3**: re-check por chunk, posicionado após o sleep (TOCTOU residual de ms, aceito) |
| 4 | major | **1º turno mudo**: triagem (automação) é assíncrona — hook do 1º incoming roda ANTES da atribuição e nada re-dispara a resposta | **A2d** (nova): gatilho pós-atribuição re-enfileira o pipeline (mesmo entry do hook, debounce respeitado); cobre também IA→IA (C7) e E2E #2 |
| 5 | major | Critério do **backfill** incompleto (ressuscitaria às avessas guards que o A6 mata) | § Riscos: critério expandido (atendimento_humano, skip_labels, última outgoing de User, whitelist de fones, 2+ elegíveis, snoozed/resolved no runbook) |
| 6 | major→produto | Conta Clássica + CaptainInbox **sem triagem** = canal 100% silencioso (greeting suprimido + gate sem dono) | **NÃO muda o gate** — NOTA DE PRODUTO em openQuestions (decisão de go-live/Fase D) |
| 7 | minor | Auto-resolve pending segue inbox-keyed (fallback `.first`) e fala sem ser dono | Desvio CONSCIENTE de D-6 até aposentadoria (A9.4) — documentado |
| 8 | minor | Reopen pós-resolve mantinha dono-espelho (contradiz narrativa §2 / teste E2E 11) | **A2e** (nova): resolve LIMPA `assignee_agent_bot_id` (só o espelho) |
| 9 | nit | FollowupJob consumia token/followup_count antes de resolver o dono; `copilot_trigger` re-keyado passa a exigir conversa da IA | A3 (ordem corrigida) + registro (impacto ~zero) |

Tarefas novas/alteradas: **A2b-expandida**, **A2c**, **A2d**, **A2e** (detalhes nas seções).
Seções editadas: A2b, A2c–A2e (novas), A3, A6, A8, A9, Riscos, Ordem de implementação,
Mapa aceite, Divergências, openQuestions. Specs do plano (§5.1-A do `ia-consolidado.md`)
atualizadas com os cenários novos.

---

## A1 — Espelho AgentBot do assistant

> **[rev2] STATUS: IMPLEMENTADO E NO AR** — migration aplicada, 12 espelhos criados via
> `rake captain:sync_mirrors`, specs 148/0. Mantido abaixo como registro do desenho.

### Decisão: coluna `agent_bots.captain_assistant_id` (NÃO `bot_config['assistant_id']`)

Fundamentação (verificada):
- `bot_config` jsonb não tem **nenhum** consumidor backend (únicos hits: strong params
  `agent_bots_controller.rb:45` e leitura frontend), não tem índice, não dá FK.
- A coluna dá: lookup reverso barato assistant→espelho (usado pelo gate A3 e pelo sync),
  **integridade referencial** (mata o risco "espelho órfão" do §7) e **unicidade 1:1 no banco**
  (índice único parcial). `conversations.assignee_agent_bot_id` não tem FK no banco
  (schema:1490-1494 — só `dependent: :nullify` de model), então o caminho de destruição
  deve ser sempre Rails-level (callbacks), nunca SQL puro.

### Migration (nova, `db/migrate/20260611120000_add_captain_assistant_to_agent_bots.rb`)

```ruby
class AddCaptainAssistantToAgentBots < ActiveRecord::Migration[7.1]
  def change
    add_reference :agent_bots, :captain_assistant,
                  null: true, index: false,
                  foreign_key: { to_table: :captain_assistants, on_delete: :nullify }
    add_index :agent_bots, :captain_assistant_id,
              unique: true,
              where: 'captain_assistant_id IS NOT NULL',
              name: 'index_agent_bots_on_captain_assistant_id'
  end
end
```

- `on_delete: :nullify` (e não cascade): assistant deletado por SQL cru → espelho fica
  desvinculado, gate resolve `captain_assistant` nil → IA cala (seguro e detectável).
  O caminho normal (Rails `destroy`) destrói o espelho via `has_one ... dependent: :destroy`.
- Enum não precisa de migration (`bot_type` integer default 0 já existe — schema:128-138).

### Model `app/models/agent_bot.rb`

```ruby
enum bot_type: { webhook: 0, captain: 1 }                       # :37 — muda 1 linha
belongs_to :captain_assistant, class_name: 'Captain::Assistant', optional: true

validates :captain_assistant_id, presence: true, if: :captain?
validates :captain_assistant_id, absence: true, if: :webhook?
validates :outgoing_url, absence: true, if: :captain?           # espelho NUNCA tem webhook URL
```

`push_event_data` (`:45-52`): fallback de avatar do espelho passa a cair no logo captain do
assistant antes do avatar da inbox:

```ruby
avatar_url: avatar_url.presence || captain_assistant&.push_event_data&.dig(:avatar_url) || inbox&.avatar_url,
```

### Sync do espelho — `enterprise/app/services/captain/assistant_mirror_service.rb` (novo)

```ruby
class Captain::AssistantMirrorService
  def initialize(assistant)
    @assistant = assistant
  end

  # Idempotente: cria ou atualiza o espelho 1:1 (unique parcial no banco garante).
  def sync!
    mirror = AgentBot.find_or_initialize_by(captain_assistant_id: @assistant.id)
    mirror.assign_attributes(
      account_id: @assistant.account_id,
      bot_type: :captain,
      name: @assistant.name,
      description: @assistant.description,
      outgoing_url: nil
    )
    mirror.save!
    sync_avatar(mirror)
    mirror
  end

  private

  def sync_avatar(mirror)
    if @assistant.avatar.attached?
      return if mirror.avatar.attached? && mirror.avatar.blob_id == @assistant.avatar.blob_id

      mirror.avatar.attach(@assistant.avatar.blob)   # compartilha o blob, sem cópia de bytes
    elsif mirror.avatar.attached?
      mirror.avatar.purge
    end
  end
end
```

### Hooks em `enterprise/app/models/captain/assistant.rb`

O model NÃO tem nenhum callback próprio hoje (verificado :19-51) — hooks entram limpos:

```ruby
has_one :agent_bot, foreign_key: :captain_assistant_id, dependent: :destroy, inverse_of: :captain_assistant

after_commit :sync_mirror_agent_bot, on: [:create, :update]
after_touch  :sync_mirror_agent_bot   # attach de avatar (ActiveStorage) faz touch, não update

def mirror_agent_bot
  agent_bot || Captain::AssistantMirrorService.new(self).sync!
end

private

def sync_mirror_agent_bot
  Captain::AssistantMirrorService.new(self).sync!
rescue StandardError => e
  Rails.logger.error("[Captain] mirror sync falhou assistant=#{id}: #{e.message}")
end
```

- **Destroy**: `dependent: :destroy` roda dentro do `assistant.destroy` → espelho some →
  `AgentBot#assigned_conversations dependent: :nullify` (`agent_bot.rb:32-35`) solta as
  conversas (órfãs → vigia D-12 na Fase C). AccessToken do espelho morre junto
  (`access_tokenable.rb` `has_one :access_token, dependent: :destroy_async`).
- **Órfão**: impossível pelo caminho Rails; por SQL cru o FK nullify desvincula (gate cala).
  Spec trava os dois sentidos.

### Backfill — `lib/tasks/captain_mirrors.rake` (novo)

```ruby
namespace :captain do
  desc 'Cria/sincroniza o AgentBot-espelho de todos os Captain::Assistant'
  task sync_mirrors: :environment do
    Captain::Assistant.find_each { |a| Captain::AssistantMirrorService.new(a).sync! }
  end
end
```

Rodar após `db:migrate` + restart (`sudo systemctl restart chatwoot.target`). Idempotente.

### Espelho NÃO dispara webhook e NÃO aparece em assignable_agents (estrutural + spec)

1. **Webhook**: hoje o espelho só não dispara porque `outgoing_url` é blank
   (`agent_bot_listener.rb:68` — acidental, não design). Tornar estrutural:

```ruby
# app/listeners/agent_bot_listener.rb:67-71
def process_webhook_bot_event(agent_bot, payload)
  return unless agent_bot.webhook?          # guard explícito por tipo
  return if agent_bot.outgoing_url.blank?

  AgentBots::WebhookJob.perform_later(agent_bot.outgoing_url, payload)
end
```

   + a validação `outgoing_url absence if: :captain?` (dupla defesa).

2. **assignable_agents**: `Inbox#assignable_agents` (`inbox.rb:168-170`) e
   `assignable_agents_controller.rb:12` retornam apenas `account.users` + administrators —
   AgentBot estruturalmente não entra. Spec trava (antecipação barata do C8).

### Proteção do espelho no CRUD de agent_bots (`agent_bots_controller.rb`)

Espelhos apareceriam em Settings→Agent Bots e poderiam ser mutados/deletados por admin via
API (`:6-8,:45` permite `bot_type`/`bot_config`). Na Fase A:

```ruby
before_action :ensure_mutable_bot, only: [:update, :destroy, :avatar, :reset_access_token]

def ensure_mutable_bot
  return unless @agent_bot.captain?

  render json: { error: I18n.t('agent_bots.captain_mirror_immutable') }, status: :unprocessable_entity
end
```

+ em create/update: rejeitar `bot_type: 'captain'` vindo de params (espelho só nasce pelo
sync). `captain_assistant_id` NÃO entra nos strong params. Filtro visual do index fica
pra Fase C (C1/C8).

i18n novo: `agent_bots.captain_mirror_immutable` (en: "AI mirror bots are managed
automatically and cannot be modified." / pt_BR: "Bots-espelho de agentes IA são
gerenciados automaticamente e não podem ser alterados.").

Nota aceita (documentar, não bloquear): `AccessTokenable` cria um AccessToken por espelho
no `after_create` — superfície de credencial extra, token nunca exposto na UI; hardening
(revogar token de bot captain) fica como follow-up opcional.

### Specs A1
- `spec/enterprise/services/captain/assistant_mirror_service_spec.rb` (novo): create→espelho
  com nome/account/bot_type/sem outgoing_url; rename→espelho renomeia; avatar attach→mesmo
  blob; remoção de avatar→purge; idempotência (2× sync = 1 registro).
- `spec/enterprise/models/captain/assistant_spec.rb`: destroy assistant → espelho destruído
  → conversa atribuída nullificada.
- `spec/models/agent_bot_spec.rb`: validações (captain exige assistant, proíbe outgoing_url;
  webhook proíbe assistant).
- `spec/listeners/agent_bot_listener_spec.rb`: espelho captain atribuído (mesmo com
  outgoing_url forçado via update_column) → `AgentBots::WebhookJob` NÃO enfileira.
- `spec/controllers/.../agent_bots_controller_spec.rb`: update/destroy de espelho → 422;
  create com `bot_type: captain` → rejeitado.
- `spec/models/inbox_spec.rb` (ou spec do controller): `assignable_agents` nunca contém
  AgentBot (trava estrutural).

---

## A2 — Gate novo: assistant resolvido pela CONVERSA

Arquivo: `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb`.
Entrada do pipeline confirmada: `message.rb:343-352 → :484-486` (after_create_commit →
HookExecutionService; nenhum listener dispara resposta).

### Forma final

```ruby
def trigger_templates
  super
  return unless should_process_captain_response?
  return perform_handoff unless captain_quota_available?

  process_captain_behavior(assigned_assistant)
end

# Gate por ATRIBUIÇÃO (D-6): a IA só processa conversa cujo dono é o espelho dela.
# pending aceito durante a transição (legado); open é o estado normal do modelo novo.
def should_process_captain_response?
  (conversation.pending? || conversation.open?) && message.incoming? && assigned_assistant.present?
end

def assigned_assistant
  return @assigned_assistant if defined?(@assigned_assistant)

  mirror = conversation.assignee_agent_bot
  @assigned_assistant = (mirror.captain_assistant if mirror&.captain?)
end

# Quota re-keyada: não depende mais de inbox.captain_active? (que morre keyado por inbox).
def captain_quota_available?
  conversation.account.usage_limits[:captain][:responses][:current_available].positive?
end

# Supressão de greeting/OOO/email_collect por ELEGIBILIDADE (inbox tem IA) OU atribuição.
# Por quê: a triagem atribui DEPOIS da criação — se a supressão fosse só por atribuição,
# a conversa receberia greeting automático na janela entre criação e triagem (regressão
# visível). Elegibilidade preserva o comportamento atual. (Resolução técnica documentada.)
def captain_handling_conversation?
  return false unless conversation.pending? || conversation.open?

  assigned_assistant.present? || ::CaptainInbox.exists?(inbox_id: inbox.id)
end
```

### Mudanças associadas no mesmo arquivo
- `human_takeover_locked?` (`:138-140`) **morre** (trava `atendimento_humano` substituída
  estruturalmente por "dono não é o espelho" — §2 do plano). Remover também o uso no
  FollowupJob (A3) — coerência nos 2 pontos.
- `schedule_or_debounce(assistant)` → `schedule_captain_response(assistant)`;
  `job_args = [conversation, assistant]` (`:110`) — **fim do re-derive da inbox**, o job
  recebe o assistant que o gate resolveu.
- `ensure_conversation_open` (`:59-71`): mantém (no modelo novo a conversa já nasce/fica
  open; em legado pending continua tirando do limbo). Sem mudança.
- `respond_to?(:captain_assistant)` (`:165`) some junto com a reescrita — elimina o
  desligamento silencioso quando A5 remover a has_one.

### A2b-EXPANDIDA (rev2) — 4 caminhos de auto-assignment + invariante de exclusividade

`scope :unassigned` (`conversation.rb:82`) considera conversa da IA como "não atribuída".
A rev1 só cobria o caminho V2 — o crítico verificou **4 caminhos** que roubam a conversa
da IA (e o callback `reset_agent_bot_when_assignee_present`, `conversation.rb:318-322`,
mataria o bot silenciosamente — ou pior, NEM rodaria, ver caminho c):

| # | Caminho | Código | Status no fluxo real |
|---|---|---|---|
| a | **Legado round-robin** — é o DEFAULT (`assignment_v2` é feature flag, off) | `auto_assignment_handler.rb:11-26,45` → `AutoAssignment::AgentAssignmentService#perform` (faz `update(assignee:)` sem olhar bot) | dispara em todo save que abre a conversa |
| b | Bulk do V2 | `inboxes/bulk_auto_assignment_job.rb:31-40` | scheduled, contas com flag |
| c | **Team-change** — `ensure_assignee_is_from_team` auto-atribui humano do time quando `team_id` muda com assignee nil e `allow_auto_assign` | `assignment_handler.rb:13-20,48-53` | **caminho da TRIAGEM D-6** (automação seta team + espelho!) |
| d | V2 scope | `auto_assignment/assignment_service.rb:28-34` + `enterprise/.../assignment_service.rb:59-60` | já coberto na rev1 |

**Invariante de exclusividade quebrada no caminho (c):** `reset_agent_bot_when_assignee_present`
é `before_validation` (`conversation.rb:71`) e roda ANTES do `before_save
ensure_assignee_is_from_team`. Quando o time muda numa conversa da IA, o reset roda com
assignee ainda nil (no-op) e o humano é setado DEPOIS → resultado persistido:
**assignee humano E bot setados juntos** = invariante de exclusividade quebrada, no fluxo
central da triagem.

Fix (4 guards — sem mexer no scope `:unassigned`; semântica de tabs é decisão da Fase C):

```ruby
# (a) app/models/concerns/auto_assignment_handler.rb:38-46 — legado, DEFAULT
def should_run_auto_assignment?
  return false unless inbox.enable_auto_assignment?
  return false if assignee_agent_bot_id.present?   # conversa da IA não entra no round-robin
  return true if conversation_status_changed_to_resolved_or_snoozed?

  assignee.blank? || inbox.members.exclude?(assignee)
end

# (a/b) app/services/auto_assignment/agent_assignment_service.rb:11-14 — defesa em
# profundidade no service compartilhado (cobre bulk e qualquer caller futuro)
def perform
  return if conversation.assignee_agent_bot_id.present?   # nunca rouba conversa da IA

  new_assignee = find_assignee
  conversation.update(assignee: new_assignee) if new_assignee
end

# (b) app/jobs/inboxes/bulk_auto_assignment_job.rb:32
unassigned_conversations = inbox.conversations.unassigned.open
                                .where(assignee_agent_bot_id: nil)
                                .limit(Limits::AUTO_ASSIGNMENT_BULK_LIMIT)

# (c) app/models/concerns/assignment_handler.rb:13-20 — NÃO auto-atribuir humano do time
# quando o espelho é dono (triagem D-6: team + espelho na mesma automação)
def ensure_assignee_is_from_team
  if team_id_changed?
    validate_current_assignee_team
    self.assignee ||= find_assignee_from_team if assignee_agent_bot_id.blank?
  elsif will_save_change_to_assignee_id? && assignee_id.present?
    sync_team_from_assignee
  end
end

# (d) como na rev1:
# app/services/auto_assignment/assignment_service.rb:28-34
conversation.status == 'open' && conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil?
# + unassigned_conversations e enterprise/.../assignment_service.rb:59-60
scope = inbox.conversations.unassigned.open.where(assignee_agent_bot_id: nil)
```

**Invariante de exclusividade (spec de regressão obrigatória):** em NENHUM fluxo —
save direto, triagem (team + espelho na mesma automação), round-robin legado, bulk V2 —
a conversa termina persistida com `assignee_id` E `assignee_agent_bot_id` presentes ao
mesmo tempo.

### A2c — Outgoing público de humano desatribui o espelho (NOVA, rev2 — sucessor transitório do `skip_after_human_response`)

**Gap (achado 2):** `reset_agent_bot_when_assignee_present` só dispara quando o assignee é
SETADO. Humano que responde **sem se atribuir** não cala mais a IA depois que
`skip_after_human_response` morrer (A6). Janela Fase A→D; **permanente no modo Clássico**.
Fix estrutural, no MESMO change-set do A2/A6 (sem janela de regressão):

```ruby
# app/models/message.rb — execute_after_create_commit_callbacks ganha o passo
# release_captain_mirror_after_human_reply logo após
# mark_pending_conversation_as_open_for_human_response (o fork já edita essa cadeia
# — message.rb:343-352). Implementação no Enterprise::Message:

# enterprise/app/models/enterprise/message.rb
def release_captain_mirror_after_human_reply
  return unless human_response?          # outgoing + sender User OU echo nativo; exclui automação/campanha (message.rb:387-395)
  return if private?
  return if template_bootstrap_message?

  mirror = conversation.assignee_agent_bot
  return unless mirror&.captain?

  conversation.update!(assignee_agent_bot_id: nil)   # IA solta a conversa
end
```

- `human_response?` reusado de propósito: cobre **echo nativo** (atendente respondendo
  pelo app WhatsApp Business) e exclui automação (`automation_rule_id`) e campanha —
  exatamente a semântica que `skip_after_human_response` tinha (`router_service.rb:100-115`).
- Mensagem do próprio assistant (sender `Captain::Assistant`) não passa em
  `human_response?` → IA continua podendo mandar várias em sequência.
- A conversa fica **sem dono e visível** (mesma família do handoff de cota A8 — vigia
  D-12/tab condicional na Fase C). Se o humano se atribuir, o callback de exclusividade
  já cobria; este hook cobre quem só responde.
- **TRANSITÓRIO — revisar na Fase D:** quando o gate universal obrigar atribuição antes
  de responder (modo Atribuição), este hook fica redundante nesse modo — remover ou
  condicionar ao modo Clássico (anotado em openQuestions).

### A2d — Gatilho pós-atribuição cutuca o pipeline (NOVA, rev2 — 1º turno + IA→IA)

**Gap (achado 4):** a triagem é ASSÍNCRONA (`AutomationRuleListener` via
`EventDispatcherJob`) — o hook do 1º incoming roda ANTES da atribuição, o gate (A2) não
vê dono, e nada re-dispara a resposta → **IA só falaria no 2º turno**. Mesmo buraco na
transferência IA→IA (job da IA-1 morre no re-check A3 e a IA-2 nunca é cutucada).

**Decisão de arquitetura da Fase A:** quando o espelho captain é SETADO numa conversa
cuja última mensagem visível é incoming sem resposta subsequente → re-enfileirar o
pipeline pelo MESMO entry do hook (router técnico + debounce respeitados).

```ruby
# enterprise concern de Conversation (novo callback)
after_commit :kick_captain_pipeline_after_mirror_assignment

def kick_captain_pipeline_after_mirror_assignment
  return unless saved_change_to_assignee_agent_bot_id? && assignee_agent_bot_id.present?

  Captain::Conversation::AssignmentKickJob.perform_later(self)
end

# enterprise/app/jobs/captain/conversation/assignment_kick_job.rb (novo)
class Captain::Conversation::AssignmentKickJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    return unless conversation.open? || conversation.pending?
    return unless conversation.assignee_agent_bot&.captain?   # re-check: dono pode ter mudado

    last = conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                       .order(:created_at).last
    return unless last&.incoming?   # já respondida (por quem for) -> não cutuca

    ::MessageTemplates::HookExecutionService.new(message: last).perform
  end
end
```

- **Reusar o `HookExecutionService`** (e não chamar o ResponseBuilderJob direto) garante:
  guards técnicos do router, debounce (`schedule_or_debounce`), espera de attachment e
  logs — "mesmo entry do hook". Greeting/OOO não duplicam: supressão por elegibilidade
  (A2) + guards próprios dos templates (`first_message_from_contact?`,
  `messages.today.template.empty?`).
- Cobre: **1º turno pós-triagem** (teste E2E #2), **transferência IA→IA** (C7, dono novo
  responde a pergunta pendente), atribuição manual de IA pelo admin a conversa com
  incoming sem resposta, e atribuição com **cota zerada** (gate → `perform_handoff` A8:
  mensagem PT imediata + espelho solto — spec em A8).
- Loop impossível: o callback só dispara em MUDANÇA de `assignee_agent_bot_id` para valor
  presente; a resposta da IA não muda o dono. Desatribuição (A2c/A8/A2e) não dispara
  (valor ausente).

### A2e — Resolve limpa o dono-espelho (NOVA, rev2)

**Gap (achado 8):** reopen pós-resolve manteria o dono-espelho, contradizendo a narrativa
§2 do plano e o teste E2E 11 ("reabre SEM dono → triagem re-atribui"). Decisão alinhada
ao plano: **resolver a conversa LIMPA `assignee_agent_bot_id`** — SÓ o espelho; assignee
humano segue a regra atual do Chatwoot (não mexe).

```ruby
# enterprise concern de Conversation (junto do callback do A2d)
before_save :release_captain_mirror_on_resolve, if: -> { status_changed? && resolved? }

def release_captain_mirror_on_resolve
  return if assignee_agent_bot_id.blank?
  return unless assignee_agent_bot&.captain?   # bot webhook preserva comportamento atual

  self.assignee_agent_bot_id = nil
end
```

- **Interação com A4 (notes/FAQ pós-resolve):** `captain_listener.conversation_resolved`
  dispara após o commit — o dono já foi limpo, então o assistant resolve pelo fallback
  "participante" (última mensagem com sender `Captain::Assistant`) que o A4 já define.
  Spec conjunto A2e×A4 obrigatório.
- **Snooze NÃO limpa** (documentado): snoozed reabre com o mesmo dono — esperado.
- Reopen: conversa reabre **sem dono → muda** até a triagem/admin atribuir — exatamente
  o teste 11; runbook do backfill anota os dois casos (snoozed e resolved-reopen).

### Specs A2 (`spec/enterprise/services/enterprise/message_templates/hook_execution_service_spec.rb` — já existe, reescrever contextos)
- conversa SEM atribuição em inbox elegível → nenhum job, log nenhum (IA muda — aceite 1).
- atribuída ao espelho da IA-1 → `ResponseBuilderJob` enfileira com IA-1 (aceite 2).
- atribuída ao espelho da IA-2 (mesma inbox, 2 elegíveis) → job com IA-2 (aceite 3).
- atribuída a humano → silêncio (gate falha antes de qualquer log).
- atribuída a AgentBot webhook (não-captain) → silêncio captain (webhook segue trilho dele).
- `custom_attributes['atendimento_humano'] = true` → NÃO bloqueia mais (trava morta).
- greeting/OOO/email_collect suprimidos em inbox elegível mesmo sem atribuição.
- debounce_seconds > 0 → DebounceService com o assistant atribuído.
- auto-assignment: conversa atribuída à IA não entra em `unassigned_conversations` nem
  passa em `assignable?` (spec em `spec/services/auto_assignment/`).
- **[rev2] A2b-expandida**: round-robin legado (flag V2 off) não rouba conversa da IA
  (`should_run_auto_assignment?` + `AgentAssignmentService#perform`); bulk V2 idem;
  **team-change**: automação seta team + espelho → NENHUM humano auto-atribuído e
  **invariante de exclusividade** preservada (nunca `assignee_id` E
  `assignee_agent_bot_id` juntos — spec de regressão em todos os 4 caminhos).
- **[rev2] A2c**: outgoing público de User em conversa do espelho → espelho desatribuído;
  echo nativo (external_echo) idem; mensagem de automação/campanha/privada/template
  bootstrap → NÃO desatribui; outgoing do próprio assistant → NÃO desatribui.
- **[rev2] A2d**: triagem assíncrona — incoming chega SEM dono (gate cala), automação
  atribui o espelho → `AssignmentKickJob` → resposta sai no 1º turno (com debounce quando
  configurado); IA→IA com incoming pendente → IA nova responde; última mensagem visível
  outgoing → kick é no-op; dono trocado entre o callback e o job → no-op.
- **[rev2] A2e**: resolve com dono-espelho → `assignee_agent_bot_id` limpo; reopen nasce
  sem dono; notes/FAQ pós-resolve saem pelo fallback "participante" (spec conjunto A4);
  resolve com bot webhook → preservado; snooze → dono mantido.
- **[rev2] registro (nit 9)**: `copilot_trigger` re-keyado passa a exigir conversa
  atribuída à IA (mensagem privada em conversa do espelho → trigger; sem dono → não) —
  impacto ~zero, documentado.

---

## A3 — Re-check de atribuição DENTRO dos jobs

Convergência confirmada: hook (`perform_later`), debounce (`perform_now` em
`debounced_response_job.rb:20`) e followup (`perform_now` em `followup_job.rb:41`) passam
todos por `ResponseBuilderJob`, que chama `captain_can_respond?` em 2 pontos: antes do LLM
(`:12`) e depois do LLM/antes do envio (`:51`). **[rev2]** O ponto `:51` cobre a troca de
dono durante o LLM, mas NÃO cobre a **rajada de chunks do humanizer** (achado 3) — por
isso o re-check passa a rodar também POR CHUNK (ver abaixo).

### `response_builder_job.rb:297-302` — forma final

```ruby
# Captain responde em pending E em open (fork), e SOMENTE se a conversa ainda está
# atribuída ao espelho DESTE assistant (gate por atribuição, D-6). Compara com o
# assistant do ARGUMENTO (serializado via GlobalID) — job em voo de IA antiga cala.
def captain_can_respond?
  status, mirror_id = Conversation.uncached do
    Conversation.where(id: @conversation.id).pick(:status, :assignee_agent_bot_id)
  end
  return false unless [Conversation.statuses[:pending], Conversation.statuses[:open], 'pending', 'open'].include?(status)

  mirror_id.present? && mirror_id == assistant_mirror_id
end

def assistant_mirror_id
  @assistant_mirror_id ||= AgentBot.captain.where(captain_assistant_id: @assistant.id).pick(:id)
end
```

Preserva os comportamentos do fork (open além de pending, `reset_followup_state`,
reply-context, dedup/humanizer) — só a condição de dono é adicionada.

### [rev2] Rajada de chunks do humanizer — re-check POR CHUNK (achado 3)

O re-check único pré-envio não basta: `send_humanized_response` dorme **1,5–7s por chunk**
(`response_builder_job.rb:205-217`) — humano assume durante o chunk 2 e a IA ainda
despejaria 3, 4, 5 por cima dele. Fix — re-check (pick uncached de
`status`+`assignee_agent_bot_id`, o mesmo `captain_can_respond?` da forma final) **depois
do sleep, imediatamente antes de cada envio** (posição deliberada: deixa a janela TOCTOU
residual em ms, não em segundos):

```ruby
def send_humanized_response(content)
  chunks = Captain::Behavior::HumanizerService.new(config: @assistant.behavior['humanizer']).split(content)

  sent = 0
  chunks.each do |chunk|
    trigger_typing_indicator
    sleep(humanizer_typing_delay(chunk))
    break unless captain_can_respond?   # re-check por chunk: humano assumiu no meio da rajada -> para AQUI
    create_outgoing_message(chunk, agent_name: @response['agent_name'])
    sent += 1
  end
  log_behavior_event('humanizer_split', { chunks: chunks.size, sent: sent }) if chunks.size > 1
end
```

TOCTOU residual de milissegundos (entre o pick e o `create!`) **documentado como
aceitável** — eliminá-lo exigiria lock pessimista por mensagem, desproporcional ao risco.

### `debounced_response_job.rb` — early-return antes do log

Token Redis NÃO protege contra troca de dono (chave por conversa+assistant). O re-check do
ResponseBuilderJob é a autoridade; aqui só evitamos `AssistantLog 'debounce_fire'` falso:

```ruby
return unless stored_token == token
Redis::Alfred.delete(key)
return unless conversation.assignee_agent_bot&.captain_assistant_id == assistant.id  # dono trocou -> cala
```

### `followup_job.rb:14-41` — resolução pelo dono atual

**[rev2, nit 9]** Dono resolvido ANTES de consumir token/`followup_count` — se a cutucada
não vai sair, não se gasta tentativa nem se invalida o token (token órfão é inofensivo:
o próximo `ProgramarFollowupTool` o substitui):

```ruby
return unless attrs['followup_token'] == token
# (linha 17 REMOVIDA: trava atendimento_humano morre — substituída pelo check de dono)
return if conversation.resolved?
return if lead_replied?(conversation)
return if reschedule_if_quiet_hours(conversation, token)

mirror = conversation.assignee_agent_bot
return unless mirror&.captain?               # dono não é IA -> cutucada morre SEM consumir token/count

assistant = mirror.captain_assistant
return unless assistant

# ... branch MAX_FOLLOWUPS (esfriado) e SÓ DEPOIS o consumo:
conversation.update!(custom_attributes: attrs.merge('followup_count' => count + 1, 'followup_token' => nil))
Captain::Conversation::ResponseBuilderJob.perform_now(conversation, assistant, directive: ...)
```

(O branch "esfriado"/`MAX_FOLLOWUPS` também fica APÓS o check de dono — humano assumiu →
o funil não move o card pra "Frio" por conta de cutucadas que nunca sairiam.)

Efeito colateral desejado: transferência IA→IA mid-followup faz a cutucada sair do dono
ATUAL (contexto programado pela IA antiga, voz da nova) — comportamento documentado.

### Specs A3 (`spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb` + debounce/followup)
- job enfileirado com IA-1, dono trocado pra IA-2 antes do perform → nenhuma mensagem,
  nenhum increment de usage.
- dono trocado pra humano antes do perform → silêncio (aceite "IA cala").
- troca de dono ENTRE o LLM e o envio (stub no generate) → mensagem não sai (re-check :51).
- debounce: token válido + dono trocado → silêncio, sem log debounce_fire (aceite 13/§5.3).
- followup: dono = espelho → cutucada sai do assistant do espelho; dono = humano → nada;
  `atendimento_humano` setado → NÃO bloqueia mais.
- **[rev2] rajada de chunks**: resposta com 4 chunks, dono trocado (humano OU outra IA)
  após o 2º chunk → chunks 3-4 NÃO saem; `humanizer_split` loga `sent: 2`.
- **[rev2] followup sem consumo**: dono = humano → token e `followup_count` INTACTOS
  (nada consumido); funil não move pra "Frio".

---

## A4 — Migrar call-sites de `inbox.captain_assistant`

Regra geral de resolução por conversa:
`conversation.assignee_agent_bot&.captain_assistant` (dono atual) com fallback
"participante" (`conversation.messages.where(sender_type: 'Captain::Assistant').order(:created_at).last&.sender`)
quando o evento ocorre após handoff (bot já desatribuído).

1. **`enterprise/app/listeners/captain_listener.rb:4-12`** (memória/FAQ pós-resolução):

```ruby
def conversation_resolved(event)
  conversation = extract_conversation_and_account(event)[0]
  assistant = conversation.assignee_agent_bot&.captain_assistant ||
              conversation.messages.where(sender_type: 'Captain::Assistant').order(:created_at).last&.sender
  return unless assistant
  return unless conversation.inbox.captain_active?   # elegibilidade + quota (re-keyado no A5)

  Captain::Llm::ContactNotesService.new(assistant, conversation).generate_and_update_notes if assistant.config['feature_memory'].present?
  Captain::Llm::ConversationFaqService.new(assistant, conversation).generate_and_deduplicate if assistant.config['feature_faq'].present?
end
```

2. **`enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb`** (7 usos):
   resolvedor por conversa + mantido como rede de segurança do legado (no modelo novo o
   conjunto `inbox.conversations.pending` esvazia — ver A9):

```ruby
def assistant_for(conversation)
  conversation.assignee_agent_bot&.captain_assistant ||
    conversation.messages.where(sender_type: 'Captain::Assistant').order(:created_at).last&.sender ||
    conversation.inbox.captain_assistants.first
end
```

   `Current.executed_by = assistant_for(conversation)` movido pra DENTRO do loop;
   `sender:`/`config['resolution_message']`/`config['handoff_message']` idem (linhas
   26,35,106,115,121,127,132). Conversa sem assistant resolvível → `next`.

3. **Scheduler** `enterprise/app/jobs/enterprise/account/conversations_resolution_scheduler_job.rb:11-20`
   — dedupe por inbox (com has_many enfileiraria N×):

```ruby
Inbox.where(id: CaptainInbox.distinct.select(:inbox_id)).find_each(batch_size: 100) do |inbox|
  next if inbox.email?
  next if inbox.account.captain_auto_resolve_disabled?

  Captain::InboxPendingConversationsResolutionJob.perform_later(inbox)
end
```

4. **`enterprise/app/controllers/enterprise/api/v1/accounts/conversations_controller.rb:5`**
   (endpoint `inbox_assistant`, alimenta copilot):

```ruby
assistant = @conversation.assignee_agent_bot&.captain_assistant || @conversation.inbox.captain_assistants.first
```

5. **`enterprise/lib/enterprise/captain/reply_suggestion_service.rb:21`** (search tool):

```ruby
assistant = conversation&.assignee_agent_bot&.captain_assistant || conversation&.inbox&.captain_assistants&.first
```

6. **`enterprise/app/models/enterprise/message.rb:26-30`** (`captain_pending_conversation?`):
   usa `CaptainInbox.exists?(inbox_id:)` — **sobrevive intacto** ao has_many; vira código
   morto quando pending morrer (A9). Sem mudança.

### Specs A4
- captain_listener: resolve com dono=IA → notes/FAQ do assistant certo; resolve pós-handoff
  (bot desatribuído mas participou) → assistant via último sender; conversa sem IA → no-op.
- auto-resolve: sender/mensagens saem do assistant da conversa (não da inbox);
  scheduler com 2 CaptainInbox da mesma inbox → 1 job só.
- inbox_assistant endpoint: conversa atribuída → assistant do espelho; sem atribuição →
  primeiro elegível; inbox sem IA → null.

---

## A5 — CaptainInbox vira ELEGIBILIDADE (has_one → has_many)

**Zero migration** — o índice único do banco é no par (schema:388) e continua prevenindo
elegibilidade duplicada.

```ruby
# enterprise/app/models/captain_inbox.rb:21
validates :inbox_id, uniqueness: { scope: :captain_assistant_id }   # espelha o índice do par

# enterprise/app/models/enterprise/concerns/inbox.rb:5-8
has_many :captain_inboxes, dependent: :destroy, class_name: 'CaptainInbox'
has_many :captain_assistants, through: :captain_inboxes, class_name: 'Captain::Assistant'
```

- A API de attach (`enterprise/.../captain/inboxes_controller.rb:12-18`) já opera por
  `assistant.captain_inboxes` — passa a aceitar 2ª IA na mesma inbox sem mudança.
- **Gate de sequência**: SÓ flipar depois de A2+A4 zerarem os call-sites singulares.
  Critério mecânico: `grep -rn '\.captain_assistant\b' app enterprise lib | grep -v spec`
  deve retornar vazio (fora `captain_assistant_id`/`captain_assistants`).
- `Enterprise::Inbox#captain_active?` re-keyado junto (ver A9) — senão NoMethodError.
- Dados atuais: a uniqueness antiga era model-only e o índice é do par → **nenhum dado
  existente viola o modelo novo**; nada a migrar.

### Specs A5
- 2 assistants elegíveis na mesma inbox → válido; mesmo par 2× → inválido (validação) e
  RecordNotUnique no raw (índice).
- `inbox.captain_assistants` retorna ambos; destroy do assistant remove a elegibilidade.

---

## A6 — Aposentar RouterService (mantendo guards técnicos)

Decisão: **enxugar a classe in-place** (`enterprise/app/services/captain/behavior/router_service.rb`)
em vez de deletar — caller único (`hook_execution_service.rb:47`) e o log `router_skip`
continuam funcionando, diff mínimo.

```ruby
class Captain::Behavior::RouterService
  def initialize(assistant:, conversation:, message:)
    @assistant = assistant
    @conversation = conversation
    @message = message
    @config = assistant.behavior['router'] || {}
  end

  # Só guards TÉCNICOS sobrevivem (D-6): activity, conteúdo vazio, grupos.
  # Guards de NEGÓCIO morreram com o gate por atribuição: whitelist de fones,
  # skip_labels, skip_agent_bot (bug latente: lia coluna inexistente), e
  # skip_after_human_response (papel assumido por: gate por atribuição + callback
  # de exclusividade reset_agent_bot_when_assignee_present + A2c, que desatribui
  # o espelho quando um humano responde SEM se atribuir).
  def should_respond?
    return false if @message.activity?
    return false if @message.content.blank? && @message.attachments.blank?
    return false if skip_groups?

    true
  end

  private

  # skip_groups continua honrando a config (comportamento preservado p/ grupos WAHA).
  def skip_groups? ... end            # mantém :72-95 intacto (detecção @g.us)
end
```

Deletar: `only_contact_phones_active?`, `contact_phone_allowed?`, `candidate_contact_phones`,
`phone_variations`, `skip_labels?`, `skip_agent_bot?` (NÃO portar — `@conversation.agent_bot_id`
não existe), `skip_after_human_response?`.

**Sem janela de regressão [rev2 — corrigido]**: `skip_after_human_response` era o que
impedia a IA de falar por cima do humano em conversa open (comentário `hook:130-133`
depende dele). A rev1 apontava só "callback + gate" como sucessores — **insuficiente**:
o callback `reset_agent_bot_when_assignee_present` só dispara em SET de assignee; humano
que responde **sem se atribuir** ficaria descoberto (achado 2). O papel passa a ser
coberto por TRÊS peças, todas no MESMO change-set (working tree, deploy atômico):
1. gate exige dono=espelho (A2);
2. `reset_agent_bot_when_assignee_present` limpa o bot quando humano se atribui;
3. **A2c**: outgoing público de humano (sem se atribuir) desatribui o espelho —
   sucessor estrutural transitório, revisar na Fase D;
4. re-check A3 (job em voo + por chunk) cala o que já estava na esteira.

Nota: a whitelist `only_contact_phones` morta aqui é REINJETADA como critério do
**backfill** (§ Riscos) — o script não pode atribuir espelho a conversa que o guard de
negócio hoje silencia.

### Specs A6
- activity → skip+log; mensagem vazia sem anexo → skip; grupo WAHA (`@g.us` nas 3 formas)
  com `skip_groups` → skip; com label antiga `atendimento` em `skip_labels` → **responde**
  (guard morto).
- **[rev2]** última outgoing de humano + `skip_after_human_response` na config: no nível
  do RouterService (unit, dono=espelho forçado) → `should_respond?` true (guard morto);
  no nível INTEGRADO → a IA cala porque o **A2c já desatribuiu o espelho** no momento da
  resposta humana (quem cala é a perda do dono, não o router).

---

## A7 — Guard 403: atribuição manual de IA é admin-only (D-3)

Local: **controller apenas** (`app/controllers/api/v1/accounts/conversations/assignments_controller.rb`).
Como cada caminho flui (verificado):

| Caminho | Passa pelo controller? | `Current.user` | Efeito do guard |
|---|---|---|---|
| UI/API admin | sim | User admin | permite |
| UI/API agente comum | sim | User agent | **403** |
| AgentBot-token (whitelist `access_token_auth_helper.rb:2-6`) | sim | **AgentBot** (`account_user` = nil) | **403** (decisão: bot não atribui IA) |
| Automação (`automation_rules/action_service.rb`) | não (in-process) | nil (`executed_by` = rule) | passa de graça |
| Macro (`macros/execution_service.rb:7`) | não | User executor | passa de graça (não usa o endpoint) |
| Tool copilot/captain (`assign_conversation_service.rb:25-29`) | não | — | passa de graça |
| Futuro `assign_ai_agent` (C5, herda de ActionService) | não | nil/executor | passa de graça |

Por isso o guard NÃO pode morar no `Conversations::AssignmentService` (caller único hoje é o
controller — verificado por grep — mas C5/C7 passarão a usá-lo): macro de agente comum
devolvendo conversa pra IA (D-3) seta `Current.user` = agente e seria bloqueada.

### Forma final

```ruby
def set_agent
  return render_captain_assignment_forbidden if forbidden_captain_assignment?

  resource = Conversations::AssignmentService.new(
    conversation: @conversation,
    assignee_id: params[:assignee_id],
    assignee_type: params[:assignee_type]
  ).perform
  render_agent(resource)
end

def forbidden_captain_assignment?
  return false unless agent_bot_assignment?
  return false unless requested_agent_bot&.captain?

  !admin_user?
end

def requested_agent_bot
  @requested_agent_bot ||= AgentBot.accessible_to(Current.account).find_by(id: params[:assignee_id])
end

# Safe navigation OBRIGATÓRIA: AgentBot-token chega aqui com Current.account_user = nil
# (whitelist BOT_ACCESSIBLE_ENDPOINTS) — guard ingênuo daria NoMethodError/500.
def admin_user?
  Current.user.is_a?(User) && Current.account_user&.administrator?
end

def render_captain_assignment_forbidden
  render json: { error: I18n.t('conversations.captain.assignment_forbidden') }, status: :forbidden
end
```

(403 explícito — Pundit renderizaria 401; precedente `conversations_controller.rb:244`.)

i18n (ambos locales, sob `conversations.captain`):
- en: `assignment_forbidden: 'Only administrators can assign AI agents to conversations.'`
- pt_BR: `assignment_forbidden: 'Somente administradores podem atribuir agentes IA a conversas.'`

Contrato preservado: bot inexistente/User inexistente continuam com o comportamento atual
(`render json: nil` / desatribuição) — endurecer isso é fora de escopo da Fase A (anotado).

### Specs A7 (`spec/controllers/api/v1/accounts/conversations/assignments_controller_spec.rb` — existe)
- admin atribui bot captain → 200 + payload `agent_bot_slim` (aceite 2).
- agente comum atribui bot captain → **403** + corpo com erro i18n (aceite 15/§5.3).
- agente comum atribui bot **webhook** → comportamento atual preservado (sem 403).
- AgentBot-token atribui bot captain → 403 (sem 500 — regressão do `account_user` nil).
- service-level: `Conversations::AssignmentService` SEM `Current.user` atribui captain
  normalmente (documenta que automação/macro/tool passam).
- paridade i18n en↔pt_BR das chaves novas.

---

## A8 — Cota zerada: handoff em PT, re-keyado pra conversa

`hook_execution_service.rb:142-154` — problemas verificados: (1) EN hardcoded;
(2) `return unless conversation.pending?` → no modelo novo (sem pending) viraria no-op
silencioso; (3) sem o guard de pending, a mensagem repetiria a CADA incoming (loop de spam),
pois o gate continuaria batendo em `perform_handoff`.

### Forma final

```ruby
def perform_handoff
  assistant = assigned_assistant
  return if assistant.blank?   # re-keyado: só age quando uma IA é dona da conversa

  Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{conversation.id}")
  I18n.with_locale(conversation.account.locale) do
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account.id,
      inbox_id: conversation.inbox.id,
      sender: assistant,    # bolha com identidade da IA (antes saía sem sender)
      content: assistant.config['handoff_message'].presence || I18n.t('conversations.captain.handoff')
    )
  end
  # IA solta a conversa: o gate para de bater aqui (sem spam) e a conversa fica
  # sem dono -> visível como órfã (vigia D-12 / tab condicional na Fase C).
  conversation.update!(assignee_agent_bot_id: nil)
  conversation.bot_handoff!
  send_out_of_office_message_after_handoff
end
```

- PT de graça: `conversations.captain.handoff` JÁ existe nos dois locales
  (`pt_BR.yml:231` "Transferindo para que outro agente dê assistência." / `en.yml:245`) —
  o locale da conta resolve. Honra `config['handoff_message']` (paridade com
  `response_builder_job.rb:147-151`).
- Conta clássica/legado (conversa pending sem atribuição): `assigned_assistant` blank →
  no-op + `bot_handoff!` não dispara. Aceitável: sem atribuição não há "IA dona" pra
  transferir; o caso legado real (Tozi) migra junto com a virada.
- **[rev2] Interação com A2d**: atribuir o espelho a conversa com incoming pendente e
  **cota já zerada** → `AssignmentKickJob` → gate → `perform_handoff` imediato (mensagem
  PT + espelho solto). Comportamento desejado: quem atribui IA sem cota vê o handoff na
  hora, não um silêncio.
- **[rev2] Nota de produto (achado 6)**: conta em modo Clássico com CaptainInbox e SEM
  triagem fica com canal silencioso (greeting suprimido por elegibilidade + gate sem
  dono). O gate NÃO muda na Fase A — registrado como NOTA DE PRODUTO em openQuestions
  (decisão de go-live/Fase D).

### Specs A8
- cota zerada + conversa atribuída à IA → mensagem no locale pt_BR da conta, sender =
  assistant, espelho desatribuído, `bot_handoff!` disparado.
- segundo incoming após o handoff → NENHUMA nova mensagem (sem spam).
- `config['handoff_message']` presente → usa o custom.
- cota zerada + conversa de humano/sem dono → no-op.
- **[rev2]** atribuir espelho com cota zerada + incoming pendente → handoff imediato via
  kick (A2d), uma única mensagem.

---

## A9 — Destino de `active_bot?` / `pending_status_enabled` / auto-resolve

Decisões (consumidores verificados):

1. **`Enterprise::Inbox#captain_active?`** (`enterprise/inbox.rb:14-16`) re-keyado pra
   ELEGIBILIDADE no mesmo change do A5:

```ruby
def captain_active?
  captain_assistants.exists? && more_responses?
end
```

   Mantém `active_bot? = super || captain_active?` funcionando para os 4 consumidores:
   `conversation.rb:345,350` (pending na criação), `message.rb:470` (reopen→pending),
   `reporting_event_listener.rb:191` e `bot_metrics_builder.rb:22` (métricas "inbox tem
   bot" — semântica preservada; refinar por atribuição é tema de relatórios, fora da Fase A).

2. **Pending-de-bot morre OPERACIONALMENTE, não por código**: todo o limbo já é gated por
   `inbox.pending_status_enabled` (coluna boolean **default false** — schema:982; validação
   `pending_status_allowed_by_inbox` em `conversation.rb:332-338`, fork). Modelo novo =
   `pending_status_enabled: false` na inbox da virada → `determine_conversation_status`/
   `reopen_resolved_conversation` nunca mais criam pending; conversa nasce open e a triagem
   atribui. O código permanece para o modo Clássico (D-13). **Adicionar ao runbook da
   virada (§6 do plano): desligar `pending_status_enabled` na inbox 91.**

3. **`Enterprise::Message#mark_pending_conversation_as_open_for_human_response`**: intacto
   (keyado em `CaptainInbox.exists?`, sobrevive ao has_many); vira código morto natural
   quando não houver mais pendings.

4. **Auto-resolve** (`InboxPendingConversationsResolutionJob`): mantido como rede de
   segurança do legado, re-keyado por conversa (A4). No modelo novo `conversations.pending`
   esvazia → no-op. Aposentadoria definitiva (remover do scheduler) fica pra depois da
   virada completa — fora da Fase A.
   **[rev2, achado 7 — desvio CONSCIENTE de D-6, documentado]**: o job continua
   inbox-keyed no fallback (`inbox.captain_assistants.first`) e fala/age em conversa que
   não é dele (sem dono). Aceito até a aposentadoria: é rede de segurança de legado
   pending, conjunto que esvazia no modelo novo. NÃO "corrigir" antes — mexer aqui é
   custo sem benefício.

### Specs A9
- inbox com IA elegível + `pending_status_enabled: false` → conversa nova nasce **open**
  (sem pending) e reopen pós-resolve vai pra **open**.
- inbox clássica (`pending_status_enabled: true`) → comportamento atual intacto.
- `captain_active?` com 2 elegíveis → true; sem elegível → false; quota zerada → false.

---

## Ordem de implementação (rev2)

```
A1 ✅ IMPLEMENTADO E NO AR (migration aplicada, 12 espelhos, specs 148/0)
 │
 ├─────────────── paralelo ────────────────────────┐
 │                                                 │
 NÚCLEO ATÔMICO (um change-set, deploy único):     A3 (re-check jobs + POR CHUNK
 A2 + A6 + A8 + A2c                                    + followup reordenado) — só dep. A1
 (hook service + router slim + quota/handoff       A7 (guard 403)            — só dep. A1
  + sucessor do skip_after_human_response)         A2b-EXPANDIDA (4 caminhos
 → A2d (gatilho pós-atribuição — usa o                + invariante)          — independente
   entry re-keyado do A2)                          A2e (resolve limpa espelho) — independente
 → A4 (call-sites restantes)                           (spec conjunto com A4)
 → A5 + A9.1 (flip has_many + captain_active?)   ← SÓ após grep singular zerar
 │
 └→ backfill (critério expandido, § Riscos) + specs completas + aceite (§ abaixo)
```

- **A1 feito**: enum `captain?` e lookup espelho↔assistant já no ar — tudo abaixo assume.
- **Núcleo atômico [rev2 — A2c entrou]**: A2/A6/A8 mudam o mesmo arquivo; a remoção do
  `skip_after_human_response` (A6) só é segura com o gate por atribuição (A2) **e o A2c**
  (humano sem se atribuir) no MESMO deploy — sem A2c há janela de regressão real
  (achado 2). A2d logo após A2 (reusa o entry re-keyado). A4 antes de A5; A5 por último
  no núcleo (gate mecânico: grep de `.captain_assistant` singular vazio).
- **Paralelizáveis**: A3, A7, A2b-expandida e A2e não tocam o hook service — podem correr
  em worktrees separados. A2e tem spec conjunto com A4 (fallback "participante") —
  integrar na rodada final.
- **Specs**: cada bloco entrega as suas; rodada final integrada
  (`bundle exec rspec spec/enterprise/services/enterprise/message_templates spec/enterprise/jobs/captain spec/controllers/api/v1/accounts/conversations/assignments_controller_spec.rb spec/models/agent_bot_spec.rb spec/listeners/agent_bot_listener_spec.rb spec/services/auto_assignment spec/jobs/inboxes/bulk_auto_assignment_job_spec.rb spec/models/conversation_spec.rb spec/models/message_spec.rb`).

### Mapa aceite da Fase A → cobertura

| Aceite | Onde é garantido |
|---|---|
| 2 assistants elegíveis na mesma inbox | A5 (has_many; índice do par) |
| conversa sem atribuição → IA muda | A2 gate (spec hook) |
| atribuir IA-1 (admin) → responde | A2 + A7 (controller 200) |
| atribuir IA-2 → IA-2 responde, IA-1 cala | A2 (assistant da conversa) + A3 (job em voo da IA-1 cala) |
| atribuir humano → IA cala | callback `conversation.rb:318-322` (existente) + A2 gate + A3 |
| debounce em voo após troca → descartado | A3 (re-check no RBJ; token NÃO basta) |
| agente comum atribui IA via API → 403 | A7 |
| **[rev2]** 1º turno: triagem assíncrona atribui APÓS o incoming → IA responde no 1º turno (E2E #2) | A2d (gatilho pós-atribuição) |
| **[rev2]** humano responde SEM se atribuir → IA cala | A2c (outgoing de humano desatribui espelho) |
| **[rev2]** team-change da triagem não rouba conversa nem quebra exclusividade | A2b-expandida caminho (c) + spec de invariante |
| **[rev2]** rajada de chunks para quando o dono troca no meio | A3 (re-check por chunk) |
| **[rev2]** resolver + lead volta → reabre SEM dono → triagem re-atribui (E2E #11) | A2e (resolve limpa espelho) |

---

## Riscos e mitigação

| Risco | Mitigação |
|---|---|
| **Deploy = virada de comportamento da IA sem flag** (gate por atribuição é incondicional; D-13 flagueia o gate universal de RESPOSTA, não o gate da IA): conversa de inbox captain sem atribuição fica MUDA até a triagem atribuir | Deploy só em homolog; antes de validar: `rake captain:sync_mirrors` (✅ feito) + **backfill com critério COMPLETO [rev2, achado 5]** via `Conversations::AssignmentService` (nunca `update_columns` — risco E2): conversas pending/open de inbox com CaptainInbox, sem assignee humano, **EXCLUINDO** (1) `custom_attributes['atendimento_humano']` truthy, (2) conversas com `skip_labels` do assistant, (3) conversas cuja última outgoing pública é de User (humano já atendia — A2c desatribuiria no minuto seguinte), e **respeitando** a whitelist `only_contact_phones` quando configurada (guards de negócio que o A6 mata não podem ser ressuscitados às avessas pelo script). **Escolha do espelho com 2+ elegíveis**: NÃO atribuir automaticamente — logar a conversa e decidir manualmente (na prática da virada há 1 elegível por inbox). **Runbook documenta**: snoozed (reabre com dono mantido; se reabrir SEM dono → muda até triagem) e resolved que reabre pós-backfill (nasce sem dono → triagem re-atribui, A2e). Roteiro §6 do plano cobre a virada real |
| Jobs em voo no deploy carregam assistant antigo (GlobalID) | A3 compara o assistant DO ARGUMENTO com o dono atual — IA errada cala; janela calma no restart |
| Troca de dono mid-debounce não invalida token Redis | A3: re-check é a autoridade; early-return no DebouncedResponseJob evita log falso |
| has_one→has_many flip silencioso (`respond_to?` em `hook:165` desligaria o captain sem erro) | A2 remove o guard `respond_to?`; gate mecânico de grep antes do A5; specs do gate quebram se a resolução sumir |
| Auto-assignment rouba conversa da IA — **4 caminhos** [rev2]: legado round-robin (DEFAULT), bulk V2, team-change da triagem, scope V2 | A2b-EXPANDIDA obrigatória antes do aceite (4 guards + spec de invariante) |
| **[rev2]** Team-change quebra invariante de exclusividade (`reset_agent_bot` é before_validation, roda ANTES do `ensure_assignee_is_from_team` before_save → humano E bot persistidos juntos) | A2b-expandida caminho (c): não auto-atribuir humano com espelho presente; spec de regressão da invariante nos 4 fluxos |
| **[rev2]** Humano que responde SEM se atribuir não cala a IA (`skip_after_human_response` morre; callback só dispara em SET de assignee) | A2c no MESMO change-set do A6 (sucessor estrutural transitório); revisar na Fase D |
| **[rev2]** Rajada de chunks do humanizer continua após troca de dono (sleep 1,5–7s/chunk; re-check único não cobre) | A3: re-check por chunk pós-sleep; TOCTOU residual de ms aceito |
| **[rev2]** 1º turno mudo: triagem assíncrona atribui DEPOIS do hook do incoming | A2d: gatilho pós-atribuição re-enfileira o pipeline (mesmo entry, debounce respeitado) |
| **[rev2]** Reopen pós-resolve manteria dono-espelho (contradiz §2/teste 11) | A2e: resolve limpa só o espelho; notes/FAQ caem no fallback "participante" (A4) |
| **[rev2]** Conta Clássica + CaptainInbox SEM triagem = canal 100% silencioso (greeting suprimido por elegibilidade + gate sem dono) | NÃO resolvido unilateralmente — NOTA DE PRODUTO em openQuestions (go-live/Fase D); rollout §6 evita a configuração (virada liga triagem+flag juntas) |
| Espelho órfão / dessincronizado | FK nullify + unique parcial + sync idempotente + `dependent: :destroy` no assistant + rake re-sincroniza + specs |
| Espelho mutado/deletado via API admin | A1: 422 em update/destroy/avatar/reset_token de bot captain; criação com bot_type captain rejeitada |
| Espelho dispara webhook se alguém setar outgoing_url | A1: validação `absence` + guard `webhook?` no listener (dupla defesa) |
| Cota zerada agora desatribui a IA → conversa órfã sem aviso a admin até C10/D-12 | Aceito na Fase A (monitorar — §7 do plano); mensagem PT + bot_handoff! tornam visível na fila |
| `CaptainInbox` dados atuais × novo modelo | Sem migração: uniqueness antiga era model-only; índice do par já existia |
| AccessToken automático por espelho (AccessTokenable) | Aceito e documentado; token nunca exposto; hardening opcional pós-fase |
| Greeting/OOO dispararia antes da triagem se supressão fosse por atribuição | Resolvido: `captain_handling_conversation?` por elegibilidade OU atribuição |
| Followup/notes/FAQ com IA "errada" após transferência | Resolução pelo dono atual (A3) / participante (A4) — comportamento documentado nos specs |

## Divergências técnicas resolvidas (registro)

1. A1: coluna `captain_assistant_id` escolhida sobre `bot_config['assistant_id']` (FK,
   índice único parcial, lookup reverso; bot_config sem consumidor backend).
2. A2: supressão greeting/OOO/email_collect mantida por ELEGIBILIDADE (não atribuição) —
   evita greeting na janela criação→triagem.
3. A2: `schedule_captain_response` recebia assistant re-derivado da inbox (`:110`) — passa
   a receber o resolvido pelo gate.
4. A2b (tarefa nova): auto-assignment excluído de conversas com `assignee_agent_bot_id`.
5. A4: scheduler do auto-resolve deduplicado por inbox (has_many enfileiraria N×).
6. A5: uniqueness composta substitui a remoção pura (espelha o índice do par).
7. A6: RouterService enxugado in-place (não deletado) — caller e log preservados; bug
   `agent_bot_id` não portado; `skip_groups` continua config-gated.
8. A7: guard no controller (não service/policy) + 403 explícito (Pundit renderia 401) +
   safe navigation para AgentBot-token (`account_user` nil); decisão: bot-token também 403.
9. A8: além do PT, condição re-keyada pra atribuição + desatribuição do espelho pós-handoff
   (anti-spam e anti-no-op) + sender = assistant.
10. A9: pending-de-bot morre por configuração (`pending_status_enabled=false` na inbox da
    virada), não por remoção de código — preserva modo Clássico (D-13).
11. Trava `atendimento_humano` removida nos 2 pontos (hook + followup) — coerência.
12. `captain_can_respond?` do fork (aceita open) preservado — specs não copiam upstream.

**[rev2 — pós-crítica]**

13. A2b expandida pra 4 caminhos (legado DEFAULT, bulk V2, team-change, scope V2) +
    invariante de exclusividade: causa-raiz do caminho (c) é ordem de callbacks
    (`before_validation` reset × `before_save` ensure_assignee_is_from_team).
14. A2c: sucessor estrutural TRANSITÓRIO do `skip_after_human_response`, keyado em
    `human_response?` (cobre echo nativo; exclui automação/campanha/privada/template
    bootstrap) — revisar na Fase D (redundante no modo Atribuição).
15. A2d: gatilho pós-atribuição reusa o ENTRY do hook (`HookExecutionService` com a
    última incoming) em vez de chamar o ResponseBuilderJob direto — preserva router
    técnico, debounce, attachment-wait e logs; greeting não duplica (supressão por
    elegibilidade + guards dos templates).
16. A2e: resolve limpa SÓ o espelho captain (webhook bots e assignee humano preservam a
    regra atual); notes/FAQ pós-resolve caem no fallback "participante" do A4.
17. A3: re-check por chunk posicionado APÓS o sleep (janela TOCTOU residual de ms, não
    de segundos); `humanizer_split` loga `sent` além de `chunks`.
18. FollowupJob: dono resolvido ANTES de consumir token/`followup_count` (nit) — cutucada
    que não sai não gasta tentativa nem move o funil pra "Frio".
19. `copilot_trigger` re-keyado (A2) passa a exigir conversa atribuída à IA — registro;
    impacto ~zero (trigger é mensagem privada num fluxo onde a IA já participa).
20. Auto-resolve pending: desvio CONSCIENTE de D-6 (inbox-keyed, fallback `.first`, fala
    sem ser dono) mantido até a aposentadoria — A9.4.
21. Backfill com critério expandido (atendimento_humano, skip_labels, última outgoing de
    User, whitelist de fones, 2+ elegíveis → manual) — § Riscos.

## openQuestions

1. **NOTA DE PRODUTO (rev2, achado 6 — decisão do Walisson; NÃO bloqueia homolog):**
   conta em modo Clássico (D-13 default) com CaptainInbox e SEM triagem = canal 100%
   silencioso — greeting suprimido por elegibilidade (comportamento **idêntico ao de
   hoje**, portanto não é regressão em si) e IA muda pelo gate sem atribuição. Em homolog
   ok; é exatamente a configuração que o rollout (§6) evita — a virada liga triagem+flag
   juntas. **Opções para o go-live/Fase D** (não resolver unilateralmente na Fase A):
   (a) condicionar a supressão de greeting OU o gate da IA ao modo da conta quando o
   toggle D-7 existir; (b) runbook proibindo elegibilidade (CaptainInbox) sem triagem
   ativa. Decidir antes do go-live.
2. **A2c é transitório:** quando o gate universal da Fase D obrigar atribuição antes de
   responder, o hook fica redundante no modo Atribuição — revisar na Fase D (remover ou
   condicionar ao modo Clássico).
3. Fora isso, nenhuma contradição com D-1..D-13. Pontos que tangenciam produto foram
   resolvidos dentro do que as decisões já estabelecem e estão registrados acima
   (supressão de greeting por elegibilidade; cota zerada → órfã; gate da IA sem flag —
   leitura literal de D-13, que lista o que o toggle cobre e não inclui o gate da IA).
