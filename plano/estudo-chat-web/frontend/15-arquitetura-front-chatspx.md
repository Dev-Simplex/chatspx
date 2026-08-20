# TASK 15 — Arquitetura front-end do widget ChatSPX para a repaginada total

> **Escopo:** raio-X do front end do NOSSO widget (`app/javascript/widget` + `app/javascript/sdk`)
> e proposta de arquitetura que sustente uma repaginada total sem virar dívida.
> **Fase:** estudo. Nenhuma linha de código foi alterada, nenhum build de produção foi rodado,
> nada foi commitado, deployado ou reiniciado.
> **Data das medições:** 11/08/2026.
> **Branch:** `homologacao` (HEAD `ee87f5e799`), fork ChatSPX sobre Chatwoot v4.12.1.

---

## Legenda dos marcadores

| Marcador | Significa |
|---|---|
| `[MEDIDO]` | Número obtido por execução real (Playwright `getComputedStyle`/`getBoundingClientRect`, `curl`, análise de bundle, `tailwindcss` CLI). O comando está junto. |
| `[FATO]` | Trecho de código com `arquivo:linha` verificável neste repositório. |
| `[INFERÊNCIA]` | Conclusão derivada de dois ou mais fatos/medições. Está marcado como dedução, não observação. |
| `[NÃO VERIFICADO]` | Não consegui comprovar nesta onda. |

**Ambiente das medições ao vivo.** Todas as medições de navegador foram feitas contra a app
já em execução em `http://localhost:3000` (a mesma VM de homologação, `192.168.8.232`), embutida
via SDK numa página host local `http://localhost:8899/host.html` — cenário cross-origin idêntico
ao real. Inbox de teste: `channel_web_widgets.id=2`, `website_token=6dPgMBcE9W69x7hHgXQnwuPN`,
**`widget_color = #009CE0`** (azul) — escolhida de propósito porque é uma cor *diferente* do verde
da marca, o que permite provar ou refutar o bug de cor. Os assets medidos são os de
`public/vite/` gerados em 29/07/2026 — os mesmos servidos hoje em `hmlchat.simplexsolucoes.com.br`
(confirmado: o HTML de `/widget` referencia `widget-EcEcykJV.css` e `widget-D0AtGYyS.js`).

**Ressalva de rigor.** Onde eu medi o launcher (fora do iframe), não afirmo nada sobre o painel;
onde medi desktop, não afirmo nada sobre mobile sem ter rodado mobile. Cada bloco diz qual
superfície e qual viewport foi medido.

---

# PARTE A — RAIO-X DO QUE EXISTE

## A1. Árvore de componentes

### A1.1 Ponto de entrada e montagem

`app/javascript/entrypoints/widget.js` monta a aplicação `[FATO]`:

- `widget.js:25-30` — `createApp(App)`, `.use(i18n)`, `.use(store)` (Vuex), `.use(router)`,
  `.use(VueDOMPurifyHTML, domPurifyConfig)`, diretiva `on-clickaway`.
- `widget.js:32-40` — `app.use(plugin, defaultConfig({rules:{startsWithPlus, isValidPhoneNumber}}))` → **FormKit**.
- `widget.js:48-54` — montagem dentro de `window.onload`, expondo `window.WOOT_WIDGET` e
  `window.actionCable` como globais.

`app/javascript/widget/App.vue` é um casco fino: `App.vue:361-382` renderiza apenas um `<router-view />`
dentro de um `<div>` com as classes de estado (`is-mobile`, `is-widget-right`, `is-bubble-hidden`,
`is-flat-design`, `dark`), mais um spinner de carregamento inicial (`App.vue:362-368`). Toda a
inteligência de App.vue está no `<script>` (386 linhas — o maior arquivo não-teste do widget).

### A1.2 Rotas e layout

`app/javascript/widget/router.js` (hash history, `createWebHashHistory`) `[FATO]`:

```
/unread-messages   → views/UnreadMessages.vue        (fora do layout)
/campaigns         → views/Campaigns.vue             (fora do layout)
/                  → components/layouts/ViewWithHeader.vue
   ├─ ''            → views/Home.vue
   ├─ /prechat-form → views/PreChatForm.vue
   ├─ /messages     → views/Messages.vue
   └─ /article      → views/ArticleViewer.vue
```

As 6 views são `() => import(...)` — **lazy de verdade** `[FATO]` (`router.js:11,16,25,30,35,40`),
confirmado no manifest do Vite: aparecem em `dynamicImports` do entry, com chunks próprios
`[MEDIDO]` (`Messages-Db7meCAO.js` 50.235 B, `PreChatForm-C8-9xKAd.js` 13.946 B,
`Home-DcK-HhCP.js` 7.925 B, `Campaigns` 1.302 B, `UnreadMessages` 1.147 B, `ArticleViewer` 592 B).

`ViewWithHeader.vue` (144 linhas) é o layout: escolhe entre `ChatHeaderExpanded` (Home com texto de
boas-vindas) e `ChatHeader` (colapsado), mais `Banner`, `<router-view/>` e `Branding`
(`ViewWithHeader.vue:104-144`).

### A1.3 Árvore de renderização

```
App.vue
└── router-view
    ├── UnreadMessages.vue ─ UnreadMessageList.vue ─ UnreadMessage.vue ─ Avatar(dashboard)
    ├── Campaigns.vue
    └── ViewWithHeader.vue
        ├── ChatHeaderExpanded.vue  ─ HeaderActions.vue
        │   └── (usa useMessageFormatter p/ introBody)
        ├── ChatHeader.vue ─ FluentIcon(shared) + HeaderActions.vue
        │                   + Availability/AvailabilityContainer.vue ─ AvailabilityText.vue
        ├── Banner.vue
        ├── Branding.vue (shared)
        └── router-view
            ├── Home.vue
            │   ├── TeamAvailability.vue ─ GroupedAvatars.vue ─ Avatar(dashboard)
            │   └── pageComponents/Home/Article/ArticleContainer.vue
            │       ├── ArticleBlock.vue ─ ArticleListItem.vue
            │       └── SkeletonLoader.vue
            ├── PreChatForm.vue ─ PreChat/Form.vue ─ Form/PhoneInput.vue (FormKit)
            ├── ArticleViewer.vue
            └── Messages.vue
                ├── ConversationWrap.vue
                │   ├── DateSeparator.vue (shared)
                │   ├── Spinner.vue (shared)
                │   ├── ChatMessage.vue  ──┬─ UserMessage.vue  ─ UserMessageBubble.vue
                │   │                      │                    + ImageBubble/VideoBubble/FileBubble
                │   │                      │                    + ReplyToChip + DragWrapper
                │   │                      └─ AgentMessage.vue ─ AgentMessageBubble.vue
                │   │                                            + Avatar(dashboard)
                │   │                                            + MessageReplyButton + ReplyToChip
                │   └── AgentTypingBubble.vue
                └── ChatFooter.vue
                    ├── FooterReplyTo.vue
                    ├── ChatInputWrap.vue
                    │   ├── ResizableTextArea.vue (shared)
                    │   ├── ChatAttachment.vue
                    │   ├── EmojiInput.vue (shared)
                    │   └── ChatSendButton.vue
                    └── Button.vue (shared, CustomButton)
```

**Reaproveitado de `app/javascript/shared`** `[FATO]`: `Spinner`, `DateSeparator`, `Button`,
`FluentIcon/Index`, `ResizableTextArea`, `emoji/EmojiInput`, `Branding`, `ChatCard`, `ChatForm`,
`ChatOptions`, `ChatOption`, `CardButton`, `CustomerSatisfaction`.

**Reaproveitado de `components-next` (dashboard)** `[FATO]`: apenas `avatar/Avatar.vue`, usado em
`AgentMessage.vue:9`, `GroupedAvatars.vue:2` e `UnreadMessage.vue:3`.

### A1.4 O vazamento de camada dashboard → widget

Este é um achado estrutural, não estético. O widget importa **13 módulos do dashboard**
diretamente `[MEDIDO]` (`grep -rn "from 'dashboard/\|from 'next/" app/javascript/widget/`):

| Arquivo do widget | Importa do dashboard |
|---|---|
| `App.vue:8` | `dashboard/components/widgets/conversation/advancedFilterItems/languages` |
| `components/AgentMessage.vue:9` | `dashboard/components-next/avatar/Avatar.vue` |
| `components/GroupedAvatars.vue:2` | `dashboard/components-next/avatar/Avatar.vue` |
| `components/UnreadMessage.vue:3` | `dashboard/components-next/avatar/Avatar.vue` |
| `components/Availability/AvailabilityContainer.vue:4` | `dashboard/composables/store.js` |
| `components/Availability/AvailabilityText.vue:4` | `dashboard/routes/dashboard/settings/inbox/helpers/businessHour.js` |
| `components/TeamAvailability.vue:5` | `dashboard/composables/store.js` |
| `components/pageComponents/Home/Article/ArticleBlock.vue:4` | `dashboard/composables/store` |
| `components/pageComponents/Home/Article/ArticleContainer.vue:7-8` | `dashboard/composables/store` |
| `composables/useAvailability.js:6` | `dashboard/composables/useTransformKeys` |
| `composables/useDarkMode.js:2` | `dashboard/composables/store` |

E `shared/` — que o widget consome inteiro — importa do dashboard em **24 pontos** `[MEDIDO]`,
com destaque para os que estão no caminho quente do widget:

- `shared/components/ResizableTextArea.vue:6` → `dashboard/helper/editorHelper`
- `shared/components/emoji/EmojiInput.vue:4` → `dashboard/components-next/button/Button.vue`
- `shared/helpers/MessageFormatter.js:4` → `dashboard/helper/whatsappGroupHelper` (adicionado
  pelo fork em `44b77d19c0`)
- `shared/helpers/BaseActionCableConnector.js:2` → `dashboard/helper/AudioAlerts/WindowVisibilityHelper`
- `shared/composables/useBranding.js:5` → `dashboard/composables/store.js`

**Consequência medida, não teórica** (ver A4.4): `dashboard/composables/useTransformKeys.js:6`
faz `import * as Sentry from '@sentry/vue'`, e `dashboard/helper/editorHelper.js:7` também.
Como `widget/composables/useAvailability.js` e `shared/components/ResizableTextArea.vue`
estão no caminho principal do widget, **o `@sentry/core` entra no bundle do widget** —
`window.__SENTRY__` existe dentro do iframe `[MEDIDO]`.

---

## A2. Estado

### A2.1 Vuex 4, não Pinia

`app/javascript/widget/store/index.js:1,15` — `createStore` de `vuex` `[FATO]`. **Não há Pinia
no widget.** Onze módulos namespaced (`store/index.js:16-28`):

| Módulo | Arquivo | Papel |
|---|---|---|
| `agent` | `store/modules/agent.js` | agentes disponíveis |
| `appConfig` | `store/modules/appConfig.js` (155 l.) | posição, cor, dark mode, flags do SDK |
| `contacts` | `store/modules/contacts.js` (119 l.) | contato corrente |
| `conversation` | `store/modules/conversation/` (index/actions 198 l./getters/mutations 116 l./helpers) | mensagens |
| `conversationAttributes` | `store/modules/conversationAttributes.js` | status da conversa |
| `conversationLabels` | `store/modules/conversationLabels.js` | labels via SDK |
| `events` | `store/modules/events.js` | eventos de página |
| `globalConfig` | `shared/store/globalConfig` | branding da instalação |
| `message` | `store/modules/message.js` | update de mensagem (form/opções) |
| `campaign` | `store/modules/campaign.js` (183 l.) | campanhas |
| `article` | `store/modules/articles.js` | artigos da central de ajuda |

### A2.2 Composables

Só três, em `widget/composables/` `[FATO]`:

- `useAttachments.js` — regras de anexo/emoji.
- `useAvailability.js` (340 l. de helper em `helpers/availabilityHelpers.js`) — horário comercial.
- `useDarkMode.js` (30 l.) — cálculo do tema.

`useDarkMode.js:20` merece nota: `const systemPreference = computed(getSystemPreference)`, onde
`getSystemPreference` (`useDarkMode.js:7-8`) lê `window.matchMedia('(prefers-color-scheme: dark)').matches`.
`matchMedia().matches` **não é uma fonte reativa do Vue** — o `computed` não tem nenhuma dependência
reativa, então nunca reavalia. `[INFERÊNCIA]`: se o usuário trocar o tema do sistema operacional com o
widget aberto, o widget não acompanha até um remount. Não testei a troca ao vivo. `[NÃO VERIFICADO]`

### A2.3 O que é global de verdade (e não deveria)

Três estados vivem em `window`, não no store `[FATO]`:

- `window.chatwootWebChannel` — configuração inteira do canal, lida direto por
  `mixins/configMixin.js:9,12,15,27,31` e por `App.vue:82`, `ViewWithHeader.vue:23,33`,
  `ChatFooter.vue:41`.
- `window.authToken` — token do contato (`entrypoints/widget.js` via `helpers/axios`).
- `window.WOOT_WIDGET`, `window.actionCable` — instâncias.

`configMixin` é um mixin de opções API que só existe para ler `window.chatwootWebChannel`. Isso
amarra 6 componentes a um global mutável e impede testar componente isolado sem stub de `window`.

### A2.4 Comunicação: o `else if` de 16 braços

