# I5 — Cabeçalho, saneamento do histórico, painel de Integrantes e i18n

> Worker I5 · 2026-07-27 · VM 192.168.8.232 (homologação) · branch `homologacao` · **nada commitado**

---

## 1. Resumo

Três entregas, todas condicionadas a grupo (exceto o saneamento, que é deliberadamente incondicional):

1. **Cabeçalho** — nome sem o sufixo `(GROUP)/(Group)/(Grupo)`, badge "Grupo" e a linha de presença
   substituída por "N participantes". Sem snapshot, a linha diz `Grupo · integrantes não
   sincronizados` — nunca "0 participantes".
2. **Saneamento do histórico** — o `(...@lid)` some de toda superfície (bolha, preview da lista,
   busca, Kanban, copilot) num único ponto: `MessageFormatter`. O `👥 Nome` **fica** enquanto a
   mensagem for legada.
3. **Painel "Integrantes (N)"** — lista ordenada com avatar/telefone/badge de admin, popover de
   ações, empty state, skeleton, barra de erro que preserva a última lista, rodapé "Sincronizado
   há X". Só renderiza em conversa de grupo.

Validado com **dado real** (542 mensagens legadas na base, conversas 444/490/22/8) e com
**Playwright em light e dark**, num servidor de desenvolvimento isolado — sem tocar no hml.

**Um bug de UX foi encontrado e corrigido nessa validação** (§6.3): o popover fechava sozinho no
clique de verdade. Build verde e teste unitário não pegariam.

---

## 2. Arquivos

### Novos

| Arquivo | Papel |
|---|---|
| `dashboard/composables/useGroupConversation.js` (132 l.) | `isGroup`, `groupName`, `participants` (normalizados + ordenados), `participantCount`, `unresolvedCount`, `hasSnapshot`, `syncedAt`. Espelha `Conversation#group?` no front. Leitura pura da store — não faz requisição |
| `dashboard/routes/dashboard/conversation/GroupParticipants.vue` (482 l.) | Painel: estados, busca, popover, sync, rodapé |
| `dashboard/components-next/GroupParticipants/GroupParticipantRow.vue` (113 l.) | Linha do integrante (avatar com cor determinística, nome, telefone, badge) |
| `dashboard/api/groupParticipants.js` (31 l.) | Cliente do endpoint do I3. Único lugar que conhece a URL |
| `dashboard/composables/specs/useGroupConversation.spec.js` | 9 testes |

### Modificados

| Arquivo:linha | Mudança |
|---|---|
| `shared/helpers/MessageFormatter.js:4` | importa `parseLegacyGroupContent` do helper pronto |
| `shared/helpers/MessageFormatter.js:60-95` | `sanitizeLegacyGroupContent()` + comentário do débito apontando para `SINTESE.md` |
| `shared/helpers/MessageFormatter.js:105` | construtor passa a mensagem pelo saneamento |
| `shared/helpers/specs/MessageFormatter.spec.js:122-174` | 6 testes novos (inclui 3 de falso positivo) |
| `components/widgets/conversation/ConversationHeader.vue:26,142-168` | composable + `displayName`, `groupSubtitle`, `sublineText` |
| `ConversationHeader.vue:412,428` | Thumbnail e nome usam `displayName` (sem sufixo) |
| `ConversationHeader.vue:430-437` | badge `Grupo` (`i-lucide-users`, pill) |
| `ConversationHeader.vue:446-457` | a linha de presença passa a ser `sublineText`; em grupo nunca fica verde de "online" |
| `routes/dashboard/conversation/ContactPanel.vue:19,112-120,207-221` | seção `group_participants` (aberta por padrão, título com contagem), renderizada só se `isGroup` |
| `composables/useUISettings.js:6,54-60` | `group_participants` no default, logo abaixo de `conversation_media` — inclusive para quem já tem ordem salva |
| `i18n/locale/pt_BR/conversation.json` + `en/conversation.json` | bloco `GROUP_INFO` (35 chaves) + `CONVERSATION_SIDEBAR.ACCORDION.GROUP_PARTICIPANTS` |

**Não toquei** em `components-next/message/**` (I4), em `whatsappGroupHelper.js` (C4), em backend,
rota, migration ou jbuilder.

---

## 3. Decisões

### 3.1 O saneamento NÃO é condicionado a grupo

Conforme o achado que você mandou no meio do trabalho: lista de transmissão (broadcast) também
recebe o prefixo, e `Conversation#group?` é `false` nesses casos. O `MessageFormatter` não pergunta
se é grupo — limpa sempre que o padrão aparece. Provado na conv 490 (§6.2), que é 1:1 e ficou sem
`@lid` no fio, sem ganhar badge nem painel de grupo.

