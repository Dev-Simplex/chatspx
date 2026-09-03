# TASK 02 — Leadster: dissecação técnica do widget web

> **Escopo:** engenharia reversa **não invasiva** do widget de chat da Leadster a partir de
> assets públicos (CDN, bundles, plugin WordPress open source, documentação oficial, HTML de
> sites em produção).
> **Data da coleta:** 11/08/2026.
> **Versão do widget analisada:** `clientVersion() === "2.67.0"`, arquivo publicado em
> `2026-07-31T12:08:32Z` (header `last-modified`).
> **Nada foi modificado no repositório ChatSPX.** Os arquivos locais
> `app/javascript/sdk/sdk.js` e `app/javascript/sdk/IFrameHelper.js` foram abertos em
> **modo leitura** apenas para a comparação da seção 12.

---

## 0. Convenções deste documento

| Marcador | Significado |
|---|---|
| **[FATO]** | Observado diretamente. O comando ou a URL usada está citado junto. Reprodutível. |
| **[INFERÊNCIA]** | Leitura/dedução minha a partir do código ou dos dados. Pode estar errada. |
| **[NÃO VERIFICADO]** | Não consegui confirmar. Registrado como lacuna, sem chute. |

Nenhum número, endpoint, evento, preço ou nome de chave neste documento foi inventado. Onde
não houve confirmação, está escrito "não verificado".

**Limite metodológico importante:** toda a análise é **estática** (leitura de bundles + requisições
`curl` pontuais). Não executei o widget num navegador real com DevTools. Portanto, a ordem exata
e o *timing* dos requests em runtime, métricas de campo de LCP/INP/CLS e o comportamento visual
são **inferências a partir do código**, não medições. Isso está sinalizado em cada seção.

**Limite ético auto-imposto:** identifiquei uma superfície onde seria possível injetar dados em
contas de clientes reais da Leadster (seção 11.2). **Não exercitei essa superfície.** Testei
apenas a leitura de configuração pública, que é exatamente o que qualquer navegador visitando
o site do cliente já faz. Também não baixei os artefatos do bucket que contêm dados de clientes
(seção 11.4).

---

## 1. Sumário executivo

O que mais importa, em ordem de impacto para o ChatSPX:

1. **[FATO] A Leadster usa Chatwoot como backend de atendimento humano.** O widget abre um
   WebSocket para `wss://atendimento.leadster.com.br/cable` assinando `RoomChannel` com
   `pubsub_token`, e consome os eventos `message.created`, `conversation.typing_on/off`,
   `conversation.updated`, `conversation.status_changed`. O host responde com o cookie
   `_chatwoot_session` e a API reporta `{"version":"4.5.2"}`. **Isto é o achado central da
   task:** o maior player brasileiro de chat de site construiu um widget proprietário de
   captura de lead **por cima da mesma base que nós já temos**.

2. **[FATO] O widget deles não é iframe e não é Shadow DOM.** É uma `div` injetada direto no
   DOM do site do cliente, estilizada por um `<style>` global no `<head>` com `all: initial`
   no container e **239 declarações `!important`**. Trocaram isolamento por controle visual —
   e pagam o preço em vazamento de CSS nos dois sentidos.

3. **[FATO] O bundle é grande: 456.101 bytes brutos**, 134.576 gzip / 133.402 brotli, num único
   arquivo sem code splitting no caminho de entrada. Para comparação, o `sdk.js` do Chatwoot
   servido pelo próprio ambiente da Leadster tem **28.768 bytes** (9.494 gzip) — o loader da
   Leadster é **~16x maior** que o do Chatwoot, porque o Chatwoot empurra o peso para dentro
   do iframe e a Leadster não tem iframe para empurrar.

4. **[FATO] Não existe API pública documentada do widget para o site host.** Não há
   `window.neurolead.setUser(...)`, não há eventos `CustomEvent` no `window`. O event bus é
   **interno** (um `<div id="nld-event-bus">` oculto) e não é contrato público. O Chatwoot,
   nesse ponto, é **muito superior**: expõe `window.$chatwoot` com 15+ métodos e 7 eventos de
   `window`. Este é um ponto onde **nós já ganhamos deles**.

5. **[FATO] Não há validação de domínio no bootstrap.** Pedi a configuração do chatbot de um
   cliente real passando `host=site-invasor-exemplo.com` e `Origin:` de outro domínio: o
   servidor devolveu **HTTP 200 com o fluxo completo** e emitiu um `cors-token` válido
   carimbado com o host forjado. `access-control-allow-origin: *`.

6. **[FATO] O widget instala o GA4 *da própria Leadster*** (`G-43W2WYML5H`) no site do
   cliente, via injeção de `googletagmanager.com/gtag/js`. Só não instala se o cliente definir
   `window.disableLeadsterGa4` — flag que **não encontrei documentada** em lugar nenhum.

7. **[FATO] Existe um segundo script**, `tracking/v1/leadster.min.js` (`window.ll`, v1.1.1,
   6.038 bytes), que persiste ~40 parâmetros de URL como cookies first-party `ll_*`, recria
   `_fbc`/`_gcl_aw` a partir de `fbclid`/`gclid` (contorno de ITP) e propaga cookies de
   rastreamento + `client_id`/`session_id` do GA4 como query params em links de saída para o
   WhatsApp. **É aqui que mora o diferencial competitivo real deles**: atribuição de lead
   ponta a ponta, não a UI do chat.

8. **[FATO] Acessibilidade é fraca.** No bundle inteiro: **1 ocorrência de `role`, 3 de
   `tabIndex`, 0 de `aria-*`**. Não há gestão de foco nem `aria-live`. É uma barra baixa que
   o ChatSPX pode superar com pouco esforço.

9. **[FATO] Em SPA, eles destroem e remontam o widget inteiro a cada troca de rota**
   (`elChatbot.remove()` → `delete window.neurolead` → novo bootstrap com novo fetch de
   configuração). **[INFERÊNCIA]** Isso descarta o estado da conversa em andamento.

10. **[FATO] O widget pisca o título da aba do site do cliente** com `"(1) Nova Mensagem!"` a
    cada 650 ms por até 60 s quando a aba está em segundo plano (classe `BlinkTitle`).

---

## 2. Metodologia e reprodutibilidade

### 2.1 Fontes primárias usadas

| # | Fonte | URL | O que deu |
|---|---|---|---|
| F1 | Plugin WordPress oficial (GPL v3) | `https://downloads.wordpress.org/plugin/leadster-marketing-conversacional.zip` | Snippet oficial exato, em código-fonte |
| F2 | Bundle de produção | `https://cdn.leadster.com.br/neurolead/neurolead.min.js` | Widget minificado, 456 KB |
| F3 | **Build de debug não minificado** | `https://cdn.leadster.com.br/neurolead/debug-production/neurolead.js` | 1.036.439 bytes, **com nomes de módulo e comentários originais** |
| F4 | Script de tracking | `https://cdn.leadster.com.br/neurolead/tracking/v1/leadster.min.js` | 6.038 bytes, legível |
| F5 | Sourcemap do tracking | `.../tracking/v1/leadster.min.js.map` | Nome do fonte: `tracking/leadster-tracking.js` |
| F6 | Listagem do bucket GCS | `https://cdn.leadster.com.br/` | Bucket `neuro-cdn` com listagem pública |
| F7 | Central de ajuda | `https://help.leadster.com.br/article/{25,36,37}` | Instruções oficiais de instalação |
| F8 | Endpoint de bootstrap | `https://app.leadster.com.br/api/chatbot/scripts/search` | Config real de um cliente + JWT |
| F9 | Backend de atendimento | `https://atendimento.leadster.com.br/api` | `{"version":"4.5.2"}` + `_chatwoot_session` |
| F10 | Site em produção (Wix) | `https://samakavision.wixsite.com/informatica` | Snippet colado, variante legada, ID numérico |
| F11 | Site em produção (SPA) | `https://procoach.decola.app` | Snippet colado, ID em formato token |
| F12 | Repositório local ChatSPX | `app/javascript/sdk/*` (leitura) | Base de comparação |

### 2.2 Comandos reprodutíveis

```bash
# F1 — snippet oficial
curl -sL https://downloads.wordpress.org/plugin/leadster-marketing-conversacional.zip -o l.zip
unzip -o l.zip && cat leadster-marketing-conversacional/views/script-code.php

# F2 — bundle + headers
curl -s -D headers.txt --compressed \
  https://cdn.leadster.com.br/neurolead/neurolead.min.js -o neurolead.min.js
wc -c neurolead.min.js && gzip -9 -c neurolead.min.js | wc -c

# F3 — build de debug (nomes originais)
curl -s --compressed \
  https://cdn.leadster.com.br/neurolead/debug-production/neurolead.js -o dbg.js

# F6 — listagem do bucket (exige User-Agent de navegador; sem UA o Cloudflare devolve 403)
curl -s -A "Mozilla/5.0 Chrome/126.0" https://cdn.leadster.com.br/

# F9 — identificação do backend de atendimento
curl -s https://atendimento.leadster.com.br/api
curl -sI https://atendimento.leadster.com.br/ | grep -i set-cookie
```

### 2.3 Como o build de debug foi lido

O arquivo `debug-production/neurolead.js` é um bundle webpack com `devtool: eval`: cada módulo
é uma string passada para `eval()`, preservando **nomes de arquivo, nomes de classe, nomes de
método e comentários originais**. Extraí os 199 módulos (83 sob `./src/`) com um parser que
localiza declarações no formato `"./src/x.js":(args)=>` e desescapa a string do `eval`.

Isso significa que boa parte dos trechos citados neste relatório é **código-fonte original da
Leadster**, não descompilação. O `neurolead.min.js` de produção **não** publica sourcemap
(`.map` → HTTP 404), mas o build de debug torna isso irrelevante.

---

## 3. Snippet de instalação

### 3.1 Snippet oficial atual — [FATO], fonte F1

Código exato, extraído de `views/script-code.php` do plugin WordPress oficial:

```php
<!--BEGIN LEADSTER SCRIPT-->
<script>
  (function (w, d, s, c) {
    try {
      var h = d.head || d.getElementsByTagName("head")[0];
      var e = d.createElement("script");

      e.setAttribute("src", s);
      e.setAttribute("charset", "UTF-8");
      e.defer = true;

      w.neuroleadId = c;
      h.appendChild(e);
    } catch (e) {}
  })(window,document,"https://cdn.leadster.com.br/neurolead/neurolead.min.js", "<?php echo esc_attr($leadster_script_code) ?>");
</script>
<!--END LEADSTER SCRIPT-->
```

Leitura técnica:

- **IIFE com 4 parâmetros injetados** (`window`, `document`, URL, ID). Padrão clássico para
  minimizar dependência de escopo global.
- **Todo o corpo dentro de `try/catch` vazio.** Se qualquer coisa falhar, falha em silêncio e
  o site do cliente não quebra. Decisão defensiva correta para script de terceiro.
- **Insere no `<head>`**, mesmo quando o snippet está no fim do `<body>`.
- **`defer = true`.** Como é um script criado dinamicamente, ele já seria assíncrono por
  padrão; `defer` num script injetado por `appendChild` **não** garante ordem em todos os
  navegadores. **[INFERÊNCIA]** O efeito prático aqui é aproximadamente `async`.
- **`charset="UTF-8"`** — atributo obsoleto no HTML5 para `<script>`, resíduo histórico.
- **A configuração inteira é uma única variável global: `window.neuroleadId`.** Não há objeto
  de settings, não há callbacks, não há opções.

### 3.2 Variante legada ainda em produção — [FATO], fonte F10

Do HTML de `https://samakavision.wixsite.com/informatica` (site Wix real):

```js
(function(n,r,l,d){try{var h=r.head||r.getElementsByTagName("head")[0],
s=r.createElement("script");s.defer=true;s.setAttribute("type","text/javascript");
s.setAttribute("src",l);n.neuroleadId=d;h.appendChild(s);}catch(e){}})(window,document,
"https://cdn.leadster.com.br/neurolead/neurolead.min.js", 68742);
```

Diferenças: nomes de parâmetro distintos (`n,r,l,d`), `type="text/javascript"` em vez de
`charset`, e **ID numérico** (`68742`) em vez de string.

### 3.3 Variante em SPA — [FATO], fonte F11

De `https://procoach.decola.app`:

```js
(function(a,b,c,d){try{var e=b.head||b.getElementsByTagName("head")[0];
var f=b.createElement("script");f.setAttribute("src",c);f.setAttribute("charset","UTF-8");
f.defer=true;a.neuroleadId=d;e.appendChild(f)}catch(g){}})(window,document,
"https://cdn.leadster.com.br/neurolead/neurolead.min.js","Jubg5SOZXaQt02lUOZizabGnK")
```

**Não há variante específica para SPA.** É o mesmo snippet. O suporte a SPA é feito
inteiramente do lado do bundle (seção 9.4).

### 3.4 Formato do identificador do cliente — [FATO]

Encontrei **dois formatos coexistindo em produção**:

| Formato | Exemplo | Origem observada |
|---|---|---|
| Inteiro | `68742` | F10 (Wix). O bundle contém `[4357,25611,11270].includes(window.neuroleadId)` — comparação numérica direta, confirmando IDs inteiros. |
| Token alfanumérico, 25 chars | `Jubg5SOZXaQt02lUOZizabGnK` | F11 (SPA) |

**[INFERÊNCIA]** O token opaco é o formato mais novo; o inteiro é legado e provavelmente é o
`companyId` cru. Note que na resposta de configuração o `companyId` aparece separado
(`"companyId": 157735`), ou seja, o token **não é** o companyId — é um identificador de
implantação que o servidor resolve. Isso é uma decisão de segurança **melhor** que expor ID
sequencial, mas, como mostra a seção 11.2, não é acompanhada de validação de origem, então o
ganho é apenas cosmético.

**[FATO]** Há também um caso especial no código: `this.disableServerCommunication = e < 0`,
onde `e` é o `neuroleadId`. Um ID **negativo** desliga toda a comunicação com o servidor.
**[INFERÊNCIA]** É o modo preview/demo usado pelo editor de fluxos deles.

### 3.5 Variantes de instalação documentadas — [FATO], fonte F7

Segundo `help.leadster.com.br/article/36-instrucoes-para-ativar-o-chat`, são **quatro** métodos
oficiais: WordPress, Google Tag Manager, Wix e HTML manual.

| Método | Detalhe oficial |
|---|---|
| **HTML manual** | "Com o código copiado, basta inseri-lo ao final do site **antes da tag `</body>`**". Justificativa oficial: "Dessa forma o nosso script é o último a ser carregado em seu site, sem afetar o tempo de carregamento da página." |
| **WordPress** | Plugin oficial. O hook é `add_action("wp_footer", "leadster_add_widget_to_footer")` — footer, coerente com o item acima. O ID é salvo na option `leadster-script-code`. |
| **Google Tag Manager** | Tag do tipo "HTML personalizado", acionador "All Pages". **A doc manda marcar a opção "Suporte para `document.write`".** |
| **Wix** | Artigo dedicado (`article/27`). Confirmado em produção pela F10. |

**Duas observações críticas sobre o GTM:**

1. **[FATO]** A instrução de marcar "Suporte para `document.write`" está na documentação
   oficial. **[INFERÊNCIA]** O snippet atual **não usa** `document.write` — usa
   `createElement` + `appendChild`. Ou a instrução é resíduo de uma versão antiga, ou é
   defensiva. Marcar essa opção sem necessidade é ruim: instrui o GTM a usar um caminho de
   injeção que pode bloquear o parser do HTML.