`App.vue:258-345`, método `registerListeners()` `[FATO]`. É um `window.addEventListener('message', …)`
com uma cadeia de **16 ramos** — 1 `if` + 15 `else if` `[MEDIDO]`
(`awk 'NR>=258 && NR<=345' App.vue | grep -cE "^\s*(} else if|if) \(message.event"` → 16):

`config-set` · `widget-visible` · `change-url` · `toggle-close-button` · `push-event` ·
`set-label` · `remove-label` · `set-user` · `set-custom-attributes` · `delete-custom-attribute` ·
`set-conversation-custom-attributes` · `delete-conversation-custom-attribute` · `set-locale` ·
`set-color-scheme` · `toggle-open` · `SDK_SET_BUBBLE_VISIBILITY`

> Nota de precisão: o briefing falava em "17 `else if`". O número medido é **16 ramos no total**
> (linhas 265, 273, 275, 284, 286, 288, 290, 292, 294, 299, 304, 309, 314, 317, 319, 341). A
> diferença não muda o diagnóstico.

Do outro lado, o SDK tem a forma certa: `sdk/IFrameHelper.js:104-117` usa um dicionário
(`IFrameHelper.events[message.event]`) — `IFrameHelper.js:113` faz
`typeof IFrameHelper.events[message.event] === 'function'`. **O padrão bom já existe no
repositório, do lado do host; só o lado do widget ficou com a escada.** `[FATO]`

### A2.5 Segurança do canal postMessage

Dois pontos, ambos `[FATO]`, herdados do upstream:

1. `widget/helpers/utils.js:8-13` — `sendMessage` faz
   `window.parent.postMessage(..., '*')`. O `targetOrigin` é curinga.
2. `widget/helpers/utils.js:18-21` — `isAValidEvent` valida **apenas o prefixo da string**
   (`chatwoot-widget:`); **não verifica `e.origin`**.

E o que trafega nesse canal inclui o token: `widget/helpers/IframeEventHelper.js:1-9`,
`loadedEventConfig()` envia `authToken: window.authToken` no evento `loaded`.
`[INFERÊNCIA]` — qualquer script rodando na página host lê o `authToken` do contato ouvindo
`message`, e qualquer origem pode injetar comandos (`set-user`, `set-label`, `toggle-open`) no widget.
Não explorei isso; é leitura de código. O lado do SDK é melhor: `IFrameHelper.js:96-102` calcula
`targetOrigin` a partir do `src` do iframe.

---

## A3. Estilo: Tailwind, tokens, SCSS legado e o bug do `widget_color`

### A3.1 Como o Tailwind está montado

Há **um único** `tailwind.config.js`, na raiz, compartilhado por dashboard, widget, portal, v3,
survey e superadmin `[FATO]`. O `content` (`tailwind.config.js:24-38`) inclui os **seis** diretórios:

```js
content: [
  './enterprise/app/views/**/*.html.erb',
  './app/javascript/widget/**/*.vue',
  './app/javascript/v3/**/*.vue',
  './app/javascript/dashboard/**/*.vue',      // ← o dashboard inteiro
  './app/javascript/portal/**/*.vue',
  './app/javascript/shared/**/*.vue',
  './app/javascript/survey/**/*.vue',
  './app/javascript/dashboard/components-next/**/*.vue',
  ... mais 4 globs de .js do dashboard
]
```

Plugins (`tailwind.config.js:348-372`): `@tailwindcss/typography`, `tailwindcss-animated` e
`iconsPlugin` com **7 coleções** de ícones (`woot`, `lucide`, `logos`, `ri`, `ph`,
`material-symbols`, `teenyicons`, `fluent`).

**Consequência medida (A4.3): o CSS do widget carrega o CSS do dashboard inteiro.**

### A3.2 Onde ficam os tokens

Dois lugares, e eles não conversam:

**(a) `theme/colors.js`** (282 linhas) mapeia nomes Tailwind → CSS custom properties. O namespace
`n:` (`theme/colors.js:105`) é o "next design system": `n-slate-*`, `n-iris-*`, `n-blue-*`,
`n-ruby-*`, `n-amber-*`, `n-teal-*`, `n-gray-*`, `n-violet-*`, mais `n-background`, `n-solid-*`,
`n-alpha-*`, `n-weak`, `n-strong`, `n-card`, `n-overlay-*`, `n-button-*`, `n-label-*` `[FATO]`.
Quase tudo é `rgb(var(--x) / <alpha-value>)`.

**Duas exceções literais** (`theme/colors.js:122-123`) `[FATO]`:

```js
black: '#000000',
brand: '#2dc46f',      // ← literal, não var()
```

**(b) `app/javascript/widget/assets/scss/woot.scss:167-382`** define os valores das custom
properties dentro de `@layer base`, com `:root` (claro, l. 169-274) e `.dark` (escuro, l. 276-381) `[FATO]`.

Aqui está a segunda peça: no fork, a rampa `--iris-*` foi **repintada de verde** —
`woot.scss:193` `--iris-9: 45 196 111` (= `#2DC46F`), `woot.scss:255` `--text-blue: 24 166 88`,
`woot.scss:272` `--border-blue: 45, 196, 111, 0.5`. No upstream, `iris` é roxo.

### A3.3 O bug: `bg-n-brand` não é uma variável

**O que o código faz** `[FATO]`:

| Arquivo:linha | Classe |
|---|---|
| `widget/components/ChatHeader.vue:28` | `<header class="… bg-n-brand …">` |
| `widget/components/ChatHeaderExpanded.vue:34` | `<header class="… bg-n-brand">` |
| `widget/components/ChatSendButton.vue:27` | `<button … class="… bg-n-brand hover:bg-[#1FB85A] …">` |

`bg-n-brand` resolve para `theme/colors.js:123` → `#2dc46f`, **um literal**. Não passa por
`var()`, não muda com tema, não muda com inbox. E o `hover:bg-[#1FB85A]` é um segundo literal,
escrito direto no arbitrary value — não existe token para ele.

**De onde veio o literal** `[MEDIDO]` (`git log -S"brand: '#2dc46f'" -- theme/colors.js`):

```
c42a446322  2026-01-26  simplex  "local: minhas alterações"
-    brand: '#2781F6',     ← upstream Chatwoot (azul)
+    brand: '#2dc46f',     ← fork ChatSPX (verde)
```

Ou seja: **o literal é do upstream; o fork só trocou o valor.** Não é um erro que nós
introduzimos — é um erro que nós herdamos e pintamos de verde. O `#1FB85A` do hover aparece em
15 lugares do repositório `[MEDIDO]`, mas apenas 1 dentro do widget (`ChatSendButton.vue:27`).

**Onde o `widget_color` real chega e onde ele para** `[FATO]`:

```
inbox.widget_color (banco)
  → app/views/widgets/show.html.erb:16 → window.chatwootWebChannel.widgetColor
    → App.vue:84  setWidgetColor(widgetColor)          → store appConfig.widgetColor
    → App.vue:85  setWidgetColorVariable(widgetColor)  → --widget-color no documentElement
```

E aqui está o achado que fecha o caso: **`--widget-color` é escrita e nunca lida.** `[MEDIDO]`

```
$ grep -rn -- "--widget-color" app/ | grep -v node_modules
app/javascript/widget/App.vue:121:          '--widget-color',
```

Uma única ocorrência em todo o repositório: a escrita em `App.vue:118-125`. **Zero consumidores
em CSS.** A variável existe e é inútil.

Quem realmente usa a cor da inbox usa por **`:style` inline**, um a um `[FATO]`:

| Componente | Linha |
|---|---|
| `widget/components/UserMessageBubble.vue:35` | `:style="{ background: widgetColor, color: textColor }"` |
| `shared/components/CustomerSatisfaction.vue:123,158-159` | idem |
| `shared/components/ChatForm.vue:144-145` | idem |
| `shared/components/ChatOption.vue:34,37` | idem |
| `shared/components/CardButton.vue:48-49,61` | idem |
| `widget/components/ChatFooter.vue:137-138` | `:bg-color="widgetColor"` |
| `sdk/IFrameHelper.js:334-335` | `chatIcon.style.background = widgetColor` (launcher, no host) |

**Prova ao vivo, com inbox de `widget_color = #009CE0`** `[MEDIDO]` — Playwright,
`getComputedStyle`, embed real cross-origin, desktop 1280×900 e mobile 375×667, temas claro e escuro:

| Superfície | Cor medida | Deveria ser | Veredito |
|---|---|---|---|
| Launcher (bolha, no host) | `rgb(0, 156, 224)` = **#009CE0** | #009CE0 | ✅ respeita |
| Bolha do usuário (dentro do iframe) | `rgb(0, 156, 224)` = **#009CE0** | #009CE0 | ✅ respeita |
| **Header do painel** | `rgb(45, 196, 111)` = **#2DC46F** | #009CE0 | ❌ ignora |
| **Botão de enviar** | `rgb(45, 196, 111)` = **#2DC46F** | #009CE0 | ❌ ignora |
| Link dentro da bolha do agente | `rgb(45, 196, 111)` = **#2DC46F** | #009CE0 | ❌ ignora |
| Borda de foco do input do emoji | `rgb(45, 196, 111)` = **#2DC46F** | #009CE0 | ❌ ignora |

O header ficou verde em **light e dark**, em **desktop e mobile** — as quatro combinações foram
medidas separadamente. `--widget-color` estava corretamente setada em `#009CE0` no
`documentElement` em todas elas. Screenshots: `shots/t15-panel-messages-desktop-light.png`,
`shots/t15-panel-messages-desktop-dark.png`, `shots/t15-panel-mobile-375.png`.

**Resultado prático: duas cores de marca na mesma tela.** A bolha do usuário é azul, o header e o
botão de enviar são verdes. Isso não é um detalhe de cor — é o produto contando duas histórias.

### A3.4 O que mais depende de `n-brand`

`[MEDIDO]` (`grep -rn "n-brand" app/javascript/widget/ app/javascript/shared/` — 23 ocorrências):

**No widget (11):** `ChatHeader.vue:28`, `ChatHeaderExpanded.vue:34`, `ChatSendButton.vue:27`,
`ChatInputWrap.vue:132` (`border-n-brand` no foco), `ChatInputWrap.vue:167` (ícone de emoji ativo),
`FileBubble.vue:85,89`, `UnreadMessageList.vue:122`, `PreChat/Form.vue:266`,
`Form/PhoneInput.vue:169`, `template/EmailInput.vue:109`.

**No SCSS do widget (4):** `woot.scss:78` (foco de input/textarea), `woot.scss:94` (foco de select),
`woot.scss:123,127,132` (classe `.button`), `views/_conversation.scss:185` (link em bolha),
`views/_conversation.scss:205` (link em bolha do agente).

**No `shared/` que o widget usa (5):** `Button.vue:34`, `Spinner.vue:16`, `ChatOption.vue:44`,
`CustomerSatisfaction.vue:122,191`, `CardButton.vue:60`, `ui/MultiselectDropdownItems.vue:167`.

Ou seja: **todo estado de foco, todo link, todo botão primário e todo spinner do widget estão
presos ao verde fixo.**

### A3.5 Outras cores fora do sistema

`[FATO]`, achadas por leitura:

- `AgentMessageBubble.vue:98` — `class="chat-bubble agent bg-white dark:bg-n-solid-3 …"`.
  `bg-white` é literal (não token). Medido: bolha do agente = `rgb(255,255,255)` no claro
  e `rgb(44,45,54)` no escuro `[MEDIDO]`.
- `AgentTypingBubble.vue:12` — mesmo `bg-white dark:bg-n-solid-3`.
- `ChatInputWrap.vue:130` — `bg-white dark:bg-n-solid-2`.
- `Messages.vue:22` — `class="… bg-n-chat-bg dark:bg-n-solid-1"`. **`chat-bg` não existe no
  namespace `n:` de `theme/colors.js`** `[MEDIDO]` (`grep "chat-bg" theme/colors.js` → vazio).
  É uma classe morta: não gera CSS. O fundo real vem do `background-image` de
  `ConversationWrap.vue:140-146`.
- `ConversationWrap.vue:140-167` — textura de fundo do fork: `linear-gradient(rgba(0,0,0,.85), …)`
  + `url('/assets/images/chat-spx-background.png')` (escuro, **88.534 B**) e
  `chat-spx-background-light.png` (**96.098 B**) `[MEDIDO]`. Valores de opacidade `0.85` e tamanho
  `400px` hardcoded, sem token.
- `woot.scss:99` — a seta do `<select>` é um SVG em data-URI com `fill: rgb(110, 111, 115)`
  cravado dentro da string; não acompanha o tema.
- `views/_conversation.scss:176` — sombra da bolha:
  `shadow-[0_0.25rem_6px_rgba(50,50,93,0.08),0_1px_3px_rgba(0,0,0,0.05)]`, literal e igual nos dois temas.
  Medido no navegador: `rgba(50,50,93,0.08) 0px 4px 6px 0px, rgba(0,0,0,0.05) 0px 1px 3px 0px`
  em light **e** em dark `[MEDIDO]`. Uma sombra calibrada para fundo claro, aplicada também no escuro.

### A3.6 SCSS legado

