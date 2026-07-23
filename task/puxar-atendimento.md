# Puxar Atendimento — plano de execução

## Context

**A dor:** dois agentes atendem o mesmo contato sem saber um do outro. Hoje o agente não vê quem está
atendendo quem, então cria conversa nova (ou entra na existente e responde por cima) — e o cliente
recebe dois atendimentos em paralelo.

**O que o dono pediu:**
1. Aba na página de contatos mostrando quem está **em atendimento**, com **agente e time**, e **sem
   mostrar nenhum trecho da conversa**.
2. Em vez de criar conversa nova, o agente **solicita** a conversa; quem atende **permite ou não**.
3. Ao criar nova conversa e escolher contato já em atendimento, o sistema **avisa** e oferece solicitar.

**Decisões travadas com o dono (2026-07-16):**
- **D1 — O pedido é o único caminho.** Conversa com dono humano só troca de mãos via pedido aprovado
  ou por admin. O "Assumir de {nome}" de hoje vira "Solicitar atendimento".
- **D2 — A aba mostra todos os times** ("atendimento geral"), **só metadado**: contato, agente, time,
  inbox, status, tempo. Nunca conteúdo de mensagem.
- **D3 — Sem resposta o pedido fica pendente**; admin aprova/força. Sem timeout automático.
- **D4 — Três fases**, cada uma entregando valor sozinha.

**Estado atual medido (staging, conta 1):** 21 conversas open+pending, 18 com agente, **17 contatos
distintos em atendimento**. `reply_assignment_gate` **desligado**; `resolve_assignment_gate` ligado.

---

## Fatos que mandam no desenho (verificados no código, não presumidos)

1. **Não existe feature flag livre.** `config/features.yml` tem **65 flags** num bitmask `bigint` de
   **63 bits** (`db/schema.rb:69`). As flags 64/65 (vindas do upstream) **já estão quebradas**. →
   Usar `store_accessor :settings` (`app/models/account.rb:103-105`), como `reply_assignment_gate` e
   `resolve_assignment_gate`. Sem migration, ligável por conta, whitelist em
   `app/controllers/api/v1/accounts_controller.rb:144`.
2. **O pedido NÃO pode ser uma `Notification`.** `Notification::RemoveDuplicateNotificationJob`
   apaga todas as notificações do mesmo `user_id` + `primary_actor_id` **ignorando o tipo**, e roda
   a cada criação (`notification.rb:222`). O pedido pendente morreria na próxima mensagem da
   conversa. → **Tabela própria**; a Notification é só o aviso.
3. **Tipo novo de notificação é seguro.** Enum `notification.rb:41-55` é `integer` sequencial (vai
   até 10); `NotificationSetting` deriva bits em colunas `integer` (31 bits). Cabe, sem migration.
   **Nunca renumerar** (o próprio arquivo avisa em `:48-50`).
4. **A trava mora na FRONTEIRA MANUAL, não no service.** Há 4+ caminhos que trocam o dono e as
   automações **bypassam** o service (`app/services/action_service.rb:52` faz `update!(assignee_id:)`).
   O fork já resolveu esse mesmo dilema e documentou em
   `assignments_controller.rb` (guard do espelho captain): *"Automação/macro/tool não passam pelo
   controller (in-process) — o guard mora SÓ aqui de propósito."* **Todo** caminho de UI
   (diálogo de responder, Kanban "Assumir", lista, menu de contexto) cai em
   `POST /conversations/:id/assignments` (`api/inbox/conversation.js:94-98`). A exceção é **ações em
   massa**, que têm porta própria (`bulk_actions_controller.rb:51` aceita `assignee_id`) — e o fork
   já duplica a checagem de gate lá (`bulk_actions_job.rb:64`).
5. **A consulta de "em atendimento" já existe — e não serve como está.**
   `app/services/live_reports/in_service_query_service.rb` faz a query certa (open+pending, filtros,
   cursor, `ListPreloader`), mas é **admin-only** (`ReportPolicy#view?`) e o serializer **expõe
   `last_message`** (`:112-124`). Reusar o **padrão**, nunca o serializer.
