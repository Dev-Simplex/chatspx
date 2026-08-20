# Estudo: chat de site — Leadster, mercado e ChatSPX

**Data:** 11–12/08/2026 · **Fase:** estudo puro, sem implementação
**Corpus:** 18 relatórios, ~31.100 linhas, 360 screenshots medidos
**Produzido por:** 3 ondas de orquestração Orca — `run_b92f5cb38a6f` (mercado),
`run_3b65793a99e0` (front end), `run_780419071dbb` (integração, em curso)

---

## Por onde começar

| Se você quer... | Leia |
|---|---|
| **Repaginar o front end** | **[frontend/16-spec-redesenho.md](frontend/16-spec-redesenho.md)** — sistema visual, componente a componente, 3 fases, checklist de aceite |
| A conclusão de negócio e o que fazer | [10-gap-analysis.md](10-gap-analysis.md) — matriz de 68 capacidades, 4 ondas, 10 decisões |
| Entender o concorrente | [01-leadster-produto.md](01-leadster-produto.md) + [02-leadster-tecnico.md](02-leadster-tecnico.md) |
| Pixel Meta / GA4 / Ads | [07-tracking-pixel-ga4.md](07-tracking-pixel-ga4.md) |
| Saber o que temos hoje | [09-nosso-widget-auditoria.md](09-nosso-widget-auditoria.md) + [frontend/15-arquitetura-front-chatspx.md](frontend/15-arquitetura-front-chatspx.md) |
| Medidas reais dos concorrentes | [frontend/11-teardown-visual.md](frontend/11-teardown-visual.md) — 14 widgets, 360 screenshots |

**Dossiê visual:** abra [`dossie.html`](dossie.html) no navegador (arquivo único, offline).

---

## Os três achados que reposicionam o projeto

### 1. O front end da Leadster é próprio; o Chatwoot está atrás, no atendimento

**Correção de 11/08/2026 — leia com atenção, a primeira redação deste índice era imprecisa.**

São duas superfícies distintas e não devem ser confundidas:

| Superfície | O que é | Tecnologia |
|---|---|---|
| Widget em `leadster.com.br` | O chat que o visitante vê (bolha, "Ana", fluxo de captura) | **Proprietário deles** — `neurolead.min.js` do CDN próprio, injetado via GTM, falando com `app.leadster.com.br/api/chatbot/*` |
| `atendimento.leadster.com.br` | Painel do agente / "WhatsApp Suite" | **Chatwoot 4.5.2 self-hosted enterprise**, white-labelado |

Observação direta em Chromium (11/08/2026, `leadster.com.br`): carrega
`cdn.leadster.com.br/neurolead/neurolead.min.js` + `modules/neurologic.js`; DOM tem
`div#registration-chatbot.nld-chatbot` com 31 elementos `.nld-*` e **zero shadow roots**;
globais `neurolead`, `neuroleadId`, `nldAPI_Neurologic_PostMessage`; **nenhum WebSocket** e
nenhum request para `atendimento.leadster.com.br` na fase de bot.

O Chatwoot é comprovado no atendimento: `GET atendimento.leadster.com.br/api` devolve
`{"version":"4.5.2"}`, o host seta `_chatwoot_session`, e o `window.globalConfig` expõe
`CHATWOOT_INBOX_TOKEN`, `INSTALLATION_NAME: "Leadster"`, `IS_ENTERPRISE: true`.

**A ponte entre os dois:** dentro do bundle `neurolead` existe um cliente ActionCable do
Chatwoot (`RoomChannel`, `pubsub_token`, `message.created`, `conversation.typing_on/off`,
`conversation.status_changed`) — ver `02-leadster-tecnico.md` §7.2. Ele **só entra em cena
no handoff para atendente humano**, não no carregamento da página.

Ou seja: **front end de captura proprietário, Chatwoot como backend de live chat humano.**

Tudo que eles vendem como WhatsApp Suite, CSAT, SLA, Automações, Campanhas, Etiquetas,
Respostas prontas e Funções personalizadas roda em Chatwoot 4.5.2 — e nós rodamos 4.12.1.

**O gap não é de plataforma de atendimento. É de camada de aquisição** — e o front end de
captura deles é justamente a peça que não temos.

### 2. O diferencial real deles é atribuição, não interface

O produto proprietário da Leadster são duas peças: o widget de captura (`neurolead`, 456 KB)
e — a que importa — o script `tracking/v1/leadster.min.js` (`window.ll`, 6 KB), que persiste
~40 parâmetros de URL como cookies `ll_*`, recria `_fbc`/`_gcl_aw` a partir de
`fbclid`/`gclid` (contorno de ITP) e propaga cookies + `client_id`/`session_id` do GA4 como
query params nos links de saída para o WhatsApp.

