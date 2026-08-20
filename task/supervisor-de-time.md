# Supervisor de Time

## Objetivo

Permitir que o **admin** marque um agente como **supervisor de um ou mais times** (na tela
Configurações → Agentes → Editar Agente). O supervisor passa a:

1. **Ver todas as conversas** dos times que supervisiona — mesmo as atribuídas a outros
   agentes, mesmo em caixas de entrada das quais ele não é membro, e mesmo com as flags de
   isolamento (`agent_conversation_isolation` / `agent_message_isolation`) ligadas.
2. **Ver os agentes** que compõem esses times (lista de membros).
3. **Gerenciar a composição** desses times: adicionar e remover agentes, e renomear um agente
   do time. Ver "F5" abaixo para o recorte exato do que ele pode e não pode.

## Decisões de design (fixadas antes de implementar)

| # | Decisão | Motivo |
|---|---------|--------|
| D1 | Supervisão é uma tabela nova (`team_supervisors`), **não** um `role` em `team_members` | Supervisionar ≠ ser membro. Virar membro mudaria contagem de time, canal do chat interno, auto-assign, visibilidade de etiquetas/respostas "de-time". |
| D2 | Supervisor vê conversas do time **independente de ser membro da caixa** | É o sentido literal de "ver todas as conversas do time". |
| D3 | Supervisor **age** na conversa como um membro do time (responder, assumir, encerrar) | A `ConversationPolicy` do fork é binária (`show?`). Um modo read-only exigiria guards novos em ~30 endpoints; fica **deferido**. |
| D4 | Supervisão **não** muda o sino/notificações | O sino foi deliberadamente estreitado para "só o assignee" (ver `bell-notifications-team-scoping-feature`). Supervisor de um time grande viraria spam. Assimetria intencional e comentada no código. |
| D5 | Sem feature flag | Inerte enquanto ninguém for marcado supervisor: `supervised_team_ids` vazio → todo caminho novo é short-circuit. |
| D6 | Permissão nova no front: `team_supervisor` em `AccountUser#permissions` | Reaproveita o `permissions:` das rotas (`permissionsHelper`) sem inventar um sistema paralelo. |
| D7 | Marcar supervisor é ação **exclusiva de admin** (`UserPolicy#update?` já é admin-only) | Senão um agente se autopromove. |

## Fases

### F1 — Fundação (backend: modelo + API de marcação)

- Migration `create_team_supervisors`: `team_id` (FK → teams, on_delete cascade),
  `user_id` (FK → users, on_delete cascade), timestamps, índice único `(team_id, user_id)`
  e índice em `user_id`.
- `app/models/team_supervisor.rb` — `belongs_to :team`, `belongs_to :user`, validação de
  unicidade por escopo, e validação de que o usuário pertence à conta do time.
- `Team`: `has_many :team_supervisors, dependent: :destroy_async`, `has_many :supervisors, through:`.
- `User`: `has_many :team_supervisions, class_name: 'TeamSupervisor', dependent: :destroy_async`,
  `has_many :supervised_teams, through: :team_supervisions, source: :team`, e
  `#supervised_team_ids_for(account_id)` com memoização por instância (escopo de request).
- `app/services/team_supervision.rb` (`module_function`, espelhando o padrão de
  `AgentMessageIsolation`):
  - `team_ids(user, account)` → `[]` para `AgentBot`/nil/conta ausente;
  - `supervises?(user, team_id, account)`;
  - `supervisor?(user, account)`;
  - `accessible_team_ids(user, account)` → membro ∪ supervisionado.
- `AgentsController#update`: aceita `supervised_team_ids` (array de ids), **só admin**,
  substitui o conjunto (add/remove diff) dentro de uma transação; ignora ids de times de
  outra conta. Também aceito no `create`? **Não** (mantém o create enxuto).
- `_agent.json.jbuilder`: expõe `supervised_team_ids`.
- `_team.json.jbuilder`: expõe `is_supervisor`; `TeamsController#index` pré-carrega os ids.
- `AccountUser#permissions`: acrescenta `'team_supervisor'` quando o usuário supervisiona
  ≥ 1 time da conta.
- Specs: modelo, service, controller de agentes (admin marca / agente recebe 403).

### F2 — Visibilidade das conversas (backend)