6. **O partial de conversa vaza mensagem.**
   `app/views/api/v1/conversations/partials/_conversation.json.jbuilder:98-110` emite
   `json.messages [last_message.try(:push_event_data)]`. Jbuilder novo e enxuto — não `json.partial!`.
7. **`assignee_last_changed_at` NÃO é "atendendo desde".** É **zerado na primeira resposta do
   agente** (`app/models/message.rb:440`). Usá-lo mostraria "—" justamente nos atendimentos que
   engrenaram. Não existe coluna `assigned_at`. → Exibir `created_at` ("aberto há") e
   `last_activity_at` ("última atividade"), que são verdade.
8. **`check_authorization` faz `controller_name.classify.constantize`** (`api/base_controller.rb:15`)
   → controller sem model correspondente quebra com `NameError`. Precisa de override (molde:
   `funnels_controller.rb:108-110`).
9. **O gancho do aviso já existe e hoje é silencioso.**
   `components-next/NewConversation/ComposeConversation.vue:221-241` já detecta conversa ativa e
   chama `sendToExistingConversation` **sem avisar nada**.
10. **Cuidado com o falso-negativo de permissão.** `contactConversations/get` passa por
    `Conversations::PermissionFilterService`, que para agente de outro time devolve **vazio** — e o
    `ConversationBuilder` reusa a conversa mesmo assim. Ou seja, **hoje** o agente manda mensagem numa
    conversa que ele não vê. O gate da Fase 2 **não** pode usar essa fonte.

---

## FASE 1 — Aba "Em atendimento" (só leitura, risco baixo)

**A linha é um ATENDIMENTO (conversa), não um contato**: um contato pode ter 2 conversas abertas em 2
inboxes com 2 agentes. Colapsar por contato obrigaria a escolher um agente arbitrário e mentir. Bônus:
a Fase 3 precisa de `conversation_id`, e a linha já carrega.

### Backend
- **Rota**: `resources :active_attendances, only: [:index]` em `config/routes.rb`, ao lado de
  `resources :contacts` (`:268-290`).
- **Controller novo** `app/controllers/api/v1/accounts/active_attendances_controller.rb` — **não**
  enfiar no `contacts_controller.rb` (já tem `rubocop:disable Metrics/ClassLength`, 332 linhas, e o
  payload é conversa-shaped). Override do `check_authorization` (fato 8).
- **Policy nova** `app/policies/active_attendance_policy.rb` → `index? = true` (espelha
  `ContactPolicy#index?`).
- **Query**: `Current.account.conversations.where(status: %w[open pending snoozed])`,
  `.where.not(contact_id: nil)`, filtro opcional `?contact_id=`, `preload(:contact, :team, :inbox,
  :assignee, :assignee_agent_bot)`, `order(last_activity_at: :desc, id: :desc)` (o `id` desempata p/
  paginação estável), Kaminari 15/página.
  - **`preload`, não `includes`** — `includes` + `order` viraria LEFT JOIN e quebraria o `total_count`.
  - **Sem `PermissionFilterService`, de propósito** (D2). Escreva a justificativa em comentário: o
    filtro protege **conteúdo**, e aqui não sai um byte de mensagem; é o mesmo grau de exposição da
    aba `Active`, que já lista contatos de toda a conta. Aplicá-lo quebraria o requisito **e** daria
    lista incompleta em silêncio.