- `widget/assets/scss/woot.scss` (383 l.) — entrada, importada por `App.vue:385`.
- `widget/assets/scss/_reset.scss`
- `widget/assets/scss/views/_conversation.scss` (209 l.) — o layout da conversa inteiro
  (posição das bolhas, avatar, agrupamento, raios de canto) mora aqui, em `@apply`, fora dos
  componentes. `[INFERÊNCIA]` — mexer no visual da conversa exige editar um SCSS global que
  ninguém encontra a partir do componente.

Estilos globais que atingem qualquer elemento dentro do iframe `[FATO]`:
`woot.scss:71-73` (`label`), `woot.scss:75-87` (`input`/`textarea` não-`.reset-base`),
`woot.scss:89-91` (`textarea`), `woot.scss:93-104` (`select`), `woot.scss:106-120`
(`p code`, `pre`, `blockquote`), `woot.scss:122-164` (`.button`).

---

## A4. Build e bundle — os números

### A4.1 Como o build é organizado

`vite.config.ts` `[FATO]`:

- `vite.config.ts:37` — plugins `ruby()` + `vue()`; `vite-plugin-ruby` descobre automaticamente
  tudo em `app/javascript/entrypoints/`.
- `vite.config.ts:26,39-43,93-99` — o SDK é buildado **separado**, em library mode
  (`BUILD_MODE=library bin/vite build`), formato IIFE, saída `public/packs/js/sdk.js`.
- `vite.config.ts:84-90` — `manualChunks: { leaflet: ['leaflet'] }` no build normal.
- `vite.config.ts:103` — alias `vue: 'vue/dist/vue.esm-bundler.js'` (**build com compilador de
  template em runtime**).
- `vite.config.ts:101-113` — aliases `widget`, `shared`, `dashboard`, `next`, `v3`, `survey`,
  `helpers`, `assets`.

São **8 entradas** no build normal `[MEDIDO]` (manifest): `dashboard`, `portal`, `sdk`,
`superadmin`, `superadmin_pages`, `survey`, `v3app`, `widget`. **Elas compartilham chunks.**

### A4.2 O que o widget baixa hoje — medição exata

Fonte: `public/vite/.vite/manifest.json`, entrada `entrypoints/widget.js`, arquivos reais em
`public/vite/assets/`. Gzip calculado com `gzip.compress(..., 9)` `[MEDIDO]`.

| Papel | Arquivo | Cru (B) | Gzip (B) |
|---|---|---:|---:|
| entry | `widget-D0AtGYyS.js` | 61.841 | 19.071 |
| import | `_plugin-vue_export-helper-C2NFN58P.js` | 223.922 | 84.950 |
| import | `useBranding-Cod3jKwR.js` | 287.030 | 85.022 |
| css | `useBranding-C1LIcEF9.css` | 1.422 | 494 |
| import | `vue-dompurify-html-BsNF8atS.js` | 131.392 | 56.255 |
| import | `sharedFrameEvents-0qZ2yOho.js` | 1.079 | 627 |
| import | `utils.esm-aAeXemek.js` | 83.343 | 25.747 |
| import | `constants-lVAyZKq6.js` | 157 | 166 |
| import | `Validators-B8yFtBg4.js` | 164.809 | 53.436 |
| import | `index-DqTgoDi8.js` | 350.867 | 104.774 |
| import | `Icon-Bl9l3BEz.js` | 6.025 | 2.160 |
| import | `Branding-CV74U7Vy.js` | 1.635 | 923 |
| import | `module-D6sSz6Gr.js` | 11.647 | 5.171 |
| **import** | **`leaflet-58r2EQLt.js`** | **150.679** | **43.491** |
| import | `index-DN3rM4CW.js` | 886 | 529 |
| **css** | **`widget-EcEcykJV.css`** | **1.103.132** | **106.127** |
| | **TOTAL EAGER** | **2.579.866** | **588.943** |

**2,46 MiB cru / 575 KiB gzip só para o widget aparecer.** As 6 views lazy somam mais
75.147 B cru quando navegadas.

**Confirmação das duas hipóteses do briefing:**

- **CSS ~1,10 MB cru? CONFIRMADO.** `widget-EcEcykJV.css` = **1.103.132 bytes** (= 1,10 MB
  decimal / 1.077 KiB). Gzip: 106.127 B.
- **Chunk do Leaflet (150 KB) no grafo? CONFIRMADO, e é pior do que parecia.** Ver A4.5.

### A4.3 Por que o CSS tem 1,1 MB

Anatomia do arquivo `[MEDIDO]`:

- 1 linha, 1.103.118 caracteres, ~5.095 blocos `{`.
- **1.291 data-URIs**, somando **549.852 bytes** — 49,8% do arquivo.
- **436 regras `.i-*`** (ícones do `@egoist/tailwindcss-icons`), somando **700.673 bytes** — **63,5% do arquivo**.
- 7 `@font-face`, 35 `@media`, 244 `@supports`, 17 `@keyframes`, 254 seletores `.prose`.

Quantos desses ícones o widget usa? `[MEDIDO]`
(`grep -rhoE "i-(lucide|ph|ri|woot|fluent|teenyicons|logos|material-symbols)-[a-z0-9-]+" app/javascript/widget/ app/javascript/shared/ | sort -u`):

**Dez.** `i-lucide-check`, `i-lucide-chevron-down`, `i-lucide-chevron-right`, `i-lucide-chevron-up`,
`i-lucide-circle-check`, `i-lucide-plus`, `i-lucide-sparkles`, `i-lucide-x`, `i-ri-star-fill`,
`i-ri-star-line`.

As 11 regras correspondentes ocupam **11.813 bytes**. As outras 425 regras — **688.860 bytes** —
são ícones que o widget nunca renderiza. Prova direta: `i-lucide-bot`, `i-lucide-shield` e
`animate-copilot-menu-in` **estão** no CSS servido ao widget e **não aparecem** em nenhum arquivo
de `widget/` ou `shared/` `[MEDIDO]`.

**Medição do contrafactual.** Rodei o Tailwind CLI com o mesmo `tailwind.config.js`, trocando só
o `content` para `widget/**` + `shared/**` (config temporário fora do repositório, saída em
`/tmp/.../twtest/out.css` — nada do repositório foi tocado) `[MEDIDO]`:

```
$ npx tailwindcss -c /tmp/.../tw.config.js -i in.css -o out.css
Done in 8878ms.

CSS só com content = widget + shared:  56.002 bytes cru /   9.501 bytes gzip
CSS atual servido ao widget:        1.103.132 bytes cru / 106.127 bytes gzip
REDUÇÃO:                            1.047.130 bytes (94,9%) / 96.626 bytes (91,0%)
```

**−94,9% do CSS cru por uma mudança de configuração de build.** Nenhuma linha de componente.

### A4.4 O que há dentro dos chunks — via sourcemap

Somei `sourcesContent` por pacote de origem, a partir dos `.map` `[MEDIDO]`. São bytes de
**código-fonte** (antes de minificar), então servem para dizer *o que está lá*, não o peso final
exato de cada parte.

**`index-DqTgoDi8.js`** (350.867 B minificados, 58 fontes):

| Origem | Bytes de fonte |
|---|---:|
| `@formkit/i18n` 1.7.2 | 510.413 |
| `date-fns` 2.21.1 | 124.733 |
| `@formkit/vue` | 73.161 |
| `@formkit/core` | 55.238 |
| `@formkit/inputs` | 50.189 |
| `app/dashboard/**` (inclui `GalleryView.vue`, 14.976 B) | 35.116 |
| `@rails/actioncable` | 19.054 |
| `urlpattern-polyfill` | 17.086 |

O FormKit inteiro — com **todas as traduções** — entra porque `entrypoints/widget.js:32-40` chama
`defaultConfig()`. O widget só usa FormKit em `PreChat/Form.vue` e `Form/PhoneInput.vue`, que são
**lazy** (rota `/prechat-form`); mas o plugin é registrado no `createApp`, então vem eager.

**`useBranding-Cod3jKwR.js`** (287.030 B minificados, 127 fontes):

| Origem | Bytes de fonte |
|---|---:|
| **`@amplitude/analytics-core`** | **229.948** |
| **`@amplitude/analytics-browser`** | **112.733** |
| `vue-i18n` 9.14.5 | 109.067 |
| **`@amplitude/plugin-autocapture-browser`** | **85.754** |
| `@intlify/core-base` | 68.273 |
| `@intlify/message-compiler` | 59.681 |
| `vuex` 4.1.0 | 44.079 |
| `app/shared/**` | 20.005 |

**O widget baixa 428.435 bytes de fonte do SDK de analytics da Amplitude.**

`[MEDIDO]` do comportamento em runtime, para não exagerar o achado: dentro do iframe,
`typeof window.amplitude === 'undefined'` e **nenhuma requisição saiu para fora do host** durante
toda a sessão de teste (launcher fechado, aberto, navegação para `/messages`). **Ou seja: o código
é baixado e avaliado, mas não inicializa nem envia dados nesta configuração.** O custo é peso e
superfície, não (hoje) coleta.

`[INFERÊNCIA]` da causa: `useBranding-Cod3jKwR.js` é importado por **4 entradas** —
`dashboard`, `survey`, `v3app` **e** `widget` `[MEDIDO]`. O Rollup agrupou nele o vendor comum
(vue-i18n, vuex) e, junto, o Amplitude que só o dashboard usa. O widget herda o vendor bundle do
dashboard.

**`Validators-B8yFtBg4.js`** (164.809 B minificados, 94 fontes):

| Origem | Bytes de fonte |
|---|---:|
| **`@sentry/core` 8.55.0** | **156.721** |
| `vue-router` 4.4.5 | 152.099 |
| `date-fns` 2.21.1 | 92.513 |
| `app/dashboard/**` (inclui `components-next/button/Button.vue`) | 15.713 |

Sentry confirmado em runtime: **`typeof window.__SENTRY__ === 'object'` dentro do iframe** `[MEDIDO]`.
Cadeia de entrada rastreada `[FATO]`: `widget/composables/useAvailability.js:6` →
`dashboard/composables/useTransformKeys.js:6` → `@sentry/vue`; e
`shared/components/ResizableTextArea.vue:6` → `dashboard/helper/editorHelper.js:7` → `@sentry/vue`.

**`_plugin-vue_export-helper-C2NFN58P.js`** (223.922 B minificados): o Vue inteiro.
`@vue/runtime-core` 261.200 + **`@vue/compiler-core` 172.248** + `runtime-dom` 57.149 +
`reactivity` 50.863 + `shared` 22.548 + **`compiler-dom` 20.369** `[MEDIDO]`.
Os ~192 KB de fonte de compilador vêm do alias `vue.esm-bundler.js` (`vite.config.ts:103`).

**`vue-dompurify-html-BsNF8atS.js`** (131.392 B minificados): `markdown-it` 165.207 +
`entities` 69.925 + `dompurify` 64.639 + `linkify-it` 23.154 + `mdurl` 15.272 + `punycode.js` 12.780
`[MEDIDO]`.

**`utils.esm-aAeXemek.js`** (83.343 B): `axios` 116.027 + `@chatwoot/utils` 101.982 `[MEDIDO]`.

**`module-D6sSz6Gr.js`** (11.647 B): `dashboard/composables/useKeyboardEvents`,
`useDetectKeyboardLayout`, `shared/helpers/KeyboardHelpers`, `tinykeys`, `vue3-click-away`,
`shared/components/FluentIcon/Index.vue`, `shared/helpers/HTMLSanitizer` `[MEDIDO]`.

### A4.5 O chunk do Leaflet: 150 KB por um helper de 100 bytes

Este merece ser contado com precisão, porque a causa não é óbvia.

**Fato 1** — o chunk contém *exclusivamente* Leaflet `[MEDIDO]`
(`leaflet-58r2EQLt.js.map` → `sources`):

```
total sources: 1
   ../../../node_modules/.pnpm/leaflet@1.9.4/node_modules/leaflet/dist/leaflet-src.js
```

**Fato 2** — ele está na lista de **imports estáticos** do entry do widget no manifest, e o HTML
servido faz `modulepreload` dele `[MEDIDO]`:

```html
<link rel="modulepreload" href="/vite/assets/leaflet-58r2EQLt.js" as="script" crossorigin="anonymous">
```

**Fato 3** — quem importa esse chunk, e o quê: `vue-dompurify-html-BsNF8atS.js`, primeira
instrução do arquivo `[MEDIDO]`:

```js
import{g as zt}from"./leaflet-58r2EQLt.js";
```

O export `g` do chunk é `jo` `[MEDIDO]`:

```js
function jo(N){return N&&N.__esModule&&Object.prototype.hasOwnProperty.call(N,"default")?N.default:N}
```

Isto é `getDefaultExportFromCjs` — **um helper de interop CommonJS de ~100 bytes**. Os outros
exports do chunk são da mesma natureza: `qo` = polyfill de `globalThis`, `Yo` = `getAugmentedNamespace`,
`Vo` = helper de `commonjsGlobal`.

**Fato 4** — o Leaflet é *executado*: dentro do iframe do widget,
**`typeof window.L === 'object'` e `window.L.version === '1.9.4'`** `[MEDIDO]`, tanto em light
quanto em dark, tanto no acesso direto a `/widget` quanto no embed via SDK.

**Fato 5** — o único uso real de Leaflet no repositório é
`dashboard/components-next/location/LocationPickerModal.vue:90-95`, e lá ele é `await import('leaflet')`,
**dinâmico** `[FATO]`.