Do nosso lado: **zero** ocorrências de `fbq`, `gtag` ou `dataLayer` em `app/`. E a origem
já está no banco, crua, em `conversations.additional_attributes.referer`, sem ninguém parsear.

### 3. No Brasil o widget não é o destino — é a rampa

75,96% das empresas redirecionam para o WhatsApp, e quem redireciona converte +0,54 p.p.
(+20% relativo). Conversão mediana de site no Brasil: 3,07%. Só 6,60% das empresas usam IA
em geração de leads — mercado praticamente virgem.

---

## Onde já ganhamos deles

| | ChatSPX | Leadster |
|---|---|---|
| Loader no site do cliente | **28,8 KB** | 456,1 KB (15,9× mais pesado) |
| API pública para o host | **14 métodos, 7 eventos** | 1 método, 0 eventos |
| Verificação de identidade HMAC | **sim, com escopo de conversa** | não tem |
| Isolamento | iframe | `div` no DOM + 239 `!important` |
| Reconexão de WebSocket | backoff exponencial + jitter, watchdog 15 s | desiste após 5 tentativas de 1 s |
| Acessibilidade | parcial | 1 `role`, 3 `tabIndex`, **0** `aria-*` |

---

## Passivo próprio, verificado

**O `widget_color` por inbox não chega ao header nem ao botão de enviar.**
`ChatHeader.vue:28`, `ChatHeaderExpanded.vue:34` e `ChatSendButton.vue:27` usam `bg-n-brand`
fixo (hover literal `#1FB85A`). Todo cliente white-label tem hoje a cor dele na bolha e a
nossa no cabeçalho. É bug de produto, não detalhe de estilo.

---

## Os 10 relatórios

| # | Arquivo | Linhas | Escopo |
|---|---|---:|---|
| 01 | `01-leadster-produto.md` | 2.582 | Empresa, tese de marketing conversacional, Panorama, linha de produto, preços, KB (202 artigos), críticas |
| 02 | `02-leadster-tecnico.md` | 2.390 | Bundle `neurolead` dissecado: carregamento, renderização, endpoints, storage, tracking, segurança |
| 03 | `03-players-globais.md` | 2.763 | Intercom, Drift, HubSpot, Zendesk, Freshchat, Tidio, Crisp, LiveChat, Olark, tawk.to e outros |
| 04 | `04-players-br.md` | 1.546 | RD Station, Take Blip, Zenvia, Octadesk, Huggy, JivoChat, Kommo, Cliengo, Movidesk e outros |
| 05 | `05-arquitetura-widgets.md` | 3.011 | Estado da arte: loader, isolamento, transporte, persistência, segurança, performance, a11y, i18n |
| 06 | `06-ux-conversao.md` | 2.270 | Anatomia do widget, proatividade, formulário conversacional, benchmarks, anti-padrões |
| 07 | `07-tracking-pixel-ga4.md` | 2.223 | Meta Pixel + CAPI, GA4, GTM, Google Ads, Consent Mode v2, atribuição, conversão offline |
| 08 | `08-ia-em-chats.md` | 1.232 | Fin, Sierra, Decagon, Lyro, Agentforce; preço por resolução; auditoria do Captain |
| 09 | `09-nosso-widget-auditoria.md` | 1.618 | Boot, API pública, features, dívidas — tudo com arquivo:linha |
| 10 | `10-gap-analysis.md` | 839 | Matriz 68 capacidades, 4 baldes de gap, tracking camada a camada, roadmap, 10 decisões |

---

## Onda 2 — redesenho do front end (12/08/2026)

Run Orca `run_3b65793a99e0`. Em `plano/estudo-chat-web/frontend/`, **9.396 linhas + 360
screenshots** em `frontend/shots/`. Regra desta onda: **medir, não opinar** — toda medida
visual veio de `getComputedStyle`/`getBoundingClientRect` em browser real.

| # | Arquivo | Linhas | Escopo |
|---|---|---:|---|
| 11 | `frontend/11-teardown-visual.md` | 1.266 | 14 widgets medidos em produção: launcher, teaser, painel, balão, composer, tipografia, paleta, mobile, dark |
| 12 | `frontend/12-motion-estados.md` | 1.033 | Durações e easings literais, typing indicator, estados de envio, scroll, foco, reduced-motion |
| 13 | `frontend/13-linguagem-visual-2026.md` | 1.542 | Material 3, HIG, Polaris, Carbon aplicados a chat; WCAG 2.2; padrões de UI de IA |
| 14 | `frontend/14-logica-concorrentes.md` | 2.005 | Máquina de estados, schema de fluxo, bootstrap, persistência, rede, handoff, erro |
| 15 | `frontend/15-arquitetura-front-chatspx.md` | 1.674 | Raio-X do nosso front com `arquivo:linha`, tokens propostos, risco de merge |
| 16 | `frontend/16-spec-redesenho.md` | 1.876 | **Especificação executável**: 6 princípios, sistema visual, componentes, 3 fases, aceite |