Todos os pontos abaixo usam `TeamSupervision` e devem ser **no-op** quando o usuário não
supervisiona nada.

- `Conversations::PermissionFilterService#accessible_conversations` — une as conversas dos
  times supervisionados ao conjunto acessível, **sem** passar pelo filtro de caixa.
- `ConversationPolicy#accessible_team_ids` — inclui os times supervisionados.
- `ConversationTeamAccessConcern#team_access_exempt?` — supervisor do time da conversa passa.
- `AgentConversationIsolation.hidden_from?` e `.exclude_hidden` — supervisor do time da
  conversa não é bloqueado (na versão SQL, `OR conversations.team_id IN (...)`).
- `AgentMessageIsolation` / `MessageFinder` — supervisor do time da conversa vê todas as
  bolhas. Verificar **todos** os call sites de `viewer_restriction_id` (preview da lista,
  histórico do contato, busca) e tratar cada um.
- `ConversationFinder#set_team` e `#force_team_queue_scope?` — usam
  `TeamSupervision.accessible_team_ids` no lugar de `current_user.teams`.
- Specs cobrindo: supervisor vê conversa de time em caixa que não é dele; supervisor abre
  conversa de outro agente com `agent_conversation_isolation` ON; agente comum continua
  bloqueado; admin inalterado.

### F3 — UI do admin (marcar supervisor)

- `EditAgent.vue`: campo multi-select "Supervisiona os times" (lista de times da conta),
  visível **só** quando a função selecionada é `agent` (admin já vê tudo). Envia
  `supervised_team_ids` no `agents/update`.
- `agents/Index.vue`: chip "Supervisor" na linha do agente que supervisiona ≥ 1 time.
- i18n `en` + `pt_BR` (`agentMgmt.json`).
- Garantir que o módulo `agents` da store repassa a chave nova.

### F4 — UI do supervisor (ver time + agentes)

- `teams/getters.js`: getter novo `getSupervisedTeams` e `getVisibleTeams` (membro ∪
  supervisionado). **Não** mexer em `getMyTeams` — ele governa visibilidade de etiquetas e
  respostas prontas "de-time".
- `ChatList.vue`: o filtro de time passa a usar `getVisibleTeams`.
- Rota `settings_teams_list`: `permissions: ['administrator', 'team_supervisor']`. Para o
  supervisor a tela lista **apenas** os times supervisionados, sem criar/editar/excluir time,
  com acesso à lista de membros.
- i18n dos rótulos novos.

### F5 — supervisor gerencia a composição do time

Decidido com o usuário em 2026-07-30. O supervisor **pode**: renomear um agente dos times dele,
adicionar agente ao time e remover agente do time. **Não pode**: excluir agente da conta,
convidar agente novo, redefinir senha, trocar função/disponibilidade, nem alterar supervisão.

| # | Decisão | Motivo |
|---|---------|--------|
| D8 | Renomear é global e isso foi **aceito conscientemente** | O nome do agente não é por time: renomear troca em toda a conta e em todo o histórico. Não há como limitar por time. |
| D9 | O **pool** de adição é a união dos membros dos times supervisionados | Escolha do usuário: não vaza o quadro completo de agentes. Consequência aceita: quem supervisiona um único time tem pool vazio, e a tela explica o porquê em vez de parecer quebrada. |
| D10 | `GET /agents` **não** é recortado no backend | Ele alimenta a store `agents` do app inteiro (menções, participantes, Kanban, ChatList, InboxView). Recortar ali deixava supervisor de time sem membros com lista vazia em tudo. O recorte é do **cliente**, só na tela de Agentes. Nunca foi controle de segurança: `UserPolicy#index?` é `true` para todo agente. |
| D11 | As guardas reais vivem nos **controllers**, não nas policies | A policy recebe a classe, não a instância — o recorte fino (alvo está num time meu? id está no pool?) precisa do registro concreto. |

Guardas: `authorize_supervisor_update` (whitelist de chave única `name`, alvo tem que estar num
time supervisionado, alvo nunca pode ser admin) e `authorize_supervisor_membership_change`
(só time supervisionado; quem entra tem que estar no pool; remover não tem restrição de pool).

Verificado por revisão adversarial: 48 asserções de ataque, incluindo chave proibida via corpo
JSON, wrapper `agent`, form-encoded e query string; autopromoção; id fora do pool como string e
de outra conta. Todas barradas com 401 e nenhuma escrita no banco.