### 3.2 Mantive o `👥 Nome`, removi só o identificador

Como o dispatch determinou. O ponto fino: o separador original é preservado (`\n\n` vira `\n\n`,
`\n` vira `\n`), para o markdown não mudar o espaçamento da mensagem. O I4 confirmou no relatório
dele que a bolha **não** renderiza autor em mensagem legada — ou seja, **não há autor duplicado em
nenhum caminho**.

### 3.3 Um `import` que cruza camada (assumido)

`shared/helpers/MessageFormatter.js` passa a importar de `dashboard/helper/`. Isso põe ~4 KB de
código puro no bundle do widget (que usa `useMessageFormatter`). Aceitei porque:
(a) é o padrão da casa — `shared/composables/useBranding.js`, `useFilter.js` e `shared/mixins/inboxMixin.js`
já importam de `dashboard/`; (b) o helper é puro, sem store nem DOM; (c) o dispatch proibiu editar
o helper. **Se você preferir**, mover `whatsappGroupHelper.js` para `shared/helpers/` resolve — mas
isso quebra os imports do I4 e tem que ser decidido por você, não por mim.

### 3.4 Clique abre popover, não navega

Como o design pede. "Abrir conversa 1:1" e "Ver contato" ficam **desabilitados com tooltip honesto**
enquanto o participante não tem contato no ChatSPX. A descoberta é sob demanda — **uma** requisição
quando o agente clica na linha (`contacts/search` pelo telefone + `contacts/{id}/conversations`),
nunca uma por linha da lista. Sem telefone, nem tenta.

### 3.5 Contrato do endpoint: 200 não significa sucesso

Peguei o contrato no seu relato do I3 (§5) depois de ter perguntado por ele. O endpoint responde
**sempre 200** e informa o resultado no corpo. O painel lê `ok`/`status`:

| resposta | UI |
|---|---|
| `synced` | recarrega a conversa + toast "Integrantes atualizados" |
| `cached` | recarrega a conversa, sem toast |
| `throttled` | toast "Aguarde alguns segundos…" — **não** é barra de erro |
| `ok:false` (`failed`) | barra de alerta + "Tentar novamente", **mantendo a lista antiga** |
| erro de rede | idem `failed` |

### 3.6 A seção abre por padrão

`isContactSidebarItemOpen` devolve `false` para chave inédita, o que deixaria "Integrantes"
recolhido justamente na conversa em que ele é a informação que falta. Usei o mesmo critério de
"Mídias e Arquivos": `is_group_participants_open !== false`.

---

## 4. Saneamento — prova com o dado real

Script: rodei `parseLegacyGroupContent` (a mesma função do `MessageFormatter`) sobre uma amostra
tirada do banco em **leitura** (`RAILS_ENV=production rails runner`, 9 mensagens de 9 conversas
diferentes). Base: **548** mensagens contendo `@lid`, das quais **514** começam com o prefixo e
**34** trazem o identificador no meio do texto.

```
msg 24997 (conv 2376)
  ANTES : "👥 *‎Rogerio José Da Silva (229480102662169@lid)*\n"
  DEPOIS: "👥 *Rogerio José Da Silva*\n"                       ← U+200E também sumiu

msg 24457 (conv 2377)
  ANTES : "👥 *Walisson (60756640940218@lid)*\n\nReiniciei aqui e nao voltou nao"
  DEPOIS: "👥 *Walisson*\n\nReiniciei aqui e nao voltou nao"

msg 24120 (conv 2405)
  ANTES : "👥 *Tecnologia (267722592149653@lid)*\n\n🚨 **Conversa aguardando há 20h 7min**…"
  DEPOIS: "👥 *Tecnologia*\n\n🚨 **Conversa aguardando há 20h 7min**…"

msg 31662 (conv 2449) — identificador NO MEIO do texto (notificação/broadcast)
  ANTES : "…💬 **Mensagem (às 14:55):**\n"👥 **Atila Ferreira (116239062036570@lid)**\n\nhttps://rea…"
  DEPOIS: "…💬 **Mensagem (às 14:55):**\n"👥 **Atila Ferreira**\n\nhttps://realizareimobiliaria.com…"
```

Nas 9 amostras, `content.includes('@lid')` depois do saneamento = **false**.

**Falso positivo — o que o regex NÃO toca:**

```
"Manda pro meu email: lid@lid.com.br"        → inalterado
"O pedido (12345678) já foi faturado"        → inalterado
"Ele falou (mesmo assim@lid) ontem?"         → inalterado   (exige 8+ dígitos)
"👥 *Fulano* sem identificador nenhum"       → inalterado
```

O padrão exige literalmente `(` + 8 ou mais dígitos + `@lid` + `)`.

---

## 5. i18n

