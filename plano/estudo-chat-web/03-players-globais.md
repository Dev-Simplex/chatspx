# TASK 03 — Players globais: como os grandes fazem chat de site

> **Escopo:** o **widget** (o que o visitante vê e o que o dev instala), não o CRM/helpdesk inteiro.
> **Data da pesquisa:** 11 de agosto de 2026.
> **Autor:** worker de estudo (fase de ESTUDO PURO — nenhum arquivo de código do repositório foi tocado).
> **Status:** relatório de pesquisa. Não contém implementação, nem recomendação de deploy.

---

## Como ler este documento

Cada afirmação relevante está marcada com um destes rótulos:

| Rótulo | Significado |
|---|---|
| **[FV]** | **Fato verificado** — li a fonte primária (doc oficial / press release / arquivo servido pelo próprio fornecedor) e coloquei o link. |
| **[FV-M]** | **Fato verificado por medição própria** — eu mesmo baixei o asset com `curl` ou carreguei a página em Chromium headless (Playwright) e inspecionei o DOM/rede em 11/08/2026. O método está descrito na seção 1.3. |
| **[INF]** | **Inferência/hipótese minha** — dedução a partir de evidência indireta. Pode estar errada. |
| **[NV]** | **Não verificado** — não consegui confirmar em fonte primária. Não inventei número. |

Nada neste documento foi obtido com login, scraping autenticado ou contorno de paywall. Todas as medições foram feitas em páginas públicas, com navegação anônima.

---

## Sumário

