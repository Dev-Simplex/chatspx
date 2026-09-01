# W6 — UX e front-end: como o ChatSPX deveria exibir grupo, autor por mensagem e integrantes

> Escopo: **somente pesquisa**. Nenhum arquivo `.vue`, `.js` ou `.scss` foi tocado.
> Data: 2026-07-27 · Worker: W6 · Base: `/home/chatwoot/chatwoot` (VM homologação 192.168.8.232)

---

## Resumo executivo

1. **O conjunto de componentes de mensagem ativo é `components-next/message/`.** O conjunto antigo
   (`components/widgets/conversation/bubble/`) **não existe mais nesta árvore** — foi removido no
   commit upstream `24ea968b00 chore: Remove older UI (#11720)`. Todo o fio da conversa passa por
   `MessagesView.vue:637 → next/message/MessageList.vue → Message.vue`. Só há **um** lugar para mexer.

2. **Existe um ponto único real de formatação de texto:** `shared/helpers/MessageFormatter.js:61`.
   Bolha, preview da lista de conversas, resultado de busca, Kanban e copilot passam todos por ele —
   direto (`new MessageFormatter`) ou via `shared/composables/useMessageFormatter.js`. É de fato o
   candidato natural a um saneamento de LID de exibição.

3. **Mas o dado ruim está PERSISTIDO.** Verifiquei no banco: o texto `👥 *Nome (lid@lid)*` está gravado
   na coluna `messages.content` (548 mensagens nesta base), e `messages.additional_attributes` está
   **vazio (`{}`)** — não existe nenhum metadado estruturado do autor. O `sender_id` da mensagem
   aponta para o **contato-grupo**, não para a pessoa. Ou seja: sanear no front esconde o sintoma e
   **não devolve o autor** — só remove o LID do meio da frase.

4. **Descoberta que corrige o briefing:** o sufixo no nome do contato-grupo **não é só `(GROUP)`**.
   Convivem na mesma base **três** variantes — `(GROUP)`, `(Group)` e `(Grupo)` — correlacionadas com a
   idade do contato. Isso reforça a hipótese de montagem externa (receptor/n8n), com versões diferentes
   ao longo do tempo.

5. **Não existe hoje NENHUM tratamento visual condicional para grupo.** Zero. Confirmado por busca:
   nenhuma ocorrência de `@g.us`, `isGroup`, `is_group` ou similar em `app/javascript/`. O único lugar
   do produto inteiro que reconhece grupo é o roteador do Captain, no back
   (`enterprise/app/services/captain/behavior/router_service.rb:33-46`).

6. **A infraestrutura visual necessária já existe e está subaproveitada:** `Avatar.vue` já tem paleta
   dupla light/dark de 6 pares e aceita override via prop `accent`; `colorHelper.js` já tem
   `adjustColorForContrast` (color2k); `_wa-skin.scss` já é o lugar canônico dos tokens WhatsApp;
   `MessageList.vue:265` já agrupa mensagens consecutivas do mesmo remetente; o serializer já expõe
   `additional_attributes` da mensagem (`_message.json.jbuilder:17`) e o websocket também
   (`app/models/message.rb:160`, via `attributes.symbolize_keys`). **A rota mais barata para o autor
   por mensagem é preencher `additional_attributes` na ingestão** — o front não precisa de novo endpoint.

7. **Dois componentes órfãos/regressões achados de quebra:** `MessageReactions.vue` existe, está pronto,
   e **não é importado por ninguém** no fio de conversa (só o chat interno tem reação renderizada) — por
   isso a reação vira uma mensagem de texto `*Reagiu com* 🚀` no fio. E `ReplyPreview.vue` **não mostra o
   autor da mensagem citada** — em grupo isso é exatamente o que falta.

---

## Achados

### A1 — FATO: o conjunto ativo é `components-next/message/`

**Evidência:**

```
app/javascript/dashboard/components/widgets/conversation/MessagesView.vue:10
  import MessageList from 'next/message/MessageList.vue';
app/javascript/dashboard/components/widgets/conversation/MessagesView.vue:637
  <MessageList ... >
```

`ls app/javascript/dashboard/components/widgets/conversation/` → **não há** diretório `bubble/`.
`git log --diff-filter=D` confirma a remoção em `24ea968b00 chore: Remove older UI (#11720)`.

Cadeia de renderização completa de uma mensagem:

```
MessagesView.vue:637
 └─ next/message/MessageList.vue:335        <Message v-bind="item.message" …>
     └─ next/message/Message.vue:929         <Component :is="componentToRender" />
         └─ bubbles/Text/Index.vue:77        <BaseBubble>
             ├─ bubbles/Base.vue:91          bloco de reply (inReplyTo)
             ├─ bubbles/Text/FormattedContent.vue:22   new MessageFormatter(content)
             └─ MessageMeta.vue:135          hora + status
```

**Onde eu mexeria para o autor por mensagem:** `Message.vue` (avatar + novo cabeçalho de autor) e
`bubbles/Base.vue` (o nome colorido dentro da bolha, como o WhatsApp faz).

---

### A2 — FATO: ponto único de processamento do texto

`app/javascript/shared/helpers/MessageFormatter.js:61-101` — classe `MessageFormatter`.
Pipeline: markdown-it (`html: false`, `breaks: true`, `linkify: true`, `typographer: true`) +
`markdownIt/link` (mentions) + `mila` (link attrs) + resize de imagem.

Consumidores (todos os caminhos que exibem `content` de mensagem no dashboard):

| Caminho | Arquivo:linha |
|---|---|
| Bolha da conversa | `components-next/message/bubbles/Text/FormattedContent.vue:22` |
| Preview na lista de conversas | `components-next/Conversation/ConversationCard/CardMessagePreview.vue:41` (via `getPlainText`) |
| Preview com meta | `components-next/Conversation/ConversationCard/CardMessagePreviewWithMeta.vue` |
| Resultado de busca | `modules/search/components/MessageContent.vue` |
| Story do Instagram | `components-next/message/bubbles/InstagramStory.vue:32` |
| Menu de contexto (copiar) | `modules/conversations/components/MessageContextMenu.vue` |
| Copilot | `components-next/copilot/CopilotAssistantMessage.vue:42` |

O preview do Kanban (`components-next/Kanban/ConversationPreviewModal.vue`) **não** chama o formatter
direto — ele renderiza `MessageList`, então herda o saneamento pela via da bolha. Mesma coisa vale
para o `PrivateChatView.vue` e o `ContactHistory.vue`.

Wrapper compartilhado: `app/javascript/shared/composables/useMessageFormatter.js:18` (`formatMessage`)
e `:37` (`getPlainText`).

**Conclusão:** um saneamento no construtor de `MessageFormatter` (linha 62-73) cobriria **todo o
front** de uma vez. Isso é real — mas ver §5 antes de comemorar.

---

### A3 — FATO: como o avatar do remetente é escolhido hoje

`components-next/message/Message.vue:737-775` — `avatarInfo`:

```js
// 738: echo externo → usa avatar da caixa de entrada
// 751: SE NÃO HÁ sender → cai em additionalAttributes.senderName / senderAvatarUrl  ← caminho Slack
// 763: sender é AgentBot/CaptainAssistant → avatarUrl
// 771: qualquer outro sender → { name: sender.name, src: sender.thumbnail }
```

Em mensagem de grupo, `sender` **existe** (é o contato-grupo), então cai sempre na linha 771 e
**todos os avatares do fio ficam iguais**: a foto do grupo, repetida. O ramo da linha 751-757 já
sabe usar um autor vindo de `additional_attributes` — está a um `if` de distância de servir a grupos.

Renderização: `Message.vue:863-872` (`[grid-area:avatar]`, `Avatar` de 28px à esquerda / 24px à
direita, com tooltip `avatarTooltip` = `"CONVERSATION.SENT_BY" + nome`, linha 777-783).
O avatar **só aparece na última mensagem de um bloco agrupado** (`v-if="!shouldGroupWithNext"`,
linha 864) — atenção, é o inverso do WhatsApp, que mostra na **primeira**.

Componente: `components-next/avatar/Avatar.vue`
- `:25` prop `accent` — **override de cor já suportado** (`{bg, text, darkBg, darkText}`)
- `:61-75` `AVATAR_COLORS` — 6 pares light + 6 pares dark, já calibrados
- `:104-115` `getColorsByNameLength` — escolhe por `props.name.length % 6`. **Determinístico mas fraco**:
  todo nome de 12 caracteres cai na mesma cor. Para grupo isso colide demais.
- `:283` `dark:!bg-[var(--dark-bg)] dark:!text-[var(--dark-text)]` — paridade light/dark já resolvida
  via CSS var inline.

---

### A4 — FATO: cabeçalho da conversa

`app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue`

| Elemento | Linha |
|---|---|
| `Thumbnail` (foto, 40px, `allow-preview`) | `:381-390` |
| Nome do contato (clicável, abre painel) | `:393-400` |
| Linha de presença ("online"/"digitando"/"visto por último") | `:409-419` |
| Subtítulo (`InboxName`, snooze, janela 24h, prioridade) | `:421-475` |
| Ações à direita (status, SLA, busca, `MoreActions`) | `:478-501` |

O header já mostra a foto do grupo — **30 dos 36 contatos-grupo desta base têm avatar anexado**
(query em `active_storage_attachments`), então a foto do grupo já chega. O que falta é: badge de grupo,
contagem de participantes, e o nome sem o sufixo `(Grupo)`.

A linha de presença (`presenceText`, `:135-139`) é **semanticamente errada para grupo** —
"visto por último" de um grupo não existe no WhatsApp; ali vai a lista de participantes.

---

### A5 — FATO: painel lateral

`app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`

- `:155` `<ContactInfo>` — bloco fixo do topo (avatar 120px, nome, e-mail/telefone, botões de ação)
- `:159-346` `<Draggable>` — as seções são **arrastáveis e ordenáveis pelo usuário**, cada uma um
  `<AccordionItem>` com um `v-else-if` por `element.name`.
- Registro de seções: `app/javascript/dashboard/composables/useUISettings.js:4-16`
  (`DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER`). O `:38-59` já tem migração automática: uma seção nova
  adicionada ao array default entra na lista de quem já tem ordem salva, sem quebrar.

**Onde caberia "Integrantes (N)":** novo `element.name === 'group_participants'` entre as linhas
219 e 220 do `ContactPanel.vue`, mais uma entrada no array de `useUISettings.js:4`.

⚠️ **Armadilha de nomenclatura:** já existe `conversation_participants`
(`ContactPanel.vue:202-219` → `ConversationParticipant.vue`). Isso é o **watchers do Chatwoot core**:
*agentes* que acompanham a conversa. Não tem nada a ver com integrantes do grupo de WhatsApp.
Chamar a seção nova de `conversation_participants` seria colisão. Use `group_participants` /
`GROUP_INFO.PARTICIPANTS`.

---

### A6 — FATO CONFIRMADO: não existe tratamento de grupo no front. Nenhum.

```
$ grep -rn "@g\.us" app/javascript --include=*.js --include=*.vue
(zero resultados relevantes — só falsos positivos de "avatar_url" e "username")

$ grep -rni "isGroup|is_group" app/javascript
(apenas isGroupByPossible, de relatórios — sem relação)
```

O único reconhecedor de grupo do produto inteiro está no back:
`enterprise/app/services/captain/behavior/router_service.rb:33-46`.

---

### A7 — FATO: componentes reutilizáveis que servem para a lista de integrantes

Reaproveitar > criar. Já existe:

| Componente | Caminho | Serve para |
|---|---|---|
| `AccordionItem` | `components/Accordion/AccordionItem.vue` | A casca da seção "Integrantes (N)". Tem slot `#button` no header (`:52`) — cabe o botão "Atualizar". |
| `Avatar` | `components-next/avatar/Avatar.vue` | Avatar por integrante, com `accent` para cor determinística. |
| `ThumbnailGroup` | `components/widgets/ThumbnailGroup.vue` | Pilha de avatares sobrepostos + "+N" — perfeito para o resumo colapsado da seção. |
| `MultiselectDropdownItems` | `shared/components/ui/MultiselectDropdownItems.vue` | Já é uma lista com busca + avatar + item selecionável. Base pronta para a lista longa com filtro. |
| `ConversationMedia` | `routes/dashboard/conversation/ConversationMedia.vue` | **Modelo de referência** de seção do painel: fetch no `onMounted`, agrupamento, paginação incremental de 9, estado vazio. Copiar a estrutura. |
| `ContactInfoRow` | `routes/dashboard/conversation/contact/ContactInfoRow.vue` | Linha ícone + label + valor. |
| `Icon` | `components-next/icon/Icon.vue` | `i-lucide-users`, `i-lucide-shield`, `i-lucide-user-x`. |

---

### A8 — FATO (verificado no banco): o que realmente chega ao front hoje

Consultas **somente SELECT** no Postgres de homologação.

**A8.1 — o LID está persistido no `content`, não é um artefato de renderização:**

```sql
select id, message_type, left(content,160) from messages where content like '%@lid%' order by id desc limit 8;
```
```
34084|0|👥 *Walisson (60756640940218@lid)*\n\nVish\n`🗓️ Hoje, 02 de mai. • 18:26 BRT`
33966|0|👥 *‎Rogerio José Da Silva (229480102662169@lid)*\n\nquando cheegar quero ver umas coisa no fw com vc
```
Total: **548** mensagens com `@lid` no corpo nesta base.

**A8.2 — não há metadado de autor. Nenhum:**

```sql
select id, sender_type, sender_id, additional_attributes::text, content_attributes::text
  from messages where id = 33966;
```
```
33966 | Contact | 1963 | {} | {}
```

**A8.3 — o `sender` é o contato-grupo, o mesmo para todo o fio:**

