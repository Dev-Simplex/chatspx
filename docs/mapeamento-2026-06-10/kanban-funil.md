# Mapeamento — Kanban / Funil (SPX fork Chatwoot)

> Área: kanban-funil · Branch: paulao · Data: 2026-06-10
> Tudo baseado em leitura do código local. Referências file:linha.

---

## 1. Modelos

### Funnel — `app/models/funnel.rb`
- `belongs_to :account` (linha 18), `belongs_to :team, optional: true` (19), `has_many :funnel_stages` e `:funnel_items` com `dependent: :destroy` (20-21).
- Campos (schema embutido, linhas 5-15): `name`, `color`, `position`, `account_id`, `team_id` (opcional), **`inbox_ids :jsonb default([])`**.
- **Escopo do funil = ACCOUNT**, com restrição opcional por inbox: scope `for_inbox` (linha 30) — `inbox_ids = '[]'` significa "cobre todas as inboxes"; senão usa contenção JSONB (`@>`). `allows_inbox?` (36-40) e `allowed_inboxes` (42-47) seguem a mesma regra.
- `normalize_inbox_ids` (51-54) compacta e converte pra inteiro no `before_save`.

### FunnelStage — `app/models/funnel_stage.rb`
- `belongs_to :funnel`, `has_many :funnel_items, dependent: :destroy` (17-18).
- **`automation_type :string`** (linha 8) — chave estável da automação. **Único por funil** quando presente (validação linha 23: `uniqueness: { scope: :funnel_id, allow_nil: true }`).
- Scopes: `ordered` (position, created_at), `with_automation(type)`, `with_open_automation`, `with_resolved_automation` (25-28).
- Valores em uso: genéricos `open`/`resolved` (funis default) e os 7 do funil Tozi: `novo_lead, aguardando_1a, em_conversa, em_silencio, agendado, qualificado, frio`.

### FunnelItem (o "card") — `app/models/funnel_item.rb`
- `belongs_to :conversation` / `:funnel` / `:funnel_stage` / `:moved_by (User, optional)` (19-22).
- **UNIQUE `(conversation_id, funnel_id)`** (comentário linha 16; índice `index_funnel_items_unique` em `db/schema.rb:891`) → **1 card por conversa POR FUNIL**. A mesma conversa pode ter cards em N funis diferentes; nunca 2 cards no mesmo funil.
- **`moved_at`** setado automaticamente em toda mudança de estágio: `before_save :set_moved_at, if: :will_save_change_to_funnel_stage_id?` (linha 29, método 36-38). É o campo certo pra "parado há X dias".
- FKs em `db/schema.rb:1496-1499`: `funnel_items → conversations` com **`on_delete: :cascade`** (apagar conversa apaga o card), `→ funnel_stages`, `→ funnels`, `→ users (moved_by_id)`.
- Scopes `by_funnel(id)` / `by_stage(id)` (31-32).

**Relação card↔conversa:** o card é uma junção `conversation × funnel` com ponteiro pro estágio. **Não há card por contato** — consequência direta: o bug das fichas/conversas duplicadas (9º dígito) gera **cards duplicados** no funil. O fork mitiga só na renderização (ver §4, `deduplicate_by_contact_phone`).

---

## 2. Automação genérica (OSS, callbacks de Conversation)

`app/models/conversation.rb`:
- **`after_create_commit :add_to_appropriate_funnel`** (linha 161; método 420-441): toda conversa nova entra em funil. Usa `Kanban::FunnelLookupService` (team funnel + default funnel) e coloca no estágio `open`/`resolved` conforme status, senão **primeiro estágio ordenado** (linha 429). `find_or_create_by`, rescue-wrapped.
- **`after_update_commit :move_to_automated_stage, if: :saved_change_to_status?`** (linha 157; método 443-448) → `Kanban::MoveConversationToAutomatedStageService`.
- **`after_update_commit :move_to_team_funnel, if: :saved_change_to_team_id?`** (linha 158; método 450-455) → `Kanban::MoveConversationToTeamFunnelService`.

