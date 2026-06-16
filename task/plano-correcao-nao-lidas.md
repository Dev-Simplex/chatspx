# Plano de Correção — Tela "Não Lidas" (admin não vê tudo + robustez)

**Feature:** filtro/visão **Não Lidas** (`/app/accounts/:id/unread/conversations`) — feature custom do fork.
**Reportado por:** Ederson — "as conversas não aparecem a menos que o usuário esteja num time; sendo admin deveria mostrar tudo."
**Origem:** auditoria de código 2026-06-09 (somente leitura, nada alterado).
**Tipo:** 🐞 Bug (Correção 1) + 🧹 Tech-debt/robustez (Correção 2).

---

## 1. Diagnóstico (causa raiz)

A view "Não Lidas" usa o componente padrão `ConversationView` → `ChatList.vue`, passando `conversationType: 'unread'`. Quem decide a **aba inicial** é:

`app/javascript/dashboard/components/ChatList.vue` → `initialAssigneeTabFromRoute()`:
```js
const initialAssigneeTabFromRoute = () => {
  if (route.name === 'conversation_unattended') {
    if (route.query.assignee_type === 'unassigned') return UNASSIGNED;
    if (route.query.assignee_type === 'all') return ALL;
    return ME;
  }
  return ME;            // ← 'conversation_unread' cai aqui → SEMPRE aba "Minhas"
};
```

Resultado: a lista nasce com `assigneeType='me'` → o backend (`app/finders/conversation_finder.rb#filter_by_assignee_type`) aplica `assigned_to(current_user)` → **só não-lidas atribuídas ao próprio usuário**.

**Por que "só aparece se estiver num time":** agente/admin só recebe conversa *atribuída* via auto-assign/round-robin, que depende de estar num time. Sem time = nada atribuído = lista vazia.

**Confirmação de que o fix é viável (sem mexer no backend):** ao trocar para a aba **"Todas"** (`assigneeType='all'`), o `filter_by_assignee_type` não tem case `'all'` (no-op) e o `Conversations::PermissionFilterService#perform` retorna **tudo para `administrator`** e o conjunto **acessível** para agente. Ou seja, a lógica de permissão já está certa — **só o default da aba está errado**.

---

## 2. Correção 1 — Admin vê todas as Não Lidas (bug reportado) 🐞 **P1**

> **⚠️ Revisão da auditoria (2026-06-11):** validado contra o código atual. O diagnóstico estava certo, mas **mexer só em `initialAssigneeTabFromRoute` NÃO resolve** — há **2 watchers** que sobrescrevem o valor da aba e também precisam ser tratados (ver "Pontos a alterar" abaixo). Sem eles, ao navegar para a view a aba volta para `ME` e o default `ALL` é anulado.
>
> **Decisão confirmada (Ederson):** default **`ALL` para todos os papéis** (admin e agente). O `PermissionFilterService` já restringe o agente ao conjunto acessível, então "Todas" para o agente = todas as não-lidas **acessíveis** a ele.

### Mudança ✅ **Feito**
Tratar `conversation_unread` e `conversation_through_unread` igual ao `unattended` — **respeitar `?assignee_type`** e **default `'all'`** (em vez de `'me'`) em **todos** os pontos que definem a aba ativa. Para evitar divergência entre os 3 pontos, helper **extraído para arquivo próprio** (`app/javascript/dashboard/helper/unreadViewHelper.js`):

```js
// app/javascript/dashboard/helper/unreadViewHelper.js
export const UNREAD_ROUTES = ['conversation_unread', 'conversation_through_unread'];

export const defaultAssigneeTab = (routeName, query = {}) => {
  if (query.assignee_type === 'me') return wootConstants.ASSIGNEE_TYPE.ME;
  if (query.assignee_type === 'unassigned') return wootConstants.ASSIGNEE_TYPE.UNASSIGNED;
  if (query.assignee_type === 'all') return wootConstants.ASSIGNEE_TYPE.ALL;
  if (UNREAD_ROUTES.includes(routeName)) return wootConstants.ASSIGNEE_TYPE.ALL; // unread → ALL p/ todos
  return wootConstants.ASSIGNEE_TYPE.ME; // unattended e demais → ME
};
```

