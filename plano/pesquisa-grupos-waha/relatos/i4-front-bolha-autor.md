# I4 — FRONT / BOLHA: o autor da mensagem na conversa de grupo

> Worker I4 · 2026-07-27 · VM 192.168.8.232 · branch `homologacao` · **nada commitado**

---

## 1. O que descobri antes de mexer (verificação, não suposição)

**Cadeia de renderização — confirmada:**

```
MessagesView.vue:637  <MessageList ... :messages="getMessages">   (import 'next/message/MessageList.vue')
  └─ MessageList.vue  → camelizza cada mensagem → <Message v-bind="item.message">
       └─ Message.vue → provideMessageContext(...) → <Component :is="componentToRender">
            └─ bubbles/Text|Image|File|Audio|Video|… → todas montam bubbles/Base.vue
```

`Base.vue` é o gargalo certo: **16 bolhas** o usam (`grep -l Base.vue bubbles/`), então o autor
renderizado nele cobre texto, mídia, arquivo, áudio, contato, e-mail e não-suportado de uma vez.

**Como o dado chega ao componente — verificado, não suposto:**

| Camada | Formato |
|---|---|
| Banco | `messages.content_attributes['group_sender']` |
| `_message.json.jbuilder:9` | `json.content_attributes message.content_attributes` — **passa cru, snake_case** |
| `MessageList.vue:95-108` | `useCamelCase(message, { deep: true, stopPaths: [...] })` |
| Componente | **`contentAttributes.groupSender`** com `{ name, lid, phone }` (as 3 chaves são palavras únicas, a camelização não as altera) |

Ou seja: **chega camelizado**. Mesmo assim leio `groupSender ?? group_sender` — o custo é uma
linha e cobre payload que entre por outro caminho (websocket direto, store legado).

**Estado do banco no momento em que escrevi (leitura, `RAILS_ENV=production rails runner`):**

- `Message.where("content_attributes ? 'group_sender'").count` → **0** (o W1 ainda não gravou)
- mensagens no formato legado (`content LIKE '👥 *%'`) → **514**, com **20 autores distintos**
- conversa 12 → `group? = true`, contato `120363040285567246@g.us`

Por isso a bolha foi escrita para **degradar sem quebrar** quando `group_sender` não existe.

---

## 2. O que mudou (arquivo:linha)

### Arquivos novos

| Arquivo | Papel |
|---|---|
| `components-next/message/groupAuthorPresenter.js` | Função pura `buildGroupAuthor(sender, labels)` → rótulo, iniciais, cores light/dark, tooltip, aria-label. Mais `groupAuthorLabels(t)` e `groupAuthorStyle(author)`. Um só lugar calcula a identidade visual, usado pela bolha **e** pelo preview de resposta |
| `components-next/message/GroupAuthorAvatar.vue` | Avatar 28px do participante (iniciais + cor determinística + tooltip) |
| `components-next/message/bubbles/GroupAuthorName.vue` | Linha do nome no topo da bolha, 13px semibold, na cor do autor |
| `specs/groupAuthorPresenter.spec.js` | 14 testes da função pura (inclui guard das chaves i18n reais) |
| `specs/groupAuthorBubble.spec.js` | 8 testes de renderização real (Base.vue + avatar) |

### Arquivos alterados

