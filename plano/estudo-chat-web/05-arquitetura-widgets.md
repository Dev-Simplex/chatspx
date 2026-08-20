# 05 — Engenharia de Widgets de Chat: o estado da arte (2026)

> **Documento de estudo. Nenhum código foi alterado.**
> Fase: estudo puro (TASK 05). Nada aqui é implementação — é a base técnica para as
> decisões posteriores de evolução do widget web do ChatSPX.
>
> - **Autor:** worker de pesquisa (Orca / task_7b8fbd696600)
> - **Data da coleta:** 11 de agosto de 2026
> - **Repositório inspecionado (somente leitura):** `/home/chatwoot/chatwoot`, branch `homologacao`
> - **Escopo:** engenharia do problema "widget de chat de site", não avaliação de fornecedor

---

## 0. Como ler este documento

### 0.1 Convenções de veracidade

Todo parágrafo relevante é marcado com uma destas etiquetas:

| Etiqueta | Significado |
|---|---|
| **[FATO]** | Verificado por mim, agora, com fonte citada: URL pública, resposta HTTP real, ou arquivo do repositório com caminho e linha. |
| **[MEDIDO]** | Número obtido por medição própria em 11/08/2026 (`curl`, `gzip`, leitura de manifest). Reprodutível — o comando está junto. |
| **[INFERÊNCIA]** | Conclusão minha a partir dos fatos acima. Pode estar errada. |
| **[NÃO VERIFICADO]** | Afirmação que circula na literatura mas que **não** consegui confirmar em fonte primária. Tratar como hipótese. |

### 0.2 O que este documento não é

- Não é uma comparação comercial de fornecedores (isso é assunto de outra task do estudo).
- Não contém código para colar. Os snippets são **ilustrativos** ou **citações de código público de terceiros**.
- Não recomenda uma implementação específica sem antes a seção 15 (Implicações), que é onde as recomendações vivem.

### 0.3 Método

1. Leitura integral de `app/javascript/sdk/` e leitura dirigida de `app/javascript/widget/`,
   `app/javascript/shared/helpers/`, `app/controllers/widgets_controller.rb`,
   `app/models/channel/web_widget.rb`, `config/initializers/rack_attack.rb`.
2. Download e inspeção estática dos bundles públicos de Leadster, Crisp, Intercom, Zendesk,
   Drift, Botpress e Typebot (`curl` + `grep`/`python3`, sem autenticação, sem burlar paywall).
3. Leitura de documentação primária: MDN, W3C/WAI, WebKit blog, Chrome Developers,
   docs oficiais de Intercom / Zendesk / Chatwoot / Botpress.
4. Consulta à API pública do GitHub para licenças e estado dos projetos open source.

---

## Sumário

| § | Tema |
|---|---|
| 1 | Anatomia de um widget de chat — as sete camadas |
| 2 | Loader / embed: síncrono, async, defer, stub queue, GTM, CMS, SPA |
| 3 | Isolamento: iframe × Shadow DOM × prefixo de classe |
| 4 | Transporte em tempo real: WebSocket, SSE, long-polling, reconexão, entrega |
| 5 | Estado e persistência: cookies, ITP, storage, identidade, continuidade |
| 6 | Segurança: XSS, sanitização, clickjacking, CSP, SRI, HMAC, rate limit, abuso |
| 7 | Performance: orçamento de bytes, facade, code splitting, Core Web Vitals |
| 8 | Acessibilidade: WCAG 2.2, ARIA `log`, teclado, foco, leitores de tela |
| 9 | Mobile web: teclado virtual, `visualViewport`, safe-area, PWA, handoff |
| 10 | Internacionalização: idiomas, RTL, datas, fuso do horário de atendimento |
| 11 | Observabilidade: monitorar um widget que roda no site dos outros |
| 12 | Backend: modelo de dados, presença, roteamento, filas, webhooks, idempotência |
| 13 | Referências open source: o que cada projeto resolve bem, e a licença |
| 14 | Benchmarks medidos em 11/08/2026 |
| 15 | **IMPLICAÇÕES PARA O CHATSPX** |
| A | Anexos: checklists de implementação e de revisão |

---

## 1. Anatomia de um widget de chat — as sete camadas

Todo widget de chat de site, independentemente do fornecedor, se decompõe nas mesmas
sete camadas. Confundir camadas é a origem de quase todo bug difícil deste domínio.

```
┌─────────────────────────────────────────────────────────────────────┐
│ (7) BACKEND: conversa, mensagem, contato, presença, roteamento      │
├─────────────────────────────────────────────────────────────────────┤
│ (6) TRANSPORTE: WebSocket / SSE / polling + REST para escrita       │
├─────────────────────────────────────────────────────────────────────┤
│ (5) APLICAÇÃO: a UI do chat (lista, composer, anexos, formulários)  │
├─────────────────────────────────────────────────────────────────────┤
│ (4) ISOLAMENTO: iframe / Shadow DOM / prefixo — a fronteira de CSS  │
├─────────────────────────────────────────────────────────────────────┤
│ (3) PONTE: postMessage entre host e widget; API pública window.*    │
├─────────────────────────────────────────────────────────────────────┤
│ (2) CHROME: bolha, badge, animação, posição — vive no DOM do host   │
├─────────────────────────────────────────────────────────────────────┤
│ (1) LOADER: 2–10 KB, decide se/quando carregar as camadas 2–6       │
└─────────────────────────────────────────────────────────────────────┘
```

**[INFERÊNCIA]** A separação (1)↔(5) é a decisão de arquitetura mais consequente do
produto inteiro. Ela determina o orçamento de bytes de 90–97% dos visitantes que nunca
abrem o chat (ver §7.1), determina se o widget quebra o CSS do cliente (§3), e determina
o custo de suporte de instalação (§2.5).

**[FATO]** O Chatwoot faz essa separação: `sdk.js` é o loader + chrome (camadas 1–3) e
`/widget` é a aplicação dentro de um iframe (camadas 4–6).
Ver `app/javascript/entrypoints/sdk.js:213-216` e `app/javascript/sdk/IFrameHelper.js:57-91`.

**[FATO]** A Leadster **não** faz essa separação: o `neurolead.min.js` é um monolito
único que contém loader, chrome, aplicação e transporte, injetado direto no DOM do host.
Verificado por download e análise estática do bundle público (§14).

---

## 2. Loader / embed

### 2.1 O espectro síncrono → async → defer → lazy

| Estratégia | Bloqueia o parser? | Ordem garantida? | Quando executa | Adequação para chat |
|---|---|---|---|---|
| `<script src>` (síncrono) | **Sim** | Sim | Ao encontrar a tag | ❌ Nunca. Bloqueia render do site do cliente. |
| `<script async src>` | Não (download), sim (exec) | **Não** | Assim que baixar | ⚠️ Aceitável para o loader; a execução ainda cai no meio do parse. |
| `<script defer src>` | Não | Sim | Antes do `DOMContentLoaded` | ✅ Bom para o loader. |
| Injeção dinâmica (`createElement('script')`) | Não | Não | Quando o código injetor rodar | ✅ Padrão de mercado; escapa do preload scanner. |
| Injeção após `load` + `requestIdleCallback` | Não | Não | Depois do site estar pronto | ✅✅ Melhor para Core Web Vitals. |
| Injeção na 1ª interação (facade) | Não | Não | `mousemove`/`scroll`/`touchstart`/clique | ✅✅✅ Impacto zero para quem não interage. |

**[FATO]** A recomendação de injetar dinamicamente após o evento `load` dentro de um
`requestIdleCallback` é documentada com código em
<https://www.corewebvitals.io/pagespeed/chat-widget-perfect-core-web-vitals>, que registra
melhora do impacto no Lighthouse de "9–16 pontos" para "0–1 ponto".

```javascript
// [CITAÇÃO — corewebvitals.io, ilustrativo]
window.addEventListener('load', function () {
  requestIdleCallback(function () {
    var s = document.createElement('script');
    s.src = 'https://your-chat-widget-url.com/chat.js';
    document.body.appendChild(s);
  });
});
```

**[FATO]** O Google Chrome documenta o padrão **facade** — "um elemento estático que se
parece com o terceiro embutido, mas não é funcional e por isso é muito menos custoso no
carregamento" — e lista explicitamente **widgets de chat (Intercom, Drift, Help Scout,
Facebook Messenger)** entre os alvos.
Fonte: <https://developer.chrome.com/docs/lighthouse/performance/third-party-facades/>

O ciclo documentado do facade é: **carga da página** → facade renderizado; **hover** →
facade faz `preconnect`; **clique** → facade se substitui pelo produto real. O exemplo
numérico do Chrome é do YouTube: facade de 3 KB substituindo player de 540 KB.

**[FATO]** O mesmo documento avisa da contrapartida: facades implicam limitações
funcionais, "como badges de notificação atrasados para widgets de chat que carregam de
forma assíncrona".

**[INFERÊNCIA]** Essa contrapartida é resolvível: o facade pode buscar a contagem de não
lidas por um `fetch` de ~1 KB (ou por um cookie já gravado numa sessão anterior) sem
carregar o app inteiro. Nenhum fornecedor que inspecionei faz isso — é uma oportunidade.

### 2.2 O padrão "stub queue"

O problema: o site do cliente quer chamar `Chat('boot', {...})` na linha seguinte ao
snippet, mas o bundle ainda não baixou. Sem stub, isso é `TypeError`.

A solução canônica (a mesma do `gtag()` do Google, do `fbq()` do Facebook e do `ic()` do
Intercom) é publicar imediatamente uma **função-tampão que só empilha argumentos**, e
deixar o bundle real drenar a fila quando chegar.

**[FATO]** Snippet oficial do Intercom, reproduzido verbatim de
<https://developers.intercom.com/installing-intercom/docs/intercom-javascript>:

```javascript
(function(){
  var w = window;
  var ic = w.Intercom;
  if (typeof ic === "function") {
    ic('update', w.intercomSettings);
  } else {
    var d = document;
    var i = function(){ i.c(arguments); };   // <- o stub
    i.q = [];                                 // <- a fila
    i.c = function(args){ i.q.push(args); };  // <- o empilhador
    w.Intercom = i;
    var l = function(){
      var s = d.createElement('script');
      s.type = 'text/javascript';
      s.async = true;
      s.src = 'https://widget.intercom.io/widget/' + APP_ID;
      var x = d.getElementsByTagName('script')[0];
      x.parentNode.insertBefore(s, x);
    };
    if (document.readyState === 'complete') { l(); }
    else if (w.attachEvent) { w.attachEvent('onload', l); }
    else { w.addEventListener('load', l, false); }
  }
})();
```

Três coisas merecem atenção nesse snippet, além da fila:

1. **Idempotência do snippet.** A primeira linha (`if (typeof ic === "function")`) trata o
   caso de o snippet ser colado duas vezes (o clássico "está no tema *e* no GTM"). Em vez
   de carregar duas vezes, vira um `update`.
2. **Espera pelo `load`.** O Intercom só injeta o bundle depois do `load` da página — a
   mesma ideia de §2.1, embutida no snippet.
3. **`insertBefore` no primeiro `<script>`** em vez de `appendChild` no `<head>`. Isso
   funciona mesmo em documentos malformados sem `<head>` explícito.

**[MEDIDO]** O que esse snippet baixa (`https://widget.intercom.io/widget/<APP_ID>`)
respondeu **3.159 bytes** em 11/08/2026. Ou seja: o "bundle" da URL do snippet ainda é um
segundo loader, não a aplicação.

**[FATO]** O **Crisp** usa a mesma família de padrão, com uma sentinela global explícita.
Extraído do bundle público `https://client.crisp.chat/l.js` (v4.9.2, build `4ea1f89`):

```javascript
this.l = "$__CRISP_INSTANCE";
this.p = "$__CRISP_INCLUDED";
// ...
if (window[this.p] === true || (window[this.l] !== undefined
    && typeof window[this.l].__init === "function")) { /* aborta */ }
```

**[FATO]** A **Leadster não usa stub queue.** O snippet oficial, retirado do plugin
WordPress publicado pela própria empresa
(<https://wordpress.org/plugins/leadster-marketing-conversacional/>, arquivo
`views/script-code.php`), é:

```html
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
  })(window, document,
     "https://cdn.leadster.com.br/neurolead/neurolead.min.js",
     "<?php echo esc_attr($leadster_script_code) ?>");
</script>
<!--END LEADSTER SCRIPT-->
```

Observações sobre este snippet, todas verificáveis no arquivo acima:

- **Configuração por variável global mutável** (`window.neuroleadId`), não por argumento de
  função. Não há API de comandos, não há fila, não há `boot()`.