## Fora de escopo (deferido)

- Relatórios escopados por supervisão.
- Kanban / funis do time supervisionado.
- Modo estritamente read-only na CONVERSA para o supervisor (D3) — a F5 abriu a gestão do
  time, mas dentro da conversa ele segue agindo como membro.
- Sino/notificações (D4).

## Validação

- `bundle exec rspec` nos arquivos tocados.
- `pnpm exec vitest run` nos specs de front tocados.
- Build de assets + restart do staging (`nicolas.chatspx.app`) e QA ao vivo.

---

## Estado: F1 ENTREGUE (contrato disponível para F2/F3/F4)

Já existe na árvore, verde e verificado:

- Tabela `team_supervisors` (migration aplicada nos bancos de **dev/staging e de test**).
- `TeamSupervisor`, `Team#supervisors`, `User#supervised_teams`,
  `User#supervised_team_ids_for(account_id)` (memoizado) e `#reset_supervised_team_ids_cache`.
- `TeamSupervision.team_ids(user, account)` / `.supervises?(user, team_id, account)` /
  `.supervisor?(user, account)` / `.accessible_team_ids(user, account)` — **use sempre este
  módulo**, nunca consulte `TeamSupervisor` direto.
- `PATCH /api/v1/accounts/:id/agents/:id` aceita `agent[supervised_team_ids][]` (admin-only).
- `_agent.json.jbuilder` → `supervised_team_ids`; `_team.json.jbuilder` → `is_supervisor`.
- `AccountUser#permissions` inclui `'team_supervisor'` para quem supervisiona ≥ 1 time,
  logo `currentAccount.permissions` no front já traz essa string.

> ⚠️ **Gotcha do banco de test desta árvore:** não rode `RAILS_ENV=test rails db:migrate` —
> o dump regenera um `db/schema.rb` defasado. O schema de test já está migrado; se precisar,
> use `db:migrate:up VERSION=`.

---

## Estado: F2 ENTREGUE (visibilidade das conversas)

Na árvore, verde e verificado. Tudo é **no-op** sem supervisor (nenhuma linha em
`team_supervisors` ⇒ `TeamSupervision.team_ids` vazio ⇒ cláusula/ramo não é sequer montado).

| Superfície | Arquivo | O que mudou |
|---|---|---|
| Lista/contagens | `conversations/permission_filter_service.rb` | `accessible_conversations` = (caixa ∩ time de membro) **∪** conversas dos times supervisionados, via `.or` — sem passar pelo filtro de caixa |
| Autorização | `conversation_policy.rb` | `accessible_team_ids` agora é `TeamSupervision.accessible_team_ids` (membro ∪ supervisionado) |
| Guard por time | `conversation_team_access_concern.rb` | supervisor do time da conversa entra em `team_access_exempt?` |
| Isolamento por agente | `agent_conversation_isolation.rb` | `hidden_from?` e `exclude_hidden` (versão SQL: `OR conversations.team_id IN (...)`) isentam o supervisor |
| Bolhas | `agent_message_isolation.rb` | método novo `restriction_id_for_conversation(conversation, user, account)` — **prefira-o** a `restriction_id_for_inbox` sempre que a conversa for conhecida |
| Bolhas (call sites) | `message_finder.rb`, `_conversation.json.jbuilder` (prévia e `last_non_activity`), `conversations/list_preloader.rb` (SQL), `conversation_finder.rb#filter_by_query` (SQL), `search_service.rb#apply_agent_isolation` | todos passaram a isentar o supervisor |
| Escopo de time da lista | `conversation_finder.rb` | `set_team` usa `scoping_team_ids` (membro ∪ supervisionado) |
| Busca | `search_service.rb` | mensagens e conversas alcançáveis = por caixa **OU** por time supervisionado |

Decisões tomadas no caminho (não estavam escritas na spec):

1. **A supervisão só AMPLIA, nunca estreita.** Em `ConversationFinder#scoping_team_ids`, se o
   agente não é membro de nenhum time o escopo continua vazio (sem filtro de time). Usar
   `accessible_team_ids` direto trancaria o supervisor-sem-time dentro do time supervisionado,
   que é o oposto da feature.