`[INFERÊNCIA]` — `manualChunks: { leaflet: ['leaflet'] }` (`vite.config.ts:86-88`) criou um chunk
onde o Rollup também hospedou os helpers de interop CJS. Todo módulo que precisa desses helpers
(incluindo `vue-dompurify-html` → `dompurify`, que é CJS) passou a importar **daquele** chunk, e o
import é estático. O widget paga 150.679 bytes de mapa geográfico para obter uma função de uma linha —
e ainda ganha `window.L` poluído dentro do iframe.

O chunk é importado por 6 das 8 entradas `[MEDIDO]`. **Não é problema só do widget.**

### A4.6 Compressão e cache — o multiplicador

`[MEDIDO]`, `curl -skI -H "Accept-Encoding: gzip, br"` contra `hmlchat.simplexsolucoes.com.br`:

```
/vite/assets/widget-EcEcykJV.css   → 200  content-length: 1103132   (sem content-encoding)
/vite/assets/leaflet-58r2EQLt.js   → 200  content-length:  150679   (sem content-encoding)
/vite/assets/index-DqTgoDi8.js     → 200  content-length:  350867   (sem content-encoding)
/brand-assets/logo_thumbnail.svg   → 200  content-length:   90492   (sem content-encoding)
```

`server: nginx/1.24.0 (Ubuntu)`, `cache-control: public, max-age=31556952`.

**O cache está certo. A compressão não existe.** O nginx serve os assets do widget **crus**.
Isso significa que a primeira visita de um usuário baixa **~2,58 MB**, não os 575 KB de gzip.

`[NÃO VERIFICADO]` — se a frota de produção (`.229`, Tozi, fábrica) está com a mesma
configuração de nginx. Medi apenas homologação. **Vale checar antes de qualquer conclusão sobre
produção.**

### A4.7 Medição no navegador — o que efetivamente trafega

`performance.getEntriesByType('resource')` dentro do iframe, embed real `[MEDIDO]`:

- **Total transferido pelo iframe: 2.686.161 bytes.**
- Nós no DOM do widget: **74** (enxuto).
- `navigation`: TTFB 195 ms, DOMContentLoaded 755 ms, load 806 ms (localhost).
- Recursos por peso: CSS 1.103.432 → `index` 351.167 → `useBranding` 287.330 →
  `plugin-vue_export-helper` 224.222 → `Validators` 165.109 → **`leaflet` 150.979** →
  `vue-dompurify-html` 131.692 → **`logo_thumbnail.svg` 90.792** → `utils.esm` 83.643 → entry 62.141.

**Achado adicional:** `public/brand-assets/logo_thumbnail.svg` = **90.492 bytes** `[MEDIDO]`, com
imagem em base64 embutida (`grep -c base64` → 1) e filtros `feColorMatrix`. É o logo do rodapé
"Powered by", renderizado com ~16 px de altura `[MEDIDO]`: elemento `.branding` mede 179,6×24 px.
**88 KiB para um logo de 24 px de altura.**

`first-paint` medido: 10.420 ms `[MEDIDO]` — mas **isso não é o tempo de carga do widget**. O
iframe nasce com `visibility: hidden` (`sdk/IFrameHelper.js:73`) e só é revelado em
`IFrameHelper.onLoad` (`IFrameHelper.js:304`); no meu roteiro o clique no launcher aconteceu aos
~10 s. Registro o número apenas para explicar por que ele não deve ser lido como FCP.

### A4.8 O gate de tamanho no CI está medindo o arquivo errado

`package.json` tem `size-limit` configurado `[FATO]`:

```json
"size-limit": [
  { "path": "public/vite/assets/widget-*.js", "limit": "300 KB" },
  { "path": "public/packs/js/sdk.js",         "limit": "40 KB"  }
]
```

E roda no CI: `.github/workflows/size-limit.yml:52` → `pnpm run size`, em PRs para `develop` `[FATO]`.

Executado agora `[MEDIDO]`:

```
public/vite/assets/widget-BpEWRSiD.js, widget-BzOzGO4G.js, widget-D0AtGYyS.js, widget-DepPkfZr.js
  Size limit: 300 kB
  Size:       76.53 kB gzipped        ← verde

public/packs/js/sdk.js
  Size limit: 40 kB
  Size:        9.57 kB gzipped        ← verde
```

Dois problemas, ambos verificados:

1. **O glob `widget-*.js` pega só o chunk de entrada.** Ele ignora os 13 imports estáticos e o CSS.
   O widget real custa 575 KiB gzip; o gate reporta 76,53 kB e passa. **O teto é falso por um fator
   de ~7,5×.**
2. **O glob casa com arquivos antigos acumulados no diretório** — quatro hashes diferentes na saída
   acima. A medição não é determinística entre builds.

O SDK, esse sim, está honesto: 9,57 kB gzip / 28.834 B cru `[MEDIDO]`, IIFE, sem Leaflet e sem
DOMPurify (`grep -c` → 0 para ambos).

---

## A5. i18n, tema e acessibilidade

### A5.1 i18n: 40 idiomas eager

`widget/i18n/index.js` faz **40 `import` estáticos** de JSON e exporta um objeto único
`[MEDIDO]` (`grep -c "^import"` → 40). Não há `import()` dinâmico, não há split por locale.

Peso `[MEDIDO]`: a pasta `locale/` tem **56 arquivos / 280.688 bytes**, dos quais **40 arquivos /
205.494 bytes** são efetivamente importados e entram no bundle. `en.json` = 4.616 B,
`pt_BR.json` = 4.903 B. (Os 16 arquivos restantes — `am`, `az`, `bn`, `et`, `hr`, `hy`, `ka`, `ms`,
`ne`, `sh`, `sl`, `sq`, `tl`, `ur`, `ur_IN`, `zh` — existem no disco e **não** estão no `index.js`;
são traduções mortas.)

`[INFERÊNCIA]` — um cliente brasileiro carrega **200.591 bytes** de traduções que jamais usará
(205.494 − 4.903 do `pt_BR`). O JSON entra no chunk de entrada, então parte do peso de 61.841 B do
entry é isso.

Seleção de idioma (`App.vue:146-162`): tenta `pt_BR`, cai para `pt`, filtrando por
`window.chatwootWebChannel.enabledLanguages`. Funciona — medido: `aria-label` do textarea veio
"Digite sua mensagem" e do emoji "Seletor de emoji" `[MEDIDO]`.

**Bug de a11y medido:** `document.documentElement.lang` = `""` (string vazia) dentro do iframe,
em todas as views e temas `[MEDIDO]`. O `dir` é setado (`App.vue:74-79`, watcher de `isRTL`), mas
**o `lang` nunca é.** Leitor de tela não sabe em que idioma pronunciar o conteúdo.

### A5.2 Tema claro/escuro

Mecânica `[FATO]`: `darkMode: 'class'` (`tailwind.config.js:23`); a classe `dark` é aplicada no
`<div>` raiz por `App.vue:377` a partir de `prefersDarkMode` (`composables/useDarkMode.js`);
os valores vivem em `woot.scss:169-274` (`:root`) e `woot.scss:276-381` (`.dark`).

O modo vem do SDK: `sdk/sdk.js:74` → `getDarkMode(chatwootSettings.darkMode)`, entregue no evento
`config-set` (`sdk/IFrameHelper.js:169`) e guardado em `appConfig.darkMode` (default `'light'`,
`store/modules/appConfig.js:22`).

**Funciona** — medido com `chatwootSettings.darkMode: 'auto'` + `prefers-color-scheme: dark`:
classe `dark` aplicada; `--slate-1` 252 252 253 → 17 17 19; `--background-color` 253 253 253 → 18 18 19;
`--solid-1` 255 255 255 → 23 23 26 `[MEDIDO]`.

**Duas ressalvas medidas:**

1. **`--iris-9` é idêntico nos dois temas: `45 196 111`** `[MEDIDO]`. A cor de marca não tem
   variante para fundo escuro. Todas as outras rampas trocam.
2. **O default é `'light'`** (`appConfig.js:22` e `sdk.js:74` via `getDarkMode`). Quem embutir o
   widget sem passar `darkMode` entrega tema claro para quem usa o SO no escuro. Confirmei o
   caminho oposto: abrindo `/widget` direto (sem SDK, portanto sem `config-set`), o contexto do
   navegador em `dark` **não** aplicou a classe `dark` `[MEDIDO]` — `rootClasses` veio
   `"flex flex-col justify-end h-full is-widget-right"`, sem `dark`.

### A5.3 Acessibilidade: o inventário medido

Contagens no DOM do widget, embed real `[MEDIDO]`. **Ressalva de escopo:** a inbox de teste tem
`welcomeTitle` e `welcomeTagline` vazios, então `ViewWithHeader.vue:35-45` mantém o header
colapsado e o `ChatHeaderExpanded` (o único componente com um `<h2>`, em `ChatHeaderExpanded.vue:48`)
**nunca renderizou** nesta sessão. As contagens abaixo valem para essa configuração — que é a de
uma inbox recém-criada, mas não é a única possível.

| Métrica | Home | Messages |
|---|---:|---:|
| `<button>` | 2 | 4 |
| elementos com `aria-label` | 0 | 2 |
| elementos com `role` | 4 | 0 |
| **elementos com `aria-live`** | **0** | **0** |
| landmarks (`header/main/footer/nav/aside`) | 1 | 2 |
| `<h1>`/`<h2>`/`<h3>` | 0 | 0 |
| `<img>` sem `alt` | 0 | 0 |
| `document.documentElement.lang` | `""` | `""` |

**O que já existe de bom** `[FATO]`: `ChatInputWrap.vue:142` (`:aria-label` no textarea),
`ChatInputWrap.vue:159` (`:aria-label` no botão de emoji), `AgentTypingBubble.vue:14`
(`alt="Agent is typing a message"`), `ChatHeader.vue:41` (`alt="avatar"`).

**O que falta, medido:**

1. **`aria-live` = 0.** Mensagem nova que chega não é anunciada. Para um produto cujo conteúdo
   inteiro chega de forma assíncrona, essa é a falha mais séria da lista.
2. **Nenhum heading nas views medidas.** O título do header colapsado é um `<span>`
   (`ChatHeader.vue:47`). Existe um `<h2>` em `ChatHeaderExpanded.vue:48`, mas ele só aparece na
   Home **e** apenas quando a inbox tem texto de boas-vindas — nunca na view de mensagens
   (`ViewWithHeader.vue:39`, `isHeaderCollapsed` retorna `true` fora da Home).
3. **Sem `<main>`.** Só `<header>` e `<footer>`.
4. **`HeaderActions.vue:83-111`** — os três botões (encerrar, popout, fechar) têm `:title`
   (`HeaderActions.vue:91`) mas **não têm `aria-label`**; e o botão de voltar (`ChatHeader.vue:30-36`)
   não tem nem `title` nem `aria-label`.
5. **Foco invisível no campo de mensagem.** Ao dar Tab até o textarea, o `outline` computado é
   `rgba(0, 0, 0, 0) solid 2px` `[MEDIDO]` — **transparente**. Vem do `outline-none` em
   `ChatInputWrap.vue:188`. O container tem `border-n-brand shadow-focus` (`ChatInputWrap.vue:132`),
   mas o elemento focado em si não sinaliza nada.
6. **Foco nos botões é o padrão do navegador**, não do produto: `rgb(16, 16, 16) auto 1px` em todos
   `[MEDIDO]`, inclusive no launcher (`.woot-widget-bubble`).
7. **Launcher sem `aria-label`** `[MEDIDO]`: `document.activeElement` após Tab na página host é o
   `<button class="woot-widget-bubble woot-elements--right">` com `aria-label: null`.
8. **Sem focus trap.** A ordem de Tab dentro do iframe, medida em sequência, foi:
   botão → input → botão emoji → link do branding → `BODY` → `BODY` → botão voltar → textarea
   `[MEDIDO]`. Sai do widget e volta, sem ciclo controlado.
9. **Alvos de toque abaixo do mínimo (mobile 375×667, `is_mobile=True`)** `[MEDIDO]` —
   todos os `button`/`a` da view de mensagens: **40×24, 24×24, 32×32, 32×32, 180×24 px**.
   O mínimo de WCAG 2.5.5 (AAA) e da Apple HIG é 44×44. **Nenhum passa.**

### A5.4 Contrastes medidos

Calculei a razão WCAG a partir das cores computadas reais (luminância relativa, fórmula
WCAG 2.1) `[MEDIDO]`:

| Par medido | Claro | Escuro | AA texto normal (4,5:1) |
|---|---:|---:|---|
| Texto da bolha do agente | **16,39:1** | **11,78:1** | passa nos dois |
| **Link dentro da bolha do agente** | **2,27:1** | 6,01:1 | **REPROVA no claro** |
| `code` dentro da bolha do agente | 5,94:1 | 6,57:1 | passa |
| **Texto da bolha do usuário** | **3,07:1** | **3,07:1** | **REPROVA nos dois** |
| Separador de data | 5,94:1 | 6,57:1 | passa |

Duas falhas, com causa rastreada:

**(1) Link na bolha do agente, tema claro: 2,27:1.** Cor medida `rgb(45,196,111)` (#2DC46F, o
`n-brand` verde) sobre fundo `rgb(255,255,255)`. Vem de `views/_conversation.scss:205`
(`.chat-bubble.agent .link { @apply text-n-brand; }`) e `_conversation.scss:185`. No escuro passa
(6,01:1) porque o fundo da bolha é `rgb(44,45,54)`. **A falha é específica do tema claro** — não
generalize.

**(2) Texto da bolha do usuário: 3,07:1 nos dois temas.** Branco sobre `#009CE0`. E não é
descuido: `UserMessageBubble.vue:25` **chama** `getContrastingTextColor(widgetColor)`. O problema é
o algoritmo. Implementação em `node_modules/@chatwoot/utils/src/helpers.ts:9-15` `[FATO]`:

```ts
export const getContrastingTextColor = (bgColor: string): string => {
  const r = parseInt(color.slice(0, 2), 16);
  const g = parseInt(color.slice(2, 4), 16);
  const b = parseInt(color.slice(4, 6), 16);
  return r * 0.299 + g * 0.587 + b * 0.114 > 186 ? '#000000' : '#FFFFFF';
};
```

É **YIQ com limiar 186** — uma heurística de brilho percebido dos anos 90, **não** a luminância
relativa da WCAG. Para `#009CE0`: `0×0,299 + 156×0,587 + 224×0,114 = 117,1` → devolve `#FFFFFF` →
3,07:1. O algoritmo escolhe entre dois extremos e **não verifica se o resultado atinge razão
alguma**. Passa em cores muito claras ou muito escuras e falha na faixa média — exatamente onde
moram as cores de marca corporativas.

Vale notar que o repositório **já tem** a ferramenta certa, sem uso no widget:
`shared/helpers/colorHelper.js` tem `adjustColorForContrast(color, backgroundColor)`, que itera
misturando a cor até bater uma razão-alvo, usando `getContrast`/`getLuminance` de `color2k` `[FATO]`.
Hoje ela serve outra finalidade e o `isWidgetColorLighter` (mesmo arquivo) é usado só pelo launcher
(`sdk/IFrameHelper.js:321`).

---

## A6. Renderização de mensagem

### A6.1 O pipeline

```
message.content (Markdown, texto puro)
  → useMessageFormatter().formatMessage(msg, isATweet, isAPrivateNote, linkify)
      shared/composables/useMessageFormatter.js:18-26
  → new MessageFormatter(...)          shared/helpers/MessageFormatter.js:98-138
      ├─ sanitizeLegacyGroupContent()  MessageFormatter.js:81-91   (fork, grupos WAHA)
      └─ createMarkdownInstance()      MessageFormatter.js:35-55
           MarkdownIt({ html:false, xhtmlOut:true, breaks:true, linkify, typographer:true,
                        quotes:'""''', maxNesting:20 })
             .use(mentionPlugin)        shared/helpers/markdownIt/link
             .use(imgResizeManager)     MessageFormatter.js:23-33
             .use(mila, {class:'link', rel:'noreferrer noopener nofollow', target:'_blank'})
  → v-dompurify-html                   AgentMessageBubble.vue:101 / UserMessageBubble.vue:33
      DOMPurify + hook afterSanitizeAttributes → força target="_blank"
      shared/helpers/HTMLSanitizer.js:10-20
```

**A sanitização é adequada** `[FATO]`: `html: false` no MarkdownIt já bloqueia HTML bruto na
entrada, e o `v-dompurify-html` roda DOMPurify na saída. Duas camadas. Saída real medida
`[MEDIDO]`:

```html
<div class="message-content text-n-slate-12"><p>Olá! Veja o <strong>plano Pro</strong> e o
<a href="https://exemplo.com" class="link" rel="noreferrer noopener nofollow" target="_blank">nosso
site</a>.</p>
<ul><li>Item um</li><li>Item dois</li></ul>
<p><code>codigo()</code></p></div>
```

**Um problema de performance, claro no código** `[FATO]`: `MessageFormatter.js:109` chama
`createMarkdownInstance(linkify)` **dentro do construtor**, e `useMessageFormatter.js:19` cria
`new MessageFormatter(...)` **a cada chamada de `formatMessage`**. E `formatMessage` é chamado no
template (`AgentMessageBubble.vue:101`), ou seja, **a cada render de cada bolha**. Uma instância
de MarkdownIt com 3 plugins é construída por mensagem, por render.
`[INFERÊNCIA]` — em conversas longas isso é trabalho repetido e desnecessário; a instância é pura e
dependeria apenas de `linkify`. Não medi o custo em ms. `[NÃO VERIFICADO]`

### A6.2 Tipos de mensagem suportados

O despacho está em `AgentMessageBubble.vue:42-67` (computeds) e `:92-152` (template) `[FATO]`:

| `content_type` | Componente | Onde |
|---|---|---|
| (texto / default) | `.chat-bubble.agent` + `v-dompurify-html` | `AgentMessageBubble.vue:94-115` |
| `input_email` | `template/EmailInput.vue` | `:104-108` |
| `integrations` | `template/IntegrationCard.vue` | `:110-114` |
| `input_select` | `shared/components/ChatOptions.vue` | `:116-123` |
| `form` | `shared/components/ChatForm.vue` | `:124-130` |
| `cards` | `shared/components/ChatCard.vue` (v-for) | `:131-140` |
| `article` | `template/Article.vue` | `:141-143` |
| `input_csat` | `shared/components/CustomerSatisfaction.vue` | `:144-150` |

Anexos são tratados um nível acima, em `AgentMessage.vue:207-240`: `image` → `ImageBubble`,
`video` → `VideoBubble`, `audio` → `<audio controls class="h-10 dark:invert">`, resto → `FileBubble` `[FATO]`.

**Onde um tipo novo entraria hoje:** três lugares ao mesmo tempo — um computed em
`AgentMessageBubble.vue:42-67`, um `v-if` no template, e a condição de exclusão em
`AgentMessageBubble.vue:95-97`, que é literalmente:

```html
v-if="!isCards && !isOptions && !isForm && !isArticle && !isCards && !isCSAT"
```

Note o `!isCards` **repetido** e `!isIntegrations`/`!isTemplateEmail` **ausentes** (esses dois
renderizam *dentro* da bolha de texto, o que é inconsistente com os demais). `[FATO]`

### A6.3 Métricas visuais das bolhas

`getComputedStyle` no embed real, desktop 1280×900, com mensagens injetadas no store `[MEDIDO]`:

| Propriedade | Bolha do agente | Bolha do usuário |
|---|---|---|
| `background` (claro) | `rgb(255, 255, 255)` | `rgb(0, 156, 224)` |
| `background` (escuro) | `rgb(44, 45, 54)` | `rgb(0, 156, 224)` |
| `color` (claro) | `rgb(28, 32, 36)` | `rgb(255, 255, 255)` |
| `color` (escuro) | `rgb(237, 238, 240)` | `rgb(255, 255, 255)` |
| `border-radius` | `20px 20px 20px 4px` | `20px 20px 4px 20px` |
| `padding` | `12px 16px` | `12px 16px` |
| `font-size` / `line-height` | `14px` / `21px` (1,5) | `14px` / `21px` |
| `box-shadow` | `rgba(50,50,93,.08) 0 4px 6px, rgba(0,0,0,.05) 0 1px 3px` | idêntico |
| `word-break` | `break-word` | `break-word` |
| `max-width` (regra) | `88%` do wrap (`_conversation.scss:7`) | `85%` (`_conversation.scss:77`) |

Outros elementos `[MEDIDO]`: nome do agente 12px/500/`rgb(96,100,108)` claro e `rgb(176,180,186)`
escuro; avatar 24×24; separador de data 14px, altura 50px; `.conversation-wrap` padding
`32px 8px 8px`; header 400×72 (desktop) e 375×72 (mobile); footer altura 48px; campo de texto
16px (bom — evita o zoom automático do iOS).

**Indicador de digitando é um GIF** `[FATO]`: `AgentTypingBubble.vue:13-18` usa
`<img src="assets/images/typing.gif">`, **19.296 bytes** `[MEDIDO]`. Não acompanha tema, não
acompanha cor de marca, não escala. O `tailwind.config.js:288-291,335` já define o keyframe
`typing-bounce` e a animação `animate-typing-bounce` — **não usados pelo widget**.

### A6.4 Lista de mensagens: sem virtualização

`ConversationWrap.vue:115-126` `[FATO]`: dois `v-for` aninhados (grupo por data → mensagens),
renderizando **todas** as mensagens no DOM. Sem `v-memo`, sem janela virtual.

Paginação: `ConversationWrap.vue:83-96`, `handleScroll` dispara `fetchOldConversations` quando
`scrollTop < 100`, guardando `previousScrollHeight` para restaurar a posição. Funciona, mas o
listener é ligado direto (`ConversationWrap.vue:64`) **sem throttle/debounce**.

`ConversationWrap.vue:67-72` — o hook `updated()` compara `previousConversationSize` e chama
`scrollToBottom()`. `[INFERÊNCIA]` — `updated()` dispara a cada re-render do componente, então há
leitura de `scrollHeight` (reflow forçado) em situações que não são chegada de mensagem.

---

# PARTE B — A ARQUITETURA PROPOSTA

## B7. Design tokens: resolver o `widget_color` na raiz

### B7.1 O diagnóstico em uma frase

Hoje existem **três** sistemas de cor concorrentes no widget: as custom properties de
`woot.scss` (tema), os literais `brand`/`#1FB85A` de `theme/colors.js` (marca), e o `:style`
inline com `widgetColor` (inbox). Eles não se conhecem, e por isso o header é verde num widget azul.

A proposta é ter **um** sistema: custom properties, com a cor da inbox entrando por elas.

### B7.2 Onde injetar (e por que o iframe ajuda)

**O iframe ajuda, e muito.** Três razões concretas, todas verificáveis no comportamento atual:

1. O widget tem um `document` próprio — `:root` é dele, não do site do cliente. Escrever
   `documentElement.style.setProperty` não colide com nada do host (o mecanismo já é usado hoje em
   `App.vue:118-125`, e funcionou: `--widget-color` estava correta em todas as medições).
2. O CSS do site host não entra (isolamento nativo do iframe) e o nosso não vaza para fora.
3. A configuração já chega antes do primeiro paint: `window.chatwootWebChannel.widgetColor` é
   escrita inline no HTML servido (`app/views/widgets/show.html.erb:16`) — está disponível **antes**
   do bundle carregar.

O que o iframe **não** resolve: o launcher vive **fora** dele, no `document` do host
(`sdk/IFrameHelper.js:326-338`). Então o sistema de tokens precisa de dois pontos de injeção —
um dentro (widget) e um fora (SDK) — alimentados pela mesma fonte.

**Ponto de injeção recomendado — o próprio ERB, não o JS.** Em `app/views/widgets/show.html.erb`,
emitir um `<style>` com os tokens derivados no servidor. Isso elimina o "flash de verde" entre o
primeiro paint e o `mounted()` do App.vue, e faz a cor funcionar mesmo se o JS demorar.
O `App.vue` continuaria reescrevendo os mesmos tokens quando o SDK mandar `config-set` (para
`darkMode` e overrides em runtime).

### B7.3 A camada de tokens proposta

Três níveis, na ordem: **primitivo → semântico → componente.**

**Nível 1 — primitivos (não mudam por inbox).** É o que já existe em `woot.scss:169-381`:
`--slate-*`, `--gray-*`, `--ruby-*`, `--amber-*`, `--teal-*`. Mantém. Só remove a pintura de
verde na rampa `--iris-*` (`woot.scss:193`), que é uma gambiarra de branding dentro de uma rampa
de primitivo.

**Nível 2 — semânticos de marca (derivados do `widget_color`).** Este é o nível que não existe hoje:

| Token | Significado | Derivação |
|---|---|---|
| `--w-brand` | a cor da inbox, crua | `inbox.widget_color` |
| `--w-brand-hover` | estado hover | `--w-brand` escurecida/clareada ~8% conforme luminância |
| `--w-brand-active` | estado pressed | ~14% |
| `--w-brand-subtle` | fundo tênue (chips, badges) | `--w-brand` a 10% de alfa |
| `--w-brand-border` | borda/foco | `--w-brand` ajustada a ≥3:1 contra `--w-surface` |
| `--w-on-brand` | **texto sobre `--w-brand`** | ver B7.4 |
| `--w-brand-readable` | **a marca usada como texto sobre a superfície** | ver B7.4 |

O `--w-brand-readable` é a peça que corrige a falha de 2,27:1 do link: **cor de marca como
preenchimento e cor de marca como texto são dois tokens diferentes.** Hoje são o mesmo, e é por
isso que o mesmo verde que funciona como fundo de header falha como cor de link sobre branco.

**Nível 3 — semânticos de superfície (por tema).** `--w-surface`, `--w-surface-raised`,
`--w-bubble-in-bg`, `--w-bubble-in-fg`, `--w-bubble-out-bg` (= `--w-brand`),
`--w-bubble-out-fg` (= `--w-on-brand`), `--w-text`, `--w-text-muted`, `--w-border`,
`--w-focus-ring`, `--w-shadow-bubble`, `--w-shadow-panel`.

Mapeados no Tailwind, esses viram `bg-w-brand`, `text-w-on-brand`, `bg-w-bubble-in` — e a
substituição de `bg-n-brand` por `bg-w-brand` nos três arquivos do bug passa a ser mecânica.

