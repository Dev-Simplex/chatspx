# 14 — Lógica e comportamento dos concorrentes (a máquina por trás da tela)

> **Onda:** Repaginada total do front end do widget ChatSPX — fase de estudo.
> **Escopo desta task:** a **lógica**. A task 11 mede o que se vê; esta mapeia o que acontece.
> **Data das medições:** 11/08/2026, entre 21h05 e 22h20 (BRT, America/Sao_Paulo).
> **Nenhum arquivo do repositório foi modificado.** Nenhum deploy, restart ou toque em produção.

---

## 0. Como ler este documento

### 0.1 Convenção de marcação

| Marca | Significado |
|---|---|
| `[MEDIDO]` | Número/comportamento observado por mim, com o comando ou a URL que produziu o número logo ao lado. |
| `[FATO]` | Afirmação de terceiro verificável, com URL. |
| `[LIDO-BUNDLE]` | Extraído por leitura estática do JavaScript servido em produção. É o código real deles, mas **código presente ≠ comportamento ativo**. |
| `[INFERÊNCIA]` | Conclusão minha a partir de dois ou mais fatos medidos. Sempre digo de onde vem. |
| `[NÃO VERIFICADO]` | Não consegui medir. Fica registrado como buraco, não como suposição. |

### 0.2 A regra dos quatro momentos (obrigatória neste documento)

Este projeto já errou por achatar dois fatos distintos. Aqui, **toda afirmação sobre rede, storage
ou estado é etiquetada com o momento em que ocorre**:

| Momento | Sigla | O que é |
|---|---|---|
| Load da página | **(a)** | O visitante chegou. Não tocou em nada. |
| Abrir o widget | **(b)** | Clique no launcher, ou chamada de API equivalente. |
| Primeira mensagem | **(c)** | O visitante manda a primeira mensagem / responde o primeiro passo do fluxo. |
| Handoff para humano | **(d)** | O bot passa a conversa para um atendente. |

Um WebSocket que existe no bundle mas só abre em (d) **não** é "o widget usa WebSocket".
Escrevo sempre "abre WebSocket em (a)" ou "abre WebSocket em (b)".

### 0.3 Método e ferramentas

- **Playwright (Python, Chromium 145.0.7632.6)** com `args=['--no-sandbox','--disable-dev-shm-usage']`,
  `locale='pt-BR'`, `timezone_id='America/Sao_Paulo'`, viewport 1440×900.
- Harness próprio com fases explícitas (A=load, B=abrir, C=mensagem, D=idle, F=offline,
  G=religar, H=SPA, E=revisita), interceptando `request`/`response`/`websocket`/`console`/`pageerror`,
  gravando corpo de resposta das APIs, cookies via `context.cookies()` (inclui HttpOnly) e
  `localStorage`/`sessionStorage` **de todos os frames**.
- **Leitura estática** dos bundles baixados com `curl` do CDN de produção de cada fornecedor.
- **Laboratório local** (`python3 -m http.server 8917`) com os snippets oficiais de instalação,
  para testar validação de domínio, storage bloqueado, SPA e multi-aba em ambiente controlado.

### 0.4 Descoberta de método que invalidaria metade das medições (e como foi corrigida)

Na primeira rodada, Crisp, Tidio e Intercom **não montavam o widget**. **No Crisp**, a causa está
explícita no loader, lido estaticamente:

```js
// https://client.crisp.chat/l.js — crisp-client v4.9.2 (4ea1f89), baixado 11/08/2026
this.u = { domains: [], agents: ["Trident","Googlebot","Bingbot","Slurp","DuckDuckBot",
  "Baiduspider","YandexBot","GTmetrix","Lighthouse","Acunetix","Ahrefs","SemrushBot",
  "SiteAuditBot","SplitSignalBot","HeadlessChrome"], engines:[...] }
// i.lt = function(t=""){ ... if (-1 !== t.indexOf(this.u.agents[n])) i = true ... }  // t = navigator.userAgent
```

`[LIDO-BUNDLE]` O UA padrão do Playwright contém a string `HeadlessChrome` — e o Crisp
**se recusa a carregar**. Todas as medições deste relatório foram refeitas com
`user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36'`.

**Rigor sobre Tidio e Intercom:** eles também passaram a montar depois da troca do UA. `[MEDIDO]`
Mas **não li o mecanismo deles** — pode ser a mesma blacklist, pode ser o banner de consentimento
tendo se comportado de outro jeito, pode ser variação da sessão. Afirmo apenas o resultado, não a
causa. `[NÃO VERIFICADO — causa em Tidio e Intercom]`

**Consequência prática para nós, além do método:** o Crisp também bloqueia `Lighthouse` e `GTmetrix`.
`[INFERÊNCIA a partir do bundle]` Isso significa que **auditorias de performance de sites que usam
Crisp não veem o peso do widget**. É uma decisão de produto agressiva e deliberada.

### 0.5 Limites de ética e escopo (o que eu deliberadamente não fiz)

- **Não enviei mensagem em nenhum chat de terceiro.** Enviar geraria um lead/ticket falso na conta
  de outra empresa. A única exceção controlada foi o Leadster, onde cliquei **na primeira opção do
  fluxo** ("Sim, começar agora") — um botão de fluxo, sem nome, e-mail ou telefone. Nenhum dado
  pessoal foi digitado em lugar nenhum.
- Onde o momento (c) exigiria enviar mensagem, o comportamento está marcado `[LIDO-BUNDLE]` ou
  `[NÃO VERIFICADO]`, nunca inventado.
- Sem login, sem burlar paywall, sem contornar proteção anti-bot além de usar um User-Agent
  de navegador comum.

---

## 1. Sumário executivo — as 12 descobertas que mudam o nosso desenho

| # | Descoberta | Evidência |
|---|---|---|
| 1 | **Crisp e Intercom abrem WebSocket no momento (a)**, antes de qualquer clique. O Intercom abre um **segundo** transporte (Ably) só em (b). | §4.2, §4.3 |
| 2 | **JivoChat abre WebSocket em (a)** com protocolo próprio de texto (tab-separated), não JSON. | §4.4 |
| 3 | **HubSpot e Zendesk não abrem nenhum transporte de tempo real** em (a) nem em (b) sem thread ativa. | §4.6, §4.7 |
| 4 | O Leadster tem **schema de fluxo declarativo em JSON com condicionais, tipos de input, máscara, interpolação `{{var}}`, score por opção e disparo de pixel como passo do fluxo**. Capturei o JSON inteiro. | §3 |
| 5 | **Segmentação: três arquiteturas distintas.** Leadster decide no servidor (1 request); Intercom manda **15 rulesets** e o cliente avalia; Crisp mantém contador de visitas em `localStorage`. | §5 |
| 6 | O **backoff do JivoChat é o mais sofisticado que li**: exponencial com jitter, teto de 32 s, watchdog de 30 s **e uma tabela de espera por motivo de fechamento** que vai de 0 s a 24 h. | §4.4 |
| 7 | O **Crisp desconecta no `pagehide` e reconecta no `pageshow`**, lembrando o estado anterior — e **não escuta `visibilitychange` em nenhum dos três bundles** (0 ocorrências). Também faz **monkey-patch de `history.pushState`/`replaceState`** para SPA, com restauração dos originais. | §4.2, §9.1, §9.3 |
| 8 | **Fila offline confirmada ao vivo no Crisp**: cortei a rede, digitei, religuei — os eventos saíram enfileirados no reconnect, inclusive o rascunho não enviado, que é **sincronizado com o servidor**. | §7.2 |
| 9 | **Validação de domínio: Crisp e Intercom validam no servidor e recusam; JivoChat não valida** — subi o widget deles em `127.0.0.1` e ele registrou visitante normalmente. | §10 |
| 10 | **Storage bloqueado: Crisp degrada em silêncio (nem carrega); JivoChat estoura `pageerror` e reporta erro** para `err.jivosite.com`. | §7.1 |
| 11 | **Telemetria de erro embutida em todos.** Crisp reporta pelo próprio WebSocket (`issue:report`); Tidio usa Sentry; HubSpot usa `exceptions.hubspot.com`; JivoChat, `err.jivosite.com`. | §7.3 |
| 12 | **Nossa API pública (13 métodos, 7 eventos) é maior que a do JivoChat em eventos e menor que a do Crisp em tudo.** O Leadster praticamente não tem API. | §11 |

---

## 2. Mapa de comportamento por fornecedor

### 2.1 Identificação das versões medidas

| Fornecedor | Versão observada | Onde apareceu |
|---|---|---|
| Leadster | `clientVersion: "2.67.0"`, `scriptVersion: 647004`, `scriptId: 202591` | corpo do POST `app.leadster.com.br/api/chatbot/events` `[MEDIDO]` |
| Crisp | `crisp-client v4.9.2` build `4ea1f89` | cabeçalho de `client.crisp.chat/l.js` `[MEDIDO]` |
| Intercom | `v=3`, `g=856a8dfa525373ed308f9a6c369a356828aa0626` | query string de todo POST a `api-iam.intercom.io` `[MEDIDO]` |
| JivoChat | `widget_version: "201.5.0"`, build `01fa91a`, shard `jvs1` | POST `telemetry.jivosite.com/w` `[MEDIDO]` |
| Tidio | `widget-v4/1_451_0`, hash `7d99179aad9dc45f4425` | path dos bundles `[MEDIDO]` |
| Zendesk | Web Widget **Classic** `web-widget-main-7e9a79b.js` | path do bundle `[MEDIDO]` |
| HubSpot | `conversations-visitor-ui static-1.30360`, embed `static-1.27861` | path do bundle e query `[MEDIDO]` |

### 2.2 Onde cada widget mora no DOM (isolamento)

`[MEDIDO]` via `getComputedStyle` + `getBoundingClientRect` em varredura de todos os elementos:

| Fornecedor | Vive em iframe? | Elemento raiz | z-index |
|---|---|---|---|
| **Leadster** | **Não** — DOM direto na página host | `div#registration-chatbot.nld-chatbot` | `9999999` |
| **Crisp** | Não (DOM direto, CSS próprio) | `div.cc-13wro` (launcher, 54×54) | `1000002` |
| **Intercom** | Sim (iframes do messenger) | `#intercom-container`, `.intercom-lightweight-app-launcher` | — |
| **JivoChat** | Híbrido: `<jdiv>` no host + `iframe#jivo_container` | `jdiv#jcont.notranslate` | `2147483646` |
| **Tidio** | Sim (`chunk-WidgetIframe`) | — | — |
| **Zendesk** | Sim (`iframe#launcher`) | `iframe#launcher` | — |
| **HubSpot** | Sim | `div#hubspot-messages-iframe-container` + `iframe#hubspot-conversations-iframe` | `9990` |
| **ChatSPX (nós)** | Sim | `div#cw-widget-holder` + `iframe#chatwoot_live_chat_widget` | `2147483000` |

**Sobre o `<jdiv>` do JivoChat:** é uma tag customizada que não existe no HTML padrão.
`[INFERÊNCIA]` a escolha serve para escapar de seletores CSS do site host (`div {…}` do cliente não
pega `jdiv`). O `class="notranslate"` que a acompanha bloqueia o Google Tradutor de mexer no widget.
`[MEDIDO — o atributo está no elemento]`

O **Leadster não usa iframe nenhum**: 31 elementos `.nld-*` diretamente no DOM da página, 0 shadow
roots. `[MEDIDO]` — isso o expõe totalmente ao CSS do site host, e é o oposto da nossa escolha.

---

## 3. Fluxo conversacional — o schema real do Leadster

Esta é a seção que a task pede com mais insistência: "se conseguir, traga o SCHEMA real do JSON de
fluxo". Consegui.

### 3.1 De onde veio

`[MEDIDO]` Interceptei o corpo da resposta de:

```
POST https://app.leadster.com.br/api/chatbot/scripts/search
     ?company=5&user=<uuid-24>&time=1786484060&path=%252F
     &host=www.leadster.com.br&query=%253Futm_test%253Dold_onboarding&platform=...
→ 200, cache-control: max-age=0, private, must-revalidate
```

Corpo salvo integralmente (7.379 bytes, 24 passos). Momento: **(a) load**, t≈5,4 s.

### 3.2 Envelope de configuração (43 chaves)

```jsonc
{
  "side": "right",
  "title": "Ana - Leadster",
  "avatar": "https://storage.googleapis.com/neuro-cdn/uploads/437c....webp",
  "modules": ["neurologic.js"],          // carregamento dinâmico de módulo — vira 2º <script>
  "version": 2,
  "waitTime": "7000",                    // ms antes de aparecer
  "modalMode": false,
  "alwaysAutoOpen": false,
  "isOpenByTriggerOnly": false,
  "isAb": false,                         // teste A/B de fluxo
  "requiredFields": ["email"],
  "useAbsolutePositioning": false,
  "disable1stPartyBranding": false,
  "whiteLabel": false,
  "privacyPolicyUrl": null,

  // paleta completa entregue pelo servidor (o widget não tem tema fixo)
  "inputColor": "#ecae26", "userMainColor": "#1771f0", "userLightColor": "#eee",
  "userAccentColor": "#fff", "robotMainColor": "#1771f0", "robotLightColor": "#ecae26",
  "robotAccentColor": "#000",

  // convite / tooltip proativo, versionado
  "tooltipMessage": "<p class=\"p1\">Vamos<strong> Começar</strong> seu <strong>Teste Grátis</strong>…</p>",
  "tooltipMessageVersionKey": 1,
  "tooltipMessageVersionDate": "2025-09-22 17:33:37",
  "tooltipMessageVersionHash": "c98269b3e6db394ee6a31fbea5b659b8",

  "notifications": [], "notificationsEnabled": false,
  "notificationsPerSession": 1, "notificationsDisplayTime": "25500",

  "gaConversionEvent": null, "fbqConversionEvents": null,

  "triggerSettings": { /* ver §5.1 */ },

  "companyId": 5, "companyName": "Leadster", "companySegment": "Software",
  "companyTimeZone": "America/Sao_Paulo",
  "companyIntegrations": "email,hubspot,webhook,zapier",
  "scriptVersionId": 647004, "scriptId": 202591,

  "script": [ /* 24 passos — ver §3.3 */ ]
}
```

### 3.3 Gramática dos passos (`script[]`) — tipologia medida

`[MEDIDO]` Contagem por assinatura de chaves nos 24 passos:

| Ocorrências | Chaves do passo | Papel |
|---|---|---|
| 10× | `say` | mensagem do bot (HTML) |
| 6× | `if` + `then` + `finish_flow` + `reject_lead` | **condicional** |
| 4× | `save` + `type` | captura de input tipado |
| 1× | `from` + `messages` + `save` | primeiro passo: mensagens + opções |
| 1× | `from` + `multi` + `selector` + `option_scores` + `save` | escolha com **score** |
| 1× | `mask` + `save` + `type` | input com máscara |
| 1× | `api` | chamada de função ao final |

#### a) Mensagem do bot

```json
{ "say": "<p>Vamos lá! Sua <b>empresa</b>&nbsp;<b>possui um site</b>?</p>", "uid": "4562cjyh" }
```
O conteúdo é **HTML com entidades**, não texto puro. `[MEDIDO]`

#### b) Interpolação de variável

```json
{ "say": "<p>Prazer {{name}}&nbsp;👋</p>", "uid": "22uvtt2" }
```
Sintaxe `{{campo}}`, onde `campo` é o `save` de um passo anterior. `[MEDIDO]`

#### c) Escolha com pontuação de lead

```json
{
  "uid": "5qwjqrca", "from": ["Sim", "Não"], "save": "site",
  "multi": false, "selector": false,
  "option_scores": { "Sim": 4 },
  "version_key": 1, "version_date": "2025-09-22 17:33:37",
  "version_hash": "4220528109f3fdc76eb4563d1a841f1d"
}
```
`option_scores` atribui **pontos de qualificação por opção escolhida**. `multi` permite seleção
múltipla; `selector` alterna botões vs. dropdown. Cada passo carrega **versionamento próprio**
(`version_key`/`version_date`/`version_hash`) — `[INFERÊNCIA]` é isso que permite relatório de
conversão por versão de passo sem quebrar histórico.

#### d) Condicional