| Arquivo:linha | Mudança |
|---|---|
| `MessageList.vue:138-159` | `isGroupConversation` — espelha `Conversation#group?` (JID `@g.us` no contato, `custom_attributes.waha_whatsapp_*`, `additional_attributes.type`) |
| `MessageList.vue:161-198` | `groupSenderOf`, `hasSameGroupAuthor`, `breaksGroupAuthorBlock` — **o conserto do bug ativo** |
| `MessageList.vue:174` (`canGroupMedia`) | Grade de mídia também deixa de juntar autores diferentes |
| `MessageList.vue:~305` (`shouldGroupWithNext`) | Passa a considerar o autor do grupo |
| `MessageList.vue:~318` | `shouldGroupWithPrevious` — novo; a bolha precisa saber se **abre** o bloco (WhatsApp) e não só se o fecha (Chatwoot) |
| `MessageList.vue:~352` (template) | Passa `:group-with-previous` e `:is-group-conversation` |
| `Message.vue:149-150` | Props `groupWithPrevious` e `isGroupConversation` |
| `Message.vue:~745-775` | `groupSender`, `groupAuthor`, `shouldShowGroupAuthorAvatar` |
| `Message.vue:~800` | `groupAuthor` entra no `provideMessageContext` |
| `Message.vue:~880` (template) | Ramo novo do `[grid-area:avatar]`: avatar do participante na **primeira** do bloco + spacer 28px nas seguintes. O ramo 1:1 virou `v-else-if`, byte a byte igual ao que era |
| `bubbles/Base.vue:17-38` | Lê `groupAuthor`/`groupWithPrevious` do contexto |
| `bubbles/Base.vue:~97` | `<GroupAuthorName>` acima do bloco de `inReplyTo` |
| `bubbles/ReplyPreview.vue:20-40` | `quotedGroupAuthor` — autor da mensagem citada |
| `bubbles/ReplyPreview.vue:~144-165` | Nome do autor citado + **barra vertical na cor dele**. Sem autor o wrapper vira `display: contents` e **some do layout** — a árvore visual do 1:1 fica idêntica |
| `specs/MessageList.spec.js` | Reescrita: mock do store + 6 testes de agrupamento |

---

## 3. As decisões que você precisa saber

### 3.1 O bug do agrupamento — e por que fui conservador

`shouldGroupWithNext` agrupava por `senderId`, que em grupo é **sempre o contato-grupo**. Duas
pessoas diferentes viravam um bloco só. A correção compara a identidade estável do participante
(`authorIdentityKey`: lid > phone > name).

**Mas ela só age quando existe dado novo.** Se **nenhuma** das duas mensagens tem `group_sender`,
vale a regra de hoje. Motivos, nesta ordem:

1. **`PrivateChatView.vue` usa o mesmo `MessageList`.** Se o agente estiver com uma conversa de
   grupo selecionada e abrir o chat interno, sem esse freio as mensagens do chat interno parariam
   de agrupar. Regressão gratuita num lugar que nada tem a ver com grupo.
2. **As 514 legadas carregam o autor dentro do texto, em cada bolha.** Mesmo agrupadas, o agente
   lê quem falou. Mudar o agrupamento do histórico mexeria em 514 mensagens sem ganho real.

Caso misto (uma com autor, outra sem) **não** agrupa — não se junta o conhecido com o desconhecido.

### 3.2 Contraste do avatar — divergi do mockup de propósito, e por quê

O mockup pinta o avatar com a cor cheia e as iniciais em **branco**. No tema claro isso passa
(verifiquei as 8 cores: 4,56:1 a 6,08:1 contra branco). **No escuro não passa**: as cores dark são
claras (`#f191c8`) e branco sobre elas dá **2,18:1**.

Minha primeira versão usou fundo translúcido + iniciais na cor. Calculei o contraste real e
também reprovou (**3,47:1**): o avatar fica sobre o papel de parede da conversa, não sobre a
bolha, e a paleta do helper foi calibrada para 4,5:1 contra o fundo da **bolha**.

**O que ficou:** fundo cheio na cor do autor, texto branco no claro e `#0b141a` no escuro.
Fiel ao mockup no claro, legível no escuro (8,6:1 a 10,3:1). O **nome** dentro da bolha usa a cor
do helper direto, que é onde os 4,5:1 dele valem.

A troca de tema é feita pelas variantes `dark:` do Tailwind sobre CSS vars (`--group-author-color`
/ `--group-author-color-dark`, o mesmo padrão de `Avatar.vue:283`). O componente **não** precisa
saber o tema ativo, e a cor acompanha a troca sem re-render.

### 3.3 Colisão de cores — achado sobre o helper (não editei)

Rodando o presenter contra os **20 autores reais** da base: 20 pessoas → **8 cores distintas** (a
paleta tem 8). "Walisson" e "Rogerio José Da Silva" caem na mesma cor. O design (§3.6.3) pedia
**12+ pares**; `whatsappGroupHelper.js` entregou 8. Como o arquivo é seu, **não toquei**. Se
quiser, é só acrescentar 4 pares à `AUTHOR_PALETTE` — nada no meu código muda.

### 3.4 Reações — avaliei e NÃO fiz (de propósito)