### B7.4 A regra de contraste automático

Substituir o YIQ binário por um cálculo de duas etapas, ambas com luminância relativa WCAG
(o `color2k` já está no projeto, usado em `shared/helpers/colorHelper.js`):

**Etapa 1 — `--w-on-brand` (texto sobre a marca).** Calcular a razão de contraste de branco e de
preto contra `--w-brand`; escolher o melhor dos dois. Se o melhor ainda ficar abaixo de 4,5:1,
**escurecer a própria marca** até que o par atinja 4,5:1 e usar essa versão escurecida como fundo
da bolha do usuário e do botão de enviar.

Com `#009CE0`: branco dá 3,07:1 e preto dá 6,83:1 `[MEDIDO]` → o algoritmo escolheria **preto** e já resolveria
a falha medida sem tocar na cor da marca. Para cores onde nenhum dos dois basta (verdes e laranjas
médios), a segunda parte da regra entra.

**Etapa 2 — `--w-brand-readable` (marca como texto).** Iterar a mistura da marca com
preto (fundo claro) ou branco (fundo escuro) até atingir **4,5:1** contra `--w-surface` do tema
corrente. É exatamente o que `shared/helpers/colorHelper.js:12-29` (`adjustColorForContrast`)
já faz — só que com alvo 3,1:1; bastaria parametrizar o alvo.

Com `#2DC46F` sobre branco (2,27:1 hoje), a iteração produziria um verde mais escuro que passa
em 4,5:1 — o link fica legível **e** continua sendo a marca.

**Etapa 3 — teto de customização.** O cliente escolhe `widget_color` livremente, mas os tokens
derivados são **calculados**, nunca informados. Assim o cliente não consegue produzir uma
combinação ilegível: escolher amarelo-limão gera `--w-on-brand: preto` e
`--w-brand-readable` = um âmbar escuro. **A liberdade fica na marca, a garantia fica no token.**

Onde calcular: no **servidor** (Ruby, no `show.html.erb`), para os tokens estarem no primeiro byte
de HTML; e o mesmo cálculo em JS para o SDK aplicar no launcher, que vive fora do iframe.
`[INFERÊNCIA]` — duplicar a fórmula em duas linguagens é um risco de divergência; a alternativa é o
servidor calcular e o SDK receber os tokens já prontos no `config-set`, o que evita a duplicação.
Recomendo a segunda.

### B7.5 O que isso apaga

- `--widget-color` escrita e nunca lida (`App.vue:118-125`).
- Os `:style` inline espalhados em 7 componentes (A3.3).
- `bg-n-brand` / `text-n-brand` / `border-n-brand` nos 23 pontos do widget e do shared (A3.4).
- O literal `hover:bg-[#1FB85A]` (`ChatSendButton.vue:27`).
- A dependência do YIQ de `@chatwoot/utils`.
- A pintura de verde na rampa `--iris-*` (`woot.scss:184-196`, `255`, `272`).

---

## B8. Estrutura de componentes

### B8.1 O que quebrar

**`App.vue` (386 linhas) → casco + roteador de eventos.**

O `registerListeners` de 16 ramos (`App.vue:258-345`) vira um mapa, no molde que o SDK já usa
(`sdk/IFrameHelper.js:104-117`):

- `widget/bridge/handlers/` — um arquivo por evento, cada um `(payload, ctx) => void`.
- `widget/bridge/index.js` — o mapa `{ 'config-set': onConfigSet, ... }` + a validação de origem
  que hoje não existe (`helpers/utils.js:18-21`).
- `App.vue` fica com template, classes de estado e a montagem da ponte.

Ganho concreto além da estética: cada handler passa a ser testável sem montar o App inteiro, e o
`postMessage` ganha um ponto único onde validar `e.origin` e trocar o `targetOrigin: '*'`
(`helpers/utils.js:9-12`) pela origem real.

**`AgentMessageBubble.vue` (152 linhas) → registry de tipos.**

Hoje: 8 computeds booleanos (`:42-67`) + 6 blocos `v-if` (`:92-152`) + a condição de exclusão com
`!isCards` duplicado (`:95-97`). Proposta:

```
widget/message-types/index.js       → { text, input_email, input_select, form, cards,
                                        article, input_csat, integrations }
widget/message-types/<tipo>.vue     → um componente por tipo
AgentMessageBubble.vue              → <component :is="resolve(contentType)" v-bind="..." />
```

Adicionar um tipo passa a ser **um arquivo + uma linha no mapa**, em vez de três edições em
lugares distintos. E resolve de quebra a inconsistência de `input_email`/`integrations`
renderizarem dentro da bolha de texto enquanto os outros renderizam fora.

**`views/_conversation.scss` (209 linhas) → estilos junto dos componentes.**

O layout da conversa (posição, agrupamento, raios de canto, `max-width`) está num SCSS global
distante dos componentes que ele estiliza. Mover para `<style scoped>` de `ChatMessage`,
`AgentMessage`, `UserMessage` e `ConversationWrap`, deixando no global só o que é
genuinamente transversal.

### B8.2 O que juntar

**`AgentMessage.vue` (266 l.) e `UserMessage.vue` (182 l.)** repetem quase tudo: `hasImageError`/
`hasVideoError` com `watch` + `mounted` idênticos (`AgentMessage.vue:41-46,143-159` e o
equivalente em `UserMessage.vue`), o mesmo bloco de anexos, o mesmo `MessageReplyButton`, o mesmo
`ReplyToChip`. Proposta: um `MessageRow.vue` com `direction: 'in' | 'out'` e slots para o que
difere de verdade (avatar + nome do agente do lado `in`; status de envio do lado `out`).

**`ChatHeader.vue` (63 l.) e `ChatHeaderExpanded.vue` (57 l.)** são o mesmo header em dois
estados. Proposta: um `WidgetHeader.vue` com `variant: 'compact' | 'expanded'`. Ambos são
arquivos que o upstream quase não toca (ver B12), então é uma junção barata em risco de merge.

**Os quatro `*Bubble.vue` de anexo** (`ImageBubble`, `VideoBubble`, `FileBubble`, mais o `<audio>`
solto em `AgentMessage.vue:231-237`) viram um `AttachmentBubble.vue` com despacho por `file_type` —
o mesmo padrão do registry de tipos.

### B8.3 O que vira primitivo

Uma pasta `widget/ui/` com componentes sem regra de negócio, cada um consumindo **só** tokens:

`WButton` (variantes brand/ghost/danger, com estado de foco visível — hoje inexistente),
`WIconButton` (com `aria-label` **obrigatório** via prop, o que faz o linter pegar as omissões de
`HeaderActions.vue:83-111`), `WBubble` (fundo/raio/sombra por token, sem saber o que renderiza
dentro), `WAvatar`, `WSpinner`, `WField`, `WSurface`.

**Regra que sustenta o redesenho:** nenhum componente de `widget/ui/` pode importar de `dashboard/`
nem conter cor literal. É uma regra verificável por lint (ver B11.4), não uma boa intenção.

### B8.4 Cortar o cordão com o dashboard

Os 13 imports de A1.4 têm soluções de tamanhos bem diferentes:

| Import | Peso do problema | Saída |
|---|---|---|
| `dashboard/composables/store` (5 usos) | trivial | 8 linhas copiadas para `widget/composables/store.js` |
| `dashboard/components-next/avatar/Avatar.vue` (3 usos) | pequeno | `widget/ui/WAvatar.vue` próprio |
| `dashboard/.../languages` (`App.vue:8`) | trivial | tabela local de direção RTL |
| `dashboard/.../businessHour.js` | pequeno | mover para `shared/` |
| **`dashboard/composables/useTransformKeys`** | **arrasta @sentry/core (156 KB de fonte)** | usar `camelcase-keys` direto |
| **`shared/.../ResizableTextArea` → `dashboard/helper/editorHelper`** | **arrasta @sentry/vue** | extrair só as funções usadas |
| `shared/helpers/MessageFormatter.js:4` → `whatsappGroupHelper` | médio | mover o helper para `shared/` |

Os dois em negrito são os que pagam a conta em bytes.

---

## B9. Performance

### B9.1 Ordenado por retorno sobre esforço

| # | Ação | Ganho medido/estimado | Esforço | Toca componente? |
|---|---|---|---|---|
| 1 | **Ligar gzip/brotli no nginx** | ~2,58 MB → ~575 KB na primeira visita | trivial | não |
| 2 | **`content` próprio do Tailwind para o widget** | **−1.047.130 B cru / −96.626 B gzip** `[MEDIDO]` | baixo | não |
| 3 | **Tirar o Leaflet do grafo eager** | −150.679 B cru / −43.491 B gzip `[MEDIDO]` | baixo | não |
| 4 | **FormKit só na rota do pre-chat** | parte relevante dos 350.867 B de `index-*` `[ESTIMATIVA]` | médio | sim (`widget.js:32-40`) |
| 5 | **Chunk vendor separado para o widget** | tira Amplitude (428 KB de fonte) e Sentry (156 KB) | médio | não |
| 6 | **i18n sob demanda** | −200.591 B de JSON `[MEDIDO]` | médio | sim (`i18n/index.js`) |
| 7 | **`vue.runtime.esm-bundler`** | ~192 KB de fonte de compilador `[ESTIMATIVA]` | médio | não |
| 8 | **Trocar o logo do branding** | −~88 KB `[MEDIDO]` | trivial | não |
| 9 | **Substituir `typing.gif` por CSS** | −19.296 B + tema/marca corretos | baixo | sim |
| 10 | **Memoizar a instância do MarkdownIt** | render de bolha | baixo | sim |

**Os itens 1, 2 e 3 sozinhos são o grosso do problema, e nenhum deles exige tocar num componente
Vue.** Isso é importante para o planejamento: dá para colher a maior parte do ganho de performance
**antes** de começar o redesenho, sem conflitar com ele.

### B9.2 Detalhamento dos três primeiros

**(1) Compressão.** Medido: nenhum asset do widget vem com `content-encoding` (A4.6). É
configuração de nginx (`gzip_types`/`brotli_types` incluindo `text/css` e
`application/javascript`). `[NÃO VERIFICADO]` se a frota de produção está igual — verificar antes.

**(2) Tailwind com `content` próprio.** Um segundo arquivo de config que herda o base e restringe
o `content` a `widget/**` + `shared/**`, usado só na compilação do CSS do widget. Medido: **56.002 B
cru / 9.501 B gzip**, contra 1.103.132 / 106.127 (A4.3). O ponto delicado é que hoje há um único
pipeline PostCSS para todas as entradas — a mudança é no build, não no CSS.

**(3) Leaflet.** Duas correções, e vale fazer as duas:
- Remover `manualChunks: { leaflet: ['leaflet'] }` (`vite.config.ts:86-88`). O `LocationPickerModal`
  já faz `await import('leaflet')` (`LocationPickerModal.vue:90`), então o Rollup criaria o chunk
  dinâmico sozinho — que era, presumo, a intenção original da linha.
- Garantir que os helpers de interop não fiquem hospedados num chunk de vendor pesado. Um
  `manualChunks` como função, mandando `node_modules/leaflet` para um chunk e deixando o resto ao
  algoritmo padrão, resolve.

Depois de aplicar, **verificar com a mesma medição**: `window.L` deve ser `undefined` dentro do
iframe, e `leaflet-*.js` não deve aparecer no `modulepreload` do HTML de `/widget`.

### B9.3 Virtualização da lista de mensagens

**Recomendação: não virtualizar agora.** Justificativa medida: o DOM inteiro do widget com a
conversa aberta tem **74 nós** `[MEDIDO]`. Cada mensagem acrescenta ~8-12 nós. Uma conversa de
50 mensagens fica na casa de 500-700 nós — irrelevante para qualquer navegador atual.

**O limiar em que passa a valer:** acima de ~200 mensagens simultâneas no DOM (~2.000 nós), e
apenas se a medição mostrar jank. Como a paginação já carrega para trás sob scroll
(`ConversationWrap.vue:83-96`), esse volume é raro num chat de site — é um cenário de suporte
técnico longo, não de conversão.

**O que fazer em vez disso, e que dá ganho hoje:**
- `v-memo` na linha de mensagem, com chave em `[message.id, message.status, message.content_attributes]`.
- Trocar o `updated()` de `ConversationWrap.vue:67-72` por um `watch` no tamanho da conversa —
  evita leitura de `scrollHeight` em re-renders que não são chegada de mensagem.
- `requestAnimationFrame` ou throttle no `handleScroll` (`ConversationWrap.vue:64,83`).
- Memoizar a instância do MarkdownIt (A6.1).

**Se um dia virtualizar:** o obstáculo real não é a biblioteca, é que o layout das bolhas depende
de seletores de irmão adjacente em `_conversation.scss:50-74,106-118`
(`.agent-message-wrap + .agent-message-wrap`, `.has-response + .user-message-wrap`) para arredondar
cantos e espaçar grupos. Uma janela virtual quebra esses seletores. **Migrar o agrupamento para
props calculadas no store (`isFirstOfGroup`, `isLastOfGroup`) é pré-requisito** — e é uma boa ideia
independentemente da virtualização.

### B9.4 Imagens e fontes