```json
{
  "if": { "conditions": [ { "field": "site", "values": ["Sim"], "operator": "=" } ],
          "mainOperator": "OR" },
  "then": { "say": "<p>Qual é a <b>URL do seu site</b>?…</p>", "uid": "9yd9j7zk" },
  "finish_flow": false,
  "reject_lead": false
}
```
Note: o condicional **envolve um único passo** (`then` é um passo, não um bloco). Um "if/else" é
escrito como **dois condicionais espelhados** com `values: ["Sim"]` e `values: ["Não"]` — foi
exatamente o que encontrei. `[MEDIDO]`

`reject_lead: true` **descarta o lead** por condição; `finish_flow: true` encerra o fluxo. Ambos
`false` em todos os passos deste fluxo, mas o campo existe em todos os 6 condicionais.

#### e) Inputs tipados

`[MEDIDO]` Tipos observados neste fluxo: `url`, `name`, `text`, `phone`, `password`,
`unique-leadster-email`.

```json
{ "uid": "f8ouznae", "mask": "(99) 99999-9999", "save": "phone", "type": "phone" }
{ "uid": "z4nj2yio", "save": "email", "type": "unique-leadster-email" }
{ "uid": "zo0e2rig", "save": "nosync::password", "type": "password" }
```

**`unique-leadster-email`** é um tipo de validação **específico do negócio deles** (checa se o e-mail
já tem conta). `[INFERÊNCIA]` pelo nome do tipo; não testei a validação porque não preenchi e-mail.

**Prefixo `nosync::`** marca campos que **não sobem para o backend** — usado em `nosync::password` e
em `nosync::0::Iniciar`. `[MEDIDO]` — confirmado no estado interno (§3.5), onde a chave literal
`"nosync::0::Iniciar"` aparece no dicionário de respostas.

#### f) Pixel de conversão **como passo do fluxo**

```json
{
  "if": { "conditions": [ { "id": 1779304246791.6711, "field": "site",
                            "values": ["Sim"], "operator": "=" } ], "mainOperator": "OR" },
  "then": {
    "say": "", "uid": "29lp4jpy",
    "adsEvents": true, "meta_event": true, "meta_pixel": true, "google_event": true,
    "meta_pixel_code": "980116012414974",
    "meta_event_options":   [ { "label": "sign_up_trial_site", "value": "sign_up_trial_site" } ],
    "google_event_options": [ { "label": "sign_up_trial_site", "value": "sign_up_trial_site" } ]
  }
}
```

E o irmão **server-side** (Conversions API), com mapeamento de campos por interpolação:

```json
{
  "then": {
    "say": "", "uid": "5qvjy77x",
    "adsApiEvents": true, "meta_event": true,
    "meta_pixel_code": "980116012414974", "meta_credential_id": 80,
    "name_field_meta": "{{name}}", "email_field_meta": "{{email}}",
    "phone_field_meta": "{{phone}}", "city_field_meta": "", "state_field_meta": "",
    "google_analytics_event": false,
    "google_analytics_credential_id": 43,
    "google_analytics_measurement_id": "G-YLJ631GJRJ"
  }
}
```

`[MEDIDO]` Isto é, para mim, **a decisão de produto mais importante do arquivo**: o disparo de
conversão (pixel do navegador **e** CAPI server-side, com credencial identificada por id) é um
**passo do fluxo**, editável por quem monta o fluxo, condicionado como qualquer outro passo. Não é
configuração global.

#### g) Passo de saída

```json
{ "api": { "data": { "url": "..." }, "function": "nldAPI_Neurologic_PostMessage" }, "uid": "fqbnnnho" }
```

`function` referencia uma **função global instalada pelo módulo** `neurologic.js` (§3.4).

### 3.4 O módulo `neurologic.js` (498 bytes, íntegro)

`[MEDIDO]` Baixado de `https://cdn.leadster.com.br/neurolead/modules/neurologic.js`
(`cache-control: public, max-age=43200`). É o arquivo inteiro:

```js
function nldAPI_Neurologic_PostMessage_Current_Window(n,e){
  window.postMessage({kind:"finished",config:n,data:neurolead.conversation.flow.data},"*"),
  window.addEventListener("message",function(n){e(n.data)},!1)
}
function nldAPI_Neurologic_PostMessage(n,e){
  window.parent.postMessage({kind:"finished",config:n,data:neurolead.conversation.flow.data},"*"),
  window.addEventListener("message",function(n){e(n.data)},!1)
}
function nldAPI_Neurologic_OnClose(){ window.parent.postMessage({kind:"closed"},"*") }
```

**Três problemas de segurança visíveis em 3 linhas** `[MEDIDO — leitura direta]`:
1. `postMessage(..., "*")` — **targetOrigin curinga**: os dados coletados no fluxo
   (`flow.data`, que inclui nome, e-mail, telefone) são entregues a **qualquer** origem que esteja
   no `window.parent`.
2. `addEventListener("message", cb)` **sem checar `event.origin`** — qualquer frame pode responder.
3. O payload é enviado **antes** de o listener existir, e não há correlação de mensagem
   (sem id/nonce).

Comparação: o nosso `IFrameHelper.sendMessage` calcula `targetOrigin` a partir de `new URL(element.src).origin`
(`app/javascript/sdk/IFrameHelper.js:88-97`) — ou seja, **nós já fazemos melhor que o Leadster nesse ponto**.
Mas o nosso `window.onmessage` também **não valida `e.origin`**, só o prefixo da string
`chatwoot-widget:` (`IFrameHelper.js:100-114`). Ver §10.4.

### 3.5 A máquina de execução do fluxo, medida ao vivo

`[MEDIDO]` Após clicar em "Sim, começar agora" na home da Leadster, li o estado interno:

```js
// window.neurolead.conversation.flow
{
  step: 1,                                        // cursor = índice inteiro no array script[]
  data: { "nosync::0::Iniciar": "Sim, começar agora" },   // respostas, chaveadas pelo `save`
  localData: …, script: …, position: …, currentAction: …,
  currentMessage: …, currentAnswer: …, inputState: …,
  smartCall: …, forceUpdate: …, callOnModulesLoad: …, callOnStateChange: …
}
```

**Onde mora a decisão do próximo passo: no CLIENTE.** `[MEDIDO + INFERÊNCIA]` O servidor entrega o
array inteiro em (a); o cliente mantém `step` como índice, avalia os `if` localmente contra `data`,
e avança. A única ida ao servidor durante o fluxo é **telemetria**, não decisão:

```
POST app.leadster.com.br/api/chatbot/events
{"userId":"c462c62f-…","sessionId":"41a41d","leadId":"c462c62f-…41a41d",
 "company":5,"script":202591,"event":"step_0","clientVersion":"2.67.0",
 "scriptVersion":647004,"time":1786486440,"devMode":false,"isMobile":false,
 "referrer":null,"location":"https://www.leadster.com.br/?utm_test=old_onboarding"}
→ 200 {}
```

`[MEDIDO]` Resposta é `{}` — o servidor não devolve nada que altere o fluxo. **Confirma** que a
decisão é 100% cliente.

`window.neurolead` expõe 40 chaves de estado. As que descrevem a máquina:
`disableServerCommunication`, `backendSyncSent`, `backendSyncSynced`, `completeWhenSynced`,
`completedWhenSynced`, `dataQueue`, `dataQueueStartPtr`, `moduleCallsQueue`, `moduleCount`,
`loadedModuleCount`, `chatOpenTriggersManager`, `popupManager`, `notificationsManager`,
`smartCall`, `filterData`, `convoScript`, `rules`, `openReason`, `isOpen`, `userId`, `sessionId`,
`guid`, `corsToken`. `[MEDIDO]`

`dataQueue` + `dataQueueStartPtr` `[INFERÊNCIA]` é uma **fila de envio com ponteiro de início** —
o padrão clássico de "envie o que já saiu, guarde o resto". `backendSyncSent`/`backendSyncSynced`
são o par de flags de confirmação. Não consegui provocar a fila (exigiria enviar dados pessoais),
então o comportamento sob falha fica `[NÃO VERIFICADO]`.

### 3.6 Estados visuais do fluxo (o que se vê em cada transição)

`[MEDIDO]` — capturas em `shots/leadster-fluxo-passo0-desktop.png` e
`shots/leadster-fluxo-passo1-apos-opcao-desktop.png`.

- Em (a), `.nld-conversation.nld-shown-slide` já está **visível e aberta**: `420×370 px` em
  `x=996, y=482` (viewport 1440×900). Texto: "Feito com Leadster / Ana - Leadster / Online agora /
  Olá, tudo bem?".
- Após o clique na opção, o painel cresce e passa a exibir a resposta do visitante à direita, a
  próxima pergunta e as novas opções ("Sim | Não").

**Nota de rigor:** o Leadster **não** apresenta um launcher fechado esperando clique nesta
configuração — ele abre sozinho. Não posso generalizar isso para todas as contas Leadster:
`alwaysAutoOpen: false` e `isOpenByTriggerOnly: false` nesta conta, e o gatilho `screen_time`
(10 s) está ligado — foi o gatilho que abriu (§5.1). Em outra conta, com outra config, o
comportamento seria diferente. `[MEDIDO nesta conta; NÃO GENERALIZÁVEL]`

### 3.7 Tidio e Cliengo — o que consegui e o que não

- **Tidio** `[MEDIDO]` chaves de estado extraídas do bundle `widget.7d99179aad9dc45f4425.js`
  (592 KB): `tidio_state`, `tidio_conversation_started`, `tidio_conversation_reply`,
  `tidio_conversation_rated`, `tidio_prechat_finished`, `tidio_widget_open`, `tidio_widget_close`,
  `tidio_widget_mute_notifications`, `tidioWidgetNewSkin`, `tidioChatApiFunctionCall`.
  O schema do fluxo (produto "Flows") **não** aparece no bundle nem no tráfego de (a)/(b) — só é
  buscado quando um flow é acionado. `[NÃO VERIFICADO]`
- **Cliengo** `[NÃO VERIFICADO]` — o site `cliengo.com` roda HubSpot, não o próprio widget, e não
  localizei um site público com Cliengo ativo dentro do tempo desta task. Fica como buraco explícito.

---

## 4. Rede e tempo real — quando cada transporte entra

Esta é a seção onde a regra dos quatro momentos mais importa.

### 4.1 Tabela-mestre: quando o transporte abre

| Fornecedor | Transporte | Abre em | Evidência |
|---|---|---|---|
| **Crisp** | socket.io v4 (Engine.IO 4) sobre WS | **(a) load**, t=13,6 s | `wss://client.relay.crisp.chat/w/92b/?EIO=4&transport=websocket` `[MEDIDO]` |
| **Intercom** | Nexus (proprietário) sobre WS | **(a) load**, t=7,2 s | `wss://nexus-websocket-a.intercom.io/pubsub/<tok>?X-Nexus-New-Client=true&X-Nexus-Version=0.20.0&user_role=visitor` `[MEDIDO]` |
| **Intercom** | **Ably** sobre WS (2º transporte) | **(b) abrir**, t=64,2 s | `wss://primary-realtime.intercom-messenger.com/?access_token=<JWT>` `[MEDIDO]` |
| **JivoChat** | WS com protocolo texto próprio | **(a) load**, t=16,8 s | `wss://vi-jvs1-20.jivosite.com/<widgetId>?<visitorId>` `[MEDIDO]` |
| **Tidio** | socket.io v4 sobre WS | **(a) load**, t=11,3 s | `wss://socket.tidio.co/socket.io/?ppk=<key>&device=desktop&cmv=2_0&ver=1.451.0&seid=<uuid>&vid=<visitorId>&EIO=4&transport=websocket` `[MEDIDO]` |
| **Zendesk** (Classic) | nenhum em (a) nem (b) | — | 0 WebSockets em 78 s de observação `[MEDIDO]` |
| **HubSpot** | nenhum em (a) nem (b) | — | 0 WebSockets em 91 s de observação `[MEDIDO]` |
| **Leadster** | ActionCable (`wss://atendimento.leadster.com.br/cable`) | **(d) handoff apenas** | 0 WS em (a)/(b)/(c-parcial); código presente no bundle `[MEDIDO + LIDO-BUNDLE]` |
| **ChatSPX (nós)** | ActionCable | (b) — o widget só monta o consumer dentro do iframe | `app/javascript/widget/helpers/actionCable.js` |

**Aviso de rigor sobre Zendesk e HubSpot:** medi *o Web Widget Classic da Figma* e *o chat do
hubspot.com*, ambos **sem thread ativa**. A ausência de WebSocket vale para essa condição. O que
acontece em (c)/(d) nesses dois é `[NÃO VERIFICADO]` — não enviei mensagem.

### 4.2 Crisp — sequência completa

```
(a) LOAD
 t=12,07s  GET  client.crisp.chat/l.js                              [cache 3h]
 t=12,24s  GET  static/javascripts/client_default_4ea1f89.js        [cache 10 anos, type=module]
 t=12,24s  GET  static/stylesheets/client_default_4ea1f89.css       [cache 10 anos]
 t=12,65s  GET  settings/website/<id>/prelude/?2026-7-11-18-41      [cache 4h — chave é a HORA]
 t=13,58s  WS   ABRE wss://client.relay.crisp.chat/w/92b/?EIO=4
 t=13,92s  <-   0{"sid":"…","upgrades":[],"pingInterval":25000,"pingTimeout":40000}
 t=13,92s  ->   40                                     (namespace connect)
 t=14,12s  <-   40{"sid":"…"}
 t=14,13s  ->   42["session:create",{website_id, website_domain, useragent, timezone:180,
                    capabilities:["browsing","call"], locales:["en","pt-BR"],
                    signature:"crisp-client@v2:<sha256>"}]
 t=14,36s  <-   42["session:created",{"session_id":"session_6fe867ba-…"}]
 t=14,36s  ->   42["session:join",{website_id, session_id, expire:300000, storage:true,
                    sync:false, children:true,
                    device:{page_url, page_title}, signature:"crisp-client@v2:<sha256>"}]
 t=14,59s  <-   42["session:joined",{session_hash, last_active, initiated:false, email:null,
                    phone:null, nickname:"visitor19457856", segments:[], data:{},
                    storage:{state:{},message:[]}, sync:{compose:{}}, buster,
                    socket:true, users_available:true, last_available,
                    response_metrics:{count:1965690,last:…,mean:5386382},
                    count_operators:29, active_operators:[…]}]
 t=14,67s  GET  static/javascripts/en_default_4ea1f89.js            [i18n sob demanda]
 t=17,71s  GET  fonts/noto_sans/0020-007F/{regular,bold}.woff2      [subset por faixa Unicode]

(b) ABRIR  (via window.$crisp.push(['do','chat:open']))
 t=19,03s  GET  stylesheets/common_default_*.css + features/chat_default_*.css
 t=19,11s  GET  javascripts/{main,common}_default_*.js + features/chat_default_*.js
 t=21,20s  GET  sounds/events/chat-message-{receive,action}.oga
 t=21,20s  GET  images/client/avatar-default.svg
 t=21,23s  GET  fonts/noto_sans/2000-206F/noto_sans_regular.woff2   [2ª faixa Unicode]
 t=21,70s  ->   42["storage:sync:update",{ray:"state/94057/0",type:"state",
                    data:{alert:{new_messages:"hide"}}}]
 t=21,70s  ->   42["session:state",{alert:{new_messages:"hide"}}]
 t=21,92s  <-   42["storage:sync:updated",{session_id,ray:"state/94057/0"}]

(D) IDLE 60s
 t=38,89s  <-  2       (ping do SERVIDOR)
 t=38,89s  ->  3       (pong, +1ms)
 t=64,10s  <-  2       Δ = 25.212 ms
 t=89,31s  <-  2       Δ = 25.208 ms
```

`[MEDIDO]` **Ping do servidor a cada ~25,21 s**, batendo com o `pingInterval: 25000` anunciado no
handshake. O cliente responde em ≤1 ms. **Não há polling HTTP nenhum no idle.**

**Detalhes que valem ouro:**

1. **O `prelude` é cacheado por HORA.** A query string é `?2026-7-11-18-41` (ano-mês-dia-hora-?),
   com `cache-control: public, max-age=14400` (4 h). `[MEDIDO]` `[INFERÊNCIA]` É cache-busting
   determinístico: todos os visitantes daquela hora compartilham a mesma URL, então o CDN serve um
   único objeto quente, e a config se propaga em no máximo 1 h. Bem mais esperto que `?t=Date.now()`.
2. **Assinatura no payload.** `signature: "crisp-client@v2:<sha256 hex>"` em `session:create` e
   `session:join`, com hashes **diferentes** entre os dois (é assinatura do payload, não do cliente).
   `[MEDIDO]` O algoritmo é derivável do bundle, então isso é anti-abuso casual, não segurança real.