### Kanban::FunnelLookupService — `app/services/kanban/funnel_lookup_service.rb`
- Retorna no máximo 2 funis: o do team (se `team_id`) e o default (`team_id: nil`), ambos via `.for_inbox(inbox_id).first` (linhas 10-19). **`.first` sem order explícito → ordena por id** — se a conta tem "Geral" (inbox_ids=[]) e "Pré-Venda Tozi" (inbox_ids=[91]), ambos `team_id: nil`, o escolhido é o de **menor id** (tipicamente o "Geral"). Ou seja: as automações genéricas open/resolved atuam num único funil default por conversa.

### Kanban::MoveConversationToAutomatedStageService — `app/services/kanban/move_conversation_to_automated_stage_service.rb`
- Mapeia status → automation_type **apenas `open` e `resolved`** (`resolve_automation_type`, linhas 32-37). Para cada funil do lookup, acha stage `with_automation` e move via `find_or_initialize_by` + `moved_by_id = Current.user&.id` (14-23). O funil Tozi não tem stages open/resolved, então este service nunca o toca (o `filter_map` pula).

### Kanban::MoveConversationToTeamFunnelService — `app/services/kanban/move_conversation_to_team_funnel_service.rb`
- Quando muda o time: re-coloca a conversa no(s) funil(is) do lookup, no estágio open/resolved ou **primeiro estágio** como fallback (linhas 16-17).

### Backfill — `app/services/kanban/funnel_items_backfill_service.rb` + job + trigger no controller
- `Kanban::FunnelItemsBackfillService`: pega até **1000** (`DEFAULT_MAX_ITEMS`, linha 4) conversas **open/resolved** (linha 50) das inboxes/team do funil **sem FunnelItem** e insere via `insert_all` com `unique_by: :index_funnel_items_unique` (linha 42). Estágio destino: `open`→stage 'open' **`|| default_stage`**, `resolved`→stage 'resolved' **`|| default_stage`** (60-69), onde `default_stage = stages.first` (linha 19).
- **Disparo automático:** `Api::V1::Accounts::FunnelItemsController#index` chama `enqueue_backfill_funnel_items` em TODO GET (linhas 13, 148-156), com throttle de 10 min por funil via cache → `Kanban::BackfillFunnelItemsJob` (`app/jobs/kanban/backfill_funnel_items_job.rb`, fila :low).
- ⚠️ **Efeito colateral crítico no funil Tozi:** ele não tem stages open/resolved, então `default_stage` = **"Novo Lead"**. Toda vez que alguém abre o Kanban do funil Pré-Venda Tozi, o backfill despeja TODAS as conversas open/resolved da inbox 91 sem card (atendimento humano normal, disparos, tudo) em "Novo Lead", 1000 por leva.
- Migration `db/migrate/20260203180000_remove_funnel_items_in_resolved_stage.rb` apagou items em stages 'resolved' com o comentário "o backfill antigo não roda mais para resolved" — **comentário desatualizado**: o service atual ainda inclui `:resolved` (linha 50).

### Funis default — `app/services/kanban/{ensure_default_funnels,create_default_funnel,create_funnel_for_team}_service.rb`
- `EnsureDefaultFunnelsService` roda em todo `FunnelsController#index` (controller linha 9): garante 1 funil default da conta + 1 por team.
- `CreateDefaultFunnelService` / `CreateFunnelForTeamService`: 3 estágios — Aberto (`automation_type: 'open'`), Em andamento (`nil`), Resolvido (`'resolved'`).

---

## 3. State machine Tozi (Bloco 3) — quem move o quê

### Spx::Tozi::FunnelPlacementService — `app/services/spx/tozi/funnel_placement_service.rb`
- `PREVENDA_AUTOMATION_TYPES = %w[novo_lead aguardando_1a em_conversa em_silencio agendado qualificado frio]` (linha 16).
- **`self.move(conversation:, to:)`** (22-24): API de movimentação keyed por automation_type (não precisa de IDs de stage). Idempotente; no-op se a inbox não é coberta por um funil de pré-venda.
- **`self.current_type(conversation)`** (27-32): automation_type atual da conversa no funil de pré-venda, ou nil.
- **`self.prevenda_funnel(conversation)`** (35-41): acha o funil da conta que cobre a inbox E tem algum stage com automation_type de pré-venda (filtra fora os funis genéricos open/resolved).
- `perform` (48-64): `find_or_initialize_by(conversation_id, funnel_id)` + seta stage; no-op se já está lá; rescue-wrapped → nil. **Não seta `moved_by_id`** (movimentos de automação ficam com moved_by nil — distinguível de movimento humano).

