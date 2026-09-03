# 07 — Tracking em chat de site: Meta Pixel, Google (GA4/GTM/Ads) e atribuição

> **Estudo de mercado — fase de pesquisa pura. Nenhuma linha de código foi alterada neste trabalho.**
> Documento gerado em **2026-08-11**. Repositório de referência: `/home/chatwoot/chatwoot`, branch `homologacao`.
> Autor: worker de pesquisa (task 07 da série `plano/estudo-chat-web/`).

---

## Como ler este documento

Cada afirmação relevante é marcada com um destes rótulos:

| Rótulo | Significado |
|---|---|
| **[FATO]** | Verificado em fonte primária (documentação oficial do fornecedor, código-fonte público baixado, ou código do próprio repositório). URL ou caminho de arquivo sempre citado. |
| **[FATO-2ª]** | Verificado em fonte secundária confiável (blog técnico especializado, help center de fornecedor terceiro). Menor confiança que **[FATO]**. |
| **[INFERÊNCIA]** | Conclusão minha a partir dos fatos acima. Não é afirmação de fonte. |
| **[NÃO VERIFICADO]** | Não consegui confirmar. Registrado como lacuna explícita, nunca preenchido com chute. |

Números, preços, nomes de eventos e endpoints só aparecem quando têm fonte. Onde não tive fonte, está escrito "não verificado".

---

## Sumário

