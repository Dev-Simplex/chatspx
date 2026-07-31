# T4 — Verificação integrada + revisão adversarial: supervisor gerenciando agentes

**Veredito: APROVADO COM CORREÇÕES.**

A postura de segurança está sólida: nenhum dos 8 ataques do enunciado conseguiu escalar
privilégio. A correção que fiz não é de segurança — é uma regressão funcional de alcance
app-wide que o recorte da API introduzia (aprovada pelo coordenador como opção C).

> Nota de status: neste fork `Pundit::NotAuthorizedError` vira **HTTP 401**
> (`RequestExceptionHandler#render_unauthorized`), não 403. Onde abaixo se lê "barrado",
> é 401 + **nenhuma escrita** (todo teste confere o estado no banco depois, não só o
> status).

---

## 1. Resultado dos 8 ataques

Rodei 48 asserções de ataque num spec de request dedicado (`type: :request`, token real
de auth, ida ao banco). Todas passaram. Depois dissolvi o arquivo temporário: as provas
que **não** existiam nos specs do T1 foram incorporadas em
`agents_controller_spec.rb` / `team_members_controller_spec.rb`; as duplicadas eu descartei.

| # | Ataque | Resultado |
|---|--------|-----------|
| 1 | Editar agente que **não está em nenhum time dele** | **BARRADO** (401, nome intacto). Testado com agente de outro time e com agente sem time nenhum. |
| 2 | Editar um **ADMIN** da conta | **BARRADO** (401), inclusive com o admin sendo membro do time supervisionado. |
| 3 | Trocar `role`/`availability`/`custom_role_id`/`auto_offline`/`email` **na mão** | **BARRADO** em todas as formas de request: corpo JSON, wrapper `agent` explícito, corpo form-encoded. Query string não escala (`agent_params` só lê de `params[:agent]`) — provado com `?role=` e `?custom_role_id=`. |
| 4 | Autopromoção / autosupervisão | **BARRADO**: promover-se a admin, supervisionar time novo, dar supervisão a subordinado, e auto-adicionar-se a time (supervisionado ou não) quando fora do pool. |
| 5 | Adicionar ao time alguém **fora do pool** via API | **BARRADO** no POST e no PATCH; barrado com id em **string** (form-encoded) e com usuário de **outra conta**; um único id inválido derruba o request inteiro. |
| 6 | Excluir agente / convidar / bulk_create / criar-editar-excluir time | **BARRADO** (todos admin-only). |
| 7 | Agente comum ganhou algo? | **NÃO.** `permissions` dele continua `['agent']` (sem `team_supervisor`), 401 em renomear, em membros de time, e o `GET /agents` dele segue igual ao de antes. |
| 8 | Fluxo do ADMIN idêntico? | **SIM.** Lista a conta inteira, troca função/disponibilidade, grava `custom_role_id`, atribui/retira supervisão, adiciona qualquer um a qualquer time (sem pool), remove de qualquer time. Admin que **também** supervisiona mantém poderes de admin. |

Extras que também passaram: supervisão de **outra conta** não dá poder nesta;
renomear **não zera** a supervisão do alvo (a guarda enterprise do `custom_role_id`
funciona); o guard é `before_action`, então recusa antes de qualquer escrita.

---

## 2. O que eu corrigi

### C1 (a única correção de peso) — o recorte do `GET /agents` regredia o app inteiro

**Problema.** `AgentsController#index` passou a filtrar a lista para supervisor não-admin.
Isso **não** era controle de segurança (`UserPolicy#index?` é `true` para qualquer agente,
antes e depois), mas `GET /agents` alimenta a store `agents` do **dashboard inteiro**:
`ConversationView`, `ConversationParticipant`, `KanbanIndex`, `InternalChatIndex`/
`InternalChatRedesign`, `ChatList`, `InboxView` — todos dão `dispatch('agents/get')`.
O supervisor, que também é um agente comum no dia a dia, perdia gente nessas telas.
**Pior caso, provado em teste:** supervisor de um time **sem membros** ⇒
`manageable_agent_ids = []` ⇒ lista **vazia** em todas elas (nem ele mesmo aparecia).

**Correção (opção C, aprovada pelo coordenador):**

- `agents_controller.rb#index` — recorte removido; volta a devolver a conta inteira para
  todo mundo, com comentário explicando por que não se deve recortar ali de novo.
- `settings/agents/Index.vue` — o recorte "só os agentes dos meus times" virou filtro de
  **cliente**, cruzando `agent.team_ids` (já exposto no jbuilder) com
  `teams/getSupervisedTeams` (getter que já existia).