### Spx::Tozi::FunnelAutomationListener — `app/listeners/spx/tozi/funnel_automation_listener.rb`
Registrado **globalmente** em `app/dispatchers/async_dispatcher.rb:14` (roda pra toda conta da instância; cada handler é rescue-wrapped pra não derrubar o EventDispatcherJob — comentário linhas 5-7).
- **`message_created`** (24-37): incoming não-activity; se `current_type` ∈ `WAITING_STAGES = %w[novo_lead aguardando_1a em_silencio frio]` (linha 18) → `ReactivationCadenceService.cancel_pending` + **move 'em_conversa'**.
- **`assignee_changed`** (42-52): `assignee_id` presente E `assignee_agent_bot_id` blank (= humano, não bot; coluna real em `db/schema.rb:726`); se `current_type` ∈ `PRE_QUALIFIED_STAGES = %w[novo_lead aguardando_1a em_conversa em_silencio agendado frio]` (linha 20) → cancela cadência + **move 'qualificado'**. Guard intencional: não re-afirma em reatribuição se já está qualificado, não sobrescreve card movido à mão pra fora desses estágios.

### Tools do Captain (enterprise/) — a IA já move o funil hoje
- **`enterprise/lib/captain/tools/programar_followup_tool.rb`**: linha 25 → `move(to: 'em_silencio')` ao programar cutucada; agenda `Captain::Conversation::FollowupJob` com token (linha 26).
- **`enterprise/lib/captain/tools/salvar_info_lead_tool.rb`**: `move_funnel_by_status` (34-43) — status `qualificado|convertido` → cancela cadência + move **'qualificado'**; `esfriado|perdido` → move **'frio'** + **inicia** `ReactivationCadenceService`.
- **`enterprise/app/jobs/captain/conversation/followup_job.rb`**: `MAX_FOLLOWUPS = 4` (linha 4); ao esgotar (24-34) marca `tozi_status_lead='esfriado'`, move **'frio'** (linha 32) e dispara a cadência HSM (linha 33). Quiet hours 21h-8h America/Cuiaba (58-66). Guards: token, `atendimento_humano`, resolved, lead respondeu.

### Entrada do lead — `app/services/meta/lead_ads/create_conversation_service.rb`
- `perform` chama `place_in_funnel(conversation)` (linha 28) → `FunnelPlacementService.new(automation_type: 'novo_lead')` (50-54). Único produtor de 'novo_lead' intencional.
- ⚠️ **`Spx::Tozi::DisparoLeadJob` NÃO coloca no funil** (grep por funnel em `app/jobs/spx/tozi/disparo_lead_job.rb`: zero matches). Leads de disparo entram em funil só por: (a) `add_to_appropriate_funnel` no funil default "Geral"; (b) backfill automático do funil Tozi → caem em "Novo Lead" indistintos.

### Cadência HSM fora da janela (Bloco 4) — `app/services/spx/tozi/reactivation_cadence_service.rb`
- `CADENCE` (20-27): HSM em **1d / 3d / 7d** (`tozi_lead_followup`, `tozi_lead_reativacao` ×2), via `ScheduledMessages::CreateService` com `template_params` (81-98). Só **Cloud API** (`cloud_api_inbox?`, 67-70; WAHA = no-op). Idempotente (`cadence_already_scheduled?`). `system_user` = primeiro administrador da conta (108-110).
- **`self.cancel_pending(conversation)`** (32-41): cancela `ScheduledMessage.pending` com `template_params` não-nulo via `update_all`.
- **Gate de schema:** tudo é no-op se a coluna `template_params` não existir (linhas 33, 51, 73). A migration é `db/migrate/20260529120000_add_template_params_to_scheduled_messages.rb`; o `db/schema.rb` local (linhas 1310-1330) **não mostra a coluna** — schema.rb desatualizado em relação à migration; em runtime depende de `db:migrate` ter rodado no ambiente.