`MessageReactions.vue` é órfão mesmo. Mas ligá-lo **não resolve** o sintoma descrito: a reação
vira mensagem de texto no fio porque a **WAHA a entrega como mensagem** — é ingestão, não front.
Ligar o componente exigiria ainda adaptar `aggregated` (ele espera `{userId: [emoji]}`, o
serializer manda `{emoji: count}` — `_message.json.jbuilder:28`) e mexer no fluxo de POST do
toggle. Custo médio, ganho parcial, fora do escopo desta task. **Fica como achado.**

---

## 4. i18n — nada pendente, mas leia o tropeço

Uso **2 chaves**. O I5 **já as criou** nos dois idiomas enquanto eu trabalhava, então não há nada
a fazer aqui:

| Chave (caminho real) | pt-BR | en |
|---|---|---|
| `GROUP_INFO.UNKNOWN_PARTICIPANT` | `Participante não identificado` | `Unidentified participant` |
| `GROUP_INFO.UNKNOWN_PARTICIPANT_HINT` | `O WhatsApp não informou quem enviou esta mensagem. Sincronize os integrantes…` | `WhatsApp did not tell us who sent this message…` |

**Tropeço que vale registrar:** eu tinha escrito `CONVERSATION.GROUP_INFO.*`. O bloco `GROUP_INFO`
mora na **raiz** do `conversation.json` (ao lado de `CONVERSATION`), como o design §5 pedia e como
o I5 fez — `t('GROUP_INFO.…')`. Corrigido, e **cravei um teste** que lê os dois JSONs de verdade e
falha se a chave não existir, para ninguém repetir o erro.

`groupAuthorLabels(t)` ainda tem fallback em pt-BR caso a chave suma no futuro (o vue-i18n devolve
a própria chave nesse caso) — dois testes cobrem os dois estados.

Reaproveitei `CONVERSATION.SENT_BY` (já existia) no `aria-label` do avatar, sem criar dependência
nova.

**Fronteira com o saneamento do I5 — conferida no diff dele:** o `MessageFormatter` mantém o
`👥 *Nome*` e remove só o `(...@lid)`. Combina exatamente com a minha degradação: mensagem legada
não tem `group_sender`, minha bolha não renderiza autor, e o nome continua visível pelo texto
saneado. **Sem autor duplicado em nenhum caminho** — e eu não chamo `parseLegacyGroupContent`.

---

## 5. O LID nunca aparece — como isso está garantido

O identificador só entra em `authorIdentityKey()` (chave do hash de cor), dentro do helper. Não vai
para `label`, `tooltip`, `aria-label`, `title`, `alt` nem `data-*`.

Coberto por 3 testes que falham se alguém regredir isso:
`groupAuthorPresenter.spec.js` ("never leaks the technical identifier"),
`groupAuthorBubble.spec.js` ("never renders the technical identifier" — varre o HTML montado) e
o teste do avatar. Rodei também contra os 20 autores reais da base: nenhum vazamento.

---

## 6. Como testei

| O quê | Resultado |
|---|---|
| `npx eslint app/javascript/dashboard/components-next/message/` | **limpo — 0 erro, 0 warning**, no diretório inteiro (o warning pré-existente de chave dinâmica em `ReplyPreview` também sumiu ao mover as chaves para o presenter) |
| `npx vitest run …/message/specs/` | **44 testes, 4 arquivos, todos verdes** |
| `npx vite build` | **exit 0** (rodado 3×, o último já com o código final: "built in 4m 2s") |
| Classes novas no CSS gerado | conferido no bundle: `--group-author-color`, `--group-author-color-dark` e `dark\:text-\[\#0b141a\]:is(.dark *)` estão em `dashboard-*.css`. A troca de tema funciona por CSS, sem JS |
| App no ar | `https://…/app/login` → **200** depois do build |
| Dado real da base (leitura) | 20 autores reais extraídos das 514 legadas → `buildGroupAuthor` produziu rótulo, iniciais e cores válidas para os 20, sem vazar LID |
| Paridade light/dark | Contraste **calculado** (não estimado) para as 8 cores nos dois temas — ver §3.2 |

**Baseline consertado de brinde:** `MessageList.spec.js` já estava **quebrado antes de mim**
(1 de 2 testes falhava com `Cannot read properties of undefined (reading 'getters')` — o
isolamento por agente passou a exigir store e a spec não mockava). Agora mocka e passa.

### ⚠️ Efeito colateral do `vite build` que você precisa saber