- `settings/agents/Index.vue` — o `isLoading` da tela passa a esperar também o fetch de
  **times** no modo supervisor: sem isso a tela piscava "não há agentes nos times que você
  supervisiona" antes dos times chegarem.
- `TeamSupervision.manageable_agent_ids` **permanece** — continua sendo a fonte do POOL
  no `TeamMembersController` e do alvo permitido em `authorize_supervisor_update`. Só o
  `index` deixou de usá-lo (comentário no service avisa).
- Specs reescritos/adicionados: 3 exemplos do `agents_controller_spec` que dependiam do
  recorte viraram 5 (incluindo "supervisor de time vazio continua vendo a conta inteira"
  e "o payload expõe `team_ids` para a tela filtrar"); 4 exemplos novos no
  `agents/specs/Index.spec.js` (filtra pelos times supervisionados; admin nunca filtra;
  empty-state quando ninguém do time supervisionado está na lista; espera os times antes
  de declarar vazio).

**Confirmação pedida pelo coordenador (item 4):** varri a árvore por qualquer outra tela
que dependesse do recorte removido — nada. O único ponto que afirmava isso era um
comentário em `agents/Index.vue` ("a lista já vem filtrada pela API"), corrigido.
`teams/Index.vue` monta o pool a partir da store `teamMembers`, não da store `agents`.

### C2 — comentário mentiroso na rota de times

`teams.routes.js` dizia que o supervisor entra "em modo somente-leitura". O T3 tornou os
**membros** editáveis. Comentário corrigido.

### C3 — `TeamMemberPolicy` estava sem spec de policy

A `UserPolicy` ganhou spec no T1, a `TeamMemberPolicy` não. Criei
`spec/policies/team_member_policy_spec.rb` (12 ex.): admin permite, agente comum não,
supervisor permite, e **supervisor de time de outra conta não permite**.

### C4 — provas de formato de request incorporadas

O guard lê `params[:agent]`, e quem monta esse hash é o ParamsWrapper — que só embrulha
o **corpo**, e só quando a chave `agent` ainda não veio. Cada forma de request monta
`params` diferente, então cada uma virou exemplo próprio no `agents_controller_spec`
(wrapper explícito, form-encoded, query string em `role` e em `custom_role_id`,
`auto_offline`/`email`). No `team_members_controller_spec` entraram: id fora do pool como
**string**, usuário de **outra conta**, e auto-adição a time não supervisionado.

---

## 3. Achados que eu NÃO corrigi (e por quê)

1. **`PATCH|POST|DELETE /team_members` sem `user_ids` responde 500.**
   `validate_member_id_params` faz `params[:user_ids].map` e estoura em `nil`.
   **Pré-existente e idêntico para o admin** — confirmei rodando o mesmo request com
   token de admin (500 nos dois). Não escreve nada, não é escalada. Ficou documentado
   como exemplo no `team_members_controller_spec` comparando supervisor × admin.
   Consertar exigiria mexer no caminho do admin, que o ataque 8 manda manter idêntico.

2. **`task/supervisor-de-time.md` está desatualizado.** O doc (commit `f87c2d953`) descreve
   F4 como "tela **somente leitura**" e o supervisor vendo agentes em modo leitura. O T1–T3
   ampliou o escopo (renomear agente, compor membros de time). O doc é arquivo commitado e
   fora da minha fase — **fica para o coordenador** decidir se atualiza junto do commit.

3. **"Redefinir senha" escondido para o supervisor é cosmético.** O botão dispara
   `Auth.resetPassword`, que bate no endpoint público do Devise (`auth/password`) — não
   autenticado, e o link vai para a caixa do próprio agente. Esconder está certo pela UX,
   mas não é uma guarda: qualquer pessoa na internet pode chamar esse endpoint. Sem ação.

4. **Duas decisões de produto que registro sem tocar** (são coerentes, mas o usuário deve
   saber):
   - o supervisor pode **remover** qualquer membro de um time que supervisiona, inclusive
     um admin — remover não tem restrição de pool (é o desenho declarado);
   - "adicionar do pool" **copia**, não move: o agente passa a estar nos dois times. Os
     textos de i18n dizem "mover agentes entre os times que você supervisiona", o que é
     uma imprecisão leve de copy, não de comportamento.

---

## 4. Regressão nas 3 telas + qualidade de UI

- **i18n:** extraí as 90 chaves `$t(...)`/`t(...)` usadas nas 3 telas e resolvi cada uma
  contra `en` e `pt_BR`. **Zero chave crua** — as 4 que "faltavam" moram em `settings.json`
  (`PROFILE_SETTINGS.FORM.AVAILABILITY.*`, pré-existentes) e existem nos dois idiomas.