- **`defer = true` numa tag injetada dinamicamente.** Scripts injetados via
  `createElement` já são assíncronos por padrão; `defer` neles é
  [ignorado](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/script#defer).
  **[INFERÊNCIA]** É um no-op — provavelmente cargo cult de um snippet estático anterior.
- **`try/catch` engolindo silenciosamente qualquer erro** (`catch (e) {}`). Protege o site
  do cliente, mas torna a falha de instalação invisível. **[INFERÊNCIA]** É uma troca
  deliberada: prefere-se um chat que não aparece a um site que quebra.
- **Injeção no `<head>`, mas o plugin o imprime no `wp_footer`** (`leadster.php:229`,
  `add_action("wp_footer", "leadster_add_widget_to_footer")`). Na prática o efeito é
  equivalente a estar no fim do body.

**[FATO]** O snippet oficial do **Chatwoot** (e portanto o herdado pelo ChatSPX) está
gerado no próprio modelo, em `app/models/channel/web_widget.rb`, método `web_widget_script`:

```javascript
(function(d,t) {
  var BASE_URL="<FRONTEND_URL>";
  var g=d.createElement(t), s=d.getElementsByTagName(t)[0];
  g.src = BASE_URL + "/packs/js/sdk.js";
  g.async = true;
  s.parentNode.insertBefore(g,s);
  g.onload = function(){
    window.chatwootSDK.run({ websiteToken: '<website_token>', baseUrl: BASE_URL })
  }
})(document,"script");
```

**[INFERÊNCIA]** O Chatwoot escolheu **callback `onload` em vez de stub queue**. As
consequências práticas:

- Não existe fila: qualquer `window.$chatwoot.*` chamado antes do `onload` é `TypeError`.
- Por isso a documentação obriga o cliente a envolver tudo em
  `window.addEventListener("chatwoot:ready", ...)` — o que é uma **API assíncrona exposta
  como se fosse síncrona**, e é a fonte número um de bug de integração.
- O `onload` sobrescreve qualquer `onload` que já existisse naquele elemento — aqui é
  inofensivo porque o elemento é recém-criado.
- Não há sentinela de dupla inclusão no snippet; a proteção existe uma camada adiante
  (`if (window.$chatwoot) return;` em `entrypoints/sdk.js:22-24`). Funciona, mas **depois**
  de já ter baixado o bundle duas vezes.

### 2.3 Tabela de decisão: como o loader deve se comportar

| Requisito | Técnica | Custo |
|---|---|---|
| Não bloquear render | injeção dinâmica | nenhum |
| Não competir com o LCP | injetar após `load` + `requestIdleCallback` | badge de não lidas atrasa |
| Zero impacto para quem não interage | facade + carregar na 1ª interação | perde proatividade (campanha, convite) |
| API utilizável imediatamente | stub queue (`q`/`c`) | ~200 bytes |
| Resistente a dupla inclusão | sentinela em `window` no **snippet** | ~80 bytes |
| Resistente a SPA/navegação | ver §2.6 | ver §2.6 |
| Não quebrar o site se o CDN cair | `try/catch` + `onerror` no script | falha silenciosa (ver §11) |

### 2.4 Instalação via Google Tag Manager

**[FATO]** A Leadster documenta GTM como um dos quatro caminhos oficiais, com a instrução
de manter "Todas as páginas" e marcar **"Body – fim"**.
Fonte: <https://help.leadster.com.br/article/36-instrucoes-para-ativar-o-chat>

Armadilhas reais do GTM para widgets de chat, todas consequência de como o GTM funciona:

1. **O GTM já é assíncrono.** Uma tag Custom HTML dentro do GTM roda depois do
   `gtm.js`, que roda depois do snippet do GTM. O widget herda toda essa latência —
   tipicamente centenas de ms a mais do que a instalação direta.
2. **`document.write` é proibido** dentro do GTM (é reescrito). Snippets legados que usam
   `document.write` simplesmente não funcionam.
3. **Disparo em SPA.** Se o gatilho for "Page View", numa SPA a tag dispara uma vez só;
   se for "History Change", dispara a cada rota e **precisa** da sentinela de dupla
   inclusão, ou o site carrega N widgets.
4. **Consent Mode.** Se a conta usa Consent Mode v2, a tag pode ser bloqueada até o
   consentimento — o chat some para quem recusou cookies. **[INFERÊNCIA]** Isso é
   geralmente indesejado: um chat de suporte costuma ser *legítimo interesse*, não
   marketing, e não deveria depender de consentimento de publicidade. Mas essa decisão é
   jurídica, não técnica.
5. **Ordem com o CMP.** Um banner de cookies que injeta um overlay com `z-index` alto pode
   cobrir a bolha (ver §3.7).

### 2.5 Instalação via plugin de CMS

**[FATO]** O plugin WordPress da Leadster é minúsculo (22.690 bytes no `.zip`) e faz
exatamente três coisas: um campo de texto no admin para o ID, `update_option`, e o
`include` do snippet no `wp_footer`.

**[INFERÊNCIA]** É a arquitetura correta para um plugin de CMS: o plugin não é o produto,
é apenas um *campo de configuração com um lugar seguro para imprimir*. Plugins que tentam
fazer mais (renderizar a bolha em PHP, cachear o bundle localmente, injetar CSS) quebram
com temas e caches de página.

Boas práticas específicas de plugin de CMS:

- Imprimir no `wp_footer`, nunca no `wp_head` (evita competir com o LCP).
- Escapar o ID (`esc_attr`) — o plugin da Leadster faz isso.
- **Não** imprimir em `is_admin()`, nem em páginas AMP, nem em requisições REST.
- Oferecer o toggle "não carregar para usuários logados" (economiza carga em intranet/e-commerce).
- Declarar compatibilidade com os caches (WP Rocket, LiteSpeed) para não terem o script
  atrasado duas vezes (o cache já atrasa; atrasar de novo dobra o tempo até a bolha).

### 2.6 Instalação em SPA (Next.js, Nuxt, Vue Router, Turbo)

Este é o ponto onde as arquiteturas divergem de verdade.

**O problema:** numa SPA, a página nunca recarrega. O widget precisa (a) sobreviver às
trocas de rota, (b) saber que a rota mudou (para campanhas por URL, para o `referer` da
conversa), e (c) não vazar memória.

**[FATO]** O Intercom resolve por polling explícito do cliente: a documentação instrui
chamar `Intercom('update')` "sempre que a view ou a URL mudar no seu app".
Fonte: <https://developers.intercom.com/installing-intercom/docs/intercom-javascript>

**[INFERÊNCIA]** Isso empurra a responsabilidade para o cliente — e é a razão pela qual
existem tantos wrappers de terceiros (`react-use-intercom`, `ember-intercom-io`,
`angular-intercom`): cada framework precisa de cola própria para chamar `update()`.

**[FATO]** O Chatwoot resolve **sozinho**, com um `MutationObserver` no `<body>` inteiro:

```javascript
// app/javascript/sdk/DOMHelpers.js:49-75
export const onLocationChangeListener = () => {
  let oldHref = document.location.href;
  const referrerHost = document.location.host;
  const config = { childList: true, subtree: true };   // <- body inteiro, recursivo
  onLocationChange({ referrerURL: oldHref, referrerHost });

  const bodyList = document.querySelector('body');
  const observer = new MutationObserver(mutations => {
    mutations.forEach(() => {
      if (oldHref !== document.location.href) {
        oldHref = document.location.href;
        onLocationChange({ referrerURL: oldHref, referrerHost });
      }
    });
  });
  observer.observe(bodyList, config);
};
```

**[INFERÊNCIA]** Esta é a decisão mais cara do SDK do Chatwoot, e merece um parágrafo:

- Um `MutationObserver` com `subtree: true` no `<body>` recebe callback para **toda**
  mutação do DOM da página inteira do cliente. Num app React/Vue típico com lista virtual,
  animação, ou um dashboard, isso é milhares de callbacks por segundo.
- O corpo do callback é barato (uma comparação de string) mas o `mutations.forEach`
  itera o array inteiro de mutações a cada lote — trabalho O(n) por lote, em cima da main
  thread do cliente. Em INP, isso conta.
- A API correta desde 2022 é a **Navigation API** (`navigation.addEventListener('navigate')`,
  Chrome 102+) ou, com suporte universal, o *monkey-patch* de `history.pushState` /
  `history.replaceState` + `popstate`. Ambas custam ~0 e são exatas.
- **[NÃO VERIFICADO]** Não medi o impacto real em INP num site com muita mutação; a
  afirmação de custo é analítica, não empírica.

**[FATO]** O Chatwoot também trata explicitamente três frameworks que **substituem o
`<body>`** — Turbo (Rails), Turbolinks e Astro — restaurando os elementos do widget no
novo body (`app/javascript/entrypoints/sdk.js:26-48` e `app/javascript/sdk/DOMHelpers.js:15-28`),
e marcando `dataset.turboPermanent = true` nos três nós que cria
(`widgetHolder`, `bubbleHolder`, `#cw-widget-styles`).

**[INFERÊNCIA]** Esse tratamento é bem feito e é um diferencial real sobre a Leadster, que
não tem nada equivalente no bundle (nenhuma ocorrência de `turbo`, `turbolinks` ou
`astro:before-swap`). Em site Rails/Hotwire, o widget da Leadster tende a sumir na primeira
navegação.

### 2.7 Checklist do loader

- [ ] Snippet ≤ 1 KB, autocontido, sem dependências.
- [ ] Sentinela de dupla inclusão **dentro do snippet**, antes do download.
- [ ] Stub queue com `q`/`c`, drenada pelo bundle real.
- [ ] Injeção dinâmica; nunca `<script src>` estático no `<head>`.
- [ ] Disparo após `load` (ou na 1ª interação, se o produto aceitar).
- [ ] `try/catch` no snippet + `onerror` no elemento script (reportado, não engolido).
- [ ] `preconnect` para o host do app antes de precisar dele.
- [ ] Detecção de mudança de rota por Navigation API / patch de `history`, não por `MutationObserver` global.
- [ ] Compatibilidade explícita com Turbo/Astro/htmx (frameworks que trocam o `<body>`).
- [ ] Versionamento imutável no path do bundle (`/v4.9.2/app.js`), loader com cache curto.

---

## 3. Isolamento: a fronteira de CSS

### 3.1 As três estratégias

| | **iframe cross-origin** | **Shadow DOM** | **Prefixo de classe + `!important`** |
|---|---|---|---|
| Herança de CSS do host | **Zero** | Zero (exceto herdáveis) | **Total** |
| `!important` do host atinge? | Não | Não | **Sim** |
| Reset de CSS necessário? | Não | Pequeno | **Enorme** |
| Fontes do host disponíveis? | Não (recarregar) | Sim | Sim |
| JS do host atinge o DOM do widget? | Não | Sim (via `shadowRoot`, se `open`) | **Sim** |
| Comunicação | `postMessage` (assíncrona) | chamada direta | chamada direta |
| Custo de bytes | + documento e runtime separados | baixo | baixo |
| Custo de latência | + 1 navegação, + 1 handshake | ~0 | ~0 |
| Redimensionamento dinâmico | precisa de protocolo | natural | natural |
| Autofill / gerenciador de senhas | funciona (é um documento) | funciona | funciona |
| Cookies próprios | **particionados/bloqueados** (§5) | 1st-party do host | 1st-party do host |
| Devtools do cliente | opaco | inspecionável | inspecionável |
| Acessibilidade | árvore separada — foco e `aria-live` não atravessam | árvore unificada | árvore unificada |
| CSP do host precisa liberar | `frame-src` | `script-src` | `script-src` |

**[FATO]** O Zendesk usa iframe: "o Web Widget de messaging renderiza dentro de um iframe
adicionado à página, então o CSS do site pode ajudar no posicionamento, mas não pode
estilizar a UI do widget."
Fonte: <https://support.zendesk.com/hc/en-us/articles/10292484466330-Messaging-Web-Widget-cookbook>

**[FATO]** O Chatwoot usa iframe. `app/javascript/sdk/IFrameHelper.js:63-69`:

```javascript
const iframe = document.createElement('iframe');
const cwCookie = Cookies.get('cw_conversation');
let widgetUrl = IFrameHelper.getUrl({ baseUrl, websiteToken });
if (cwCookie) { widgetUrl = `${widgetUrl}&cw_conversation=${cwCookie}`; }
iframe.src = widgetUrl;
iframe.allow = 'camera;microphone;fullscreen;display-capture;picture-in-picture;clipboard-write;';
```

**[MEDIDO]** A Leadster usa **prefixo de classe no DOM do host**: o bundle não contém
nenhuma ocorrência de `attachShadow`, `shadowRoot`, nem de `createElement("iframe")`.
Contém 239 ocorrências de `!important` e classes prefixadas `nld-*`
(`.nld-conversation`, `.nld-popup`, `.nld-backdrop`, `.nld-typing-indicator`, …).

**[MEDIDO]** O **Typebot** usa Shadow DOM: 3 ocorrências de `attachShadow` e 15 de
`shadowRoot` em `@typebot.io/js@0/dist/web.js`, com os custom elements
`typebot-bubble` e `typebot-standard`.

**[MEDIDO]** O **Botpress** (`webchat/v3.2/inject.js`) não usa Shadow DOM (zero
`attachShadow`); usa um reset de baixa especificidade com `:where()`:

```css
/* extraído do início de inject.js */
:where(.bpReset) *, :where(.bpReset) :after, :where(.bpReset) :before,
:where(.bpReset) ::backdrop, ...
```

**[INFERÊNCIA]** `:where()` tem especificidade zero, o que é a escolha *correta* para um
reset que não quer brigar com o host — mas é também a escolha que **perde** para qualquer
regra do host. É um reset que se rende de propósito. Funciona porque as regras seguintes do
Botpress são de especificidade normal; o `:where()` só zera a herança.

### 3.2 Iframe: armadilhas reais

**Same-origin ou cross-origin?**
Se o widget é servido do mesmo host do site, o iframe é same-origin e o JS do host pode
acessar `iframe.contentDocument` livremente — isso apaga o benefício de isolamento de
segurança e é péssimo para um produto multi-tenant. **[INFERÊNCIA]** Para SaaS, o iframe
deve ser sempre cross-origin (domínio do fornecedor). Para self-hosted colado no mesmo
domínio do site (caso possível no ChatSPX), o isolamento é só de CSS, não de segurança.

**`sandbox`.**
**[FATO]** A MDN e o web.dev alertam que combinar `allow-scripts` com `allow-same-origin`
num iframe de mesma origem "deixa o documento embutido remover o próprio atributo
`sandbox` — tornando-o não mais seguro do que não usar `sandbox`".
Fontes: <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/iframe>,
<https://web.dev/articles/sandboxed-iframes>

**[FATO]** O Chatwoot **não** usa `sandbox` no iframe do widget (verificado em
`IFrameHelper.js:63-91`). Usa apenas `allow=` com uma lista permissiva
(`camera;microphone;fullscreen;display-capture;picture-in-picture;clipboard-write;`).

**[INFERÊNCIA]** `display-capture` num widget de chat é notável: é a permissão de
compartilhamento de tela. Faz sentido se o produto tem videochamada; se não tem, é
superfície de permissão concedida à toa. `clipboard-write` idem.

**Altura e redimensionamento.**
Um iframe não cresce com o conteúdo. É preciso um protocolo. **[FATO]** O Chatwoot tem
esse protocolo: o app dentro do iframe emite `updateIframeHeight` com `extraHeight` e
`isFixedHeight`, e o SDK aplica `height: Npx !important` (`IFrameHelper.js:137-143, 262-266`).

**[INFERÊNCIA]** Reescrever o atributo `style` inteiro
(`iframe.setAttribute('style', 'height: ... !important')`) apaga qualquer outro estilo
inline que o iframe tivesse — inclusive o `visibility: hidden` inicial. No fluxo atual isso
funciona por ordem de eventos, mas é frágil: qualquer reordenação de mensagens vira bug
visual.

**Scroll no host.**
**[FATO]** O Chatwoot intercepta `wheel` no holder para impedir *scroll chaining*
(`IFrameHelper.js:121-135`). **[INFERÊNCIA]** A solução moderna e barata é CSS puro:
`overscroll-behavior: contain` no container rolável. Custa uma linha, funciona em toque e
em teclado, e não gasta um listener não passivo — que é exatamente o tipo de listener que o
Lighthouse sinaliza.

**Foco e acessibilidade.**
**[INFERÊNCIA]** Este é o custo escondido do iframe e quase ninguém fala dele: o iframe é
uma **árvore de acessibilidade separada**. Consequências concretas:
- `aria-live` dentro do iframe **é** anunciado pelo leitor de tela, mas o usuário precisa
  ter entrado no iframe; anúncios de mensagem nova para quem está na página do host são
  perdidos.
- Um focus trap no host não prende o foco dentro do iframe, e vice-versa.
- A bolha (que vive no host) e o painel (que vive no iframe) precisam coordenar foco por
  `postMessage` — o Chatwoot faz o retorno de foco à bolha ao fechar
  (`bubbleHelpers.js:81`, `chatBubble.focus()`), mas não faz o inverso ao abrir.

### 3.3 Shadow DOM: armadilhas reais

- **Propriedades herdáveis atravessam.** `font-family`, `color`, `line-height`,
  `letter-spacing`, `direction` e as *custom properties* (`--*`) do host **entram** no
  shadow root. Isso é frequentemente desejável (herdar a fonte do site) e frequentemente
  desastroso (herdar `line-height: 3` de um tema exótico). O controle é `all: initial` ou
  `all: revert` no `:host`, mais a redeclaração explícita do que se quer herdar.
- **`::part()` e `:host-context()`** dão ao host um canal legítimo de customização —
  usar isso é melhor do que documentar seletores internos, que viram contrato acidental.
- **Estilos globais do host com `!important` não entram** no shadow root: essa é a garantia
  central. Mas o host ainda controla o *elemento hospedeiro* (`display`, `position`,
  `z-index`, `transform`).
- **`transform` no ancestral quebra `position: fixed`.** Se qualquer ancestral do host
  tiver `transform`, `filter`, `perspective`, `backdrop-filter`, `will-change` ou
  `contain: paint`, ele vira o *containing block* e o `position: fixed` do widget passa a
  ser relativo a ele. Isso vale para Shadow DOM e para prefixo; **iframe também sofre**
  (o iframe inteiro é reposicionado). A mitigação real é ancorar o widget como filho
  direto de `<body>` — que é o que Chatwoot e Leadster fazem.
- **Devtools:** `mode: 'open'` deixa o cliente inspecionar (bom para suporte);
  `mode: 'closed'` não impede nada de verdade (o JS do host pode interceptar `attachShadow`
  antes) e só atrapalha o próprio suporte. **[INFERÊNCIA]** Usar `open`.

### 3.4 Prefixo de classe: por que a Leadster escolheu, e o que custa

**[MEDIDO]** 239 `!important` no bundle da Leadster. **[INFERÊNCIA]** Esse número é a
medida direta do custo da escolha: cada `!important` é uma briga perdida-e-recuperada
contra o CSS de algum cliente. É dívida que só cresce — nunca se remove um `!important`
com segurança, porque não se sabe qual cliente dependia dele.

O que se **ganha** com prefixo, e é real:
- Herda a fonte do site sem baixar fonte nova (economia de bytes e de FOUT).
- Zero latência de navegação extra.
- Redimensionamento natural, sem protocolo.
- Uma única árvore de acessibilidade e de foco.
- Cookies e storage 1st-party do host, imunes a particionamento (§5.2).

**[INFERÊNCIA]** Para o mercado da Leadster (conversão/geração de lead em sites de PME,
predominantemente WordPress com temas de terceiros), a herança de fonte é uma *feature*: o
chat parece parte do site. O modelo de negócio dela tolera o custo de suporte de CSS
porque o widget é comercialmente do lado do marketing, não do suporte crítico.

### 3.5 `z-index`: a guerra de fundo

**[MEDIDO]** Valores de `z-index` encontrados nos bundles:

| Produto | `z-index` do container principal |
|---|---|
| Chatwoot / ChatSPX | `2147483000 !important` (`sdk.js:15` e `:53`) |
| Leadster | até `9999999999` (dez noves) |
| Crisp | (não extraído do loader; o app é carregado depois) |

`2147483647` é o máximo de int32; `2147483000` deixa 647 níveis de folga acima — é uma
escolha deliberada e razoável do Chatwoot. `9999999999` **excede** int32 e é clampado pelo
navegador. **[INFERÊNCIA]** Na prática ambos vencem quase tudo, mas o valor da Leadster é
tecnicamente incorreto (fora do intervalo especificado).

**[INFERÊNCIA]** O problema real não é o valor: é o **contexto de empilhamento**. Um
`z-index` de dez bilhões perde para um elemento em outro *stacking context* mais alto. Se o
CMP do cliente cria um contexto com `isolation: isolate` ou `transform`, o widget vai para
baixo dele independentemente do número. A mitigação: ser filho direto de `<body>`, e
oferecer ao cliente um parâmetro de `zIndex` (o Zendesk oferece —
<https://support.zendesk.com/hc/en-us/articles/10292484466330-Messaging-Web-Widget-cookbook>).

### 3.6 `postMessage`: a ponte e sua segurança

**[FATO]** A MDN é explícita em três regras:
1. "Se você não espera receber mensagens de outros sites, **não** adicione listeners de
   `message`."
2. "**Sempre** verifique a identidade do remetente usando as propriedades `origin` e
   possivelmente `source`."
3. "**Sempre** especifique um target origin exato, não `*`."
Fonte: <https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage>

**[FATO]** O Chatwoot acerta o **envio**:

```javascript
// app/javascript/sdk/IFrameHelper.js:94-103
sendMessage: (key, value) => {
  const element = IFrameHelper.getAppFrame();
  const targetOrigin = element?.src ? new URL(element.src).origin : window.location.origin;
  element.contentWindow.postMessage(
    `chatwoot-widget:${JSON.stringify({ event: key, ...value })}`,
    targetOrigin                       // <- correto: origem exata, não '*'
  );
},
```

**[FATO]** E erra a **recepção**:

```javascript
// app/javascript/sdk/IFrameHelper.js:104-117
initPostMessageCommunication: () => {
  window.onmessage = e => {
    if (typeof e.data !== 'string' || e.data.indexOf('chatwoot-widget:') !== 0) {
      return;                          // <- único filtro: prefixo da string
    }
    const message = JSON.parse(e.data.replace('chatwoot-widget:', ''));
    if (typeof IFrameHelper.events[message.event] === 'function') {
      IFrameHelper.events[message.event](message);
    }
  };
},
```

Não há **nenhuma** checagem de `e.origin` nem de `e.source`. Qualquer janela — um popup
aberto pelo site, outro iframe de terceiro na mesma página, um anúncio — pode postar
`"chatwoot-widget:{\"event\":\"setAuthCookie\",\"data\":{\"widgetAuthToken\":\"...\"}}"`
para a janela do host e o SDK executa o handler.

**[INFERÊNCIA — impacto]** Os handlers disponíveis nesse dicionário incluem
`setAuthCookie` (grava o cookie `cw_conversation`), `loaded`, `error` (que remove o cookie
de usuário), `popoutChatWindow`, `toggleBubble` e `setBubbleLabel`. Um terceiro malicioso
na mesma página consegue, no mínimo:
- **Fixar sessão:** gravar um `cw_conversation` de sua escolha, sequestrando a conversa do
  visitante para uma conversa controlada pelo atacante (e lendo o que a vítima escrever).
- **Negação de serviço:** disparar `error` com `SET_USER_ERROR` para apagar o cookie de
  identidade.
- **Phishing de UI:** abrir/fechar a bolha e trocar o rótulo (`setBubbleLabel` grava via
  `innerText`, não `innerHTML` — não é XSS, mas é enganação de UI).

Também vale notar: `window.onmessage = ...` (atribuição de propriedade) **sobrescreve**
qualquer handler que o site do cliente já tivesse registrado por `window.onmessage`. É um
efeito colateral no site alheio. O correto seria `addEventListener`.

**[NÃO VERIFICADO]** Não testei a exploração na prática (isso exigiria montar uma página
de ataque; está fora do escopo de estudo). O raciocínio é por leitura de código.

**Formato de mensagem.** **[INFERÊNCIA]** Usar string com prefixo
(`"chatwoot-widget:" + JSON`) em vez de objeto estruturado é um vestígio de compatibilidade
antiga. `postMessage` suporta *structured clone* desde sempre nos navegadores relevantes;
um objeto `{ ns: 'chatwoot', v: 1, event, payload }` economiza serialização, evita o
`JSON.parse` de string arbitrária e permite versionar o protocolo.

### 3.7 Recomendação de isolamento

**[INFERÊNCIA]** A escolha certa depende do que se otimiza:

| Se o objetivo principal é… | Escolha |
|---|---|
| Não quebrar em 10 mil sites que você não controla | **iframe** |
| Parecer nativo do site do cliente | Shadow DOM |
| Peso mínimo e integração visual profunda | Shadow DOM |
| Suporte a navegadores antigos (< 2019) | iframe |
| Cookies 1st-party garantidos (§5.2) | Shadow DOM ou prefixo |
| Menor custo de suporte de CSS | iframe |
| Melhor acessibilidade de anúncio de mensagem nova | Shadow DOM |

Um **híbrido** é possível e é o que eu recomendaria estudar: **chrome (bolha, badge,
convite proativo) em Shadow DOM no host**, e **painel de conversa em iframe**. Isso dá:
anúncio acessível e badge instantâneo sem carregar o app, e isolamento forte para a parte
pesada. **[NÃO VERIFICADO]** Não encontrei um fornecedor que documente exatamente esse
híbrido; é proposta minha.

---

## 4. Transporte em tempo real

### 4.1 As três opções

| | WebSocket | SSE (`EventSource`) | Long-polling |
|---|---|---|---|
| Direção | bidirecional | servidor→cliente | servidor→cliente (+ POST separado) |
| Reconexão automática | **não** (você escreve) | **sim** (nativa do navegador) | você escreve |
| Retomada por ID | não (você escreve) | **sim** (`Last-Event-ID`) | você escreve |
| Limite de conexões por origem | alto | 6 em HTTP/1.1; **sem limite prático em HTTP/2** | 6 em HTTP/1.1 |
| Passa por proxy corporativo antigo | às vezes não | sim (é HTTP) | sim |
| Cabeçalhos customizados no handshake | não (só via subprotocol/query) | não no `EventSource` nativo | sim |
| Compressão | `permessage-deflate` (opcional) | `Content-Encoding` normal | normal |
| Custo por conexão ociosa | baixo | baixo | alto (reabre sempre) |

**[FATO]** Sobre o limite de 6 conexões: "essa restrição não se aplica com HTTP/2, onde os
streams são multiplexados sobre uma única conexão".
Fonte: <https://ably.com/blog/websockets-vs-sse>

**[FATO]** Sobre retomada: "quando o servidor emite IDs de evento e retém eventos
reproduzíveis, o navegador pode enviar `Last-Event-ID` para o servidor retomar a partir do
último evento entregue. […] Reconexão de WebSocket e ressincronização de estado são código
que os times escrevem eles mesmos."
Fonte: <https://ably.com/blog/websockets-vs-sse>

**[INFERÊNCIA]** Para um widget de chat, o argumento "WebSocket porque chat é
bidirecional" é **fraco**: o envio de mensagem já é um `POST` REST em praticamente todos os
produtos (inclusive Chatwoot e Leadster). O que realmente flui pelo socket é
servidor→cliente. O argumento forte a favor de WebSocket é outro: **latência de
typing/presença** e **não precisar de um POST por evento efêmero**.

O argumento forte a favor de **SSE** é a retomada nativa por `Last-Event-ID`, que resolve
de graça o problema mais difícil da seção 4.4 (mensagens perdidas na reconexão). Quem usa
WebSocket precisa reimplementar isso — e a maioria implementa mal.

### 4.2 Como o Chatwoot faz

**[FATO]** ActionCable (WebSocket) sobre `RoomChannel`, autenticado por `pubsub_token`.
`app/javascript/shared/helpers/BaseActionCableConnector.js` e
`app/javascript/widget/helpers/actionCable.js`.

Parâmetros verificados no código (valores desta branch `homologacao`):

| Parâmetro | Valor | Local |
|---|---|---|
| Intervalo de presença (widget) | 60.000 ms | `widget/helpers/actionCable.js:16` |
| Jitter de presença | até 5.000 ms | `BaseActionCableConnector.js:5` |
| Backoff base de reconexão | 1.000 ms | `BaseActionCableConnector.js:6` |
| Backoff máximo | 30.000 ms | `BaseActionCableConnector.js:7` |
| Jitter de reconexão | até 500 ms | `BaseActionCableConnector.js:165` |
| Checagem de "stream parado" | a cada 15.000 ms | `BaseActionCableConnector.js:9` |
| Limiar de silêncio | 25.000 ms | `BaseActionCableConnector.js:15` |
| Timeout de "digitando" do agente | 30.000 ms | `widget/helpers/actionCable.js:138` |

O backoff é exponencial com jitter, corretamente saturado:

```javascript
// BaseActionCableConnector.js:162-174
initReconnectTimer = () => {
  this.clearReconnectTimer();
  const jitter = Math.random() * 500;
  const delay = Math.min(
    BASE_RECONNECT_INTERVAL * 2 ** this.reconnectAttempts + jitter,
    MAX_RECONNECT_INTERVAL
  );
  this.reconnectAttempts += 1;
  this.reconnectTimer = setTimeout(() => { this.checkConnection(); }, delay);
};
```

**[FATO]** Há tratamento explícito de **aba em background** e de **bfcache**, com
comentários em português (customização do ChatSPX, não do upstream):

```javascript
// BaseActionCableConnector.js:87-116
this.handleReturnToForeground = () => {
  const conn = this.consumer.connection;
  if (conn && !conn.isOpen()) conn.reopen();
  this.reconnectAttempts = 0;
  this.clearReconnectTimer();
  this.checkConnection();
  window.reconnectService?.handleRouteSpecificFetch?.();
};
document.addEventListener('visibilitychange', this.onVisibilityChange);
window.addEventListener('focus', this.handleReturnToForeground);
window.addEventListener('pageshow', this.onPageShow);   // event.persisted → bfcache
```

**[INFERÊNCIA]** Isso está acima da média do mercado. Os três gatilhos cobrem os três
casos que a lib do Rails erra sozinha: troca de aba, foco de janela sem troca de aba
(máquina que dormiu), e volta pelo botão "voltar" com bfcache. É a correção documentada em
`reference_chatspx_desconectado_ui_race` do vault.

**[FATO]** Recuperação de mensagens perdidas na reconexão existe e é por cursor:

```javascript
// widget/helpers/actionCable.js:33-47
onDisconnected = () => { this.setLastMessageId(); };
onReconnect     = () => { this.syncLatestMessages(); };
```

```javascript
// widget/store/modules/conversation/actions.js
syncLatestMessages: async ({ state, commit }) => {
  const { lastMessageId, conversations } = state;
  const { data: { payload, meta } } = await getMessagesAPI({ after: lastMessageId });
  // ...filtra as que faltam e faz merge
}
```

**[INFERÊNCIA]** O padrão está certo (cursor `after=<id>`), mas tem dois furos:
1. `setLastMessageId` é gravado no `onDisconnected`. Se o socket morrer sem disparar
   `disconnected` (o caso do "stream silencioso" que o próprio `staleCheck` existe para
   detectar), o cursor fica velho — ou, pior, o `syncLatestMessages` roda com o cursor de
   uma sessão anterior.
2. Não há paginação no `after`: se o visitante ficou 3 dias com a aba aberta e voltou, a
   resposta é uma página só. **[NÃO VERIFICADO]** Não confirmei o limite do endpoint.

### 4.3 Como a Leadster faz — e a descoberta

**[MEDIDO]** Extraído do bundle público `neurolead.min.js`:

```javascript
const Lo = function (t, e, n) {
  let i = arguments.length > 3 && undefined !== arguments[3] ? arguments[3] : 0;
  if (i >= 5) n(new Error("Failed to connect after 5 attempts."));
  else try {
    const o = new WebSocket("wss://atendimento.leadster.com.br/cable");
    o.onopen = () => {
      const n = { command: "subscribe",
                  identifier: JSON.stringify({ channel: "RoomChannel", pubsub_token: t }) };
      o.send(JSON.stringify(n)), e(o);
    };
    const a = () => { setTimeout(() => { Lo(t, e, n, i + 1) }, 1e3) };
    o.onerror = a; o.onclose = a;
  } catch (t) { n(t) }
};
```

**[FATO]** `wss://.../cable`, `command: "subscribe"`, `channel: "RoomChannel"`,
`pubsub_token` — isso é a **assinatura exata do ActionCable do Chatwoot**. Comparar com
`app/javascript/shared/helpers/BaseActionCableConnector.js:35-41` deste repositório:

```javascript
this.subscription = this.consumer.subscriptions.create(
  { channel: 'RoomChannel', pubsub_token: pubsubToken, account_id: ..., user_id: ... },
  { ... }
);
```

**[MEDIDO]** E o fluxo de criação de contato confirma:

```javascript
async createContact() {
  // ...
  const { data: e } = await Mn.post("/livechat/conversations", t);
  // ...
  this.livechatConversationId = n.conversation.id;
  this.livechatSourceId = n.contact.source_id;   // <- source_id: campo do ContactInbox do Chatwoot
  // ...
  return this.createSocket(n.contact.pu /* pubsub_token */ ...)
}
```

**[INFERÊNCIA — achado principal do estudo]** A Leadster roda **Chatwoot (ou um fork dele)
por baixo** para o handoff humano ("Leadster Atendimento"). O bot de qualificação é
proprietário e roda no bundle; quando a conversa vira atendimento humano, o backend da
Leadster faz proxy (`POST /livechat/conversations`) para criar contato + conversa no
Chatwoot, devolve `contact.source_id` e `contact.pubsub_token` ao browser, e o **browser
conecta direto no ActionCable do Chatwoot**.

**Consequências desse achado para o ChatSPX** (detalhadas em §15):
- O ChatSPX já é dono da camada que a Leadster teve que comprar/adotar.
- O diferencial competitivo da Leadster não está no chat: está no **bot de qualificação
  conversacional, na captação de lead e na camada de conversão** — e no fato de o widget
  ser leve o suficiente para viver no DOM do site.
- A reconexão da Leadster é **pior** que a do Chatwoot: intervalo fixo de 1s, máximo 5
  tentativas, depois desiste para sempre. Sem backoff, sem jitter, sem `visibilitychange`,
  sem retomada por cursor.

**[MEDIDO]** A Leadster também trata abandono de chat via `pagehide` no `window.top`:

```javascript
useChatAbandonmentNotice() { return !!this.message.useChatAbandonmentNotice }
handlePageHide() {
  this.flow.livechatActive && this.useChatAbandonmentNotice()
    && (this.showAbandonmentNotice(), this.createNote(), this.flow.livechatActive = !1, ...)
}
```

**[INFERÊNCIA]** `createNote()` no `pagehide` é uma boa ideia de produto (o agente vê
"visitante saiu da página") mas é uma requisição no `pagehide` — que só é confiável com
`navigator.sendBeacon()` ou `fetch(..., {keepalive: true})`. Não consegui confirmar qual é
usado. **[NÃO VERIFICADO]**

### 4.4 Ordenação, deduplicação e "exactly once"

**[FATO]** "Prometer exactly-once é impraticável sobre redes não confiáveis, então você
projeta para semântica at-least-once e adiciona IDs estáveis de mensagem para deduplicação
idempotente **tanto no servidor quanto no cliente**."
Fonte: <https://www.systemdesignsandbox.com/learn/idempotency-deduplication>

**[FATO]** "Um sequenciador do lado do servidor particionado por `conversation_id` atribui
números de sequência monotônicos que definem a ordem autoritativa das mensagens."
Fonte: idem.

**O modelo correto, em quatro peças:**

1. **ID de idempotência gerado no cliente** (UUID v4 ou ULID), enviado no POST. O servidor
   o guarda com índice único por conversa. Retry do cliente → mesmo ID → servidor devolve
   a mensagem já criada, HTTP 200, sem duplicar.
2. **Sequência autoritativa do servidor** (`seq` monotônico por conversa, ou o `id` da
   tabela). O cliente ordena por `seq`, nunca por `created_at` do cliente — relógios de
   visitante estão errados.
3. **Reconciliação otimista por ID, não por conteúdo.** Ao chegar a confirmação, o cliente
   troca a mensagem temporária cujo `idempotency_id` bate.
4. **Gap detection.** Se o cliente tem `seq` 10 e chega `seq` 12, ele sabe que perdeu a 11
   e busca o intervalo — sem esperar a reconexão.

**[FATO]** O Chatwoot **tem** o campo para isso no backend — `echo_id`:

```ruby
# app/controllers/api/v1/widget/base_controller.rb:85
echo_id: permitted_params[:message][:echo_id],
```
```ruby
# app/controllers/api/v1/widget/messages_controller.rb:67
params.permit(:id, :before, :after, :website_token,
              message: [:content, :referer_url, :timestamp, :echo_id, :reply_to])
```

**[FATO]** E o widget **não o envia**:

```javascript
// app/javascript/widget/api/endPoints.js:25-39
const sendMessage = (content, replyTo) => ({
  url: `/api/v1/widget/messages${search}`,
  params: { message: { content, reply_to: replyTo,
                       timestamp: new Date().toString(),
                       referer_url: referrerURL } }   // <- sem echo_id
});
```

**[FATO]** Em vez de ID, o widget reconcilia **por igualdade de conteúdo**:

```javascript
// app/javascript/widget/store/modules/conversation/helpers.js:46-49
export const findUndeliveredMessage = (messageInbox, { content }) =>
  Object.values(messageInbox).filter(
    message => message.content === content && message.status === 'in_progress'
  );
```

**[INFERÊNCIA — bug latente]** O visitante que manda "oi", não recebe resposta e manda
"oi" de novo antes da primeira confirmar tem **duas** mensagens temporárias com o mesmo
conteúdo. Quando a confirmação da primeira chega, `findUndeliveredMessage` devolve as duas,
o código pega `[messageInConversation]` (a primeira do array — ordem de `Object.values`,
que é ordem de inserção de chaves string/UUID, portanto não garantida semanticamente) e
apaga uma delas. Resultado possível: uma mensagem some da tela e reaparece depois, ou fica
presa em `in_progress` para sempre.

**[FATO]** O widget **gera** um UUID para a mensagem temporária — ele existe, só não viaja:

```javascript
// app/javascript/widget/store/modules/conversation/helpers.js:5-16
export const createTemporaryMessage = ({ attachments, content, replyTo }) => {
  const timestamp = new Date().getTime() / 1000;
  return { id: getUuid(), content, attachments, status: 'in_progress', ... };
};
```

**[INFERÊNCIA]** Este é o conserto de menor custo e maior impacto de toda a lista: enviar
`echo_id: message.id` no POST e reconciliar por ele. O backend já aceita o campo.

### 4.5 Fila offline e reenvio

**[FATO]** O widget do Chatwoot marca a mensagem como `failed` no `catch` e para por aí:

```javascript
// widget/store/modules/conversation/actions.js
} catch (error) {
  commit('pushMessageToConversation', { ...message, status: 'failed' });
  commit('updateMessageMeta', { id, meta: { ...meta, error: '' } });
}
```

Não há: fila persistida, retry automático, backoff, nem detecção de `navigator.onLine`.
**[FATO]** Não há nenhuma ocorrência de `localStorage`, `indexedDB`, `BroadcastChannel` ou
`SharedWorker` em `app/javascript/widget/` (verificado por `grep` recursivo).

**O desenho de referência** (**[INFERÊNCIA]**, síntese da literatura de §4.4):

```
enviar(msg):
  msg.idempotency_id = uuid()
  persistir em IndexedDB (store "outbox", status="pending")
  render otimista
  POST com idempotency_id
    ok      -> outbox.delete(id); reconcilia por idempotency_id
    rede    -> mantém "pending"; agenda retry com backoff (1s,2s,4s… teto 60s)
    4xx     -> status="failed"; expõe botão "tentar de novo"; não faz retry automático
  ao voltar online (evento 'online') ou ao reabrir o widget:
    drenar outbox em ordem de criação
```

Pontos finos que a literatura costuma esconder:
- `navigator.onLine` é **mentiroso**: dá `true` para "conectado ao roteador", não
  "consegue falar com o servidor". Serve como *gatilho de tentativa*, nunca como verdade.
- A ordem importa: drenar a outbox em paralelo entrega fora de ordem. Drenar em série.
- Reenvio precisa de teto de idade: uma mensagem de 3 dias atrás não deve ser entregue
  como se fosse agora. Marcar como expirada e perguntar ao usuário.

### 4.6 Indicadores: digitando, entregue, lido

| Indicador | Origem da verdade | Custo | Armadilha |
|---|---|---|---|
| **digitando** (visitante→agente) | evento efêmero do cliente | 1 evento por burst | não mandar por keystroke; *throttle* de 2–3 s e um "off" com debounce |
| **digitando** (agente→visitante) | evento do servidor | — | precisa de timeout no cliente (senão fica "digitando" para sempre) |
| **enviado** | ACK do POST | — | não confundir com "chegou no agente" |
| **entregue** | servidor persistiu | — | só faz sentido se houver push confiável |
| **lido** | `contact_last_seen_at` / `agent_last_seen_at` | 1 POST por foco | privacidade: alguns clientes querem desligar |

**[FATO]** O Chatwoot tem timeout de segurança de 30 s no "agente digitando"
(`widget/helpers/actionCable.js:136-141`) — correto e frequentemente esquecido em
implementações caseiras.

**[FATO]** Tem `setUserLastSeenAt` (`widget/api/conversation.js`), que alimenta o "lido".

**[INFERÊNCIA]** Falta o oposto: o widget não mostra "o agente leu sua mensagem" com
robustez, porque `agent_last_seen_at` não flui como evento próprio no widget. Isso é
percepção de qualidade — o WhatsApp treinou o mercado a esperar os dois tiques.

### 4.7 Sincronização entre múltiplas abas

Três mecanismos, em ordem crescente de capacidade:

| Mecanismo | O que resolve | Suporte | Custo |
|---|---|---|---|
| `storage` event | avisar outras abas que algo mudou | universal | só dispara em **outras** abas; passa por string |
| `BroadcastChannel` | pub/sub estruturado entre abas mesma origem | Baseline moderno | não elege líder sozinho |
| Web Locks API | **eleição de líder** determinística | Chrome/Edge/Firefox/Safari 15.4+ | precisa de fallback |
| `SharedWorker` | **uma** conexão para N abas | sem Safari confiável historicamente | complexo; debugging ruim |

**[FATO]** "Um algoritmo de eleição de líder garante que exatamente uma aba está
gerenciando o acesso a dados remotos."
Fonte: <https://rxdb.info/leader-election.html>

**[FATO]** A biblioteca `tab-election` "usa a Locks API se possível e cai para um algoritmo
de eleição por mensagens se WebLocks não estiver disponível".
Fonte: <https://github.com/dabblewriter/tab-election>

**[INFERÊNCIA]** Para um widget de chat, o padrão custo-benefício é:
**Web Locks para eleger o líder + BroadcastChannel para distribuir eventos**, sem
`SharedWorker`. O líder mantém o WebSocket; as demais abas recebem por BroadcastChannel e
fazem só render. Se o líder morre, o lock é liberado pelo navegador automaticamente e outra
aba assume — sem heartbeat manual, sem timeout arbitrário.

Ganhos concretos: N abas abertas = 1 conexão (menos carga no servidor, menos bateria),
badge de não-lidas consistente entre abas, e som de notificação tocando uma vez só em vez
de N vezes.

**[FATO]** Nada disso existe no widget do Chatwoot hoje (grep negativo, §4.5). Com o
widget em iframe, N abas = N conexões ActionCable.

---

## 5. Estado e persistência

### 5.1 O fim do cookie de terceiros — estado real em 2026

**[FATO]** Em abril de 2025 o Google abandonou oficialmente o plano de eliminar cookies de
terceiros no Chrome, encerrando a iniciativa Privacy Sandbox naquele formato.
Fonte: <https://www.techinterview.org/post/3233475403/frontend-cookies-storage-privacy-2026/>

**[FATO]** Isso **não** significa que voltou tudo como era:
- **Safari** bloqueia cookies de terceiros integralmente (ITP).
- **Firefox** particiona por padrão via Total Cookie Protection — cada site de topo tem seu
  próprio pote de cookies para o mesmo terceiro.
- **Chrome** suporta o atributo `Partitioned` (CHIPS) desde a v114.
Fonte: <https://developer.mozilla.org/en-US/docs/Web/Privacy/Guides/Third-party_cookies/Partitioned_cookies>

**[INFERÊNCIA]** Para um widget em iframe cross-origin, o resultado prático é: **assuma
que seu cookie é particionado por site de topo**. Um visitante que fala com você em
`clientea.com.br` e depois em `clienteb.com.br` é, para efeitos de storage, duas pessoas —
mesmo que seja o mesmo fornecedor de chat nos dois. Isso é desejável do ponto de vista de
privacidade e é o que a legislação quer.

### 5.2 ITP e o limite de 7 dias

**[FATO]** Duas regras distintas do WebKit, frequentemente confundidas:

1. **Fevereiro/2019 — cookies escritos por script:** "o ITP limita a expiração de cookies
   do lado do cliente a sete dias", mirando "o uso, por scripts de terceiros, de cookies
   first-party para fins de rastreamento entre sites".
2. **Março/2020 — todo storage escrito por script:** o ITP "deleta todo o storage
   script-writable de um site após sete dias de uso do Safari **sem interação do usuário no
   site**". Abrange IndexedDB, LocalStorage, media keys, SessionStorage, registros e cache
   de Service Worker.

Fonte: <https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/>

**[FATO]** A condição-gatilho é literal: "sete dias de uso do Safari sem interação do
usuário no site" — o contador **reseta** quando o usuário interage com o site.

**[FATO]** Exceção documentada: web apps adicionados à tela inicial não sofrem a deleção,
porque "os dias de uso correspondem ao uso real da aplicação".

**[INFERÊNCIA — o que isso significa para um widget de chat]**
- Um cookie de sessão de conversa gravado por `document.cookie` (que é o caso do
  `js-cookie` usado pelo Chatwoot) **dura no máximo 7 dias no Safari**, por mais que você
  peça 365.
- A mitigação real é gravar o cookie **pelo servidor**, com `Set-Cookie` em resposta HTTP,
  no domínio do próprio widget. Cookies `Set-Cookie` de first-party não sofrem o cap de 7
  dias (sofrem outras regras, mas não essa).
- A mitigação *falsa* é migrar para `localStorage`: desde março/2020 ele cai na mesma regra
  (e some inteiro, não só expira).
- Para continuidade de longo prazo, a única âncora confiável é **identidade**: e-mail,
  telefone, ou `identifier` autenticado por HMAC (§6.6). Storage é cache, não verdade.

**[FATO]** O Chatwoot grava o cookie por JS, com `expires: 365`:

```javascript
// app/javascript/sdk/cookieHelpers.js:26-45
export const setCookieWithDomain = (name, value,
  { expires = 365, baseDomain = undefined } = {}) => {
  const cookieOptions = { expires, sameSite: 'Lax', domain: baseDomain };
  // ...
  Cookies.set(name, value, cookieOptions);
};
```

**[INFERÊNCIA]** Portanto, no Safari: 7 dias, não 365. E o token JWT por trás vale 180 dias
por padrão (`app/services/widget/token_service.rb`, `DEFAULT_EXPIRY_DAYS = 180`) — ou seja,
**o token vive 26x mais do que o cookie que o carrega no Safari**. O visitante Safari perde
o histórico de conversa depois de uma semana sem voltar, embora o servidor ainda o
reconhecesse.

Faltam também os atributos modernos: não há `Secure`, não há `Partitioned`.
`sameSite: 'Lax'` sem `Secure` é rejeitado por navegadores em contexto de iframe
cross-site — e `SameSite=Lax` num cookie que precisa viajar em iframe de terceiro
simplesmente não é enviado. **[INFERÊNCIA]** No fluxo atual isso não quebra porque o cookie
é lido pelo *SDK no host* e passado por query string ao iframe
(`IFrameHelper.js:65-68`, `widgetUrl = ...&cw_conversation=${cwCookie}`), não pelo header
`Cookie`. É um contorno que funciona, mas coloca o token de sessão **na URL** — que vaza
em `Referer`, em logs de servidor, e no histórico do navegador.

### 5.3 A tabela de storage

| Mecanismo | Capacidade típica | Sobrevive a fechar aba? | ITP 7 dias? | Síncrono? | Uso recomendado num widget |
|---|---|---|---|---|---|
| Cookie (via JS) | 4 KB/cookie | sim | **sim** | sim | token de sessão curto; nada mais |
| Cookie (`Set-Cookie`) | 4 KB | sim | não (regras próprias) | — | **token de sessão** |
| `sessionStorage` | ~5 MB | **não** (por aba) | sim | sim | rascunho do composer |
| `localStorage` | ~5 MB | sim | **sim** | sim (bloqueia!) | preferências (som, tema) |
| IndexedDB | centenas de MB | sim | **sim** | não | outbox offline, cache de histórico |
| Cache API | idem | sim | **sim** | não | assets do widget |
| Memória | — | não | — | — | tudo que não precisa sobreviver |

**[INFERÊNCIA]** `localStorage` é síncrono e bloqueia a main thread. Num widget que roda no
site alheio, cada leitura de `localStorage` no caminho crítico é INP do cliente. Para
outbox e histórico, IndexedDB (assíncrono) é obrigatório, não opcional.

**[MEDIDO]** A Leadster usa `localStorage` 31 vezes, com as chaves
`lastNotificationViewed`, `lastNotificationViewedText` e `neuroleadsPreferredVersions`; e
cookies `leadster_hide_tooltip`, `livechat_conversation_id` (1 dia), além de ler `_fbc` e
`_gcl_aw` (identificadores de clique do Facebook e do Google Ads).

**[INFERÊNCIA]** Ler `_fbc`/`_gcl_aw` é atribuição de campanha: a Leadster carimba na
conversa de qual anúncio o lead veio. É um recurso de produto, não técnico — e é
exatamente o tipo de coisa que diferencia uma ferramenta de conversão de uma de suporte.

### 5.4 Identidade do visitante: entre sessões e entre subdomínios

**Entre sessões (mesmo navegador).** Depende do storage — e portanto do §5.2.

**Entre subdomínios.** **[FATO]** O Chatwoot expõe `baseDomain` em `chatwootSettings`, que
vira o atributo `domain` do cookie (`cookieHelpers.js:31`). Definindo
`baseDomain: '.empresa.com.br'`, o cookie vale para `app.` e `www.` e `loja.`.

**[INFERÊNCIA]** Isso resolve o caso 1st-party (o widget servido do mesmo domínio-pai).
Não resolve o caso do SaaS multi-tenant, onde o widget mora em `chat.chatspx.app` e os
clientes em domínios variados — ali o compartilhamento entre domínios diferentes **não
deve** existir (é rastreamento cross-site, é o que os navegadores estão matando).

**Entre dispositivos.** Só por identidade autenticada. Não há truque.

### 5.5 Continuidade de conversa e "resume"

Quatro níveis, do mais fraco ao mais forte:

1. **Nenhum.** Toda visita começa do zero. (Nenhum produto sério faz isso.)
2. **Por cookie/token.** A sessão retoma se o storage sobreviveu. É o nível do Chatwoot.
3. **Por e-mail (continuidade assíncrona).** A conversa continua por e-mail quando o
   visitante sai. **[FATO]** O Chatwoot tem isso: `continuity_via_email`, default `TRUE`,
   em `app/models/channel/web_widget.rb`.
4. **Por identidade verificada.** O cliente autentica o visitante no seu próprio sistema e
   passa a identidade assinada. Funciona em qualquer dispositivo, imune a limpeza de
   storage. É o nível do `setUser` + HMAC (§6.6).

**[INFERÊNCIA]** O nível 3 é subestimado e é onde o Chatwoot tem vantagem estrutural sobre
widgets puramente front-end como o da Leadster: por ser um *helpdesk* completo, a conversa
sobrevive fora do browser.

### 5.6 Limpeza de dados e LGPD

Requisitos que o widget precisa suportar tecnicamente (a interpretação jurídica não é minha):

- **Direito de eliminação.** Um botão/API que apaga cookie, storage local e dispara a
  exclusão no servidor. **[FATO]** O Chatwoot tem o lado do cliente:
  `window.$chatwoot.reset()` remove `cw_conversation` e o cookie de usuário e recarrega o
  iframe (`entrypoints/sdk.js:195-210`). Não dispara exclusão no servidor.
- **Minimização.** Não coletar IP se não precisar. **[FATO]** O Chatwoot condiciona a
  coleta de IP a uma feature flag: `created_at_ip` só é gravado se
  `feature_enabled?('ip_lookup')` (`app/controllers/widgets_controller.rb:67-73`). Isso é
  bem desenhado.
- **Transparência.** O widget deve declarar o que grava. Não é código, é conteúdo.
- **Retenção.** Purga automática de conversas antigas. É backend (§12).

---

## 6. Segurança

### 6.1 Mapa de superfície de ataque

```
                    ┌── (A) o site do cliente é hostil ou comprometido
                    │
  VISITANTE ────────┼── (B) outro terceiro na mesma página é hostil
                    │
                    ├── (C) o próprio visitante é o atacante (abuso, spam, XSS por conteúdo)
                    │
                    └── (D) rede/MITM
                                │
  WIDGET ───────────────────────┼── (E) o widget vaza dados de um tenant para outro
                                │
  BACKEND ──────────────────────┴── (F) o agente é atacado pelo conteúdo do visitante
```

O ponto **(F)** é o mais esquecido e o mais grave: um XSS no painel do agente escala de
"um visitante" para "toda a operação de atendimento".

### 6.2 XSS no conteúdo da mensagem

**[FATO]** O Chatwoot usa `markdown-it` com `html: false` — a defesa de primeira linha
correta:

```javascript
// app/javascript/shared/helpers/MessageFormatter.js
return MarkdownIt({
  html: false,            // <- HTML bruto no markdown é escapado, não interpretado
  xhtmlOut: true, breaks: true, langPrefix: 'language-',
  linkify, typographer: true, maxNesting: 20,
}).use(mentionPlugin).use(imgResizeManager)
  .use(mila, { attrs: { class: 'link', rel: 'noreferrer noopener nofollow', target: '_blank' } });
```

Três acertos nesse trecho:
- `html: false` — o vetor principal fechado na origem.
- `rel: 'noreferrer noopener nofollow'` em todo link — fecha `window.opener` (tabnabbing) e
  não vaza o referrer.
- `maxNesting: 20` — limita ReDoS/blowup por markdown patológico.

**[FATO]** Há uma segunda camada com DOMPurify (`vue-dompurify-html` está no bundle do
widget, §14), configurada em `app/javascript/shared/helpers/HTMLSanitizer.js`:

```javascript
export const afterSanitizeAttributes = currentNode => {
  if ('target' in currentNode) { currentNode.setAttribute('target', '_blank'); }
};
export const domPurifyConfig = { hooks: { afterSanitizeAttributes } };
```

**[INFERÊNCIA]** Defesa em profundidade correta (markdown-it + DOMPurify). Duas
observações:
1. O hook força `target="_blank"` em tudo que tenha `target`, mas **não** força
   `rel="noopener"` correspondente. Se algum caminho de renderização escapar do `mila`,
   nasce um tabnabbing.
2. `linkify: true` transforma texto solto em link. Isso significa que **o visitante
   controla o `href` de um `<a>` que o agente vai ver**. `markdown-it` bloqueia
   `javascript:` por padrão em `validateLink`, mas isso depende de a versão estar
   atualizada e de ninguém ter sobrescrito `md.validateLink`. **[NÃO VERIFICADO]** Não
   auditei se `validateLink` foi customizado neste fork.

**Checklist de sanitização para chat** (**[INFERÊNCIA]**, síntese):

- [ ] Markdown com `html: false`. Nunca `dangerouslySetInnerHTML`/`v-html` sem DOMPurify.
- [ ] Bloquear esquemas: só `http`, `https`, `mailto`, `tel`. Rejeitar `javascript:`,
      `data:`, `vbscript:`, `blob:` em `href`.
- [ ] `rel="noopener noreferrer"` em **todo** link com `target="_blank"`.
- [ ] Atributos de imagem: só `src`, `alt`, `width`, `height`. Nada de `onerror`.
- [ ] Limite de tamanho da mensagem no **servidor** (não só no cliente).
- [ ] Nome do contato também é conteúdo hostil — sanitizar em avatar, título, notificação.
- [ ] O mesmo sanitizador nos **dois** lados (widget e painel do agente). Divergência entre
      eles é o bug clássico.

### 6.3 Clickjacking e `frame-ancestors`

**[FATO]** O Chatwoot implementa restrição de domínio corretamente, e o código merece ser
citado inteiro porque é bem feito:

```ruby
# app/controllers/widgets_controller.rb:79-97
def allow_iframe_requests
  if @web_widget.allowed_domains.blank? || embedded_from_non_web_origin?
    response.headers.delete('X-Frame-Options')
  else
    domains = @web_widget.allowed_domains.split(',').map(&:strip).join(' ')
    response.headers['Content-Security-Policy'] = "frame-ancestors #{domains}"
  end
end

# Mobile WebViews (iOS/Android) load content from file:// or null origins,
# which cannot match any domain in frame-ancestors. When the per-inbox flag
# is enabled, skip frame-ancestors for these requests.
def embedded_from_non_web_origin?
  return false unless @web_widget.allow_mobile_webview?
  origin = request.headers['Origin']
  origin.blank? || origin == 'null' || origin&.start_with?('file://')
end
```

**[INFERÊNCIA]** Análise:
- ✅ Usa `frame-ancestors` (CSP nível 2), não o obsoleto `X-Frame-Options` — correto,
  porque `X-Frame-Options` não suporta lista de domínios.
- ✅ Trata o caso WebView mobile com uma flag por inbox, em vez de abrir para todos.
- ⚠️ **O default é aberto**: `allowed_domains` em branco → deleta `X-Frame-Options` e não
  põe `frame-ancestors`. Qualquer site do mundo pode embutir o widget de qualquer conta.
  Isso é conveniência de onboarding paga com segurança.
- ⚠️ Não há validação do formato dos domínios: `allowed_domains` vai direto para o header.
  Um valor com `;` pode injetar outra diretiva CSP. **[NÃO VERIFICADO]** — o front
  sanitiza (`sanitizedAllowedDomains` em `ConfigurationPage.vue:190`), mas a API pode ser
  chamada diretamente.

**O ataque que `frame-ancestors` previne, concretamente:** um site hostil embute o widget
da Empresa X, coloca um overlay transparente sobre ele, e induz a vítima a "clicar em algo"
que na verdade abre uma conversa e envia dados. Ou pior: embute o widget e, junto, um
script que finge ser o suporte da Empresa X para colher dados.

### 6.4 CSP do site host quebrando o widget

Este é o suporte nº 1 de qualquer fornecedor de widget.

**[FATO]** As diretivas que o Intercom exige, da documentação oficial
(<https://www.intercom.com/help/en/articles/3894-using-intercom-with-content-security-policy>):

| Diretiva | Valor (resumido da doc) |
|---|---|
| `script-src` | `https://app.intercom.io https://widget.intercom.io https://js.intercomcdn.com` |
| `connect-src` | `https://via.intercom.io`, `https://api.intercom.io`, variantes regionais, `wss://*.intercom-messenger.com` e websockets |
| `img-src` | `blob:`, `data:`, `https://downloads.intercomcdn.com`, `https://static.intercomassets.com`, variantes regionais |
| `font-src` | `https://js.intercomcdn.com https://fonts.intercomcdn.com` |
| `media-src` | `https://js.intercomcdn.com https://downloads.intercomcdn.com` (+ regionais) |
| `style-src` | `'unsafe-inline'` |
| `child-src` / `frame-src` / `worker-src` | `https://intercom-sheets.com`, `https://www.intercom-reporting.com`, YouTube/Vimeo/Wistia |

**[FATO]** O modo de falha mais cruel está documentado por terceiros: "se você esquecer
`wss://*.intercom.io` em `connect-src`, o widget carrega mas nunca conecta, fazendo o chat
parecer quebrado."
Fonte: <https://dev.to/sitesecurityscore/csp-for-third-party-scripts-the-practical-cheat-sheet-for-ga-stripe-intercom-and-more-1gh8>

**[FATO]** O Zendesk publica página dedicada a CSP:
<https://developer.zendesk.com/documentation/zendesk-web-widget-sdks/sdks/web/csp/>

**[INFERÊNCIA]** O que se aprende disso, para um produto:

1. **Publicar a lista de diretivas é obrigação de fornecedor**, não cortesia. Sem isso,
   todo cliente com CSP abre chamado.
2. **`style-src 'unsafe-inline'` é uma exigência tóxica.** O Intercom exige. Qualquer
   cliente com CSP séria vai reclamar, porque `'unsafe-inline'` em `style-src` reabre uma
   classe de ataques. A alternativa moderna: gerar um `nonce` ou usar
   `style-src-elem`/`'strict-dynamic'`, ou — melhor — **não usar estilo inline**.
   **[FATO]** O Chatwoot injeta uma tag `<style>` com `innerHTML`
   (`app/javascript/sdk/DOMHelpers.js:4-10`), o que exige `style-src 'unsafe-inline'` do
   cliente. E define estilo inline em vários pontos (`iframe.style.visibility`,
   `chatIcon.style.background`, `setAttribute('style', ...)`).
3. **A arquitetura em iframe muda as diretivas exigidas.** Com iframe cross-origin, o
   cliente precisa liberar `frame-src` (para o iframe) e `script-src` (para o loader) — mas
   **não** precisa liberar `connect-src` do WebSocket, porque a conexão parte de dentro do
   iframe, que tem CSP própria. Isso é uma vantagem real e pouco citada do iframe.
   **[INFERÊNCIA]**

### 6.5 SRI (Subresource Integrity)

**[INFERÊNCIA]** SRI (`integrity="sha384-..."`) é frequentemente pedido por times de
segurança de clientes grandes e é **incompatível com o modelo de widget de chat**, por uma
razão simples: o hash trava a versão. Se o fornecedor publica um patch de segurança no
bundle, todo cliente com SRI passa a receber `ERR_BLOCKED_BY_RESPONSE` até atualizar o hash
à mão.

Saídas possíveis, em ordem de preferência:
1. **Loader versionado e imutável** (`/loader/v3.4.1/loader.js`) com SRI publicado por
   versão, e o loader busca o app por um manifesto — o app não precisa de SRI porque não é
   `<script src>` do host.
2. Publicar os hashes num endpoint estável e documentar a rotina de atualização.
3. Recusar SRI e compensar com `frame-ancestors`, CSP restrita no iframe e auditoria.

**[NÃO VERIFICADO]** Não encontrei nenhum dos fornecedores inspecionados publicando hashes
SRI.

### 6.6 Verificação de identidade por HMAC — por que existe

**[FATO]** O propósito, na palavra da Intercom: a verificação de identidade "ajuda a
garantir que as conversas entre você e seus usuários permaneçam privadas e que um usuário
não possa se passar por outro".
Fonte: <https://developers.intercom.com/installing-intercom/react-native/identity-verification>

**[FATO]** O ataque concreto, também documentado: "sem verificação de identidade adequada,
um atacante poderia se passar por um usuário para pedir informações sensíveis à equipe de
suporte".
Fonte: <https://19whoami19.medium.com/uncovering-intercom-misconfigurations-from-ignored-widgets-to-high-impact-vulnerabilities-26115f9481ca>

**Por que o HMAC precisa existir, do zero:** o snippet do widget roda no browser da vítima.
Qualquer coisa que o browser afirme (`setUser('12345', {email: 'ceo@empresa.com'})`) é
afirmação do cliente, não prova. Sem assinatura, eu abro o console do seu site, chamo
`setUser` com o e-mail do seu CEO, e o seu agente vê o histórico de conversas do CEO — e
acredita que sou ele.

O HMAC resolve porque a chave só existe no **seu servidor**: você calcula
`HMAC-SHA256(chave_secreta, user_id)` no backend, entrega o digest ao browser, e o
fornecedor recalcula e compara.

**[FATO]** O Chatwoot implementa exatamente isso:

```ruby
# app/controllers/api/v1/widget/contacts_controller.rb:56-70
return false if params[:identifier_hash].blank? && !@web_widget.hmac_mandatory
# ...
params[:identifier_hash] == OpenSSL::HMAC.hexdigest('sha256', @web_widget.hmac_token, ...)
```

**[FATO]** E tem o flag `hmac_mandatory` (default **`FALSE`**, ver
`app/models/channel/web_widget.rb:9`) que, quando ligado, recusa `setUser` sem assinatura.

**[FATO]** O Chatwoot também usa a verificação para escopar o que a conversa enxerga:

```ruby
# app/controllers/api/v1/widget/base_controller.rb:12-18
if @contact_inbox.hmac_verified?
  verified_contact_inbox_ids = @contact.contact_inboxes
    .where(inbox_id: auth_token_params[:inbox_id], hmac_verified: true).map(&:id)
  @conversations = @contact.conversations.where(contact_inbox_id: verified_contact_inbox_ids)
else
  @conversations = @contact_inbox.conversations.where(inbox_id: auth_token_params[:inbox_id])
end
```

**[INFERÊNCIA]** Este é um desenho *cuidadoso*: contatos verificados só veem conversas de
contact_inboxes verificados. Impede que uma sessão anônima que depois se identifica herde
conversas de outra sessão. É melhor do que a média.

**[FATO]** O Intercom já migrou o padrão de HMAC para **JWT**: "JWTs permitem tokens
assinados com tempo limitado, reduzindo o risco de ataques de replay", e a doc chama JWT de
método recomendado, mantendo HMAC por retrocompatibilidade.
Fonte: <https://www.intercom.com/help/en/articles/10589769-authenticating-users-in-the-messenger-with-json-web-tokens-jwts>

**[INFERÊNCIA]** A crítica ao HMAC puro é justa: o digest de `user_id` **não expira**.
Se ele vazar (num log, num HTML cacheado, numa captura de tela do DOM), vale para sempre.
JWT com `exp` curto resolve. É a direção que o mercado tomou.

**[FATO]** O `hmac_token` do Chatwoot é gerado por `has_secure_token` com índice único
(`app/models/channel/web_widget.rb:48`) — geração criptograficamente adequada.

### 6.7 Rate limiting e abuso de widget público

Um widget de chat é, por definição, um endpoint de escrita **não autenticado** exposto na
internet. Ele será abusado.

**[FATO]** Limites do Chatwoot, confirmados em duas fontes independentes — o código local e
a documentação oficial:

```ruby
# config/initializers/rack_attack.rb:172-190
# Rack attack on widget APIs can be disabled by setting ENABLE_RACK_ATTACK_WIDGET_API to false
throttle('api/v1/widget/conversations', limit: 6,  period: 12.hours) # POST
throttle('api/v1/widget/contacts',      limit: 60, period: 1.hour)   # PATCH/PUT
throttle('widget?website_token=...',    limit: 5,  period: 1.hour)   # GET sem cw_conversation
```

**[FATO]** A doc oficial confirma os mesmos números e o gem (`rack_attack`):
<https://developers.chatwoot.com/self-hosted/monitoring/rate-limiting>

**[INFERÊNCIA]** Análise crítica desses limites:
- ✅ 5 sessões novas por IP/hora é uma defesa eficaz contra criação em massa de contatos.
- ⚠️ **Todos os limites são por IP.** Numa empresa com NAT (todo mundo saindo pelo mesmo
  IP público), 5 pessoas diferentes abrindo o chat esgotam a cota. Esse é um falso positivo
  caro: o cliente reclama que "o chat não abre".
- ⚠️ **Não há limite de mensagens por conversa.** Depois de criar a conversa, o visitante
  pode postar em `POST /api/v1/widget/messages` sem throttle específico — só o global
  `req/ip` de 3000/minuto. Um bot pode encher o banco e a caixa do agente.
- ⚠️ O flag `ENABLE_RACK_ATTACK_WIDGET_API` existe justamente porque os limites causam
  falso positivo. Desligar é comum. **[NÃO VERIFICADO]** — não sei o valor em produção.

**Defesas complementares** (**[INFERÊNCIA]**, síntese de
<https://developers.cloudflare.com/waf/rate-limiting-rules/best-practices/>):

| Camada | Técnica | Custo para o usuário legítimo |
|---|---|---|
| Rede | WAF / rate limit por IP+ASN na borda | zero |
| Sessão | limite por token de conversa, não só por IP | zero |
| Conteúdo | limite de tamanho, de taxa e de repetição | zero |
| Comportamento | *proof of work* invisível antes da 1ª mensagem | ~100 ms |
| Desafio | CAPTCHA/Turnstile só quando o score piora | alto — usar por último |
| Domínio | `allowed_domains` obrigatório (§6.3) | zero, mas exige config |
| Conteúdo | detecção de spam/flood no servidor + auto-resolve | zero |

**[INFERÊNCIA]** O maior ganho de custo-benefício é tornar `allowed_domains`
**obrigatório por padrão em contas novas**. Hoje, com o default vazio, o `website_token` de
qualquer conta pode ser usado em qualquer site — e o token é público por natureza (está no
HTML do cliente).

### 6.8 Exposição de dados sensíveis no bundle

**[MEDIDO]** O bundle da Leadster contém `https://www.facebook.com/tr?id=` e
`https://connect.facebook.net/en_US/fbevents.js` — ou seja, o widget de chat carrega o
**pixel do Facebook** no site do cliente.

**[INFERÊNCIA]** Isso é significativo em dois eixos:
1. **Privacidade/LGPD.** O cliente instalou um chat e ganhou um rastreador de terceiro,
   possivelmente sem declarar isso na política de privacidade dele.
2. **Performance.** É mais uma origem, mais um handshake, mais bytes — dentro do orçamento
   do widget de chat.
**[NÃO VERIFICADO]** Não confirmei em que condições esse código dispara (pode ser opt-in
por conta). A presença no bundle é fato; o disparo, não.

**Regras gerais para o que **não** pode estar num bundle público de widget:**
- Chaves de API que não sejam explicitamente públicas.
- Endpoints administrativos.
- Sourcemaps de código proprietário em produção (o bundle da Leadster referencia
  `git.io/JUIaE#` — resquício de mensagem de erro de biblioteca, inofensivo).
- Listas de clientes, IDs internos, e-mails de equipe.
- Lógica de precificação ou de limites de plano que valha a pena burlar.

**[MEDIDO]** Curiosidade relevante: o loader do Crisp embute seletores CSS que identificam
**sites específicos** (`sellpass.io`, `cdn.sellix.io`, `api.sellsn.io`, `ereemby.com`) numa
lista chamada `engines`, usada para abortar o carregamento. **[INFERÊNCIA]** É uma
*blocklist* de clientes/plataformas — provavelmente antiabuso (revenda não autorizada ou
uso em sites de fraude). Está publicamente legível no bundle, o que é um vazamento leve de
inteligência antifraude.

---

## 7. Performance

### 7.1 O orçamento de bytes e por que ele é injusto

**[FATO]** "Apenas 3–10% dos visitantes usam o chat durante a sessão."
Fonte: <https://www.corewebvitals.io/pagespeed/chat-widget-perfect-core-web-vitals>

**[INFERÊNCIA]** Esse número define todo o resto. Se 95% dos visitantes não abrem o chat,
95% do custo do widget é desperdício puro — e é desperdício *no site do cliente*, cobrado
na métrica dele, não na sua. Um widget que carrega 500 KB no load é um widget que gasta
475 KB à toa por 20 visitantes.

**Orçamento defensável (proposta minha, [INFERÊNCIA]):**

| Fase | Alvo (gzip) | Contém |
|---|---|---|
| Loader | **≤ 3 KB** | stub queue, sentinela, decisão de quando carregar |
| Chrome (bolha + badge) | **≤ 15 KB** | bolha, badge, animação, convite proativo, i18n do rótulo |
| App do chat (on-demand) | ≤ 120 KB | lista, composer, anexos, formulários |
| Extras (on-demand) | sob demanda | emoji picker, upload, gravação de áudio, artigos |

O corte crítico é **chrome ≠ app**. A bolha e o badge precisam aparecer cedo (senão o
produto perde proatividade); o app não precisa existir até o clique.

### 7.2 Benchmarks reais medidos

**[MEDIDO]** Em 11/08/2026, comandos reproduzíveis:
`curl -sS -L -H "Accept-Encoding: gzip, br" -o /dev/null -w "%{size_download}" <url>` e
`gzip -c <arquivo> | wc -c`.

| Produto | Arquivo | Bruto | Comprimido | O que é |
|---|---|---:|---:|---|
| **Crisp** | `client.crisp.chat/l.js` v4.9.2 | 7.637 B | **2.906 B** | loader puro |
| **Intercom** | `widget.intercom.io/widget/<APP_ID>` | — | **3.159 B** | loader (2º estágio) |
| **Zendesk** | `static.zdassets.com/ekr/snippet.js` | 9.693 B | **3.965 B** | loader |
| **Chatwoot/ChatSPX** | `/packs/js/sdk.js` (build local) | 28.834 B | **9.523 B** | loader + chrome + ponte |
| **Drift** | `js.driftt.com/include/1/<id>.js` | — | **64.055 B** | loader gordo |
| **Leadster** | `cdn.leadster.com.br/neurolead/neurolead.min.js` | 456.101 B | **132.941 B** | **tudo** |
| **Botpress** | `cdn.botpress.cloud/webchat/v3.2/inject.js` | 598.667 B | **193.225 B** | **tudo** |
| **Typebot** | `@typebot.io/js@0/dist/web.js` | 689.351 B | **196.922 B** | **tudo** |
| **Chatwoot/ChatSPX** | app do widget (JS+CSS, entry + imports estáticos) | 2.519.4 KB | **577,4 KB** | app dentro do iframe |

**[MEDIDO]** Decomposição do app do widget do ChatSPX (build local em
`public/vite/`, via `.vite/manifest.json`, entry `entrypoints/widget.js` + imports estáticos
transitivos):

| Arquivo | gzip | bruto |
|---|---:|---:|
| `assets/widget-EcEcykJV.css` | **104,9 KB** | 1.077,3 KB |
| `assets/index-DqTgoDi8.js` | 102,5 KB | 342,6 KB |
| `assets/useBranding-*.js` | 83,2 KB | 280,3 KB |
| `assets/_plugin-vue_export-helper-*.js` | 83,0 KB | 218,7 KB |
| `assets/vue-dompurify-html-*.js` | 55,0 KB | 128,3 KB |
| `assets/Validators-*.js` | 52,4 KB | 160,9 KB |
| `assets/leaflet-*.js` | 42,7 KB | 147,1 KB |
| `assets/utils.esm-*.js` | 25,2 KB | 81,4 KB |
| `assets/widget-D0AtGYyS.js` (entry) | 18,6 KB | 60,4 KB |
| demais (6 arquivos) | 9,9 KB | 21 KB |
| **TOTAL** | **577,4 KB** | **2.519,4 KB** |

**[INFERÊNCIA — ressalvas importantes]**
- Esta medição é da build **do ChatSPX** (fork com features próprias), não do Chatwoot
  upstream. O número upstream pode ser bem menor.
- Os nomes de chunk do Vite são enganosos: `leaflet-*.js` é um chunk *compartilhado* que
  recebeu o nome de um dos módulos que o originou; ele é importado por 40+ entradas do
  projeto, incluindo o dashboard. Não significa que o widget usa mapas — significa que o
  agrupamento de chunks do Vite **misturou** vendor do dashboard com vendor do widget.
- O que **não** é ressalva: os bytes são transferidos de verdade. `manifest.json` lista
  esses arquivos como `imports` (estáticos) da entry do widget.
- O CSS de 1,08 MB bruto (105 KB gzip) para um widget de chat é anômalo por qualquer
  padrão. **[INFERÊNCIA]** Sugere Tailwind sem purge efetivo para o entrypoint do widget,
  ou CSS do dashboard vazando para o bundle do widget.

**[INFERÊNCIA — consequência]** Como o iframe é criado imediatamente no `run()`
(`entrypoints/sdk.js:213`), **todo visitante** de um site com ChatSPX baixa ~577 KB gzip,
mesmo sem nunca clicar na bolha. Isso é 4,3× o bundle inteiro da Leadster e 4,9× o do
Zendesk+Intercom somados.

### 7.3 Code splitting: onde cortar

**[INFERÊNCIA]** A régua correta para decidir o que é *loader* e o que é *app*:

> **Está no loader** aquilo sem o que a bolha não pode aparecer com aparência correta.
> **Todo o resto** é on-demand.

O que costuma estar no loader e não deveria:
- Biblioteca de datas completa (`date-fns` inteiro em vez de 2 funções).
- Emoji picker e seu dicionário.
- Markdown renderer (só faz falta quando há mensagem).
- i18n de todos os idiomas (carregue um; busque o resto).
- Ícones como componentes em vez de sprite/SVG inline.
- DOMPurify (só faz falta quando há conteúdo remoto).

**[FATO]** O Chatwoot importa `js-cookie`, `md5`, `date-fns/addHours` e vários helpers
compartilhados no `sdk.js` (`entrypoints/sdk.js:1-19`, `IFrameHelper.js:1-38`).
`md5` está lá só para calcular o hash de comparação do cookie de usuário em `setUser`.

**[INFERÊNCIA]** `md5` (~4 KB) no loader para uma comparação de cache é caro. `SubtleCrypto`
(nativo) ou um hash simples de string resolveriam a zero bytes. Não é criptografia — é só
detectar se o objeto de usuário mudou.

### 7.4 Preconnect, dns-prefetch e prioridade

**[MEDIDO]** O loader do Crisp contém `dns-prefetch` e `preconnect` explícitos.

**[INFERÊNCIA]** A sequência correta e barata:

```html
<!-- ilustrativo -->
<link rel="dns-prefetch" href="https://chat.exemplo.com">
<link rel="preconnect"   href="https://chat.exemplo.com" crossorigin>
```

- `dns-prefetch` custa quase nada e resolve o DNS cedo.
- `preconnect` abre TCP+TLS — mais caro; use no máximo 2–4 origens e só as que serão
  realmente usadas, senão compete com o LCP.
- Emitir o `preconnect` **no hover da bolha** (padrão facade) é o melhor dos dois mundos:
  zero custo no load, latência quase zero no clique.

**[FATO]** O `fetchpriority="low"` no script do widget é a forma padronizada de dizer ao
navegador para não competir com a imagem do LCP. **[NÃO VERIFICADO]** Nenhum dos bundles
inspecionados o usa.

### 7.5 CLS: o pecado do botão flutuante

**[FATO]** O guia de Core Web Vitals recomenda "esconder widgets até estarem prontos usando
transições de opacidade atreladas a callbacks `ready()` específicos do fornecedor, para
prevenir layout shifts".
Fonte: <https://www.corewebvitals.io/pagespeed/chat-widget-perfect-core-web-vitals>

**[INFERÊNCIA]** Na verdade, um botão `position: fixed` **não deveria** causar CLS, porque
sai do fluxo. CLS aparece quando:
- O widget insere algo no fluxo (banner de convite no topo, por exemplo).
- A bolha muda de tamanho depois de aparecer (rótulo expandido chegando depois do ícone).
- A fonte do rótulo carrega depois e o botão redimensiona (FOUT → shift).
- O widget empurra elementos `fixed` do próprio site (botão de "voltar ao topo").

**[FATO]** O Chatwoot evita o pior caso: o iframe nasce com `visibility: hidden`
(`IFrameHelper.js:73`) e só aparece no evento `loaded` (`IFrameHelper.js:302-304`). E a
bolha é criada com dimensões fixas em CSS (`64×64`), então não redimensiona.

**[FATO]** Mas o rótulo expandido **é** preenchido depois, por mensagem:
`setBubbleLabel` → `setBubbleText` → `textNode.innerText = bubbleText`
(`bubbleHelpers.js:21-26`). Com `woot-widget--expanded`, `width: auto !important`
(`sdk.js:110`) — a largura muda quando o texto chega. **[INFERÊNCIA]** Como o elemento é
`fixed`, não conta para o CLS da página, mas é um *jank* visual perceptível.

### 7.6 `content-visibility`

**[FATO]** `content-visibility: auto` "liga contenção de layout, de estilo e de pintura; se
o elemento não é relevante para o usuário (fora da viewport), ele pula a renderização", e
"conteúdos pulados permanecem acessíveis a recursos do agente de usuário como find-in-page
e navegação por tab". `contain-intrinsic-size` fornece um tamanho padrão para prevenir
layout shift. Baseline desde setembro de 2024.
Fonte: <https://developer.mozilla.org/en-US/docs/Web/CSS/content-visibility>

**[INFERÊNCIA]** Aplicação num chat: uma conversa longa (centenas de mensagens) pode aplicar
`content-visibility: auto` + `contain-intrinsic-size` por bloco de data ou por mensagem, e
ganhar a maior parte do benefício de uma lista virtualizada com uma linha de CSS e **sem**
os bugs de virtualização (perda de posição de scroll, seleção quebrada, Ctrl+F que não
acha). Para um widget de chat — onde a conversa raramente passa de algumas centenas de
mensagens — essa é quase certamente a escolha certa em vez de virtualização.

Cuidado: `content-visibility: hidden` **não** é acessível (equivalente a `display: none`
para find-in-page). Só `auto` serve aqui.

### 7.7 Cache, CDN, versionamento e invalidação

**[MEDIDO]** Cabeçalhos reais do CDN da Leadster:

```
cache-control: public, max-age=43200          (12 horas)
etag: "cb683b5ad943cc9e5e7eb40c41670fe1"
last-modified: Fri, 31 Jul 2026 12:08:32 GMT
access-control-allow-origin: *
cf-cache-status: HIT
server: cloudflare                            (origem: Google Cloud Storage)
```

**[INFERÊNCIA]** `max-age=43200` numa **URL não versionada** (`neurolead.min.js`) significa:
- Um patch de segurança leva até 12 horas para chegar a todos os visitantes.
- Não há rollback instantâneo: o bundle velho fica cacheado no browser.
- É a troca clássica de "URL estável, cache curto" contra "URL versionada, cache eterno".

**A prática correta** (**[INFERÊNCIA]**):

| Recurso | URL | `Cache-Control` |
|---|---|---|
| Loader | `/loader.js` (estável) | `max-age=300, stale-while-revalidate=86400` |
| App | `/app/v4.9.2/main-a1b2c3.js` (imutável) | `max-age=31536000, immutable` |
| Config por conta | `/c/<token>.json` | `max-age=60, stale-while-revalidate=600` |

O loader curto permite corrigir rápido; o app imutável permite cache eterno; a config
separada permite mudar cor/idioma sem invalidar o app. `stale-while-revalidate` dá o melhor
dos dois mundos: serve do cache imediatamente e revalida em background.

### 7.8 O que o Crisp faz — e a discussão que isso levanta

**[MEDIDO]** O loader do Crisp contém, verbatim:

```javascript
this.u = {
  domains: [],
  agents: ["Trident","Googlebot","Bingbot","Slurp","DuckDuckBot","Baiduspider",
           "YandexBot","GTmetrix","Lighthouse","Acunetix","Ahrefs","SemrushBot",
           "SiteAuditBot","SplitSignalBot","HeadlessChrome"],
  engines: [ /* seletores de sites específicos */ ]
};
// ...
i.lt = function (t = "") {           // t = navigator.userAgent
  var i = !1;
  try { for (var n = 0; n < this.u.agents.length; n++)
          if (-1 !== t.indexOf(this.u.agents[n])) { i = !0; break } }
  catch (e) {} finally { return i }
};
```

**[FATO]** A lista inclui `Lighthouse`, `GTmetrix` e `HeadlessChrome`, que **não são
crawlers de busca** — são as ferramentas com que se mede performance.

**[INFERÊNCIA]** Isso significa que **as medições de performance de um site com Crisp não
incluem o Crisp**. Quando o cliente roda PageSpeed Insights, o widget não carrega e o site
parece rápido. Os usuários reais continuam pagando o custo.

Há uma leitura caridosa e uma dura, e ambas são plausíveis:
- **Caridosa:** não faz sentido carregar um chat para um bot; economiza infra e não polui
  as métricas do cliente com algo que o bot nunca usaria.
- **Dura:** é *gaming* de auditoria. Os dados de campo (CrUX), que é o que o Google
  realmente usa para ranking, vêm de usuários reais e **incluem** o widget. Então a
  otimização engana o cliente e o consultor de SEO, não o Google.

**[INFERÊNCIA]** Bloquear `Googlebot`/`Bingbot` é defensável e comum. Bloquear
`Lighthouse`/`GTmetrix` é uma decisão de produto que eu **não** recomendaria replicar: se o
widget é lento o suficiente para precisar se esconder da régua, o problema é o widget.

Vale notar também: `HeadlessChrome` na lista quebra testes E2E (Playwright/Puppeteer) do
próprio cliente, que passam a nunca ver o widget. **[INFERÊNCIA]** Isso é um custo de
suporte real e provavelmente não intencional.

**[MEDIDO]** O Crisp também faz *differential serving* por versão de navegador:

```javascript
this.S = [
  { pattern: /edg(?:e)?\/([0-9.]+)/,      versions: { support: 18,  legacy: 117 } },
  { pattern: /chrom(?:e|ium)\/([0-9.]+)/, versions: { support: 63,  legacy: 117 } },
  { pattern: /firefox\/([0-9.]+)/,        versions: { support: 67,  legacy: 67  } },
  { pattern: /opr\/([0-9.]+)/,            versions: { support: 50,  legacy: 103 } },
  { pattern: /version\/([0-9.]+)(?: mobile\/(?:[^\s]+))? safari\//,
                                          versions: { support: 12,  legacy: 14  } },
  { pattern: /android ([0-9.]+)/,         versions: { support: 5,   legacy: 10  } }
];
```

**[INFERÊNCIA]** Duas fronteiras: abaixo de `support`, não carrega nada; entre `support` e
`legacy`, carrega um bundle transpilado (mais pesado); acima de `legacy`, carrega o bundle
moderno. É o padrão *module/nomodule* feito à mão, com granularidade por versão. É trabalho
sério e mostra que o Crisp trata o orçamento de bytes como recurso de primeira classe.

---

## 8. Acessibilidade

### 8.1 O que a norma exige, especificamente

**[FATO]** A técnica **ARIA23** do W3C/WAI é a referência direta para chat: "Usando
`role=log` para identificar atualizações sequenciais de informação". Ela mapeia para o
critério de sucesso **4.1.3 Status Messages** (WCAG 2.1 AA, mantido em 2.2).
Fonte: <https://www.w3.org/WAI/WCAG21/Techniques/aria/ARIA23>

**[FATO]** Valores implícitos de `role="log"`: `aria-live="polite"` e `aria-atomic="false"`.
O exemplo oficial é literalmente uma conversa de chat:

```html
<!-- [CITAÇÃO — W3C ARIA23] -->
<div id="chatRegion" role="log" aria-labelledby="chatHeading">
  <h4 id="chatHeading">Chat History</h4>
  <ul id="conversation">
    <li>The latest chat message</li>
  </ul>
</div>
```

**[FATO]** Exemplo funcional do W3C:
<https://www.w3.org/WAI/WCAG21/working-examples/aria-role-log/chatlog.html>

### 8.2 Critérios WCAG 2.2 que mordem um widget de chat

| Critério | Nível | O que quebra num chat típico |
|---|---|---|
| 1.4.3 Contraste mínimo (4.5:1) | AA | cor de marca do cliente sobre a bolha; texto cinza em `placeholder`; timestamp |
| 1.4.11 Contraste não textual (3:1) | AA | borda do input, ícone de enviar, indicador de foco |
| 2.1.1 Teclado | A | emoji picker, upload, seleção de resposta rápida |
| 2.1.2 Sem armadilha de teclado | A | focus trap mal feito que não deixa sair |
| 2.4.3 Ordem de foco | A | painel abre e o foco fica no `<body>` |
| **2.4.11 Foco não obscurecido (mínimo)** | **AA (novo em 2.2)** | **a bolha do chat cobre o elemento focado do site** |
| 2.4.7 Foco visível | AA | outline removido "por estética" |
| **2.5.8 Tamanho do alvo (mínimo 24×24)** | **AA (novo em 2.2)** | **botão de fechar pequeno; ações inline na mensagem** |
| 3.2.6 Ajuda consistente | A (novo em 2.2) | posição do chat mudando entre páginas |
| 4.1.3 Mensagens de status | AA | mensagem nova não anunciada (→ `role="log"`) |

**[INFERÊNCIA]** O **2.4.11 (Focus Not Obscured)** é o critério novo mais relevante e o
menos discutido: uma bolha fixa no canto inferior direito **cobre** o elemento que recebeu
foco quando o usuário tabula até o rodapé. Isso é, literalmente, o modo de operação padrão
de todo widget de chat do mercado. **[NÃO VERIFICADO]** Não encontrei nenhum fornecedor
tratando isso explicitamente. Mitigações possíveis: recolher a bolha quando houver foco
por teclado em elemento sobreposto; ou usar `scroll-margin-block-end` no host (mas o
fornecedor não controla o host).

### 8.3 Gerenciamento de foco: a coreografia correta

```
estado FECHADO
  bolha: tabulável (é um <button>), aria-expanded="false",
         aria-label traduzido ("Abrir chat de atendimento"),
         aria-controls apontando para o painel

abrir (clique ou Enter/Space)
  → painel renderiza
  → foco vai para o campo de mensagem (ou para o cabeçalho, se houver conteúdo a ler antes)
  → aria-expanded="true"
  → foco fica preso no painel (focus trap) SE o painel for modal em mobile
  → em desktop (painel não modal) NÃO prender: o usuário deve poder tabular de volta ao site

nova mensagem do agente
  → inserida dentro do container role="log"
  → NÃO mover o foco (isso rouba o contexto de quem está digitando)
  → o leitor de tela anuncia por conta do aria-live implícito

fechar (Esc ou clique)
  → foco volta para a bolha
  → aria-expanded="false"
```

**[FATO]** As boas práticas de foco descritas na literatura batem com isso: "o launcher
deve ser focável e alcançável por Tab. Quando o widget abre, o foco deve mover para o campo
de mensagem. Ao fechar, retornar o foco ao launcher. Prender o foco apenas quando o widget
está aberto, não quando minimizado."
Fonte: <https://threada.ai/blog/wcag-22-chat-widget-accessibility-checklist/>

**[FATO]** O Chatwoot faz **um** desses passos: retorna o foco à bolha ao fechar.

```javascript
// app/javascript/sdk/bubbleHelpers.js:74-83
const handleBubbleToggle = newIsOpen => {
  IFrameHelper.events.onBubbleToggle(newIsOpen);
  if (newIsOpen) { dispatchWindowEvent({ eventName: CHATWOOT_OPENED }); }
  else { dispatchWindowEvent({ eventName: CHATWOOT_CLOSED }); chatBubble.focus(); }
};
```

**[FATO]** E não faz os outros. Verificado por grep em `app/javascript/widget/`:
- **Nenhuma** ocorrência de `role="log"`, `role="status"` ou `aria-live`.
- `aria-label` aparece em 2 lugares apenas (`ChatInputWrap.vue:142` no textarea e
  `:159` no botão de emoji).
- Não há `aria-expanded` nem `aria-controls` na bolha; o `title` é a string **hardcoded em
  inglês** `'Open chat window'` (`bubbleHelpers.js:60`) — não passa por i18n.
- Não há focus trap.
- Não há foco automático no composer ao abrir (o `focus()` de `ChatInputWrap.vue:122` é
  disparado por outro fluxo, não pela abertura).

**[INFERÊNCIA]** O impacto prático: um usuário de leitor de tela **não é notificado** de
mensagens novas do agente. Ele precisa entrar no iframe e navegar manualmente para
descobrir que foi respondido. Isso é a falha de acessibilidade mais grave do widget, e é
uma falha de 4.1.3 (nível AA).

**[INFERÊNCIA]** O agravante arquitetural: por estar em iframe, mesmo adicionando
`role="log"` dentro do widget, o anúncio só acontece se o usuário tiver o "contexto" do
iframe. A solução completa exige um `aria-live` **no documento do host** (região
visualmente oculta, atualizada por `postMessage` com o texto "Nova mensagem de <agente>"),
o que hoje não existe.

### 8.4 Contraste automático

**[FATO]** O Zendesk ajusta cores automaticamente: "para fins de acessibilidade, o Web
Widget (Classic) ajusta cores automaticamente usando um algoritmo para garantir uma razão
de contraste mínima conforme as diretrizes WCAG".
Fonte: <https://support.zendesk.com/hc/en-us/articles/4408832257562-Advanced-customization-of-Web-Widget-Classic->

**[FATO]** O Chatwoot tem uma versão rudimentar disso: `isWidgetColorLighter(widgetColor)`
troca o ícone e o texto para escuro quando a cor de marca é clara
(`IFrameHelper.js:321-324`, `sdk.js:113-115` e `:143-145`).

**[INFERÊNCIA]** É binário (claro/escuro), não calcula razão de contraste real. Um verde
médio pode falhar 4.5:1 nos dois modos. O correto é calcular a luminância relativa e
escolher preto ou branco pelo maior contraste — e avisar o cliente no painel de
configuração quando a cor escolhida não atinge o mínimo em nenhum dos dois.

### 8.5 `prefers-reduced-motion`

**[FATO]** O CSS do SDK do Chatwoot tem 9 declarações de `transition` com `transform`,
`scale` e `rotate` (`app/javascript/sdk/sdk.js:197-240`), incluindo
`transform: translateX(8px) scale(.75) rotate(45deg)`.

**[FATO]** Não há nenhuma media query `prefers-reduced-motion` em todo o arquivo.

**[INFERÊNCIA]** Para um usuário com sensibilidade vestibular, uma bolha que gira e escala
a cada abertura/fechamento é desconfortável. O conserto é ~5 linhas de CSS e é obrigatório
sob 2.3.3 (AAA) e recomendado sob boas práticas de AA.

### 8.6 Checklist de acessibilidade de chat

- [ ] Container da conversa com `role="log"` (ou `role="region" aria-live="polite"`).
- [ ] `aria-live` **no host** para anunciar mensagem nova quando o widget está em iframe.
- [ ] Bolha é `<button>` com `aria-expanded`, `aria-controls` e `aria-label` **traduzido**.
- [ ] Badge de não lidas com texto acessível ("3 mensagens não lidas"), não só o ponto.
- [ ] Foco vai para o composer ao abrir; volta para a bolha ao fechar; `Esc` fecha.
- [ ] Focus trap **apenas** quando o painel é modal (mobile fullscreen).
- [ ] Todos os alvos ≥ 24×24 px (WCAG 2.2 — 2.5.8); ideal 44×44.
- [ ] Contraste ≥ 4.5:1 para texto e ≥ 3:1 para bordas/ícones, calculado, não presumido.
- [ ] Foco visível com outline de contraste ≥ 3:1 contra os dois fundos adjacentes.
- [ ] `prefers-reduced-motion: reduce` desliga transform/scale/rotate.
- [ ] Mensagem nova **não** rouba o foco.
- [ ] Anexos e emoji picker operáveis 100% por teclado, com rótulos.
- [ ] Testado com NVDA + Firefox, VoiceOver + Safari, e navegação só por teclado.

---

## 9. Mobile web

### 9.1 O teclado virtual: o problema mais mal resolvido da web

**[FATO]** O diagnóstico canônico: "no Safari do iOS, quando o teclado aparece, o Layout
Viewport permanece do mesmo tamanho mas o Visual Viewport encolhe. Itens com
`position: fixed; bottom: 0;` podem ficar escondidos debaixo do teclado virtual."
Fonte: <https://www.bram.us/2021/09/13/prevent-items-from-being-hidden-underneath-the-virtual-keyboard-by-means-of-the-virtualkeyboard-api/>

**[FATO]** E por que `100vh` não resolve: "quando o teclado virtual aparece, unidades de
viewport como `100vh` não levam em conta a presença desse teclado".
Fonte: idem.

### 9.2 As quatro gerações de solução

| Geração | Técnica | Suporte | Veredito |
|---|---|---|---|
| 1 | `--vh` custom property atualizada em `resize` | universal | funciona mal; jank; não detecta teclado |
| 2 | `window.visualViewport` + listeners de `resize`/`scroll` | Safari 13+, Chrome 61+ | preciso, mas caro e cheio de casos de borda |
| 3 | Unidades dinâmicas `dvh` / `svh` / `lvh` | Baseline moderno | **melhor custo-benefício** |
| 4 | `interactive-widget=resizes-content` no meta viewport + VirtualKeyboard API | Chromium | mais controle; suporte parcial |

**[FATO]** Sobre a geração 3: "unidades de viewport dinâmicas contabilizam o teclado de
tela. A unidade `dvh` reflete a altura visível do viewport, ajustando quando o teclado
aparece, e funciona no Safari do iOS e no Android (versões recentes)."
Fonte: <https://www.franciscomoretti.com/blog/fix-mobile-keyboard-overlap-with-visualviewport>

**[FATO]** Sobre a geração 4, o meta viewport ganhou a chave `interactive-widget`:
`<meta name="viewport" content="width=device-width, interactive-widget=resizes-content">`.
Fonte: <https://www.htmhell.dev/adventcalendar/2024/4/>

**[FATO]** O widget do Chatwoot **não usa nenhuma das gerações 2, 3 ou 4**. Grep negativo
em `app/javascript/widget/` e `app/javascript/sdk/` para `dvh`, `visualViewport`,
`safe-area` e `env(`.

**[FATO]** Usa `100vh` e `100%`:

```css
/* app/javascript/sdk/sdk.js */
.woot-widget-holder iframe { height: 100% !important; max-height: 100vh !important; }
@media only screen and (max-width: 667px) {
  .woot-widget-holder { height: 100%; right: 0; top: 0; width: 100%; }
  .woot-widget-holder iframe { min-height: 100% !important; }
}
.woot--hide { bottom: -100vh !important; ... }
```

**[FATO]** E o `<meta viewport>` do documento do widget desabilita o zoom:

```html
<!-- app/views/widgets/show.html.erb:6 -->
<meta name="viewport" content="width=device-width, initial-scale=1,
      maximum-scale=1, user-scalable=0" />
```

**[INFERÊNCIA — dois problemas]**
1. **`user-scalable=0` + `maximum-scale=1` viola WCAG 1.4.4 (Resize Text, nível AA)**, que
   exige poder ampliar até 200%. É uma prática que o mercado adotou para evitar o
   auto-zoom do iOS em inputs com `font-size < 16px` — a solução correta é usar
   `font-size: 16px` no input, não desligar o zoom do usuário. iOS moderno ignora
   `user-scalable=0`, mas Android não.
2. **Sem `dvh`/`visualViewport`, o composer no mobile fica sob o teclado** em pelo menos
   parte dos casos. **[NÃO VERIFICADO]** — não testei em dispositivo real; a conclusão vem
   da ausência das mitigações conhecidas + o uso de `100%`/`100vh`.

### 9.3 Safe area e notch

```css
/* ilustrativo */
.chat-composer {
  padding-block-end: max(12px, env(safe-area-inset-bottom));
  padding-inline: max(12px, env(safe-area-inset-left)) max(12px, env(safe-area-inset-right));
}
```

Requer `viewport-fit=cover` no meta viewport para as variáveis `env()` terem valor
diferente de zero. **[FATO]** O widget do Chatwoot não tem `viewport-fit=cover` nem
`env(safe-area-inset-*)`. **[INFERÊNCIA]** Em iPhone com barra de gestos, o botão de enviar
pode ficar colado (ou sob) a barra inferior no modo fullscreen.

### 9.4 Fullscreen versus bolha em mobile

**[FATO]** O Chatwoot faz fullscreen abaixo de 667 px de largura (`sdk.js:242-279`), e
esconde a bolha de fechar (`bottom: 60px; opacity: 0; visibility: hidden`) quando aberto —
o fechamento fica a cargo do header dentro do iframe (`toggleCloseButton` envia
`{ isMobile }` para o app, `IFrameHelper.js:341-347`).

**[INFERÊNCIA]** Fullscreen em mobile é a escolha certa. O ponto fino é o **botão físico de
voltar do Android**: um widget fullscreen que não intercepta `popstate` faz o usuário sair
do site inteiro quando queria só fechar o chat. A técnica é empurrar uma entrada de
histórico ao abrir (`history.pushState`) e fechar no `popstate`. **[FATO]** Não há nenhum
tratamento de `popstate` no widget (grep negativo).

### 9.5 Gestos

**[INFERÊNCIA]** Comportamentos esperados por usuários de mobile em 2026, e o que custa:

| Gesto | Expectativa | Implementação |
|---|---|---|
| Arrastar para baixo no header | fecha o painel | `touchstart/move/end` + `transform`, ou `<dialog>` + CSS |
| Deslizar em uma mensagem | responder | swipe-to-reply (padrão WhatsApp) |
| Puxar para baixo no topo da lista | carregar histórico | `IntersectionObserver` no topo é melhor |
| Toque fora | fecha (só quando não é fullscreen) | overlay clicável |

**[FATO]** O Chatwoot tem `DragWrapper.vue` no widget — mas é para *drag and drop de
arquivo*, não gesto de fechar. **[FATO]** Tem `MessageReplyButton.vue` (botão, não swipe).

**[FATO]** `overscroll-behavior` não aparece em nenhum arquivo do widget; o
*scroll chaining* é combatido por um listener `wheel` não-passivo no SDK
(`IFrameHelper.js:121-135`), que só cobre mouse, não toque.

### 9.6 PWA e app nativo

- **PWA:** um widget de chat dentro de uma PWA instalada escapa do cap de 7 dias do ITP
  (§5.2), o que é uma vantagem real de continuidade. **[FATO]** conforme
  <https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/>
- **Deep link para app nativo:** se o cliente tem app, o widget deveria oferecer
  "continuar no app" via Universal Link / App Link. Nenhum dos produtos inspecionados faz.
- **WebView:** **[FATO]** o Chatwoot tem tratamento explícito de WebView
  (`allow_mobile_webview` na flag 5 do bitmask de `feature_flags`, mais o
  `embedded_from_non_web_origin?` em §6.3, mais `RNHelper.isRNWebView()` no `App.vue:61`).
  Isso é maduro e pouco comum.

### 9.7 Handoff para WhatsApp

**[FATO]** O formato é `https://wa.me/<numero>?text=<mensagem URL-encoded>`, com o número em
formato internacional sem espaços, traços, sinais de mais ou zeros à esquerda.
Fonte: <https://u2l.ai/blog/whatsapp-click-to-chat-link>

**[FATO]** "O texto pré-preenchido é uma mensagem que sua empresa recebe: o que estiver em
`?text=` chega na sua caixa literalmente como a primeira mensagem do cliente."
Fonte: idem. **[NÃO VERIFICADO]** O número citado nessa fonte de "30–50% de aumento na
conversão de toque→envio" não tem metodologia publicada; tratar como marketing.

**[MEDIDO]** A Leadster tem `https://wa.me/$` no bundle (template com interpolação) e
`img/wpp_logo.png` — ou seja, o handoff para WhatsApp é recurso de primeira classe do
produto dela.

**[INFERÊNCIA]** O design correto do handoff, para não perder o contexto:

1. O widget **não** manda o visitante embora sem carimbar: antes de abrir o `wa.me`, cria
   ou atualiza a conversa no seu backend com um marcador (`handoff_to: whatsapp`,
   `handoff_token: <uuid>`).
2. O `?text=` pré-preenchido inclui um código curto opaco (`#A7K2`) que o backend
   reconhece — assim, quando a mensagem chega pelo canal WhatsApp, você **une** a conversa
   web à conversa WhatsApp do mesmo contato, em vez de criar um contato órfão.
3. Em desktop, `wa.me` abre o WhatsApp Web; em mobile, o app. Não use `api.whatsapp.com`
   (legado) nem `whatsapp://` (falha se não instalado).
4. `target="_blank" rel="noopener"`, e nunca navegar a aba atual (o visitante perde o site
   do cliente).

**[INFERÊNCIA]** O item 2 é o que separa um handoff de um "botão de WhatsApp". Sem ele, o
lead que sai do chat vira um contato novo, sem histórico, e o time de atendimento perde a
qualificação que o bot acabou de fazer.

---

## 10. Internacionalização

### 10.1 Idiomas

**[FATO]** O widget do Chatwoot tem **55 arquivos de locale** em
`app/javascript/widget/i18n/locale/`, incluindo `ar`, `he`, `fa`, `ur`, `ur_IN` (RTL),
`pt_BR` e `pt`.

**[FATO]** A seleção de idioma tem três fontes, nesta ordem de precedência
(`entrypoints/sdk.js:50-56` e `App.vue:80-96`):
1. `chatwootSettings.locale` explícito;
2. `chatwootSettings.useBrowserLanguage` → `window.navigator.language.replace('-', '_')`;
3. `window.chatwootWebChannel.locale` (o locale da conta), como default.

Mais a troca em runtime por `window.$chatwoot.setLocale(...)`.

**[INFERÊNCIA]** `navigator.language.replace('-', '_')` transforma `pt-BR` em `pt_BR`
(bom) mas também `zh-Hant-TW` em `zh_Hant-TW` (quebrado — só o primeiro hífen é
substituído). O correto é normalizar com `Intl.Locale` e cair para o idioma base quando a
variante não existir (`pt-PT` → `pt`). **[NÃO VERIFICADO]** Não confirmei o comportamento
de fallback do i18n do widget para locales inexistentes.

### 10.2 RTL

**[FATO]** O widget implementa RTL:

```javascript
// app/javascript/widget/App.vue:63-78
isRTL() {
  return this.$root.$i18n.locale ? getLanguageDirection(this.$root.$i18n.locale) : false;
},
// ...
isRTL: { immediate: true, handler(value) { document.documentElement.dir = value ? 'rtl' : 'ltr'; } },
```

**[FATO]** E usa as variantes do Tailwind nos componentes:

```html
<!-- app/javascript/widget/components/ChatInputWrap.vue:130 -->
class="items-center flex ltr:pl-3 rtl:pr-3 ltr:pr-2 rtl:pl-2 rounded-lg ..."
```

**[FATO]** A referência de mercado recomenda o caminho oposto — **propriedades lógicas**:
"em vez de propriedades físicas como `margin-left`, use propriedades lógicas como
`margin-inline-start`, que funcionam tanto em RTL quanto em LTR."
Fonte: <https://dev.to/web_dev-usman/stop-fighting-rtl-layouts-use-css-logical-properties-for-better-design-5g3m>

**[INFERÊNCIA]** `ltr:pl-3 rtl:pr-3` funciona, mas duplica cada declaração e é fácil de
esquecer metade. `ps-3` (padding-inline-start, disponível no Tailwind) faz o mesmo com uma
classe e sem chance de divergência. É dívida de estilo, não bug — mas é dívida que cresce.

**[INFERÊNCIA]** Um ponto que quase todo mundo erra em RTL de chat: a **direção do balão**
não deve inverter com o idioma da *interface*, e sim seguir a convenção de "minhas
mensagens de um lado, do agente do outro". Em RTL, "minhas mensagens" migram para a
esquerda. Isso sai de graça com propriedades lógicas e exige cuidado manual com as físicas.

**[INFERÊNCIA]** Outro ponto: mensagens **individuais** podem ter direção diferente da
interface (um usuário árabe colando um link em inglês). O tratamento correto é
`dir="auto"` no elemento de texto da mensagem, que aplica o algoritmo bidi por parágrafo.
**[FATO]** Não há `dir="auto"` em nenhum componente de mensagem do widget (grep negativo).

### 10.3 Datas, números e moedas

**[INFERÊNCIA]** A regra é curta: `Intl.*` para tudo, nunca formatação manual.

| Necessidade | API |
|---|---|
| "há 3 minutos" | `Intl.RelativeTimeFormat(locale, { numeric: 'auto' })` |
| separador de data em conversa longa | `Intl.DateTimeFormat(locale, { dateStyle: 'full' })` |
| hora da mensagem | `Intl.DateTimeFormat(locale, { timeStyle: 'short' })` — respeita 12h/24h por locale |
| tamanho de arquivo | `Intl.NumberFormat(locale, { style: 'unit', unit: 'megabyte' })` |
| moeda (catálogo, cobrança no chat) | `Intl.NumberFormat(locale, { style: 'currency', currency })` |
| lista ("João, Maria e Ana") | `Intl.ListFormat` |
| plural | `Intl.PluralRules` — evita `count === 1 ? 'x' : 'xs'` que quebra em ru/pl/ar |

**[FATO]** O Chatwoot usa `date-fns` (`import addHours from 'date-fns/addHours'` no SDK).
`date-fns` exige importar o locale por idioma; com 55 idiomas isso é peso ou fallback
silencioso para inglês. `Intl` é nativo, zero bytes e cobre todos.

### 10.4 Fuso do horário de atendimento

**[FATO]** O Chatwoot resolve isso corretamente, e vale registrar porque é um erro comum:
o servidor envia **o offset já calculado no fuso da inbox**, não o fuso cru:

```erb
<%# app/views/widgets/show.html.erb:23-28 %>
workingHoursEnabled: <%= @web_widget.inbox.working_hours_enabled %>,
workingHours:        <%= @web_widget.inbox.working_hours.to_json.html_safe %>,
utcOffset:  '<%= ActiveSupport::TimeZone[@web_widget.inbox.timezone].now.formatted_offset %>',
timezone:   '<%= @web_widget.inbox.timezone %>',
```

**[INFERÊNCIA]** Mandar `utcOffset` já resolvido é o que faz o horário funcionar quando o
visitante está em outro fuso — a pergunta "estamos abertos?" tem que ser respondida no fuso
da **empresa**, não do visitante. Mas há uma sutileza: o offset é congelado no momento do
render da página. Se o visitante deixar a aba aberta atravessando uma virada de horário de
verão, o cálculo fica errado até recarregar. O consumidor cai para `DEFAULT_TIMEZONE = 'UTC'`
quando ausente (`useAvailability.js:8`), o que é um default perigoso: falha silenciosa para
UTC faz a empresa parecer aberta de madrugada.

### 10.5 Checklist de i18n

- [ ] Todo texto da UI vem de arquivo de locale — inclusive `title`/`aria-label` da bolha
      (hoje `'Open chat window'` está hardcoded, §8.3).
- [ ] `dir` no `<html>` do widget e `dir="auto"` no texto de cada mensagem.
- [ ] Propriedades lógicas no CSS (`padding-inline-start`), não `ltr:`/`rtl:` duplicados.
- [ ] `Intl.*` para data, hora, número, lista e plural.
- [ ] Fallback de locale por idioma base (`pt-PT` → `pt` → `en`), nunca falha silenciosa.
- [ ] Locale carregado sob demanda (55 arquivos não podem estar no bundle inicial).
- [ ] Horário de atendimento no fuso da empresa, com DST recalculado, sem default UTC mudo.
- [ ] Texto de placeholder e mensagens de erro traduzidos (é onde o inglês vaza).
- [ ] Teste de expansão: alemão ocupa ~35% mais espaço que inglês; o layout não pode quebrar.

---

## 11. Observabilidade de um widget que roda no site dos outros

### 11.1 O problema é diferente de monitorar sua própria aplicação

Você não controla: o navegador, a rede, o CSP, as extensões, os outros scripts da página,
nem a versão do seu bundle que está em cache. E você não pode pedir para o usuário abrir o
console.

**[FATO]** Não há **nenhuma** instrumentação de erro no widget nem no SDK do Chatwoot:
grep por `Sentry` e `glitchtip` em `entrypoints/widget.js` e `entrypoints/sdk.js` retorna
vazio. Os `catch` do fluxo de mensagem são silenciosos
(`actions.js`: `catch (error) { // Ignore error }`).

**[INFERÊNCIA]** Isso significa que, hoje, um erro no widget de um cliente do ChatSPX é
invisível para a operação. O visitante vê a mensagem falhar; ninguém fica sabendo.

### 11.2 O que instrumentar

| Categoria | Sinal | Por quê |
|---|---|---|
| **Instalação** | loader baixado × `chatwootSDK.run()` chamado | detecta snippet incompleto no cliente |
| **Instalação** | erro de CSP (`securitypolicyviolation`) | é o suporte nº 1 (§6.4) |
| **Carga** | tempo loader→bolha visível, loader→app pronto | regressão de performance |
| **Transporte** | taxa de reconexão, tempo até reconectar, mensagens recuperadas por `after=` | saúde do realtime |
| **Entrega** | mensagens enviadas × confirmadas × falhadas | o KPI que importa |
| **Erros** | exceções não tratadas com stack | correção |
| **Uso** | abertura, 1ª mensagem, resolução | produto |

**[FATO]** O evento `securitypolicyviolation` existe no DOM e permite ao próprio widget
detectar que foi bloqueado por CSP — mas se o script nem carregou, ele não pode se
autodenunciar. Por isso a detecção precisa ser **cruzada no servidor**: "o `GET /loader.js`
aconteceu mas nenhum `POST /telemetry/boot` veio deste `website_token` nos últimos N dias"
= instalação quebrada.

**[INFERÊNCIA]** Esse cruzamento servidor-side é a métrica de observabilidade mais valiosa
e mais barata que existe para um widget, e quase ninguém faz. Ela vira um alerta acionável
("o cliente X instalou e nunca bootou") em vez de um chamado de suporte três semanas depois.

### 11.3 Sentry/GlitchTip dentro de um widget de terceiro

Três problemas específicos, e as respostas documentadas:

**(a) Não poluir o Sentry do cliente, e não ser poluído pelo dele.**
**[FATO]** O SDK do Sentry tem `allowUrls`, que "filtra erros com base nos frames da pilha,
não na URL da página" — permitindo capturar só erros originados no seu próprio bundle.
E existe `thirdPartyErrorFilterIntegration`, que "permite filtrar erros originados de
terceiros, como extensões de navegador […] ou widgets de serviços de terceiros que também
usam Sentry".
Fonte: <https://docs.sentry.io/platforms/javascript/configuration/filtering/>

**[INFERÊNCIA]** Ou seja: a integração existe justamente porque widgets como o nosso
poluem o Sentry dos clientes. Se instrumentarmos, **temos** que usar um cliente Sentry
isolado (não o global `window.Sentry`, que pode ser do cliente) e restringir por
`allowUrls` ao nosso host.

**(b) PII.**
**[FATO]** "O hook `beforeSend` é invocado antes de um erro ou evento de mensagem ser
enviado e pode ser usado para modificar os dados do evento e remover informação sensível.
[…] garantir que dados sensíveis nunca deixem o ambiente local."
Fonte: <https://docs.sentry.io/platforms/javascript/data-management/sensitive-data/>

**[INFERÊNCIA]** Num widget de chat, o **conteúdo da mensagem é PII por definição** — pode
conter CPF, endereço, dados de saúde. Regras mínimas:
- Nunca colocar `content` de mensagem em breadcrumb, tag, extra ou nome de transação.
- `sendDefaultPii: false`.
- Redigir a URL: o token de conversa viaja na query string (§5.2) e cairia no relatório.
- Redigir corpo de request/response de qualquer breadcrumb de `fetch`/XHR.
- Session Replay: **desligado**, ou com máscara total de texto. Um replay de chat é uma
  gravação da conversa.

**(c) Volume e amostragem.**
**[INFERÊNCIA]** Um widget em milhares de sites gera ordens de grandeza mais eventos que um
dashboard. Sem amostragem, o custo explode e o sinal se perde. Desenho recomendado:
- `sampleRate` de erros: 100% para erros novos, decaindo por *fingerprint* (o mesmo erro
  10.000 vezes/hora não precisa de 10.000 eventos).
- `tracesSampleRate` baixo (0,01–0,05) e dinâmico.
- **Rate limit no cliente**: no máximo N eventos por sessão, para não transformar um loop
  de erro num ataque ao próprio endpoint.
- Bloquear erros vindos de extensões (`chrome-extension://`) e de outras origens.

### 11.4 Métricas de entrega — o que realmente importa

**[INFERÊNCIA]** Um painel útil de widget tem quatro números, e nenhum deles é "erros":

1. **Taxa de boot:** `run()` bem-sucedidos ÷ loaders baixados. Cai → instalação/CSP.
2. **Taxa de entrega da 1ª mensagem:** mensagens confirmadas ÷ tentadas, na 1ª mensagem da
   sessão. Cai → backend, rate limit, ou rede.
3. **Tempo até a resposta do agente (TTFR).** É produto, não infra, mas é o que o cliente
   compra.
4. **Taxa de reconexão silenciosa:** quantas sessões precisaram do `syncLatestMessages`.
   Sobe → problema de infraestrutura de WebSocket (LB derrubando conexão, timeout de proxy).

---

## 12. Padrões de arquitetura de backend para chat

### 12.1 Modelo de dados canônico

```
Account 1─┬─n Inbox (canal: web, whatsapp, email, …)
          │
          └─n Contact ─n ContactInbox (contato × canal, com source_id)
                              │
                              └─n Conversation ─n Message
                                       │
                                       ├─ status: open | pending | snoozed | resolved
                                       ├─ assignee (Agent), team
                                       └─ labels, custom_attributes
```

**[FATO]** Este é o modelo do Chatwoot, verificável em `app/models/`. O `ContactInbox`
carrega `source_id` (o identificador do contato **naquele canal**) e `pubsub_token` (o
canal de realtime daquele contato). Confirmado por uso em
`app/controllers/widgets_controller.rb:44-52` e no bundle da Leadster (§4.3).

**[INFERÊNCIA]** A peça de design mais importante aqui é o **`ContactInbox`**: ele separa
"quem é a pessoa" de "como ela chegou". É o que permite unificar o mesmo humano que falou
pelo site e pelo WhatsApp, sem forçar a unificação (que seria errada quando não se tem
certeza). Muita implementação caseira erra isso colocando `phone`/`email` direto na
conversa.

### 12.2 Presença de agente

Três níveis:
1. **Online/offline binário** por heartbeat.
2. **Disponibilidade declarada** (online / ocupado / ausente), independente do heartbeat.
3. **Capacidade** (nº de conversas simultâneas), que alimenta o roteamento.

**[FATO]** O Chatwoot faz heartbeat por ActionCable: `update_presence` a cada 20 s no
dashboard e **60 s no widget**, com jitter de até 5 s
(`BaseActionCableConnector.js:4-5, 69-78`; `widget/helpers/actionCable.js:16`).

**[INFERÊNCIA]** O jitter é importante e frequentemente esquecido: sem ele, 5.000 abas
abertas às 9h00 mandam heartbeat no mesmo milissegundo a cada 20 s, criando *thundering
herd* previsível. Está correto aqui.

**[INFERÊNCIA]** O widget mandar presença a cada 60 s é caro em escala e de valor duvidoso:
o que o agente precisa saber é "o visitante ainda está na página", que é melhor obtido por
`visibilitychange` + `pagehide` (eventos, não polling).

### 12.3 Roteamento e filas

| Estratégia | Quando usar | Risco |
|---|---|---|
| Round-robin | times homogêneos | ignora carga real |
| Menor carga | volume alto | precisa de capacidade confiável |
| Por habilidade/idioma | multi-idioma, multi-produto | fila esvaziando devagar |
| Por time + fallback | operação estruturada | complexidade de config |
| Bot primeiro, humano depois | qualificação (modelo Leadster) | handoff mal feito perde o contexto |

**[INFERÊNCIA]** O ponto crítico de qualquer roteamento é o que acontece **quando ninguém
atende**: precisa haver timeout de fila com escalação, e o visitante precisa ser informado
com honestidade ("tempo de espera ~4 min" ou "responderemos por e-mail"). Silêncio é a pior
resposta e é o default de quase toda implementação.

### 12.4 Webhooks de saída e idempotência

**[INFERÊNCIA]** Regras que valem para qualquer webhook de chat:

- **Assinar** o payload: `X-Signature: sha256=HMAC(segredo, corpo)` + timestamp, com janela
  de tolerância para evitar replay.
- **ID de evento estável** (`event_id`), para o receptor deduplicar. Reentregas são normais.
- **Retry com backoff exponencial e jitter**, teto de tentativas, e *dead-letter* visível
  ao cliente.
- **Ordem não garantida.** Documentar isso; incluir `seq` no payload para o receptor
  ordenar se precisar.
- **Timeout curto** (5 s) e circuito aberto por endpoint: um cliente lento não pode
  segurar a fila dos outros.
- **Payload versionado** (`"version": "2"`), nunca mudança silenciosa de contrato.

### 12.5 Idempotência ponta a ponta

Recapitulando §4.4 do lado do servidor:

```
POST /widget/messages
  Idempotency-Key: <uuid do cliente>      (ou message.echo_id no corpo)

  servidor:
    chave existe para esta conversa? -> devolve a mensagem já criada (200), não cria outra
    senão -> cria em transação, grava a chave, devolve 201
    chave expira em ~24h
```

**[FATO]** O Chatwoot tem o campo (`echo_id`) mas o widget não o usa (§4.4).
**[INFERÊNCIA]** O `echo_id` do Chatwoot também não é *enforcement* de idempotência — ele é
usado para eco de reconciliação no painel do agente. Idempotência real exigiria índice
único em `(conversation_id, echo_id)` e o `find_or_create`. **[NÃO VERIFICADO]** Não
auditei se existe esse índice.

---

## 13. Referências open source para estudar

**[FATO]** Licenças e estado, consultados na API pública do GitHub e nos arquivos `LICENSE`
em 11/08/2026:

| Projeto | Licença | Estrelas | Stack | Estado |
|---|---|---:|---|---|
| **Chatwoot** | MIT (core) + **licença Enterprise proprietária** em `enterprise/` | 35.726 | Ruby on Rails + Vue 3 | ativo |
| **Papercups** | MIT | 6.100 | Elixir/Phoenix + React | **último push 15/02/2024** |
| **Chaskiq** | AGPL-3.0-or-later **+ Commons Clause** (`LICENSE.txt`, NOASSERTION) | 3.554 | Rails + React | ativo |
| **Tiledesk** | **MIT** (migrado de AGPL-3.0) | — | Node.js + Angular | ativo |
| **Rocket.Chat** | MIT (core) + licença própria em `ee/` | 45.958 | TypeScript/Meteor | ativo |
| **Botpress** | MIT | 14.857 | TypeScript | ativo |
| **Typebot** | **FSL-1.1-Apache-2.0** (não é OSI) | 10.251 | TypeScript/Next.js | ativo |
| **Chatscope** (`chat-ui-kit-react`) | MIT | 1.767 | React | ativo |
| **BotMan** | MIT | 6.164 | PHP | ativo |

**[FATO]** A licença do Chatwoot é explícita sobre a divisão:

```
* All content that resides under the "enterprise/" directory of this repository,
  if that directory exists, is licensed under the license defined in "enterprise/LICENSE".
* Content outside of the above mentioned directories or restrictions above is
  available under the "MIT Expat" license as defined below.
```

**[FATO]** E a licença Enterprise: "Este software […] só pode ser usado em produção se você
(e qualquer entidade que você represente) tiver concordado e estiver em conformidade com os
Chatwoot Subscription Terms of Service […] e de outra forma tiver uma licença Chatwoot
Enterprise válida para o número correto de assentos."

**[FATO]** O Tiledesk anunciou publicamente a migração de AGPL-3.0 para MIT:
<https://tiledesk.com/blog/we-have-two-surprise-announcements-we-are-moving-tiledesk-open-source-license-to-mit-and-we-will-have-a-unique-codebase-from-now-onwards/>

**[FATO]** A FSL do Typebot "não é uma licença aprovada pela OSI e restringe uso comercial
concorrente por um período antes de cada release converter para open source"
(Apache-2.0 após o período).

### 13.1 O que aprender de cada um

**Chatwoot** — *o que já temos.*
Melhor no mercado open source em: modelo de dados omnichannel (`ContactInbox`), tratamento
de Turbo/Astro no SDK, verificação HMAC com escopo de conversa, rate limiting embutido,
`frame-ancestors` por inbox, WebView mobile, 55 idiomas com RTL.
Pior em: peso do bundle do widget, acessibilidade, mobile viewport, idempotência,
validação de `origin` no `postMessage`.
**Licença:** MIT no que importa para o widget (`app/javascript/sdk` e `app/javascript/widget`
estão fora de `enterprise/`). **Seguro para estudar e derivar.**

**Papercups** — *arquivetura de realtime em Elixir.*
O que aprender: Phoenix Channels dá presença e *pubsub* distribuído de graça, com
reconexão e `join`/`leave` bem definidos — é a implementação de referência de como o
transporte *deveria* se comportar. **[FATO]** Sem push desde fevereiro de 2024: estudar o
desenho, não adotar o código.
**Licença:** MIT — permissiva.

**Chaskiq** — *o mais próximo do Intercom em recursos.*
O que aprender: sistema de *campanhas e bots visuais* dentro do widget, arquitetura
plugável ("permitindo que desenvolvedores implementem seus próprios blocos de dashboard"),
e um editor de conteúdo rico embutido no chat.
**Licença: AGPL-3.0 + Commons Clause. ⚠️ Não copiar código.** AGPL contamina serviço em
rede; a Commons Clause proíbe venda. É o pior caso possível para um produto comercial.
**Estudar apenas conceitualmente, sem olhar implementação.**

**Tiledesk** — *bot builder + chat unificados, agora MIT.*
O que aprender: o desenho do *design de fluxo conversacional* acoplado ao widget, e o
handoff bot→humano. A migração para MIT torna o código legalmente aproveitável.
**Licença: MIT — aproveitável.**

**Rocket.Chat Livechat** — *escala e multi-tenant.*
O que aprender: o widget do Rocket.Chat (`packages/livechat`) é um dos poucos open source
que trata *departamentos*, *transferência de conversa*, *transcrição por e-mail* e
*roteamento por fila* de forma completa. Também tem um dos melhores tratamentos de
`postMessage` API entre host e iframe.
**Licença:** MIT no core, mas confira o caminho específico — `ee/` é proprietário.

**Botpress webchat** — *o oposto arquitetural do Chatwoot.*
**[MEDIDO]** 598 KB brutos / 193 KB gzip num arquivo único, sem Shadow DOM, com
`@import` de Google Fonts embutido no CSS.
O que aprender: **o que não fazer** no orçamento de bytes; e, no lado positivo, o padrão de
reset com `:where(.bpReset)` (especificidade zero) e a API de configuração declarativa.
O `@import` de fonte externa é especialmente instrutivo: obriga o cliente a liberar
`fonts.googleapis.com` e `fonts.gstatic.com` na CSP dele, e adiciona duas origens ao
caminho crítico.
**Licença:** MIT.

**Typebot** — *o único com Shadow DOM de verdade.*
**[MEDIDO]** 689 KB brutos / 197 KB gzip; 3 `attachShadow`, 15 `shadowRoot`; custom
elements `typebot-bubble` e `typebot-standard`.
O que aprender: como empacotar um widget como *custom element* consumível tanto por
`<script type="module">` quanto por React/Vue wrappers, e como fazer Shadow DOM sem
perder a customização (via CSS custom properties expostas).
**Licença: FSL-1.1-Apache-2.0. ⚠️ Restringe uso comercial concorrente.** Como o ChatSPX
compete no mesmo espaço, **não copiar código** — estudar a técnica.

**Chatscope (`chat-ui-kit-react`)** — *só a UI, bem feita.*
O que aprender: a taxonomia de componentes de uma UI de chat madura (MessageList,
MessageGroup, MessageSeparator, TypingIndicator, Avatar com status, ConversationHeader) e
os detalhes de scroll/auto-scroll que sempre dão trabalho.
**Licença: MIT — aproveitável diretamente.** É a fonte mais segura da lista para copiar
padrões de UI.

**BotMan** — *abstração de canais.*
O que aprender: a ideia de *driver* por canal com uma API de conversa única. Irrelevante
para o widget em si (é PHP e do lado servidor), mas é a melhor referência conceitual de
como não acoplar a lógica de bot ao canal.
**Licença: MIT.**

### 13.2 Tabela de risco de licença

| Licença | Posso ler? | Posso copiar trecho? | Posso derivar produto comercial fechado? |
|---|---|---|---|
| MIT | sim | sim (mantendo aviso) | **sim** |
| Apache-2.0 | sim | sim (mantendo aviso + NOTICE) | sim |
| AGPL-3.0 | sim | **não** para produto fechado | **não** — contamina serviço em rede |
| AGPL + Commons Clause | sim | **não** | **não** — e proíbe venda |
| FSL-1.1 | sim | **não** enquanto restrito | **não** para concorrente |
| Chatwoot `enterprise/` | sim (código visível) | **não** sem licença paga | **não** |

**[INFERÊNCIA]** Regra prática para o time: **antes de abrir um arquivo de projeto
concorrente com intenção de aproveitar, confira a licença**. Ler AGPL não contamina; copiar
sim. E "eu me inspirei" é uma linha fina que advogados desenham diferente de engenheiros.

---

## 14. Benchmarks medidos em 11/08/2026 — tabela consolidada

Todos reprodutíveis. Comandos ao final da seção.

### 14.1 Peso

| Produto | Estágio 1 (loader) | Estágio 2 (app) | Total gzip |
|---|---:|---:|---:|
| Crisp | 2,9 KB | não medido (carregado depois) | ≥ 2,9 KB |
| Intercom | 3,2 KB | não medido | ≥ 3,2 KB |
| Zendesk | 4,0 KB | não medido | ≥ 4,0 KB |
| Chatwoot/ChatSPX | 9,5 KB | **577,4 KB** | **586,9 KB** |
| Drift | 64,1 KB | não medido | ≥ 64,1 KB |
| Leadster | — (monolito) | — | **132,9 KB** |
| Botpress v3.2 | — (monolito) | — | **193,2 KB** |
| Typebot | — (monolito) | — | **196,9 KB** |

### 14.2 Arquitetura

| Produto | Isolamento | Transporte | Backend do handoff | Bloqueia auditores? |
|---|---|---|---|---|
| Chatwoot/ChatSPX | iframe | ActionCable (WS) | próprio | não |
| Leadster | DOM do host + prefixo `nld-` | WebSocket cru | **Chatwoot** (§4.3) | não |
| Crisp | (app não inspecionado) | — | próprio | **sim** (§7.8) |
| Botpress | DOM do host + `:where(.bpReset)` | — | próprio | não |
| Typebot | **Shadow DOM** | — | próprio | não |
| Zendesk | iframe | WS (`wss://*.zendesk.com`) | próprio | não |
| Intercom | iframe (`intercom-sheets.com` em `frame-src`) | WS (`wss://*.intercom-messenger.com`) | próprio | não |

### 14.3 Reconexão

| Produto | Estratégia | Máximo | Retomada |
|---|---|---|---|
| Chatwoot/ChatSPX | exponencial 1s→30s + jitter 500ms + `visibilitychange`/`focus`/`pageshow` + watchdog 15s/25s | ilimitado | `GET ?after=<lastMessageId>` |
| Leadster | fixo 1s | **5 tentativas, depois desiste** | nenhuma |

### 14.4 Comandos de reprodução

```bash
# peso comprimido de qualquer loader
curl -sS -L -H "Accept-Encoding: gzip, br" -o /dev/null \
     -w "%{http_code} %{size_download}B %{content_type}\n" "<url>"

# peso bruto e gzip local
curl -sS -L "<url>" -o f.js && echo "raw=$(wc -c <f.js) gz=$(gzip -c f.js | wc -c)"

# cabeçalhos de cache
curl -sSI "<url>"

# peso do widget do Chatwoot a partir do manifest do Vite
# (entry entrypoints/widget.js + imports estáticos transitivos + css)
python3 -c "..."   # ver §7.2
```

---

## 15. IMPLICAÇÕES PARA O CHATSPX

> Esta seção é recomendação. Nada aqui foi implementado. Cada item cita a evidência que o
> sustenta e é classificado por impacto × esforço.

### 15.0 Resumo executivo em cinco frases

1. **O ChatSPX já é o backend que a concorrente brasileira de referência usa por baixo** —
   a Leadster roda ActionCable/`RoomChannel`/`pubsub_token` do Chatwoot para o handoff
   humano (§4.3). Nosso gap com ela não é de chat, é de **conversão e de peso**.
2. **O widget pesa 586,9 KB gzip e carrega tudo isso para 100% dos visitantes**, dos quais
   ~3–10% abrirão o chat (§7.1, §7.2). Esse é o problema número um, e é o que mais afeta o
   cliente que nos instala.
3. **Há uma falha de segurança concreta e barata de corrigir:** o `postMessage` do host não
   valida `event.origin` (§3.6), permitindo fixação de sessão por qualquer terceiro na
   mesma página.
4. **A acessibilidade está abaixo do mínimo legal:** sem `role="log"`, sem `aria-live`, sem
   foco ao abrir, com `user-scalable=0` (§8.3, §9.2). Isso é risco em cliente público e em
   cliente grande com compliance.
5. **Onde estamos à frente:** tratamento de Turbo/Astro, reconexão com `visibilitychange` e
   watchdog, HMAC com escopo de conversa, `frame-ancestors` por inbox, rate limiting
   embutido, 55 idiomas com RTL, continuidade por e-mail. Nada disso deve ser jogado fora
   numa reescrita.

### 15.1 Onde o ChatSPX está alinhado com o estado da arte

| Área | Evidência | Comentário |
|---|---|---|
| Separação loader/app | `sdk.js` 9,5 KB × app em iframe | a arquitetura está **certa**; o problema é o tamanho do app |
| Isolamento por iframe | `IFrameHelper.js:57-91` | escolha correta para SaaS multi-tenant |
| `targetOrigin` no envio | `IFrameHelper.js:96-102` | correto, não usa `'*'` |
| Reconexão | `BaseActionCableConnector.js` | exponencial + jitter + `visibilitychange` + `focus` + `pageshow` + watchdog — **acima da média do mercado** |
| Recuperação de mensagens | `syncLatestMessages` com `after=` | padrão de cursor correto |
| Timeout de "digitando" | 30 s (`actionCable.js:138`) | frequentemente esquecido; aqui existe |
| HMAC com escopo | `base_controller.rb:12-18` | contatos verificados só veem conversas verificadas — desenho fino |
| `frame-ancestors` por inbox | `widgets_controller.rb:79-97` | com tratamento explícito de WebView |
| Rate limiting | `rack_attack.rb:172-190` | existe e é documentado |
| Sanitização | `markdown-it` `html:false` + DOMPurify + `rel="noreferrer noopener nofollow"` | defesa em profundidade correta |
| Minimização de IP | `widgets_controller.rb:67-73` | coleta condicionada a feature flag — maduro |
| SPA/Turbo/Astro | `entrypoints/sdk.js:26-48` | a Leadster não tem nada equivalente |
| i18n | 55 locales + RTL + `utcOffset` resolvido no servidor | robusto |
| Continuidade por e-mail | `continuity_via_email` default `TRUE` | vantagem estrutural sobre widgets front-only |

### 15.2 Onde o ChatSPX está atrasado

Ordenado por (impacto ÷ esforço), do melhor retorno para o pior.

#### 🔴 P0 — corrigir independentemente de qualquer redesign

| # | Gap | Evidência | Por que é P0 |
|---|---|---|---|
| 1 | **`window.onmessage` sem validar `event.origin`** | `IFrameHelper.js:104-117` | Qualquer terceiro na página do cliente pode gravar `cw_conversation` (fixação de sessão) ou apagar identidade. Contraria a orientação explícita da MDN (§3.6). Correção: `addEventListener` + comparação com a origem do `baseUrl`. |
| 2 | **Token de sessão na query string** | `IFrameHelper.js:65-68` | O JWT de 180 dias viaja na URL do iframe → vaza em `Referer`, logs e histórico. |
| 3 | **`allowed_domains` vazio por padrão** | `web_widget.rb:6`, `widgets_controller.rb:80` | Qualquer site do mundo embute o widget de qualquer conta. Deveria ser preenchido no onboarding com o `website_url` que já é obrigatório. |
| 4 | **Cookie sem `Secure` nem `Partitioned`** | `cookieHelpers.js:26-45` | `SameSite=Lax` sem `Secure` é rejeitado em contexto cross-site; sem `Partitioned` o Chrome tende a bloquear (§5.1). |
| 5 | **Sem `role="log"` / `aria-live`** | grep negativo em `widget/` | Falha WCAG 4.1.3 (AA). Usuário de leitor de tela não sabe que foi respondido (§8.3). |

#### 🟠 P1 — alto impacto, esforço médio

| # | Gap | Evidência | Ganho esperado |
|---|---|---|---|
| 6 | **App de 577 KB gzip carregado para todos** | §7.2 | Facade + carga sob demanda tiraria ~570 KB do caminho de 90–97% dos visitantes. É o maior ganho isolado disponível. |
| 7 | **CSS de 1,08 MB bruto / 105 KB gzip** | §7.2 | Anômalo. Investigar purge do Tailwind e vazamento de CSS do dashboard para o entrypoint do widget. |
| 8 | **`echo_id` não enviado; reconciliação por conteúdo** | `endPoints.js:25-39`, `helpers.js:46-49` | Bug latente de duplicação/sumiço de mensagem (§4.4). O backend **já aceita** o campo — é uma linha no front. |
| 9 | **Sem fila offline nem retry** | `actions.js` `catch` → `status:'failed'` | Mensagem perdida em rede instável é a pior experiência possível num chat (§4.5). |
| 10 | **`MutationObserver` global no `<body>` do cliente** | `DOMHelpers.js:49-75` | Custo de INP no site alheio. Substituível por Navigation API + patch de `history` a custo ~zero (§2.6). |
| 11 | **Sem `dvh`/`visualViewport`/`safe-area`** | grep negativo | Composer sob o teclado em mobile (§9.2). `dvh` resolve a maior parte com CSS. |
| 12 | **`user-scalable=0, maximum-scale=1`** | `widgets/show.html.erb:6` | Viola WCAG 1.4.4 (AA). Substituível por `font-size: 16px` nos inputs. |
| 13 | **Zero observabilidade no widget** | grep negativo por Sentry/GlitchTip | Erro no cliente é invisível para nós. Já temos GlitchTip na frota — falta instrumentar o widget com cliente isolado + scrubbing de PII (§11.3). |

#### 🟡 P2 — melhora real, esforço maior ou valor menos imediato

| # | Gap | Evidência | Nota |
|---|---|---|---|
| 14 | Sem stub queue (API só após `chatwoot:ready`) | `web_widget.rb#web_widget_script` | ~200 bytes eliminam a classe inteira de bug de integração (§2.2). |
| 15 | Sem sentinela de dupla inclusão **no snippet** | idem | Hoje a proteção é depois do download. |
| 16 | Sem `preconnect` / `fetchpriority` | grep negativo | Latência do primeiro clique. |
| 17 | Sem sincronização entre abas | grep negativo | N abas = N conexões, N sons, badge inconsistente (§4.7). Web Locks + BroadcastChannel. |
| 18 | Sem `content-visibility` na lista | grep negativo | Conversa longa fica pesada; 2 linhas de CSS (§7.6). |
| 19 | Sem `prefers-reduced-motion` | `sdk.js:197-240` | ~5 linhas de CSS (§8.5). |
| 20 | Sem `dir="auto"` por mensagem | grep negativo | Texto misto LTR/RTL renderiza errado (§10.2). |
| 21 | `ltr:`/`rtl:` duplicados em vez de propriedades lógicas | `ChatInputWrap.vue:130` | Dívida de estilo (§10.2). |
| 22 | `title="Open chat window"` hardcoded em inglês | `bubbleHelpers.js:60` | Vaza inglês em conta pt-BR — e é o rótulo acessível da bolha. |
| 23 | Sem `popstate` (botão voltar do Android fecha o site) | grep negativo | §9.4. |
| 24 | Sem `overscroll-behavior` | grep negativo | Substitui o listener `wheel` não-passivo do SDK (§3.2). |
| 25 | Contraste binário claro/escuro | `IFrameHelper.js:321-324` | Não calcula razão real; Zendesk faz melhor (§8.4). |
| 26 | `iframe.allow` permissivo (`display-capture`, `clipboard-write`) | `IFrameHelper.js:70-71` | Reduzir ao que o produto realmente usa. |
| 27 | `md5` no loader para comparar cache | `cookieHelpers.js:21` | ~4 KB do orçamento de 9,5 KB por uma comparação. |
| 28 | Sem `sandbox` no iframe | `IFrameHelper.js:63-91` | Avaliar com cuidado — `allow-scripts` + `allow-same-origin` juntos anulam (§3.2). |
| 29 | Cache do `sdk.js` não versionado por path | build atual | Impede `immutable` + rollback instantâneo (§7.7). |
| 30 | Rate limit só por IP | `rack_attack.rb` | Falso positivo em NAT corporativo (§6.7). |

### 15.3 A decisão arquitetural que precisa ser tomada antes de qualquer código

**A pergunta:** manter iframe, migrar para Shadow DOM, ou fazer híbrido?

**[INFERÊNCIA]** Minha recomendação, com o raciocínio explícito:

**Manter o iframe para o painel de conversa. Mover o chrome (bolha, badge, convite
proativo, anúncio de acessibilidade) para Shadow DOM no host.**

Por quê:

| Motivo | Peso |
|---|---|
| O iframe é o que faz o widget não quebrar em 10 mil temas WordPress. Descartá-lo trocaria 577 KB de peso por uma dívida infinita de CSS (a Leadster tem 239 `!important` para provar) | alto |
| O chrome no host resolve **de graça** três P0/P1 de uma vez: `aria-live` no documento do cliente (§8.3), badge instantâneo sem carregar o app (§7.1), e o facade que corta 570 KB (§7.2) | alto |
| A ponte `postMessage` já existe e já está estruturada; o híbrido não a inventa, só a reduz | médio |
| Shadow DOM para o chrome é pouco código e pouca superfície: um botão, um badge, uma bolha de convite | médio |
| Migração completa para Shadow DOM exigiria reescrever isolamento, testar em N temas, e ainda perderia a garantia de CSP do iframe (§6.4) | contra |

**O que isso implica na prática, em fases (proposta, não plano aprovado):**

- **Fase 0 — segurança e a11y sem mexer na arquitetura.** Itens 1–5 do P0. Não muda
  bundle, não muda UX, corrige o que é indefensável.
- **Fase 1 — orçamento de bytes.** Investigar o CSS de 1,08 MB (item 7) e o agrupamento de
  chunks do Vite. Provavelmente é o ganho mais barato de todos, e talvez nem exija
  refatoração — só configuração de build.
- **Fase 2 — chrome em Shadow DOM + facade.** O iframe só nasce no primeiro clique (ou
  quando há campanha proativa/mensagem não lida). Aqui entram os itens 6, 13, 14, 15, 16.
- **Fase 3 — confiabilidade de entrega.** Itens 8, 9, 17: `echo_id`, outbox em IndexedDB,
  Web Locks + BroadcastChannel.
- **Fase 4 — mobile e polimento.** Itens 11, 12, 18–27.

**[INFERÊNCIA]** A ordem importa: fazer Fase 2 antes da Fase 1 esconde o problema de peso
em vez de resolvê-lo (o app continua gordo, só carrega mais tarde). E fazer Fase 3 antes da
Fase 0 é priorizar conforto sobre segurança.

### 15.4 O que aprender especificamente da Leadster

**[INFERÊNCIA]** Separando o que é bom do que é ruim, com base no que medi:

**Copiar (conceito, não código):**
- **Convite proativo como recurso central**, não como afterthought. A Leadster tem
  `nld-chatbot-invite-message`, `nld-invite-message-container`, timers e regras — é o
  motor de conversão dela.
- **Atribuição de campanha na conversa.** Ler `_fbc` e `_gcl_aw` e carimbar de qual anúncio
  o lead veio. Custo baixo, valor comercial alto para clientes de performance.
- **Nota automática de abandono** (`pagehide` → `createNote`). O agente ver "o visitante
  saiu da página" muda o comportamento dele.
- **Handoff para WhatsApp como primeira classe**, com o cuidado de costura de contexto que
  descrevi em §9.7.
- **O orçamento de bytes.** 132,9 KB para o produto **inteiro** contra os nossos 586,9 KB.
  Esse número deveria estar num dashboard nosso.

**Não copiar:**
- Prefixo + 239 `!important` em vez de isolamento.
- Reconexão fixa de 1 s com desistência em 5 tentativas.
- Nenhuma retomada de mensagens perdidas.
- `z-index: 9999999999` (fora do intervalo válido).
- Carregar o pixel do Facebook a partir de um widget de chat.
- `try/catch` que engole o erro de instalação sem reportar.

**[INFERÊNCIA — a leitura estratégica]** O achado de §4.3 reposiciona a conversa
competitiva. Não estamos "atrás da Leadster no chat". Ela **usa** a nossa camada. A
diferença de mercado dela está em três coisas que não são infraestrutura: (a) o bot de
qualificação conversacional, (b) o posicionamento de marketing/conversão em vez de suporte,
e (c) um widget leve o suficiente para o time de marketing do cliente não vetar a
instalação. As três são atacáveis — e (c) é a que mais depende de engenharia pura.

### 15.5 O que NÃO fazer

**[INFERÊNCIA]** Anti-recomendações, para o caso de alguém propor:

- ❌ **Não bloquear Lighthouse/GTmetrix/HeadlessChrome** como o Crisp (§7.8). Além de ser
  gaming de auditoria, quebra os testes E2E dos clientes e não engana o CrUX, que é o que
  o Google usa de verdade.
- ❌ **Não migrar para SSE.** O ganho (retomada por `Last-Event-ID`) não compensa jogar
  fora a infraestrutura ActionCable já madura + a reconexão que já está acima da média.
  A mesma retomada já existe via `after=<lastMessageId>`.
- ❌ **Não abandonar o iframe.** Ver §15.3.
- ❌ **Não copiar código de Chaskiq (AGPL + Commons Clause) nem de Typebot (FSL).** §13.2.
- ❌ **Não adicionar SRI ao snippet** sem antes versionar o loader por path (§6.5).
- ❌ **Não "resolver" o peso só com facade.** Facade adia; não emagrece.
- ❌ **Não desligar `ENABLE_RACK_ATTACK_WIDGET_API`** para calar reclamação de NAT. A
  correção é limitar por token de conversa além do IP (§6.7).

### 15.6 Métricas para saber se deu certo

**[INFERÊNCIA]** Sem estas medições, qualquer refatoração vira opinião:

| Métrica | Onde medir | Alvo proposto |
|---|---|---|
| Bytes gzip até a bolha visível | build + WebPageTest | ≤ 20 KB |
| Bytes gzip até o chat utilizável | build | ≤ 150 KB |
| Tempo `sdk.js` → bolha visível | RUM próprio | p75 ≤ 300 ms |
| Impacto no LCP do site do cliente | comparação A/B com/sem widget | ≤ 50 ms |
| Long tasks atribuídas ao widget | `PerformanceObserver` no host | 0 acima de 50 ms |
| Taxa de boot (run ÷ loader baixado) | servidor, §11.2 | ≥ 98 % |
| Taxa de entrega da 1ª mensagem | servidor | ≥ 99,5 % |
| Sessões que precisaram de `syncLatestMessages` | servidor | ≤ 2 % |
| Violações axe-core no widget | CI | 0 críticas |
| Contraste calculado da cor de marca | painel de config | avisa quando < 4.5:1 |

---

## Anexo A — Checklist de revisão de um widget de chat

Consolidado das seções anteriores. Serve como *definition of done* de um redesign.

### A.1 Loader
- [ ] Snippet ≤ 1 KB, com sentinela de dupla inclusão e stub queue
- [ ] Injeção dinâmica, após `load`, dentro de `requestIdleCallback`
- [ ] `try/catch` + `onerror` reportado (não engolido)
- [ ] `preconnect` no hover da bolha
- [ ] Path versionado imutável para o app; loader com cache curto + `stale-while-revalidate`
- [ ] Detecção de rota por Navigation API / patch de `history`, não `MutationObserver` global
- [ ] Turbo / Turbolinks / Astro / htmx tratados

### A.2 Isolamento
- [ ] Decisão explícita (iframe / Shadow DOM / híbrido) documentada com o porquê
- [ ] `z-index` dentro de int32, filho direto de `<body>`, parâmetro configurável
- [ ] `postMessage`: `targetOrigin` exato no envio, `event.origin` validado na recepção
- [ ] `addEventListener`, nunca `window.onmessage =` (não sequestrar handler do cliente)
- [ ] Protocolo de mensagem versionado, objeto estruturado, não string com prefixo
- [ ] `overscroll-behavior: contain` no lugar de listener `wheel`

### A.3 Transporte
- [ ] Backoff exponencial + jitter + teto
- [ ] Reconexão em `visibilitychange`, `focus`, `pageshow` (bfcache)
- [ ] Watchdog de stream silencioso
- [ ] Retomada por cursor (`after=<id>` ou `Last-Event-ID`)
- [ ] `echo_id`/idempotency key gerado no cliente e enviado ao servidor
- [ ] Reconciliação otimista por ID, nunca por conteúdo
- [ ] Outbox em IndexedDB com retry serial e teto de idade
- [ ] Timeout no indicador de "digitando"
- [ ] Web Locks + BroadcastChannel para 1 conexão por navegador

### A.4 Estado
- [ ] Token de sessão via `Set-Cookie` do servidor (não `document.cookie`)
- [ ] `Secure`, `SameSite` apropriado, `Partitioned` quando cross-site
- [ ] Nada de token na query string
- [ ] Expiração do cookie coerente com a do token
- [ ] IndexedDB (assíncrono) para outbox/histórico; `localStorage` só para preferências
- [ ] `reset()` que apaga tudo, incluindo do lado servidor
- [ ] Coleta de IP condicionada a flag

### A.5 Segurança
- [ ] Markdown `html: false` + DOMPurify nos **dois** lados (widget e agente)
- [ ] Allowlist de esquemas de URL; `rel="noopener noreferrer"` em todo `target="_blank"`
- [ ] `frame-ancestors` preenchido por padrão em contas novas
- [ ] Lista de diretivas CSP publicada na doc do produto
- [ ] Não exigir `style-src 'unsafe-inline'` do cliente (sem estilo inline)
- [ ] HMAC (ou JWT com `exp`) obrigatório para contas que usam `setUser`
- [ ] Rate limit por IP **e** por token de conversa
- [ ] Limite de mensagens por conversa, não só de criação de conversa
- [ ] Nenhum segredo, endpoint admin ou lista de clientes no bundle

### A.6 Performance
- [ ] Orçamento declarado e verificado no CI (falha o build se estourar)
- [ ] Chrome ≤ 20 KB gzip; app on-demand
- [ ] Facade com preconnect no hover
- [ ] Sem CLS: dimensões fixas, `visibility` até pronto, fonte com `font-display: swap`
- [ ] `content-visibility: auto` + `contain-intrinsic-size` na lista longa
- [ ] `fetchpriority="low"` no script
- [ ] i18n e emoji picker carregados sob demanda

### A.7 Acessibilidade
- [ ] `role="log"` na conversa
- [ ] `aria-live` no **host** quando o painel está em iframe
- [ ] Bolha `<button>` com `aria-expanded`, `aria-controls`, `aria-label` traduzido
- [ ] Foco: composer ao abrir, bolha ao fechar, `Esc` fecha
- [ ] Focus trap só quando modal
- [ ] Alvos ≥ 24×24 (WCAG 2.2 — 2.5.8)
- [ ] Contraste calculado, não presumido (4.5:1 texto, 3:1 não texto)
- [ ] `prefers-reduced-motion`
- [ ] Sem `user-scalable=0`
- [ ] Auditoria axe-core no CI + teste manual NVDA/VoiceOver

### A.8 Mobile
- [ ] `dvh` (com fallback), ou `visualViewport`
- [ ] `viewport-fit=cover` + `env(safe-area-inset-*)`
- [ ] `popstate` intercepta o botão voltar do Android
- [ ] Inputs com `font-size: 16px` (evita auto-zoom do iOS sem desligar o zoom)
- [ ] Gestos: arrastar para fechar; scroll lock correto
- [ ] Handoff WhatsApp com costura de contexto (código no `?text=`)

### A.9 i18n
- [ ] Zero string hardcoded (incluindo `title`/`aria-label`)
- [ ] `dir` no root + `dir="auto"` por mensagem
- [ ] Propriedades lógicas no CSS
- [ ] `Intl.*` para data/hora/número/lista/plural
- [ ] Fallback de locale por idioma base
- [ ] Horário de atendimento no fuso da empresa, com DST, sem default UTC silencioso

### A.10 Observabilidade
- [ ] Cliente de erro **isolado** (não o `window.Sentry` do cliente)
- [ ] `allowUrls` restrito ao nosso host
- [ ] `beforeSend` removendo conteúdo de mensagem, URL com token, e PII
- [ ] Session Replay desligado ou com máscara total
- [ ] Amostragem + rate limit de eventos por sessão
- [ ] Cruzamento servidor: loader baixado × boot recebido (detecção de instalação quebrada)
- [ ] Métricas de entrega (§15.6) num painel

---

## Anexo B — Índice de fontes

### Documentação primária (padrões e navegadores)
- MDN — `Window.postMessage()`: <https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage>
- MDN — `<iframe>` e `sandbox`: <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/iframe>
- MDN — `content-visibility`: <https://developer.mozilla.org/en-US/docs/Web/CSS/content-visibility>
- MDN — Cookies particionados (CHIPS): <https://developer.mozilla.org/en-US/docs/Web/Privacy/Guides/Third-party_cookies/Partitioned_cookies>
- MDN — Storage Access API: <https://developer.mozilla.org/en-US/docs/Web/API/Storage_Access_API>
- W3C/WAI — ARIA23 (`role=log`): <https://www.w3.org/WAI/WCAG21/Techniques/aria/ARIA23>
- W3C/WAI — exemplo funcional de chat log: <https://www.w3.org/WAI/WCAG21/working-examples/aria-role-log/chatlog.html>
- WebKit — Full Third-Party Cookie Blocking and More (ITP, cap de 7 dias): <https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/>
- Chrome Developers — Third-party facades: <https://developer.chrome.com/docs/lighthouse/performance/third-party-facades/>
- web.dev — Sandboxed iframes: <https://web.dev/articles/sandboxed-iframes>

### Documentação de fornecedores
- Intercom — instalação e stub queue: <https://developers.intercom.com/installing-intercom/docs/intercom-javascript>
- Intercom — CSP: <https://www.intercom.com/help/en/articles/3894-using-intercom-with-content-security-policy>
- Intercom — JWT no lugar de HMAC: <https://www.intercom.com/help/en/articles/10589769-authenticating-users-in-the-messenger-with-json-web-tokens-jwts>
- Intercom — verificação de identidade (propósito): <https://developers.intercom.com/installing-intercom/react-native/identity-verification>
- Zendesk — CSP: <https://developer.zendesk.com/documentation/zendesk-web-widget-sdks/sdks/web/csp/>
- Zendesk — cookbook do Web Widget (iframe, zIndex): <https://support.zendesk.com/hc/en-us/articles/10292484466330-Messaging-Web-Widget-cookbook>
- Zendesk — contraste automático: <https://support.zendesk.com/hc/en-us/articles/4408832257562-Advanced-customization-of-Web-Widget-Classic->
- Chatwoot — rate limiting: <https://developers.chatwoot.com/self-hosted/monitoring/rate-limiting>
- Botpress — embed: <https://www.botpress.com/docs/webchat/get-started/embed-in-element>
- Leadster — instalação via HTML: <https://help.leadster.com.br/article/37-instalar-o-codigo-via-html>
- Leadster — vias de ativação (WordPress, GTM, Wix, HTML): <https://help.leadster.com.br/article/36-instrucoes-para-ativar-o-chat>
- Leadster — plugin WordPress (fonte do snippet oficial): <https://wordpress.org/plugins/leadster-marketing-conversacional/>
- Sentry — filtering (`allowUrls`, `thirdPartyErrorFilterIntegration`): <https://docs.sentry.io/platforms/javascript/configuration/filtering/>
- Sentry — scrubbing de PII (`beforeSend`): <https://docs.sentry.io/platforms/javascript/data-management/sensitive-data/>

### Análise técnica de terceiros
- Ably — WebSockets vs SSE: <https://ably.com/blog/websockets-vs-sse>
- corewebvitals.io — chat widget com Core Web Vitals perfeitos: <https://www.corewebvitals.io/pagespeed/chat-widget-perfect-core-web-vitals>
- RxDB — leader election: <https://rxdb.info/leader-election.html>
- tab-election (Web Locks + BroadcastChannel): <https://github.com/dabblewriter/tab-election>
- broadcast-channel (pubkey): <https://github.com/pubkey/broadcast-channel>
- System Design Sandbox — idempotência e deduplicação: <https://www.systemdesignsandbox.com/learn/idempotency-deduplication>
- Bram.us — VirtualKeyboard API e viewport: <https://www.bram.us/2021/09/13/prevent-items-from-being-hidden-underneath-the-virtual-keyboard-by-means-of-the-virtualkeyboard-api/>
- Francisco Moretti — teclado móvel com `dvh`: <https://www.franciscomoretti.com/blog/fix-mobile-keyboard-overlap-with-visualviewport>
- HTMHell — `interactive-widget` no meta viewport: <https://www.htmhell.dev/adventcalendar/2024/4/>
- Threada — checklist WCAG 2.2 para chat widget: <https://threada.ai/blog/wcag-22-chat-widget-accessibility-checklist/>
- dev.to — CSP para scripts de terceiros: <https://dev.to/sitesecurityscore/csp-for-third-party-scripts-the-practical-cheat-sheet-for-ga-stripe-intercom-and-more-1gh8>
- techinterview.org — cookies, storage e privacidade em 2026: <https://www.techinterview.org/post/3233475403/frontend-cookies-storage-privacy-2026/>
- Medium (19whoami19) — má configuração de Intercom e impersonation: <https://19whoami19.medium.com/uncovering-intercom-misconfigurations-from-ignored-widgets-to-high-impact-vulnerabilities-26115f9481ca>
- dev.to — propriedades lógicas para RTL: <https://dev.to/web_dev-usman/stop-fighting-rtl-layouts-use-css-logical-properties-for-better-design-5g3m>
- U2L — guia wa.me: <https://u2l.ai/blog/whatsapp-click-to-chat-link>
- Cloudflare — boas práticas de rate limiting: <https://developers.cloudflare.com/waf/rate-limiting-rules/best-practices/>
- Tiledesk — mudança de licença para MIT: <https://tiledesk.com/blog/we-have-two-surprise-announcements-we-are-moving-tiledesk-open-source-license-to-mit-and-we-will-have-a-unique-codebase-from-now-onwards/>

### Artefatos públicos baixados e inspecionados em 11/08/2026
- `https://cdn.leadster.com.br/neurolead/neurolead.min.js`
- `https://client.crisp.chat/l.js` (v4.9.2, build `4ea1f89`)
- `https://widget.intercom.io/widget/<APP_ID>`
- `https://static.zdassets.com/ekr/snippet.js`
- `https://js.driftt.com/include/1/<id>.js`
- `https://cdn.botpress.cloud/webchat/v3.2/inject.js`
- `https://cdn.jsdelivr.net/npm/@typebot.io/js@0/dist/web.js`
- `https://downloads.wordpress.org/plugin/leadster-marketing-conversacional.zip`
- `https://api.github.com/repos/{chatwoot,papercups-io,chaskiq,Tiledesk,RocketChat,botpress,baptisteArno,chatscope,botman}/...`

### Arquivos do repositório citados (leitura apenas)
```
app/javascript/entrypoints/sdk.js
app/javascript/sdk/IFrameHelper.js
app/javascript/sdk/sdk.js
app/javascript/sdk/DOMHelpers.js
app/javascript/sdk/bubbleHelpers.js
app/javascript/sdk/cookieHelpers.js
app/javascript/shared/helpers/BaseActionCableConnector.js
app/javascript/shared/helpers/HTMLSanitizer.js
app/javascript/shared/helpers/MessageFormatter.js
app/javascript/widget/App.vue
app/javascript/widget/helpers/actionCable.js
app/javascript/widget/api/conversation.js
app/javascript/widget/api/endPoints.js
app/javascript/widget/composables/useAvailability.js
app/javascript/widget/store/modules/conversation/{actions,mutations,helpers}.js
app/javascript/widget/components/{ChatInputWrap,ConversationWrap,UserMessageBubble}.vue
app/javascript/widget/i18n/locale/*.json            (55 arquivos)
app/controllers/widgets_controller.rb
app/controllers/api/v1/widget/base_controller.rb
app/controllers/api/v1/widget/contacts_controller.rb
app/controllers/api/v1/widget/messages_controller.rb
app/models/channel/web_widget.rb
app/services/widget/token_service.rb
app/views/widgets/show.html.erb
app/views/widget_tests/index.html.erb
config/initializers/rack_attack.rb
public/vite/.vite/manifest.json
LICENSE, enterprise/LICENSE
```

---

## Anexo C — Perguntas em aberto

Coisas que este estudo **não** conseguiu resolver e que valem investigação dirigida:

1. **[NÃO VERIFICADO]** O CSS de 1,08 MB do widget é purge mal configurado, vazamento do
   dashboard, ou característica do fork? Comparar com uma build limpa do upstream.
2. **[NÃO VERIFICADO]** `md.validateLink` do `markdown-it` foi customizado neste fork?
   Se sim, `javascript:` pode estar liberado.
3. **[NÃO VERIFICADO]** Existe índice único em `(conversation_id, echo_id)`? Sem ele,
   `echo_id` não garante idempotência real.
4. **[NÃO VERIFICADO]** `ENABLE_RACK_ATTACK_WIDGET_API` está ligado nas VMs de produção da
   frota?
5. **[NÃO VERIFICADO]** O endpoint `GET /api/v1/widget/messages?after=` pagina? Qual o
   limite? Importa para reconexão após muitas horas.
6. **[NÃO VERIFICADO]** O `pagehide` da Leadster usa `sendBeacon`/`keepalive`? Determina se
   a nota de abandono realmente chega.
7. **[NÃO VERIFICADO]** Em que condições o bundle da Leadster dispara o pixel do Facebook —
   sempre, ou opt-in por conta?
8. **[NÃO VERIFICADO]** Comportamento real do composer sob teclado virtual em iOS/Android
   — precisa de teste em dispositivo, não análise estática.
9. **[NÃO VERIFICADO]** Impacto medido do `MutationObserver` global em INP num site com
   muita mutação de DOM.
10. **[NÃO VERIFICADO]** A exploração do `postMessage` sem validação de origem — descrita
    por leitura de código, não reproduzida. Vale um PoC controlado antes de dimensionar a
    correção.

---

*Fim do documento. Nenhum arquivo de código foi modificado nesta task.*