Rodei `npx vite build --outDir <scratchpad> --emptyOutDir` justamente para não tocar no ambiente.
**O `--outDir` foi ignorado**: o `vite-plugin-ruby` força o destino a partir de `config/vite.json`,
e o build **regravou `public/vite/`** (assets e manifest de 15:02). Ou seja, a homologação passou a
servir um bundle construído a partir do working tree atual — que inclui o WIP dos outros workers.

- `public/vite*` está no `.gitignore` (`.gitignore:87`), então **o working tree/git não foi afetado**.
- O build terminou com exit 0 e `https://…/app/login` responde **200** — nada quebrado.
- Aconteceu **3×**. Não há como voltar ao bundle anterior; de qualquer forma você vai rodar o
  build oficial ao integrar. **Só não conte com o bundle atual como "o de antes"** — ele reflete o
  working tree de agora, incluindo o WIP dos outros workers.
- **Lado bom:** o último build já saiu com o código final, então a homologação está servindo o
  front com esta implementação. Dá para validar visualmente sem rebuildar.

---

## 7. Como chegar na tela para validar visualmente

Conta **3** (todas as conversas de grupo estão nela).

| Cenário | Onde | O que esperar |
|---|---|---|
| **Grupo, histórico legado** | `/app/accounts/3/conversations/444` — "Simplex - Notificações (Grupo)", inbox 17, **325 mensagens legadas** | **Nada pode mudar.** Autor ainda dentro do texto, agrupamento como hoje. É o teste de não-regressão do histórico |
| **Grupo, muitas mensagens** | `/app/accounts/3/conversations/5` — "Sentinela Monitoramento (GROUP)", `group? = true`, 1.722 msgs | idem |
| **Conversa 1:1** | qualquer uma sem `(Grupo)`/`(GROUP)` no nome | **Pixel-idêntica.** Avatar continua na última do bloco, sem nome, sem barra no reply |

**O autor estruturado só aparece depois do W1 gravar `group_sender`** — hoje o banco tem 0
mensagens com ele. Para ver a bolha nova antes disso, injete o atributo em 3 mensagens de teste
(**escrita no banco — decisão sua, eu não fiz**; é reversível):

```ruby
# RAILS_ENV=production bundle exec rails runner '...'
msgs = Conversation.find(2405).messages.incoming.last(3)
[
  { 'name' => 'Rogerio José Da Silva', 'lid' => '229480102662169', 'phone' => '5566999991234' },
  { 'name' => 'Rogerio José Da Silva', 'lid' => '229480102662169', 'phone' => '5566999991234' },
  { 'name' => 'Angela Tozi',           'lid' => '260330953380002', 'phone' => nil }
].each_with_index do |sender, i|
  m = msgs[i]
  m.update_columns(content_attributes: m.content_attributes.merge('group_sender' => sender))
end
# reverter: m.update_columns(content_attributes: m.content_attributes.except('group_sender'))
```

Esperado: as **duas primeiras** com nome+avatar só na primeira (bloco agrupado), a terceira com
**outra cor** e bloco próprio; telefone só no hover; nenhum `@lid` em lugar nenhum. Um `group_sender`
com `name`/`phone` nulos deve virar "Participante não identificado" em itálico cinza com avatar `?`.

---

## 8. O que ficou de fora

1. **Reações** (§3.4) — avaliado, não feito, com a justificativa acima.
2. **Clique no nome abrir o painel do integrante** (design §3.1) — depende do painel do I5/F3. O
   nome tem `tabindex="0"` e tooltip; falta só o handler quando o painel existir.
3. **Cabeçalho, painel lateral, i18n e saneamento do texto legado** — são do I5, não toquei.
4. **`whatsappGroupHelper.js`** — não editei (regra do briefing). Sugestão de paleta em §3.3.
5. **Validação visual no navegador** — é sua, conforme a task. Receita em §7.
6. **`isGroupConversation` está duplicado** entre o meu `MessageList.vue` e o que o I5 fizer no
   cabeçalho. Não criei composable compartilhado para não colidir com ele no mesmo arquivo. Se
   quiser um ponto único depois, o candidato natural é `whatsappGroupHelper.js` (seu) recebendo um
   `isGroupConversation(chat)` — minhas 20 linhas saem sem alterar mais nada.