2. **A busca também foi alargada** (escopo de caixa de `SearchService`), não só o isolamento de
   bolha — senão o supervisor via a conversa na lista mas não a achava na busca.
3. **`Conversations::VisibilityService` NÃO foi espelhado** (é o espelho inverso do
   `PermissionFilterService`, mas governa o sino) — D4, e está comentado nos dois lados.

Fora do escopo de F2, ficam de pé (não regridem nada, só não enxergam supervisão):

- `ActiveAttendancesController#requester_context` usa `user.teams` → na aba "Em atendimento" as
  capacidades por linha (`open/assume/request`) ignoram supervisão.
- `Attachments::GalleryScopeBuilder` escopa por `user.inboxes` → a galeria de conta não mostra
  mídia do time supervisionado (o `exclude_hidden` dela já é ciente, o escopo de caixa não).
- `ConversationFinder#set_inboxes` usa `assigned_inboxes` → filtrar a lista por uma caixa da qual
  o supervisor não é membro devolve vazio (não alcançável pela UI: o seletor só lista as dele).
- `Conversations::PdfExportService` não aplica isolamento de agente (pré-existente, roda em job).

Specs novos: `spec/services/team_supervision_visibility_spec.rb` (28 ex.) e
`spec/controllers/api/v1/accounts/team_supervisor_access_spec.rb` (8 ex.).

> ⚠️ **Gotcha de spec:** `AssignmentHandler#ensure_assignee_is_from_team` zera o `assignee_id` no
> `create` se o dono ainda não é membro da caixa **e** do time. Crie os `inbox_member`/`team_member`
> antes e só então atribua (`conversation.update!(assignee: owner)`), senão o cenário perde o
> "dono humano" e o isolamento por agente nunca dispara.

---

## Estado: F3 + F4 ENTREGUES (UI de marcar supervisor + UI do supervisor)

Commit `858071efc`. Na árvore, verde, deployado no staging.

| Superfície | Arquivo | O que mudou |
|---|---|---|
| Marcar supervisor | `settings/agents/EditAgent.vue` | função "Supervisor" no seletor (é `agent` no backend — a diferença são os times) + multi-select "Supervisiona os times". Envia `supervised_team_ids`. |
| Chip na lista | `settings/agents/Index.vue` | linha do agente que supervisiona ≥ 1 time ganha o chip e os nomes dos times |
| Getters novos | `store/modules/teams/getters.js` | `getSupervisedTeams` e `getVisibleTeams`. **`getMyTeams` ficou intocado de propósito** — ele governa etiquetas/respostas "de-time", que continua sendo só de membro (D1) |
| Filtro de time da lista | `ChatList.vue` | passou a usar `getVisibleTeams` (membro ∪ supervisionado) |
| Tela de Times | `settings/teams/Index.vue` + `teams.routes.js` | rota abre para `team_supervisor`; supervisor vê **só** os times que supervisiona e pode expandir a lista de membros |
| Isolamento no front | `composables/useAgentIsolation.js`, `useTeamIsolation.js` e call sites (`Message.vue`, `KanbanCard.vue`, previews) | o supervisor deixa de ver o cadeado 🔒 nas conversas/bolhas dos times dele |

Decisões tomadas no caminho:

1. **"Supervisor" é rótulo de UI, não `role` do backend.** No banco continua `agent`; o
   seletor só existe para o admin ter onde marcar os times. Rebaixar Supervisor → Agente é a
   única troca que **limpa** `supervised_team_ids` (senão a supervisão seguia valendo sem
   aparecer em lugar nenhum); promover a admin ou a função personalizada **omite** a chave e
   preserva a configuração.
2. **Supervisor sem nenhum time marcado bloqueia o envio** — seria idêntico a agente comum,
   com o admin achando que configurou algo.

---

## Estado: F5 ENTREGUE (supervisor gerencia agentes e composição do time)

Commits `c4c3fc068` (backend) + `6f63ca1ba` (telas) + `a5f73b3fe` (decisões D8–D11 acima).
Na árvore, verde, deployado no staging. **Pendente: QA visual do usuário.**

### O contrato, em uma frase

O supervisor **renomeia** um agente dos times dele e **compõe** esses times (adiciona do pool,
remove sem restrição). Tudo o mais — excluir agente da conta, convidar, redefinir senha, trocar
função/disponibilidade/`custom_role_id`, alterar supervisão, criar/editar/excluir time —
continua **exclusivo de admin**.