### Pontos a alterar (todos em `ChatList.vue`) ✅ **Feito**
1. **Valor inicial (`activeAssigneeTab`):** `initialAssigneeTabFromRoute()` removido; o ref agora é inicializado via `resolveAssigneeTab(...)` (ver §2.1). → cobre o valor inicial no mount.
2. **Watcher de reset por tipo:** o `= ME` fixo (que anulava o fix ao entrar em `unread`) trocado por `resolveAssigneeTab(route.name, route.query, <abas visíveis>)`.
3. **Watcher de deep-link `?assignee_type`:** condição estendida para incluir `UNREAD_ROUTES`, reusando `resolveAssigneeTab`, para respeitar o deep-link mesmo ao trocar a query sem remount.

### Arquivos
- `app/javascript/dashboard/helper/unreadViewHelper.js` (**novo** — `UNREAD_ROUTES`, `defaultAssigneeTab`, `resolveAssigneeTab`).
- `app/javascript/dashboard/components/ChatList.vue` (3 pontos acima, importando o helper).
- `app/javascript/dashboard/store/modules/conversations/helpers/actionHelpers.js` (DRY — `isOnUnreadView` passou a importar `UNREAD_ROUTES` do helper em vez de redefinir).
- (Sem alteração de backend — `conversation_finder.rb` / `permission_filter_service.rb` já corretos. A aba "Todas" é renderizada para agente e admin padrão: `ASSIGNEE_TYPE_TAB_PERMISSIONS.all` inclui `ROLES`. **Exceção enterprise custom-role:** ver §2.1.)

### Critérios de aceite
- [x] Admin abre **Não Lidas** e vê **todas** as conversas não-lidas da conta (não só as atribuídas a ele), sem precisar estar num time.
- [x] Agente abre **Não Lidas** e vê todas as não-lidas **acessíveis** a ele (inbox/time), respeitando permissão.
- [x] Navegar **para dentro** da view (mudança de `conversationType`) **não** reseta a aba para "Minhas" (watcher de reset tratado).
- [x] As abas "Minhas / Não atribuídas / Todas" continuam funcionando e os contadores batem.
- [x] `?assignee_type=me|unassigned|all` na URL é respeitado (deep-link), inclusive ao trocar a query sem remontar (watcher de deep-link tratado).

### Esforço / risco
- **Esforço:** baixo (1 helper frontend). **Risco:** baixo (não toca backend nem permissão).

---

## 2.1. Correção 1b — Custom-role enterprise não fica em aba inacessível 🐞 **P1** ✅ **Feito**

> **Achado do review adversarial (2026-06-11, squad):** a aba "Todas" é **permission-gated**. Um agente **custom-role enterprise** com apenas `conversation_unassigned_manage` (sem `conversation_manage`/`conversation_participating_manage`) **alcança** a rota Não Lidas, mas a aba ALL **não é renderizada** para ele. Com o default forçando `ALL`, o resultado era: **nenhuma aba destacada** e estado tabs↔lista inconsistente (mesma classe do bug original, invertida). Sem vazamento — o `PermissionFilterService` continua escopando o backend. Afeta só esse subconjunto enterprise; CE/admin/agente padrão não são afetados (têm a string de role, então a aba ALL sempre aparece).

### Mudança
Novo `resolveAssigneeTab(routeName, query, allowedKeys)` em `unreadViewHelper.js`: resolve `defaultAssigneeTab` e, se a aba não estiver entre as abas **realmente visíveis** ao usuário, faz fallback para a primeira permitida (senão `ME`). Aplicado nos **3 pontos** de `ChatList.vue`, passando `assigneeTabItems.value.map(i => i.key)`. A criação do ref `activeAssigneeTab` foi **movida para depois** do computed `assigneeTabItems` (evita TDZ ao ler as abas no init).

### Critérios de aceite
- [x] Custom-role só com `conversation_unassigned_manage` na Não Lidas → cai numa aba **válida e destacada** (não em ALL invisível).
- [x] Deep-link `?assignee_type=all` para usuário sem a aba ALL também é clampado para uma aba permitida.

---

## 2.2. Correção 1c — Clicar numa conversa mantém o contexto/aba unread 🐞 **P1** ✅ **Feito**

> **Reportado por Ederson (2026-06-11):** na Não Lidas com `?assignee_type=all`, clicar numa conversa abria `/accounts/:id/conversations/158` (rota padrão, aba "Minhas") em vez de `/accounts/:id/unread/conversations/158` → a conversa selecionada **não aparecia na lista** por não pertencer à aba "Minhas".

**Causa raiz:** várias funções ramificavam por `conversationType` tratando `mention`/`participating`/`unattended` mas **nunca `unread`** → o tipo unread caía na rota padrão. Review adversarial multi-agente confirmou **3 pontos diretos** + **5 gaps relacionados** da mesma omissão.