3. **`expire: 300000`** (5 min) no `session:join` — `[INFERÊNCIA]` é o TTL de presença da sessão no
   servidor, renovado pelos pings.
4. **`storage: {state:{}, message:[]}`** e **`sync: {compose:{}}`** vêm do servidor: o Crisp
   **hospeda o estado do cliente no servidor**, não só no `localStorage` (ver §7.2, onde o rascunho
   não enviado sobe).
5. **Code splitting por momento**: o bundle de chat (`features/chat_default_*.js`, 134.709 bytes)
   **só é baixado em (b)**. Em (a) só entram `client` (337.015 B) e o CSS.

**Configuração de reconexão** `[LIDO-BUNDLE]` — `client_default_4ea1f89.js`, offset ~179185:

```js
this.socket = io(this.ioRelayClient.url, {
  path: this.ioRelayClient.path, transports: e, autoConnect: false,
  timeout: 25000, reconnectionDelay: 15000, reconnectionDelayMax: 60000,
  reconnectionAttempts: 5, randomizationFactor: 0.5
});
this.stream = io(this.ioRelayStream.url, {
  path: this.ioRelayStream.path, transports: e, reconnection: false, autoConnect: false
});
```

Ou seja **dois sockets**: `client.relay.crisp.chat` (com reconexão) e
`stream.relay.crisp.chat` (**sem reconexão**). Os defaults do socket.io (1 s / 5 s / infinitas
tentativas) foram **deliberadamente trocados** por 15 s / 60 s / 5 tentativas com jitter 0,5.
`[INFERÊNCIA]` É uma escolha de proteger o servidor, não o usuário: reconectar devagar reduz
"thundering herd" num incidente, à custa de o visitante ficar até ~22,5 s sem tempo real.
Só observei o `stream` no bundle — em (a)/(b) ele **não** abriu. `[MEDIDO]`

**Ciclo de vida da aba** `[LIDO-BUNDLE]` — offset ~179480:

```js
Listener.addEventListener("window","pagehide", () => {
  this.Ee = this.socket.connected || false;
  this.Ce = this.stream.connected || false;
  if (this.socket.connected) this.socket.disconnect();
  if (this.stream.connected) this.stream.disconnect();
});
Listener.addEventListener("window","pageshow", () => {
  if (this.Ee) { this.Ee = false; this.socket.connect(); }
  if (this.Ce) { this.Ce = false; this.stream.connect(); }
});
```

**Desconecta de propósito no `pagehide` e restaura no `pageshow`, lembrando quem estava conectado.**
Isso é o oposto da nossa abordagem (nós tentamos *manter* e reabrir no `visibilitychange`).
Nenhum `visibilitychange` no caminho do socket do Crisp. `[LIDO-BUNDLE]`

### 4.3 Intercom — dois transportes, dois momentos

```
(a) LOAD
 t=3,45s  GET  widget.intercom.io/widget/tx2p130c        [cache 300s, s-maxage 300]
 t=4,13s  GET  js.intercomcdn.com/frame-modern.e79f0e95.js
 t=4,14s  GET  js.intercomcdn.com/vendor-modern.0157725d.js
 t=5,06s  POST api-iam.intercom.io/messenger/web/launcher_settings
 t=5,06s  POST api-iam.intercom.io/messenger/web/ping
 t=6,08s  GET  js.intercomcdn.com/{vendors~app~tooltips,vendors~sentry~app,vendors~app,
                                    app~tooltips,app}-modern.*.js     (5 chunks)
 t=7,22s  WS   ABRE wss://nexus-websocket-a.intercom.io/pubsub/<token>
 t=7,68s  ->   {"eventName":"nx.Subscribe","nx.Topics":["*"]}
 t=7,68s  ->   {"eventName":"nx.UserPresence","eventData":{"current_page":"https://www.intercom.com/"}}
 t=25,7s  GET  images/typing-indicator-dots-{light,dark}.webp   ← pré-carrega o "digitando" em (a)
 t=47,1s  POST api-iam.intercom.io/messenger/web/rulesets/58118832/match
 t=49,5s  <-   {"eventName":"NewComment","eventData":{"conversationId":"215475450826964",…}}
 t=49,5s  POST api-iam.intercom.io/messenger/web/conversations/215475450826964
 t=51,2s  GET  audio/operator.*.mp3
 t=55,2s  ->   {"eventName":"nx.Ping","eventGuid":"1786484625621",
                "eventData":{"sendTime":…,"endpoint":"…"}}
 t=57,3s  <-   {"eventName":"ACK","eventGuid":1786484625,…}

(b) ABRIR  (via window.Intercom('show'))
 t=63,46s POST messenger/web/open
 t=63,46s POST rtm/connect
 t=63,58s POST messenger/web/home | /conversations | /help_center_content | /news   (4 em paralelo)
 t=63,75s POST rtm/authorize
 t=64,23s WS   ABRE wss://primary-realtime.intercom-messenger.com/?access_token=<JWT>
 t=64,96s <-   {"action":4,"connectionId":"s7kfmqnvUC","connectionDetails":{
                 "clientId":"uc:tx2p130c:6a7b975f4f39f4b27549542f",
                 "maxMessageSize":262144,"maxInboundRate":50,"maxOutboundRate":50,
                 "maxFrameSize":1468006,"serverId":"frontdoor.8bc4.us-east-1-A…"}}
 t=64,96s ->   {"action":10,"channel":"uc:tx2p130c:6a7b975f4f39f4b27549542f"}    (ATTACH)
 t=65,15s <-   {"action":11,"channel":"…","channelSerial":"01786484618448-000@…","flags":786432}
 t=64,40s POST messenger/web/new_conversation_content
 t=79,60s <-   {"action":0}      (heartbeat Ably)
```

`[MEDIDO]` **Dois transportes, dois protocolos, dois momentos.** O JWT do Ably decodifica para
`{"iat":1786484634,"exp":1786488234,"x-ably-capability":"{\"uc:tx2p130c:6a7b975f4f39f4b27549542f\":[\"subscribe\"]}"}` —
**capability restrita a `subscribe` num único canal**, validade 3.600 s. `[MEDIDO — decodificação do
JWT capturado]`

Isso é um modelo de autorização bem melhor que o nosso `pubsub_token` (que é um bearer opaco de
validade indefinida). O token do Intercom **expira em 1 h e só pode assinar um canal**.

**Ping do Nexus:** enviado **pelo cliente** (não pelo servidor, ao contrário do Crisp), com
`sendTime` e o `endpoint` no payload. Duas amostras: t=55,18 s e t=107,12 s → **Δ = 51,94 s**.
`[MEDIDO — 2 amostras; intervalo nominal não confirmado]`

**Todo request HTTP do Intercom carrega:**
`app_id`, `v=3`, `g=<hash do build>`, `s=<uuid da sessão>`, `r=`, `platform=web`,
`installation_type=npm-package`, **`Idempotency-Key=<hex16>`**, `is_intersection_booted`,
`page_title`, `user_active_company_id`, `user_data={anonymous_id…}`, `referer`. `[MEDIDO]`

**A `Idempotency-Key` por request é o detalhe de engenharia mais copiável do Intercom.** Nós não
temos nada equivalente: se o nosso POST de mensagem for reenviado (retry de rede, duplo clique,
service worker), duplicamos a mensagem.

### 4.4 JivoChat — o protocolo de texto e o melhor backoff que li

```
(a) LOAD
 t=5,82s  GET  code-jvs.jivosite.com/widget/gw2zYi08MM             [cache 7200s]  (loader 18 KB)
 t=6,60s  GET  code-jvs.jivosite.com/script/widget/config/<id>     [cache 7200s]
 t=7,08s  GET  node-jvs1-az2-20.jivosite.com/widget/status/1/<id>?rnd=0.075…  [no-store]
 t=7,99s  GET  code-jvs1.jivosite.com/script/widget/config/<id>?v=1786355769   [cache 7200s]
 t=13,40s GET  code-jvs1.jivosite.com/js/bundle.js?rand=1786360576  [cache 86400s]  (1,53 MB)
 t=14,79s GET  css/01fa91a/widget.css                               [cache 864000s]
 t=14,79s GET  script/stat/campaign/visit/1/<id>?ids[]=241&ids[]=242
 t=14,82s GET  widget/visitor_number/1/<id>/<visitorId>?            [no-store]
 t=14,85s GET  js/01fa91a/locale-pt-BR-json.js                      [cache 86400s]
 t=15,11s GET  sounds/{agent_message,notification,outgoing_message}.mp3   [206 Partial, cache 30d]
 t=16,78s WS   ABRE wss://vi-jvs1-20.jivosite.com/<widgetId>?<visitorId>

(b) ABRIR  (via window.jivo_api.open())
 t=20,25s GET  css/01fa91a/chatcontainer.widget.css      ← code splitting
 t=20,25s GET  js/01fa91a/chatcontainer.js
 t=20,61s GET  images/pattern/1.svg

(D) IDLE
 t=73,66s POST telemetry.jivosite.com/w
          {"event":"visitors_presence","widget_id":"gw2zYi08MM","chat_mode":"offline",
           "site_id":1,"device":"desktop","visitor_id":"f097955f95f826be",
           "widget_version":"201.5.0","shard":"jvs1","client_id":235981638}
```

**Protocolo do WebSocket** `[MEDIDO ao vivo no lab local]` — linhas separadas por `\n`, campos por `\t`:

```
->  \t\t\tpurl\thttp://127.0.0.1:8917/jivo.html\n
->  \t\t\tptitle\tLab Jivo\n
->  \t\t\tnavcount\t1\n
->  \t\t\tvisits\t1\n
->  \t\t\tchats\t0\n
->  \t\t\tvisible\ttrue\n
->  \t\t\tstatus\ton_site\n
<-  1779799\tgw2zYi08MM\td8e75e9320d6a81d\t
->  \tgw2zYi08MM\t1779799\tpurl\thttp://127.0.0.1:8917/jivo.html\n
```

Campos do visitante enviados em (a): `purl`, `ptitle`, `navcount`, `visits`, `chats`, `visible`,
`status`. Depois do `<-` de identificação (`<clientId>\t<widgetId>\t<visitorId>\t`), o cliente passa
a endereçar as mensagens (`\t<widgetId>\t<clientId>\t<chave>\t<valor>`). `[MEDIDO]`

**A camada de transporte, lida do bundle** (`code-jvs1.jivosite.com/js/bundle.js`, offset ~216270):

```js
var t = 2e4,   // 20.000 ms — heartbeat: g.send(".")
    r = 2e3,   // 2.000 ms  — delay inicial de reconexão
    i = 32e3,  // 32.000 ms — teto do backoff
    o = 3e4;   // 30.000 ms — watchdog de silêncio
var l = function(e){ return Math.random() * e | 0 };   // jitter uniforme [0, e)

// heartbeat
var _ = function(){ try { g.send(".") } catch(e){} ; p = setTimeout(_, t) };

// reconexão
var y = function(){
  g && (v(), i < (h <<= 1) && (h = i));   // h dobra, saturando em i (32 s)
  g = new WebSocket(n);
  g.onclose = function(t){
    if (t.reason) { var n = -1; switch (t.reason) {
      case "Protocol Error": case "Unsupported Data": case "Invalid Data":
      case "Message Too Big": case "Mandatory Ext.": case "Invalid Response":
      case "Normal Closure":  case "Void Time":        n = 0;              break;
      case "Service Restart":                          n = 6e4  + l(6e5);  break;  //  1– 11 min
      case "Try Again Later":                          n = 6e5  + l(6e5);  break;  // 10– 20 min
      case "Internal Error":                           n = 18e5 + l(6e5);  break;  // 30– 40 min
      case "Going Away":                               n = 36e5 + l(6e5);  break;  // 60– 70 min
      case "Policy Violation":                         n = 72e5;           break;  // 120  min
      case "Blacklisted":                              n = 864e5;          break;  //  24  h
    } if (-1 !== n) return v(), p = null, void s("ondrop", n); }
    else s("onerror", new Error("close-is-not-clean"));
    if (3 <= ++m) return v(), p = null, s("ondrop", 6e5 + l(6e5)),
                        void s("onfail", "Network Unreachable");
    p = setTimeout(y, h + l(r)); i < (h <<= 1) && (h = i);
  };
  g.onmessage = function(e){ m = 0; clearTimeout(f); f = setTimeout(y, o); /* … */ };
  g.onopen    = function(n){ h = r; f = setTimeout(y, o); p = setTimeout(_, t); s("onopen") };
};

// limite de payload
var C = function(e){ var n = String(e).length;
  if (typeof Blob === "function") n = new Blob([e]).size;
  if (!(8192 >= n)) throw new RangeError("message-too-big"); /* … */ };
```

`[LIDO-BUNDLE]` Resumindo o que isso significa:

| Mecanismo | Valor | Efeito |
|---|---|---|
| Heartbeat | `"."` a cada **20 s** | keep-alive mínimo (1 byte) |
| Watchdog | **30 s** sem mensagem → reconecta | detecta socket "zumbi" que não fechou |
| Backoff | 2 s → 4 → 8 → 16 → **32 s** (teto) | exponencial, dobrando |
| Jitter | `+ rand(0, 2000 ms)` | dessincroniza a frota |
| Desistência | **3 falhas** → espera **10–20 min** e emite `onfail("Network Unreachable")` | para de martelar |
| Espera por motivo | tabela de 0 s a **24 h** | o servidor **controla o backoff do cliente** pelo `close reason` |
| Payload máximo | **8.192 bytes** (medido com `Blob` quando disponível) | erro local, não no servidor |
| Reset | `onmessage` zera `m`; `onopen` zera `h` | recuperação limpa |

A **tabela de espera por motivo de fechamento** é a peça que eu não vi em mais ninguém. O servidor
fecha com `reason: "Try Again Later"` e o cliente **some por 10 a 20 minutos**. Com `"Blacklisted"`,
**24 horas**. Isso dá ao backend um botão de válvula durante incidente ou abuso, sem depender de o
cliente ser bonzinho.

**Visibilidade** `[LIDO-BUNDLE]` — offset ~130857:

```js
t.listenVisibility = function(e){
  const t = debounce(e, 50);
  … document.addEventListener(i, t.bind(this,n), false);
    parent.document.addEventListener(i, t.bind(this,n), false);
    parent.document.addEventListener("focus", t.bind(this,n), false);
    parent.document.addEventListener("blur",  …);
}
```

O widget (rodando dentro do iframe) escuta `visibilitychange`, `focus` e `blur` **do documento pai**,
com `debounce(50ms)`. Cobre os quatro prefixos legados (`moz`, `ms`, `webkit`). `[LIDO-BUNDLE]`

**Também no bundle** `[LIDO-BUNDLE]`: `getUTMParamsFromUrl` / `parseUTM` / `setUTM` capturando
`campaign, source, medium, keyword, term, content`, e `navigator.sendBeacon` (1 ocorrência).

### 4.5 Tidio — conectou e caiu

```
(a) LOAD  (em www.tidio.com)
 t= 9,79s GET  www.tidio.com/api/chat-widget-config      ← config no domínio do HOST (1st party)
 t=10,11s GET  code.tidio.co/<publicKey>.js
 t=10,30s GET  widget-v4/1_451_0/static/js/render.<hash>.js
 t=10,38s GET  widget-v4/1_451_0/static/js/chunk-WidgetIframe.<hash>.js
 t=10,38s GET  widget-v4/fonts/{mulish,inter}.woff2
 t=10,40s GET  widget-v4//tururu.mp3 + notification-sound.mp3      ← note a barra dupla
 t=10,46s GET  widget-v4/1_451_0/static/js/widget.<hash>.js
 t=11,30s WS   ABRE wss://socket.tidio.co/socket.io/?ppk=<key>&device=desktop&cmv=2_0
                    &ver=1.451.0&seid=<uuid>&vid=<visitorId>&EIO=4&transport=websocket
 t=11,97s <-   0{"sid":"…","upgrades":[],"pingInterval":25000,"pingTimeout":60000,
                 "maxPayload":1000000}
 t=12,20s ->   420["visitorRegister",{id, originalVisitorId, distinct_id:null, country:null,
                    name:"", city:null, browser_session_id:"", created:1786484702, email:"",
                    project_public_key:"<key>", phone:"", ip:null, lang:"pt-br", browser…}]
 t=12,21s <-   42["connected"]
 t=12,37s <-   41                          ← DISCONNECT enviado pelo SERVIDOR
 t=12,54s      WebSocket fechado
```

