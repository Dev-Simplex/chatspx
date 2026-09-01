# Verificação adversarial — Escolher quais agentes participam de cada isolamento

**Data:** 19/08/2026 · **Branch:** `nicolas` · **Commits sob exame:** `8aec9690c` (dados/API),
`7ae443c7d` (UI), `bf4b8c749` (leitura)
**Método:** leitura dos três diffs + execução dos specs existentes + 11 sondas próprias
(`rspec` descartável, já removido) + `rubocop`/`eslint`/`vitest`.

## Veredito curto

A feature **entrega o que foi pedido** e — o que mais importava — **entra inerte**: com a tabela de
exceções vazia a SQL dos quatro pontos de leitura é literalmente a de antes (medido, §4). Os dez
critérios passam. **Nenhum defeito de vazamento foi encontrado no caminho principal.**

Achei **2 defeitos de regra** (um deles um vazamento estreito e real), **1 problema de performance**
e **4 pontas soltas**. Nada disso bloqueia o deploy em staging; o D-1 deve ser resolvido antes da
frota.

---

## 1. Os 10 critérios de aceite

| # | Critério | Veredito | Evidência |
|---|---|---|---|
| 1 | Toggle desligado: nenhuma lista aparece, nada muda | **PASSA** | `Settings.vue:889` e `:906` — o slot `#editor` está sob `v-if="teamMessageIsolation"` / `v-if="agentMessageIsolation"`; `SettingsToggleSection` só renderiza a faixa com `v-if="$slots.editor"`. A busca de membros também é represada (`Settings.vue:468`: `if (!inboxId \|\| !this.showIsolationParticipants) return`). Sonda P10: com as duas flags OFF e uma exceção gravada, o agente vê tudo — igual a hoje |
| 2 | Ligar pela 1ª vez numa caixa existente: todos marcados, comportamento de hoje | **PASSA** | `_inbox.json.jbuilder:28-29` deriva a lista (`isolation_candidate_user_ids - exceções`); sem exceção devolve todos os membros não-admin. Spec `inboxes_controller_spec.rb` "exposes every non admin member as participant when there is no exemption". Payload antigo em cache → `null` → tela mostra todos marcados e **não manda a chave** (`Settings.vue:436-438`, `:608-621`) |
| 3 | Desmarcar: passa a ver os outros na lista, na conversa, no histórico do contato **e na busca** | **PASSA** | Sonda P7, ponta a ponta, nos quatro pontos: `finder_ve_alheia=true preview=alheia conv_finder_achou=true busca_achou=true`. E o agente **não** isento no mesmo inbox continua sem ver (`finder_ve_minha=false busca_achou_minha=false`). O histórico do contato usa `ListPreloader` + `_conversation.json.jbuilder` (`contacts/conversations_controller.rb:16`), ambos cobertos |
| 4 | Remarcar devolve o isolamento | **PASSA** | `sync_isolation_exemptions` (`inboxes_controller.rb:132-141`) apaga o que saiu de `exempt_ids`; spec "gives the isolation back when the agent is checked again" |
| 5 | Vale para os dois, de forma independente | **PASSA (com ressalva D-2)** | `isolation_type` entra na chave única; specs "does not touch the other isolation" e "ignores an exemption of the agent isolation". **Ressalva:** um supervisor de time **não pode** ser isentado do isolamento de TIME pela tela (ver D-2) |
| 6 | O isento não ganha nada além de leitura | **PASSA** | Sonda P5: `InboxPolicy#update? = false`, `administrator? = false` para o agente isento. A tabela só é lida em 4 lugares (grep completo em §3) — nenhum é policy/permissão. O 3º toggle (`AgentConversationIsolation`) usa só `viewer_restriction_id`, que **não** foi tocado: a exceção de mensagem não abre conversa bloqueada |
| 7 | Tirar o agente da conta remove a exceção | **PASSA** | Sonda P9, nos três caminhos: `Agents::DestroyJob` → `antes=2 depois=0`; `Inbox#remove_members` → `sobrou=0`; `user.destroy` → `sobrou=0`. Os três chegam no `InboxMember after_destroy` (`inbox_member.rb:48-50`) ou no `dependent: :destroy` do `User` |
| 8 | Recarregar traz as marcações salvas | **PASSA** | A lista é derivada no jbuilder a cada `GET`, não guardada no cliente; spec do controller confere o `participant_ids` no corpo do `PATCH` |
| 9 | Specs cobrindo os 4 cenários pedidos | **PASSA** | (a) exceção lê o escondido: `agent_message_isolation_spec.rb`, `message_finder_spec.rb`, `search_service_spec.rb`, `list_preloader_spec.rb`; (b) não-exceção segue sem ver: idem; (c) lista vazia = regra antiga: `conversation_team_message_isolation_spec.rb:53`; (d) job sem `Current.user`: `conversation_team_message_isolation_spec.rb:63` **e** `:71` (com exceção gravada). 272 exemplos nos arquivos de isolamento |
| 10 | `rubocop` e `eslint` limpos | **PASSA** | Saídas coladas em §5 |