- **Erro 403/401 legível:** `memberActionError` traduz 401 **e** 403 para
  `TEAMS_SETTINGS.MEMBERS.FORBIDDEN` ("Você não tem permissão... só é possível mover
  agentes entre os times que você supervisiona") e cai em `ACTION_ERROR` no resto. O erro
  aparece **dentro** do diálogo, que fica aberto — não some numa toast.
- **Estado vazio do pool explicado:** três estados distintos e corretos —
  `SINGLE_TEAM` (supervisiona 1 time só ⇒ botão já nasce desabilitado **com a explicação
  ao lado**, sem precisar abrir diálogo vazio), `EMPTY_POOL` (todos já estão neste time) e
  `LOADING`. Bom padrão.
- **Tela do ADMIN intacta:** todo o bloco de membros (expandir, remover, adicionar) está
  atrás de `v-if="isSupervisorView"`, e criar/editar/excluir time atrás de `v-if="isAdmin"`.
  O admin não vê nada novo. Coberto por spec dos dois lados.
- **Modal de edição no modo supervisor:** só o campo Nome; sem `select` de função, sem
  disponibilidade, sem times supervisionados, sem "Redefinir senha"; as regras de validação
  também encolhem (validar campo invisível travaria o Salvar). O payload enviado é
  exatamente `{ id, name }` — verificado em spec.
- **APIs de componente conferidas:** `Dialog` expõe mesmo `open()`/`close()` +
  `disableConfirmButton`/`isLoading`; `Checkbox` usa `defineModel` + emit `change`.
  O stub do spec espelha o contrato real.

---

## 5. Números (rodados de verdade, nesta árvore)

| Comando | Resultado |
|---|---|
| `npx vitest run .../settings/agents/ .../settings/teams/ .../store/modules/specs/teams/` | **7 arquivos, 68 testes, 68 passando, 0 falhas** |
| `rspec agents_controller_spec + team_members_controller_spec + spec/models/team_supervisor_spec.rb` | **82 exemplos, 2 falhas** — as **2 pré-existentes** de schema/thumbnail (`conform_schema`: `thumbnail` vazio não é URI válida), nas linhas 22 e 525. **Não aumentei.** |
| `rspec spec/models/team_supervisor_spec.rb + spec/policies/{user,team_member}_policy_spec + spec/services/team_supervision*_spec + team_supervisor_access_spec` | **85 exemplos, 0 falhas** |
| `rspec spec/services/` | **1884 exemplos, 67 falhas, 18 pendentes** — todas pré-existentes e **não relacionadas**: 13 arquivos (pin/forward service, `spx/ai_config`, WAHA, LeadSquared, CSAT, `pdf_data_resolver`, `account_deletion`...). Verifiquei um a um: **nenhum** dos 13 referencia supervisão, as policies ou os controllers alterados; as mensagens de erro são de Redis/GlobalConfig/dispatcher/contagem de conversa. Rodei **duas vezes**, antes e depois da minha correção: **mesmos 1884/67/18 e os mesmos 13 arquivos** — a correção não moveu nada. |
| `npx eslint` (9 arquivos .vue/.js alterados) | **0 erros**, 2 warnings pré-existentes (`no-dynamic-keys`, em linhas que ninguém tocou) |
| `bundle exec rubocop` (11 arquivos .rb alterados) | **11 arquivos, 0 offenses** |
| Spec adversarial dedicado (temporário, já dissolvido nos specs definitivos) | **48 exemplos, 0 falhas** |

Nada foi commitado. **Não** rodei `assets:precompile` nem reiniciei serviço — o deploy é do
coordenador.

---

## 6. Arquivos que EU (T4) alterei

- `app/controllers/api/v1/accounts/agents_controller.rb` — recorte do `index` removido
- `app/services/team_supervision.rb` — comentário (o método permanece, agora com 2 papéis)
- `app/javascript/dashboard/routes/dashboard/settings/agents/Index.vue` — filtro no cliente + guarda de loading
- `app/javascript/dashboard/routes/dashboard/settings/agents/specs/Index.spec.js` — +6 exemplos
- `app/javascript/dashboard/routes/dashboard/settings/teams/teams.routes.js` — comentário
- `spec/controllers/api/v1/accounts/agents_controller_spec.rb` — index reescrito + 8 ataques novos
- `spec/controllers/api/v1/accounts/team_members_controller_spec.rb` — 3 ataques novos
- `spec/policies/team_member_policy_spec.rb` — **novo**