### Backend (onde moram as guardas)

| Arquivo | O que mudou |
|---|---|
| `user_policy.rb` / `team_member_policy.rb` | `update?`/`create?`/`destroy?` passam a aceitar supervisor. **Só abrem a porta** — a policy recebe a CLASSE, não sabe quem é o alvo (D11) |
| `agents_controller.rb` | `authorize_supervisor_update` (`before_action`, barra **antes** de qualquer escrita): whitelist de chave única `name` → alvo dentro dos times supervisionados → alvo nunca administrador |
| `team_members_controller.rb` | `authorize_supervisor_membership_change`: só time supervisionado; quem ENTRA tem que estar no pool; `destroy` não tem restrição de pool |
| `team_supervision.rb` | `manageable_agent_ids(user, account)` — a união dos membros dos times supervisionados. Dois papéis: alvo permitido do rename **e** pool de adição |
| `enterprise/.../agents_controller.rb` | `associate_agent_with_custom_role` ganhou `return unless administrator?`. Ele roda depois do `super` e escrevia `custom_role_id` **incondicionalmente** — sem a guarda, o supervisor renomeando alguém (request sem a chave) **zerava** a função personalizada do alvo |

### Front (só não oferece o que seria recusado)

- `settings/agents/Index.vue` — abre para o supervisor com título "Agentes dos meus times",
  lista recortada **no cliente** (`agent.team_ids` × `getSupervisedTeams`), sem convidar e sem
  nenhuma ação de excluir. O botão de editar também some na linha de um **administrador**: o
  backend recusa com 401 e o admin aparece na lista quando é membro do time — sem esconder, o
  supervisor cairia num beco (abre o modal, renomeia, só descobre no erro).
- `settings/agents/EditAgent.vue` — modo supervisor mostra **só** o campo Nome (sem Função,
  Disponibilidade, times supervisionados nem "Redefinir a senha") e envia exatamente
  `{ id, name }`, batendo com a whitelist do backend. As regras de validação também encolhem:
  validar campo invisível travaria o Salvar por um valor que ele não pode nem ver.
- `settings/teams/Index.vue` — cada membro ganhou remover-do-time (com confirmação nominal) e
  cada time um "Adicionar agente" com checkboxes do pool.
- `settings/teams/helpers/supervisedTeamMembers.js` (**novo**) — o POST reusa `TeamsAPI.addAgents`;
  o DELETE mora aqui porque aquele client não tem `removeAgents`. Ambos devolvem a **promise
  crua do axios** de propósito: a store `teamMembers` embrulha em `new Error(error)` e perde o
  `response.status`, que é justamente como distinguimos "não autorizado" de falha qualquer.
- i18n `en` + `pt_BR`: `AGENT_MGMT.{HEADER,DESCRIPTION}_SUPERVISOR`, `AGENT_MGMT.LIST.404_SUPERVISOR`,
  `TEAMS_SETTINGS.MEMBERS.{FORBIDDEN,ACTION_ERROR,REMOVE.*,ADD.*}`.

### Gotchas que custaram caro (leia antes de mexer)

> ⚠️ **`Pundit::NotAuthorizedError` vira HTTP 401 neste fork**, não 403
> (`RequestExceptionHandler#render_unauthorized`). Ao tratar o erro no front, case **os dois**
> — é o que `memberActionError` faz. Sem isso o usuário lia "Request failed with status code 401".

> ⚠️ **A whitelist de chaves lê `params[:agent]`, e quem monta esse hash é o ParamsWrapper** —
> que só embrulha o **corpo**, e só quando a chave `agent` ainda não veio. Cada forma de request
> monta `params` diferente (corpo JSON, wrapper `agent` explícito, form-encoded, query string),
> então cada uma tem exemplo próprio no spec. A query string **não** entra no wrapper: o que
> segura ali é `agent_params` ler exclusivamente de `params[:agent]` — não mude isso.

> ⚠️ **Nunca recorte `GET /agents` no backend** (D10). Ele alimenta a store `agents` do app
> inteiro. O comentário no `index` e no `manageable_agent_ids` existe para impedir a recaída.