### Tabela-resumo das transições automáticas (Bloco 3)

| Evento | De (guard) | Para | Onde |
|---|---|---|---|
| Conversa de lead Meta criada | — | novo_lead | meta/lead_ads/create_conversation_service.rb:28,51 |
| Incoming do lead | novo_lead, aguardando_1a, em_silencio, frio | em_conversa (+cancela HSM) | funnel_automation_listener.rb:24-37 |
| Atribuição a humano | qualquer pré-venda exceto qualificado | qualificado (+cancela HSM) | funnel_automation_listener.rb:42-52 |
| Agente programa follow-up | (sem guard de estágio) | em_silencio | programar_followup_tool.rb:25 |
| Follow-up atinge MAX (4) | (sem guard de estágio) | frio (+inicia HSM) | followup_job.rb:32-33 |
| salvar_info_lead status=qualificado/convertido | (sem guard) | qualificado | salvar_info_lead_tool.rb:36-38 |
| salvar_info_lead status=esfriado/perdido | (sem guard) | frio (+inicia HSM) | salvar_info_lead_tool.rb:39-41 |

**Estágios SEM trigger automático: `agendado` e `aguardando_1a`.** Nenhuma chamada `move(to: 'agendado')` ou `move(to: 'aguardando_1a')` existe no código (grep). Só movimento humano (UI/API) os alimenta.

---

## 4. API HTTP (o que uma IA externa usaria)

Rotas em `config/routes.rb:130-140` (escopo `/api/v1/accounts/:account_id/`):
- `resources :funnels` (index/show/create/update/destroy) + `POST :id/reorder_stages`
- `resources :funnel_stages` aninhado (CRUD; `funnel_stage_params` permite `name, position, color, automation_type` — `funnel_stages_controller.rb:62`)
- `resources :funnel_items` aninhado (index/create/update/destroy) + `POST funnel_items/bulk_move`

### FunnelItemsController — `app/controllers/api/v1/accounts/funnel_items_controller.rb`
- **`index`** (10-31): `policy_scope` + includes; **enfileira backfill** (§2); modo cursor opcional (`params[:mode]=cursor` + feature flag `kanban_cursor_loading`, linhas 109-111; flag declarada em `config/features.yml:231`) via `Kanban::FunnelItemsQueryService`; senão `legacy_scope` paginado (124-146). Ordenação: `conversations.last_activity_at DESC` (query service linha 19). Filtros suportados: `stage_id`, `exclude_automation_type`, paginação. **Não há filtro por `moved_at`**.
- **Dedup visual por telefone BR** (`deduplicate_by_contact_phone`, 158-190): agrupa por stage+telefone normalizado (insere o 9º dígito em números 55+12d — linha 188!), mantém o card de atividade mais recente. **Só na renderização** — o banco mantém os duplicados.
- **`create`** (33-41): aceita `conversation_id` **ou `display_id`** (lookup 90-99) + `funnel_stage_id` → `FunnelItems::MoveService`.
- **`update`** (43-52): muda o estágio do item (drag-and-drop usa este) → `FunnelItems::MoveService`.
- **`bulk_move`** (59-78): `conversation_ids[]` + `stage_id` → MoveService em loop.

### FunnelItems::MoveService — `app/services/funnel_items/move_service.rb`
- `find_or_initialize_by(conversation, funnel)` + seta stage/moved_by/moved_at (13-25).
- ⚠️ **Side effect** `update_conversation_status` (34-44): se o stage destino tem `automation_type` **'resolved'** → **resolve a conversa**; **'open'** → reabre. Ou seja, arrastar card pra coluna "Resolvido" do funil Geral resolve a conversa de verdade (e com bot na inbox, a próxima resposta do cliente cai no limbo `pending` conhecido). No funil Tozi não há esses types, então drag lá não mexe em status.

