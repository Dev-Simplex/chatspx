# TASK 09 — Auditoria completa do widget de site do ChatSPX

> **Documento de estudo. Leitura apenas. Nenhum arquivo de código foi modificado na produção deste relatório.**
>
> Repositório auditado: `/home/chatwoot/chatwoot` — branch `homologacao`, HEAD `ee87f5e799`
> Base upstream declarada: Chatwoot `v4.12.1` (`config/app.yml:2`)
> Data da auditoria: 2026-08-11

---

## SUMÁRIO

- [0. Como ler este documento](#0-como-ler-este-documento)
- [1. Resumo executivo](#1-resumo-executivo)
- [2. Mapa de arquitetura](#2-mapa-de-arquitetura)
  - [2.1 Camadas](#21-camadas)
  - [2.2 Inventário de arquivos por camada](#22-inventário-de-arquivos-por-camada)
- [3. Sequência exata de boot](#3-sequência-exata-de-boot)
  - [3.1 Passo a passo (T0 → primeira mensagem)](#31-passo-a-passo-t0--primeira-mensagem)
  - [3.2 Tabela de requisições de rede](#32-tabela-de-requisições-de-rede)
  - [3.3 Diagrama textual](#33-diagrama-textual)
- [4. API pública `window.$chatwoot`](#4-api-pública-windowchatwoot)
  - [4.1 Snippet de instalação real](#41-snippet-de-instalação-real)
  - [4.2 `window.chatwootSettings` — todas as chaves](#42-windowchatwootsettings--todas-as-chaves)
  - [4.3 Métodos de `window.$chatwoot`](#43-métodos-de-windowchatwoot)
  - [4.4 Propriedades de estado expostas](#44-propriedades-de-estado-expostas)
  - [4.5 Eventos emitidos para o site host](#45-eventos-emitidos-para-o-site-host)
  - [4.6 Identity validation (HMAC)](#46-identity-validation-hmac)
- [5. Protocolo postMessage entre SDK e iframe](#5-protocolo-postmessage-entre-sdk-e-iframe)
  - [5.1 SDK → widget](#51-sdk--widget-parent--iframe)
  - [5.2 Widget → SDK](#52-widget--sdk-iframe--parent)
- [6. Backend](#6-backend)
  - [6.1 Modelo do canal](#61-modelo-do-canal-channelwebwidget)
  - [6.2 Controller HTML do iframe](#62-controller-html-do-iframe)
  - [6.3 Endpoints públicos da API do widget](#63-endpoints-públicos-da-api-do-widget)
  - [6.4 Payloads de resposta](#64-payloads-de-resposta)
  - [6.5 Onde ficam browser/referer/UTM](#65-onde-ficam-browserrefererutm)
  - [6.6 Campanhas](#66-campanhas)
  - [6.7 Autenticação e tokens](#67-autenticação-e-tokens)
- [7. Persistência no navegador](#7-persistência-no-navegador)
- [8. Realtime (ActionCable)](#8-realtime-actioncable)
- [9. Inventário de features do widget](#9-inventário-de-features-do-widget)
- [10. Configuração no dashboard](#10-configuração-no-dashboard)
  - [10.1 Abas da inbox Website](#101-abas-da-inbox-website)
  - [10.2 Campos configuráveis sem código](#102-campos-configuráveis-sem-código)
  - [10.3 O que exige fork/patch](#103-o-que-exige-forkpatch)
- [11. Tracking e atribuição hoje](#11-tracking-e-atribuição-hoje)
- [12. Build e peso](#12-build-e-peso)
- [13. Limitações, dívidas técnicas e pontos frágeis](#13-limitações-dívidas-técnicas-e-pontos-frágeis)
  - [13.1 Lista priorizada](#131-lista-priorizada)
  - [13.2 Detalhamento por item](#132-detalhamento-por-item)
- [14. Customizações do ChatSPX sobre o upstream](#14-customizações-do-chatspx-sobre-o-upstream)
- [15. Pontos de extensão seguros](#15-pontos-de-extensão-seguros)
- [16. IMPLICAÇÕES PARA O CHATSPX](#16-implicações-para-o-chatspx)
- [Anexo A — Cobertura de testes](#anexo-a--cobertura-de-testes-existente)
- [Anexo B — Comandos de verificação](#anexo-b--comandos-de-verificação-usados)

---

## 0. Como ler este documento

Convenção usada em todo o relatório:

| Marcador | Significado |
|---|---|
| **FATO VERIFICADO** | Li o código/arquivo/artefato no repositório e a referência `arquivo:linha` aponta para a evidência. Reproduzível com os comandos do Anexo B. |
| **MEDIDO** | Número obtido rodando comando local (tamanho de bundle, contagem de chaves i18n). Comando no Anexo B. |
| **INFERÊNCIA** | Conclusão minha derivada do código, mas não observada em runtime (ex.: ordem exata de requisições numa aba real). |
| **NÃO VERIFICADO** | Não consegui confirmar dentro do escopo desta task. |

Tudo neste relatório vem de leitura do repositório local. **Não houve execução de servidor, migration, deploy nem acesso a produção.** As URLs de referência do upstream Chatwoot citadas apontam para o repositório público `github.com/chatwoot/chatwoot` na tag `v4.12.1`, que é a base declarada do fork.

---

## 1. Resumo executivo

O widget de site do ChatSPX é o widget do Chatwoot v4.12.1 com uma camada fina de reskin visual. A arquitetura é:

1. Um **SDK** de ~29 KB (IIFE, sem dependências externas em runtime) que o cliente cola no `<head>`. Ele só faz três coisas: injeta CSS na página do cliente, cria a bolha (dois `<button>` + SVG inline) e cria um `<iframe>`.
2. Um **iframe** apontando para `{baseUrl}/widget?website_token=…`, que carrega uma **SPA Vue 3 completa** (Vuex + vue-router com hash history + vue-i18n + FormKit + DOMPurify).
3. Um canal de comunicação **`postMessage` com prefixo de string** (`chatwoot-widget:`) entre os dois.
4. Um backend Rails com **13 endpoints públicos** sob `/api/v1/widget/*`, autenticados por **JWT de 180 dias** guardado num cookie de primeira parte no domínio do cliente.

### O que está bom

- Isolamento de CSS é forte: o painel roda dentro de iframe, então o CSS do cliente não vaza para dentro nem vice-versa (exceto a folha da bolha, que é injetada no host).
- A superfície de API pública (`window.$chatwoot`) é razoavelmente rica: 14 métodos, 7 eventos de janela, HMAC de identidade, atributos customizados de contato **e** de conversa, labels.
- i18n do widget está **100% traduzido para pt-BR** — 85 de 85 chaves (**MEDIDO**), só `COMPONENTS.FILE_BUBBLE.DOWNLOAD` ficou igual ao inglês (mas "Download" é aceitável em pt-BR).
- Reconexão de WebSocket foi endurecida pelo próprio ChatSPX (watchdog de stream silencioso, reconexão em `focus`/`pageshow`/`visibilitychange`) — `app/javascript/shared/helpers/BaseActionCableConnector.js:1-218`.

### O que está ruim

| # | Problema | Gravidade |
|---|---|---|
| 1 | **CSS do widget tem 1,10 MB cru / 106 KB gzip** porque o Tailwind do widget compila as classes de todo o dashboard | Alta |
| 2 | **O chunk do Leaflet (150 KB cru / 43 KB gzip) está no grafo crítico do widget** — mapa que o widget nunca usa | Alta |
| 3 | **A customização visual do ChatSPX quebrou o `widget_color` por inbox**: header e botão de enviar viraram verde `#2dc46f` fixo | Alta (produto/SaaS) |
| 4 | **Duas classes Tailwind inventadas não existem no tema** e geram zero CSS: `bg-n-chat-bg` e `shadow-focus` | Média |
| 5 | **Zero tracking de origem**: nenhum UTM, `gclid`, `fbclid`, nem `dataLayer`. Só `referer` e `browser` | Alta (produto) |
| 6 | **`window.onmessage = …`** sobrescreve o handler de mensagem do site do cliente | Média |
| 7 | **Nenhuma verificação de `event.origin`** nos dois lados do postMessage | Média (segurança) |
| 8 | **Acessibilidade praticamente inexistente**: 2 `aria-label` em todo o widget, bolha sem rótulo traduzido, lista de mensagens sem `aria-live` | Alta |
| 9 | **`MutationObserver` na `<body>` inteira com `subtree: true`** só para detectar troca de URL em SPA | Média (performance no site do cliente) |
| 10 | **Orçamento de bundle (`size-limit`) só vigia o entry JS**, não o CSS nem os chunks compartilhados | Média |

### O gap principal frente ao mercado (para medir contra a Leadster e afins)

Hoje o widget é **reativo**: espera o visitante clicar. O que existe de proatividade é a "campanha" — regra de URL + tempo na página + horário comercial (`app/javascript/widget/helpers/campaignHelper.js:33-47`). Não existe: qualificação por fluxo conversacional dentro do widget, roteamento por resposta, captura de origem de mídia paga, integração com camada de dados de analytics, ou entrega de lead para CRM a partir do widget. Tudo isso hoje só existe fora do widget (Flows/Automações) e **não é acionável pelo widget web**.

---

## 2. Mapa de arquitetura

### 2.1 Camadas

```
┌───────────────────────────────────────────────────────────────────────────────┐
│  SITE DO CLIENTE  (origem: cliente.com.br)                                     │
│                                                                                │
│  <script> → GET {BASE_URL}/packs/js/sdk.js   (IIFE, 28.834 B / 9.491 B gzip)   │
│                                                                                │
│  window.chatwootSDK.run({ websiteToken, baseUrl })                             │
│         │                                                                      │
│         ├── injeta <style id="cw-widget-styles">  ← SDK_CSS (sdk/sdk.js)       │
│         ├── cria  <div id="cw-bubble-holder">     ← 2 <button> + SVG           │
│         ├── cria  <div id="cw-widget-holder">     ← wrapper posicionado        │
│         │        └── <iframe id="chatwoot_live_chat_widget">                   │
│         ├── define window.$chatwoot  (API pública, 14 métodos)                 │
│         ├── define window.onmessage  (⚠ sobrescreve o do cliente)              │
│         ├── MutationObserver(body, {childList, subtree})  ← detecta troca URL   │
│         └── cookies: cw_conversation / cw_user_<token> / cw_snooze_campaigns_till│
│                                                                                │
│         ↕  postMessage  string "chatwoot-widget:{json}"  (sem check de origin) │
│                                                                                │
│  ┌──────────────────────────────────────────────────────────────────────────┐ │
│  │  IFRAME  (origem: chatspx.app)  →  GET /widget?website_token=…            │ │
│  │                                                                           │ │
│  │  app/views/widgets/show.html.erb                                          │ │
│  │    window.chatwootWebChannel = {…}   ← config do canal, injetada no HTML  │ │
│  │    window.chatwootPubsubToken = '…'  ← token do ActionCable               │ │
│  │    window.authToken           = '…'  ← JWT de 180 dias                    │ │
│  │    window.globalConfig        = {…}  ← branding + limites                 │ │
│  │                                                                           │ │
│  │  SPA Vue 3  (entrypoints/widget.js)                                       │ │
│  │    ├── Vuex   11 módulos                                                  │ │
│  │    ├── Router hash history, 6 rotas                                       │ │
│  │    ├── i18n   51 locales                                                  │ │
│  │    ├── FormKit (pre-chat form)                                            │ │
│  │    ├── DOMPurify (sanitização de markdown de mensagem)                    │ │
│  │    └── ActionCableConnector → wss://…/cable  (RoomChannel)                │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼  HTTPS  X-Auth-Token: <JWT>
┌───────────────────────────────────────────────────────────────────────────────┐
│  RAILS  (chatspx.app)                                                          │
│    WidgetsController          → HTML do iframe                                 │
│    Api::V1::Widget::*         → 13 endpoints públicos                          │
│    Channel::WebWidget         → website_token, hmac_token, feature_flags       │
│    ContactInbox               → source_id (UUID) + pubsub_token                │
│    Conversation               → additional_attributes {browser, referer, …}     │
│    RoomChannel                → broadcast realtime                             │
└───────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Inventário de arquivos por camada

**SDK — 892 linhas ao todo** (**MEDIDO**: `wc -l app/javascript/sdk/*.js`)

| Arquivo | Linhas | Responsabilidade |
|---|---:|---|
| `app/javascript/entrypoints/sdk.js` | 222 | Entry do build IIFE. Define `window.chatwootSDK.run` e toda a API `window.$chatwoot`. |
| `app/javascript/sdk/sdk.js` | 295 | **Só CSS.** Exporta a constante `SDK_CSS` (folha injetada na página do cliente). Nome confuso — não é o entrypoint. |
| `app/javascript/sdk/IFrameHelper.js` | 348 | Cria o iframe, o canal postMessage e o mapa `events` (19 handlers). |
| `app/javascript/sdk/bubbleHelpers.js` | 112 | Cria bolha, ícone SVG, estados aberto/fechado, badge de não lidas. |
| `app/javascript/sdk/DOMHelpers.js` | 75 | `loadCSS`, helpers de classe, restauração pós-Turbo/Astro, `MutationObserver` de URL. |
| `app/javascript/sdk/cookieHelpers.js` | 45 | Nome do cookie de usuário, hash MD5 do payload de `setUser`, `setCookieWithDomain`. |
| `app/javascript/sdk/settingsHelper.js` | 14 | Normaliza `type`, `widgetStyle`, `darkMode`. |
| `app/javascript/sdk/constants.js` | 3 | `BUBBLE_DESIGN`, `WIDGET_DESIGN`, `DARK_MODE`. |

**Widget (SPA Vue) — 200 arquivos** (**MEDIDO**: `find app/javascript/widget -type f | wc -l`)

| Diretório | Conteúdo relevante |
|---|---|
| `widget/App.vue` (387 linhas) | Componente raiz. `mounted` orquestra o boot; `registerListeners` (linhas 258-345) é o roteador de eventos vindos do SDK — 17 `else if` encadeados. |
| `widget/router.js` | 6 rotas: `unread-messages`, `campaigns`, `home`, `prechat-form`, `messages`, `article-viewer`. `createWebHashHistory`. |
| `widget/views/` | 6 views (as 6 rotas). Todas lazy-loaded (`() => import(...)`). |
| `widget/components/` | 30 componentes. Núcleo: `ConversationWrap`, `ChatMessage`, `AgentMessageBubble`, `UserMessageBubble`, `ChatFooter`, `ChatInputWrap`, `ChatHeader`, `ChatHeaderExpanded`, `PreChat/Form`. |
| `widget/store/` | 11 módulos Vuex: `agent`, `appConfig`, `contacts`, `conversation`, `conversationAttributes`, `conversationLabels`, `events`, `globalConfig`, `message`, `campaign`, `article`. |
| `widget/api/` | 10 wrappers axios. `endPoints.js` centraliza a montagem de URL/params. |
| `widget/composables/` | 3: `useAttachments`, `useAvailability`, `useDarkMode`. |
| `widget/helpers/` | 11: `actionCable`, `axios`, `campaignHelper`, `campaignTimer`, `availabilityHelpers`, `IframeEventHelper`, `popoutHelper`, `urlParamsHelper`, `utils`, `uuid`, `WidgetAudioNotificationHelper`. |
| `widget/i18n/locale/` | **51 arquivos de locale**, incluindo `pt_BR.json` e `pt.json`. |
| `widget/mixins/` | 2: `configMixin` (lê `window.chatwootWebChannel`), `messageMixin`. |

**Backend**

| Arquivo | Papel |
|---|---|
| `app/models/channel/web_widget.rb` | Modelo do canal. 109 linhas. |
| `app/controllers/widgets_controller.rb` | Serve o HTML do iframe. 99 linhas. **Marcado como TODO de remoção na linha 1.** |
| `app/views/widgets/show.html.erb` | 43 linhas. Injeta 4 globais JS. |
| `app/controllers/api/v1/widget/base_controller.rb` | Base dos 11 controllers públicos. |
| `app/controllers/api/v1/widget/*.rb` | 9 controllers + 1 de integração (Dyte). |
| `app/controllers/concerns/website_token_helper.rb` | `auth_token_params`, `set_web_widget`, `set_contact`. |
| `app/services/widget/token_service.rb` | JWT HS256, expiração configurável (default 180 dias). |
| `app/helpers/widget_helper.rb` | `build_contact_inbox_with_token`. |
| `enterprise/app/controllers/enterprise/widgets_controller.rb` | Só o gate geográfico (`allowed_countries` via IP lookup). |

---

## 3. Sequência exata de boot

### 3.1 Passo a passo (T0 → primeira mensagem)

**FATO VERIFICADO** — cada passo tem referência de arquivo:linha. **INFERÊNCIA** quanto à ordem temporal exata em runtime (não medida com DevTools nesta task).

**T0 — Página do cliente carrega**

O snippet gerado por `Channel::WebWidget#web_widget_script` (`app/models/channel/web_widget.rb:64-82`) insere um `<script async>` apontando para `{FRONTEND_URL}/packs/js/sdk.js` e, no `onload`, chama `window.chatwootSDK.run({ websiteToken, baseUrl })`.

**T1 — `runSDK` executa** — `app/javascript/entrypoints/sdk.js:21-217`

1. Guarda de idempotência: se `window.$chatwoot` já existe, retorna (linha 22-24). Isso significa que **um segundo `run()` é silenciosamente ignorado** — não há troca de inbox em runtime.
2. Registra 3 listeners de frameworks de navegação: `turbo:before-render` (linha 27), `turbolinks:before-render` (linha 40), `astro:before-swap` (linha 46). Todos chamam `restoreWidgetInDOM`, que reanexa os 3 nós (`cw-bubble-holder`, `cw-widget-holder`, `cw-widget-styles`) ao novo `<body>` — `app/javascript/sdk/DOMHelpers.js:24-28`.
3. Lê `window.chatwootSettings` (linha 50). Se `useBrowserLanguage` for true, o locale vira `navigator.language.replace('-', '_')` (linhas 54-56).
4. Monta `window.$chatwoot` com 18 propriedades de estado + 14 métodos (linhas 58-211).
5. Chama `IFrameHelper.createFrame({ baseUrl, websiteToken })` (linha 213).

**T2 — `createFrame`** — `app/javascript/sdk/IFrameHelper.js:57-91`

1. Guarda de idempotência: se o iframe já existe, retorna (linha 58-60).
2. `loadCSS()` injeta `<style id="cw-widget-styles">` com todo o `SDK_CSS` no `<body>` do cliente — `app/javascript/sdk/DOMHelpers.js:4-10`.
3. Cria `<iframe>` com `src = {baseUrl}/widget?website_token={token}` (linha 54-56). **Se o cookie `cw_conversation` existir, ele é anexado como querystring**: `&cw_conversation={jwt}` (linhas 64-68).
4. `iframe.allow = 'camera;microphone;fullscreen;display-capture;picture-in-picture;clipboard-write;'` (linhas 70-71). **Note: nenhum atributo `sandbox`.**
5. `iframe.style.visibility = 'hidden'` — o iframe carrega escondido (linha 73).
6. Classes do holder: `woot-widget-holder woot--hide woot-elements--{right|left}` + opcionais `woot-widget--without-bubble` e `woot-widget-holder--flat` (linhas 75-84).
7. `widgetHolder.dataset.turboPermanent = true` (linha 85) — sobrevive a morphing do Turbo.
8. Chama `initPostMessageCommunication()`, `initWindowSizeListener()`, `preventDefaultScroll()` (linhas 88-90).

**T3 — `initPostMessageCommunication`** — `app/javascript/sdk/IFrameHelper.js:104-117`

```js
window.onmessage = e => {
  if (typeof e.data !== 'string' || e.data.indexOf('chatwoot-widget:') !== 0) return;
  const message = JSON.parse(e.data.replace('chatwoot-widget:', ''));
  if (typeof IFrameHelper.events[message.event] === 'function') {
    IFrameHelper.events[message.event](message);
  }
};
```

Dois problemas aqui, ambos **FATO VERIFICADO**:
- **Atribuição direta a `window.onmessage`** (não `addEventListener`) → **destrói qualquer handler `onmessage` que o site do cliente já tivesse**.
- **Nenhuma checagem de `e.origin`** → qualquer iframe/janela na página pode disparar `IFrameHelper.events[*]`, incluindo `setAuthCookie` (linha 213-215), que grava cookie de autenticação.

**T4 — Iframe carrega `/widget`** — `app/controllers/widgets_controller.rb`

Cadeia de `before_action` (linhas 5-12):
1. `set_global_config` — carrega `LOGO_THUMBNAIL`, `BRAND_NAME`, `WIDGET_BRAND_URL`, `DIRECT_UPLOADS_ENABLED`, `MAXIMUM_FILE_UPLOAD_SIZE`, `INSTALLATION_NAME` (linhas 16-25).
2. `set_web_widget` — `Channel::WebWidget.find_by!(website_token:)`; 404 se não achar (linhas 27-32).
3. `ensure_account_is_active` — 401 se conta suspensa (linhas 61-63).
4. `ensure_location_is_supported` — no-op no core; no enterprise faz IP lookup contra `account.custom_attributes['allowed_countries']` (`enterprise/app/controllers/enterprise/widgets_controller.rb:4-13`).
5. `set_token` — decodifica o JWT vindo de `?cw_conversation=` (linhas 34-41).
6. `set_contact` — busca `ContactInbox` por `source_id` do payload do JWT (linhas 43-52).
7. `build_contact` — **se não houver contato, cria um contato + contact_inbox + token novos imediatamente** (linhas 54-59). Ou seja: **abrir a página do cliente já cria uma linha em `contacts` e `contact_inboxes`, mesmo sem o visitante clicar na bolha.**
8. `allow_iframe_requests` (after_action) — remove `X-Frame-Options` se `allowed_domains` estiver vazio; senão define `Content-Security-Policy: frame-ancestors {domains}` (linhas 79-86). Exceção para WebView mobile quando a flag `allow_mobile_webview` está ligada (linhas 91-96).

O ERB (`app/views/widgets/show.html.erb:8-34`) injeta:

```js
window.chatwootWebChannel = { avatarUrl, hasAConnectedAgentBot, locale, websiteName,
  websiteToken, welcomeTagline, welcomeTitle, widgetColor, portal, enabledFeatures,
  enabledLanguages, replyTime, preChatFormEnabled, preChatFormOptions, workingHoursEnabled,
  csatSurveyEnabled, workingHours, outOfOfficeMessage, utcOffset, timezone,
  allowMessagesAfterResolved, disableBranding }
window.chatwootPubsubToken = '<contact_inbox.pubsub_token>'
window.authToken = '<JWT>'
window.globalConfig = { … }
```

**T5 — SPA monta** — `app/javascript/entrypoints/widget.js:48-54`

No `window.onload`: monta o app em `#app` e instancia `new ActionCableConnector(app, window.chatwootPubsubToken)`.

**T6 — `App.vue#mounted`** — `app/javascript/widget/App.vue:81-102`

1. `setLocale(locale)`, `setWidgetColor(widgetColor)`, `setWidgetColorVariable(widgetColor)` — este último grava `--widget-color` no `documentElement` (linhas 118-125).
2. `setHeader(window.authToken)` — define `X-Auth-Token` como header default do axios (`app/javascript/widget/helpers/axios.js:9-11`).
3. Se está em iframe → `registerListeners()` + `sendLoadedEvent()`.
   Se **não** está em iframe (modo popout / mobile webview) → busca conversas e agentes direto, sem esperar `config-set`.
4. `conversationAttributes/getAttributes` → **GET `/api/v1/widget/conversations`**.
5. `registerUnreadEvents()`, `registerCampaignEvents()`.

**T7 — `sendLoadedEvent`** — widget → SDK

Envia `{ event: 'loaded', config: { authToken, channelConfig } }` (`app/javascript/widget/helpers/IframeEventHelper.js:1-9`) via `window.parent.postMessage(..., '*')` (`app/javascript/widget/helpers/utils.js:8-13`). **Note o `'*'`** — o widget não restringe o target origin.

**T8 — SDK trata `loaded`** — `app/javascript/sdk/IFrameHelper.js:159-198`

1. `updateAuthCookie(message.config.authToken, baseDomain)` → grava o cookie `cw_conversation` **no domínio do cliente**, com validade de 365 dias (linha 160, `cookieHelpers.js:26-45`).
2. `window.$chatwoot.hasLoaded = true`.
3. Envia `config-set` de volta para o widget, com 13 chaves de configuração do `chatwootSettings` (linhas 163-179).
4. `IFrameHelper.onLoad({ widgetColor })` — torna o iframe visível, cria a bolha (linhas 302-340).
5. `toggleCloseButton()` — informa ao widget se está em viewport mobile (`matchMedia('(max-width: 668px)')`, linhas 341-347).
6. Se `window.$chatwoot.user` existe → envia `set-user`.
7. Registra listeners de primeira interação (`click`, `touchstart`, `keypress`, `keydown`) para inicializar o `AudioContext` e baixar `/audio/widget/ding.mp3` (linhas 145-156, 191-193).
8. **Dispara `window.dispatchEvent(new CustomEvent('chatwoot:ready'))`** — a menos que seja um `reset()` (linhas 195-197).

**T9 — `onLoad` cria a bolha** — `app/javascript/sdk/IFrameHelper.js:302-340`

1. `createBubbleHolder(hideMessageBubble)` → `<div id="cw-bubble-holder" class="woot--bubble-holder">` no `<body>` (`bubbleHelpers.js:64-72`).
2. `onLocationChangeListener()` → dispara `change-url` imediatamente **e** instala um `MutationObserver` na `<body>` com `{childList: true, subtree: true}` que compara `document.location.href` a cada mutação (`DOMHelpers.js:49-75`).
3. Cria o SVG da bolha, aplica `widgetColor` como `background` inline (linhas 334-335), e se a cor for clara adiciona `woot-widget-bubble-color--lighter` (linhas 321-324).
4. `onClickChatBubble()` → `bubbleHolder.addEventListener('click', onBubbleClick)`.

**T10 — Widget recebe `config-set`** — `app/javascript/widget/App.vue:265-272`

Dispara em paralelo:
- `setLocale(message.locale)` e `setBubbleLabel()` → devolve `setBubbleLabel` ao SDK com `$t('BUBBLE.LABEL')`.
- **GET `/api/v1/widget/messages`** (`fetchOldConversations`) → depois `setUnreadView()`.
- **GET `/api/v1/widget/inbox_members?website_token=…`** (`fetchAvailableAgents`).
- `setAppConfig(message)` → grava as 13 opções no Vuex.
- **GET `/api/v1/widget/contact`** (`contacts/get`).
- `setCampaignReadData(campaignsSnoozedTill)`.

**T11 — Widget recebe `change-url`** — `app/javascript/widget/App.vue:275-283`

- `initCampaigns({ currentURL, websiteToken, isInBusinessHours })` → se o cache local `chatwoot_campaigns_{token}` (TTL 1h) estiver frio, faz **GET `/api/v1/widget/campaigns?website_token=…`**.
- Grava `window.referrerURL = referrerURL` e `setReferrerHost(referrerHost)` no Vuex.

**T12 — Bolha clicada** — `bubbleHelpers.js:85-98`

- Alterna `woot--hide` em `chatBubble`, `closeBubble` e `widgetHolder`.
- `handleBubbleToggle(newIsOpen)` → `IFrameHelper.events.onBubbleToggle(isOpen)` (`IFrameHelper.js:250-255`), que:
  - envia `toggle-open` para o widget, e
  - se abriu, chama `pushEvent('webwidget.triggered')` → **POST `/api/v1/widget/events`** com `{name: 'webwidget.triggered', event_info: {initiated_at, referer}}`.
- Dispara `chatwoot:opened` ou `chatwoot:closed` na `window` do cliente.

**T13 — Envio da primeira mensagem**

Dois caminhos, dependendo de `shouldShowPreChatForm` (`app/javascript/widget/mixins/configMixin.js:39-45`):

- **Com pre-chat:** `PreChatForm.vue#onSubmit` → `conversation/createConversation` → **POST `/api/v1/widget/conversations`** com `{contact: {name,email,phone_number}, message: {content, timestamp, referer_url}, custom_attributes}`.
- **Sem pre-chat:** `ChatFooter#handleSendMessage` → `conversation/sendMessage` → **POST `/api/v1/widget/messages`**. O controller cria a conversa on-the-fly se ela não existir (`app/controllers/api/v1/widget/messages_controller.rb:45-47`).

Em ambos, o backend monta `conversation.additional_attributes` com `browser_language`, `browser`, `initiated_at` e `referer` (`app/controllers/api/v1/widget/base_controller.rb:31-46`).

### 3.2 Tabela de requisições de rede

**INFERÊNCIA** (derivada do código; não medida em navegador real). Ordem aproximada.

| # | Método | URL | Origem no código | Autenticação | Quando |
|---|---|---|---|---|---|
| 1 | GET | `{BASE_URL}/packs/js/sdk.js` | `web_widget.rb:70` | — | Sempre, todo page-load |
| 2 | GET | `{baseUrl}/widget?website_token=X[&cw_conversation=JWT]` | `IFrameHelper.js:54-69` | Cookie na querystring | Sempre |
| 3 | GET | `/vite/assets/widget-*.js` + `widget-*.css` + ~12 chunks | `show.html.erb:37` | — | Sempre (cacheável por hash) |
| 4 | WS | `/cable` (RoomChannel, `pubsub_token`) | `widget.js:50` | `pubsub_token` | Após `window.onload` |
| 5 | GET | `/api/v1/widget/conversations?…` | `App.vue:99` → `conversation.js:24-26` | `X-Auth-Token` | `App.mounted` |
| 6 | GET | `/api/v1/widget/messages?…` | `App.vue:268` → `endPoints.js:64-67` | `X-Auth-Token` | Após `config-set` |
| 7 | GET | `/api/v1/widget/inbox_members?website_token=X` | `App.vue:269` → `endPoints.js:73-78` | `X-Auth-Token` | Após `config-set` |
| 8 | GET | `/api/v1/widget/contact?…` | `App.vue:271` → `contacts.js:6-8` | `X-Auth-Token` | Após `config-set` |
| 9 | GET | `/api/v1/widget/campaigns?website_token=X` | `App.vue:277` → `endPoints.js:79-84` | `X-Auth-Token` | Após `change-url`, se cache frio |
| 10 | GET | `/hc/{slug}/{locale}/articles.json?page=1&sort=views&status=1&per_page=6` | `endPoints.js:100-108` | `X-Auth-Token` | Se a inbox tem portal ligado |
| 11 | GET | `{baseUrl}/audio/widget/ding.mp3` | `AudioNotificationHelper.js:41` | — | Na 1ª interação do usuário |
| 12 | POST | `/api/v1/widget/events` | `events.js:12-18` | `X-Auth-Token` | Ao abrir a bolha |
| 13 | PATCH | `/api/v1/widget/contact/set_user` | `contacts.js:12-17` | `X-Auth-Token` | Se o site chamar `setUser` |
| 14 | POST | `/api/v1/widget/conversations` | `endPoints.js:4-23` | `X-Auth-Token` | 1ª mensagem com pre-chat |
| 15 | POST | `/api/v1/widget/messages` | `endPoints.js:25-39` | `X-Auth-Token` | Cada mensagem |
| 16 | POST | `/api/v1/widget/conversations/update_last_seen` | `conversation.js:35-40` | `X-Auth-Token` | Ao ver mensagens |
| 17 | POST | `/api/v1/widget/conversations/toggle_typing` | `conversation.js:28-33` | `X-Auth-Token` | Ao digitar |
| 18 | POST | `/api/v1/widget/direct_uploads` | `ChatAttachment.vue:86` | `X-Auth-Token` (header manual) | Anexo com direct upload |

**Contagem no caminho crítico até o widget ficar utilizável (sem conversa prévia): 1 script + 1 documento + ~14 assets + 1 WebSocket + 5 chamadas de API.** — **INFERÊNCIA**.

### 3.3 Diagrama textual

```
site do cliente          SDK (window.$chatwoot)        iframe (SPA Vue)         Rails
──────────────────────────────────────────────────────────────────────────────────────
<script async> ─────────────────────────────────────────────────────► GET /packs/js/sdk.js
                          run({websiteToken,baseUrl})
                          loadCSS() → <style>
                          createFrame() ──────────────► GET /widget?website_token
                                                                       ├─ find_by website_token
                                                                       ├─ decode cw_conversation JWT
                                                                       ├─ set/build contact_inbox
                                                                       └─ render show.html.erb
                                                        mount Vue
                                                        new ActionCable ──────► WS /cable
                                                        ◄── postMessage 'loaded'
                          setCookie cw_conversation
                          postMessage 'config-set' ───►
                          onLoad() → cria bolha
                          dispatch chatwoot:ready
                                                        GET /widget/messages ──►
                                                        GET /widget/inbox_members ──►
                                                        GET /widget/contact ──►
                          postMessage 'change-url' ───►
                                                        GET /widget/campaigns ──►
   [usuário clica]
                          onBubbleClick()
                          postMessage 'toggle-open' ──►
                          pushEvent('webwidget.triggered')
                                                        POST /widget/events ──►
                          dispatch chatwoot:opened
   [usuário digita]
                                                        POST /widget/conversations ──►
                                                        ◄────────────── message.created (WS)
```

---

## 4. API pública `window.$chatwoot`

### 4.1 Snippet de instalação real

**FATO VERIFICADO** — gerado por `app/models/channel/web_widget.rb:64-82`:

```html
<script>
  (function(d,t) {
    var BASE_URL="https://chatspx.app";
    var g=d.createElement(t),s=d.getElementsByTagName(t)[0];
    g.src=BASE_URL+"/packs/js/sdk.js";
    g.async = true;
    s.parentNode.insertBefore(g,s);
    g.onload=function(){
      window.chatwootSDK.run({
        websiteToken: 'XXXXXXXXXXXXXXXXXXXXXXXX',
        baseUrl: BASE_URL
      })
    }
  })(document,"script");
</script>
```

Observações:
- O `BASE_URL` vem de `ENV.fetch('FRONTEND_URL', '')`. Se a variável não estiver setada, o snippet gerado sai **quebrado** (src `/packs/js/sdk.js` relativo ao site do cliente).
- `/packs/js/sdk.js` **não tem fingerprint de conteúdo** (o `vite.config.ts:63-69` força `entryFileNames: 'js/sdk.js'` no modo library). Ou seja: um deploy que muda o SDK depende inteiramente de cabeçalhos de cache do servidor para propagar. **NÃO VERIFICADO**: quais headers o nginx da frota devolve para `/packs/`.
- Não existe `integrity`/SRI, nem `crossorigin`.

### 4.2 `window.chatwootSettings` — todas as chaves

**FATO VERIFICADO** — `app/javascript/entrypoints/sdk.js:50-81`.

| Chave | Tipo | Default | Efeito | Linha |
|---|---|---|---|---|
| `locale` | string | `undefined` | Locale do widget (usa `_` como separador: `pt_BR`) | 51 |
| `baseDomain` | string | `undefined` | Domínio dos cookies. Usar `.dominio.com.br` para compartilhar sessão entre subdomínios | 52 |
| `useBrowserLanguage` | bool | `false` | Se true, sobrescreve `locale` com `navigator.language` | 54-56 |
| `hideMessageBubble` | bool | `false` | Esconde a bolha (para launcher próprio) | 62 |
| `position` | `'left'\|'right'` | `'right'` | Lado da tela. Qualquer valor ≠ `'left'` vira `'right'` | 64 |
| `type` | `'standard'\|'expanded_bubble'` | `'standard'` | Bolha redonda ou "pílula" com texto | 68 |
| `launcherTitle` | string | `''` | Texto da pílula (só com `type: 'expanded_bubble'`) | 69 |
| `showPopoutButton` | bool | `false` | Mostra botão de abrir em janela separada | 70 |
| `showUnreadMessagesDialog` | bool | `true` | Mostra o preview de não lidas fora do painel | 71 |
| `widgetStyle` | `'standard'\|'flat'` | `'standard'` | Cantos arredondados vs quadrados | 72 |
| `darkMode` | `'light'\|'auto'\|'dark'` | `'light'` | Esquema de cor | 74 |
| `welcomeTitle` | string | `''` | Sobrescreve o título vindo da inbox | 75 |
| `welcomeDescription` | string | `''` | Sobrescreve o subtítulo vindo da inbox | 76 |
| `availableMessage` | string | `''` | Texto quando há agente online | 77 |
| `unavailableMessage` | string | `''` | Texto quando não há agente | 78 |
| `enableFileUpload` | bool | `undefined` | Sobrescreve a feature flag da inbox (se explícito) | 79 |
| `enableEmojiPicker` | bool | `true` | Sobrescreve a feature flag da inbox | 80 |
| `enableEndConversation` | bool | `true` | Sobrescreve a feature flag da inbox | 81 |

Precedência entre `chatwootSettings` e a configuração da inbox: para `enableFileUpload` a regra está explícita em `app/javascript/widget/composables/useAttachments.js:25-33` — se o SDK setou explicitamente (`!== undefined`), o SDK vence; senão cai na feature flag da inbox.

### 4.3 Métodos de `window.$chatwoot`

**FATO VERIFICADO** — todos em `app/javascript/entrypoints/sdk.js`.

| Método | Assinatura | Linha | O que faz | Efeito colateral |
|---|---|---:|---|---|
| `toggle` | `(state?: 'open'\|'close')` | 83-85 | Abre/fecha o painel. Sem argumento, alterna. | `postMessage` interno; dispara `chatwoot:opened`/`closed` |
| `toggleBubbleVisibility` | `(visibility: 'show'\|'hide')` | 87-102 | Mostra/esconde a bolha em runtime | Manipula classes CSS + envia `sdk-set-bubble-visibility` |
| `popoutChatWindow` | `()` | 104-110 | Abre o chat em `window.open` 400×600 | Fecha o painel embutido |
| `setUser` | `(identifier: string\|number, user: object)` | 112-137 | Identifica o visitante | **Lança `Error`** se o identificador não for string/number, ou se `user` não tiver nenhuma de `avatar_url`/`email`/`name`. Grava cookie `cw_user_<websiteToken>` com MD5 do payload |
| `setCustomAttributes` | `(attrs: object)` | 139-145 | Atributos customizados **do contato** | **Lança `Error`** se objeto vazio |
| `deleteCustomAttribute` | `(key: string)` | 147-155 | Remove um atributo do contato | **Lança `Error`** se vazio |
| `setConversationCustomAttributes` | `(attrs: object)` | 157-165 | Atributos customizados **da conversa** | **Lança `Error`** se objeto vazio |
| `deleteConversationCustomAttribute` | `(key: string)` | 167-175 | Remove atributo da conversa | **Lança `Error`** se vazio |
| `setLabel` | `(label: string)` | 177-179 | Adiciona label à conversa | Silencioso. Backend só aplica se a label existir na conta (`labels_controller.rb:22-25`) |
| `removeLabel` | `(label: string)` | 181-183 | Remove label | Silencioso |
| `setLocale` | `(locale = 'en')` | 185-187 | Troca o idioma em runtime | Só aplica se o locale estiver em `enabledLanguages` (`App.vue:146-162`) |
| `setColorScheme` | `(darkMode = 'light')` | 189-193 | Troca `light`/`auto`/`dark` | Normalizado por `getDarkMode` |
| `reset` | `()` | 195-210 | Encerra a sessão do visitante | Remove `cw_conversation` e `cw_user_*`, recarrega o iframe, seta `resetTriggered = true` (**suprime o próximo `chatwoot:ready`**) |

**Detalhe importante em `setUser` (linhas 123-128):** o SDK calcula o MD5 do payload e compara com o cookie existente. Se for igual, **retorna sem fazer nada**. Isso significa que chamar `setUser` com os mesmos dados é barato, mas também que **uma mudança apenas em `custom_attributes` que não passe pelas 4 chaves de `ALLOWED_USER_ATTRIBUTES` (`avatar_url`, `email`, `name`, `identifier_hash` — `cookieHelpers.js:4-5`) não invalida o cache** e a chamada é engolida.

**Atributos do objeto `user` aceitos pelo widget** — `app/javascript/widget/store/modules/contacts.js:45-74`: `email`, `name`, `avatar_url`, `identifier_hash`, `phone_number`, `company_name`, `city`, `country_code`, `description`, `social_profiles`, `custom_attributes`. Os cinco do meio (`company_name`, `city`, `description`, `country_code`, `social_profiles`) são empacotados em `additional_attributes`.

### 4.4 Propriedades de estado expostas

| Propriedade | Fonte | Uso prático |
|---|---|---|
| `window.$chatwoot.hasLoaded` | `IFrameHelper.js:161` | Saber se o handshake terminou |
| `window.$chatwoot.isOpen` | `bubbleHelpers.js:91` | Saber se o painel está aberto |
| `window.$chatwoot.user` | `sdk.js:131` | Último payload passado a `setUser` |
| `window.$chatwoot.identifier` | `sdk.js:130` | Último identificador |
| `window.$chatwoot.websiteToken` / `baseUrl` / `baseDomain` / `locale` / `position` / `type` / … | `sdk.js:58-81` | Configuração corrente |

### 4.5 Eventos emitidos para o site host

**FATO VERIFICADO** — `app/javascript/widget/constants/sdkEvents.js:1-7`. Disparados via `window.dispatchEvent(new CustomEvent(name, {detail: data}))` (`app/javascript/shared/helpers/CustomEventHelper.js:1-15`).

| Evento | `detail` | Onde é disparado | Observação |
|---|---|---|---|
| `chatwoot:ready` | — | `IFrameHelper.js:195-197` | **Não dispara após `reset()`** |
| `chatwoot:opened` | — | `bubbleHelpers.js:78` | |
| `chatwoot:closed` | — | `bubbleHelpers.js:80` | Também devolve foco à bolha (`chatBubble.focus()`) |
| `chatwoot:error` | `{ …dados do erro }` | `IFrameHelper.js:199-205` | Hoje só é usado para `SET_USER_ERROR` (HMAC inválido) |
| `chatwoot:on-message` | payload completo da mensagem | `helpers/actionCable.js:65-69, 81-86` | Dispara em `message.created` e em `message.updated` **apenas quando `content_attributes.submitted_values` muda** (`IframeEventHelper.js:29-46`) |
| `chatwoot:on-start-conversation` | `{ hasConversation: bool }` | `TeamAvailability.vue:19-24`, `ChatFooter.vue:84-88` | Dispara quando o usuário clica em "iniciar conversa", **não** quando a conversa é de fato criada |
| `chatwoot:postback` | `{ …dados }` | `IFrameHelper.js:221-226` | **Nenhum caminho no widget emite `postback` hoje** — handler órfão |

**Lacunas relevantes de evento** (**FATO VERIFICADO** — busquei e não existem):
- Não há evento de **conversa criada** com o `conversation_id`. `chatwoot:on-start-conversation` é intenção, não conclusão.
- Não há evento de **mensagem enviada pelo visitante** (só recebe `on-message` do realtime).
- Não há evento de **pre-chat submetido** com os valores dos campos.
- Não há evento de **CSAT respondido**.
- Não há evento de **artigo aberto** / help center consultado.
- Não há evento de **campanha exibida** (o `campaign.triggered` é um POST de servidor, não um evento de janela).

### 4.6 Identity validation (HMAC)

**FATO VERIFICADO**.

Geração do hash (lado do cliente, no servidor dele) — exemplo no próprio repo, `app/views/widget_tests/index.html.erb:6-11`:

```ruby
OpenSSL::HMAC.hexdigest('sha256', <hmac_token da inbox>, user_id.to_s)
```

Validação no backend — `app/controllers/api/v1/widget/contacts_controller.rb:64-70`:

```ruby
params[:identifier_hash] == OpenSSL::HMAC.hexdigest('sha256', @web_widget.hmac_token, params[:identifier].to_s)
```

Regras de quando validar — `contacts_controller.rb:55-62`:
- Se `identifier_hash` está em branco **e** `hmac_mandatory` é false → não valida.
- Se `custom_attributes` está presente **e** `identifier` está em branco → não valida (é update de atributos, não identificação).
- Caso contrário → valida; 401 com `{error: 'HMAC failed: Invalid Identifier Hash Provided'}` se falhar.

Efeitos de sucesso — `contacts_controller.rb:12-25`:
- Se o contato atual já tem um `identifier` **diferente** do novo → cria um `contact_inbox` novo (com token novo), isolando as conversas do usuário anterior.
- Marca `contact_inbox.hmac_verified = true`, o que muda a busca de conversas em `base_controller.rb:10-17`: conversas passam a ser buscadas por **todos os `contact_inbox` verificados do contato**, não só pelo `source_id` atual. Isso é o que faz o histórico seguir o usuário entre dispositivos.

O token HMAC por inbox é exposto no dashboard em `settingsPage/ConfigurationPage.vue:342` e `:384`, e o toggle `hmac_mandatory` em `:360` / `:392`.

---

## 5. Protocolo postMessage entre SDK e iframe

Formato do envelope, nos dois sentidos: **string** `chatwoot-widget:` + JSON. Constante em `app/javascript/widget/helpers/constants.js:16`.

### 5.1 SDK → widget (parent → iframe)

Emissor: `IFrameHelper.sendMessage(key, value)` (`IFrameHelper.js:94-103`). **Target origin: a origem do `src` do iframe** — customização do ChatSPX, ver §14.

Receptor: `App.vue:258-345`.

| Evento | Payload | Ação no widget | Linha em App.vue |
|---|---|---|---|
| `config-set` | 13 chaves de config + `campaignsSnoozedTill` | Aplica config, busca conversas/agentes/contato | 265-272 |
| `widget-visible` | — | Rola conversa para o fim | 273-274 |
| `change-url` | `{referrerURL, referrerHost}` | Inicia campanhas, grava `window.referrerURL` | 275-283 |
| `toggle-close-button` | `{isMobile}` | Alterna layout mobile | 284-285 |
| `push-event` | `{eventName}` | POST `/widget/events` (com supressão em rotas de unread/campanha) | 286-287, 247-257 |
| `set-label` | `{label}` | POST `/widget/labels` | 288-289 |
| `remove-label` | `{label}` | DELETE `/widget/labels/:label` | 290-291 |
| `set-user` | `{identifier, user}` | PATCH `/widget/contact/set_user` | 292-293 |
| `set-custom-attributes` | `{customAttributes}` | PATCH `/widget/contact` | 294-298 |
| `delete-custom-attribute` | `{customAttribute}` | POST `/widget/contact/destroy_custom_attributes` | 299-303 |
| `set-conversation-custom-attributes` | `{customAttributes}` | POST `/widget/conversations/set_custom_attributes` | 304-308 |
| `delete-conversation-custom-attribute` | `{customAttribute}` | POST `/widget/conversations/destroy_custom_attributes` | 309-313 |
| `set-locale` | `{locale}` | Troca idioma + atualiza label da bolha | 314-316 |
| `set-color-scheme` | `{darkMode}` | Troca esquema de cor | 317-318 |
| `toggle-open` | `{isOpen}` | Roteia entre `home`/`messages`, reseta campanha | 319-340 |
| `sdk-set-bubble-visibility` | `{hideMessageBubble}` | Atualiza estado da bolha no Vuex | 341-342 |

### 5.2 Widget → SDK (iframe → parent)

Emissor: `app/javascript/widget/helpers/utils.js:8-13` — **`window.parent.postMessage(msg, '*')`**. **FATO VERIFICADO: usa `'*'`, sem restrição de origem.**

Receptor: `IFrameHelper.events` (`IFrameHelper.js:158-297`).

| Evento | Payload | Ação no SDK | Linha |
|---|---|---|---|
| `loaded` | `{config: {authToken, channelConfig}}` | Grava cookie, envia `config-set`, cria bolha, dispara `chatwoot:ready` | 159-198 |
| `error` | `{errorType, data}` | Dispara `chatwoot:error`; se `SET_USER_ERROR`, apaga o cookie de usuário | 199-205 |
| `onEvent` | `{eventIdentifier, data}` | Dispara evento arbitrário na `window` do cliente | 206-208 |
| `setBubbleLabel` | `{label}` | Atualiza texto da pílula | 209-211 |
| `setAuthCookie` | `{data: {widgetAuthToken}}` | **Regrava o cookie de autenticação** | 213-215 |
| `setCampaignReadOn` | — | Cookie `cw_snooze_campaigns_till` por 1 hora | 217-219 |
| `postback` | `{…}` | Dispara `chatwoot:postback` | 221-226 |
| `toggleBubble` | `'open'\|'close'\|undefined` | Alterna painel | 228-237 |
| `popoutChatWindow` | `{baseUrl, websiteToken, locale}` | Abre janela separada | 239-243 |
| `closeWindow` | — | Fecha painel e limpa modo unread | 245-248 |
| `onBubbleToggle` | `isOpen` | Envia `toggle-open`; se abriu, `pushEvent('webwidget.triggered')` | 250-255 |
| `onLocationChange` | `{referrerURL, referrerHost}` | Envia `change-url` | 256-261 |
| `updateIframeHeight` | `{extraHeight, isFixedHeight}` | Redimensiona iframe (modo unread/campanha) | 262-266 |
| `setUnreadMode` | — | Adiciona `has-unread-view` e abre o painel | 268-271 |
| `resetUnreadMode` | — | Remove `has-unread-view` | 273 |
| `handleNotificationDot` | `{unreadMessageCount}` | Liga/desliga o ponto vermelho na bolha | 274-288 |
| `closeChat` | — | Fecha painel | 290-292 |
| `playAudio` | — | `window.playAudioAlert()` | 294-296 |

**Superfície de ataque (FATO VERIFICADO):** como não há checagem de `e.origin` em `IFrameHelper.js:105-116`, qualquer script rodando na página do cliente (ou qualquer iframe de terceiro com acesso a `window.top`) pode enviar `chatwoot-widget:{"event":"setAuthCookie","data":{"widgetAuthToken":"..."}}` e trocar a sessão do visitante. O impacto prático é limitado (quem já roda JS na página do cliente tem acesso ao cookie de qualquer jeito), mas é um endurecimento barato e sem custo de merge.

---

## 6. Backend

### 6.1 Modelo do canal (`Channel::WebWidget`)

**FATO VERIFICADO** — `app/models/channel/web_widget.rb`.

Colunas (do schema annotation, linhas 3-27):

| Coluna | Tipo | Default | Papel |
|---|---|---|---|
| `website_token` | string | gerado | Identificador público (`has_secure_token`, linha 47). Índice único. |
| `hmac_token` | string | gerado | Segredo do identity validation (linha 48). Índice único. |
| `hmac_mandatory` | boolean | `false` | Força validação HMAC |
| `allowed_domains` | text | `""` | CSV de domínios para `frame-ancestors` |
| `continuity_via_email` | boolean | `true` | Continuidade da conversa por e-mail |
| `feature_flags` | integer | `7` | Bitmask (FlagShihTzu) |
| `pre_chat_form_enabled` | boolean | `false` | Liga o pre-chat |
| `pre_chat_form_options` | jsonb | — | Campos do pre-chat |
| `reply_time` | integer | `0` | Enum: `in_a_few_minutes`/`in_a_few_hours`/`in_a_day` (linha 58) |
| `website_url` | string | — | Domínio informado (obrigatório, linha 43) |
| `welcome_title` / `welcome_tagline` | string | — | Cabeçalho expandido |
| `widget_color` | string | `#1f93ff` | Cor do widget (obrigatória, linha 44) |

Feature flags (bitmask, linhas 50-56):

| Bit | Flag | Efeito no widget |
|---:|---|---|
| 1 | `attachments` | Mostra o clipe de anexo |
| 2 | `emoji_picker` | Mostra o seletor de emoji |
| 3 | `end_conversation` | Mostra o botão de encerrar conversa |
| 4 | `use_inbox_avatar_for_bot` | Usa o avatar da inbox para mensagens de bot |
| 5 | `allow_mobile_webview` | Ignora `frame-ancestors` para origens `null`/`file://` |

Default `7` = bits 1+2+3 ligados (anexos, emoji, encerrar conversa).

Pre-chat default (linhas 84-101): três campos `standard` — `emailAddress` (email, required, **enabled: false**), `fullName` (text, enabled: false), `phoneNumber` (text, enabled: false). Ou seja, **por padrão nenhum campo está habilitado**, e `shouldShowPreChatForm` (`configMixin.js:39-45`) exige pelo menos um habilitado. Consequência: ligar só o toggle "Pre-chat form" na tela não faz nada visível.

### 6.2 Controller HTML do iframe

`app/controllers/widgets_controller.rb` herda de `ActionController::Base` (não da `ApplicationController`) — linha 2.

**Linha 1: `# TODO : Delete this and associated spec once 'api/widget/config' end point is merged`.**

Isso revela uma dívida arquitetural real: existem **dois caminhos de configuração**:
1. O ERB, que injeta `window.chatwootWebChannel` no HTML (usado pelo widget web).
2. `POST /api/v1/widget/config` (`app/controllers/api/v1/widget/configs_controller.rb`), que devolve a mesma coisa em JSON.

**FATO VERIFICADO:** `grep -rn "widget/config" app/javascript/` retorna **zero ocorrências**. O endpoint existe, tem spec (`spec/controllers/api/v1/widget/configs_controller_spec.rb`), mas o widget web **não o usa**. **INFERÊNCIA:** ele existe para os SDKs mobile (React Native / Flutter) do Chatwoot.

Implicação prática: **qualquer campo de configuração novo tem que ser adicionado em dois lugares** (`show.html.erb` e `configs/create.json.jbuilder`), ou fica inconsistente entre web e mobile.

### 6.3 Endpoints públicos da API do widget

**FATO VERIFICADO** — `config/routes.rb:593-620`.

| Verbo | Rota | Controller#ação | Autenticação | Observação |
|---|---|---|---|---|
| POST | `/api/v1/widget/direct_uploads` | `DirectUploads#create` | `X-Auth-Token` | Herda de `ActiveStorage::DirectUploadsController` |
| POST | `/api/v1/widget/config` | `Configs#create` | `X-Auth-Token` opcional | **Não usado pelo widget web** |
| GET | `/api/v1/widget/campaigns` | `Campaigns#index` | `website_token` | `skip_before_action :set_contact` — **não exige contato** |
| POST | `/api/v1/widget/events` | `Events#create` | `X-Auth-Token` | Dispara `campaign.triggered` / `webwidget.triggered` |
| GET | `/api/v1/widget/messages` | `Messages#index` | `X-Auth-Token` | Paginação por `before`/`after` |
| POST | `/api/v1/widget/messages` | `Messages#create` | `X-Auth-Token` | Cria conversa se não existir |
| PATCH | `/api/v1/widget/messages/:id` | `Messages#update` | `X-Auth-Token` | Usado por CSAT, form, input_email, input_select |
| GET | `/api/v1/widget/conversations` | `Conversations#index` | `X-Auth-Token` | Devolve **só a última** conversa |
| POST | `/api/v1/widget/conversations` | `Conversations#create` | `X-Auth-Token` | Cria conversa + 1ª mensagem em transação |
| POST | `/api/v1/widget/conversations/destroy_custom_attributes` | `Conversations#destroy_custom_attributes` | `X-Auth-Token` | |
| POST | `/api/v1/widget/conversations/set_custom_attributes` | `Conversations#set_custom_attributes` | `X-Auth-Token` | |
| POST | `/api/v1/widget/conversations/update_last_seen` | `Conversations#update_last_seen` | `X-Auth-Token` | |
| POST | `/api/v1/widget/conversations/toggle_typing` | `Conversations#toggle_typing` | `X-Auth-Token` | |
| POST | `/api/v1/widget/conversations/transcript` | `Conversations#transcript` | `X-Auth-Token` | 402 se plano free; 429 se estourou rate limit de e-mail |
| GET | `/api/v1/widget/conversations/toggle_status` | `Conversations#toggle_status` | `X-Auth-Token` | **GET que muda estado** — resolve a conversa. 403 se `end_conversation` desligada |
| GET | `/api/v1/widget/contact` | `Contacts#show` | `X-Auth-Token` | |
| PATCH | `/api/v1/widget/contact` | `Contacts#update` | `X-Auth-Token` | |
| PATCH | `/api/v1/widget/contact/set_user` | `Contacts#set_user` | `X-Auth-Token` + HMAC | |
| POST | `/api/v1/widget/contact/destroy_custom_attributes` | `Contacts#destroy_custom_attributes` | `X-Auth-Token` | |
| GET | `/api/v1/widget/inbox_members` | `InboxMembers#index` | `website_token` | `skip_before_action :set_contact`. **Expõe nome + avatar + status de todos os agentes da inbox sem autenticação de contato** |
| POST | `/api/v1/widget/labels` | `Labels#create` | `X-Auth-Token` | |
| DELETE | `/api/v1/widget/labels/:id` | `Labels#destroy` | `X-Auth-Token` | |
| POST | `/api/v1/widget/integrations/dyte/add_participant_to_meeting` | `Integrations::Dyte#add_participant_to_meeting` | `X-Auth-Token` | Videochamada |

**Nota de segurança (FATO VERIFICADO):** `GET /api/v1/widget/inbox_members?website_token=X` faz `skip_before_action :set_contact` (`inbox_members_controller.rb:2`) — basta ter o `website_token` (que está no HTML de qualquer site que usa o widget) para listar id, nome e avatar de todos os agentes da inbox. É comportamento upstream, não regressão nossa.

### 6.4 Payloads de resposta

**FATO VERIFICADO** — jbuilders em `app/views/api/v1/widget/`.

`GET /widget/messages` — `messages/index.json.jbuilder`:
```json
{ "payload": [ { "id": 1, "content": "…", "message_type": 0, "content_type": "text",
                 "content_attributes": {}, "created_at": 1786468726,
                 "conversation_id": 42, "attachments": [...], "sender": {...} } ],
  "meta": { "contact_last_seen_at": 1786468000 } }
```

`GET /widget/conversations` — `conversations/index.json.jbuilder`: só `id` (display_id), `inbox_id`, `contact_last_seen_at`, `status`. **Nenhum atributo customizado, nenhum `additional_attributes`.**

`GET /widget/contact` — `contacts/show.json.jbuilder`: `id`, `has_email`, `has_name`, `has_phone_number`, `identifier`. **Deliberadamente não devolve valores, só booleanos** — bom para privacidade.

`GET /widget/campaigns` — `campaigns/index.json.jbuilder`: `id` (display_id), `trigger_rules`, `trigger_only_during_business_hours`, `message`, `sender`.

`GET /widget/inbox_members` — `inbox_members/index.json.jbuilder`: `id`, `name` (available_name), `avatar_url`, `availability_status`.

### 6.5 Onde ficam browser/referer/UTM

**FATO VERIFICADO** — `app/controllers/api/v1/widget/base_controller.rb:31-74`:

```ruby
def conversation_params
  {
    account_id:, inbox_id:, contact_id:, contact_inbox_id:,
    additional_attributes: {
      browser_language: browser.accept_language&.first&.code,
      browser: {
        browser_name:, browser_version:, device_name:, platform_name:, platform_version:
      },
      initiated_at: { timestamp: permitted_params[:message][:timestamp] },
      referer: permitted_params[:message][:referer_url]   # FIXME: typo referrer (linha 32)
    },
    custom_attributes: permitted_params[:custom_attributes].presence || {}
  }
end
```

| Dado | Onde é gravado | Origem |
|---|---|---|
| `browser_language` | `conversation.additional_attributes` | Header `Accept-Language` (gem `browser`) |
| `browser.*` (5 campos) | `conversation.additional_attributes` | User-Agent (gem `browser`) |
| `initiated_at.timestamp` | `conversation.additional_attributes` | `new Date().toString()` do cliente |
| `referer` | `conversation.additional_attributes` | `window.referrerURL`, que é o **href da própria página** (não o `document.referrer`) |
| `created_at_ip` | `contact.additional_attributes` | **Somente se `ip_lookup` estiver habilitada na conta** (`widgets_controller.rb:67-73`) |
| `custom_attributes` (conversa) | `conversation.custom_attributes` | Campos `conversation_attribute` do pre-chat ou `setConversationCustomAttributes` |
| `custom_attributes` (contato) | `contact.custom_attributes` | Campos `contact_attribute` do pre-chat ou `setCustomAttributes` |

**Atenção ao nome `referer`:** ele **não** é o `document.referrer` do navegador (de onde o visitante veio). É a URL da página onde ele estava quando abriu a conversa — vem de `onLocationChangeListener`, que grava `document.location.href` (`DOMHelpers.js:50-59`). Ou seja: **hoje não sabemos de onde o lead veio, apenas onde ele estava.** Isso é central para o gap frente à Leadster.

Para eventos (`POST /widget/events`), o payload adicional é montado em `events_controller.rb:12-18`: `widget_language`, `browser_language`, `browser` (mesmo objeto). E no front, `generateEventParams()` (`app/javascript/widget/api/events.js:4-9`) anexa `initiated_at.timestamp` e `referer: window.referrerURL`.

### 6.6 Campanhas

**FATO VERIFICADO**.

Lado do widget:
1. `initCampaigns` (`store/modules/campaign.js:80-104`) — só busca uma vez por sessão (`uiFlags.hasFetched`), com cache em localStorage de 1 hora (linhas 48-53).
2. `formatCampaigns` extrai `timeOnPage`, `url`, `triggerOnlyDuringBusinessHours` (`campaignHelper.js:20-30`).
3. `filterCampaigns` casa a URL corrente com o padrão usando `URLPattern` (polyfill `urlpattern-polyfill`) e aplica o filtro de horário comercial (`campaignHelper.js:33-47`).
4. `campaignTimer.initTimers` agenda `setTimeout(timeOnPage * 1000)` por campanha (`campaignTimer.js:7-15`).
5. Ao disparar: `startCampaign` **refaz o GET de campanhas** (para checar se foi desabilitada) e, se ainda existe, seta `activeCampaign` (`campaign.js:105-123`). **Só executa se o widget estiver fechado** (linha 115).
6. `App.vue#setCampaignView` (linhas 200-214) exige `!messageCount` — **campanha nunca aparece para quem já trocou mensagem**.
7. Se o visitante clica na campanha: se há pre-chat, vai para o form; senão executa direto (`App.vue:177-194`).
8. `executeCampaign` → **POST `/widget/events`** com `name: 'campaign.triggered'`.

Lado do backend:
- `CampaignListener#campaign_triggered` (`app/listeners/campaign_listener.rb:2-16`) → `Campaigns::CampaignConversationBuilder`.
- O builder trava o `contact_inbox`, **recusa se já existe qualquer conversa** (`app/builders/campaigns/campaign_conversation_builder.rb:13`), cria a conversa com `campaign_id` e o `additional_attributes` vindo do `event_info`, e usa `Messages::MessageBuilder` com o `campaign.sender`.
- Erros são engolidos: `rescue StandardError => e; Rails.logger.info(e.message); nil` (linhas 19-21).

**Limitações estruturais da campanha atual** (FATO VERIFICADO no código acima):
- Gatilhos disponíveis: **apenas URL + tempo na página + horário comercial**. Não há: scroll, exit intent, número de páginas vistas, retorno de visitante, origem de tráfego, dispositivo, primeira visita vs recorrente.
- Uma campanha é **uma mensagem única**, não um fluxo. Não há ramificação, nem captura estruturada.
- **Uma campanha por contato para sempre**: se já existe conversa, nunca mais dispara.
- Snooze global de 1 hora via cookie (`cw_snooze_campaigns_till`), não por campanha.

### 6.7 Autenticação e tokens

**FATO VERIFICADO**.

| Token | Geração | Validade | Onde vive |
|---|---|---|---|
| `website_token` | `has_secure_token` (`web_widget.rb:47`) | Permanente | Público, no snippet do site |
| `hmac_token` | `has_secure_token` (`web_widget.rb:48`) | Permanente | Secreto, no servidor do cliente |
| Auth JWT | `Widget::TokenService#generate_token` | **180 dias** (configurável em `WIDGET_TOKEN_EXPIRY`, `config/installation_config.yml:497-501`) | Cookie `cw_conversation` no domínio do cliente + header `X-Auth-Token` |
| `pubsub_token` | `ContactInbox` | Permanente | `window.chatwootPubsubToken`, usado no ActionCable |
| `source_id` | `SecureRandom.uuid` para `Channel::WebWidget` (`app/builders/contact_inbox_builder.rb:56-58`) | Permanente | Dentro do JWT |

Payload do JWT: `{ source_id, inbox_id, exp, iat }` (`app/helpers/widget_helper.rb:4-5`, `app/services/widget/token_service.rb:8-13`). Assinado com `Rails.application.secret_key_base`, HS256 (`app/services/base_token_service.rb:20-30`).

**Nota:** decode falho (expirado/inválido) devolve `{}` silenciosamente (`base_token_service.rb:9-13`). No `WidgetsController#build_contact`, isso resulta em um **contato novo** — a conversa antiga fica órfã do ponto de vista do visitante.

---

## 7. Persistência no navegador

**FATO VERIFICADO**.

### Cookies (domínio do cliente)

| Cookie | Valor | Expiração | Flags | Onde |
|---|---|---|---|---|
| `cw_conversation` | JWT de autenticação | **365 dias** (default de `setCookieWithDomain`) | `sameSite: Lax`, `domain: baseDomain` se configurado. **Sem `secure`** | `IFrameHelper.js:40-43`, `cookieHelpers.js:26-45` |
| `cw_user_<websiteToken>` | MD5 do payload de `setUser` | 365 dias | idem | `sdk.js:134-136`, `cookieHelpers.js:7-21` |
| `cw_snooze_campaigns_till` | timestamp (ms) | **1 hora** | idem | `IFrameHelper.js:45-51` |

Detalhe: o JWT tem validade de 180 dias, mas o **cookie** tem 365. Ou seja, existe uma janela de ~185 dias em que o cookie ainda está lá mas o token já expirou — e o resultado é a criação silenciosa de um contato novo.

Ausência de `secure: true` (`cookieHelpers.js:31-35`): em site servido por HTTPS o cookie ainda vai só por HTTPS na prática pelo `SameSite=Lax` + contexto, mas o flag explícito não está lá. **INFERÊNCIA:** provavelmente para não quebrar instalações HTTP locais.

### localStorage (dentro do iframe, origem `chatspx.app`)

| Chave | Conteúdo | TTL | Onde |
|---|---|---|---|
| `chatwoot_campaigns_<websiteToken>` | Lista de campanhas | 1 hora | `store/modules/campaign.js:9,48-53,67` |
| `chatwoot_most_read_articles_<slug>_<locale>` | Artigos populares | 24 horas (default) | `store/modules/articles.js:4,27,36` + `shared/helpers/cache.js:4` |

Como o localStorage é da origem do ChatSPX, ele é **compartilhado entre todos os sites que usam o mesmo servidor** — o que é exatamente o que se quer (cache global de campanhas por token).

---

## 8. Realtime (ActionCable)

**FATO VERIFICADO** — `app/javascript/widget/helpers/actionCable.js` + `app/javascript/shared/helpers/BaseActionCableConnector.js`.

Eventos assinados (`actionCable.js:21-31`):

| Evento | Handler | Efeito |
|---|---|---|
| `message.created` | `onMessageCreated` | Adiciona a mensagem, emite `ON_AGENT_MESSAGE_RECEIVED`, dispara `chatwoot:on-message` no host, toca som se `sender_type === 'User'` |
| `message.updated` | `onMessageUpdated` | Atualiza; só dispara `chatwoot:on-message` se `submitted_values` mudou |
| `conversation.typing_on` / `typing_off` | `onTypingOn/Off` | Bolha de "digitando", com timeout automático de 30 s |
| `conversation.status_changed` | `onStatusChange` | Atualiza status; reseta campanha se resolvida |
| `conversation.created` | `onConversationCreated` | Recarrega atributos da conversa |
| `presence.update` | `onPresenceUpdate` | Atualiza lista de agentes online |
| `contact.merged` | `onContactMerge` | Reconecta com o novo `pubsub_token` |

Intervalo de presença no widget: **60 s** (`actionCable.js:16`), contra 20 s do dashboard (`BaseActionCableConnector.js:4`).

Autenticação do canal: `RoomChannel#current_user` (`app/channels/room_channel.rb:46-54`) — se `params[:user_id]` está em branco, busca `ContactInbox.find_by!(pubsub_token:)` e usa o contato. É por isso que o widget não precisa de user_id.

**Observação:** `BaseActionCableConnector` acessa `app.$store.getters.getCurrentAccountId` e `getCurrentUserID` (linhas 39-40). **FATO VERIFICADO:** esses getters **não existem** no store do widget (`grep` em `app/javascript/widget/` retorna zero). Resultado: `account_id` e `user_id` chegam `undefined` na subscrição. Funciona porque `RoomChannel` trata `params[:user_id].blank?`. É comportamento upstream, mas é frágil — qualquer mudança no `RoomChannel` que passe a exigir `account_id` derruba o widget silenciosamente.

Reconexão (customização ChatSPX, ver §14): watchdog de 15 s que detecta stream silencioso (>25 s sem evento) e refaz o fetch da rota; reconexão imediata em `visibilitychange`, `focus` e `pageshow` (bfcache). No widget, o gap-fill via `window.reconnectService` é no-op (o comentário na linha 96 diz isso explicitamente) — quem cobre é `onReconnect → syncLatestMessages` (`actionCable.js:37-47`), que busca mensagens `after: lastMessageId`.

---

## 9. Inventário de features do widget

**FATO VERIFICADO** para todas as linhas. Legenda: ✅ existe e é completo · 🟡 parcial · ❌ não existe.

| Feature | Estado | Evidência | Observação crítica |
|---|:---:|---|---|
| **Pre-chat form** | ✅ | `widget/components/PreChat/Form.vue`, `views/PreChatForm.vue` | FormKit; campos `standard` + `contact_attribute` + `conversation_attribute`; validação por regex por campo; input de telefone com DDI. **Por padrão nenhum campo vem habilitado.** |
| — campos condicionais / lógica | ❌ | — | Não há "mostre X se Y". A única filtragem é esconder campos já conhecidos do contato (`Form.vue:83-105`). |
| — múltiplas etapas | ❌ | — | Formulário de uma tela só. |
| **Campanhas / mensagens proativas** | 🟡 | `store/modules/campaign.js`, `helpers/campaignHelper.js` | Só URL + tempo na página + horário comercial. Uma mensagem, sem fluxo. Nunca reaparece para quem já conversou. Ver §6.6. |
| **Artigos do Help Center** | ✅ | `components/pageComponents/Home/Article/*`, `store/modules/articles.js` | 6 artigos mais lidos na Home; abre em `IframeLoader` dentro do próprio widget. Cache de 24 h. |
| — busca de artigos | ❌ | — | Não há campo de busca no widget. Só a lista dos 6 mais vistos e "ver todos". |
| **CSAT** | ✅ | `shared/components/CustomerSatisfaction.vue` | Emoji ou estrelas (`display_type`), com campo de feedback. Enviado via `PATCH /widget/messages/:id`. |
| **NPS** | 🟡 | aba `nps` em `Settings.vue:1254-1256` | Existe configuração de inbox, mas **não achei renderização de NPS dentro do widget** — **NÃO VERIFICADO** se é entregue por outro canal. |
| **Upload de arquivo** | ✅ | `components/ChatAttachment.vue` | Direct upload (ActiveStorage) ou indireto. Colar do clipboard funciona (linhas 51-65). Limite vem de `MAXIMUM_FILE_UPLOAD_SIZE`. |
| **Áudio (gravação de voz)** | ❌ | — | O composer não tem gravador. `iframe.allow` até inclui `microphone`, mas nada usa. |
| **Emoji picker** | ✅ | `shared/components/emoji/EmojiInput.vue`, `ChatInputWrap.vue:171-176` | Feature flag por inbox + override do SDK. |
| **Respostas rápidas / botões** | 🟡 | `AgentMessageBubble.vue:116-123` (`input_select`), `:131-140` (`cards`) | Só a partir de mensagens **do agente/bot** com `content_type` específico. O visitante não tem sugestões proativas. |
| **Formulário dentro da conversa** | ✅ | `shared/components/ChatForm.vue` via `content_type: 'form'` | |
| **Coleta de e-mail no meio da conversa** | ✅ | `components/template/EmailInput.vue` (`content_type: 'input_email'`) | Toggle "Enable email collect box" na inbox. |
| **Indicador de digitando (agente)** | ✅ | `AgentTypingBubble.vue`, `actionCable.js:105-127` | Timeout de 30 s. |
| **Indicador de digitando (visitante → agente)** | ✅ | `POST /widget/conversations/toggle_typing` | |
| **Contador de não lidas** | ✅ | `store/modules/conversation/getters.js:40-50` | Ponto vermelho na bolha + painel de preview (máx. 3 mensagens, `getters.js:58`). |
| **Preview de não lidas fora do painel** | ✅ | `views/UnreadMessages.vue`, `IFrameHelper.js:268-271` | Controlado por `showUnreadMessagesDialog`. |
| **Som de notificação** | ✅ | `WidgetAudioNotificationHelper.js`, `AudioNotificationHelper.js` | `/audio/widget/ding.mp3`, inicializado na 1ª interação (política de autoplay). |
| **Continuidade por e-mail** | ✅ | coluna `continuity_via_email`, toggle em `Settings.vue:1177-1188` | |
| **Transcrição por e-mail** | ✅ | `POST /widget/conversations/transcript` | 402 em plano free, rate limit por conta. |
| **Encerrar conversa pelo visitante** | ✅ | `GET /widget/conversations/toggle_status`, `HeaderActions.vue` | Feature flag `end_conversation`. |
| **Retomar / nova conversa** | 🟡 | `ChatFooter.vue:82-89, 133-151` | Só aparece quando a conversa está resolvida **e** `allow_messages_after_resolved` está desligado. |
| **Múltiplas conversas simultâneas** | ❌ | `base_controller.rb:19-21` (`conversations.last`) | O widget só conhece a **última** conversa. Não há lista/inbox do visitante. |
| **Responder mensagem específica (reply-to)** | ✅ | `FooterReplyTo.vue`, `ReplyToChip.vue`, `MessageReplyButton.vue` | |
| **Dark mode** | ✅ | `composables/useDarkMode.js` | `light` / `dark` / `auto` (segue `prefers-color-scheme`). |
| **Tradução / i18n** | ✅ | 51 locales; **pt-BR 85/85 chaves** (**MEDIDO**) | Locale vem da conta, do `chatwootSettings`, do `?locale=` ou do navegador. |
| **RTL** | ✅ | `App.vue:64-68, 74-79` | Define `document.documentElement.dir`. |
| **Cor customizada** | 🟡 | `widget_color` na inbox | **Regressão ChatSPX**: header, botão de enviar e link do pre-chat ficaram travados em `#2dc46f`. Ver §13.2 item 3. |
| **Posição (esquerda/direita)** | ✅ | `chatwootSettings.position` + config da inbox | |
| **Avatar customizado** | ✅ | avatar da inbox (`show.html.erb:9`) | Upload na tela de settings. |
| **Bolha customizada** | 🟡 | `type: 'expanded_bubble'` + `launcherTitle` | Só duas formas (círculo / pílula). Ícone é um SVG **hardcoded** (`bubbleHelpers.js:10-11`) — não é trocável sem patch. |
| **Launcher próprio do cliente** | ✅ | `hideMessageBubble` + `window.$chatwoot.toggle()` | |
| **Tela cheia no mobile** | ✅ | `sdk.js:242-279` | `< 667px` → 100% da viewport; a bolha some quando aberto. |
| **Modo popout (janela separada)** | ✅ | `helpers/popoutHelper.js`, `showPopoutButton` | 400×600. |
| **WebView mobile (app nativo)** | ✅ | flag `allow_mobile_webview`, `widgets_controller.rb:91-96` | |
| **Videochamada** | 🟡 | `components/template/IntegrationCard.vue`, `integrations/dyte_controller.rb` | Só Dyte, iniciada pelo agente. |
| **Anexo com preview de imagem/vídeo** | ✅ | `ImageBubble.vue`, `VideoBubble.vue`, `FileBubble.vue` | |
| **Arrastar-e-soltar arquivo** | ✅ | `components/DragWrapper.vue` | |
| **Histórico paginado (scroll infinito)** | ✅ | `ConversationWrap.vue:83-96` | Carrega ao chegar a `scrollTop < 100`. |
| **Restauração pós-navegação SPA (Turbo/Astro)** | ✅ | `sdk.js:27-48`, `DOMHelpers.js:15-28` | |
| **Persistência entre subdomínios** | ✅ | `chatwootSettings.baseDomain` | |
| **Identity validation (HMAC)** | ✅ | ver §4.6 | |
| **Atributos customizados (contato + conversa)** | ✅ | 4 métodos no SDK | |
| **Labels via SDK** | ✅ | `setLabel` / `removeLabel` | Backend só aceita labels já existentes na conta. |
| **Restrição de domínio** | ✅ | `allowed_domains` → `frame-ancestors` | |
| **Restrição geográfica** | ✅ (enterprise) | `enterprise/.../widgets_controller.rb:4-13` | Requer `ip_lookup`. |
| **Branding "Powered by"** | ✅ | `shared/components/Branding.vue` | Removível por feature de conta `disable_branding`. |
| **Acessibilidade (a11y)** | ❌ | 2 `aria-label` em todo o widget | Ver §13.2 item 8. |
| **Captura de UTM / origem de mídia** | ❌ | — | Ver §11. |
| **Integração com `dataLayer` / GA4 / Meta Pixel** | ❌ | — | Ver §11. |
| **Fluxo conversacional / qualificação no widget** | ❌ | — | Existe motor Flows no produto, mas não é acionável pelo widget web. |
| **Agendamento / calendário no widget** | ❌ | — | |
| **Reporte de erro do widget para observabilidade** | ❌ | ~20 `catch { // Ignore error }` | O widget não envia nada para o GlitchTip. |

---

## 10. Configuração no dashboard

### 10.1 Abas da inbox Website

**FATO VERIFICADO** — `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue:143-210`.

| Aba | Chave | Componente |
|---|---|---|
| Configurações | `inbox-settings` | inline em `Settings.vue:683-1233` |
| Colaboradores | `collaborators` | `settingsPage/CollaboratorsPage.vue` |
| Horário comercial | `business-hours` | `components/WeeklyAvailability.vue` |
| CSAT | `csat` | `settingsPage/CustomerSatisfactionPage.vue` |
| NPS | `nps` | `settingsPage/NetPromoterScorePage.vue` |
| Pre-chat form | `pre-chat-form` | `PreChatForm/Settings.vue` |
| Configuração | `configuration` | `settingsPage/ConfigurationPage.vue` |
| Bot | `bot-configuration` | `components/BotConfiguration.vue` (se feature `agent_bots`) |

### 10.2 Campos configuráveis sem código

**FATO VERIFICADO**.

**Aba "Configurações" — bloco geral:**

| Campo | Linha | Persiste em |
|---|---:|---|
| Avatar da inbox | 698-707 | `inbox.avatar` |
| Nome da inbox | 709-722 | `inbox.name` |
| Domínio do site | 749-762 | `channel.website_url` |
| Central de Ajuda (portal) | 776-789 | `inbox.portal_id` |
| Lock to single conversation | 791-804 | `inbox.lock_to_single_conversation` |
| Isolamento de mensagem por time / agente | 806-835 | `inbox.*` |
| Status "Pendente" | 837-844 | `inbox.*` |
| Nome do remetente (perfil/negócio) | 846-899 | `inbox.sender_name_type`, `business_name` |

**Aba "Configurações" — acordeão "Recursos do widget"** (`Settings.vue:901-1114`):

| Campo | Linha | Persiste em |
|---|---:|---|
| Título de boas-vindas | 906-922 | `channel.welcome_title` |
| Subtítulo (editor rich text, 255 chars) | 924-942 | `channel.welcome_tagline` |
| Cor do widget (color picker) | 944-950 | `channel.widget_color` |
| Posição da bolha (left/right) | 956-983 | localStorage do builder |
| Tipo da bolha (standard/expanded) | 985-1011 | localStorage do builder |
| Título do launcher | 1015-1031 | localStorage do builder |
| Tempo de resposta esperado | 1032-1061 | `channel.reply_time` |
| Feature: anexos | 1068-1078 | bit 1 de `feature_flags` |
| Feature: emoji picker | 1079-1089 | bit 2 |
| Feature: encerrar conversa | 1090-1100 | bit 3 |
| Feature: usar avatar da inbox para bot | 1101-1111 | bit 4 |

**Ponto de atenção (FATO VERIFICADO):** posição, tipo e título do launcher são salvos em `localStorage` com a chave `widgetBubble_<inboxId>` (`Settings.vue:351`, `dashboard/constants/localStorage.js:3`) e **só servem para gerar o snippet de instalação na prévia**. Não são persistidos no servidor. Se o cliente instalou o snippet e depois muda a posição na tela, **nada acontece no site dele** até ele copiar o snippet de novo. Isso é uma armadilha de UX real.

**Acordeão "Preferências do canal"** (`Settings.vue:1116-1189`):

| Campo | Linha |
|---|---:|
| Mensagem de saudação (com editor) | 1120-1149 |
| Caixa de coleta de e-mail | 1151-1162 |
| Permitir mensagens após resolvida | 1164-1175 |
| Continuidade via e-mail | 1177-1188 |

**Aba "Configuração"** (`settingsPage/ConfigurationPage.vue:290+`):

| Campo | Linha |
|---|---:|
| Domínios permitidos (`frame-ancestors`) | 301 (`allowedDomains`) |
| Permitir WebView mobile | 76-82 do template |
| Token HMAC (somente leitura) | 342, 384 |
| Validação de identidade obrigatória | 360, 392 |
| Script de instalação | via `inbox.web_widget_script` |

### 10.3 O que exige fork/patch

**FATO VERIFICADO** — nenhum destes é configurável pela UI:

| Item | Onde está travado |
|---|---|
| Ícone da bolha | SVG hardcoded em `bubbleHelpers.js:10-11` |
| Tamanho da bolha (64×64 / 56×56 flat) | `sdk.js:47-48, 66-67` |
| Tamanho do painel (400×640, min 250) | `sdk.js:281-290` |
| Breakpoint mobile (667px) | `sdk.js:147, 242, 281` e `IFrameHelper.js:343` (668px — **inconsistente com o CSS**) |
| Offsets da bolha (20px bottom/left/right) | `sdk.js:45, 124, 128` |
| `z-index` (2147483000) | `sdk.js:15, 53` |
| Cor do ponto de não lida (`#ff4040`) | `sdk.js:85` |
| Título acessível da bolha (`'Open chat window'`, em inglês) | `bubbleHelpers.js:60` |
| Fonte do widget | `shared/assets/fonts/widget_fonts` via `woot.scss:5` |
| Imagem de fundo da conversa | `ConversationWrap.vue` (customização ChatSPX) |
| Textos padrão do widget fora dos 3 campos de boas-vindas | arquivos de locale |
| Número de artigos exibidos (6) | `endPoints.js:106` |
| Número de mensagens no preview de não lidas (3) | `getters.js:58` |
| Timeout do "digitando" (30 s) | `actionCable.js:138` |
| Intervalo de presença (60 s) | `actionCable.js:16` |
| TTL do cache de campanhas (1 h) / artigos (24 h) | `campaign.js:49` / `cache.js:4` |
| Snooze de campanha (1 h) | `IFrameHelper.js:46` |
| Permissões do iframe (`allow`) | `IFrameHelper.js:70-71` |
| Expiração do cookie (365 dias) | `cookieHelpers.js:29` |

---

## 11. Tracking e atribuição hoje

**FATO VERIFICADO** — busca exaustiva por `utm_`, `gclid`, `fbclid`, `dataLayer`, `gtag(` em `app/javascript/sdk`, `app/javascript/widget`, `app/controllers/api/v1/widget` e `app/models/channel/web_widget.rb`: **zero ocorrências**.

A única ocorrência de UTM no widget inteiro é **de saída**, no link de branding: `shared/components/Branding.vue:33-49` monta `utm_source={referrerHost}&utm_medium=widget&utm_campaign=branding` no link "Powered by". Ou seja, o widget adiciona UTM ao **nosso próprio link**, mas não captura nada da página do visitante.

### O que o widget sabe hoje sobre a origem

| Dado | Capturado? | Onde vai parar |
|---|:---:|---|
| URL da página onde a conversa começou | ✅ | `conversation.additional_attributes.referer` |
| Host da página | ✅ | Vuex `appConfig.referrerHost` (usado só para o link de branding) |
| `document.referrer` (de onde o visitante veio) | ❌ | — |
| `utm_source` / `utm_medium` / `utm_campaign` / `utm_term` / `utm_content` | ❌ | — |
| `gclid` (Google Ads) | ❌ | — |
| `fbclid` (Meta Ads) | ❌ | — |
| `msclkid`, `ttclid` e afins | ❌ | — |
| Landing page da sessão (primeira página vista) | ❌ | — |
| Número de páginas vistas antes de abrir o chat | ❌ | Ele **observa** troca de URL (`change-url`), mas só usa para campanhas — não acumula histórico |
| Tempo total no site | ❌ | Só `timeOnPage` por campanha, e apenas como gatilho |
| Dispositivo / navegador / SO | ✅ | `conversation.additional_attributes.browser` |
| Idioma do navegador | ✅ | `conversation.additional_attributes.browser_language` |
| IP | 🟡 | Só `contact.additional_attributes.created_at_ip`, e **só se a feature `ip_lookup` estiver ligada na conta** |
| Geolocalização | 🟡 | Só como gate de bloqueio (enterprise), não persistida na conversa |

### O que o widget dispara para fora

| Destino | Existe? | Detalhe |
|---|:---:|---|
| `window.dataLayer` (GTM) | ❌ | Não há nenhuma referência |
| `gtag()` / GA4 | ❌ | — |
| Meta Pixel (`fbq`) | ❌ | — |
| Eventos `CustomEvent` na `window` | ✅ | 7 eventos (§4.5) — o cliente pode fazer a ponte manualmente |
| Webhooks de servidor | ✅ | `webwidget.triggered` e `campaign.triggered` via `WebhookListener` (`app/listeners/webhook_listener.rb:65-73`) e `AgentBotListener` (`app/listeners/agent_bot_listener.rb:36-43`) |

**Conclusão de tracking:** o cliente que quiser medir "quantos leads o chat gerou por campanha do Google Ads" precisa, hoje, escrever JavaScript próprio: escutar `chatwoot:on-start-conversation`, ler os UTMs da URL ele mesmo, e chamar `window.$chatwoot.setCustomAttributes({...})`. **Nada disso é automático nem documentado na UI.** Esse é o buraco mais visível frente a concorrentes posicionados como ferramenta de geração de leads.

---

## 12. Build e peso

**MEDIDO** — comandos no Anexo B. Artefatos de `public/vite` e `public/packs` no estado atual do repositório.

### SDK

| Artefato | Cru | Gzip |
|---|---:|---:|
| `public/packs/js/sdk.js` (IIFE, servido ao cliente) | **28.834 B** | **9.491 B** |

Construído por `pnpm run build:sdk` = `BUILD_MODE=library vite build` (`package.json:15`), com `formats: ['iife']` e `inlineDynamicImports: true` (`vite.config.ts:86-93`). Amarrado ao `assets:precompile` via `lib/tasks/build.rake:3-13`.

Orçamento declarado: **40 KB** (`package.json` → `size-limit`). Folga confortável.

### Widget (SPA no iframe)

Grafo de import a partir de `entrypoints/widget.js`, segundo `public/vite/.vite/manifest.json`:

| Chunk | Cru | Gzip | Comentário |
|---|---:|---:|---|
| `widget-D0AtGYyS.js` (entry) | 61.841 | 19.071 | O código do widget em si |
| **`widget-EcEcykJV.css`** | **1.103.132** | **106.127** | ⚠ Tailwind de **todo o app** |
| `useBranding-Cod3jKwR.js` | 287.030 | 85.022 | |
| `index-DqTgoDi8.js` | 350.867 | 104.774 | |
| `_plugin-vue_export-helper-C2NFN58P.js` | 223.922 | 84.950 | |
| `Validators-B8yFtBg4.js` | 164.809 | 53.436 | libphonenumber (input de telefone) |
| **`leaflet-58r2EQLt.js`** | **150.679** | **43.491** | ⚠ mapa que o widget nunca usa |
| `vue-dompurify-html-BsNF8atS.js` | 131.392 | 56.255 | |
| `utils.esm-aAeXemek.js` | 83.343 | 25.747 | |
| `module-D6sSz6Gr.js` | 11.647 | 5.171 | |
| `Icon-Bl9l3BEz.js` | 6.025 | 2.160 | |
| `Branding-CV74U7Vy.js` | 1.635 | 923 | |
| `useBranding-C1LIcEF9.css` | 1.422 | 494 | |
| `index-DN3rM4CW.js` | 886 | 529 | |
| `sharedFrameEvents-0qZ2yOho.js` | 1.079 | 627 | |
| `constants-lVAyZKq6.js` | 157 | 166 | |
| **TOTAL do caminho crítico** | **2.579.866** (~2,46 MB) | **588.943** (~575 KB) | |

Mais 6 chunks lazy (as views): `Home`, `Messages`, `PreChatForm`, `Campaigns`, `UnreadMessages`, `ArticleViewer`.

### Por que o CSS tem 1,1 MB

**FATO VERIFICADO:**
- `app/javascript/widget/assets/scss/woot.scss:2-4` importa `tailwindcss/base`, `components` e `utilities` inteiros.
- `tailwind.config.js:24-37` define `content` incluindo `./app/javascript/dashboard/**/*.vue`, `./app/javascript/dashboard/components-next/**/*.{vue,js}`, `./app/javascript/portal/**/*.vue`, `./app/views/**/*.html.erb` etc.

Como o Tailwind gera **um único conjunto de utilitários a partir de todos os globs**, e o widget importa esse conjunto inteiro, **todas as classes usadas em qualquer lugar do produto acabam no CSS do widget**. O widget usa uma fração ínfima disso.

Isso é upstream (o Chatwoot tem o mesmo problema), mas o ChatSPX **piorou** ao adicionar mais globs e mais tokens de tema (`wa-composer`, `wa`, etc. — `tailwind.config.js:40-63`).

### Por que o Leaflet está no grafo

**FATO VERIFICADO:** `vite.config.ts:80-84` define `manualChunks: { leaflet: ['leaflet'] }`. Ao forçar o Leaflet num chunk nomeado, o Rollup acabou colocando nesse mesmo chunk os **helpers de interop CommonJS** (`getDefaultExportFromCjs`, `getAugmentedNamespace` — visíveis no fim do arquivo: `export{Yo as a,qo as c,jo as g,Xo as l}`). Como `vue-dompurify-html` e `Validators` usam esses helpers, eles passaram a **importar o chunk do Leaflet**, arrastando 150 KB de biblioteca de mapas para dentro do widget.

Confirmação no manifest: `entrypoints/widget.js` lista `_leaflet-58r2EQLt.js` diretamente entre seus `imports`, e `_vue-dompurify-html-BsNF8atS.js` também.

**INFERÊNCIA:** o `manualChunks` foi introduzido para enxugar o bundle do dashboard (o comentário em `vite.config.ts:78-79` diz exatamente isso), sem perceber o efeito colateral no widget.

### Orçamento de bundle

`package.json` → `size-limit`:

```json
[ { "path": "public/vite/assets/widget-*.js", "limit": "300 KB" },
  { "path": "public/packs/js/sdk.js",        "limit": "40 KB" } ]
```

**Problema (FATO VERIFICADO):** o glob `widget-*.js` casa apenas com o **entry de 62 KB**. Nem o CSS de 1,1 MB, nem os ~1,3 MB de chunks compartilhados entram na conta. O orçamento está verde enquanto o widget real pesa 20× mais.

---

## 13. Limitações, dívidas técnicas e pontos frágeis

### 13.1 Lista priorizada

| # | Item | Severidade | Esforço | Arquivo:linha |
|---:|---|---|---|---|
| 1 | CSS do widget com 1,10 MB / 106 KB gz (Tailwind do app inteiro) | 🔴 Alta | Médio | `widget/assets/scss/woot.scss:2-4` + `tailwind.config.js:24-37` |
| 2 | Chunk do Leaflet (150 KB / 43 KB gz) no grafo crítico do widget | 🔴 Alta | Baixo | `vite.config.ts:80-84` |
| 3 | `widget_color` por inbox quebrado pela customização ChatSPX | 🔴 Alta | Baixo | `ChatHeader.vue:28,35,48,53,58`; `ChatSendButton.vue:27,29`; `ChatHeaderExpanded.vue:34,50,54`; `HeaderActions.vue:94,101,110` |
| 4 | Classes Tailwind inexistentes: `bg-n-chat-bg`, `shadow-focus` (zero CSS gerado) | 🟠 Média | Baixo | `Messages.vue:22`; `ChatInputWrap.vue:131` |
| 5 | Zero captura de origem (UTM/gclid/fbclid/referrer) | 🔴 Alta (produto) | Médio | ausente por todo o SDK |
| 6 | Acessibilidade: 2 `aria-label` no widget inteiro; bolha sem rótulo traduzido; sem `aria-live` | 🔴 Alta | Médio | `bubbleHelpers.js:60`; `ConversationWrap.vue` |
| 7 | `window.onmessage = …` destrói handler do site do cliente | 🟠 Média | Baixo | `IFrameHelper.js:105` |
| 8 | Sem verificação de `event.origin` nos dois lados | 🟠 Média (segurança) | Baixo | `IFrameHelper.js:105-116`; `widget/helpers/utils.js:18-22` |
| 9 | Widget → parent com `targetOrigin: '*'` | 🟠 Média (segurança) | Baixo | `widget/helpers/utils.js:9-12` |
| 10 | `MutationObserver` na `<body>` inteira com `subtree: true` | 🟠 Média (perf no cliente) | Baixo | `DOMHelpers.js:61-74` |
| 11 | `size-limit` só vigia o entry JS | 🟠 Média | Baixo | `package.json` (`size-limit`) |
| 12 | Contato criado no page-load, antes de qualquer interação | 🟠 Média (dados) | Alto | `widgets_controller.rb:54-59` |
| 13 | `emitter.$emit` — mitt não tem esse método (bug real) | 🟠 Média | Trivial | `ChatFooter.vue:102` |
| 14 | Erros engolidos em ~20 lugares, sem telemetria | 🟠 Média | Médio | `store/modules/**` |
| 15 | `campaignTimer.clearTimers` grava no índice errado | 🟡 Baixa | Trivial | `campaignTimer.js:17-22` |
| 16 | Estado do Vuex mutado fora de mutation | 🟡 Baixa | Baixo | `conversation/actions.js:124-127` |
| 17 | Dois caminhos de config (ERB + `/widget/config`) que precisam ser mantidos em par | 🟠 Média | Médio | `widgets_controller.rb:1`; `configs/create.json.jbuilder` |
| 18 | Breakpoint mobile divergente: 667px no CSS vs 668px no JS | 🟡 Baixa | Trivial | `sdk.js:242,281` vs `IFrameHelper.js:343` |
| 19 | `notificationBubble` criado e nunca usado | 🟡 Baixa | Trivial | `bubbleHelpers.js:19` |
| 20 | Handler `postback` órfão (nada emite) | 🟡 Baixa | Trivial | `IFrameHelper.js:221-226` |
| 21 | Cookie 365 dias vs JWT 180 dias → contato duplicado silencioso | 🟠 Média (dados) | Baixo | `cookieHelpers.js:29` vs `token_service.rb:2` |
| 22 | `GET /widget/conversations/toggle_status` muda estado via GET | 🟡 Baixa | Baixo | `routes.rb:600`, `conversations_controller.rb:57-65` |
| 23 | `inbox_members` exposto só com `website_token` | 🟡 Baixa | Médio | `inbox_members_controller.rb:2` |
| 24 | Posição/tipo da bolha salvos só em localStorage do dashboard | 🟠 Média (UX) | Médio | `Settings.vue:351` |
| 25 | `getCurrentAccountId`/`getCurrentUserID` inexistentes no store do widget | 🟡 Baixa | Baixo | `BaseActionCableConnector.js:39-40` |
| 26 | Sem `sandbox` no iframe; `allow` inclui `camera`/`microphone`/`display-capture` sem uso | 🟡 Baixa | Baixo | `IFrameHelper.js:70-71` |
| 27 | `/packs/js/sdk.js` sem fingerprint nem SRI | 🟡 Baixa | Médio | `vite.config.ts:63-69` |

### 13.2 Detalhamento por item

**#3 — `widget_color` quebrado (o mais grave para um SaaS multi-cliente)**

Comparando com o upstream v4.12.1:

```diff
- <header class="flex justify-between w-full p-5 bg-n-background gap-2">
+ <header class="flex justify-between w-full p-5 bg-n-brand gap-2">
```
(`app/javascript/widget/components/ChatHeader.vue:28`)

```diff
-  <FluentIcon v-if="!loading" icon="send" :style="`color: ${color}`" />
+  <FluentIcon v-if="!loading" icon="send" class="text-white" />
```
(`app/javascript/widget/components/ChatSendButton.vue:29`; a prop `color` foi **removida** nas linhas 19-22 do upstream)

E `theme/colors.js:227`:
```js
brand: '#2dc46f',
```

**FATO VERIFICADO** no CSS gerado:
```
.bg-n-brand{--tw-bg-opacity: 1;background-color:#2dc46f}
```

Ou seja: `n-brand` é uma **cor literal**, não uma CSS custom property. O `--widget-color` que `App.vue:118-125` grava no `documentElement` a partir do `widget_color` da inbox **não é mais consumido** pelo header nem pelo botão de enviar. O `ColorPicker` da tela de settings (`Settings.vue:948`) continua lá, salvando no banco, mas o efeito visual sumiu do topo do widget e do botão principal.

Onde `widget_color` **ainda** funciona: a bolha (aplicada inline em `IFrameHelper.js:334-335`), o botão de "iniciar conversa" (`TeamAvailability.vue:37`), o botão de nova conversa (`ChatFooter.vue:137`) e o CSAT (`CustomerSatisfaction.vue:43,55`).

Resultado: **widget com bolha da cor do cliente e header verde ChatSPX.** Para um SaaS white-label isso é um bug de produto, não de estilo.

**#4 — Classes Tailwind mortas**

```bash
$ grep -c "bg-n-chat-bg" public/vite/assets/widget-EcEcykJV.css
0
$ grep -c "shadow-focus" public/vite/assets/widget-EcEcykJV.css
0
$ grep -rn "chat-bg" theme/ tailwind.config.js
(nada)
```

- `app/javascript/widget/views/Messages.vue:22` — `bg-n-chat-bg` não existe. No modo claro, o container de mensagens fica sem background próprio (herda do pai); no escuro o `dark:bg-n-solid-1` cobre.
- `app/javascript/widget/components/ChatInputWrap.vue:131` — `shadow-focus` não existe. O input focado ganha apenas `border-n-brand`, sem o halo que o design pedia.

Ambas foram introduzidas no commit `4284a31898 feat(ui): WhatsApp design system + Lucide icon migration`.

**#6 — Acessibilidade**

Busca exaustiva (**MEDIDO**): `grep -rn "aria-" app/javascript/widget app/javascript/sdk --include=*.vue --include=*.js | grep -vc spec` → **2**.

As duas estão em `ChatInputWrap.vue:142` (`aria-label` no textarea) e `:159` (`aria-label` no botão de emoji). Fora isso:

- A bolha é um `<button>` sem `type`, sem `aria-label`, com `title = 'Open chat window'` **hardcoded em inglês** (`bubbleHelpers.js:60`) — o único texto do widget que não passa pelo i18n.
- `bubbleHolder.addEventListener('click', ...)` é registrado no **wrapper `<div>`** (`bubbleHelpers.js:101`), não nos botões — funciona por bubbling, mas navegação por teclado depende do foco cair num dos `<button>` filhos.
- A lista de mensagens (`ConversationWrap.vue`) não tem `role="log"` nem `aria-live="polite"` — **leitores de tela não anunciam mensagens novas**.
- Não há focus trap no iframe: com Tab, o usuário sai do widget para a página do cliente sem perceber.
- ESC só fecha se o foco estiver dentro do container do `ViewWithHeader` (`ViewWithHeader.vue:108`); ESC estando na bolha não faz nada.
- `ArticleListItem.vue:22` usa `role="button"` num elemento não focável.
- A única coisa boa: `chatBubble.focus()` ao fechar (`bubbleHelpers.js:81`), que devolve o foco corretamente.

**#7 / #8 / #9 — postMessage**

```js
// app/javascript/sdk/IFrameHelper.js:105
window.onmessage = e => { ... }          // sobrescreve o do cliente, sem check de origin
```
```js
// app/javascript/widget/helpers/utils.js:9-12
window.parent.postMessage(`chatwoot-widget:${JSON.stringify({...msg})}`, '*');
```
```js
// app/javascript/widget/helpers/utils.js:18-22
isAValidEvent: e => typeof e.data === 'string' && e.data.indexOf(WOOT_PREFIX) === 0,
```

O sentido SDK→widget **já foi corrigido** no fork (usa a origem do `src` do iframe — ver §14). Os outros três pontos continuam abertos e são correções de 3 a 5 linhas cada.

**#10 — MutationObserver**

```js
// app/javascript/sdk/DOMHelpers.js:61-74
const bodyList = document.querySelector('body');
const observer = new MutationObserver(mutations => {
  mutations.forEach(() => {
    if (oldHref !== document.location.href) { ... }
  });
});
observer.observe(bodyList, { childList: true, subtree: true });
```

Toda mutação do DOM do site do cliente (qualquer re-render de React/Vue/Angular, qualquer animação que adicione nó) dispara um callback que roda `mutations.forEach` — ou seja, o `if` é reavaliado uma vez **por mutação**, não uma vez por lote. Em SPA pesada isso é ruído contínuo no main thread do cliente. As APIs modernas (`navigation.addEventListener('navigate')`, ou monkey-patch de `history.pushState` + `popstate`) resolvem sem observar o DOM.

**#12 — Contato criado no page-load**

`widgets_controller.rb:54-59` chama `build_contact` incondicionalmente no `before_action`. Como o iframe é criado no `createFrame` **imediatamente**, antes de qualquer clique, **todo visitante que carrega uma página com o widget instalado gera uma linha em `contacts` + `contact_inboxes`**, com nome gerado pelo Haikunator (`ContactInboxWithContactBuilder#create_contact` → `::Haikunator.haikunate(1000)`).

Consequências: base de contatos inflada com registros anônimos, `contact_inboxes` crescendo linearmente com pageviews de visitantes novos, e ruído em qualquer relatório de contatos. É comportamento upstream, mas com volume de tráfego de cliente real vira um problema de custo e de qualidade de dado.

**#13 — `emitter.$emit`**

```js
// app/javascript/widget/components/ChatFooter.vue:97-105
emitter.emit(BUS_EVENTS.SHOW_ALERT, { ... });   // linha 97 — correto
} catch (error) {
  emitter.$emit(BUS_EVENTS.SHOW_ALERT, { ... }); // linha 102 — mitt não tem $emit
}
```

`app/javascript/shared/helpers/mitt.js:1-3` exporta `mitt()` puro, cuja API é `on/off/emit`. `$emit` é `undefined` → `TypeError` dentro do `catch` → rejeição não tratada. Efeito prático: **quando o envio de transcrição por e-mail falha, o usuário não vê o erro** e o console do widget quebra.

**#15 — `campaignTimer.clearTimers`**

```js
// app/javascript/widget/helpers/campaignTimer.js:17-22
clearTimers = () => {
  this.campaignTimers.forEach(timerId => {
    clearTimeout(timerId);
    this.campaignTimers[timerId] = null;   // ← índice errado
  });
};
```

`campaignTimers` é usado como mapa indexado por `campaignId` (linha 11). No `forEach`, `timerId` é o **valor** (o handle do timer), então `clearTimeout(timerId)` está certo, mas `this.campaignTimers[timerId] = null` escreve num índice arbitrário (o número do handle), criando buracos no array e deixando os slots dos `campaignId` com handles obsoletos. Não causa bug visível (o `initTimers` sobrescreve), mas vaza memória em SPAs com muita troca de rota.

**#16 — Mutação fora de mutation**

```js
// app/javascript/widget/store/modules/conversation/actions.js:124-127
missingMessages.forEach(message => {
  conversations[message.id] = message;   // `conversations` vem de state, mutado direto
});
```

Viola o contrato do Vuex (`strict: false` salva no build de produção, mas o devtools mente). Só afeta manutenção.

**#21 — Cookie 365 vs JWT 180**

`cookieHelpers.js:26-30` define `expires = 365` como default, e `updateAuthCookie` não passa `expires` (`IFrameHelper.js:40-43`). O `Widget::TokenService::DEFAULT_EXPIRY_DAYS = 180`. Depois de 180 dias, o cookie continua sendo enviado, o `decode_token` devolve `{}` (`base_token_service.rb:9-13`), e `WidgetsController#build_contact` cria um contato novo. O visitante recorrente vira um lead novo, e o histórico dele some — **sem nenhum log, sem nenhum aviso**.

---

## 14. Customizações do ChatSPX sobre o upstream

**FATO VERIFICADO** — `git diff v4.12.1 HEAD` restrito à área do widget. Total: **14 arquivos, 98 inserções, 72 remoções**.

| Arquivo | Mudança | Commit | Avaliação |
|---|---|---|---|
| `app/javascript/sdk/IFrameHelper.js:94-102` | `postMessage` passou de `'*'` para a origem do `src` do iframe | `87095e111b feat: auditoria completa best practices 2026` | ✅ Boa. Endurecimento de segurança sem custo de merge. |
| `app/javascript/sdk/sdk.js:42,132` | Cor da bolha `#1f93ff` → `#2dc46f` | — | 🟡 É só o default do CSS; a cor real vem inline do `widget_color`. Baixo impacto. |
| `app/javascript/widget/assets/images/logo.svg:8` | `#47A7F6` → `#2dc46f` | — | ✅ Neutro. |
| `app/javascript/widget/assets/scss/woot.scss:182-378` | Paleta `iris` (12 tons, claro + escuro), `--text-blue`, `--solid-blue`, `--solid-iris`, `--border-blue` remapeados de azul para verde | — | 🟡 Funciona, mas ocupa a variável semântica `iris`/`blue` com verde. Todo merge do upstream que toque na paleta vai conflitar. |
| `app/javascript/widget/components/ChatHeader.vue` | `bg-n-background`→`bg-n-brand`; `text-n-slate-12`→`text-white`; `bg-n-teal-10`→`bg-white/80` | `4284a31898 feat(ui): WhatsApp design system` | 🔴 **Quebra `widget_color`.** Ver §13.2 item 3. |
| `app/javascript/widget/components/ChatHeaderExpanded.vue:34,50,54` | `bg-transparent`→`bg-n-brand`; textos → branco | idem | 🔴 Idem. |
| `app/javascript/widget/components/HeaderActions.vue:94,101,110` | Ícones → `text-white` | idem | 🔴 Só legível sobre o header verde. |
| `app/javascript/widget/components/ChatSendButton.vue:19-22,27,29` | Prop `color` **removida**; botão fixo em `bg-n-brand hover:bg-[#1FB85A]` | idem | 🔴 Idem. |
| `app/javascript/widget/components/ChatInputWrap.vue:53,130-133,177,188` | Removeu `widgetColor` do mapGetters; trocou box-shadow por border; `shadow-focus` (inexistente) | idem | 🔴 `shadow-focus` não gera CSS. |
| `app/javascript/widget/components/AgentMessageBubble.vue:98` | `bg-n-background`→`bg-white` | idem | 🟡 Perde a adaptação ao tema claro custom. |
| `app/javascript/widget/components/AgentTypingBubble.vue:12` | idem | idem | 🟡 Idem. |
| `app/javascript/widget/components/PreChat/Form.vue:266` | Link `text-n-blue-11`→`text-n-brand` | idem | 🟡 Verde fixo. |
| `app/javascript/widget/views/Messages.vue:22` | `bg-n-slate-2`→`bg-n-chat-bg` (**classe inexistente**) | idem | 🔴 Zero CSS gerado. |
| `app/javascript/widget/components/ConversationWrap.vue:102-108,139-172` | Fundo com textura: `linear-gradient(rgba(...,0.85))` + `url('/assets/images/chat-spx-background[-light].png')`, `background-size: 400px`, `> * { position: relative; z-index: 2 }` | idem | 🟡 Funciona (os PNGs existem: 88.534 B e 96.098 B em `public/assets/images/`), mas são **2 requisições extras de ~90 KB cada** no primeiro paint do widget, sem `preload` e sem versão WebP/AVIF. |

Fora da área estrita do widget, mas com impacto direto nele:

| Arquivo | Mudança | Avaliação |
|---|---|---|
| `app/javascript/shared/helpers/BaseActionCableConnector.js` | **+132 linhas**: watchdog de stream silencioso (15 s / 25 s), reconexão em `visibilitychange` + `focus` + `pageshow(persisted)`, backoff exponencial com jitter, `isDestroyed` guard, limpeza de listeners no `disconnect()` | ✅ **Excelente.** Trabalho sólido, comentado em pt-BR, resolve o problema real do banner "Desconectado". |
| `vite.config.ts:80-84` | `manualChunks: { leaflet: ['leaflet'] }` | 🔴 Efeito colateral: puxa 150 KB de Leaflet para o widget. |
| `vite.config.ts:39-58` | `optimizeDeps.include` para Vue Flow / vue-shepherd | ✅ Neutro para o widget (só afeta dev). |
| `tailwind.config.js:40-63` | Tokens `wa-composer`, `wa`, `brand` | 🟡 Aumenta o CSS gerado do widget. |
| `app/builders/contact_inbox_builder.rb:9-45` | Reuso de `contact_inbox` para WAHA e WhatsApp Cloud | ✅ Não afeta `Channel::WebWidget` (o `case` cai em `SecureRandom.uuid`). |

**Conclusão de merge:** a área do SDK está praticamente limpa (2 mudanças, uma delas uma melhoria genuína que vale propor upstream). A área do **componente visual do widget** está poluída com hardcode de cor, e é ela que vai conflitar em todo bump de versão. A recomendação está em §16.

---

## 15. Pontos de extensão seguros

Lugares onde dá para encaixar código novo com **baixo risco de conflito** em merges futuros do upstream.

### 15.1 Novos eventos para o site do cliente

**Padrão existente:** adicione uma constante em `app/javascript/widget/constants/sdkEvents.js` e, no ponto de origem, envie:

```js
IFrameHelper.sendMessage({ event: 'onEvent', eventIdentifier: MEU_EVENTO, data: {...} });
```

O SDK repassa automaticamente via `IFrameHelper.events.onEvent` (`IFrameHelper.js:206-208`) → `dispatchWindowEvent`. **Não precisa tocar no SDK.** É o ponto de extensão mais barato do sistema inteiro.

Risco de merge: **muito baixo** — `sdkEvents.js` tem 7 linhas e raramente muda upstream.

### 15.2 Novo tipo de mensagem (content_type)

`app/javascript/widget/components/AgentMessageBubble.vue:42-67` tem um bloco de `computed` de um par por `content_type`, e o template (linhas 92-152) faz o switch. Adicionar um tipo é: 1 computed + 1 bloco no template + 1 componente em `shared/components/`.

Risco de merge: **médio** — o `v-if` composto na linha 95-97 (`!isCards && !isOptions && …`) é frágil e conflita. **Recomendação:** refatorar para um mapa `contentType → componente` e um `<component :is>`, o que **reduz** a superfície de conflito ao invés de aumentá-la.

O lado servidor já é genérico: `content_type` é uma coluna de `messages` e `content_attributes` é jsonb.

### 15.3 Novo bloco de configuração por inbox

Três lugares, sempre os mesmos:

1. **Backend, coluna ou flag:**
   - Flag booleana barata → adicionar bit em `has_flags` (`app/models/channel/web_widget.rb:50-56`). **Cuidado:** só restam bits livres a partir do 6; a coluna é integer.
   - Configuração estruturada → nova coluna jsonb, ou reaproveitar `inbox.additional_attributes` (padrão já usado pelo ChatSPX em `pin_mode` e `agent_signature_enabled` — `settingsPage/ConfigurationPage.vue:104-115`). **Esta é a rota de menor atrito de merge**, porque `additional_attributes` já é jsonb livre e não exige migration.
2. **Exposição ao widget:** adicionar em `app/views/widgets/show.html.erb` (dentro de `window.chatwootWebChannel`) **e** em `app/views/api/v1/widget/configs/create.json.jbuilder` (para não divergir do mobile).
3. **Consumo no widget:** `app/javascript/widget/mixins/configMixin.js` já é o ponto canônico de leitura de `window.chatwootWebChannel` — adicionar um computed lá.
4. **UI:** `Settings.vue` dentro do `<SettingsAccordion :title="$t('INBOX_MGMT.WIDGET_FEATURES')">` (linhas 901-1114) ou de um acordeão novo.
5. **Permissão de escrita:** adicionar a chave em `Channel::WebWidget::EDITABLE_ATTRS` (`web_widget.rb:34-40`).

Risco de merge: **médio-baixo** se usar `additional_attributes` (sem migration, sem tocar em `EDITABLE_ATTRS`).

### 15.4 Novo método na API pública do SDK

`app/javascript/entrypoints/sdk.js:83-210` — basta adicionar um método que faça `IFrameHelper.sendMessage('meu-evento', payload)` e um `else if` em `App.vue:258-345`.

Risco de merge: **médio** — a cadeia de `else if` em `App.vue` é exatamente o tipo de código que conflita. **Recomendação:** substituir a cadeia por um mapa `{eventName: handler}` **antes** de adicionar métodos novos. Um mapa reduz conflito a nível de linha; a cadeia garante conflito.

### 15.5 Capturar dados adicionais na criação da conversa

`app/controllers/api/v1/widget/base_controller.rb:31-46` monta `conversation_params.additional_attributes`. Dois caminhos:

- **Sem tocar em código compartilhado (recomendado):** o front já envia `custom_attributes` no `POST /widget/conversations` (`endPoints.js:20`) e o controller já os aceita (`conversations_controller.rb:100`). Basta o widget preencher esse objeto com o que quisermos (UTMs, landing page, etc.). **Zero conflito de merge.**
- **Tocando no backend:** estender `additional_attributes` no `base_controller`, o que requer também estender `permitted_params` (linha 97-101). Conflita a cada bump.

### 15.6 Interceptar/enriquecer o boot do SDK

`app/javascript/entrypoints/sdk.js:21-24` retorna cedo se `window.$chatwoot` existir. Um wrapper próprio (script separado, carregado antes) pode:
- Ler UTMs/`gclid`/`fbclid` da URL e do `document.referrer`;
- Persistir em cookie de primeira parte;
- Chamar `chatwootSDK.run(...)`;
- No `chatwoot:ready`, chamar `setCustomAttributes` com os dados capturados.

**Isso é 100% fora do fork** — nenhum arquivo do Chatwoot é tocado. É a rota de menor risco para resolver o gap de tracking (§11) sem herdar dívida de merge.

### 15.7 Estilos da bolha e do holder

O CSS injetado no site do cliente é uma única template string em `app/javascript/sdk/sdk.js:1-295`. Ele é um arquivo isolado, raramente alterado upstream (só 2 mudanças de cor em toda a história do fork).

Risco de merge: **baixo**. É o lugar certo para mexer em tamanho de bolha, offsets, animações e responsividade.

### 15.8 O que evitar

| Não mexa em | Motivo |
|---|---|
| `App.vue:258-345` (cadeia de `else if`) | Conflita em todo merge. Refatore antes de estender. |
| `AgentMessageBubble.vue:92-152` | O `v-if` composto conflita. Refatore para `<component :is>`. |
| `woot.scss:182-378` (paleta) | Já está sequestrada por verde; upstream mexe nessa faixa com frequência. Melhor introduzir tokens **novos** (`--spx-*`) do que remapear os existentes. |
| Classes Tailwind hardcoded nos componentes | Foi assim que nasceram os itens #3 e #4. Use CSS var (`--widget-color`) ou token de tema declarado. |
| `base_controller.rb` `permitted_params` | Alto atrito. Prefira `custom_attributes`. |

---

## 16. IMPLICAÇÕES PARA O CHATSPX

Achados acionáveis, por camada. **São recomendações — nenhuma implementação foi feita nesta task.**

### 16.1 Correções de regressão (fazer antes de qualquer feature nova)

| # | O que | Onde | Por quê |
|---|---|---|---|
| R1 | Devolver o `widget_color` ao header, botão de enviar e ícones de ação: trocar `bg-n-brand`/`text-white` hardcoded por `rgb(var(--widget-color))` ou aplicar via `:style` como o upstream fazia | `ChatHeader.vue`, `ChatHeaderExpanded.vue`, `HeaderActions.vue`, `ChatSendButton.vue`, `PreChat/Form.vue` | Sem isso, todo cliente do SaaS tem um widget com a cor dele na bolha e a nossa no header. É bug de produto white-label. |
| R2 | Declarar `chat-bg` no `theme/colors.js` e `shadow-focus` no `boxShadow` do `tailwind.config.js` — ou remover as classes | `Messages.vue:22`, `ChatInputWrap.vue:131` | Hoje geram zero CSS. O design pretendido não está no ar. |
| R3 | Corrigir `emitter.$emit` → `emitter.emit` | `ChatFooter.vue:102` | Erro de transcrição por e-mail é engolido e quebra o console. |
| R4 | Alinhar expiração do cookie com a do JWT (180 dias, ou o valor de `WIDGET_TOKEN_EXPIRY`) | `cookieHelpers.js:29` / `IFrameHelper.js:40-43` | Elimina a janela de 185 dias em que o visitante recorrente vira lead novo silenciosamente. |
| R5 | Corrigir `campaignTimer.clearTimers` para limpar pelo `campaignId` | `campaignTimer.js:17-22` | Vazamento de timers em SPA. |

### 16.2 Performance (o item de maior retorno por esforço)

| # | O que | Ganho estimado | Esforço |
|---|---|---|---|
| P1 | **Tirar o Leaflet do grafo do widget**: em vez de `manualChunks: {leaflet: ['leaflet']}` (objeto), usar a forma de função e só isolar o Leaflet quando o chunk de origem for do dashboard; ou remover o `manualChunks` e confiar no `import()` dinâmico que `LocationPickerModal.vue` já faz | **−150 KB cru / −43 KB gzip** no caminho crítico | Baixo |
| P2 | **Compilar um Tailwind separado para o widget**, com `content` restrito a `app/javascript/widget/**` + `app/javascript/shared/**` | **INFERÊNCIA:** ordem de −90% do CSS (de 1,10 MB para algo na casa de 60–120 KB cru) | Médio |
| P3 | Ajustar o `size-limit` para cobrir o **grafo inteiro** (JS + CSS), com orçamento realista (ex.: 250 KB gzip) e falhar o CI ao estourar | Previne regressão futura | Baixo |
| P4 | Converter os 2 PNGs de fundo (~90 KB cada) para WebP/AVIF e/ou substituir por gradiente/SVG procedural | −150 KB de imagem no primeiro paint | Baixo |
| P5 | Trocar o `MutationObserver` da `<body>` por `history.pushState`/`replaceState` monkey-patch + `popstate` (ou a Navigation API, com fallback) | Tira ruído contínuo do main thread do **site do cliente** | Baixo |
| P6 | Avaliar `<link rel="preconnect">` para o domínio do ChatSPX no snippet de instalação | Corta 1 RTT de TLS no boot | Trivial |

### 16.3 Produto — fechar o gap de geração de lead

Este é o bloco que responde ao motivo do estudo. Em ordem de valor.

| # | O que | Camada | Nota |
|---|---|---|---|
| G1 | **Captura automática de origem**: no boot do SDK, ler `utm_*`, `gclid`, `fbclid`, `msclkid`, `ttclid` e `document.referrer`; persistir em cookie de primeira parte com modelo de atribuição (primeiro toque + último toque); anexar ao `custom_attributes` da conversa | SDK + widget | **Pode ser feito sem tocar no backend** via `custom_attributes` (§15.5). Rota de menor risco de merge. |
| G2 | **Landing page e jornada**: acumular a lista de URLs vistas antes da abertura do chat (o `change-url` já passa por lá) e enviar como atributo da conversa | SDK + widget | Reusa infra existente. |
| G3 | **Eventos de conversão para o site do cliente**: emitir `chatspx:conversation-created` (com `conversation_id`), `chatspx:prechat-submitted` (com os campos), `chatspx:csat-submitted`, `chatspx:message-sent` | widget → SDK (via `onEvent`) | §15.1: **zero mudança no SDK**. Permite que o cliente empurre para GTM/GA4/Meta ele mesmo. |
| G4 | **Ponte opcional com `dataLayer`**: uma flag em `chatwootSettings` (`pushToDataLayer: true`) que faz o SDK dar `window.dataLayer.push({event: 'chatspx_…'})` nos eventos acima | SDK | Diferencial direto frente ao Chatwoot cru; é o que ferramentas de geração de lead entregam pronto. |
| G5 | **Gatilhos de campanha além de URL+tempo**: exit intent, profundidade de scroll, nº de páginas na sessão, visitante novo vs recorrente, origem de tráfego, dispositivo | SDK (detecção) + backend (`trigger_rules` jsonb) | `campaign.trigger_rules` já é jsonb — dá para estender sem migration. |
| G6 | **Campanha como fluxo, não como mensagem**: permitir que a campanha entregue uma sequência com perguntas de qualificação e ramificação, reusando o motor Flows já existente no produto | backend + widget | Maior esforço, maior valor. Hoje Flows não é acionável pelo widget web. |
| G7 | **Pre-chat multi-etapa com lógica condicional** | widget (`PreChat/Form.vue`) + `pre_chat_form_options` jsonb | O jsonb já aceita a estrutura; falta o front. |
| G8 | **Persistir posição/tipo/título da bolha no servidor** (hoje só localStorage do dashboard) | backend (`additional_attributes`) + `show.html.erb` + SDK | Elimina a armadilha de "mudei na tela e nada aconteceu no site". |
| G9 | **Busca no Help Center dentro do widget** | widget | Deflexão de atendimento; a API do portal já existe. |
| G10 | **Gravação de áudio no composer** | widget | `iframe.allow` já concede `microphone`. |

### 16.4 Acessibilidade

| # | O que | Onde |
|---|---|---|
| A1 | `aria-label` traduzido na bolha e no botão de fechar (usar o i18n, não `title` hardcoded) | `bubbleHelpers.js:60` |
| A2 | `role="log"` + `aria-live="polite"` na lista de mensagens | `ConversationWrap.vue` |
| A3 | Focus trap dentro do iframe quando aberto, com ESC global fechando | `App.vue` / `ViewWithHeader.vue:108` |
| A4 | `type="button"` explícito nos botões da bolha (evita submit acidental se o widget cair dentro de um `<form>` do cliente) | `bubbleHelpers.js:17-18` |
| A5 | Trocar `role="button"` em `<div>` por `<button>` real | `ArticleListItem.vue:22` |
| A6 | Auditoria de contraste do header verde `#2dc46f` com texto branco (**NÃO VERIFICADO** — não medi; `#2dc46f` sobre branco é ~2.2:1, texto branco sobre `#2dc46f` fica na casa de 2.3:1, abaixo do mínimo WCAG AA de 4.5:1) | `ChatHeader.vue` |

### 16.5 Segurança e robustez

| # | O que | Onde |
|---|---|---|
| S1 | Trocar `window.onmessage = …` por `window.addEventListener('message', …)` | `IFrameHelper.js:105` |
| S2 | Validar `e.origin` contra a origem do `baseUrl` no SDK, e contra a origem do parent no widget | `IFrameHelper.js:105-116`, `widget/helpers/utils.js:18-22` |
| S3 | Trocar `postMessage(msg, '*')` do widget por origem explícita (o widget conhece o `referrerHost`) | `widget/helpers/utils.js:9-12` |
| S4 | Enxugar `iframe.allow` para só o que é usado hoje (`fullscreen`, `clipboard-write`); reintroduzir `camera`/`microphone` só quando houver feature que use | `IFrameHelper.js:70-71` |
| S5 | Adicionar `secure: true` ao cookie quando `location.protocol === 'https:'` | `cookieHelpers.js:31-35` |
| S6 | Trocar `GET /widget/conversations/toggle_status` por `POST`/`PATCH` (GET não deve mudar estado; prefetchers de navegador podem resolver conversas) | `routes.rb:600` |
| S7 | Enviar erros do widget para o GlitchTip em vez de `catch { // Ignore error }` — hoje falhas silenciosas no widget são invisíveis para a operação | `store/modules/**` |
| S8 | Fingerprint + SRI no `/packs/js/sdk.js`, ou pelo menos uma política de cache explícita documentada | `vite.config.ts:63-69` |

### 16.6 Manutenibilidade / preparo para merge do upstream

| # | O que | Por quê |
|---|---|---|
| M1 | Refatorar `App.vue:258-345` de cadeia de `else if` para mapa `{event: handler}` | Cada feature nova hoje aumenta a chance de conflito. Um mapa isola por linha. |
| M2 | Refatorar `AgentMessageBubble.vue` para `<component :is>` com mapa de `content_type` | Idem, e o `v-if` composto atual já tem `!isCards` duplicado (linha 96) |
| M3 | Substituir hardcode de cor por CSS custom properties (`--widget-color`, `--spx-*`) | Torna a customização visual **dados**, não código — some do diff contra o upstream |
| M4 | Introduzir tokens `--spx-*` novos em vez de remapear `iris`/`blue` | A faixa `woot.scss:182-378` conflita a cada bump |
| M5 | Adicionar teste de smoke que renderize o widget e falhe se uma classe Tailwind usada não existir no tema | Evita repetir o caso `bg-n-chat-bg` |
| M6 | Documentar (no `PRODUCT.md` ou em `plano/`) que **toda config nova do canal precisa entrar em dois lugares**: `show.html.erb` e `configs/create.json.jbuilder` | Evita divergência web vs mobile |
| M7 | Propor upstream o patch de `targetOrigin` do `IFrameHelper.sendMessage` | Se aceito, some do nosso diff |

### 16.7 Ordem sugerida de execução

1. **Bloco R** (regressões) — é correção, não feature; destrava a cor por cliente.
2. **P1 + P3** (Leaflet + orçamento) — algumas horas, corta 43 KB gzip e trava a regressão.
3. **G1 + G3** (captura de origem + eventos de conversão) — resolve o gap competitivo mais visível e pode ser feito **fora do fork**.
4. **P2** (Tailwind do widget) — o ganho maior, mas exige cuidado para não quebrar estilo.
5. **A1–A5** (acessibilidade) — barato e vira argumento comercial (LGPD/acessibilidade em licitação pública).
6. **M1–M4** (refatoração para merge) — **antes** de G5/G6/G7, senão a dívida de merge dobra.
7. **G5 → G7 → G6** (campanhas e pre-chat) — o roadmap de produto propriamente dito.

---

## Anexo A — Cobertura de testes existente

**FATO VERIFICADO.**

**Backend (RSpec):**
- `spec/controllers/widgets_controller_spec.rb`
- `spec/controllers/api/v1/widget/` — `campaigns`, `configs`, `contacts`, `conversations`, `direct_uploads`, `events`, `inbox_members`, `labels`, `messages`, `integrations/`
- `spec/models/channel/web_widget_spec.rb`

**Front (Vitest):**
- SDK: `app/javascript/sdk/specs/cookieHelpers.spec.js`, `settingsHelpers.spec.js` — **só 2 arquivos, cobrindo os 2 helpers mais simples. `IFrameHelper.js` (348 linhas) e `entrypoints/sdk.js` (222 linhas) não têm nenhum teste.**
- Widget store: specs para `agent`, `appConfig`, `articles`, `campaign`, `contact`, `conversation`, `conversationAttributes`, `message` (actions/getters/mutations) — cobertura razoável.
- Widget helpers: `availabilityHelpers`, `campaignHelper`, `urlParamsHelper`, `utils`.
- Widget composables: `useAttachments`, `useAvailability`, `useDarkMode`.
- Widget API: `endPoints.spec.js`.
- Widget mixins: `configMixin`, `messageMixin`.
- **Nenhum teste de componente Vue do widget** (0 arquivos `.spec.js` em `widget/components/` ou `widget/views/`).

**Lacuna crítica:** a peça que roda no site de terceiros (o SDK) é a menos testada do sistema.

---

## Anexo B — Comandos de verificação usados

Todos read-only. Reproduzíveis a partir de `/home/chatwoot/chatwoot` na branch `homologacao`.

```bash
# Estado do repo
git rev-parse HEAD                        # ee87f5e799…
git remote -v                             # origin=Dev-Simplex/chatspx  upstream=chatwoot/chatwoot
cat config/app.yml                        # version: '4.12.1'

# Diff contra o upstream, restrito à área do widget
git diff --stat v4.12.1 HEAD -- \
  app/javascript/sdk app/javascript/widget \
  app/controllers/api/v1/widget app/models/channel/web_widget.rb \
  app/views/widgets app/javascript/entrypoints/sdk.js \
  app/javascript/entrypoints/widget.js
# → 14 arquivos, 98 inserções, 72 remoções

git diff --stat v4.12.1 HEAD -- app/javascript/shared/
# → BaseActionCableConnector.js  +132 linhas

# Tamanho do SDK
ls -la public/packs/js/sdk.js             # 28.834 B
python3 -c "import gzip;print(len(gzip.compress(open('public/packs/js/sdk.js','rb').read(),9)))"
                                          # 9.491 B

# Grafo crítico do widget (JS + CSS, cru + gzip)
python3 - <<'EOF'
import json, os, gzip
m = json.load(open('public/vite/.vite/manifest.json'))
seen = set()
def walk(k):
    if k in seen or k not in m: return
    seen.add(k)
    for i in m[k].get('imports', []): walk(i)
walk('entrypoints/widget.js')
tot = totgz = 0
for k in sorted(seen):
    files = [m[k]['file']] + m[k].get('css', [])
    for f in files:
        p = os.path.join('public/vite', f)
        if not os.path.exists(p): continue
        d = open(p,'rb').read()
        tot += len(d); totgz += len(gzip.compress(d,9))
        print(f"{f:52s} {len(d):>9,} / {len(gzip.compress(d,9)):>9,}")
print(f"TOTAL {tot:,} cru / {totgz:,} gzip")
EOF
# → 2.579.866 cru / 588.943 gzip

# Classes Tailwind mortas
grep -c "bg-n-chat-bg"  public/vite/assets/widget-*.css   # 0
grep -c "shadow-focus"  public/vite/assets/widget-*.css   # 0
grep -o "\.bg-n-brand{[^}]*}" public/vite/assets/widget-*.css
# → .bg-n-brand{--tw-bg-opacity: 1;background-color:#2dc46f}

# Tracking: ausência de UTM / dataLayer no SDK e no widget
grep -rni "utm_\|gclid\|fbclid\|dataLayer\|gtag(" \
  app/javascript/sdk app/javascript/widget \
  app/controllers/api/v1/widget app/models/channel/web_widget.rb
# → vazio

# Acessibilidade
grep -rn "aria-" app/javascript/widget app/javascript/sdk \
  --include=*.vue --include=*.js | grep -vc spec        # 2

# Cobertura i18n pt-BR do widget
python3 - <<'EOF'
import json
def flat(d,p=''):
    o={}
    for k,v in d.items():
        kk=f"{p}.{k}" if p else k
        o.update(flat(v,kk)) if isinstance(v,dict) else o.update({kk:v})
    return o
en=flat(json.load(open('app/javascript/widget/i18n/locale/en.json')))
pt=flat(json.load(open('app/javascript/widget/i18n/locale/pt_BR.json')))
print(len(en),'chaves en;', len([k for k in en if k not in pt]),'faltando em pt_BR')
EOF
# → 85 chaves en; 0 faltando em pt_BR

# Endpoint /widget/config não é usado pelo front
grep -rn "widget/config" app/javascript/                 # vazio

# Contagem de arquivos
wc -l app/javascript/sdk/*.js                            # 892 total
find app/javascript/widget -type f | wc -l               # 200
```

---

**Fim do relatório.**

Este documento é o "antes" do estudo de chat de site. As tarefas paralelas (Leadster e demais referências de mercado) devem ser lidas contra a tabela de features da §9, contra o gap de tracking da §11 e contra os pontos de extensão da §15 — é lá que o "depois" tem que encaixar sem herdar dívida de merge.