- [0. Resumo executivo](#0-resumo-executivo)
- [1. O problema de rastreamento específico do chat de site](#1-o-problema-de-rastreamento-específico-do-chat-de-site)
- [2. Meta / Facebook](#2-meta--facebook)
  - [2.1 Meta Pixel: anatomia](#21-meta-pixel-anatomia)
  - [2.2 Os 17 eventos padrão](#22-os-17-eventos-padrão)
  - [2.3 Que eventos fazem sentido em um chat](#23-que-eventos-fazem-sentido-em-um-chat)
  - [2.4 Como um widget de terceiro dispara no pixel do CLIENTE](#24-como-um-widget-de-terceiro-dispara-no-pixel-do-cliente)
  - [2.5 Conversions API (CAPI)](#25-conversions-api-capi)
  - [2.6 Deduplicação](#26-deduplicação-event_id-janela-de-48-h-e-o-fallback-por-fbp)
  - [2.7 fbp, fbc, fbclid](#27-fbp-fbc-fbclid-os-três-identificadores)
  - [2.8 Event Match Quality](#28-event-match-quality-emq)
  - [2.9 CAPI Gateway](#29-capi-gateway-o-atalho-da-meta)
  - [2.10 Click-to-WhatsApp e ctwa_clid](#210-click-to-whatsapp-ctwa_clid--o-caso-mais-relevante-para-o-chatspx)
- [3. Google](#3-google)
  - [3.1 gtag.js x GTM x GTM server-side](#31-gtagjs-x-gtm-x-gtm-server-side)
  - [3.2 Eventos GA4 do ciclo de lead](#32-eventos-ga4-do-ciclo-de-vida-do-lead)
  - [3.3 client_id e session_id](#33-client_id-e-session_id-a-chave-de-tudo)
  - [3.4 Measurement Protocol](#34-measurement-protocol-ga4-server-side)
  - [3.5 dataLayer e GTM](#35-datalayer-e-gtm-a-interface-de-facto-do-mercado)
  - [3.6 GTM server-side](#36-gtm-server-side-sgtm)
  - [3.7 Google Ads](#37-google-ads-conversões-gclid-enhanced-conversions-e-import-offline)
  - [3.8 Consent Mode v2](#38-consent-mode-v2)
  - [3.9 LGPD e GDPR](#39-lgpd-brasil-e-gdpr-europa)
- [4. Quem entrega o quê — levantamento fornecedor a fornecedor](#4-quem-entrega-o-quê--levantamento-fornecedor-a-fornecedor)
  - [4.1 Leadster — dissecação do bundle real](#41-leadster--dissecação-do-bundle-real)
  - [4.2 JivoChat](#42-jivochat)
  - [4.3 Tidio](#43-tidio)
  - [4.4 Intercom](#44-intercom)
  - [4.5 Drift](#45-drift)
  - [4.6 HubSpot](#46-hubspot)
  - [4.7 Zendesk](#47-zendesk)
  - [4.8 RD Station](#48-rd-station-marketing--conversas)
  - [4.9 Octadesk](#49-octadesk)
  - [4.10 Tabela comparativa consolidada](#410-tabela-comparativa-consolidada)
- [5. Atribuição: da origem anônima à venda](#5-atribuição-da-origem-anônima-à-venda)
- [6. Estado do Chatwoot / ChatSPX — auditoria do repositório](#6-estado-do-chatwoot--chatspx--auditoria-do-repositório)
- [7. IMPLICAÇÕES PARA O CHATSPX](#7-implicações-para-o-chatspx)
- [8. Apêndices](#8-apêndices)

---

## 0. Resumo executivo

**Sete conclusões que sustentam o resto do documento:**

1. **O mercado brasileiro de "chat que gera lead" já trata pixel + GA4 como recurso de primeira classe, não como integração opcional.** A Leadster — referência principal deste estudo — embute no próprio bundle JavaScript a instalação do GA4 e do Meta Pixel, o disparo de eventos client-side e um pipeline server-side de Conversions API com hash SHA-256 dos dados do lead. Isso é **[FATO]** verificado por leitura direta do bundle público `neurolead.min.js` v2.67.0 (ver §4.1).

2. **O Chatwoot/ChatSPX hoje tem ZERO rastreamento de marketing no widget.** Não existe uma única ocorrência de `fbq`, `gtag`, `dataLayer` ou `googletagmanager` em `app/` — verificado por grep no repositório (ver §6). O que existe é `referer` (URL da página), dados de browser e `custom_attributes` — matéria-prima, não tracking.

3. **A arquitetura de iframe do widget Chatwoot é uma restrição estrutural que precisa ser respeitada.** O widget roda em `<iframe>` de outro domínio; ele **não** enxerga `window.fbq` nem `window.dataLayer` do site do cliente. Mas o Chatwoot já possui um canal `iframe → parent` (`postMessage` com `eventIdentifier` → `dispatchWindowEvent`) que é exatamente o lugar certo para pendurar o disparo de tags **[FATO]**, ver `app/javascript/sdk/IFrameHelper.js:206`.

4. **Chat é o caso de uso *perfeito* para Conversions API server-side**, porque o chat é a única superfície do site que rotineiramente coleta **e-mail e telefone** de forma estruturada — que são exatamente os dois parâmetros de maior peso no *Event Match Quality* da Meta **[FATO-2ª]** e os campos mínimos das *Enhanced Conversions* do Google **[FATO]**. Um formulário de contato entrega isso uma vez; o chat entrega isso com contexto e progressivamente.

5. **Perde-se de 20% a 40% dos eventos só no client-side.** Cerca de 31,5% dos visitantes rodam bloqueadores que impedem o Meta Pixel de carregar; GA4 é bloqueado entre 5–15% (público geral) e 40–60% (público técnico) **[FATO-2ª]**. Safari/ITP corta cookies escritos por JavaScript para 7 dias **[FATO]**. Server-side não é luxo: é o que separa "medição decorativa" de medição.

6. **Deduplicação e consentimento são requisitos, não polimento.** Sem `event_id` compartilhado entre Pixel e CAPI, a conta do cliente conta a mesma conversão duas vezes **[FATO]**. Sem Consent Mode v2, campanhas do cliente na Europa perdem sinal e o cliente brasileiro fica exposto ao Guia Orientativo de Cookies da ANPD **[FATO]**.

7. **O gap para o ChatSPX é bem delimitado e cabe em 5 componentes**: (a) configuração por caixa de entrada, (b) captura e persistência de origem (UTM/gclid/fbclid/referrer), (c) ponte de eventos iframe→SDK→tags do cliente, (d) fila server-side para CAPI/Measurement Protocol com hash, (e) camada de consentimento + logs. Detalhado em §7.

---

## 1. O problema de rastreamento específico do chat de site

Um formulário HTML é fácil de medir: há um `submit`, há uma página de obrigado, há um `gtag('event','generate_lead')` no `onSubmit`. O chat quebra todas essas premissas:

| Premissa do tracking clássico | O que o chat faz |
|---|---|
| Conversão = 1 evento discreto | Conversão é um **processo** com etapas (abriu → interagiu → deu nome → deu e-mail → qualificou) |
| Há uma página de destino ("obrigado") | Não há navegação; tudo acontece na mesma URL |
| O código do formulário roda no `window` do site | O chat roda em **iframe de outro domínio** (Chatwoot, Intercom, Tidio, JivoChat, Zendesk) |
| Os dados do lead ficam no site | Os dados do lead ficam no **servidor do fornecedor de chat** |
| O lead "termina" ali | O lead continua: agente atende, qualifica, vira oportunidade, fecha semanas depois |

Consequências diretas:

- **[INFERÊNCIA]** Quem faz chat precisa oferecer **mais de um evento**, não um só. O "lead" é o evento comercialmente importante, mas otimização de campanha e diagnóstico exigem os eventos intermediários.
- **[INFERÊNCIA]** Quem faz chat é dono do dado de PII (e-mail/telefone) mas **não** é dono da página. Isso empurra a arquitetura para: eventos leves no navegador (pelo SDK do parent) + eventos ricos no servidor (CAPI/MP), amarrados por um identificador comum.
- **[INFERÊNCIA]** Como o lead evolui depois (qualificação, venda), o fornecedor de chat está sentado no ponto exato onde nascem as **conversões offline** — e ninguém no mercado de chat brasileiro está explorando isso bem (ver §4.10).

---

## 2. Meta / Facebook

### 2.1 Meta Pixel: anatomia

O Meta Pixel é um snippet JavaScript que cria a função global `fbq` e carrega `https://connect.facebook.net/en_US/fbevents.js`. O snippet canônico (reproduzido literalmente do bundle da Leadster, que usa a versão oficial da Meta — ver §4.1) é:

```js
!function(f,b,e,v,n,t,s){
  if(f.fbq) return;
  n = f.fbq = function(){ n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments) };
  if(!f._fbq) f._fbq = n;
  n.push = n; n.loaded = !0; n.version = '2.0'; n.queue = [];
  t = b.createElement(e); t.async = !0;
  t.src = 'https://connect.facebook.net/en_US/fbevents.js';
  s = b.getElementsByTagName(e)[0];
  s.parentNode.insertBefore(t, s);
}(window, document, 'script');

fbq('init', '<PIXEL_ID>');
fbq('track', 'PageView');
```

Funções principais:

| Chamada | O que faz | Fonte |
|---|---|---|
| `fbq('init', PIXEL_ID)` | Registra um pixel. Pode ser chamada mais de uma vez para múltiplos pixels. | [Meta Pixel — advanced](https://developers.facebook.com/docs/meta-pixel/advanced/) **[FATO]** |
| `fbq('init', PIXEL_ID, {em: '...', ph: '...'})` | Registra com *advanced matching* manual (PII no navegador). | **[FATO-2ª]** ver §2.5 |
| `fbq('track', 'Lead', {...}, {eventID: '...'})` | Dispara evento **padrão** em **todos** os pixels inicializados. O 4º argumento carrega `eventID` para deduplicação. | [Deduplicação](https://developers.facebook.com/docs/marketing-api/conversions-api/deduplicate-pixel-and-server-events) **[FATO]** |
| `fbq('trackCustom', 'MeuEvento', {...})` | Dispara evento **customizado** (nome livre) em todos os pixels. | **[FATO]** |
| `fbq('trackSingle', PIXEL_ID, 'Purchase', {...})` | Dispara **só** no pixel indicado. | [Meta Pixel — advanced](https://developers.facebook.com/docs/meta-pixel/advanced/) **[FATO]** |
| `fbq('trackSingleCustom', PIXEL_ID, 'Step4', {})` | Evento custom em um pixel só. | **[FATO]** |
| `fbq('set', 'autoConfig', false, PIXEL_ID)` | Desliga o envio automático de metadados (advanced matching automático, coleta de botões). | **[FATO]** |

**Aviso literal da documentação da Meta:** *"Using the `track` function on pages that have multiple Pixels could produce over-firing or unexpected behavior"* — [developers.facebook.com/docs/meta-pixel/advanced](https://developers.facebook.com/docs/meta-pixel/advanced/) **[FATO]**.

Esse aviso é **a razão técnica número 1** pela qual um widget de chat não pode simplesmente chamar `fbq('track', ...)` na página de um cliente (ver §2.4).

Há ainda o fallback `<noscript>`, um GIF/IMG de 1×1:

```html
<img height="1" width="1" style="display:none"
     src="https://www.facebook.com/tr?id=<PIXEL_ID>&ev=PageView&noscript=1" />
```

A Leadster usa exatamente esse formato programaticamente quando `fbq` não existe **[FATO]** (ver §4.1).

### 2.2 Os 17 eventos padrão

Lista completa e literal da [referência oficial do Meta Pixel](https://developers.facebook.com/docs/meta-pixel/reference) **[FATO]**:

| # | Evento | Descrição oficial (resumida) | Relevância para chat |
|---|---|---|---|
| 1 | `AddPaymentInfo` | Informação de pagamento adicionada no checkout | Baixa |
| 2 | `AddToCart` | Produto adicionado ao carrinho | Baixa (exceto e-commerce com chat de venda) |
| 3 | `AddToWishlist` | Produto adicionado à lista de desejos | Baixa |
| 4 | `CompleteRegistration` | "When a registration form is completed" | **Alta** — pré-chat preenchido |
| 5 | `Contact` | Contato iniciado por telefone, SMS, e-mail **ou chat** | **Altíssima** — é o evento nomeado para chat |
| 6 | `CustomizeProduct` | Customização de produto | Baixa |
| 7 | `Donate` | Doação | Nicho |
| 8 | `FindLocation` | Busca por loja física | Nicho |
| 9 | `InitiateCheckout` | Entrada no fluxo de checkout | Baixa |
| 10 | `Lead` | "When a registration is completed" / envio de dados com aceite de contato | **Altíssima** — o evento comercial padrão |
| 11 | `Purchase` | Compra concluída | **Alta** (via conversão offline, ver §5.3) |
| 12 | `Schedule` | "When a person books an appointment" | **Alta** — chat que agenda |
| 13 | `Search` | Busca realizada | Média (busca na base de conhecimento) |
| 14 | `StartTrial` | Início de trial | Média |
| 15 | `SubmitApplication` | Envio de candidatura/aplicação | Média |
| 16 | `Subscribe` | Assinatura de serviço pago | Média |
| 17 | `ViewContent` | Visita a página relevante | Baixa (o site já faz) |

Mais o `PageView`, disparado pelo código base **[FATO-2ª]**.

**Object properties aceitas** pelos eventos padrão (também da referência oficial) **[FATO]**:
`content_category`, `content_ids`, `content_name`, `content_type`, `contents`, `currency`, `num_items`, `predicted_ltv`, `search_string`, `status`, `value`.

Observação prática **[INFERÊNCIA]**: `value` + `currency` são o que permite ao cliente rodar campanhas de **valor** (ROAS) em vez de campanhas de volume. Um chat que qualifica lead consegue estimar `value` (ex.: lead de plano enterprise vale 10× lead de plano básico) — isso é diferencial competitivo real e quase ninguém no mercado de chat entrega.

### 2.3 Que eventos fazem sentido em um chat

Proposta de mapeamento **[INFERÊNCIA]**, construída a partir dos eventos padrão da Meta (§2.2) e do que os fornecedores realmente disparam (§4):

| Momento no chat | Evento Meta sugerido | Padrão ou custom | Por quê |
|---|---|---|---|
| Widget carregado na página | *(nenhum)* | — | Ruído puro; o `PageView` do site já cobre |
| Bolha do chat exibida / convite proativo aparece | `ChatInviteShown` | custom | Só para diagnóstico de funil; não usar como conversão |
| Visitante **abre** o chat | `ChatOpened` | custom | Sinal fraco de intenção; útil como público de remarketing |
| Visitante **envia a primeira mensagem** | `Contact` | **padrão** | É literalmente a definição do evento `Contact` da Meta |
| Pré-chat preenchido (nome + e-mail/telefone) | `CompleteRegistration` | **padrão** | Formulário concluído |
| Lead identificado (temos e-mail **ou** telefone) | `Lead` | **padrão** | Evento de otimização principal |
| Lead qualificado por regra/agente/IA | `QualifiedLead` | custom (ou `Lead` com `status`) | Otimizar por lead *bom*, não por lead |
| Agendamento marcado pelo chat | `Schedule` | **padrão** | Direto |
| Venda fechada (dias depois) | `Purchase` | **padrão**, via CAPI offline | Fecha o ciclo, alimenta lances por valor |

**[INFERÊNCIA] Regra de ouro:** o evento de otimização de campanha deve ser o mais *raro e mais correlacionado com receita* que ainda tenha volume suficiente. Para a maioria dos clientes de chat isso é `Lead`; para os maduros, `QualifiedLead` ou `Purchase` offline.

### 2.4 Como um widget de terceiro dispara no pixel do CLIENTE

Este é o ponto de arquitetura mais delicado de toda a frente. Há três estratégias no mercado, e elas não são equivalentes.

#### Estratégia A — reutilizar o `fbq` global do site

```js
if (typeof window.fbq === 'function') {
  window.fbq('track', 'Lead', { content_name: 'chat' }, { eventID: evtId });
}
```

- **Prós:** zero configuração para o cliente; o evento entra com todos os pixels que o cliente já configurou; herda cookies `_fbp`/`_fbc` do domínio do cliente.
- **Contras:** dispara em **todos** os pixels inicializados na página (o aviso literal da Meta em §2.1). Em sites de agência com 3 pixels (cliente, agência, parceiro), o evento vaza para todos.
- **Mitigação:** usar `trackSingle` com o Pixel ID que o cliente configurou no painel do chat, e ler os pixels presentes na página para validar.

**A Leadster faz exatamente essa leitura** — trecho literal do bundle **[FATO]**:

```js
r = () => {
  if (void 0 === window.fbq) return [];
  const t = window.fbq.getState().pixels.map(t => t.id);
  return t.length > 0 ? t : [];
}
```

Ou seja: `window.fbq.getState().pixels` é usado para **descobrir** quais pixels já existem na página antes de decidir se precisa instalar o seu.

#### Estratégia B — carregar o próprio pixel com o ID do cliente

```js
fbq('init', '<PIXEL_ID_DO_CLIENTE>');   // instalado pelo widget
fbq('track', 'Lead');
```

- **Prós:** funciona mesmo se o cliente não tiver pixel no site; controle total.
- **Contras:** **duplicidade grave** se o site já tiver o mesmo pixel — dois `init` do mesmo ID e um `track` sem `trackSingle` produzem eventos duplicados; e `PageView` duplicado infla métricas de tráfego.

**A Leadster resolve isso com um guard** — trecho literal **[FATO]**:

```js
installMetaPixel(t, e) {   // t = pixelId, e = skipPageView
  ... snippet padrão ...
  fbq("init", t),
  e || fbq("track", "PageView")
}
```

O segundo argumento existe justamente para **não** disparar `PageView` de novo. E há o guard duro no fallback:

```js
insertMetaPixel(t, e) {
  if (fbq) return;                      // se já existe fbq, não injeta o <img>
  const n = document.createElement("img");
  n.src = "https://www.facebook.com/tr?id=" + t + "&ev=" + e + "&noscript=1";
  ...
}
```

#### Estratégia C — não tocar no pixel; empurrar para o `dataLayer` e deixar o GTM do cliente decidir

```js
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({ event: 'chatspx_lead', chat_inbox: 'site', lead_email_hash: '...' });
```

- **Prós:** zero risco de duplicidade, zero PII exposta se você só mandar hash, e o cliente mantém governança de tags (é o que times de dados exigem).
- **Contras:** exige que o cliente configure a tag no GTM — atrito de onboarding.

**Praticamente todo fornecedor sério oferece a Estratégia C, e os melhores oferecem A/B *e* C.** Ver §4.10.

**[INFERÊNCIA] Recomendação para o ChatSPX:** oferecer as três, nessa ordem de precedência em runtime:
1. Se o cliente configurou Pixel ID no painel **e** existe `window.fbq` → `trackSingle` naquele ID.
2. Se configurou Pixel ID e **não** existe `fbq` → instalar pixel com `skipPageView = true` e disparar `trackSingle`.
3. Sempre, em paralelo e independentemente do item 1/2 → `dataLayer.push` com um nome de evento prefixado (`chatspx_*`).

E **sempre** mandar o mesmo `event_id` para o CAPI server-side (§2.6).

### 2.5 Conversions API (CAPI)

#### Por que existe

Três forças criaram a CAPI **[FATO-2ª]**, corroboradas por dados de mercado:

1. **Bloqueadores de anúncio:** ~31,5% dos visitantes rodam bloqueadores que impedem o Meta Pixel de carregar — [Seresa / dados de mercado 2026](https://seresa.io/seed/data-loss-adblockers/adblocker-impact-ad-blocker-facebook-pixel) **[FATO-2ª]**.
2. **ITP / navegadores:** Safari bloqueia cookies de terceiros por padrão e limita armazenamento escrito por script — [WebKit, "Full Third-Party Cookie Blocking and More"](https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/) **[FATO]**.
3. **iOS / App Tracking Transparency:** eventos server-side não passam pelo opt-out de rastreamento do navegador/app **[FATO-2ª]**.

Resultado agregado citado por fontes de mercado: pixels client-side subcontam conversões em **20–40%**; setups server-side chegam a 85–95% de precisão de atribuição contra 70–80% do browser **[FATO-2ª]** ([Cometly](https://www.cometly.com/post/ad-blockers-preventing-conversion-tracking), [Improvado](https://improvado.io/blog/what-is-tracking-pixel)). Tratar esses números como ordem de grandeza, não como medida exata.

#### Como se chama a API

Endpoint **[FATO]** ([Meta — Using the API](https://developers.facebook.com/docs/marketing-api/conversions-api/using-the-api)):

```
POST https://graph.facebook.com/v25.0/<PIXEL_ID>/events?access_token=<ACCESS_TOKEN>
```

Exemplo literal da documentação:

```bash
curl -X POST \
  -F 'data=[
       {
         "event_name": "Purchase",
         "event_time": 1762902353,
         "user_data": {
           "em": ["309a0a5c3e211326ae75ca18196d301a9bdbd1a882a4d2569511033da23f0abd"],
           "ph": ["254aa248acb47dd654ca3ea53f48c2c26d641d23d7e2e93a1ec56258df7674c4"],
           "client_ip_address": "123.123.123.123",
           "client_user_agent": "$CLIENT_USER_AGENT"
         },
         "custom_data": { "currency": "usd", "value": 123.45 },
         "event_source_url": "http://jaspers-market.com/product/123",
         "action_source": "website"
       }
     ]' \
  -F 'access_token=<ACCESS_TOKEN>' \
https://graph.facebook.com/v25.0/<PIXEL_ID>/events
```

Limites e regras **[FATO]** (mesma fonte):

| Regra | Valor |
|---|---|
| Eventos por request | até **1.000** em `data` |
| Janela de `event_time` | até **7 dias** antes do envio |
| Eventos offline / `physical_store` | enviar em até **62 dias** |
| `action_source` válidos | `website`, `app`, `physical_store`, `offline` (e `business_messaging` para CTWA — ver §2.10) |
| `test_event_code` | **só** para testes; "You need to remove it when sending your production payload" |

#### Parâmetros de identificação do usuário (`user_data`)

Tabela completa da [documentação oficial de customer information parameters](https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/customer-information-parameters) **[FATO]**:

| Campo | Hash SHA-256? | Normalização exigida | Observação |
|---|---|---|---|
| `em` (e-mail) | **Sim** | trim + lowercase | O parâmetro de maior impacto em matching |
| `ph` (telefone) | **Sim** | só dígitos, **com código do país** (ex.: `16505551212`) | 2º de maior impacto |
| `fn` (nome) | **Sim** | lowercase, sem pontuação, UTF-8 se houver acento | |
| `ln` (sobrenome) | **Sim** | idem | |
| `db` (nascimento) | **Sim** | `YYYYMMDD` | |
| `ge` (gênero) | **Sim** | `f` / `m` | |
| `ct` (cidade) | **Sim** | lowercase, sem espaço/pontuação (`saopaulo`) | |
| `st` (estado) | **Sim** | código de 2 letras, lowercase (`sp`) | Doc oficial cita ANSI dos EUA; para BR usar UF |
| `zp` (CEP) | **Sim** | lowercase, sem espaço/hífen | |
| `country` | **Sim** | ISO 3166-1 alpha-2 lowercase (`br`) | "Always include your customers' countries" |
| `external_id` | **Recomendado** | consistente entre envios | Ex.: ID do contato no ChatSPX |
| `client_ip_address` | **Nunca** | IPv4/IPv6 válido | "Must never be hashed" |
| `client_user_agent` | **Nunca** | string do navegador | "Required for website events" |
| `fbc` | **Nunca** | `fb.{index}.{timestamp}.{fbclid}` | Ver §2.7 |
| `fbp` | **Nunca** | `fb.{index}.{timestamp}.{random}` | Ver §2.7 |
| `subscription_id` | Não | string | |
| `fb_login_id` | Não | integer | |
| `lead_id` | Não | integer | ID de Meta Lead Ads |
| `anon_id`, `madid` | Não | — | Só eventos de app |
| `page_id`, `page_scoped_user_id` | Não | — | Messenger |
| `ctwa_clid` | Não | string | **Click-to-WhatsApp** — ver §2.10 |
| `ig_account_id`, `ig_sid` | Não | — | Instagram |

#### Por que o chat é o candidato PERFEITO para CAPI

Este é o argumento central da frente. Desdobrando **[INFERÊNCIA]**, ancorado nos fatos acima:

1. **O chat coleta e-mail e telefone como parte do produto, não como enxerto.** Pré-chat, bot de qualificação e o próprio agente pedindo "me passa seu WhatsApp" produzem `em` e `ph` — os dois campos de maior peso em EMQ (§2.8). Um e-commerce só tem isso no checkout; um site institucional, quase nunca.

2. **O chat coleta esses dados de forma *estruturada e validada*.** O ChatSPX já valida telefone no pré-chat (`startsWithPlus`, `isValidPhoneNumber` — `app/javascript/widget/components/PreChat/`, **[FATO]** verificado no repo). Dado validado hasheia melhor: telefone sem código de país simplesmente não casa.

3. **O servidor do chat já tem IP e user-agent do visitante.** `client_ip_address` e `client_user_agent` são obrigatórios/recomendados para eventos de site e o backend do chat os tem naturalmente na requisição do widget. O Chatwoot já parseia o user-agent (`browser_params` em `app/controllers/api/v1/widget/base_controller.rb`, **[FATO]**).

4. **O chat sobrevive ao bloqueador.** Se o Pixel foi bloqueado, o evento CAPI ainda sai — porque quem envia é o servidor do chat, não o navegador. O chat funciona mesmo com bloqueador (é uma conversa, não um anúncio).

5. **O chat conhece o desfecho.** Diferente de um formulário, o chat sabe se o lead virou oportunidade, se agendou, se comprou. Isso é matéria-prima direta para `Purchase` offline e conversões de valor (§5.3).

6. **O chat tem identidade persistente própria.** `contact_id` do ChatSPX é um `external_id` estável, que a Meta recomenda enviar (hash recomendado) e que amarra múltiplas conversas do mesmo contato.

**[INFERÊNCIA] Conclusão:** um chat que faz CAPI corretamente entrega ao cliente um EMQ estruturalmente melhor do que o site do cliente consegue sozinho. Esse é um argumento de venda, não só uma feature.

### 2.6 Deduplicação: `event_id`, janela de 48 h e o fallback por `fbp`

Regra literal da [documentação de deduplicação](https://developers.facebook.com/docs/marketing-api/conversions-api/deduplicate-pixel-and-server-events) **[FATO]**:

> *"We determine if events are identical based on their **ID** and **name**."*

Ou seja, a chave de deduplicação é o par **(`event_id`, `event_name`)**. No navegador:

```js
fbq('track', 'Lead', { value: 100, currency: 'BRL' }, { eventID: '3f1c...-uuid' });
```

No servidor, o mesmo `event_id` e o mesmo `event_name`:

```json
{ "event_name": "Lead", "event_id": "3f1c...-uuid", "event_time": 1786000000, "action_source": "website", "user_data": { "em": ["<sha256>"], "fbp": "fb.1.1786000000.123456789" } }
```

Pontos críticos **[FATO]**:

- Janela: *"events are only deduplicated if they are received within 48 hours of when we receive the first event with a given `event_id`"*.
- Fallback: sem `event_id`, a Meta tenta deduplicar por **`event_name` + `fbp`** (e/ou `external_id`), mas *"only works for deduplicating events sent first from the browser and then through the server"*.
- **[FATO-2ª]** Deduplicação **não** olha `em`, `ph` ou outros identificadores — esses servem para *matching*, não para dedup ([Watsspace](https://watsspace.com/blog/meta-conversions-api-deduplication-event_id/)).
- **[FATO-2ª]** Recomenda-se `event_id` como UUID v4 ou ULID, gerado **uma vez por ação do usuário** e propagado para os dois caminhos.
- **[FATO-2ª]** Jobs em lote com atraso longo quebram a dedup na prática, porque o evento server pode chegar fora da janela ou depois de o Meta já ter contabilizado.

**[INFERÊNCIA] Para o ChatSPX:** o `event_id` deve nascer no **backend** (junto com o registro do evento na tabela de tracking), ser devolvido ao widget e propagado ao SDK para o `fbq`. Nascer no navegador e subir é possível, mas fica frágil se o navegador for fechado antes do POST.

### 2.7 `fbp`, `fbc`, `fbclid`: os três identificadores

| Item | O que é | Onde vive | Formato |
|---|---|---|---|
| `fbclid` | Parâmetro de query que a Meta adiciona à URL de destino quando alguém clica no anúncio | URL (`?fbclid=...`) | opaco |
| `_fbc` | Cookie derivado do `fbclid` | cookie first-party do domínio do cliente | `fb.{subdomainIndex}.{timestamp}.{fbclid}` |
| `_fbp` | Cookie de identificação do navegador criado pelo pixel | cookie first-party | `fb.{subdomainIndex}.{timestamp}.{random}` |

**[FATO]** Formatos confirmados na [doc de customer information parameters](https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/customer-information-parameters).

**Como a Leadster cria o `_fbc` quando ele não existe** — código literal do bundle **[FATO]**:

```js
Zi = () => {
  const t = $i("_fbc", null, !1);            // lê cookie _fbc
  if (t) return t;
  const e = new URLSearchParams(window.location.search).get("fbclid");
  if (!e) return null;
  let n = 0;
  const i = window.location.hostname.split(".");
  2 === i.length ? n = 1 : i.length > 2 && (n = i.length - 1);   // subdomainIndex
  const o = `fb.${n}.${Date.now()}.${e}`;
  return Qi("_fbc", o, { days: 90, shouldParseJson: !1 }), o
}
```

Isto é uma implementação de referência do algoritmo de `subdomainIndex` e do TTL de 90 dias. **[INFERÊNCIA]** É exatamente o que o ChatSPX precisaria replicar no SDK (no `window` do cliente, não no iframe) para não depender do pixel do cliente existir.

Regras de higiene **[FATO-2ª]** ([Adsuploader](https://adsuploader.com/blog/meta-conversions-api), [Cometly](https://www.cometly.com/post/facebook-conversion-api-setup)):
- **Nunca** hashear `fbp`/`fbc` — hashear quebra o matching por completo.
- **Nunca** fabricar `fbc` sem um `fbclid` real.
- Incluir `fbp`/`fbc` nos eventos server mesmo quando há `event_id`, porque eles elevam EMQ e ligam o evento ao clique no anúncio.

### 2.8 Event Match Quality (EMQ)

**[FATO-2ª]** ([Triple Whale](https://www.triplewhale.com/blog/event-match-quality), [CustomerLabs](https://www.customerlabs.com/blog/improve-your-event-match-quality-from-ok-to-great/), [SignalBridge](https://www.signalbridgedata.com/blog/what-is-event-match-quality)):

| Faixa | Leitura |
|---|---|
| ≥ 8,0 | "Great" — matching de alta confiança |
| 6,0 – 7,9 | "Good" |
| 4,0 – 5,9 | "OK" — matching fraco |
| < 4,0 | Ruim |

Alvo prático citado: **≥ 6,0 para todos os eventos, ≥ 8,0 para `Purchase`**. O item de maior impacto marginal citado é **adicionar telefone hasheado**, que costuma levar o score para a faixa 7,0–8,5.

Parâmetros que compõem o score: e-mail, telefone, nome, sobrenome, cidade, estado, CEP, país, gênero, data de nascimento, `external_id`, `client_ip_address`, `client_user_agent`.

**[INFERÊNCIA]** Um chat bem instrumentado consegue naturalmente: `em`, `ph`, `fn`, `ln`, `external_id`, `client_ip_address`, `client_user_agent`, `fbp`, `fbc` — nove sinais. Isso deveria colocar o cliente na faixa 8+ sem esforço adicional dele. **Vale expor o EMQ estimado no painel do ChatSPX como métrica de saúde da integração.**

### 2.9 CAPI Gateway: o atalho da Meta

**[FATO-2ª]** ([Enalitica](https://enalitica.com/blog/meta-capi-gateway), [Jon Loomer](https://www.jonloomer.com/facebook-conversions-api-gateway/), [Pix-Vu](https://pix-vu.com/blog/meta-conversions-api-gateway-simple-setup-guide)):

- É uma aplicação pré-construída da Meta que o anunciante instala **na própria nuvem** (AWS via EKS/ECS Express, ou GCP).
- Ela observa os eventos do Pixel no navegador e envia uma cópia server-side dos mesmos eventos.
- O software é gratuito; *"the only cost of the Conversions API Gateway is the associated cloud resource or partner fees"*. Estimativas de custo citadas: US$ 5–30/mês self-hosted, podendo ir a US$ 400+/mês em volume alto.
- Setup a partir do Events Manager; criação da stack leva 30–40 min.

**[INFERÊNCIA] Por que isso importa para o ChatSPX:** o CAPI Gateway é o principal *concorrente* de uma feature nativa. Mas ele **só espelha o que o pixel já viu** — logo, ele não resolve o problema do chat (evento que nasce no servidor do chat, com PII que o navegador não tem, ou evento que acontece dias depois). O posicionamento do ChatSPX é: *"a CAPI que sabe coisas que o navegador nunca soube"*.

### 2.10 Click-to-WhatsApp, `ctwa_clid` — o caso mais relevante para o ChatSPX

**[FATO]** O parâmetro `ctwa_clid` existe oficialmente nos *customer information parameters* da CAPI: *"Click ID for ads that click to WhatsApp"* — [doc oficial](https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/customer-information-parameters).

**[FATO-2ª]** ([MetricFixer](https://metricfixer.com/publications/analytics-conversion-tracking/track-click-to-whatsapp-ads-campaign-ad-creative-without-website), [WOZTELL](https://support.woztell.com/portal/en/kb/articles/wa-conversion-flow), [Whapi](https://whapi.cloud/blog/track-click-to-whatsapp-ctwa-clid)):

- Quando alguém clica num anúncio Click-to-WhatsApp, a Meta injeta o `ctwa_clid` no **webhook da mensagem** (objeto `referral` no `contextInfo`), **não** na URL.
- Para o evento CAPI ser atribuído ao anúncio, o payload precisa de `ctwa_clid`, `action_source: "business_messaging"` e `messaging_channel: "whatsapp"`.
- Sem isso, o evento é aceito mas **não** é associado ao clique — o algoritmo não aprende e o CPL sobe.

**[INFERÊNCIA] Implicação direta e grande para o ChatSPX:** a plataforma já é forte em WhatsApp. Se o ChatSPX capturar o `referral.ctwa_clid` do webhook do WhatsApp Cloud/WAHA e emitir eventos CAPI `business_messaging`, ele resolve um problema que os clientes hoje **não conseguem** resolver sozinhos (a "attribution black hole" do CTWA). Isso pode valer mais comercialmente do que o pixel do chat web. Registrar como frente irmã desta.

**[NÃO VERIFICADO]** Se o webhook do WhatsApp Cloud API entregue hoje ao ChatSPX já traz o objeto `referral` completo, e se o WAHA repassa esse campo. Precisa de checagem no código de ingestão de webhook (fora do escopo desta task, que é estudo de mercado).

---
## 3. Google

### 3.1 gtag.js x GTM x GTM server-side

Três camadas distintas que o mercado confunde o tempo todo:

| Camada | O que é | Global JS | Quem controla |
|---|---|---|---|
| **gtag.js** | Biblioteca da Google Tag, carregada de `https://www.googletagmanager.com/gtag/js?id=<ID>` | `window.gtag`, `window.dataLayer` | Desenvolvedor do site |
| **GTM (web container)** | Gerenciador de tags; carrega `gtm.js` e escuta o `dataLayer` | `window.dataLayer`, `window.google_tag_manager` | Time de marketing/dados |
| **GTM server-side (sGTM)** | Container que roda em servidor próprio; recebe requests HTTP e distribui para destinos | — | Time de dados/infra |

**[FATO]** O `gtag` é, por baixo, um wrapper de `dataLayer.push(arguments)`. Confirmado literalmente no bundle da Leadster, que reproduz o snippet oficial:

```js
installGa4(t) {
  const e = document.createElement("script");
  e.src = "https://www.googletagmanager.com/gtag/js?id=" + t;
  document.head.appendChild(e);
  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function () { dataLayer.push(arguments) };
  gtag("js", new Date);
  gtag("config", t);
}
```

**[INFERÊNCIA] Consequência prática importante:** se um widget de terceiro faz `dataLayer.push(['config', ...])` mal-feito ou sobrescreve `window.gtag`, ele pode quebrar a medição do site inteiro do cliente. Qualquer implementação nossa tem que ser **aditiva** (`window.gtag = window.gtag || ...`), nunca destrutiva.

### 3.2 Eventos GA4 do ciclo de vida do lead

O GA4 tem uma família de eventos **recomendados** feita sob medida para geração de leads. Fonte primária: [Recommended events — Google](https://developers.google.com/analytics/devguides/collection/ga4/reference/events); detalhamento por evento confirmado em [Stape](https://stape.io/news/ga4-new-recommended-events-lead-generation) **[FATO-2ª para os parâmetros por evento]**.

| Evento | Quando disparar | Parâmetros | No chat |
|---|---|---|---|
| `generate_lead` | Usuário atinge o critério de lead qualificado / envia formulário | `currency`, `value`, `lead_source`, `items` | **Principal.** Dispara quando temos e-mail/telefone |
| `qualify_lead` | Lead marcado como promissor | `currency`, `value` | Quando bot/agente/IA qualifica |
| `working_lead` | Usuário contata ou é contatado por um representante | `currency`, `value`, `lead_status` | Quando o agente humano assume a conversa |
| `disqualify_lead` | Lead marcado como inadequado | `currency`, `value`, `disqualified_lead_reason` | Motivo de descarte |
| `close_convert_lead` | Lead virou cliente | `currency`, `value` | Venda fechada (server-side) |
| `close_unconvert_lead` | Lead não converteu | `currency`, `value`, `unconvert_lead_reason` | Perda |
| `sign_up` | Usuário criou conta | `method` | Cadastro via chat |
| `login` | Usuário fez login | `method` | Raro em chat |

Exemplo oficial de `generate_lead` **[FATO]**:

```js
gtag("event", "generate_lead", {
  currency: "USD",
  value: 30.03,
  lead_source: "Trade show",
  items: [ { item_id: "SKU_12345", item_name: "Stan and Friends Tee" } ]
});
```

Exemplo oficial de `sign_up` **[FATO]**:

```js
gtag("event", "sign_up", { method: "Google" });
```

**[INFERÊNCIA]** Esta família de 6 eventos é **exatamente** o modelo mental de um chat de qualificação. Nenhum fornecedor de chat que estudei usa essa família de forma completa — todos param em `generate_lead` ou em eventos custom. Há espaço para o ChatSPX se posicionar como "o chat que fala GA4 nativo do lead ao fechamento".

Restrições de nomenclatura do GA4 **[FATO]** ([Measurement Protocol — sending events](https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events)):
- nome do evento: máximo **40 caracteres**, apenas alfanuméricos e `_`;
- até **25 parâmetros** por evento;
- valor de parâmetro: até **100 caracteres** (500 no GA360).

### 3.3 `client_id` e `session_id`: a chave de tudo

Este é o detalhe técnico que separa uma integração GA4 boa de uma inútil.

**[FATO]** ([Simo Ahava — Session attribution with GA4 Measurement Protocol](https://www.simoahava.com/analytics/session-attribution-with-ga4-measurement-protocol/)) Para um evento server-side ser atribuído corretamente, são necessários três elementos:

> *"The Client ID, which you can get from BigQuery (user_pseudo_id), the _ga cookie, or using the GTAG GET API Custom Template."*
> *"The Session ID, which you can get from BigQuery (event parameter named ga_session_id), the _ga_<measurement ID> cookie"*
> *"The timestamp (in microseconds) of the event, set to a maximum 72 hours into the past"*

**[FATO-2ª]** Eventos do Measurement Protocol **não herdam** propriedades de sessão automaticamente; sem `session_id`, o evento chega no GA4 mas perde `source/medium/campaign` — o famoso "conversão que aparece como (direct)".

#### Como capturar client_id e session_id no navegador

A API oficial é `gtag('get', ...)`. A Leadster implementa exatamente isso, com timeout e fallback para cookie — código literal do bundle **[FATO]**:

```js
Xi = async function (t, e, n, i = t => t) {
  try {
    return "function" == typeof window.gtag && t
      ? new Promise(n => {
          window.gtag("get", t, e, t => { n(t || null) });
          setTimeout(() => n(null), 1e3);              // timeout de 1 segundo
        }).then(e => (e ? i(e) : n(t)))
      : n(t)
  } catch { return null }
}

to = t => Xi(t, "client_id", () => $i("_ga", null, !1) || null);       // fallback cookie _ga
eo = t => Xi(t, "session_id", t => {
  if (!t) return null;
  const e = t.replace("G-", "");                                       // _ga_XXXXXXX
  const n = $i(`_ga_${e}`, ...)
  ...
});
```

Traduzindo **[INFERÊNCIA]**: pede `client_id` e `session_id` ao `gtag` do site; se o `gtag` não responder em 1 s, cai para leitura direta dos cookies `_ga` e `_ga_<MEASUREMENT_ID sem o "G-">`. É uma implementação de referência muito boa e vale copiar o padrão (não o código).

E de onde sai o Measurement ID quando o cliente não informou? Do próprio `dataLayer` — código literal **[FATO]**:

```js
const e = (Array.isArray(window.dataLayer)
  ? [...new Set(window.dataLayer
      .filter(t => Array.isArray(t) && "config" === t[0] && t[1])
      .map(t => t[1]))]
  : []).at(-1) ?? null;
```

Ou seja: varre o `dataLayer` procurando entradas `['config', '<ID>']` e pega a última. **[INFERÊNCIA]** Autoconfiguração real: o cliente não precisa digitar o ID do GA4 se ele já está na página.

### 3.4 Measurement Protocol (GA4 server-side)

**[FATO]** ([doc oficial](https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events)):

```
POST https://www.google-analytics.com/mp/collect?measurement_id=<G-XXXX>&api_secret=<SECRET>
```
Para dados coletados na UE: `https://region1.google-analytics.com/mp/collect`.

Payload:

```json
{
  "client_id": "1234567.7654321",
  "user_id": "contact_98765",
  "timestamp_micros": 1786000000000000,
  "consent": { "ad_user_data": "GRANTED", "ad_personalization": "DENIED" },
  "user_properties": { "lead_status": { "value": "qualified" } },
  "events": [{
    "name": "generate_lead",
    "params": {
      "session_id": "1786000000",
      "engagement_time_msec": 100,
      "currency": "BRL",
      "value": 250.0,
      "lead_source": "chatspx_widget"
    }
  }]
}
```

Limites oficiais **[FATO]**:

| Limite | Valor |
|---|---|
| Eventos por request | 25 |
| Parâmetros por evento | 25 |
| Tamanho do corpo | < 130 kB |
| Backdating | até 72 h |
| Requisições não-conversão | 100 milhões/hora por propriedade |
| Prazo para atribuição correta | evento deve chegar em até 48 h |

**Limitações que precisam estar escritas no manual do produto [FATO-2ª]:**
- Sem `session_id` → sem stitching → conversão sem origem de campanha.
- Sem `engagement_time_msec` → pode não aparecer no relatório Tempo Real (a documentação afirma que é necessário; há relatos de que na prática nem sempre).
- **Não existe** deduplicação nativa no GA4 como na Meta. Se você mandar `generate_lead` pelo `gtag` e de novo pelo MP, o GA4 conta **duas vezes**. O controle é seu.
- O `api_secret` é credencial sensível: *"manter em sigilo absoluto"* — nunca pode ir para o navegador.

**[INFERÊNCIA]** Para o ChatSPX isso define uma regra dura de arquitetura: **ou** o evento GA4 vai pelo navegador **ou** vai pelo Measurement Protocol — nunca os dois para o mesmo evento lógico. A escolha correta depende de haver ou não `gtag` na página: se há, mandar pelo navegador (herda sessão de graça) e usar o MP só para eventos que acontecem depois (qualificação, venda).

### 3.5 `dataLayer` e GTM: a interface *de facto* do mercado

O padrão universal:

```js
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({
  event: 'chatspx_lead',              // nome que vira o gatilho no GTM
  chat_inbox_id: 42,
  chat_conversation_id: 987,
  lead_source: 'organic',
  value: 250,
  currency: 'BRL'
});
```

No GTM, o cliente cria um **acionador do tipo "Evento personalizado"** com o nome exato (`chatspx_lead`) ou com regex, e liga a uma tag GA4/Google Ads/Meta.

Como os fornecedores documentam isso:

- **Tidio [FATO-2ª]**: prefixa todos os eventos com `tidio_` e documenta que se pode capturar tudo com a regex `^tidio_\w+` ([help.tidio.com](https://help.tidio.com/hc/en-us/articles/9049293832220-Integration-with-Google-Tag-Manager)). Categorias de evento: `widget`, `prechat`, `conversation`.
- **Drift [FATO-2ª]**: documenta `drift.on('startConversation', ...)` e recomenda o `dataLayer.push` com `eventCategory`/`eventAction`/`eventLabel` ([devdocs.drift.com/docs/drift-events](https://devdocs.drift.com/docs/drift-events)).
- **HubSpot [FATO-2ª]**: `window.HubSpotConversations.on('conversationStarted', payload => dataLayer.push({event:'hs_chat_started'}))` ([community HubSpot](https://community.hubspot.com/t5/Reporting-Analytics/HubSpot-Chat-amp-Google-Analytics-Event-Tracking/m-p/370205)).
- **Leadster [FATO]**: além do `gtag`, empurra `dataLayer.push({event: 'new_lead'})` e `dataLayer.push({event: <nome do evento Meta configurado>})` — ver §4.1.

**[INFERÊNCIA] Boas práticas de nomenclatura para o ChatSPX:**
1. Prefixo fixo e único (`chatspx_`) para permitir regex de captura em massa.
2. `snake_case`, ≤ 40 caracteres (limite do GA4).
3. Nomes estáveis: um evento renomeado quebra o GTM de todos os clientes.
4. Documentar cada evento com: nome, quando dispara, parâmetros, tipo, exemplo de payload — em uma página pública.
5. Nunca colocar PII crua no `dataLayer` (ele é legível por qualquer script da página). Só hash ou identificadores opacos.

### 3.6 GTM server-side (sGTM)

**[FATO]** ([Google — server-side tagging](https://developers.google.com/tag-platform/tag-manager/server-side)): *"Server-side tagging is a way to instrument your tags to measure user activity wherever it happens."* Benefícios oficialmente listados: *"Improve page performance"*, *"Unlock more detailed user privacy controls"*, *"Improve data quality"*. Setup em **Cloud Run** ou **App Engine**, ou "a platform of your choice", com domínio próprio (*"set up your own domain"*).

Custo de mercado **[FATO-2ª]**:

| Opção | Preço citado | Fonte |
|---|---|---|
| Stape (gerenciado) | a partir de US$ 17–20/mês; free tier 10k req/mês; ~US$ 100/mês para 5M req | [TagFly](https://tagfly.io/blog/stape-alternatives-priced-and-the-request-billing-trap/), [Capterra](https://www.capterra.com/p/10028692/Global-Server-GTM-Hosting/) |
| Stape + CAPI Gateway | US$ 17 + US$ 8/mês, TCO estimado US$ 75–275+/mês | [SignalBridge](https://www.signalbridgedata.com/blog/server-side-tracking-pricing-comparison) |
| Google Cloud Run | custo de infra, variável | [alexisvantal](https://alexisvantal.com/articles/server-side-gtm-cost/) |
| RudderStack self-hosted | só infra, ~US$ 200–500/mês em escala | [Improvado](https://improvado.io/blog/open-source-segment-alternative) |
| RudderStack cloud | free até 1M eventos/mês; Starter US$ 500/mês (3M eventos) | idem |
| Jitsu | open source, binário Go, ~50 destinos | idem |

**Alerta de armadilha [FATO-2ª]:** a contagem de "requests" do Stape inclui *carregamentos de script* (`gtm.js`, `gtag.js`) servidos pelo container, além de bots, crawlers e sessões de preview — não só hits de conversão. Isso costuma dobrar a conta em relação à estimativa ingênua.

**[INFERÊNCIA] Quando sGTM vale a pena para um cliente de chat:** quando ele já gasta o suficiente em mídia para que 20–30% de perda de sinal seja materialmente caro, **e** já tem quem opere. Para a base típica do ChatSPX (PMEs brasileiras), sGTM é overkill: o valor está em o **ChatSPX** ser o servidor que envia CAPI/MP, entregando o benefício do server-side sem o cliente ter que operar container nenhum. Esse é o argumento de posicionamento mais forte de toda esta pesquisa.

### 3.7 Google Ads: conversões, gclid, Enhanced Conversions e import offline

#### Identificadores de clique

| Parâmetro | Quando aparece |
|---|---|
| `gclid` | Clique padrão em anúncio do Google (web) |
| `gbraid` | Tráfego de app→web em iOS (privacidade) |
| `wbraid` | Tráfego web→app em iOS |
| `_gcl_aw` | Cookie first-party derivado do `gclid` |

**[FATO]** A Leadster gera o `_gcl_aw` quando não existe — código literal do bundle:

```js
(() => {
  const t = $i("_gcl_aw", null, !1);
  if (t) return t;
  const e = new URLSearchParams(window.location.search).get("gclid");
  if (!e) return null;
  const n = `GCL.${Math.floor(Date.now() / 1e3)}.${e}`;
  Qi("_gcl_aw", n, { days: 90, shouldParseJson: !1 })
})();
```

Formato `GCL.{unix_seconds}.{gclid}`, TTL de 90 dias — o mesmo TTL do próprio `gclid` no Google (ver abaixo).

#### Conversão client-side no Google Ads

```js
gtag('event', 'conversion', {
  send_to: 'AW-123456789/AbC-D_efG-h12_34-567',
  value: 250.0,
  currency: 'BRL',
  transaction_id: 'chatspx-lead-987'
});
```

**[FATO]** A Leadster dispara exatamente essa forma:

```js
this.metadata.gtagConversionId && gtag("event", "conversion", {
  send_to: this.metadata.gtagConversionId,
  event_callback: () => {}
})
```

#### Enhanced Conversions (web)

**[FATO]** ([Google Ads Help 9888656](https://support.google.com/google-ads/answer/9888656)): *"Enhanced conversions is a feature that can improve the accuracy of your conversion measurement"*, enviando dados hasheados do cliente. O hashing é *"a secure one-way hashing algorithm"* SHA-256.

Formato do payload via gtag **[FATO-2ª]** ([Google Ads Help 13262500](https://support.google.com/google-ads/answer/13262500), [TAGGRS](https://taggrs.io/docs/server-side-tracking/google-ads/enhanced-conversions)):

```js
gtag('set', 'user_data', {
  "sha256_email_address": "<sha256(lowercase(trim(email)))>",
  "sha256_phone_number": "<sha256(E.164)>",
  "address": {
    "sha256_first_name": "<sha256>",
    "sha256_last_name": "<sha256>",
    "city": "sao paulo",
    "region": "SP",
    "postal_code": "01310-000",
    "country": "BR"
  }
});
```

Regras **[FATO-2ª]**:
- Telefone em **E.164**: 11 a 15 dígitos, com `+` e código do país, sem hífen/parênteses/espaço.
- Mínimo aceitável: e-mail hasheado.
- `city`, `region`, `postal_code`, `country` vão **sem hash**.

**Note a simetria com a Leadster [FATO]**: o payload que ela manda ao próprio backend usa exatamente esses nomes de campo do Google:

```js
$a = async t => ({
  platform: "google_analytics",
  google_analytics_event_options: t.google_analytics_event_options,
  credential_id: t.google_analytics_credential_id,
  client_id: await to(t.google_analytics_measurement_id),
  session_id: await eo(t.google_analytics_measurement_id),
  sha256_email_address: await fo({ key: t?.email_field_google_analytics }),
  sha256_phone_number:  await bo({ key: t?.phone_field_google_analytics }),
  sha256_first_name:    await vo({ key: t?.name_field_google_analytics }),
  sha256_last_name:     await yo({ key: t?.name_field_google_analytics }),
  city:   await go({ key: t?.city_field_google_analytics }),
  region: await mo({ key: t?.state_field_google_analytics }),
  device: { category, language, screen_resolution, operating_system, browser },
  referrer_url: w(), current_url: x(), test_mode: ...
})
```

**[INFERÊNCIA]** Isso indica fortemente que o backend da Leadster usa esse payload tanto para o Measurement Protocol do GA4 (`client_id`/`session_id`/`device`) quanto para Enhanced Conversions do Google Ads (`sha256_*`). É a mesma coleta servindo dois destinos — arquitetura que vale imitar.

#### Enhanced Conversions **for Leads**

**[FATO]** ([Google Ads Help 13258081](https://support.google.com/google-ads/answer/13258081)): usa SHA-256 sobre dados first-party (e-mail, telefone E.164, nome, endereço) antes de enviar ao Google. Nota literal relevante: *"Enhanced conversions for web and leads are now combined into a single on/off setting. Starting from April 2026, Google Ads accepts user-provided data from website tags, Data Manager, and API connections."*

**[INFERÊNCIA]** A unificação em 2026 simplifica o produto: basta o ChatSPX conseguir enviar `user_data` hasheado consistentemente e o mesmo dado serve web e leads.

#### Import de conversões offline

**[FATO-2ª]** ([Google Ads API — upload offline](https://developers.google.com/google-ads/api/docs/conversions/upload-offline), [Google Ads Help 7012522](https://support.google.com/google-ads/answer/7012522)):

| Regra | Valor |
|---|---|
| Janela do `gclid` | **90 dias** — "Google retains the GCLID for only 90 days" |
| Janela para conversões com PII (enhanced for leads) | **63 dias** |
| Frequência recomendada de upload | ao menos **diária**, para o Smart Bidding responder |
| Objeto da API | `ClickConversion` dentro de `UploadClickConversionRequest`; recomenda-se enviar `gclid` **e** `user_identifiers` juntos |

**[INFERÊNCIA] Esse é o "santo graal" do chat:** o `gclid` chega na primeira visita, o lead conversa, o negócio fecha 30 dias depois, e o ChatSPX — que guardou o `gclid` no contato — sobe a conversão com o valor real da venda. Nenhum concorrente de chat brasileiro que verifiquei entrega isso hoje (ver §4.10). É a feature de maior valor percebido e de menor concorrência.

### 3.8 Consent Mode v2

**[FATO]** ([Google — Consent mode](https://developers.google.com/tag-platform/security/guides/consent)):

| Sinal | O que controla |
|---|---|
| `ad_storage` | Armazenamento (cookies) para publicidade |
| `analytics_storage` | Armazenamento para analytics |
| `ad_user_data` | *"Sets consent for sending user data related to advertising to Google"* |
| `ad_personalization` | *"Sets consent for personalized advertising"* |

Código canônico **[FATO]**:

```js
// ANTES de qualquer comando que envie dados de medição
gtag('consent', 'default', {
  'ad_storage': 'denied',
  'ad_user_data': 'denied',
  'ad_personalization': 'denied',
  'analytics_storage': 'denied',
  'wait_for_update': 500
});

function allConsentGranted() {
  gtag('consent', 'update', {
    'ad_user_data': 'granted',
    'ad_personalization': 'granted',
    'ad_storage': 'granted',
    'analytics_storage': 'granted'
  });
}
```

Por região (ISO 3166-2) **[FATO]**:

```js
gtag('consent', 'default', { 'analytics_storage': 'denied', 'region': ['ES', 'US-AK'] });
```

Aviso literal da Google **[FATO]**: *"The order of the code here is vital. If your consent code is called out of order, consent defaults won't work."*

**Básico x Avançado [FATO-2ª]**: no modo **avançado**, as tags carregam sempre (com funcionalidade limitada quando negado), o que permite pings sem cookie e habilita modelagem. No modo **básico**, as tags só carregam após consentimento.

**Modelagem [FATO-2ª]** ([Google Analytics Help 11161109](https://support.google.com/analytics/answer/11161109), [Plausible](https://plausible.io/blog/consent-mode-ga4-modeled-data)): para ativar *behavioral modeling* no GA4 a propriedade precisa coletar pelo menos **1.000 eventos/dia com `analytics_storage='denied'` por 7 dias**, e o consent mode precisa estar em todas as páginas com as tags carregando antes do banner.

**[INFERÊNCIA] Impacto para o ChatSPX:** o widget não pode assumir consentimento. Precisa de um modo em que:
- eventos **client-side** só disparam se `ad_storage`/`analytics_storage` estiverem `granted` (ou se o cliente marcar "meu site não usa CMP");
- eventos **server-side** carregam o campo `consent` no payload do MP e respeitam `opt_out`/limitação de PII na CAPI;
- exista um `$chatwoot.setConsent({...})` para o CMP do cliente informar o estado.

### 3.9 LGPD (Brasil) e GDPR (Europa)

**[FATO]** A ANPD publicou o **Guia Orientativo "Cookies e Proteção de Dados Pessoais"** ([gov.br/anpd](https://www.gov.br/anpd/pt-br/centrais-de-conteudo/materiais-educativos-e-publicacoes/guia_orientativo_cookies_e_protecao_de_dados_pessoais)).

**[FATO-2ª]** ([LEC](https://www.lec.com.br/guia-orientativo-da-anpd/), [Mattos Filho](https://www.mattosfilho.com.br/en/unico/brazilian-data-protection/), [Confidata](https://confidata.com.br/blog/cookies-rastreamento-consentimento-anpd)):
- Publicado originalmente em **18/10/2022**; versão atualizada citada como publicada em 22/11/2024 e atualizada em 23/01/2025. Nova orientação prevista para o biênio 2025-2026.
- **Cookies necessários** podem se apoiar em **legítimo interesse**, desde que o titular seja informado e possa se opor.
- **Cookies não necessários** exigem consentimento **livre, informado, inequívoco e granular**.
- É obrigatório permitir **revogação fácil e gratuita** do consentimento.

**[INFERÊNCIA]** Pixel de Meta e GA4 são, sem discussão, cookies **não necessários** — o que significa que a ativação padrão precisa ser "desligado até haver consentimento" quando o cliente declarar operar sob CMP. E o ChatSPX, ao processar PII do visitante para enviar a terceiros (Meta/Google), atua como **operador** por conta do cliente: isso precisa estar no contrato/DPA e visível no painel, com:
- lista de destinos de dados por caixa de entrada;
- log de quais campos foram enviados (sem armazenar o valor cru desnecessariamente);
- botão de desligar por conta;
- retenção definida para os logs.

**[NÃO VERIFICADO]** Se o ChatSPX/Simplex já possui DPA ou aditivo de tratamento com os clientes que cubra envio de PII hasheada a Meta/Google. Precisa de verificação jurídica antes do lançamento da feature.

---
## 4. Quem entrega o quê — levantamento fornecedor a fornecedor

### 4.1 Leadster — dissecação do bundle real

Esta seção é a mais valiosa do documento, porque não depende de marketing: é leitura do código que roda no navegador dos clientes da Leadster.

**Método [FATO]:** baixei o bundle público do widget com:

```bash
curl -s https://cdn.leadster.com.br/neurolead/neurolead.min.js -o neurolead.js
# http=200  size=456101 bytes
```

Versão declarada no próprio bundle: `clientVersion() { return "2.67.0" }`. Data do download: **2026-08-11**. Nada de login, nada de paywall — é o arquivo que qualquer site que instala a Leadster carrega. A instalação é documentada como `https://cdn.leadster.com.br/neurolead/neurolead.min.js` com um identificador da empresa ([WordPress.org — plugin Leadster](https://wordpress.org/plugins/leadster-marketing-conversacional/)) **[FATO-2ª]**.

#### 4.1.1 Arquitetura de tracking da Leadster: três camadas

**[INFERÊNCIA]** a partir do código lido:

```
┌──────────────────────────── NAVEGADOR DO VISITANTE ────────────────────────────┐
│                                                                                 │
│  Camada 1 — GA4 PRÓPRIO DA LEADSTER                                             │
│    installLeadsterGa4()  →  gtag config G-43W2WYML5H                            │
│    (telemetria de produto da própria Leadster; desligável por window.disableLeadsterGa4) │
│                                                                                 │
│  Camada 2 — TAGS DO CLIENTE (client-side)                                       │
│    detecta window.fbq.getState().pixels  e  dataLayer ['config', ID]            │
│    instala o que faltar  →  fbq('track', <evento>)  /  gtag('event', ...)       │
│    e SEMPRE dataLayer.push({event: ...})                                        │
│                                                                                 │
│  Camada 3 — COLETA PARA SERVER-SIDE                                             │
│    hash SHA-256 (crypto.subtle) de email/telefone/nome/cidade/estado            │
│    + fbp/fbc + client_id/session_id + urls                                      │
│         │                                                                        │
└─────────┼────────────────────────────────────────────────────────────────────────┘
          ▼  POST /marketing_event/block-events   (e /whatsapp_tracking)
┌─────────────────────── BACKEND LEADSTER ────────────────────────┐
│  platform: "meta"  → Conversions API                            │
│  platform: "google_analytics" → Measurement Protocol / EC       │
│  credential_id → credencial OAuth/token do cliente              │
└──────────────────────────────────────────────────────────────────┘
```

#### 4.1.2 Instalação de tags (código literal)

```js
const Ya = new class {
  installGa4(t) {
    const e = document.createElement("script");
    e.src = "https://www.googletagmanager.com/gtag/js?id=" + t;
    document.head.appendChild(e);
    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function () { dataLayer.push(arguments) };
    gtag("js", new Date);
    gtag("config", t)
  }
  installLeadsterGa4() { this.installGa4("G-43W2WYML5H") }
  installMetaPixel(t, e) { /* snippet oficial */ fbq("init", t), e || fbq("track", "PageView") }
  insertMetaPixel(t, e) {
    if (fbq) return;
    const n = document.createElement("img");
    n.src = "https://www.facebook.com/tr?id=" + t + "&ev=" + e + "&noscript=1";
    n.height = "1"; n.width = "1"; n.style = "display:none";
    document.body.appendChild(n)
  }
}
```

E o gancho de inicialização **[FATO]**:

```js
setupGoogleAnalytics() { window.disableLeadsterGa4 || Ya.installLeadsterGa4() }
setupClientGa4() {
  const { gaConversionEvent: t } = this.metadata || {};
  Array.isArray(t) && t[2] && Ya.installGa4(t[2])
}
setupMetaPixel() {
  if (this.metadata.fbqConversionEvents) {
    const t = this.metadata.fbqConversionEvents[1];
    if (!t) return;
    Ya.installMetaPixel(t);
    Ya.insertMetaPixel(t, "PageView")
  }
}
```

**[FATO] Achado notável:** a Leadster instala **um GA4 próprio dela** (`G-43W2WYML5H`) na página de todos os clientes por padrão, a menos que a variável global `window.disableLeadsterGa4` esteja definida.

**[INFERÊNCIA]** Isso é telemetria de produto por cima do site do cliente. É uma escolha agressiva de privacidade que **eu não recomendaria replicar** no ChatSPX sem consentimento explícito e documentado — sob a LGPD isso é tratamento de dados do visitante do cliente para finalidade própria do fornecedor (§3.9).

#### 4.1.3 O disparo do lead (código literal, o coração da coisa)

```js
sendSyncEvents() {
  if (window.dataLayer = window.dataLayer || [], window.gtag
    ? ( gtag("event", "new_lead"),
        gtag("event", "Leadster", { event_category: "new_lead" }),
        gtag("event", this.metadata.gaConversionEvent[1], { event_category: this.metadata.gaConversionEvent[0] }),
        this.metadata.gtagConversionId && gtag("event", "conversion", {
          send_to: this.metadata.gtagConversionId, event_callback: () => {}
        }) )
    : window.__gaTracker
      ? __gaTracker("send", "event", this.metadata.gaConversionEvent[0], this.metadata.gaConversionEvent[1])
      : window.dataLayer.push({ event: "new_lead" }),
    this.metadata.fbqConversionEvents) {
      const t = this.metadata.fbqConversionEvents[1];
      t && ( "undefined" == typeof fbq && Ya.insertMetaPixel(t, this.metadata.fbqConversionEvents[0]),
             fbq("track", this.metadata.fbqConversionEvents[0]),
             window.dataLayer.push({ event: this.metadata.fbqConversionEvents[0] }) )
    }
}
```

Decodificando **[INFERÊNCIA]**:

| Ordem | Ação | Observação |
|---|---|---|
| 1 | `gtag('event','new_lead')` | Evento fixo, nome próprio da Leadster (não é `generate_lead` do GA4) |
| 2 | `gtag('event','Leadster',{event_category:'new_lead'})` | Segundo evento redundante, formato "GA universal traduzido" |
| 3 | `gtag('event', <ação configurada>, {event_category: <categoria configurada>})` | O par Categoria/Ação que o cliente define no painel |
| 4 | `gtag('event','conversion',{send_to:<AW-...>})` | Conversão do Google Ads, se configurada |
| — | fallback `__gaTracker` | Compatibilidade com o plugin *MonsterInsights* do WordPress (Universal Analytics legado) |
| — | fallback `dataLayer.push({event:'new_lead'})` | Quando não há `gtag` nenhum na página |
| 5 | `fbq('track', <evento Meta configurado>)` | **`track`, não `trackSingle`** |
| 6 | `dataLayer.push({event: <evento Meta configurado>})` | Espelha no dataLayer |

**[INFERÊNCIA] Crítica técnica ao design da Leadster** (útil para nós fazermos melhor):
- Usa `fbq('track', ...)` e não `trackSingle` → em página com múltiplos pixels o evento vaza para todos, exatamente o que a Meta avisa em §2.1.
- Não passa `eventID` no `fbq` → **não há deduplicação** entre o evento client-side e o evento server-side enviado via `/marketing_event/block-events`. **[NÃO VERIFICADO]** se o backend deles gera `event_id` e o correlaciona de outra forma; pelo lado do navegador, não vi `eventID` sendo passado.
- Nomes de evento GA4 são livres (Categoria/Ação vindo do painel) em vez dos eventos recomendados (`generate_lead`); a documentação deles inclusive instrui o usuário a *"copiar o nome do evento do Tag Assistant"* ([help.leadster.com.br/article/122](https://help.leadster.com.br/article/122-como-configurar-o-google-analytics-para-enviar-eventos-de-conversoes)) **[FATO]** — ou seja, o cliente descobre o nome por engenharia reversa em vez de ler documentação.
- Dispara 3 eventos GA4 para o mesmo lead (`new_lead`, `Leadster`, `<ação>`), o que polui a propriedade do cliente.

#### 4.1.4 Eventos de etapa (funil dentro do chat)

```js
sendClientAnalyticsEvent(t, e, n) {
  let i = `Etapa - ${n} - ${t.split("::").slice(-1)[0]}`;
  this.metadata.gaConversionEvent && this.metadata.gaConversionEvent.length >= 2 && (
    window.__gaTracker && __gaTracker("send", "event", "Neurologic", i),
    window.gtag && gtag("event", i, { event_category: "Neurologic" })
  )
}
```

E os eventos internos (enviados ao backend da Leadster, não ao cliente) **[FATO]**:

```js
this.sendAnalyticsEvent("load", () => {}, !0);
this.sendAnalyticsEvent((0, In.Fr)() ? "is_mobile" : "is_desktop", () => {}, !0);
// por passo do fluxo:
this.sendAnalyticsEvent(`step_${r}`);
// ao concluir:
this.sendAnalyticsEvent("finish", () => {}, !0);
// evento de interação com IA:
sendAnalyticEvents() { window.gtag && window.gtag("event", "leadster_ai_interaction") }
// blocos:
Gi.dispatch("storeAnalyticBlockInfo", { name: "whatsapp", action: "view"|"click", label, uid, payload })
```

**[INFERÊNCIA]** Portanto a Leadster tem duas trilhas: uma **para o cliente** (GA4/Ads/Meta do cliente) e uma **interna** (`load`, `is_mobile`, `step_N`, `finish`, blocos) que alimenta o relatório da própria Leadster. Modelo correto — e é o que o ChatSPX deveria fazer, com a diferença de que os eventos internos devem ir para o **nosso** backend, não para um GA4 injetado no site do cliente.

#### 4.1.5 Camada server-side: payloads reais

**Endpoint [FATO]:** `POST /marketing_event/block-events` (base do axios `Mn`; o host não estava explicitamente no trecho lido — **[NÃO VERIFICADO]** qual é o host exato, mas `app.leadster.com.br` / `app.getleadster.com` aparecem no bundle).

Envelope comum **[FATO]**:

```js
Ha = async function (t, e, n = 0) {
  const payload = {
    ...t,
    timestamp: Date.now(),
    block_uid: e.uid,
    location: x(),          // current_url
    lead_id: neurolead.guid || neurolead.metadata.guid,
    user_id: neurolead.userId,
    script: neurolead.metadata.scriptId,
    script_version: neurolead.metadata.scriptVersionId,
    company: neurolead.metadata.companyId
  };
  return (await Mn.post("/marketing_event/block-events", payload)).data
  // catch: if (500 === status && n < 3) retry (n+1)
}
```

**Payload Meta [FATO]:**

```js
Ga = async t => (Zi(), {
  platform: "meta",
  meta_event_options: t.meta_event_options,
  credential_id: t.meta_credential_id,
  action_source: "website",
  fbp: cookie("_fbp"),
  fbc: cookie("_fbc"),
  em: await hash(email), ph: await hash(phone),
  fn: await hash(firstName), ln: await hash(lastName),
  ct: await hash(city), st: await hash(state),
  referrer_url: w(), current_url: x(),
  test_mode: t.test_mode ?? window.neurolead?.test_mode,
  test_event_code: t.test_event_code ?? window.neurolead?.test_event_code
})
```

**Payload Google [FATO]:** já reproduzido em §3.7.

**Hash [FATO]:**

```js
ao = async t => {
  if (!t) return null;
  const e = (new TextEncoder).encode(t);
  const n = await crypto.subtle.digest("SHA-256", e);
  return Array.from(new Uint8Array(n)).map(t => t.toString(16).padStart(2, "0")).join("")
}
so = t => {                       // normalização
  if (null == t) return null;
  const e = ("string" == typeof t ? t : String(t)).trim();
  return e ? e.toLowerCase().replace("{{", "").replace("}}", "") : null
}
```

**[FATO] Achado importante: o hash é feito no NAVEGADOR (`crypto.subtle`), não no servidor.** A PII crua nunca sai do navegador nesses payloads — só o SHA-256 hex.

**[INFERÊNCIA]** Decisão de privacidade defensável e elegante. Custo: o servidor da Leadster não pode re-normalizar nem corrigir um telefone mal formatado (hash errado = match perdido, silenciosamente). Para o ChatSPX, que **já tem** os dados no servidor (o chat é nosso), hashear no servidor é mais robusto — mas o argumento de privacidade do hash no cliente merece ser considerado quando o dado nunca precisa ficar em claro no nosso lado.

**Retry e polling de campo [FATO]:** todos os extratores (`fo`, `bo`, `vo`, `yo`, `wo`, `xo`) fazem **5 tentativas com delay** esperando o campo aparecer na `dataQueue` do fluxo antes de desistir — porque o dado do lead vai sendo preenchido conforme a conversa avança.

**Telefone para WhatsApp [FATO]:** existe uma variante `_o` que **não** hasheia, só limpa (`t.replace(/\D/g, "")`), usada no endpoint `/whatsapp_tracking`:

```js
Io = async function (t, e, n = 0) {
  const payload = { ...t, timestamp: Date.now(), block_uid: e.uid, lead_id, user_id, script, script_version, company };
  return (await Mn.post("/whatsapp_tracking", payload)).data
}
Mo = async t => {
  Zi();                                   // garante _fbc
  /* garante _gcl_aw a partir de gclid */
  const measurementId = <último ['config', ID] do dataLayer>;
  const i = {
    phone: await _o({ key: phoneField }),
    metadata: {
      cookies: { client_id: await to(measurementId), session_id: await eo(measurementId), ...todosOsCookies },
      referrer_url: w(), referrer_params: k(w()),
      current_url: x(), current_params: k(x()),
      device: In.hf, is_mobile: (0, In.Fr)()
    }
  };
  return i.phone ? await Io(i, t) : null
}
```

**[FATO] `...Ki(!1)` copia TODOS os cookies do domínio** para dentro de `metadata.cookies`. **[INFERÊNCIA]** É como eles pegam `_fbp`, `_fbc`, `_gcl_aw`, `_ga`, e qualquer UTM que o site tenha guardado em cookie — de uma vez. Funciona, mas é uma coleta indiscriminada que sob LGPD é difícil de justificar. Para o ChatSPX: **coletar por allowlist explícita** (`_fbp`, `_fbc`, `_ga`, `_ga_*`, `_gcl_aw`, `_gcl_dc`, e cookies de UTM configurados), nunca `document.cookie` inteiro.

**Captura de UTM [FATO]:** o bundle tem `referrer_params: k(w())` e `current_params: k(x())`, onde `k()` transforma a query string em objeto. Ou seja, os UTMs são capturados via parsing dos parâmetros da URL atual e da referrer, e enviados dentro de `metadata` — não há campos `utm_source` fixos no payload (as ocorrências literais de `utm_source`/`utm_medium`/`utm_campaign` que encontrei no bundle são da URL de marca no rodapé "Criado com Leadster", com `utm_source=clientes&utm_medium=referral`).

#### 4.1.6 Detecção de configuração e mensagens de erro

```js
a = () => { if (!i.meta_event) throw Error("Leadster script block: Meta Ads is disabled") }
s = () => {
  if (i.meta_pixel && null !== i.meta_pixel_code) return i.meta_pixel_code;
  const t = neurolead.metadata.fbqConversionEvents;
  return null != t && t[1] ? t[1] : null
}
r = () => {
  if (void 0 === window.fbq) return [];
  const t = window.fbq.getState().pixels.map(t => t.id);
  return t.length > 0 ? t : []
}
l = () => { if (null === e && 0 === n.length) throw Error("Leadster script block: Pixel code not found") }
```

E, no lado Google:

```js
c = () => { n.includes(e) || Ya.installGa4(e) }             // só instala se já não estiver na página
d = () => {
  const t = null !== e ? e : (n.length > 0 ? n : void 0);
  i.google_event_options.map(t => t.value).forEach(e => {
    window.gtag("event", e, { send_to: Array.isArray(t) ? t : [t] })
  })
}
```

**[INFERÊNCIA]** Este é o padrão de ouro que devemos copiar: **detectar → não duplicar → instalar só o que falta → disparar com `send_to` explícito**. A Leadster faz isso no lado Google (`send_to`) mas **não** no lado Meta (`track` em vez de `trackSingle`). Fazer os dois é fazer melhor que a referência do mercado.

#### 4.1.7 O que a documentação pública da Leadster diz (e não diz)

**[FATO]** ([help.leadster.com.br/article/120](https://help.leadster.com.br/article/120-como-configurar-os-eventos-do-pixel-da-meta-e-o-ga4-de-maneira-automatizada)): o artigo "Como configurar os eventos do pixel da Meta e o GA4 de maneira automatizada" é essencialmente **um vídeo** — não há especificação escrita de nomes de eventos, parâmetros ou payloads.

**[FATO]** ([help.leadster.com.br/article/122](https://help.leadster.com.br/article/122-como-configurar-o-google-analytics-para-enviar-eventos-de-conversoes)): o caminho documentado é via **GTM**, criando tag "Evento do GA4"; o nome do evento se obtém *"copiando o nome do evento do Tag Assistant"*; parâmetros vêm dos campos "Categoria" e "Ação" do painel Leadster. Nota literal: *"Os dados de conversões não são mostrados em tempo real, pode demorar de 5 à 30 minutos para contabilizar."*

**[FATO]** ([help.leadster.com.br/article/82](https://help.leadster.com.br/article/82-com-quais-plataformas-consigo-integrar-a-leadster)): a lista de integrações nativas (20: RD Station, HubSpot, PipeRun, ActiveCampaign, Salesforce, Zoho, Bitrix24, Exact Sales, Google Sheets, etc.) **não menciona** Google Analytics, GA4, GTM, Meta Pixel, Google Ads ou CAPI. Existe também "Zapier, Pluga e Webhook".

**[INFERÊNCIA] Leitura estratégica:** a Leadster tem uma implementação de tracking tecnicamente sofisticada e uma documentação fraca. Isso significa que (a) a barreira de entrada técnica é alta, mas (b) a barreira de *comunicação* é baixa — um concorrente que documente bem seus eventos ganha a preferência de agências e times de dados, que são quem realmente escolhe essa categoria de ferramenta.

### 4.2 JivoChat

**[FATO]** ([jivochat.com/help/integrations/fb-pixel.html](https://www.jivochat.com/help/integrations/fb-pixel.html)) — 17 eventos enviados automaticamente ao Facebook Pixel, com nomes literais:

`Chat_established`, `Chat_requested`, `Proactive_invitation_shown`, `Proactive_invitation_accepted`, `Proactive_invitation_rejected`, `Offline_form_shown`, `Offline_message_sent`, `User_gave_contacts_during_chat`, `Callback_invitation_shown`, `Callback_requested`, `Mobile_call`, `In-chat_email_form_shown`, `In-chat_email_form_submitted`, `Continue_in_social`, `Client_initiates_chat`, `Client_answer_on_agent_request`, `Prechat_phrase_clicked`.

Nota literal: *"All events are sent automatically, and it is not necessary to put special tracking codes on your website"* **[FATO]**.

**[FATO]** ([jivochat.com/help/integrations/google-analytics-integration.html](https://www.jivochat.com/help/integrations/google-analytics-integration.html)) — 18 eventos equivalentes no Google Analytics; requisito literal: *"all you need is a counter on the website and a professional license on JivoChat"*. Para marcar como conversão: Configuration → Events → Create event, condição `event_name: JivoSite` + ID do evento.

**[INFERÊNCIA]** JivoChat é o fornecedor com a **maior granularidade de eventos** que encontrei — e todos são eventos **custom** (nomes próprios), não padrão da Meta. Isso é bom para diagnóstico e ruim para otimização: `Chat_established` não é um evento que o algoritmo da Meta entende semanticamente como `Lead`. O ideal é o que proponho em §2.3: eventos padrão para o que importa comercialmente + custom para o resto.

### 4.3 Tidio

**[FATO-2ª]** ([help.tidio.com — GTM](https://help.tidio.com/hc/en-us/articles/9049293832220-Integration-with-Google-Tag-Manager), [GA4](https://help.tidio.com/hc/en-us/articles/5422047432732-Integration-with-Google-Analytics-GA4)):
- Eventos prefixados com `tidio_`, capturáveis no GTM com a regex `^tidio_\w+`.
- Três categorias: `widget`, `prechat`, `conversation`.
- Envio via `dataLayer.push`.
- A integração GA4 direta foi descontinuada; a documentação oficial aponta para o caminho GTM.

Eventos da API JS `tidioChatApi` **[FATO-2ª]** ([DumbData](https://dumbdata.co/listeners/tidio-chat-event-listener/)): `open`, `close`, `conversationStart`, `messageFromOperator`, `messageFromVisitor`, `preFormFilled`, `setStatus`. Padrão de push recomendado:

```js
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({ event: 'Tidio_chat_interaction', chatAction: 'User Sent First Message' });
```

**[INFERÊNCIA]** Tidio escolheu o caminho "só dataLayer". É a opção mais barata de manter e a mais segura juridicamente, mas transfere 100% do trabalho para o cliente. Para PME brasileira sem agência, isso é atrito que mata a adoção.

### 4.4 Intercom

**[FATO]** ([intercom.com/help/en/articles/2454807](https://www.intercom.com/help/en/articles/2454807-google-analytics-app)) — app oficial de Google Analytics; instala pelo App Store do Intercom, autoriza acesso, cola o GA4 tracking ID.

Eventos enviados (nomes literais) **[FATO]**:
`Opened Messenger`, `Closed Messenger`, `Triggered Message`, `Viewed Message`, `Started New Conversation`, `Sent a Reply`, `Provided Email Address`, `Interacted with App`, `Completed App Flow`.

Dimensões customizadas sugeridas: `custom_bot_id`, `eventCategory`, `eventLabel`, `message_id`, `page_title` **[FATO]**.

Declaração literal de privacidade **[FATO]**: *"Intercom does not send any personally identifiable information (PII), or other sensitive data to Google Analytics."*

Há também rota via GTM documentada ([intercom.com/help/en/articles/6990698](https://www.intercom.com/help/en/articles/6990698-setting-up-the-ga4-integration-with-google-tag-manager)) **[FATO-2ª]**.

**[INFERÊNCIA]** O Intercom é o benchmark de **UX de configuração** (instalar app + colar ID), e é justamente esse padrão que o ChatSPX deve perseguir: *"o cliente só cola um ID e funciona"* — que é literalmente o pedido do usuário nesta task. Note que o Intercom **não** oferece Meta Pixel nativo; a lacuna do mercado global é essa.

### 4.5 Drift

**[FATO-2ª]** ([devdocs.drift.com/docs/drift-events](https://devdocs.drift.com/docs/drift-events)) — API de eventos JS no `window`:

```js
drift.on('startConversation', function (event) {
  // enviar para GA / dataLayer
});
```

Eventos citados na documentação e por integradores: `startConversation`, `chatOpen`, `chatClose`, `welcomeMessage:open`, entre outros **[FATO-2ª]**. Existe integração "one-click" com Google Analytics **[FATO-2ª]**. Padrão de GTM documentado por terceiros usa `dataLayer.push` com `eventCategory`/`eventAction`/`eventLabel`.

### 4.6 HubSpot

**[FATO-2ª]** (comunidade oficial HubSpot, [370205](https://community.hubspot.com/t5/Reporting-Analytics/HubSpot-Chat-amp-Google-Analytics-Event-Tracking/m-p/370205)): a superfície é a API `window.HubSpotConversations` com o callback `hsConversationsOnReady`:

```js
window.hsConversationsOnReady = [function() {
  window.HubSpotConversations.on('conversationStarted', payload => {
    window.dataLayer.push({ event: 'hs_chat_started' });
  });
  window.HubSpotConversations.on('contactAssociated', payload => {
    window.dataLayer.push({ event: 'hs_chat_contact_associated' });
  });
}];
```

**[INFERÊNCIA]** HubSpot entrega o **hook**, não a integração. Quem entrega a integração é o consultor. Para o ChatSPX, oferecer hooks (que o Chatwoot já tem, ver §6) é o mínimo; oferecer a integração pronta é o diferencial.

### 4.7 Zendesk

**[FATO-2ª]** ([support.zendesk.com/hc/en-us/articles/4408893279770](https://support.zendesk.com/hc/en-us/articles/4408893279770-Setting-up-Zendesk-Chat-with-Google-Analytics)): existe configuração de Google Analytics para o Zendesk Chat, mas relatos da própria comunidade indicam que **não há suporte nativo a GA4 no Web Widget**.

**[NÃO VERIFICADO]** Estado atual (2026) do suporte GA4 no Zendesk Web Widget messaging.

### 4.8 RD Station (Marketing + Conversas)

**[FATO]** ([ajuda.rdstation.com — Instalar pixel do Facebook](https://ajuda.rdstation.com/s/article/Instalar-pixel-do-Facebook?language=pt_BR)): no RD Station Marketing existe a opção *"Adicionar o código do pixel da Meta por conta própria"*, com checkboxes *"Conectar a API de conversões"* e *"Instalar código do pixel em todas as landing pages"*.

**[FATO-2ª]** ([rdstation.com/produtos/conversas](https://www.rdstation.com/produtos/conversas/)): o RD Station Conversas centraliza WhatsApp, Instagram, Messenger e chat de site, com integração declarada a plataformas de anúncio e dashboards de conversão.

**[NÃO VERIFICADO]** Se o **chat de site** do RD Station Conversas (e não apenas as landing pages do RD Marketing) dispara eventos nativos para Pixel/GA4, e quais são os nomes desses eventos. Não encontrei documentação pública específica. Este é um ponto que vale checagem manual em uma conta de teste antes de qualquer comparação comercial.

### 4.9 Octadesk

**[FATO-2ª]** ([octadesk.com](https://www.octadesk.com/produtos/plataforma-de-atendimento)): conecta WhatsApp API oficial, Instagram Direct, Messenger e chat de site; integra nativamente com RD Station, HubSpot, Pipedrive e Salesforce.

**[NÃO VERIFICADO]** Existência e detalhe de integração nativa com Meta Pixel/GA4 a partir do chat de site do Octadesk. Não localizei documentação pública específica.

### 4.10 Tabela comparativa consolidada

Legenda: ✅ nativo documentado · ⚠️ parcial / exige trabalho do cliente · ❌ não encontrado · ❔ não verificado

| Fornecedor | Meta Pixel client-side | Meta CAPI server-side | Dedup `event_id` | GA4 client-side | GA4 server-side (MP) | Google Ads conversão | Enhanced Conv. | dataLayer/GTM | Conversão offline | Captura UTM/gclid/fbclid | Consent Mode |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Leadster** | ✅ (instala e dispara; usa `track`) | ✅ (`platform:"meta"`, hash no browser) | ❌ (sem `eventID` no `fbq`) | ✅ (instala + `gtag('event')`) | ✅ (`client_id`+`session_id`) | ✅ (`send_to` AW-) | ✅ (campos `sha256_*`) | ✅ | ❔ | ✅ (`_fbc`, `_gcl_aw`, params) | ❔ |
| **JivoChat** | ✅ (17 eventos automáticos) | ❔ | ❔ | ✅ (18 eventos) | ❔ | ⚠️ (via GA como conversão) | ❔ | ⚠️ (via listeners de terceiros) | ❌ | ❔ | ❔ |
| **Tidio** | ❌ | ❌ | ❌ | ⚠️ (só via GTM) | ❌ | ⚠️ | ❌ | ✅ (`tidio_*`) | ❌ | ❔ | ❔ |
| **Intercom** | ❌ | ❌ | ❌ | ✅ (app oficial, 9 eventos) | ❌ | ⚠️ | ❌ | ✅ | ❌ | ❔ | ❔ |
| **Drift** | ❌ | ❌ | ❌ | ✅ (one-click + API JS) | ❌ | ⚠️ | ❌ | ✅ | ❌ | ❔ | ❔ |
| **HubSpot** | ❌ | ❌ (existe no HubSpot Ads, não no chat) | ❌ | ⚠️ (hooks JS) | ❌ | ⚠️ | ❌ | ⚠️ (o cliente escreve) | ⚠️ (via CRM) | ⚠️ | ❔ |
| **Zendesk** | ❌ | ❌ | ❌ | ⚠️ (GA legado; GA4 ❔) | ❌ | ❌ | ❌ | ⚠️ | ❌ | ❔ | ❔ |
| **RD Station** | ⚠️ (pixel + CAPI em LPs) | ⚠️ (em LPs) | ❔ | ❔ | ❔ | ❔ | ❔ | ❔ | ⚠️ (via CRM) | ⚠️ | ❔ |
| **Octadesk** | ❔ | ❔ | ❔ | ❔ | ❔ | ❔ | ❔ | ❔ | ❔ | ❔ | ❔ |
| **Chatwoot / ChatSPX hoje** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ (só `referer`) | ❌ |

**[INFERÊNCIA] Leituras da tabela:**

1. **Ninguém fecha o ciclo.** Nenhum fornecedor da lista entrega conversão offline (venda que fecha depois) de volta para Meta/Google a partir do chat. É a maior lacuna aberta do mercado.
2. **Dedup é raro.** Nem a Leadster, que é a mais avançada tecnicamente, passa `eventID` no `fbq`. Fazer dedup direito é barato e vira argumento técnico verificável ("seu Events Manager não vai contar duas vezes").
3. **Fora do Brasil, Meta Pixel em chat quase não existe.** Intercom, Drift, Tidio e Zendesk investiram só no Google. Isso reflete o público deles (SaaS B2B americano). No Brasil, onde Meta Ads é a principal fonte de lead de PME, isso inverte — e é exatamente o que a Leadster explorou.
4. **O ChatSPX parte do zero**, mas parte de uma arquitetura (SDK + iframe + webhooks + custom attributes) que já tem os ganchos necessários (§6).

---
## 5. Atribuição: da origem anônima à venda

### 5.1 Captura de origem — o inventário completo do que precisa ser capturado

| Sinal | Onde vive | Como capturar | TTL prático |
|---|---|---|---|
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content` | query string da landing page | `new URLSearchParams(location.search)` | definido por você |
| `utm_id` | query string | idem | idem |
| `gclid` | query string (Google Ads) | idem; espelhado no cookie `_gcl_aw` | **90 dias** (limite do Google) **[FATO-2ª]** |
| `gbraid` / `wbraid` | query string (iOS) | idem | idem |
| `fbclid` | query string (Meta) | idem; espelhado em `_fbc` | 90 dias (padrão de mercado) **[FATO]** |
| `msclkid` | query string (Microsoft Ads) | idem | **[NÃO VERIFICADO]** janela oficial |
| `ttclid` | query string (TikTok Ads) | idem | **[NÃO VERIFICADO]** |
| `document.referrer` | navegador | primeira página da sessão | sessão |
| Landing page (URL de entrada) | navegador | primeira página da sessão | sessão |
| `_fbp` | cookie criado pelo pixel | `document.cookie` | 90 dias |
| `_ga` / `_ga_<ID>` | cookies do GA4 | `document.cookie` ou `gtag('get')` | 2 anos / sessão |
| IP + User-Agent | requisição HTTP | servidor | requisição |
| Página onde a conversa começou | navegador | já existe no Chatwoot (§6) | — |

### 5.2 Primeira sessão x última sessão: a decisão de modelo

Nenhum fornecedor de chat que estudei documenta a política dele aqui — é um ponto cego do mercado **[INFERÊNCIA]**.

Os três modelos possíveis:

| Modelo | Regra | Bom para | Ruim para |
|---|---|---|---|
| **First-touch** | Grava a origem da **primeira** visita e nunca sobrescreve | Descobrir o que gera demanda no topo | Subestima remarketing |
| **Last-touch** | Sobrescreve sempre com a origem mais recente antes da conversa | Bater com o que o Google Ads/Meta reportam | Superestima marca/direto |
| **Ambos** | Grava dois conjuntos: `first_*` e `last_*` | Analisar de verdade | Mais colunas |

**[INFERÊNCIA] Recomendação para o ChatSPX:** gravar **os dois**, em `custom_attributes` do contato e da conversa, com regras explícitas:
- `first_utm_*`, `first_referrer`, `first_landing_page`, `first_seen_at` → gravados **uma vez**, nunca sobrescritos (write-once).
- `last_utm_*`, `last_referrer`, `last_landing_page` → sobrescritos a cada nova sessão com parâmetros de origem presentes.
- `gclid`, `fbclid` → gravar o **mais recente não vazio**, com timestamp, porque o Google/Meta usam o clique mais recente na janela.
- Regra de sobrescrita: só sobrescrever `last_*` se a nova sessão tiver **algum** parâmetro de campanha ou um referrer externo; navegação interna não zera a origem (erro clássico).

### 5.3 O ciclo completo — diagrama textual

```
┌─ D+0, 14h02 ──────────────────────────────────────────────────────────────────┐
│ VISITANTE ANÔNIMO                                                             │
│  clica no anúncio  →  chega em  site.com/planos?utm_source=google              │
│                       &utm_medium=cpc&utm_campaign=marca&gclid=EAIaIQ...       │
│                                                                                │
│  O QUE PRECISA ACONTECER TECNICAMENTE:                                         │
│   • SDK do chat lê location.search e document.referrer                         │
│   • grava first_* (write-once) e last_* em localStorage + cookie first-party    │
│   • deriva _fbc de fbclid (fb.{n}.{ts}.{fbclid}) e _gcl_aw de gclid            │
│   • lê _fbp; lê client_id/session_id via gtag('get') com timeout               │
└────────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─ D+0, 14h05 ──────────────────────────────────────────────────────────────────┐
│ ABRE O CHAT / ENVIA 1ª MENSAGEM                                                │
│                                                                                │
│  EVENTOS:                                                                      │
│   client-side → fbq trackSingle 'Contact' (eventID=E1)                         │
│                 gtag('event','chatspx_conversation_started')                    │
│                 dataLayer.push({event:'chatspx_conversation_started'})          │
│   server-side → CAPI 'Contact' (event_id=E1, fbp, fbc, ip, ua)                 │
│   persistência → conversation.custom_attributes.first_utm_* / last_utm_*        │
└────────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─ D+0, 14h08 ──────────────────────────────────────────────────────────────────┐
│ LEAD IDENTIFICADO — deu nome, e-mail e WhatsApp                                │
│                                                                                │
│  EVENTOS:                                                                      │
│   client-side → fbq trackSingle 'Lead' (eventID=E2)                            │
│                 gtag('event','generate_lead',{currency:'BRL',value:X})          │
│                 gtag('event','conversion',{send_to:'AW-.../...'})               │
│   server-side → CAPI 'Lead' (event_id=E2 + em/ph/fn/ln hasheados + fbp/fbc)     │
│                 GA4 MP 'generate_lead' (client_id, session_id) [se não foi web] │
│                 Google Ads Enhanced Conversions (sha256_email/phone)            │
│  PERSISTÊNCIA → contact.custom_attributes: gclid, fbclid, first_utm_*, ...      │
└────────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─ D+0, 14h30 — D+2 ────────────────────────────────────────────────────────────┐
│ QUALIFICAÇÃO (bot, regra de automação, agente ou IA)                           │
│  server-side → CAPI 'QualifiedLead' (custom) + GA4 MP 'qualify_lead'           │
│               (ou 'disqualify_lead' com disqualified_lead_reason)               │
└────────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─ D+2 ─────────────────────────────────────────────────────────────────────────┐
│ CRM (RD Station / HubSpot / Pipedrive / CRM próprio)                           │
│  o contato viaja COM os campos de origem: gclid, fbclid, first_utm_*           │
│  → sem isso, o CRM reporta "origem: site" e a atribuição morre aqui            │
└────────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─ D+18 ────────────────────────────────────────────────────────────────────────┐
│ VENDA FECHADA — R$ 8.400                                                       │
│  server-side → Google Ads Offline Conversion Import                            │
│                 ClickConversion { gclid, conversion_action, value, currency,    │
│                                   conversion_date_time }  [janela: 90 dias]     │
│               → Meta CAPI 'Purchase' action_source:'offline' ou 'website'       │
│                 com em/ph hasheados + fbc  [janela offline: 62 dias]            │
│               → GA4 MP 'close_convert_lead' {value, currency}                   │
│  RESULTADO → Smart Bidding e a otimização da Meta passam a mirar RECEITA,       │
│              não volume de lead                                                 │
└────────────────────────────────────────────────────────────────────────────────┘
```

**Requisitos técnicos por peça [INFERÊNCIA, ancorado nos fatos das §2 e §3]:**

| Peça | Exige |
|---|---|
| Captura de origem | SDK no `window` do cliente (não no iframe), storage first-party, write-once para `first_*` |
| Evento client-side | `fbq`/`gtag` presentes ou instaláveis; consentimento; `trackSingle`/`send_to` |
| Evento server-side Meta | Pixel ID + **access token** do cliente (System User Token), fila, retry, hash SHA-256, `event_id` compartilhado |
| Evento server-side GA4 | Measurement ID + **api_secret**, `client_id`, `session_id`, evento em até 48–72 h |
| Enhanced Conversions | conversão do Ads configurada com EC ligado; e-mail hasheado no mínimo; telefone em E.164 |
| Offline import | `gclid` guardado ≤ 90 dias, `conversion_action` do cliente, credencial da Google Ads API (developer token + OAuth) ou upload de CSV |
| CRM | campos de origem propagados no payload de sincronização |

**[INFERÊNCIA] O elo mais fraco de toda a cadeia é a credencial.** Pixel ID e Measurement ID são públicos e triviais de colar. **Access token da Meta**, **api_secret do GA4** e **OAuth da Google Ads API** não são — e é aí que o "cola um ID e funciona" quebra. Solução do mercado (e a que recomendo): OAuth de um clique via Facebook Login for Business e Google OAuth, exatamente como a Leadster faz com o `credential_id` que aparece nos payloads dela **[FATO]**.

### 5.4 Server-side tagging: quando vale

| Cenário do cliente | Recomendação |
|---|---|
| Gasta < R$ 5 mil/mês em mídia, sem agência | Client-side + CAPI **feito pelo ChatSPX**. Não vender sGTM. |
| R$ 5–50 mil/mês, com agência | Client-side + CAPI + MP pelo ChatSPX; dataLayer bem documentado para a agência plugar no GTM dela |
| > R$ 50 mil/mês, time de dados próprio | Cliente provavelmente já tem sGTM/Stape; o ChatSPX deve ser uma **fonte** limpa (dataLayer + webhook), não competir |
| Já usa Segment/RudderStack | Expor os eventos por webhook em formato consumível; não tentar substituir o CDP |

**[INFERÊNCIA]** A tese central: **o ChatSPX pode entregar 80% do benefício do server-side sem o cliente precisar de servidor nenhum**, porque nós já somos o servidor que tem o dado. Isso é vantagem estrutural de quem faz chat, e é o que deve ser dito na página do produto.

### 5.5 Ad blockers e ITP — quanto se perde de fato

**[FATO-2ª]** (compilado das fontes citadas em §2.5):

| Métrica | Valor citado | Fonte |
|---|---|---|
| Usuários que bloqueiam anúncios | 29,5% (Q2/2025, global) a 42,7% (dependendo da metodologia) | [Cropink](https://cropink.com/ad-blockers-usage-statistics), [Sleek](https://getsleek.io/blog/adblocker-impact-on-analytics) |
| Meta Pixel bloqueado | ~31,5% dos visitantes | [Seresa](https://seresa.io/seed/data-loss-adblockers/adblocker-impact-ad-blocker-facebook-pixel) |
| GA4 bloqueado (público geral) | 5–15% | [Sleek](https://getsleek.io/blog/adblocker-impact-on-analytics) |
| GA4 bloqueado (público técnico) | 40–60% | idem |
| Subcontagem típica de conversões (blockers + ITP) | 20–40% | [Improvado](https://improvado.io/blog/what-is-tracking-pixel) |
| Precisão com server-side | 85–95% (vs 70–80% client-side) | [Cometly](https://www.cometly.com/post/ad-blockers-preventing-conversion-tracking) |

**ITP / Safari [FATO]** ([WebKit](https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/)):
- *"Cookies for cross-site resources are now blocked by default across the board."*
- Apagamento de *"all of a website's script-writable storage after seven days of Safari use without user interaction on the site"* — inclui IndexedDB, LocalStorage, SessionStorage, Service Workers.
- Desde fev/2019, ITP limita a expiração de cookies escritos no cliente a **7 dias**.

**[INFERÊNCIA] Consequências concretas para um chat:**
1. `_fbp`, `_fbc`, `_gcl_aw` e qualquer cookie de origem que o widget escreva via JavaScript **duram 7 dias no Safari**, mesmo com `expires: 90 days`. Um lead que clicou no anúncio há 10 dias e volta pelo Safari perde a atribuição do lado do navegador.
2. O único jeito de preservar isso é **guardar no servidor** — o que um chat faz naturalmente ao gravar `gclid`/`fbclid` no contato. Mais um ponto onde o chat tem vantagem estrutural sobre um pixel puro.
3. O cookie `cw_conversation` do Chatwoot cai na mesma regra (é escrito via `js-cookie` no top window, `expires: 365` — ver §6.1). No Safari, um visitante que some por 7 dias volta como novo contato. **Isso já é um problema hoje, independente de tracking.**

---

## 6. Estado do Chatwoot / ChatSPX — auditoria do repositório

> Toda esta seção é **[FATO]** por leitura direta do repositório em `/home/chatwoot/chatwoot`, branch `homologacao`, em 2026-08-11. **Nenhum arquivo foi modificado.**

### 6.1 O que já existe

#### Eventos do SDK expostos ao site do cliente

`app/javascript/widget/constants/sdkEvents.js`:

```js
export const CHATWOOT_ERROR = 'chatwoot:error';
export const CHATWOOT_ON_MESSAGE = 'chatwoot:on-message';
export const CHATWOOT_ON_START_CONVERSATION = 'chatwoot:on-start-conversation';
export const CHATWOOT_POSTBACK = 'chatwoot:postback';
export const CHATWOOT_READY = 'chatwoot:ready';
export const CHATWOOT_OPENED = 'chatwoot:opened';
export const CHATWOOT_CLOSED = 'chatwoot:closed';
```

Sete eventos, disparados como `CustomEvent` no `window` do site do cliente:

| Evento | Onde é disparado | Arquivo:linha |
|---|---|---|
| `chatwoot:ready` | após carga do iframe | `app/javascript/sdk/IFrameHelper.js:196` |
| `chatwoot:error` | erro do widget | `IFrameHelper.js:200` |
| `chatwoot:opened` / `chatwoot:closed` | toggle da bolha | `app/javascript/sdk/bubbleHelpers.js:78-80` |
| `chatwoot:on-message` | mensagem recebida via ActionCable | `app/javascript/widget/helpers/actionCable.js:67,83` (repassado por `IFrameHelper.js:206`) |
| `chatwoot:on-start-conversation` | início de conversa | `app/javascript/widget/components/ChatFooter.vue:86`, `TeamAvailability.vue:21` |
| `chatwoot:postback` | postback de bot | `IFrameHelper.js` (função `postback`) |

**Mecanismo (o achado mais importante da auditoria):** o iframe envia ao parent uma mensagem com `eventIdentifier`, e o SDK transforma em `CustomEvent`:

```js
// app/javascript/sdk/IFrameHelper.js:206
onEvent({ eventIdentifier: eventName, data }) {
  dispatchWindowEvent({ eventName, data });
}
```

**[INFERÊNCIA]** Isto é *exatamente* o ponto de extensão necessário. Qualquer evento novo criado dentro do widget (iframe) pode chegar ao `window` do cliente sem mudar a arquitetura — basta adicionar um `eventIdentifier`. O disparo de `fbq`/`gtag`/`dataLayer` mora no SDK (parent), que é onde essas globais existem.

#### Métodos do SDK

**[FATO]** ([documentação oficial Chatwoot](https://www.chatwoot.com/hc/user-guide/articles/1677587234-how-to-send-additional-user-information-to-chatwoot-using-sdk)):

```js
window.$chatwoot.setUser("<identifier>", {
  email, name, avatar_url, phone_number, identifier_hash,   // HMAC SHA256
  description, country_code, city, company_name, social_profiles
});
window.$chatwoot.setCustomAttributes({ accountId: 1, pricingPlan: "paid" });
window.$chatwoot.deleteCustomAttribute("attribute-key");
window.$chatwoot.setLabel("support-ticket");
window.$chatwoot.removeLabel("support-ticket");
window.$chatwoot.reset();
```

No repo, os endpoints correspondentes existem em `app/javascript/widget/api/contacts.js` (`setUser`, `setCustomAttributes`, `deleteCustomAttribute`) e `app/javascript/widget/api/conversation.js` (`setCustomAttributes`, `deleteCustomAttribute` de conversa).

#### Dados de origem já capturados

`app/javascript/sdk/DOMHelpers.js` — o SDK observa mudanças de URL (inclusive em SPAs, via `MutationObserver`) e envia ao iframe:

```js
export const onLocationChangeListener = () => {
  let oldHref = document.location.href;
  const referrerHost = document.location.host;
  onLocationChange({ referrerURL: oldHref, referrerHost });
  const observer = new MutationObserver(mutations => {
    mutations.forEach(() => {
      if (oldHref !== document.location.href) {
        oldHref = document.location.href;
        onLocationChange({ referrerURL: oldHref, referrerHost });
      }
    });
  });
  observer.observe(document.querySelector('body'), { childList: true, subtree: true });
};
```

**[FATO] Ponto crítico:** `referrerURL` é `document.location.href` — a **URL completa, com query string**. Ou seja, **os UTMs, o `gclid` e o `fbclid` já chegam ao backend do Chatwoot hoje**, embutidos na URL. Eles são enviados em `message[referer_url]` (`app/javascript/widget/api/endPoints.js`) e gravados em:

```ruby
# app/controllers/api/v1/widget/base_controller.rb
additional_attributes: {
  browser_language: browser.accept_language&.first&.code,
  browser: browser_params,          # browser_name, browser_version, device_name, platform_name, platform_version
  initiated_at: timestamp_params,
  referer: permitted_params[:message][:referer_url]
}
```

**[INFERÊNCIA] Este é o achado mais acionável de toda a auditoria:** a origem já está no banco, em `conversations.additional_attributes.referer`, em texto. Ninguém parseia. Um parser de UTM/gclid/fbclid sobre esse campo já entregaria valor imediato — sem tocar no widget.

Ressalvas **[FATO]**:
- `Conversation#validate_referer_url` (`app/models/conversation.rb:536-540`) **anula** o campo se a URL não for válida.
- Existe um comentário no próprio código: `# FIXME: typo referrer in additional attributes, will probably require a migration.` (`base_controller.rb:32`) — a chave é `referer` (uma consoante), não `referrer`.
- O `referer` é gravado apenas com a URL vigente **no momento do envio** da mensagem/conversa — não é um histórico, e não é a landing page da sessão.

#### Eventos do backend

`app/controllers/api/v1/widget/events_controller.rb` recebe eventos genéricos do widget e os despacha:

```ruby
def create
  Rails.configuration.dispatcher.dispatch(
    permitted_params[:name], Time.zone.now,
    contact_inbox: @contact_inbox,
    event_info: permitted_params[:event_info].to_h.merge(event_info)
  )
end
```

Hoje o único emissor é `IFrameHelper.pushEvent('webwidget.triggered')` (`IFrameHelper.js:253`), disparado quando a bolha é aberta. O evento existe em `lib/events/types.rb:14` (`WEBWIDGET_TRIGGERED = 'webwidget.triggered'`) e é escutado por `app/listeners/webhook_listener.rb:65` e `app/listeners/agent_bot_listener.rb:36`.

**[INFERÊNCIA]** Há um canal de eventos genérico widget→backend **subutilizado**. É por ele que eventos de tracking deveriam entrar.

#### Webhooks

`app/models/webhook.rb:32-34` — eventos permitidos:

```ruby
ALLOWED_WEBHOOK_EVENTS = %w[
  conversation_status_changed conversation_updated conversation_created
  contact_created contact_updated
  message_created message_updated webwidget_triggered
  inbox_created inbox_updated
  conversation_typing_on conversation_typing_off
].freeze
```

**[INFERÊNCIA]** É possível montar tracking externo hoje usando `conversation_created` + `contact_updated`, mas: (a) sem `event_id` para dedup, (b) sem hash, (c) sem origem parseada, (d) exigindo um middleware que o cliente teria que construir e hospedar. É o "hack" que qualquer integrador faria — e é exatamente o que a issue #7642 chama de *"altamente não confiável"*.

#### Modelo de dados disponível

| Campo | Modelo | Uso possível para tracking |
|---|---|---|
| `additional_attributes` (jsonb) | `contacts`, `conversations` | onde `referer`, `browser`, `initiated_at` já vivem |
| `custom_attributes` (jsonb) | `contacts`, `conversations` | onde `gclid`, `fbclid`, `first_utm_*` deveriam viver |
| `custom_attribute_definitions` | conta | permite tipar/exibir os atributos no dashboard (`attribute_model: conversation_attribute | contact_attribute`) |
| `contact_inboxes.source_id` | — | identificador estável por caixa de entrada |
| `conversations.campaign_id` | — | campanhas **do próprio Chatwoot** (mensagem proativa), não campanha de mídia |
| `pubsub_token` | `contact_inboxes` | — |

E os `automation_rules` já aceitam `referer` como atributo condicional (`app/models/automation_rule.rb:38`) **[FATO]** — ou seja, já dá para criar regra "se referer contém `utm_source=google` então adicionar label".

#### Pré-chat: onde a PII nasce

`app/models/channel/web_widget.rb` tem `pre_chat_form_enabled` e `pre_chat_form_options` (com `require_email` e `pre_chat_fields`). O componente de pré-chat valida telefone (`startsWithPlus`, `isValidPhoneNumber`) e e-mail **[FATO]** (`app/javascript/widget/components/PreChat/`).

**[INFERÊNCIA]** É aqui que nasce o `Lead`. O evento de conversão mais valioso do produto deve ser disparado no sucesso deste formulário — e é aqui que se colhe `em`/`ph` já validados para a CAPI.

#### Cookies do widget

**[FATO]** `app/javascript/sdk/cookieHelpers.js` e `IFrameHelper.js:40-49`:

```js
const updateAuthCookie = (cookieContent, baseDomain = '') =>
  setCookieWithDomain('cw_conversation', cookieContent, { baseDomain });

// cookieHelpers.js
export const setCookieWithDomain = (name, value, { expires = 365, baseDomain = undefined } = {}) => {
  Cookies.set(name, value, { expires, sameSite: 'Lax', domain: baseDomain });
};
```

Cookies: `cw_conversation` (token de autenticação do visitante) e `cw_user_<websiteToken>`. São **first-party** no domínio do cliente, escritos por JavaScript, `SameSite=Lax`, `expires` de 365 dias.

**[INFERÊNCIA]** Como visto em §5.5, no Safari esses cookies são truncados para 7 dias. Se formos guardar origem em cookie, o mesmo limite se aplica — logo a origem **precisa** ser persistida no servidor (no contato), não só no navegador.

### 6.2 O que NÃO existe — a lista negativa

Verificação por `grep` no repositório **[FATO]**:

```bash
grep -rn "dataLayer\|gtag\|fbq\|facebook.*pixel\|googletagmanager" app/ \
  --include=*.js --include=*.vue --include=*.rb --include=*.erb -il
# (nenhum resultado)

grep -rln "fbq|gtag|dataLayer" enterprise/ app/views
# (nenhum resultado)
```

| Não existe | Consequência |
|---|---|
| Qualquer chamada a `fbq`, `gtag`, `dataLayer` | Nenhum evento de marketing sai do widget |
| Qualquer integração Meta Pixel / CAPI | — |
| Qualquer integração GA4 / GTM / Measurement Protocol | — |
| Qualquer integração Google Ads | — |
| Parsing de UTM / `gclid` / `fbclid` | A origem chega crua em `referer` e morre lá |
| Campos de origem no modelo de contato | Não há `utm_source` etc. como atributo de primeira classe |
| Camada de consentimento (Consent Mode) | — |
| Fila/worker de envio server-side para plataformas de anúncio | — |
| Configuração de tracking por caixa de entrada | — |

**Exceção que confunde:** existe `app/javascript/dashboard/helper/AnalyticsHelper/` usando **Amplitude** (`@amplitude/analytics-browser`), habilitado por `CLOUD_ANALYTICS_TOKEN` (`config/installation_config.yml:238`) **[FATO]**. Isso é **telemetria de produto do dashboard do agente** (eventos como `'Sent a message'`, `'Applied a label'`, `'Downloaded a report'`), **não** rastreamento do visitante do site. Não confundir as duas coisas em nenhuma comunicação interna.

Também existe `LOG_ROCKET_PROJECT_ID` nas variáveis de ambiente **[FATO]** ([docs Chatwoot](https://developers.chatwoot.com/self-hosted/configuration/environment-variables)) — session replay do dashboard, mesma categoria.

### 6.3 A restrição arquitetural do iframe

```
   Site do cliente (https://cliente.com.br)          ┌──────── iframe (https://chat.chatspx.app) ───────┐
   ┌──────────────────────────────────────┐          │                                                   │
   │ window                                │          │ window (outro origin)                             │
   │  ├─ fbq            ← EXISTE AQUI      │          │  ├─ Vue app do widget                             │
   │  ├─ gtag/dataLayer ← EXISTE AQUI      │          │  ├─ store, api                                    │
   │  ├─ document.cookie (_fbp/_ga/_gcl)   │          │  └─ NÃO enxerga fbq/gtag do parent  ✗            │
   │  └─ $chatwoot (SDK)  ←── postMessage ─┼──────────┤                                                   │
   └──────────────────────────────────────┘          └───────────────────────────────────────────────────┘
```

**[FATO]** O widget é servido em iframe de outra origem (`IFrameHelper.js` monta o iframe com a URL do servidor Chatwoot). **[INFERÊNCIA]** Consequências não-negociáveis para o desenho:

1. **Todo disparo de tag tem que morar no SDK (parent).** O código do widget (Vue, dentro do iframe) nunca poderá chamar `fbq` diretamente.
2. **Toda leitura de cookie de marketing (`_fbp`, `_fbc`, `_ga`, `_gcl_aw`) tem que morar no SDK.** O iframe não vê `document.cookie` do cliente.
3. **A ponte já existe** (`eventIdentifier` → `dispatchWindowEvent`). Basta estendê-la com um tipo de mensagem dedicado a tracking.
4. **O bundle do SDK cresce.** Hoje `sdk.js` é enxuto (majoritariamente CSS + lógica de bolha). Adicionar tracking exige cuidado com peso — é script de terceiro no site do cliente, e peso vira reclamação de Core Web Vitals.

### 6.4 O que a comunidade Chatwoot já pediu

| Issue | Título | Data | Status | Conteúdo |
|---|---|---|---|---|
| [#5965](https://github.com/chatwoot/chatwoot/issues/5965) | Chatwoot integration with Google Analytics | nov/2022 | **[FATO-2ª]** aberta | Pede envio de eventos de meta do visitante ao GA: abertura do widget, início de conversa, envio de formulário, fim de conversa |
| [#7642](https://github.com/chatwoot/chatwoot/issues/7642) | [CW-2338] Chatwoot Conversion Tracking | 29/jul/2023 | **[FATO]** aberta, assinada a `pranavrajs` | Autor usa `chatwoot:on-message` como gambiarra e chama de *"altamente não confiável"*; pede avaliação automática de conversas contra condições para marcar conversão |
| [#7981](https://github.com/chatwoot/chatwoot/issues/7981) | [CW-2588] Pushing Chatwoot events to data layer | 25/set/2023 | **[FATO]** aberta, labels `feature-request`, `⛈️ feature/messenger`, `🐗 Need Product Spec` | Pede push ao dataLayer de: Opened Messenger, Started a Conversation, Replied to a Conversation, Conversation Closed, Closed Messenger, Ticket Created, Ticket Processed — explicitamente inspirado no Intercom |

**[INFERÊNCIA]** Três anos de pedidos, nenhum entregue no upstream. Isso significa: (a) demanda real e persistente confirmada por terceiros, (b) nenhum risco de o upstream entregar isso antes de nós e tornar o trabalho redundante, (c) se fizermos bem, é candidato natural a contribuição upstream — ou a diferencial proprietário do ChatSPX, o que a Simplex preferir.

### 6.5 Tabela de gap consolidada

| Capacidade | Leadster | ChatSPX hoje | Gap |
|---|---|---|---|
| Detectar pixel/GA já instalado na página | ✅ `fbq.getState().pixels`, `dataLayer ['config']` | ❌ | Implementar no SDK |
| Instalar tag faltante sem duplicar | ✅ com `skipPageView` | ❌ | Implementar no SDK |
| Disparar evento no pixel do cliente | ✅ (`track`) | ❌ | Implementar — e usar `trackSingle` (melhor que a referência) |
| Disparar evento GA4 | ✅ | ❌ | Implementar, com nomes recomendados (`generate_lead`) |
| Conversão Google Ads | ✅ `send_to` | ❌ | Implementar |
| `dataLayer.push` documentado | ✅ (parcialmente) | ❌ | Implementar + documentar melhor que eles |
| Hash SHA-256 de PII | ✅ no browser | ❌ | Implementar no servidor (temos o dado) |
| CAPI server-side | ✅ | ❌ | Implementar |
| GA4 Measurement Protocol | ✅ | ❌ | Implementar |
| `client_id` / `session_id` do site host | ✅ `gtag('get')` + fallback cookie | ❌ | Implementar no SDK |
| `_fbc` a partir de `fbclid` | ✅ | ❌ | Implementar no SDK |
| `_gcl_aw` a partir de `gclid` | ✅ | ❌ | Implementar no SDK |
| Captura de UTM | ✅ (params de URL) | ⚠️ chega cru em `referer`, não parseado | Parser + campos dedicados |
| Deduplicação `event_id` | ❌ | ❌ | **Fazer melhor que a referência** |
| Consent Mode | ❔ | ❌ | Implementar |
| Conversão offline (venda) | ❔ | ❌ | **Espaço em branco do mercado** |
| Configuração por caixa de entrada | ✅ (por script/fluxo) | ❌ | Implementar |
| Log/auditoria de envio | ❔ | ❌ | Implementar (exigência LGPD) |

---
## 7. IMPLICAÇÕES PARA O CHATSPX

> Esta seção é **recomendação**, não implementação. Nenhum código foi escrito no repositório.
> Tudo aqui é **[INFERÊNCIA]** minha, ancorada nos fatos das seções anteriores.

### 7.1 A tese em uma frase

> **O ChatSPX está sentado sobre o dado que a Meta e o Google mais querem (e-mail e telefone validados, com IP, user-agent e desfecho comercial) e hoje não manda nada. Fechar esse loop é a maior alavanca de valor percebido disponível no produto — e o único concorrente que faz isso bem no Brasil (Leadster) faz com falhas que sabemos corrigir.**

### 7.2 O contrato de eventos proposto

Nomes estáveis, prefixo `chatspx_`, `snake_case`, ≤ 40 caracteres (limite GA4).

| # | Evento ChatSPX | Quando dispara | Meta Pixel | GA4 | Google Ads | Server-side | Parâmetros |
|---|---|---|---|---|---|---|---|
| 1 | `chatspx_widget_loaded` | SDK pronto (`chatwoot:ready`) | — | — | — | não | `inbox_id` |
| 2 | `chatspx_widget_opened` | bolha aberta | `ChatOpened` (custom) | `chatspx_widget_opened` | — | opcional | `inbox_id`, `page_url` |
| 3 | `chatspx_conversation_started` | 1ª mensagem do visitante | **`Contact`** (padrão) | `chatspx_conversation_started` | — | **sim** | `conversation_id`, `inbox_id`, `first_utm_*` |
| 4 | `chatspx_prechat_submitted` | pré-chat concluído | **`CompleteRegistration`** | `chatspx_prechat_submitted` | — | **sim** | campos preenchidos (só nomes, não valores) |
| 5 | `chatspx_lead` | contato passa a ter e-mail **ou** telefone | **`Lead`** | **`generate_lead`** | `conversion` (`send_to`) | **sim** (com `em`/`ph` hasheados) | `value`, `currency`, `lead_source`, `conversation_id` |
| 6 | `chatspx_lead_qualified` | regra/agente/IA marca como qualificado | `QualifiedLead` (custom) | **`qualify_lead`** | conversão secundária | **sim** | `value`, `currency`, `qualification_reason` |
| 7 | `chatspx_lead_disqualified` | descartado | — | **`disqualify_lead`** | — | opcional | `disqualified_lead_reason` |
| 8 | `chatspx_agent_engaged` | agente humano assume | — | **`working_lead`** | — | opcional | `lead_status`, `agent_id` |
| 9 | `chatspx_meeting_scheduled` | agendamento confirmado | **`Schedule`** | `chatspx_meeting_scheduled` | conversão | **sim** | `scheduled_at` |
| 10 | `chatspx_conversation_resolved` | conversa resolvida | — | `chatspx_conversation_resolved` | — | opcional | `resolution`, `duration_s` |
| 11 | `chatspx_deal_won` | negócio ganho (CRM/funil Kanban) | **`Purchase`** (offline) | **`close_convert_lead`** | **Offline Conversion Import** | **sim** | `value`, `currency`, `gclid`, `deal_id` |
| 12 | `chatspx_deal_lost` | negócio perdido | — | **`close_unconvert_lead`** | — | opcional | `unconvert_lead_reason` |

**Regras do contrato:**
- Eventos 3, 4, 5, 6, 9, 11 nascem com um **`event_id` (UUID v4) gerado no backend** e são enviados pelos dois caminhos com o mesmo ID.
- Eventos 11 e 12 são **exclusivamente server-side** (o navegador já não existe).
- Todos são também empurrados ao `dataLayer` — sempre, independentemente de haver `fbq`/`gtag`.
- Nenhum evento leva PII crua ao `dataLayer` ou aos parâmetros do `fbq`/`gtag` client-side. PII só vai server-side, hasheada.

### 7.3 Arquitetura proposta — cinco componentes

```
┌───────────────────────── NAVEGADOR DO VISITANTE ───────────────────────────┐
│                                                                            │
│  ┌── SDK (top window, domínio do cliente) ──────────────────────────────┐  │
│  │  [C2] Coletor de origem                                              │  │
│  │    • lê location.search: utm_*, gclid, gbraid, wbraid, fbclid, msclkid│ │
│  │    • lê document.referrer, landing page                              │  │
│  │    • deriva _fbc de fbclid, _gcl_aw de gclid (TTL 90d)               │  │
│  │    • lê _fbp, _ga, _ga_<ID> (allowlist, nunca document.cookie inteiro)│ │
│  │    • gtag('get', ID, 'client_id'|'session_id') com timeout 1s        │  │
│  │    • persiste first_* (write-once) e last_* em localStorage          │  │
│  │                                                                       │  │
│  │  [C3] Ponte de tags                                                  │  │
│  │    • recebe eventos do iframe via eventIdentifier                    │  │
│  │    • detecta fbq.getState().pixels / dataLayer ['config', ID]        │  │
│  │    • instala o que falta (skipPageView) ou usa o existente           │  │
│  │    • dispara fbq trackSingle / gtag event send_to / dataLayer.push   │  │
│  │    • respeita [C5] consentimento                                     │  │
│  └───────────────────────────────────┬──────────────────────────────────┘  │
│                                       │ postMessage                         │
│  ┌── iframe (widget) ─────────────────▼──────────────────────────────────┐  │
│  │  emite eventos de negócio; envia origem coletada ao backend           │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────┬───────────────────────────────────────┘
                                     │ HTTPS
┌────────────────────────────────────▼───────────────────────────────────────┐
│                         BACKEND CHATSPX (Rails)                            │
│                                                                             │
│  [C1] Configuração por inbox        [C4] Fila server-side                   │
│   • pixel_id + access_token          • job por evento (Sidekiq)             │
│   • measurement_id + api_secret      • normaliza + SHA-256 (em/ph/fn/ln/ct/st)│
│   • google_ads: customer_id,         • monta payload CAPI / MP / Ads        │
│     conversion_action, OAuth         • retry com backoff; DLQ               │
│   • mapa evento→destino (on/off)     • dedup: mesmo event_id do client      │
│   • modo teste (test_event_code)     • janelas: CAPI 7d, MP 72h, Ads 90d    │
│                                                                             │
│  [C5] Consentimento + auditoria                                             │
│   • estado de consent por contato/conversa                                  │
│   • log: evento, destino, campos enviados (nomes), status, resposta         │
│   • kill switch por conta e por inbox; retenção configurável                │
│                                                                             │
│  Persistência: contact.custom_attributes / conversation.custom_attributes    │
│    first_utm_source, first_utm_medium, first_utm_campaign, first_referrer,   │
│    first_landing_page, last_utm_*, gclid, gclid_at, fbclid, fbp, fbc,        │
│    ga_client_id, ga_session_id                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                     │                         │                    │
                     ▼                         ▼                    ▼
            Meta Conversions API      GA4 Measurement Protocol   Google Ads API
```

#### C1 — Configuração por caixa de entrada

Onde: tela de configuração da inbox do tipo Website (e, na fase 2, WhatsApp para CTWA).

| Campo | Tipo | Obrigatório | Observação |
|---|---|---|---|
| Meta Pixel ID | string | não | Se vazio, só `dataLayer` |
| Meta Access Token | secret | não | Idealmente por **OAuth**, não colado à mão |
| Meta test_event_code | string | não | Só em modo teste |
| GA4 Measurement ID | string | não | Autodetectável do `dataLayer` |
| GA4 API Secret | secret | não | Só para Measurement Protocol |
| Google Ads Conversion (`send_to`) | string | não | `AW-XXXX/label` |
| Google Ads OAuth | conexão | não | Para offline import |
| Mapa de eventos | tabela | sim | Qual evento ChatSPX vira qual evento em cada destino |
| Valor do lead | número/regra | não | Habilita otimização por valor |
| Modo de consentimento | enum | sim | `sem CMP` / `aguardar consentimento` / `sempre negado` |

**[INFERÊNCIA]** O "cola um ID e funciona" que o usuário pediu é atingível **para o caminho client-side** (Pixel ID e Measurement ID bastam). Para o caminho server-side (que é o que dá o ganho real), é preciso token — e a única forma de manter a promessa é **OAuth de um clique**. Isso deve ser tratado como requisito de produto, não como detalhe técnico.

#### C2 — Coletor de origem

Regras:
- Executar **antes** de qualquer outra coisa no SDK, na primeira visita.
- `first_*` é write-once; `last_*` sobrescreve **apenas** quando há parâmetro de campanha ou referrer externo.
- Nunca copiar `document.cookie` inteiro (crítica à Leadster, §4.1.5): usar allowlist.
- Persistir **no servidor** (contato/conversa), porque o Safari corta o storage local em 7 dias (§5.5).
- Formatos oficiais para `_fbc` (`fb.{n}.{ts}.{fbclid}`) e `_gcl_aw` (`GCL.{unix}.{gclid}`), TTL 90 dias.

#### C3 — Ponte de tags

Pseudocódigo de contrato (ilustrativo, **não** é implementação):

```js
// no SDK, top window
window.addEventListener('chatspx:track', function (e) {
  const { event, meta, ga4, ads, params, eventId } = e.detail;
  if (!consentAllows('ad_storage')) return;      // C5

  // 1) dataLayer SEMPRE
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({ event: 'chatspx_' + event, ...params });

  // 2) Meta — trackSingle no pixel configurado, com eventID para dedup
  if (meta && meta.pixelId) {
    ensurePixel(meta.pixelId);                   // instala com skipPageView se faltar
    window.fbq('trackSingle', meta.pixelId, meta.eventName, params, { eventID: eventId });
  }

  // 3) GA4 — send_to explícito
  if (ga4 && ga4.measurementId && typeof window.gtag === 'function') {
    window.gtag('event', ga4.eventName, { ...params, send_to: ga4.measurementId });
  }

  // 4) Google Ads
  if (ads && ads.sendTo && typeof window.gtag === 'function') {
    window.gtag('event', 'conversion', { send_to: ads.sendTo, value: params.value, currency: params.currency });
  }
});
```

Diferenças deliberadas em relação à Leadster:
1. **`trackSingle`** em vez de `track` — não vaza para pixels de terceiros na página.
2. **`eventID` presente** — habilita a deduplicação com o evento server-side.
3. **`send_to` explícito no GA4** — não polui outras propriedades configuradas na página.
4. **`dataLayer.push` sempre** — quem usa GTM não fica dependente do resto.
5. **Nunca instalar GA4 próprio do ChatSPX no site do cliente** (a Leadster instala `G-43W2WYML5H`; nós não faremos isso).

#### C4 — Fila server-side

- Um job por evento, idempotente pelo `event_id`.
- Normalização antes do hash, seguindo a tabela oficial da Meta (§2.5) e a do Google (§3.7): telefone em E.164 para Google, só dígitos com DDI para Meta.
- Backoff exponencial; a Leadster usa 3 tentativas em erro 500 **[FATO]** — recomendo mais: 5 tentativas com backoff e uma dead-letter queue visível no painel.
- Respeitar janelas: CAPI 7 dias (62 offline), MP 72 h de backdating (48 h para atribuição), Ads 90 dias de `gclid` / 63 dias com PII.
- Enviar sempre `client_ip_address` e `client_user_agent` reais do visitante — nunca o IP do servidor ChatSPX (erro comum que destrói o EMQ).

#### C5 — Consentimento e auditoria

- Método público novo no SDK, tipo `window.$chatwoot.setConsent({ ad_storage: 'granted', analytics_storage: 'granted', ad_user_data: 'granted', ad_personalization: 'denied' })`, para o CMP do cliente chamar.
- Estado padrão configurável por conta: quem opera sob CMP começa negado.
- Log de auditoria por evento: `event_id`, destino, `event_name`, lista de **nomes** de campos enviados (não os valores), timestamp, status HTTP, mensagem de erro, EMQ retornado quando disponível.
- Kill switch por conta e por inbox.
- Retenção configurável do log (sugestão: 90 dias).

### 7.4 Roadmap sugerido em quatro fases

| Fase | Escopo | Valor entregue | Risco |
|---|---|---|---|
| **F0 — Origem (1–2 semanas)** | Parser de `additional_attributes.referer` já existente + coletor de UTM/gclid/fbclid no SDK + persistência em `custom_attributes` + exibição no painel do contato/conversa + filtro por origem | "De onde veio esse lead?" respondido para 100% da base, retroativamente para o que já está no banco | Baixíssimo. Não toca em tag nenhuma. **Comece por aqui.** |
| **F1 — Client-side (2–4 semanas)** | Configuração por inbox (Pixel ID, Measurement ID, `send_to`), ponte de tags no SDK, `dataLayer.push` documentado, eventos 1–5 e 9 | Cliente cola dois IDs e vê conversão no Gerenciador de Anúncios e no GA4 | Médio: mexer no `window` do cliente exige cuidado (não sobrescrever `gtag`, não duplicar `PageView`) |
| **F2 — Server-side (4–8 semanas)** | CAPI + Measurement Protocol + hash + `event_id`/dedup + fila + logs + Consent Mode + OAuth Meta/Google | Recupera os 20–40% perdidos; EMQ alto; diferencial técnico verificável | Alto: credenciais, LGPD, custo de infra, suporte |
| **F3 — Ciclo fechado (8+ semanas)** | Enhanced Conversions, Offline Conversion Import a partir do funil Kanban/CRM, eventos 11–12, `ctwa_clid` para Click-to-WhatsApp | **Espaço em branco do mercado.** Otimização por receita, não por volume de lead | Alto: depende da Google Ads API (developer token) e do funil de vendas do cliente estar no ChatSPX |

**[INFERÊNCIA]** A F0 tem a melhor relação valor/risco de todo o roadmap: o dado **já está no banco** (§6.1), ninguém o usa, e ela não exige negociação com Meta nem Google. É a fase que compra credibilidade para pedir orçamento das outras.

### 7.5 Decisões de projeto que precisam ser tomadas antes de codar

| # | Decisão | Opções | Minha recomendação |
|---|---|---|---|
| 1 | Onde hashear a PII | Navegador (como a Leadster) x Servidor | **Servidor.** Já temos o dado em claro; hashear no servidor permite normalizar/corrigir e evita bug silencioso de match. |
| 2 | Quem gera o `event_id` | Navegador x Backend | **Backend**, devolvido ao widget. Sobrevive a fechar a aba. |
| 3 | GA4: client-side ou Measurement Protocol | Um, outro, ou os dois | **Um por evento lógico.** Se há `gtag` na página → client-side (herda sessão). Se não há, ou o evento é tardio → MP com `client_id`/`session_id` guardados. Nunca os dois. |
| 4 | Instalar tag faltante no site do cliente | Sim x Não | **Sim, opt-in explícito** na configuração da inbox, com aviso claro de que o ChatSPX passará a injetar script de terceiro. Nunca por padrão. |
| 5 | Instalar GA4 próprio do ChatSPX | Sim (como a Leadster) x Não | **Não.** Telemetria de produto vai para o nosso backend, não para o site do cliente. |
| 6 | Nomes de evento GA4 | Custom x Recomendados | **Recomendados** (`generate_lead`, `qualify_lead`, `working_lead`, `close_convert_lead`) — falam a língua do GA4 e habilitam relatórios prontos. |
| 7 | Nomes de evento Meta | Custom x Padrão | **Padrão para o que otimiza** (`Contact`, `Lead`, `CompleteRegistration`, `Schedule`, `Purchase`), custom para diagnóstico. |
| 8 | Valor do lead | Não enviar x Fixo x Por regra | **Por regra**, configurável (ex.: por resposta do pré-chat, por label, por funil). É o que destrava campanhas por ROAS. |
| 9 | Consentimento padrão | Ligado x Desligado | **Desligado quando a conta declarar operar com CMP**; ligado quando declarar que não usa. Nunca decidir por conta própria. |
| 10 | Escopo da configuração | Conta x Inbox | **Inbox.** Agências e clientes multi-site precisam de pixels diferentes por site. |

### 7.6 Riscos e como mitigar

| Risco | Impacto | Mitigação |
|---|---|---|
| Quebrar a medição do site do cliente (sobrescrever `gtag`, duplicar `PageView`) | Altíssimo — perda de confiança irreversível | Código aditivo (`x = x \|\| ...`), `skipPageView`, `trackSingle`/`send_to`, modo "somente dataLayer" como padrão seguro |
| Conversão contada em dobro (Pixel + CAPI sem dedup) | Alto — cliente toma decisão de mídia com número inflado | `event_id` obrigatório em todo evento com par client/server; teste de QA que compara contagens |
| PII vazando para o `dataLayer` ou para os params do `fbq` | Altíssimo — incidente LGPD | Regra dura: PII só server-side, só hasheada; lint/teste que barra campos sensíveis no payload client-side |
| Token da Meta ou `api_secret` do GA4 vazando para o navegador | Altíssimo | Segredos **nunca** saem do backend; nunca aparecem em endpoint público do widget |
| Cliente sem CMP disparando tag sem consentimento na Europa | Médio/Alto | Consent Mode integrado + declaração obrigatória na configuração |
| Peso do `sdk.js` crescendo e prejudicando Core Web Vitals do cliente | Médio | Carregar a parte de tracking sob demanda (só quando há configuração ativa); orçamento de bytes explícito |
| Custo de infra da fila server-side em escala | Médio | Batch (CAPI aceita até 1.000 eventos/request), throttling por conta, métricas de custo por conta |
| Suporte: "não apareceu no Gerenciador" | Alto (custo operacional recorrente) | Painel de diagnóstico com log por evento, modo teste com `test_event_code`, e uma página de documentação pública de verdade (o ponto fraco da Leadster, §4.1.7) |
| Upstream Chatwoot lançar algo conflitante | Baixo | Três anos de issues abertas sem entrega (§6.4); manter a implementação isolada em módulo próprio para facilitar merge |

### 7.7 Como medir se deu certo

**[INFERÊNCIA]** Métricas de sucesso da feature, do nosso lado:

| Métrica | Meta sugerida |
|---|---|
| % de inboxes Website com tracking configurado | > 40% em 90 dias |
| EMQ médio dos eventos `Lead` dos clientes | ≥ 7,0 (idealmente 8,0+) |
| Taxa de entrega da fila server-side (2xx / total) | > 99% |
| Eventos deduplicados corretamente (amostragem no Events Manager) | 100% dos pares |
| Chamados de suporte por 100 inboxes com tracking ligado | tendência decrescente mês a mês |
| Diferença entre leads no ChatSPX e conversões reportadas no destino | < 10% |

---

## 8. Apêndices

### 8.1 Snippets de referência (para consulta, não para colar)

**Meta Pixel com dedup:**
```js
fbq('trackSingle', '<PIXEL_ID>', 'Lead', {
  content_name: 'chat_prechat',
  value: 250.0,
  currency: 'BRL'
}, { eventID: '9f2b6d4e-1a3c-4c8e-9f11-7a2b6c4d8e10' });
```

**Meta CAPI equivalente (servidor):**
```json
{
  "data": [{
    "event_name": "Lead",
    "event_time": 1786000000,
    "event_id": "9f2b6d4e-1a3c-4c8e-9f11-7a2b6c4d8e10",
    "event_source_url": "https://cliente.com.br/planos?utm_source=google&gclid=EAIa...",
    "action_source": "website",
    "user_data": {
      "em": ["<sha256(lowercase(trim(email)))>"],
      "ph": ["<sha256(digits_with_country_code)>"],
      "fn": ["<sha256>"], "ln": ["<sha256>"],
      "ct": ["<sha256('saopaulo')>"], "st": ["<sha256('sp')>"],
      "country": ["<sha256('br')>"],
      "external_id": ["<sha256('contact_98765')>"],
      "fbp": "fb.1.1786000000.1234567890",
      "fbc": "fb.1.1785990000.EAIaIQobChMI...",
      "client_ip_address": "200.150.100.50",
      "client_user_agent": "Mozilla/5.0 ..."
    },
    "custom_data": { "value": 250.0, "currency": "BRL", "content_name": "chat_prechat" }
  }]
}
```

**GA4 client-side:**
```js
gtag('event', 'generate_lead', {
  send_to: 'G-XXXXXXXXXX',
  currency: 'BRL',
  value: 250.0,
  lead_source: 'chatspx_widget'
});
```

**GA4 Measurement Protocol (servidor):**
```
POST https://www.google-analytics.com/mp/collect?measurement_id=G-XXXXXXXXXX&api_secret=SECRET
```
```json
{
  "client_id": "1234567.7654321",
  "timestamp_micros": 1786000000000000,
  "consent": { "ad_user_data": "GRANTED", "ad_personalization": "GRANTED" },
  "events": [{
    "name": "close_convert_lead",
    "params": { "session_id": "1786000000", "engagement_time_msec": 100, "currency": "BRL", "value": 8400.0 }
  }]
}
```

**Google Ads — conversão client-side:**
```js
gtag('event', 'conversion', {
  send_to: 'AW-123456789/AbC-D_efG-h12_34-567',
  value: 250.0, currency: 'BRL',
  transaction_id: 'chatspx-lead-987'
});
```

**Google Ads — Enhanced Conversions:**
```js
gtag('set', 'user_data', {
  sha256_email_address: '<sha256>',
  sha256_phone_number: '<sha256 do E.164>',
  address: {
    sha256_first_name: '<sha256>', sha256_last_name: '<sha256>',
    city: 'sao paulo', region: 'SP', postal_code: '01310-000', country: 'BR'
  }
});
```

**dataLayer:**
```js
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({
  event: 'chatspx_lead',
  chatspx_inbox_id: 42,
  chatspx_conversation_id: 987,
  chatspx_event_id: '9f2b6d4e-1a3c-4c8e-9f11-7a2b6c4d8e10',
  lead_source: 'google / cpc / marca',
  value: 250, currency: 'BRL'
});
```

**Consent Mode v2:**
```js
gtag('consent', 'default', {
  ad_storage: 'denied', ad_user_data: 'denied',
  ad_personalization: 'denied', analytics_storage: 'denied',
  wait_for_update: 500
});
// depois do aceite:
gtag('consent', 'update', {
  ad_storage: 'granted', ad_user_data: 'granted',
  ad_personalization: 'granted', analytics_storage: 'granted'
});
```

### 8.2 Checklist de QA de uma integração de tracking

1. [ ] Instalar em página **sem** pixel: o widget instala? Dispara `PageView` duplicado? (não deve)
2. [ ] Instalar em página **com** pixel do mesmo ID: há duplicidade? (não deve)
3. [ ] Instalar em página com **3 pixels diferentes**: o evento vaza para os outros? (não deve, com `trackSingle`)
4. [ ] Meta Events Manager → o evento aparece com `Browser` **e** `Server` e o total **não** dobra
5. [ ] Meta Events Manager → EMQ ≥ 6,0 (idealmente 8,0)
6. [ ] Meta Test Events com `test_event_code` mostra os dois eventos com o mesmo `event_id`
7. [ ] GA4 DebugView → evento chega com `session_id` e a origem da sessão está correta (não "(direct)")
8. [ ] GA4 → o evento **não** é contado duas vezes (client + MP)
9. [ ] Google Ads → conversão registrada, com valor e moeda
10. [ ] `gclid` persistido no contato e legível no painel
11. [ ] Com bloqueador de anúncio ligado: client-side falha, server-side entrega
12. [ ] Safari (ITP): fluxo funciona; origem sobrevive porque está no servidor
13. [ ] CMP negando consentimento: nenhum evento client-side dispara; server-side respeita o estado
14. [ ] `dataLayer` não contém e-mail, telefone ou nome em claro
15. [ ] Log de auditoria registra o envio, sem armazenar valores de PII
16. [ ] Erro 5xx do destino: retry acontece; após N falhas vai para DLQ visível
17. [ ] Console do navegador limpo (nenhum erro do SDK na página do cliente)
18. [ ] `window.gtag` e `window.dataLayer` do cliente permanecem funcionais depois de carregar o widget

### 8.3 Glossário

| Termo | Definição |
|---|---|
| **CAPI** | Conversions API — envio server-to-server de eventos para a Meta |
| **EMQ** | Event Match Quality — nota 0–10 da Meta para a capacidade de casar o evento com uma pessoa |
| **MP** | Measurement Protocol — API server-to-server do GA4 |
| **sGTM** | Google Tag Manager server-side |
| **EC** | Enhanced Conversions — envio de dados hasheados do cliente ao Google Ads |
| **OCI** | Offline Conversion Import — importação de conversões que aconteceram fora do site |
| **ITP** | Intelligent Tracking Prevention — mecanismo de privacidade do Safari/WebKit |
| **CMP** | Consent Management Platform — banner/gestor de consentimento |
| **CTWA** | Click-to-WhatsApp — anúncio que abre conversa no WhatsApp |
| **`fbclid` / `gclid`** | Identificadores de clique de anúncio, injetados na URL de destino |
| **`_fbp` / `_fbc`** | Cookies first-party da Meta (browser ID e click ID) |
| **`client_id` / `session_id`** | Identificadores do GA4 para navegador e sessão |
| **Dedup** | Deduplicação de um mesmo evento enviado por dois caminhos |

### 8.4 Lacunas explícitas (o que NÃO foi verificado)

1. Se o RD Station Conversas dispara eventos nativos para Pixel/GA4 a partir do **chat de site** (só confirmei pixel + CAPI nas landing pages do RD Marketing).
2. Se o Octadesk tem integração nativa com Meta Pixel/GA4 no chat de site.
3. Estado atual do suporte GA4 no Zendesk Web Widget messaging.
4. Se o backend da Leadster gera `event_id` e faz deduplicação de outra forma (pelo lado do navegador, não vi `eventID` sendo passado ao `fbq`).
5. Host exato da API da Leadster para `/marketing_event/block-events` e `/whatsapp_tracking`.
6. Janela oficial de retenção do `msclkid` (Microsoft Ads) e do `ttclid` (TikTok).
7. Se o webhook do WhatsApp Cloud API / WAHA entrega hoje ao ChatSPX o objeto `referral` com `ctwa_clid`.
8. Se a Simplex já possui DPA/aditivo contratual que cubra o envio de PII hasheada a Meta/Google em nome dos clientes.
9. Preços atuais e oficiais de Stape/RudderStack (usei valores citados por fontes secundárias em 2026; conferir na página do fornecedor antes de qualquer decisão de compra).
10. Se a Leadster oferece deduplicação, consent mode ou conversão offline — não há documentação pública e não consegui inferir do bundle.

### 8.5 Fontes

**Meta (oficiais)**
- [Meta Pixel — Reference (eventos padrão e propriedades)](https://developers.facebook.com/docs/meta-pixel/reference)
- [Meta Pixel — Advanced (múltiplos pixels, trackSingle, autoConfig)](https://developers.facebook.com/docs/meta-pixel/advanced/)
- [Meta Pixel — Conversion tracking](https://developers.facebook.com/docs/meta-pixel/implementation/conversion-tracking/)
- [Conversions API — Using the API](https://developers.facebook.com/docs/marketing-api/conversions-api/using-the-api)
- [Conversions API — Customer information parameters](https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/customer-information-parameters)
- [Conversions API — Deduplicate Pixel and Server Events](https://developers.facebook.com/docs/marketing-api/conversions-api/deduplicate-pixel-and-server-events)

**Google (oficiais)**
- [GA4 — Recommended events](https://developers.google.com/analytics/devguides/collection/ga4/reference/events)
- [GA4 — Measurement Protocol: sending events](https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events)
- [Tag Platform — Consent mode](https://developers.google.com/tag-platform/security/guides/consent)
- [Tag Manager — Server-side tagging](https://developers.google.com/tag-platform/tag-manager/server-side)
- [Google Ads Help — Enhanced conversions (web)](https://support.google.com/google-ads/answer/9888656)
- [Google Ads Help — Enhanced conversions com Google tag](https://support.google.com/google-ads/answer/13258081)
- [Google Ads Help — Enhanced conversions com GTM](https://support.google.com/google-ads/answer/13262500)
- [Google Ads Help — Offline conversions com GCLID](https://support.google.com/google-ads/answer/7012522)
- [Google Ads API — Manage offline conversions](https://developers.google.com/google-ads/api/docs/conversions/upload-offline)
- [GA4 Help — Behavioral modeling for consent mode](https://support.google.com/analytics/answer/11161109)

**Fornecedores de chat**
- [Leadster — bundle público `neurolead.min.js` v2.67.0](https://cdn.leadster.com.br/neurolead/neurolead.min.js) *(fonte primária de código)*
- [Leadster — Configurar eventos do pixel da Meta e GA4](https://help.leadster.com.br/article/120-como-configurar-os-eventos-do-pixel-da-meta-e-o-ga4-de-maneira-automatizada)
- [Leadster — Configurar GA4 para eventos de conversões](https://help.leadster.com.br/article/122-como-configurar-o-google-analytics-para-enviar-eventos-de-conversoes)
- [Leadster — Plataformas de integração](https://help.leadster.com.br/article/82-com-quais-plataformas-consigo-integrar-a-leadster)
- [Leadster — plugin WordPress](https://wordpress.org/plugins/leadster-marketing-conversacional/)
- [JivoChat — Facebook Pixel](https://www.jivochat.com/help/integrations/fb-pixel.html)
- [JivoChat — Google Analytics](https://www.jivochat.com/help/integrations/google-analytics-integration.html)
- [Tidio — Integração com GTM](https://help.tidio.com/hc/en-us/articles/9049293832220-Integration-with-Google-Tag-Manager)
- [Tidio — Integração com GA4](https://help.tidio.com/hc/en-us/articles/5422047432732-Integration-with-Google-Analytics-GA4)
- [Intercom — Google Analytics app](https://www.intercom.com/help/en/articles/2454807-google-analytics-app)
- [Intercom — GA4 com GTM](https://www.intercom.com/help/en/articles/6990698-setting-up-the-ga4-integration-with-google-tag-manager)
- [Drift — Drift Events](https://devdocs.drift.com/docs/drift-events)
- [HubSpot Community — Chat & GA event tracking](https://community.hubspot.com/t5/Reporting-Analytics/HubSpot-Chat-amp-Google-Analytics-Event-Tracking/m-p/370205)
- [Zendesk — Zendesk Chat com Google Analytics](https://support.zendesk.com/hc/en-us/articles/4408893279770-Setting-up-Zendesk-Chat-with-Google-Analytics)
- [RD Station — Instalar pixel do Facebook](https://ajuda.rdstation.com/s/article/Instalar-pixel-do-Facebook?language=pt_BR)
- [RD Station Conversas](https://www.rdstation.com/produtos/conversas/)
- [Octadesk — Plataforma de atendimento](https://www.octadesk.com/produtos/plataforma-de-atendimento)

**Chatwoot**
- [Chatwoot — Enviar informações adicionais via SDK](https://www.chatwoot.com/hc/user-guide/articles/1677587234-how-to-send-additional-user-information-to-chatwoot-using-sdk)
- [Chatwoot — Variáveis de ambiente](https://developers.chatwoot.com/self-hosted/configuration/environment-variables)
- [Issue #5965 — Integration with Google Analytics](https://github.com/chatwoot/chatwoot/issues/5965)
- [Issue #7642 — Chatwoot Conversion Tracking](https://github.com/chatwoot/chatwoot/issues/7642)
- [Issue #7981 — Pushing Chatwoot events to data layer](https://github.com/chatwoot/chatwoot/issues/7981)

**Privacidade e navegadores**
- [ANPD — Guia Orientativo: Cookies e Proteção de Dados Pessoais](https://www.gov.br/anpd/pt-br/centrais-de-conteudo/materiais-educativos-e-publicacoes/guia_orientativo_cookies_e_protecao_de_dados_pessoais)
- [WebKit — Full Third-Party Cookie Blocking and More](https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/)
- [LEC — Guia Orientativo da ANPD](https://www.lec.com.br/guia-orientativo-da-anpd/)
- [Mattos Filho — Brazilian data protection](https://www.mattosfilho.com.br/en/unico/brazilian-data-protection/)

**Mercado, custos e dados (fontes secundárias)**
- [Simo Ahava — Session attribution with GA4 Measurement Protocol](https://www.simoahava.com/analytics/session-attribution-with-ga4-measurement-protocol/)
- [Stape — GA4 recommended events for lead generation](https://stape.io/news/ga4-new-recommended-events-lead-generation)
- [Triple Whale — Event Match Quality](https://www.triplewhale.com/blog/event-match-quality)
- [CustomerLabs — EMQ score](https://www.customerlabs.com/blog/improve-your-event-match-quality-from-ok-to-great/)
- [SignalBridge — What is Event Match Quality](https://www.signalbridgedata.com/blog/what-is-event-match-quality)
- [SignalBridge — Server-side tracking pricing comparison](https://www.signalbridgedata.com/blog/server-side-tracking-pricing-comparison)
- [TagFly — Stape alternatives, priced](https://tagfly.io/blog/stape-alternatives-priced-and-the-request-billing-trap/)
- [Cometly — Ad blockers preventing conversion tracking](https://www.cometly.com/post/ad-blockers-preventing-conversion-tracking)
- [Improvado — What is a tracking pixel](https://improvado.io/blog/what-is-tracking-pixel)
- [Sleek Analytics — AdBlocker impact on web analytics](https://getsleek.io/blog/adblocker-impact-on-analytics)
- [Cropink — Ad blocker usage statistics](https://cropink.com/ad-blockers-usage-statistics)
- [Seresa — Do ad blockers affect Facebook Pixel?](https://seresa.io/seed/data-loss-adblockers/adblocker-impact-ad-blocker-facebook-pixel)
- [Watsspace — Meta CAPI deduplication event_id](https://watsspace.com/blog/meta-conversions-api-deduplication-event_id/)
- [Adsuploader — Meta Conversions API](https://adsuploader.com/blog/meta-conversions-api)
- [Enalitica — Meta CAPI Gateway](https://enalitica.com/blog/meta-capi-gateway)
- [Jon Loomer — Facebook Conversions API Gateway](https://www.jonloomer.com/facebook-conversions-api-gateway/)
- [MetricFixer — Click-to-WhatsApp attribution](https://metricfixer.com/publications/analytics-conversion-tracking/track-click-to-whatsapp-ads-campaign-ad-creative-without-website)
- [WOZTELL — CAPI for WhatsApp Ads](https://support.woztell.com/portal/en/kb/articles/wa-conversion-flow)
- [Whapi — Track Click-to-WhatsApp ROI with ctwa_clid](https://whapi.cloud/blog/track-click-to-whatsapp-ctwa-clid)
- [DumbData — Tidio Chat event listener](https://dumbdata.co/listeners/tidio-chat-event-listener/)
- [Plausible — Consent Mode e modelagem no GA4](https://plausible.io/blog/consent-mode-ga4-modeled-data)
- [Improvado — Open source Segment alternatives](https://improvado.io/blog/open-source-segment-alternative)

### 8.6 Arquivos do repositório citados (leitura apenas)

```
app/javascript/sdk/sdk.js
app/javascript/sdk/IFrameHelper.js                     (linhas 40-49, 160, 196-260)
app/javascript/sdk/DOMHelpers.js                       (onLocationChange / onLocationChangeListener)
app/javascript/sdk/bubbleHelpers.js                    (linhas 78-80)
app/javascript/sdk/cookieHelpers.js
app/javascript/widget/constants/sdkEvents.js
app/javascript/widget/api/endPoints.js
app/javascript/widget/api/events.js
app/javascript/widget/api/contacts.js
app/javascript/widget/api/conversation.js
app/javascript/widget/helpers/actionCable.js           (linhas 67, 83)
app/javascript/widget/components/ChatFooter.vue        (linha 86)
app/javascript/widget/components/TeamAvailability.vue  (linha 21)
app/javascript/widget/components/PreChat/
app/javascript/widget/store/modules/contacts.js
app/javascript/widget/store/modules/campaign.js
app/javascript/widget/store/modules/appConfig.js
app/javascript/dashboard/helper/AnalyticsHelper/index.js
app/javascript/dashboard/helper/AnalyticsHelper/events.js
app/javascript/dashboard/helper/scriptHelpers.js
app/controllers/api/v1/widget/base_controller.rb       (linhas 30-45, 63-70)
app/controllers/api/v1/widget/events_controller.rb
app/controllers/api/v1/widget/conversations_controller.rb
app/controllers/api/v1/widget/messages_controller.rb
app/models/webhook.rb                                  (linhas 32-34)
app/models/conversation.rb                             (linhas 154, 536-540)
app/models/contact.rb                                  (push_event_data / webhook_data)
app/models/contact_inbox.rb
app/models/custom_attribute_definition.rb
app/models/channel/web_widget.rb
app/models/automation_rule.rb                          (linha 38)
app/listeners/webhook_listener.rb                      (linha 65)
app/listeners/agent_bot_listener.rb                    (linha 36)
lib/events/types.rb                                    (linha 14)
config/installation_config.yml                         (linha 238 — CLOUD_ANALYTICS_TOKEN)
```

---

**Fim do documento.** Nenhum arquivo do repositório foi modificado durante esta pesquisa; o único artefato em disco é este markdown.