- **Jbuilder novo** `app/views/api/v1/accounts/active_attendances/index.json.jbuilder`. Envelope
  `meta{count,current_page}` + `payload` igual ao de contatos (o front reusa a paginação).
  - Expor: `id` (display_id), `conversation_id`, `status`, `created_at`, `last_activity_at`,
    `contact{id,name,thumbnail,phone_number,email}`, `inbox{id,name,channel_type}`,
    `assignee{id,name,thumbnail,type,is_captain?}`, `team{id,name}`.
  - **Fora de propósito**: `messages`, `unread_count`, labels, custom/additional_attributes,
    email/role do agente.
  - 3 variantes de assignee, espelhando `_conversation.json.jbuilder:36-83`: humano / espelho
    captain (`type: 'agent_bot'`) / "Agente Removido" (assignee_id sem user).

### Frontend
- **API client** `api/activeAttendances.js` (molde `api/contacts.js:85-88`).
- **Store novo** `store/modules/activeAttendances.js` — **não** escrever no store `contacts` (é
  chaveado por id de contato; records conversa-shaped corromperiam a aba "Todos os contatos").
  Getter `getByContactId` (a Fase 2 usa).
- **Aba** = rota irmã (o molde exato é a aba `Active`), nos 5 pontos:
  `routes/dashboard/contacts/routes.js:33-37` · `components-next/sidebar/Sidebar.vue:575-580` ·
  `ContactsIndex.vue` (flag de view `:118`, título `:135-141`, empty state `:144-150`, dispatch
  `:213-221`/`:262-266`/`:325-328`/`:427-430`) · `ContactsListLayout.vue:44-59,84-93` ·
  `ContactHeader.vue:17` (esconder busca/filtro/sort de contato).