2. **[INFERÊNCIA]** Há uma contradição entre a doc do HTML manual ("antes de `</body>`, para
   não afetar o carregamento") e a realidade do snippet, que injeta o `<script>` no `<head>`.
   O ganho de colocar no footer é quase nulo, porque o `appendChild` no head acontece assim
   que o snippet roda.

**[NÃO VERIFICADO]:** não há documentação oficial pública de instalação em Next.js, React,
Vue, Shopify, VTEX ou Nuvemshop. As páginas do painel
(`app.leadster.com.br/implementation/our_code_tutorial` e `.../tag_manager_tutorial`) exigem
login e **não foram acessadas**.

---

## 4. Cadeia de carregamento

### 4.1 Diagrama textual — [FATO] para os passos, [INFERÊNCIA] para o timing

```
 [T0] Navegador faz parse do HTML do site do cliente
        │
        │  snippet inline (síncrono, ~350 bytes)
        ▼
      window.neuroleadId = "<ID>"
      document.head.appendChild(<script defer src="cdn.leadster.com.br/.../neurolead.min.js">)
        │
        │  REQUEST 1 ── GET cdn.leadster.com.br/neurolead/neurolead.min.js
        │               456.101 B brutos / 133.402 B brotli
        │               cache-control: public, max-age=43200 (12 h)
        │               access-control-allow-origin: *
        ▼
 [T1] Bundle executa. Registra 3 caminhos de boot (idempotentes via `if (window.neurolead) return`):
        window.addEventListener('load', boot)
        document.addEventListener('readystatechange', → se readyState==='complete', boot)
        se readyState já === 'complete' → boot() imediato
        │
        ▼
 [T2] boot()
        ├─ injeta <style> no <head> com o CSS do widget (style-loader do webpack)
        ├─ injeta o markup: <div class="nld-chatbot nld-nodisplay"> … </div>
        │     dentro dele: <div id="nld-event-bus">  (barramento interno, display:none)
        │     alvo: #nld-custom-container se existir, senão document.body
        ├─ gera/recupera identidade: localStorage["neuroleadUser"]
        ├─ instala o GA4 DA LEADSTER (G-43W2WYML5H) — a menos que window.disableLeadsterGa4
        │     │
        │     │  REQUEST 2 ── GET www.googletagmanager.com/gtag/js?id=G-43W2WYML5H
        │     ▼
        └─ dispara o evento interno "load"
              │
              │  REQUEST 3 ── POST app.leadster.com.br/api/chatbot/events   (XHR)
              ▼
 [T3] loadConversationScript()
        │  monta a URL de bootstrap com 7+ parâmetros
        │
        │  REQUEST 4 ── POST app.leadster.com.br/api/chatbot/scripts/search?company=…&user=…
        │               &time=…&path=…&host=…&query=…&platform=desktop|mobile
        │               [&script_id=…][&preferredVersions[k]=v]
        │               ← 200 JSON (~3,5 KB no caso medido)
        │               ← header  Cors-Token: <JWT HS256>
        ▼
 [T4] createFromJSON(config)
        ├─ this.corsToken = resposta.headers['cors-token']
        ├─ httpClient.setDefaultHeaders({'Cors-Token': corsToken})   ← todas as chamadas seguintes
        ├─ aplica cores, avatar, título, subtítulo, lado (right|left)
        ├─ persiste versão de A/B em localStorage["neuroleadsPreferredVersions"] se config.isAb
        ├─ setupClientGa4()   → REQUEST 5 (condicional): gtag/js?id=<GA4 do cliente>
        ├─ setupMetaPixel()   → REQUEST 6 (condicional): connect.facebook.net/en_US/fbevents.js
        │                                              + fbq('track','PageView')
        ├─ inicializa os 7 gatilhos de abertura (chatOpenTriggersManager)
        │
        │  REQUEST 7 ── GET cdn.leadster.com.br/neurolead/img/avatar/<n>.png  (avatar)
        ▼
 [T5] Widget visível (avatar + balão teaser após `waitTime`, 7000 ms no caso medido)
        │
        │  evento interno "show" → POST /api/chatbot/events
        ▼
 [T6] Usuário abre o chat  → evento "user_open" → POST /api/chatbot/events
        │
        ├─ a cada passo respondido → evento "step_<n>" → POST /api/chatbot/events
        │
        ├─ se o fluxo tem bloco de livechat:
        │     POST /api/chatbot/livechat/validate_available_time   (se useAvailableTime)
        │     POST /api/chatbot/livechat/validate_agent_online     (se checkAgentOnline)
        │     POST /api/chatbot/livechat/conversations             (cria contato+conversa)
        │        │
        │        ▼
        │     WEBSOCKET ── wss://atendimento.leadster.com.br/cable
        │                  {"command":"subscribe",
        │                   "identifier":"{\"channel\":\"RoomChannel\",\"pubsub_token\":\"…\"}"}
        │                  ← message.created / conversation.typing_on|off
        │                  ← conversation.updated / conversation.status_changed
        │
        └─ ao concluir → evento "finish" + sendSyncEvents() (GA4/Meta/Ads)
```

### 4.2 O endpoint de bootstrap, literal — [FATO], build de debug F3

```js
loadConversationScript() {
  if (window.neuroleadDefaultScript) return this.createFromJSON(window.neuroleadDefaultScript);
  let preferred = {};
  if (localStorage && localStorage.getItem) {
    const raw = localStorage.getItem("neuroleadsPreferredVersions");
    preferred = raw ? JSON.parse(raw) : {};
  }
  const url = (company, path, host, query, platform, user, versions = {}, scriptId = null) => {
    const u = new URL(`${BASE_URL_API}/scripts/search`);
    u.searchParams.append("company", company);
    u.searchParams.append("user", user);
    u.searchParams.append("time", new Date / 1e3 | 0);
    u.searchParams.append("path", encodeURIComponent(path));
    u.searchParams.append("host", encodeURIComponent(host));
    u.searchParams.append("query", encodeURIComponent(query));
    u.searchParams.append("platform", encodeURIComponent(platform));
    if (scriptId) u.searchParams.append("script_id", scriptId);
    Object.keys(versions).map(k =>
      u.searchParams.append(`preferredVersions[${encodeURIComponent(k)}]`,
                            encodeURIComponent(versions[k])));
    return u.href;
  }(window.neuroleadId, window.location.pathname, window.location.hostname || "localhost",
    window.location.search, isMobile() ? "mobile" : "desktop", this.userId, preferred,
    window.neuroleadPSId);
  this.loadConversation(url);
}
```

Pontos relevantes:

- **`path`, `host` e `query` da página vão para o servidor no bootstrap.** É assim que eles
  fazem segmentação de fluxo por URL e por UTM — o servidor decide **qual chatbot** entregar
  com base na página. Arquitetonicamente elegante: a regra de segmentação fica no servidor, o
  cliente só reporta contexto.
- **`window.location.search` inteiro é enviado**, incluindo quaisquer parâmetros sensíveis que
  o site do cliente use na URL. **[INFERÊNCIA]** É um risco de vazamento incidental de PII
  (ex.: um site que passa `?email=` na URL entrega esse e-mail à Leadster no bootstrap).
- **`preferredVersions`** é o mecanismo de "grude" do teste A/B: uma vez sorteada a variante,
  ela é persistida em `localStorage` e reenviada em todo bootstrap.

### 4.3 Base de URL escolhida em runtime — [FATO]

```js
const getBaseHost = () => {
  const secondLevel = () => {
    const parts = (arguments[0] ?? window.location.hostname).split(".");
    return parts.length > 1 ? parts[parts.length - 2] : parts[0];
  };
  return "getleadster" === secondLevel()
    ? "https://app.getleadster.com"
    : "https://app.leadster.com.br";
};
const BASE_URL_API = `${getBaseHost()}/api/chatbot`;
const CDN_BASE     = "https://cdn.leadster.com.br/neurolead";
```

**[INFERÊNCIA]** A escolha do backend depende do **domínio do site do cliente**, não de
configuração. Se o site do cliente for `qualquercoisa.getleadster.com`, o widget aponta para o
backend internacional. Como o `arguments[0]` da função interna nunca é passado nas chamadas
que encontrei, na prática isso lê sempre `window.location.hostname`. É um acoplamento frágil,
mas de baixo impacto real.

### 4.4 O bundle não faz code splitting no caminho de entrada — [FATO]

A listagem do bucket mostra que **existe** um diretório de chunks
(`neurolead/chunks/b641ce74f362b637f9e0352231a084983d565d50.js`, 95.328 bytes) e um chunk
nomeado no build de debug (`debug-production/chunks/ia-interaction-products-recommendation.js`,
238.892 bytes). **[INFERÊNCIA]** Há lazy loading, mas apenas para o módulo de recomendação de
produtos do ShopBot (e-commerce) — **não** para o núcleo do chat. Os 456 KB do bundle
principal são carregados sempre, em toda página, mesmo que o visitante nunca abra o chat.

---

## 5. Estratégia de renderização e isolamento de CSS

### 5.1 O veredito: DOM direto, sem iframe e sem Shadow DOM — [FATO]

Busca no bundle inteiro por `attachShadow`, `shadowRoot`, `createElement("iframe")` e
`<iframe`: **zero ocorrências**. O widget é injetado assim:

```js
(function inject(html, target) {
  const parent = target || document.body || document.getElementsByTagName("body")[0];
  let wrapper = document.createElement("div");
  wrapper.innerHTML = html;
  return parent.appendChild(wrapper.firstElementChild);
})(`
  <div class="nld-chatbot nld-nodisplay">
    <div id="nld-event-bus"></div>
    <div class="nld-backdrop nld-nodisplay"></div>
    <div class="nld-avatar nld-nodisplay nld-shown-slide">
      <div class="nld-chatbot-invite-container">
        …
        <span class="nld-footer nld-verified">Verificado pela Leadster</span>
        <span class="nld-footer nld-time"></span>
        <div class="nld-typing-indicator"><span></span><span></span><span></span></div>
      </div>
    </div>
    <div class="nld-conversation nld-hidden-slide nld-nodisplay">
      <div class="nld-brand-footer"></div>
      <div class="nld-bg">
        <div class="nld-conversation-header">
          <div class="nld-close"><img class="nld-close-white" src="\${closeButtonImage}" …></div>
          <div class="nld-infobar">
            <div class="nld-avatar"></div>
            <div class="nld-info">
              <div class="nld-title"></div>
              <div class="nld-subtitle"></div>
            </div>
          </div>
        </div>
        <div id="context" class="nld-ctx"></div>
      </div>
      <div class="nld-popup-container nld-nodisplay">
        <div class="nld-popup"></div>
      </div>
    </div>
  </div>
`, document.getElementById("nld-custom-container") || null);

window.neurolead = new Chatbot(el, neuroleadId);
```

Detalhe de arquitetura interessante: **se o site do cliente definir um
`<div id="nld-custom-container">`, o widget é montado ali dentro** em vez de no `<body>`.
É o único ponto de extensão que o host tem sobre o widget — e é um bom padrão, que vale copiar.

### 5.2 Como tentam isolar CSS — [FATO]

Três camadas, todas frágeis:

1. **`all: initial` no container raiz:**
   ```css
   .nld-chatbot {
     all: initial;
     font-size: initial;
     position: absolute;
     z-index: 9999999999;
     top: 0;
     left: 0;
   }
   ```
2. **Prefixo de namespace `nld-` em toda classe** (contei 80+ classes distintas).
3. **`!important` massivo: 239 declarações** no CSS do bundle.

Além disso usam **styled-components 5.3.11** (confirmado por `data-styled-version="5.3.11"` no
bundle), que gera classes com hash e injeta `<style>` adicionais no `<head>`.

### 5.3 Riscos reais de vazamento — [INFERÊNCIA] fundamentada

**Do site host para o widget:** `all: initial` reseta **apenas o elemento raiz** — não os
descendentes. Uma regra do site como `div { line-height: 2 }`, `* { box-sizing: border-box }`,
`img { max-width: 100% }` ou `button { border: none }` atinge o interior do widget em cheio. Os
239 `!important` são justamente a resposta a isso: força bruta em vez de isolamento. E
`!important` do host com especificidade maior ainda ganha.

> Nota de contexto para o ChatSPX: nós já vivemos exatamente esse problema no sentido inverso.
> Está registrado na memória do projeto que `_base.scss:286` aplica `border-none` a **todo**
> `<button>` do dashboard, sabotando bordas de componentes. É o mesmo mecanismo — CSS global
> catch-all vencendo o componente. A Leadster expõe o widget deles a essa classe de bug em
> **todo site de cliente**, que é um universo de CSS que eles não controlam.

**Do widget para o site host:** o CSS do widget é injetado no `<head>` **global**. Se qualquer
seletor não estiver prefixado, vaza. Encontrei ao menos um seletor não prefixado:

```css
.calendar-prev.disabled,
.calendar-next.disabled {
  cursor: not-allowed!important;
  pointer-events: none;
}
```

**[INFERÊNCIA]** Um site de cliente que tenha `.calendar-prev` ou `.calendar-next` (nomes
genéricos o suficiente para colidir) teria seu próprio componente quebrado pelo widget.

**`z-index: 9999999999`** — dez dígitos, acima do máximo prático. O Chatwoot usa `2147483000`
(perto do máximo de int32), o que é igualmente agressivo mas ao menos tem justificativa
numérica.

### 5.4 Efeitos colaterais no host que não são CSS — [FATO], achado importante

Este trecho está no construtor do widget:

```js
addEventListeners() {
  this.elCloseInvite.onclick = function (t) { … }.bind(this);
  this.elClose.onclick  = this.close.bind(this);
  this.elAvatar.onclick = this.toggle.bind(this);
  window.onresize       = this.onResize.bind(this);      // ← SOBRESCREVE
  document.onmouseup    = this.onMouseUp.bind(this);     // ← SOBRESCREVE
  window.onmousemove    = this.onMouseMove.bind(this);   // ← SOBRESCREVE
  document.addEventListener("focusin", this.onFocusInput.bind(this));
  …
}
```

**[FATO]** `window.onresize`, `document.onmouseup` e `window.onmousemove` são atribuídos com
`=`, não com `addEventListener`. **[INFERÊNCIA]** Isso **destrói silenciosamente** qualquer
handler que o site do cliente tenha registrado nessas mesmas propriedades. Um site que use
`window.onresize = recalcularLayout` perde o recálculo de layout no momento em que o widget da
Leadster monta. É um bug de convivência clássico, e sério, num script de terceiro.

Adicionalmente, o `history.pushState` e o `history.replaceState` do host são
**monkey-patched** (seção 9.4) — outra intrusão no ambiente do host.

---

## 6. Rede: endpoints, protocolos e domínios

### 6.1 Domínios envolvidos — [FATO]

| Domínio | Papel | Evidência |
|---|---|---|
| `cdn.leadster.com.br` | CDN de assets. Google Cloud Storage (bucket `neuro-cdn`) atrás de Cloudflare. | Headers `x-goog-generation`, `x-goog-storage-class: MULTI_REGIONAL`; `server: cloudflare` |
| `app.leadster.com.br` | API do chatbot (`/api/chatbot/*`). Hospedagem Cloud 66. | Header `x-powered-by: cloud66` |
| `app.getleadster.com` | Equivalente internacional | String no bundle + função `getBaseHost()` |
| `atendimento.leadster.com.br` | **Chatwoot** — atendimento humano (REST + ActionCable) | `_chatwoot_session`, `{"version":"4.5.2"}` |
| `www.googletagmanager.com` | gtag.js (GA4 da Leadster e do cliente) | `installGa4()` |
| `connect.facebook.net` | fbevents.js (Meta Pixel) | `insertMetaPixel()` |
| `shopbot.leadster.com.br` | Produto de e-commerce (ShopBot) | Link de rodapé condicional a `companySegment === "E-commerce"` |

### 6.2 Tabela de endpoints — [FATO], todos extraídos do bundle

Base: `https://app.leadster.com.br/api/chatbot`

| Método | Caminho | Função | Payload / params observados |
|---|---|---|---|
| POST | `/scripts/search` | **Bootstrap.** Resolve qual fluxo entregar. | Query: `company`, `user`, `time`, `path`, `host`, `query`, `platform`, `script_id?`, `preferredVersions[k]?` |
| POST | `/events` | Telemetria do widget (XHR direto, não axios) | `userId`, `sessionId`, `leadId`, `company`, `script`, `event`, `clientVersion`, `scriptVersion`, `time`, `devMode`, `isMobile`, `referrer`, `location` |
| POST | `/livechat/conversations` | Cria contato + conversa no Chatwoot | `...message`, `data`, `script`, `leadId`, `company` |
| POST | `/livechat/messages` | Envia mensagem do visitante | `...message`, `message`, `script`, `sourceId`, `conversationId`, `company` |
| POST | `/livechat/notes` | Nota interna (abandono / encerramento) | idem + `keepalive: true` via `fetch` |
| POST | `/livechat/validate_available_time` | Checa janela de atendimento | `...message`, `script`, `company` |
| POST | `/livechat/validate_agent_online` | Checa se há agente online | idem |
| POST | `/validate-url` | Valida URL informada pelo lead | `{url, company, script}` |
| GET | `/script-blocks/whatsapp-phone` | Escolhe número de WhatsApp (rodízio) | `script`, `script_version_id`, `block_uid`, `is_mobile`; `timeout: 3000 ms` |
| POST | `/whatsapp_tracking` | Rastreia clique para WhatsApp | `+ timestamp`, `block_uid`, `lead_id`, `user_id`, `script`, `script_version`, `company` |
| POST | `/marketing_event/block-events` | **Meta CAPI / GA4 Measurement Protocol server-side** | ver 10.3 |
| POST | `/analytics_field_blocks` | Evento de bloco analítico | `user_id`, `session_id`, … |
| POST | `/ai/conversation/sac_chatbot` | Turno de conversa com IA | — |
| PUT | `/ai/conversation/evaluate` | Avaliação 👍/👎 da resposta da IA | `{evaluation, lead_id, history_tracker_id, script}` |
| PUT | `/ai/history_tracker/{id}/evaluate` | Idem, base alternativa | `{evaluation}` |
| POST | `/ai/conversation/generate_public_link` | Link público do histórico da conversa com IA | — |
| GET | `/schedules/available-calendar` | Agenda: dias disponíveis | — |
| GET | `/schedules/available-representative` | Agenda: representante | — |
| POST | `/schedules` | Cria agendamento | — |
| — | `/qa_test` | Segmento de path do ambiente de QA do script de tracking | — |

Assets estáticos:

| URL | Bytes |
|---|---|
| `cdn.leadster.com.br/neurolead/neurolead.min.js` | 456.101 (133.402 br) |
| `cdn.leadster.com.br/neurolead/tracking/v1/leadster.min.js` | 6.038 (2.270 gzip) |
| `cdn.leadster.com.br/neurolead/img/avatar.png` | **123.277** |
| `cdn.leadster.com.br/neurolead/img/avatar/3.png` | 15.604 |
| `cdn.leadster.com.br/neurolead/img/wpp_logo.png` | 10.986 |
| `cdn.leadster.com.br/neurolead/img/restart_chat.png` | 777 |
| `cdn.leadster.com.br/leadster/state_cities.json` | 125.782 |

### 6.3 Cabeçalhos e CORS — [FATO]

Resposta real de `POST /api/chatbot/scripts/search` (comando na seção 11.2):

```
HTTP/2 200
content-type: application/json; charset=utf-8
cors-token: eyJhbGciOiJIUzI1NiJ9.eyJyYW5kb20iOiI2NmZkNzFlNjczOWJkNzNlYmEyNmE3OTRiYTNiMTIzMCIs…
cache-control: max-age=0, private, must-revalidate
access-control-allow-origin: *
vary: Origin
access-control-expose-headers: Cors-Token
access-control-max-age: 1728000
access-control-allow-methods: GET, PUT, POST, OPTIONS
content-security-policy: frame-ancestors 'self' https://*.gobots.com.br
x-powered-by: cloud66
x-runtime: 0.032199
```

Do CDN:

```
access-control-allow-origin: *
access-control-expose-headers: *
cache-control: public, max-age=43200
content-encoding: br
```

A política de CORS do bucket (`https://cdn.leadster.com.br/cors.json`, público):

```json
[
    {
        "origin": ["*"],
        "method": ["GET"],
        "maxAgeSeconds": 3000,
        "responseHeader": ["Authorization", "Content-Range", "Accept", "Content-Type", "Origin", "Range"]
    }
]
```

**[INFERÊNCIA]** O `content-security-policy: frame-ancestors 'self' https://*.gobots.com.br`
na API do chatbot indica integração/relação corporativa com a **GoBots** — o painel da
Leadster é embutido em iframe por eles. É um dado de negócio, não técnico, e não foi
investigado além disso.

### 6.4 O `Cors-Token` — [FATO]

É um **JWT HS256**. Payload decodificado (base64url do segmento 2) de uma resposta real:

```json
{
  "random": "66fd71e6739bd73eba26a794ba3b1230",
  "data": {
    "script_id": 204915,
    "host": "https://procoach.decola.app",
    "skip_validation": false
  },
  "exp": 1786492223,
  "timestamp": 1786477823
}
```

- **TTL = 14.400 s (4 horas)** (`exp - timestamp`).
- O token é devolvido em **header** (`Cors-Token`), exposto via
  `access-control-expose-headers`, e reenviado pelo cliente em **todas** as chamadas seguintes
  (`httpClient.setDefaultHeaders({'Cors-Token': token})`).
- Há uma flag `skip_validation` no payload — **[INFERÊNCIA]** provavelmente para contas
  internas/demo que ignoram checagem de host.
- **HTTP 401 em qualquer chamada faz o widget se fechar e esconder o avatar**:
  ```js
  xhr.onreadystatechange = () => {
    if (401 === xhr.status) return this.close(!0), void this.hideAvatar();
    …
  };
  ```

### 6.5 Protocolo do canal de mensagem — [FATO]

Há **dois regimes distintos**, e essa é uma decisão de arquitetura importante:

**Regime 1 — fluxo automatizado (o padrão): sem canal em tempo real.**
O fluxo inteiro vem no JSON do bootstrap. As perguntas, opções, máscaras e ramificações são
executadas **localmente no navegador**. Não há polling, não há SSE, não há WebSocket. O
servidor só recebe eventos de telemetria e a sincronização do lead. **É por isso que o chat
deles parece instantâneo:** não há round-trip por mensagem.

**Regime 2 — atendimento humano (bloco de livechat): WebSocket.**

```js
const connectSocket = function (pubsubToken, resolve, reject, attempt = 0) {
  if (attempt >= 5) reject(new Error("Failed to connect after 5 attempts."));
  else try {
    const ws = new WebSocket("wss://atendimento.leadster.com.br/cable");
    ws.onopen = () => {
      const msg = {
        command: "subscribe",
        identifier: JSON.stringify({ channel: "RoomChannel", pubsub_token: pubsubToken })
      };
      ws.send(JSON.stringify(msg));
      resolve(ws);
    };
    const retry = () => { setTimeout(() => { connectSocket(pubsubToken, resolve, reject, attempt + 1); }, 1000); };
    ws.onerror = retry;
    ws.onclose = retry;
  } catch (e) { reject(e); }
};
```

Reconexão: **retry fixo de 1 s, máximo 5 tentativas**, sem backoff exponencial e sem jitter.
**[INFERÊNCIA]** Depois de 5 falhas o chat de atendimento humano fica mudo sem avisar o
visitante — não encontrei tratamento de erro final na UI.

Envio de mensagem do visitante é **REST** (`POST /livechat/messages`); recebimento é
**WebSocket**. Assimétrico, mas coerente com o backend Chatwoot.

---

## 7. O achado central: a Leadster roda Chatwoot

### 7.1 Evidência — [FATO]

```bash
$ curl -s https://atendimento.leadster.com.br/api
{"version":"4.5.2","timestamp":"2026-08-11 19:46:15","queue_services":"ok","data_services":"ok"}

$ curl -sI https://atendimento.leadster.com.br/ | grep -i set-cookie
set-cookie: _chatwoot_session=y1QGDEnR3Gd28300zfPLRgTAcAVR5oJTWPp1fF2Qdnrl7X9yfXcLbbfPt9KnxfEPn…

$ curl -sI https://atendimento.leadster.com.br/packs/js/sdk.js | head -1
HTTP/2 200          # content-length: 28768
```

Três provas independentes: o endpoint `/api` do Chatwoot com o schema exato de resposta
(`version`/`timestamp`/`queue_services`/`data_services`), o cookie de sessão `_chatwoot_session`
e o `packs/js/sdk.js` servido no caminho canônico.

### 7.2 Confirmação pelo vocabulário do widget — [FATO]

O `onmessage` do WebSocket da Leadster trata exatamente os eventos do Chatwoot:

```js
this.socket.onmessage = t => {
  let e = JSON.parse(t.data);
  if (!e.message || !e.message.event) return;
  const n = e.message.event;
  switch (e = e.message.data, n) {
    case "message.created":
      if ("Contact" !== e.sender_type) {
        this.markConversationStarted();
        this.conversation.setAgentTyping(false);
        let t = "", n = null;
        if (this.message.shouldShowAgentName && e.sender?.name) {
          t = `<p><b>${e.sender.name}:</b></p>`;
          n = e.sender?.avatar_url || null;
        }
        this.conversation.addMessage("left", this.flow.substituteVariables(t + e.content), null, n);
      }
      break;
    case "conversation.typing_on":  … break;
    case "conversation.typing_off": … break;
    case "conversation.updated": {
      const t = e.meta?.assignee || null;
      …
      const e2 = t?.available_name || t?.name;
      …
    }
    case "conversation.status_changed":
      "resolved" === e.status && ( … this.socket.close(), … this.flow.livechatResolved());
  }
}
```

Cruzando com o nosso repositório (leitura apenas):

| Símbolo no widget da Leadster | Onde existe no ChatSPX |
|---|---|
| `channel: "RoomChannel"` | `app/javascript/shared/helpers/BaseActionCableConnector.js:37` |
| `pubsub_token` | `app/channels/room_channel.rb:32` (`stream_from pubsub_token`) |
| `message.created` | `app/listeners/hook_listener.rb:71` |
| `conversation.typing_on` | `app/listeners/webhook_listener.rb:106` |
| `conversation.status_changed` | `app/listeners/webhook_listener.rb:2` |
| `sender_type === "Contact"` | modelo `Message` (polimórfico) |
| `contact.source_id` | `app/models/contact_inbox.rb:12` |
| `assignee.available_name` | `app/models/concerns/user_attribute_helpers.rb` |

**[INFERÊNCIA] — e é uma inferência forte:** a Leadster não reimplementou nada disso. Eles
rodam uma instância de Chatwoot (4.5.2) como plataforma de atendimento e escreveram um widget
próprio que fala com ela através de uma camada de API própria (`/api/chatbot/livechat/*`), que
funciona como fachada — traduzindo entre o modelo de "fluxo de captura" deles e o modelo de
contato/conversa do Chatwoot.

### 7.3 Por que isso importa muito para o ChatSPX

A pilha da Leadster, decomposta:

```
 ┌──────────────────────────────────────────────┐
 │  Widget proprietário (neurolead, Preact)     │  ← o que eles construíram
 │  · fluxo conversacional client-side          │
 │  · gatilhos de abertura                      │
 │  · teste A/B de chamadas                     │
 │  · captura + validação de campos             │
 ├──────────────────────────────────────────────┤
 │  API de fachada /api/chatbot (Rails/Cloud66) │  ← o que eles construíram
 │  · segmentação de fluxo por URL              │
 │  · tracking / atribuição / CAPI              │
 ├──────────────────────────────────────────────┤
 │  CHATWOOT 4.5.2                              │  ← o que NÓS JÁ TEMOS
 │  · contatos, conversas, agentes              │
 │  · ActionCable (RoomChannel)                 │
 │  · caixa de entrada, atribuição, resolução   │
 └──────────────────────────────────────────────┘
```

**Nós já possuímos a camada de baixo, inteira, e com muito mais recursos que a versão 4.5.2**
(o ChatSPX carrega Captain/IA, automações Flow, times, relatórios). O que a Leadster tem e nós
não temos é a **camada de cima**: um widget de captura conversacional com gatilhos, A/B e
atribuição.

Isso reposiciona todo o problema. Não se trata de "construir um concorrente da Leadster do
zero". Trata-se de construir a camada que falta sobre uma base que já é mais forte que a deles.

---

## 8. Performance

### 8.1 Peso medido — [FATO]

| Artefato | Bruto | Comprimido | Observação |
|---|---|---|---|
| `neurolead.min.js` | **456.101 B** | 133.402 B (brotli) / 134.576 B (gzip -9) | Sempre carregado |
| `tracking/v1/leadster.min.js` | 6.038 B | 2.270 B (gzip) | Condicional |
| CSS | — | — | **Embutido no JS** (style-loader) |
| `avatar.png` (padrão) | **123.277 B** | — | PNG, sem WebP/AVIF |
| `avatar/3.png` | 15.604 B | — | Avatar específico |
| `state_cities.json` | 125.782 B | — | Só se o fluxo usa bloco estado/cidade |
| gtag.js (Leadster) | ~ | — | Terceiro, sempre |
| fbevents.js | ~ | — | Terceiro, condicional |

**Comparativo direto com o Chatwoot** — medido no próprio ambiente da Leadster, o que torna a
comparação justa:

| | Leadster | Chatwoot (`atendimento.leadster.com.br/packs/js/sdk.js`) | Razão |
|---|---|---|---|
| Loader no host | 456.101 B | **28.768 B** | **15,9x** |
| Loader gzip | 134.576 B | **9.494 B** | **14,2x** |

A diferença é estrutural, não de qualidade de código: o Chatwoot carrega no host apenas o
suficiente para desenhar a bolha e criar um `<iframe>`; **todo o peso da aplicação de chat vive
dentro do iframe** e só é baixado quando o iframe carrega. A Leadster não tem iframe, então
tudo — Preact, styled-components, date-fns, axios, calendário, telefone internacional, CSS —
precisa estar no bundle do host.

### 8.2 Bibliotecas identificadas dentro do bundle — [FATO]

| Lib | Evidência |
|---|---|
| **Preact** | `__webpack_require__("./node_modules/preact/debug/dist/debug.module.js")` no build de debug |
| **styled-components 5.3.11** | `data-styled-version="5.3.11"` |
| **@emotion/is-prop-valid** | módulo `./node_modules/@emotion/is-prop-valid/…` |
| **axios** | `axios.create({baseURL, headers})`, `AxiosHeaders`, `xsrfCookieName` |
| **date-fns** | 11 ocorrências; links para `github.com/date-fns/date-fns/blob/master/docs/unicodeTokens.md` |

**[INFERÊNCIA]** A escolha de Preact (em vez de React) é o único movimento claro de economia de
peso. Ela é anulada por trazer styled-components **e** emotion **e** axios **e** date-fns
completo no mesmo bundle. `axios` para um cliente que faz meia dúzia de POSTs é peso puro
quando `fetch` existe — e o próprio código já usa `fetch` em um lugar (`/livechat/notes`).

### 8.3 O que **não** existe no bundle — [FATO]

Busca por padrões de otimização, resultado:

| Padrão | Ocorrências |
|---|---|
| `requestIdleCallback` | **0** |
| `IntersectionObserver` | **0** |
| `<link rel="preconnect">` / `dns-prefetch` | **0** |
| `loading="lazy"` | **0** |
| `requestAnimationFrame` | 5 (usado só no handler de rota SPA) |

Não há **nenhuma** estratégia de carregamento ocioso. O bundle inteiro é parseado e executado
assim que baixa.

### 8.4 Impacto em Core Web Vitals — [INFERÊNCIA], não medido

Não rodei Lighthouse nem coletei métricas de campo. O que o código permite deduzir:

- **LCP:** o widget é injetado após `load`/`readyState === 'complete'`, então **[INFERÊNCIA]**
  não deve competir com o LCP na maioria dos casos. Ponto a favor deles. Porém, 133 KB
  comprimidos de JS baixando em paralelo com os recursos da página disputam banda em conexões
  móveis ruins e podem, sim, atrasar o LCP em 3G/4G congestionado.
- **INP / TBT:** aqui o risco é alto. 456 KB de JS para parsear e executar na thread principal,
  sem `requestIdleCallback`, sem fatiar em tarefas. **[INFERÊNCIA]** É uma tarefa longa
  provável no bootstrap. Some-se a isso o fato de que o widget instala um handler de `click`
  em **todo o `window`** (para detectar troca de rota, seção 9.4) e sobrescreve
  `window.onmousemove` — dois caminhos quentes de interação.
- **CLS:** **[INFERÊNCIA]** baixo. O container é `position: absolute` / os filhos são
  posicionados de forma fixa, e a montagem ocorre depois do `load`, então não empurra conteúdo.
  Este é provavelmente o Web Vital em que eles vão melhor.

**Recomendação de verificação futura:** rodar Lighthouse e WebPageTest contra um site real com
Leadster (ex.: F11) com e sem o script, para transformar essas inferências em números. Não fiz
isso porque exigiria execução de navegador, fora do escopo desta coleta estática.

### 8.5 Ausência de lazy load do chat pesado — [FATO]

O critério da pergunta original ("só carrega o chat pesado quando abre?") tem resposta clara:
**não**. O fluxo, o renderizador, o calendário, o seletor de telefone internacional e o CSS
inteiro são carregados em toda página, para todo visitante, tenha ele intenção de abrir o chat
ou não. Só o módulo de recomendação de produtos do ShopBot é um chunk separado.

---

## 9. Persistência, identidade e comportamento em runtime

### 9.1 Geração de identidade — [FATO]

```js
guidGenerator() {
  const key = "neuroleadUser";
  this.userId = null;
  if (localStorage && localStorage.getItem) this.userId = localStorage.getItem(key);

  let hex4 = () => (65536 * (1 + Math.random()) | 0).toString(16).substring(1);
  let guid = hex4()+hex4()+"-"+hex4()+"-"+hex4()+"-"+hex4()+"-"+hex4()+hex4()+hex4();

  if (this.userId) {                        // visitante recorrente
    this.sessionId = guid.substring(30, 36);
    return this.userId + this.sessionId;
  }
  this.userId    = guid.substring(0, 30);   // visitante novo
  this.sessionId = guid.substring(30, 36);
  if (localStorage && localStorage.getItem) localStorage.setItem(key, this.userId);
  return guid;
}
```

Consequências:

- **`userId` = 30 caracteres, persistente em `localStorage`.** É como reconhecem visitante
  recorrente. Não usa cookie, então **não sobrevive entre subdomínios** e morre em navegação
  anônima.
- **`sessionId` = 6 caracteres, regerado a cada page load.** Não é persistido. **[INFERÊNCIA]**
  "Sessão" aqui significa literalmente "carregamento de página", não sessão de navegação —
  então uma visita com 5 páginas gera 5 `sessionId` diferentes.
- **`leadId` = `userId + sessionId`** (concatenação simples).
- **A entropia vem de `Math.random()`**, não de `crypto.getRandomValues()`. **[INFERÊNCIA]**
  Para telemetria isso é aceitável; mas como esse mesmo `leadId` é usado como chave em chamadas
  server-side (`/marketing_event/block-events`, `/whatsapp_tracking`), um identificador
  previsível é uma escolha ruim. Note ainda o bug de formato: `hex4()` pode retornar menos de
  4 dígitos quando o valor sorteado tem zeros à esquerda — o `substring(1)` de um hex de 5
  dígitos pode dar 4, mas a construção `(65536 * (1 + Math.random()) | 0)` sempre produz
  ≥ 65536, então na prática são sempre 4 dígitos. Sem impacto.

### 9.2 Tabela de chaves de `localStorage` — [FATO]

| Chave | Conteúdo | TTL | Uso |
|---|---|---|---|
| `neuroleadUser` | `userId` (30 chars) | Permanente | Identidade do visitante recorrente |
| `neuroleadsPreferredVersions` | JSON `{scriptId: scriptVersionId}` | Permanente | **Grude do teste A/B** — mantém a variante sorteada |
| `lastNotificationViewed` | Índice numérico | Permanente | Rotação de notificações do teaser |
| `lastNotificationViewedText` | Texto | Permanente | Reexibe a última notificação como 1ª mensagem do chat |
| `leadster_ai_interaction` | — | — | **[NÃO VERIFICADO]** — string presente no bundle, uso não confirmado |
| `neuroled_location_list` | — | — | **[NÃO VERIFICADO]** — string presente (note o typo "neuroled"), uso não confirmado |

O helper é trivial e sempre serializa em JSON:

```js
class LocalStorage {
  setItem(key, data) { if (localStorage && localStorage.setItem) localStorage.setItem(key, JSON.stringify(data)); }
  getItem(key, defaultValue = null) {
    if (localStorage && localStorage.getItem) { const item = JSON.parse(localStorage.getItem(key)); return item || defaultValue; }
  }
}
```

### 9.3 Tabela de cookies — [FATO]

O escritor de cookies:

```js
const setCookie = function (name, value, ttl = {hours: 24, days: 0, minutes: 0}) {
  if ("undefined" == typeof document) return;
  const d = new Date();
  const ms = 60 * (ttl.hours || 0) * 60 * 1e3
           + 24 * (ttl.days  || 0) * 60 * 60 * 1e3
           + 60 * (ttl.minutes|| 0) * 1e3;
  d.setTime(d.getTime() + ms);
  try {
    const v = encodeURIComponent(JSON.stringify(value));
    document.cookie = `${name}=${v}; domain=${window.location.hostname}; path=/; expires=${d.toUTCString()}; SameSite=Strict; Secure`;
  } catch { return }
};
```

| Cookie | Valor | TTL | Escopo | Origem |
|---|---|---|---|---|
| `<userId>` | `{"lead_id": …}` — **o nome do cookie é o próprio `userId`** | — | host | Vincula lead ↔ visitante |
| `livechat_conversation_id` | ID da conversa no Chatwoot | 1 dia | host | Retomada de atendimento |
| `leadster_hide_tooltip` | `true` | 1 hora | host | Só quando `companySegment === "E-commerce"` |
| `cooldown_{trigger}_{mobile\|desktop}_{scriptId}` | `true` | `cooldownPeriod` (min) | host | Antirreabertura por gatilho |
| `leadster_trigger_page_access_{scriptId}` | Contador inteiro | 7 h | host | Gatilho "N acessos de página" |
| `privacy_policy_{…}` | — | — | host | **[NÃO VERIFICADO]** — template de chave presente no bundle |
| `_fbc` | `fb.{n}.{ts}.{fbclid}` | 90 dias | host | **Recriado pela Leadster** (ver 10.4) |
| `_gcl_aw` | `GCL.{ts}.{gclid}` | 90 dias | host | **Recriado pela Leadster** |

Cookies **lidos** (não escritos) pelo widget: `_fbp`, `_fbc`, `_ga`, `_ga_{MEASUREMENT_ID}`,
`_gcl_aw`, `__trf.src` e `_rdtrk` (estes dois últimos apenas se o cliente tem integração RD
Station, checado via `companyIntegrations.split(",").includes("rdstation")`).

**Três observações de qualidade sobre a implementação de cookies:**

1. **`domain=window.location.hostname`** fixa o cookie no host exato. Um visitante que vai de
   `www.site.com` para `loja.site.com` é tratado como pessoa nova. O Chatwoot faz melhor:
   `setCookieWithDomain(..., { baseDomain })` permite cookie no domínio-pai.

2. **`SameSite=Strict`** em todos. Correto e conservador — mas quebra a continuidade em
   navegação vinda de link externo (o cookie não é enviado na primeira requisição).

3. **[INFERÊNCIA] Bug real:** a chamada `setCookie("_fbc", valor, {days: 90, shouldParseJson: false})`
   passa uma flag `shouldParseJson` que **o `setCookie` nunca lê**. Ele sempre faz
   `JSON.stringify`. Resultado: o cookie `_fbc` do Meta é gravado **com aspas literais**
   (`_fbc="fb.1.1786477823.abc"` em vez de `_fbc=fb.1.1786477823.abc`). Como a leitura
   correspondente usa `$i("_fbc", null, false)` (sem parse), o valor volta com as aspas. Esse
   valor com aspas alimenta o `fbc` enviado ao Meta CAPI (seção 10.3). **[INFERÊNCIA]** Isso
   provavelmente degrada o *matching* de atribuição no Meta e pode corromper o cookie `_fbc`
   legítimo do Pixel do próprio cliente. Vale registrar como armadilha a **não** repetir.

### 9.4 Os 7 gatilhos de abertura — [FATO], código-fonte do build de debug

| `TYPE` | Classe | Mecanismo |
|---|---|---|
| `screen_time` | `ScreenTime` | `setTimeout(openChat, value * 1000)` |
| `page_scroll` | `PageScroll` | `(scrollY + innerHeight) / scrollHeight * 100 >= value` |
| `cursor_outside` | `CursorOutside` | **Exit intent:** `mouseleave` com `clientY <= 0`, confirmado após 200 ms |
| `inactivity_time` | `InactivityTime` | Ociosidade do usuário |
| `page_click` | `PageClick` | Clique em qualquer lugar da página |
| `clicked_at` | `ClickedAt` | Clique em elementos de uma classe CSS configurável (`shouldPersist = true`) |
| `page_access` | `PageAccess` | Contador em cookie: abre no N-ésimo acesso |

Exit intent, literal:

```js
class CursorOutside extends BaseTrigger {
  static TYPE = 'cursor_outside';
  initialize() { document.addEventListener('mouseleave', this.onMouseLeave); }
  onMouseLeave(event) {
    if (!this.enabled) return;
    if (event.clientY <= 0) {
      if (this.timeoutId) clearTimeout(this.timeoutId);
      this.timeoutId = setTimeout(() => { this.openChat(); this.disable(); }, 200);
    }
  }
}
```

Gatilho por rolagem:

```js
class PageScroll extends BaseTrigger {
  static TYPE = 'page_scroll';
  onScroll() {
    if (!this.enabled) return;
    const scrollPercentage = (window.scrollY + window.innerHeight) / document.documentElement.scrollHeight * 100;
    if (scrollPercentage >= this.config.value) { this.openChat(); this.disable(); }
  }
}
```

Contrato base, com o controle de *cooldown*:

```js
class BaseTrigger {
  static TYPE = null;
  constructor(config, isMobile, openCallback) {
    …
    this.cooldownPeriodControl = new CooldownPeriodControl(this.config, this.constructor.TYPE, isMobile);
    if (this.constructor.TYPE === null)
      throw new Error('Static TYPE property must be defined by all subclasses of BaseTrigger');
  }
  initialize() { throw new Error('Method is of abstract type and must be implemented'); }
  clean()      { throw new Error('Method is of abstract type and must be implemented'); }
  openChat() {
    if (this.cooldownPeriodControl.isUnderCooldown()) return;
    this.openCallback(this.config.openMode, this.constructor.TYPE);
    this.cooldownPeriodControl.setCooldownIfNeeded();
  }
}
```

E a chave de cooldown, que é **por gatilho, por dispositivo e por script**:

```js
getCookieKey() {
  const scriptId = window.neurolead?.convoScript?.scriptId || 0;
  const device   = this.isMobile ? "mobile" : "desktop";
  return `cooldown_${this.triggerType}_${device}_${scriptId}`;
}
```

**Ponto de design que vale copiar:** cada gatilho tem configuração **separada para desktop e
mobile**, resolvida em `_getTriggerSettingsForDevice`:

```js
_getTriggerSettingsForDevice(t) {
  if (!t?.enabled) return null;
  const cfg = isMobile() ? t.mobile : t.desktop;
  return cfg?.enabled ? cfg : null;
}
```

Não é "um gatilho com um toggle de mobile" — são **duas configurações independentes**. Um
exit-intent faz sentido em desktop e é inútil em touch; scroll a 50% em mobile é outra coisa
que scroll a 50% em desktop. Eles modelaram isso corretamente.

**Gatilhos NÃO encontrados no bundle:** não há gatilho por **URL/regex de página** nem por
**UTM** no cliente. **[INFERÊNCIA]** Isso é resolvido no servidor: `path`, `host` e `query` vão
no bootstrap e o servidor decide qual fluxo entregar. Arquitetura melhor que a nossa
intuição inicial — a segmentação por URL não precisa estar no cliente.

### 9.5 Comportamento em SPA — [FATO]

```js
const remountWidget = () => {
  window.neurolead.elChatbot.remove();
  window.neurolead?.chatOpenTriggersManager?.clearTriggers(true);
  delete window.neurolead;
  boot();
};

new class {
  constructor(callback) { this.callback = callback }
  listen() {
    this._overrideHistoryMethods();
    ["popstate", "onload", "click"].forEach(evt => {
      window.addEventListener(evt, e => { this._onRouteChange(e) });
    });
  }
  _overrideHistoryMethods() {
    const origPush = history.pushState, origReplace = history.replaceState, self = this;
    history.pushState = function (...args) {
      const r = origPush.apply(history, args);
      self._onRouteChange(new Event("popstate"));
      return r;
    };
    history.replaceState = function (...args) {
      const r = origReplace.apply(history, args);
      self._onRouteChange(new Event("popstate"));
      return r;
    };
  }
  _onRouteChange(e) {
    if (typeof this.callback == "function" && window.neurolead) this.callback(window.location.href, e);
  }
}((href, e) => {
  const allowed = new Set(["onload", "popstate", "click"]);
  if (("click" !== e?.type || allowed.has(lastType)) && lastHref !== window.location.href) {
    requestAnimationFrame(remountWidget);
    lastType = e?.type;
    lastHref = window.location.href;
  }
}).listen();
```

Leitura:

- **Monkey-patch de `history.pushState` e `history.replaceState`** do host. Funciona com
  qualquer roteador (React Router, Vue Router, Next.js). É a abordagem pragmática e universal.
- **Também escuta `click` em todo o `window`** — um listener em caminho quente de interação
  para cada clique da página.
- **A resposta à troca de rota é destruir e recriar o widget inteiro**, com novo
  `POST /scripts/search`. **[INFERÊNCIA]** Uma conversa em andamento é perdida quando o
  visitante navega dentro da SPA. Não encontrei nenhum mecanismo de persistência ou
  reidratação do estado da conversa.

Compare com o Chatwoot, que resolve o mesmo problema **preservando** o widget: `restoreWidgetInDOM`
para Turbo/Turbolinks/Astro e `dataset.turboPermanent = true` no holder. O Chatwoot **preserva
estado**; a Leadster **descarta**. Aqui nós já somos melhores.

### 9.6 Múltiplas abas — [FATO]

- **Não há `BroadcastChannel`, não há listener de evento `storage`, não há `SharedWorker`.**
- `visibilitychange` aparece **uma única vez**, e é no `BlinkTitle`.

**[INFERÊNCIA]** Cada aba mantém seu próprio `sessionId`, seu próprio WebSocket e seu próprio
estado. Não há sincronização entre abas. Duas abas abertas do mesmo site geram duas conexões e
duas sessões de telemetria.

### 9.7 Teaser, notificações e o "piscar" do título — [FATO]

O teaser (balão de convite) é controlado por `waitTime` do JSON de configuração (7000 ms no
caso medido) e pelo `NotificationsManager`, cujo código-fonte comentado é:

```js
class NotificationsManager {
  /*
   * If `enabled`, use the elements inside el to display
   * notifications, changing them every `displayTime` milliseconds
   * and showing at maximum `amount` notifications.
   */
  constructor(scriptVersionId, enabled, tooltipMessage, el, chatSide, displayTime, amount, mobile) {
    …
    this.typingTime = 2000;
    this.platform = mobile ? "mobile" : "desktop";
    this.smartCall = new SmartCall();
    if (enabled && scriptVersionId && amount > 0) this.startTimer();
  }
  fetchNotification(success, fail) {
    const viewedLeads         = this.getList("Leads").join(",");
    const viewedNotifications = this.getList("Notifications").join(",");
    const lastNotificationViewed = this.smartCall.getLastNotificationViewed();
    const params = `viewed_notifications=${viewedNotifications}&viewed_leads=${viewedLeads}`
                 + `&platform=${this.platform}&last_notification=${lastNotificationViewed}`;
    …
  }
}
```

Detalhes:

- **Exibe um indicador de digitação por 2 s antes de cada notificação** (`typingTime = 2000`),
  simulando alguém digitando. É teatro de presença humana.
- **Rastreia quais notificações e quais "leads" já foram vistos** e envia isso ao servidor para
  não repetir.
- O texto da última notificação vista é **reinjetado como primeira mensagem do chat** quando o
  visitante abre:
  ```js
  addFirstBlockMessages(t) {
    const e = this.getLastNotificationViewedText();
    return null !== e ? [{say: t[0].say}, {say: e}] : t;
  }
  ```
  Continuidade narrativa entre o teaser e a conversa. Detalhe fino e inteligente.

**Piscar do título da aba — o dark pattern:**

```js
class BlinkTitle {
  constructor() {
    if (!BlinkTitle.instance) {
      this._intervalRef = null;
      this._originalTitle = document.title;
      BlinkTitle.instance = this;
      document.addEventListener('visibilitychange', () => this._handleVisibilityChange(), false);
    }
    return BlinkTitle.instance;
  }
  blink(message = i18n_dictionary[neuroleadLanguage]['new_message'], delay = 650, timeout = 60000) {
    if (!document.hidden) return;
    if (this._intervalRef) return;
    const thisRef = this;
    this._intervalRef = setInterval(() => this._changeTitle(message), delay);
    setTimeout(() => thisRef._stopBlink(), timeout);
  }
  _changeTitle(message) {
    document.title = document.title === this._originalTitle ? message : this._originalTitle;
  }
}
```

Com `new_message: "(1) Nova Mensagem!"` no dicionário pt-BR. **O widget de um terceiro
manipula o `document.title` do site do cliente**, alternando a cada 650 ms por até 60 s, quando
a aba está em segundo plano. Funciona para chamar atenção, é hostil ao usuário, e o cliente
provavelmente não sabe que isso acontece.

**Som e badge:** busca por `new Audio(` no bundle → **0 ocorrências**. **[INFERÊNCIA]** Não há
notificação sonora; o "badge" é o próprio piscar do título e o balão teaser. (O Chatwoot, ao
contrário, tem `AudioNotificationHelper` com áudio real.)

### 9.8 Mobile vs desktop — [FATO]

- Detecção via helper `device_helper.js` (`isMobile()`), usada em: escolha de `platform` no
  bootstrap, seleção de configuração de gatilho, lado do widget (`mobileSide` vs `side`),
  rodízio de número de WhatsApp e escolha de notificação.
- Classes dedicadas: `nld-fullscreen`, `nld-chatbot-invite-container-{small,medium}`,
  `nld-avatar-{small,medium}` — o teaser tem 3 tamanhos.
- Overflow diferenciado: `mobile ? "overflow-y: auto;" : "overflow-y: scroll;"`.
- **Comportamento específico de teclado em mobile:**
  ```js
  onFocusInput(t) {
    const tag = t.target.tagName, isFocusIn = "focusin" == t.type;
    if (["input","textarea"].includes(tag.toLowerCase()) && isMobile()) {
      if (!this.isOpen) { isFocusIn ? (this.hideTooltip(), this.hideAvatar()) : this.showAvatar(); }
    }
  }
  ```
  Quando o visitante foca um campo **do site do cliente** em mobile, o widget se esconde para
  não brigar com o teclado virtual, e reaparece ao desfocar. **Detalhe de UX excelente, e
  barato de copiar.**

---

## 10. Tracking embutido

### 10.1 Telemetria própria — [FATO]

```js
sendAnalyticsEvent(eventName, callback = () => {}, skipServer = false) {
  if (this.disableServerCommunication) return;
  if (window.ga) window.ga("neurolead.send", "event", window.neuroleadId.toString(), eventName);
  else if (window._gaq) _gaq.push(["neurolead._trackEvent", window.neuroleadId.toString(), eventName]);
  if (skipServer) return;
  let payload = {
    userId: this.userId, sessionId: this.sessionId, leadId: this.userId + this.sessionId,
    company: window.neuroleadId, script: this.metadata.scriptId, event: eventName,
    clientVersion: this.clientVersion(), scriptVersion: this.metadata.scriptVersionId,
    time: (new Date).getTime() / 1e3 | 0, devMode: !!window.neuroleadEventDevMode,
    isMobile: isMobile(), referrer: getReferrer(), location: window.location.href || document.URL
  };
  const send = delay => {
    const url = `${BASE_URL_API}/events`;
    let xhr = new XMLHttpRequest();
    xhr.open("POST", url, true);
    xhr.setRequestHeader("Content-Type", "application/json; charset=UTF-8");
    xhr.setRequestHeader("Cors-Token", this.corsToken);
    xhr.timeout = 30000;
    xhr.send(JSON.stringify(payload));
    xhr.onreadystatechange = () => {
      if (401 === xhr.status) return this.close(true), void this.hideAvatar();
      if (4 == xhr.readyState) { 200 == xhr.status ? callback() : setTimeout(() => { send(2 * delay) }, delay); }
    };
  };
  send(1000);
}
```

**Nomes de evento internos:** `load`, `show`, `user_open`, `close`, `finish`,
`step_{n}` e `{trigger_type}_triggered` (ex.: `cursor_outside_triggered`).

Notas: retry com **backoff exponencial** (1 s → 2 s → 4 s …) sem teto e sem jitter; usa
`XMLHttpRequest` cru em vez do axios do resto do código; `window.ga`/`window._gaq` são
Universal Analytics **legado** (a string `"neurolead.send"` é o nome do tracker deles, não uma
API pública — ver seção 11.1).

### 10.2 Eventos disparados para GA4, Google Ads e Meta — [FATO]

```js
sendSyncEvents() {
  window.dataLayer = window.dataLayer || [];
  if (window.gtag) {
    gtag("event", "new_lead");
    gtag("event", "Leadster", { event_category: "new_lead" });
    gtag("event", this.metadata.gaConversionEvent[1], { event_category: this.metadata.gaConversionEvent[0] });
    if (this.metadata.gtagConversionId)
      gtag("event", "conversion", { send_to: this.metadata.gtagConversionId, event_callback: () => {} });
  } else if (window.__gaTracker) {
    __gaTracker("send", "event", this.metadata.gaConversionEvent[0], this.metadata.gaConversionEvent[1]);
  } else {
    window.dataLayer.push({ event: "new_lead" });
  }
  if (this.metadata.fbqConversionEvents) {
    const pixel = this.metadata.fbqConversionEvents[1];
    if (pixel) {
      if ("undefined" == typeof fbq) insertMetaPixel(pixel, this.metadata.fbqConversionEvents[0]);
      fbq("track", this.metadata.fbqConversionEvents[0]);
      window.dataLayer.push({ event: this.metadata.fbqConversionEvents[0] });
    }
  }
}
```

E, por etapa do fluxo:

```js
sendClientAnalyticsEvent(fieldName, value, step) {
  let label = `Etapa - ${step} - ${fieldName.split("::").slice(-1)[0]}`;
  if (this.metadata.gaConversionEvent && this.metadata.gaConversionEvent.length >= 2) {
    if (window.__gaTracker) __gaTracker("send", "event", "Neurologic", label);
    if (window.gtag) gtag("event", label, { event_category: "Neurologic" });
  }
}
```

**Tabela de eventos exatos disparados no site do cliente:**

| Destino | Nome do evento | Parâmetros | Quando |
|---|---|---|---|
| GA4 (`gtag`) | `new_lead` | — | Lead concluído |
| GA4 (`gtag`) | `Leadster` | `event_category: "new_lead"` | Lead concluído |
| GA4 (`gtag`) | `{gaConversionEvent[1]}` — ex.: `Lead` | `event_category: {gaConversionEvent[0]}` — ex.: `Leadster` | Lead concluído |
| Google Ads (`gtag`) | `conversion` | `send_to: {gtagConversionId}` | Lead concluído, se configurado |
| GA4 (`gtag`) | `Etapa - {n} - {campo}` | `event_category: "Neurologic"` | **Cada passo do fluxo** |
| UA legado (`__gaTracker`) | categoria `Neurologic`, ação `Etapa - {n} - {campo}` | — | Cada passo |
| Meta Pixel (`fbq`) | `track` `{fbqConversionEvents[0]}` — ex.: `Leadster-Lead` | — | Lead concluído |
| GTM (`dataLayer`) | `{event: "new_lead"}` | — | Fallback, se não há `gtag` |
| GTM (`dataLayer`) | `{event: "{fbqConversionEvents[0]}"}` | — | Junto com o Pixel |

Valores confirmados de um cliente real (config F8): `gaConversionEvent: ["Leadster","Lead"]`,
`fbqConversionEvents: ["Leadster-Lead"]`.

**Nome de evento com espaços, hífens e acento (`"Etapa - 3 - email"`)** é uma escolha ruim para
GA4, que recomenda `snake_case` e limita a 40 caracteres. **[INFERÊNCIA]** Nomes longos de campo
podem ser truncados no GA4.

### 10.3 Envio server-side: Meta CAPI e GA4 Measurement Protocol — [FATO]

```js
const buildMetaPayload = async opts => (ensureFbc(), {
  platform: "meta",
  meta_event_options: opts.meta_event_options,
  credential_id: opts.meta_credential_id,
  action_source: "website",
  fbp: getCookie("_fbp", null, false),
  fbc: getCookie("_fbc", null, false),
  em: await sha256Email({ key: opts?.email_field_meta }),
  ph: await sha256Phone({ key: opts?.phone_field_meta }),
  fn: await sha256First({ key: opts?.name_field_meta }),
  ln: await sha256Last ({ key: opts?.name_field_meta }),
  ct: await sha256City ({ key: opts?.city_field_meta }),
  st: await sha256State({ key: opts?.state_field_meta }),
  referrer_url: getReferrer(), current_url: getCurrentUrl(),
  test_mode: opts.test_mode ?? window.neurolead?.test_mode,
  test_event_code: opts.test_event_code ?? window.neurolead?.test_event_code
});

const buildGaPayload = async opts => ({
  platform: "google_analytics",
  google_analytics_event_options: opts.google_analytics_event_options,
  credential_id: opts.google_analytics_credential_id,
  client_id:  await getGa4ClientId (opts.google_analytics_measurement_id),
  session_id: await getGa4SessionId(opts.google_analytics_measurement_id),
  sha256_email_address: await sha256Email({ key: opts?.email_field_google_analytics }),
  sha256_phone_number:  await sha256Phone({ key: opts?.phone_field_google_analytics }),
  sha256_first_name:    await sha256First({ key: opts?.name_field_google_analytics }),
  sha256_last_name:     await sha256Last ({ key: opts?.name_field_google_analytics }),
  city: …, region: …,
  device: { category, language, screen_resolution, operating_system, browser },
  referrer_url: …, current_url: …, test_mode: …
});

const postBlockEvent = async function (payload, block, attempt = 0) {
  try {
    const body = { ...payload, timestamp: Date.now(), block_uid: block.uid, location: getCurrentUrl(),
                   lead_id: getLeadId(), user_id: getUserId(), script: getScriptId(),
                   script_version: getScriptVersionId(), company: getCompanyId() };
    return (await http.post("/marketing_event/block-events", body)).data;
  } catch (e) {
    if (500 === e.response?.status && attempt < 3) return postBlockEvent(payload, block, attempt + 1);
    throw e;
  }
};
```

O hash é `crypto.subtle.digest("SHA-256", …)` no cliente:

```js
const sha256 = async v => {
  if (!v) return null;
  const bytes = new TextEncoder().encode(v);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)) /* → hex */;
};
```

**Isso é sofisticado e é o núcleo da proposta de valor deles.** O widget:

1. Hasheia PII (e-mail, telefone, nome, cidade, estado) **no navegador**, com SHA-256, no
   formato exigido pelo Advanced Matching do Meta e pelo User-Provided Data do GA4.
2. Coleta `_fbp`/`_fbc` e `client_id`/`session_id` do GA4 do próprio navegador.
3. Envia tudo ao backend da Leadster, que repassa para o Meta CAPI e o GA4 Measurement Protocol
   usando uma **credencial armazenada** (`credential_id`) — o cliente configura a integração
   uma vez no painel.
4. Suporta `test_mode` / `test_event_code` para validar sem sujar dados.

Resultado prático para o anunciante: conversão atribuída mesmo com bloqueador de anúncio, ITP
ou falha do Pixel no cliente. É exatamente o que uma agência de performance quer comprar.

### 10.4 O script `window.ll` — atribuição cross-domain — [FATO]

Arquivo completo em `https://cdn.leadster.com.br/neurolead/tracking/v1/leadster.min.js`,
`version = "1.1.1"`, 6.038 bytes. O sourcemap revela o nome do fonte:
`tracking/leadster-tracking.js`. O que ele faz:

**(a) Persiste ~40 parâmetros de URL como cookies first-party `ll_*` por 30 dias:**

```
utm_source, utm_medium, utm_campaign, utm_content, utm_term, utm_id, fbclid, gclid,
gad_source, campaignid, adsetid, adset, adid, adgroupid, targetid, adcampaign, groupid,
__hsfp, __hssc, __hstc, __s, _hsenc, hsCtaTracking, _openstat, dclid, mc_eid, mkt_tok,
ml_subscriber, ml_subscriber_hash, msclkid, oly_anon_id, oly_enc_id, rb_clickid, s_cid,
vero_conv, vero_id, wickedid, yclid, src
```

```js
document.cookie = "ll_" + param + "=" + encodeURIComponent(value) + "; path=/; max-age=2592000";
```

**(b) Recria `_fbc` e `_gcl_aw` como cookies first-party** a partir de `fbclid`/`gclid` da URL:

```js
t.createFbc = function () {
  if (t.hasConsent() && !t.getRawCookie("_fbc")) {
    var e = new URLSearchParams(window.location.search).get("fbclid");
    if (e) {
      var n = window.location.hostname.split("."),
          i = n.length <= 1 ? 0 : 2 === n.length ? 1 : n.length - 1;
      t.setCookie("_fbc", "fb." + i + "." + Date.now() + "." + e, 90);
    }
  }
};
```

Isso é contorno explícito de ITP/limitação de cookie de terceiro: o clique do anúncio vira um
cookie de primeira parte do site, com 90 dias de vida.

**(c) Propaga tudo em links de saída — o mecanismo mais interessante:**

```js
t.addParamsToLinksOnEvent = function () {
  …
  var allowedHosts = ["qa.leadster.com.br", "app.leadster.com.br", "localhost"];
  var suffix = ".getleadster.com";
  document.addEventListener("click", function (ev) {
    var a = ev.target.closest('a[href*="/whatsapp/collect"], a[href*="/l/"]');
    if (!a) return;
    // só age se o destino for domínio Leadster
    …
    if (!(ev.ctrlKey || ev.metaKey || ev.shiftKey || ev.altKey || 1 === ev.button) && t.hasConsent()) {
      ev.preventDefault();
      var url = new URL(a.href);
      var cookies = t.collectTrackerCookies();
      for (var k in cookies) if (!url.searchParams.has(k)) url.searchParams.append(k, cookies[k]);
      var measurementId = t.getGa4MeasurementIds()[0] || null;
      var target = a.target || "_self";
      var win = "_blank" === target ? window.open("", "_blank") : null;
      Promise.all([t.getGa4Field(measurementId, "client_id"), t.getGa4Field(measurementId, "session_id")])
        .then(function (r) {
          if (r[0]) url.searchParams.append("client_id", r[0]);
          if (r[1]) url.searchParams.append("session_id", String(r[1]));
          var fbc = t.getRawCookie("_fbc"), fbp = t.getRawCookie("_fbp");
          if (fbc) url.searchParams.append("_fbc", fbc);
          if (fbp) url.searchParams.append("_fbp", fbp);
          a.href = url.toString();
          win ? win.location.href = a.href : window.open(a.href, target);
        }).catch(function () { win && win.close() });
    }
  });
};
```

Ou seja: quando o visitante clica em "Falar por WhatsApp", o clique é **interceptado**, os
cookies de rastreamento e os identificadores de sessão do GA4 são **anexados à URL de saída**, e
só então a navegação prossegue. É assim que a Leadster consegue atribuir uma venda fechada no
WhatsApp à campanha de origem — o elo que quase todo mundo perde.

Os cookies coletados (`collectTrackerCookies`) são: `_fbp`, `_fbc`, `_ga`, `_gid`, `_gat`,
`_gcl_aw`, `_gcl_dc`, `_gcl_gb`, `_gcl_gf`, `_gcl_ha`, `_gcl_au`, `__utma`, `__utmb`, `__utmc`,
`__utmz`, prefixos `_gac_`, `_ga_`, `_gat_`, e todos os `ll_*` (com o prefixo removido).

**(d) Consentimento (LGPD):**

```js
t.hasConsent = function () {
  return !consentRequired || !(!window.llConfig || true !== window.llConfig.consent);
};
t.grantConsent = function () {
  window.llConfig || (window.llConfig = {});
  window.llConfig.consent = true;
  this.saveParams(); this.initAllGa4(); this.initAllFbPixels();
};
t.init = function () {
  this.saveParams();
  this.addParamsToLinksOnEvent();
  t.hasConsent() && (this.initAllGa4(), this.initAllFbPixels());
};
```

Ativado por `window.llConfig.consentRequired = true` ou pelo atributo
`data-consent-required` no `<script>`. O loader no widget também suporta **SRI**
(`script.integrity` + `crossOrigin = "anonymous"`).

**[INFERÊNCIA] Duas observações críticas sobre esse desenho de consentimento:**

1. **O padrão é "sem consentimento requerido".** `consentRequired` é `false` por omissão, e o
   `autoInit` é `true`. Ou seja: **por padrão o script grava dezenas de cookies e inicializa
   GA4/Pixel antes de qualquer opt-in.** O cliente precisa saber que existe `llConfig` para
   fazer o certo — e isso não está na documentação pública que encontrei.
2. **Nota importante e honesta:** mesmo com `consentRequired: true`, o `init()` chama
   `this.saveParams()` **fora** da guarda de consentimento na primeira linha — mas
   `saveParams()` internamente começa com `if (t.hasConsent())`, então na prática ele respeita
   o consentimento. `addParamsToLinksOnEvent()` também registra o listener sempre, mas só age
   dentro de `if (… && t.hasConsent())`. **O desenho está correto**; o problema é apenas o
   valor padrão.

---

## 11. Segurança e privacidade

### 11.1 API pública para o site host: **ela não existe** — [FATO]

Este era um item obrigatório da investigação, e a resposta é negativa e importante.

**Globais que o widget define em `window`:**

| Global | Direção | Papel |
|---|---|---|
| `window.neuroleadId` | host → widget | **Único ponto de configuração.** Definido pelo snippet. |
| `window.neurolead` | widget → host | A instância do chatbot. Não é uma API — é o objeto interno vazando. |
| `window.neuroleadLanguage` | widget | Idioma resolvido |
| `window.neuroleadDefaultScript` | host → widget | Injeta um fluxo pronto, pulando o bootstrap. Não documentado. |
| `window.neuroleadCompanyId`, `neuroleadScriptId`, `neuroleadPSId` | ambos | Overrides não documentados |
| `window.neuroleadLeadDemoMode`, `neuroleadEventDevMode` | host → widget | Flags de demo/dev |
| `window.disableLeadsterGa4` | host → widget | **Desliga o GA4 da Leadster.** Não documentado. |
| `window.ll`, `window.llConfig` | ambos | API do script de tracking (esta sim, é uma API) |

**Eventos emitidos no `window`: zero.** Busca por `dispatchEvent(new CustomEvent` no `window`:
o único uso de `CustomEvent` é o barramento **interno**:

```js
const EventBus = {
  on(name, cb)     { document.getElementById("nld-event-bus").addEventListener(name, e => cb(e.detail)) },
  dispatch(name, d){ document.getElementById("nld-event-bus").dispatchEvent(new CustomEvent(name, {detail: d})) },
  remove(name, cb) { document.getElementById("nld-event-bus").removeEventListener(name, cb) }
};
```

Ele é ancorado num `<div id="nld-event-bus">` com `display: none !important`, dentro do próprio
widget. Eventos que trafegam nele: `onFinishFlow`, `onFinishChat`, `cancelAutoRedirect`,
`storeAnalyticBlockInfo`, `analyticBlockEventCompleted`, `analyticBlockEventError`,
`analyticBlockEventSuccess`, `viewedLeadsterAIBlock`, `updateRetailerItemId`.

**[INFERÊNCIA]** Como é um elemento do DOM com `id` conhecido, um site host **conseguiria**
escutar esses eventos (`document.getElementById('nld-event-bus').addEventListener('onFinishFlow', …)`).
Mas isso é acoplamento a detalhe interno, não contrato — pode quebrar em qualquer release.

**Sobre `neurolead.send` e `neurolead._trackEvent`:** essas strings **aparecem** no bundle e
poderiam ser confundidas com uma API pública. Não são. São o nome do *tracker* do Universal
Analytics legado:

```js
window.ga("neurolead.send", "event", …)     // "neurolead" é o nome do tracker do UA
_gaq.push(["neurolead._trackEvent", …])     // sintaxe do ga.js clássico
```

**Não há:** identificação programática do visitante (`setUser`), atributos customizados,
`toggle()`, `reset()`, `setLocale()`, callbacks de ciclo de vida, nem `dataLayer.push` de
eventos de UI (só de conversão).

**Este é o maior ponto fraco competitivo da Leadster.** O Chatwoot expõe uma API de integração
completa; a Leadster é uma caixa preta. Para um cliente com produto logado que quer amarrar o
chat à identidade do usuário, a Leadster simplesmente não atende.

### 11.2 Ausência de validação de domínio — [FATO], teste executado

**O que foi testado:** se o identificador do cliente funciona quando requisitado de outro
domínio.

```bash
$ curl -s -D - -X POST -H "Origin: https://site-invasor-exemplo.com" \
  "https://app.leadster.com.br/api/chatbot/scripts/search?company=Jubg5SOZXaQt02lUOZizabGnK\
&user=zz9&time=$(date +%s)&path=%2F&host=site-invasor-exemplo.com&query=&platform=desktop"
```

**Resultado:**

```
HTTP/2 200
access-control-allow-origin: *
cors-token: eyJhbGciOiJIUzI1NiJ9.eyJyYW5kb20iOiIxZGFkZDBiNmJjOWUyYjE0NDZlMzYxMzA1N2EwYjkyNCIs…
```

JWT decodificado:

```json
{"random":"1dadd0b6bc9e2b1446e3613057a0b924",
 "data":{"script_id":204915,
         "host":"https://site-invasor-exemplo.com",
         "skip_validation":false},
 "exp":1786492249,"timestamp":1786477849}
```

Corpo: **3.470 bytes, o fluxo completo, idêntico ao da requisição legítima** (`title` do
chatbot, todas as perguntas, todos os campos).

**Conclusões — [FATO]:**

- O campo `host` do JWT é **ecoado do parâmetro de query controlado pelo cliente**, não
  derivado do header `Origin` nem validado contra uma allowlist do cliente.
- `access-control-allow-origin: *` permite que qualquer página leia a resposta.
- `skip_validation: false` sugere que existe *algum* mecanismo de validação previsto no
  desenho, mas ele **não está bloqueando** neste caminho.

**Consequências — [INFERÊNCIA]:**

- Qualquer pessoa pode **clonar o chatbot de qualquer cliente** copiando o ID do HTML público
  e colando no próprio site.
- O `cors-token` obtido é aceito nas rotas seguintes (`/events`, `/livechat/*`,
  `/marketing_event/block-events`), o que abre superfície para **poluição de dados** —
  telemetria e leads falsos numa conta alheia.

**Não exercitei essa superfície.** Testei apenas a leitura de configuração, que é o que todo
navegador já faz ao visitar o site do cliente. Injetar dados numa conta de terceiro seria
abusivo e está fora do escopo autorizado desta task.

**[NÃO VERIFICADO]:** se existe uma configuração de allowlist de domínios no painel da Leadster
que, ativada, faria essa requisição falhar. O cliente testado pode simplesmente não tê-la
habilitada. Não tenho acesso ao painel.

### 11.3 Ausência de verificação de identidade (HMAC) — [FATO]

Busca no bundle por `hmac`, `identifier_hash`, `identity` e derivados: **nenhuma ocorrência**.
Não há assinatura de identidade do visitante.

Contraste com o Chatwoot, que implementa isso:

```js
// app/javascript/sdk/cookieHelpers.js
const ALLOWED_USER_ATTRIBUTES = [...REQUIRED_USER_KEYS, 'identifier_hash'];
```

```js
// app/javascript/entrypoints/sdk.js  — uso documentado
window.$chatwoot.setUser('<user_id>', {
  identifier_hash: '<hmac_sha256_do_servidor>',
  email: 'jane@example.com',
  name: 'Jane Doe',
});
```

O Chatwoot permite que o servidor do cliente assine a identidade do visitante com HMAC-SHA256,
impedindo que alguém se passe por outro contato. **A Leadster não tem equivalente** — mas
também não precisa, já que não tem conceito de visitante autenticado.

### 11.4 Exposição do bucket de CDN — [FATO]

```bash
$ curl -s -A "Mozilla/5.0 Chrome/126.0" https://cdn.leadster.com.br/
<?xml version='1.0' encoding='UTF-8'?><ListBucketResult …><Name>neuro-cdn</Name>…
```

O bucket **`neuro-cdn`** (Google Cloud Storage) tem **listagem pública habilitada**. Sem
`User-Agent` de navegador o Cloudflare devolve 403, o que dá uma falsa sensação de proteção.
Enumerei 25.000 objetos (a listagem é paginada e continua além disso).

O que está exposto — apenas os itens de **código**, que foram os únicos que examinei:

| Caminho | Bytes | Significado |
|---|---|---|
| `neurolead/debug-production/neurolead.js` | 1.036.439 | **Build não minificado**, com nomes de módulo, classes, métodos e comentários originais |
| `neurolead/editor/neurologic-flowchart-editor.js` | 3.085.422 | Editor de fluxos |
| `neurolead/editor/neurologic-flowchart-editor.js.map` | **11.519.578** | **Sourcemap do editor** |
| `neurolead/ecommerce/widget-ecommerce.min.js(.map)` | 111.166 / 545.526 | ShopBot + sourcemap |
| `neurolead/buyback/buyback.min.js(.map)` | 7.292 / 28.141 | + sourcemap |
| `neurolead/neurolead.{v1,v2,rc1,rc2,rc3}.min.js` | 41 KB – 151 KB | Builds históricos |
| `neurolead/bkp_old/neurolead.js` | 355.869 | Backup antigo |
| `neurolead/modules/*.js` | 56 B – 2,9 KB | **Módulos com nome de cliente**: `usaflex`, `jornaldocarro`, `kontaazul`, `imobille`, `rosa_imperial`, `henry_store`, `imobiliaria_rota_do_sol` |
| `neurolead/neurolead/scripts/*.json` | 1,5 KB – 23 KB | **Fluxos de clientes** em arquivos estáticos, nomeados pela empresa |

**O que eu deliberadamente NÃO baixei:** os arquivos `scripts/*.json` de clientes, os 22.831
objetos sob `screenshots_production/`, e `neurolead/crawler-data/HelloHTTP.zip` (101.636.595
bytes). Registro a existência como achado de superfície; inspecionar conteúdo de clientes
estaria fora do escopo autorizado e seria invasão de privacidade de terceiros.

**Impacto — [INFERÊNCIA]:** publicar sourcemaps e builds de debug em produção elimina qualquer
valor da minificação como proteção de propriedade intelectual. Foi exatamente isso que permitiu
que boa parte deste relatório citasse o código-fonte original deles.

### 11.5 O que trafega em claro — [FATO]

Todo o tráfego é HTTPS. Dentro dele:

| Dado | Para onde | Forma |
|---|---|---|
| `window.location.search` **inteiro** | `app.leadster.com.br` (bootstrap) | Texto puro |
| Respostas do lead (nome, e-mail, telefone) | `app.leadster.com.br` (sync) | **Texto puro** |
| E-mail/telefone/nome para o Meta e GA4 | `app.leadster.com.br` → Meta/Google | **SHA-256** (correto) |
| `_fbp`, `_fbc`, `_ga`, `client_id`, `session_id` | `app.leadster.com.br` + query string de links de saída | Texto puro |
| `navigator.userAgent`, `document.referrer`, URL completa | `/api/chatbot/events` | Texto puro |

**[INFERÊNCIA]** Há uma assimetria notável: eles hasheiam PII para o Meta/Google (porque a
plataforma exige) mas trafegam a mesma PII em claro para o próprio backend. Isso é normal — é o
backend deles, é o produto — mas vale registrar que o `query` inteiro da URL do cliente sendo
enviado no bootstrap é um vetor de coleta acidental de PII que eles provavelmente não pretendem.

### 11.6 LGPD e política de privacidade — [FATO]

O widget renderiza um bloco de política de privacidade com dois textos (dicionário pt-BR):

```
"privacy_policy_leadster": "Clicando acima você aceita nossas | Políticas de privacidade",
"privacy_policy_website":  "Clicando acima você aceita as Políticas de privacidade deste |site| e da | Leadster"
```

A URL da política é montada com UTMs próprias, o que é um detalhe revelador:

```js
utmMedium: "utm_medium=privacidade",
utmCampaign: `utm_campaign=${encodeURIComponent(location.hostname)}`
```

Eles rastreiam quantos leads clicam na política de privacidade **e de qual site do cliente
vieram** — usando o link de política como canal de aquisição. A config do cliente traz
`privacyPolicyUrl` (era `null` no cliente medido) e `whiteLabel: false`.

O consentimento formal existe apenas no script `window.ll` (seção 10.4), com padrão
permissivo. O widget principal **não** tem gate de consentimento: ele grava
`localStorage["neuroleadUser"]`, cookies de cooldown e dispara telemetria antes de qualquer
interação do visitante.

---

## 12. Comparação lado a lado: Leadster × Chatwoot/ChatSPX

Base: `app/javascript/sdk/sdk.js`, `app/javascript/sdk/IFrameHelper.js`,
`app/javascript/sdk/cookieHelpers.js`, `app/javascript/entrypoints/sdk.js`,
`app/javascript/widget/constants/sdkEvents.js` — todos **lidos, não modificados**.

### 12.1 Snippet

**Chatwoot** (de `app/views/widget_tests/index.html.erb`):

```js
(function(d,t) {
  var BASE_URL = "…";
  var g=d.createElement(t), s=d.getElementsByTagName(t)[0];
  g.src = BASE_URL + "/packs/js/sdk.js";
  g.defer = true; g.async = true;
  s.parentNode.insertBefore(g,s);
  g.onload = function() {
    window.chatwootSDK.run({ websiteToken: '<token>', baseUrl: BASE_URL })
  }
})(document,"script");
```

| | **Leadster** | **Chatwoot / ChatSPX** |
|---|---|---|
| Configuração | 1 global (`window.neuroleadId`) | Objeto `chatwootSettings` + `run({websiteToken, baseUrl})` |
| Callback de carga | Nenhum | `g.onload` explícito |
| Inserção | `head.appendChild` | `insertBefore` no primeiro `<script>` |
| Flags | `defer` | `defer` **e** `async` |
| Self-host | Impossível (CDN fixo) | `baseUrl` é parâmetro |
| Opções do host | Nenhuma | `position`, `locale`, `type`, `darkMode`, `hideMessageBubble`, `launcherTitle`, `widgetStyle`, `showPopoutButton`, `enableFileUpload`, `enableEmojiPicker`, `enableEndConversation`, `useBrowserLanguage`, `welcomeTitle`, `welcomeDescription`, `availableMessage`, `unavailableMessage`, `baseDomain` |

### 12.2 Renderização e isolamento

| | **Leadster** | **Chatwoot / ChatSPX** |
|---|---|---|
| Técnica | `div` no DOM do host | **`<iframe id="chatwoot_live_chat_widget">`** |
| Isolamento de CSS | `all: initial` + 239 `!important` + prefixo `nld-` | **Total** (contexto de documento separado) |
| CSS no host | Folha completa do widget no `<head>` | Apenas `SDK_CSS` (bolha + holder), ~7 KB |
| Vazamento host → widget | **Sim**, provável | **Impossível** |
| Vazamento widget → host | **Sim**, observado (`.calendar-prev`) | Restrito a `.woot-*` |
| `z-index` | `9999999999` | `2147483000` |
| Permissões de mídia | N/A | `iframe.allow = 'camera;microphone;fullscreen;display-capture;picture-in-picture;clipboard-write;'` |
| Comunicação | Chamada direta de método | `postMessage` com `targetOrigin` verificado |
| Ponto de montagem custom | `#nld-custom-container` | Não há equivalente |
| Handlers globais do host | **Sobrescreve** `window.onresize`, `document.onmouseup`, `window.onmousemove` | Usa `addEventListener` |
| `history.pushState` | **Monkey-patched** | Não toca |

O `postMessage` do Chatwoot com verificação de origem:

```js
sendMessage: (key, value) => {
  const element = IFrameHelper.getAppFrame();
  const targetOrigin = element?.src ? new URL(element.src).origin : window.location.origin;
  element.contentWindow.postMessage(`chatwoot-widget:${JSON.stringify({ event: key, ...value })}`, targetOrigin);
}
```

### 12.3 API pública

| | **Leadster** | **Chatwoot / ChatSPX** |
|---|---|---|
| Objeto global | `window.neurolead` (interno, sem contrato) | **`window.$chatwoot`** (documentado) |
| Identificar visitante | **Não existe** | `setUser(identifier, {email, name, avatar_url, identifier_hash})` |
| Verificação de identidade | **Não existe** | **HMAC** via `identifier_hash` |
| Atributos customizados | Não | `setCustomAttributes`, `deleteCustomAttribute`, `setConversationCustomAttributes`, `deleteConversationCustomAttribute` |
| Labels | Não | `setLabel`, `removeLabel` |
| Abrir/fechar | Não | `toggle('open'\|'close')`, `toggleBubbleVisibility('show'\|'hide')` |
| Idioma em runtime | Não | `setLocale(locale)` |
| Tema | Não | `setColorScheme('light'\|'dark')` |
| Reset | Não | `reset()` |
| Popout | Não | `popoutChatWindow()` |
| **Eventos no `window`** | **Zero** | `chatwoot:ready`, `chatwoot:opened`, `chatwoot:closed`, `chatwoot:error`, `chatwoot:on-message`, `chatwoot:on-start-conversation`, `chatwoot:postback` |

### 12.4 Persistência

| | **Leadster** | **Chatwoot / ChatSPX** |
|---|---|---|
| Identidade | `localStorage["neuroleadUser"]` | Cookie `cw_conversation` (token JWT do widget) |
| Escopo | `domain = hostname` exato | `setCookieWithDomain(..., { baseDomain })` — **subdomínios** |
| Hash de usuário | — | Cookie `cw_user_{websiteToken}` = **MD5** de `{identifier + atributos}` |
| TTL | Permanente (localStorage) | 365 dias (padrão de `setCookieWithDomain`) |
| `SameSite` | `Strict` | `Lax` |
| Campanhas | — | `cw_snooze_campaigns_till` (1 h) |
| Modo anônimo | **Perde tudo** (localStorage) | Perde também, mas cookie tem melhor compatibilidade |

### 12.5 SPA e ciclo de vida

| | **Leadster** | **Chatwoot / ChatSPX** |
|---|---|---|
| Detecção | Monkey-patch de `pushState`/`replaceState` + listener de `click` global | `turbo:before-render`, `turbolinks:before-render`, `astro:before-swap` + `onLocationChangeListener` |
| Reação | **Destrói e remonta**, refaz o bootstrap | **Preserva** via `restoreWidgetInDOM` + `dataset.turboPermanent = true` |
| Estado da conversa | **[INFERÊNCIA] perdido** | Preservado |
| Cobertura de frameworks | Universal (qualquer roteador) | Turbo, Turbolinks, Astro — **não cobre React/Vue Router puros** |

**Este é um empate com lados opostos:** eles têm cobertura universal e comportamento ruim; nós
temos comportamento bom e cobertura restrita a frameworks server-driven. A síntese (monkey-patch
universal **+** preservação de estado) é melhor que os dois.

### 12.6 Peso

| | **Leadster** | **Chatwoot / ChatSPX** |
|---|---|---|
| JS no host (bruto) | 456.101 B | **28.768 B** |
| JS no host (gzip) | 134.576 B | **9.494 B** |
| CSS no host | Embutido no JS (completo) | `SDK_CSS` (bolha/holder) |
| Aplicação de chat | **No host** | **Dentro do iframe** (carregada sob demanda) |
| `cache-control` | `max-age=43200` (12 h) | `max-age=31556952` (1 ano) |

### 12.7 Onde cada um ganha

**A Leadster ganha em:**
- Fluxo conversacional client-side (percepção de velocidade)
- 7 gatilhos de abertura, com config independente desktop/mobile
- Teste A/B nativo de chamadas, com grude em `localStorage`
- Segmentação de fluxo por URL resolvida no servidor
- Atribuição ponta a ponta (CAPI, Measurement Protocol, cross-domain para WhatsApp)
- Teaser com rotação de notificações e continuidade narrativa
- Esconder o widget quando o teclado virtual abre em mobile

**O Chatwoot/ChatSPX ganha em:**
- Isolamento real (iframe)
- API pública completa + eventos de `window`
- Verificação de identidade por HMAC
- 16x mais leve no host
- Preservação de estado em SPA
- Cookie com escopo de domínio-pai
- Notificação sonora real
- Self-host / white-label
- Acessibilidade (o Chatwoot tem `chatBubble.focus()` na gestão de foco; a Leadster não tem nada)

---

## 13. Acessibilidade e i18n

### 13.1 Acessibilidade — [FATO]

Contagem no bundle inteiro:

| Padrão | Ocorrências |
|---|---|
| `aria-*` | **0** |
| `role` | **1** |
| `tabIndex` | **3** |

Não há `aria-live` para anunciar mensagens novas a leitor de tela, não há `role="log"` nem
`role="dialog"`, não há armadilha de foco no painel aberto, não há `aria-label` no botão do
avatar, e não encontrei tratamento de `Escape` para fechar.

Existem rótulos de imagem no dicionário i18n (`avatar`, `logo`, `close_button`, `right_arrow`),
o que sugere uso em atributos `alt` — confirmado no markup:
`<img class="nld-close-white" src="…" alt="${closeButtonLabel}">`. É o mínimo, e é o que há.

**[INFERÊNCIA]** Um leitor de tela navegando um site com Leadster encontra uma `div` sem papel
semântico contendo um chat cujas mensagens novas não são anunciadas. Não passaria numa auditoria
WCAG 2.1 AA. **Isso é uma barra baixa que o ChatSPX pode superar com esforço modesto** — e é
argumento comercial real para clientes com exigência de acessibilidade (setor público,
educação, grandes empresas com política de a11y).

### 13.2 Internacionalização — [FATO]

Idiomas com dicionário no bundle: **`pt-BR`, `en-US`, `es-ES`**. Aparecem também as strings
`de-DE`, `fr-FR`, `it-IT`, mas apenas 1 ocorrência cada — **[INFERÊNCIA]** provavelmente em
listas de país do seletor de telefone internacional, não em dicionários de UI.

Resolução do idioma:

```js
const getCurrentLocale = () =>
  (window.neuroleadDefaultScript || {}).lang || window.neuroleadLanguage || "pt-BR";
```

O idioma vem da configuração do fluxo (`convoScript.lang`), com fallback `pt-BR`. **Não há
detecção pelo `navigator.language`** — contraste com o Chatwoot, que tem
`chatwootSettings.useBrowserLanguage`.

Trecho do dicionário pt-BR (código-fonte original):

```js
const i18n_dictionary = {
  "pt-BR": {
    "input-placeholder": "Sua resposta...",
    "input-birthday": "DD/MM/AAAA",
    "send-text": "Enviar",
    "now": "agora",
    "online_now": "Online agora",
    "powered_by": "Feito com",
    "test_free_leadster": "Teste Grátis Leadster",
    "send_whatsapp": "Falar por WhatsApp",
    "restart_chat": "Reiniciar Chat",
    "new_message": "(1) Nova Mensagem!",
    "error_schedule_line_1": "Não conseguimos agendar sua reunião neste momento 😥",
    "leadster_ai": {
      "input-placeholder": "Qual sua dúvida?...",
      "default_end_conversation_label": "Falar com um atendente",
      "warning_by_idle_timeout": "Ainda por aqui? 👀 Se quiser continuar, é só responder. A sessão expira em 2 minutos.",
      "disconnected_by_idle_timeout": "Opa! A conversa foi encerrada por inatividade. Reinicie o chat para tentar de novo 😉",
      "thumbs_up": "Resposta satisfatória",
      "thumbs_down": "Resposta insatisfatória"
    },
    "wrong_messages": { "phone": "Desculpe, não entendi o seu telefone.", … }
  }
}
```

Observações de produto:
- O tom é **deliberadamente informal e brasileiro** ("Opa!", "Ainda por aqui? 👀"), com emoji
  no corpo das mensagens de sistema. É um alinhamento de marca consistente.
- A pegada de marca é embutida: `"powered_by": "Feito com"`, `"test_free_leadster"`,
  `"Verificado pela Leadster"` no markup, e o rodapé linka para `leadster.com.br/agentes-leadster`
  (ou `shopbot.leadster.com.br` se `companySegment === "E-commerce"`). Removível apenas com
  `whiteLabel: true` na configuração.
- Formatação de datas via **date-fns**; horas exibidas com `zeroPad` manual; timestamps relativos
  ("À 3 minutos") com pluralização por idioma.
- Fuso horário: `newDateWithCompanyTimeZone()` usa `metadata.companyTimeZone`
  (`"America/Sao_Paulo"` no cliente medido) — as janelas de atendimento respeitam o fuso da
  empresa, não o do visitante. Decisão correta.

---

## 14. Estrutura da configuração e do fluxo

### 14.1 Resposta real do bootstrap — [FATO], fonte F8

Chaves de topo (cliente real, valores parcialmente reproduzidos):

```json
{
  "side": "right",
  "title": "Ana - Procoach",
  "avatar": "https://cdn.leadster.com.br/neurolead/img/avatar/3.png",
  "script": [ /* 13 blocos */ ],
  "version": 2,
  "waitTime": 7000,
  "avatarSize": "default",
  "inputColor": "#ecae26",
  "notifications": [],
  "userMainColor": "#4CAF50",
  "requiredFields": ["phone"],
  "robotMainColor": "#4CAF50",
  "tooltipMessage": "<p>🏆 Ei, <strong>atleta</strong>! …</p>",
  "userLightColor": "#eee",
  "robotLightColor": "#ecae26",
  "userAccentColor": "#fff",
  "robotAccentColor": "#000",
  "gaConversionEvent": ["Leadster", "Lead"],
  "fbqConversionEvents": ["Leadster-Lead"],
  "notificationsEnabled": false,
  "notificationsPerSession": 1,
  "notificationsDisplayTime": 20000,
  "tooltipMessageVersionKey": 1,
  "tooltipMessageVersionDate": "2025-10-28 14:04:29",
  "tooltipMessageVersionHash": "b0e99e597126b01f812af74c1b5286a7",
  "isAb": false,
  "isOpenByTriggerOnly": false,
  "triggerSettings": {},
  "companyId": 157735,
  "companyName": "Procoach",
  "companySegment": "Software",
  "companyTimeZone": "America/Sao_Paulo",
  "companyIntegrations": "email",
  "scriptVersionId": 651280,
  "scriptId": 204915,
  "privacyPolicyUrl": null,
  "whiteLabel": false
}
```

Notável: **cada texto tem versão própria** (`tooltipMessageVersionKey`, `...VersionDate`,
`...VersionHash`, e os blocos têm `version_key`/`version_date`/`version_hash`). É a
infraestrutura do teste A/B: cada variante de chamada é versionada individualmente e o
resultado é medido por versão. Isso é mais granular que "duas variantes do chatbot inteiro" —
é **A/B por mensagem**.

### 14.2 Estrutura dos blocos do fluxo — [FATO]

Chaves observadas: `uid`, `say`, `save`, `type`, `from`, `mask`, `multi`, `selector`,
`messages`, `option_scores`, `version_key`, `version_date`, `version_hash`.

Exemplos reais:

```json
{ "uid":"bka8s4tx", "say":"<p>Qual &eacute; o seu <b>nome</b>?</p>" }
{ "uid":"aq1e6x10", "save":"name",  "type":"name" }
{ "uid":"g229cboo", "say":"<p>Prazer <b>{{name}}</b> 👋</p>" }
{ "uid":"wneolocj", "save":"email", "type":"email" }
{ "uid":"of7fd639", "save":"phone", "type":"phone", "mask":"(99) 99999-9999" }
{ "uid":"w0hhkdez", "save":"Colaboradores", "multi":false, "selector":false,
  "from":["1 a 500","501 a 1000","1.001 a 2.000","2.001 a 3.000","Acima de 3.000"] }
```

Elementos de design a registrar:

- **`{{name}}` como interpolação** de respostas anteriores — o `substituteVariables()` também
  suporta `{first-name}` (primeiro nome capitalizado) e `{previous-answer}`.
- **`save: "nosync::0::Iniciar"`** — o prefixo `nosync::` marca campos que **não** vão para o
  CRM. Essa convenção aparece em `getLeadData()`:
  ```js
  t.forEach(item => {
    let k = item.key, v = item.value;
    if (item.hasOwnProperty("then")) { k = item.then.key; v = item.then.value; }
    if (!k.startsWith("nosync::")) e.push({ name: k, value: v });
  });
  ```
- **`option_scores`** — pontuação por opção escolhida. É **lead scoring embutido no fluxo**.
- **`mask`** no formato `(99) 99999-9999` — máscara declarativa.
- Tipos de bloco encontrados nos módulos-fonte: `message`, `selector`, `selector_single`,
  `selector_multi`, `selector_date`, `selector_time`, `selector_messages`, `state_city`,
  `country_state`, `whatsapp_block`, `redirect_block`, `scheduler_block`, `reset_chat`,
  `privacy_policy_message`, `IntlPhone`, `SelectStateCity`, `AdsEventsBlock` (com sub-blocos
  `GoogleAnalytics` e `MetaPixel`), `IaInteractionBlock` (com `Loader`, `QuestionInput`,
  `ResponseEvaluation`, `SkipButton`).
- Validador dedicado: `conversation/src/validators/corporate_email.js` — **rejeita e-mail
  pessoal** (Gmail/Hotmail) quando o fluxo é B2B. Detalhe de produto muito bem pensado.

### 14.3 Arquitetura de módulos do fonte — [FATO], 83 módulos sob `./src/`

```
src/
├── boot.js, chat.js, inject-dom.js, inject-css.js
├── i18n.js, hosts.js, conditional-evaluator.js
├── blink-title.js, notifications_manager.js, popup_manager.js, smart_call.js
├── conversation/
│   ├── index.js
│   └── src/
│       ├── flow.js, input.js, autoinput.js, message.js, footer.js, color.js, timestamp.js
│       ├── blocks/          (14 blocos .js + 9 componentes .jsx)
│       ├── components/      (countdown, location, Spinner)
│       └── validators/      (corporate_email)
├── helpers/                 (13)
│   ├── http_client.js, cookie_helper.js, local_storage.js, event_bus.js
│   ├── device_helper.js, route_listener.js, throttle.js
│   ├── url_helper.js, string_helper.js, whatsapp_helper.js
│   ├── i18n_helper.js, format_date_time.js, ads_configs.js
└── services/
    ├── chat-open-triggers/  (Manager, CooldownPeriodControl + 7 triggers + BaseTrigger)
    └── idle-timeout/        (IdleTimeoutManager, IdleTimeoutFeedback, useIdleTimeout)
```

**[INFERÊNCIA]** É uma arquitetura limpa e bem separada. O `conditional-evaluator.js` e o
`ConditionEvaluator` (`static evaluate(t, e) { const {mainOperator} = …`) implementam ramificação
condicional do fluxo no cliente. O `services/idle-timeout/` gerencia expiração de conversa com
IA (aviso aos 2 min, encerramento depois).

---

## 15. Lacunas: o que NÃO foi possível verificar

Registro explícito, para não induzir a erro:

1. **Métricas reais de Core Web Vitals.** Não rodei Lighthouse nem coletei dados de campo.
   Tudo na seção 8.4 é inferência a partir do código.
2. **Ordem e timing exatos dos requests em runtime.** O diagrama da seção 4.1 é derivado da
   leitura do código, não de um waterfall de DevTools.
3. **Conteúdo do painel administrativo** (`app.leadster.com.br/implementation/*`) — exige login.
   Não acessado.
4. **Se existe allowlist de domínio configurável** no painel que corrigiria o achado 11.2. O
   cliente testado pode simplesmente não tê-la ativado.
5. **Uso real de `leadster_ai_interaction` e `neuroled_location_list`** — strings presentes no
   bundle, uso não confirmado.
6. **Cookie `privacy_policy_{…}`** — template de chave presente, gravação não observada.
7. **Preços, número de clientes, volume de leads** — fora do escopo desta task técnica e não
   investigados.
8. **Comportamento visual real** (animações, responsividade, contraste medido) — exigiria
   execução em navegador.
9. **O widget de e-commerce (ShopBot)** — `widget-ecommerce.min.js` (111 KB) foi identificado
   no bucket mas **não** analisado. É um produto separado e mereceria uma task própria.
10. **Rate limiting nas rotas da API.** Não testei, porque testar significaria enviar volume
    contra infraestrutura de terceiro.

---

## 16. IMPLICAÇÕES PARA O CHATSPX

Recomendações apenas. Nenhum código foi escrito, nenhuma decisão foi tomada.

### 16.1 A implicação estratégica que muda o enquadramento

**Achado:** a Leadster roda Chatwoot 4.5.2 como backend de atendimento humano (seção 7).

**Implicação:** o problema não é "construir um concorrente da Leadster". É "construir a camada
de captura conversacional sobre uma base que já temos e que já é mais completa que a deles".
Eles tiveram que adotar Chatwoot; nós **somos** Chatwoot, com Captain/IA, Flow e relatórios em
cima.

**Recomendação:** enquadrar a evolução do widget web como **camada de aquisição sobre o
ChatSPX**, não como produto novo. E, comercialmente, considerar que a arquitetura deles valida
a nossa — não o contrário.

### 16.2 Decisão de arquitetura mais importante: manter o iframe

**Achado:** eles abandonaram o iframe e pagam com 239 `!important`, vazamento de CSS nos dois
sentidos, 456 KB no host e sobrescrita de handlers globais do site do cliente.

**Recomendação: não repetir esse erro.** Manter o iframe do Chatwoot. Ele nos dá isolamento
real, peso 16x menor no host e imunidade ao CSS do cliente. O custo do iframe é a comunicação
por `postMessage`, que já está implementada e funcionando.

**Onde ceder um pouco:** a única vantagem real do DOM direto é o teaser/nudge parecer parte da
página. Isso pode ser resolvido com um **segundo iframe pequeno** para o teaser, ou com o
teaser no DOM (leve, poucas regras, bem prefixado) e o chat no iframe. Híbrido, não binário.

### 16.3 Copiar: os 7 gatilhos com configuração separada desktop/mobile

**Achado:** `screen_time`, `page_scroll`, `cursor_outside` (exit intent), `inactivity_time`,
`page_click`, `clicked_at`, `page_access` — cada um com **configuração independente** para
desktop e mobile, e cooldown por cookie com chave
`cooldown_{tipo}_{dispositivo}_{scriptId}`.

**Recomendação:** implementar o conjunto. É a funcionalidade de maior impacto direto em
conversão e a de menor complexidade técnica de todo o relatório. Adotar também o contrato
`BaseTrigger` (abstrato, `static TYPE`, `initialize`/`clean`/`openChat`/`tearDown`), que é um
bom desenho e torna cada gatilho novo trivial.

**Melhorar em relação a eles:** adicionar gatilho por **regex de URL** e por **UTM** no cliente
(eles só têm isso no servidor), e permitir combinação booleana de gatilhos.

### 16.4 Copiar: segmentação de fluxo resolvida no servidor

**Achado:** `path`, `host`, `query` e `platform` vão no bootstrap; **o servidor decide qual
fluxo entregar**.

**Recomendação:** adotar esse padrão. Mantém a regra de segmentação no backend (auditável,
alterável sem deploy de front) e o cliente burro. É melhor que embutir regras de roteamento no
widget.

**Cuidado:** eles enviam `window.location.search` **inteiro**, o que coleta PII acidental de
sites que passam dados na URL. **Recomendação: enviar uma allowlist de parâmetros** (UTMs,
`gclid`, `fbclid`, `msclkid`) em vez da query crua.

### 16.5 Copiar: atribuição ponta a ponta — o diferencial real deles

**Achado:** o que a Leadster vende não é a UI do chat. É a resposta para "de qual campanha veio
essa venda". A pilha: cookies `ll_*` (~40 parâmetros, 30 dias) → recriação de `_fbc`/`_gcl_aw`
como first-party → propagação de cookies + `client_id`/`session_id` do GA4 na query string do
link de saída para o WhatsApp → Meta CAPI e GA4 Measurement Protocol server-side com PII
hasheada em SHA-256.

**Recomendação:** priorizar isso. É a lacuna competitiva mais valiosa e a que menos aparece
numa comparação superficial de features. Especificamente:

1. **Persistência de parâmetros de campanha** em cookie first-party (podemos fazer melhor:
   `domain` do domínio-pai, como já fazemos com `setCookieWithDomain`).
2. **Propagação de contexto no clique para o WhatsApp.** Hoje perdemos o rastro exatamente ali.
   Isso conversa diretamente com o que já temos mapeado sobre WhatsApp interativo nas automações.
3. **Envio server-side (CAPI / Measurement Protocol)** a partir do backend, com credencial
   armazenada por conta — modelo `credential_id` deles é o padrão certo, e já temos
   `account_integrations` para guardar credencial.
4. **Hash SHA-256 no cliente** via `crypto.subtle` antes de qualquer envio de PII para
   plataformas de anúncio.

**Não copiar o bug:** eles gravam `_fbc` com aspas JSON (seção 9.3, item 3), o que
provavelmente degrada o matching e pode corromper o cookie do Pixel do cliente. Se
implementarmos, gravar valor cru.

### 16.6 Copiar: detalhes de UX pequenos e de alto retorno

| Detalhe | Onde está | Por que copiar |
|---|---|---|
| Esconder o widget no `focusin` de input em mobile | seção 9.8 | Elimina a briga com o teclado virtual. Barato e sensível. |
| Indicador de digitação 2 s antes do teaser | seção 9.7 | Cria presença sem enganar sobre o conteúdo. |
| Última notificação vira 1ª mensagem do chat | seção 9.7 | Continuidade narrativa entre teaser e conversa. Detalhe fino. |
| `#nld-custom-container` como ponto de montagem | seção 5.1 | Permite ao cliente posicionar o widget no layout dele. |
| Validador de e-mail corporativo | seção 14.2 | Rejeita Gmail/Hotmail em fluxo B2B. Qualifica o lead na origem. |
| `nosync::` como prefixo de campo não sincronizado | seção 14.2 | Convenção simples para campos de controle. |
| `option_scores` (lead scoring no fluxo) | seção 14.2 | Pontuação por resposta, sem depender do CRM. |
| Fuso da empresa nas janelas de atendimento | seção 13.2 | Correto por padrão. |
| A/B **por mensagem**, com hash e versão | seção 14.1 | Mais granular que A/B do bot inteiro. |
| "Grude" da variante A/B em `localStorage` | seção 9.2 | Visitante recorrente vê sempre a mesma variante. |

### 16.7 NÃO copiar

| Prática deles | Por quê |
|---|---|
| Sobrescrever `window.onresize`, `document.onmouseup`, `window.onmousemove` com `=` | Destrói handlers do site do cliente. **Sempre `addEventListener`.** |
| Piscar `document.title` do host (`BlinkTitle`) | Dark pattern hostil, manipula a aba do cliente. Se algum dia for pedido, que seja **opt-in explícito** do cliente. |
| Injetar o **nosso** GA4 no site do cliente | `G-43W2WYML5H` sem opt-in é abuso de confiança. Se precisarmos de telemetria, usar canal próprio e declarar. |
| Publicar sourcemaps e builds de debug em produção | Foi o que permitiu este relatório citar o código-fonte deles. |
| Bucket de CDN com listagem pública | Expõe assets históricos, fluxos e nomes de cliente. |
| `access-control-allow-origin: *` no bootstrap com o fluxo completo | Ver 16.8. |
| Consentimento com padrão permissivo | `consentRequired: false` por omissão é risco de LGPD para o cliente. |
| `Math.random()` para identificador usado server-side | `crypto.getRandomValues()` / `crypto.randomUUID()`. |
| Destruir e remontar o widget a cada troca de rota SPA | Perde a conversa. Nós já fazemos melhor. |

### 16.8 Segurança: fazer o que eles não fizeram

**Achado:** o ID do cliente funciona de qualquer domínio; o `host` é ecoado do parâmetro;
`access-control-allow-origin: *`; o fluxo completo é entregue a qualquer origem.

**Recomendações:**

1. **Allowlist de domínios por inbox**, validada contra o header `Origin`/`Referer` no
   servidor — não contra um parâmetro que o cliente controla. Com modo "somente aviso" durante
   a migração, para não quebrar clientes existentes.
2. **`Access-Control-Allow-Origin` refletindo a origem validada**, não `*`.
3. **Manter e divulgar o `identifier_hash` (HMAC)** que já temos. É uma vantagem competitiva
   real sobre eles e está subutilizada.
4. **Não publicar sourcemaps de produção**; se o bundle do widget for para bucket, **desabilitar
   listagem**.
5. **Rate limiting** nas rotas públicas do widget por `website_token` + IP.

### 16.9 Acessibilidade: uma vantagem barata de conquistar

**Achado:** 0 `aria-*`, 1 `role`, 3 `tabIndex` no widget inteiro deles.

**Recomendação:** tratar a11y como diferencial explícito. O mínimo que já os supera:
`role="dialog"` + `aria-modal` no painel, `aria-live="polite"` na lista de mensagens,
`aria-label` no botão da bolha, armadilha de foco enquanto aberto, `Escape` para fechar, e
contraste AA verificado nas cores configuráveis pelo cliente (o painel deles deixa escolher
qualquer cor, sem validar contraste — nós podemos validar).

Isso destrava clientes de setor público, educação e grandes contas com política de
acessibilidade — mercados onde a Leadster hoje não pode entrar.

### 16.10 Performance: preservar a vantagem que já temos

**Achado:** 28.768 B (nós) contra 456.101 B (eles) no host. **15,9x.**

**Recomendação:** tratar isso como métrica de produto, não detalhe técnico. Estabelecer um
**orçamento de bytes para o loader** (sugestão: teto de 40 KB brutos) e verificar em CI. É um
argumento de venda concreto para qualquer cliente que meça Core Web Vitals — e um que a
Leadster estruturalmente **não pode** igualar sem reescrever para iframe.

Complementos baratos: `preconnect` para o host do widget no snippet, `cache-control` longo (já
temos 1 ano contra os 12 h deles), e manter a aplicação pesada dentro do iframe.

### 16.11 Ordem sugerida de ataque

Do maior retorno sobre esforço para o menor:

1. **Gatilhos de abertura** (7 tipos, config desktop/mobile separada, cooldown) — maior impacto
   em conversão, menor complexidade.
2. **Teaser/nudge com rotação e continuidade** para a primeira mensagem.
3. **Persistência de parâmetros de campanha + propagação no clique para WhatsApp** — fecha o
   buraco de atribuição.
4. **Segmentação de fluxo por URL resolvida no servidor** (com allowlist de parâmetros).
5. **Envio server-side para Meta CAPI / GA4 Measurement Protocol** com credencial por conta.
6. **Allowlist de domínios por inbox** (segurança).
7. **Acessibilidade AA** no widget.
8. **A/B por mensagem** com versionamento e grude.
9. **Detalhes de UX** da tabela 16.6.

---

## 17. Apêndice: índice de artefatos coletados

Todos em `/tmp/claude-1001/-home-chatwoot-chatwoot/5e12fcca-428e-43db-aae2-3b28f6866230/scratchpad/leadster/`
(diretório temporário de sessão, fora do repositório):

| Arquivo | Bytes | Origem |
|---|---|---|
| `neurolead-plain.js` / `n.js` | 456.101 | Bundle de produção |
| `dbg.js` | 1.036.439 | Build de debug (nomes originais) |
| `mods.json` | — | 199 módulos extraídos do build de debug |
| `ll.js` | 6.038 | Script de tracking `window.ll` |
| `ll.map` | 8.034 | Sourcemap do tracking |
| `cfg.json` | 3.470 | Config real de cliente (bootstrap legítimo) |
| `cfg-forjado.json` | 3.470 | Config obtida com host forjado (teste 11.2) |
| `hdr-search.txt`, `h1.txt` | — | Headers das duas requisições |
| `bucket.xml` | — | Listagem do bucket `neuro-cdn` |
| `wp/leadster-marketing-conversacional/` | — | Plugin WordPress oficial descompactado |
| `cw-sdk.js` | 28.768 | `sdk.js` do Chatwoot da Leadster (comparação) |

**Nenhum arquivo do repositório ChatSPX foi modificado.** O único arquivo escrito no repositório
é este relatório.

---

*Relatório produzido em 11/08/2026 por análise estática de assets públicos. Widget Leadster
versão 2.67.0 (publicado em 31/07/2026); script de tracking 1.1.1; backend de atendimento
Chatwoot 4.5.2.*