`[MEDIDO]` O servidor mandou `41` (disconnect do namespace) 160 ms após o `connected`, e **não houve
reconexão em 78 s de observação**. Não sei a causa. Hipóteses que **não** testei: detecção de
automação no servidor, rate limit, ou comportamento normal quando o widget está oculto.
`[NÃO VERIFICADO — causa desconhecida]`

Registro o que dá para afirmar: **o Tidio abre WS em (a)**, com `pingInterval 25 s`,
`pingTimeout 60 s`, `maxPayload 1.000.000` — e o primeiro evento do protocolo é `visitorRegister`,
que **cria a identidade do visitante no load, antes de qualquer interação**.

Também `[MEDIDO]`: a config do widget vem de **`www.tidio.com/api/chat-widget-config`** — o domínio
do próprio site, não do CDN. Mesmo padrão do HubSpot (§4.6). `[INFERÊNCIA]` Serve para sobreviver a
bloqueadores de terceiros.

### 4.6 HubSpot — sem tempo real, config em 1st party, iframe com UTK na URL

```
(a) LOAD
 t=5,98s GET  js.usemessages.com/conversations-embed.js
 t=6,58s GET  www.hubspot.com/_hcms/livechat/widget?portalId=53
                &conversations-embed=static-1.27861&mobile=false
                &messagesUtk=<utk32>&traceId=<…>              ← 1st party, via CMS do host
 t=7,63s GET  app.hubspot.com/conversations-visitor/53/threads/utk/<utk32>
                ?uuid=<uuid>&mobile=false&mobileSafari=false&hideWelcomeMessage=false
                &hstc=&domain=hubspot.com&inApp5…              ← DOCUMENT do iframe
 t=7,95s GET  static.hsappstatic.net/conversations-visitor-ui/static-1.30352/sass/visitor.css
 t=7,96s GET  static.hsappstatic.net/conversations-visitor-ui/static-1.30360/bundles/visitor.js
 t=8,70s GET  conversations-visitor-ui-lang-pt-br.js + I18n-lang-pt-br.js
              + i18n-data-data-modern-locales-pt-br.js         ← 3 arquivos de i18n
 t=8,71s GET  audio/notification.mp3
 t=9,48s POST exceptions.hubspot.com/frontend/observability/page-tracking/store/  (Sentry/raven 3.19.1)
 t=9,48s POST app.hubspot.com/api/cartographer/v1/rhumb                          (telemetria)
 t=9,49s GET  api/livechat-public/v1/feedback/survey/CSAT/628
 t=9,49s GET  api/livechat-public/v1/bots/public/bot/6215392/welcomeMessages

(b) ABRIR (via HubSpotConversations.widget.open())
 t=26,88s GET  threadview-utv.js + 8338.js + CurrentView-ThreadView.js   ← code splitting

(D) IDLE 50s
 t=57,3s POST api/cartographer/v1/performance     (só telemetria)
 t=68,3s POST metrics-fe-na1.hubspot.com/metrics/v1/frontend/custom/send
```

`[MEDIDO]` **Zero WebSocket, zero polling de mensagens em 91 s.** O único tráfego recorrente é
telemetria de performance.

**A identidade viaja na URL do iframe:** `.../threads/utk/<messagesUtk>`. O `messagesUtk` é o mesmo
token de rastreamento do HubSpot Analytics `[INFERÊNCIA pelo nome e pelo cookie `__hsUserToken`
presente no host]` — ou seja, **o chat e o CRM compartilham a identidade do visitante por
construção**.

Storage lido **por frame** `[MEDIDO]`:
- Frame host (`www.hubspot.com`): `hs-messages-is-open=true` (cookie, `.hubspot.com`, TTL ≈ 30 min),
  `lastExternalReferrer`, `lastExternalReferrerTime`, IndexedDB `hs-cta-interactions@1`.
- Frame do widget (`app.hubspot.com/conversations-visitor/…`): **apenas** `hubspot-modern-theme = {"53":"light"}`.

**O widget guarda quase nada no próprio origin.** Todo o estado relevante está no cookie de 1ª parte
do host e na URL do iframe. `[MEDIDO]`

### 4.7 Zendesk — Web Widget Classic

```
(a) LOAD  (em help.figma.com)
 t=1,46s GET  static.zdassets.com/ekr/snippet.js?key=web_widget/figma.zendesk.com
 t=2,00s GET  ekr.zdassets.com/compose/web_widget/figma.zendesk.com
 t=2,39s GET  static.zdassets.com/web_widget/classic/latest/web-widget-main-7e9a79b.js
 t=2,82s GET  web-widget-5433-7e9a79b.js
 t=2,82s GET  web-widget-locales/classic/pt-br-json-7e9a79b.js
 t=2,95s GET  web-widget-locales/classic/en-us-json-7e9a79b.js     ← baixa DOIS locales
 t=2,83s GET  figma.zendesk.com/embeddable/config                  ← config no domínio do cliente
```

`[MEDIDO]` A `key` do snippet é literalmente `web_widget/<subdominio>.zendesk.com` — não é um UUID
opaco. O caminho `/latest/` significa que **não há versão pinada**: o bundle muda sob os pés do site.

**API pública, medida por erro:** chamar `zE('messenger','open')` devolveu

```
Method messenger.open does not exist.
Check out the Developer API docs to make sure you're implementing it correctly,
https://developer.zendesk.com/embeddables/docs/widget/introduction
```

`[MEDIDO]` — mensagem de erro **com link para a documentação**. É um detalhe de DX que vale copiar:
o erro ensina. `zE('webWidget','open')` funcionou.

Nenhum WebSocket em (a) nem (b), nesta instalação sem chat ativo. `[MEDIDO]`

---

## 5. Segmentação e gatilhos — onde mora a decisão

Três arquiteturas radicalmente diferentes, todas medidas.

### 5.1 Leadster — decisão no servidor, execução no cliente

O request de (a) já carrega o contexto de segmentação **na query string**:

```
POST app.leadster.com.br/api/chatbot/scripts/search
  ?company=5
  &user=<uuid>                 ← visitante
  &time=1786484060
  &path=%252F                  ← path da página (duplo-encoded)
  &host=www.leadster.com.br
  &query=%253Futm_test%253Dold_onboarding   ← query string INTEIRA, com UTM
  &platform=…
```

`[MEDIDO]` O servidor escolhe **qual fluxo** devolver com base em host + path + query (UTM). Um
request, uma resposta, fluxo escolhido.

Os **gatilhos de abertura** vêm dentro da resposta, em `triggerSettings`, e rodam no cliente:

```json
{
  "clicked_at":      { "desktop": {"value":"", "enabled":true,  "openMode":"default"},
                       "mobile": {"value":"", "enabled":false}, "enabled": false },
  "page_click":      { "desktop": {"value":10, "enabled":true,  "cooldownPeriod":null},
                       "mobile":  {"value":20, "enabled":false}, "enabled": false },
  "page_access":     { "desktop": {"value":4,  "enabled":true},  "mobile": {"value":4},  "enabled": false },
  "page_scroll":     { "desktop": {"value":60, "enabled":true},  "mobile": {"value":60}, "enabled": false },
  "screen_time":     { "desktop": {"value":10, "enabled":true,  "cooldownPeriod":43800},
                       "mobile":  {"value":10, "enabled":false}, "enabled": true },
  "cursor_outside":  { "desktop": {"enabled":true, "openMode":"default"}, "enabled": false },
  "inactivity_time": { "desktop": {"value":40, "enabled":true},  "mobile": {"value":40}, "enabled": false }
}
```

**Sete tipos de gatilho, cada um com configuração separada para desktop e mobile, com `cooldownPeriod`
e `openMode` por dispositivo.** `[MEDIDO]`

A implementação são classes no cliente `[LIDO-BUNDLE]` (`neurolead.min.js`, offset ~400030):

```js
class extends ps { static TYPE = "screen_time";
  initialize(){ this.timeoutId = setTimeout(this.openChat, 1e3 * this.config.value) } }
class extends ps { static TYPE = "inactivity_time";
  initialize(){ document.addEventListener(…, this.resetInactivityTimer) } }
class extends ps { static TYPE = "page_scroll";
  initialize(){ window.addEventListener("scroll", this.onScroll) } }
class extends ps { /* page_click */
  onClick(){ this.clickCount++; if (this.clickCount >= this.config.value) { this.openChat(); this.disable() } } }
class extends ps { static TYPE = "cursor_outside";
  initialize(){ document.addEventListener("mouseleave", this.onMouseLeave) } }
```

Cada gatilho é uma classe com `initialize()`, `clean()`, `enable()`, `disable()` e `shouldPersist`.
Arquitetura limpa e extensível.

**Verificação de ponta a ponta do gatilho `screen_time`** `[MEDIDO]`:

```
t= 6,418s  POST /api/chatbot/events  {"event":"show"}
t=17,037s  POST /api/chatbot/events  {"event":"screen_time_triggered"}
Δ = 10.619 ms  ←→  triggerSettings.screen_time.desktop.value = 10 (segundos)
```

O gatilho configurado como 10 s disparou 10,6 s após o `show`. **Configuração e comportamento
batem.**

### 5.2 Intercom — o servidor manda as REGRAS, o cliente avalia

O `POST /messenger/web/ping` de (a) devolve, junto com a config, um array **`client_matches` com 15
rulesets** `[MEDIDO]`:

```json
{ "user_id":"6a7b975f4f39f4b27549542f", "company_id":"-1",
  "ruleset_id": 58118832,
  "ruleset_match_behavior": "single_match",
  "ruleset_link_object_type": "custom_bot",
  "matching_locations": [0, 25, 12],
  "predicates": [
    { "attribute":"client_attributes.time_on_page",     "type":"duration_integer",
      "comparison":"eq", "value":"10" },
    { "attribute":"client_attributes.last_visited_url", "type":"string",
      "comparison":"eq", "value":"https://www.intercom.com/" } ] }
```

**Vocabulário completo medido nos 15 rulesets:**

| Campo | Valores observados |
|---|---|
| `attribute` | `client_attributes.last_visited_url`, `client_attributes.time_on_page`, `client_attributes.pointer_selector` |
| `type` | `string`, `duration_integer`, `css_selector` |
| `comparison` | `contains`, `eq` |
| combinadores | `{"type":"or","predicates":[…]}`, `{"type":"and","predicates":[…]}` — **aninháveis** |
| `ruleset_match_behavior` | `single_match`, `multi_match`, `transient_match` |
| `ruleset_link_object_type` | `chat`, `survey`, `series_condition`, `custom_bot`, `button_custom_bot` |

`client_attributes.pointer_selector` com `type: "css_selector"` é o mais interessante: permite
**disparar um bot quando o visitante clica num seletor CSS específico do site host** — por exemplo
`[data-trigger-bot-from-api]` ou `[data-intercom-target="See how automations can streamline your tasks"]`.
`[MEDIDO]` É a ponte entre o CMS do cliente e o bot, sem código.

**Quando a regra casa**, o cliente materializa no servidor:

```
t=47,1s  POST api-iam.intercom.io/messenger/web/rulesets/58118832/match
→ 200 { "custom_bot": { "id":"215475450826964", "ux_style":"bot",
        "last_participating_admin": {"first_name":"Fin","is_bot":true,…},
        "composer_state": {"visible":true,"custom_bot_active":true,"workflow_active":true,
                           "placeholder":"Message…","visibility":"visible_and_enabled"},
        "header": {"use_bot_header":true,"background_color":"#ffffff",
                   "foreground_primary_color":"#222222","background_color_dark":"#14161a",…},
        "analytics_metadata": {"custom_bot_id": 58118832}, … } }
```

`[MEDIDO]` E, 2,4 s depois, o mesmo conteúdo chega **também pelo WebSocket Nexus** como `NewComment`.
Ou seja: **push e pull para o mesmo evento**.

**Nota de rigor:** o predicado é `time_on_page eq 10` e o `POST /match` saiu em t=47,1 s, não em
t≈15 s. Não sei o mecanismo de avaliação (polling em intervalo? avaliação em eventos discretos?
`time_on_page` contado desde outra origem?). Registro o observado, não o mecanismo.
`[NÃO VERIFICADO — cadência de avaliação]`

