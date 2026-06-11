# Mapeamento — Visibilidade e Permissões de Conversas (ChatSPX, branch paulao)

> Gerado em 2026-06-10. Baseado 100% em leitura do código local (app/ + enterprise/), com referências arquivo:linha.
> Contexto: Tozi (Account 6, inbox 91), corretores com custom role restritiva, secretária de triagem que "não vê" conversas atribuídas a corretores.

---

## 1. Arquitetura em camadas — quem filtra o quê

A visibilidade de conversas passa por **4 camadas independentes** (e nem sempre consistentes entre si):

| # | Camada | Arquivo | Quando roda |
|---|--------|---------|-------------|
| 1 | `Conversations::PermissionFilterService` (OSS) | `app/services/conversations/permission_filter_service.rb` | Toda listagem (finder, filter service, copilot search) |
| 2 | `Enterprise::Conversations::PermissionFilterService` (overlay) | `enterprise/app/services/enterprise/conversations/permission_filter_service.rb` | Prepended no OSS; ativa só p/ agent com `custom_role_id` |
| 3 | `ConversationFinder` (filtros extras: inbox, time, status, tipo) | `app/finders/conversation_finder.rb` | Lista da UI (`GET /conversations`) |
| 4 | `ConversationPolicy` + `Enterprise::ConversationPolicy` (acesso unitário) | `app/policies/conversation_policy.rb` + `enterprise/app/policies/enterprise/conversation_policy.rb` | `show?` em todo endpoint de conversa individual |

E mais duas camadas no **frontend**:

| 5 | Tabs Mine/Unassigned/All gated por permissão | `app/javascript/dashboard/constants/permissions.js:32-53` + `ChatList.vue:221-252` |
| 6 | Filtro client-side de eventos real-time | `app/javascript/dashboard/store/modules/conversations/helpers.js:102-136` (`applyRoleFilter`) |

---

## 2. O modelo de papéis

### 2.1 Papéis base (OSS)

`AccountUser` (`app/models/account_user.rb:34`): `enum role: { agent: 0, administrator: 1 }`.

- `AccountUser#permissions` OSS (`app/models/account_user.rb:57-59`): retorna `['administrator']` ou `['agent']`.
- Overlay Enterprise (`enterprise/app/models/enterprise/account_user.rb:2-4`): se tem `custom_role`, retorna `custom_role.permissions + ['custom_role']`.
- Associação `belongs_to :custom_role` vem de `enterprise/app/models/enterprise/concerns/account_user.rb:5`.

### 2.2 Custom roles (Enterprise)

`enterprise/app/models/custom_role.rb:31-38` — permissões possíveis:

```ruby
PERMISSIONS = %w[
  conversation_manage
  conversation_unassigned_manage
  conversation_participating_manage
  contact_manage
  report_manage
  knowledge_base_manage
].freeze
```

Atribuição do role ao agente: `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb:14-16` (`associate_agent_with_custom_role` no create/update do agente). CRUD do role: `enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb`.

### 2.3 O que cada papel VÊ na listagem

**Administrator** — `app/services/conversations/permission_filter_service.rb:10-14`: `return conversations if user_role == 'administrator'` → vê **tudo da conta**, sem filtro de inbox nem time (na camada de permissão; o finder ainda aplica filtros de UI).

**Agent puro (sem custom role)** — `accessible_conversations` (`permission_filter_service.rb:18-25`):
```ruby
conversations_by_inbox = conversations.where(inbox: user.inboxes.where(account_id: account.id))
if user_team_ids.any?
  conversations_by_inbox.where('team_id IN (?) OR team_id IS NULL', user_team_ids)
else
  conversations_by_inbox
end
```
→ vê **TODAS as conversas das inboxes onde é membro** (`inbox_members`, ver `app/models/user.rb:99-100`), inclusive as atribuídas a outros agentes. Se estiver em times, vê conversas dos seus times OU sem time. **Este é o ponto-chave: agente "puro" já é um papel de triagem natural.**

**Agent com custom role** — overlay Enterprise (`enterprise/app/services/enterprise/conversations/permission_filter_service.rb:18-30`), hierarquia documentada no próprio código (`conversation_manage > conversation_unassigned_manage > conversation_participating_manage`):