```sql
select id, name, phone_number, identifier, custom_attributes::text from contacts where id = 1963;
```
```
1963 | Simplex - Uptime (Grupo) | (vazio) | 120363403758104643@g.us
     | {"waha_whatsapp_chat_id": "120363403758104643@g.us"}
```
```sql
select count(distinct sender_id) from messages where conversation_id = 2446;  -- → 2
```
(2 = o contato-grupo nas incoming + o agente nas outgoing. Nunca a pessoa que falou.)

**A8.4 — ⚠️ CORREÇÃO AO BRIEFING: três sufixos convivem, não só `(GROUP)`:**

```sql
select id, name, identifier from contacts where identifier like '%@g.us' order by id desc limit 15;
```
```
1987 | Astra online #1 (Grupo)                              | 120363403210205427@g.us
1977 | Simplex - Notificações (Grupo)                        | 120363421242156930@g.us
1975 | COMUNIDADE DOS VILAS DE SINOP 🏠 (Group)              | 120363201678176528@g.us
1973 | Desapegue sinop (Group)                              | 120363220960547202@g.us
 853 | Residencial - Carandá Bosque 🏠 (GROUP)               | 120363317690481563@g.us
 833 | Suporte 24h | Sentinela (GROUP)                       | 120363328254485268@g.us
```
36 contatos-grupo no total. O sufixo migrou `(GROUP)` → `(Group)` → `(Grupo)` conforme a idade do
registro. **Isso é evidência de código externo versionado**, não de uma constante do Rails —
reforça a hipótese do briefing sobre receptor/n8n.

**A8.5 — a reação é uma MENSAGEM de texto no fio, não um chip:**

```sql
select id, replace(left(content,240), chr(10),' \n ') from messages where content like '%eagiu com%' order by id desc limit 6;
```
```
32957 | 👥 *Paulo Moggi (20942428352717@lid)* \n  \n *Reagiu com* 🤨
32235 | *Reagiu com* 🚀
31789 | *📱 Enviado do WhatsApp* \n 🚨 **Nova mensagem do cliente!** \n 👤 **Responsável:** Jorge Miguel
      | \n 🙍‍♂️ **Cliente:** Rozangela Cristina \n 💬 **Mensagem (às 15:12):** \n "**Reagiu com** 👍"
```

E `grep -rn "Reagiu com" app/ lib/ enterprise/ config/` → **zero resultados**. Confirma: montado fora
do Rails. (O último registro mostra um envelope de notificação inteiro — outra camada externa
empacotando texto. Fora do meu escopo, mas é evidência para W1/W2.)

**A8.6 — o back JÁ tem reações estruturadas e o front não usa:**

`app/views/api/v1/models/_message.json.jbuilder:28` — `json.reactions` (mapa `emoji => count`).
`components-next/message/Message.vue:156` — prop `reactions: Array` declarada… **e nunca usada** no
`<template>`. `MessageReactions.vue` (127 linhas, funcional, com picker e chips agregados) **não é
importado por nenhum arquivo** — `grep -rn "MessageReactions" app/javascript` retorna vazio.
As reações renderizadas hoje são só as do chat interno
(`routes/dashboard/internalChat/components/redesign/MessageBubble.vue:98`).

**A8.7 — o canal de entrega do autor já está aberto:**

`app/views/api/v1/models/_message.json.jbuilder:17` → `json.additional_attributes` (REST)
`app/models/message.rb:160-172` → `attributes.symbolize_keys` inclui `additional_attributes` (websocket)
`components-next/message/Message.vue:151` → prop `additionalAttributes` já declarada e repassada
`components-next/message/MessageList.vue:105` → `useCamelCase(deep: true)` cameliza tudo

⇒ Um `additional_attributes.group_author = {name, phone, lid, avatar_url, role}` gravado na ingestão
**chega ao componente sem uma linha de mudança no serializer, no store ou na API**. Esse é o menor
caminho estrutural.

---

## 2. Referência: como o WhatsApp resolve isso

O produto tem direção estética "WhatsApp-fiel" aprovada e o skin já existe
(`app/javascript/dashboard/assets/scss/_wa-skin.scss`, 3334 linhas, tokens light/dark).
O agente já conhece o WhatsApp — copiar o comportamento reduz treinamento a zero.