> ⚠️ **No modo supervisor, o `isLoading` da tela de Agentes espera também o fetch de TIMES.**
> O recorte depende deles: sem esperar, a tela pisca "não há agentes nos times que você
> supervisiona" antes de mostrar quem existe.

> ⚠️ **`loadedMemberTeamIds` (e não `membersOf(id).length`) é o que diz se a lista de membros já
> foi buscada** — um time legitimamente sem membros seria refetchado para sempre. E o DELETE
> responde `head :ok` (sem corpo), então a lista só reflete depois de um GET novo (`force: true`).

### Verificação (revisão adversarial T4 — relatório em `task/T4-revisao-adversarial-supervisor.md`)

48 asserções de ataque num spec de request dedicado, todas **barradas** com 401 e **nenhuma
escrita** no banco: alvo fora dos times supervisionados; alvo administrador; chave proibida
(`role`/`availability`/`custom_role_id`/`auto_offline`/`email`) por corpo JSON, wrapper `agent`,
form-encoded e query string; autopromoção e autosupervisão; auto-adição a time; id fora do pool
(inclusive como string e de outra conta); rotas admin-only; agente comum sem nenhum ganho; e
fluxo do admin idêntico ao de antes.

Números: vitest 7 arquivos / 68 testes / 0 falhas · rspec agentes+membros+modelo 82 ex. /
2 falhas (as **2 pré-existentes** de schema-thumbnail) · rspec policies+supervisão 85 ex. /
0 falhas · `spec/services/` 1884 ex. / 67 falhas / 18 pendentes (todas pré-existentes e sem
relação, idênticas antes e depois) · eslint 0 erros · rubocop 0 offenses.

### Conhecido e aceito (não são bugs)

- **Renomear é global** (D8): troca o nome em toda a conta e em todo o histórico.
- **"Adicionar do pool" COPIA, não move** — o agente passa a estar nos dois times. O texto de
  i18n fala em "mover agentes entre os times que você supervisiona"; é imprecisão de copy, não
  de comportamento.
- **Remover não tem restrição de pool**: o supervisor pode tirar qualquer membro de um time que
  supervisiona, inclusive um administrador. Tirar do time não reduz o poder de ninguém.
- **`POST|PATCH|DELETE /team_members` sem `user_ids` responde 500** (`validate_member_id_params`
  faz `params[:user_ids].map` e estoura em `nil`). **Pré-existente e idêntico para o admin** —
  não escreve nada, não é escalada. Documentado como exemplo no spec comparando os dois papéis.
- **"Redefinir senha" escondido para o supervisor é cosmético**: o botão chama o endpoint público
  do Devise (`auth/password`), não autenticado, e o link vai para a caixa do próprio agente.

---

## Briefing operacional (vale para TODOS os workers desta feature)

1. **Branch `nicolas`**, diretório `/home/chatwoot/chatwoot`. Vários agentes trabalham em
   paralelo na MESMA árvore: **toque somente nos arquivos da sua fase**. Se precisar de um
   arquivo de outra fase, avise o coordenador em vez de editar.
2. **NÃO commite, NÃO faça push, NÃO faça deploy.** O coordenador fecha isso no fim.
3. **NUNCA** rode `git checkout/restore/reset` amplo (`-- .`). A árvore tem trabalho não
   commitado de outras frentes. `git stash` também é proibido.
4. Migrations: esta feature só **cria tabela nova** (aditivo, reversível). Pode rodar
   `bundle exec rails db:migrate` e `RAILS_ENV=test bundle exec rails db:migrate`. Nada de
   `db:reset`, `db:drop`, `db:schema:load`.
5. Rode os specs dos arquivos que você tocou (`bundle exec rspec <arquivos>`). Se um spec
   já estava vermelho antes de você mexer, diga isso no relatório em vez de "consertar".
6. Estilo do fork: comentários em pt-BR explicando o **porquê**, no tom dos arquivos
   vizinhos. Siga `rubocop` (`bundle exec rubocop <arquivos>`) e o eslint do projeto.
7. Todo caminho novo tem que ser **no-op** quando ninguém é supervisor — nada de regressão
   para admin nem para agente comum.
8. No `worker_done`, informe: arquivos alterados, comandos rodados com o resultado real,
   decisões que você tomou por conta própria e o que ficou faltando.