| Permissão | Base da listagem |
|---|---|
| `conversation_manage` | `accessible_conversations` → igual ao agent puro (tudo das suas inboxes, respeitando times) |
| `conversation_unassigned_manage` | `mine UNION unassigned` (linhas 32-38: `assigned_to(user)` ∪ `unassigned`) |
| `conversation_participating_manage` | `accessible_conversations.assigned_to(user)` — **só as atribuídas a ele** (linha 26) |
| nenhuma das 3 | `Conversation.none` (linha 28) |

⚠️ Detalhe importante: para `conversation_participating_manage` a **listagem** usa só `assignee_id` — ser *participante* (`conversation_participants`) **não** coloca a conversa na lista padrão (mas dá acesso unitário, ver §2.4, e aparece na view "Participando", ver §4.3).

### 2.4 O que cada papel pode ABRIR (policy `show?`)

`ConversationPolicy#show?` (`app/policies/conversation_policy.rb:10-12`): `administrator? || agent_bot? || agent_can_view_conversation?`, onde `agent_can_view_conversation? = inbox_access? || team_access?` (linhas 16-18, 36-44) — agente puro abre qualquer conversa de inbox onde é membro, ou de time onde está.

Overlay `Enterprise::ConversationPolicy#show?` (`enterprise/app/policies/enterprise/conversation_policy.rb:2-11`): exige o `super` (inbox/team) **e**, se houver custom role:
- `conversation_manage` → tudo (linha 15-17);
- `conversation_unassigned_manage` → `unassigned_conversation? || assigned_to_user?` (linhas 19-23);
- `conversation_participating_manage` → `assigned_to_user? || participant?` (linhas 25-29) — **aqui participante CONTA** (`participant?` em `app/policies/conversation_policy.rb:50-52`).

### 2.5 `show?` controla TUDO (visibilidade == operabilidade)

- Endpoint unitário: `app/controllers/api/v1/accounts/conversations_controller.rb:182-185` (`authorize @conversation, :show?`).
- Todos os sub-recursos (mensagens, assignments, labels, participants): `app/controllers/api/v1/accounts/conversations/base_controller.rb:6-9` — **só** `authorize :show?`. Ex.: `messages_controller.rb` e `assignments_controller.rb` herdam dele sem checagem adicional.
- `Conversations::AssignmentService` (`app/services/conversations/assignment_service.rb`) **não tem gate de permissão**: quem consegue abrir a conversa consegue atribuí-la a **qualquer** agente (a descrição "assign to self" do role em `custom_role.rb:21` não é imposta no backend).
- Única exceção: `destroy?` exige administrator (`conversation_policy.rb:6-8`).

**Conclusão estrutural: não existe modo leitura.** Quem vê, opera. Não há permissão nativa "ver tudo mas operar só o seu".

---

## 3. Filtros adicionais do `ConversationFinder` (e divergências do fork)

`app/finders/conversation_finder.rb`:

1. **Inbox** — `set_inboxes` (117-122): usa `current_user.assigned_inboxes` (`app/models/user.rb:136-138`: admin → todas as inboxes da conta; agent → só as que é membro). Se `params[:inbox_id]` não vier, **não** filtra a query por inbox aqui — quem filtra por inbox é a camada de permissão (admin vê tudo; agent é filtrado pelo PermissionFilterService).
2. **Permissão** — `find_all_conversations` (156-166) aplica o `PermissionFilterService` em toda listagem.
3. **🔴 Time (CUSTOMIZAÇÃO DO FORK)** — `set_team` (128-141): se não veio `team_id` no request **e** o usuário não é admin **e** pertence a algum time → `@team_ids = current_user.teams.pluck(:id)`; `filter_by_team` (212-216) aplica `where(team_id: @team_ids)` — **EXCLUI conversas com `team_id IS NULL`**. Histórico: introduzido no baseline do fork (commit `c42a44632`, 26/01/2026) com `OR team_id IS NULL` em `filter_by_status`; o commit `5e298bdb3` (26/03/2026, "remover filtro de time duplicado") removeu o ramo com `IS NULL`, deixando o filtro estrito. Efeitos:
   - Um agente que pertença a QUALQUER time deixa de ver na lista todas as conversas sem time (que na Tozi é praticamente todas — disparos não setam team).
   - Diverge da camada de permissão (que inclui `OR team_id IS NULL` — `permission_filter_service.rb:21`). A interseção vence: **conversa sem time some da lista** para agente em time.
   - `current_user.teams.pluck(:id)` **não é escopado por conta** — times de outra conta vazam para o filtro.