---

## 2. As pegadinhas do .md, atacadas uma a uma

### 2.1 "Administrador some da lista e continua isento?" — **SIM, mas o texto da tela mente no card de time**

Some: `IsolationParticipants.vue:51` filtra `role === 'administrator'` fora de `candidates`, e
`Inbox#isolation_candidate_user_ids` (`inbox.rb:111`) filtra `role: :agent` no servidor — id de admin
mandado na mão é ignorado (spec "never turns the administrator into an exemption").

Continua isento **do isolamento por agente**: `viewer_restriction_id` devolve `nil` para admin
(`agent_message_isolation.rb:50`).

**Mas** o `.md` partiu de uma premissa errada ("ele já é isento nas duas regras"). Medido (sonda P2,
controle): com `team_message_isolation` ON, **o administrador NÃO é isento** — ele não vê a mensagem
de outro time. A implementação acertou em não mexer nisso ("Mudar o que administrador enxerga" está
fora de escopo, e o `team_message_isolation.rb:14-18` documenta a decisão). O que ficou errado é a
**cópia da tela**: `ADMIN_NOTE` = "Administradores não aparecem aqui: eles nunca são isolados"
aparece nos **dois** cards e é falsa no de time. Ver **D-3**.

### 2.2 "Supervisor de time continua isento sem regra duplicada?" — **SIM, sem duplicação; mas a tela erra no card de time**

Não há regra duplicada: `TeamSupervision` só é consultada onde já era, em
`AgentMessageIsolation.restriction_id_for_conversation` (`agent_message_isolation.rb:67-74`) e nas
cláusulas `supervised` do finder/preloader/search. A tarefa C **explicitamente não grava** exceção
para supervisor (`IsolationParticipants.vue:98-100` sobe o supervisor sempre como participante) —
decisão certa, é o que impede esticar uma isenção por-time para a caixa inteira.

**Defeito:** o selo `ALWAYS_EXEMPT` ("isento sempre") aparece **nos dois cards**, e no de TIME é
falso. Medido (sonda P8): `supervisor_ve_msg_de_outro_time=false`,
`TeamMessageIsolation.exempt?(supervisor)=false`. Ver **D-2**.

### 2.3 "Resolveu no ponto único ou saiu editando os quatro pontos na mão e esqueceu um?" — **Editou três na mão, mas de propósito, e não esqueceu nenhum**

O `.md` supôs que um `return nil if exempt?` em `restriction_id_for_inbox` cobriria os quatro. **A
suposição do `.md` está errada** e a implementação está certa: `conversation_finder`,
`list_preloader` e `search_service` **nunca chamaram** `restriction_id_for_inbox` — eles chamam
`viewer_restriction_id` e resolvem a flag do inbox **por linha, no SQL**, porque a listagem mistura
caixas. Grep completo dos consumidores:

```
_conversation.json.jbuilder:108,139  → restriction_id_for_conversation   (coberto pelo exempt?)
message_finder.rb:41                 → restriction_id_for_conversation   (coberto pelo exempt?)
search_service.rb:153,160            → viewer_restriction_id + exempt_inbox_ids
list_preloader.rb:63,80              → viewer_restriction_id + exempt_inbox_ids
conversation_finder.rb:272,306       → viewer_restriction_id + exempt_inbox_ids
agent_conversation_isolation.rb:22   → viewer_restriction_id (3º toggle, NÃO tocado — correto)
```

Nenhum ponto ficou de fora — **inclusive a busca**, que era o que mais escapava: sonda P7,
`busca_achou=true` com exceção e `false` sem. E a exceção **não** vazou para o 3º toggle.

### 2.4 "O filtro de TIME continua valendo com `Current.user` nulo (job)?" — **SIM, provado**

`TeamMessageIsolation.exempt?` (`team_message_isolation.rb:34-40`) devolve `false` para qualquer
coisa que não seja `User`, então `apply?` mantém o filtro. Provado por dois specs próprios:

- `conversation_team_message_isolation_spec.rb:63` — "keeps the filter when there is no Current.user"
- `conversation_team_message_isolation_spec.rb:71` — **o teste que importa**: mantém o filtro no
  caminho de job **mesmo com uma exceção gravada** para aquele agente. Passa.

Também confirmei o ciclo de vida do `Current.user` no request: `application_controller.rb:17` seta
para **todo** controller não-devise (nil quando não há sessão) e `request_exception_handler.rb:23`
faz `Current.reset` no `ensure`. Ver **D-6** para o resíduo do lado do Sidekiq.

### 2.5 "Exceção some quando o agente sai da conta?" — **SIM, nos três caminhos**

Sonda P9, medido: `Agents::DestroyJob` (o caminho real de "tirar da conta") →
`inbox_members.destroy_all` → `after_destroy` → `antes=2 depois=0`. Remover só da caixa
(`Inbox#remove_members`, também `destroy_all`) → `sobrou=0`. Apagar o `User` de vez → `sobrou=0`
(via `dependent: :destroy` + FK `ON DELETE CASCADE`).

---

## 3. Risco nº 1: lista vazia reproduz o comportamento ANTIGO?

**SIM — verificado no nível da SQL gerada, não só do comportamento.** Sonda P3, com zero exceções:

```
P3 finder_tem_excecao=false
P3 preloader_tem_excecao_agente=false
P3 preloader_team_clause=AND (c.team_id IS NULL OR m.team_id IS NULL OR m.team_id = c.team_id)
```

A cláusula de time saiu **idêntica, caractere a caractere**, à que estava no
`list_preloader.rb` antes do commit. As três cláusulas de exceção são strings interpoladas que só
existem quando o array não é vazio (`conversation_finder.rb:294`, `list_preloader.rb:100,113`), e o
`search_service.rb:160` faz `isolated_inbox_ids -= []`, um no-op. Nos dois pontos que passam pelo
serviço, `exempt?` devolve `false` e o `return nil` não dispara.

Auditei também a inversão participantes↔exceções nos dois sentidos:

- Migração entra sem nenhuma linha → todos participam → isolamento intacto. ✔
- `PATCH` sem a chave **não mexe em nada** (`inboxes_controller.rb:123`: `next unless
  permitted_params.key?`) — spec "leaves the exemptions alone when the key is absent". ✔
- Caminho **multipart real do front** (o que a tela usa de verdade, não o `as: :json` dos specs):
  sonda P6 mandou `agent_message_isolation_participant_ids[]=""` e o servidor gravou exceção para os
  dois agentes, devolvendo `participant_ids=[]`. "Desmarquei todo mundo" chega como tal, e não como
  "não falei de lista nenhuma". ✔ (`channelActions.js:16-24`)
- Auditei os **16 outros pontos** que chamam `inboxes/updateInbox`: nenhum manda array no nível de
  topo com `formData: true`, então a mudança do `buildInboxData` não regride nada. ✔