**Também medido:** o `launcher_settings` de (a) devolve `layout.ai_suggestions` com três sugestões
**em português** ("O que a Fin pode fazer por mim?", "O Can Fin pode ser integrado com meu Help
Desk?", "Quais resultados a Fin pode gerar?") para um visitante com `country_code: "br"` e
`locale: "en"`. `[MEDIDO]` — a personalização de sugestões de IA é resolvida no servidor,
com localização (inclusive com um erro de tradução visível: "O Can Fin pode ser integrado…").

### 5.3 Crisp — contador de visitas no cliente

`[MEDIDO]` As chaves de gatilho vivem no `localStorage` do host:

```
crisp-client/trigger/<websiteId>/visit/count = 1
crisp-client/trigger/<websiteId>/visit/last  = 1786484484603
```

E a API expõe `$crisp.push(["do","trigger:run", ["<nome>"]])` `[FATO —
https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/dollar-crisp/]`.

**Multi-aba:** abri duas abas; `visit/count` permaneceu **1** e `visit/last` foi atualizado pela
segunda aba. `[MEDIDO]` — o contador é de *visitas*, não de abas.

### 5.4 Comparativo de arquitetura de segmentação

| | Leadster | Intercom | Crisp | ChatSPX (hoje) |
|---|---|---|---|---|
| Onde decide **qual conteúdo** | Servidor (1 request com host+path+query) | Servidor manda **regras**, cliente avalia | Servidor (settings) | Servidor (campanhas) |
| Onde decide **quando abrir** | Cliente (7 classes de gatilho) | Cliente (predicados) | Cliente (contador + trigger) | Cliente (campanha por URL/tempo) |
| Config por dispositivo | **Sim, desktop/mobile separados** | Não observado | Não observado | Não |
| Cooldown | **Sim** (`cooldownPeriod`) | Não observado | Não observado | `cw_snooze_campaigns_till` (1 h) |
| Gatilho por seletor CSS do host | Sim (`clicked_at`) | **Sim** (`pointer_selector`) | Não observado | **Não** |
| Requests durante o fluxo | 0 (só telemetria) | 1 por regra casada | — | — |

---

## 6. Bootstrap comparado — o que custa entrar na página

### 6.1 Tempo até o transporte de tempo real estar de pé (em (a))

`[MEDIDO]` — medido do início da navegação, em rede real, no site de produção de cada fornecedor.
**Estes números incluem o tempo do site host** (o Crisp injeta o `l.js` tardiamente no próprio
site deles, por exemplo), então servem para comparar *ordem de grandeza e sequência*, não para
ranquear performance de widget isolado.

**Variação entre execuções:** o Leadster foi medido em 3 execuções e o `neurolead.min.js` entrou em
3,31 s / 3,31 s / 4,95 s. Trate todos os números desta tabela com ±1,5 s de folga — a rede e o site
host dominam. O que **não** varia é a ordem dos eventos, e é isso que a tabela serve para comparar.

| Fornecedor | 1º script do widget | Transporte pronto | Δ (script → transporte) |
|---|---|---|---|
| Intercom | 3,45 s | 7,22 s (Nexus) | **3,77 s** |
| Leadster | 3,31 s (3,31–4,95 s em 3 execuções) | — (não abre em (a)) | — |
| JivoChat | 5,82 s | 16,78 s | **10,96 s** |
| Tidio | 10,11 s | 11,30 s | **1,19 s** |
| Crisp | 12,07 s | 13,58 s | **1,51 s** |
| Zendesk | 1,46 s | — (não abre em (a)) | — |
| HubSpot | 5,98 s | — (não abre em (a)) | — |

### 6.2 Serial vs paralelo

| Fornecedor | Cadeia serial em (a) | Profundidade |
|---|---|---|
| **JivoChat** | loader → config → status → config(v) → bundle → css → locale → sons → WS | **9 saltos** |
| **Crisp** | l.js → client.js + css (paralelo) → prelude → WS → i18n → fontes | **5 saltos** |
| **Intercom** | widget/<id> → frame+vendor (paralelo) → launcher_settings + ping (paralelo) → 5 chunks → WS | **4 saltos** |
| **HubSpot** | embed.js → /_hcms/livechat/widget → iframe document → css+js → i18n(3) | **5 saltos** |
| **Tidio** | api/chat-widget-config → <key>.js → render.js → widget.js → WS | **5 saltos** |
| **Zendesk** | snippet.js → compose → main.js → 5433.js + locales + embeddable/config | **4 saltos** |
| **ChatSPX** | sdk.js → iframe `/widget?website_token=` → bundle do widget → ActionCable | **4 saltos** |

`[MEDIDO]` A cadeia do JivoChat é a mais profunda e a mais serial — e o preço aparece no
Δ de 10,96 s até o WebSocket.

### 6.3 Política de cache observada

| Recurso | Fornecedor | `cache-control` |
|---|---|---|
| Loader | Crisp `l.js` | `public, max-age=10800` (3 h) |
| Loader | Intercom `widget/<id>` | `max-age=300, s-maxage=300, public` (5 min) |
| Loader | JivoChat `widget/<id>` | `max-age=7200` (2 h) |
| Bundle com hash | Crisp `client_default_<hash>.js` | `public, max-age=315360000` (**10 anos**) |
| Bundle | JivoChat `js/bundle.js?rand=…` | `max-age=86400` (1 dia) |
| CSS | JivoChat `css/<build>/widget.css` | `max-age=864000` (10 dias) |
| Sons | JivoChat `.mp3` | `max-age=2592000` (30 dias), servidos com **206 Partial Content** |
| Config | Crisp `settings/website/<id>/prelude/?<ano-mês-dia-hora>` | `public, max-age=14400` (4 h) |
| Config | Leadster `scripts/search` | `max-age=0, private, must-revalidate` |
| Status | JivoChat `widget/status/…` | `no-cache, no-store, must-revalidate` |

`[MEDIDO]` O padrão bom é claro: **loader curto (minutos/horas) + bundle imutável por hash (anos) +
config com janela** (`prelude` do Crisp, 4 h com chave horária). O anti-padrão é
`?rand=<timestamp>` no bundle do JivoChat, que **quebra o cache do navegador entre carregamentos**
se o timestamp variar — no meu caso ele foi estável (`rand=1786360576`), o que sugere que é o
timestamp do **build**, não do request. `[INFERÊNCIA]`

### 6.4 Peso dos bundles

`[MEDIDO]` — bytes transferidos, `curl -w '%{size_download}'`, 11/08/2026:

| Arquivo | Bytes | Momento em que entra |
|---|---|---|
| Crisp `l.js` (loader) | 7.637 | (a) |
| Crisp `client_default_4ea1f89.js` | 337.015 | (a) |
| Crisp `common_default_*.js` | 62.391 | (b) |
| Crisp `chat_default_*.js` | 134.709 | **(b)** |
| Crisp `main_default_*.js` | 206 | (b) |
| Intercom `widget/tx2p130c` (loader) | 3.159 | (a) |
| JivoChat `widget/<id>` (loader) | 18.483 | (a) |
| JivoChat `js/bundle.js` | **1.531.814** | (a) |
| Tidio `widget.<hash>.js` | 592.048 | (a) |
| Zendesk `snippet.js` | 9.693 | (a) |
| Leadster `neurolead.min.js` | 456.101 | (a) |
| Leadster `modules/neurologic.js` | 498 | (a) |
| **ChatSPX `public/packs/js/sdk.js`** | **28.834** | (a) |
| **ChatSPX `public/vite/assets/sdk-DKziGHsh.js`** | **25.983** | (a) |

**O JivoChat baixa 1,53 MB em (a).** O Crisp baixa 344 KB em (a) e adia 197 KB para (b) — a melhor
divisão que medi. `[MEDIDO]`

---

## 7. Erro, storage e degradação

### 7.1 Storage bloqueado — teste controlado

Bloqueei `localStorage`, `sessionStorage` e `document.cookie` via `add_init_script`, lançando
`SecurityError` no getter (simula Safari em modo restrito / navegação privada agressiva /
extensão de privacidade).

| Fornecedor | Resultado `[MEDIDO]` |
|---|---|
| **Crisp** (em `crisp.chat`) | **Não carrega nada.** Nenhum request para `client.crisp.chat`, nenhum elemento fixo, nenhum WebSocket. Falha silenciosa e limpa. |
| **JivoChat** (lab local) | **Quebra.** Console: `sessionStorage not available SecurityError: Access denied`, seguido de `pageerror: Access denied` (exceção **não tratada**, que vaza para o `window.onerror` do site host). Widget não monta. Dispara `GET https://err.jivosite.com/widget`. |

O comportamento do Crisp é explicado pelo loader `[LIDO-BUNDLE]`:

```js
i.ut = function(){ var t = false;
  try {
    if (navigator.cookieEnabled === true) t = true;
    else if (window.localStorage && …) {
      var i = "" + (new Date).getTime(), n = "crisp-client/loader/storage/check";
      window.localStorage.setItem(n, i);
      t = (window.localStorage.getItem(n) === i);   // escrita+leitura REAL, não feature-detect
    }
  } catch(e) {} finally { return t } };
```

Ele **escreve e relê uma chave de teste** (`crisp-client/loader/storage/check`) em vez de confiar em
`typeof localStorage !== 'undefined'`. Esse é o jeito certo — o Safari em ITP expõe o objeto e
falha na escrita.

O loader do Crisp também recusa carregar quando `window.innerWidth < 280` (`this.m = 280`),
quando não há `window.WebSocket`, e quando o UA casa a blacklist. `[LIDO-BUNDLE]`

### 7.2 Offline e fila — teste controlado no Crisp

Sequência executada `[MEDIDO]`:

```
t=12,61s  WS aberto (fase A)
t=18,32s  abro o widget (fase B)
t=29,10s  ctx.set_offline(True)
t=29,32s  WS FECHADO  (Δ = 223 ms após cortar a rede)
          — digito "teste offline" no compositor —
t=40,45s  ctx.set_offline(False)          (11,3 s offline)
t=48,50s  WS REABRE                       (Δ = 8,05 s após a rede voltar)
t=48,85s  <- 0{"sid":…,"pingInterval":25000,"pingTimeout":40000}
t=49,06s  -> 42["message:compose:send",{"type":"start"}]
t=49,06s  -> 42["message:compose:send",{"type":"stop"}]
t=49,06s  -> 42["message:compose:send",{"type":"start","excerpt":"teste"}]
t=49,06s  -> 42["storage:sync:update",{"ray":"state/2778/1","type":"state",
                                        "data":{"textarea":"teste offline"}}]
t=49,06s  -> 42["session:state",{"textarea":"teste offline"}]
t=49,06s  -> 42["session:join",{…,"sync":true,…}]
t=49,28s  <- 42["session:joined",{…,"initiated":false,…}]
```

Quatro conclusões, todas medidas:

1. **Detecção de queda é imediata** (223 ms) — o socket fecha, não espera timeout.
2. **Não há tentativa de reconexão durante o offline** — nenhum WS novo nos 11,3 s.
3. **A reconexão levou 8,05 s** após a rede voltar. Compatível com
   `reconnectionDelay: 15000, randomizationFactor: 0.5` (janela [7,5 s; 22,5 s]). `[INFERÊNCIA]`
4. **Existe fila offline**, e ela guarda **eventos de UI, não só mensagens**: os três
   `message:compose:send` (indicador de digitação) foram bufferizados e despachados **todos de uma
   vez** no reconnect, fora de ordem temporal útil. `[MEDIDO]` `[INFERÊNCIA]` Isso é um bug de
   qualidade: o operador do outro lado recebe "começou a digitar / parou / começou" comprimidos em
   1 ms, 20 s depois do fato.
5. **O rascunho não enviado sobe para o servidor** (`session:state {textarea:"teste offline"}` e
   `storage:sync:update`). Note que `sync` passou de `false` (join inicial) para **`true`** no
   re-join. `[MEDIDO]` O Crisp sincroniza o que você está digitando **antes de você enviar** —
   é isso que permite ao operador ver o "está digitando: teste…" com o texto parcial.

Nenhuma conversa foi criada (`initiated: false`), então este teste não gerou ticket na conta deles.

### 7.3 Telemetria de erro — todos têm, cada um de um jeito

| Fornecedor | Canal | Payload observado |
|---|---|---|
| **Crisp** | **pelo próprio WebSocket** | `42["issue:report",{"project":"crisp-client","revision":"4ea1f89","environment":"production","useragent":"…","page":"http://127.0.0.1:8917/crisp.html","level":"error","namespace":"[ERROR] [el:el.spawnClient]","traceback":"Spawn client with error mode"}]` `[MEDIDO]` |
| **JivoChat** | `GET https://err.jivosite.com/widget` | disparado quando o storage está bloqueado `[MEDIDO]` |
| **Tidio** | Sentry próprio: `sentry.tidio.co/api/29/envelope/` | `sentry.javascript.nextjs/10.50.0`, `release: homepage-next@1.660.0` `[MEDIDO — no site host]` |
| **HubSpot** | `exceptions.hubspot.com/frontend/observability/page-tracking/store/` | `raven-js/3.19.1`, `deployable=conversations-visitor-ui` `[MEDIDO]` |
| **Intercom** | `js.intercomcdn.com/vendors~sentry~app-modern.*.js` carregado em (a); `sentry_dsn` no loader | `"sentry_dsn":"https://f305de69cac64a84a494556d5303dc2d@app.getsentry.com/24287"` `[MEDIDO — leitura do loader]` |
| **Leadster** | não observado no tráfego de (a)/(b)/(c-parcial) | `[NÃO VERIFICADO]` |
| **ChatSPX** | — | não há telemetria de erro do widget |

O Crisp reportar erro **pelo mesmo WebSocket da sessão** é elegante: um canal só, já autenticado,
funciona mesmo quando o site host tem CSP restritiva contra domínios de terceiros.

### 7.4 O que ninguém faz: CSP

`[NÃO VERIFICADO]` Não consegui testar comportamento sob CSP restritiva do site host dentro do
tempo desta task. É um buraco relevante — vale uma medição dedicada, porque a resposta muda
o desenho do nosso loader (inline vs. arquivo, `connect-src`, `frame-src`).

---

## 8. Persistência — todas as chaves, com TTL medido

### 8.1 Tabela completa

`[MEDIDO]` — `context.cookies()` (inclui HttpOnly) + `localStorage`/`sessionStorage` por frame.

#### Crisp (origin = site host)

| Tipo | Chave | Valor | TTL medido |
|---|---|---|---|
| LS | `crisp-client/session/<websiteId>` | `session_6fe867ba-80e8-4b2e-a089-9942f7f06b90` | — |
| LS | `crisp-client/session/<websiteId>:e` | `1786500252221` (epoch ms) | **≈ 4 h 23 min** à frente |
| LS | `crisp-client/trigger/<websiteId>/visit/count` | `1` | — |
| LS | `crisp-client/trigger/<websiteId>/visit/last` | `1786484484603` | — |
| Cookie | `crisp-client%2Fsession%2F<websiteId>` | mesmo session_id | **182,5 dias** (`expires` − `now` = 15.768.000 s) |
| Cookie | `crisp-client%2Fsocket%2F<websiteId>` | `1` | **48 h** (172.805 s) |

Curiosidade `[MEDIDO]`: o TTL do cookie é **15.768.000 segundos** e o `:e` do localStorage está
**15.768.000 milissegundos** à frente. Mesma constante, unidades diferentes. Pode ser intencional
(sessão curta no cliente, reconhecimento longo no cookie) ou um deslize de unidade. Não afirmo qual.

#### Intercom (origin = site host)

| Tipo | Chave | Valor | TTL medido |
|---|---|---|---|
| Cookie | `intercom-id-<appId>` | UUID | **≈ 270 dias** (23.330.000 s) |
| Cookie | `intercom-device-id-<appId>` | UUID | **≈ 270 dias** |
| Cookie | `intercom-session-<appId>` | **vazio** para visitante anônimo | **7 dias** (604.800 s) |
| LS | `intercom.intercom-state-<appId>` | estado do messenger (`openConfig`, `spaces`, badges) | — |
| LS | `ably-transport-preference` | `{"value":"web_socket"}` | — |
| SS | `intercom.played-notifications` | `{"215475450826964":"message-44148192"}` | sessão |
| LS | `awswaf_session_storage`, `awswaf_token_refresh_timestamp` | token do AWS WAF | — |

**Três identificadores distintos**: `id` (pessoa), `device-id` (dispositivo), `session` (sessão).
O `played-notifications` em `sessionStorage` evita repetir o som da mesma mensagem ao trocar de
página — detalhe pequeno e caro de descobrir sozinho.

#### JivoChat (origin = site host)

| Tipo | Chave | Conteúdo |
|---|---|---|
| LS | `jv_<hash8>_<widgetId>` | **mensagem proativa inteira em cache**: `{"private_id":"5ff3f5be-…","created_ts":1786485917375,"status":"read","from":"agent","text":"Dúvidas sobre o Jivo? …","type":"fortest"}` |
| LS | `jv_temp_sended_stats_<campanhaId>_<widgetId>` | estatísticas pendentes de envio |
| Cookie | **nenhum** | `[MEDIDO]` |

**Zero cookies.** Todo o estado em `localStorage`. `[MEDIDO]` — e o `type: "fortest"` na mensagem
cacheada sugere que essa é a mensagem de teste da conta deles.

#### Tidio

| Tipo | Chave |
|---|---|
| LS/estado | `tidio_state`, `tidio_conversation_started`, `tidio_conversation_reply`, `tidio_conversation_rated`, `tidio_prechat_finished`, `tidio_widget_open`, `tidio_widget_close`, `tidio_widget_mute_notifications`, `tidioWidgetNewSkin` `[LIDO-BUNDLE]` |
| Query do WS | `vid=<visitorId 32 chars>`, `seid=<uuid da sessão>` `[MEDIDO]` |

#### Zendesk (Web Widget Classic)

| Tipo | Chave | Valor medido |
|---|---|---|
| LS | `ZD-buid` | `276ad5b220684ff0a60b59000f91f88f` (browser uid) |
| LS | `ZD-suid` | `{"id":"f0812c2348df468c8128e95fa0243253","expiry":1786487242736,"tabs":{"count":1,"expiry":0}}` |
| LS | `ZD-store` | `{"activeEmbed":"helpCenterForm","widgetShown":false,"is_chatting":false}` |

**`ZD-suid.tabs.count` é um contador explícito de abas.** Ver §9.2.
TTL da sessão: `expiry − now ≈ 1.800 s` = **30 min**, renovado por atividade. `[MEDIDO]`

#### HubSpot

| Tipo | Chave | TTL |
|---|---|---|
| Cookie (host) | `hs-messages-is-open` = `true` | **≈ 30 min** (1.812 s) |
| Cookie (host) | `__hsUserToken` / `messagesUtk` | (não isolei o TTL) `[NÃO VERIFICADO]` |
| LS (iframe) | `hubspot-modern-theme` = `{"53":"light"}` | — |
| IndexedDB (host) | `hs-cta-interactions@1` | — |

**Único fornecedor medido que usa IndexedDB.** `[MEDIDO]`

#### ChatSPX — nós, hoje

| Tipo | Chave | TTL |
|---|---|---|
| Cookie | `cw_conversation` (authToken JWT) | **365 dias**, `sameSite: 'Lax'` (`app/javascript/sdk/cookieHelpers.js:26-45`) |
| Cookie | `cw_user_<websiteToken>` | md5 dos dados do usuário, 365 dias |
| Cookie | `cw_snooze_campaigns_till` | +1 h (`app/javascript/sdk/IFrameHelper.js:44-50`) |
| localStorage | **nenhum** | `grep -rn "localStorage\|sessionStorage" app/javascript/widget/` → **0 resultados** `[MEDIDO]` |

### 8.2 Visitante recorrente e aba anônima

- **Reconhecimento de recorrente**: Crisp usa cookie de 182 dias + LS; Intercom usa
  `intercom-id`/`intercom-device-id` de ~270 dias; JivoChat usa só LS; nós usamos cookie de 365 dias.
- **Aba anônima**: `[INFERÊNCIA — não testei diretamente]` Como cookie e localStorage são
  particionados por perfil, todos perdem a identidade. O Crisp é o único que **detecta e degrada
  antes de tentar** (§7.1), porque testa escrita real.

### 8.3 Segunda visita — medição direta no Crisp

Carreguei `crisp.chat/en/`, esperei 16 s, recarreguei a mesma URL no mesmo contexto e comparei.
`[MEDIDO]`

```
1ª VISITA (fase A)
  t=13,37s  WS abre
  t=13,88s  -> 42["session:create",{website_id, website_domain, useragent, timezone, …}]
  t=14,11s  <- 42["session:created",{"session_id":"session_a451449e-7472-4e9d-a808-4ba4b00bee61"}]
  t=14,11s  -> 42["session:join",{session_id, expire:300000, storage:true, sync:FALSE, …}]
  t=14,35s  <- 42["session:joined",{session_hash:"60656989c064600", last_active:1786487487760,
                   nickname:"visitor19458035", storage:{state:{},message:[]}, sync:{compose:{}}}]
  t=18,23s  WS fechado (navegação)

2ª VISITA (fase E — reload da mesma URL)
  t=29,69s  WS abre
  t=30,19s  -> 42["session:join",{session_id:"session_a451449e-…",   ← MESMO id, do localStorage
                   expire:300000, storage:true, sync:TRUE, …}]        ← sync mudou para true
            ↑ NÃO há session:create. O passo é pulado.
  t=30,42s  <- 42["session:joined",{session_hash:"60656989c064600",   ← mesmo hash
                   last_active:1786487487760,                          ← last_active PRESERVADO
                   nickname:"visitor19458035",                         ← mesmo apelido
                   storage:{state:{},message:[]},
                   sync:{compose:{}, messages:[]}}]                    ← chave `messages` só aparece aqui
```

Três achados:

1. **`session:create` é executado uma única vez.** Nas visitas seguintes o cliente lê o
   `session_id` de `crisp-client/session/<websiteId>` e vai direto para `session:join`. Um
   round-trip a menos e nenhuma sessão órfã criada.
2. **`sync` alterna de `false` para `true`** entre a primeira e a segunda visita. `[INFERÊNCIA]`
   `sync:true` sinaliza "já tenho estado local, me mande o delta" — e é coerente com a resposta
   passar a incluir `sync.messages[]`.
3. **`visit/count` continuou `1`** após o reload. `[MEDIDO]` Recarregar a página **não** conta como
   nova visita — o contador de gatilho tem semântica de sessão, não de pageview. Detalhe que faz
   diferença se copiarmos o mecanismo de gatilho por visita.

**Retomada de conversa:** o histórico volta do servidor em `storage.message[]` / `sync.messages[]`.
No meu teste os arrays vieram vazios **porque não havia conversa** — não enviei mensagem. O
mecanismo está medido; o conteúdo com mensagens reais é `[NÃO VERIFICADO]`.

Nós retomamos por caminho diferente: `cw_conversation` (JWT em cookie) é anexado à query string do
iframe (`app/javascript/sdk/IFrameHelper.js:63-68`), e o widget busca as mensagens por REST ao
montar. Funciona, mas custa um carregamento de iframe antes de qualquer coisa acontecer.

---

## 9. SPA e múltiplas abas

### 9.1 Troca de rota (SPA)

**Crisp** `[LIDO-BUNDLE]` — offset ~180350, o mais completo que li:

```js
Re(){
  if (typeof window.history !== "object") return;
  if (typeof window.history.pushState !== "function") return;
  if (typeof window.history.replaceState !== "function") return;
  let t = window.history;
  this.$e = t.pushState;
  t.pushState = function(...e){ let s = this.$e.apply(t, e);
    window.dispatchEvent(new Event("crisp-pushstate")); return s };
  this.qe = t.replaceState;
  t.replaceState = function(...e){ let s = this.qe.apply(t, e);
    window.dispatchEvent(new Event("crisp-replacestate")); return s };
}
Me(){ if (this.$e) window.history.pushState = this.$e;      // RESTAURA os originais
      if (this.qe) window.history.replaceState = this.qe }
je(){ this.Session._sendDevice();
      this.event.emit("window:history", { page_url: document.location.href,
                                          page_domain: document.location.hostname }) }
```

Monkey-patch dos dois métodos, evento customizado, **e um método de desmontagem que devolve os
originais**. Guardas de tipo antes de tocar em `history`. É o padrão correto.

**Teste ao vivo** `[MEDIDO]` — página local, `history.pushState` para `/rota-2?utm_source=lab`:
o launcher do Crisp permaneceu montado com o **mesmo elemento e as mesmas dimensões**
(`div.cc-13wro z=1000002 1362,826,54,54` antes e depois), a URL mudou, e **não houve remontagem**.

**Nós** `[MEDIDO por leitura do nosso código]`: `app/javascript/sdk/DOMHelpers.js` expõe
`onLocationChangeListener()` e `restoreWidgetInDOM(newBody)`, e o `entrypoints/sdk.js:26-48`
registra handlers para **Turbo (`turbo:before-render` com detecção de `morph`), Turbolinks e Astro
(`astro:before-swap`)**. Cobrimos frameworks específicos; o Crisp cobre o primitivo
(`pushState`/`replaceState`), que funciona em **qualquer** SPA. Ver recomendação §12.

### 9.2 Múltiplas abas

| Fornecedor | Comportamento medido |
|---|---|
| **Crisp** | Duas abas → **dois WebSockets independentes** (abertos em t=13,7 s e t=31,4 s). Mesmo `session_id` (compartilhado via LS). `visit/count` continua **1**. **Sem eleição de líder.** `[MEDIDO]` |
| **Zendesk** | `ZD-suid.tabs.count` foi de **1 → 2**; `ZD-suid.id` e `ZD-buid` idênticos entre abas; `expiry` renovado (+17,3 s). **Contagem explícita de abas.** `[MEDIDO]` |
| **Intercom** | `[NÃO VERIFICADO]` |
| **JivoChat / Tidio / HubSpot** | `[NÃO VERIFICADO]` |
| **ChatSPX** | `[NÃO VERIFICADO]` — mas por construção cada aba monta seu próprio iframe e seu próprio consumer ActionCable, então o comportamento esperado é o do Crisp (N sockets). `[INFERÊNCIA]` |

O `tabs.count` do Zendesk é a única coordenação multi-aba explícita que encontrei.

### 9.3 Ciclo de vida da aba — quem escuta o quê

Contagem de ocorrências nos bundles de produção, `grep -o … | wc -l` `[MEDIDO]`:

| Bundle | `visibilitychange` | `document.hidden` | `pagehide` | `pageshow` |
|---|---|---|---|---|
| `crisp_client_default_4ea1f89.js` | **0** | **0** | 1 | 1 |
| `crisp_chat_default_4ea1f89.js` | 0 | 0 | 0 | 0 |
| `crisp_common_default_4ea1f89.js` | 0 | 0 | 0 | 0 |
| `code-jvs1.jivosite.com/js/bundle.js` | **4** | 1 | 0 | 0 |
| `neurolead.min.js` (Leadster) | 1 | 2 | 3 | 0 |
| `tidio_widget.js` | 1 | 0 | 2 | 0 |
| **ChatSPX** `BaseActionCableConnector.js` | **1** | — | — | **1** (`persisted`) + `focus` |

Duas leituras diretas:

1. **O Crisp não escuta `visibilitychange` em lugar nenhum dos três bundles.** Ele reage
   exclusivamente a `pagehide`/`pageshow`. `[MEDIDO]` `[INFERÊNCIA]` Isso significa que **trocar de
   aba não desconecta nem reconecta o Crisp** — só sair da página (navegação, bfcache) faz isso.
   O socket fica aberto com a aba em segundo plano, sustentado pelo ping de 25 s do servidor.
2. **O JivoChat faz o oposto**: só `visibilitychange` (nos quatro prefixos legados), e escutando
   também no `parent.document` — mais `focus`/`blur` do pai. Nenhum `pagehide`/`pageshow`.

**Nós somos os únicos que cobrem os três caminhos** (`visibilitychange` + `focus` + `pageshow`
com `event.persisted`), o que era o objetivo do F0 "sempre conectado". Isso é vantagem real,
não paridade.

**Tentativa de medir aba em segundo plano — falhou, e registro por quê.** Tentei dois caminhos:

- `page.bring_to_front()` em outra aba do mesmo contexto: `document.hidden` permaneceu `false` na
  aba de trás (Chromium headless não esconde de fato). O socket seguiu aberto e o ping manteve
  cadência de **25.228 ms e 25.203 ms** ao longo de 91 s — o que confirma a estabilidade do ping,
  mas **não** mede background.
- CDP `Page.setWebLifecycleState {state:"frozen"}` por 35 s e depois `"active"`: os comandos foram
  aceitos, mas **nenhum** evento (`freeze`, `visibilitychange`, `pagehide`) foi disparado na página
  (`window.__ev` ficou vazio). Observação colateral: durante os 35 s de "frozen" **nenhum frame
  trafegou** no WebSocket (o esperado seria ≥1 ping), e ao retomar vieram dois pings com 9.271 ms de
  intervalo em vez de 25 s.

Esse último ponto é **indício**, não medição: `[NÃO VERIFICADO]`. O comportamento real de aba em
segundo plano exige um Chromium com interface gráfica e abas de verdade — fica como medição
pendente para quem continuar.

---

## 10. Segurança do comportamento

### 10.1 Validação de domínio — teste controlado

Subi o snippet oficial de cada fornecedor, com o `websiteId`/`appId` público deles, em
`http://127.0.0.1:8917/`. Resultado `[MEDIDO]`:

| Fornecedor | Valida? | Evidência exata |
|---|---|---|
| **Crisp** | **Sim, no servidor** | Enviou `session:create` com `website_domain: "127.0.0.1"`; resposta: `42["session:created",{"error":"invalid_website_id"}]`. Nada gravado em LS/cookie. O launcher **monta visualmente**, mas o cliente entra em "error mode" e reporta `issue:report` com `namespace:"[ERROR] [el:el.spawnClient]"`. |
| **Intercom** | **Sim, no servidor** | `POST /messenger/web/ping` → `{"type":"error.list","errors":[{"code":"403","message":"This domain has not been trusted for the Intercom app defined in the JavaScript snippet."}]}`. **Zero WebSocket aberto.** Nada gravado. |
| **JivoChat** | **Não** | Abriu WebSocket normalmente, recebeu `1779799\tgw2zYi08MM\td8e75e9320d6a81d`, registrou o visitante com `purl=http://127.0.0.1:8917/jivo.html` e gravou `jv_<hash>_<widgetId>` no localStorage com a mensagem proativa. |
| **Tidio** | Inconclusivo | Nenhum WS, nada gravado, mas também não vi mensagem de erro. Pode ser rejeição silenciosa ou falha de bootstrap. `[NÃO VERIFICADO]` |

Detalhe interessante do Intercom `[MEDIDO]`: o `launcher_settings` **foi servido com 200** mesmo em
domínio não confiável, devolvendo cores, paddings e layout. Só o `ping` (que cria sessão) é
bloqueado. **A configuração visual vaza; a sessão não.**

**Nós**: `[NÃO VERIFICADO]` — não testei o ChatSPX em domínio arbitrário nesta task. Pelo código,
`GET /widget?website_token=<token>` não parece validar `Origin`/`Referer` contra uma allowlist de
domínios do inbox. Isso merece verificação dedicada (fora do escopo desta task de estudo).

### 10.2 Assinatura de identidade

| Fornecedor | Mecanismo |
|---|---|
| **Intercom** | `user_hash` (HMAC do identificador com a secret do app), enviado em `intercomSettings`. `[NÃO VERIFICADO NESTA TASK]` — não consegui observá-lo porque medi como visitante anônimo; consta da doc de Identity Verification deles, que não abri nesta task |
| **Crisp** | `CRISP_TOKEN_ID` no loader `[LIDO-BUNDLE]`; `signature:"crisp-client@v2:<sha256>"` nos frames de sessão `[MEDIDO]` — derivável do bundle, portanto **não** é prova de identidade |
| **ChatSPX** | `identifier_hash` (HMAC) suportado em `setUser` (`app/javascript/sdk/cookieHelpers.js:5`) |
| **JivoChat** | `jivo_api.setUserToken()` existe `[MEDIDO na enumeração da API]`; não verifiquei se é assinado `[NÃO VERIFICADO]` |

### 10.3 O que dá para forjar

`[INFERÊNCIA a partir das medições]`:

1. **JivoChat**: qualquer site pode incorporar o widget de qualquer `widgetId` e gerar visitantes
   falsos no painel do dono. Medido em §10.1.
2. **Leadster**: `nldAPI_Neurologic_PostMessage` entrega `flow.data` (nome, e-mail, telefone) para
   `"*"` — qualquer parent frame. Se um site incorporar a página que roda o fluxo dentro de um
   iframe malicioso, colhe os dados do lead. Medido em §3.4.
3. **Crisp / Intercom**: o `signature`/`Idempotency-Key` são anti-abuso casual, não segurança. Mas a
   validação de domínio no servidor **fecha a porta principal**.

### 10.4 postMessage — comparação honesta

| | Envia com `targetOrigin` | Valida `event.origin` ao receber |
|---|---|---|
| **Leadster** | `"*"` ❌ | **não** ❌ |
| **ChatSPX (SDK → widget)** | `new URL(element.src).origin` ✅ (`IFrameHelper.js:88-97`) | **não** ❌ (`IFrameHelper.js:100-114`: só checa o prefixo `chatwoot-widget:`) |

`[MEDIDO — leitura do nosso código]` Fazemos metade certo. O `window.onmessage` do SDK aceita
mensagem de **qualquer** origem, desde que a string comece com `chatwoot-widget:`. Como o handler
despacha para `IFrameHelper.events[...]` — que inclui `setAuthCookie` — isso merece atenção no
redesenho. Não é o escopo desta task corrigir; é o escopo desta task **apontar**.

---

## 11. API pública para o site host

### 11.1 Nossa base de comparação

`[MEDIDO — leitura de `app/javascript/entrypoints/sdk.js`]`

**`window.$chatwoot` — 13 métodos** (contagem minha, feita hoje, sobre
`app/javascript/entrypoints/sdk.js:83-210`): `toggle`, `toggleBubbleVisibility`, `popoutChatWindow`,
`setUser`, `setCustomAttributes`, `deleteCustomAttribute`, `setConversationCustomAttributes`,
`deleteConversationCustomAttribute`, `setLabel`, `removeLabel`, `setLocale`, `setColorScheme`,
`reset`. Mais `window.chatwootSDK.run({baseUrl, websiteToken})`, que é do outro objeto.

> **Divergência com o enunciado desta task**, registrada de propósito: o briefing fala em "14
> métodos". Contei **13** funções em `window.$chatwoot`. Chegando a 14 se incluirmos
> `chatwootSDK.run` (objeto diferente). As demais entradas do objeto (`baseUrl`, `hasLoaded`,
> `isOpen`, `position`, `locale`, `websiteToken`, `darkMode`, …) são **propriedades**, não métodos —
> e essa distinção importa para o redesenho: hoje o site host lê `$chatwoot.isOpen` como campo, o
> que impede que a gente troque a implementação sem quebrar integração. O Crisp expõe o equivalente
> como método (`$crisp.is("chat:opened")`).

**7 eventos** (`app/javascript/widget/constants/sdkEvents.js`): `chatwoot:ready`, `chatwoot:error`,
`chatwoot:on-message`, `chatwoot:on-start-conversation`, `chatwoot:postback`, `chatwoot:opened`,
`chatwoot:closed`.

### 11.2 Comparativo

| Fornecedor | Métodos | Eventos | Fonte |
|---|---|---|---|
| **Crisp** | **~60** em 5 namespaces (`do` 18, `set` 9, `get` 9, `is` 10, `config` 13) | **15** (`on`) | `[FATO — docs.crisp.chat]` |
| **JivoChat** | **26** | **2 úteis** (`jivo_onLoadCallback`, `jivo_onMessageReceived`) | `[MEDIDO — enumeração de `window.jivo_api` ao vivo]` |
| **Tidio** | **21** | ~9 (`ready`, `open`, `close`, `messageFromVisitor`, `messageFromOperator`, `newMessage`, `setStatus`, `conversationStart`, `prechat`) | `[MEDIDO — enumeração + bundle]` |
| **Intercom** | **19** | **4** (`onHide`, `onShow`, `onUnreadCountChange`, `onUserEmailSupplied`) | `[FATO — developers.intercom.com]` |
| **ChatSPX (nós)** | **13** | **7** | `[MEDIDO — código]` |
| **Zendesk** | `zE('webWidget', …)` (Classic) | — | `[MEDIDO — erro documentado ao chamar método inexistente]` |
| **Leadster** | **~0** (3 funções globais `nldAPI_*`, que são *callbacks do fluxo*, não API do host) | 0 | `[MEDIDO]` |

**Enumeração completa medida ao vivo:**

`window.jivo_api` (26): `chatMode`, `clearHistory`, `close`, `getContactInfo`,
`getUnreadMessagesCount`, `getUtm`, `getVisitorNumber`, `isCallbackEnabled`, `open`, `sendMessage`,
`sendOfflineMessage`, `sendPageTitle`, `setClientAttributes`, `setContactInfo`, `setCustomData`,
`setExternalData`, `setMaxLink`, `setRules`, `setTelegramLink`, `setUserToken`, `setVKLink`,
`setWhatsAppLink`, `setWidgetColor`, `showCampaignPopup`, `showProactiveInvitation`, `startCall`.

`window.tidioChatApi` (21): `addVisitorTags`, `adjustStyles`, `chatDisplay`, `close`, `display`,
`hide`, `messageFromOperator`, `messageFromVisitor`, `open`, `popUpHide`, `popUpOpen`,
`removeStyles`, `setColorPalette`, `setColorPallete` *(sic — o typo está no produto, mantido por
compatibilidade)*, `setContactProperties`, `setDeviceType`, `setFeatures`, `setVisitorCurrency`,
`setVisitorData`, `show`, `track`. Propriedades: `eventPrefix`, `queue`, `readyEventWasFired`.

### 11.3 O que eles têm que nós não temos

| Capacidade | Quem tem | Nosso equivalente |
|---|---|---|
| **Enviar mensagem programaticamente** | Crisp (`message:send`), JivoChat (`sendMessage`), Intercom (`startConversation`, `showNewMessage`), Tidio (`messageFromVisitor`) | **nenhum** |
| **Injetar mensagem local do operador** (sem passar pelo servidor) | Crisp (`message:show`), Tidio (`messageFromOperator`) | **nenhum** |
| **Ler contagem de não lidas** | Crisp (`get chat:unread:count`), JivoChat (`getUnreadMessagesCount`) | **nenhum** (só o ponto vermelho, interno) |
| **Consultar estado** (`is chat:opened`, `is website:available`) | Crisp (10 predicados) | **nenhum** (temos `$chatwoot.isOpen` como propriedade, não como API) |
| **Rodar gatilho / cenário de bot sob demanda** | Crisp (`trigger:run`, `bot:scenario:run`) | **nenhum** |
| **Rastrear evento de negócio** | Crisp (`set session:event`), Intercom (`trackEvent`), Tidio (`track`) | **nenhum** |
| **Abrir artigo do help center** | Crisp (`helpdesk:article:open`), Intercom (`showArticle`) | **nenhum** |
| **Reconfigurar em runtime** (cor, locale, posição, som, z-index) | Crisp (13 `config`) | parcial: `setLocale`, `setColorScheme` |
| **Fila de chamadas antes do boot** | Crisp (`window.$crisp = []`), Intercom (`i.q = []`), Tidio (`tidioChatApi.queue`) | **não** — chamar antes do `loaded` quebra |
| **`shutdown` / limpeza no logout** | Intercom (`shutdown`), Crisp (`session:reset`), JivoChat (`clearHistory`) | `reset()` (existe, mas depende do iframe montado) |

**A fila pré-boot é a lacuna mais barata de fechar e a que mais gera bug de integração.** Os três
grandes fazem a mesma coisa: `window.X = []` no snippet, e o bundle drena a fila quando carrega.

---

## 12. Diagramas

### 12.1 Máquina de estados — Crisp (a mais completa que medi)

```
                      ┌──────────────┐
   (a) load           │   AUSENTE    │
        │             └──────┬───────┘
        ▼                    │ l.js executa; checa UA, storage, WebSocket, innerWidth>=280
   ┌─────────────┐           │
   │  RECUSADO   │◄──────────┤ falha em qualquer checagem  → nada é injetado (silencioso)
   └─────────────┘           │
                             ▼ ok
                    ┌────────────────┐  polling 100ms, timeout 30s,
                    │  CARREGANDO    │  espera $__CRISP_INSTANCE.__init
                    │ (#crisp-loader)│  E getComputedStyle(#crisp-loader).display==='none'
                    └───────┬────────┘  ← o CSS chegando é o sinal de "pronto"
                            ▼
                    ┌────────────────┐  WS abre; session:create
                    │   CONECTANDO   │
                    └───┬────────┬───┘
          erro do svc   │        │ session:created {session_id}
     invalid_website_id │        ▼
                        │  ┌──────────────┐  session:join {expire:300000, storage, sync}
                        │  │   ENTRANDO   │
                        │  └──────┬───────┘
                        ▼         ▼ session:joined
              ┌──────────────┐  ┌─────────────────────────────┐
              │  ERROR MODE  │  │   PRONTO / FECHADO           │◄──┐
              │ issue:report │  │  launcher visível, WS vivo   │   │
              └──────────────┘  └──────┬──────────────────────┘   │
                                       │ (b) chat:open              │ chat:close
                                       ▼                            │
                       ┌────────────────────────────────┐          │
                       │  ABERTO                        │──────────┘
                       │  baixa chat_default_*.js (197KB)│
                       │  session:state {alert:{...}}    │
                       └───┬────────────────────────────┘
                           │ (c) message:send            [não medido — não enviei mensagem]
                           ▼
                       ┌────────────────────┐
                       │  CONVERSA ATIVA    │
                       └────────────────────┘

   Eixo ortogonal — ciclo de vida da aba (vale em QUALQUER estado acima):
      pagehide  → memoriza socket.connected/stream.connected e DESCONECTA os dois
      pageshow  → reconecta só os que estavam conectados
      offline   → socket fecha em ~223ms; NÃO tenta reconectar enquanto offline
      online    → reconecta após ~8s (delay 15s ± jitter 0,5); DRENA a fila de eventos
      pushState/replaceState → evento crisp-pushstate → Session._sendDevice()
```

### 12.2 Sequência — Intercom, os dois transportes

```
 navegador            widget.intercom.io        api-iam.intercom.io      nexus-ws        ably-ws
    │                        │                          │                   │              │
(a) │──GET /widget/<appId>──►│                          │                   │              │
    │◄──loader + config──────│                          │                   │              │
    │──GET frame-modern.js, vendor-modern.js───────────►│                   │              │
    │──POST /messenger/web/launcher_settings───────────►│                   │              │
    │◄──{alignment,color,padding,theme_mode,ai_suggestions[3]}──────────────│              │
    │──POST /messenger/web/ping────────────────────────►│                   │              │
    │◄──{app, user{anonymous_id,country_code}, client_matches[15 rulesets]}─│              │
    │────────────── ABRE WS ────────────────────────────────────────────────►│              │
    │──nx.Subscribe {topics:["*"]}, nx.UserPresence{current_page}───────────►│              │
    │                                                   │                   │              │
    │  [cliente avalia os 15 predicados localmente]      │                   │              │
    │──POST /rulesets/58118832/match───────────────────►│                   │              │
    │◄──{custom_bot: conversa completa, header, composer_state}─────────────│              │
    │◄────────────── NewComment (mesmo evento, via push) ───────────────────│              │
    │                                                   │                   │              │
(b) │──POST /messenger/web/open ───────────────────────►│                   │              │
    │──POST /rtm/connect ──────────────────────────────►│                   │              │
    │──POST /home | /conversations | /help_center_content | /news (paralelo)►│              │
    │──POST /rtm/authorize ────────────────────────────►│                   │              │
    │◄──JWT {exp: iat+3600, x-ably-capability:{"uc:<app>:<user>":["subscribe"]}}            │
    │──────────────────── ABRE WS (Ably) ───────────────────────────────────────────────────►│
    │◄──action:4 CONNECTED {maxMessageSize:262144, maxInboundRate:50}───────────────────────│
    │──action:10 ATTACH {channel:"uc:<app>:<user>"}────────────────────────────────────────►│
    │◄──action:11 ATTACHED {channelSerial, flags:786432}────────────────────────────────────│
    │◄──action:0 (heartbeat) ───────────────────────────────────────────────────────────────│
```

### 12.3 Máquina do fluxo — Leadster

```
   servidor                                cliente
      │
      │  POST /scripts/search?host&path&query   (a)
      ├────────────────────────────────────────►
      │  { script:[24 passos], triggerSettings, cores, waitTime:7000 }
      │
      │                            ┌─────────────────────────────────┐
      │                            │  step = 0                        │
      │                            │  data  = {}                      │
      │                            └───────────────┬─────────────────┘
      │                                            │
      │   ┌────────────────────────────────────────┴──────────────────────────┐
      │   │  LOOP DO CLIENTE (o servidor não participa)                       │
      │   │                                                                    │
      │   │   script[step] tem…                                                │
      │   │     "say"            → renderiza HTML, interpola {{campo}}          │
      │   │                        a partir de data, step++                     │
      │   │     "from"           → renderiza opções; ao clicar:                 │
      │   │                        data[save] = opção            [MEDIDO]        │
      │   │                        step++                        [MEDIDO]        │
      │   │                        (o campo option_scores existe [MEDIDO]; que    │
      │   │                         ele acumule num score é [INFERÊNCIA] — não    │
      │   │                         cheguei a um passo pontuado no meu percurso)  │
      │   │     "save"+"type"    → renderiza input (com "mask" se houver),       │
      │   │                        valida por type, data[save] = valor, step++   │
      │   │     "if"             → avalia conditions contra data                 │
      │   │                        casou  → executa "then" (que é UM passo)      │
      │   │                        não    → pula                                 │
      │   │                        finish_flow → encerra | reject_lead → descarta│
      │   │     "api"            → chama window[api.function](api.data, cb)      │
      │   │                                                                      │
      │   │   a cada transição: POST /api/chatbot/events {"event":"step_N"}       │
      │   │                     → 200 {}   (telemetria pura; NÃO altera o fluxo)  │
      │   └──────────────────────────────────────────────────────────────────────┘
      │
      │   campos com prefixo "nosync::" nunca sobem
      │   handoff (d) → só então abre wss://atendimento.leadster.com.br/cable
      │                 {command:"subscribe", identifier:{channel:"RoomChannel", pubsub_token}}
      │                 retry: 5 tentativas, delay FIXO 1000ms, sem backoff, sem jitter
```

---

## 13. Tabela comparativa de decisões de arquitetura

| Decisão | Leadster | Crisp | Intercom | JivoChat | Tidio | Zendesk | HubSpot | **ChatSPX hoje** |
|---|---|---|---|---|---|---|---|---|
| Isolamento | DOM direto | DOM direto | iframe | `<jdiv>` + iframe | iframe | iframe | iframe | **iframe** |
| WS em (a) | não | **sim** | **sim** | **sim** | **sim** | não | não | não |
| WS em (b) | não | (já aberto) | **sim (2º)** | (já aberto) | (já aberto) | não | não | **sim** |
| Protocolo | REST + ActionCable em (d) | socket.io v4 | Nexus + Ably | texto `\t`/`\n` | socket.io v4 | REST | REST | ActionCable |
| Heartbeat | — | servidor 25 s | cliente ~52 s | cliente 20 s (`"."`) | 25 s (anunciado) | — | — | presence 60 s + jitter 5 s |
| Backoff | 5×, fixo 1 s | 15 s→60 s, 5×, jitter .5 | não medido | 2→32 s + jitter, 3 falhas, **tabela por motivo** | não medido | — | — | 1 s→30 s exp, jitter 500 ms, ilimitado |
| Watchdog de silêncio | não | não | não | **30 s** | não | — | — | timer de 25 s existe, **mas é inerte no widget** (§15.1 D3) |
| Ciclo de aba | — | `pagehide`/`pageshow` | não medido | `visibilitychange`+`focus`+`blur` do **parent** | não medido | — | — | `visibilitychange`+`focus`+`pageshow(persisted)` |
| Gap-fill ao reconectar | — | re-`session:join` | não medido | não medido | — | — | — | **`syncLatestMessages()`** |
| Fila offline | `dataQueue` (não provado) | **sim (medido)** | não medido | não medido | não medido | — | — | **não** |
| Idempotência de request | não | não | **`Idempotency-Key` por request** | não | não | — | — | **não** |
| SPA | não medido | **patch de `pushState`/`replaceState` + restauração** | não medido | não medido | não medido | — | — | Turbo/Turbolinks/Astro |
| Multi-aba | não medido | N sockets, sem eleição | não medido | não medido | não medido | **`tabs.count`** | não medido | N sockets `[INFERÊNCIA]` |
| Valida domínio | não medido | **sim (servidor)** | **sim (servidor)** | **não** | inconclusivo | não medido | não medido | `[NÃO VERIFICADO]` |
| Telemetria de erro | não observado | **pelo WS** | Sentry | `err.jivosite.com` | Sentry | não medido | `exceptions.hubspot.com` | **não tem** |
| Storage bloqueado | não medido | **não carrega (limpo)** | não medido | **`pageerror` + falha** | não medido | não medido | não medido | não medido |
| Code splitting (a)/(b) | não | **sim (344 KB / 197 KB)** | sim | **sim** (`chatcontainer.js`) | sim | sim | **sim** | **não** |
| i18n sob demanda | não | **sim** (`en_default_*.js`) | não medido | **sim** (`locale-pt-BR-json.js`) | não medido | sim (2 locales) | **sim** (3 arquivos) | não |
| Config em 1st party | não | não | não | não | **sim** (`/api/chat-widget-config`) | **sim** (`<sub>.zendesk.com/embeddable/config`) | **sim** (`/_hcms/livechat/widget`) | não |
| Fila pré-boot da API | — | **sim** (`$crisp=[]`) | **sim** (`i.q=[]`) | não medido | **sim** (`queue`) | sim (`zE` fila) | sim | **não** |
| Métodos públicos | ~0 | ~60 | 19 | 26 | 21 | — | — | **13** |
| Eventos públicos | 0 | 15 | 4 | 2 | ~9 | — | — | **7** |

---

## 14. Handoff bot → humano

O que consegui medir, e o que não:

| Fornecedor | O que muda no handoff | Como sei |
|---|---|---|
| **Leadster** | **Troca de transporte**: sai do REST puro e abre `wss://atendimento.leadster.com.br/cable`, canal `RoomChannel` com `pubsub_token` — que é **ActionCable do Chatwoot**. Retry de 5 tentativas com delay fixo de 1 s. | `[LIDO-BUNDLE]` `neurolead.min.js` offset ~317620. **Não abre em (a), (b) nem no início de (c)** — 0 WebSockets medidos nessas fases. |
| **Intercom** | Sem troca de transporte — o Ably já está aberto desde (b). O que muda é o conteúdo: `last_participating_admin` deixa de ser `{first_name:"Fin", is_bot:true}`. | `[MEDIDO]` no corpo de `/rulesets/<id>/match`; a transição em si é `[NÃO VERIFICADO]`. |
| **Crisp** | `session:joined` já traz `users_available`, `count_operators: 29`, `active_operators[]` com avatares e `response_metrics {count, last, mean}` desde (a). | `[MEDIDO]` — a *disponibilidade humana* é conhecida no load, antes de qualquer bot. |
| **JivoChat** | Telemetria carrega `chat_mode: "offline"`. | `[MEDIDO]` no POST `telemetry.jivosite.com/w`. |
| **HubSpot** | `bots/public/bot/6215392/welcomeMessages` é buscado em (a); a transição é `[NÃO VERIFICADO]`. | — |

**O que ninguém me deixou medir sem enviar mensagem:** fila de espera, mensagem de fora de horário,
tempo de espera exibido. `[NÃO VERIFICADO]` — precisaria de uma conta de teste própria em cada
produto, o que está fora do escopo desta task.

Uma peça relevante `[MEDIDO]`: o `ping` do Intercom devolve
`expected_response_delay_translation_key: "a_day"`,
`launcher_expected_response_delay_translation_key: "the_team_typically_replies_in_day"`,
`localized_expected_response_delay_short_text: "Within a day"` e
`..._long_text: "We typically reply within a day"`. **A expectativa de resposta vem pronta e
localizada do servidor, em quatro variantes** (chave + chave do launcher + texto curto + texto
longo). Nós montamos isso no cliente.

---

## 15. O QUE ISSO SIGNIFICA PARA O REDESENHO DO CHATSPX

Recomendações, sem código de implementação. Cada uma aponta a evidência que a sustenta.

### 15.1 Decisões de transporte

**D1 — Abrir o WebSocket em (a), não em (b). Recomendado: SIM, com condição.**
Crisp, Intercom, JivoChat e Tidio abrem em (a). Nós só abrimos quando o iframe monta o widget.
O ganho é a mensagem proativa chegar em tempo real e o "está online" ser verdadeiro no primeiro
segundo. A condição: **o iframe pesado não deve ser a porta de entrada do socket**. Separar
"conector de presença" (leve, em (a)) de "aplicação de chat" (pesada, em (b)) é o desenho do Crisp
e é o que eu recomendo. Sem isso, abrir em (a) significa carregar o widget inteiro em (a) — piora
tudo.

**D2 — Backoff: manter o nosso, adicionar a tabela por motivo. Recomendado: SIM.**
Nosso backoff (1 s → 30 s exponencial, jitter 500 ms, tentativas ilimitadas) é **melhor para o
usuário** que o do Crisp (15 s → 60 s, 5 tentativas). O que nos falta é o mecanismo do JivoChat:
**deixar o servidor ditar o tempo de espera pelo `close reason`**. Num incidente, hoje a nossa
frota inteira martela em 1 s. Uma tabela mínima (`"Try Again Later"` → 10–20 min,
`"Service Restart"` → 1–11 min) dá ao backend uma válvula que hoje não existe.

**D3 — Watchdog de silêncio: temos o timer, mas ele é inerte no widget. Recomendado: ativar.**
`STALE_CHECK_INTERVAL=15000` / `STALE_EVENT_THRESHOLD=25000` em
`app/javascript/shared/helpers/BaseActionCableConnector.js:120-138` é o equivalente ao
`f = setTimeout(y, o)` de 30 s do JivoChat — **mas a ação depende de `window.reconnectService`**:

```js
if (isTabVisible && isStale && window.reconnectService) {
  window.reconnectService.handleRouteSpecificFetch?.();
  this.lastEventReceivedAt = Date.now();
}
```

`[MEDIDO — leitura do nosso código]` `window.reconnectService` **existe no dashboard e não existe no
widget** (o próprio comentário no `handleReturnToForeground` diz "No-op no widget"). Ou seja: o
timer roda a cada 15 s dentro do widget e **não faz nada**. Um socket silenciosamente morto no
widget do visitante hoje só se resolve quando o `disconnected` do ActionCable dispara — e se ele não
disparar, não se resolve. Corrigir isso é barato: dar ao widget o seu próprio *refetch* de mensagens
para o watchdog chamar. Essa é a recomendação mais concreta da seção.

**D4 — Ciclo de aba: manter a nossa abordagem, não copiar o Crisp.**
O Crisp desconecta no `pagehide` e reconecta no `pageshow`. Nós reabrimos no
`visibilitychange` + `focus` + `pageshow(persisted)` (commit F0 "sempre conectado"). A nossa
abordagem entrega mensagem mais rápido ao voltar; a deles economiza conexão. Para um produto onde
o agente responde durante a sessão, **a nossa está certa**. Manter.

**D5 — Gap-fill: já temos, e é diferencial.**
`onReconnect → syncLatestMessages()` (`app/javascript/widget/helpers/actionCable.js:37-46`).
Não vi equivalente explícito em nenhum concorrente medido. Manter e documentar.

### 15.2 Decisões de bootstrap

**D6 — Code splitting por momento. Recomendado: SIM. Maior ganho isolado disponível.**
O Crisp baixa 344 KB em (a) e adia 197 KB (o bundle de chat) para (b). O JivoChat adia o
`chatcontainer.js`. Nós baixamos **o widget inteiro** quando o iframe monta. Dividir em
"presença/launcher" e "conversa" é a mudança de maior impacto percebido nesta lista.

**D7 — i18n sob demanda. Recomendado: SIM.**
Crisp (`en_default_*.js`), JivoChat (`locale-pt-BR-json.js`) e HubSpot (3 arquivos pt-br) carregam
só o idioma necessário. Considerando que a nossa prioridade é pt-BR mas o produto é multi-idioma,
embarcar todos os locales no bundle principal é peso puro.

**D8 — Cache do endpoint de configuração com chave horária. Recomendado: SIM.**
O `prelude/?2026-7-11-18-41` do Crisp (`max-age=14400`) é a ideia mais barata e mais esperta que
medi: URL determinística por hora → um objeto quente no CDN para todos os visitantes daquela hora,
propagação máxima de 1 h. Custo de implementação: baixo. Ganho: elimina um round-trip não cacheável
do caminho crítico.

**D9 — Servir a configuração em 1st party. Recomendado: AVALIAR.**
Tidio (`/api/chat-widget-config`), Zendesk (`<sub>.zendesk.com/embeddable/config`) e HubSpot
(`/_hcms/livechat/widget`) servem config pelo domínio do host/cliente. Isso sobrevive a bloqueadores
de terceiros. Para nós exigiria um proxy no site do cliente — só faz sentido para contas grandes.
Registrar como opção, não como padrão.

### 15.3 Decisões de fluxo conversacional

**D10 — Adotar o modelo declarativo do Leadster, com três correções. Recomendado: SIM.**
O schema deles (§3) é bom e está provado em produção. O que copiar:
- passos como array com cursor inteiro; `save` nomeando a variável;
- inputs tipados com `type` + `mask`;
- interpolação `{{campo}}`;
- `option_scores` para qualificação;
- `finish_flow` / `reject_lead` como propriedades do condicional;
- versionamento por passo (`version_key`/`version_date`/`version_hash`);
- prefixo `nosync::` para campos que não trafegam;
- **disparo de conversão como passo do fluxo**, com pixel do navegador e CAPI server-side.

As três correções que eu faria:
1. **`if` deve envolver um bloco, não um passo.** O modelo deles obriga a duplicar o condicional
   para escrever if/else (medi 6 condicionais para 2 bifurcações reais). Isso não escala.
2. **`say` não deveria ser HTML cru.** Eles entregam `<p class="p1">…` com entidades. Num widget
   sem iframe (o deles), isso é injeção de HTML de terceiro no DOM do cliente. Usar um formato
   restrito (markdown limitado ou AST) é mais seguro e mais fácil de estilizar.
3. **A decisão 100% no cliente impede mudar o fluxo no meio.** O Intercom mostra o meio-termo:
   servidor manda regras, cliente avalia, e o cliente **materializa no servidor** quando casa
   (`/rulesets/<id>/match`). Recomendo o modelo do Intercom para *segmentação* e o do Leadster para
   *execução do fluxo*.

**D11 — Gatilhos: adotar as sete classes do Leadster, com config por dispositivo e cooldown.**
`screen_time`, `inactivity_time`, `page_scroll`, `page_click`, `page_access`, `cursor_outside`
(exit intent), `clicked_at` (seletor CSS) — **cada um com valores separados para desktop e mobile,
`cooldownPeriod` e `openMode`**. Nossa campanha atual não tem nada disso. E o gatilho por seletor
CSS do site host (`pointer_selector` do Intercom / `clicked_at` do Leadster) é a ponte entre o CMS
do cliente e o chat, sem código no site.

### 15.4 Decisões de API pública

**D12 — Fila pré-boot. Recomendado: SIM. É a lacuna mais barata.**
`window.$crisp = []`, `Intercom.q = []`, `tidioChatApi.queue`. Hoje, chamar `$chatwoot.setUser()`
antes do `chatwoot:ready` simplesmente perde a chamada. Isso gera bug de integração em todo cliente
que usa GTM.

**D13 — Fechar as cinco lacunas de API que aparecem em 3+ concorrentes:**
enviar mensagem programaticamente; ler contagem de não lidas; consultar estado
(`isOpen`/`isAvailable` como método); rastrear evento de negócio; abrir artigo do help center.

**D14 — Idempotency-Key por request. Recomendado: SIM.**
Todo POST do Intercom carrega `Idempotency-Key=<hex16>`. Nós não temos nada equivalente — um retry
de rede duplica mensagem. Custo baixo, elimina uma classe inteira de bug.

### 15.5 Decisões de robustez e segurança

**D15 — Detectar storage indisponível por escrita real, e degradar em silêncio.**
O `ut()` do Crisp escreve e relê `crisp-client/loader/storage/check`. O JivoChat só testa a
existência — e estoura `pageerror` no site do cliente. Nós usamos cookie, então o modo de falha é
diferente, mas o princípio vale: **testar de verdade e nunca vazar exceção para o `window.onerror`
do site host**.

**D16 — Telemetria de erro do widget. Recomendado: SIM.**
Todos os cinco fornecedores que consegui medir têm. Nós não temos nada. Já rodamos GlitchTip na
frota — o widget é o único componente sem observabilidade. O padrão do Crisp (reportar pelo próprio
WebSocket) contorna CSP do site host e não adiciona domínio novo.

**D17 — Validar domínio no servidor. Recomendado: SIM, e verificar o estado atual com urgência.**
Crisp responde `invalid_website_id`; Intercom responde
`403 "This domain has not been trusted for the Intercom app defined in the JavaScript snippet."`.
JivoChat não valida e eu **registrei um visitante falso no painel deles a partir de `127.0.0.1`**.
Precisamos saber em qual dos dois grupos estamos. Copiar o desenho do Intercom: **liberar a config
visual, bloquear a criação de sessão** — assim o widget não "quebra feio" numa staging esquecida,
mas também não cria dado.

**D18 — Validar `event.origin` no `window.onmessage` do SDK.**
`app/javascript/sdk/IFrameHelper.js:100-114` aceita mensagem de qualquer origem que comece com
`chatwoot-widget:`, e o handler inclui `setAuthCookie`. Já enviamos com `targetOrigin` correto;
falta o lado do recebimento. Não é escopo desta task corrigir — é escopo apontar.

**D19 — SPA: trocar a cobertura por framework pela cobertura por primitivo.**
Cobrimos Turbo, Turbolinks e Astro nominalmente. O Crisp faz patch de `pushState`/`replaceState`
com guardas de tipo **e restaura os originais na desmontagem** — funciona em React Router, Vue
Router, SvelteKit, Next, htmx e no que vier. Manter os handlers de framework como reforço, adicionar
o primitivo como base.

### 15.6 O que NÃO copiar

| Não copiar | Por quê |
|---|---|
| **Bloquear Lighthouse/GTmetrix por UA** (Crisp) | Esconder o custo do widget da auditoria do cliente é enganoso. Se o widget é leve, ele aguenta a auditoria. |
| **`postMessage(…, "*")` sem checar origin** (Leadster) | Vaza os dados do lead para qualquer parent frame. |
| **Bundle de 1,53 MB em (a)** (JivoChat) | 4,5× o Crisp em (a), 53× o nosso `sdk.js`. |
| **`/latest/` sem versão pinada** (Zendesk) | O bundle muda sob os pés do site do cliente, sem janela de teste. |
| **Enfileirar eventos de UI efêmeros na fila offline** (Crisp) | Os três `message:compose:send` saíram juntos em 1 ms, 20 s depois do fato. Fila offline deve carregar **intenções** (mensagem enviada), não **estados transitórios** (digitando). |
| **Widget sem iframe** (Leadster) | 31 elementos `.nld-*` no DOM do host, expostos ao CSS do cliente. A nossa escolha de iframe está certa; a task 11 tem os números visuais. |

---

## 16. Buracos declarados (o que esta task NÃO estabeleceu)

Lista explícita, para não virar suposição de ninguém depois:

1. **Momento (c) — primeira mensagem** — medido apenas no Leadster (clique em opção de fluxo).
   Nos outros seis, não enviei mensagem. Transporte, payload e ACK da primeira mensagem em Crisp,
   Intercom, JivoChat, Tidio, Zendesk e HubSpot: `[NÃO VERIFICADO]`.
2. **Momento (d) — handoff** — inferido do bundle no Leadster; não observado em nenhum fornecedor.
3. **Comportamento sob CSP restritiva do site host** — não testado em ninguém.
4. **Aba anônima** — não testado diretamente.
5. **Multi-aba** — medido só em Crisp e Zendesk.
5b. **Segunda visita / retomada** — medida só no Crisp (§8.3), e com histórico vazio, porque não
    enviei mensagem. Nos outros seis fornecedores: `[NÃO VERIFICADO]`.
6. **Cliengo** — não localizei instalação pública ativa.
7. **Causa do disconnect imediato do Tidio** (`41` 160 ms após `connected`) — desconhecida.
8. **Cadência de avaliação dos `client_matches` do Intercom** — o predicado dizia
   `time_on_page eq 10` e o `/match` saiu em t=47,1 s. Mecanismo não determinado.
9. **Validação de domínio do ChatSPX** — não testada nesta task.
10. **Multi-aba do ChatSPX** — inferida por construção, não medida.
11. **Aba em segundo plano de verdade** — duas tentativas falharam (§9.3). O que sei sobre esse
    cenário vem de leitura de bundle, não de observação. Exige Chromium com interface gráfica.
12. **CSP restritiva** — não testada em nenhum fornecedor (§7.4).

---

## 17. Artefatos e evidências

### 17.1 Capturas referenciadas neste documento

Todas em `plano/estudo-chat-web/frontend/shots/`:

| Arquivo | O que mostra |
|---|---|
| `leadster-fluxo-passo0-desktop.png` | Leadster em (a): painel já aberto, 420×370 em (996,482) |
| `leadster-fluxo-passo1-apos-opcao-desktop.png` | Leadster após clicar "Sim, começar agora": `step=1`, novas opções |
| `crisp-painel-aberto-desktop.png` | Crisp em (b), painel aberto |
| `crisp-offline-11s-desktop.png` | Crisp com a rede cortada, texto digitado no compositor |
| `crisp-reconectado-desktop.png` | Crisp após religar a rede e drenar a fila |
| `crisp-localhost-dominio-rejeitado-desktop.png` | Crisp em `127.0.0.1`: launcher monta, sessão recusada (`invalid_website_id`) |
| `intercom-messenger-aberto-desktop.png` | Intercom em (b), com a conversa proativa do Fin |
| `intercom-localhost-dominio-nao-confiavel-desktop.png` | Intercom em `127.0.0.1`: 403 "domain has not been trusted" |
| `jivochat-painel-aberto-desktop.png` | JivoChat em (b) |
| `jivochat-localhost-sem-validacao-dominio-desktop.png` | JivoChat em `127.0.0.1`: **funcionou**, visitante registrado |
| `hubspot-widget-aberto-desktop.png` | HubSpot em (b) |
| `tidio-launcher-load-desktop.png` | Tidio em (a) |

### 17.2 Como reproduzir

O JSON de fluxo do Leadster foi capturado assim (o harness completo está descrito em §0.3):

```python
# fase A, interceptando o corpo da resposta
page.on('response', lambda r: bodies.append(r.text())
        if 'app.leadster.com.br/api/chatbot/scripts/search' in r.url else None)
```

Os bundles foram baixados com:

```bash
curl -s -o crisp_client.js https://client.crisp.chat/static/javascripts/client_default_4ea1f89.js
curl -s -o jivo_bundle.js  https://code-jvs1.jivosite.com/js/bundle.js
curl -s -o neurolead.js    https://cdn.leadster.com.br/neurolead/neurolead.min.js
curl -s -o tidio_widget.js https://code.tidio.co/widget-v4/1_451_0/static/js/widget.7d99179aad9dc45f4425.js
```

O teste de validação de domínio: servidor local (`python3 -m http.server 8917`) com os snippets
oficiais de instalação e os IDs públicos observados nos sites dos próprios fornecedores
(`-JzqEmX56venQuQw4YV8`, `tx2p130c`, `gw2zYi08MM`, `w0i4b7fdeerfqqn4w8lwb7ahjasjnrmd`).

O teste de storage bloqueado, via `add_init_script`:

```js
const bloq = () => { throw new DOMException('Access denied','SecurityError'); };
Object.defineProperty(window, 'localStorage',   {get: bloq, configurable: true});
Object.defineProperty(window, 'sessionStorage', {get: bloq, configurable: true});
Object.defineProperty(document, 'cookie', {get: () => '', set: () => {}, configurable: true});
```

---

*Documento produzido em 11/08/2026. Nenhum arquivo de código do repositório foi alterado.
Nenhuma mensagem foi enviada a nenhum chat de terceiro. Nenhum dado pessoal foi digitado em
nenhum formulário.*