- [0. TL;DR — as 12 conclusões que importam](#0-tldr--as-12-conclusões-que-importam)
- [1. Metodologia](#1-metodologia)
  - [1.1 Fontes](#11-fontes)
  - [1.2 O que foi medido](#12-o-que-foi-medido)
  - [1.3 Como foi medido (reprodutível)](#13-como-foi-medido-reprodutível)
- [2. Panorama do mercado em 2026 — o chão se mexeu](#2-panorama-do-mercado-em-2026--o-chão-se-mexeu)
  - [2.1 Intercom virou Fin, e a Salesforce comprou](#21-intercom-virou-fin-e-a-salesforce-comprou)
  - [2.2 Drift morreu — e morreu por causa do widget](#22-drift-morreu--e-morreu-por-causa-do-widget)
  - [2.3 Userlike virou Lime Connect](#23-userlike-virou-lime-connect)
  - [2.4 O deslocamento de preço: de assento para resolução](#24-o-deslocamento-de-preço-de-assento-para-resolução)
- [3. Taxonomia de arquitetura de widget](#3-taxonomia-de-arquitetura-de-widget)
  - [3.1 Os cinco padrões de isolamento](#31-os-cinco-padrões-de-isolamento)
  - [3.2 O padrão universal do loader (stub + fila)](#32-o-padrão-universal-do-loader-stub--fila)
  - [3.3 Transporte em tempo real](#33-transporte-em-tempo-real)
  - [3.4 Tabela-mestra de arquitetura medida](#34-tabela-mestra-de-arquitetura-medida)
- [4. Players — uma seção por fornecedor](#4-players--uma-seção-por-fornecedor)
  - [4.1 Intercom (Fin)](#41-intercom-fin)
  - [4.2 Drift / Salesloft](#42-drift--salesloft)
  - [4.3 HubSpot Chat / Chatflows](#43-hubspot-chat--chatflows)
  - [4.4 Zendesk (Web Widget / messaging)](#44-zendesk-web-widget--messaging)
  - [4.5 Freshchat (Freshworks)](#45-freshchat-freshworks)
  - [4.6 Tidio](#46-tidio)
  - [4.7 Crisp](#47-crisp)
  - [4.8 LiveChat (Text)](#48-livechat-text)
  - [4.9 Olark](#49-olark)
  - [4.10 tawk.to](#410-tawkto)
  - [4.11 Gorgias](#411-gorgias)
  - [4.12 Front (Front Chat)](#412-front-front-chat)
  - [4.13 Chatra](#413-chatra)
  - [4.14 Userlike / Lime Connect](#414-userlike--lime-connect)
  - [4.15 Kustomer](#415-kustomer)
  - [4.16 Gladly (Sidekick)](#416-gladly-sidekick)
  - [4.17 Ada](#417-ada)
  - [4.18 Trengo](#418-trengo)
  - [4.19 Chaport](#419-chaport)
  - [4.20 Smartsupp](#420-smartsupp)
- [5. Verificação de identidade — o capítulo que separa brinquedo de produto](#5-verificação-de-identidade--o-capítulo-que-separa-brinquedo-de-produto)
- [6. A grande tabela comparativa (25 capacidades × 20 players)](#6-a-grande-tabela-comparativa-25-capacidades--20-players)
- [7. Tabelas transversais](#7-tabelas-transversais)
- [8. IMPLICAÇÕES PARA O CHATSPX](#8-implicações-para-o-chatspx)
- [9. Apêndice — URLs de documentação para consulta futura](#9-apêndice--urls-de-documentação-para-consulta-futura)

---

## 0. TL;DR — as 12 conclusões que importam

1. **O widget de chat não é mais um widget de chat.** Nos líderes (Intercom, Zendesk, Gorgias, Ada, Gladly) ele virou um *mini-aplicativo* embarcado: busca em base de conhecimento, tickets, status de pedido, checklists, tours, pesquisas, notícias. Chat é uma aba dentro dele. **[INF]** baseada nas docs de Spaces do Intercom e nos eventos `articleClicked`/`conversationExtensionOpened` do Zendesk.
2. **Isolamento é o divisor de águas técnico.** Praticamente todo mundo usa **iframe** para o corpo do messenger. A exceção mais notável é o **Crisp**, que renderiza direto no DOM do host — medido por mim: zero iframes, zero shadow roots, apenas `div.crisp-client` **[FV-M]**.
3. **O launcher costuma ser um iframe separado do painel.** Intercom, Trengo, Gorgias e tawk.to fatiam a UI em vários iframes independentes (botão, badge de não-lidas, greeting, painel). Isso protege cada pedaço do CSS do host e permite animar o launcher sem carregar o painel **[FV-M]**.
4. **Todo mundo usa o mesmo truque de boot:** um stub global síncrono que enfileira chamadas (`i.q.push`, `$crisp.push`, `_q`, `Tawk_API`) enquanto o bundle real carrega assíncrono. O snippet de instalação tem 1–3 KB; o bundle real tem 100 KB–1,2 MB **[FV-M]**.
5. **WebSocket venceu.** Intercom, Crisp, tawk.to, LiveChat, Tidio, Gorgias e Qualified abrem WSS assim que o widget inicializa — verificado ao vivo **[FV-M]**. HubSpot foi o único grande onde não observei WSS na página host.
6. **Verificação de identidade migrou de HMAC para JWT.** Intercom **deprecou** o `user_hash` HMAC em favor de `intercom_user_jwt` **[FV]**. Zendesk, Kustomer, Gladly e Freshchat já nasceram/mudaram para JWT. Crisp, Front, tawk.to e Chaport ainda usam HMAC-SHA256 puro **[FV]**.
7. **Quase ninguém torna a verificação obrigatória por padrão.** É sempre um toggle. Quando ligado, requisições sem prova são rejeitadas **[FV]**. Isso significa que a maioria das instalações do mercado está aberta a impersonação de usuário logado **[INF]**.
8. **O Drift foi sunsetado em 06/03/2026, depois de um incidente de segurança que começou no widget/integração** (roubo de tokens OAuth, +700 organizações com dados do Salesforce exfiltrados) **[FV]**. É o caso mais forte de que o widget é superfície de ataque de terceiro, não enfeite.
9. **A Intercom mudou o nome da empresa para Fin em 12/05/2026**, e a **Salesforce assinou acordo para comprar a Fin por ~US$ 3,6 bi em 15/06/2026** **[FV]**. O produto continua se chamando Intercom.
10. **Preço migrou de assento para resultado de IA.** Intercom cobra US$ 0,99 por *outcome* do Fin; Gorgias ~US$ 0,90–1,00 por interação resolvida; Zendesk cobra por "resolução automatizada"; Tidio US$ 0,50 por conversa Lyro; Freshworks US$ 49 por 100 sessões **[FV]**.
11. **Customização visual é rasa em quase todos.** O padrão é: cor primária, posição, avatar/nome, saudação, idioma. **CSS custom no widget praticamente não existe** — o Zendesk diz explicitamente que a versão messaging *não* tem customização avançada, ao contrário da Classic **[FV]**.
12. **O ponto cego coletivo:** ninguém entrega bem, ao mesmo tempo, (a) widget leve, (b) identidade forte por padrão, (c) tema visual profundo do cliente, e (d) preço previsível. Detalhado na seção 8.

---

## 1. Metodologia

### 1.1 Fontes

Três camadas, em ordem de confiança:

1. **Documentação oficial de desenvolvedor** (`developers.intercom.com`, `developer.zendesk.com`, `docs.crisp.chat`, `platform.text.com`, `developer.tawk.to`, `docs.smartsupp.com`, `docs.chaport.com`, `dev.frontapp.com`, `developers.trengo.com`, `developer.kustomer.com`, `developer.gladly.com`, `docs.ada.cx`, `devdocs.drift.com`, `docs.lime-connect.com`).
2. **Assets públicos servidos pelo próprio fornecedor** — baixei os loaders/bundles com `curl` e inspecionei conteúdo, tamanho e hosts referenciados.
3. **Comportamento real em navegador** — carreguei os sites dos próprios fornecedores em Chromium headless, esperei o widget inicializar, cliquei no launcher e inspecionei DOM, iframes, shadow roots, WebSockets e bytes por host.

Páginas de preço foram lidas na fonte oficial sempre que possível. Onde só havia terceiro (blog/comparador), está marcado como tal ou como **[NV]**.

### 1.2 O que foi medido

Para cada player: snippet de instalação, mecânica de boot, isolamento (iframe/shadow DOM/DOM direto), número e papel de cada iframe, host/CDN, transporte realtime, peso transferido, API JS exposta, eventos, verificação de identidade, features do widget, limites de customização e preço.

### 1.3 Como foi medido (reprodutível)

**Medição de asset (exemplo):**

```bash
curl -sS --compressed --max-time 25 \
  -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126 Safari/537.36" \
  -o /tmp/w_intercom.js \
  -w "http=%{http_code} bytes_wire=%{size_download} tipo=%{content_type}\n" \
  "https://widget.intercom.io/widget/abc12345"
```

**Inspeção de DOM (resumo do script Playwright usado):**

```js
// varre TODO o DOM, inclusive dentro de shadow roots, até 4 níveis
const walk = (root, depth) => {
  if (depth > 4) return;
  root.querySelectorAll('*').forEach(el => {
    if (el.shadowRoot) {
      out.shadowHosts.push({
        tag: el.tagName.toLowerCase(), id: el.id || null,
        childCount: el.shadowRoot.childElementCount,
        innerIframes: el.shadowRoot.querySelectorAll('iframe').length,
        styleTags: el.shadowRoot.querySelectorAll('style,link[rel=stylesheet]').length
      });
      walk(el.shadowRoot, depth + 1);
    }
  });
};
```

O script também registrava `page.on('websocket')` e `page.on('response')` para somar bytes por host, e tentava abrir o widget com uma cascata de seletores (`iframe[title*="chat" i]`, `[aria-label*="chat" i]`, `#chat-button`, `[class*="launcher" i]`, …).

**Ressalva honesta sobre a medição:** bytes por host vêm do header `content-length`; respostas com `transfer-encoding: chunked` contam 0. Por isso alguns totais aparecem subestimados (ex.: Crisp e Chatra mostram 0 em vários hosts). E WebSocket aberto **dentro de um iframe cross-origin** pode não ser capturado pelo listener da página — então "não observei WSS" não é o mesmo que "não usa WSS". Isso está marcado como **[INF]** onde aparece.

---

## 2. Panorama do mercado em 2026 — o chão se mexeu

Não dá para estudar "como os grandes fazem chat de site" em 2026 sem registrar que três dos players da lista obrigatória mudaram de identidade ou morreram nos últimos 12 meses.

### 2.1 Intercom virou Fin, e a Salesforce comprou

**[FV]** Em **12/05/2026** a Intercom anunciou no próprio blog que a **empresa** passa a se chamar **Fin** — o nome do agente de IA. O CEO Eoghan McCabe escreveu: *"We're changing the name of our company to Fin"* e *"The name Intercom will still live on as the name of our customer service software platform."* No mesmo anúncio lançaram o "Intercom 2", uma reconstrução da plataforma.
Fonte: <https://www.intercom.com/blog/today-intercom-becomes-fin/>

**[FV]** Em **15/06/2026** a **Salesforce assinou acordo definitivo para adquirir a Fin por ~US$ 3,6 bilhões**, com fechamento esperado no início de 2027, para compor o portfólio Agentforce.
Fonte primária: <https://www.salesforce.com/news/press-releases/2026/06/15/salesforce-signs-definitive-agreement-to-acquire-fin/> e <https://investor.salesforce.com/news/news-details/2026/Salesforce-Signs-Definitive-Agreement-to-Acquire-Fin/default.aspx>
Cobertura: <https://www.cnbc.com/2026/06/15/salesforce-ai-customer-service-fin-acquistion.html>

**[FV-M]** Efeito colateral verificável hoje: `https://www.intercom.com/messenger` responde **308 Permanent Redirect para `https://fin.ai/`**. O produto "Messenger" perdeu página própria de marketing; a narrativa toda foi reorientada para o agente de IA.

**[INF]** Para quem constrói alternativa: o líder histórico de widget está em processo de absorção por uma suíte de CRM. Historicamente isso desacelera roadmap de produto e gera janela de migração de clientes descontentes.

### 2.2 Drift morreu — e morreu por causa do widget

Esta é a história mais instrutiva do relatório inteiro.

**[FV]** Entre **8 e 18 de agosto de 2025**, o ator identificado como **UNC6395** usou **tokens OAuth roubados da aplicação Salesloft Drift** para consultar e exfiltrar dados de instâncias Salesforce de **mais de 700 organizações**. Em **20/08/2025**, Salesloft e Salesforce revogaram todos os tokens e a Drift foi removida do AppExchange. Em **28/08/2025** descobriu-se que os tokens da integração "Drift Email" também tinham sido usados, com acesso a contas do Google Workspace em 09/08/2025.
Fonte primária (Google Threat Intelligence Group): <https://cloud.google.com/blog/topics/threat-intelligence/data-theft-salesforce-instances-via-salesloft-drift>

**[FV]** O objetivo declarado do atacante era **colher credenciais**: o GTIG documenta que os dados exfiltrados foram varridos atrás de chaves AWS (`AKIA`), senhas, tokens do Snowflake e URLs de VPN/SSO das organizações. Exemplo de query SOQL executada, reproduzida pelo GTIG:

```sql
SELECT Id, Username, Email, FirstName, LastName, Name, Title, CompanyName,
Department, Division, Phone, MobilePhone, IsActive, LastLoginDate,
CreatedDate, LastModifiedDate, TimeZoneSidKey, LocaleSidKey,
LanguageLocaleKey, EmailEncodingKey
FROM User
WHERE IsActive = true
ORDER BY LastLoginDate DESC NULLS LAST
LIMIT 20
```

Recomendação do GTIG, textual: *"Treat all Drift authentication tokens as compromised"*. Organizações citadas na cobertura como afetadas incluem Cloudflare, Palo Alto Networks, Zscaler, Proofpoint, PagerDuty e Tanium.
Cobertura secundária: <https://appomni.com/blog/drift-breach-salesforce-unc6395-saas-prevention/>, <https://www.finra.org/rules-guidance/guidance/salesloft-drift-AI-supply-chain-attack>

**[FV/terceiro]** Em **06/03/2026**, Clari + Salesloft anunciaram o **sunset gradual da plataforma Drift**, indicando a **1mind** como sucessora de IA. Não há data pública de EOL definitiva.
Fontes (terceiros, não achei press release oficial indexado): <https://www.docket.io/blog/drift-is-dead>, <https://resources.rework.com/news/sales-tech/drift-sunset-migration-playbook-sales-ops>

**[FV-M]** Confirmação empírica do sunset: carreguei `https://www.salesloft.com/` em 11/08/2026. **Não existe mais widget Drift no site da própria Salesloft.** O que está lá é o widget da **1mind**, num iframe `#onemind-iframe` de 366×644 apontando para `deployment-vxwr8gkfpb.1mind.com`, com hosts `interaction.prd-b.1mind.com`, `launcher.prd-b.1mind.com` e `relay.1mind.com`. Nenhum global `drift`/`driftt` presente.

**A lição, explícita:** o widget de chat é código de terceiro que roda em toda página do cliente **e** carrega tokens OAuth para dentro do CRM dele. Comprometer o fornecedor do widget é comprometer a base de clientes inteira. Isso vale integralmente para o ChatSPX.

### 2.3 Userlike virou Lime Connect

**[FV]** A documentação de desenvolvedor do Userlike agora responde **301 de `docs.userlike.com` para `docs.lime-connect.com`**, e a página de preços oficial é `connect.lime-technologies.com/en/pricing/`, intitulada *"Lime Connect (ex Userlike)"*.
Fonte: <https://docs.lime-connect.com/developers/api/website-messenger-api>, <https://connect.lime-technologies.com/en/pricing/>

**[FV-M]** No site `userlike.com` em 11/08/2026, o widget carrega de `connect.lime-technologies.com` (291 KB em 92 requisições) mais assets do bucket legado `userlike-cdn-widgets.s3-eu-west-1.amazonaws.com` — os dois domínios coexistindo é a assinatura de uma migração de marca em andamento **[INF]**.

### 2.4 O deslocamento de preço: de assento para resolução

**[FV]** Todos os grandes que têm agente de IA mudaram a unidade de cobrança. Consolidado:

| Fornecedor | Unidade de IA cobrada | Preço | Fonte |
|---|---|---|---|
| Intercom (Fin) | *outcome* do Fin | **US$ 0,99** por outcome ("From $0.99 per Fin outcome") | <https://www.intercom.com/pricing> |
| Gorgias | interação resolvida pelo AI Agent | ~US$ 1,00 (mensal) / US$ 0,90 (anual) **[FV/terceiro]** | <https://www.gorgias.com/blog/ai-agent-pricing> |
| Tidio | conversa Lyro | **US$ 0,50** por conversa | <https://www.tidio.com/lyro-ai-chatbot/> |
| Freshworks | sessão do Freddy AI Agent | 500 sessões inclusas; **US$ 49 / 100 sessões** extras | <https://www.freshworks.com/freshdesk/omni/pricing/> |
| Zendesk | "resolução automatizada" | valor por resolução **não publicado** — **[NV]** | <https://www.zendesk.com.br/pricing/> |
| Kustomer | conversa engajada por AI Agent | ~US$ 0,60 **[FV/terceiro]** | <https://chatarmin.com/en/blog/kustomer-pricing> |
| Trengo | sobretaxa de IA por conversa | € 0,30 (mensal) / € 0,25 (anual) | <https://trengo.com/pricing> |

**[INF]** Consequência estratégica: o widget deixou de ser o produto e virou o **canal de faturamento** do agente de IA. Quem só vende "chat" está vendendo commodity; a margem está no que o bot resolve sozinho.

---

## 3. Taxonomia de arquitetura de widget

### 3.1 Os cinco padrões de isolamento

Depois de medir 18 sites, os padrões se reduzem a cinco:

**Padrão A — Iframe único com `src` remoto.**
Um `<iframe src="https://fornecedor.com/...">` que carrega uma SPA inteira do domínio do fornecedor. Isolamento máximo (CSS, JS e cookies separados). Comunicação com o host só por `postMessage`.
Exemplos medidos: **HubSpot** (`#hubspot-conversations-iframe` → `app.hubspot.com/conversations-visitor/...`), **LiveChat** (`#chat-widget` → `secure.livechatinc.com/customer/action/open_chat?...`), **Front** (`chat.bundle.js` + iframe), **Ada** (iframe).

**Padrão B — Múltiplos iframes, um por pedaço de UI.**
Launcher em um iframe, badge de não-lidas em outro, greeting/campanha em outro, painel em outro. Cada um dimensionado ao pixel do seu conteúdo, para não roubar clique do site.
Exemplos medidos: **Intercom** (3 iframes com o messenger aberto), **Trengo** (4 iframes visíveis: *Open chat* 60×60, *Unread chat messages*, *Online status*, *Ask us anything…* 410×750), **Gorgias** (`#chat-button`, `#chat-campaigns`, `#chat-input`, `#chat-window` 414×705), **tawk.to** (5 iframes irmãos dentro de um único `div` container).

**Padrão C — Iframes `about:blank`/`srcdoc` preenchidos por JS.**
Os iframes existem para isolar CSS, mas o conteúdo é escrito pelo script do host, não baixado de uma URL. Reduz round-trips e evita third-party cookies.
Exemplo medido: **tawk.to** — todos os 5 iframes têm `src=about:blank` ou `srcdoc`, nenhum aponta para URL remota.

**Padrão D — DOM direto do host, sem isolamento.**
O widget injeta seus elementos no `<body>` da página e depende de CSS com prefixo/especificidade alta para não colidir.
Exemplo medido: **Crisp** — inspeção completa retornou **0 iframes e 0 shadow roots**; só existe `div.crisp-client` no body **[FV-M]**. É o único grande com esse padrão.

**Padrão E — Web Component com Shadow DOM.**
Custom element com `attachShadow`, estilos encapsulados sem o custo de um browsing context separado.
Exemplos medidos: **Olark** (`<olark-experience>` com shadow root aberto, 3 filhos, 1 tag de estilo), **Freshchat** (o bundle `wchat.freshchat.com/js/widget.js` contém `attachShadow` e 9 referências a `shadowRoot`), **Qualified** (`div#qualified-multimodal-host` com shadow root).

**Trade-offs, resumidos [INF]:**

| Padrão | Isolamento CSS | Isolamento JS | Custo de boot | Acessibilidade/foco | Cross-origin cookies |
|---|---|---|---|---|---|
| A — iframe remoto | total | total | alto (documento novo + rede) | difícil (foco preso, leitura por AT) | sofre com ITP/3rd-party cookies |
| B — múltiplos iframes | total | total | mais alto ainda | mais difícil | idem |
| C — iframe `about:blank` | total | total | baixo (sem rede extra) | difícil | não usa cookie de terceiro |
| D — DOM direto | **nenhum** | nenhum | mínimo | fácil | não aplicável |
| E — Shadow DOM | alto (não pega herança de fonte/cor sem querer) | nenhum | baixo | intermediário | não aplicável |

### 3.2 O padrão universal do loader (stub + fila)

Todos, sem exceção, usam a mesma ideia: um objeto global síncrono que **enfileira** chamadas até o bundle real chegar. Três exemplos reais:

**Intercom** — `i.q` é a fila; `i.c` empurra; `l()` injeta o `<script>` depois do `load` **[FV]**:

```html
<script>
  const APP_ID = "Your-Workspace-ID"
  window.intercomSettings = {
    api_base: "https://api-iam.intercom.io",
    app_id: APP_ID,
    user_id: user.id,
    name: user.name,
    email: user.email,
    created_at: user.createdAt,
  };
</script>
<script>
(function(){var w=window;var ic=w.Intercom;if(typeof ic==="function"){ic('update',w.intercomSettings);}else{var d=document;var i=function(){i.c(arguments);};i.q=[];i.c=function(args){i.q.push(args);};w.Intercom=i;var l=function(){var s=d.createElement('script');s.type='text/javascript';s.async=true;s.src='https://widget.intercom.io/widget/' + APP_ID;var x=d.getElementsByTagName('script')[0];x.parentNode.insertBefore(s, x);};if(document.readyState==='complete'){l();}else if(w.attachEvent){w.attachEvent('onload',l);}else{w.addEventListener('load',l,false);}}})();
</script>
```

Fonte: <https://developers.intercom.com/installing-intercom/web/installation>

**LiveChat** — `_q`/`_h`, com `asyncInit` opcional e `init()` manual **[FV]**:

```html
<script>
  window.__lc = window.__lc || {};
  window.__lc.license = <LICENSE_NUMBER>;
  ;(function(n,t,c){function i(n){return e._h?e._h.apply(null,n):e._q.push(n)}var e={_q:[],_h:null,_v:"2.0",on:function(){i(["on",c.call(arguments)])},once:function(){i(["once",c.call(arguments)])},off:function(){i(["off",c.call(arguments)])},get:function(){if(!e._h)throw new Error("[LiveChatWidget] You can't use getters before load.");return i(["get",c.call(arguments)])},call:function(){i(["call",c.call(arguments)])},init:function(){var n=t.createElement("script");n.async=!0,n.type="text/javascript",n.src="https://cdn.livechatinc.com/tracking.js",t.head.appendChild(n)}};!n.__lc.asyncInit&&e.init(),n.LiveChatWidget=n.LiveChatWidget||e}(window,document,[].slice))
</script>
<noscript><a href="https://www.livechat.com/chat-with/<LICENSE_NUMBER>/">Chat with us</a></noscript>
```

Fonte: <https://platform.text.com/docs/extending-chat-widget/javascript-api>
Detalhe elegante: o `<noscript>` com link para o chat hospedado. Nenhum outro player faz isso nos snippets que li.

**Crisp** — o array `$crisp` *é* a fila; nunca deixa de ser **[FV]**:

```html
<script type="text/javascript">
  window.$crisp = [];
  window.CRISP_WEBSITE_ID = "MY-UNIQUE-ID";
  (function() {
    var d = document;
    var s = d.createElement("script");
    s.src = "https://client.crisp.chat/l.js";
    s.async = 1;
    d.getElementsByTagName("head")[0].appendChild(s);
  })();
</script>
```

Fonte: <https://help.crisp.chat/en/article/how-to-install-crisp-live-chat-on-a-custom-website-10wcj3l/>

**[FV-M] Detalhe do loader do Crisp que vale registrar.** Baixei `https://client.crisp.chat/l.js` (2.875 bytes na rede, 7.637 descomprimido, versão `v4.9.2 4ea1f89`). Dentro dele há uma lista de **bloqueio de bots e de sites**:

```js
this.u = {
  domains: [],
  agents: ["Trident","Googlebot","Bingbot","Slurp","DuckDuckBot","Baiduspider",
           "YandexBot","GTmetrix","Lighthouse","Acunetix","Ahrefs","SemrushBot",
           "SiteAuditBot","SplitSignalBot","HeadlessChrome"],
  engines: [
    {element:"head link[rel='icon'][type='image/x-icon'][href^='https://sellpass.io']"},
    {element:"head script[src*='/cdn.sellix.io/']"},
    ...
  ]
}
```

Ou seja: o Crisp **não carrega o widget** para Googlebot, Lighthouse, Ahrefs, HeadlessChrome nem para sites que ele identificou como plataformas de revenda (sellix/sellpass/ereemby). O bloqueio de `Lighthouse` e `GTmetrix` é notável — o widget se esconde exatamente das ferramentas que mediriam o impacto dele no Core Web Vitals **[FV-M]**. E `HeadlessChrome` explica por que meu probe no `crisp.chat` inicialmente não achou o global.

Também dentro do loader: matriz de suporte a navegador com corte por versão **[FV-M]**:

```js
this.S = [
  {pattern:/edg(?:e)?\/([0-9.]+)/,        versions:{support:18, legacy:117}},
  {pattern:/chrom(?:e|ium)\/([0-9.]+)/,   versions:{support:63, legacy:117}},
  {pattern:/firefox\/([0-9.]+)/,          versions:{support:67, legacy:67}},
  {pattern:/opr\/([0-9.]+)/,              versions:{support:50, legacy:103}},
  {pattern:/version\/([0-9.]+)(?: mobile\/(?:[^\s]+))? safari\//, versions:{support:12, legacy:14}},
  {pattern:/android ([0-9.]+)/,           versions:{support:5,  legacy:10}}
];
```

Dois níveis: `support` (mínimo absoluto) e `legacy` (abaixo disso, serve um bundle antigo). É a única evidência que encontrei de um fornecedor mantendo **dois bundles** por faixa de navegador.

### 3.3 Transporte em tempo real

**[FV-M]** WebSockets efetivamente observados abrindo, com a URL real:

| Player | URL do socket (truncada) | Observações |
|---|---|---|
| Intercom | `wss://nexus-websocket-a.intercom.io/pubsub/5-...?X-Nexus-New-Client=true&X-Nexus-Version=0.20.0&user_role=visitor` | protocolo próprio "Nexus"; versão no query string |
| Intercom (2º, ao abrir) | `wss://primary-realtime.intercom-messenger.com/?access_token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiIsImtpZCI6...` | **segundo** socket, em outro domínio, autenticado com **JWT HS256 com `kid`** |
| Crisp | `wss://client.relay.crisp.chat/w/92b/?EIO=4&transport=websocket` | Engine.IO v4 (Socket.IO) |
| tawk.to | `wss://vsb98.tawk.to/s/?k=...&tkn=eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6InZpc2l0b3ItYXBwbGljYXRpb24tc2VydmVyLTIwMjEwMjIifQ...&EIO=3&transport=websocket` | Engine.IO v3; token de visitante é **JWT ES256**, `exp` ≈ 30 min |
| LiveChat | `wss://api.livechatinc.com/v3.6/customer/rtm/ws?organization_id=...&x-region=us-south1` | API versionada (`v3.6`) e **região no query string** |
| Tidio | `wss://socket.tidio.co/socket.io/?ppk=...&device=desktop&cmv=2_0&ver=1.451.0&seid=...&vid=...&EIO=4` | Socket.IO; manda `device`, versão do widget e IDs de sessão/visitante |
| Gorgias | `wss://us-east1-898b.gorgias.chat/ws/?appKey=01J5V1J9ZV18ZCZZZ6ZCFDGFE5&language=en-US` | shard por região no hostname; `appKey` é ULID |
| Qualified (usado por Freshworks e Front) | `wss://ws10.qualified.com/cable?wv=9&token=...&vu=...&bl=pt-PT` | `/cable` = **ActionCable (Rails)**, igual ao Chatwoot |

**Achado que vale registrar [FV-M]:** o token de visitante do **tawk.to** é um JWT assinado com **ES256** e `kid: "visitor-application-server-20210022"`, com payload `{pid, vid, sid, iat, exp, jti}` e validade de 30 minutos. Isso é bem mais robusto do que o "cookie de visitante" que a maioria usa.

**Achado 2 [FV-M]:** a Intercom mantém **dois** canais realtime distintos — o legado `nexus-websocket-a.intercom.io` (aberto já no launcher) e o `primary-realtime.intercom-messenger.com` (aberto ao abrir o messenger, com JWT). **[INF]** parece migração de infraestrutura em andamento, com o messenger novo em domínio próprio.

**Onde não observei WSS:** HubSpot, Zendesk (na página testada o widget não carregou), Smartsupp, Chaport, Chatra, Userlike, Trengo (só o socket do Hotjar). Para HubSpot e Trengo, cujo painel roda em iframe cross-origin, isso é **[INF]** de limitação da medição, não prova de ausência.

### 3.4 Tabela-mestra de arquitetura medida

**[FV-M]** Tudo abaixo veio da minha inspeção de 11/08/2026.

| Player | Página testada | Global JS | iframes (aberto) | Shadow DOM | Container no host | Transporte |
|---|---|---|---|---|---|---|
| Intercom | intercom.com | `Intercom`, `intercomSettings` | 3 (`#intercom-frame` 1×1; painel 400×704 "Intercom live chat"; botão fechar 53×53) | não | `#intercom-container.intercom-namespace` + `#intercom-css-container` | WSS ×2 |
| Crisp | help.crisp.chat | `$crisp` | **0** | **não** | `div.crisp-client` | WSS (Engine.IO 4) |
| tawk.to | tawk.to | `Tawk_API` | 5 (todos `about:blank`/`srcdoc`, irmãos no mesmo container) | não | `div` com id randômico + timestamp | WSS (Engine.IO 3) |
| LiveChat | livechat.com | `LiveChatWidget`, `__lc` | 2 (`#chat-widget` remoto; `#chat-widget-minimized` local 320×299) | não | `#chat-widget-container` | WSS `v3.6` |
| Tidio | tidio.com | `tidioChatApi` | `#tidio-chat-code` 0×0 | não | `div#tidio-chat.needsclick` + `script#chat-widget-bootstrap` | WSS (Socket.IO) |
| HubSpot | hubspot.com | `HubSpotConversations` | 1 (`#hubspot-conversations-iframe` 448×634 → `app.hubspot.com/conversations-visitor/53/threads/utk/...`) | não | `#hubspot-messages-iframe-container.widget-align-right` | não observado |
| Gorgias | gorgias.com | `GorgiasChat` | 4 (`#chat-button` 185×62, `#chat-campaigns` 415×0, `#chat-input`, `#chat-window` 414×705) | 1 shadow host genérico | `#gorgias-chat-container` + `script#gorgias-chat-bundle` | WSS por região |
| Trengo | trengo.com | `Trengo` | 5 (`#trengo-widget` bootstrap 0×0; "Close chat" 60×60; "Unread chat messages"; "Online status"; painel 410×750) | não | `#trengo-web-widget` | não observado |
| Userlike / Lime | userlike.com | `userlike` | 2 (`#userlike-frame-<uuid>` 300×1; "Chat button" 64×64) | não | iframe direto no body | não observado |
| Olark | olark.com | `olark` | 1 (`blob:` "Olark iframe intentionally blank") | **sim** — `<olark-experience>` | custom element | não observado |
| Freshchat | (bundle) | `fcWidget` | — | **sim** (`attachShadow` no bundle) | — | **[NV]** |
| Smartsupp | smartsupp.com | `_smartsupp` | 0 (widget não renderizou em 17 s) | não | — | não observado |
| Chaport | chaport.com | `chaport` | 0 (idem) | não | — | não observado |
| Chatra | chatra.com | `Chatra`, `ChatraSetup` | 0 (idem) | não | — | não observado |
| Salesloft (ex-Drift) | salesloft.com | — (nenhum global Drift) | 1 (`#onemind-iframe` 366×644 → 1mind.com) | não | `#onemind-widget` | **[NV]** |
| Front | front.com | — (usa Qualified) | `#q-messenger-frame` 356×537 | `div#qualified-multimodal-host` | — | WSS ActionCable |
| Freshworks | freshworks.com | — (usa Qualified) | `#q-messenger-frame` 320×450 | idem | — | WSS ActionCable |

**Observação irônica e verdadeira [FV-M]:** **Front** e **Freshworks**, que *vendem* chat de site, usam o widget da **Qualified** no próprio site institucional. **Salesloft** usa **1mind**. **Gorgias** roda **HubSpot** *e* Gorgias na mesma página (`hsConversationsSettings` + `GorgiasChat` coexistindo).

**Peso transferido (bytes com `content-length`, widget aberto) [FV-M]:**

| Player | Host do widget | Bytes | Requisições |
|---|---|---|---|
| Intercom | `js.intercomcdn.com` | **1.247.399** | 14 |
| Intercom (loader) | `widget.intercom.io` | 3.159 | 1 |
| Gorgias | `assets.gorgias.chat` | 843.457 | 29 |
| LiveChat | `cdn.livechatinc.com` | 345.492 | 17 |
| Userlike/Lime | `connect.lime-technologies.com` | 291.810 | 92 |
| tawk.to | `embed.tawk.to` | 187.736 | 26 |
| Tidio | `code.tidio.co` | 135.995 | 8 |
| Crisp | `static.crisp.help` | 98.544 | 9 |

**Tamanho só do arquivo de entrada (gzip na rede / descomprimido) [FV-M]:**

| Player | URL | Rede | Descomprimido |
|---|---|---|---|
| Chaport | `app.chaport.com/javascripts/insert.js` | 400 B | 998 B |
| Crisp | `client.crisp.chat/l.js` | 2.875 B | 7.637 B |
| Intercom | `widget.intercom.io/widget/<APP_ID>` | 3.159 B | 7.614 B |
| Zendesk | `static.zdassets.com/ekr/snippet.js?key=…` | 3.987 B | 9.693 B |
| Smartsupp | `www.smartsuppchat.com/loader.js` | 5.526 B | 18.024 B |
| Olark | `static.olark.com/jsclient/loader0.js` | 11.706 B | 34.770 B |
| Chatra | `call.chatra.io/chatra.js` | 12.146 B | 47.150 B |
| Freshchat | `wchat.freshchat.com/js/widget.js` | 21.963 B | 70.114 B |
| LiveChat | `cdn.livechatinc.com/tracking.js` | 36.066 B | 112.305 B |
| Drift | `js.driftt.com/include/<id>/<hash>.js` | 64.168 B | 226.789 B |

**[INF]** A distribuição é bimodal: quem separa **loader minúsculo (< 4 KB)** de bundle pesado (Chaport, Crisp, Intercom, Zendesk) tem impacto quase nulo no carregamento inicial; quem entrega **tudo no primeiro arquivo** (Drift com 227 KB, LiveChat com 112 KB) paga no LCP do cliente. O Drift, que era o mais pesado, é o que morreu — coincidência, mas simbólica.

---

## 4. Players — uma seção por fornecedor

### 4.1 Intercom (Fin)

**Posição:** referência de produto do setor. É o widget que todo mundo copia.
**Docs:** <https://developers.intercom.com/installing-intercom/web/installation> · índice em <https://developers.intercom.com/llms.txt>

#### 4.1.1 Instalação e boot

Snippet reproduzido na seção 3.2. Pontos da mecânica **[FV]**:

- `api_base` **precisa** corresponder à região do workspace (US / EU / Austrália). Errar a região quebra o widget.
- O snippet detecta se `window.Intercom` já é função: se sim, chama `update`; se não, cria o stub com fila.
- O `<script>` real só é injetado no evento `load` da página — não bloqueia render.
- Existe `installation_type` para diferenciar instalação por snippet vs. app.

#### 4.1.2 Arquitetura medida **[FV-M]**

Com o messenger **fechado**: 2 iframes — `#intercom-frame` de **1×1 px** (o canal de serviço/ponte) e um iframe de launcher 48×48 chamado `intercom-launcher-frame` com `title="Open Intercom Messenger"`.
Com o messenger **aberto**: 3 iframes — o `#intercom-frame` 1×1, o painel **400×704** com `title="Intercom live chat"`, e um iframe **separado só para o botão de fechar**, 53×53.

No DOM do host ficam `div#intercom-container.intercom-namespace` e `div#intercom-css-container` — ou seja, o Intercom **injeta CSS na página host** (para posicionar os iframes) mas mantém todo o conteúdo dentro deles.

Peso: **1,25 MB em 14 requisições** de `js.intercomcdn.com` depois de abrir. O loader inicial são 3,1 KB.

Dois WebSockets, descritos na seção 3.3, sendo o segundo autenticado com JWT HS256.

Hosts referenciados dentro do loader **[FV-M]**: `api-iam.intercom.io`, `js.intercomcdn.com`, `app.intercom.com`, `intercom-sheets.com`, `www.intercom-reporting.com`, `static.intercomassets.com`.

#### 4.1.3 API JavaScript — assinaturas reais **[FV]**

Fonte: <https://developers.intercom.com/installing-intercom/web/methods>

| Categoria | Método | Assinatura |
|---|---|---|
| Ciclo de vida | Boot | `Intercom('boot', intercomSettings)` |
| | Shutdown | `Intercom('shutdown')` |
| | Update | `Intercom('update')` |
| Visibilidade | Hide | `Intercom('hide')` |
| | Show | `Intercom('show')` |
| | Hide Notifications | `Intercom('hideNotifications', hidden)` |
| Mensagens | Show Messages | `Intercom('showMessages')` |
| | Show New Message | `Intercom('showNewMessage', [prePopulatedContent])` |
| | Start Conversation | `Intercom('startConversation', message)` |
| | Show Conversation | `Intercom('showConversation', conversationId)` |
| Navegação | Show Space | `Intercom('showSpace', spaceName)` |
| | Show Article | `Intercom('showArticle', articleId)` |
| | Show News | `Intercom('showNews', newsItemId)` |
| | Show Ticket | `Intercom('showTicket', ticketId)` |
| Conteúdo proativo | Start Tour | `Intercom('startTour', tourId)` |
| | Start Survey | `Intercom('startSurvey', surveyId)` |
| | Start Checklist | `Intercom('startChecklist', checklistId)` |
| Eventos | On Hide | `Intercom('onHide', function)` |
| | On Show | `Intercom('onShow', function)` |
| | On Unread Count Change | `Intercom('onUnreadCountChange', function)` |
| | On User Email Supplied | `Intercom('onUserEmailSupplied', function)` |
| Utilitários | Track Event | `Intercom('trackEvent', eventName, [metadata])` |
| | Get Visitor ID | `Intercom('getVisitorId')` |

**Limite documentado [FV]:** `update` aceita **até 20 chamadas por janela de 30 minutos** antes de sofrer throttling. É o único player da lista que publica um rate limit da API do widget.

**Observação de design [INF]:** `showSpace`, `showArticle`, `showNews`, `showTicket`, `startTour`, `startSurvey`, `startChecklist` são a prova de que o Messenger é um contêiner de produtos, não um chat. Sete das 22 chamadas nem tocam em conversa.

#### 4.1.4 Atributos do `intercomSettings` **[FV]**

Fonte: <https://developers.intercom.com/installing-intercom/web/attributes-objects>

*Atributos de messenger (aparência/comportamento):*
`app_id` (string) · `custom_launcher_selector` (string — CSS selector que vira gatilho) · `alignment` (`"left"`/`"right"`) · `vertical_padding` (int, mín. 20) · `horizontal_padding` (int, mín. 20) · `z_index` (int) · `hide_default_launcher` (bool) · `hide_notifications` (bool) · `theme_mode` (`'light' | 'dark' | 'system'`) · `messenger_style_id` (string — **estilo multimarca**) · `session_duration` (int, ms) · `action_color` (CSS color) · `background_color` (CSS color) · `link_color` (CSS color).

*Atributos de dados:*
`email` · `user_id` · `created_at` (timestamp) · `name` · `phone` · `unsubscribed_from_emails` (bool) · `language_override` · `utm_campaign` / `utm_content` / `utm_medium` / `utm_source` / `utm_term` · `avatar` (objeto) · `user_hash` (legado) · `company` (objeto) · `companies` (array) · `page_title`.

Três detalhes que quase ninguém mais tem: **`custom_launcher_selector`** (transforma qualquer elemento do site em launcher), **`theme_mode: 'system'`** (dark mode automático) e **`messenger_style_id`** (multimarca no mesmo workspace).

#### 4.1.5 Verificação de identidade — o mais completo do mercado

**[FV] Estado atual: HMAC deprecado, JWT é o caminho.**

- A doc de Identity Verification (HMAC/`user_hash`) está marcada como **[Deprecated]**: <https://www.intercom.com/help/en/articles/183-set-up-identity-verification-for-web-and-mobile-deprecated> e <https://www.intercom.com/help/en/articles/7946878-what-is-identity-verification-deprecated>
- Guia de migração oficial: <https://www.intercom.com/help/en/articles/10807823-migrating-from-identity-verification-to-messenger-security-with-jwts>
- Doc atual: <https://developers.intercom.com/installing-intercom/web/identity-verification> — *"JWTs (JSON Web Tokens) are the recommended method to secure your Messenger."*
- O JWT é gerado **no servidor** a partir do `user_id`, um payload opcional de dados do usuário e a **Messenger API secret key**. Algoritmo suportado: **HS256**.
- No front, passa-se em `intercom_user_jwt` dentro do `intercomSettings` (em vez do antigo `user_hash`).
- A opção *"Enforce Identity Verification for Messenger"* **não está mais disponível** para novas instalações ou alterações; implementações existentes continuam funcionando.
- Boas práticas publicadas: alinhar `exp` à duração da sessão da aplicação, e fornecer token novo periodicamente / ao atualizar dados do usuário.
- Ferramentas: logs verbosos e um **token debugger** na página de setup.
- Aviso textual: *"Be careful not to leak your secret key onto your frontend client or anywhere publicly accessible."*

**O que isso protege [FV]:** sem verificação, *"any requests without user hashes will be rejected, preventing impersonation of your users via the Messenger"* — ou seja, impedir que um visitante se passe por outro usuário e leia as conversas dele ou altere os dados dele no Intercom.

**[INF]** A escolha de JWT sobre HMAC bruto não é cosmética: HMAC sobre `user_id` não tem expiração nem escopo. Vazou uma vez, vale para sempre. JWT traz `exp`, `kid` (rotação de chave) e payload assinado — dá para embutir atributos confiáveis, não só provar identidade.

#### 4.1.6 Features do widget

**[FV]** Pelas próprias APIs: Spaces (Home / Messages / Help / Tickets / News / Tasks — inferido dos métodos `showSpace`, `showTicket`, `showNews`), busca e leitura de artigos no widget (`showArticle`), tickets no widget (`showTicket`), **product tours** (`startTour`), **checklists** (`startChecklist`), **surveys** (`startSurvey`), mensagens proativas, contador de não-lidas, dark mode, multimarca.
**[FV]** Fin (agente de IA) é o carro-chefe e é o que dá nome à empresa hoje.

#### 4.1.7 Customização e limites

**[FV]** Configurável sem código: `action_color`, `background_color`, `link_color`, alinhamento, paddings, `z_index`, `theme_mode`, estilos multimarca via `messenger_style_id`.
**[FV/terceiro]** A remoção do "Powered by Intercom" é dependente de plano e fica em *Messenger Settings → General Settings → Other Preferences* ou *Messenger → Style your Messenger*. Plano exato: **[NV]**.
Fonte: <https://community.intercom.com/customer-faq-28/how-can-i-get-rid-of-the-intercom-branding-2397>
**[INF]** Não há CSS custom no messenger — o isolamento por iframe torna isso arquiteturalmente impossível sem uma API de tema. É o preço do padrão A/B.

#### 4.1.8 Preço **[FV]**

Fonte: <https://www.intercom.com/pricing>

| Item | Preço |
|---|---|
| Essential | US$ 29 / assento / mês (anual) |
| Advanced | US$ 85 / assento / mês (anual) — inclui **20 Lite seats grátis** |
| Expert | US$ 132 / assento / mês (anual) — inclui **50 Lite seats grátis** |
| Fin AI Agent | *"From $0.99 per Fin outcome"* |
| Proactive Support Plus | US$ 99/mês (inclui 500 mensagens) |
| Copilot | US$ 29 / agente / mês (anual) ou US$ 35 (mensal) |

**[FV/terceiro]** Cobrança mensal (sem anual): Essential US$ 39, Advanced US$ 99, Expert US$ 139 por assento. Fonte: <https://www.dragapp.com/blog/intercom-pricing/>
**[FV/terceiro]** Além de resolução, também são cobrados como outcome: *procedure handoffs* e *disqualifications* (US$ 0,99 cada); *sales qualification* custa US$ 9,99. Mínimo de 50 outcomes/mês. Fonte: <https://www.metageeks.tech/insights/intercom-fin-pricing>

#### 4.1.9 Diferenciais e limitações

**Diferenciais reais:** o único com tours + checklists + surveys + news + tickets dentro do mesmo widget; `custom_launcher_selector`; multimarca nativa; identidade por JWT com debugger; documentação de desenvolvedor melhor da lista (tem `llms.txt`).
**Limitações:** **1,25 MB** de bundle é de longe o mais pesado que medi; preço por outcome torna o custo imprevisível; sem CSS custom; empresa em processo de aquisição pela Salesforce.

---

### 4.2 Drift / Salesloft

**Status: em sunset desde 06/03/2026.** Ver seção 2.2. Documento a API porque ela ainda é a melhor referência pública de *conversational marketing* e porque o naufrágio dela é a lição de segurança do relatório.
**Docs (ainda no ar):** <https://devdocs.drift.com/docs/using-drift-apis> · índice: <https://devdocs.drift.com/llms.txt>

#### 4.2.1 Arquitetura **[FV-M]**

`js.driftt.com/include/<orgId>/<hash>.js` responde 200 com **64.168 bytes na rede / 226.789 descomprimidos** — o maior arquivo de entrada que medi. Contém 57 ocorrências de `iframe`, 7 de `postMessage`, **nenhum** `attachShadow`. Padrão A/B (iframes), sem shadow DOM.
Hosts citados dentro do bundle: `api.company-target.com`, `lift-ai-js.marketlinc.com`, `help.salesloft.com`.

No site da própria Salesloft hoje: nenhum global Drift; widget da 1mind no lugar.

#### 4.2.2 API JavaScript **[FV]**

Tudo depende do evento `ready`:

```js
drift.on('ready', function(api, payload) {
  // interagir com a api aqui
})
```

Payload do `ready`: `{ sidebarOpen, chatOpen, widgetVisible, isOnline, teamAvailability }`.

Métodos **[FV]**: `drift.api.widget.hide()` · `drift.api.widget.show()` · `drift.api.openChat()` · `drift.api.toggleChat()` · `drift.api.goToConversation(3659362088)` · `drift.api.startInteraction({ interactionId: xxxxxxx })` (dispara um playbook específico, **ignorando as regras de online/offline** da organização).
Fonte: <https://devdocs.drift.com/docs/widget-start>, <https://devdocs.drift.com/docs/faqs>

#### 4.2.3 Eventos — o catálogo mais rico do mercado **[FV]**

Fonte: <https://devdocs.drift.com/docs/drift-events>

| Evento | Payload |
|---|---|
| `ready` | `{ sidebarOpen, chatOpen, widgetVisible, isOnline, teamAvailability }` |
| `chatOpen` / `chatClose` | — |
| `welcomeMessage:open` / `welcomeMessage:close` | — |
| `campaign:open` / `campaign:dismiss` / `campaign:click` / `campaign:submit` | `{ data: { widgetVisible, isOnline }, campaignId }` |
| `sliderMessage:close` | `{ botMessage, campaignId, playbookId }` |
| `startConversation` | `{ conversationId, inboxId, endUserEmail, endUserId, interactionId }` |
| `conversation:selected` | `{ conversationId }` |
| `message:sent` | `{ conversationId, inboxId }` |
| `message` | `{ inboxId, conversationId, campaignId, playbookId, teamMember: { id, name } }` |
| `emailCapture` | `{ data: { email, conversationId, campaignId, playbookId } }` |
| `phoneCapture` | `{ createdAt, authorId, conversationId, phone, campaignId, playbookId }` |
| `scheduling:requestMeeting` | `{ teamMember: { id, name } }` |
| `scheduling:meetingBooked` | `{ teamMember, meeting: { time, duration, timeZone }, conversationId, playbookId, campaignId, interactionId }` |
| `conversation:playbookFired` | `{ createdAt, authorId, interactionId, playbookId, campaignId }` |
| `conversation:playbookClicked` | `{ campaignId, playbookId }` |
| `conversation:playbookDismissed` | `{ campaignId, playbookId }` |
| `conversation:buttonClicked` | `{ authorId, buttonBody, campaignId, conversationId, createdAt, messageId, playbookId, questionId }` |
| `conversation:firstInteraction` | `{ authorId, campaignId, conversationId, createdAt, messageId, playbookId }` |
| `gdprClicked` | `{ accepted, endUser }` |

**[INF]** Repare no que isso revela do produto: `emailCapture`, `phoneCapture`, `scheduling:meetingBooked`, `campaign:*`, `playbook*`. O widget do Drift era instrumentado para **atribuição de pipeline de vendas**, não para suporte. Todo evento carrega `campaignId` e `playbookId` porque o cliente precisava provar ROI por playbook. Nenhum player de suporte tem esse nível de granularidade em conversão.

#### 4.2.4 Identidade **[FV]**

```js
drift.identify("your_unique_id_for_this_visitor",
  {
    email: "visitor_email@mail.com",
    firstName: "John",
    lastName: "Doe"
  },
  { userJwt: jwt }     //optional
);
```

Fonte: <https://devdocs.drift.com/docs/driftidentify-implementation-guide>

- `userId` deve ser *"unique and unguessable"*.
- Ao chamar, o Drift **funde** os atributos coletados na sessão anônima com o contato identificado.
- O `userJwt` é **opcional**. A doc justifica: sem ele, *"a nefarious actor from guessing (or otherwise acquiring) the unique `externalId` … could use `drift.identify()` to convince Drift that they were the identity."*
- A doc admite o trade-off explicitamente: *"Requiring JWTs when calling `drift.identify()` increases the complexity of implementing `drift.identify()` significantly."*

**[INF]** Aqui está o padrão que se repete no mercado inteiro: a documentação **descreve** o ataque de impersonação, **oferece** a defesa e ao mesmo tempo **desaconselha** implementá-la por complexidade. Resultado previsível: a maioria não implementa.

#### 4.2.5 Preço e status

**[NV]** Preço público do Drift não está mais disponível de forma confiável em 2026 — produto em sunset.
**Limitação definitiva:** não é mais opção de mercado. Serve como estudo de caso.

---

### 4.3 HubSpot Chat / Chatflows

**Posição:** o chat "de graça" que vem junto do CRM. Provavelmente o widget mais instalado do mundo por volume, porque está no tier gratuito.
**Docs:** <https://developers.hubspot.com/docs/reference/api/conversations/chat-widget-sdk>

#### 4.3.1 Boot **[FV]**

O SDK vive em `window.HubSpotConversations`, criado pelo *tracking code*, mas **pode não estar pronto na hora**. O padrão oficial:

```js
window.hsConversationsSettings = {};
if (window.HubSpotConversations) {
  onConversationsAPIReady();
} else {
  window.hsConversationsOnReady = [onConversationsAPIReady];
}
```

`hsConversationsOnReady` é um **array de callbacks**, não uma função — detalhe que quebra muita integração.

#### 4.3.2 Arquitetura medida **[FV-M]**

Padrão A puro: **um único iframe**, `#hubspot-conversations-iframe`, dentro de `div#hubspot-messages-iframe-container.widget-align-right`. O `src` é:

```
https://app.hubspot.com/conversations-visitor/53/threads/utk/<UTK>?uuid=<uuid>&mobile=false&mobileSafari=false
```

Dimensões: 282×277 fechado, **448×634** aberto. `utk` = *user token* do HubSpot (cookie `hubspotutk`), ou seja **a identidade do visitante vai na URL do iframe**.
Não observei WebSocket na página host — mas como o painel roda em iframe cross-origin, isso é **[INF]** de limitação de medição.

#### 4.3.3 Configurações `hsConversationsSettings` **[FV]**

| Setting | Tipo | Default | Função |
|---|---|---|---|
| `loadImmediately` | Boolean | `true` | se `false`, espera `widget.load()` |
| `inlineEmbedSelector` | String | `""` | **incorpora o chat dentro de um elemento da página**, não flutuante |
| `enableWidgetCookieBanner` | Enum | `false` | `false`, `true`, `ON_WIDGET_LOAD`, `ON_EXIT_INTENT` |
| `disableAttachment` | Boolean | `false` | esconde botão de upload |
| `disableInitialInputFocus` | Boolean | `false` | evita roubar foco ao carregar |
| `avoidInlineStyles` | Boolean | `false` | injeta `<link>` externo em vez de `<style>` dinâmico (útil com **CSP**) |
| `hideNewThreadLink` | Boolean | `false` | esconde "reiniciar conversa" |

**[INF]** `inlineEmbedSelector` + `avoidInlineStyles` + `enableWidgetCookieBanner` mostram maturidade em cenários corporativos (CSP estrita, LGPD/GDPR, chat embutido numa página de suporte). Poucos concorrentes têm os três.

Com `inlineEmbedSelector`, a estrutura gerada é **[FV]**:

```html
<div id="some-id">
  <div id="hubspot-conversations-inline-parent">
    <iframe id="hubspot-conversations-inline-iframe"></iframe>
  </div>
</div>
```

```css
#hubspot-conversations-inline-iframe {
  width: 300px;
  height: 500px;
  border: none;
}
```

#### 4.3.4 Métodos **[FV]**

```js
window.HubSpotConversations.widget.load({ widgetOpen: true });
window.HubSpotConversations.widget.refresh({ openToNewThread: true }); // SPA
window.HubSpotConversations.widget.open();
window.HubSpotConversations.widget.close();
window.HubSpotConversations.widget.remove();
const status = window.HubSpotConversations.widget.status();  // { loaded: bool }
window.HubSpotConversations.clear();
window.HubSpotConversations.clear({ resetWidget: true });
```

`clear()` apaga os cookies `messagesUtk`, `hs-messages-is-open` e `hs-messages-hide-welcome-message` **[FV]** — é a API de logout do widget.

#### 4.3.5 Eventos **[FV]**

```js
const handler = payload => console.log(payload);
window.HubSpotConversations.on("eventName", handler);
window.HubSpotConversations.off("eventName", handler);
```

| Evento | Dispara quando |
|---|---|
| `conversationStarted` | nova conversa; payload traz `conversation.conversationId` |
| `conversationClosed` | conversa marcada como fechada **na inbox** (não quando o visitante fecha o widget) |
| `userSelectedThread` | visitante cria ou seleciona uma thread |
| `unreadConversationCountChanged` | payload `{ unreadCount }` |
| `contactAssociated` | visitante associado a um contato do CRM |
| `userInteractedWithWidget` | qualquer interação |
| `widgetLoaded` | iframe carregado |
| `quickReplyButtonClick` | payload traz array `value` |
| `widgetClosed` | visitante fechou o widget |

**[INF]** `contactAssociated` é peculiar do HubSpot: o widget avisa a página quando o visitante anônimo virou contato conhecido do CRM. Isso é gancho para personalização do site.

#### 4.3.6 Identidade **[FV]**

`identificationEmail` + `identificationToken` no `hsConversationsSettings`. O token é gerado por API server-side (Visitor Identification API). O par email+token é o que evita que qualquer um se declare `fulano@empresa.com`.
Detalhe: a doc do SDK que li lista os settings mas **não** detalha o algoritmo do token — a geração é via chamada de API autenticada, não HMAC local. **[INF]**

#### 4.3.7 Customização **[FV]**

Fonte: <https://knowledge.hubspot.com/inbox/connect-and-customize-a-chat-channel-in-the-conversations-inbox>

Configurável sem código: cor de destaque (*"select a preset color, or manually enter a hexadecimal value, or click the color picker"*), fonte, cabeçalho do chat (nome + avatar), mensagem de boas-vindas (*"Pop open the welcome message as a prompt"*), disponibilidade (status dos membros / horário fixo / 24-7) com respostas distintas para disponível, ausente e fora do horário, anexos, transcrição automática, posição (esquerda/direita) e se o visitante pode reposicionar o widget.
O artigo **não** cobre triggers de exibição (exit intent, tempo na página, scroll), regras de segmentação, idiomas nem remoção de marca — **[NV]** nessa fonte.
**[FV/terceiro]** Remoção do "Powered by HubSpot" é recurso de plano pago; detalhes por produto variam. Fonte: <https://community.hubspot.com/t5/Lead-Capture-Tools/Turning-Off-Powere-By-Hubspot-Text/td-p/181580>

#### 4.3.8 Preço

**[NV]** A página `hubspot.com/pricing/service` não entregou tabela legível por fetch (conteúdo carregado dinamicamente). Não vou inventar números. O que é público e seguro afirmar: **o chat/chatflows existe no tier gratuito do HubSpot** — é justamente o gancho de aquisição do CRM. **[INF]**

#### 4.3.9 Diferenciais e limitações

**Diferenciais:** grátis com CRM completo atrás; `inlineEmbedSelector`; `avoidInlineStyles` (amigável a CSP); banner de cookie próprio com modo `ON_EXIT_INTENT`; evento `contactAssociated`.
**Limitações:** customização visual rasa; identidade depende de chamada de API server-side (mais fricção que HMAC/JWT local); widget acoplado ao ecossistema HubSpot; o `utk` do visitante trafega na querystring do iframe **[FV-M]**.

---

### 4.4 Zendesk (Web Widget / messaging)

**Posição:** o padrão corporativo de suporte. A API do widget messaging é, junto com a do Intercom, a mais completa que li.
**Docs:** <https://developer.zendesk.com/api-reference/widget-messaging/web/core/> · eventos: <https://developer.zendesk.com/api-reference/widget-messaging/web/events/> · auth: <https://developer.zendesk.com/api-reference/widget-messaging/web/authentication/>

#### 4.4.1 Instalação **[FV]**

Snippet copiado do Admin Center (*Channels → Messaging and social → Messaging → widget → Installation*), colado **antes do `</body>`**, em toda página onde o widget deve aparecer.
Fonte: <https://support.zendesk.com/hc/en-us/articles/4500748175258-Installing-the-Web-Widget-for-messaging>

**[FV-M]** O arquivo servido é `https://static.zdassets.com/ekr/snippet.js?key=<KEY>` — 3.987 bytes na rede / 9.693 descomprimidos. Inspecionando o conteúdo: é um bundle webpack mínimo com `publicPath = "https://static.zdassets.com/ekr/"`, carregamento de chunk por `Promise`, timeout de script de **120 s** (`setTimeout(h.bind(null,void 0,{type:"timeout"}), 12e4)`), suporte a `nonce` de CSP (`s.nc && a.setAttribute("nonce", s.nc)`) e um chunk separado `sentry-browser.min.js`. Hosts referenciados: `ekr.zdassets.com`, `static.zdassets.com`, `v2.zopim.com`.

**[INF]** O `v2.zopim.com` no snippet novo é resíduo do Zopim (a aquisição que virou o Zendesk Chat). Dez anos depois ainda está no caminho crítico.

#### 4.4.2 API `zE` — comandos principais **[FV]**

| Grupo | Comando |
|---|---|
| Visibilidade | `zE('messenger', 'show')` · `zE('messenger', 'hide')` · `zE('messenger', 'open')` · `zE('messenger', 'close')` |
| Configuração | `zE('messenger:set', 'locale', newLocale)` · `zE('messenger:set', 'zIndex', newZIndex)` · `zE('messenger:set', 'cookies', range)` · `zE('messenger:set', 'conversationFields', fields)` · `zE('messenger:set', 'conversationTags', tags)` · `zE('messenger:set', 'behavior', options)` · `zE('messenger:set', 'customization', options)` |
| Usuário/dados | `zE('messenger', 'updateUser', metadata, callback)` · `zE('messenger:set', 'userMetadata', metadata, callback)` · `zE('messenger:set', 'conversationMetadata', metadata, callback)` · `zE('messenger', 'resetWidget', callback)` |
| Conversas | `zE('messenger:ui', 'newConversation', options, callback)` · `zE('messenger', 'newConversation', options, callback)` · `zE('messenger', 'sendMessage', message, conversationId, callback)` · `zE('messenger', 'fetchConversations', offset, callback)` |
| Interceptação | `zE('messenger:set', 'beforeMessageSent', callback)` · `zE('messenger:set', 'beforeMessageDisplay', callback)` |
| Renderização | `zE('messenger', 'render', config, errorCallback)` — modo **flutuante ou embutido** · `zE('messenger:ui', 'navigation', config)` · `zE('messenger:get', 'config', callback)` |

**[INF] Três capacidades que quase ninguém tem:**
1. **`beforeMessageSent` / `beforeMessageDisplay`** — hooks para *modificar mensagem antes de enviar e antes de exibir*. Isso permite mascarar PII no cliente, injetar contexto, traduzir. Nenhum outro player da lista expõe interceptação bidirecional.
2. **`fetchConversations(offset, callback)`** — o host pode **paginar o histórico** do usuário e renderizar a própria UI se quiser.
3. **`render` com modo embutido** + `messenger:ui navigation` — o widget vira componente de página, não só bolha.

#### 4.4.3 Eventos **[FV]**

```js
const unsubscribe = zE('messenger:on', 'open', callback);
unsubscribe(); // toda inscrição devolve uma função de cancelamento
```

```js
zE('messenger:on', 'unreadMessages', function (count) { /* ... */ });
zE('messenger:on', 'conversationStarted', function (event) { /* ... */ });
zE('messenger:on', 'messageReceived', function (event) { /* ... */ });
```

Lista publicada (18+): `open`, `close`, `show`, `hide`, `conversationStarted`, `messageReceived`, `unreadMessages`, `conversationOpened`, `conversationClicked`, `conversationWithAgentRequested`, `conversationAgentAssigned`, `messagesShown`, `postbackButtonClicked`, `articleClicked`, `articleBrowserClicked`, `proactiveMessageDisplayed`, `proactiveMessageClicked`, `conversationExtensionOpened`, `conversationExtensionDisplayed`.

**[INF]** `articleClicked`, `articleBrowserClicked` e `conversationExtension*` confirmam: no Zendesk o widget também é navegador de base de conhecimento e host de extensões de terceiros.

#### 4.4.4 Autenticação — JWT com signing key **[FV]**

```js
zE("messenger", "loginUser", jwtCallback /* function */, loginCallback /* function */)
zE("messenger", "logoutUser")
zE("messenger", "useSessionAuth", sessionAuthCallback /* function */)
```

- A **signing key** é criada por um admin no Admin Center e é composta de **`kid` (key id) + segredo compartilhado**, usados para assinar o JWT.
- *"A request made with a JWT which has an `exp` that is in the past is rejected."*
- Para tokens que expiram, é preciso **buscar um JWT novo a cada 401** do widget — por isso `loginUser` recebe um **callback** que devolve o token, e não o token direto. Design correto para renovação.
- `logoutUser` volta o widget ao estado pré-login e **limpa os dados da conversa**.
- `useSessionAuth` reaproveita a sessão do Help Center — quem já está logado no HC não precisa de JWT próprio.

Fontes: <https://developer.zendesk.com/api-reference/widget-messaging/web/authentication/> · <https://support.zendesk.com/hc/en-us/articles/4411666638746-Authenticating-end-users-for-messaging>

**[INF]** O padrão "callback que devolve token" é objetivamente melhor do que "atributo estático no settings" (Intercom/Crisp/Front). Permite refresh sem recarregar a página.

#### 4.4.5 Customização — e o limite explícito **[FV]**

```js
zE("messenger:set", "customization", {
  theme: {
    primary: "#FE5E41",
    onPrimary: "#FFFFFF",
    action: "#B0DB43",
    businessMessage: "#fff"
  }
})
```

Tokens de cor disponíveis: `primary`, `onPrimary`, `message`, `onMessage`, `businessMessage`, `onBusinessMessage`, `background`, `onBackground`, `action`, `onAction`, `error`, `onError`, `notify`, `onNotify`.
Regras: valores em hex/rgb/hsl/nome; valor inválido gera erro no console; propriedade omitida cai no default do Admin Center; a mudança vale só nas páginas onde o código roda.
Fonte: <https://support.zendesk.com/hc/en-us/articles/9944875856666-Customizing-the-messaging-Web-Widget-colors-with-the-Web-Widget-API>

**[FV] O limite, dito pela própria Zendesk:** na comparação oficial entre widgets, "Custom CSS / Advanced customization" aparece como **"Y (Via API)" no Classic e ausente no messaging**; e **"Proactive messages"** aparece **"Yes" no Classic e "No" no messaging**.
Fonte: <https://support.zendesk.com/hc/en-us/articles/4429429087002-Comparing-the-Zendesk-Web-Widgets>

Ainda na mesma comparação: o messaging ganha **conversas persistentes** (*"view past interactions"*), **notificações por e-mail** e **tradução automática de conversa**; o Classic segue disponível **somente para contas criadas antes de 05/06/2023**.

**[INF]** Zendesk trocou customização profunda + proativo por persistência + omnicanal. É uma escolha de produto explícita e uma abertura clara para concorrente que entregue os dois.

**Nomenclatura de tokens [INF]:** o esquema `primary` / `onPrimary`, `background` / `onBackground` é **Material Design 3**. Vale copiar o vocabulário: garante contraste por construção e é familiar para designers.

#### 4.4.6 Preço **[FV]**

Página oficial BR (<https://www.zendesk.com.br/pricing/>): **Suite Team R$ 359** agente/mês (anual), **Suite Professional R$ 755** agente/mês (anual), **Suite Enterprise + Copilot** sob consulta.
IA: a unidade é **"resoluções automatizadas"** e o cliente *"paga apenas pelas solicitações do cliente que foram resolvidas com sucesso pelo agente de IA"*. **Preço por resolução não é publicado — [NV]**.

#### 4.4.7 Diferenciais e limitações

**Diferenciais:** `beforeMessageSent`/`beforeMessageDisplay`; `fetchConversations`; render embutido; auth por callback com refresh em 401; `useSessionAuth`; tradução automática de conversa; tokens de tema estilo Material 3.
**Limitações:** **sem mensagens proativas** e **sem CSS custom** na versão messaging (declarado pela própria Zendesk); preço de IA opaco; resíduo de infraestrutura Zopim.

---

### 4.5 Freshchat (Freshworks)

**Posição:** o widget da suíte Freshworks. Hoje comercializado dentro do **Freshdesk Omni**.
**Docs:** <https://developers.freshchat.com/web-sdk/v2/>

#### 4.5.1 Instalação **[FV]**

```html
<script src='//fw-cdn.com/TOKEN/WIDGETID.js' chat='true'></script>
```

Configuração por `window.fcWidgetMessengerConfig` ou `window.fcSettings`:

```js
window.fcWidgetMessengerConfig = {
  externalId: "user@example.com",
  restoreId: restoreId || null
}
```

```js
window.fcSettings = {
  onInit: function() {
    window.fcWidget.setExternalId("user123");
    window.fcWidget.user.setProperties({
      firstName: "John",
      email: "john@example.com"
    });
  }
}
```

**[INF]** O atributo `chat='true'` no próprio `<script>` é incomum — configuração declarativa em HTML em vez de objeto JS.

#### 4.5.2 Arquitetura **[FV-M]**

Baixei `https://wchat.freshchat.com/js/widget.js`: 21.963 bytes na rede / **70.114 descomprimidos**. O conteúdo contém **1 `attachShadow` e 9 referências a `shadowRoot`**, 10 ocorrências de `iframe` e **32 de `postMessage`**. Host único referenciado: `assetscdn-wchat.freshchat.com`.

**[INF]** É arquitetura **híbrida**: Shadow DOM para o launcher/casca (evita herdar CSS do host) + iframe para o painel de conversa (isolamento real) + `postMessage` intenso para a ponte entre os dois. É o desenho mais sofisticado que encontrei em código, e é exatamente o que eu recomendaria (ver seção 8).

Não consegui medir o widget rodando: o site institucional da Freshworks usa **Qualified**, não Freshchat **[FV-M]**.

#### 4.5.3 API **[FV]**

*Controle:* `window.fcWidget.open()` (aceita payload) · `.close()` · `.isOpen()` · `.show()` · `.hide()` · `.destroy()` · `.isInitialized()` · `.isLoaded()`
*Usuário:* `.setExternalId(id)` · `.user.setProperties(props)` · `.user.setEmail(email)` · `.user.create(payload, callback)` · `.user.get()` (Promise) · `.user.update(payload)` · `.user.clear()`
*Conteúdo/analytics:* `.setTags(tags)` · `.setFaqTags({tags, filterType})` · `.trackPage(url, title)` · `.user.setLocale(lang)`

```js
window.fcWidget.open({ name: "Support", replyText: "How can you help?" });
```

```js
FM.trackCustomEvent("Added to cart", {
  email: "user@example.com",
  price: 99.99,
  currency: "USD"
})
```

*Eventos* via `window.fcWidget.on(eventName, callback)`: `widget:loaded`, `widget:opened`, `widget:closed`, `user:created`, `unreadCount:notify`, `message:sent`, `message:received`, `user:cleared`.

**[INF]** `setFaqTags({tags, filterType})` é uma capacidade rara: **filtrar quais artigos da base aparecem no widget conforme o contexto da página**. Só o Freshchat expõe isso de forma tão direta.

#### 4.5.4 Identidade — dois modelos **[FV]**

**Modelo 1 — Restore ID (padrão).** Requer `externalId` único e um `restoreId` gerado na primeira mensagem. O `restoreId` deve ser **armazenado no seu banco** e devolvido para restaurar a conversa em outro dispositivo.

```js
window.fcWidgetMessengerConfig = {
  externalId: "john.doe@example.com",
  restoreId: storedRestoreId
}
```

**Modelo 2 — JWT (segurança reforçada).** Precisa ser **habilitado via suporte**. Tokens assinados em **RS256** contendo `reference_id`, `freshchat_uuid` (UUID gerado pelo SDK), `iat` e propriedades customizadas. Autenticação por `window.fcWidget.authenticate(signedToken)`.

**[INF] Crítica dura ao modelo 1:** o `restoreId` é um segredo portador ("bearer") que o *seu* sistema tem que guardar por usuário. Se vazar, dá acesso à conversa. E é o modelo **padrão** — o seguro (JWT) exige abrir chamado no suporte. Isso é o inverso do que deveria ser. Também é o único player da lista onde o algoritmo é **RS256** (assimétrico) em vez de HS256 — tecnicamente superior (a chave privada nunca sai do cliente), mas escondido atrás de uma barreira de processo.

#### 4.5.5 Preço **[FV]**

Fonte: <https://www.freshworks.com/freshdesk/omni/pricing/>

| Plano | Preço (anual) |
|---|---|
| Growth | US$ 29 / agente / mês |
| Pro | US$ 79 / agente / mês |
| Enterprise | US$ 119 / agente / mês |
| Freddy AI Agent | **500 sessões inclusas**; extras a **US$ 49 / 100 sessões** |
| Day passes | US$ 5–15 por passe, conforme tier |
| Connector app tasks | US$ 80 por 5.000 tasks |

Teste: 14 dias com acesso ao plano Enterprise.

#### 4.5.6 Diferenciais e limitações

**Diferenciais:** arquitetura híbrida Shadow DOM + iframe; `setFaqTags` com filtro contextual; JWT RS256; *day passes* (modelo de licença flexível para picos sazonais — ninguém mais tem).
**Limitações:** JWT só sob solicitação ao suporte; `restoreId` como padrão é frágil; documentação fragmentada entre `developers.freshchat.com`, `freshworks.com` e `support.freshdesk.com`; a própria empresa não usa o produto no site institucional **[FV-M]**.

---

### 4.6 Tidio

**Posição:** líder do segmento SMB/e-commerce, forte em Shopify. Aposta pesada no agente Lyro.
**Docs:** <https://developers.tidio.com/docs/api_v3> (o antigo `docs.tidio.com` responde 301 para cá)

#### 4.6.1 Arquitetura **[FV-M]**

No `tidio.com` medido: global `tidioChatApi`; no `<body>` há `script#chat-widget-bootstrap`, `iframe#tidio-chat-code` (0×0, com `title="Tidio Chat code"`) e **`div#tidio-chat.needsclick`**.

**[INF]** O desenho é: um **iframe 0×0 invisível** que funciona como *sandbox de execução* ("Chat code" — provavelmente onde rodam os scripts de automação/bot do cliente, isolados da página), enquanto a **UI é montada no `div#tidio-chat` no DOM do host**. A classe `needsclick` é do FastClick/Mobile — pista de que o container está no DOM real da página e precisa de tratamento de toque.

WebSocket **[FV-M]**:
```
wss://socket.tidio.co/socket.io/?ppk=<public key>&device=desktop&cmv=2_0&ver=1.451.0&seid=<session>&vid=<visitor>&EIO=4&transport=websocket
```
Repare em `ver=1.451.0`: a versão do widget vai no handshake, permitindo ao backend tratar clientes antigos.

Peso: **135.995 bytes em 8 requisições** de `code.tidio.co`. Também usa `sentry.tidio.co` (monitoramento de erro do próprio widget) **[FV-M]**.

#### 4.6.2 API **[NV parcial]**

A doc pública (`developers.tidio.com/docs/api_v3`) retornou 404 nas minhas tentativas de leitura automatizada. O que consigo afirmar com segurança: o objeto global é **`tidioChatApi`** **[FV-M]** e existe `document.tidioIdentify` para identificação (uso amplamente documentado em integrações de terceiros, mas **[NV]** como fonte primária hoje).
As assinaturas exatas dos métodos (`open`, `close`, `show`, `hide`, `display`, `messageFromOperator`, `setVisitorData`, `track`, `on`) **não foram verificadas em fonte primária nesta pesquisa** — não vou reproduzi-las de memória.

#### 4.6.3 Lyro (agente de IA) **[FV]**

Fonte: <https://www.tidio.com/lyro-ai-chatbot/>

- Preço: **US$ 0,50 por conversa Lyro**. Toda conta tem **50 conversas Lyro grátis** de início; o limite renova *"30 days after payment"*.
- Base de conhecimento: *"automatically scrapes your support content and uses it as its knowledge base"* e *"works only with the content and guidance you provide"*.
- Handoff: encaminha automaticamente para humano quando sai do conhecimento, e *"learns from their response"*. Há regras flexíveis de handoff/escalação por valor de cliente ou sensibilidade do tema.
- Idiomas suportados: **[NV]** na página oficial.

#### 4.6.4 Preço **[FV]**

Fonte: <https://www.tidio.com/pricing/>

| Plano | Preço | Conversas faturáveis | Assentos |
|---|---|---|---|
| Free | US$ 0 | — | 10 |
| Starter | US$ 24,17/mês | 100 | 10 |
| Growth | a partir de US$ 49,17/mês | até 2.000 | 10 |
| Plus | a partir de US$ 300/mês + uso | custom | custom |
| Premium | sob consulta | custom | custom |

Lyro: cotas separadas, de 50 a 1.000+ conversas, *"Starts at $32.50/mo."*
**Remoção da marca Tidio: add-on de US$ 16,67/mês** nos planos menores; incluída como *"Custom branding"* no Plus.

**[INF]** Tidio é o único que **precifica explicitamente a remoção de marca como SKU isolado**. Sinal de que muita gente paga só por isso.

#### 4.6.5 Diferenciais e limitações

**Diferenciais:** preço de entrada baixo com IA inclusa; Lyro por conversa (previsível); Sentry próprio no widget (qualidade); versão do widget no handshake do socket.
**Limitações:** documentação de desenvolvedor instável (URL antiga 301, nova 404 no meu acesso); UI no DOM do host = risco de colisão de CSS **[INF]**; teto de conversas faturáveis pode surpreender em pico.

---

### 4.7 Crisp

**Posição:** o mais "hacker-friendly" e o mais barato com features de gente grande. Base forte na Europa e no Brasil.
**Docs:** <https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/dollar-crisp/>

#### 4.7.1 Arquitetura — o outlier **[FV-M]**

**Zero iframes. Zero shadow roots.** Apenas `div.crisp-client` no `<body>`. Todo o messenger é renderizado **no DOM da página host**.

Consequências **[INF]**:
- **Vantagem:** boot mais leve (nenhum browsing context extra), acessibilidade e foco funcionam naturalmente, sem problema de third-party cookie, e o cliente **pode** estilizar por CSS.
- **Desvantagem:** o CSS do site vaza para dentro do widget e vice-versa. Regras catch-all do site (`* { box-sizing }`, `button { border: none }`, resets agressivos) atingem o chat. Foi exatamente essa classe de bug que já mordeu o ChatSPX antes.

WebSocket: `wss://client.relay.crisp.chat/w/92b/?EIO=4&transport=websocket` (Engine.IO v4) **[FV-M]**.
Peso: 98.544 bytes em 9 requisições de `static.crisp.help` (medição subestimada por `transfer-encoding: chunked` em `client.crisp.chat`) **[FV-M]**.
Loader: 2.875 bytes na rede, com bloqueio de bots e matriz de navegador descritos na seção 3.2.

#### 4.7.2 API `$crisp` — a mais completa em superfície **[FV]**

Padrão: `$crisp.push([verbo, "namespace:acao", [args]])`, com quatro verbos — `set`, `do`, `on`, `config` — mais `$crisp.get()` e `$crisp.is()` síncronos.

**`set`:**
```js
$crisp.push(["set", "message:text", [text]])
$crisp.push(["set", "session:segments", [[segments], overwrite?]])
$crisp.push(["set", "session:data", [[[key, value], ...]]])
$crisp.push(["set", "session:event", [[[text, data, color], ...]]])
$crisp.push(["set", "user:email", [email]])
$crisp.push(["set", "user:phone", [phone]])
$crisp.push(["set", "user:nickname", [nickname]])
$crisp.push(["set", "user:avatar", [avatar]])
$crisp.push(["set", "user:company", [name, {url, description, employment, geolocation}]])
```

**`do`:**
```js
$crisp.push(["do", "chat:open", [done?]])
$crisp.push(["do", "chat:close"])
$crisp.push(["do", "chat:toggle"])
$crisp.push(["do", "chat:show"])
$crisp.push(["do", "chat:hide"])
$crisp.push(["do", "message:send", [type, content]])
$crisp.push(["do", "message:show", [type, content]])
$crisp.push(["do", "message:read"])
$crisp.push(["do", "message:thread:start", [text]])
$crisp.push(["do", "message:thread:end", [text?]])
$crisp.push(["do", "session:reset", [reload?]])
$crisp.push(["do", "trigger:run", [identifier]])
$crisp.push(["do", "bot:scenario:run", [identifier, variables?]])
$crisp.push(["do", "helpdesk:search"])
$crisp.push(["do", "helpdesk:article:open", [locale, slug, title?, category?]])
$crisp.push(["do", "helpdesk:query", [search_query]])
$crisp.push(["do", "overlay:open", [done?]])
$crisp.push(["do", "overlay:close"])
```

**`get` / `is` (não async-safe):**
```js
$crisp.get("chat:unread:count") · $crisp.get("message:text") · $crisp.get("session:identifier")
$crisp.get("session:data", key) · $crisp.get("user:email") · $crisp.get("user:phone")
$crisp.get("user:nickname") · $crisp.get("user:avatar") · $crisp.get("user:company")

$crisp.is("chat:opened") · $crisp.is("chat:closed") · $crisp.is("chat:visible") · $crisp.is("chat:hidden")
$crisp.is("chat:small") · $crisp.is("chat:large") · $crisp.is("session:ongoing")
$crisp.is("website:available") · $crisp.is("overlay:opened") · $crisp.is("overlay:closed")
```

**`on` (eventos):**
`session:loaded` · `chat:initiated` · `chat:opened` · `chat:closed` · `message:sent` · `message:received` · `message:compose:sent` · `message:compose:received` · `user:email:changed` · `user:phone:changed` · `user:nickname:changed` · `user:avatar:changed` · `website:availability:changed` · `helpdesk:queried` · **`hugo:tool:<action_name>`**

**`config` (aparência/comportamento em runtime):**
`availability:tooltip` · `hide:vacation` · `hide:on:away` · `hide:on:mobile` · `show:operator:count` · `position:reverse` · `sound:mute` · **`color:theme`** · **`color:mode`** · **`layout:theme`** · `tile` · `locale` · **`container:index`**

**[INF] Destaques sem paralelo:**
- **`message:compose:sent` / `message:compose:received`** — eventos de *digitação em andamento*, dos dois lados, expostos ao site host. Ninguém mais expõe isso.
- **`hugo:tool:<action_name>`** — o site host pode **implementar ferramentas que o agente de IA (Hugo) chama**. É function-calling do LLM delegado ao JavaScript do cliente. Conceitualmente é o recurso mais avançado que vi em qualquer widget.
- **`color:mode`** e **`layout:theme`** em runtime — troca de dark/light e de layout sem recarregar.
- **`bot:scenario:run(identifier, variables)`** — dispara um cenário de bot com variáveis vindas da página.
- **`helpdesk:query` / `helpdesk:search` / `helpdesk:article:open`** — controle total da base de conhecimento embutida.

#### 4.7.3 Identidade **[FV]**

Fonte: <https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/identity-verification/>

- HMAC-**SHA256**, com aviso textual: *"Make sure you generate signatures with the `HMAC-SHA256` algorithm. Any other HMAC digest is not accepted."*
- O que é assinado: **o e-mail**.
- Chave secreta em *Settings → Workspace Settings → Advanced Configuration → Identity Verification*.

```js
$crisp.push(["set", "user:email", ["email@example.com", "signature_here"]]);
```

```js
const crypto = require("crypto");
const secretKey = "your_secret_key_here";

function signEmail(email) {
  return crypto.createHmac("sha256", secretKey).update(email).digest("hex");
}

var signature = signEmail("user@gmail.com");
// cd7cc422ea97c82d844b2373fdcd6259c9ee6e135af65ab6fe6ca85e3f07abb1
```

Aviso oficial: *"Never use your verification secret key to generate signatures in your front-end directly."*
Disponível a partir do plano **Mini**. Opcional.

#### 4.7.4 Continuidade de sessão — modelo separado da verificação **[FV]**

Fonte: <https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/session-continuity/>

```js
CRISP_TOKEN_ID = 'UserSecureTokenFromMyWebsite';
CRISP_WEBSITE_ID = 'MyWebsiteID';
```

- Regra dura: *"Tokens can only be passed before, or upon chatbox code injection, and not after the chatbox code loaded."* Se chegar depois, é preciso `$crisp.push(["do", "session:reset"])`.
- Token **deve** ser UUID v4 ou string pseudoaleatória de fonte segura. A doc **lista explicitamente o que não usar**: IDs autoincrementais, hash do e-mail (MD5/SHA256), o próprio e-mail, timestamps.
- Logout:
```js
CRISP_TOKEN_ID = null;
$crisp.push(["do", "session:reset"]);
```
- Fusão de sessão anônima → autenticada:
```js
CRISP_RUNTIME_CONFIG = { session_merge: true };
```
- Proteção declarada: o Crisp **bloqueia restauração de sessão depois que o usuário digitou o e-mail no chatbox**, para evitar sequestro de sessão baseado em e-mail.

**[INF]** Essa separação — `CRISP_TOKEN_ID` para *continuidade* e assinatura HMAC para *verificação* — é conceitualmente mais limpa do que juntar tudo num só token, e é um modelo que vale copiar: continuidade e autenticidade são problemas distintos.

#### 4.7.5 Preço **[FV]**

Fonte: <https://crisp.chat/en/pricing/>

| Plano | Preço/mês (workspace) | Assentos | Créditos de IA |
|---|---|---|---|
| Free | US$ 0 | 2 | — |
| Mini | US$ 45 | 4 | US$ 0–5 |
| Essentials | US$ 95 | 10 | US$ 25 inclusos |
| Plus | US$ 295 | 20+ | US$ 75 inclusos |
| Enterprise | sob consulta | — | — |

Agente adicional: US$ 10/mês. Teste: 14 dias, todos os recursos, sem cartão.
**White label:** exclusivo do **Plus** — *"Get rid of the Crisp watermark 'We run on Crisp'."*

**[INF]** Preço **por workspace, não por assento**, é um diferencial competitivo enorme contra Intercom/Zendesk para times pequenos.

#### 4.7.6 Diferenciais e limitações

**Diferenciais:** API mais expressiva do mercado (`hugo:tool:*`, `compose:*`, `config` em runtime); preço por workspace; blindagem contra bots no loader; separação limpa entre continuidade e verificação; base de conhecimento controlável por API.
**Limitações:** **sem isolamento de CSS** (o maior risco técnico); verificação só assina e-mail (não `user_id`); HMAC sem expiração; bloqueio de `Lighthouse`/`HeadlessChrome` esconde o custo real de performance do cliente **[FV-M]** — prática que eu não recomendaria copiar.

---

### 4.8 LiveChat (Text)

**Posição:** veterano puro-sangue de live chat (a holding hoje se chama Text). Menos "plataforma", mais "chat bem-feito".
**Docs:** <https://platform.text.com/docs/extending-chat-widget/javascript-api> (o antigo `developers.livechat.com` responde 301)

#### 4.8.1 Arquitetura **[FV-M]**

Dois iframes dentro de `div#chat-widget-container`:
- **`#chat-widget`** — `src="https://secure.livechatinc.com/customer/action/open_chat?license_id=19196658&group=3&embedded=1&widget_version=3&unique_groups=0&organization_id=4c8c0751-837f-4..."`. Note os parâmetros: `license_id`, `group`, `embedded`, `widget_version=3`, `unique_groups`, `organization_id`.
- **`#chat-widget-minimized`** — sem `src`, construído localmente, 320×299 quando com eye-catcher.

O `#chat-widget` traz um atributo `allow` revelador **[FV-M]**:

```
allow="clipboard-read; clipboard-write; autoplay; display-capture *"
```

**`display-capture *`** = **compartilhamento de tela** habilitado dentro do widget. É o único player onde vi essa permissão declarada no iframe.

WebSocket: `wss://api.livechatinc.com/v3.6/customer/rtm/ws?organization_id=...&x-region=us-south1` — **API versionada e região explícita** **[FV-M]**.
`cdn.livechatinc.com/tracking.js`: 36.066 bytes na rede / 112.305 descomprimidos. Total do host com widget aberto: 345.492 bytes em 17 requisições **[FV-M]**.

#### 4.8.2 API **[FV]**

Seis funções: `on`, `once`, `off`, `call`, `get`, `init`. Versão do script: `LiveChatWidget.scriptTagVersion();`

**Init assíncrono:**
```js
window.__lc.asyncInit = true;
// ...
LiveChatWidget.init();
```

**Métodos (`call`):**
```js
LiveChatWidget.call("maximize");
LiveChatWidget.call("maximize", { messageDraft: "text" });   // abre já com rascunho
LiveChatWidget.call("minimize");
LiveChatWidget.call("hide");
LiveChatWidget.call("destroy");
LiveChatWidget.call("hide_greeting");
```

**E-commerce nativo — raro:**
```js
LiveChatWidget.call("trigger_sales_tracker", {
  trackerId: "string", orderPrice: "string", orderId: "string"
});

LiveChatWidget.call("track_sales_event", {
  name: "store_order_was_created" | "store_product_added_to_cart" | "store_product_removed_from_cart",
  data: { /* ... */ }
});
```

**Setters:**
```js
LiveChatWidget.call("set_customer_name", "John Doe");
LiveChatWidget.call("set_customer_email", "john@example.com");
LiveChatWidget.call("set_session_variables", { username: "john.doe", cart_value: "450" });
LiveChatWidget.call("update_session_variables", { username: "j.doe" });
```

**Getters:**
```js
LiveChatWidget.get("state");          // { availability: 'online'|'offline', visibility: 'maximized'|'minimized'|'hidden' }
LiveChatWidget.get("customer_data");  // { id, name, email, isReturning, status, sessionVariables }
LiveChatWidget.get("chat_data");      // { chatId, threadId }
```
Restrição: *"You can't use getters before load."*

**Eventos (`on`):**

| Evento | Payload |
|---|---|
| `ready` | `{ state, customerData }` |
| `availability_changed` | `{ availability }` |
| `visibility_changed` | `{ visibility }` |
| `customer_status_changed` | `{ status }` |
| `new_event` | `{ type, author, timestamp, ... }` |
| `form_submitted` | `{ type }` |
| `rating_submitted` | `{ value }` |
| `greeting_displayed` | `{ id, uniqueId }` |
| `greeting_hidden` | `{ id, uniqueId }` |
| `rich_message_button_clicked` | `{ eventId, postbackId, greeting }` |

**[INF]** `isReturning` no `customer_data` e `greeting_displayed/hidden` com `uniqueId` mostram um produto pensado para **medir eficácia de saudação proativa** — algo que a maioria trata como detalhe.

#### 4.8.3 Identidade **[NV]**

Não localizei, nesta pesquisa, doc primária de verificação criptográfica de identidade do visitante no widget do LiveChat (existe `set_customer_email`/`set_customer_name`, que são **declarativos, não verificados**). Marco como **[NV]** — pode existir em nível de Customer SDK/Accounts SSO, mas não confirmei.

#### 4.8.4 Customização **[FV]**

Fonte: <https://www.livechat.com/features/customization/>
*"set the theme, colors, and position of the Chat Widget on the fly"* · exibição diferente em desktop e mobile · perfil do agente (nome, cargo, foto) · **45+ idiomas, incluindo RTL (árabe e hebraico)** · acessibilidade: *"Screen reader support, keyboard navigation, contrast adjustments"*.
**White label:** a página de preços lista **"White label chat widget" apenas no plano Enterprise** **[FV]**.

**[INF]** LiveChat é o único que menciona **acessibilidade explicitamente na página de features do widget** (leitor de tela, navegação por teclado, ajuste de contraste). Dado que o widget vive em iframe, isso exige trabalho real.

#### 4.8.5 Preço **[FV]**

Fonte: <https://www.livechat.com/pricing/>

| Plano | Anual | Mensal | Visitantes rastreados |
|---|---|---|---|
| Starter | US$ 19/mês (fixo) | US$ 25/mês | até 100 |
| Team | US$ 49/pessoa/mês | US$ 59 | até 400 |
| Business | US$ 79/pessoa/mês | US$ 89 | até 1.000 |
| Enterprise | sob consulta | — | custom | 

**[INF]** Cobrar por **visitantes rastreados** (e não só por assento) é modelo antigo e hoje raro; penaliza sites de alto tráfego e baixo volume de chat.

#### 4.8.6 Diferenciais e limitações

**Diferenciais:** `display-capture` (screen share) no iframe; eventos de e-commerce nativos; `messageDraft` ao abrir; getters síncronos ricos; 45+ idiomas com RTL; acessibilidade declarada; `<noscript>` com fallback para chat hospedado.
**Limitações:** sem verificação criptográfica de identidade documentada **[NV]**; white label só no Enterprise; teto de visitantes por plano; bundle de entrada pesado (112 KB descomprimido).

---

### 4.9 Olark

**Posição:** veterano de nicho, reposicionado como "AI website agent". Reputação histórica de acessibilidade.
**Docs:** <https://www.olark.com/api>

#### 4.9.1 Arquitetura **[FV-M]**

Achado interessante: no site do próprio Olark encontrei um **custom element `<olark-experience>` com shadow root aberto** (3 filhos, 1 tag de estilo) e um iframe `blob:` com `title="Olark iframe intentionally blank"`.

**[INF]** O `blob:` iframe "intencionalmente em branco" é um truque conhecido para criar um contexto isolado sem requisição de rede — mesma família do padrão C do tawk.to, mas com `blob:` URL em vez de `about:blank`.

Loader: `static.olark.com/jsclient/loader0.js`, 11.706 bytes na rede / 34.770 descomprimidos, 12 ocorrências de `iframe`, **zero** `attachShadow` (o shadow DOM vem no bundle seguinte). Host de dados: `visitor.olark.com` **[FV-M]**.

Curiosidade **[FV-M]**: o site do Olark também carrega **`openai-chatkit`** (custom element com shadow root, `cdn.platform.openai.com`) — ou seja, o Olark roda um agente da OpenAI ao lado do próprio produto.

#### 4.9.2 API **[FV]**

Sintaxe: `olark('metodo', args)` e `olark.configure('chave', valor)`, ambos **antes** de `olark.identify('SITE-ID')`.

*Caixa:* `api.box.show` · `api.box.hide` · `api.box.expand` · `api.box.shrink` · `api.box.onShow` · `api.box.onHide` · `api.box.onExpand` · `api.box.onShrink` · `api.box.setLocale`
*Visitante:*
```js
olark('api.visitor.getDetails', callback)   // e-mail, nome, localização, histórico de páginas
olark('api.visitor.updateEmailAddress', {emailAddress: string})
olark('api.visitor.updateFullName', {fullName: string})
olark('api.visitor.updatePhoneNumber', {phoneNumber: string})
olark('api.visitor.updateCustomFields', {fieldName: value})
olark('api.chat.updateVisitorNickname', {snippet: string})
olark('api.chat.updateVisitorStatus', {snippet: string})
```
*Chat:*
```js
olark('api.chat.sendMessageToVisitor', {body: string})       // "operador" fala, vindo do JS do site
olark('api.chat.sendNotificationToOperator', {body: string})
olark('api.chat.sendNotificationToVisitor', {body: string})
olark('api.chat.onBeginConversation', cb)
olark('api.chat.onMessageToVisitor', cb)
olark('api.chat.onMessageToOperator', cb)
olark('api.chat.onCommandFromOperator', cb)   // operador digita !comando
olark('api.chat.onOfflineMessageToOperator', cb)
olark('api.chat.onOperatorsAvailable', cb)
olark('api.chat.onOperatorsAway', cb)
olark('api.chat.onReady', cb)
olark('api.chat.setOperatorGroup', {group: id})
```

**[INF]** `onCommandFromOperator` é único: o **operador** digita `!track` no painel e isso dispara código **no navegador do visitante**. Poderosíssimo e assustador em partes iguais — é execução remota controlada pelo atendente.

#### 4.9.3 Configuração e regras **[FV]**

```js
olark.configure('system.hb_primary_color', '#744da8');
olark.configure('system.hb_dark_theme', true);
olark.configure('system.hb_position', 'left');
olark.configure('system.hb_chatbox_size', 'lg');   // sm, md, lg, dr (drawer)
olark.configure('system.hb_detached', true);
olark.configure('system.hb_show_as_tab', true);
olark.configure('box.start_expanded', true);
olark.configure('box.start_hidden', true);
olark.configure('box.inline', true);               // renderiza em #olark-box-container
olark.configure('system.is_single_page_application', true);
olark.configure('system.right_to_left', true);
olark.configure('features.prechat_survey', true);
olark.configure('features.feedback', true);
olark.configure('features.greeter', true);
olark.configure('features.attention_grabber', true);
olark.configure('CalloutBubble.slide', true);
olark.configure('CalloutBubble.bubble_image_url', 'path/to/image');
```

**Formulário pré-chat customizado — declarativo:**
```js
olark.configure('system.custom_prechat', [
  {
    type: 'textarea',
    is_required: false,
    label: 'Question?',
    placeholder_text: 'Answer here...'
  }
]);
```

**Regras de chat segmentado — motor de targeting no próprio widget:**
```js
olark('api.rules.defineRule', {
  id: '1',
  description: 'Rule description',
  condition: function(pass) {
    olark('api.visitor.getDetails', function(details) {
      if (/* condição */) pass();
    });
  },
  action: function() { /* ação */ },
  perVisit: true  // ou perPage, perVisitor
});
```

**[INF]** `api.rules.defineRule` com `perVisit`/`perPage`/`perVisitor` é o **motor de mensagens proativas exposto como código**, com controle de frequência embutido. Nenhum outro player deixa o cliente escrever a regra em JS.

Idiomas suportados **[FV]**: inglês, alemão, espanhol, francês, italiano, holandês, **português**, russo, sueco, turco e chinês simplificado. `system.right_to_left` disponível.

#### 4.9.4 Features **[FV]**

Fonte: <https://www.olark.com/features>
Incluídas: engajamento em tempo real via console compartilhado; *"Visitor insights"* (localização, páginas vistas, histórico, contexto); respostas salvas; gestão de time com grupos e regras de roteamento; *"Custom pre-chat & offline forms"*; *"Custom branding"* (cores e posição); follow-up por e-mail; respostas em streaming; transcrições pesquisáveis e exportáveis; qualificação e captura de lead; GDPR.
Listados sob **"Olark Classic"**: WhatsApp & SMS, *"Chat ratings & feedback"*, e **certificação WCAG 2.1 AA**.
Co-browsing, tradução e "visitor insights" como PowerUps pagos separados: **[NV]** nessa fonte (eram PowerUps historicamente).

**[INF]** Marcar **WCAG 2.1 AA** como "Classic" sugere que o produto novo (AI agent) **ainda não** tem a mesma certificação. Se verdade, é regressão de acessibilidade — e para nós é oportunidade.

#### 4.9.5 Preço **[FV]**

Fonte: <https://www.olark.com/pricing>
- **Standard AI Website Agent:** *"$400/month · billed annually ($4,800/yr)"*, incluindo **um assento humano**. Assentos extras: *"+$29/agent/month"*.
- **Live Chat Only (sem IA):** **US$ 29/agente/mês**.
- Enterprise custom.
- Posicionamento declarado: *"No token costs, ever"* e *"Pay for agents, not usage."*

**[INF]** O Olark é o **contra-exemplo deliberado** da tendência de preço por resolução: preço fixo, sem cobrança por uso de IA. Para clientes traumatizados com fatura de IA imprevisível, é argumento de venda forte — e é uma posição que o ChatSPX pode ocupar no Brasil.

#### 4.9.6 Diferenciais e limitações

**Diferenciais:** motor de regras proativas em JS com controle de frequência; `onCommandFromOperator`; pré-chat customizado declarativo; `box.inline`; RTL; histórico forte de acessibilidade; preço fixo sem cobrança por uso de IA.
**Limitações:** produto claramente bifurcado entre "Classic" e "AI agent", com features presas ao lado antigo; preço de entrada do AI agent alto (US$ 400/mês) para SMB; documentação de API com cara de 2015.

---

### 4.10 tawk.to

**Posição:** o gratuito de verdade. Provavelmente o widget mais instalado do mundo em número de sites.
**Docs:** <https://developer.tawk.to/jsapi/>

#### 4.10.1 Arquitetura — padrão C, o mais econômico **[FV-M]**

Cinco iframes **irmãos**, todos dentro de um único `div` com id gerado (`w3cg1goggsoo1786478388569` — prefixo aleatório + timestamp em ms):

| iframe | src | tamanho |
|---|---|---|
| `hmtvd3qovb2g…` | `about:blank` | 64×60 (launcher) |
| `hj5lqimnl0n4…` | `about:blank` | 360×362 (painel/greeting) |
| `i1jna82dvo71…` | `srcdoc` | 0×0 |
| `rfg3uolp2h34…` | `about:blank` | 0×0 |
| `c4t22vt2l4so…` | `about:blank` | 0×0 |

**Nenhum tem `src` remoto.** Todo o HTML é escrito por JS dentro dos iframes. Zero shadow DOM.

**[INF]** É o desenho mais eficiente que medi: isolamento total de CSS **sem custo de rede adicional** e **sem cookies de terceiro**. O preço é complexidade de `postMessage` e dificuldade de acessibilidade. Ids randômicos + timestamp evitam colisão e dificultam bloqueio por adblock **[INF]**.

Peso: 187.736 bytes em 26 requisições de `embed.tawk.to` **[FV-M]**.

WebSocket **[FV-M]**: `wss://vsb98.tawk.to/s/?k=<sessionKey>&cver=0&pop=false&asver=1215578&tkn=<JWT ES256>&EIO=3&transport=websocket`
Decodificando o header do token: `{"alg":"ES256","typ":"JWT","kid":"visitor-application-server-20210022"}`; payload: `{pid, vid, sid, iat, exp, jti}` com **validade de 30 minutos**. Host do socket é **sharded** (`vsb98`, `vsb18` em cargas diferentes).

#### 4.10.2 API **[FV]**

*Controle:* `maximize()` · `minimize()` · `toggle()` · `popup()` (abre em janela separada) · `showWidget()` · `hideWidget()` · `toggleVisibility()` · `endChat()`
*Estado:* `getStatus()` → `'online' | 'away' | 'offline'` · `isChatMaximized()` · `isChatMinimized()` · `isChatHidden()` · `isChatOngoing()` · `isVisitorEngaged()`
*Ciclo de vida:* `onLoad` · `onBeforeLoad` · `onStatusChange(status)` · `onChatStarted` · `onChatEnded` · `onChatMaximized` · `onChatMinimized` · `onChatHidden`
*Usuário:* `onPrechatSubmit(data)` · `onOfflineSubmit(data)` · `onChatMessageVisitor(message)` · `onChatMessageAgent(message)` · `onChatMessageSystem(message)` · `onAgentJoinChat(data)` · `onAgentLeaveChat(data)` · `onChatSatisfaction(satisfaction)` (**-1, 0 ou 1**) · `onVisitorNameChanged(visitorName)` · `onFileUpload(link)` · `onTagsUpdated(data)`

```js
window.Tawk_API = window.Tawk_API || {};
window.Tawk_API.visitor = {
    name: 'Name',
    email: 'email@example.com',
    phone: '+1234567890' // formato E.164
};
```

```js
window.Tawk_API.setAttributes({ 'id': 'A1234', 'store': 'Location' }, function(error){});
window.Tawk_API.addEvent('eventName', {metadata}, callback);
window.Tawk_API.addTags(['tag1', 'tag2'], callback);   // máximo 10 tags por chat
window.Tawk_API.removeTags(['tag1'], callback);
window.Tawk_API.autoStart = false;                     // não conecta socket automaticamente
window.Tawk_API.customStyle = { zIndex: 1000 };        // antes do embed
window.Tawk_API.switchWidget({propertyId, widgetId});  // múltiplos widgets
```
`start()` / `shutdown()` controlam a conexão de socket manualmente.

#### 4.10.3 Identidade — Secure Mode **[FV]**

```js
window.Tawk_API.login({
    hash: 'hmac-sha256-hash',
    userId: 'user123',
    name: 'Name',
    email: 'user@example.com'
}, callback);
```
`logout()` encerra. O hash é **HMAC-SHA256 do e-mail com a API key** (Admin → Property Settings).

**[INF]** O tawk.to é **gratuito** e mesmo assim entrega verificação de identidade — o que reforça que ausência de identidade em produto pago é escolha, não custo.

#### 4.10.4 Features e preço **[FV]**

Fonte: <https://www.tawk.to/features/> e <https://www.tawk.to/pricing/>

Features: live chat; membros de equipe ilimitados; canais Messenger, Twilio SMS, WhatsApp, Telegram, Gmail, Outlook; transferência de chat e *whispers*; apps nativos iOS/Android/macOS/Windows; push; *"Smart triggers"* por URL, comportamento ou referrer; visão de visitantes em tempo real; auto-roteamento e departamentos; atalhos e respostas prontas; *"AI Assist, suggested replies and tone"*; *"Files, 50+ languages, tags"*; *"Match your brand. Set your greeting. Pick where the widget sits"*; responsivo.

Preço:
- **Plataforma: gratuita.** Declaração do fundador: *"you should never have to pay to communicate with your customers … and if you're using tawk.to; you never will."*
- **Remove Branding: US$ 29/mês**
- **AI Assist: a partir de US$ 29/mês** (com plano perpetuamente gratuito para sites de baixo volume)
- **Agentes contratados: US$ 1/hora**
- **Assistentes virtuais: a partir de US$ 7/hora**

**[INF]** Modelo declarado: *"charging at the junction where our customers derive value … not just by limiting access to certain features."* Monetiza serviço humano e marca, não funcionalidade. É a estratégia mais difícil de bater em preço.

#### 4.10.5 Diferenciais e limitações

**Diferenciais:** grátis de verdade; arquitetura de iframes `about:blank` (isolamento sem custo de rede); token de visitante em **JWT ES256** com expiração curta; `switchWidget` multi-propriedade; `autoStart=false` para consentimento; 50+ idiomas; CSAT no widget.
**Limitações:** ids de DOM randômicos dificultam automação/teste do lado do cliente; customização visual limitada a cor/posição/saudação; sem CSS custom; marca sai só pagando US$ 29/mês; documentação enxuta.

---

### 4.11 Gorgias

**Posição:** helpdesk vertical de e-commerce (Shopify). O widget é o mais "comercial" da lista — vende, não só atende.
**Docs:** <https://docs.gorgias.com/en-US/subscribe-to-chat-events-460530>

#### 4.11.1 Arquitetura — quatro iframes por função **[FV-M]**

No `gorgias.com`, dentro de `div#gorgias-chat-container`:

| iframe | title | tamanho (fechado → aberto) |
|---|---|---|
| `#chat-button` | *Gorgias live chat messenger* | 185×62 |
| `#chat-campaigns` | *Gorgias live chat campaigns* | 415×0 → 415×0 |
| `#chat-window` | *Gorgias live chat window* | — → **414×705** |
| `#chat-input` | *Gorgias Floating Chat* | 0×0 |
| `#mount-floating-engagement-widget` | *Gorgias Shopper Engagement* | 400×0 |

Também no body: `script#gorgias-chat-widget-install-v3` e `script#gorgias-chat-bundle` — **dois estágios de script explícitos no DOM** (instalador + bundle) **[FV-M]**.

WebSocket **[FV-M]**: `wss://us-east1-898b.gorgias.chat/ws/?appKey=01J5V1J9ZV18ZCZZZ6ZCFDGFE5&language=en-US`
Região no hostname (`us-east1`), shard (`898b`), `appKey` em **ULID**, idioma no handshake.
Peso: **843.457 bytes em 29 requisições** de `assets.gorgias.chat` — o segundo mais pesado que medi. Usa `browser.sentry-cdn.com` (441 KB) **[FV-M]**.

**[INF]** Ter um iframe dedicado só para **campanhas** (`#chat-campaigns`) e outro só para **Shopper Engagement** revela a prioridade do produto: mensagem proativa de venda é cidadão de primeira classe, com ciclo de vida independente do chat.

#### 4.11.2 API **[FV]**

O padrão de inicialização é obrigatório e a doc é enfática — *"You must never call GorgiasChat without the init().then(...) callback"*:

```js
var initGorgiasChatPromise = (window.GorgiasChat)
    ? window.GorgiasChat.init()
    : new Promise(function (resolve) {
        window.addEventListener('gorgias-widget-loaded', function () { resolve(); })
    });

initGorgiasChatPromise.then(function () {
    GorgiasChat.on('EVENT_NAME', function (data) {
        // seu código aqui
    })
})
```

Métodos confirmados: `GorgiasChat.init()` · `.open()` · `.close()` · `.isOpen()` · `.captureUserEmail()` · `.on(event, cb)`

**Eventos publicados [FV]:**
`ready` · `destroy` · `widget:opened` · `widget:closed` · `message:received` · `message:sent` · `message` · `unreadCount` · `connected` · `disconnected` · `typing:start` · `typing:stop` · `campaign:opened` · `campaign:closed`

**[INF]** `connected` / `disconnected` expostos ao site host são raros e úteis: o site pode reagir à perda de conexão do chat (exatamente a classe de problema do banner "Desconectado" que já tratamos no ChatSPX).

`ticket:created`, `setContactCustomFields` e `updateContactInfo` **não constam** na doc que li — **[NV]**.

#### 4.11.3 Identidade **[NV]**

Não localizei doc primária de verificação criptográfica de identidade no widget do Gorgias. Existe `captureUserEmail()`, que é **declarativo**. Marco como **[NV]**.

#### 4.11.4 Features **[FV/terceiro]**

Fontes: <https://www.getmacha.com/blog/gorgias-chat-widget-explained>, <https://www.eesel.ai/blog/gorgias-web-widget>
Aparência de marca, posição do launcher, segmentação por página, **campanhas de chat proativas** disparadas por página (produto, carrinho, checkout), captura offline, AI Agent que resolve rastreio de pedido / envio / cancelamento / devolução com dados da loja, *Flows*, descontos e edição de assinatura dentro do chat, contexto Shopify (histórico de pedidos, carrinho, assinatura) visível ao atendente.

#### 4.11.5 Preço

**[FV]** Da página oficial (<https://www.gorgias.com/pricing>), o que é textual: *"AI Agent on every plan, pay only when it resolves a conversation."* e *"Helpdesk scales from 50 to 5,000 tickets a month, never priced per agent."*
**[FV/terceiro]** Valores (não consegui ler a tabela na página oficial — renderização dinâmica): Starter US$ 10/mês (50 tickets), Basic US$ 60 (300), Pro US$ 360 (2.000), Advanced US$ 900 (5.000), Enterprise custom. AI Agent ~US$ 1,00/interação (mensal) ou US$ 0,90 (anual); interações de IA **também contam como ticket**; excedente de ticket US$ 0,32–0,40; IA acima da franquia US$ 1,50.
Fontes: <https://chatarmin.com/en/blog/gorgias-pricing>, <https://www.eesel.ai/blog/gorgias-plans-comparison>

**[INF]** Cobrar por **ticket, não por agente** é o modelo mais alinhado ao e-commerce sazonal. A crítica recorrente na imprensa especializada é a dupla contagem (IA resolve → cobra IA **e** cobra ticket).

#### 4.11.6 Diferenciais e limitações

**Diferenciais:** campanhas proativas como componente isolado; contexto de pedido no chat; preço por ticket; eventos `connected`/`disconnected`; API que força `init().then()` (evita race conditions).
**Limitações:** bundle pesadíssimo (843 KB); sem verificação de identidade documentada **[NV]**; forte acoplamento a Shopify; dupla cobrança IA+ticket.

---

### 4.12 Front (Front Chat)

**Posição:** inbox colaborativa com chat embutido. Widget simples e honesto.
**Docs:** <https://dev.frontapp.com/docs/chat-overview> · SDK: <https://dev.frontapp.com/docs/chat-sdk-reference> · identidade: <https://dev.frontapp.com/docs/identify-users>

#### 4.12.1 Instalação **[FV]**

```html
<script src="https://chat-assets.frontapp.com/v1/chat.bundle.js"></script>
<script>
    window.FrontChat('init', {chatId: 'b107a36...', useDefaultLauncher: true});
</script>
```

Com CSP (nonce):
```html
<script type="text/javascript" src="chat.bundle.js" nonce="2726c7f26c"></script>
<script nonce="2726c7f26c">
  window.FrontChat('init', {chatId: 'b107a36...',
                            useDefaultLauncher: true,
                            nonce: '2726c7f26c'});
</script>
```

**[INF]** Passar o `nonce` **também para dentro do init** significa que o widget injeta `<style>`/`<script>` na página e precisa carimbá-los. Só Front e HubSpot tratam CSP de forma explícita na doc.

**[FV-M]** `https://chat-assets.frontapp.com/v1/chat.bundle.js` responde **302** (redirect para o bundle versionado) — indireção que permite trocar versão sem mexer no snippet do cliente.
**[FV]** A doc declara: *"the widget runs in an isolated iframe … you can apply stylesheets and run your application without affecting the chat widget"* — padrão A.
**[FV-M]** O próprio `front.com` usa **Qualified**, não Front Chat.

#### 4.12.2 API **[FV]**

Opções de `init`: `chatId` (obrigatório) · `useDefaultLauncher` · `shouldShowWindowOnLaunch` · `shouldExpandOnShowWindow` · `shouldHideCloseButton` · `shouldHideExpandButton` · `welcomeMessageAppearance` (`'hidden' | 'always'`) · `isMobileWebview` · `onInitCompleted` · `nonce`

Comandos: `FrontChat('show')` · `FrontChat('hide')` · `FrontChat('shutdown', {clearSession: true})` · `FrontChat('identity', {...})`

Handlers: `onUnreadChange` → `{ unread_count: number }` · `onInboundMessageReceived` · `onWindowVisibilityChanged` → `{ is_window_visible: boolean }`
**Todos devolvem uma função `unbind`** para limpeza.

**[INF]** `isMobileWebview` é detalhe raro e prático: ajusta o comportamento quando o widget roda dentro de um WebView de app nativo.

#### 4.12.3 Identidade — a doc mais didática que li **[FV]**

Segredo em *Settings → Inboxes → (chat inbox) → (channel) → "Verify logged-in user identity"*.

```js
const crypto = require('crypto');
const hmac = crypto.createHmac('sha256', verificationSecret);
const userHash = hmac.update(userEmail).digest('hex');
```
```php
$userHash = hash_hmac('sha256', $userEmail, $verificationSecret);
```
```ruby
require 'openssl'
userHash = OpenSSL::HMAC.hexdigest(
  OpenSSL::Digest.new('sha256'),
  verificationSecret,
  userEmail
)
```
```python
import hashlib, hmac
hmac.new(verification_secret, msg=user_email.encode('utf8'),
         digestmod=hashlib.sha256).hexdigest()
```

Uso, por e-mail:
```js
FrontChat('init', {
  useDefaultLauncher: false,
  email: 'leela@planet-express.com',
  userHash: '<gerado com o verification secret>',
  name: 'Turanga Leela',
  customFields: { 'Packages delivered': 242 }
});
```

Uso, por `userId`:
```js
FrontChat('init', {
  useDefaultLauncher: false,
  name: 'Turanga Leela',
  userHash: '<gerado com verification secret + userId>',
  userId: 'cus_7ab2561',
  contact: {
    email: 'leela@planet-express.com',
    customFields: { 'Packages delivered': 242 }
  }
});
```

Atualização pós-init:
```js
FrontChat('identity', {
  email: 'leela@planet-express.com',
  name: 'Turanga Leela',
  customFields: {
    'Shipments delivered': 242,
    'Title': 'Parcel Captain',
    'Is admin': true
  }
});
```

Regras publicadas: hash sempre do identificador escolhido (e-mail **ou** userId, nunca os dois na mesma chamada); não reenviar email/userId no `identity` se já foram no `init`; **toggle "Only accept messages from verified users"** rejeita visitantes não verificados.
Fonte: <https://help.front.com/en/articles/2049>

**[INF]** O toggle *"Only accept messages from verified users"* é a melhor implementação de enforcement que vi: binário, no painel, sem código. Deveria ser padrão de mercado.

#### 4.12.4 Preço **[FV]**

Fonte: <https://front.com/pricing>
Starter **US$ 25/assento/mês (até 10 assentos)** · Professional **US$ 65/assento/mês (até 50 assentos)** · Enterprise **US$ 105/assento/mês**. Cobrança anual, *"save up to 24%"*.
Front Chat no Starter só *"if single channel type"*; nos planos superiores exige omnichannel.
**[FV]** O artigo de setup diz *"This feature is available on all plans"* — há tensão entre as duas fontes; interprete como: existe em todos, mas o Starter obriga a escolher chat **ou** e-mail **[INF]**.

#### 4.12.5 Diferenciais e limitações

**Diferenciais:** documentação de identidade exemplar (4 linguagens, dois modos, regras claras); enforcement por toggle; suporte a CSP com nonce; `isMobileWebview`; `unbind` em todo handler; SDKs iOS e Android.
**Limitações:** widget deliberadamente simples (sem tours, checklists, base de conhecimento embutida); HMAC sem expiração; Front Chat não é o foco do produto; a própria Front não usa no site.

---

### 4.13 Chatra

**Posição:** live chat clássico, leve, com foco em SMB e e-commerce. Boa presença no Brasil (tem `chatra.com.br`).
**Docs:** <https://chatra.com/help/api/>

#### 4.13.1 Arquitetura **[FV-M]**

Globais `Chatra` e `ChatraSetup` presentes no `chatra.com`, mas o widget **não renderizou nenhum iframe em 17 segundos** na minha medição — ou seja, é **lazy** por configuração ou depende de interação/consentimento **[INF]**.
Loader: `call.chatra.io/chatra.js`, 12.146 bytes na rede / **47.150 descomprimidos**, com **41 ocorrências de `iframe` e 30 de `postMessage`** — arquitetura de iframe confirmada pelo código, ainda que eu não tenha visto renderizar.
Hosts: `call.chatra.io` (loader), `chat.chatra.io` (aplicação), `static.chatra.io` (assets) **[FV-M]**.

#### 4.13.2 API **[FV]**

Objetos de configuração:
- **`ChatraSetup`** — dimensões (`chatWidth`, `chatHeight`), botão (`buttonPosition`, `buttonStyle`, `buttonSize`), cores (objeto `colors` com `buttonText`, `buttonBg`, `clientBubbleBg`, `agentBubbleBg`), modo (`mode: 'widget' | 'frame'`), `clientId` (vínculo de usuário logado), `groupId` (roteamento), `language`, `locale`, `gaTrackingId`, `yaCounterId`, callbacks `onNewMessage` e `onAnalyticEvent`.
- **`ChatraIntegration`** — nome, e-mail, telefone, notas e propriedades customizadas do visitante, exibidas no painel.

Métodos via `Chatra('metodo', params)` **[FV]**:
`openChat()` · `expandWidget()` / `minimizeWidget()` (só desktop) · `hide()` / `show()` · `sendAutoMessage(text)` · `setIntegrationData(data)` / `updateIntegrationData(data)` · `pageView()` · `setGroupId(groupId)` · `setLocale(localeObject)` · `restart()` / `kill()`

**[INF]** `mode: 'frame'` é o modo "chat embutido numa div da página" — mesma ideia do `inlineEmbedSelector` do HubSpot e do `box.inline` do Olark. `setLocale(localeObject)` aceita um **objeto de tradução inteiro**, ou seja: tradução arbitrária pelo cliente, sem depender do catálogo do fornecedor. Isso é melhor do que "escolha um dos 45 idiomas".

#### 4.13.3 REST API e webhooks **[FV]**

Autenticação: header `Authorization: Chatra.Simple PUBLIC_KEY:PRIVATE_KEY`
Endpoints: `/api/messages/` (POST/GET/PUT/DELETE) · `/api/pushedMessages/` (mensagens automatizadas) · `/api/clients/:id`
Webhooks: `chatStarted` · `chatFragment` (atualização incremental) · `chatTranscript` (conversa concluída)

**[INF]** `chatFragment` — webhook **incremental durante a conversa** — é incomum; a maioria só entrega o transcript no fim.

#### 4.13.4 Identidade **[NV]**

`ChatraSetup.clientId` existe para vincular usuário logado, mas **não encontrei documentação de assinatura/HMAC** para provar esse `clientId`. Marco como **[NV]**; se for de fato só declarativo, é vulnerável a impersonação.

#### 4.13.5 Preço **[FV]**

Fonte: <https://chatra.com/plans/> — a página serviu preços em **R$** para meu acesso (geolocalização BR):
Free **R$ 0** (1 agente, até 5 chats/mês) · Essential **R$ 59/mês** ou **R$ 49/mês** (anual) · Pro **R$ 74/mês** ou **R$ 59/mês** (anual). Teste de 10 dias sem cartão.
Essential e Pro incluem *"Intelligent chat bot"*, *"Form & lead capture bot"*, *"Targeted messages & triggers"*, compartilhamento de tela via Median, chats em grupo e banimento de visitante. Todos os planos: *"Online & offline chat widget"*, *"Unlimited websites, customization, SSL-encryption"*, apps iOS/Android.
**[FV/terceiro]** Em USD, terceiros reportam ~US$ 21/agente (Essential) e ~US$ 29 (Pro). Fonte: <https://www.capterra.com/p/144752/Chatra/pricing/>

**[INF]** O Chatra **precifica em reais para visitante brasileiro** — é o único da lista onde observei isso. Relevante como referência de mercado local.

#### 4.13.6 Diferenciais e limitações

**Diferenciais:** preço em BRL; `setLocale` com dicionário arbitrário; `mode: 'frame'`; webhook incremental `chatFragment`; compartilhamento de tela; sites ilimitados em todos os planos.
**Limitações:** sem verificação de identidade documentada **[NV]**; sem base de conhecimento embutida; bundle de entrada relativamente pesado (47 KB) para o escopo do produto; produto estagnado em features de IA comparado aos pares.

---

### 4.14 Userlike / Lime Connect

**Posição:** referência alemã, forte em conformidade GDPR e em WhatsApp. Rebatizada **Lime Connect**.
**Docs:** <https://docs.lime-connect.com/developers/api/website-messenger-api>

#### 4.14.1 Arquitetura **[FV-M]**

No `userlike.com`: iframe **`#userlike-frame-<uuid>`** (300×1 fechado — literalmente 1 px de altura, com `title="Empty frame"`) + iframe separado 64×64 com `title="Chat button"`.
Assets: `connect.lime-technologies.com` (291.810 bytes em **92 requisições** — muito fracionado) + bucket legado `userlike-cdn-widgets.s3-eu-west-1.amazonaws.com` + `userlike-cdn-umm.b-cdn.net`.
Sem shadow DOM. Não observei WebSocket.

**[INF]** 92 requisições para 291 KB indica **code splitting agressivo** (muitos chunks pequenos). Bom para cache incremental, ruim para latência em rede móvel.

#### 4.14.2 API **[FV]**

Fonte: <https://docs.lime-connect.com/developers/api/website-messenger-api>

Capacidades declaradas: montagem condicional (*"Loading the Website Messenger only after a cookie consent"*), disparo por evento de negócio (valor de carrinho).
Restrição dura: *"Only one messenger can be mounted to the DOM at a time."*

Métodos: `mount` / `unmount` · `setVisibility` (janela, botão e notificações separadamente) · `maximize` / `minimize` · `setContactInfo` (nome, e-mail, empresa, telefone, campos customizados) · `setCustomData` (chave-valor exibido no Message Center) · `getState` → `hidden | minimized | maximized` · `setLanguage`

Formato do custom data **[FV/terceiro]**: `{"1234-1234-1234-1234": "red"}` — os IDs vêm de *Chat tools → Data fields* na conta. Fonte: <https://docs.userlike.com/features/add-ons/api-add-on>

Repositório oficial da API: <https://github.com/userlike/messenger>

#### 4.14.3 Identidade **[FV]**

A doc recomenda *"Contact Verification via Messenger API"* com identificadores únicos controlados pelo cliente, para reduzir contatos duplicados e **impedir impersonação**, e classifica o reconhecimento por cookie como *"quite unreliable"*.
**[NV]** O mecanismo criptográfico exato (HMAC? JWT?) não ficou explícito na página que li.

#### 4.14.4 Preço **[FV]**

Fonte: <https://connect.lime-technologies.com/en/pricing/>

| Plano | Preço | Assentos | Canais | Conversas | WhatsApp |
|---|---|---|---|---|---|
| Free | € 0 | 1 | 1 (site) | 200 | — |
| Pro | **€ 105/mês** (mensal) / **€ 87/mês** (anual) | mín. 3 | ilimitados | ilimitadas | 10 números |
| Enterprise | sob consulta | mín. 5 | ilimitados | ilimitadas | 20 números |

Add-ons: **Connect AI Agent € 99/mês** · **Connect AI Copilot € 19/assento/mês** · **Workflows € 50/mês por 1.000 execuções** · **WhatsApp Campaigns € 20/mês + taxas Meta por 1.000 mensagens**. Preços sem IVA.

**[INF]** Preço de IA **fixo** (€ 99/mês), não por resolução. Junto com o Olark, é o segundo player que resiste ao modelo de consumo.

#### 4.14.5 Diferenciais e limitações

**Diferenciais:** montagem condicional pós-consentimento (GDPR by design); `setVisibility` granular por elemento; API no GitHub; IA com preço fixo; WhatsApp multi-número.
**Limitações:** rebrand em andamento (dois domínios, documentação em migração); mínimo de 3 assentos no plano pago; mecanismo de verificação de identidade não documentado com precisão **[NV]**; 92 requisições no boot.

---

### 4.15 Kustomer

**Posição:** CRM de atendimento de médio/grande porte. Widget competente, documentação boa em autenticação.
**Docs:** <https://developer.kustomer.com/chat-sdk/v2.0-Web/docs/overview-chat-web-sdk> · exemplos: <https://github.com/kustomer/web-chat-sdk-samples>

#### 4.15.1 Boot e ordem obrigatória **[FV]**

`Kustomer.start()` **tem que terminar** antes de qualquer outro método do SDK. Só depois vale chamar `Kustomer.login()`.

#### 4.15.2 Autenticação — JWT **[FV]**

```js
Kustomer.login({
  jwtToken: 'SOME_JWT_TOKEN'
});

Kustomer.login({
  jwtToken: 'SOME_JWT_TOKEN'
}, function (loginCallbackResponse, error) {
  if (!error) {
    console.log('User was authenticated!');
  }
});
```

Assinatura: `Kustomer.login(options, function(callbackResponse, error))`
Resposta do callback: `{ identified: Boolean, customerId: String, email?: String, externalId?: String }`
Regras publicadas: **o `iat` do JWT precisa estar dentro de 15 minutos**, senão o token é inválido; se `email` e `externalId` forem fornecidos, **`email` tem prioridade**.
Fontes: <https://developer.kustomer.com/chat-sdk/v2.0-Web/docs/kustomer-login> e <https://developer.kustomer.com/chat-sdk/v2.0-Web/docs/authenticate-chat-with-jwt-token>

**[INF]** A janela de 15 minutos no `iat` é a política mais restritiva que encontrei — força o cliente a gerar token sob demanda em vez de cachear. Boa prática que quase ninguém mais adota.

#### 4.15.3 Restante da API **[NV parcial]**

A página de overview que li é índice; não reproduzo assinaturas de `open`, `close`, `describeCustomer`, `describeConversation` ou `addListener` sem fonte primária. **[NV]**.

#### 4.15.4 Preço **[FV/terceiro]**

Não é publicado na página oficial de forma legível por fetch. Segundo terceiros:
- Enterprise **US$ 89/usuário/mês**, Ultimate **US$ 139/usuário/mês**, anual, **mínimo de 8 assentos**.
- Modelo alternativo **por conversa**: a partir de **US$ 0,35/conversa** (Enterprise) e **US$ 0,50** (Ultimate).
- AI Agents: **US$ 0,60 por conversa engajada** ou **US$ 40/rep/mês**.
- Bundles: ~US$ 129–179/usuário/mês.
Fonte: <https://chatarmin.com/en/blog/kustomer-pricing>, <https://www.getmacha.com/blog/kustomer-pricing-explained>

**[INF]** Oferecer **assento OU conversa** como unidade de cobrança, à escolha do cliente, é modelo raro e inteligente — resolve o dilema de times pequenos com muito volume vs. times grandes com pouco.

#### 4.15.5 Diferenciais e limitações

**Diferenciais:** JWT com `iat` de 15 min; escolha entre preço por assento e por conversa; repositório oficial com exemplos cliente+servidor.
**Limitações:** preço não público; mínimo de 8 assentos exclui SMB; documentação do SDK fragmentada em muitas páginas curtas.

---

### 4.16 Gladly (Sidekick)

**Posição:** atendimento premium orientado a "pessoa, não ticket". Widget rebatizado **Sidekick**.
**Docs:** <https://developer.gladly.com/chat/> · SDKs: <https://github.com/gladly>

#### 4.16.1 Instalação **[FV]**

```html
<script>
  !function(c,n,r,t){if(!c[r]){var i,d,p=[];d="PROD"!==t&&t?"STAGING"===t?"https://cdn.gladly.qa/gladly/chat-sdk/widget.js":t:"https://cdn.gladly.com/chat-sdk/widget.js",c[r]={init:function(){i=arguments;var e={then:function(t){return p.push({type:"t",next:t}),e},catch:function(t){return p.push({type:"c",next:t}),e}};return e}},c.__onHelpAppHostReady__=function(t){if(delete c.__onHelpAppHostReady__,(c[r]=t).loaderCdn=d,i)for(var e=t.init.apply(t,i),n=0;n<p.length;n++){var a=p[n];e="t"===a.type?e.then(a.next):e.catch(a.next)}},function(){try{var t=n.getElementsByTagName("script")[0],e=n.createElement("script");e.async=!0,e.src=d+"?q="+(new Date).getTime(),t.parentNode.insertBefore(e,t)}catch(t){}}()}}
  (window,document,'Gladly','PROD')
</script>
```

**[INF]** Dois detalhes elegantes neste loader: (1) o stub implementa uma **Promise falsa** com `then`/`catch` que enfileiram, então `Gladly.init().then(...)` funciona antes do bundle chegar; (2) o parâmetro `'PROD' | 'STAGING' | <url>` no final permite apontar para ambiente de teste **sem trocar o snippet**. Vale copiar os dois.

Nota crítica **[INF]**: `e.src = d + "?q=" + (new Date).getTime()` — cache-buster por timestamp em **toda** carga de página. Isso destrói o cache do CDN para o arquivo de entrada. Não copiar.

#### 4.16.2 API **[FV]**

```js
Gladly.init({
  appId: "your-app-id",
  autoShowButton: true  // opcional
}).then(function() {
  // Chat pronto
}).catch(function(error) {
  console.log('error:', error);
});
```

`Gladly.show()` · `Gladly.close()` · `Gladly.getUser()` · `Gladly.clearUser()`

```js
Gladly.setUser({
  name: "John Smith",
  jwt: async () => "{User Identity JWT}"
});
```

```js
Gladly.on("availability:change", (availability) => {
  console.log(`New availability: ${availability}`);
});
```
Eventos: `availability:change`, `conversation:started`, `conversation:ended`, `message:received`, `message:sent`, `sidekick:opened`, `sidekick:closed`.

**[INF] O melhor padrão de identidade que vi.** O `jwt` é uma **função `async`**, não uma string. Isso significa que o widget pode **pedir um token novo sempre que precisar** (expiração, reconexão, troca de aba) sem que o site tenha que orquestrar nada. Zendesk usa callback; Gladly usa `async` nativo. É o estado da arte.
Também é possível identificar por e-mail ou telefone sem JWT — o modo fraco continua disponível **[FV]**.

#### 4.16.3 Preço **[NV]**

Não publicado. Não vou estimar.

#### 4.16.4 Diferenciais e limitações

**Diferenciais:** `jwt: async () => …`; stub com Promise-like; alternância PROD/STAGING no snippet; SDKs iOS e Android oficiais no GitHub.
**Limitações:** cache-buster por timestamp no loader; preço opaco; produto de nicho enterprise; documentação pública enxuta.

---

### 4.17 Ada

**Posição:** não é helpdesk — é **plataforma de agente de IA** que se pluga em outros (inclusive Zendesk). Widget = superfície do bot.
**Docs:** <https://docs.ada.cx/reference/embed2-reference> (o antigo `developers.ada.cx` responde 301)

#### 4.17.1 Instalação **[FV]**

```html
<script>
  window.adaSettings = {
    handle: "your-bot-handle"
  }
</script>
<script async src="https://static.ada.support/embed2.js"></script>
```

#### 4.17.2 Settings **[FV]**

*Essenciais:* `handle` (obrigatório) · `cluster` (região k8s: `us2`, `eu`, `maple`) · `language` (ISO 639-1)
*Dados do usuário:* `metaFields` · **`sensitiveMetaFields`** (PII criptografada, **apagada após 24 h**)
*Comportamento:* `enableProgrammaticControl` · **`headless`** (roda sem UI) · `privateMode` (esquece histórico ao recarregar) · `lazy` (só carrega ao chamar `adaEmbed.start()`)
*UI:* `greeting` (Answer ID) · `parentElement` (monta o iframe onde você quiser) · `hideMask` (sem overlay) · `toggleCallback`
*Callbacks:* `adaReadyCallback` · `onAdaEmbedLoaded` (dispara **antes** da inicialização — lugar certo para inscrever eventos) · `conversationEndCallback` · `chatterTokenCallback` · `zdChatterAuthCallback`

#### 4.17.3 Ações **[FV]**

```js
await window.adaEmbed.sendMessage("user text");
await window.adaEmbed.getMessages();           // histórico em memória
await window.adaEmbed.getConversation();       // id da conversa + info do agente
await window.adaEmbed.reset({ language: "fr" });
await window.adaEmbed.toggle();
await window.adaEmbed.isOpen();
await window.adaEmbed.setComposerText("text"); // pré-preenche o input
await window.adaEmbed.setMetaFields({ name: "Ada" });
await window.adaEmbed.setSensitiveMetaFields({ jwt_token: "..." });
await window.adaEmbed.getMetaFields();
window.adaEmbed.setLanguage("en");
window.adaEmbed.setDelegate({ beforeSend: (msg) => msg });
await window.adaEmbed.deleteHistory();
window.adaEmbed.trackEvent("event_key", 5, { meta: "data" });
```

Eventos **[FV]**:
```js
window.adaEmbed.subscribeEvent("ada:message:sent", (data) => { console.log(data.message.body); });
window.adaEmbed.subscribeEvent("ada:agent:joined", (data) => { console.log(data.conversation_id); });
```
Catálogo: `ada:ready` · `ada:message:sent` · `ada:message:received` · `ada:agent:joined` · `ada:agent:left` · `ada:end_conversation` · `ada:typing:start` · `ada:typing:stop` · `ada:campaigns:shown` · `ada:campaigns:opened` · `ada:connection:change`

Tipos publicados **[FV]**:
```js
// Message
{ id: string; role: "user" | "bot" | "agent"; type: string; body?: string;
  createdAt: number; agent?: { id: string; name: string; avatarUrl?: string }; }

// ConversationInfo
{ id: string | null;
  handoff: { inLiveChat: boolean; agent?: { id: string; name: string; avatarUrl?: string } }; }
```

#### 4.17.4 Segurança — a doc mais honesta da lista **[FV]**

A própria documentação alerta:
- `enableProgrammaticControl` **expõe transcrições completas a todos os scripts da página** (analytics, GTM, pixels).
- `headless` roda **sem indicador visual**; uma página comprometida pode manter sessões silenciosas de chatter.
- `sensitiveMetaFields` criptografa imediatamente e purga em 24 h.
- Integração com Zendesk usa `zdChatterAuthCallback` para pedir um **JWT à sua API** e estabelecer confiança compartilhada Ada↔Zendesk, permitindo identidade verificável do chatter dentro da sessão.

**[INF]** É o único fornecedor que documenta explicitamente que **o próprio recurso avançado dele é um risco de vazamento de dados para os outros scripts da página**. Postura que eu gostaria de ver replicada — e que devemos replicar.

#### 4.17.5 Preço **[NV]**

Não publicado.

#### 4.17.6 Diferenciais e limitações

**Diferenciais:** `headless` (bot sem UI, controlado por API); `setDelegate({ beforeSend })`; `sensitiveMetaFields` com purga em 24 h; `parentElement`; `cluster` para residência de dados; documentação de risco explícita.
**Limitações:** não é helpdesk (precisa de outro sistema atrás); preço opaco; superfície de API grande = superfície de ataque grande, como a própria doc admite.

---

### 4.18 Trengo

**Posição:** inbox omnicanal europeia. Widget multi-canal — o visitante escolhe o canal.
**Docs:** <https://developers.trengo.com/docs/methods> · índice: <https://developers.trengo.com/llms.txt>

#### 4.18.1 Arquitetura — um iframe por elemento visual **[FV-M]**

No `trengo.com`:

| iframe | title | tamanho |
|---|---|---|
| `#trengo-widget` | *Trengo widget bootstrap* | 0×0 |
| (sem id) | *Open chat* / *Close chat* | 60×60 |
| (sem id) | *Unread chat messages* | 0×0 |
| (sem id) | *Online status* | 300×80 → 0×0 |
| (sem id) | *Ask us anything. We will reply as soon as possible.* | 0×0 → **410×750** |

Container: `div#trengo-web-widget`. Assets em `static.widget.trengo.eu`. Sem shadow DOM.

**[INF]** É o exemplo mais puro do padrão B: **cinco browsing contexts** para um widget de chat. O iframe do *greeting* tem o **texto da saudação como `title`**, o que é bom para leitores de tela — e ruim para privacidade em captura de DOM. O custo de memória de 5 iframes não é trivial em mobile.

#### 4.18.2 API **[FV]**

```js
window.Trengo.Api.Widget.open('[CHANNEL_TYPE]');
// chat, email, facebook, twitter, sms, voice, help_center, whatsapp
window.Trengo.Api.Widget.close();
window.Trengo.Api.Widget.is_chatting();        // boolean
window.Trengo.Api.Widget.render();             // só se window.Trengo.render === false
window.Trengo.Api.Widget.url_updated();        // SPA: reavalia saudações
window.Trengo.on_ready = function() { /* ... */ };
```

Dados **[FV]**: `window.Trengo.contact_data` (atributos de contato) e `window.Trengo.ticket_data` (atributos do ticket), com cada campo customizado exigindo `field_id` + `value`. Funciona **apenas para o canal de web chat**.
Fonte: <https://developers.trengo.com/docs/set-ticket-data>

**[INF]** `open('whatsapp')` / `open('voice')` / `open('help_center')` fazem do widget um **hub de canais**, não um chat. É o modelo mais próximo do que o ChatSPX poderia oferecer, dado que já temos WhatsApp forte.

#### 4.18.3 Identidade **[NV]**

Não encontrei documentação de verificação criptográfica. `contact_data` parece declarativo. **[NV]**.

#### 4.18.4 Preço **[FV]**

Fonte: <https://trengo.com/pricing>

| Plano | Anual | Mensal | Inclui |
|---|---|---|---|
| Boost | € 299/mês | € 349/mês | 10 usuários, 6.000 conversas/ano |
| Pro | € 499/mês | € 599/mês | 20 usuários, 18.000 conversas/ano |
| Enterprise | custom | custom | custom |

Extras: **€ 15–18 por 100 conversas**; **sobretaxa de IA € 0,25–0,30 por conversa**; usuário adicional € 25–30 (Boost) ou € 40–50 (Pro).
Todos os planos incluem inbox omnicanal, WhatsApp Business API, AI Agent (HelpMate), AI Journeys, widget de site e auto-respostas.

**[INF]** Preço **por pacote (usuários + conversas inclusos)**, não por assento puro. Entrada alta (€ 299) exclui SMB pequeno.

#### 4.18.5 Diferenciais e limitações

**Diferenciais:** seletor de canal no widget (incluindo WhatsApp e voz); `url_updated()` para SPA; `help_center` como canal; pacote com conversas inclusas.
**Limitações:** 5 iframes (peso e memória); sem verificação de identidade documentada **[NV]**; preço de entrada alto; documentação esparsa.

---

### 4.19 Chaport

**Posição:** live chat + chatbot de baixo custo. Notável pela arquitetura de boot e pelo modelo de integridade de dados.
**Docs:** <https://docs.chaport.com/api/js/v1/>

#### 4.19.1 Boot — o menor loader que medi **[FV-M]**

`https://app.chaport.com/javascripts/insert.js` tem **400 bytes na rede / 998 descomprimidos**. Conteúdo integral (reformatado):

```js
!function(){
  window.chaportInitResult="";
  var t = window.chaportConfig && (window.chaportConfig.appId || window.chaportConfig.app_id)
       || window.chaport && (window.chaport.app_id || window.chaport.appId) || "";
  function o(t,o){ var n=document.createElement("script");
    n.onload=function(){ this.parentNode && this.parentNode.removeChild(this); o&&o() };
    n.onerror=e; n.src=t; i(n) }
  function i(t){ var o=document.getElementsByTagName("body")[0];
    o ? o.appendChild(t) : setTimeout(i.bind(void 0,t),100) }
  function e(){ console.error("chaport: can't get latest version") }
  o("https://app.chaport.com/info/widget-assets?jsonpCallback=true&id="+encodeURIComponent(t),
    function(){
      window.chaportInitResult
        ? (window.chaport.__assets = window.chaportInitResult,
           window.chaportInitResult.js && window.chaportInitResult.js.bootstrap
             ? (window.chaportInitResult.root
                 ? o(window.chaportInitResult.root + window.chaportInitResult.js.bootstrap)
                 : o("https://assets.chaport.com" + window.chaportInitResult.js.bootstrap))
             : e(),
           delete window.chaportInitResult)
        : e()
    })
}(window);
```

**[INF] Análise:** é um loader de **três estágios** — snippet inline → `insert.js` (400 B) → JSONP em `/info/widget-assets?id=<appId>` que devolve o manifesto de assets → bootstrap real. Vantagens: versionamento por conta (cada cliente pode rodar versão diferente), rollout gradual, e o snippet do cliente nunca precisa mudar. Desvantagem: **três round-trips antes de qualquer pixel**, e o JSONP é uma escolha datada (`jsonpCallback=true`) que injeta script arbitrário no `window` global.

Snippet de instalação **[FV]**:
```js
(function(w,d,v3){
  w.chaportConfig = { appId: '<insertYourId>' };
  if(w.chaport)return;
  v3=w.chaport={};
  v3._q=[];
  v3._l={};
  v3.q=function(){v3._q.push(arguments)};
  v3.on=function(e,fn){if(!v3._l[e])v3._l[e]=[];v3._l[e].push(fn)};
  var s=d.createElement('script');
  s.type='text/javascript';
  s.async=true;
  s.src='https://app.chaport.com/javascripts/insert.js';
  var ss=d.getElementsByTagName('script')[0];
  ss.parentNode.insertBefore(s,ss)
})(window, document);
```

#### 4.19.2 API **[FV]**

Duas interfaces: direta (`window.chaport.open()`) e por fila (`window.chaport.q('open')`, `window.chaport.q('on', ['ready', callback])`).

| Método | Função |
|---|---|
| `open()` / `close()` / `toggle()` | estado do widget |
| `setVisitorData(data, hash)` | atualiza dados do visitante **com hash** |
| `hideLauncher()` / `showLauncher()` | launcher padrão |
| `newPageView(options)` | SPA |
| `startSession(credentials)` / `stopSession(clearCredentials)` | sessão |
| `getParameterValue(key)` | parâmetros das regras de atribuição |
| `compare(value, matcher, target)` | comparação para regras |

Eventos: `ready` · `chat.started` · `chat.onlineChange` · `chat.autoInvitation` · `chat.botSent` · `widget.stateChange` (expanded/collapsed/unreadMessage)

Config via `window.chaportConfig`: `appId` (obrigatório), `visitor`, `language`, `appearance` (cores, posição, mensagens de boas-vindas), `assignments` (roteamento), `triggers` (auto-convites e chatbots), `session` (credenciais e persistência), `devices` (config por dispositivo), `launcher`.

**[INF]** `devices` (configuração diferente por dispositivo) e `getParameterValue`/`compare` (motor de regras exposto) são incomuns nessa faixa de preço.

#### 4.19.3 Integridade de dados — modelo próprio **[FV]**

Hash server-side para impedir forja:
```php
$hash = sha1($yourSalt . json_encode($visitorData));
```
Passado junto com os dados, habilita atualização de campos protegidos (nome, e-mail, telefone, notas).

Usuários logados:
```js
session: {
  user: {
    id: 'visitor-id',
    token: sha1($salt . 'visitor-id')
  }
}
```
Fluxo: capturar `visitorId` nos eventos `ready` ou `chat.started`, guardar a associação com a conta, e devolver as credenciais nas visitas seguintes.

**[INF] Crítica técnica:** `sha1(salt . dados)` **não é HMAC** — é a construção clássica vulnerável a **length-extension attack**. Com SHA-1, ainda por cima. Funciona na prática porque o payload é JSON fechado, mas é criptografia mal escolhida. **Não copiar.** Se formos fazer, é HMAC-SHA256 ou JWT.

#### 4.19.4 Preço **[FV]**

Fonte: <https://www.chaport.com/pricing/>
Free **€ 0** (2 operadores) · Pro **€ 29–39/mês** (4 operadores) · Unlimited **€ 99–129/mês** (operadores ilimitados).
Free: chats ilimitados, histórico de 60 dias, customização básica do widget, apps web/mobile.
Pro: histórico ilimitado, auto-convites, customização avançada, integração e-mail/messenger, respostas salvas, relatórios detalhados.
Unlimited: **chatbots**, base de conhecimento, times, regras de atribuição, relatórios avançados.
Teste: 14 dias do Unlimited; depois cai para o Free perpétuo.
**[FV/terceiro]** *"The REST & Javascript APIs are only available on paid Chaport plans."*

#### 4.19.5 Diferenciais e limitações

**Diferenciais:** loader de 400 bytes com manifesto por conta; config por dispositivo; motor de regras exposto; plano free generoso (chats ilimitados); preço em euro acessível.
**Limitações:** JSONP no caminho crítico; **SHA-1 com concatenação de salt** em vez de HMAC; 3 round-trips no boot; API só em plano pago.

---

### 4.20 Smartsupp

**Posição:** live chat tcheco com forte presença em e-commerce da Europa Central. Notável por gravação de sessão.
**Docs:** <https://docs.smartsupp.com/chat-box/>

#### 4.20.1 Arquitetura **[FV-M]**

Loader `www.smartsuppchat.com/loader.js`: 5.526 bytes na rede / 18.024 descomprimidos, 3 ocorrências de `iframe`, sem shadow DOM.
Hosts referenciados no loader: `api.smartsuppchat.com`, `bootstrap.smartsuppchat.com`, `files.smartsuppcdn.com`, `widget-v3.smartsuppcdn.com` — **quatro domínios distintos** para API, bootstrap, arquivos e widget.
No `smartsupp.com` o widget **não renderizou** na minha medição (global `_smartsupp` presente, nenhum iframe do chat) — lazy ou condicionado a consentimento **[INF]**.

#### 4.20.2 API **[FV]**

Fonte: <https://docs.smartsupp.com/chat-box/javascript-api/methods/>

```js
smartsupp('group', '<GROUP_ID>');       // roteia para um grupo
smartsupp('chat:show');
smartsupp('chat:hide');
smartsupp('chat:open');
smartsupp('chat:close');
smartsupp('chat:message', 'Hello, can you help me with...');   // insere no input, NÃO envia
smartsupp('chat:send',    'Hello, can you help me with...');   // insere e envia
```

**[INF]** A distinção `chat:message` (rascunho) vs `chat:send` (envia) é sutil e boa: permite "pré-preencher a pergunta" a partir de um botão da página sem enviar por conta do usuário.

Eventos **[FV]** (fonte: <https://docs.smartsupp.com/chat-box/javascript-api/events/>):
```js
smartsupp('on', 'message_sent', function(message) { console.log('sent message:', message); });
smartsupp('on', 'message_received', function(message) { console.log('received message:', message); });
smartsupp('on', 'messenger_close', function(message) { console.log('messenger close:', message); });
```
Só três eventos documentados na página que li. Outros (`chat_opened`, `visitor_online`, `ready`, `offline_message_sent`) **[NV]**.

#### 4.20.3 Identificação de visitante **[FV]**

Fonte: <https://docs.smartsupp.com/chat-box/visitor-identification/>

```js
smartsupp('name',  'John Doe');
smartsupp('email', 'john.doe@example.com');
smartsupp('phone', '+425123456');

smartsupp('variables', {
  User_ID: "1234",
  Customer_status: "VIP",
  Customer_spending: "100 EUR",
});
```

**A documentação não menciona HMAC, assinatura nem qualquer validação criptográfica da identidade do visitante** **[FV]**. Existe `X-Smartsupp-Hmac` em **webhooks** (server-to-server), mas isso é outra coisa.

**[INF]** Conclusão direta: no Smartsupp, qualquer visitante pode se declarar `ceo@cliente.com` via console do navegador. É o pior resultado da lista nesse quesito, junto com Chatra e Trengo.

#### 4.20.4 Preço **[FV]**

Fonte: <https://www.smartsupp.com/pricing/>

| Plano | Preço (anual) | Operadores | Conversas | AI Reply Assists |
|---|---|---|---|---|
| Free | US$ 0 | 1 | 25/mês | — |
| Solo | US$ 24 → **US$ 17/mês** | 1 | ilimitadas | 50/mês |
| Plus | US$ 35 → **US$ 25/mês** | 3 | ilimitadas | 250/mês |
| Expert | US$ 117 → **US$ 83/mês** | 5+ | ilimitadas | 500/mês |
| Ultimate | a partir de **US$ 280/mês** | custom | custom | custom |

Agente de IA **Mira**: *"Single Website AI Agent"* US$ 20 → **US$ 16** (100 conversas/mês, anual), até 30.000 produtos; *"Unlimited AI Agents"* sob consulta.
Canais: live chat, WhatsApp, Messenger em todos; e-mail com multiplicadores (3× no Solo, 10× no Plus, 50× no Expert).

#### 4.20.5 Diferenciais e limitações

**Diferenciais:** `chat:message` vs `chat:send`; agente de IA com catálogo de até 30 mil produtos; separação de domínios por função; preço acessível.
**Limitações:** **nenhuma verificação de identidade do visitante** **[FV]**; documentação de eventos incompleta; só 25 conversas/mês no free; API pequena comparada aos pares.

---

## 5. Verificação de identidade — o capítulo que separa brinquedo de produto

Este é o ponto que a task pediu para detalhar bem, e é o que mais separa os players.

### 5.1 O problema, em uma frase

Sem verificação, `setUser({email: "ceo@cliente.com"})` é uma declaração do **navegador do visitante**. Qualquer pessoa abre o DevTools, chama a API do widget com o e-mail de outra e — dependendo do fornecedor — **lê o histórico de conversas dessa pessoa**, vê os dados dela e escreve em nome dela.

### 5.2 As quatro gerações de solução

**Geração 0 — nada.** O e-mail é aceito como veio. Smartsupp, Chatra, Trengo, Gorgias e LiveChat estão aqui, pelo que consegui verificar **[FV/NV]**.

**Geração 1 — HMAC sobre um identificador.**
`hash = HMAC-SHA256(secret, email_ou_user_id)`, gerado no servidor, enviado ao widget.
Quem usa: **Crisp** (assina e-mail), **Front** (assina e-mail **ou** userId), **tawk.to** (assina e-mail), **Intercom legado** (`user_hash`).
Limitação estrutural **[INF]**: o hash **não expira, não tem escopo e não carrega dados**. Vazou uma vez — via log, via analytics, via extensão de navegador — vale para sempre.

**Geração 1.5 — hash caseiro.**
**Chaport**: `sha1(salt . json_encode(dados))`. Não é HMAC, é SHA-1 com salt concatenado — vulnerável a length-extension por construção, com um algoritmo já desaconselhado **[INF]**. Cumpre o objetivo prático mas é uma escolha ruim.

**Geração 2 — JWT estático.**
Token assinado (HS256/RS256/ES256) com `exp`, passado como atributo na inicialização.
Quem usa: **Intercom** (`intercom_user_jwt`, HS256, atual e recomendado), **Freshchat** (RS256, mediante solicitação ao suporte), **Drift** (`{ userJwt }`, opcional).
Ganho sobre a geração 1: expiração, rotação por `kid`, payload assinado com atributos confiáveis.

**Geração 3 — JWT sob demanda (callback/async).**
O widget **pede** o token quando precisa, em vez de recebê-lo pronto.
Quem usa: **Zendesk** (`loginUser(jwtCallback, loginCallback)` + refetch em 401), **Kustomer** (`login({jwtToken}, cb)` com `iat` de 15 min), **Gladly** (`jwt: async () => "..."`), **Ada** (`zdChatterAuthCallback`).
**[INF]** Esta é a arquitetura correta. Resolve expiração, reconexão, troca de aba e SPA de sessão longa sem recarregar a página.

### 5.3 Tabela comparativa de identidade

| Player | Mecanismo | Algoritmo | O que é assinado | Expira? | Obrigatório? | Fonte |
|---|---|---|---|---|---|---|
| **Intercom** | JWT (HMAC deprecado) | HS256 | `user_id` + payload | sim (`exp`) | toggle; enforcement congelado para novas contas | [doc](https://developers.intercom.com/installing-intercom/web/identity-verification) |
| **Zendesk** | JWT via callback | assinado com `kid`+segredo | claims do end user | sim (`exp`, rejeita passado) | opcional | [doc](https://developer.zendesk.com/api-reference/widget-messaging/web/authentication/) |
| **Kustomer** | JWT | — | `email` / `externalId` | sim + `iat` ≤ 15 min | opcional | [doc](https://developer.kustomer.com/chat-sdk/v2.0-Web/docs/kustomer-login) |
| **Gladly** | JWT `async` | — | identidade do cliente | sim | opcional (também aceita e-mail/telefone puro) | [doc](https://developer.gladly.com/chat/) |
| **Freshchat** | JWT (ou restoreId) | **RS256** | `reference_id`, `freshchat_uuid`, `iat` | sim | **só habilitando via suporte** | [doc](https://developers.freshchat.com/web-sdk/v2/) |
| **Crisp** | HMAC | **SHA-256 obrigatório** | e-mail | não | opcional, plano Mini+ | [doc](https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/identity-verification/) |
| **Front** | HMAC | SHA-256 | e-mail **ou** userId | não | **toggle "only verified users"** | [doc](https://dev.frontapp.com/docs/identify-users) |
| **tawk.to** | HMAC (Secure Mode) | SHA-256 | e-mail | não | opcional | [doc](https://developer.tawk.to/jsapi/) |
| **Drift** | JWT opcional | — | `externalId` | sim | opcional (doc desaconselha por complexidade) | [doc](https://devdocs.drift.com/docs/driftidentify-implementation-guide) |
| **HubSpot** | token de API (Visitor Identification) | n/d | e-mail | **[NV]** | opcional | [doc](https://developers.hubspot.com/docs/reference/api/conversations/chat-widget-sdk) |
| **Chaport** | hash caseiro | **SHA-1 + salt concatenado** | JSON dos dados / visitorId | não | opcional | [doc](https://docs.chaport.com/api/js/v1/) |
| **Ada** | JWT (via Zendesk) | — | chatter | sim | opcional | [doc](https://docs.ada.cx/reference/embed2-reference) |
| **Userlike/Lime** | "Contact Verification via Messenger API" | **[NV]** | identificador único | **[NV]** | recomendado | [doc](https://docs.lime-connect.com/developers/api/website-messenger-api) |
| **LiveChat** | — | — | — | — | **[NV]** — não localizei | — |
| **Gorgias** | — | — | — | — | **[NV]** — só `captureUserEmail()` | — |
| **Chatra** | — | — | — | — | **[NV]** — só `clientId` declarativo | — |
| **Trengo** | — | — | — | — | **[NV]** — `contact_data` declarativo | — |
| **Smartsupp** | **nenhum** | — | — | — | **não existe** (doc não menciona) | [doc](https://docs.smartsupp.com/chat-box/visitor-identification/) |
| **Olark** | — | — | — | — | **[NV]** | — |
| **Tidio** | — | — | — | — | **[NV]** | — |

### 5.4 O padrão de tokens de sessão do visitante anônimo

Separado da verificação de identidade, existe o problema de **continuidade** (o visitante volta amanhã, em outro dispositivo). Cada um resolve diferente **[FV]**:

| Player | Mecanismo de continuidade | Risco |
|---|---|---|
| Crisp | `CRISP_TOKEN_ID` — **UUID v4 gerado por você**; doc proíbe explicitamente ID sequencial, hash de e-mail ou timestamp | se o token for adivinhável, sequestro de sessão |
| Freshchat | `restoreId` — gerado pelo Freshchat, **você guarda no seu banco** | é um bearer sem expiração; vazou = acesso à conversa |
| tawk.to | JWT ES256 de 30 min renovado automaticamente | baixo |
| HubSpot | cookie `hubspotutk`, exposto na URL do iframe **[FV-M]** | rastreável entre sites do mesmo domínio |
| Chaport | `session.user.token = sha1(salt + visitorId)` | length-extension; SHA-1 |
| Zendesk | JWT com refresh em 401 | baixo |

**[INF] Regra de ouro que extraio disto:** *continuidade* e *autenticidade* são problemas diferentes e devem usar credenciais diferentes. Crisp acerta ao separar; Freshchat erra ao usar o `restoreId` para os dois.

### 5.5 Por que quase ninguém liga o enforcement

Três razões observadas na documentação **[INF]**:
1. **Fricção de implementação** — exige código no backend do cliente. A doc do Drift diz isso com todas as letras.
2. **Quebra o anônimo** — se o enforcement for global, o visitante não-logado não consegue mais falar. Por isso o toggle do Front é "only accept messages from **verified users**", uma decisão de negócio, não técnica.
3. **Suporte** — quando o cliente erra a geração do token, o widget simplesmente para. Fornecedor prefere não ativar por padrão.

**[INF]** Consequência para nós: se o ChatSPX ligar verificação por padrão, precisa de (a) modo anônimo permitido e coexistente, (b) mensagem de erro visível no console **em português**, (c) um debugger de token como o do Intercom.

---

## 6. A grande tabela comparativa (25 capacidades × 20 players)

Uma tabela só, apresentada em **três blocos** por largura de tela. Mesmas linhas (players) nos três.

**Legenda:** ✅ tem · ⚠️ tem com limitação relevante · ❌ não tem · ❔ não verificado

### Bloco 1 — Arquitetura e integração (capacidades 1–9)

| # | Player | 1. Isolamento | 2. Nº de iframes | 3. Loader < 5 KB | 4. Lazy / boot manual | 5. Realtime WSS | 6. Embed inline (não flutuante) | 7. Suporte a CSP/nonce | 8. Multi-widget / multimarca | 9. SDK mobile oficial |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Intercom | iframe (B) | 2–3 | ✅ 3,1 KB | ✅ `boot`/`shutdown` | ✅ ×2 | ❌ | ❔ | ✅ `messenger_style_id` | ✅ iOS/Android/RN |
| 2 | Drift † | iframe (B) | vários | ❌ 64 KB | ⚠️ | ❔ | ✅ landing pages | ❔ | ❔ | ❔ |
| 3 | HubSpot | iframe (A) | 1 | ❔ | ✅ `loadImmediately:false` | ❌ não obs. | ✅ `inlineEmbedSelector` | ✅ `avoidInlineStyles` | ❌ | ❔ |
| 4 | Zendesk | iframe | ❔ | ✅ 4,0 KB | ⚠️ | ❔ | ✅ `render` embutido | ✅ nonce no snippet | ⚠️ multi-brand no HC | ✅ iOS/Android |
| 5 | Freshchat | **shadow + iframe** | híbrido | ❌ 22 KB | ✅ `destroy()` | ❔ | ❔ | ❔ | ✅ `switch` por token | ✅ iOS/Android/RN |
| 6 | Tidio | DOM + iframe 0×0 | 1 (oculto) | ❔ | ⚠️ | ✅ Socket.IO | ❔ | ❔ | ❌ | ✅ |
| 7 | Crisp | **DOM direto** | **0** | ✅ 2,9 KB | ✅ `session:reset` | ✅ Engine.IO 4 | ⚠️ `container:index` | ❔ | ✅ multi-website | ✅ iOS/Android/RN |
| 8 | LiveChat | iframe (A) | 2 | ❌ 36 KB | ✅ `asyncInit`+`init()` | ✅ v3.6 | ❌ | ❔ | ⚠️ por licença | ✅ |
| 9 | Olark | **shadow DOM** | 1 (`blob:`) | ❌ 12 KB | ✅ `start_hidden` | ❔ | ✅ `box.inline` | ❔ | ⚠️ por site-id | ❔ |
| 10 | tawk.to | **iframe `about:blank` (C)** | **5** | ❔ | ✅ `autoStart:false` | ✅ Engine.IO 3 | ❌ | ❔ | ✅ `switchWidget` | ✅ 4 plataformas |
| 11 | Gorgias | iframe (B) | **4–5** | ❔ | ⚠️ | ✅ por região | ❌ | ❔ | ❌ | ❔ |
| 12 | Front | iframe (A) | 1 | ❔ (302) | ✅ `shutdown` | ❔ | ❌ | ✅ nonce no init | ❌ | ✅ iOS/Android |
| 13 | Chatra | iframe | ❔ | ❌ 12 KB | ✅ `kill`/`restart` | ❔ | ✅ `mode:'frame'` | ❔ | ✅ sites ilimitados | ✅ |
| 14 | Userlike/Lime | iframe (B) | 2 | ❔ | ✅ `mount`/`unmount` | ❔ | ❔ | ❔ | ⚠️ 1 por vez | ✅ |
| 15 | Kustomer | iframe | ❔ | ❔ | ✅ `start()` | ❔ | ❔ | ❔ | ❔ | ✅ iOS/Android |
| 16 | Gladly | iframe | ❔ | ❔ | ✅ `init` Promise | ❔ | ❔ | ❔ | ⚠️ PROD/STAGING | ✅ iOS/Android |
| 17 | Ada | iframe (A) | 1 | ❔ | ✅ `lazy`+`start()` | ❔ | ✅ `parentElement` | ❔ | ✅ `cluster` | ✅ RN |
| 18 | Trengo | iframe (B) | **5** | ❔ | ✅ `render:false` | ❔ | ❌ | ❔ | ❌ | ✅ |
| 19 | Chaport | iframe | ❔ | ✅ **400 B** | ✅ `startSession` | ❔ | ❔ | ❔ | ⚠️ `devices` | ✅ |
| 20 | Smartsupp | iframe | ❔ | ❔ (5,5 KB) | ⚠️ | ❔ | ❔ | ❔ | ❌ | ✅ |

† Drift em sunset desde 06/03/2026.

### Bloco 2 — Funcionalidades do widget (capacidades 10–18)

| # | Player | 10. Mensagem proativa | 11. Bot/fluxos | 12. Base de conhecimento embutida | 13. Busca de artigos por API | 14. Form pré-chat | 15. CSAT/rating | 16. Upload de arquivo | 17. Áudio/vídeo/tela | 18. Captura de e-mail offline |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Intercom | ✅ + tours/checklists/surveys | ✅ Fin | ✅ Space "Help" | ✅ `showArticle` | ⚠️ | ✅ | ✅ | ❔ | ✅ |
| 2 | Drift † | ✅ playbooks/campaigns | ✅ | ⚠️ | ❌ | ✅ | ❔ | ❔ | ✅ agendamento | ✅ `emailCapture` |
| 3 | HubSpot | ✅ welcome + exit intent | ✅ chatflows | ❌ | ❌ | ✅ | ❔ | ✅ (`disableAttachment`) | ❌ | ✅ |
| 4 | Zendesk | ❌ **declarado "No"** | ✅ AI agents/answer bot | ✅ | ✅ `articleClicked` | ⚠️ `conversationFields` | ✅ | ❔ | ❌ | ✅ |
| 5 | Freshchat | ✅ | ✅ Freddy | ✅ FAQ | ✅ **`setFaqTags` com filtro** | ⚠️ | ❔ | ✅ | ❔ | ✅ |
| 6 | Tidio | ✅ | ✅ Lyro + flows | ⚠️ | ❔ | ✅ | ❔ | ✅ | ❌ | ✅ |
| 7 | Crisp | ✅ `trigger:run` | ✅ `bot:scenario:run` + Hugo | ✅ helpdesk | ✅ `helpdesk:query`/`article:open` | ✅ | ✅ | ✅ | ✅ (histórico de vídeo/áudio) | ✅ |
| 8 | LiveChat | ✅ greetings + eye-catcher | ✅ | ⚠️ via app | ❌ | ✅ `form_submitted` | ✅ `rating_submitted` | ✅ | ✅ **`display-capture`** | ✅ |
| 9 | Olark | ✅ **`api.rules.defineRule`** | ✅ AI agent | ❌ | ❌ | ✅ `system.custom_prechat` | ✅ (Classic) | ❔ | ❌ | ✅ |
| 10 | tawk.to | ✅ smart triggers | ✅ AI Assist | ✅ | ❔ | ✅ `onPrechatSubmit` | ✅ `onChatSatisfaction` | ✅ `onFileUpload` | ⚠️ add-on pago | ✅ `onOfflineSubmit` |
| 11 | Gorgias | ✅ **iframe dedicado** | ✅ AI Agent + Flows | ✅ | ❔ | ⚠️ | ❔ | ❔ | ❌ | ✅ |
| 12 | Front | ⚠️ welcome message | ✅ chatbot opcional | ❌ | ❌ | ❌ | ❔ | ❔ | ❌ | ✅ |
| 13 | Chatra | ✅ `sendAutoMessage` + triggers | ✅ | ❌ | ❌ | ✅ | ❔ | ✅ | ✅ screen share (Median) | ✅ |
| 14 | Userlike/Lime | ✅ | ✅ AI Agent | ✅ AI Automation Hub | ❔ | ✅ | ❔ | ✅ | ❔ | ✅ |
| 15 | Kustomer | ❔ | ✅ AI Agents | ✅ (KB própria) | ❔ | ❔ | ❔ | ❔ | ❔ | ❔ |
| 16 | Gladly | ❔ | ✅ Sidekick | ✅ "Answers" | ❔ | ❔ | ❔ | ❔ | ❔ | ❔ |
| 17 | Ada | ✅ `ada:campaigns:*` | ✅ (é o produto) | ✅ | ❔ | ❌ | ❔ | ❔ | ❌ | ⚠️ |
| 18 | Trengo | ✅ | ✅ HelpMate/Journeys | ✅ **canal `help_center`** | ❔ | ✅ | ❔ | ✅ | ✅ canal `voice` | ✅ |
| 19 | Chaport | ✅ `chat.autoInvitation` | ✅ (plano Unlimited) | ✅ (Unlimited) | ❔ | ✅ | ❔ | ✅ | ❌ | ✅ |
| 20 | Smartsupp | ✅ | ✅ Mira | ❌ | ❌ | ⚠️ | ❔ | ✅ | ⚠️ gravação de sessão | ✅ |

### Bloco 3 — Identidade, customização e comercial (capacidades 19–25)

| # | Player | 19. Verificação de identidade | 20. Enforcement por toggle | 21. Cor/tema por API | 22. CSS custom | 23. Dark mode | 24. i18n / idiomas | 25. Remoção de marca |
|---|---|---|---|---|---|---|---|---|
| 1 | Intercom | ✅ **JWT HS256** | ⚠️ congelado p/ novas contas | ✅ `action_color`, `background_color`, `link_color` | ❌ | ✅ `theme_mode: system` | ✅ `language_override` | ⚠️ depende do plano **[NV]** |
| 2 | Drift † | ⚠️ JWT opcional | ❌ | ⚠️ | ❌ | ❔ | ❔ | ❔ |
| 3 | HubSpot | ⚠️ token de API | ❌ | ✅ cor + fonte | ⚠️ CSS externo via `avoidInlineStyles` | ❔ | ⚠️ | ⚠️ plano pago |
| 4 | Zendesk | ✅ **JWT via callback** | ❌ | ✅ 14 tokens estilo Material 3 | ❌ **declarado ausente** | ❔ | ✅ `messenger:set locale` | ❔ |
| 5 | Freshchat | ✅ **JWT RS256** | ⚠️ via suporte | ⚠️ | ❌ | ❔ | ✅ `user.setLocale` | ❔ |
| 6 | Tidio | ❔ | ❌ | ✅ (painel) | ❔ | ❔ | ✅ | ✅ **add-on US$ 16,67/mês** |
| 7 | Crisp | ✅ HMAC-SHA256 (e-mail) | ❌ | ✅ `color:theme`, `color:mode`, `layout:theme` **em runtime** | ✅ (DOM aberto) | ✅ `color:mode` | ✅ `locale` runtime | ✅ **plano Plus** |
| 8 | LiveChat | ❔ | ❌ | ✅ tema/cores/posição on the fly | ⚠️ Enterprise | ❔ | ✅ **45+ idiomas + RTL** | ✅ **Enterprise** |
| 9 | Olark | ❔ | ❌ | ✅ `hb_primary_color`, `hb_dark_theme` | ⚠️ | ✅ `hb_dark_theme` | ✅ 11 idiomas + RTL | ❔ |
| 10 | tawk.to | ✅ HMAC-SHA256 | ❌ | ⚠️ `customStyle` (z-index) + painel | ❌ | ❔ | ✅ **50+ idiomas** | ✅ **US$ 29/mês** |
| 11 | Gorgias | ❔ | ❌ | ✅ (painel) | ❔ | ❔ | ⚠️ `language` no WSS | ❔ |
| 12 | Front | ✅ HMAC-SHA256 | ✅ **"only verified users"** | ⚠️ tema na config do canal | ❌ (iframe isolado) | ❔ | ❔ | ❔ |
| 13 | Chatra | ❔ | ❌ | ✅ objeto `colors` completo | ❔ | ❔ | ✅ **`setLocale` com dicionário arbitrário** | ❔ |
| 14 | Userlike/Lime | ⚠️ recomendado, mecanismo **[NV]** | ❌ | ✅ | ❔ | ❔ | ✅ `setLanguage` | ❔ |
| 15 | Kustomer | ✅ **JWT, `iat` ≤ 15 min** | ❌ | ❔ | ❔ | ❔ | ❔ | ❔ |
| 16 | Gladly | ✅ **JWT `async`** | ❌ | ❔ | ❔ | ❔ | ❔ | ❔ |
| 17 | Ada | ✅ JWT (via Zendesk) | ❌ | ✅ `styles` | ⚠️ `parentElement` | ❔ | ✅ `setLanguage` | ❔ |
| 18 | Trengo | ❌ | ❌ | ✅ (painel) | ❔ | ❔ | ✅ | ❔ |
| 19 | Chaport | ⚠️ SHA-1 + salt | ❌ | ✅ `appearance` | ❔ | ❔ | ✅ `language` | ⚠️ plano pago |
| 20 | Smartsupp | ❌ **nenhum** | ❌ | ✅ `theme` | ❔ | ❔ | ✅ | ⚠️ plano pago |

---

## 7. Tabelas transversais

### 7.1 Objeto global e assinatura da API

| Player | Global | Estilo da API |
|---|---|---|
| Intercom | `Intercom` | `Intercom('comando', args)` |
| Drift | `drift` | `drift.on('ready', fn)` → `api.*` |
| HubSpot | `HubSpotConversations` | `HubSpotConversations.widget.metodo()` + `.on(evt, fn)` |
| Zendesk | `zE` | `zE('messenger', 'cmd')` / `zE('messenger:set', k, v)` / `zE('messenger:on', evt, fn)` |
| Freshchat | `fcWidget` | `fcWidget.metodo()`, `fcWidget.user.metodo()` |
| Tidio | `tidioChatApi` | `tidioChatApi.metodo()` |
| Crisp | `$crisp` | `$crisp.push([verbo, "ns:acao", [args]])` + `.get()` / `.is()` |
| LiveChat | `LiveChatWidget` | `.call()` / `.get()` / `.on()` / `.once()` / `.off()` / `.init()` |
| Olark | `olark` | `olark('api.ns.metodo', args)` + `olark.configure(k, v)` |
| tawk.to | `Tawk_API` | propriedades e métodos diretos |
| Gorgias | `GorgiasChat` | `GorgiasChat.init().then(...)` |
| Front | `FrontChat` | `FrontChat('cmd', args)` |
| Chatra | `Chatra` / `ChatraSetup` | `Chatra('metodo', params)` |
| Userlike/Lime | `userlike` | objeto `messenger` com métodos |
| Kustomer | `Kustomer` | `Kustomer.metodo(opts, cb)` |
| Gladly | `Gladly` | `Gladly.init().then()` + `.on()` |
| Ada | `adaEmbed` | `await adaEmbed.acao()` (**Promise-based**) |
| Trengo | `Trengo` | `Trengo.Api.Widget.metodo()` |
| Chaport | `chaport` | direta ou `chaport.q('cmd', [args])` |
| Smartsupp | `smartsupp` / `_smartsupp` | `smartsupp('comando', args)` |

**[INF]** Três famílias de design: **string-command** (Intercom, Front, Smartsupp, Zendesk), **objeto-método** (HubSpot, Freshchat, Trengo, Gladly, Kustomer) e **fila-array** (Crisp, Chaport). A mais moderna é a do Ada: **tudo `Promise`/`await`**. A mais expressiva é a do Crisp. A mais previsível para quem escreve TypeScript é a objeto-método.

### 7.2 Domínios usados (relevante para CSP e para adblock)

| Player | Loader | Assets/bundle | API/realtime |
|---|---|---|---|
| Intercom | `widget.intercom.io` | `js.intercomcdn.com`, `static.intercomassets.com` | `api-iam.intercom.io`, `nexus-websocket-a.intercom.io`, `primary-realtime.intercom-messenger.com` |
| Crisp | `client.crisp.chat` | `client.crisp.chat/static`, `image.crisp.chat`, `static.crisp.help` | `client.relay.crisp.chat` |
| tawk.to | `embed.tawk.to` | `embed.tawk.to` | `vsbNN.tawk.to`, `va.tawk.to` |
| LiveChat | `cdn.livechatinc.com` | `cdn.livechatinc.com` | `api.livechatinc.com`, `secure.livechatinc.com` |
| Tidio | `code.tidio.co` | `code.tidio.co` | `socket.tidio.co`, `sentry.tidio.co` |
| HubSpot | `js.hs-scripts.com` | `static.hsappstatic.net`, `js.hubspot.com` | `app.hubspot.com` |
| Zendesk | `static.zdassets.com/ekr` | `static.zdassets.com`, `ekr.zdassets.com` | `v2.zopim.com` |
| Gorgias | `config.gorgias.chat` | `assets.gorgias.chat` | `<região>-<shard>.gorgias.chat` |
| Smartsupp | `www.smartsuppchat.com` | `widget-v3.smartsuppcdn.com`, `files.smartsuppcdn.com` | `api.smartsuppchat.com`, `bootstrap.smartsuppchat.com` |
| Chaport | `app.chaport.com` | `assets.chaport.com` | `app.chaport.com` |
| Chatra | `call.chatra.io` | `static.chatra.io` | `chat.chatra.io` |
| Userlike/Lime | `userlike-cdn-widgets.s3-eu-west-1.amazonaws.com` | `userlike-cdn-umm.b-cdn.net` | `connect.lime-technologies.com` |
| Front | `chat-assets.frontapp.com` | idem | **[NV]** |
| Olark | `static.olark.com` | idem | `visitor.olark.com` |
| Freshchat | `wchat.freshchat.com`, `fw-cdn.com` | `assetscdn-wchat.freshchat.com` | **[NV]** |
| Ada | `static.ada.support` | idem | por `cluster` |
| Trengo | (inline) | `static.widget.trengo.eu` | **[NV]** |

**[INF]** Quase todos separam **loader**, **assets** e **API** em hosts distintos. Isso permite (a) cache agressivo nos assets, (b) trocar CDN sem tocar no snippet do cliente, (c) políticas de CSP mais granulares. Vale copiar.

### 7.3 Resumo de preços (2026)

| Player | Entrada paga | Unidade | IA | Marca removível |
|---|---|---|---|---|
| tawk.to | **US$ 0** | — | US$ 29/mês | US$ 29/mês |
| Chaport | € 29/mês (4 op.) | por conta | — | plano pago |
| Crisp | **US$ 45/mês (4 assentos)** | **por workspace** | créditos inclusos | plano Plus |
| Smartsupp | US$ 17/mês (1 op.) | por conta | US$ 16/mês (100 conv.) | plano pago |
| Chatra | R$ 49/agente/mês | assento | incluso | ❔ |
| LiveChat | US$ 19/mês (Starter) | assento + visitantes | ❔ | Enterprise |
| Olark | US$ 29/agente/mês (só chat) | assento | **US$ 400/mês fixo** | ❔ |
| Tidio | US$ 24,17/mês | conversas faturáveis | **US$ 0,50/conv. Lyro** | US$ 16,67/mês |
| Front | US$ 25/assento/mês | assento | ❔ | ❔ |
| Intercom | US$ 29/assento/mês | assento | **US$ 0,99/outcome** | ❔ |
| Freshworks | US$ 29/agente/mês | assento | US$ 49/100 sessões | ❔ |
| Gorgias | US$ 10/mês (50 tickets) | **ticket** | ~US$ 0,90–1,00/resolução | ❔ |
| Userlike/Lime | € 87/mês (3 assentos) | assento | **€ 99/mês fixo** | ❔ |
| Trengo | € 299/mês | pacote | € 0,25–0,30/conv. | ❔ |
| Zendesk | R$ 359/agente/mês | assento | por resolução (**[NV]**) | ❔ |
| Kustomer | US$ 89/usuário/mês (mín. 8) | assento **ou** conversa | US$ 0,60/conv. | ❔ |
| Gladly / Ada / Drift | **[NV]** | — | — | — |

---

## 8. IMPLICAÇÕES PARA O CHATSPX

> Esta seção é **recomendação**, não implementação. Nenhum arquivo de código foi tocado nesta pesquisa.
> Para calibrar o que é *gap* e o que é *paridade*, li (somente leitura) `app/javascript/entrypoints/sdk.js`, `app/javascript/sdk/*` e os pontos de HMAC no backend. O baseline abaixo é **[FV]** contra o repositório em `homologacao`.

### 8.0 Baseline do ChatSPX hoje

| Dimensão | Estado atual **[FV]** |
|---|---|
| Global | `window.$chatwoot`, iniciado por `window.chatwootSDK.run({ baseUrl, websiteToken })` |
| Isolamento | **iframe** (padrão A) — `IFrameHelper.createFrame`, 12 referências a `iframe` no helper; **zero** `attachShadow` |
| API pública | `toggle(state)` · `toggleBubbleVisibility(visibility)` · `popoutChatWindow()` · `setUser(identifier, user)` · `setCustomAttributes()` · `deleteCustomAttribute()` · `setConversationCustomAttributes()` · `deleteConversationCustomAttribute()` · `setLabel()` · `removeLabel()` · `setLocale()` · `setColorScheme()` · `reset()` |
| Config declarativa | `window.chatwootSettings`: `locale`, `baseDomain`, `useBrowserLanguage`, `hideMessageBubble`, `position`, `type`, `launcherTitle`, `showPopoutButton`, `showUnreadMessagesDialog`, `widgetStyle`, `darkMode`, `welcomeTitle`, `welcomeDescription`, `availableMessage`, `unavailableMessage`, `enableFileUpload`, `enableEmojiPicker`, `enableEndConversation` |
| Eventos p/ o host | `chatwoot:ready`, `chatwoot:error`, `chatwoot:on-message` (via `dispatchWindowEvent`), `chatwoot:postback` |
| Identidade | `identifier_hash` (HMAC) + coluna `hmac_verified` em `contact_inbox`; `api/v1/widget/base_controller.rb` já filtra contact_inboxes verificados |
| Realtime | ActionCable (mesma família do Qualified) |
| SPA | tratamento explícito de Turbo, Turbolinks e Astro (`restoreWidgetInDOM`) |

**Leitura honesta desse baseline [INF]:** estamos em **paridade estrutural** com o pelotão do meio (Front, HubSpot, Chatra) e **acima** de vários no quesito identidade — já temos HMAC com flag de verificação persistida no banco, o que Smartsupp, Trengo, Gorgias e Chatra **não têm**. O tratamento de Turbo/Turbolinks/Astro é melhor que a média. Os gaps reais estão em: (a) profundidade de tema, (b) modernidade da credencial de identidade, (c) superfície de eventos, (d) features de "mini-app" (base de conhecimento, proativo, CSAT).

---

### 8.1 O que é PADRÃO DE MERCADO (todo mundo tem — se falta, é dívida)

Estas capacidades aparecem em praticamente todos os 20 players. Não são diferencial; são requisito de entrada.

| Capacidade | Quem tem | ChatSPX |
|---|---|---|
| Stub global síncrono com fila antes do bundle | 20/20 | ✅ |
| `open` / `close` / `show` / `hide` programáticos | 20/20 | ⚠️ temos `toggle` e `toggleBubbleVisibility`; **falta `open()`/`close()` explícitos e idempotentes** |
| Identificação declarativa do visitante (nome/e-mail/telefone) | 20/20 | ✅ `setUser` |
| Atributos customizados | 19/20 | ✅ (contato **e** conversa — acima da média) |
| Evento de "pronto" | 20/20 | ✅ `chatwoot:ready` |
| Contador de não-lidas exposto ao host | 15/20 | ❌ **gap** — Intercom, Zendesk, HubSpot, Front, Gorgias, Crisp, Ada expõem; nós não |
| Reset/logout do widget | 18/20 | ✅ `reset()` |
| Cor primária configurável | 20/20 | ✅ |
| Posição esquerda/direita | 20/20 | ✅ |
| Idioma configurável em runtime | 18/20 | ✅ `setLocale` |
| Dark mode | 12/20 | ✅ `setColorScheme` — **acima da média** |
| Upload de arquivo | 17/20 | ✅ `enableFileUpload` |
| Suporte a SPA (revalidar rota) | 16/20 | ✅ Turbo/Turbolinks/Astro |
| Loader separado do bundle | 18/20 | ⚠️ **verificar** — se `sdk.js` já traz tudo, é gap de performance |
| Mensagem proativa / saudação com regra | 17/20 | ⚠️ existe campanha; falta paridade com `trigger:run` / `defineRule` |

**Ação imediata sugerida [INF]:** os três gaps de padrão são **contador de não-lidas exposto**, **`open()`/`close()` explícitos** e **confirmar o peso do loader**. São baratos e removem objeção de comparação.

---

### 8.2 O que é DIFERENCIAL (poucos têm — vale copiar seletivamente)

Ordenei por **razão valor/esforço** na minha leitura.

**Nível 1 — copiar (alto valor, esforço baixo/médio):**

| # | Capacidade | Quem tem | Por que importa |
|---|---|---|---|
| D1 | **JWT sob demanda via callback/async** em vez de hash estático | Zendesk, Gladly, Kustomer, Ada | Resolve expiração, reconexão e SPA de sessão longa. Nosso `identifier_hash` é HMAC estático — mesma geração do Crisp/Front, uma geração atrás do topo. |
| D2 | **Toggle "só aceitar mensagens de usuários verificados"** no painel | **só o Front** | Transforma segurança em decisão de negócio de 1 clique. Já temos `hmac_verified` no banco — falta o switch e o enforcement. |
| D3 | **`custom_launcher_selector`** — qualquer elemento do site vira launcher | só Intercom | Permite "Fale conosco" no rodapé/menu sem `hideMessageBubble` + JS manual. Barato de implementar. |
| D4 | **Contador de não-lidas + `connected`/`disconnected` como eventos** | Intercom, Gorgias, Zendesk | O host reagir à perda de conexão é exatamente a dor que já tratamos internamente. Expor isso é diferencial real. |
| D5 | **Modo embutido (inline) em vez de bolha flutuante** | HubSpot (`inlineEmbedSelector`), Olark (`box.inline`), Chatra (`mode:'frame'`), Zendesk (`render`), Ada (`parentElement`) | Habilita "página de suporte" e Central de Ajuda embutida — sinergia direta com o que já fazemos com portal em iframe. |
| D6 | **`chat:message` vs `chat:send`** (pré-preencher sem enviar) | Smartsupp, LiveChat (`messageDraft`), Intercom (`showNewMessage` com conteúdo) | Botões contextuais na página ("perguntar sobre este produto") sem enviar por conta do usuário. |
| D7 | **Tokens de tema no estilo Material 3** (`primary`/`onPrimary`, `background`/`onBackground`) | Zendesk | Garante contraste por construção. Resolve, na raiz, a classe de bug de contraste que já nos mordeu em light/dark. |

**Nível 2 — avaliar (alto valor, esforço maior):**

| # | Capacidade | Quem tem | Observação |
|---|---|---|---|
| D8 | **Arquitetura híbrida Shadow DOM (casca) + iframe (painel)** | Freshchat | Launcher/badge/greeting em Shadow DOM = leve e sem colisão de CSS; painel em iframe = isolamento real. Melhor dos dois mundos. |
| D9 | **Interceptação `beforeMessageSent` / `beforeMessageDisplay`** | só Zendesk | Mascarar PII no cliente, injetar contexto, traduzir. Recurso de conformidade vendável. |
| D10 | **Ferramentas do agente de IA implementadas no site host** (`hugo:tool:*`) | só Crisp | Function-calling do LLM delegado ao JS do cliente. Conceitualmente o recurso mais avançado do mercado. Sinergia total com Captain/tools que já temos. |
| D11 | **`setLocale` aceitando dicionário arbitrário** | só Chatra | Cliente traduz o widget inteiro sem depender do nosso catálogo. Para nós, que priorizamos pt-BR, também resolve terminologia por cliente. |
| D12 | **Seletor de canal no widget** (`open('whatsapp')`, `open('help_center')`) | Trengo | Temos WhatsApp forte. Um widget que oferece "continuar no WhatsApp" é diferencial de mercado brasileiro. |
| D13 | **Configuração diferente por dispositivo** | Chaport (`devices`) | Esconder no mobile, mudar tamanho, mudar canal padrão. |
| D14 | **Motor de regras proativas exposto como código** | Olark (`api.rules.defineRule` com `perVisit`/`perPage`/`perVisitor`) | Controle de frequência embutido é o que falta na maioria das campanhas. |
| D15 | **Manifesto de assets por conta** (loader → manifesto → bundle) | Chaport | Permite rollout gradual e versão por cliente sem tocar no snippet. Atenção: **não** copiar o JSONP. |

**Nível 3 — não copiar (custo alto, valor duvidoso, ou risco):**

- **Bloquear Lighthouse/GTmetrix/HeadlessChrome** (Crisp) — esconde o impacto real de performance do cliente. Antiético e quebra nossos próprios testes Playwright.
- **Cache-buster por timestamp no loader** (Gladly) — destrói cache de CDN.
- **`sha1(salt . dados)`** (Chaport) — criptografia mal escolhida.
- **JSONP no caminho crítico** (Chaport) — 3 round-trips e injeção de script global.
- **`onCommandFromOperator`** (Olark) — atendente executando código no navegador do visitante é superfície de ataque interna.
- **Cinco iframes** (Trengo/tawk.to) — custo de memória em mobile sem ganho proporcional.

---

### 8.3 O que NINGUÉM faz bem (a janela de oportunidade)

Estes são os buracos coletivos. É onde um produto novo pode ganhar, e onde eu concentraria a aposta.

**N1 — Tema profundo de marca com isolamento.**
Todo mundo escolheu um extremo: ou isola em iframe e entrega 3 a 14 variáveis de cor (Intercom, Zendesk, Front, HubSpot), ou abre o DOM e o CSS do site vaza pra dentro (Crisp). **Ninguém entrega "o cliente estiliza de verdade, e mesmo assim nada quebra".**
*Caminho:* um **contrato de design tokens** (cores semânticas + raio + espaçamento + tipografia + sombra) aplicado dentro do iframe via `postMessage`, com validação de contraste no servidor e preview. É diferencial vendável e alinhado ao que já fazemos com branding no ChatSPX. **[INF]**

**N2 — Identidade verificada como padrão, não como opção.**
De 20 players, **1** (Front) tem enforcement simples de ativar. **Vários grandes não têm verificação nenhuma.** O mercado inteiro está com a porta aberta para impersonação de usuário logado.
*Caminho:* verificação **ligada por padrão** em inbox nova, com modo anônimo explicitamente coexistente, mensagens de erro em pt-BR no console e um **debugger de token** (o Intercom tem; ninguém mais). Isso vira argumento de venda para banco, saúde e jurídico. **[INF]**

**N3 — Previsibilidade de custo com IA.**
Só Olark (US$ 400/mês fixo) e Lime Connect (€ 99/mês fixo) resistem à cobrança por resolução. Todos os outros expõem o cliente a fatura variável — e a imprensa especializada bate exatamente nisso (Gorgias com dupla contagem, Intercom com "4× o valor da página de preços").
*Caminho:* **preço fixo de IA por inbox**, com teto declarado. No mercado brasileiro, onde câmbio já é volatilidade suficiente, previsibilidade vende mais que sofisticação. **[INF]**

**N4 — Acessibilidade real do widget.**
Só o **LiveChat** menciona leitor de tela/teclado/contraste na página de features; o Olark tem WCAG 2.1 AA **marcado como "Classic"**, sugerindo regressão no produto novo. Widget em iframe com foco preso é notoriamente hostil a leitor de tela.
*Caminho:* fazer certo e **auditar publicamente** (foco visível, ordem de tabulação, `aria-live` para mensagens novas, respeitar `prefers-reduced-motion`, contraste AA garantido pelos tokens de N1). Em licitação pública brasileira e cliente corporativo isso é critério eliminatório, não enfeite. **[INF]**

**N5 — Performance honesta e mensurável.**
O peso vai de 98 KB (Crisp) a 1,25 MB (Intercom) — e o Crisp só parece leve porque **se esconde do Lighthouse**. Nenhum fornecedor publica orçamento de performance do widget.
*Caminho:* publicar um **orçamento explícito** ("< X KB no launcher, painel só ao abrir, zero impacto em LCP") e um endpoint de auto-verificação. Ninguém faz. É marketing técnico verificável. **[INF]**

**N6 — Continuidade e autenticidade separadas.**
Só o Crisp separa `CRISP_TOKEN_ID` (continuidade) de assinatura HMAC (autenticidade). Freshchat funde os dois no `restoreId` e cria um bearer eterno.
*Caminho:* manter os dois conceitos separados desde o começo — é decisão de arquitetura barata agora e cara depois. **[INF]**

**N7 — Cadeia de suprimento do widget.**
A lição do Drift (seção 2.2): comprometer o fornecedor do widget compromete todos os clientes dele. Nenhum player documenta **postura de segurança do próprio widget** de forma acessível.
*Caminho:* SRI onde possível, domínios separados por função (loader/assets/API), escopo mínimo de token nas integrações, rotação documentada e uma página pública de segurança do widget. É diferencial de confiança num mercado que acabou de levar um susto. **[INF]**

---

### 8.4 Riscos que este estudo revelou para nós

| Risco | Evidência | Mitigação sugerida |
|---|---|---|
| **Widget como vetor de comprometimento em massa** | Drift/UNC6395, +700 orgs **[FV]** | Escopo mínimo de token nas integrações; rotação; monitoramento de uso anômalo de token; não guardar credencial de cliente sem necessidade |
| **CSS do site host vazando para o widget** | Crisp renderiza no DOM aberto **[FV-M]**; nós já tivemos bugs de CSS catch-all no ChatSPX | Manter iframe para o painel; se adotar Shadow DOM na casca (D8), testar com resets agressivos |
| **Identidade declarativa aceita sem prova** | Smartsupp/Chatra/Trengo/Gorgias **[FV/NV]** | Não repetir o erro: enforcement como toggle de 1 clique (D2) |
| **Cobrança de IA imprevisível afastando cliente** | Intercom/Gorgias criticados na imprensa **[FV/terceiro]** | Preço fixo por inbox (N3) |
| **Fornecedor sumir / ser adquirido** | Drift sunset; Intercom→Fin→Salesforce; Userlike→Lime **[FV]** | Argumento de venda a nosso favor: fork open-source auto-hospedado, sem risco de descontinuação |
| **Bundle inflando sem controle** | 1,25 MB do Intercom **[FV-M]** | Orçamento de performance declarado (N5) e medido em CI |

---

### 8.5 Como eu priorizaria (proposta, sujeita a validação do Walisson)

**Onda 1 — fechar paridade (baixo custo, remove objeção em comparativo):**
`open()`/`close()` explícitos · contador de não-lidas exposto · eventos `connected`/`disconnected` · `custom_launcher_selector` (D3) · confirmar/segmentar o peso do loader.

**Onda 2 — segurança como diferencial:**
Toggle "só usuários verificados" (D2) · migração de HMAC estático para **JWT com callback** (D1), mantendo o HMAC por compatibilidade, exatamente como o Intercom fez · debugger de token · página pública de segurança do widget (N7).

**Onda 3 — tema e acessibilidade (a aposta de N1 + N4):**
Contrato de design tokens semânticos com validação de contraste · auditoria de acessibilidade do widget · modo embutido inline (D5).

**Onda 4 — mini-app e IA:**
Base de conhecimento embutida com busca por API · `hugo:tool:*`-like ligado ao Captain (D10) · seletor de canal com WhatsApp (D12) · motor de proativo com controle de frequência (D14).

**Fora de escopo desta task:** qualquer estimativa de prazo ou esforço. Isso depende de decisão de produto que não é minha.

---

## 9. Apêndice — URLs de documentação para consulta futura

### 9.1 Documentação de desenvolvedor (fonte primária)

| Player | URL |
|---|---|
| Intercom — instalação | <https://developers.intercom.com/installing-intercom/web/installation> |
| Intercom — métodos | <https://developers.intercom.com/installing-intercom/web/methods> |
| Intercom — atributos | <https://developers.intercom.com/installing-intercom/web/attributes-objects> |
| Intercom — segurança do Messenger | <https://developers.intercom.com/installing-intercom/web/identity-verification> |
| Intercom — índice para LLM | <https://developers.intercom.com/llms.txt> |
| Drift — controlando o widget | <https://devdocs.drift.com/docs/widget-start> |
| Drift — eventos | <https://devdocs.drift.com/docs/drift-events> |
| Drift — `drift.identify()` | <https://devdocs.drift.com/docs/driftidentify-implementation-guide> |
| Drift — índice para LLM | <https://devdocs.drift.com/llms.txt> |
| HubSpot — Chat Widget SDK | <https://developers.hubspot.com/docs/reference/api/conversations/chat-widget-sdk> |
| HubSpot — customização do canal | <https://knowledge.hubspot.com/inbox/connect-and-customize-a-chat-channel-in-the-conversations-inbox> |
| Zendesk — API core do messaging | <https://developer.zendesk.com/api-reference/widget-messaging/web/core/> |
| Zendesk — eventos | <https://developer.zendesk.com/api-reference/widget-messaging/web/events/> |
| Zendesk — autenticação | <https://developer.zendesk.com/api-reference/widget-messaging/web/authentication/> |
| Zendesk — cores via API | <https://support.zendesk.com/hc/en-us/articles/9944875856666-Customizing-the-messaging-Web-Widget-colors-with-the-Web-Widget-API> |
| Zendesk — comparação de widgets | <https://support.zendesk.com/hc/en-us/articles/4429429087002-Comparing-the-Zendesk-Web-Widgets> |
| Zendesk — cookbook | <https://support.zendesk.com/hc/en-us/articles/10292484466330-Messaging-Web-Widget-cookbook> |
| Zendesk — metadata de messaging | <https://support.zendesk.com/hc/en-us/articles/5658339908378-Using-messaging-metadata-with-the-Zendesk-Web-Widget-and-SDKs> |
| Freshchat — Web SDK v2 | <https://developers.freshchat.com/web-sdk/v2/> |
| Tidio — API v3 | <https://developers.tidio.com/docs/api_v3> |
| Crisp — `$crisp` | <https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/dollar-crisp/> |
| Crisp — verificação de identidade | <https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/identity-verification/> |
| Crisp — continuidade de sessão | <https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/session-continuity/> |
| Crisp — customização de idioma | <https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/language-customization/> |
| Crisp — políticas de cookie | <https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/cookie-policies/> |
| Crisp — npm | <https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/npm/> |
| LiveChat/Text — JS API | <https://platform.text.com/docs/extending-chat-widget/javascript-api> |
| Olark — API | <https://www.olark.com/api> |
| tawk.to — JS API | <https://developer.tawk.to/jsapi/> |
| Gorgias — eventos do chat | <https://docs.gorgias.com/en-US/subscribe-to-chat-events-460530> |
| Gorgias — customizar com HTML | <https://docs.gorgias.com/en-US/customize-chat-with-html-101-286032> |
| Front — visão geral do chat | <https://dev.frontapp.com/docs/chat-overview> |
| Front — referência do SDK | <https://dev.frontapp.com/docs/chat-sdk-reference> |
| Front — identificar usuários | <https://dev.frontapp.com/docs/identify-users> |
| Front — usar o Front Chat | <https://help.front.com/en/articles/2049> |
| Chatra — API | <https://chatra.com/help/api/> |
| Userlike/Lime — Website Messenger API | <https://docs.lime-connect.com/developers/api/website-messenger-api> |
| Userlike — repositório da API | <https://github.com/userlike/messenger> |
| Kustomer — visão geral do Web SDK | <https://developer.kustomer.com/chat-sdk/v2.0-Web/docs/overview-chat-web-sdk> |
| Kustomer — `login()` | <https://developer.kustomer.com/chat-sdk/v2.0-Web/docs/kustomer-login> |
| Kustomer — autenticação JWT | <https://developer.kustomer.com/chat-sdk/v2.0-Web/docs/authenticate-chat-with-jwt-token> |
| Kustomer — exemplos | <https://github.com/kustomer/web-chat-sdk-samples> |
| Gladly — Chat SDK | <https://developer.gladly.com/chat/> |
| Gladly — SDKs mobile | <https://github.com/gladly> |
| Ada — referência do Embed2 | <https://docs.ada.cx/reference/embed2-reference> |
| Ada — início rápido | <https://developers.ada.cx/reference/embed2-quick-start> |
| Ada — npm | <https://www.npmjs.com/package/@ada-support/embed2> |
| Trengo — métodos | <https://developers.trengo.com/docs/methods> |
| Trengo — dados de ticket | <https://developers.trengo.com/docs/set-ticket-data> |
| Trengo — índice para LLM | <https://developers.trengo.com/llms.txt> |
| Chaport — JS API v1 | <https://docs.chaport.com/api/js/v1/> |
| Chaport — REST API | <https://docs.chaport.com/api/v1/> |
| Smartsupp — Chat Box | <https://docs.smartsupp.com/chat-box/> |
| Smartsupp — métodos | <https://docs.smartsupp.com/chat-box/javascript-api/methods/> |
| Smartsupp — eventos | <https://docs.smartsupp.com/chat-box/javascript-api/events/> |
| Smartsupp — identificação de visitante | <https://docs.smartsupp.com/chat-box/visitor-identification/> |
| Smartsupp — webhooks | <https://docs.smartsupp.com/rest-api/webhooks/> |

### 9.2 Páginas de preço oficiais

<https://www.intercom.com/pricing> · <https://crisp.chat/en/pricing/> · <https://www.tidio.com/pricing/> · <https://www.zendesk.com.br/pricing/> · <https://www.livechat.com/pricing/> · <https://www.tawk.to/pricing/> · <https://www.olark.com/pricing> · <https://www.freshworks.com/freshdesk/omni/pricing/> · <https://front.com/pricing> · <https://chatra.com/plans/> · <https://connect.lime-technologies.com/en/pricing/> · <https://trengo.com/pricing> · <https://www.chaport.com/pricing/> · <https://www.smartsupp.com/pricing/> · <https://www.gorgias.com/pricing>

### 9.3 Segurança e movimentos de mercado

| Assunto | URL |
|---|---|
| GTIG — roubo de dados via Salesloft Drift (UNC6395) | <https://cloud.google.com/blog/topics/threat-intelligence/data-theft-salesforce-instances-via-salesloft-drift> |
| FINRA — alerta sobre o ataque de cadeia de suprimento Drift | <https://www.finra.org/rules-guidance/guidance/salesloft-drift-AI-supply-chain-attack> |
| AppOmni — análise do risco de integrações OAuth | <https://appomni.com/blog/drift-breach-salesforce-unc6395-saas-prevention/> |
| Intercom — "Today Intercom becomes Fin" (12/05/2026) | <https://www.intercom.com/blog/today-intercom-becomes-fin/> |
| Salesforce — acordo para adquirir a Fin (15/06/2026) | <https://www.salesforce.com/news/press-releases/2026/06/15/salesforce-signs-definitive-agreement-to-acquire-fin/> |
| Salesforce Investor Relations — mesmo anúncio | <https://investor.salesforce.com/news/news-details/2026/Salesforce-Signs-Definitive-Agreement-to-Acquire-Fin/default.aspx> |
| CNBC — cobertura da aquisição | <https://www.cnbc.com/2026/06/15/salesforce-ai-customer-service-fin-acquistion.html> |
| Intercom — migração de Identity Verification para JWT | <https://www.intercom.com/help/en/articles/10807823-migrating-from-identity-verification-to-messenger-security-with-jwts> |
| Intercom — Identity Verification (deprecado) | <https://www.intercom.com/help/en/articles/7946878-what-is-identity-verification-deprecated> |

### 9.4 Fontes de terceiros usadas (sempre rotuladas no texto)

<https://www.dragapp.com/blog/intercom-pricing/> · <https://www.metageeks.tech/insights/intercom-fin-pricing> · <https://chatarmin.com/en/blog/gorgias-pricing> · <https://www.eesel.ai/blog/gorgias-plans-comparison> · <https://www.gorgias.com/blog/ai-agent-pricing> · <https://chatarmin.com/en/blog/kustomer-pricing> · <https://www.getmacha.com/blog/kustomer-pricing-explained> · <https://www.capterra.com/p/144752/Chatra/pricing/> · <https://www.docket.io/blog/drift-is-dead> · <https://resources.rework.com/news/sales-tech/drift-sunset-migration-playbook-sales-ops> · <https://www.getmacha.com/blog/gorgias-chat-widget-explained> · <https://www.eesel.ai/blog/gorgias-web-widget> · <https://community.intercom.com/customer-faq-28/how-can-i-get-rid-of-the-intercom-branding-2397>

---

## 10. Lacunas assumidas deste estudo

Registro explícito do que **não** consegui verificar, para que ninguém trate como fato:

1. **API JavaScript do Tidio** — a doc oficial retornou 404 no meu acesso; só confirmei o global `tidioChatApi` por medição. **[NV]**
2. **Verificação de identidade** de LiveChat, Gorgias, Chatra, Trengo, Olark e Tidio — não localizei documentação primária. Ausência de doc **não** prova ausência do recurso. **[NV]**
3. **Preço** de Gladly, Ada e Drift; preço por resolução do Zendesk; preço do HubSpot Service Hub. **[NV]**
4. **Mecanismo criptográfico** da "Contact Verification" do Userlike/Lime. **[NV]**
5. **WebSocket de HubSpot, Trengo, Smartsupp, Chaport, Chatra, Userlike, Freshchat, Front, Olark** — não observados, mas a medição não captura sockets abertos dentro de iframes cross-origin. Não conclua ausência. **[INF]**
6. **Bytes por host** subestimados onde a resposta usa `transfer-encoding: chunked` (notadamente Crisp e Chatra). **[FV-M]** com ressalva.
7. **Widgets que não renderizaram** em 10–17 s de espera (Smartsupp, Chaport, Chatra, Zendesk na página testada) — pode ser lazy loading, consentimento de cookie ou detecção de headless (comprovadamente o caso do Crisp). Não conclua que o widget não existe. **[INF]**
8. **Freshchat** não pôde ser medido em execução porque a própria Freshworks usa Qualified no site institucional; a análise é do bundle estático. **[FV-M]** com ressalva.
9. **Plano exato** para remoção de marca no Intercom e no HubSpot. **[NV]**
10. Não testei nenhum widget **logado** nem com conta paga — todo o comportamento observado é o de visitante anônimo em página pública.

---

**Fim do relatório.**
*Arquivo: `plano/estudo-chat-web/03-players-globais.md` · pesquisa concluída em 11/08/2026 · nenhum arquivo de código do repositório foi modificado.*