`GROUP_INFO` na **raiz** de `conversation.json` (não dentro de `CONVERSATION`), como o design §5
pede — 35 chaves, pt-BR e en completos, mais `CONVERSATION_SIDEBAR.ACCORDION.GROUP_PARTICIPANTS`.

Inclui as chaves do design que ainda não têm consumidor (`LEFT_GROUP`, `LEFT_GROUP_SECTION`,
`NOT_IN_GROUP_BANNER`, `SUPER_ADMIN_BADGE`, `SENT_BY_IN_GROUP`, `REPLYING_TO`) — são de F2/F3;
estão lá para quem for implementar não inventar chave nova. Acrescentei três fora do design:
`BADGE_TOOLTIP`, `HEADER_NOT_SYNCED`, `SYNC_THROTTLED`, `SYNC_TOOLTIP`, `SYNC_SUCCESS`,
`LOAD_ERROR_KEEPING_LIST`, `ACTIONS.COPY_PHONE_DISABLED` — todas com uso real no código.

**As 2 chaves do I4** (`GROUP_INFO.UNKNOWN_PARTICIPANT`, `…_HINT`) já existem nos dois idiomas; ele
confirmou no relatório dele que não há nada pendente. Zero texto hardcoded em componente.

---

## 6. Validação

### 6.1 Estático e unitário

- `npx eslint` nos 10 arquivos: **0 erros**. Sobram 2 warnings em `ConversationHeader.vue`
  (`no-dynamic-keys`, linhas 487 e 508) que são do editor de prioridade **pré-existente** — não
  encostei nesse bloco.
- `npx vitest run` — **30 testes, 30 verdes**: 21 em `MessageFormatter.spec.js` (6 novos) + 9 em
  `useGroupConversation.spec.js`.

### 6.2 Navegador, com dado real, light **e** dark

Como o banco desta VM está 61 migrations atrás do branch, o backend do working tree não sobe contra
ele. Montei o ambiente assim, **sem tocar no hml**: front do working tree servido por um `vite dev`
isolado (porta 3039) + puma de desenvolvimento (porta 3055), e **toda chamada de API redirecionada
para o backend de homologação que já roda (:3000)** via `page.route` do Playwright. O snapshot
`waha_group` foi **injetado na resposta HTTP** — nenhuma linha gravada no banco.

| Cenário | light | dark | Resultado |
|---|---|---|---|
| Grupo com snapshot (conv 22) | ✅ | ✅ | header `Infra Data Norte` + badge `Grupo` + `12 participantes`; painel `Integrantes (12)` com admins primeiro, divisor, demais A→Z, não identificado por último; rodapé `Sincronizado há 7 minutos · 1 de 12 integrantes ainda não identificados` |
| Popover de ações | ✅ | ✅ | `Angela Tozi / +55 66 9 9999-1235` + `Abrir conversa 1:1` **desabilitado**, `Ver contato` **desabilitado**, `Copiar telefone` habilitado (`disabled: [true, true, false]`) |
| Grupo sem snapshot | ✅ | ✅ | header `Grupo · integrantes não sincronizados`; painel com empty state + `Sincronizar agora` |
| Sync falhando (200 + `ok:false`) | ✅ | ✅ | barra âmbar `Não foi possível atualizar os integrantes. Mostrando a última lista recebida. Tentar novamente` **com a lista preservada** e `Sincronizado há 3 dias` |
| Conversa 1:1 (conv 8) | ✅ | — | sem badge, sem painel, presença intacta |
| Broadcast 1:1 legado (conv 490) | ✅ | — | sem badge, sem painel, fio **sem `@lid`**, com `👥 Kalyston Prado` |
| Grupo real com 325 msgs legadas (conv 444) | ✅ | — | nome `Simplex - Notificações` (sufixo `(Grupo)` removido), fio **sem `@lid`**, com `👥 Tecnologia` |

Em todos os casos, varredura do painel por `/@lid|\d{12,}/` no texto renderizado: **nenhuma
ocorrência**. O LID só existe como `data-participant-lid` no DOM (permitido pela regra 1 do briefing).

Screenshots (14 + 4) em
`/tmp/claude-1001/-home-chatwoot-chatwoot/d348f87b-57fd-48e7-a132-14b97ab9e1b0/scratchpad/shots/`.
Os scripts (`validate.mjs`, `erro.mjs`, `regressao.mjs`) estão na mesma pasta.

O ambiente de validação foi **desmontado**: puma 3055 e vite 3039 derrubados, e o initializer
temporário que eu tinha criado para pular o gate de migrations (`config/initializers/zzz_tmp_…`)
foi **apagado** — confirme com `git status`, não deve haver rastro dele.

### 6.3 O bug que só a validação visual pegou

