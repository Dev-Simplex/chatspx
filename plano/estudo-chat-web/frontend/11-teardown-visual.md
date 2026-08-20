# 11 — Teardown visual medido dos widgets concorrentes

**Onda:** Repaginada total do front end do widget ChatSPX — fase de estudo
**Data das medições:** 11/08/2026 (todas as medidas foram colhidas neste dia; widgets em produção mudam)
**Método:** Chromium headless via Playwright (`--no-sandbox --disable-dev-shm-usage`), viewport desktop **1440×900** (DPR 1) e mobile **390×844** (DPR 2, `is_mobile`, `has_touch`, UA de iPhone 17.5), `locale=pt-BR`. Toda medida vem de `getBoundingClientRect()` + `getComputedStyle()` percorrendo o DOM principal, **shadow roots** e **todos os iframes** do widget.
**Scripts usados:** `wt_lib.py` (harness), `deep.py` (snapshot fechado/aberto), `focus.py` (subárvore), `probe.py` (launcher + hover), `palette.py` (extração de paleta) — mantidos no scratchpad da sessão, fora do repositório.

## Convenção de marcação

| Marca | Significado |
|---|---|
| **[MEDIDO]** | Número lido de `getComputedStyle`/`getBoundingClientRect` no browser, nesta sessão |
| **[FATO]** | Verificável em fonte citada (URL) ou no código-fonte deste repositório |
| **[INFERÊNCIA]** | Conclusão minha a partir de dados medidos — não é observação direta |
| **[NÃO VERIFICADO]** | Não consegui medir; declarado explicitamente |

> **Aviso de rigor.** Cada superfície foi medida separadamente. Onde só medi o launcher fechado, **não** afirmo nada sobre o painel aberto. Onde só medi desktop, **não** afirmo nada sobre mobile. Todas as lacunas estão marcadas como `[NÃO VERIFICADO]`.

---

## 0. Sumário de cobertura

| Widget | Site medido | Launcher | Teaser | Painel desktop | Mobile | Dark |
|---|---|---|---|---|---|---|
| Intercom | www.intercom.com | ✅ | ✅ | ✅ | parcial | ✅ **suporta** |
| Crisp | crisp.chat/en | ✅ | — | ✅ | ✅ | ✅ testado → **não suporta** |
| Tidio | www.tidio.com | ✅ | — | ✅ | ❌ | ✅ testado → **não suporta** |
| tawk.to | www.tawk.to | ✅ | ✅ | ✅ | ✅ | ❌ |
| JivoChat | www.jivochat.com.br | ✅ | ✅ | ✅ | ✅ | ❌ |
| Zendesk | support.zendesk.com/hc/pt-br | ✅ | — | ❌ | ❌ | ❌ |
| HubSpot | www.hubspot.com | ✅ | ✅ | ✅ | ❌ | ❌ |
| LiveChat | www.livechat.com | ✅ (card) | ✅ | ✅ | ❌ | ✅ testado → **não suporta** |
| Chatra | chatra.com | ✅ | — | ✅ | ❌ | ❌ |
| Leadster | www.leadster.com.br | ✅ | ✅ (é o próprio painel) | ✅ | ❌ | ❌ |
| Huggy (PowerZap) | www.huggy.io/pt-br | ✅ | ✅ | ✅ | ❌ | ❌ |
| Olark | www.olark.com | ✅ | ✅ | parcial | ❌ | ❌ |
| Octadesk | octadesk.com | ✅ (WhatsApp) | — | — | ❌ | ❌ |
| Salesloft/1Mind (ex-Drift) | www.salesloft.com | — | — | parcial | ❌ | ❌ |
| Smartsupp | www.smartsupp.com | ❌ bloqueado por consentimento | — | — | — | — |
| Freshchat | freshworks.com/live-chat-software | ❌ não renderizou | — | — | — | — |
| **ChatSPX (nosso)** | localhost (SDK + código) | ✅ | n/a | ✅ | ✅ (CSS) | parcial |

---

# PARTE A — Fichas técnicas

---

## A1. Intercom

**URL medida:** `https://www.intercom.com/` · Screenshots: `intercom-closed-desktop.png`, `intercom-open-desktop.png`, `intercom-launcher-desktop.png`, `intercom-launcher-hover-desktop.png`, `intercom-closed-desktop-dark.png`, `intercom-open-mobile.png`

**Arquitetura [MEDIDO]:** três iframes `about:blank` (srcdoc/blob) — `#intercom-frame` (1×1, invisível, host de estilo), `iframe.intercom-launcher-frame` (o botão) e um terceiro iframe sem id (o painel). Wrapper no DOM da página, conteúdo dentro dos iframes.

### A. Launcher (fechado)