### Resposta JSON do card — `app/views/api/v1/models/_funnel_item.json.jbuilder`
- `id, conversation_id, funnel_id, funnel_stage_id, moved_at, moved_by_id, created_at, updated_at` + conversa embutida (`display_id, status, contact_id, inbox_id, assignee_id, last_activity_at`, contato com `phone_number`, last_message). `moved_at` **é exposto** na leitura — dá pra calcular "parado há X dias" client-side, mas não dá pra filtrar server-side.

### Permissões — `app/policies/funnel_policy.rb`, `funnel_item_policy.rb`, `funnel_stage_policy.rb`
- `FunnelPolicy`: index/create = qualquer `agent?` ou `administrator?` (4-6, 21-23); funis de team só pra membros (Scope, 44-67).
- `FunnelItemPolicy`: index/create/update/destroy = qualquer agent/admin (4-22); **Scope filtra só por account** (24-31).
- ⚠️ **A custom role "Corretor" (conversation_participating_manage) NÃO é respeitada no Kanban.** Não existe override em `enterprise/` (grep "funnel" em enterprise/ → só as 3 tools/job do Captain). O `Enterprise::Conversations::PermissionFilterService` filtra a lista de conversas, mas o funnel_items#index entrega TODOS os cards do funil, com nome/telefone/última mensagem, pra qualquer agent. Corretor vê no Kanban o que não vê na inbox. (Por outro lado, é exatamente por onde a secretária enxergaria tudo.)

---

## 5. Frontend

### Rotas — `app/javascript/dashboard/routes/dashboard/kanban/routes.js`
- `/accounts/:accountId/kanban` (`kanban_index`) e `/kanban/:funnelId` (`kanban_funnel`), `permissions: ['administrator','agent']` (linhas 4-6).

### Página — `app/javascript/dashboard/routes/dashboard/kanban/pages/KanbanIndex.vue` (921 linhas)
- Alterna `viewMode` `kanban | list | calendar` (linhas 818-841): `KanbanBoard`, `ListView`, `CalendarView` (todos em `app/javascript/dashboard/components-next/Kanban/`).
- Filtros de UI: busca, labels, assignee, status, stages (KanbanFilterSelect; persistidos por usuário em localStorage, linha 64-67). CRUD de funil via `FunnelForm`; agendamento via `ScheduledMessageForm`/`ScheduledMessagesDrawer`.

### Drag-and-drop (como o humano move o card)
1. `KanbanColumn.vue` usa vuedraggable; no drop, `handleDropChange` (107-115) emite `moveItem { item, stageId }`.
2. `KanbanBoard.vue#handleMoveItem` (237-292): lock anti-double-move, despacha **`store.dispatch('kanban/updateItem', { funnelId, itemId, data: { funnel_stage_id } })`** (248-252); em erro, alerta + refetch dos 2 stages.
3. Store `app/javascript/dashboard/store/modules/kanban/actions.js:480-484` → `KanbanAPI.updateItem`.
4. `app/javascript/dashboard/api/kanban.js:109-113` → **`PATCH /api/v1/accounts/:account_id/funnels/:funnelId/funnel_items/:itemId`** body `{ funnel_item: { funnel_stage_id } }`.
5. Backend: `FunnelItemsController#update` → `FunnelItems::MoveService` (com o side effect de status descrito no §4).
- Board também permite arrastar colunas (reorder de stages → `POST reorder_stages`, `Funnels::ReorderStagesService`).
- `ListView.vue` não move cards (emite só scheduleMessage/removeItem/manageScheduled — linha 18). `CalendarView.vue` é a agenda de ScheduledMessages (não de cards). `MoveItemModal.vue` existe mas **não é importado em lugar nenhum** (código morto).
- `KanbanAPI` (api/kanban.js) também embute o client de `scheduled_messages` (126-205) — o Kanban é a casa da UI de mensagens agendadas.

---

## 6. Rakes — `lib/tasks/spx_tozi.rake`