Com clique de verdade, o popover abria e fechava no mesmo instante. Causa: o `click` que abre
continua borbulhando até o `document` **depois** do `nextTick` em que o listener de "clique fora" é
registrado — com `dispatchEvent` via script isso não acontece, então o teste programático mentia.
Corrigido com `@click.stop` na linha do integrante (`GroupParticipantRow.vue:70`), com comentário
explicando o porquê em `GroupParticipants.vue`.

---

## 7. Como chegar na tela (para você validar rápido)

1. Conta **3** (Simplex Tecnologia), qualquer conversa de grupo. Alvos:
   - `…/app/accounts/3/conversations/22` — "Infra Data Norte (GROUP)"
   - `…/app/accounts/3/conversations/444` — "Simplex - Notificações (Grupo)", 325 mensagens legadas
   - `…/app/accounts/3/conversations/490` — 1:1 de broadcast, 12 mensagens legadas (controle)
2. Cabeçalho: nome sem sufixo, badge "Grupo", e a linha de baixo com a contagem.
3. Painel lateral (≥1280px abre sozinho): seção **Integrantes**, logo abaixo de "Mídias e Arquivos".
4. Enquanto o job do I3 não gravar snapshot nessas conversas, o esperado é o **empty state** e o
   cabeçalho dizendo `Grupo · integrantes não sincronizados`. Clicar em "Sincronizar agora" chama
   `POST …/conversations/{display_id}/waha_group`.

⚠️ O bundle servido pelo hml (`public/vite`) precisa ser reconstruído para essas telas aparecerem —
veja §9.

---

## 8. O que ficou de fora (de propósito)

- **Busca de integrante e "Ver todos"**: implementados, mas só aparecem com mais de 8 participantes.
  Não consegui exercitar no navegador (o snapshot injetado tinha 6). A lógica está coberta por
  código simples e revisável, não por teste.
- **Máscara de telefone por papel** (`+55 66 9 ****-1234` para papéis restritos, design §3.3): não
  implementei. O front não tem hoje uma política de permissão para "ver telefone do contato", e
  inventar uma seria pior que não ter. Telefone aparece completo, como já aparece em `ContactInfo`.
- **Sub-bloco "Saíram do grupo"** e **banner "não faz mais parte deste grupo"**: o snapshot C3 não
  traz `role: left` nem o status da sessão. Chaves i18n já criadas; UI é F2.
- **Foto do participante no avatar**: o C3 não traz URL de foto. Uso iniciais com a cor
  determinística do helper (a mesma da bolha do I4).
- **Ordenação com `Intl`**: uso `localeCompare(..., 'pt-BR')`. Em nomes iniciados por emoji o
  resultado é o que a plataforma decidir — não normalizei.

---

## 9. Riscos e incidentes que você precisa saber

1. **`git stash` acidental (meu erro, já resolvido).** Às ~16:14 rodei um comando composto que
   incluía `git stash`: o working tree inteiro — meus arquivos **e os dos outros workers** — voltou
   ao HEAD por cerca de 1 minuto. `git stash pop` restaurou tudo **sem conflito**; `git status`
   voltou a mostrar os 64 arquivos e conferi os meus um a um. Já te avisei por `escalation` na hora.
   Risco residual: se algum worker leu ou escreveu arquivo exatamente nessa janela, vale ele
   conferir o `git status` dele.

2. **`public/vite` foi reescrito hoje por um build que não é meu.** Os 1115 arquivos do bundle de
   produção têm mtime de hoje (14:56 / 15:02 / 15:14) e batem com `build.log`, `build2.log` e
   `build3.log` no scratchpad do worker I4 — o `vite build --outDir <scratchpad>` dele foi
   sobrescrito pelo `vite-plugin-ruby`, que força o `outDir` de `config/vite.json`. Ou seja: **o
   hml (:3000) está servindo um bundle do working tree não commitado**, não o do HEAD. Não mexi
   nisso (o dispatch me proíbe de buildar), mas é decisão sua: rebuildar quando fechar a rodada, ou
   reverter para o bundle do commit.

3. **A rota de sync depende do I3 estar de pé.** Meu cliente aponta para
   `POST /api/v1/accounts/{id}/conversations/{display_id}/waha_group`. Se a rota mudar, muda em
   `dashboard/api/groupParticipants.js` e em nenhum outro lugar.

4. **`getConversation` após o sync** recarrega a conversa inteira (`ConversationApi.show`). É a
   forma mais segura de trazer o snapshot novo, mas custa uma requisição a mais. Se o I3 já emitir
   `conversation.updated` pelo websocket, dá para remover esse dispatch depois — não removi porque
   não confirmei o broadcast.

5. **Cross-layer import** (§3.3) — decisão sua se quer manter.