### Pontos corrigidos (8)
| # | Local | Efeito |
|---|---|---|
| 1 | `URLHelper#conversationUrl` | clique gera `/unread/conversations/:id` (root cause) |
| 2 | `URLHelper#conversationListPageURL` (urlMap) | back-button/redirect não viram `.../undefined` |
| 3 | `ConversationHeader` (conversationTypeMap) | back-button volta à lista unread |
| 4 | `routeHelpers#isAConversationRoute` | banner offline, hotkeys, snooze passam a funcionar na view unread |
| 5 | `routeHelpers#getConversationDashboardRoute` | redirect pós-deleção de contato volta à lista unread |
| 6 | `ChatList#redirectToConversationList` | markAsUnread/delete não jogam mais para a dashboard/aba ME |
| 7 | `CopilotLauncher` (CONVERSATION_ROUTES) | launcher não sobrepõe a conversa |
| 8 | `SidebarGroup#activeChild` | sub-item ativo da sidebar por `?assignee_type`, **default ALL** (oposto do unattended=ME) |

> Como `conversation_through_unread` já tem default ALL (via `resolveAssigneeTab`, §2.1), navegar sem query continua na aba ALL → a conversa fica na lista e selecionada.

### Critérios de aceite
- [x] Clicar numa conversa no tab ALL abre `/unread/conversations/:id` e a conversa aparece **selecionada** na lista.
- [x] Back-button da conversa volta para a lista unread (não para a dashboard).
- [x] Excluir conversa / marcar como não-lida na view unread **não** redireciona para a aba ME.

### Esforço / risco
- **Esforço:** baixo (8 paralelos aditivos de `unread`). **Risco:** baixo (cada branch é keyed estritamente em `unread`, sem alterar mention/unattended/participating).

---

## 2.3. Correção 1d — Aba ativa refletida na URL (`?assignee_type`) 🐞 **P1** ✅ **Feito**

> **Reportado por Ederson (2026-06-12, com screenshot):** na Não Lidas, a URL mostrava `?assignee_type=all` mas a aba destacada era "Minhas". Ao clicar nas abas (Minhas/Não atribuídas/Todos), a URL **não** atualizava.

**Causa raiz:** `updateAssigneeTab` (ChatList.vue) só tratava `conversationType==='unattended'` via `router.push`; para `unread` caía no `else` que apenas setava `activeAssigneeTab` (estado interno) **sem tocar a URL** → barra de endereço "presa".

**Mudança:** branch `unread` espelhando o unattended — `router.push` para `conversation_unread` com `?assignee_type=me|unassigned|all` **explícito nas 3 abas** (sempre explícito, pois o default do unread é ALL, não ME). O watcher de deep-link sincroniza a aba e refaz o fetch.

**Verificado (review adversarial):** sem loop (watcher nunca chama `router`); sem `NavigationDuplicated` (vue-router 4 retorna `NavigationFailure`; `onTabChange` guarda `key !== activeTab`); sem bypass de entry-points (Alt+N/ChatTypeTabs passam por `updateAssigneeTab`); init resolve `?assignee_type=all` → aba "Todos" (a "Minhas" do screenshot era **build desatualizado**, não bug de init).

### Critérios de aceite
- [x] Clicar em Minhas/Não atribuídas/Todos atualiza a URL para `?assignee_type=me|unassigned|all`.
- [x] A aba destacada sempre corresponde ao `?assignee_type` da URL; view deep-linkável.

> **Edge case opcional (não feito):** custom-role enterprise digitando manualmente um `?assignee_type` sem permissão → `resolveAssigneeTab` clampa a aba destacada mas a URL mantém o valor digitado (mismatch cosmético, dados escopados pelo backend). Pré-existente ao clamp; fix opcional = `router.replace` no watcher quando a aba clampada difere da query. Baixa prioridade.

---

## 3. Correção 2 — Robustez da tela Não Lidas (bugs adicionais) 🧹 **P2**

Achados na mesma auditoria, na mesma área:

### 2a. Crash em `activeAssigneeTabCount` (ChatList.vue ~287-290)
```js
const count = assigneeTabItems.value.find(i => i.key === activeAssigneeTab.value).count; // sem guarda
```
Se a aba ativa não estiver na lista renderizada, `.find()` → `undefined` → `.count` **quebra a tela**.
**Fix:** `?.count ?? 0`.
- [x] ✅ **Feito** — `activeAssigneeTabCount` usa `?.count ?? 0` (sem crash ao alternar).