---

## 4. Defeitos encontrados

### D-1 · Agente com exceção promovido a administrador vira o único "admin" que burla o isolamento de time — **MÉDIO, corrigir antes da frota**

**Onde:** `app/models/inbox.rb:111` (`isolation_candidate_user_ids` filtra `role: :agent`),
`app/services/team_message_isolation.rb:34` (`exempt?` não olha o papel).

**Medido (sonda P2):**

```
P2 admin_ve_oculta=false        <- administrador normal NÃO vê msg de outro time (comportamento de hoje)
P2 promovido_ve_oculta=true     <- ex-agente com exceção, agora admin, VÊ
P2 excecao_ainda_existe=true
P2 aparece_como_candidato=false <- e sumiu da tela, então o admin não enxerga nem remove a linha
```

Promover um agente que tinha exceção de `team_message` dá a ele uma visibilidade que **nenhum outro
administrador tem**, em silêncio, e a linha desaparece da tela no mesmo movimento. Ela é limpa
sozinha só se alguém abrir aquela caixa e salvar aquele card de novo (aí o promovido não é mais
candidato e o `scope.where.not(user_id: exempt_ids).destroy_all` a apaga).

**Proposta (não apliquei — é defeito de regra):** filtrar por papel na leitura, que fecha o buraco
sem depender de nenhum evento. Em `User#isolation_exempt_inbox_ids_for` (`user.rb:179`), acrescentar
o join que já existe no `isolation_candidate_user_ids`:

```ruby
inbox_isolation_exemptions.joins(:inbox)
                          .where(inboxes: { account_id: account_id }, isolation_type: isolation_type)
                          .where(inbox_id: Inbox.where(account_id: account_id))   # já filtrado acima
                          .pluck(:inbox_id)
# + um `return [] if account_users.find_by(account_id:)&.administrator?` no topo do método
```

O guarda no topo (`return [] if ... administrator?`) é o de uma linha e resolve os dois isolamentos
de uma vez. Alternativa complementar: `AccountUser after_update` apagando as exceções quando `role`
muda para `administrator`.

### D-2 · No card de TIME, o supervisor aparece como "isento sempre" — e não é — **MÉDIO**

**Onde:** `IsolationParticipants.vue:98-100` (força supervisor como participante),
`:228-232` (selo `ALWAYS_EXEMPT`), `en/inboxMgmt.json:763,767`.

**Medido (sonda P8):** `supervisor_ve_msg_de_outro_time=false`,
`TeamMessageIsolation.exempt?(supervisor)=false`.

O componente é o mesmo nos dois cards e não sabe de qual isolamento está falando. No card de agente o
selo é (quase) verdade; no de time é **falso**, e o efeito colateral é que o supervisor de time é o
único agente da caixa que **não dá para isentar** do isolamento de time — furando o critério 5 para
esse recorte de gente.

**Proposta:** passar `isolation-type` como prop. Com `'agent_message'`, mantém o comportamento atual;
com `'team_message'`, o supervisor vira uma linha normal, com caixinha, e sai do
`supervisorAgents.map` do `updateParticipants`.

### D-3 · "Administradores nunca são isolados" é falso no card de time — **BAIXO (cópia)**

**Onde:** `en/inboxMgmt.json:766` (`ADMIN_NOTE`), renderizado em `IsolationParticipants.vue:252`.

O `.md` afirmava que o admin já é isento das duas regras; medido, ele **não** é isento do isolamento
de time (sonda P2, `admin_ve_oculta=false`) — e isso é o comportamento de hoje, preservado de
propósito e documentado em `team_message_isolation.rb:14-18`. A implementação acertou; a frase da
tela é que herdou a premissa errada.