**2.1 — Nome do autor acima da bolha.** Em conversa de grupo (e **só** em grupo), cada bolha
recebida traz o nome do remetente em negrito, tamanho menor que o corpo, **colorido**, na primeira
linha dentro da bolha. Cada participante recebe uma cor de uma paleta fixa, atribuída de forma
determinística a partir da identidade da pessoa — o mesmo participante mantém a mesma cor durante
toda a conversa. A cor pode diferir entre grupos distintos, e branco nunca é atribuído.
([Intertoons](https://intertoons.com/logic-behind-whatsapp-group-member-color.html))

**2.2 — Agrupamento por autor.** Mensagens consecutivas do mesmo autor formam um bloco: o nome
aparece **só na primeira** bolha do bloco; as seguintes vêm sem nome e com o canto superior
"reto" (sem a ponta/tail). Só a primeira bolha do bloco tem a tail apontando para o avatar.

**2.3 — Avatar do autor.** No WhatsApp Web, em grupo, o avatar do autor fica à esquerda, alinhado à
**primeira** bolha do bloco. Sem foto, cai em iniciais sobre cor sólida derivada da mesma paleta.

**2.4 — Citação/reply.** O bloco de citação acima do texto mostra **o nome do autor citado**, na cor
dele, e uma prévia truncada do conteúdo. Clicar rola até a mensagem original.

**2.5 — Reações.** Agregadas como chips abaixo da bolha (`👍 3`), nunca como mensagem no fio. Tocar
o chip abre a lista de quem reagiu, agrupada por emoji.

**2.6 — Painel "Dados do grupo".** Aberto ao clicar no nome no cabeçalho. Contém: foto grande, nome,
`"Grupo · N participantes"`, descrição, mídia, e a lista de participantes. Os **administradores
aparecem primeiro com um badge "Admin"**; o restante segue em ordem alfabética.
([WhatsApp Help Center](https://faq.whatsapp.com/633713745095781/), [Alphr](https://www.alphr.com/whatsapp-find-group/))
Tocar num participante abre uma folha de ações: "Enviar mensagem", "Ver contato", "Info".

**2.7 — Eventos de sistema.** Entradas/saídas/mudança de assunto aparecem como pílulas centralizadas
no fio, sem avatar e sem bolha ("Fulano entrou usando o link de convite", "Beltrano saiu",
"Ciclano mudou o assunto do grupo para X"). O ChatSPX já tem exatamente essa primitiva:
`MESSAGE_VARIANTS.ACTIVITY` → `bubbles/Activity.vue`, centralizada por `Message.vue:387`.

**2.8 — O que a WAHA entrega** (para saber o que é honestamente exibível):
`GET /api/{session}/groups/{id}` (subject, description, invite),
`GET /api/{session}/groups/{id}/participants/v2` (`id`, `role` ∈ `participant|admin|superadmin|left`),
`GET /api/{session}/groups/{id}/picture`.
([WAHA — Groups](https://waha.devlike.pro/docs/how-to/groups/))
⇒ o `id` do participante pode vir como `@lid` **ou** `@c.us`. O design **precisa** tratar o caso
"tenho o participante mas não sei quem é" como estado de primeira classe (§3.4).

---

## 3. Design proposto para o ChatSPX

### 3.1 — Bolha de mensagem de grupo

Regra: **o nome do autor só aparece quando a conversa é de grupo e a mensagem é `incoming`.**
Conversas 1:1 ficam **pixel-idênticas ao que são hoje** — mudança zero de risco.

**Bloco de 2 mensagens consecutivas do mesmo autor + 1 de outro:**

```
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  ╭───╮  ┌────────────────────────────────────────────╮                   │
│  │ R │  │ Rogerio José Da Silva          ← nome, cor determinística,     │
│  ╰───╯  │                                  13px, semibold, sem telefone  │
│  ↑      │ quando chegar quero ver umas coisas no fw   │                   │
│  avatar │                                   09:41 ✓✓ │                   │
│  28px   ╰────────────────────────────────────────────╯  ← canto ⌐ reto  │
│  só na  ┌────────────────────────────────────────────╮     (segue bloco) │
│  1ª     │ e o wifi do 2º andar tá caindo             │                   │
│         │                                   09:41 ✓✓ │                   │
│         ╰────────────────────────────────────────────╯                   │
│                                                                          │
│  ╭───╮  ┌────────────────────────────────────────────╮                   │
│  │ A │  │ Angela Tozi                    ← outra cor  │                   │
│  ╰───╯  │ TOZIADM                                     │                   │
│         │                                   09:43 ✓✓ │                   │
│         ╰────────────────────────────────────────────╯                   │
└──────────────────────────────────────────────────────────────────────────┘
```

**O telefone/LID NUNCA aparece no corpo.** Ele vive em três lugares e só neles:

```
  hover no nome ─┐
                 ▼
        ┌──────────────────────────────────┐
        │ Rogerio José Da Silva            │
        │ +55 66 9 9999-1234               │   ← tooltip
        │ Toque para ver o contato         │
        └──────────────────────────────────┘

  hover no avatar → mesmo tooltip (reaproveita `avatarTooltip`, Message.vue:777)
  clique no nome  → abre o painel do integrante / conversa 1:1
```

**Autor não identificado** (só temos o LID, sem nome nem telefone resolvido):

```
  ╭───╮  ┌────────────────────────────────────────────╮
  │ ? │  │ Participante não identificado    ⓘ         │  ← itálico, cor neutra
  ╰───╯  │                                             │     (n-slate-11), NUNCA colorida
  cinza  │ bom dia pessoal                             │
         │                                   08:12     │
         ╰────────────────────────────────────────────╯

  hover no ⓘ → "O WhatsApp não informou quem enviou esta mensagem.
                Sincronize os integrantes do grupo para tentar identificar."
```

Regra dura: **nunca renderizar `229480102662169@lid` na interface.** Nem no corpo, nem no tooltip,
nem no `title`. Se um dia for preciso para depuração, vai no `data-*` do DOM ou num "Copiar ID
técnico" dentro do menu de contexto — não em texto visível.

**Variante com telefone mas sem nome** (caso comum e honesto):

```
  ╭───╮  ┌────────────────────────────────────────────╮
  │ 66 │  │ +55 66 9 9999-1234                        │  ← o número É o nome; cor determinística
  ╰───╯  │ boa tarde                                   │     derivada do número
```

---

### 3.2 — Cabeçalho da conversa de grupo

```
┌────────────────────────────────────────────────────────────────────────────────┐
│  ╭────╮  TI TOZI - Inovação  👥                        [Resolver] [🔍] [⋮]     │
│  │foto│  ← sem o sufixo "(Grupo)"  ↑ badge                                     │
│  │ 40 │     badge de grupo         i-lucide-users, 14px, n-slate-11            │
│  ╰────╯  12 participantes · Suporte WhatsApp · ⏱ 18h restantes                 │
│           ↑ clicável → abre painel   ↑ InboxName    ↑ janela 24h (já existe)   │
└────────────────────────────────────────────────────────────────────────────────┘
```

Decisões:
- **A linha "12 participantes" substitui a linha de presença** (`presenceText`,
  `ConversationHeader.vue:409-419`) quando é grupo. "Visto por último" de um grupo não faz sentido e
  hoje mostraria o `last_seen_at` do contato-grupo — um dado sem significado.
- **O sufixo `(Grupo)`/`(Group)`/`(GROUP)` é removido só na exibição** por um helper
  (`stripGroupSuffix`), enquanto a origem não for corrigida. É cosmético e reversível.
- **Sem sync:** a linha vira `Grupo · integrantes não sincronizados` com um link "Sincronizar".
- Clicar no nome já abre o painel hoje (`toggleContactPanel`, `:397`) — mantém.

---

### 3.3 — Painel lateral: "Integrantes (N)"

Nova seção arrastável, posicionada **logo abaixo de "Mídias e Arquivos"** por padrão (é a segunda
coisa que o agente procura num grupo). Renderiza **apenas** quando a conversa é de grupo.

**Estado normal:**

```
┌────────────────────────────────────────────────┐
│ ▾  Integrantes (12)                    [ ⟳ ]   │  ← AccordionItem + slot #button
├────────────────────────────────────────────────┤
│  🔍 Buscar integrante…                         │  ← só aparece se N > 8
│                                                │
│  ╭──╮ Angela Tozi                    [Admin]   │  ← admins primeiro
│  │AT│ +55 66 9 9111-2233                       │
│  ╰──╯                                          │
│  ╭──╮ Rogerio José Da Silva          [Admin]   │
│  │RS│ +55 66 9 9999-1234                       │
│  ╰──╯                                          │
│  ─────────────────────────────────────────────  │
│  ╭──╮ Ederson Ricieri Davi                     │  ← demais em ordem alfabética
│  │ED│ +55 66 9 8888-4321                       │
│  ╰──╯                                          │
│  ╭──╮ Walisson                                 │
│  │ W│ +55 66 9 7777-0001                       │
│  ╰──╯                                          │
│  ╭──╮ Participante não identificado        ⓘ   │  ← itálico, cinza, sem cor
│  │? │ —                                        │     ordenado por último
│  ╰──╯                                          │
│                                                │
│         Ver todos os 12 integrantes            │  ← se N > 8, mostra 8 + link
│                                                │
│  Sincronizado há 4 min                         │  ← rodapé discreto, 11px
└────────────────────────────────────────────────┘
```

Por linha: **avatar 32px** (foto do WhatsApp se houver, senão iniciais na cor determinística do
autor — a mesma cor da bolha, o que amarra visualmente as duas telas), **nome**, **telefone
mascarado**, **badge de admin**.

Mascaramento do telefone: `+55 66 9 9999-1234` (formatado, completo) para quem tem permissão de ver
contato; `+55 66 9 ****-1234` para papéis restritos, seguindo a política que a conta já usar. Se não
houver telefone: `—`, nunca o LID.

**Ordenação:** (1) admins A→Z, (2) demais A→Z, (3) não identificados por último, (4) quem saiu
(`role: left`) fora da lista principal — ver estados degradados.

**Ação de clique — recomendação:** abrir um **popover de ações**, não navegar direto. Navegar direto
para uma conversa 1:1 é destrutivo demais (pode criar conversa nova sem querer, e tira o agente do
grupo que ele está lendo):

```
        clique numa linha
                ▼
   ┌──────────────────────────────────┐
   │  ╭──╮ Angela Tozi        [Admin] │
   │  │AT│ +55 66 9 9111-2233         │
   │  ╰──╯                            │
   │ ──────────────────────────────── │
   │  💬  Abrir conversa 1:1          │  ← só se já existir contato resolvido
   │  👤  Ver contato                 │
   │  📋  Copiar telefone             │
   └──────────────────────────────────┘
```

Se o participante não tem contato correspondente no ChatSPX, "Abrir conversa 1:1" fica desabilitado
com tooltip `"Este integrante ainda não tem um contato no ChatSPX"` — honesto, sem link morto.

**Estado carregando:**

```
┌────────────────────────────────────────────────┐
│ ▾  Integrantes                                 │
├────────────────────────────────────────────────┤
│  ▨▨▨  ▨▨▨▨▨▨▨▨▨▨▨▨                             │  ← 3 linhas skeleton
│  ▨▨▨  ▨▨▨▨▨▨▨▨                                 │     (shimmer, prefers-reduced-motion respeitado)
│  ▨▨▨  ▨▨▨▨▨▨▨▨▨▨                               │
└────────────────────────────────────────────────┘
```

**Estado vazio / nunca sincronizado:**

```
┌────────────────────────────────────────────────┐
│ ▾  Integrantes                                 │
├────────────────────────────────────────────────┤
│              ╭─────────╮                       │
│              │   👥    │                       │
│              ╰─────────╯                       │
│    Integrantes ainda não sincronizados         │
│    O ChatSPX ainda não recebeu a lista de      │
│    participantes deste grupo.                  │
│                                                │
│           [ Sincronizar agora ]                │
└────────────────────────────────────────────────┘
```

---

### 3.4 — Estados de erro e degradado

| Situação | O que a UI mostra | Onde |
|---|---|---|
| Grupo nunca sincronizado | Empty state acima + CTA "Sincronizar agora" | Painel |
| WAHA fora do ar / falha no fetch | Barra `⚠ Não foi possível carregar os integrantes` + `[Tentar novamente]`. **Mantém a última lista em cache visível, marcada como desatualizada** ("Sincronizado há 3 dias") | Painel |
| Sync parcial (N ids, M nomes) | Lista normal + rodapé `3 de 12 integrantes ainda não identificados` | Painel |
| Participante só com LID | Linha "Participante não identificado" + ⓘ. Nunca o LID. | Painel + bolha |
| Participante que saiu (`role: left`) | Fora da lista principal, num sub-bloco recolhido `Saíram do grupo (2)`. Na bolha, mensagens antigas dele mantêm nome + `(saiu do grupo)` em cinza no tooltip | Painel + bolha |
| Grupo do qual a sessão saiu | Banner no topo do fio: `Você não faz mais parte deste grupo. Não é possível enviar mensagens.` + composer desabilitado | Fio |
| Autor da mensagem não bate com nenhum integrante da lista | Renderiza o nome que veio na mensagem, sem link de ação; sem inventar vínculo | Bolha |

Princípio: **degradar mostrando menos, nunca mostrando errado.** Preferimos "não identificado" a um
nome adivinhado, e preferimos "desatualizado" a uma lista vazia.

---

### 3.5 — Reações e replies com autor

**Reação (corrigir a regressão do A8.6):** parar de tratar reação como mensagem no fio; renderizar
como chip agregado colado na bolha, no padrão WhatsApp:

```
   ┌────────────────────────────────────────────╮
   │ Angela Tozi                                 │
   │ Resolvido ✅                                │
   │                                   09:03 ✓✓ │
   ╰──────────────────────────────╯              │
      ╭────────╮ ╭───────╮
      │ 👍  2  │ │ 🎉  1 │      ← chips; hover → "Rogerio, Walisson"
      ╰────────╯ ╰───────╯         clique → lista de quem reagiu
```

`MessageReactions.vue` já implementa exatamente isso (chips agregados + contagem + toggle) — falta
**importá-lo** em `Message.vue` e passar `:reactions` (que já existe como prop na linha 156 e já é
serializado em `_message.json.jbuilder:28`). Custo baixíssimo, ganho alto.

**Reply com autor** (`ReplyPreview.vue` hoje só mostra o texto, `:115-119`):

```
   ┌────────────────────────────────────────────╮
   │ ┃ Angela Tozi              ← nome do autor citado, NA COR DELE
   │ ┃ Alguém consegue olhar o Wi-Fi?           │  ← barra vertical colorida à esquerda
   │ ───────────────────────────────────────────│
   │ Já estou indo lá                            │
   │                                   09:44 ✓✓ │
   ╰────────────────────────────────────────────╯
```

A barra vertical à esquerda da citação usa a cor do autor citado — é o que faz o agente identificar
a thread de relance, sem ler.

---

### 3.6 — Cores por autor: como derivar (acessibilidade + dark mode)

O ChatSPX exige paridade light/dark. Regras concretas:

1. **Chave do hash = identidade estável, não o nome.** Ordem de preferência:
   `lid` → `phone` → `name`. Usar o nome como chave faz a cor mudar quando a pessoa muda o nome no
   WhatsApp — inaceitável. E **não** usar `name.length` (é o que `Avatar.vue:108` faz hoje: 6 baldes,
   colisão garantida num grupo de 12).

2. **Hash determinístico simples e estável** (FNV-1a ou djb2 sobre a chave) → `hash % PALETTE.length`.
   Determinístico ⇒ o mesmo participante tem a mesma cor em toda sessão, em todo dispositivo, sem
   estado persistido.

3. **Paleta de 12+ pares**, declarada em `_wa-skin.scss` junto dos outros tokens
   (`--wa-author-1` … `--wa-author-12` e `--wa-author-N-dark`). Doze cobre a maioria dos grupos de
   trabalho; acima disso a repetição é aceitável (o WhatsApp também repete).

4. **Contraste verificado nos dois temas, não estimado.** O repo já tem a ferramenta:
   `shared/helpers/colorHelper.js:12` `adjustColorForContrast(color, backgroundColor)` (color2k,
   itera até atingir a razão alvo). Alvo: **≥ 4.5:1** para o nome do autor — é texto pequeno
   (13px) e portador de informação, então WCAG AA de texto normal, não a régua de 3:1 de texto
   grande que a função usa por padrão hoje. Backgrounds a validar: `--wa-bubble-in` (#ffffff) no
   light e `--wa-bubble-in-dark` (#202c33) no dark. **Duas verificações, não uma** — uma cor que
   passa no branco costuma reprovar no #202c33.

5. **A cor nunca é o único portador de significado.** O nome está escrito por extenso ao lado; a cor
   é reforço. Isso resolve daltonismo e é o que permite usar 12 cores sem virar ruído.

6. **O avatar usa a MESMA cor** via a prop `accent` que `Avatar.vue:25` já aceita — nome e avatar
   sempre concordam, na bolha e no painel.

7. **Cor reservada:** participante não identificado recebe **neutro** (`n-slate-11`), fora da paleta.
   Cinza comunica "não sei quem é" sem precisar de texto adicional.

---

## 4. Ganho rápido (Fase 0) no front — análise honesta

**A pergunta:** existe um ponto único onde `👥 *Nome (lid@lid)*` poderia ser saneado para exibição
imediata, sem migration e sem tocar na ingestão?

**Resposta: sim, existe** — `shared/helpers/MessageFormatter.js:62-73` (o construtor). Um regex
aplicado ali (`/\((\d{10,})@lid\)/g` → remover; e opcionalmente `/^👥\s*/` → remover) cobriria
**todas** as superfícies do dashboard de uma vez (§A2): bolha, lista de conversas, busca, Kanban,
menu de contexto. É uma mudança de ~5 linhas, sem migration, sem deploy de backend, reversível por
`git revert`.

### O que essa mudança realmente entrega

| | |
|---|---|
| ✅ | O agente para de ver `(229480102662169@lid)` no meio da frase, hoje |
| ✅ | Custo mínimo, risco mínimo, reversível em um commit |
| ✅ | Cobre todas as telas do dashboard de uma vez |
| ❌ | **Não devolve o autor como dado.** Continua sendo texto dentro do `content`, não um campo. Nada de avatar por autor, nada de cor, nada de agrupamento correto, nada de lista de integrantes |
| ❌ | **Não conserta a busca.** `messages.content` continua com o LID; a busca do servidor casa com ele, e uma busca por "Rogerio" continua trazendo lixo formatado |
| ❌ | **Não conserta a IA.** O Captain lê `content` do banco. O prompt continua recebendo `👥 *Nome (229480102662169@lid)*` — ruído que gasta token e confunde o classificador |
| ❌ | **Não conserta relatórios, export, transcript e notificação push** — todos leem `content` no backend, longe do `MessageFormatter` |
| ❌ | **Mascara o problema.** Depois que a tela fica limpa, a pressão para consertar a origem cai a zero. Em 3 meses ninguém lembra que o banco tem 548 mensagens sujas — e a cada mês entram mais |
| ⚠️ | **Risco de regex.** `\d{10,}@lid` é específico o bastante para ser seguro, mas todo saneamento por regex sobre conteúdo de usuário tem falso positivo. Alguém colando um LID legítimo numa mensagem teria o texto alterado silenciosamente |

### Recomendação

**Fazer a Fase 0 — mas com três condições explícitas, senão ela vira a solução final por inércia.**

1. **Saneie para exibição, sim, mas trate como analgésico, não como tratamento.** O commit da Fase 0
   deve conter, no próprio código, um comentário apontando para o issue da correção na origem. Sem
   isso, o débito some do radar.

2. **Prefira sanear no ponto único de formatação a espalhar por componente.** Um helper dedicado
   (`sanitizeWhatsappGroupPrefix`) chamado de dentro do construtor de `MessageFormatter` — e **não**
   um regex inline em cada `.vue`. Um lugar para achar, um lugar para remover quando a origem for
   corrigida.

3. **Comece a correção na origem em paralelo, não depois.** O caminho estrutural correto é gravar
   `additional_attributes.group_author` na ingestão (§A8.7) — o canal até o componente **já está
   aberto** (serializer, websocket, prop e camelização já existem). Do lado do front, isso é a
   diferença entre "o texto ficou menos feio" e "o agente sabe quem falou". A Fase 0 compra tempo
   para essa correção; ela não substitui a correção.

**Sobre remover o prefixo `👥`:** eu **não** removeria na Fase 0. Enquanto não houver autor
estruturado, o `👥 Nome` é literalmente a única indicação de quem falou. Tirá-lo antes de ter o
substituto **piora** a experiência — o agente perde a informação e não ganha nada. Remover só o
`(lid@lid)`, que é puro ruído, e deixar o `👥 Nome` até o autor estruturado estar no ar.

---

## 5. i18n

Prioridade do produto: **pt-BR primeiro**, depois `en`.

**Arquivos:**
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` (**prioridade**)
- `app/javascript/dashboard/i18n/locale/en/conversation.json`

**Namespace novo, no topo do arquivo, ao lado de `CONVERSATION_PARTICIPANTS`** (que já existe e é dos
watchers — ver §A5, não colidir):

```jsonc
"GROUP_INFO": {
  "BADGE":                      "Grupo",
  "PARTICIPANTS_COUNT":         "{count} participantes",
  "PARTICIPANTS_COUNT_ONE":     "1 participante",
  "SIDEBAR_TITLE":              "Integrantes",
  "SIDEBAR_TITLE_WITH_COUNT":   "Integrantes ({count})",
  "SEARCH_PLACEHOLDER":         "Buscar integrante…",
  "ADMIN_BADGE":                "Admin",
  "SUPER_ADMIN_BADGE":          "Criador",
  "SHOW_ALL":                   "Ver todos os {count} integrantes",
  "SHOW_LESS":                  "Ver menos",

  "UNKNOWN_PARTICIPANT":        "Participante não identificado",
  "UNKNOWN_PARTICIPANT_HINT":   "O WhatsApp não informou quem enviou esta mensagem. Sincronize os integrantes do grupo para tentar identificar.",
  "NO_PHONE":                   "Telefone não disponível",

  "LEFT_GROUP":                 "saiu do grupo",
  "LEFT_GROUP_SECTION":         "Saíram do grupo ({count})",
  "NOT_IN_GROUP_BANNER":        "Você não faz mais parte deste grupo. Não é possível enviar mensagens.",

  "EMPTY_TITLE":                "Integrantes ainda não sincronizados",
  "EMPTY_BODY":                 "O ChatSPX ainda não recebeu a lista de participantes deste grupo.",
  "SYNC_NOW":                   "Sincronizar agora",
  "SYNCING":                    "Sincronizando…",
  "SYNCED_AT":                  "Sincronizado {relative}",
  "NOT_SYNCED":                 "Integrantes não sincronizados",
  "PARTIALLY_RESOLVED":         "{unresolved} de {total} integrantes ainda não identificados",

  "LOAD_ERROR":                 "Não foi possível carregar os integrantes",
  "LOAD_ERROR_RETRY":           "Tentar novamente",
  "STALE_WARNING":              "Esta lista pode estar desatualizada",

  "ACTIONS": {
    "OPEN_DM":                  "Abrir conversa 1:1",
    "OPEN_DM_DISABLED":         "Este integrante ainda não tem um contato no ChatSPX",
    "VIEW_CONTACT":             "Ver contato",
    "COPY_PHONE":               "Copiar telefone",
    "PHONE_COPIED":             "Telefone copiado"
  },

  "SENT_BY_IN_GROUP":           "Enviado por {name} neste grupo",
  "REPLYING_TO":                "Respondendo a {name}"
}
```

Complementos em blocos **já existentes** do mesmo arquivo:

```jsonc
// dentro de CONVERSATION_SIDEBAR.ACCORDION (para o rótulo da seção arrastável)
"GROUP_PARTICIPANTS": "Integrantes do grupo"

// dentro de CONVERSATION.REACTIONS (o bloco já existe — PICKER_TOOLTIP está em uso)
"REACTED_BY":       "Reagiram: {names}",
"REACTED_BY_YOU":   "Você e mais {count}"
```

Notas de tradução:
- pt-BR usa **"Integrantes"** no painel e **"participantes"** na contagem do cabeçalho — é o
  vocabulário do WhatsApp em pt-BR, e o agente reconhece.
- `Admin` fica **sem tradução** — é como aparece no WhatsApp brasileiro.
- `SYNCED_AT` recebe `{relative}` já formatado por `date-fns` (o header já faz isso em
  `ConversationHeader.vue:127-128` com `formatDistanceToNowStrict`); não montar a string no JSON.
- Plural: o projeto usa chaves separadas (`TOTAL_PARTICIPANT_TEXT` / `TOTAL_PARTICIPANTS_TEXT` em
  `CONVERSATION_PARTICIPANTS`) em vez de pluralização do vue-i18n. Seguir a convenção da casa.

---

## 6. Pontos de intervenção (arquivo:linha)

Nada disto foi implementado — é o mapa para quem for implementar.

### Fase 0 — saneamento de exibição (front-only, ~5 linhas)

| # | Arquivo:linha | Mudança |
|---|---|---|
| 0.1 | `app/javascript/shared/helpers/MessageFormatter.js:62-73` | No construtor, passar `this.message` por um `sanitizeWhatsappGroupPrefix()` antes de guardar. Remove só `(\d{10,}@lid)`; **mantém** o `👥 Nome` |
| 0.2 | `app/javascript/shared/helpers/` (arquivo novo) | O helper isolado + comentário apontando para o issue da correção na origem |
| 0.3 | `app/javascript/shared/helpers/specs/` | Spec do helper: com LID, sem LID, LID no meio da frase, texto do usuário contendo `@lid` legítimo |

### Fase 1 — autor por mensagem (depende de `additional_attributes.group_author` vir do back)

| # | Arquivo:linha | Mudança |
|---|---|---|
| 1.1 | `components-next/message/provider.js:1-164` | Expor `groupAuthor` e `isGroupConversation` no contexto da mensagem |
| 1.2 | `components-next/message/Message.vue:737-775` (`avatarInfo`) | Novo ramo **antes** da linha 759: se `additionalAttributes.groupAuthor` existir e for `incoming`, usar nome/avatar/accent do autor |
| 1.3 | `components-next/message/Message.vue:863-872` | Inverter a regra do avatar em grupo: mostrar na **primeira** do bloco (WhatsApp), não na última (`v-if="!shouldGroupWithNext"`) |
| 1.4 | `components-next/message/bubbles/Base.vue:90-97` | Inserir o `<GroupAuthorLabel>` acima do bloco de `inReplyTo`, condicionado a grupo + incoming + primeira do bloco |
| 1.5 | `components-next/message/MessageList.vue:265-290` (`shouldGroupWithNext`) | Comparar também o autor do grupo — hoje compara só `senderId`, que em grupo é sempre o mesmo contato e **agrupa pessoas diferentes no mesmo bloco** ⚠️ regressão silenciosa hoje |
| 1.6 | `components-next/avatar/Avatar.vue:104-115` | **Não alterar.** Passar `accent` de fora (a prop já existe na linha 25); a lógica de hash mora no helper novo |
| 1.7 | `shared/helpers/` (arquivo novo) | `authorColor.js`: hash determinístico (lid→phone→name) + paleta + `adjustColorForContrast` (`colorHelper.js:12`) |
| 1.8 | `assets/scss/_wa-skin.scss:14-44` (bloco `:root`) | Tokens `--wa-author-1..12` + `--wa-author-N-dark` |
| 1.9 | `components-next/message/bubbles/ReplyPreview.vue:112-119` | Mostrar o autor citado (nome na cor dele) acima do texto |

### Fase 2 — cabeçalho de grupo

| # | Arquivo:linha | Mudança |
|---|---|---|
| 2.1 | `components/widgets/conversation/ConversationHeader.vue:393-400` | Nome sem sufixo `(Grupo)/(Group)/(GROUP)` + badge `i-lucide-users` |
| 2.2 | `components/widgets/conversation/ConversationHeader.vue:409-419` | Em grupo, trocar `presenceText` por `GROUP_INFO.PARTICIPANTS_COUNT` |
| 2.3 | `dashboard/composables/` (arquivo novo) | `useGroupConversation.js`: `isGroup` (via `contact.identifier.endsWith('@g.us')` ou `custom_attributes.waha_whatsapp_chat_id`), `participants`, `syncState` |

### Fase 3 — painel de integrantes

| # | Arquivo:linha | Mudança |
|---|---|---|
| 3.1 | `dashboard/composables/useUISettings.js:4-16` | Adicionar `{ name: 'group_participants' }` ao array default (a migração automática das linhas 38-59 cuida de quem já tem ordem salva) |
| 3.2 | `routes/dashboard/conversation/ContactPanel.vue:219-220` | Novo bloco `v-else-if="element.name === 'group_participants'"` com `AccordionItem` |
| 3.3 | `routes/dashboard/conversation/` (arquivo novo) | `GroupParticipants.vue` — espelhar a estrutura de `ConversationMedia.vue:1-90` (fetch no mount, agrupamento, paginação incremental, empty state) |
| 3.4 | `components-next/` (arquivo novo) | `GroupParticipantRow.vue` — `Avatar` (com `accent`) + nome + telefone + badge + popover de ações |
| 3.5 | `dashboard/api/` (arquivo novo) | Cliente do endpoint de participantes (a rota back ainda não existe — ver Lacunas) |
| 3.6 | `dashboard/store/modules/` (arquivo novo) | Módulo `groupParticipants` com `uiFlags.isFetching` / `isSyncing` — seguir o padrão de `conversationWatchers` |

### Fase 4 — reações e eventos (correções de regressão)

| # | Arquivo:linha | Mudança |
|---|---|---|
| 4.1 | `components-next/message/Message.vue:156` + `:929` | Importar e renderizar `MessageReactions.vue` (hoje órfão) passando `:reactions` — já serializado em `_message.json.jbuilder:28` |
| 4.2 | `components-next/message/MessageReactions.vue:22-32` | Adaptar `aggregated` ao formato `{emoji: count}` do serializer (hoje espera `{userId: [emoji]}`) |
| 4.3 | `components-next/message/bubbles/Activity.vue` | Usar para eventos de sistema do grupo (entrou/saiu/mudou assunto) — a primitiva centralizada já existe (`Message.vue:387`, `MESSAGE_VARIANTS.ACTIVITY`) |

---

## 7. Lacunas / o que não consegui verificar

1. **NÃO CONFIRMADO — quem monta `👥 *Nome (lid@lid)*`.** Confirmei que **não é o Rails**
   (`grep -rn "Reagiu com" app/ lib/ enterprise/ config/` → zero; o emoji 👥 não aparece em código de
   ingestão). A variação `(GROUP)`/`(Group)`/`(Grupo)` correlacionada com a idade do contato aponta
   para camada externa versionada, mas **não abri o receptor/n8n** — está fora do meu escopo (W1/W2).

2. **NÃO CONFIRMADO — se a WAHA devolve a foto individual de cada participante.** A doc lista
   `GET /groups/{id}/picture` (foto **do grupo**). Para a foto de cada participante o caminho
   provável é `GET /contacts/profile-picture`, mas **não testei contra a API** (a blindagem permite
   GET, mas preferi não tocar a instância sem necessidade). **O design não depende disso** — o
   fallback de iniciais coloridas cobre 100% dos casos e é o que o WhatsApp faz.

3. **NÃO CONFIRMADO — o endpoint back de participantes não existe.** `Waha::ApiService` não tem
   método para `/groups/{id}/participants` (confirmado no briefing) e não há rota Rails que exponha
   isso. A Fase 3 do front **está bloqueada** por essa dependência de backend. Marquei o ponto 3.5
   como "rota ainda não existe".

4. **NÃO VERIFIQUEI VISUALMENTE.** Não rodei Playwright nem dev server (restrição da tarefa). Os
   mockups são derivados da leitura do código e do skin, não de captura de tela. Antes de dar
   qualquer fase como pronta, a regra da casa vale: validação Playwright em **light e dark**.

5. **NÃO MEDI os contrastes.** Recomendei ≥ 4.5:1 e apontei a ferramenta
   (`colorHelper.js:12`) e os dois backgrounds a testar (`#ffffff` e `#202c33`), mas **não rodei os
   cálculos** para uma paleta concreta de 12 cores. Isso precisa ser feito com números antes de
   fechar os tokens do `_wa-skin.scss`.

6. **NÃO INVESTIGUEI** a superfície mobile/app nem o widget — só o dashboard do agente.

7. **Escopo declarado da §4:** avaliei o saneamento **no front**. Se o time preferir sanear no
   backend (no `content` gravado, ou num `webhook_content`), isso muda a análise de custo/benefício —
   mas aí já não é "sem tocar na ingestão".

---

## 8. Implicações para a solução

**O que este mapa habilita:**

- O canal de dados até o componente **já está aberto**: gravar `additional_attributes.group_author`
  na ingestão faz o autor chegar em `Message.vue` sem tocar em serializer, store, API ou websocket.
  Isso torna a Fase 1 (autor por mensagem) muito mais barata do que parecia — é essencialmente um
  ramo novo em `avatarInfo` + um label na bolha.
- O agrupamento, o skin light/dark, a paleta de avatar com override, o accordion arrastável do painel
  e a verificação de contraste **já existem**. Quase nada precisa ser criado do zero.
- Duas correções de regressão (reações órfãs, reply sem autor) dão ganho visível com custo baixo e
  são independentes do trabalho de grupo — podem ir antes.

**O que este mapa impede / obriga a encarar:**

- **A Fase 3 (lista de integrantes) está bloqueada por backend.** Não existe endpoint. O front pode
  ser desenhado e até stubado, mas não entrega valor sozinho.
- **`MessageList.vue:265` agrupa mensagens de pessoas diferentes hoje.** Como em grupo o `senderId` é
  sempre o contato-grupo, duas mensagens de pessoas diferentes no mesmo minuto entram no mesmo bloco
  visual — o agente lê como se fosse a mesma pessoa. Isso é um bug **ativo**, não hipotético, e a
  Fase 0 não o corrige (nem piora).
- **Sanear no front sem corrigir a origem deixa busca, IA, export e relatório sujos.** A Fase 0 é
  legítima como analgésico, mas comprar a tela limpa e parar aí significa carregar 548 mensagens
  sujas (e crescendo) para sempre.

---

## Referências

**Código (este repo, branch `homologacao`):**
- `app/javascript/dashboard/components-next/message/Message.vue` (1111 linhas)
- `app/javascript/dashboard/components-next/message/MessageList.vue:265-290`
- `app/javascript/dashboard/components-next/message/bubbles/Base.vue:90-108`
- `app/javascript/dashboard/components-next/message/bubbles/Text/FormattedContent.vue:22`
- `app/javascript/dashboard/components-next/message/bubbles/ReplyPreview.vue:112-119`
- `app/javascript/dashboard/components-next/message/MessageReactions.vue` (órfão)
- `app/javascript/dashboard/components-next/avatar/Avatar.vue:25,61-115,283`
- `app/javascript/shared/helpers/MessageFormatter.js:61-101`
- `app/javascript/shared/helpers/colorHelper.js:12-28`
- `app/javascript/shared/composables/useMessageFormatter.js:18,37`
- `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue:381-419`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue:149-346`
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationParticipant.vue` (watchers, não grupo)
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationMedia.vue:1-90` (modelo de seção)
- `app/javascript/dashboard/composables/useUISettings.js:4-59`
- `app/javascript/dashboard/components/Accordion/AccordionItem.vue`
- `app/javascript/dashboard/components/widgets/ThumbnailGroup.vue`
- `app/javascript/dashboard/assets/scss/_wa-skin.scss:14-44`
- `app/views/api/v1/models/_message.json.jbuilder:17,28`
- `app/models/message.rb:159-187`
- `enterprise/app/services/captain/behavior/router_service.rb:33-46`
- `git log`: `24ea968b00 chore: Remove older UI (#11720)`

**Banco (SELECT, homologação):** `messages` (548 registros com `@lid` em `content`),
`contacts` (36 com `identifier like '%@g.us'`, 30 com avatar em `active_storage_attachments`).

**Externas:**
- [WAHA — Groups](https://waha.devlike.pro/docs/how-to/groups/) — endpoints `GET /groups/{id}`,
  `/participants/v2` (`role`: participant|admin|superadmin|left), `/picture`
- [WhatsApp Help Center — How to manage group admins](https://faq.whatsapp.com/633713745095781/)
- [Alphr — How to Find a Group in WhatsApp](https://www.alphr.com/whatsapp-find-group/) — estrutura do
  painel "Dados do grupo": contagem, admins primeiro com badge, demais em ordem alfabética
- [Intertoons — Logic behind WhatsApp Group Member Color](https://intertoons.com/logic-behind-whatsapp-group-member-color.html) —
  atribuição determinística de cor por participante; cores só aparecem em grupos