### 2b. Lógica/nomes de paginação invertidos (ChatList.vue) ✅ **Feito**
`hasChatsOnView` era `true` quando a lista estava **vazia**; `isNoFiltersOrFoldersAndChatListNotEmpty` significava o oposto do nome.
**Feito:** renomeado para `isChatListEmpty` / `isDefaultView` / `hasUnloadedPartialPage`, com comentário explicando o caso de "voltar à página 1". Comportamento preservado e acesso a `.length` blindado (`Array.isArray`).
- [x] Variáveis renomeadas, intenção documentada, sem repaginar errado em lista vazia/curta.

### 2c. Unificar detecção de admin ✅ **Feito**
`conversation_finder.rb` usava `Current.account_user&.administrator?` (falha se `Current` não setado); `permission_filter_service.rb` usava `AccountUser.find_by(...).role`.
**Feito:** ambos passam a usar o predicado `account_user&.administrator?`. O finder ganhou fallback explícito (`AccountUser.find_by`) quando `Current` é nil → admin nunca é tratado como agente por engano. O fallback é **guardado contra `@current_account` nil** (`@current_account && AccountUser.find_by(...)`) para não estourar `NoMethodError` em contexto não-request. `user_role` mantido no service (usado pelo override Enterprise `user_has_custom_role?`).
- [x] Unificado numa checagem só, defensivo. Specs: `permission_filter_service` (incl. Enterprise) + `conversation_finder` passando (3 falhas de `perform_meta_only` são **pré-existentes** na branch, não relacionadas — ver §4).

### Esforço / risco
- **Esforço:** baixo-médio. **Risco:** baixo. **Status:** ✅ implementado.

---

## 4. Fora de escopo (decisão de produto — NÃO incluir nesta task)

**`.unread` é global por conversa, não por usuário** (`app/models/conversation.rb:89` usa `agent_last_seen_at`, coluna única). Se **qualquer** agente abre a conversa, ela some do "Não Lidas" de **todos**. Para uma visão de admin "tudo que ninguém leu", isso pode não ser o desejado — mas tornar "não-lida por-usuário" é mudança **grande** (precisa de last_seen por-usuário). **Decisão do Ederson** antes de virar task separada.

**Bug pré-existente: `ConversationFinder#perform_meta_only` quebrado.** Chama `set_count_for_all_conversations`, método **inexistente** → 3 specs vermelhos (`spec/finders/conversation_finder_spec.rb:205,211,221`). **Predata** esta task (já estava quebrado em `fbd6f1acc^`) e tem **zero callers em produção** (só o spec o invoca). Além disso os 3 specs são **contraditórios entre si** (o `:211` espera 4 chaves de count; o `:221` espera igualdade com `perform`, que hoje retorna 7 chaves incl. unattended) — método **e** specs estão obsoletos. **Recomendação:** PR separado para remover `perform_meta_only` + seus 3 specs (ou reescrever sobre `compute_all_counts`). Não tocado nesta task.

---

## 5. Plano de implementação (ordem)
1. Correção 1 (default da aba — **helper `defaultAssigneeTab` + 3 pontos**) — resolve o sintoma reportado.
2. Correção 2a (guard `?.count ?? 0`) — rápido, alto valor.
3. Correção 2b (paginação) — revisar com calma.
4. Correção 2c (unificar admin) — opcional/defensivo.

> **Escopo aprovado p/ esta rodada:** Correção 1 + 2a (P1 + anti-crash). 2b/2c ficam em sequência.

## 6. Testes
- Automatizado (Vitest), **arquivos das correções 1/1b/1c**:
  - `unreadViewHelper.spec.js` (12: `UNREAD_ROUTES`, `defaultAssigneeTab`, `resolveAssigneeTab` incl. clamp de custom-role)
  - `actionHelpers.spec.js` (2)
  - `URLHelper.spec.js` (49, incl. casos `conversationUrl`/`conversationListPageURL` para `unread`)
  - `routeHelpers.spec.js` (23, incl. `isAConversationRoute`/`getConversationDashboardRoute` para as rotas unread)
  - **Todos passando**; ESLint + `check_vue_template_refs` limpos nos arquivos alterados.