- **Componentes novos** `Contacts/Pages/AttendanceList.vue` + `Contacts/AttendanceCard/AttendanceCard.vue`
  — **não** estender `ContactsCard.vue` (traz form de edição, delete, seleção). Card: contato →
  agente (badge "IA" quando `type === 'agent_bot'`, "Sem responsável" quando ausente) → time ("Sem
  time") → inbox → status → "aberto há {tempo}" → botão **"Solicitar atendimento"**.
- **O botão nasce desabilitado** ("Em breve"), emitindo `request-attendance {conversationId, contactId}`.
  Não criar endpoint stub que a Fase 3 vai desfazer.
- **Sem barra de ações em massa** na aba (seleção/labels/delete são de contato).
- **i18n** pt_BR **e** en: `SIDEBAR.IN_ATTENDANCE`, `CONTACTS_LAYOUT.HEADER.IN_ATTENDANCE_TITLE`,
  `CONTACTS_LAYOUT.EMPTY_STATE.*`, `CONTACTS_LAYOUT.IN_ATTENDANCE.*`.

---

## FASE 2 — Aviso ao criar conversa (o gancho já existe)

- **Dois lugares**: banner inline no `ComposeNewConversationForm.vue` assim que o contato é escolhido
  (molde visual: banner de WhatsApp inválido `:500-525`) **e** gate no submit em
  `ComposeConversation.vue:221-241` (o agente pode ignorar o banner; e há corrida).
- **Fonte de verdade = endpoint da Fase 1 com `?contact_id=`** — nunca `contactConversations` (fato
  10: falso-negativo → o agente escreve numa conversa invisível para ele). É por isso que o
  `contact_id` mora no endpoint da Fase 1.
- **Cross-inbox**: `getActiveConversationByInbox` filtra por inbox; o aviso **não pode** — o contato
  pode estar em atendimento em outra inbox, que é justamente a duplicação a evitar. Texto distingue
  "nesta caixa" vs "em outra caixa ({nome})".
- **Variantes** (espelham `AssignToReplyDialog.vue:70-77`): dono humano → "em atendimento com {nome}
  ({time})"; dona IA → "atendido pela {IA}"; sem dono → aviso leve "conversa aberta na fila do time",
  ação primária **Ir para a conversa** (não há a quem solicitar).
- **Composable único** `composables/useAttendanceGate.js` → `{ fetchAttendances, resolveGate }`
  retornando `{ blocked, attendance, variant, sameInbox }`. Consumidores: `ComposeConversation.vue` e
  `message/bubbles/ContactCard.vue:222` (`startConversation`), **removendo** a cópia
  `findActiveConversation` (`:201-218`) — hoje já são duas verdades divergentes; uma terceira seria fatal.
- **Componente** `NewConversation/components/AttendanceWarningDialog.vue` (molde `AssignToReplyDialog.vue`).
- Sem a Fase 3, as ações são **Ir para a conversa** / **Enviar mesmo assim** / Cancelar. O valor —
  parar de mandar mensagem calado — não depende de pedido nenhum.
- **i18n**: `COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.*` (pt_BR + en).

---

## FASE 3 — Pedido e aprovação (o grosso)

> ⚠️ **Correção a uma premissa minha:** não existe "ponto único de atribuição". São **8 caminhos**
> que escrevem `assignee_id` (service, automação, round-robin ×2, toggle_status, o próprio modelo,
> bulk job, `update_all` no destroy). Guard no `AssignmentService` = **falsa segurança** + bypass em
> 5 callers legítimos. O guard vai nas **superfícies humanas**, e são **três**, não uma.

### O buraco do D1 (verificado — e NÃO é bug do fork)
**`toggle_status_service.rb:58`**: `should_assign_conversation?` só checa
`status == 'open' && @user.agent?` — **não checa se a conversa já tem dono**. Quem **reabre a
conversa resolvida de um colega vira o dono** (`:19` → `:67` `update!(assignee: @user)`), sem passar
por controller nenhum.

⚠️ **Isso é comportamento do Chatwoot ORIGINAL**, copiado fielmente para o service do fork — o
upstream tem a linha idêntica em `conversations_controller.rb:97-99` ("quem reabre, assume"). **Não
corrigir isoladamente**: hoje, sem o gate, mudar isso alteraria o dia a dia de todos (o agente
reabriria e a conversa continuaria com o dono antigo, possivelmente ausente) sem nada em troca — e o
`reply_assignment_gate` está desligado, então ele responderia assim mesmo. O lugar certo é o **guard
(c) desta fase**, que é **no-op quando o gate está desligado**: quem ligar o modo aceita a regra
nova; quem não ligar não vê diferença.

### ✅ Já resolvido (commit `0a6138416`, 2026-07-16)
`queue_escalation_after` existia no `store_accessor` + schema JSON mas estava **fora** da whitelist
(`accounts_controller.rb:144-149`) → a API descartava calada. Não era bug ativo (nenhuma UI usa; o
job lê com padrão), mas era a armadilha exata que esta fase repetiria. Corrigido + **spec cobrindo as
4 settings de atribuição** (nenhuma tinha teste — foi assim que a omissão passou). **Ao criar
`takeover_request_gate`, a spec nova é o lugar de incluí-la.**

### Configuração
`store_accessor :settings, :takeover_request_gate` (vocabulário "takeover" já é o do fork:
`notification_listener.rb:49`, `fireTakeoverConfetti`, `conversation_unassignment`). Os **4 pontos**:
JSON schema `account.rb:44-46` · `store_accessor` `:103-105` · helper
`takeover_request_gate_enabled?` `:~224` · **whitelist `accounts_controller.rb:144`** (o passo
esquecido). Toggle no molde de `ResolveGateToggle.vue`. **Nada em `features.yml`** (fato 1).
**Independente do `reply_assignment_gate`** — não acoplar no backend (acoplamento implícito =
surpresa); a UI apenas avisa que faz mais sentido com o modo Atendimento ligado.

### Tabela `conversation_takeover_requests` (migration idempotente)
Colunas: `account_id`, `conversation_id`, `requester_id`, **`owner_id` (SNAPSHOT do dono no momento
do pedido)**, `status`, `resolution_source`, `reason`, `response_note`, `responded_by_id`,
`responded_at`, timestamps.
- **`owner_id` é snapshot, não `conversation.assignee_id` lido depois**: se a conversa trocar de mãos
  por outro caminho, precisamos saber *contra quem* o pedido foi feito — ler o assignee atual responde
  a pergunta errada.
- **Índice único PARCIAL `[conversation_id, requester_id] WHERE status = 0`**: impede o **mesmo**
  agente pedir 2×; **permite** agentes diferentes pedirem a mesma conversa (o dono escolhe); e não
  bloqueia um novo pedido depois de um `cancelled`.
- Índices: `[owner_id, status]` ("preciso responder"), `[requester_id, status]` ("meus pedidos"),
  `[account_id, status]` (admin). `if_not_exists: true` em tudo.
- Estados: `pending → approved | denied | cancelled | superseded`; `resolution_source: owner | admin |
  system` (os três juntos: `responded_by_id` sozinho não distingue "o dono aprovou" de "um admin que
  por acaso é o dono" de "o sistema encerrou").

### A trava (D1) — PORO `Conversations::TakeoverGate` em 3 superfícies
Regras (passa livre): gate desligado · ator não é `User` · **admin** · conversa **sem dono** ·
dona **IA/AgentBot** · o próprio dono · no-op · `Current.takeover_approval_in_progress`.

| # | Onde | Por quê |
|---|---|---|
| a | `assignments_controller#set_agent` | **Toda** atribuição manual humana passa aqui (dropdown, `AssignToReplyDialog`, Kanban, menu, API). 422 `takeover_request_required` + `meta.current_assignee/team/existing_request` (molde `messages_controller.rb:252-266`). |
| b | `bulk_actions_job` (`:33-42`) | Porta própria: seta `Current.user` (`:20`) e faz `update(params)` com `assignee_id`. Guard irmão do `resolution_blocked?` (`:44-61`); `next` + log. **Não** criar pedidos em massa (500 pedidos = DoS social). |
| c | `toggle_status_service#should_assign_conversation?` | Fecha o roubo silencioso acima. Fail-safe: pula só o self-assign; reabrir continua permitido. |

**Passam livres, sem precisar de bypass nenhum** (é o ponto do desenho): automações
(`action_service.rb:52`), macros, round-robin, Captain/IA, kanban automation, `conversation_builder`,
admin, self-assign de conversa sem dono, e a própria aprovação.

**NÃO pôr guard no modelo (`AssignmentHandler`)**: `Macros::ExecutionService:7` faz
`Current.user = user` → **toda macro com `assign_agent` quebraria em silêncio**; `update_all` no
`agents/destroy_job.rb:43` pula callbacks; e `throw :abort` viraria `RecordNotSaved` em ~11 call
sites que não tratam.

### API
`POST .../conversations/:cid/takeover_requests` (`reason`) · `POST .../takeover_requests/:id/{approve,deny,cancel}`
· `GET /takeover_requests?scope=incoming|outgoing&status=pending`.
- Pendurar em `Conversations::BaseController` → herda `authorize :show?` **e** `authorize_team_access` de graça.
- Policy: `create?` = não-admin · `approve?`/`deny?` = **dono ou admin** (D3) · `cancel?` = solicitante ou admin.
  `index` filtra por `owner_id`/`requester_id` → seguro por construção, sem `PermissionFilterService`.
- Erros: `conversation_unassigned` · `conversation_owned_by_bot` · `takeover_request_exists` ·
  `takeover_request_closed` · **`takeover_request_stale`** (no approve, `conversation.assignee_id != owner_id`).
- **`approve` com `with_lock` + `reload`** e `Current.takeover_approval_in_progress = true` num
  `ensure ... = nil` (thread-local + Puma reusa threads — precedente `Macros::ExecutionService:21-22`).
  Aprovar supersede os pedidos irmãos **na mesma transação**.

### Notificação + realtime
- **2 tipos novos** (não 3): `11 conversation_takeover_requested` (ao dono) ·
  `12 conversation_takeover_responded` (ao solicitante; aprovado/negado distinguidos no corpo — cada
  tipo custa 2 bits e uma linha de preferência). Receita de 8 passos (espelho de `dfc42ac83`), sem
  migration. **Congelar a numeração em spec** (`expect(NOTIFICATION_TYPES[:conversation_unassignment]).to eq(10)`).
- **Criar a Notification DIRETO no service síncrono**, com `secondary_actor` **explícito** — o pedido
  não é efeito colateral de evento, é o próprio ato. Isso **elimina** o problema do `Current.user`
  nil no dispatcher async (fato: `assignment_handler.rb:70-77`) em vez de contorná-lo.
- ⚠️ **O sino NÃO serve de CTA**: `RemoveDuplicateNotificationJob` apaga por `user_id +
  primary_actor_id` ignorando o tipo → com `primary_actor = conversation`, o aviso do pedido some na
  próxima mensagem. E **não** tente pôr o request como `primary_actor`:
  `Notification::PRIMARY_ACTORS = ['Conversation']` (`:38`) + ~5 métodos assumem Conversation.
  → **O pedido sobrevive na tabela** (por isso ela existe); a aprovação mora em **duas superfícies
  duráveis**: **banner no topo da conversa** ("Ana pediu esta conversa: '…' [Aprovar] [Negar]") e
  **lista "Pedidos"** com contador. O sino só leva à conversa.
- **Realtime dirigido** (3 pontos, molde `FUNNEL_ITEM_MOVED`): `lib/events/types.rb` →
  `action_cable_listener.rb` com `[owner.pubsub_token]` / `[requester, owner].uniq` — **nunca**
  broadcast para a conta inteira (pedido é dado entre duas pessoas) → `helper/actionCable.js`.

### UI — `AssignToReplyDialog.vue` (variante **b**, dono humano)
Com o gate ON: `onConfirm` (`:132-157`) chama `createTakeoverRequest({conversationId, reason})` e
**não** emite `confirm` (o ReplyBox não pode reenviar — nada foi assumido), **não** dispara
`fireTakeoverConfetti()` (não houve takeover) e **não** chama `assignTeam` (mudar o time da conversa
**de outra pessoa** antes da aprovação é efeito colateral não autorizado). Campo `reason` opcional.
Variantes (a) sem dono, (c) IA e (d) fora do time: **intactas**.

### Casos de borda
| Caso | Tratamento |
|---|---|
| **Dono/solicitante sai da conta** | `agents/destroy_job.rb:43` usa `update_all` → **pula callbacks**; adicionar `supersede` explícito lá, senão ficam pedidos órfãos para sempre. |
| **Reatribuída por outro caminho** | `after_commit` **novo e independente** na Conversation (não pendurar em `process_assignment_changes` — reentrância): assignee mudou e ≠ `owner_id` → `superseded`; **exceção**: novo dono == `requester_id` → `approved`/`system`. |
| **Conversa resolvida com pedido pendente** | **Não invalida** (coerente com D3). Cuidado com o guard (c) na reabertura. |
| **Dois agentes pedem a mesma conversa** | Permitido; o dono escolhe; aprovar um supersede os outros na mesma transação. |
| **Solicitante desiste** | `cancelled`, **sem** notificar o dono (ruído puro) — só o evento realtime some com o banner. |
| **Dona IA / sem dono / admin** | Gate não bloqueia; pedir conversa de bot → 422 `conversation_owned_by_bot`. |

---

## Verificação

**Fase 1 (a spec que trava o requisito):**
- `spec/controllers/api/v1/accounts/active_attendances_controller_spec.rb`: 401 sem auth · retorna
  open/pending/snoozed e **não** resolved · **agente de OUTRO time VÊ** (trava contra alguém
  "consertar" com `PermissionFilterService`) · **payload NÃO tem `messages`**
  (`expect(json['payload'].first).not_to have_key('messages')` — blinda a privacidade contra reuso
  acidental do partial) · variantes de assignee (humano/IA/removido/ausente) · `?contact_id=` filtra ·
  paginação · **N+1** (`not_to exceed_query_limit`).
- Front: spec do store, spec do `AttendanceCard` (badge IA, "Sem responsável"/"Sem time", emite
  `request-attendance`), paridade i18n por subárvore (molde `i18n/specs/reply-gate-ptbr.spec.js`).

**Fase 2:** spec do `useAttendanceGate` (sem atendimento → `blocked:false`; humano/IA/sem dono →
variantes; **outra inbox → `blocked:true, sameInbox:false`** — o caso que o código de hoje erra) ·
spec de que `createConversation` **não** envia sem confirmação · `ContactCard.startConversation` passa
pelo gate.

**Fase 3 — o que a trava promete:**
- `assignments_controller_spec` (já existe): gate ON + não-dono → 422 **E `conversation.reload.assignee`
  inalterado** (assertar as duas coisas — 422 sem checar o efeito já passou verde em código quebrado).
  Gate OFF → 200; admin → 200; sem dono → 200; dona IA → 200.
- **`toggle_status_service_spec` (já existe) — o mais fácil de esquecer e o mais importante**: agente
  reabre conversa **resolvida de outro dono** com gate ON → assignee **permanece** o original. Hoje
  ele rouba e nenhum teste percebe.
- `bulk_actions_job_spec`: bulk com `assignee_id` sobre conversa de terceiro → inalterado **e nenhum
  pedido criado**.

**Fase 3 — o que a trava NÃO pode quebrar (mais importante que o item acima):**
- `action_service_spec` (automação) e **`macros/execution_service_spec`** com gate ON → **mudam** o
  dono. O de macro é o que documenta por que o guard não está no modelo (`Macros::ExecutionService:7`
  seta `Current.user`).
- `auto_assignment/agent_assignment_service_spec` → round-robin ignora o gate.
- **`assignment_service_spec` (já existe) continua verde SEM alteração** = prova executável de que o
  gate não mora no service.

**Fase 3 — fluxo:** índice parcial (2º pending do mesmo requester → `RecordNotUnique`; requester
diferente OK; `cancelled` não bloqueia novo) · aprovar atribui (regressão clássica: o próprio
caminho de aprovação ser bloqueado pelo gate) · aprovar 2× → `closed` · conversa já reatribuída →
`stale` · `Current.takeover_approval_in_progress` volta a `nil` no `ensure` (thread-local vazando
entre requests é o bug que ninguém acha) · `agents/destroy_job` supersede pendentes · **spec do
`RemoveDuplicateNotificationJob`**: pedido criado → mensagem nova na conversa → o **pedido sobrevive**
(a tabela é justamente o que garante isso).

**Fase 3 — front:** `AssignToReplyDialog.spec.js` (já existe, 215 linhas): variante (b) com gate ON
chama `createTakeoverRequest`, **não** emite `confirm`, **não** chama `assignTeam`, **não** dispara
confetti; variantes (a)/(c)/(d) inalteradas.

**No navegador (staging `nicolas.chatspx.app` — [[test-in-staging-not-production]]):** a aba lista os
17 contatos em atendimento com agente/time e **sem trecho de conversa** · agente de outro time
enxerga · criar conversa para contato atendido mostra o aviso · com o gate ligado, "Assumir" vira
"Solicitar" e o dono recebe no sino em tempo real · aprovar transfere · negar não transfere · admin
força. Rodar com **dois navegadores/usuários** (solicitante e dono) — é a única forma de ver o
tempo real de verdade.

---

## Notas de execução
- Commit ao fim de cada fase ([[commit-at-end-of-each-phase]]); cada fase é deployável sozinha.
- Nada de `features.yml`. Nada de renumerar enum de notificação.
- Medir baseline de specs antes (a suíte tem falhas pré-existentes de ambiente).
- Migration da Fase 3: aplicar no staging e **no banco de teste**; produção/frota são decisão à parte
  ([[runbook-deploy-producao]]).