4. **🔴 Gate de time no acesso unitário (CUSTOMIZAÇÃO DO FORK)** — `authorize_team_access` (`conversations_controller.rb:231-243`): não-admin recebe **403** ao abrir/operar conversa cujo `team_id` aponta para time do qual não é membro. Também `validate_team_param_access` (245-256).
5. **Status** — `filter_by_status` (206-210): default `open`. Conversas **pending não aparecem** na aba default — é o mecanismo do "limbo pending" (combinado com `Conversation#pending_status_allowed_by_inbox` e `determine_conversation_status`, `app/models/conversation.rb:324-337`).
6. **Tipo** — `filter_by_conversation_type` (180-192): `mention`, `participating`, `unattended`, `unread`. Nota: o ramo `participating` (184-185) **substitui** a relação por `current_user.participating_conversations` — bypassa o filtro de permissão e de inbox.
7. **Contagens** — `compute_all_counts` (245-274) roda **sobre o conjunto já filtrado por permissão** → os contadores das tabs são consistentes com o que o usuário vê.
8. Código morto: `perform_meta_only` (83-97) chama `set_count_for_all_conversations`, que **não existe** no finder (só em `app/services/filter_service.rb:110`) — levantaria `NoMethodError` se chamado; não há callers (`meta` usa `perform_counts_only`).

Outros consumidores do mesmo filtro de permissão:
- Custom views/folders: `app/services/conversations/filter_service.rb:31-36`.
- Conversas do contato: `app/controllers/api/v1/accounts/contacts/conversations_controller.rb:9`.
- Copilot (IA): `enterprise/app/services/captain/tools/copilot/search_conversations_service.rb:51-57` — a IA "enxerga" com os mesmos olhos do usuário que a invoca.

---

## 4. Frontend — tabs, views e real-time

### 4.1 Tabs Mine / Unassigned / All

`app/javascript/dashboard/constants/permissions.js:32-53` (`ASSIGNEE_TYPE_TAB_PERMISSIONS`), aplicado em `ChatList.vue:221-252` via `filterItemsByPermission`:

| Tab (pt_BR: Minhas / Não atribuídas / Todos) | Quem vê a tab |
|---|---|
| `me` | administrator, agent, e as 3 permissões de conversa |
| `unassigned` | administrator, agent, `conversation_manage`, `conversation_unassigned_manage` |
| `all` | administrator, agent, `conversation_manage`, `conversation_participating_manage` |

Curiosidades: role *participating* vê a tab "Todos" (mas o backend já restringiu a base a `assigned_to(user)`, então "Todos" ≈ "Minhas"); role *unassigned_manage* **não** vê a tab "Todos". O backend mapeia a tab em `filter_by_assignee_type` (`conversation_finder.rb:168-178`).

A role efetiva do front vem de `getUserPermissions`/`getUserRole` (`app/javascript/dashboard/helper/permissionsHelper.js:14-26`): se `custom_role_id` presente → role `custom_role` e usa as permissões serializadas da conta.

### 4.2 View "Não lidas" (custom do fork)

- Scope SQL: `Conversation.unread` (`app/models/conversation.rb:89-96`) — existe incoming criada após `agent_last_seen_at` (ou nunca visto). Comentário do fork nas linhas 86-88.
- Backend: `conversation_type=unread` → `filter_by_conversation_type` (`conversation_finder.rb:188-190`) — aplicado **depois** do filtro de permissão, então cada papel vê só as suas não-lidas.
- Rotas front: `conversation.routes.js:180-201` (`conversation_unread`, `conversation_through_unread`), meta `permissions: CONVERSATION_PERMISSIONS` (administrator, agent + as 3 permissões — linhas 5-11 do mesmo arquivo).
- Sidebar: `components-next/sidebar/Sidebar.vue:202-208` (item "Unread", abaixo de Menções).
- Heading: `ChatList.vue:373-375` → `CHAT_LIST.UNREAD_HEADING` ("Não lidas" em `i18n/locale/pt_BR/chatlist.json:13`).
- Real-time: `filterByUnread` (`store/modules/conversations/helpers.js:58-62`) mantém na view só `unread_count > 0`.
- Consequência prática: para a secretária com role restritiva, "Não lidas" NÃO contorna a permissão — uma resposta de lead numa conversa atribuída a corretor continua invisível para ela.