- **`spx:tozi:setup_funnel[account_id,inbox_id]`** (29-53): idempotente; cria/atualiza funil **"Pré-Venda Tozi"** com `inbox_ids=[inbox]` e os 7 estágios `PREVENDA_STAGES` (16-24): novo_lead(0), aguardando_1a(1), em_conversa(2), em_silencio(3), agendado(4), qualificado(5), frio(6) — match por `automation_type`, atualiza nome/cor/posição sem duplicar. Em prod: funil id=41, stages 127-133 (STATE.md).
- **`spx:tozi:backfill_funnel[account_id]`** (233-255): coloca conversas com `additional_attributes->>'source' = 'meta_lead_ads'` em "Novo Lead" (find_or_initialize, não move quem já tem card). Escopo bem mais estreito que o backfill genérico do Kanban.
- (No mesmo arquivo: `create_templates` — 4 HSMs da cadência, idempotente; `disparo`/`disparo_teste` — motor de disparo, sem relação com funil.)

---

## 7. Respostas diretas às perguntas

**Card↔conversa?** FK dupla: `FunnelItem(conversation_id, funnel_id, funnel_stage_id)`, único por (conversa, funil). Card morre em cascata com a conversa. Não existe card por contato.

**Transições automáticas hoje?** As 7 da tabela do §3. Produtor de 'novo_lead' = só o hook Meta Lead Ads. `em_conversa` e `qualificado` via listener global (eventos `message_created`/`assignee_changed`); `em_silencio`, `frio`, `qualificado` também via tools do Captain e FollowupJob.

**Stages sem trigger?** `agendado` e `aguardando_1a` — só humano move (ou API). `aguardando_1a` deveria ser alimentado pelo pós-1ª-HSM (gap do DisparoLeadJob); `agendado` pediria uma tool de agendamento.

**Como humano move?** Drag-and-drop → `PATCH /api/v1/accounts/:aid/funnels/:fid/funnel_items/:iid` `{funnel_item:{funnel_stage_id}}`. Em lote: `POST .../funnel_items/bulk_move` `{conversation_ids:[], stage_id:}`.

**O que uma IA usaria pra…**
- *Mover card:* backend/tool → `Spx::Tozi::FunnelPlacementService.move(conversation:, to: '<automation_type>')` (idempotente, sem IDs, no-op seguro). HTTP → PATCH funnel_items (precisa do item id) ou POST funnel_items com `display_id` da conversa + `funnel_stage_id` (o create reusa o item existente via MoveService).
- *Consultar estágio de um lead:* backend → `FunnelPlacementService.current_type(conversation)`. HTTP → **não existe** endpoint "estágio da conversa X"; teria que `GET funnel_items?stage_id=` por estágio ou listar tudo e filtrar por `conversation_id`.
- *Listar parados há X dias:* **não existe endpoint**. Dado existe (`moved_at`, exposto no JSON), consulta canônica seria `FunnelItem.by_funnel(f).by_stage(s).where('moved_at < ?', x.days.ago)`. O index ordena por `last_activity_at` e não filtra por `moved_at` — pra orquestração de follow-up isso é o buraco mais óbvio a fechar (endpoint `stale` ou filtro `moved_before`).

**Funil por inbox ou account? Multi-funil?** Por **account**, com restrição opcional a inboxes (`inbox_ids`) e a team (`team_id`). Multi-funil funciona no modelo (N funis, card por funil), e o `FunnelPlacementService` discrimina o funil Tozi por automation_type. MAS a automação genérica (`FunnelLookupService`) só atua no primeiro funil default por id — coexistência Geral×Tozi depende dessa ordem.

---

## 8. Gaps e riscos