**Fontes — achado que economiza análise futura.** `shared/assets/fonts/widget_fonts` declara
**7 `@font-face` da Inter** (Thin, Light, Regular, Italic, Medium, SemiBold, Bold), e os 7 `.woff2`
são publicados (**773.684 bytes** somados) `[MEDIDO]`. Mas `theme.fontFamily.sans`
(`tailwind.config.js:10-20,69`) **não inclui Inter**, e a `font-family` computada no widget é
`-apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, …` `[MEDIDO]`.

**Consequência: nenhum arquivo de fonte é baixado** — nenhum `Inter-*.woff2` aparece na lista de
recursos do iframe `[MEDIDO]`. Ou seja, **o custo de rede hoje é zero**; o que existe é 7 blocos
`@font-face` inúteis no CSS e 773 KB de arquivos publicados à toa.

Para o redesenho isso é uma **decisão em aberto, não um bug**: ou assume-se a stack de fonte do
sistema (mais rápido, zero requisição, aparência nativa por plataforma) ou adota-se a Inter de
verdade — e aí subset + `font-display: swap` + 2 pesos, não 7.

**Imagens:**
- `logo_thumbnail.svg` **90.492 B** para renderizar a 24 px `[MEDIDO]` — trocar por um SVG
  desenhado à mão ou um PNG de 2×.
- `chat-spx-background.png` 88.534 B + `chat-spx-background-light.png` 96.098 B `[MEDIDO]` — o
  padrão de fundo. Como é tileado a 400 px, um WebP ou um padrão SVG resolveria por uma fração.
  `[INFERÊNCIA]` — os dois são baixados? Não apareceram na lista de recursos do iframe na minha
  sessão (a view de mensagens só foi aberta via hash), então **não confirmei**. `[NÃO VERIFICADO]`
- `typing.gif` 19.296 B — substituir por três `<span>` com `animate-typing-bounce`, keyframe que
  **já existe** em `tailwind.config.js:288-291`.

---

## B10. Isolamento e tema dentro do iframe

### B10.1 O que o iframe já protege (e o que não)

**Protege:** o CSS do site do cliente não entra no widget, e o nosso não sai. Isso é isolamento
real e é a razão de o widget nunca ter tido problema de "o site quebrou meu chat".

**Não protege:** o CSS que **nós mesmos** colocamos dentro do iframe. E é aí que está o vazamento.

### B10.2 Como o CSS do dashboard chega ao widget hoje

Não é vazamento por herança de DOM — é vazamento **por build**. A cadeia, toda medida:

1. `tailwind.config.js:24-38` tem um `content` único que inclui `./app/javascript/dashboard/**/*.vue`.
2. `widget/assets/scss/woot.scss:2-4` importa `tailwindcss/base|components|utilities`.
3. O Tailwind gera as utilidades de **todo** o `content` e o widget recebe o arquivo inteiro.
4. Resultado medido: 436 regras de ícone (700.673 B) para 10 ícones usados; classes como
   `i-lucide-bot` e `animate-copilot-menu-in`, que não existem em `widget/` nem `shared/`,
   presentes no CSS servido ao widget (A4.3).

**Como cortar:** o item 2 de B9.1 — `content` próprio. Corte de 94,9% medido.

### B10.3 O outro vazamento: globais dentro do iframe

`[MEDIDO]` — inventário de `window` dentro do iframe do widget:

```
L, __SENTRY__, WOOT_WIDGET, actionCable, chatwootWebChannel,
chatwootPubsubToken, authToken, globalConfig, referrerURL
```

`L` (Leaflet 1.9.4) e `__SENTRY__` **não deveriam existir ali**. `authToken` e `globalConfig` em
`window` são leitura fácil para qualquer script que rode no mesmo documento.

Proposta: mover `chatwootWebChannel`, `authToken` e `globalConfig` para dentro do store na
inicialização (o ERB continua servindo, o JS lê uma vez e apaga o global) e eliminar `L`/`__SENTRY__`
pelas correções de B9.

### B10.4 Tema dentro do iframe

A mecânica está certa (classe `dark` + custom properties). Os três ajustes:

1. **Aplicar `dark` no `<html>`, não no `<div>` raiz.** Hoje `App.vue:377` põe no div. Isso
   significa que `<body>` e `<html>` ficam fora do escopo — foi exatamente por isso que, medindo
   `getComputedStyle(document.documentElement)`, os tokens vieram com valores de tema claro mesmo
   com a classe `dark` presente `[MEDIDO]`. Não gera bug visível hoje porque tudo pintado está
   dentro do div, mas é uma armadilha para quem for redesenhar.
2. **Definir `color-scheme` no `:root`** para que scrollbars e controles nativos (`<audio controls>`
   de `AgentMessage.vue:231-237`, `<select>` do pre-chat) acompanhem o tema. Hoje o
   `color-scheme: light dark` está em `ConversationWrap.vue:138`, só no container da conversa.
3. **Dar variante escura à cor de marca.** `--iris-9` é `45 196 111` nos dois temas `[MEDIDO]`.
   No novo sistema, `--w-brand-readable` já resolve isso por construção (B7.4).

E um ajuste de comportamento, não de CSS: hoje o default é `light` (A5.2). `[INFERÊNCIA]` — mudar o
default do SDK para `auto` faria o widget respeitar a preferência do sistema sem que o cliente
precise configurar nada. É decisão de produto; a mudança é uma linha (`sdk/sdk.js:74`).

---

## B11. Testes

### B11.1 O que já existe

| Ferramenta | Versão | Estado |
|---|---|---|
| **Vitest** | 3.0.5 | ativo — `pnpm test` (`package.json`), jsdom, 33 specs no widget `[MEDIDO]` |
| **Playwright** | ^1.59.1 | instalado; `playwright.config.js` existe, mas `testDir: 'spec/e2e'` e o único suite é Copilot (dashboard) `[FATO]` |
| **Histoire** | 0.17.15 | configurado (`histoire.config.ts`); **1 única story no widget** — `Availability/AvailabilityText.story.vue` `[MEDIDO]` |
| **size-limit** | ^8.2.4 | ativo no CI, medindo o arquivo errado (A4.8) |

**Lacuna medida:** dos 33 specs do widget, **apenas 2 montam componente** (`messageMixin.spec.js`
e `configMixin.spec.js`, e mesmo esses testam mixin, não render) `[MEDIDO]`. Todo o resto é store,
helpers e API. **Não há um único teste de render de componente do widget.** Um redesenho total
sobre essa base é redesenho sem rede.

### B11.2 Regressão visual

O caminho mais curto usa o que já está instalado, sem adicionar dependência:

- **Playwright já está no projeto** e `toHaveScreenshot()` faz comparação de imagem nativa. Basta
  um segundo projeto no `playwright.config.js` (`testDir: 'spec/e2e/widget'`) e uma página host
  fixa servida do próprio repositório.
- **A matriz mínima**, derivada do que este estudo mediu: 4 views (`home`, `messages`,
  `prechat-form`, `unread`) × 2 temas × 2 viewports (1280×900 e 375×667) = **16 snapshots**.
- **Fixtures determinísticas obrigatórias.** As mensagens precisam ser injetadas no store, não
  vir do backend — usei exatamente essa técnica nesta onda
  (`store.commit('conversation/pushMessageToConversation', msg)`) e ela funciona bem. Sem isso, o
  snapshot depende de dados vivos e vira flaky.
- **Congelar tempo** — o separador de data renderiza "Hoje" (`shared/components/DateSeparator.vue`).

**Uma trava específica que este estudo justifica:** um teste que roda a mesma inbox com **duas
`widget_color` diferentes** e afirma que header, botão de enviar e bolha do usuário têm o **mesmo**
`background-color`. Esse teste falharia hoje e é a garantia de que o bug de A3.3 não volta.

### B11.3 Acessibilidade

`@axe-core/playwright` integra com o Playwright já instalado. As asserções que este estudo torna
concretas (todas com número medido para comparar):

1. `document.documentElement.lang` não vazio (hoje: `""`).
2. Existe pelo menos um `[aria-live]` na view de mensagens (hoje: 0).
3. Todo `<button>` tem nome acessível (hoje: 0 de 2 na Home, 2 de 4 em Messages).
4. Contraste ≥ 4,5:1 para texto normal (hoje falha em 2 pares: link na bolha do agente no claro,
   2,27:1; texto da bolha do usuário, 3,07:1).
5. Alvo de toque ≥ 44×44 no viewport móvel (hoje: 0 de 5 passam).
6. Indicador de foco visível — `outline-width > 0` **e** `outline-color` não transparente
   (hoje o textarea tem `rgba(0,0,0,0) solid 2px`).

### B11.4 Travar o peso do bundle no CI

O `size-limit` precisa medir **o que o navegador baixa**, não um glob de arquivo. Duas correções:

**(a) Medir o grafo, não o arquivo.** Um script que lê `public/vite/.vite/manifest.json`, resolve
o fecho transitivo de `imports` + `css` da entrada `entrypoints/widget.js` e soma — é exatamente o
cálculo que produziu a tabela de A4.2 e ele cabe em ~30 linhas. Alternativa mais simples: apontar
o `size-limit` para o conjunto explícito de arquivos do grafo.

**(b) Limpar o diretório antes de medir**, para o glob não casar com builds antigos (hoje casa com
4 hashes `[MEDIDO]`).

**Orçamentos propostos** — a coluna "hoje" é medida, e cada teto tem uma razão:

| Métrica | Hoje `[MEDIDO]` | Teto proposto | Por quê |
|---|---:|---:|---|
| JS eager do widget (gzip) | 482.322 B | 150 KB | após tirar Leaflet, Amplitude, Sentry e FormKit eager |
| CSS do widget (gzip) | 106.127 B | 20 KB | o `content` restrito já mede 9.501 B |
| CSS do widget (cru) | 1.103.132 B | 80 KB | idem |
| Total eager (gzip) | 588.943 B | 170 KB | soma dos dois |
| SDK (gzip) | 9.570 B | 15 KB | já está bom; trava para não regredir |

E uma trava que não é de tamanho, mas fecha o buraco que gerou este relatório: **um teste que falha
se `leaflet-*.js` aparecer nos imports estáticos da entrada `entrypoints/widget.js` no manifest.**
Uma linha de asserção contra um bug de 150 KB.

---

## B12. Risco de merge com o upstream

### B12.1 Quanto o fork já divergiu

`[MEDIDO]` — `git diff --numstat v4.12.1 HEAD -- app/javascript/widget/ app/javascript/sdk/`:

| Arquivo | + | − |
|---|---:|---:|
| `widget/components/ConversationWrap.vue` | 37 | 3 |
| `widget/assets/scss/woot.scss` | 32 | 32 |
| `widget/components/ChatInputWrap.vue` | 5 | 10 |
| `widget/components/ChatHeader.vue` | 5 | 5 |
| `sdk/IFrameHelper.js` | 4 | 1 |
| `widget/components/ChatHeaderExpanded.vue` | 3 | 3 |
| `widget/components/HeaderActions.vue` | 3 | 3 |
| `widget/components/ChatSendButton.vue` | 2 | 6 |
| `sdk/sdk.js` | 2 | 2 |
| `widget/components/AgentMessageBubble.vue` | 1 | 1 |
| `widget/components/AgentTypingBubble.vue` | 1 | 3 |
| `widget/components/PreChat/Form.vue` | 1 | 1 |
| `widget/views/Messages.vue` | 1 | 1 |
| `widget/assets/images/logo.svg` | 1 | 1 |

**O widget está praticamente virgem.** Apenas 4 commits do fork tocaram `widget/` ou `sdk/` na
história inteira `[MEDIDO]`: `4284a31898` (design system WhatsApp + Lucide), `baf08bad28`
(upgrade 4.10.1→4.12.1), `87095e111b` (auditoria best practices), `c42a446322` (o commit que trocou
o brand para verde).

**Isso é bom e ruim ao mesmo tempo.** Bom: merges de upstream têm passado limpos até aqui. Ruim: a
repaginada vai transformar essa área de "quase idêntica ao upstream" em "totalmente reescrita" — e
é exatamente aí que os merges futuros vão doer.

### B12.2 O que o upstream mexe

Duas leituras complementares — frequência histórica (36 meses, até `v4.16.2`, excluindo i18n e
specs) e a variação concreta nas 4 minors que já passaram desde a nossa base `[MEDIDO]`:

| Arquivo | Commits (36 m) | v4.12.1→v4.16.2 | Fork mexeu? |
|---|---:|---:|---|
| `components/ChatInputWrap.vue` | **17** | +12 −9 | **sim (+5 −10)** |
| `components/AgentMessage.vue` | **17** | — | não |
| `components/PreChat/Form.vue` | **16** | +39 −33 | sim (+1 −1) |
| `components/ChatFooter.vue` | **15** | +37 −12 | não |
| `views/Home.vue` | 13 | — | não |
| `components/UserMessage.vue` | 13 | +3 −4 | não |
| `App.vue` | 12 | +4 −0 | não |
| `components/Form/PhoneInput.vue` | 11 | — | não |
| `views/PreChatForm.vue` | 10 | +6 −7 | não |
| `components/UnreadMessage.vue` | 10 | — | não |
| `sdk/IFrameHelper.js` | 10 | — | sim (+4 −1) |
| `assets/scss/woot.scss` | 9 | **+30 −4** | **sim (+32 −32)** |
| `components/HeaderActions.vue` | 8 | — | sim (+3 −3) |
| `components/ChatHeader.vue` | 8 | — | sim (+5 −5) |
| `components/AgentMessageBubble.vue` | 8 | — | sim (+1 −1) |
| `components/layouts/ViewWithHeader.vue` | 7 | — | não |
| `components/ChatHeaderExpanded.vue` | 7 | — | sim (+3 −3) |
| `store/modules/appConfig.js` | 6 | — | não |
| `components/AgentTypingBubble.vue` | 6 | — | sim (+1 −3) |
| `store/modules/conversation/actions.js` | 5 | **+51 −8** | não |
| `components/ConversationWrap.vue` | 5 | — | **sim (+37 −3)** |
| `views/Messages.vue` | 4 | — | sim (+1 −1) |
| `composables/useDarkMode.js` | 4 | — | não |