**Proposta:** junto com o `isolation-type` do D-2, trocar a nota no card de time por algo como
"Administradores não aparecem aqui — para tirar o isolamento de time de um administrador, desligue a
chave da caixa". E, no card de agente, o selo do supervisor idealmente diria "isento nas conversas do
time que supervisiona": a isenção dele é por time
(`agent_message_isolation.rb:71`: `TeamSupervision.supervises?(user, conversation.team_id, ...)`),
não pela caixa inteira — `restriction_id_for_inbox` sozinho **não** isenta supervisor.

### D-4 · N+1 no `GET /inboxes` — **MÉDIO (performance), a mensagem do commit diz o contrário**

**Onde:** `app/models/inbox.rb:111-116`, chamado por `_inbox.json.jbuilder:28-29`.

**Medido (sonda P1b), 6 caixas com membros:**

```
P1b inboxes=6 queries_nao_cache=6
P1b account_users_queries=6
```

O `includes(:inbox_members, :inbox_isolation_exemptions)` do `inboxes_controller.rb:19-21` resolve
duas das três consultas, mas o `account.account_users.where(user_id: member_ids, role: :agent)` é
**uma consulta por caixa**. A lista de caixas é carregada em todo boot do dashboard; numa conta com
30 caixas são 30 consultas novas por carregamento.

**Proposta:** resolver os agentes da conta uma vez só. Ou memoizar no `Account`
(`account.agent_user_ids`), ou o controller montar `Set` uma vez e o jbuilder passar adiante.

### D-5 · O bloco novo de i18n está em português dentro do `en.json`, e o `pt_BR` não tem o bloco — **BAIXO**

**Onde:** `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json:758-770`.

Todas as chaves vizinhas do arquivo estão em inglês (`"AGENT_MESSAGE_ISOLATION_SUB_TEXT": "When
enabled, ..."`), e a `pt_BR/inboxMgmt.json:754` tem a tradução correspondente. O bloco novo entrou só
no `en` e **em português**. Não quebra a tela (o `createI18n` de `entrypoints/dashboard.js:39` não
declara `fallbackLocale`, então ele cai no default, que é o próprio `locale: 'en'`, e o usuário pt_BR
recebe o texto em português por acidente feliz), mas inverte a convenção da casa e deixa o usuário
`en` lendo português.

**Não corrigi de propósito:** traduzir só o `en` para inglês faria o usuário pt_BR passar a ler
**inglês**, que é pior do que está. O conserto certo são dois arquivos (inglês no `en`, o texto atual
no `pt_BR`) e a tarefa pedia para commitar só o relatório.

### D-6 · Duas pontas soltas — **BAIXO**

1. **Código morto:** `User#reset_isolation_exempt_inbox_ids_cache` (`user.rb:190`) nunca é chamado —
   grep em `app/`, `lib/`, `enterprise/` e `spec/` não devolve nenhum consumidor. O espelho dele
   (`reset_supervised_team_ids_cache`) é chamado em `agents_controller.rb:151`. Ou liga, ou apaga.
2. **Resíduo do `Current` no Sidekiq:** `lib/current.rb` é `thread_mattr_accessor`, não
   `ActiveSupport::CurrentAttributes`, e **não há server middleware do Sidekiq fazendo `Current.reset`**
   (`config/initializers/sidekiq.rb:18-33`). Hoje todos os setters (`BulkActionsJob`,
   `Macros::ExecutionService`, `Flows::*`) limpam no `ensure`, então **não achei bug vivo**. Mas até
   este commit um `Current.user` vazado numa thread de worker era inofensivo para o filtro de time;
   agora ele muda o que o job enxerga. Um `Current.reset` num server middleware fecha a classe
   inteira do problema por uma linha.

### Observação (não é defeito) · o contador "{selected} de {total}"

`IsolationParticipants.vue:158` conta supervisores no **total** e nunca no **selecionado**: uma caixa
com 2 agentes marcados + 1 supervisor lê "2 de 3 marcados", como se algo estivesse desmarcado. O
comentário do `:76` diz que é intencional ("quantos seguem isolados"). Aceitável; se o D-2 for
corrigido, o supervisor vira selecionável no card de time e o número passa a bater sozinho lá.