1. **Kanban vaza dados pra custom role "Corretor"**: `FunnelItemPolicy::Scope` filtra só por account (funnel_item_policy.rb:24-31); nenhum override Enterprise. Corretor vê todos os cards (nome, telefone, última mensagem) de conversas que a permissão de inbox esconde dele.
2. **Backfill automático polui o funil Tozi**: todo GET do board (throttle 10 min) despeja conversas open/resolved da inbox 91 sem card no 1º estágio "Novo Lead" (`default_stage = stages.first`, backfill service:19,60-69). Atendimento humano comum vira "lead novo" no funil de pré-venda.
3. **DisparoLeadJob não coloca lead no funil** — leads de disparo entram via backfill, indistintos, em "Novo Lead", em vez de `aguardando_1a` com origem de campanha.
4. **Cards duplicados por conversa duplicada** (9º dígito): dedup é só visual no controller (funnel_items_controller.rb:158-190); o banco mantém N cards. A consolidação de conversas (delete cascade) limpa os cards órfãos, mas o estágio "vencedor" fica indefinido.
5. **`assignee_changed` → 'qualificado' confunde atribuição administrativa com handoff**: round-robin de disparo, reatribuição em massa ou triagem da secretária promovem o card a "Qualificado" sem qualificação real (guard é só "estava em estágio de pré-venda").
6. **Listener global multi-tenant**: `FunnelAutomationListener` roda 1+ query (`current_type`, com joins) em todo `message_created`/`assignee_changed` de toda conta (async_dispatcher.rb:14) — já apontado em `docs/AUDITORIA-SPX-2026-06-04.md` (§ gate por feature-flag).
7. **Drag pode resolver conversa**: `FunnelItems::MoveService#update_conversation_status` (move_service.rb:34-44) resolve/reabre conforme automation_type do stage destino — combinado com bot na inbox, alimenta o limbo pending conhecido.
8. **`ReactivationCadenceService` inerte sem a coluna `template_params`**: `db/schema.rb` local não mostra a coluna em scheduled_messages (1310-1330) embora a migration 20260529120000 exista; em prod depende do migrate (a landmine 20260330120000 já causou medo de `db:migrate` puro).
9. **Sem API de consulta orientada a orquestração**: nenhum endpoint "estágio do lead", "parados há X dias", "cards por automation_type"; cursor mode atrás de feature flag.
10. **Comentário desatualizado** na migration 20260203180000 vs comportamento atual do backfill (ainda inclui resolved). **`MoveItemModal.vue` é código morto.**

---

## 9. Pontos de plugagem pra IA orquestradora

1. **`Spx::Tozi::FunnelPlacementService.move/current_type`** — API de movimentação idempotente keyed por automation_type; é o contrato que as tools do Captain já usam. Nova tool de orquestração (triagem, agendar visita → 'agendado', devolver pra fila) deve chamar isso.
2. **Tools Captain existentes como template** (`programar_followup_tool.rb`, `salvar_info_lead_tool.rb`): padrão pronto de "decisão do agente → side effect no funil + cadência". Faltam tools simétricas pra 'agendado' e pra mover entre corretores.
3. **Eventos via `AsyncDispatcher#listeners`** (async_dispatcher.rb:11-25): `message_created`, `assignee_changed` já consumidos; `conversation_status_changed`, `conversation_created` etc. disponíveis pro mesmo padrão de listener (com gate por conta).
4. **REST completa** `funnels`/`funnel_stages`/`funnel_items` (+`bulk_move`, +create por `display_id`) — suficiente pra um orquestrador externo mover/criar cards; estágios novos podem ser criados via API com `automation_type` custom (funnel_stages_controller.rb:62).
5. **`moved_at` + `moved_by_id`** — base pronta pra detectar leads parados (moved_by nil = automação; preenchido = humano). Falta só expor filtro/endpoint.
6. **`ScheduledMessages` + `template_params`** (Bloco 4) — braço de ação fora da janela 24h, já integrado ao funil (cadência agenda/cancela conforme estágio). A IA pode agendar HSM determinístico via `ScheduledMessages::CreateService`.
7. **Hooks de ciclo de vida em Conversation** (conversation.rb:156-161) — qualquer criação de conversa entra em funil; um hook tipo `place_in_funnel` no DisparoLeadJob fecharia a lacuna do 'aguardando_1a'.
8. **`Captain::Conversation::FollowupJob`** — laço de follow-up in-window dirigido pelo agente, com token/guards; ponto natural pra IA decidir "cutucar vs esfriar vs escalar".