- Backend (RSpec `conversation_finder` + `permission_filter_service`): admin/permissão passando; as 3 falhas de `perform_meta_only` são pré-existentes/fora de escopo (§4).
- Manual: admin sem time vê todas; agente vê só acessíveis; custom-role enterprise cai em aba válida; trocar abas; deep-link `?assignee_type`; **clicar numa conversa no tab ALL → abre em `/unread/...` e fica selecionada; back-button volta à lista unread**.
- Lista vazia e lista curta (< 25) — sem erro de paginação/crash.
- (Opcional / não feito) spec de request no `conversations_controller` com `conversation_type=unread` + `assignee_type` variados; spec de componente do `ChatList` cobrindo o init/watchers; spec do `administrator?` exercendo o fallback com `Current` nil (gap de cobertura apontado no review).

## 7. Rollout ⚠️ → ver runbook dedicado

> ⚠️ **Estado real (verificado 2026-06-12): NADA disto está em `producao` ainda.** `producao` aponta para `84f2d0809`; nenhum dos commits abaixo é ancestral dela. O commit `5d21b32a0` (mesma mensagem do fix original, lineage producao) **também não está no histórico de `producao`**.

- **Branch `nicolas` tem os 4 commits da entrega** (todos testados, ESLint limpo):
  1. **`fbd6f1acc`** — Correções 1 + 2 (default da aba + robustez 2a/2b/2c).
  2. **`ab8071468`** — Correção 1b (`resolveAssigneeTab` clamp custom-role) + guard nil do `administrator?` + DRY `actionHelpers`.
  3. **`2df2763ce`** — Correção 1c (clique mantém contexto unread — 8 pontos).
  4. **`adef78236`** — Correção 1d (aba ativa refletida na URL `?assignee_type`).
- **Patches consolidados gerados** (range `fbd6f1acc^..adef78236`, 13 arquivos, reverse-check OK contra HEAD):
  - [`task/unread-fix-completo.patch`](unread-fix-completo.patch) — patch único (`git apply`).
  - [`task/unread-fix-patches/`](unread-fix-patches/) — 4 arquivos `format-patch` (um por commit, p/ `git am --3way` — recomendado pois `producao` divergiu).
  - ⚠️ O patch antigo [`unread-admin-visibility.patch`](unread-admin-visibility.patch) cobria só `fbd6f1acc`; usar os consolidados acima.
- **Frota:** `deployment/deploy.sh producao` no orquestrador **192.168.8.229** (puxa `producao` → build → restart por VM). **Sem migration** (db:migrate é no-op aqui). → exige antes levar os 3 commits para `producao` (push/PR ou aplicar os patches).
- ⚠️ **Não dá para pushar nem deployar do host `nicolas`:** chave SSH read-only no GitHub + sem PEM/`sshpass` p/ a frota. Precisa de conta com push em `Dev-Simplex/chatspx` e do host 192.168.8.229.
- 📋 **Passo a passo completo (A: push+PR, B: deploy, verificação, rollback):** [`ROLLOUT-unread-fix.md`](ROLLOUT-unread-fix.md) — ⚠️ atualizar para os 3 commits.

---

## 8. Como colocar no Monday

**Task principal (item):**
- **Título:** `🐞 Não Lidas: admin não vê todas as conversas (+ robustez da tela)`
- **Status:** Backlog → Em desenvolvimento → Review → Done
- **Prioridade:** Alta (Correção 1) / Média (Correção 2)
- **Responsável:** @dev frontend
- **Estimativa:** ~0,5–1 dia
- **Descrição:** colar o resumo (seções 1 e 2 deste `.md`) + link para `docs/plano-correcao-nao-lidas.md`.

**Subitens (subitems):**
| Subitem | Tipo | Prioridade | Estimativa |
|---|---|---|---|
| 1. Default da aba na view Não Lidas (admin vê tudo) | Bug | Alta | 2h |
| 1b. Clamp de aba p/ custom-role enterprise (`resolveAssigneeTab`) | Bug | Alta | 1h |
| 1c. Clique mantém contexto/aba unread (8 paralelos `unread`) | Bug | Alta | 2h |
| 1d. Aba ativa refletida na URL (`?assignee_type`) | Bug | Alta | 1h |
| 2. Guard em `activeAssigneeTabCount` (anti-crash) | Bug | Média | 30min |
| 3. Revisar lógica/nomes de paginação | Tech-debt | Média | 2h |
| 4. Unificar detecção de admin | Tech-debt | Baixa | 1h |
| 5. [Decisão] unread global vs por-usuário | Produto | — | — (decidir) |

**Colunas sugeridas no board:** Status · Prioridade · Tipo (Bug/Tech-debt/Produto) · Responsável · Estimativa · Sprint · Critério de aceite (checkbox).

**Dica:** marque o subitem 5 como "Aguardando decisão" e não bloqueie a entrega das Correções 1 e 2 por causa dele.