| Propriedade | Valor [MEDIDO] |
|---|---|
| Wrapper (`div.intercom-with-namespace-4wz414`) | 48 × 48 px |
| `position` / offsets | `fixed`; `bottom: 20px`; `right: 20px` |
| `z-index` | `2147483000` |
| Forma | o wrapper tem `border-radius: 0px`; **o círculo é o iframe interno**: `iframe.intercom-launcher-frame` com `border-radius: 50%` |
| Fundo do botão (dentro do iframe) | `rgb(0, 0, 0)` — preto sólido (cor escolhida pela Intercom no próprio site) |
| `box-shadow` | **nenhuma** no wrapper nem no iframe (`none`) |
| Ícone | SVG próprio, **24 × 24 px**, centralizado (12px de folga em cada lado) |
| Ícone de fechar (estado aberto) | SVG **32,8 × 32,8 px** |
| Badge de não lidas | `span` **16 × 16 px**, `background: rgb(223, 32, 32)` (#DF2020), `color: rgb(250, 250, 250)`, texto `"1"`, ancorado no canto superior direito do wrapper (x=1413 num launcher que ocupa 1372→1420) |
| `transition` em repouso | `transform 0.167s cubic-bezier(0.33, 0, 0, 1)` |
| **Hover** | `transform: matrix(1.1, 0, 0, 1.1, 0, 0)` → caixa passa a **52,8 × 52,8 px**; a `transition` muda para `transform 0.25s cubic-bezier(0.33, 0, 0, 1)` |
| Halo ambiente | `div` **500 × 500 px** `fixed` em (940, 400) com `background-image: radial-gradient(at 100% 100%, rgba(29, 39, 54, 0.16) 0% …)` — uma sombra difusa gigante atrás do canto, separada do launcher |

O halo de 500×500 é a peça mais incomum: a Intercom não usa `box-shadow` no botão; usa um **gradiente radial de tela cheia atrás do canto inferior direito** para dar profundidade ao conjunto launcher+painel.

### C. Painel aberto (desktop)

| Elemento | Medida [MEDIDO] |
|---|---|
| Host (`div.intercom-with-namespace-vzjtt8`) | **400 × 704 px** em (1020, 112) → `right: 20px`, distância do topo 112px, distância do fundo 84px |
| `border-radius` | **24 px** (uniforme) |
| `box-shadow` | `rgba(9, 14, 21, 0.16) 0px 5px 40px 0px` |
| `transition` | `width .2s, height .2s, max-height .2s, transform .2s` |
| Header (`nav`) | **400 × 54 px**, `padding: 8px 13px` |
| — botão voltar | 38 × 38, `border-radius: 10px`, ícone 16 × 16, `transition: color .2s, background-color .2s, box-shadow .2s` |
| — avatar | **32 × 32**, `border-radius: 16.7%` (≈ 5,3px — quadrado arredondado, **não** círculo) |
| — nome (`h1`) | "Fin" · **14 px / 600** · `line-height: 15.4px` · `rgb(20, 22, 26)` |
| — subtítulo (`p`) | "The team can also help" · **12,68 px** · `line-height: 18,51px` · `rgb(108, 111, 116)` |
| — botão opções / fechar | 38 × 38 e **36 × 36**, `border-radius: 10px`, ícones 16 × 16; fechar com `transition: background-color .15s` |
| Corpo da conversa | 400 × 555 px (área rolável), `padding: 0 0 20px` |
| Composer (área) | 400 × 89 px |
| Rodapé | 400 × 30 px em y=674 — só `"Privacy Policy"` **12 px** `rgb(108, 111, 116)`. **Sem "Powered by Intercom"** |

**Balão do agente [MEDIDO]**

| Propriedade | Valor |
|---|---|
| Caixa | 312 × 96,8 px, começa em x=16 (16px da borda esquerda do painel) |
| `background-color` | `rgb(245, 245, 245)` (#F5F5F5) |
| `border-radius` | **20 px em todos os quatro cantos** (sem "rabinho", sem canto achatado) |
| `padding` | `12px 16px` |
| `max-width` | **280 px** = **70 % da largura do painel (400px)** |
| `margin-bottom` | 20 px |
| Texto | **14 px** · `line-height: 19,6px` (1,4) · `rgb(20, 22, 26)` |
| `transition` | `background-color .3s, border .3s, margin-bottom .3s` |
| Timestamp | "Fin • AI Agent • Just now" · `position: absolute` abaixo do balão · **12 px** · `line-height: 12px` · `letter-spacing: 0.072px` · `rgb(108, 111, 116)` |
| Avatar na mensagem | **[NÃO VERIFICADO]** — na conversa medida não havia avatar por mensagem, só no header |

**Composer [MEDIDO]**

- Contêiner 368 × 81 px em x=16 · `background: rgb(255,255,255)` · `border: 1px solid rgb(229, 229, 229)` · `border-radius: 16px` · `transition: outline-width .1s ease-in, border-color .1s ease-in`
- `textarea` 366 × 23 px · **14 px / lh 21px** · `padding: 0 8px 2px 16px` · placeholder `"Ask a question…"`
- Barra de ações 366 × 36 px, `padding: 4px 8px 0 12px`, `gap: 8px`: anexo, emoji, GIF e gravação — todos **24 × 24** com `opacity: 0.8` e `transition: opacity .2s`; ícones 16 × 16
- Botão enviar **32 × 32**, `border-radius: 32px`, estado desabilitado `background: rgba(9, 14, 21, 0.1)` e ícone `rgb(214, 214, 214)`

### D. Tipografia

Uma única stack em **100 % dos 111 elementos do painel** [MEDIDO]:
`system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji"`
Tamanhos observados: **16 px** (base, 70 ocorrências), **14 px** (20), **18 px** (15), **12 px** (3), **12,68 px** (1).

### E. Paleta [MEDIDO — extraída do painel]

| Cor | Uso |
|---|---|
| `#FFFFFF` | fundo do painel, do header e do composer |
| `#F5F5F5` | balão do agente |
| `#14161A` `rgb(20,22,26)` | texto primário (42 elementos) |
| `#6C6F74` `rgb(108,111,116)` | texto secundário, ícones, timestamp (32 elementos) |
| `#DF2020` `rgb(223,32,32)` | badge de não lidas |
| `rgba(9,14,21,0.1)` | botão enviar desabilitado |
| `#000000` | fundo do launcher |

### F. Mobile (390 × 844)

- Aparece um **teaser em iframe de 390 × 222 px em (0, 666)** — **largura total da tela**, ancorado no rodapé [MEDIDO].
- O painel aberto no mobile **[NÃO VERIFICADO]** — o clique automatizado não abriu.

### G. Dark mode — **o Intercom é o único da amostra que responde a `prefers-color-scheme: dark`** [MEDIDO]

| Elemento | Light | Dark |
|---|---|---|
| Balão do agente | `rgb(245, 245, 245)` | `rgb(43, 45, 49)` |
| Texto do balão | `rgb(20, 22, 26)` | `rgb(247, 247, 247)` |
| Composer (fundo) | `rgb(255, 255, 255)` | `rgb(20, 22, 26)` |
| Texto secundário / timestamp | `rgb(108, 111, 116)` | `rgb(160, 162, 166)` |
| Botão enviar (disabled) | `rgba(9, 14, 21, 0.1)` | `rgba(255, 255, 255, 0.1)` |

Note que as **classes CSS mudam** (`intercom-1e0b6bi` → `intercom-11dowma`): não é um `@media` sobre as mesmas classes, é um tema alternativo compilado — [INFERÊNCIA] o runtime escolhe o conjunto de classes conforme o esquema de cor.

---

## A2. Crisp

**URL medida:** `https://crisp.chat/en/` · Screenshots: `crisp-closed-desktop.png`, `crisp-open-desktop.png`, `crisp-launcher-desktop.png`, `crisp-open-mobile.png`, `crisp-closed-desktop-dark.png`

**Arquitetura [MEDIDO]:** **zero iframes**. Todo o widget vive no DOM da página (`div.crisp-client > #crisp-chatbox`), com classes ofuscadas prefixadas `cc-`.

### A. Launcher

| Propriedade | Valor [MEDIDO] |
|---|---|
| Caixa (`div.cc-13wro`) | **54 × 54 px** |
| Offsets | `fixed`; `bottom: 20px`; `right: 24px`; `z-index: 1000002` |
| `border-radius` | `100%` no wrapper e no círculo interno |
| Fundo | `rgb(25, 112, 240)` (#1970F0) — no `span.cc-2gk6o` interno, **não** no wrapper |
| `box-shadow` | `rgba(0, 0, 0, 0.05) 0px 4px 10px 0px` — também no span interno |
| Ícone | `span` com `background-image: url("data:image/svg+xml,…")`, **35 × 30 px** |
| `transition` | wrapper: `all`; círculo: `background-color .1s linear, outline .15s ease-in-out, transform …` |
| Hover | **sem delta medido** no wrapper (mesmo `rect`, mesmos estilos) |
| `role`/`aria` | `role="button"`, `aria-label="Open chat"`, `tabindex="0"`, `data-maximized="false"` |
| Badge | **[NÃO VERIFICADO]** — não havia não lidas na sessão |

### C. Painel aberto

| Elemento | Medida [MEDIDO] |
|---|---|
| Painel (`div.cc-w7v18`) | **400 × 730 px** em (1016, 80) → `top: 80px`, `right: 24px`, `bottom: 90px` |
| `border-radius` | **16 px** | 
| `box-shadow` | `rgba(0,0,0,0.02) 0px 10px 2px 0px, rgba(0,0,0,0.12) 0px 4px 20px 0px` (duas camadas) |
| `z-index` / `overflow` | `1000001` / `hidden` |
| `transition` | `width .15s ease-in-out, height .15s ease-in-out` |
| Header | 400 × 110 px, `padding: 10px 12px 16px` |
| — **segmented control** | 264 × 40 px, `border-radius: 20px`, `background: rgb(240,242,245)`, `padding: 4px` |
| — aba ativa | 109 × 32 px, `background: rgb(25,112,240)`, `box-shadow: rgba(255,255,255,0.45) 0 1px 2px inset, …`, texto 12 px "Crisp Noto Sans Bold" branco |
| — abas inativas | texto 12 px `rgb(28, 41, 59)` |
| — avatar do operador | SVG 36 × 36 |
| — título (`h2`) | "Questions? Chat with us." · **13 px / 700** · lh 18px · `letter-spacing: 0.2px` · `rgb(28, 41, 59)` |
| — subtítulo | **11,6 px** · `letter-spacing: 0.2px` · `rgb(102, 120, 138)` |
| Corpo | 400 × 508 px, `padding: 0 15px` |
| Composer | 380 × 85 px em (1026, 691) |
| Branding | link 118,8 × 16 px, **11 px**, `opacity: 0.75`, `transition: opacity .05s linear` |

**Balão do operador [MEDIDO]**

| Propriedade | Valor |
|---|---|
| `background` | `rgb(240, 242, 245)` (#F0F2F5) |
| `border-radius` | **12 px** uniforme |
| `padding` | `8px 14px 9px` (assimétrico no eixo vertical) |
| Texto | **12,6 px** · `line-height: 18px` · `rgb(28, 41, 59)` |
| Fonte | `"Crisp Noto Sans Regular", sans-serif` |
| Espaço entre balões | `margin-bottom: 22px` no wrapper `.cc-1grfa` |

**Sugestões / quick replies [MEDIDO]:** 34,2 px de altura, `border-radius: 12px`, fundo branco, `border: 1px solid rgb(211, 221, 230)`, `box-shadow: rgba(0,0,0,0.03) 0 2px 2px`, texto **12,2 px**, `padding: 10px 12px`, `transition: background-color .1s ease-in-out, transform .1s ease…`

**Composer [MEDIDO]:** contêiner 380 × 85, fundo branco, `padding: 0 6px 6px 13px`; **em foco** ganha `border: 1px solid rgb(25,112,240)` + anel `box-shadow: color(srgb 0.864706 0.915882 0.991176) 0px 0px 0px 3px`, `transition: border-color .1s ease-in-out, box-shadow .1s ease-in-out`. `textarea` 359 × 18 px · **13,6 px** · lh 18px · `letter-spacing: 0.15px` · placeholder `"Compose your message..."`. Botão enviar **36 × 36**, `border-radius: 13px` (≈ 36 %), `transition: background-color .05s linear`.

### D/E. Tipografia e paleta [MEDIDO]

Fonte proprietária: `"Crisp Noto Sans Regular"` (71 elementos) e `"Crisp Noto Sans Bold"` (5), com fallback `"Helvetica Neue", Helvetica, Arial`. Base do container é **11 px** (o Crisp escala tudo a partir de um `font-size` pequeno; os textos reais ficam entre 11,6 e 13,6 px).

Paleta: `#FFFFFF` (painel), `#F0F2F5` (balão + trilho do segmented), `#1C293B` (texto), `#66788A` (texto secundário), `#1970F0` (marca), `#055EE1` (variante pressionada), `#D3DDE6` (borda de sugestão).

Raios em uso: **16px** (painel), **12px** (balão e sugestões), **20px** (segmented), **13px** (botão enviar), **100%** (launcher).

### F. Mobile (390 × 844) [MEDIDO]

Painel vira **390 × 844 px em (0, 0)** — **fullscreen com `border-radius: 0`**.

### G. Dark [MEDIDO]

Com `color_scheme='dark'`, o painel continua `rgb(255,255,255)` → **não suporta**.

---

## A3. Tidio

**URL medida:** `https://www.tidio.com/` · Screenshots: `tidio-closed-desktop.png`, `tidio-open-desktop.png`, `tidio-open-chat.png`, `tidio-t05-desktop.png`

**Arquitetura [MEDIDO]:** **Shadow DOM**. Tudo vive no `shadowRoot` de `div#tidio-chat.needsclick` — nenhum iframe. (Consequência prática: CSS da página hospedeira não vaza para dentro, e ferramentas que só varrem `document.querySelectorAll` não enxergam o widget.)

### A. Launcher

| Propriedade | Valor [MEDIDO] |
|---|---|
| Caixa (`div#button`) | **56 × 56 px** em (1360, 792) → `right: 24px`, `bottom: 52px` |
| Botão (`button#button-body`) | 56 × 56, `border-radius: 28px` (= 50 %) |
| Fundo | `rgb(5, 102, 255)` (#0566FF) |
| `box-shadow` | `rgba(8, 15, 26, 0.08) 0px 2px 8px 0px, rgba(8, 15, 26, 0.12) 0px 2px 2px 0px` (duas camadas: uma difusa, uma de contato) |
| `transition` | `0.15s cubic-bezier(0.4, 0, 0.2, 1)` |
| Ícone fechado (`#ic_bubble`) | SVG **24 × 24 px** branco |
| Ícone aberto (`#ic_close`) | SVG **28 × 28 px** branco |
| Hover | escala para **61,6 × 61,6 px** = **1,1×** [MEDIDO com cursor sobre o botão] |
| Wrapper de layout | `div#tidio-chat-root` 112 × 824 px, `margin-top: 24px`, `margin-bottom: 52px`, `gap: 12px`, `max-width: 372px` |

### C. Painel aberto

Dois estados distintos — **medi os dois**:

| | Estado "home" | Estado "chat" |
|---|---|---|
| Painel (`div.chat`) | **372 × 589 px** | **372 × 700 px** |
| Posição | (1044, 191) → `right: 24px` | idem |
| `border-radius` | **12 px** | 12 px |
| `box-shadow` | `rgba(0, 18, 46, 0.16) 0px 8px 18px 0px` | idem |
| `transition` | `height 0.2s ease-in-out` | idem |

**Header [MEDIDO]:** **372 × 284 px** — mais de um terço da altura do painel. `background: rgb(5, 102, 255)` com uma imagem sobreposta em `opacity: 0.16` (`div.tidio-107vpyd`, S3 da Tidio). `padding: 20px`.
- Avatar 32 × 32, `border-radius: **4px**` (quadrado arredondado) sobre `rgb(5,102,255)`.
- Título `h2` **24 px / 700**, `line-height: 31px`, branco.
- Texto de apoio `line-height: 20px`, branco: *"AI chat powered by our team - how can we help you?"*
- Botão de opções 28 × 28, ícone 20 × 20, `transition: .16s ease-in-out`.

**Lista de ações (home) [MEDIDO]:** cartão contêiner 332 × 148, `border-radius: 12px`, `border: 1px solid rgb(226, 232, 239)`; itens 330 × 48, `padding: 14px 16px`, `gap: 8px`, rótulo **14 px / 500** `rgb(6, 19, 43)`, chevron 20 × 20.
Cartão destacado "Chat with Lyro": 332 × 72, `border-radius: 12px`, título 14 px/500, subtítulo **12 px** `rgb(76, 89, 107)`.

**Abas inferiores [MEDIDO]:** 372 × 67, dois botões 144 × 42, ícones 24 × 24, rótulo **12 px / 500**; ativo `rgb(8,15,26)`, inativo `rgb(100, 116, 145)`.

**Composer (estado chat) [MEDIDO]:** `textarea#new-message-textarea` 296 × 52 px, **14 px / lh 20px**, `padding: 16px 0`. Botão enviar 24 × 24 com ícone 20 × 20 em `rgba(100, 116, 145, 0.5)` (desabilitado). Emoji 24 × 24. Contador/tooltip 12 px lh 18.

**Branding [MEDIDO]:** `a` "Powered by Tidio." 171 × 24, SVG do logo, **font-size 10 px**, cor `rgb(136, 148, 171)`.

### D. Tipografia

Fonte proprietária **`TidioInter, sans-serif`** em toda a árvore [MEDIDO]. Escala: 24 (título), 14 (corpo/itens), 12 (secundário/abas), 10 (branding).

### E. Paleta [MEDIDO]

`#0566FF` (marca, header e launcher) · `#FFFFFF` (painel/cartões) · `#080F1A` `rgb(8,15,26)` (texto forte) · `#06132B` (rótulos) · `#4C596B` (secundário) · `#647491` (ícones inativos) · `#8894AB` (branding) · `#E2E8EF` (bordas).

### F/G

- **Mobile:** launcher detectado em 44,8 × 44,8 px (= 56 × 0,8) [MEDIDO], mas **o painel não abriu no teste automatizado** → **[NÃO VERIFICADO]**.
- **Dark:** painel continua `rgb(255,255,255)` → **não suporta** [MEDIDO].

---

## A4. tawk.to

**URL medida:** `https://www.tawk.to/` · Screenshots: `tawkto-closed-desktop.png`, `tawkto-open-desktop.png`, `tawkto-open-mobile.png`

**Arquitetura [MEDIDO]:** **três iframes independentes** — launcher (64 × 60), painel (`srcdoc`, 400 × 700) e **um iframe só para o rodapé de branding** (400 × 45). É o único da amostra que isola o "Powered by" num iframe próprio.

### A. Launcher

| Propriedade | Valor [MEDIDO] |
|---|---|
| iframe host | **64 × 60 px** em (1356, 820) → iframe a `right: 20px`, `bottom: 20px`, `z-index: 1000003`. O **botão** de 60 × 60 fica em (1356, 820)→(1416, 880) dentro dele, ou seja **24 px** da borda direita e 20 px da base; os 4 px extras de largura do iframe existem para o badge transbordar |
| Botão interno | **60 × 60 px**, `border-radius: 100%` |
| Fundo | `rgb(5, 168, 78)` (#05A84E) |
| `box-shadow` | `rgba(130, 130, 130, 0.08) 0px 4px 4px 0px` — sombra bem discreta |
| Ícone | SVG **32 × 32 px** branco (`.tawk-min-chat-icon`) |
| **Badge** | `span.tawk-badge` **20 × 20 px**, `border-radius: 50%`, `background: rgb(191, 18, 18)` (#BF1212), texto branco **10,99 px / lh 20px**, ancorado em (40, 0) do iframe → canto superior direito, transbordando o círculo |

### C. Painel aberto

| Elemento | Medida [MEDIDO] |
|---|---|
| iframe | **400 × 700 px** em (1020, 102) → `right: 20px`, `bottom: 98px`; `border-radius: 18px` |
| `box-shadow` (no iframe) | `rgba(0,0,0,0.08) 10px 10px 40px 0px, rgba(26,26,26,0.12) 5px 14px …` — sombra **deslocada para a direita e para baixo**, incomum |
| Contêiner interno | 400 × 700, `border-radius: 18px` |
| Header | **400 × 62 px**, `background: rgb(5, 168, 78)`, `border-radius: 18px 18px 0 0` |
| — nome | "Apollo" **20 px / lh 24px** branco |
| — botões | 32 × 30, `border-radius: 8px` |
| Avatar na mensagem | **40 × 40**, `border-radius: 15px` (quadrado arredondado, não círculo), fundo `rgb(239,239,239)` |
| Nome do agente acima do balão | **12 px** · lh 19,42px · `rgb(84, 84, 84)` · `margin-top: 4px, margin-bottom: 1px` |
| Grupo de mensagem | 320 px de largura (= 80 % de 400), deslocado 60 px da esquerda (avatar 40 + gap 20) |

**Balão do agente [MEDIDO]:** 260,8 px de largura máxima observada · `background: rgb(229, 229, 229)` · `color: rgb(49, 49, 49)` · **`border-radius: 8px` uniforme** · `padding: 12px` · **14 px / lh 22,65px** (1,62).

**Botões de resposta rápida [MEDIDO]:** 35,6 px de altura, `border-radius: 8px`, fundo branco, `border: 1px solid rgb(5,168,78)`, texto **14 px / lh 24px** na cor da marca, `padding: 4.8px 16px`, `box-shadow: rgba(130,130,130,0.08) 0 4px 4px`.

**Composer [MEDIDO]:** `textarea.tawk-chatinput-editor` **12,99 px**, placeholder `"Type and press [enter].."`, `padding-right: 88px` para caber os botões. Botões 28,8 × 22 e 30,8 × 22, `border-radius: 10px`, ícones de nota +1/−1 em `rgb(3,168,78)` e `rgb(191,18,18)`.

**Rodapé (iframe separado) [MEDIDO]:** pill **161 × 30 px** centralizado, `border-radius: 100px`, fundo branco, `border: 1px solid rgb(246,246,246)`, `box-shadow: rgba(0,0,0,0.04) 0px 6px 12px 0px`, `padding: 6px 14px`, texto **12 px** `rgb(79, 79, 79)`, logo SVG 107 × 15.

### D/E

Fonte **Lato** (proprietária carregada pelo widget) em toda a árvore [MEDIDO]. Paleta: `#05A84E` (marca) · `#E5E5E5` (balão) · `#313131` (texto do balão) · `#545454` (nome do agente) · `#BF1212` (badge/negativo) · `#EFEFEF` (fundo do avatar) · `#4F4F4F` (branding).

### F. Mobile (390 × 844) [MEDIDO]

Painel vira **390 × 844 px em (0, 0)** — **fullscreen**.

---

## A5. JivoChat

**URL medida:** `https://www.jivochat.com.br/` · Screenshots: `jivochat-closed-desktop.png`, `jivochat-open-desktop.png`, `jivochat-open-mobile.png`

**Arquitetura [MEDIDO]:** elementos customizados `<jdiv>` no DOM da página, sem iframe. Classes com hash CSS-modules.

### A. Launcher — **não é uma bolha**

No desktop o estado fechado é uma **etiqueta horizontal colada na base** [MEDIDO]:

| Propriedade | Valor |
|---|---|
| `jdiv#jvLabelWrap` | **301,42 × 40 px** em (1098,58; 860) → **`bottom: 0`** (encostada na borda inferior) |
| `border-radius` | **`8px 34px 0px 0px`** — assimétrico, canto superior direito muito maior |
| Fundo | `linear-gradient(95deg, rgb(47, 50, 74) 20%, …)` |
| `box-shadow` | `rgba(0, 0, 0, 0.17) 0px 12px 14px 8px` |
| Conteúdo | ícone 20 × 40 (SVG data-URI) + texto 186,42 × 16 + logo 27 × 18 + "folha" decorativa 33 × 33 com `border-radius: 0 24px 0 0` |
| `z-index` | `2147483647` (máximo) |
| Variante bolha | no **mobile** o launcher medido é um `jdiv` **65 × 65 px** [MEDIDO] — formato diferente do desktop |

### C. Painel aberto

| Elemento | Medida [MEDIDO] |
|---|---|
| Painel (`jdiv.main__PcyDs`) | **336 × 496 px** em (1074, 404) → `right: 30px`, **`bottom: 0`** |
| `border-radius` | **`10px 33px 0px 0px`** — o painel repete a assinatura assimétrica do launcher |
| `box-shadow` | `rgba(0, 0, 0, 0.25) 0px 20px 40px 8px` — a sombra mais pesada da amostra |
| Header | **336 × 70 px**, `linear-gradient(95deg, rgb(47,50,74) 20%, rgb(66,72,…))` + `background-image` de padrão (PNG do CDN), `border-radius: 8px 33px 0 0` |
| — nome | "Envie-nos uma mensagem" **15 px / lh 18px** `rgb(240, 241, 241)` |
| Corpo | 336 × 426, contêiner com `padding: 40px 0 10px` |
| Composer | **336 × 110 px** |

**Balão do agente [MEDIDO]:** `background: rgb(240, 243, 244)` · `color: rgb(34, 45, 56)` · **`border-radius: 12px`** · `padding: 12px 16px` · **15 px / lh 19,6px** · `margin-bottom: 2px` · largura 252,8 px = **75 % do painel** · `aria-label` com o timestamp completo (`11/08/2026 21:37:29`). Links internos em `rgb(54, 127, 238)`.

**Composer [MEDIDO]:** `textarea` 336 × 60 px, **15 px / lh 20px**, `padding: 18px 58px 0 16px`, placeholder `"Digite aqui"`. Botão enviar **34 × 34**, `border-radius: 100%`, `background: rgb(241, 240, 240)` no estado desabilitado, ícone via `background-image` SVG. Ícones de menu e emoji 24 × 24 numa barra 120 × 24.

**Botão "ir para o fim" [MEDIDO]:** 35 × 35, `border-radius: 36px`, fundo branco, `border: 1px solid rgb(224,229,233)`, `box-shadow: rgba(0,0,0,0.2) 0 2px 10px`, `opacity: 0.5`, `transition: bottom .15s, opacity .15s`.

**Branding [MEDIDO]:** faixa 336 × 30 px **no topo do corpo** (não no rodapé), texto "Chat desenvolvido por" **13 px / lh 30px** `rgb(149, 157, 165)` + logo 27 × 18.

### D/E

Fonte: `Arial, system-ui, -apple-system, Arial, sans-serif` [MEDIDO] — **o único da amostra que ainda ancora em Arial**. Paleta: `#2F324A`→`#42484…` (gradiente do header) · `#F0F3F4` (balão) · `#222D38` (texto) · `#367FEE` (links) · `#959DA5` (branding) · `#F1F0F0` (botão enviar desabilitado).

### F. Mobile (390 × 844) [MEDIDO]

`jdiv.main__p4v3r` **390 × 844** com `background: rgba(0, 0, 0, 0.4)` → **fullscreen com camada de escurecimento** por trás.

---

## A6. HubSpot

**URL medida:** `https://www.hubspot.com/` · Screenshots: `hubspot-closed-desktop.png`, `hubspot-open-desktop.png`

**Arquitetura [MEDIDO]:** um iframe `#hubspot-conversations-iframe` (448 × 634) que contém **launcher e painel juntos**; o iframe é maior que o painel para acomodar a sombra e o botão.

### A. Launcher

| Propriedade | Valor [MEDIDO] |
|---|---|
| Caixa base | **60 × 60 px** |
| `border-radius` | **50 %** |
| Fundo | `rgb(31, 31, 31)` (#1F1F1F) — quase preto |
| `box-shadow` | `rgba(0,0,0,0.1) 0px 2px 6px 0px, rgba(0,0,0,0.2) 0px 4px 16px 0px` |
| `transition` | `transform 0.1s ease-in-out` |
| Hover | caixa passa a **66 × 66 px** = **1,1×** [MEDIDO] |
| Estado fechado (antes de abrir) | contêiner `#hubspot-messages-iframe-container` 282 × 277 px — [INFERÊNCIA] o retângulo maior existe porque um teaser proativo estava sendo exibido |

### C. Painel aberto

| Elemento | Medida [MEDIDO] |
|---|---|
| Painel real | **416 × 530 px**, offset 16 px dentro do iframe → na página: `right: 16px`, `bottom: 88px` |
| `border-radius` | **10 px** |
| `box-shadow` | `rgba(0, 0, 0, 0.1) 0px 4px 16px 0px` |
| `transition` | `0.25s ease-in-out` |
| Header | **416 × 72 px**, `background: rgb(31, 31, 31)`, `border-radius: 8px 8px 0 0` |
| — avatar | **36 × 36**, `border-radius: 50%`, `padding: 2px` com fundo branco (anel), imagem interna 32 × 32 |
| — nome | "HubBot" · **font-weight 700 / lh 20px** · branco |
| — subtítulo | "Powered by AI" · **11 px** · branco |
| — botões (expandir / fechar) | **40 × 40**, `border-radius: 3px`, ícones 20 × 20, `transition: background-color .15s ease-out` |
| Corpo | 416 × 458 px, lista com `padding: 8px 0` |
| Composer (área) | 416 × 71 px |
| Handle de redimensionar | `div` 416 × 8 px no topo, `aria-label="Resize widget height"` — **o único da amostra com painel redimensionável pelo visitante** |

**Balão do agente [MEDIDO]:** `background: rgb(245, 243, 242)` (#F5F3F2, um cinza quente) · **`border-radius: 10px`** · `padding: 8px 16px` · **`max-width: max(100% - 48px, 284px)`** · texto **14 px / lh 24px** (1,71 — a maior entrelinha da amostra) · `color: rgb(20, 20, 20)`. Avatar por mensagem **32 × 32**.

**Quick replies [MEDIDO]:** 34 px de altura, `border-radius: 10px`, fundo branco, `border: 1px solid rgb(103, 101, 101)`, texto **12 px / 600 / lh 18px**, `padding: 7px 10px`, `max-width: 384px`, `transition: color .2s, border-color .2s, opacity .2s`, `gap: 8px`.

**Composer [MEDIDO]:** 384 × 42 px, **`border-radius: 28px` (pill)**, `border: 1px solid rgb(103,101,101)`, `padding: 0 8px`; input 282 × 38, **14 px / lh 22px**, placeholder `"Ask me anything…"`; botões anexo e enviar **40 × 40**, `border-radius: 50%`, ícone em `rgb(155, 152, 151)`.

**Disclaimer de IA [MEDIDO]:** faixa 416 × 24 px, texto *"AI-generated content may be inaccurate."* **12,6 px / lh 24px**, `transition: opacity 1s ease-in`.

**Aviso de consentimento [MEDIDO]:** bloco 416 × 98 px, `background: rgb(245,243,242)`, `padding: 12px 28px`, texto **12 px / lh 24px** `rgb(66, 91, 118)` com link para a política; botão de dispensar 28 × 28 `border-radius: 50%`.

### D/E

Fonte proprietária **`"Lexend Deca", sans-serif`** [MEDIDO], base **14 px / lh 24px**. Paleta: `#1F1F1F` (marca escura: launcher + header) · `#F5F3F2` (balão e avisos) · `#141414` (texto) · `#33475B` (texto de botão) · `#425B76` (aviso) · `#676565` (bordas) · `#9B9897` (ícones).

---

## A7. LiveChat

**URL medida:** `https://www.livechat.com/` · Screenshots: `livechat2-closed-desktop.png`, `livechat2-open-desktop.png`, `livechat2-closed-desktop-dark.png`

**Arquitetura [MEDIDO]:** dois iframes — `#chat-widget-minimized` (320 × 299) e `#chat-widget` (420 × 800). O estado "fechado" **não é uma bolha**.

### A/B. Estado minimizado — um cartão completo, não um launcher

| Elemento | Medida [MEDIDO] |
|---|---|
| iframe minimizado | **320 × 299 px** em (1120, 601) |
| Pill de saudação | **141,2 × 30,4 px**, `border-radius: 40px`, fundo branco, `padding: 8px 30px 8px 8px`, `gap: 12px`, avatar 24 × 24 `border-radius: 50%`, texto "Text AI Support" |
| Botão dispensar saudação | 24 × 24, `border-radius: 12px`, `background: rgb(240,240,240)`, ícone 20 × 20 `rgb(110,110,110)`, `transition: transform .25s cubic-bezier(0.14, 0, 0, 1)` |
| Cartão | **296 × 236,6 px**, `border-radius: **26 px**`, fundo branco, `border: 1px solid rgb(227,227,227)`, `padding: 4px`, `transition: border-color .3s cubic-bezier(0.33,0,0.67,1)` |
| Sombra (pill e cartão) | `rgba(0,0,0,0.125) 0px 0.362176px 0.941657px -1px, …` — **sombra em escada com valores fracionários** (perfil físico) |
| Balão de boas-vindas | `background: rgb(240,240,240)`, `border-radius: **22px 22px 6px 6px**`, `padding: 12px`, texto `rgb(107,107,107)` |
| Botões CTA | 27,6 px de altura, `border-radius: 12px`; primário `rgb(217, 51, 17)`, secundário `rgb(27, 27, 32)`; texto **14 px / 700 / lh 19,6px** branco; `transition: background-color .3s cubic-bezier(0.33,0,0.67,1)` |
| Input inline | 286 × 60 px, `border-radius: **30px**`, **14 px**, `padding: 1px 54px 1px 13px`, placeholder `"Write a message…"`; botão enviar **40 × 40** `border-radius: 50%` `background: rgb(227,227,227)`, ícone 32 × 32 |

### C. Painel expandido

| Elemento | Medida [MEDIDO] |
|---|---|
| iframe | **420 × 800 px** em (1020, 100) |
| Painel real | **388 × 768 px** (16 px de folga para a sombra) → na página `right: 20px`, `bottom: 16px` |
| `border-radius` | **24 px** |
| `background` | `rgb(246, 246, 247)` — **fundo cinza, não branco** |
| `box-shadow` | `rgba(0,0,0,0.08) 0px 0.48px 2.41px -0.38px, rgba(0,0,0,0.25) 0px 4px 20px -0.75px` |
| Barra superior | 388 × 76 px com **`backdrop-filter: blur(8px)`** — barra translúcida sobre o conteúdo |
| **Header flutuante** | `#agent-bar` **194 × 60 px**, `border-radius: 24px`, fundo branco, sombra própria, `padding: 12px`, **centralizado e sobreposto** ao conteúdo (não é uma faixa de largura total) |
| — avatar | 36 × 36, `border-radius: 50%`, `border: 1px solid rgb(227,227,227)` |
| — nome | **13 px / 700**; status **13 px** `opacity: 0.7` |
| Botões de janela | **28 × 28**, `border-radius: 50%`, `background: rgb(221, 221, 221)`, `transition: transform .25s cubic-bezier(0.14, 0, 0, 1)` |
| Lista de mensagens | 388 × 641 px, `padding: 20px` |
| Avatar por mensagem | **20 × 20**, `border-radius: 50%` |

**Balão do agente [MEDIDO] — dois níveis:**
- Casca externa `background: rgb(255,255,255)`, `border-radius: 24px`, `padding: 4px`, `max-width: 296px` (= 76 % de 388)
- Balão interno `background: rgb(240, 240, 240)`, **`border-radius: 22px 22px 6px 6px`**, `padding: 12px`, **16 px / lh 21,6px**, texto `rgb(107,107,107)`
- `transition: margin-bottom .2s cubic-bezier(0.14,0,0,1) 0.3s` (com atraso de 300 ms)

### D/E/G

Fonte: stack de sistema `system-ui, "Segoe UI", Roboto, Helvetica, Arial` [MEDIDO]. Paleta: `#F6F6F7` (painel) · `#FFFFFF` (cartões/casca) · `#F0F0F0` (balão) · `#6B6B6B` (texto) · `#111111` (título) · `#DDDDDD` (botões) · `#E3E3E3` (bordas) · `#D93311` (CTA primário) · `#1B1B20` (CTA secundário).
**Dark:** painel continua `rgb(246,246,247)` → **não suporta** [MEDIDO].

---

## A8. Chatra

**URL medida:** `https://chatra.com/` (redireciona para `chatra.com.br`) · Screenshots: `chatra-closed-desktop.png`, `chatra-open-desktop.png`

### A. Launcher [MEDIDO]

| Propriedade | Valor |
|---|---|
| `div#chatra` | **60 × 60 px** em (1360, 820) → `right: 20px`, `bottom: 20px`, `z-index: 9999` |
| Wrapper `#chatra__iframe-wrapper` | `border-radius: 50%`, `max-width: 100%` |
| `box-shadow` | `rgba(0,0,0,0.1) 0px 0px 3px 0px, rgba(0,0,0,0.3) 0px 0px 10px 0px` — **duas camadas sem deslocamento vertical** (halo, não sombra projetada) |
| `transition` | `box-shadow 0.2s linear` no wrapper; `visibility .2s linear, opacity .2s linear` no host |
| Conteúdo | `iframe#chatra__iframe` 60 × 60 |
| Fonte do host | `Cera, "Helvetica Neue", Arial, sans-serif` |

### C. Painel aberto [MEDIDO]

| Elemento | Medida |
|---|---|
| iframe | **450 × 600 px** em (970, 280) → `right: 20px`, `bottom: 20px` |
| `container__inner` | 450 × 600, **`border-radius: 0px`** — **o único painel totalmente quadrado da amostra** |
| `box-shadow` | `rgba(0, 0, 0, 0.3) 0px 0px 10px 0px` (halo) |
| Header | **450 × 49 px**, `padding: 4.5px 0`; texto de boas-vindas **15 px / lh 40px**; botão fechar 47 × 40 `opacity: 0.6` |
| Bloco de rostos | 3 avatares **64 × 64** `border-radius: 50%`, nomes **11,61 px / lh 15,09px** |
| Linha de status | "Conectado 2 horas atrás" **13,5 px / lh 20,25px** `rgba(0, 0, 0, 0.4)` |
| Mensagem de boas-vindas | **15 px / lh 22,5px**, `padding: 22.5px 15px` |
| Composer | **450 × 56 px**, fundo branco, `box-shadow: rgba(0,0,0,0.1) 0 0 1px, rgba(0,0,0,0.2) …`, `padding: 4.5px 15px`, `transition: transform .2s ease-out 0.05s` |
| — `textarea` | 366 × 47, **15 px / lh 22,5px**, `padding: 12px 7.5px`, placeholder `"Mensagem..."` |
| — botões emoji / anexo | 27 × 27, cores `rgb(190,190,195)` e `rgb(4, 121, 245)` |

**Tipografia [MEDIDO]:** `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, …` com base **15 px / lh 22,5px** (razão exata de 1,5). Todos os tamanhos derivam dessa base por múltiplos de 0,9 e 0,774 (13,5 px e 11,61 px) — [INFERÊNCIA] escala tipográfica proporcional, não valores absolutos.

**Balão do visitante [NÃO VERIFICADO]** — não enviei mensagem para não abrir atendimento real.

---

## A9. Zendesk

**URL medida:** `https://support.zendesk.com/hc/pt-br` (a home `zendesk.com.br` **não** carrega o Web Widget — verifiquei: nenhuma referência a `zdassets.com/ekr/snippet.js` no HTML servido; o botão preto de lá é um componente da própria página) · Screenshot: `zendesk-closed-zdweb.png`

### A. Launcher [MEDIDO]

| Propriedade | Valor |
|---|---|
| `iframe#launcher` | **64 × 64 px** em (1360, 820) → `right: 16px`, `bottom: 16px` |
| Botão interno | 64 × 64, `border-radius: 50%`, `border: 2px solid rgb(17, 17, 13)` |
| Fundo | `rgb(17, 17, 13)` (#11110D) — preto levemente esverdeado |
| `box-shadow` | `rgba(36, 36, 36, 0.15) 0px 20px 30px 0px` — **deslocamento vertical de 20 px**, o maior da amostra |
| Ícone | SVG **36 × 36 px**, cor `rgb(92, 105, 112)` |
| **Animação de troca de ícone** | dois ícones empilhados em contêineres 60 × 60 posicionados em `top: 2px` e `top: 62px`, com `transition: top 0.5s cubic-bezier(0.66, 0, 0.12, 1)` → **o ícone desliza verticalmente** ao abrir/fechar, em vez de fazer fade ou rotação |
| `transition` do botão | `border-color .25s ease-in-out, box-shadow .1s ease-in-out` |
| `aria-label` | `"Abrir janela de mensagens"` (localizado em pt-BR) |
| Fonte | `system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI"…` |

**Painel aberto: [NÃO VERIFICADO]** — o clique programático no iframe do launcher não abriu o `webWidget` em nenhuma das três tentativas (esperas de 10 s, 14 s e 16 s após o clique). Não afirmo nada sobre o painel do Zendesk.

---

## A10. Leadster

**URL medida:** `https://www.leadster.com.br/` (widget injetado via GTM; aparece em ~2–4 s e **abre sozinho**) · Screenshots: `leadster-open-desktop.png`, `leadster-focus-before-desktop.png`, `leadster-fechado-focus-after-desktop.png`

**Arquitetura [MEDIDO]:** DOM da página, classes com prefixo `nld-` (herança do nome antigo *Neurolead*), sem iframe e sem shadow DOM.

### A. Launcher (estado fechado, medido após fechar o painel) [MEDIDO]

| Propriedade | Valor |
|---|---|
| `div.nld-avatar` | **60 × 60 px** em (1362, 816) → `right: 18px`, `bottom: 24px` |
| `border-radius` | **30 px** (círculo perfeito) |
| Fundo | `rgb(23, 113, 240)` (#1771F0) **+ `background-image`: a foto da atendente** (`storage.googleapis.com/neuro-cdn/...`) |
| `box-shadow` | `rgba(0, 0, 0, 0.15) 0px 0px 12px 0px` (halo, sem deslocamento) |
| Ícone | **não há ícone** — o launcher é o **rosto de uma pessoa** |

Esse é o desvio mais radical da amostra: **9 dos 13 launchers medidos são um ícone de balão dentro de um círculo colorido; o da Leadster é uma fotografia humana.**

### C. Painel (abre proativamente, sem clique)

| Elemento | Medida [MEDIDO] |
|---|---|
| `div.nld-conversation` | **420 × 370 px** em (996, 482) → `right: 24px`, `bottom: 48px`, `z-index: 32767` |
| `border-radius` | **12 px** |
| `box-shadow` | `rgba(0, 0, 0, 0.15) 0px 0px 24px 0px` (halo simétrico) |
| Header | **420 × 100 px**, `background: rgb(23, 113, 240)`, `border-radius: 8px 8px 0 0` |
| — avatar | **50 × 50**, `border-radius: 25px`, foto |
| — título | "Ana - Leadster", branco, fonte `"Open Sans Regular"` |
| — subtítulo | "Online agora" **12 px** branco |
| — botão fechar | 25 × 25, imagem PNG branca (não SVG) |
| Corpo | 420 × 298 px, `padding-right: 50px` no scroller |
| Máscara de topo | `div.nld-overlay` 420 × 36 px com `linear-gradient(rgb(255,255,255), rgba(255,255,255,0))` — **desvanece o texto que sobe** |
| **Composer** | **não existe no estado inicial** — só um botão de CTA |
| Branding | pill **187,7 × 22 px** *abaixo* do painel, `background: rgb(238,238,238)`, `border-radius: 0 0 6px 6px`, `border: 1px solid rgb(221,221,221)`, **13 px**, "Feito com **Leadster**" (`font-weight: 700`) + logo 22 × 16, cor `rgb(102, 114, 124)` |

**Balão do agente [MEDIDO]:** `background: rgb(238, 238, 238)` (#EEEEEE) · **`border-radius: 24 px` uniforme** · `padding: 16px 24px` (o mais generoso da amostra) · **14,4 px / lh 21,6px** (1,5) · `color: rgb(0,0,0)` · grupo com `max-width: 80%`, contêiner interno `max-width: calc(100% - 40px)` · avatar por mensagem **32 × 32** · `margin-bottom: 6px`.

**CTA dentro do balão [MEDIDO]:** `button` 194,6 × 45,6 px, `background: rgb(23,113,240)`, **`border-radius: 24px`**, `box-shadow: rgba(0,0,0,0.15) 0px 3px 6px 0px`, texto **14,4 px** branco, `padding: 12px 16px`, ícone de seta 16 × 16, `margin-bottom: 7px`.
**Microcopy legal [MEDIDO]:** **10,8 px / lh 16,2px**, `max-width: 80%`, link em `rgb(0, 119, 204)`.

**Tipografia [MEDIDO] — duas famílias no mesmo widget:** `"Plus Jakarta Sans", sans-serif` no contêiner e `"Open Sans Regular", sans-serif` em todo o conteúdo da conversa. A escala de 14,4 / 21,6 / 10,8 / 16,2 px indica [INFERÊNCIA] um `font-size` base de 90 % (16 × 0,9 = 14,4).

---

## A11. Huggy (widget "PowerZap")

**URL medida:** `https://www.huggy.io/pt-br` · Screenshots: `huggy-closed-desktop.png`, `huggy-open-desktop.png`

**Arquitetura [MEDIDO]:** três iframes — botão (100 × 75), painel (370 × 564) e *smart trigger* (350 × 141). Classes com prefixo `powerzap_`.

### A. Launcher [MEDIDO]

| Propriedade | Valor |
|---|---|
| iframe host | **100 × 75 px** em (1340, 825) |
| Botão `#buttonOpen` | **65 × 65 px** |
| `border-radius` | **35 %** (≈ 22,75 px) — **não é círculo nem pill: é um "squircle"** |
| Fundo | `rgb(129, 22, 215)` (#8116D7) |
| `box-shadow` | `rgba(0, 0, 0, 0.23) 0px 3px 12px 0px, rgba(0, 0, 0, …)` |
| Ícone | **icon font** (`i.macke.macke-chat-filled`) **32 × 32 px** branco — o único da amostra que não usa SVG |
| `transition` | `0.3s cubic-bezier(0.25, 0.8, 0.25, 1)` |
| Offsets efetivos | botão em (1355, 825)→(1420, 890) → **`right: 20px`, `bottom: 10px`** — o mais colado à base entre as bolhas |

### B. Teaser [MEDIDO]

`iframe.powerzap_iframe_smarttrigger_message` **350 × 141 px** em (1082, 684) — fica **acima e à esquerda** do botão.

### C. Painel [MEDIDO]

| Elemento | Medida |
|---|---|
| iframe | **370 × 564 px** em (1046, 256) |
| Header | **370 × 64 px**, `background: rgb(129, 22, 215)` + `background-image` SVG de padrão, `border-radius: 6px 6px 0 0`, `box-shadow: rgba(0,0,0,0.2) 0px 1px 4px 0px` |
| — título | "Huggy - Atendimento Digital", branco, bloco de 19 px de altura, `transition: .3s cubic-bezier(0.25,0.8,0.25,1)` |
| Corpo | 370 × 500, `background: rgb(247, 247, 247)`, `border-radius: 0 0 2px 10px` (assimétrico) |
| Lista de balões | `padding: 0 15px`, item com `margin: 10px 0` |
| Avatar por mensagem | **32 × 32**, `border-radius: 50%` |
| Composer | **370 × 63 px**, fundo branco |

**Balão do agente [MEDIDO]:** `background: rgb(255,255,255)` · **`border-radius: 7px`** (o menor raio de balão da amostra) · `box-shadow: rgba(0,0,0,0.07) 0px 2px 23px 0px` — **o único balão da amostra com sombra própria** · `padding: 10px` · **`max-width: 85%`** · **14 px** · `color: rgb(52, 71, 76)`.

**Composer [MEDIDO]:** input `div#input.TextArea` 244,1 × 17, **14 px**, `color: rgb(86,86,86)`, **fonte Lato** (o resto do painel é Rubik); botão de opções 31,9 × 33 `border-radius: 6px`; emoji 26 × 29; enviar 40 × 39 — todos com `transition: .2s cubic-bezier(0.25,0.8,0.25,1)`.

**Tipografia [MEDIDO]:** `Rubik, "Apple Color Emoji", "Segoe UI Emoji"…` no painel; `Lato, sans-serif` no campo de entrada.

---

## A12. Olark

**URL medida:** `https://www.olark.com/` · Screenshot: `olark-closed-desktop.png`

**Achado de arquitetura [MEDIDO]:** o site do Olark hoje serve o chat através de um **custom element `<olark-experience>` com Shadow DOM**, e o painel de conversa é **`<openai-chatkit>`** — um iframe apontando para `https://cdn.platform.openai.com/deployments/chatkit/index-*.html`. Ou seja, [FATO — medido no DOM] a olark.com está rodando o **ChatKit da OpenAI** dentro do shell do Olark.

### A. Launcher — **pill com rótulo, não bolha** [MEDIDO]

| Propriedade | Valor |
|---|---|
| `button#olark-show-button` | **183,7 × 52 px** em (1232,3; 824) |
| `border-radius` | **999 px** (pill) |
| Fundo | `rgb(91, 62, 142)` (#5B3E8E) — confirmado por amostragem de pixel no screenshot: (1240,850) = `(91,62,142)` |
| Borda | **`1px solid rgb(255,255,255)`** — contorno branco, o que dá o efeito de "pill outline" |
| `box-shadow` | `rgba(11, 31, 42, 0.25) 0px 10px 24px 0px` |
| Ícone | 32 × 32 (SVG `.olark-show-button-chat-bubble-icon`, path 27,7 × 24,7), branco |
| Rótulo | `span` **119,7 × 21 px**, **18 px** branco, `system-ui, sans-serif` — texto ao lado do ícone |
| Pilha | `div#olark-launcher-stack` **312 × 108 px** em (1104, 768) — agrupa teaser + botão |

### B. Teaser [MEDIDO]

`div#olark-agent-preview-wrap` **320 × 54 px** em (1100, 764), com botão de dispensar **9,8 × 9,8 px** (área de toque muito pequena — [INFERÊNCIA] abaixo do mínimo recomendado de 24 px do WCAG 2.2 *Target Size (Minimum)*).

### C. Painel

O shell `#olark-chatkit-shell.minimized` fica **fora da viewport** (17,53 px de largura em x=1440,44) no estado minimizado [MEDIDO]. O header do shell usa `background: rgb(91, 62, 142)`; o bloco de consentimento de privacidade usa `rgb(248, 250, 252)`. **Medidas do painel expandido: [NÃO VERIFICADO]** — o clique automatizado abriu o ChatKit em 398 × 766,8 px em (1041, 49) [MEDIDO], mas não consegui percorrer o conteúdo interno do iframe da OpenAI.

---

## A13. Octadesk

**URL medida:** `https://octadesk.com/` · Screenshot: `octadesk-closed-desktop.png`

[MEDIDO] A home da Octadesk **não expõe um widget de chat próprio**. O que existe no canto é o widget de WhatsApp deles:
- `button#clique_chatform_floater.octa-wa-floater` **60 × 60 px** em (1356, 816)
- `div#octaWaBox.octa-wa-box` **349,2 × 465,6 px** em (1061,4; 343,2), `z-index: 9999`
- Fonte do site: `Poppins, Arial, sans-serif`; a página adiciona a classe `octa-wa-open` ao `<body>` quando a caixa abre

[INFERÊNCIA] A Octadesk usa a própria caixa de WhatsApp como canal principal de entrada no site institucional — não o live chat.

---

## A14. Drift → Salesloft / 1Mind

[FATO — medido] `https://www.drift.com/` redireciona para `https://www.salesloft.com/`.
[FATO — medido] A salesloft.com serve `div#onemind-widget` **366 × 644 px** em (1050, 232), `z-index: 2147483647`, contendo um iframe de `deployment-*.1mind.com` — um agente em vídeo, não um widget de chat clássico.
[FATO — fontes web] O Drift está em *sunset* anunciado em março de 2026 após a aquisição pela Salesloft; clientes estão sendo migrados. Fontes: [salespeak.ai](https://salespeak.ai/blog/drift-sunset-replacing-chat-widget-not-enough-2026/), [myaskai.com](https://myaskai.com/blog/drift-alternatives-2026), [marketbetter.ai](https://marketbetter.ai/blog/drift-review-2026/).

**Consequência para este estudo:** o "padrão Drift" (launcher + mensagem proativa de qualificação B2B) **não deve ser copiado de um produto morto**. O que sobrevive dele está no Qualified e no 1Mind.

---

## A15. Não medidos — declarados

- **Smartsupp** (`www.smartsupp.com`): o widget **não carrega** enquanto o banner de consentimento (Cookiebot / `#CookieBanner`) não é aceito. Tentei três seletores de aceite; nenhum funcionou no headless. **[NÃO VERIFICADO]**
- **Freshchat** (`www.freshworks.com/live-chat-software/`): a página carrega o iframe `my-*.freshchat.com/home/51281`, mas com caixa **0 × 0** — não renderizado. A superfície de chat visível naquela página é do **Qualified** (`div#qualified-multimodal-host`, shadow DOM). **[NÃO VERIFICADO]** para o Freshchat.

---

## A16. ChatSPX — o nosso

**Como foi medido:** subi uma página de teste no scratchpad (`http://localhost:8912/`, com `<meta name="viewport">`) carregando o SDK real de `http://localhost:3000/packs/js/sdk.js` com o `websiteToken` de uma inbox Web Widget desta VM de homologação. Medidas de runtime marcadas **[MEDIDO]**; medidas de folha de estilo marcadas **[FATO — código]** com o arquivo.
Screenshots: `chatspx-closed-desktop.png`, `chatspx-open-desktop.png`, `chatspx-open-conv.png`, `chatspx-closed-mobile.png`, `chatspx-open-mobile.png`.

> Nota operacional: pelo domínio público (`hmlchat.…`) o endpoint `/widget` devolveu **429** durante a sessão (rate limit do Rack::Attack acionado pelas minhas próprias reaberturas). A medição foi feita apontando o SDK para `localhost:3000`, que não é limitado. Isso **não** altera o CSS medido.

### A. Launcher

| Propriedade | Valor |
|---|---|
| `button.woot-widget-bubble` | **64 × 64 px** [MEDIDO em (1356, 816) desktop e (306, 760) mobile] |
| Offsets | `bottom: 20px`; `right: 20px`; `position: fixed`; `z-index: 2147483000` [FATO — `app/javascript/sdk/sdk.js`] |
| `border-radius` | **100 px** (círculo) |
| `background` | **medido em runtime: `rgb(0, 156, 224)` = `#009CE0`** — o `widget_color` da inbox sobrescreve o padrão. O valor `#2dc46f` (verde) é apenas o *default* embutido no CSS do SDK [FATO — `sdk.js`] |
| `box-shadow` | `0 8px 24px rgba(0, 0, 0, .16)` |
| Ícone | SVG **24 × 24 px** com `margin: 20px` |
| **Hover** | muda **só a sombra**: `0 8px 32px rgba(0, 0, 0, .4)`. **Não há escala, nem translação, nem mudança de cor** |
| Transição de entrada/saída | medida em runtime: `transform 0.3s, opacity 0.1s, visibility linear, bottom linear`; ao esconder: `translateX(8px) scale(.75) rotate(-30deg)` [FATO — código] |
| Badge de não lidas | pseudo-elemento `::after` **12 × 12 px**, `background: #ff4040`, `border: 2px solid #fff`, `border-radius: 100%`, ancorado em `top: 0; right: 0` |
| Variante *flat* | 56 × 56 px, `border-radius: 0`, SVG com `margin: 16px` |
| Variante *expandida* | `height: 48px`, `width: auto`, texto **16 px / 500**, SVG 20 × 20 com `margin: 14px 8px 14px 16px`, `padding-right: 20px` |

### C. Painel aberto (desktop)

| Propriedade | Valor |
|---|---|
| `.woot-widget-holder` | `width: 400px`; `height: calc(90% - 64px - 20px)`; `max-height: 640px`; `min-height: 250px` [FATO — código] |
| Medido | iframe **400 × 640 px** em (1020, 156) → `right: 20px`, `bottom: 104px` [MEDIDO] ✔ bate com o CSS |
| `border-radius` | **16 px** |
| `box-shadow` | `0 5px 40px rgba(0, 0, 0, .16)` |
| `transition` | `opacity 0.2s linear, transform 0.25s linear`; ao esconder, `translateY(40px)` |
| Header | **400 × 72 px**, `padding: 20px`, `gap: 8px`, `background: rgb(45, 196, 111)` (#2DC46F) [MEDIDO] |
| — título | **16 px / 500**, branco |
| — subtítulo | **12 px / lh 12px**, `rgba(255, 255, 255, 0.8)` |
| — botão voltar (na conversa) | 40 × 24 com ícone 24 × 24 branco |
| Corpo | `background: rgb(249, 249, 251)` |
| Área de conversa | 400 × 468 px, `padding: 32px 8px 8px`, com `linear-gradient(rgba(255,255,255,0.85), …)` sobreposto |
| Cartão "Estamos conectados" | 368 × 144 px em (16, 432), `border-radius: 12px`, `background: rgb(253,253,253)`, `padding: 16px 20px`, `gap: 12px` |
| — avatares empilhados | **36 × 36**, `border-radius: 9999px`, sobreposição `-16px`; iniciais **14,4 px / 500** |
| — CTA "Iniciar Conversa" | texto `rgb(0, 156, 224)` **/500**, ícone 20 × 20 |
| Composer (footer) | 400 × 48 px em y=540, `padding: 0 20px`, `margin-bottom: 4px` |
| — caixa | 360 × 48 px, `border-radius: 8px`, fundo branco, `padding: 0 8px 0 12px`, `transition: 0.2s cubic-bezier(0.4, 0, 0.2, 1)` |
| — `textarea` | 268 × 32 px, `lh 24px`, `padding: 4px 0`, placeholder `"Digite sua mensagem"` |
| — botões anexo / emoji | **32 × 32** com ícones 20 × 20 em `rgb(28, 32, 36)`. **Não há botão de enviar visível** — envia com Enter |
| Rodapé de branding | 400 × 48 px, `padding: 12px 0`; "Desenvolvido por CHAT - SPX" **12 px / lh 12px**, `rgb(96, 100, 108)`, `opacity: 0.9` |

**Balões [FATO — `app/javascript/widget/assets/scss/views/_conversation.scss`]**

| Propriedade | Valor |
|---|---|
| `.chat-bubble` base | `border-radius: 1.25rem` (**20 px**); `padding: 12px 16px` (`py-3 px-4`); `font-size: 14px` (`text-sm`); `line-height: 1.5` (**21 px**); `display: inline-block`; `word-break: break-word` |
| `box-shadow` | `0 0.25rem 6px rgba(50,50,93,0.08), 0 1px 3px rgba(0,0,0,0.05)` — **temos sombra no balão** |
| Borda | `1px solid` `n-slate-5` (light) / `n-slate-11/50` (dark) |
| `.chat-bubble.agent` | fundo `white` / dark `n-solid-3`; texto `n-slate-12`; **canto inferior esquerdo 4 px** |
| `.chat-bubble.user` | fundo = `widgetColor` inline; cor do texto calculada por contraste; **canto inferior direito 4 px** |
| Agrupamento | mensagens consecutivas do mesmo lado achatam o **canto superior** para 4 px (`.chat-bubble-wrap + .chat-bubble-wrap`) |
| Espaçamento | entre balões do mesmo grupo **2 px** (`mt-0.5`); entre grupos de lados diferentes **16 px** (`mt-4`); `margin-bottom: 4px` no wrapper |
| Larguras máximas | agente **88 %** (`.agent-message`), com `message-wrap` a 90 % disso; visitante **85 %** |
| Avatar por mensagem | **24 × 24** (`h-6 w-6`), com `margin-top: -32px` no thumbnail |
| Nome do agente | `text-xs` (**12 px**) `font-medium`, `margin: 8px 0` |

### F. Mobile [MEDIDO + FATO — código]

`@media (max-width: 667px)`: `.woot-widget-holder { height: 100%; width: 100%; right: 0; top: 0 }` → **fullscreen**. Medido: iframe **390 × 844 px em (0, 0)** com a página em 390 × 844. O launcher some ao abrir (`.woot-widget-bubble.woot--close { bottom: 60px; opacity: 0; visibility: hidden; z-index: -1 }`).
**Sem tratamento de `safe-area-inset`** em nenhuma regra do `sdk.js` [FATO — busca no arquivo]. Ver seção C-4.

### Observações de coerência interna (encontradas ao medir)

1. **Duas cores de marca no mesmo painel** [MEDIDO]: o header saiu `rgb(45, 196, 111)` = `#2DC46F` (o verde padrão do SDK) enquanto o CTA "Iniciar Conversa" saiu `rgb(0, 156, 224)` = `#009CE0` — que é exatamente o `widget_color` configurado na inbox. Ou seja, **a cor da inbox chega em parte da UI e não chega no header** nesta build. Isso é observação, não diagnóstico de causa.
2. **Breakpoint com sobreposição exata** [FATO — código]: `@media (max-width: 667px)` e `@media (min-width: 667px)` coexistem em `sdk.js`. Em exatamente 667 px de viewport **as duas regras aplicam**, e o resultado depende da ordem de cascata. Vale escolher 666/667 ou 667/668.
3. **`height: calc(90% - 64px - 20px)` com `max-height: 640px`** [FATO — código]: em telas curtas (por exemplo 800 px de altura), o painel fica com 636 px e o cálculo domina; em telas altas, o `max-height` domina. É um contrato de altura de duas etapas — nenhum concorrente medido usa percentual da janela; todos usam altura fixa.

---

## A17. Teasers / mensagens proativas — comparativo dedicado

O item B da investigação. Medidas todas em desktop 1440 × 900 [MEDIDO].

| Widget | Caixa | Posição | Raio | Fundo / sombra | Conteúdo |
|---|---|---|---|---|---|
| **Intercom** | iframe **400 × 221** em (1050, 669) | `fixed`; `bottom: 54px`; **`right: -10px`** (transborda 10 px para fora da viewport) | no iframe: 0 | transparente no host (tudo desenhado dentro) | cartão "Hi there 👋 / You are now speaking with Fin…" com assinatura "Fin • Just now" |
| **Crisp** | `span.cc-1gbrw` **349 × 127,5** em (1075, 760) | `fixed`; `right: 16px`; `bottom: 12px`; `margin-bottom: -78px`; `max-width: 360px` | **33 px** | branco; `rgba(0,0,0,.02) 0 6px 6px 0`, + 2ª camada | título **13,6 px** "Crisp Noto Sans **Bold**" `ls .05px`; status "We are online" **13,6 px** `#66788A`; grupo de 3 avatares (95 × 32); **dois botões** |
| — botões do Crisp | primário **153 × 38**, secundário **101 × 38** | — | **19 px** | primário `#1970F0` + texto 12,4 px branco Bold; secundário `#D3DDE6` + texto `#1C293B` | `padding: 0 18px`; `transition: background-color .15s ease-in-out, transform .15s` |
| **tawk.to** | iframe **360 × 362** em (1060, 448) | acima do launcher | — | — | cartão com perguntas sugeridas (medido em detalhe na ficha A4) |
| **HubSpot** | contêiner **282 × 277** em (1158, 623) | acima do launcher | — | — | cartão "Want to chat about HubSpot?" com botão de fechar |
| **Huggy** | iframe **350 × 141** em (1082, 684); cartão interno **260 × 107** | acima e à esquerda do botão | **6 px** | branco; `rgba(0,0,0,.1) 0 1px 6px 0` | avatar **32 × 32** `border-radius: 48px` com `box-shadow: rgba(0,0,0,.15) 0 0 20px`; descrição **14 px**; **campo de resposta embutido** 199 × 28 (placeholder "Escreva uma resposta...", raio `0 0 2px 10px`); rodapé "FEITO POR" **9 px** |
| **Olark** | `div#olark-agent-preview-wrap` **320 × 54** em (1100, 764) | dentro da pilha `#olark-launcher-stack` (312 × 108) | — | — | prévia do agente; **botão de dispensar de 9,8 × 9,8 px** (`rgba(15,23,42,.55)`) |
| **LiveChat** | pill **141,2 × 30,4** + cartão **296 × 236,6** | (1120, 601) | 40 px (pill) / 26 px (cartão) | branco; sombra em escada fracionária | saudação + balão + 2 CTAs + **input inline** |
| **JivoChat** | `jdiv#jivo_action` **336 × 70** | sobreposto ao topo do painel | — | — | rótulo de ação |
| **Leadster** | **não tem teaser separado** — o painel de 420 × 370 **abre sozinho** em ~2–4 s | — | — | — | — |
| **ChatSPX** | **não tem** | — | — | — | — |

**Três padrões que valem registro:**

1. **Teaser com campo de resposta embutido** (Huggy e LiveChat): o visitante pode digitar **sem abrir o painel**. Reduz um clique inteiro do funil.
2. **Teaser com botões de escolha** (Crisp, tawk.to, HubSpot): dois a quatro atalhos de intenção em vez de um convite genérico.
3. **`right` negativo** (Intercom, `-10px`): o iframe transborda a viewport de propósito, [INFERÊNCIA] para que a sombra desenhada dentro dele não pareça cortada na borda.

**Nós não temos nenhum dos três.** O ChatSPX não tem teaser — o mais próximo é a `has-unread-view` (`.woot-widget-holder.has-unread-view`: `min-height: 80px`, `bottom: 94px`, `border-radius: 0`, sem sombra) [FATO — `sdk.js`], que é uma prévia de mensagem não lida, não uma mensagem proativa de captura.

---

# PARTE B — Tabela comparativa

## B1. Launcher fechado (desktop 1440 × 900)

| Widget | Tamanho | Forma / raio | Offset (right, bottom) | Fundo | Sombra | Ícone | Hover |
|---|---|---|---|---|---|---|---|
| **Intercom** | 48 × 48 | círculo (50 % no iframe) | 20, 20 | `#000000` | **nenhuma** (usa halo radial 500×500) | SVG 24 | `scale(1.1)` em `.25s cubic-bezier(.33,0,0,1)` |
| **Crisp** | 54 × 54 | `100%` | 24, 20 | `#1970F0` | `0 4px 10px rgba(0,0,0,.05)` | SVG-bg 35 × 30 | sem delta medido |
| **Tidio** | 56 × 56 | `28px` (=50 %) | 24, 52 | `#0566FF` | `0 2px 8px rgba(8,15,26,.08)`, `0 2px 2px rgba(8,15,26,.12)` | SVG 24 | escala **1,1×** |
| **tawk.to** | 60 × 60 (iframe 64 × 60) | `100%` | 24, 20 (iframe a 20) | `#05A84E` | `0 4px 4px rgba(130,130,130,.08)` | SVG 32 | [NÃO VERIFICADO] |
| **Zendesk** | 64 × 64 | `50%` + borda 2px | 16, 16 | `#11110D` | `0 20px 30px rgba(36,36,36,.15)` | SVG 36 | ícone **desliza** `top .5s cubic-bezier(.66,0,.12,1)` |
| **HubSpot** | 60 × 60 | `50%` | ~16, ~16 | `#1F1F1F` | `0 2px 6px rgba(0,0,0,.1)`, `0 4px 16px rgba(0,0,0,.2)` | SVG | escala **1,1×** em `transform .1s ease-in-out` |
| **Chatra** | 60 × 60 | `50%` | 20, 20 | (iframe) | `0 0 3px rgba(0,0,0,.1)`, `0 0 10px rgba(0,0,0,.3)` | (iframe) | `box-shadow .2s linear` |
| **Leadster** | 60 × 60 | `30px` | 18, 24 | `#1771F0` + **foto** | `0 0 12px rgba(0,0,0,.15)` | **rosto humano** | [NÃO VERIFICADO] |
| **Huggy** | 65 × 65 | **`35%`** (squircle) | 20, **10** | `#8116D7` | `0 3px 12px rgba(0,0,0,.23)`, … | **icon font** 32 | `.3s cubic-bezier(.25,.8,.25,1)` |
| **Olark** | **183,7 × 52** | `999px` (**pill com rótulo**) + borda 1px branca | 24, 24 | `#5B3E8E` | `0 10px 24px rgba(11,31,42,.25)` | SVG 32 + texto 18 px | [NÃO VERIFICADO] |
| **JivoChat** | **301,4 × 40** (etiqueta) | **`8px 34px 0 0`** | 40, **0** | gradiente `#2F324A →` | `0 12px 14px 8px rgba(0,0,0,.17)` | SVG 20 × 40 + texto | [NÃO VERIFICADO] |
| **LiveChat** | **card 296 × 236,6** | `26px` | 20, ~0 | branco | escada fracionária | avatar 24 | — |
| **Octadesk** (WhatsApp) | 60 × 60 | — | ~24, ~24 | — | — | — | — |
| **ChatSPX** | **64 × 64** | `100px` | **20, 20** | **`#009CE0`** (widget_color; default do CSS é `#2dc46f`) | `0 8px 24px rgba(0,0,0,.16)` | SVG 24 | **só a sombra** (`.4` de opacidade) |

## B2. Painel aberto (desktop 1440 × 900)

| Widget | Largura × altura | Raio | Offset (right, bottom) | Sombra | Header (altura, fundo) | Composer |
|---|---|---|---|---|---|---|
| **Intercom** | **400 × 704** | 24 px | 20, 84 | `0 5px 40px rgba(9,14,21,.16)` | 54 px, branco | 368 × 81, raio 16, borda 1px |
| **Crisp** | **400 × 730** | 16 px | 24, 90 | `0 10px 2px rgba(0,0,0,.02)`, `0 4px 20px rgba(0,0,0,.12)` | 110 px, branco (segmented control) | 380 × 85, borda de foco azul |
| **Tidio** | **372 × 589** (home) / **372 × 700** (chat) | 12 px | 24; base a 120 (home) / 9 (chat) | `0 8px 18px rgba(0,18,46,.16)` | **284 px**, `#0566FF` + imagem | textarea 296 × 52 |
| **tawk.to** | **400 × 700** | 18 px | 20, 98 | `10px 10px 40px rgba(0,0,0,.08)`, `5px 14px … rgba(26,26,26,.12)` | 62 px, `#05A84E` | textarea 12,99 px |
| **HubSpot** | **416 × 530** | 10 px | 16, 88 | `0 4px 16px rgba(0,0,0,.1)` | 72 px, `#1F1F1F` | **384 × 42, pill 28 px** |
| **LiveChat** | **388 × 768** | 24 px | 20, 16 | `0 .48px 2.41px -.38px rgba(0,0,0,.08)`, `0 4px 20px -.75px rgba(0,0,0,.25)` | **flutuante 194 × 60**, branco | dentro do card |
| **Chatra** | **450 × 600** | **0 px** | 20, 20 | `0 0 10px rgba(0,0,0,.3)` | 49 px, branco | 450 × 56 |
| **JivoChat** | **336 × 496** | **`10px 33px 0 0`** | 30, **0** | `0 20px 40px 8px rgba(0,0,0,.25)` | 70 px, gradiente escuro | 336 × 110 |
| **Leadster** | **420 × 370** | 12 px | 24, 48 | `0 0 24px rgba(0,0,0,.15)` | 100 px, `#1771F0` | **não existe** |
| **Huggy** | **370 × 564** | `6px 6px 0 0` no header | ~24, ~80 | header `0 1px 4px rgba(0,0,0,.2)` | 64 px, `#8116D7` | 370 × 63 |
| **ChatSPX** | **400 × 640** (`max-height`) | **16 px** | **20, 104** | `0 5px 40px rgba(0,0,0,.16)` | **72 px**, `#2DC46F` | 360 × 48, raio 8 |

## B3. Balão de mensagem do agente

| Widget | Fundo | Raio | Padding | `max-width` | Fonte / entrelinha | Sombra | Timestamp |
|---|---|---|---|---|---|---|---|
| **Intercom** | `#F5F5F5` | **20 px uniforme** | 12/16 | 280 px (70 %) | 14 / **19,6** (1,40) | não | 12 px abaixo, absoluto |
| **Crisp** | `#F0F2F5` | 12 px | 8/14/9 | — | 12,6 / **18** (1,43) | não | não no balão |
| **tawk.to** | `#E5E5E5` | **8 px** | 12 | 320 px (80 %) | 14 / **22,65** (1,62) | não | fora do balão |
| **HubSpot** | `#F5F3F2` | 10 px | 8/16 | `max(100%-48px, 284px)` | 14 / **24** (1,71) | não | — |
| **LiveChat** | `#F0F0F0` (casca branca) | **`22 22 6 6`** | 12 | 296 px (76 %) | 16 / **21,6** (1,35) | casca tem | — |
| **JivoChat** | `#F0F3F4` | 12 px | 12/16 | 252,8 px (75 %) | 15 / **19,6** (1,31) | não | em `aria-label` |
| **Leadster** | `#EEEEEE` | **24 px** | **16/24** | grupo 80 % | 14,4 / **21,6** (1,50) | não | não |
| **Huggy** | `#FFFFFF` | **7 px** | 10 | **85 %** | 14 | **`0 2px 23px rgba(0,0,0,.07)`** | não |
| **Tidio** (cartões) | `#FFFFFF` | 12 px | 14/16 | 332 px (89 %) | 14 / **20** (1,43) | não | — |
| **ChatSPX** | branco | **20 px**, canto inferior do lado 4 px | **12/16** | **88 %** | **14 / 21** (1,50) | **`0 4px 6px rgba(50,50,93,.08)`, `0 1px 3px rgba(0,0,0,.05)`** | fora do balão |

## B4. Tipografia

| Widget | Família | Própria? | Base | Corpo | Secundário | Branding |
|---|---|---|---|---|---|---|
| Intercom | `system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji"` | não | 16 | 14 | 12 / 12,68 | — |
| Crisp | `"Crisp Noto Sans Regular"/"Bold", "Helvetica Neue", Helvetica, Arial` | **sim** | 11 | 12,6 | 11,6 | 11 |
| Tidio | `TidioInter, sans-serif` | **sim** | 14 | 14 | 12 | **10** |
| tawk.to | `Lato, sans-serif` | **sim** | 14 | 14 | 12 | 12 |
| HubSpot | `"Lexend Deca", sans-serif` | **sim** | 14 | 14 | 11 / 12 | 12,6 |
| LiveChat | `system-ui, "Segoe UI", Roboto, Helvetica, Arial` | não | **16** | 16 | 13 | — |
| Chatra | `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto` | não | **15** | 15 | 13,5 / 11,61 | — |
| JivoChat | `Arial, system-ui, -apple-system, Arial` | não | 15 | 15 | 14 | 13 |
| Leadster | `"Plus Jakarta Sans"` + `"Open Sans Regular"` | **sim (2)** | 14,4 | 14,4 | 12 / 10,8 | 13 |
| Huggy | `Rubik` + `Lato` (input) | **sim (2)** | 14 | 14 | — | — |
| Zendesk | `system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI"` | não | 14 (só o launcher) | — | — | — |
| **ChatSPX** | `-apple-system, system-ui, BlinkMacSystemFont, "Segoe UI"…` | **não** | **16** | **14** | **12** | **12** |

## B5. Paleta por widget (cores efetivamente encontradas)

| Widget | Marca | Fundo painel | Balão agente | Texto forte | Texto fraco | Bordas |
|---|---|---|---|---|---|---|
| Intercom | `#000000` | `#FFFFFF` | `#F5F5F5` | `#14161A` | `#6C6F74` | `#E5E5E5` |
| Crisp | `#1970F0` | `#FFFFFF` | `#F0F2F5` | `#1C293B` | `#66788A` | `#D3DDE6` |
| Tidio | `#0566FF` | `#FFFFFF` | `#FFFFFF` | `#080F1A` | `#4C596B` / `#647491` | `#E2E8EF` |
| tawk.to | `#05A84E` | `#FFFFFF` | `#E5E5E5` | `#313131` | `#545454` | `#E9E9E9` |
| HubSpot | `#1F1F1F` | `#FFFFFF` | `#F5F3F2` | `#141414` | `#425B76` | `#676565` |
| LiveChat | `#D93311` / `#1B1B20` | `#F6F6F7` | `#F0F0F0` | `#111111` | `#6B6B6B` | `#E3E3E3` |
| JivoChat | `#2F324A` (gradiente) | `#FFFFFF` | `#F0F3F4` | `#222D38` | `#959DA5` | `#E0E5E9` |
| Leadster | `#1771F0` | `#FFFFFF` | `#EEEEEE` | `#000000` | `#66727C` | `#DDDDDD` |
| Huggy | `#8116D7` | `#F7F7F7` | `#FFFFFF` | `#34474C` | `#565656` | — |
| Olark | `#5B3E8E` | `#F8FAFC` | — | — | `rgba(15,23,42,.55)` | `#FFFFFF` (borda do pill) |
| Zendesk | `#11110D` | — | — | — | `#5C6970` | — |
| **ChatSPX** | `#009CE0` (launcher + ações) / **`#2DC46F` só no header** | `#F9F9FB` | `#FFFFFF` | `#1C2024` | `#60646C` | `n-slate-5` |

## B6. Mobile (390 × 844)

| Widget | Comportamento medido | Raio | Launcher some? |
|---|---|---|---|
| **Crisp** | **fullscreen 390 × 844 em (0,0)** | 0 | [NÃO VERIFICADO] |
| **tawk.to** | **fullscreen 390 × 844 em (0,0)** | — | [NÃO VERIFICADO] |
| **JivoChat** | **fullscreen 390 × 844** com camada `rgba(0,0,0,0.4)` atrás | 0 | [NÃO VERIFICADO] |
| **Intercom** | teaser em iframe **390 × 222 em (0,666)** — largura total; painel [NÃO VERIFICADO] | — | — |
| **ChatSPX** | **fullscreen 390 × 844 em (0,0)** [MEDIDO]; `height:100%; width:100%; right:0; top:0` | 0 | **sim** (`opacity:0; visibility:hidden`) |
| Tidio / HubSpot / LiveChat / Chatra / Leadster / Huggy | [NÃO VERIFICADO] | | |

---

# PARTE C — Padrões convergentes

Esta é a parte que define o **"normal" numérico do mercado**. Onde 7, 8 ou 9 de 9 concordam, fugir do valor é uma decisão de design que precisa ser deliberada — não acidental.

## C1. O launcher tem um tamanho canônico: **54–65 px, mediana 60**

Nove concorrentes têm launcher em formato de bolha. Medidos [MEDIDO]:

```
Intercom  48 ██████████████████
Crisp     54 ████████████████████
Tidio     56 █████████████████████
tawk.to   60 ██████████████████████
HubSpot   60 ██████████████████████
Chatra    60 ██████████████████████
Leadster  60 ██████████████████████
Zendesk   64 ████████████████████████
Huggy     65 ████████████████████████
--- nosso ---
ChatSPX   64 ████████████████████████
```

- **8 de 9** ficam entre **54 e 65 px**. O único fora é o Intercom, em 48.
- **Mediana = 60 px.** Moda = 60 px (4 ocorrências).
- Nossos **64 px** estão dentro da faixa, no quartil superior. **Não há motivo métrico para mexer.**

## C2. O launcher fica a **20 px** do canto — e essa é a maior unanimidade da amostra

| Offset `right` | Widgets |
|---|---|
| 16 px | Zendesk, HubSpot |
| **20 px** | **Intercom, tawk.to, Chatra, Huggy, ChatSPX** |
| 18 px | Leadster |
| 24 px | Crisp, Tidio |

`bottom`: **20 px em 5 de 9**; exceções são Zendesk/HubSpot (16), Leadster (24) e Tidio (52 — porque o wrapper do Tidio tem `margin-bottom: 52px` para acomodar a pilha de teaser).

Faixa total: **16–24 px em 9 de 9**. Nada na amostra usa 8, 12, 32 ou 40.

## C3. **Círculo perfeito** é o padrão; o squircle é a única dissidência

- `border-radius` ≥ 50 % (círculo) em **8 de 9**: Intercom (50 % no iframe), Crisp (100 %), Tidio (28 px = 50 %), tawk.to (100 %), Zendesk (50 %), HubSpot (50 %), Chatra (50 %), Leadster (30 px = 50 %).
- **Huggy** usa `35%` — um squircle visivelmente diferente.
- Formatos alternativos que **não são bolha**: Olark (pill 183,7 × 52 com rótulo de texto), JivoChat (etiqueta 301 × 40 colada na base), LiveChat (não tem launcher — tem um cartão de 296 × 237 sempre visível).

[INFERÊNCIA] Existe uma bifurcação em curso: **bolha silenciosa** (a maioria) versus **launcher que já diz alguma coisa** (Olark, JivoChat, LiveChat). Os três que quebraram o círculo o fizeram para caber texto.

## C4. Ícone do launcher: SVG, entre **43 % e 65 % do diâmetro**

| Widget | Ícone | Diâmetro | Razão |
|---|---|---|---|
| Crisp | 35 × 30 | 54 | **65 %** |
| Zendesk | 36 | 64 | 56 % |
| tawk.to | 32 | 60 | 53 % |
| Intercom | 24 | 48 | 50 % |
| Huggy | 32 | 65 | 49 % |
| Tidio | 24 | 56 | 43 % |
| **ChatSPX** | **24** | **64** | **37,5 %** ← o menor da amostra |

**Nosso ícone é proporcionalmente o menor de todos.** Com `margin: 20px` num botão de 64, sobra muito ar. O ponto médio do mercado (≈ 52 %) num botão de 64 px daria um ícone de **32–34 px**.
Formato: **SVG em 8 de 9**; só a Huggy usa icon font.

## C5. Sombra do launcher: **presente em 8 de 9**, blur entre 4 e 30 px

| Widget | Sombra |
|---|---|
| Zendesk | `0 20px 30px rgba(36,36,36,.15)` (a mais deslocada) |
| **ChatSPX** | `0 8px 24px rgba(0,0,0,.16)` |
| Huggy | `0 3px 12px rgba(0,0,0,.23)` + 2ª camada |
| Chatra | `0 0 3px rgba(0,0,0,.1)` + `0 0 10px rgba(0,0,0,.3)` (halo, sem offset) |
| Crisp | `0 4px 10px rgba(0,0,0,.05)` |
| Tidio | `0 2px 8px rgba(8,15,26,.08)` + `0 2px 2px rgba(8,15,26,.12)` |
| HubSpot | `0 2px 6px rgba(0,0,0,.1)` + `0 4px 16px rgba(0,0,0,.2)` |
| tawk.to | `0 4px 4px rgba(130,130,130,.08)` |
| Leadster | `0 0 12px rgba(0,0,0,.15)` |
| **Intercom** | **nenhuma** — usa um gradiente radial de 500 × 500 px atrás do canto |

**5 de 9 usam duas camadas** (uma de contato, curta e opaca; uma ambiente, longa e translúcida). Nós usamos **uma camada só**. Opacidade da camada ambiente: 0,05–0,25 (nossa 0,16 está no meio).

## C6. Hover: **escala 1,1× é o gesto padrão**

Dos que consegui medir com delta [MEDIDO]:

| Widget | O que muda | Duração / curva |
|---|---|---|
| Intercom | `scale(1.1)` | 250 ms `cubic-bezier(.33,0,0,1)` |
| Tidio | escala 1,1× (56 → 61,6) | 150 ms `cubic-bezier(.4,0,.2,1)` |
| HubSpot | escala 1,1× (60 → 66) | 100 ms `ease-in-out` |
| Zendesk | ícone **desliza verticalmente** | 500 ms `cubic-bezier(.66,0,.12,1)` |
| Chatra | só `box-shadow` | 200 ms linear |
| Crisp | nenhum delta medido | — |
| **ChatSPX** | **só `box-shadow`** (0,16 → 0,40 de opacidade) | não declarada para `box-shadow` |

**3 de 6 escalam 1,1×** em 100–250 ms. Nós somos do grupo minoritário (só sombra) e, além disso, a nossa `transition` do `.woot-widget-bubble` lista `transform, opacity, visibility, bottom` — **`box-shadow` não está na lista**, então a mudança de sombra no hover é instantânea, sem interpolação [FATO — `app/javascript/sdk/sdk.js`].

## C7. Painel: **largura 370–420 px em 8 de 10**; 400 px é o valor mais repetido

```
JivoChat  336 ████████████████
Huggy     370 ██████████████████
Tidio     372 ██████████████████
LiveChat  388 ███████████████████
Intercom  400 ████████████████████
Crisp     400 ████████████████████
tawk.to   400 ████████████████████
HubSpot   416 ████████████████████
Leadster  420 █████████████████████
Chatra    450 ██████████████████████
--- nosso ---
ChatSPX   400 ████████████████████
```

- **8 de 10 entre 370 e 420 px.** Fora da faixa: JivoChat (336) e Chatra (450). **Mediana = 394 px. Moda = 400 px** (3 concorrentes + nós).
- Alturas: 370 (Leadster) a 768 (LiveChat); **5 de 10 ficam em 700 px ou mais**; mediana 632. **Nós temos 640 — na mediana.**
- **Nenhum concorrente medido usa altura percentual da janela.** Todos usam pixel fixo. Nós usamos `calc(90% - 84px)` limitado a 640 px.

## C8. Raio do painel: **10–24 px em 8 de 10; mediana 16**

| 0 px | 10 | 12 | 16 | 18 | 24 |
|---|---|---|---|---|---|
| Chatra | HubSpot | Tidio, Leadster | **Crisp, ChatSPX** | tawk.to | Intercom, LiveChat |

JivoChat é o caso especial: `10px 33px 0 0` — raio assimétrico deliberado, repetido no launcher, funcionando como assinatura de marca. **Nossos 16 px estão exatamente na mediana.**

[INFERÊNCIA] Existe um agrupamento no topo: Intercom e LiveChat — que também são os dois que usam header neutro em vez de header colorido — são os únicos em 24 px.

## C9. Balão de mensagem: aqui **não há consenso** — e é onde mais dá para escolher

| Raio | Widgets |
|---|---|
| 7–10 px | Huggy (7), tawk.to (8), HubSpot (10) |
| 12 px | Crisp, JivoChat |
| 20–24 px | **Intercom (20), ChatSPX (20)**, LiveChat (22 nos cantos superiores), Leadster (24) |

**Mediana = 12 px**, mas a distribuição é **bimodal**: um grupo "documento" (7–12 px) e um grupo "conversa" (20–24 px). Não existe meio-termo popular.

**Canto achatado / agrupamento:**
- **7 de 9** usam raio **uniforme** nos quatro cantos (Intercom, Crisp, tawk.to, HubSpot, JivoChat, Leadster, Huggy).
- Só **LiveChat** (`22 22 6 6`) e **nós** (canto inferior do lado da origem em 4 px, canto superior em 4 px quando consecutivo) fazem o achatamento no canto de origem.
- **Nenhum** da amostra desenha "rabinho"/tail triangular.

**`max-width`:** 70 % (Intercom) → 89 % (Tidio). **6 de 8 entre 70 % e 85 %.** Nossos **88 %** são o segundo mais largo da amostra.

**Padding:** vertical **8–16 px**, horizontal **10–24 px**. Mediana **12 / 16** — exatamente o nosso valor.

**Sombra no balão:** só **2 de 9** têm — Huggy (`0 2px 23px rgba(0,0,0,.07)`) e **nós** (duas camadas). Os outros 7 usam contraste de fundo puro. **Somos, junto com a Huggy, exceção aqui.**

**Espaço entre balões:** 2 px (nós, mesmo grupo) → 22 px (Crisp). Entre grupos de lados diferentes: 16 px (nós), 20 px (Intercom), 24 px (tawk.to).

## C10. Tipografia: **14 px / entrelinha 1,4–1,5** é o corpo padrão

- Corpo em **14 px: 6 de 11** (Intercom, tawk.to, HubSpot, Tidio, Huggy, ChatSPX). 15 px: 2 (Chatra, JivoChat). 16 px: 1 (LiveChat). 14,4 px: Leadster. 12,6 px: Crisp.
- `line-height` do balão: **1,31 → 1,71** (JivoChat 1,31 · LiveChat 1,35 · Intercom 1,40 · Crisp e Tidio 1,43 · Chatra, Leadster e nós 1,50 · tawk.to 1,62 · HubSpot 1,71); mediana **1,465**. Nossa 1,50 está dentro.
- Texto secundário: **10–13 px** em 11 de 11. Nossos 12 px estão no meio.
- **Fonte própria vs. stack de sistema: 6 × 6 — empate exato.** Os 6 com fonte própria são Crisp (`Crisp Noto Sans`), Tidio (`TidioInter`), tawk.to (`Lato`), HubSpot (`Lexend Deca`), Leadster (`Plus Jakarta Sans` + `Open Sans`), Huggy (`Rubik` + `Lato`). Os 6 com stack de sistema incluem Intercom, LiveChat, Chatra, JivoChat, Zendesk e **nós**.
- **Dois widgets usam duas famílias diferentes no mesmo painel** (Leadster e Huggy) — [INFERÊNCIA] isso não parece decisão de design, e sim herança de camadas antigas.
- **`letter-spacing` é praticamente ausente**: só Crisp (0,15–0,2 px) e Intercom (0,072 px no timestamp) declaram algo diferente de `normal`.

## C11. Header: **49–72 px** na maioria, mas existe uma escola de "header-hero"

| Faixa | Widgets |
|---|---|
| 49–72 px (barra) | Chatra 49, Intercom 54, LiveChat 60 (flutuante), tawk.to 62, Huggy 64, JivoChat 70, HubSpot 72, **ChatSPX 72** |
| 100–284 px (hero) | Leadster 100, Crisp 110, **Tidio 284** |

**8 de 11 ficam entre 49 e 72 px.** Nossos 72 px estão no topo dessa faixa.

**Cor do header:** cor de marca sólida em **7 de 11** (Tidio, tawk.to, HubSpot, JivoChat, Leadster, Huggy, ChatSPX); branco/neutro em 3 (Intercom, Crisp, Chatra); LiveChat usa um cartão branco flutuante.
[INFERÊNCIA] Os dois que usam header neutro (Intercom, LiveChat) são também os dois com maior raio de painel (24 px) e os dois que constroem o balão sobre contraste de fundo em vez de cor de marca — parecem seguir uma mesma escola. Não afirmo qual é a mais recente: não verifiquei datas de redesign.

**Avatar no header:** 32 (Intercom, Tidio), 36 (Crisp, HubSpot, LiveChat, ChatSPX), 40 (tawk.to), 50 (Leadster).
**Forma do avatar — achado:** **3 de 7 não são círculo**: Intercom `16.7%` (≈5,3 px em 32), Tidio `4px`, tawk.to `15px` em 40. O quadrado-arredondado está entrando.

**Botões de ação do header:** 28 × 28 (LiveChat), 32 × 30 (tawk.to), 36–38 (Intercom), 40 × 40 (HubSpot), 25 × 25 (Leadster), 47 × 40 (Chatra). **Mediana ≈ 36 px.** O botão de fechar da Leadster (25 px) e o *dismiss* do teaser do Olark (**9,8 px**) ficam abaixo do mínimo de 24 × 24 CSS px recomendado pelo WCAG 2.2 *Target Size (Minimum)* [INFERÊNCIA a partir de medida].

## C12. Composer: o mercado sempre mostra um botão de enviar — **nós somos a única exceção**

| Widget | Botão enviar | Tamanho | Forma |
|---|---|---|---|
| Intercom | sim | 32 × 32 | `32px` |
| Crisp | sim | 36 × 36 | `13px` |
| JivoChat | sim | 34 × 34 | `100%` |
| HubSpot | sim | 40 × 40 | `50%` |
| LiveChat | sim | 40 × 40 | `50%` |
| Huggy | sim | 40 × 39 | — |
| Tidio | sim | 24 × 24 | — |
| **ChatSPX** | **não existe** | — | — |

**7 de 7 concorrentes com composer medido têm botão de enviar visível.** Nós só temos anexo e emoji (32 × 32 com ícones de 20 px); o envio depende de Enter. Em mobile, sem teclado físico, isso é um problema de descoberta [INFERÊNCIA].

**Forma da caixa de texto:** pill (`28px` HubSpot, `30px` LiveChat inline), arredondada (`16px` Intercom, `8px` ChatSPX), ou sem raio com borda superior (Chatra, JivoChat). **Alturas 42–110 px**; a nossa (48) é a segunda menor.

**Foco:** só Crisp e Intercom declaram um estado de foco visível no contêiner (Crisp com anel de 3 px na cor da marca; Intercom com `outline-width` animado em 100 ms). Nossa caixa tem `transition: 0.2s cubic-bezier(0.4,0,0.2,1)` mas [NÃO VERIFICADO] se há mudança visual de foco — não capturei o estado focado.

## C13. Branding do rodapé: **10–13 px, sempre em cinza**

| Widget | Formato | Tamanho | Cor |
|---|---|---|---|
| Tidio | logo SVG | **10 px** | `#8894AB` |
| Crisp | link | 11 px, `opacity .75` | — |
| tawk.to | **pill 161 × 30 em iframe próprio** | 12 px | `#4F4F4F` |
| **ChatSPX** | link | 12 px, `opacity .9` | `#60646C` |
| JivoChat | faixa **no topo** do corpo | 13 px | `#959DA5` |
| Leadster | **pill fora do painel**, abaixo dele | 13 px `/700` | `#66727C` |
| Intercom, HubSpot | **não têm** | — | — |

Dois padrões notáveis: o tawk.to isola o branding num **iframe separado** (o site hospedeiro não consegue escondê-lo por CSS), e a Leadster o coloca **fora** do painel, como uma aba pendurada.

## C14. Mobile: **fullscreen é unânime nos que medi**

4 de 4 medidos (Crisp, tawk.to, JivoChat, ChatSPX) viram **390 × 844 em (0,0)**, `border-radius: 0`. Nenhum bottom-sheet parcial, nenhum painel de altura reduzida.
Só o **JivoChat** adiciona uma camada `rgba(0,0,0,0.4)` por trás.

**Sobre `safe-area`:** o nosso `sdk.js` **não declara nenhuma regra com `env(safe-area-inset-*)`** [FATO — busca no arquivo]. Para os concorrentes, **[NÃO VERIFICADO]** — `env()` é resolvido antes do `getComputedStyle`, então a minha coleta não distingue um `padding-bottom: 0px` vindo de `env()` de um zero literal. Só posso afirmar a lacuna no nosso lado.

## C15. Dark mode: **1 de 4** — e o que ele muda

Testei `prefers-color-scheme: dark` em quatro widgets. **Só o Intercom responde.** Crisp, Tidio e LiveChat mantêm o painel claro.
O Intercom troca **o conjunto de classes**, não só variáveis: `intercom-1e0b6bi` → `intercom-11dowma`. A troca cobre balão, texto, composer, timestamp e botão de enviar (tabela em A1-G).

## C16. Timing e curvas de animação

Durações medidas, agregadas:

| Faixa | Uso típico |
|---|---|
| 50–150 ms | mudança de cor de fundo em hover (Crisp 50/100 ms, HubSpot 100 ms, Tidio 150 ms) |
| 150–300 ms | abertura/fechamento do painel, escala do launcher (Intercom 167/200/250 ms, Crisp 150 ms, Tidio 200 ms, ChatSPX 200/250/300 ms) |
| 300–500 ms | gestos deliberados (LiveChat 300 ms com *delay* de 300 ms, Chatra 400 ms, **Zendesk 500 ms** no deslize do ícone) |

**Curvas customizadas em 7 de 11**: `.33,0,0,1` (Intercom), `.4,0,.2,1` (Tidio e o nosso composer), `.14,0,0,1` e `.33,0,.67,1` (LiveChat), `.66,0,.12,1` (Zendesk), `.25,.8,.25,1` (Huggy), `.39,.24,.21,.99` (JivoChat). Só Chatra e partes do nosso SDK usam `linear`/`ease` puro.

## C17. `z-index`: a corrida armamentista

`2147483647` (JivoChat, 1Mind) > `2147483000` (**Intercom e nós**) > `10000010` (Huggy) > `1000003` (tawk.to) > `1000002` (Crisp) > `9999` (Chatra) > `9990` (HubSpot) > `32767` (Leadster).
Nosso valor está empatado com o Intercom — [INFERÊNCIA] é o teto prático sem entrar em guerra com quem usa o máximo do int32.

## C18. Arquitetura de isolamento

| Estratégia | Widgets |
|---|---|
| **iframe** (isolamento total de CSS) | Intercom (3), tawk.to (**3**, incluindo um só para o branding), HubSpot (1), LiveChat (2), Chatra (1), Zendesk (1+), Huggy (3), **ChatSPX (1)** |
| **Shadow DOM** | Tidio, Olark |
| **DOM aberto** | Crisp, JivoChat, Leadster |

**8 de 13 usam iframe.** [INFERÊNCIA] Continua sendo a escolha dominante para isolamento — e é a nossa.

---

# PARTE D — Índice de screenshots

Todos em `plano/estudo-chat-web/frontend/shots/`. Nomenclatura desta task: `<widget>-<estado>-<viewport>[-dark].png`.

**Montagem comparativa:** `COMPARATIVO-launchers-desktop.png` — os 13 cantos inferiores direitos (recorte 340 × 240 px de cada screenshot fechado em 1440 × 900) lado a lado. É a imagem para abrir primeiro: mostra numa tela só a diferença entre bolha silenciosa, pill com rótulo, etiqueta na base, cartão sempre aberto e rosto humano.

| Widget | Fechado | Aberto | Launcher recortado | Mobile | Dark |
|---|---|---|---|---|---|
| Intercom | `intercom-closed-desktop.png` | `intercom-open-desktop.png` | `intercom-launcher-desktop.png` · `intercom-launcher-hover-desktop.png` | `intercom-closed-mobile.png` · `intercom-open-mobile.png` | `intercom-closed-desktop-dark.png` · `intercom-open-desktop-dark.png` |
| Crisp | `crisp-closed-desktop.png` | `crisp-open-desktop.png` | `crisp-launcher-desktop.png` · `crisp-launcher-hover-desktop.png` | `crisp-closed-mobile.png` · `crisp-open-mobile.png` | `crisp-closed-desktop-dark.png` · `crisp-open-desktop-dark.png` |
| Tidio | `tidio-closed-desktop.png` | `tidio-open-desktop.png` · `tidio-open-chat.png` | `tidio-t05-desktop.png` | `tidio-closed-mobile.png` · `tidio-open-mobile.png` | `tidio-closed-desktop-dark.png` · `tidio-open-desktop-dark.png` |
| tawk.to | `tawkto-closed-desktop.png` | `tawkto-open-desktop.png` | — | `tawkto-closed-mobile.png` · `tawkto-open-mobile.png` | — |
| JivoChat | `jivochat-closed-desktop.png` | `jivochat-open-desktop.png` | — | `jivochat-closed-mobile.png` · `jivochat-open-mobile.png` | — |
| Zendesk | `zendesk-closed-zdweb.png` · `zendesk-closed-zd2.png` | (não abriu) | — | — | — |
| HubSpot | `hubspot-closed-desktop.png` | `hubspot-open-desktop.png` | — | — | — |
| LiveChat | `livechat2-closed-desktop.png` | `livechat2-open-desktop.png` | — | — | `livechat2-closed-desktop-dark.png` · `livechat2-open-desktop-dark.png` |
| Chatra | `chatra-closed-desktop.png` | `chatra-open-desktop.png` | — | — | — |
| Leadster | `leadster-fechado-focus-after-desktop.png` | `leadster-open-desktop.png` · `leadster-focus-before-desktop.png` | — | — | — |
| Huggy | `huggy-closed-desktop.png` | `huggy-open-desktop.png` | — | — | — |
| Olark | `olark-closed-desktop.png` | `olark-open-desktop.png` | — | — | — |
| Octadesk | `octadesk-closed-desktop.png` | `octadesk-open-desktop.png` | — | — | — |
| Salesloft/1Mind | `onemind-closed-desktop.png` | (não abriu — banner de consentimento) | — | — | — |
| **ChatSPX** | `chatspx-closed-desktop.png` | `chatspx-open-desktop.png` · `chatspx-open-conv.png` | — | `chatspx-closed-mobile.png` · `chatspx-open-mobile.png` | — |

Há também séries de *timeline* (`<widget>-t<segundos>-<viewport>.png`) capturadas a cada 2 s durante o carregamento, úteis para ver quando cada peça aparece — em especial `leadster-t*` (o widget é injetado por GTM e abre sozinho) e `intercom-t*`.

---

# O QUE ISSO SIGNIFICA PARA O REDESENHO DO CHATSPX

Recomendações, em ordem de impacto. Nenhuma traz código de implementação — são decisões de design com o número que as sustenta.

## 1. O que **não** mexer: já estamos no padrão

Estes valores nossos coincidem com a mediana ou a moda do mercado. Mudá-los custa esforço e não compra nada:

| Nosso valor | Posição no mercado |
|---|---|
| Launcher **64 × 64** | dentro de 54–65 (8 de 9); mediana 60 |
| Offsets **20 / 20** | valor mais repetido (5 de 9) |
| Launcher circular (`100px`) | 8 de 9 |
| Painel **400 px** de largura | a moda exata (3 concorrentes) |
| Painel **640 px** de altura | mediana 632 |
| Painel raio **16 px** | mediana exata |
| Balão padding **12 / 16** | mediana exata |
| Corpo **14 px / lh 1,5** | 6 de 11 usam 14 px; mediana de lh 1,45 |
| Secundário **12 px** | 11 de 11 entre 10 e 13 |
| Branding **12 px** cinza | 10–13 px em todos que têm |
| Mobile **fullscreen** | 4 de 4 |
| Isolamento por **iframe** | 8 de 13 |
| `z-index` **2147483000** | empatado com o Intercom |

**Conclusão:** o esqueleto do nosso widget é normal. O redesenho não precisa (e não deve) recomeçar da geometria.

## 2. Corrigir o que está fora do padrão sem intenção

Três coisas nossas estão fora da faixa do mercado, e nenhuma parece decisão deliberada:

**2.1 — O ícone do launcher é pequeno demais.** 24 px num botão de 64 = **37,5 %**, contra 43–65 % do mercado (mediana ≈ 52 %). O botão parece vazio. Um ícone de **32–34 px** nos coloca no centro da distribuição sem alterar o tamanho do botão.

**2.2 — Não existe botão de enviar no composer.** 7 de 7 concorrentes com composer medido têm um, entre 24 e 40 px, quase sempre circular. Em desktop o Enter resolve; em mobile, onde o painel é fullscreen e o teclado virtual ocupa metade da tela, a ausência de um alvo de envio é a diferença entre a mensagem sair e não sair. **Recomendo adotar um botão de 32–36 px circular**, alinhado ao lado direito da caixa, com estado desabilitado visível (o padrão do mercado é fundo neutro + ícone cinza, como Intercom e JivoChat fazem).

**2.3 — O hover do launcher não anima.** A nossa `transition` lista `transform, opacity, visibility, bottom` — **`box-shadow` não está incluída**, e a mudança de sombra no hover acontece de forma instantânea. Ou incluímos `box-shadow` na lista, ou trocamos o gesto por **`scale(1.1)` em 150–250 ms**, que é o que 3 de 6 fazem e é o gesto que o visitante reconhece.

## 3. O header não recebe a cor da conta — resolver antes de redesenhar

[MEDIDO] Numa mesma inbox com `widget_color = #009CE0`:

| Superfície | Cor medida |
|---|---|
| Launcher | `rgb(0, 156, 224)` = **`#009CE0`** ✔ |
| CTA "Iniciar Conversa" | `rgb(0, 156, 224)` = **`#009CE0`** ✔ |
| **Header do painel** | `rgb(45, 196, 111)` = **`#2DC46F`** ✘ (o verde *default* do SDK) |

Ou seja: **o launcher e as ações pegam a cor da conta; o header não.** O visitante vê um botão azul que abre um painel de topo verde. Qualquer redesenho de paleta amplifica isso. **Definir uma única fonte de verdade para a cor da marca e garantir que ela alcance header, CTA, balão do visitante, foco do composer e launcher.** Nenhum concorrente medido exibe duas cores de marca simultâneas no mesmo widget.

## 4. Escolher deliberadamente de que lado da bifurcação do balão ficamos

O raio do balão é **bimodal**: 7–12 px (grupo "documento": Huggy, tawk.to, HubSpot, Crisp, JivoChat) ou 20–24 px (grupo "conversa": Intercom, LiveChat, Leadster, nós). Não há meio-termo popular. Estamos em 20 px, no grupo "conversa" — que é o grupo dos redesigns mais recentes.

Duas decisões a tomar dentro desse grupo:

**4.1 — Manter ou não o canto achatado.** **7 de 9** usam raio uniforme nos quatro cantos; só LiveChat e nós achatamos o canto de origem. O achatamento é bom sinal de agrupamento, mas nos coloca em minoria. Se mantivermos, mantenhamos por convicção — funciona bem quando combinado com o espaçamento de 2 px entre consecutivas, que já temos.

**4.2 — A sombra do balão é nossa maior anomalia visual.** Só 2 de 9 têm sombra no balão (nós e a Huggy). Sete widgets constroem a separação por **contraste de fundo**: fundo do painel branco + balão do agente em cinza, ou o inverso. Nosso balão do agente é **branco (`#FFFFFF`) sobre fundo de painel `#F9F9FB`** — 6 pontos de diferença nos canais R e G e 4 no B, praticamente indistinguível; a sombra vira muleta para compensar. **Recomendo remover a sombra e resolver por contraste**, seguindo o par que o mercado usa: painel branco + balão em cinza (Intercom `#FFFFFF`/`#F5F5F5`; Crisp `#FFFFFF`/`#F0F2F5`; HubSpot `#FFFFFF`/`#F5F3F2`; tawk.to `#FFFFFF`/`#E5E5E5`), ou o inverso do LiveChat (painel `#F6F6F7` + balão branco).

## 5. Reduzir a largura máxima do balão

Nossos **88 %** são o segundo maior da amostra; **6 de 8 ficam entre 70 % e 85 %**. Em 400 px de painel, 88 % dá 352 px de linha — longo demais para 14 px de fonte. O Intercom, que é o mais disciplinado, usa **70 %** (280 px). **Recomendo 78–82 %**, que encurta a linha sem parecer estreito e cria a "escada" visual que separa agente de visitante.

## 6. Dark mode é uma vantagem real e barata

**Apenas 1 de 4 testados suporta.** O Intercom trocou o tema inteiro; Crisp, Tidio e LiveChat continuam claros mesmo com `prefers-color-scheme: dark`. Nosso widget **já tem tokens `dark:`** nos componentes Vue (`dark:bg-n-solid-3`, `dark:text-n-slate-12`, `dark:border-n-slate-11/50`) [FATO — código]. O que falta é fechar o circuito: garantir que o holder, o header, o composer e o rodapé sigam o esquema, e decidir se seguimos o sistema, a configuração da conta, ou ambos. **É a diferenciação com melhor razão esforço/percepção de todo este levantamento.**

## 7. Mobile: falta `safe-area`

O nosso `sdk.js` não trata `env(safe-area-inset-*)` em nenhuma regra [FATO — busca no arquivo]; para os concorrentes isso é [NÃO VERIFICADO] (ver C14). Como nosso painel vira fullscreen com `top: 0; height: 100%`, no iPhone o header encosta no notch/Dynamic Island e o composer encosta na barra de gestos. É uma correção pequena e visível, e resolve um defeito real do nosso lado — independentemente do que os concorrentes façam.

Ainda em mobile: o breakpoint duplicado em **exatamente 667 px** (`max-width: 667px` e `min-width: 667px` coexistem) deixa o comportamento nessa largura dependente da ordem da cascata. Escolher 666/667 ou 667/668 antes de mexer em qualquer coisa responsiva.

## 8. Onde quebrar o padrão de propósito — três apostas com evidência

**8.1 — Launcher que fala.** Três concorrentes abandonaram a bolha para caber texto: Olark (pill 183,7 × 52 com rótulo), JivoChat (etiqueta 301 × 40 colada na base) e LiveChat (cartão de 296 × 237 sempre visível). **Nós já temos essa variante no CSS do SDK** — `.woot-widget-bubble.woot-widget--expanded`: 48 px de altura, largura automática, texto 16 px/500, SVG 20 px, `padding-right: 20px` [FATO — `app/javascript/sdk/sdk.js`]. Ela existe e depende de configuração; **[NÃO VERIFICADO]** quantas contas da frota a usam hoje. Se estiver ociosa, ativá-la com uma frase de contexto é a mudança de maior efeito de conversão disponível sem escrever componente novo.

**8.2 — Rosto em vez de ícone.** A Leadster põe **uma fotografia de pessoa** no launcher de 60 px, e repete o rosto no header (50 px) e nas mensagens (32 px). É a única da amostra que faz isso, e é o concorrente brasileiro direto. O padrão do resto do mercado é o balão genérico. Para um produto que vende atendimento humano + IA, o rosto é uma diferenciação forte — e o custo é uma configuração de imagem, não um componente novo.

**8.3 — Avatar quadrado-arredondado.** **3 de 7** já não usam círculo no avatar do header: Intercom `16.7%`, Tidio `4px`, tawk.to `15px`. É um sinal pequeno mas consistente de modernização visual, e é gratuito.

## 9. O que o mercado abandonou — não copiar

- **Drift está em sunset** desde março de 2026; a salesloft.com nem serve mais o widget dele, serve um agente 1Mind em vídeo. Copiar o "padrão Drift" de qualificação B2B é copiar um produto que está sendo desligado.
- **Duas famílias tipográficas no mesmo painel** (Leadster: `Plus Jakarta Sans` + `Open Sans`; Huggy: `Rubik` + `Lato`) — nos dois casos parece herança, não decisão.
- **Header colorido de largura total** ainda é maioria (7 de 11), mas Intercom e LiveChat o abandonaram em favor de header neutro — e são justamente os dois com maior raio de painel e com a separação de balões resolvida por contraste. Vale considerar o header neutro com a cor da marca aplicada em ações e no balão do visitante. (Não verifiquei datas de redesign; a leitura de "tendência" é inferência a partir da coincidência dessas três escolhas.)

## 10. Alvos de toque abaixo do mínimo — verificar os nossos

Encontrei botões abaixo de 24 × 24 CSS px na amostra: o *dismiss* do teaser do Olark (**9,8 × 9,8**), o fechar da Leadster (25 × 25, no limite) e os botões do composer do tawk.to (28,8 × **22**). Nossos botões de anexo e emoji têm caixa de **32 × 32** com ícone de 20 — dentro do mínimo. Ao redesenhar, **manter 32 px como piso de caixa** e não reduzir para 24 mesmo que o ícone diminua.

---

## Limites deste levantamento — para o próximo que ler

- Tudo foi medido em **11/08/2026**. Widgets em produção mudam sem aviso; refazer as medidas antes de usá-las como referência daqui a alguns meses.
- **Painel do Zendesk, painel do Tidio em mobile, painel do Intercom em mobile, Smartsupp e Freshchat: não medidos** (Intercom e Tidio em mobile foram tentados duas vezes cada, com coordenada explícita e com detecção automática de launcher; o painel não abriu em nenhuma). Estão marcados como `[NÃO VERIFICADO]` no corpo do documento e **não** entraram em nenhuma contagem de padrão convergente.
- **Nenhum balão de visitante foi medido em concorrente** — não enviei mensagens para não abrir atendimentos reais. Todas as afirmações sobre balões referem-se ao **balão do agente**. O do visitante (cor de marca, canto oposto) é `[NÃO VERIFICADO]` em toda a amostra externa; só o nosso está descrito, e a partir do código.
- As cores de marca observadas (`#000000` no Intercom, `#1F1F1F` no HubSpot, `#1970F0` no Crisp) são **as escolhas desses fornecedores nos próprios sites**, não os padrões de fábrica que eles entregam aos clientes.
- Hover foi medido movendo o cursor e relendo o `computedStyle`; onde não houve delta, registrei "sem delta medido" — o que **não** prova ausência de efeito (pode haver mudança apenas em pseudo-elemento ou em filho que não amostrei).