### B12.3 O mapa: campo minado × zona segura

**🔴 CAMPO MINADO — upstream mexe muito E é lógica, não visual.** Reescrever aqui custa caro em
todo merge futuro:

| Arquivo | Por quê |
|---|---|
| `components/ChatInputWrap.vue` | 17 commits, mexido nas 4 últimas minors, e o fork já mexeu |
| `components/PreChat/Form.vue` | 16 commits, +39 −33 só desde a nossa base |
| `components/ChatFooter.vue` | 15 commits, +37 −12 desde a base |
| `store/modules/conversation/*` | +51 −8 em `actions.js`, +29 em `mutations.js` desde a base |
| `assets/scss/woot.scss` | 9 commits, +30 −4 desde a base, **e o fork já reescreveu 32 linhas** — colisão praticamente garantida |
| `api/endPoints.js` / `api/conversation.js` | +29 −11 e +17 −4 desde a base |
| `sdk/IFrameHelper.js` | 10 commits; é a ponte, mexer aqui quebra o contrato dos dois lados |

**🟢 ZONA SEGURA — upstream mexe pouco ou nada, e o que existe é apresentação:**

| Arquivo | Commits (36 m) | Desde v4.12.1 |
|---|---:|---|
| `components/ChatHeader.vue` | 8 | **zero mudanças** |
| `components/ChatHeaderExpanded.vue` | 7 | **zero** |
| `components/ChatSendButton.vue` | — | **zero** |
| `components/HeaderActions.vue` | 8 | **zero** |
| `components/ConversationWrap.vue` | 5 | **zero** |
| `components/AgentMessageBubble.vue` | 8 | **zero** |
| `components/AgentTypingBubble.vue` | 6 | **zero** |
| `components/layouts/ViewWithHeader.vue` | 7 | **zero** |
| `views/Messages.vue` | 4 | **zero** |
| `views/Home.vue` | 13 | **zero** |
| `assets/scss/views/_conversation.scss` | — | **zero** |
| **arquivos novos que criarmos** | — | risco zero por definição |

**É uma coincidência muito favorável:** os três arquivos do bug de cor — `ChatHeader.vue`,
`ChatHeaderExpanded.vue`, `ChatSendButton.vue` — estão **todos** na zona segura, com **zero**
mudanças do upstream em 4 minors. Corrigir o `widget_color` é barato em risco de merge.

### B12.4 Como estruturar o redesenho para minimizar conflito

Quatro regras, derivadas do mapa acima:

**1. Todo componente novo em pasta nova.** `widget/ui/`, `widget/message-types/`, `widget/bridge/`
não existem no upstream — conflito zero, para sempre. Quanto mais do redesenho morar em arquivos
novos, menor o custo permanente.

**2. Nos arquivos do campo minado, substituir por delegação, não reescrever.** Em vez de
redesenhar `ChatInputWrap.vue` (17 commits) por dentro, deixá-lo como uma casca fina que renderiza
`widget/ui/WComposer.vue`. Quando o upstream mudar a lógica de anexo/emoji, o merge acontece num
arquivo de 30 linhas em vez de num de 190.

**3. Tokens em arquivo próprio, não em `woot.scss`.** `woot.scss` é o pior dos dois mundos:
o upstream mexe (+30 −4 desde a base) **e** o fork já reescreveu 32 linhas. Colocar
`widget/assets/scss/_tokens.scss` (novo) e deixar `woot.scss` apenas com o `@import` reduz a
superfície de conflito a uma linha.

**4. Nunca tocar em `store/modules/conversation/` para fins visuais.** É o módulo que o upstream
mais mexeu desde a nossa base (+51 −8 em actions, +29 em mutations). Se o redesenho precisar de
`isFirstOfGroup`/`isLastOfGroup` (B9.3), calcular num getter **novo** em arquivo separado, não
alterando `getters.js`.

E uma medida de higiene que este estudo torna óbvia: **antes de começar, rodar o merge de
`v4.16.2` sozinho.** Hoje ele mexe em 113 arquivos do widget (+4.332 −7.635) `[MEDIDO]`. Fazer
isso *depois* do redesenho é resolver dois problemas embaralhados.

---

# O QUE ISSO SIGNIFICA PARA O REDESENHO DO CHATSPX

**1. A cor da marca não chega no produto, e isso está medido.** Numa inbox configurada com
`#009CE0`, a bolha do launcher e a bolha do usuário são azuis, mas o header, o botão de enviar,
os links das mensagens e os estados de foco são `#2DC46F`. O widget mostra **duas cores de marca
na mesma tela**, em light e dark, desktop e mobile. A causa é rastreável até um literal
(`theme/colors.js:123`) e a uma variável CSS que é escrita e nunca lida (`App.vue:118-125`, zero
consumidores). Recomendo tratar isso como o **primeiro item** do redesenho, não como um detalhe de
acabamento — e os três arquivos envolvidos estão na zona segura de merge, o que torna a correção
barata.

**2. Antes de desenhar qualquer tela, arrumar o build.** Três mudanças que não tocam num único
componente Vue devolvem a maior parte do peso: ligar compressão no nginx (hoje o widget trafega
cru, ~2,58 MB), dar um `content` próprio ao Tailwind (medido: −94,9% do CSS, de 1.103.132 para
56.002 bytes) e tirar o Leaflet do grafo eager (−150.679 bytes, e de quebra some o `window.L`
dentro do iframe). Fazer isso **antes** significa que o redesenho começa num terreno limpo e que
os ganhos não vão se confundir com os efeitos do redesenho.

**3. O widget herda o bundle do dashboard, e essa é a dívida de fundo.** Ele baixa o SDK da
Amplitude (428 KB de fonte), o Sentry (156 KB), o FormKit inteiro com todos os idiomas (510 KB só
de i18n) e 40 traduções eager (205 KB, das quais 200 KB nunca serão usadas por um cliente
brasileiro), porque compartilha chunks com o dashboard e porque 13
arquivos do widget importam de `dashboard/`. Recomendo tratar "widget não importa de `dashboard/`"
como **regra de lint**, verificável, e não como convenção — é o único jeito de a fronteira não
voltar a vazar durante um redesenho de meses.

**4. Um sistema de tokens de três níveis resolve cor, tema e customização de uma vez.** Primitivos
(o que já existe), semânticos de marca derivados do `widget_color`, e semânticos de superfície por
tema. A peça que falta hoje e que corrige duas falhas de contraste medidas é separar **marca como
preenchimento** de **marca como texto** (`--w-on-brand` e `--w-brand-readable`), calculando ambos
por luminância WCAG em vez do YIQ binário de `@chatwoot/utils` — que devolve branco sobre `#009CE0`
e produz 3,07:1. O cálculo certo já existe no repositório (`shared/helpers/colorHelper.js`), só
não é usado no widget. Injetar os tokens no HTML servido pelo ERB elimina o flash de cor errada no
primeiro paint; o iframe **ajuda**, porque nos dá um `:root` que é só nosso.

**5. A acessibilidade está abaixo do que se espera de um produto de 2026, e o redesenho é a hora.**
Zero `aria-live` (mensagem que chega não é anunciada — num chat), `lang` vazio, nenhum heading,
foco invisível no campo de mensagem (`outline` transparente medido), launcher sem nome acessível e
**nenhum** alvo de toque atingindo 44×44 no mobile. Nada disso é caro de corrigir quando se está
reescrevendo os componentes; todos são caros de corrigir depois.

**6. Não virtualizar a lista agora.** O DOM inteiro do widget tem 74 nós. O ganho seria zero e o
custo é alto, porque o layout das bolhas depende de seletores de irmão adjacente em
`_conversation.scss`. O que dá retorno hoje é `v-memo`, trocar o `updated()` por `watch`,
throttle no scroll e memoizar a instância do MarkdownIt (hoje uma nova é construída por bolha, por
render). Se um dia o volume justificar, o pré-requisito é mover o agrupamento de mensagens de
CSS para dados.

**7. Estruturar o redesenho por pastas novas é a defesa contra o custo de merge.** O widget está
quase idêntico ao upstream (4 commits do fork na história), e o upstream continua mexendo — 113
arquivos do widget mudaram entre a nossa base e a v4.16.2. O padrão que protege é: componentes
novos em `widget/ui/`, `widget/message-types/`, `widget/bridge/` (conflito zero por construção);
nos arquivos que o upstream mais mexe (`ChatInputWrap`, `PreChat/Form`, `ChatFooter`,
`store/conversation/`), deixar cascas finas que delegam, em vez de reescrever por dentro; tokens
em arquivo próprio, nunca dentro de `woot.scss`. E rodar o merge de `v4.16.2` **antes** de começar,
para não embaralhar dois problemas.

**8. O gate de tamanho no CI hoje dá falso verde.** Ele reporta 76,53 kB gzip enquanto o widget
real custa 575 KiB — fator de ~7,5×, porque mede um glob de arquivo em vez do grafo de imports.
Corrigir isso é pré-requisito para que qualquer meta de performance do redesenho signifique alguma
coisa. E vale acrescentar uma asserção específica: falhar o build se `leaflet-*.js` voltar a
aparecer nos imports estáticos da entrada do widget.

---

## Anexo — arquivos de imagem gerados por esta task

Em `plano/estudo-chat-web/frontend/shots/` (prefixo `t15-`):

| Arquivo | O que mostra |
|---|---|
| `t15-launcher-desktop-light.png` / `-dark.png` | Launcher fechado, 1280×900, embed real |
| `t15-launcher-mobile-375.png` | Launcher fechado, 375×667, `is_mobile` |
| `t15-panel-home-desktop-light.png` / `-dark.png` | Painel aberto na view Home |
| `t15-panel-messages-desktop-light.png` / `-dark.png` | View de mensagens — **header verde com `widget_color` azul** |
| `t15-panel-bolhas-desktop-light.png` / `-dark.png` | Bolhas com mensagens injetadas |
| `t15-bolhas-markdown-light.png` / `-dark.png` | Markdown na bolha do agente — link com 2,27:1 no claro |
| `t15-panel-mobile-375.png` | Painel em tela cheia no mobile |
| `t15-messages-mobile-375.png` | View de mensagens no mobile — alvos de toque |
| `t15-panel-aberto-1280.png` | Painel aberto sobre a página host |

## Anexo — como reproduzir as medições principais

```bash
# 1. Peso do grafo eager do widget (a tabela de A4.2)
python3 -c "import json;m=json.load(open('public/vite/.vite/manifest.json'));
e=m['entrypoints/widget.js'];print(e['imports'], e['css'])"

# 2. Conteúdo real do chunk 'leaflet'
python3 -c "import json;print(json.load(open('public/vite/assets/leaflet-58r2EQLt.js.map'))['sources'])"

# 3. Quem importa o chunk leaflet, e o quê
head -c 60 public/vite/assets/vue-dompurify-html-BsNF8atS.js

# 4. Ícones no CSS do widget × ícones usados
grep -o "\.i-lucide-[a-z0-9-]*" public/vite/assets/widget-EcEcykJV.css | sort -u | wc -l
grep -rhoE "i-(lucide|ri)-[a-z0-9-]+" app/javascript/widget/ app/javascript/shared/ | sort -u

# 5. CSS com content restrito (config temporário FORA do repo)
npx tailwindcss -c /tmp/.../tw.config.js -i in.css -o out.css   # → 56.002 B

# 6. Compressão servida
curl -skI -H "Accept-Encoding: gzip, br" \
  https://hmlchat.simplexsolucoes.com.br/vite/assets/widget-EcEcykJV.css | grep -i content-

# 7. Ramos do postMessage em App.vue
awk 'NR>=258 && NR<=345' app/javascript/widget/App.vue \
  | grep -cE "^\s*(} else if|if) \(message.event"        # → 16

# 8. --widget-color: escritas × leituras
grep -rn -- "--widget-color" app/ | grep -v node_modules  # → 1 (só a escrita)

# 9. Gate de tamanho atual
npx size-limit                                            # → 76.53 kB gzipped (falso verde)
```

As medições de navegador foram feitas com Playwright (`sync_playwright`,
`args=['--no-sandbox','--disable-dev-shm-usage']`) contra uma página host local que embute o SDK de
`http://localhost:3000`, com `getComputedStyle`/`getBoundingClientRect` e
`performance.getEntriesByType('resource')`. As mensagens usadas para medir bolhas foram injetadas
via `store.commit('conversation/pushMessageToConversation', …)` — **nenhuma mensagem foi enviada
ao backend e nenhum dado foi criado em homologação.**