### 4.3 View "Participando"

`conversation_type=participating` (`conversation_finder.rb:184-185`) lista `current_user.participating_conversations` (via `conversation_participants`, `app/models/user.rb:96-97`). **Bypassa o PermissionFilterService** — é o único caminho de lista em que um corretor *participating* vê conversas que não estão atribuídas a ele (desde que seja participante).

Como alguém vira participante:
- Atribuição: `ParticipationListener#assignee_changed` (`app/listeners/participation_listener.rb:4-14`) — todo assignee vira participante **e permanece** após reatribuição (participantes acumulam).
- Menção em nota privada: `app/services/messages/mention_service.rb:69`.
- API: `app/controllers/api/v1/accounts/conversations/participants_controller.rb` (create/update/destroy por `user_ids`).

Para role *participating*, ser participante dá `show?` (policy linha 27-29) + aparece em "Participando" — **mecanismo nativo de "compartilhar" uma conversa com quem não é o assignee**.

### 4.4 Real-time (ActionCable)

`app/listeners/action_cable_listener.rb:197-215` (`user_tokens`): eventos de conversa/mensagem são enviados para **todos os membros da inbox + todos os admins** (caches `inbox:<id>:member_pubsub_tokens` e `account:<id>:admin_pubsub_tokens`). **O servidor não filtra por custom role** — o filtro é client-side: `applyRoleFilter` (`helpers.js:102-136`) espelha a regra do backend (admin/agent → tudo; `conversation_manage` → tudo; `unassigned_manage` → não-atribuída ou minha; `participating` → atribuída a mim). Ou seja, o payload chega ao browser do corretor mesmo de conversas que ele "não vê" — só não é exibido. (Vazamento teórico de dados no websocket para quem inspecionar o tráfego.)

---

## 5. Respostas diretas às perguntas

### 5.1 Por que a secretária não vê conversas atribuídas a corretores?

Caminhos possíveis no código (qual deles vale depende do cadastro dela em produção):