### Os problemas de cor, agora medidos e fechados

O widget mostra **duas cores de marca na mesma tela**: com `widget_color = #009CE0`, o launcher
e o balão do visitante saem `#009CE0`, mas header, botão de enviar, links e foco saem `#2DC46F`.
Causa rastreada: `brand: '#2dc46f'` é literal em `theme/colors.js:123`, e a variável
`--widget-color` que `App.vue:118-125` escreve **não tem um único consumidor em CSS**.
Nenhum dos 16 concorrentes medidos exibe duas cores de marca simultâneas.

Contraste reprovando AA, medido em produção:
- balão do visitante: **3,07:1** (mínimo AA é 4,5:1), nos dois temas
- link na bolha do agente: **2,27:1** no tema claro
- **header verde com texto branco: 2,25:1** — reprova AA e reprova até o mínimo de componente (3:1)

O último fechou a lacuna que o `09 §16.4 A6` tinha deixado como estimativa não verificada.
Se o verde ficar, o texto tem de ser preto (9,35:1). E a heurística YIQ que usamos hoje diverge
da regra WCAG em **11 de 16** cores de marca testadas, sempre escolhendo branco onde preto teria
mais contraste.

### O que já está certo

Doze medidas nossas coincidem com a mediana ou a moda do mercado: launcher 64×64 (faixa 54–65),
offsets 20/20 (o valor mais repetido), painel 400 px (moda exata), altura 640 (mediana 632),
raio 16 px (mediana exata), padding do balão 12/16 (mediana exata), mobile fullscreen, iframe,
`z-index` 2147483000. **O redesenho não recomeça da geometria** — ataca cor, movimento,
acessibilidade e peso (2,58 MB crus servidos sem compressão).

---

## Onda 3 — integração site ↔ chat (12/08/2026)

Run Orca `run_780419071dbb`. Em `plano/estudo-chat-web/integracao/`, **6.024 linhas**.
Origem: o pedido de "o site se vincular ao chat e passar parâmetros".

| # | Arquivo | Linhas | Escopo |
|---|---|---:|---|
| 17 | `integracao/17-handshake-parametros.md` | 1.933 | API de identificação de 11 fornecedores (assinatura literal + runtime), segurança do handshake HMAC vs JWT, inventário do nosso `$chatwoot` |
| 18 | `integracao/18-webhooks-apis.md` | 1.456 | Catálogo de eventos de 9 fornecedores com payloads reais, confiabilidade (assinatura/retry/idempotência), inventário do nosso webhook |
| 19 | `integracao/19-contexto-na-pratica.md` | 1.060 | Que contexto passar por vertical, como o mercado exibe ao atendente, risco de PII e prompt injection |
| 20 | `integracao/20-spec-integracao.md` | 1.580 | **Síntese**: contrato de integração, matriz de 42 capacidades × 5, modelo de ameaça, faseamento |

**Tese da frente:** não perdemos em superfície — 13 métodos, 7 eventos, HMAC, webhook assinado
com timestamp; é mais que Leadster, Tidio, JivoChat e tawk.to. **Perdemos em contrato.**
O defeito mais caro: atributo enviado pelo site sem `CustomAttributeDefinition` prévia é gravado
no banco, entra no prompt da IA e fica **invisível no painel do agente**
(`CustomAttributes.vue:76-89` itera as definições, não os valores).

---

## Convenção de evidência

Os relatórios marcam **[FATO]** (verificado, com URL ou arquivo:linha) e
**[INFERÊNCIA]** (leitura do autor). O que não deu para verificar está marcado
**não verificado**. A síntese cita a origem de cada bloco no formato `[F, 02 §7.1]`.

---

## Estado

**Estudo encerrado em 12/08/2026.** Três ondas, 22 relatórios, 36.189 linhas,
360 screenshots medidos. Nenhum arquivo de código foi alterado.

As 24 decisões em aberto estão consolidadas em **[DECISOES.md](DECISOES.md)**, junto com os
6 defeitos verificados que **não dependem de decisão** — esses estão errados hoje, em produção,
para todos os clientes.