---

## 5. Saídas das ferramentas

### rubocop — 23 arquivos, limpo

```
$ bundle exec rubocop --force-exclusion $(git diff --name-only 8aec9690c^..bf4b8c749 | grep -E '\.(rb|jbuilder)$')
Inspecting 23 files
.......................
23 files inspected, no offenses detected
```

### eslint — 5 arquivos, limpo

```
$ npx eslint Settings.vue IsolationParticipants.vue IsolationParticipants.spec.js \
             channelActions.js buildInboxData.spec.js
ESLINT_EXIT=0        (sem nenhuma saída)
```

### rspec — 288 exemplos, 3 falhas, **as 3 pré-existentes**

```
$ bundle exec rspec spec/models/inbox_isolation_exemption_spec.rb \
    spec/models/conversation_team_message_isolation_spec.rb \
    spec/services/agent_message_isolation_spec.rb spec/services/team_message_isolation_spec.rb \
    spec/services/team_supervision_spec.rb spec/finders/message_finder_spec.rb \
    spec/finders/conversation_finder_spec.rb spec/services/conversations/list_preloader_spec.rb \
    spec/services/search_service_spec.rb spec/controllers/api/v1/accounts/inboxes_controller_spec.rb

288 examples, 3 failures

rspec ./spec/finders/conversation_finder_spec.rb:211            # perform_meta_only returns the correct counts
rspec ./spec/controllers/.../inboxes_controller_spec.rb:317     # deletes inbox
rspec ./spec/controllers/.../inboxes_controller_spec.rb:381     # creates a webwidget inbox when administrator
```

**Provei que são pré-existentes**, não confiei na aparência: criei um worktree em `8aec9690c^`
(= `1157fa38e`, o commit anterior à tarefa A) e rodei os mesmos dois arquivos:

```
$ cd <worktree em 1157fa38e> && bundle exec rspec spec/finders/conversation_finder_spec.rb \
    spec/controllers/api/v1/accounts/inboxes_controller_spec.rb
124 examples, 3 failures
rspec ./spec/finders/conversation_finder_spec.rb:211
rspec ./spec/controllers/api/v1/accounts/inboxes_controller_spec.rb:317
rspec ./spec/controllers/api/v1/accounts/inboxes_controller_spec.rb:381
```

Os **mesmos três**, nas mesmas linhas, sem uma linha da feature no repositório. As causas são
alheias: chaves extras de contagem (`ai_count`, `unattended_*`) de outras features do fork; a mensagem
de exclusão de caixa traduzida para português; e `test.com` reprovado no `format: uri` do schema
OpenAPI **do corpo da requisição**. Confirmei também que os dois campos novos do
`_inbox.json.jbuilder` **não** quebram o schema da resposta — o único erro reportado é o
`/channel/website_url` do request.

O worktree foi removido e o schema do banco de teste restaurado (`db:test:prepare`); a árvore de
trabalho está como estava.

### vitest — 12 testes, limpo

```
$ npx vitest run IsolationParticipants.spec.js buildInboxData.spec.js
 ✓ buildInboxData.spec.js (3 tests) 9ms
 ✓ IsolationParticipants.spec.js (9 tests) 434ms
 Test Files  2 passed (2)
      Tests  12 passed (12)
```

---

## 6. O que eu mexi

**Nada de código.** `rubocop` e `eslint` já estavam limpos e não achei typo nem string faltando que
justificasse tocar em arquivo — o único candidato (o i18n do D-5) exige mexer no `pt_BR`, que estava
fora do escopo desta verificação. Os arquivos temporários de sonda foram apagados e o worktree de
comparação foi removido; `git status` está igual ao do início da tarefa.

## 7. Recomendação

Liberado para staging. Antes da frota, corrigir **D-1** (é o único que muda visibilidade em
silêncio) e **D-2/D-3** (a tela afirma uma isenção que não existe). **D-4** entra na primeira janela
de performance; **D-5** e **D-6** são higiene.