1. **Ela tem custom role com `conversation_participating_manage`** (o role "Corretor" #1 da Tozi, conforme STATE) → lista = `assigned_to(ela)` (`enterprise/.../permission_filter_service.rb:26`) e `show?` nega (policy linhas 25-29). Conversa atribuída a corretor é 100% invisível e inacessível.
2. **Ela tem `conversation_unassigned_manage`** (o role clássico de triagem) → vê não-atribuídas + as dela (linhas 32-38), mas a conversa do disparo **já nasce atribuída ao corretor** (`DisparoLeadJob` atribui) → quando o lead responde dias depois, a conversa reabre **já atribuída** → fora do conjunto dela. Esse cenário casa exatamente com o sintoma relatado.
3. **Ela não é membro da inbox 91** → agente puro só vê inboxes onde é membro (`permission_filter_service.rb:19`; `InboxPolicy#show?` em `app/policies/inbox_policy.rb:22-27`).
4. **Filtro de time do fork** — se ela pertence a algum time, a lista exclui conversas sem time (`conversation_finder.rb:212-216`), escondendo praticamente tudo que vem de disparo.
5. **Limbo pending** — conversa que reabriu como `pending` (inbox com bot) não aparece na aba default "Abertas" (`filter_by_status`, default `open`) para ninguém, independentemente de permissão.

### 5.2 Existe combinação NATIVA "ver tudo da inbox mas operar só o seu"?

**Não.** O modelo é: a mesma permissão que dá visibilidade dá operação. `show?` é o único gate de todos os endpoints de conversa (base_controller.rb:6-9), inclusive responder, atribuir, resolver. Não há `read-only`, não há separação ver/agir, e o `AssignmentService` nem restringe o alvo da atribuição. As opções nativas são discretas:
- `conversation_manage` (ou agent puro) = vê tudo das suas inboxes **e** opera tudo;
- `conversation_unassigned_manage` = vê/opera não-atribuídas + as suas;
- `conversation_participating_manage` = vê/opera só as suas (+ participadas via show?/"Participando").

### 5.3 Como dar à secretária visão de triagem sem promovê-la a administrator?

Opções nativas, da mais simples à mais cirúrgica:

1. **Agent puro (sem custom role) + membro da inbox 91 + fora de qualquer time** — vê TODAS as conversas da inbox (não-atribuídas e as dos corretores), tabs Mine/Unassigned/All completas, e não vê outras inboxes. É o desenho clássico do Chatwoot para triagem. Custo: ela também *pode operar* qualquer conversa (não há como impedir por permissão).
2. **Custom role com `conversation_manage`** — equivalente funcional ao item 1 na prática de conversas (a base é a mesma `accessible_conversations`), com a vantagem de poder negar `report_manage`/`contact_manage` etc. e de sinalizar semanticamente "triagem".
3. **`conversation_unassigned_manage`** — só funciona se o fluxo garantir que toda conversa que precisa de triagem esteja **não-atribuída** (ex.: a IA/automação zera assignee ao reabrir — é o que a AutomationRule #53 faz hoje, com o efeito colateral conhecido). Frágil para o caso "lead respondeu dias depois em conversa já atribuída".
4. **Participantes como concessão pontual** — adicionar a secretária como participante (API `participants_controller.rb` ou menção) dá `show?` + view "Participando" mesmo com role restritiva. Serve como mecanismo de exceção orquestrável (a IA pode adicionar/remover), mas não dá visão de lista "tudo da inbox".

Recomendação objetiva: **opção 1 ou 2** (idênticas em visibilidade de conversa), garantindo que ela esteja **fora de times** (por causa do filtro do fork §3.3) e que a aba/status considere `pending` quando a Clara religar.

### 5.4 Inbox members importam? Teams mudam a visibilidade? Participantes dão acesso?

- **Inbox members**: sim, é a fronteira primária para qualquer não-admin (lista: `permission_filter_service.rb:19`; abrir: `conversation_policy.rb:36-38`; o próprio `set_inboxes` do finder). Admin ignora (`user.assigned_inboxes` → todas).
- **Teams**: mudam em 3 lugares — (a) camada de permissão: conversa de time alheio é excluída, sem time é incluída (`permission_filter_service.rb:20-24`); (b) **fork**: finder esconde conversas SEM time de agentes que estão em times (`conversation_finder.rb:134-140` + `212-216`); (c) **fork**: 403 unitário em conversa de time alheio (`conversations_controller.rb:231-243`). Além disso, `team_access?` na policy dá acesso de abertura a conversas do seu time mesmo fora das suas inboxes (`conversation_policy.rb:40-44`).
- **Participantes**: dão `show?` **apenas** para custom role *participating* (`enterprise/conversation_policy.rb:25-29`); para agent puro/`conversation_manage` são irrelevantes (já veem); para `unassigned_manage` **não** dão acesso (gap: um participante com esse role não consegue abrir a conversa participada — `permits_unassigned_manage?` ignora `participant?`). Na lista padrão nunca contam; só na view "Participando" (que bypassa permissões).

---

## 6. Gaps e riscos identificados

1. **Sem modo leitura / sem separação ver×agir** — qualquer desenho "secretária vê tudo" implica "secretária pode mexer em tudo". Para a IA orquestradora vale o mesmo: visibilidade concedida = operação concedida.
2. **Filtro de time do fork esconde conversas sem time** (`conversation_finder.rb:212-216`) — bomba latente: colocar qualquer corretor/secretária num Team faz as conversas de disparo (team_id NULL) sumirem da lista. Diverge da camada de permissão (que inclui NULL). E `current_user.teams` não é escopado por conta.
3. **Role *participating* lista só por assignee** — participante não aparece na lista padrão (`enterprise/.../permission_filter_service.rb:26`), só em "Participando" e no acesso unitário. UX confusa para "compartilhamento".
4. **`conversation_unassigned_manage` ignora participant?** na policy (`enterprise/conversation_policy.rb:19-23`) — inconsistência entre roles.
5. **View "Participando" bypassa o PermissionFilterService** (`conversation_finder.rb:184-185`) — hoje inócuo (participações são concedidas), mas é um caminho de lista fora do modelo de permissão.
6. **Real-time não filtra por custom role no servidor** (`action_cable_listener.rb:197-215`) — payloads de conversas "invisíveis" chegam ao browser de todos os membros da inbox; o sigilo é só de UI.
7. **AssignmentService sem gate** — corretor *participating* pode reatribuir a conversa dele para qualquer um (e perdê-la de vista); a IA pode usar isso, mas humanos também.
8. **Limbo pending** é ortogonal a permissão: pending some da aba default para todos os papéis; com role restritiva o efeito é agravado (nem o contador unattended/unread da secretária acusa).
9. **Código morto**: `ConversationFinder#perform_meta_only` (`conversation_finder.rb:83-97`) chama método inexistente — quebraria se alguém o usasse.
10. **Auto-resolve/automations não respeitam visibilidade** — automação que zera assignee (#53) muda quem vê a conversa como efeito colateral; qualquer orquestração de atribuição é, na prática, uma orquestração de visibilidade.

---

## 7. Ganchos para a IA orquestradora

1. **Atribuir = dar visibilidade.** `POST /api/v1/accounts/:id/conversations/:display_id/assignments` (`assignments_controller.rb:3-11`) ou `Conversations::AssignmentService` — para roles *participating*, a atribuição é o interruptor de visibilidade do corretor. A IA que tria DEVE atribuir (ou desatribuir para devolver à fila da secretária `unassigned_manage`).
2. **Participantes como "cc".** `participants_controller.rb` / `conversation.conversation_participants.find_or_create_by(user_id:)` — concede acesso unitário + view "Participando" sem mudar assignee. Ideal para supervisão pontual (secretária acompanhar conversa de corretor) e reversível.
3. **Copilot tools já respeitam o modelo**: `search_conversations_service.rb:51-57` filtra pelo mesmo `PermissionFilterService` do usuário; `assign_conversation_service.rb:19-21` exige `conversation_manage` do usuário invocador (`base_service.rb:42-52`). Uma IA orquestradora "de sistema" deve rodar como admin/service user para enxergar tudo.
4. **Eventos de atribuição**: `ParticipationListener#assignee_changed` (Wisper) — qualquer listener novo pode reagir a mudanças de assignee (ex.: notificar secretária, mover card no kanban, recalcular fila).
5. **Scope `Conversation.unread`** (`conversation.rb:89-96`) — sinal pronto para a IA detectar "lead respondeu e ninguém viu" **sem depender da permissão de nenhum humano** (rodar account-wide via service role).
6. **Ponto de extensão limpo para um futuro papel "triagem vê tudo"**: o overlay `Enterprise::Conversations::PermissionFilterService#filter_by_permissions` é o único lugar a tocar para criar uma 4ª permissão (ex.: `conversation_view_all`) ou para incluir `participating_conversations` na base do role *participating* — mudança pequena e localizada (espelhar em `Enterprise::ConversationPolicy` e `helpers.js#applyRoleFilter` + `permissions.js`).
7. **Counts por papel já existem** (`compute_all_counts`) — a IA pode usar `GET /conversations/meta` impersonando perfis para auditar "o que cada um vê" (ex.: detectar conversas órfãs invisíveis para a equipe).

---

## 8. Questões em aberto (exigem dados de produção, fora do escopo de leitura de código)

- Qual é exatamente o cadastro da secretária na Account 6 (role, custom_role_id, inbox_members, teams)? Define qual dos caminhos do §5.1 é o vigente.
- Há Teams cadastrados/usados na Account 6? Se sim, o gap §6.2 está ativo.
- O role "Corretor" #1 tem só `conversation_participating_manage` ou acumula outras permissões?
- A AutomationRule #53 (zera assignee no `conversation_opened`) ainda está ativa? Ela interage diretamente com o modelo (devolve visibilidade à fila não-atribuída ao custo de perder o dono).
