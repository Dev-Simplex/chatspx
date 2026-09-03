# 12 — Movimento, micro-interações e estados

**Onda:** estudo de front end para a repaginada do widget ChatSPX · **Data da coleta:** 11/08/2026
**Escopo:** como os widgets de chat do mercado se movem e como respondem, com números medidos.
**Nada foi implementado.** Nenhum arquivo de código do repositório foi alterado.

---

## Como ler este documento

Toda afirmação carrega uma marcação de origem:

| Marca | Significa |
|---|---|
| **[MEDIDO]** | Número extraído da engine no navegador (`getComputedStyle`, `getBoundingClientRect`, `document.getAnimations()`, série por `requestAnimationFrame`). Reproduzível com o comando indicado. |
| **[FATO]** | Texto literal do CSS ou do JavaScript servido pelo fornecedor, com o arquivo/URL de origem. |
| **[INFERÊNCIA]** | Conclusão minha a partir de dados medidos — não observei diretamente. |
| **[NÃO VERIFICADO]** | Não consegui medir. Fica registrado como buraco, não como opinião. |

Duas frases desta onda merecem cuidado especial, porque foram exatamente o tipo de coisa que
poderia virar conclusão errada se eu tivesse resumido rápido:

1. **A Leadster não toca som.** Eu capturei três `new Audio()` na página dela — e eles vêm do
   `js.hs-analytics.net` (HubSpot), não do widget. Provado por *stack trace*, não por suposição.
2. **Launcher medido ≠ painel medido.** Onde eu medi só o botão fechado, não afirmo nada sobre o
   painel aberto. Onde medi desktop, não afirmo nada sobre mobile. Cada linha diz qual superfície foi medida.

---

## Método

Instrumentação própria em Playwright (Chromium 145 headless, `--no-sandbox --disable-dev-shm-usage`),
com um script injetado em **todos os frames** via `add_init_script` antes de qualquer código da página.
Quatro instrumentos:

1. **`document.getAnimations()`** — a fonte mais confiável. Devolve cada `CSSTransition`/`CSSAnimation`
   viva com `duration`, `delay`, `easing` **literal**, `iterations`, `fill` e o elemento-alvo. Isso não é
   estimativa: é o que a engine de composição está executando.
2. **Série por `requestAnimationFrame`** — amostra `opacity`, `transform`, `rect`, `display` e `visibility`
   de até 70 elementos a cada frame (~22–27 ms/frame medidos), para conferir a duração declarada contra a real.
3. **Leitura do CSS servido** — `document.styleSheets` percorrido recursivamente (incluindo `@media`,
   `@supports`, `adoptedStyleSheets` e shadow roots), mais download direto por `curl` quando a folha é
   cross-origin. É daqui que saem os `@keyframes` e os `cubic-bezier(...)` literais.
4. **Monkey-patch de efeitos colaterais** — `HTMLMediaElement.play`, `new Audio`, `AudioContext`,
   `Notification`, `navigator.vibrate` e um `MutationObserver` no `<title>`, todos com timestamp
   (`performance.now()`) e *stack trace*. O observer de `<title>` foi validado num teste controlado antes
   de eu concluir qualquer coisa a partir dele (ver §12).

Cada alvo passou por: carregar → aceitar cookies → assentar (9–22 s) → medir o launcher em repouso →
`mousemove` (hover) → `mousedown` (press) → `mouseup` (abre) → gravar 2,8–5 s de abertura → medir o painel →
foco/Tab/Shift+Enter → `Escape` → fechar → medir de novo.

**Sem login, sem paywall, sem envio de mensagem a atendente humano.** Onde há bot automático (Leadster,
Octadesk, Intercom/Fin, tawk/Apollo, Crisp/Hugo), a conversa avançou sozinha e eu apenas observei.

### Alvos e o que foi possível medir

| Fornecedor | URL medida | Launcher | Painel | Observação |
|---|---|---|---|---|
| **Leadster** (neurolead) | `www.leadster.com.br` | ✅ | ✅ | Abre **sozinho**, sem clique |
| **Intercom** | `www.intercom.com` | ✅ | ✅ | Melhor documentado do mercado |
| **Crisp** | `docs.crisp.chat` | ✅ | ✅ | Painel no DOM da página, não em iframe |
| **tawk.to** | `www.tawk.to` | ✅ | ✅ | 5 iframes irmãos; CSS baixado por `curl` |
| **HubSpot** | `www.hubspot.com/products/service` | ✅ | parcial | Container mede 100×96 → 448×634 |
| **LiveChat** | `www.livechat.com` | ✅ | ✅ | Painel 420×800 em iframe |
| **JivoChat** | `www.jivochat.com` | ✅ | ✅ | Painel pré-renderizado fora da viewport |
| **Octadesk** (octa-wa) | `www.octadesk.com` | ✅ | ✅ | Caixa WhatsApp — referência BR |
| **Zoho SalesIQ** | `www.zoho.com/salesiq` | ✅ | ❌ | Clique não abriu na sessão medida |
| **Zendesk** | `www.zendesk.com.br` | ✅ | ❌ | Launcher custom; messenger não abriu |
| **Chatwoot** (upstream) | `www.chatwoot.com` | ✅ | ✅ | Nossa base — comparação direta |
| **ChatSPX** (nosso) | `app/javascript/sdk` + `widget` | ✅ | ✅ | Lido do repositório, não medido em runtime |

Descartados por não servirem o widget na sessão medida: Tidio (`tidio.com`, nenhum widget carregou),
Drift (`drift.com` hoje serve o assistente **1mind**, não o Drift Messenger), Freshchat
(`freshworks.com` serve **Qualified**), Olark (`olark.com` hoje serve **OpenAI ChatKit**).
Esse último é um dado de mercado por si só: em 2026, dois sites de fornecedores de chat já trocaram
o próprio produto por um assistente de IA de terceiros na home. [MEDIDO — recon de 30 URLs]

---

## 1. Tabela mestra — durações e easings por interação

Tudo abaixo é **[MEDIDO]** (engine) ou **[FATO]** (CSS servido). Onde a duração medida difere da
declarada, mostro as duas.

### 1.1 Launcher

| Fornecedor | Tamanho | Repouso (transition) | Hover | Press | "Chamar atenção" |
|---|---|---|---|---|---|
| **Intercom** | 48×48 | `transform 167ms cubic-bezier(.33,0,0,1)` | `scale(1.1)` em `250ms cubic-bezier(.33,0,0,1)` — medido **243 ms** | `scale(0.85)` em `134ms cubic-bezier(.45,0,.2,1)` — medido **119 ms** | entrada `300ms cubic-bezier(.4,0,.2,1)`: `scale(.8)+op0 → scale(1)+op1` |
| **Crisp** | 54×54 | `bg 100ms linear`, `outline-color/width 150ms ease-in-out`, `transform 150ms ease-in-out` | muda `transform` + `outline-width` (150 ms) | encolhe (54 → 52,2 px medido) | não observado |
| **Octadesk** | 60×60 | `transform 200ms ease` | 60 → 64,8 px (**scale ≈ 1,08**) | não isolado | **`octaWaRadar` 2400ms linear infinite** |
| **HubSpot** | 60×60 | `transform 100ms ease-in-out` | 60 → 64,6 px (**scale ≈ 1,077**) | não isolado | não observado |
| **Zendesk** | 64×64 | `all` | sem mudança de transform/sombra | sem mudança | entrada `0.2s ease-in jBcSpD` |
| **Chatwoot/ChatSPX** | 64×64 (48 de altura no modo expandido) | `transform 300ms ease, opacity 100ms ease` | **só a sombra**: `0 8px 24px rgba(0,0,0,.16)` → `0 8px 32px rgba(0,0,0,.4)` | **nada** | nenhuma |
| **Leadster** | 60×60 | `all` (sem duração declarada) | sem mudança | sem mudança | entrada `nld-slide-in 500ms` + selo verde `nld-super-pop-in 500ms cubic-bezier(0,.35,.28,.9)` com `delay 1s` |
| **tawk.to** | iframe 64×60 | — (iframe) | não isolado | não isolado | badge "1" injetado em **1 588 ms** |

### 1.2 Painel

| Fornecedor | Tamanho medido | Raio | Sombra | Abertura | Fechamento |
|---|---|---|---|---|---|
| **Intercom** | 400×704 | 24 px | `rgba(9,14,21,.16) 0 5px 40px` | `transform 300ms cubic-bezier(0,1.2,1,1)` + `opacity 83ms ease-out` + `width/height/max-height 200ms`, origem `right bottom` | mesma transition (simétrica na declaração) |
| **Crisp** | 400×730 | 16 px | `0 10px 2px rgba(s,.02), 0 4px 20px rgba(s,.12)` | animação **100 ms** `ease-in-out both` | animação **150 ms** `both` (+ ícone 200 ms com `delay 50ms`) |
| **Chatwoot/ChatSPX** | 400×640 | — | `0 5px 40px rgba(0,0,0,.16)` | `opacity 200ms linear` + `transform 250ms linear` | idem, e o holder some para `bottom:-100vh` |
| **Octadesk** | 349×466 | — | — | `opacity 250ms ease` + `transform 250ms ease` | idem 250 ms |
| **JivoChat** | 300–336×496 | — | — | `WidgetContainer_OPEN_WIDGET…` **300 ms linear** | `WidgetContainer_CLOSE…` **300 ms linear** |
| **LiveChat** | 420×800 | — | — | `transform 430ms cubic-bezier(.33,0,0,1)` | não isolado |
| **Leadster** | 420×370 (max-height 550 px) | 12 px | `rgba(0,0,0,.15) 0 0 24px` | `nld-slide-in` **500 ms** `forwards` (`translateY(100px)`+op0 → 0+op1) | `nld-slide-out` **500 ms** |
| **HubSpot** | 448×634 / 416×530 | — | — | não isolado | não isolado |

### 1.3 Leitura rápida da tabela

- **A faixa de trabalho do mercado é 100–300 ms.** Nada fora disso, exceto Leadster (500 ms) e
  LiveChat (430 ms). [MEDIDO]
- **Só o Intercom usa curva com overshoot.** `cubic-bezier(0, 1.2, 1, 1)` — a ordenada do primeiro ponto
  de controle é 1,2, acima de 1, então o painel ultrapassa o valor final e volta. Curvas customizadas
  existem em outros (LiveChat `cubic-bezier(.33,0,0,1)`, tawk `cubic-bezier(1,.5,.8,1)`, Leadster
  `cubic-bezier(0,.35,.28,.9)`), mas **nenhuma passa de 1** — todas desaceleram sem passar do ponto. [FATO]
- **Chatwoot/ChatSPX é o único cujo painel tem `transition` declarada com easing `linear`** — o
  movimento não tem aceleração nem desaceleração, que é o que dá a sensação de "mecânico".
  [FATO — `app/javascript/sdk/sdk.js:14`; confirmado pela engine em `www.chatwoot.com`, §2.2]
- **A Leadster é a única cujo painel entra por `@keyframes` em vez de `transition`** (`nld-slide-in`,
  `animation-fill-mode: forwards`), o que impede transição reversível — abrir e fechar são duas
  animações distintas, não a ida e a volta da mesma. [FATO]

---

## 2. Abertura e fechamento do painel

### 2.1 Intercom — o mais bem construído que medi

**[FATO]** `www.intercom.com`, regra servida no documento principal:

```css
.intercom-namespace .intercom-with-namespace-vzjtt8 {
  z-index: 2147483002; position: fixed; bottom: 84px; right: 20px;
  transform-origin: right bottom;
  height: min(704px, 100% - 104px); min-height: 80px;
  width: min(400px, max(0px, -20px + 100dvw));
  max-height: 704px; border-radius: 24px; overflow: hidden;
  box-shadow: rgba(9, 14, 21, 0.16) 0px 5px 40px 0px;
  transition: width 200ms, height 200ms, max-height 200ms,
              transform 300ms cubic-bezier(0, 1.2, 1, 1),
              opacity 83ms ease-out;
}
```

Quatro decisões que valem ser lidas com atenção:

1. **`transform-origin: right bottom`** — o painel cresce *a partir do launcher*, não do próprio centro.
   É o que faz o gesto parecer causado pelo clique.
2. **`opacity 83ms ease-out` contra `transform 300ms`** — a opacidade termina em 1/4 do tempo do
   movimento. O painel fica **visível quase imediatamente** e só o *movimento* leva 300 ms. Isso é o
   oposto do padrão ingênuo (`transition: all 300ms`), que deixa o conteúdo fantasma metade da animação.
   83 ms é um número escolhido, não redondo — 5 frames a 60 Hz.
3. **`cubic-bezier(0, 1.2, 1, 1)`** — overshoot suave só no transform.
4. **`min()` / `max()` / `100dvw` no dimensionamento** — o painel se adapta sem media query, e usa
   `dvh`/`dvw` (unidade dinâmica) em vez de `vh`, que é justamente o conserto do problema da barra de
   endereço no mobile.

**[MEDIDO]** Sequência real capturada (`rec-intercom-desktop-open.json`, 238 amostras a ~22,6 ms):
`t=514,8 ms` entra o hover → `scale` chega a 1,1 em `t=757,6` (**243 ms**) → `t=1938,5` press →
`scale` 0,85 em `t=2057,7` (**119 ms**) → `t=2550,0` soltar o botão dispara as duas transitions do painel
(`opacity 83 ms` + `transform 300 ms`, ambas confirmadas pela engine com o easing literal acima).

### 2.2 Chatwoot (nossa base) — o que a engine executa de fato

**[MEDIDO]** `www.chatwoot.com`, 279 amostras a ~17,8 ms/frame (`rec-chatwoot-desktop-open.json`).
No instante do clique (`t=2 150,9 ms`) a engine disparou **oito** transições simultâneas:

| Alvo | Propriedade | Duração | Delay | Easing |
|---|---|---|---|---|
| `.woot-widget-holder` (400×640) | `opacity` | 200 ms | 0 | **`linear`** |
| `.woot-widget-holder` | `transform` | 250 ms | 0 | **`linear`** |
| `.woot-widget-bubble` (164×48) | `transform` | 300 ms | 0 | `ease` |
| `.woot-widget-bubble` | `opacity` | 200 ms | 0 | `ease` |
| `.woot-widget-bubble` | `visibility` | 0 ms | **500 ms** | `linear` |
| `.woot-widget-bubble` | `bottom` | 0 ms | **200 ms** | `ease` |
| botão de fechar | `opacity` | 100 ms | 0 | `ease` |
| botão de fechar | `transform` | 300 ms | 0 | `ease` |

Os `delay` de 200 ms e 500 ms em propriedades de duração zero (`visibility`, `bottom`) são a técnica
clássica de "só troque a visibilidade depois que a animação terminar" — está correta. O problema não é
a orquestração, é a **curva**: o painel inteiro se move em `linear`, sem aceleração nem desaceleração.
Um retângulo de 400×640 atravessando 40 px em velocidade constante é exatamente o que o olho lê como
"animação de software", e não como objeto físico.

### 2.3 Fechamento é mais rápido que abertura? — resposta medida, e ela contraria a expectativa

A hipótese comum ("o mercado fecha mais rápido") **só se confirma em parte**:

| Fornecedor | Abre | Fecha | Simétrico? |
|---|---|---|---|
| Crisp | 100 ms | **150 ms** | não — **fecha 50% mais lento** [MEDIDO] |
| JivoChat | 300 ms | 300 ms | sim [MEDIDO] |
| Octadesk | 250 ms | 250 ms | sim [MEDIDO] |
| Intercom | 300 ms (transform) | 300 ms declarados | sim na declaração [FATO] |
| Leadster | 500 ms (`slide-in`) | 500 ms (`slide-out`) | sim [FATO] |
| tawk.to | `.slide-fade-enter-active: all .3s ease` | `.slide-fade-leave-active: all .8s cubic-bezier(1,.5,.8,1)` | **não — sai quase 3× mais lento** [FATO] |
| tawk.to (outro bloco) | `all .2s ease` | `all .1s cubic-bezier(1,.5,.8,1)` | **não — sai 2× mais rápido** [FATO] |

**[INFERÊNCIA]** Não existe uma convenção de mercado aqui. O tawk.to tem os dois padrões opostos
convivendo em arquivos diferentes do mesmo widget, o que sugere ausência de sistema, não escolha.
O padrão que se sustenta é o do Crisp e do Intercom: **entrada rápida (100–300 ms) e saída no mesmo
intervalo ou levemente maior**, porque o usuário já decidiu ir embora e a saída não precisa de urgência —
precisa não piscar.

### 2.4 Há stagger na abertura?

**[MEDIDO]** Nos oito painéis que consegui abrir, **nenhum escalona a entrada dos elementos internos**
no momento da abertura. O painel entra como um bloco só. O stagger, quando existe, está na entrada de
*mensagens* (§6) e no Crisp no ícone do launcher (`delay 50 ms` na saída) — nunca no conteúdo do painel.

---

## 3. Launcher: repouso, hover, press e "chamar atenção"

### 3.1 Hover — três escolas

**[MEDIDO]** Medi o mesmo gesto (mover o mouse até o centro do launcher e esperar 850 ms) em todos:

| Escola | Quem | O que muda |
|---|---|---|
| **Escala** | Intercom (1,10), HubSpot (≈1,077), Octadesk (≈1,08) | o botão cresce; sombra intacta |
| **Sombra** | Chatwoot/ChatSPX | `0 8px 24px rgba(0,0,0,.16)` → `0 8px 32px rgba(0,0,0,.4)` — blur +8 px e **opacidade 2,5×** |
| **Contorno** | Crisp | `outline-width` + `outline-color` em 150 ms `ease-in-out`, mais um `transform` |
| **Nada** | Zendesk, Leadster, JivoChat | sem alteração de `transform`, `box-shadow` ou `background` medida |

A escolha do Chatwoot merece um comentário: saltar a opacidade da sombra de **0,16 para 0,40** é um
salto grande — a sombra fica quase preta sob o botão. Como não há escala, o feedback é uma mancha
escura crescendo, não um objeto reagindo. [MEDIDO + FATO — `sdk.js:46` e `sdk.js:133`]

### 3.2 Press — só um fornecedor faz direito

**[MEDIDO]** O único launcher que reage ao `mousedown` de forma perceptível é o **Intercom**:
`scale(0.85)` — 15% menor — em `134 ms cubic-bezier(0.45, 0, 0.2, 1)`, medido em **119 ms**
(48 px → 40,8 px). É uma curva diferente da do hover, mais "seca" na entrada.

Crisp encolhe discretamente (54 → 52,2 px). **Chatwoot/ChatSPX, Zendesk, Leadster e JivoChat não têm
estado `:active` nenhum** — o botão não responde ao toque, só ao resultado. Em conexão lenta, isso
significa clicar e não ter confirmação de que o clique foi registrado.

### 3.3 A animação de "chamar atenção"

**[FATO]** Só encontrei duas, e são bem diferentes:

**Octadesk** — `octaWaRadar`, **2400 ms `linear infinite`** no próprio botão. Um pulso contínuo de
radar em volta do botão do WhatsApp. Roda **para sempre**, sem contagem, sem parar após interação
observada. [MEDIDO — presente em todas as fases: aberto, fechado, após `Esc`]

**Leadster** — não é um pulso contínuo, é uma **entrada encenada em duas partes**:
```css
.nld-chatbot > .nld-avatar::after {
  content:""; width:15px; height:15px; position:absolute; bottom:0; right:0;
  background-color: rgb(46,204,113); border-radius: 9px !important;
  transform: scale(0,0);
  animation: .5s cubic-bezier(0,.35,.28,.9) 1s 1 normal forwards nld-super-pop-in;
}
@keyframes nld-super-pop-in {
  0%   { opacity:0; transform: scale(0,0); }
  30%  { opacity:1; background-color: white; transform: scale(1.5,1.5); }
  80%  { transform: scale(1,1); }
  100% { opacity:1; transform: scale(1,1); }
}
```
O avatar entra deslizando de baixo (500 ms), e **1 segundo depois** o selo verde de "online" estoura
até 150% do tamanho — piscando branco no pico — e assenta. É uma animação de 15 px que carrega
sozinha a mensagem "tem gente aqui agora". Custo: 4 linhas de CSS.

**[INFERÊNCIA]** O contraste entre as duas é instrutivo: a Octadesk gasta um loop infinito para
chamar atenção (e vira ruído após o primeiro segundo); a Leadster gasta 500 ms **uma vez** e diz
mais. O gesto que só acontece uma vez é o que o olho registra.

---

## 4. Teaser (mensagem proativa antes do clique)

**[MEDIDO]** Cronometrei da navegação (`domcontentloaded`) até o teaser ficar visível:

| Fornecedor | Quando aparece | Tamanho | Como entra |
|---|---|---|---|
| **Leadster** | **≈ 10,0 s** (`t=9986 ms`) | 269×48 | `nld-pop-in-middle` 500 ms `forwards`: `translateY(-50%) scale(0,0)` → `scale(1,1)` |
| **tawk.to** | **≈ 6,4 s** (`t=6415 ms`) | 360×545 → 360×362 | iframe `message-preview` próprio |
| **HubSpot** | container aos **4,1 s**, cresce aos **6,8 s** | 100×96 → 448×634 | não isolado |
| **LiveChat** | **≈ 19,1 s** (`t=19052 ms`) | 420×800 → 320×299 | não isolado |
| **Crisp** | presente no primeiro scan | 392×128 | não isolado |

A Leadster segue com uma segunda encenação dentro do teaser: [FATO]
```css
.nld-invite-message-container.nld-notification .nld-footer.nld-time {
  opacity: 0; animation: nld-slide-in .4s cubic-bezier(0,.35,.28,.9) forwards; animation-delay: .25s;
}
.nld-invite-message-container.nld-notification .nld-footer.nld-verified {
  opacity: 0; animation: nld-slide-in .4s cubic-bezier(0,.35,.28,.9) forwards; animation-delay: .5s;
}
```
O balão entra, **250 ms depois** aparece o horário, **500 ms depois** aparece o selo "Verificado pela
Leadster". Três tempos escalonados para simular uma mensagem que acabou de chegar. É o único
stagger deliberado que encontrei em todo o corpus.

**Como o teaser sai:** [MEDIDO] na Leadster, quando o painel auto-abre em `t≈18,6 s`, o convite recebe
`nld-hidden` (`nld-pop-out` 300 ms: `scale(1)` → `scale(0)`) e o avatar recebe `nld-hidden-slide`
(`nld-slide-out` 500 ms) **no mesmo frame** (`t=18654,3` e `t=18654,9`).

**Volta em visitas seguintes?** [NÃO VERIFICADO] — tentei medir com três visitas consecutivas no mesmo
contexto de navegador (cookies e `localStorage` preservados), mas **a partir da 2ª visita o site da
Leadster respondeu com o checkpoint anti-bot da Vercel** ("Falha ao verificar seu navegador — Código 21",
`shots/leadster-repeat-visita2.png`). As três visitas voltaram vazias por esse motivo, não por ausência
de teaser. Registro como buraco: **a frequência de reaparição do teaser não foi medida em nenhum
fornecedor.** É uma pergunta que importa para o redesenho (quantas vezes o widget pode importunar o
mesmo visitante) e que fica em aberto.

---

## 5. Indicador de digitando — o detalhe que quase ninguém acerta

Esta seção está escrita para ser reimplementável sem olhar o original.

### 5.1 Leadster — pontos que **encolhem**, não saltam

**[FATO]** CSS embutido em `cdn.leadster.com.br/neurolead/neurolead.min.js` (448 KB):
```css
.nld-chatbot .nld-typing-indicator { width: 54px; display: inline-block; vertical-align: middle; }
.nld-chatbot .nld-typing-indicator > span {
  width: 12px; height: 12px; border-radius: 6px !important;
  margin-right: 6px; float: left; opacity: 0.5; background: #2ecc71;
}
.nld-typing-indicator > span:nth-child(1) { animation: 1s nld-blink infinite 0.1666s; }
.nld-typing-indicator > span:nth-child(2) { animation: 1s nld-blink infinite 0.3332s; }
.nld-typing-indicator > span:nth-child(3) { animation: 1s nld-blink infinite 0.5s;    }
@keyframes nld-blink { 50% { opacity: 1; transform: scale(0.5); } }
```
Leitura: 3 pontos de **12 px**, espaçados **6 px**, largura total **54 px**, opacidade de repouso
**0,5**, ciclo de **1 s**, defasagem de **166,6 ms** entre pontos (1/6 do ciclo), `ease` (padrão).
No meio do ciclo o ponto fica **opaco e encolhe pela metade** (`scale(0.5)`) — some para dentro em vez
de pular. É a assinatura mais original do corpus.

**Detalhe que só aparece medindo:** o componente escreve `style="background-color:#aaaaaa"` inline em
cada `<span>` [FATO — `neurolead.min.js`], então **o verde `#2ecc71` do CSS nunca aparece**: na tela os
pontos são cinza. O CSS e o componente discordam, e o componente vence.

### 5.2 tawk.to — o salto exagerado

**[FATO]** `embed.tawk.to/_s/v4/app/6a79567aaa5/css/max-widget.css`:
```css
.agentTypingIndicator .dot {
  display:inline-block; width:5px; height:5px; border-radius:50%;
  margin-right:3px; background:#303131;
  animation: typing 1.3s linear infinite;
}
.agentTypingIndicator .dot:nth-child(2) { animation-delay: -1.1s; }
.agentTypingIndicator .dot:nth-child(3) { animation-delay: -0.9s; }
@keyframes typing { 0%, 60%, 100% { transform: none } 30% { transform: translateY(-10px) } }
```
Ciclo de **1,3 s `linear`**, pontos de **5 px**, salto de **10 px** — o ponto sobe **duas vezes o próprio
diâmetro**. Os delays são **negativos** (−1,1 s e −0,9 s), truque para já começar adiantado sem esperar o
primeiro ciclo; a defasagem efetiva entre pontos é de **200 ms**. Fica parado de 60% a 100% do ciclo
(520 ms de pausa), o que dá o ritmo de "vaga-lume" em vez de onda contínua.

### 5.3 Octadesk — o clone fiel do WhatsApp

**[FATO]** `www.octadesk.com`:
```css
.octa-wa-typing { display:inline-flex; gap:4px; padding:12px 14px; }
.octa-wa-typing span {
  width:7px; height:7px; border-radius:50%; background: rgb(154,160,166);
  animation: 1.2s ease-in-out 0s infinite octaWaTyping;
}
.octa-wa-typing span:nth-child(2) { animation-delay: .15s; }
.octa-wa-typing span:nth-child(3) { animation-delay: .3s;  }
@keyframes octaWaTyping {
  0%, 60%, 100% { transform: translateY(0);    opacity: .5; }
  30%           { transform: translateY(-4px); opacity: 1;  }
}
```
**7 px**, `gap: 4px`, cinza `#9AA0A6` (o cinza do Google/WhatsApp), ciclo **1,2 s `ease-in-out`**,
stagger **150 ms**, salto de **4 px** (pouco mais da metade do diâmetro) **combinado com opacidade
0,5 → 1**. Este é o desenho mais "correto" do corpus: `ease-in-out` dá o arco natural, o salto curto
não descola do texto e a opacidade faz o trabalho pesado.

### 5.4 Comparação lado a lado

| | Leadster | tawk.to | Octadesk |
|---|---|---|---|
| Diâmetro do ponto | 12 px | 5 px | 7 px |
| Espaço entre pontos | 6 px (margin) | 3 px (margin) | 4 px (gap) |
| Ciclo | 1,0 s | 1,3 s | 1,2 s |
| Easing | `ease` (padrão) | `linear` | `ease-in-out` |
| Stagger | 166,6 ms | 200 ms (delay negativo) | 150 ms |
| Movimento | `scale(0.5)` (encolhe) | `translateY(-10px)` (salta 2× o Ø) | `translateY(-4px)` (salta 0,57× o Ø) |
| Opacidade | 0,5 → 1 | fixa | 0,5 → 1 |
| Pausa no ciclo | 50% | 40% (60→100%) | 40% (60→100%) |

**[INFERÊNCIA]** Os três convergem em: **3 pontos, ciclo ~1–1,3 s, stagger de 150–200 ms, e um trecho
parado de 40–50% do ciclo**. O que divide é o verbo — encolher, saltar alto, saltar curto. Saltar 2× o
diâmetro (tawk) chama atenção demais para um estado de espera; encolher (Leadster) é original mas lê
como "carregando", não como "digitando"; **saltar pouco com opacidade (Octadesk/WhatsApp) é o que
lê como digitação**.

### 5.5 Intercom, Crisp, LiveChat, HubSpot

**[NÃO VERIFICADO]** Não localizei o indicador de digitando no CSS servido de nenhum dos quatro.
No Intercom os nomes de animação são hasheados por build (`animation-1s3hfsj`) e os 10 keyframes
capturados são todos de entrada/saída de mensagem e view — nenhum é oscilação infinita. No Crisp os
nomes mudam a cada carregamento, e os keyframes referenciados pelas regras (`cc-1rpb5`, `cc-1nnve`)
não aparecem em `document.styleSheets` — provavelmente injetados fora do CSSOM acessível.
**[INFERÊNCIA]** Nos quatro, o indicador provavelmente é SVG/Lottie ou componente com animação em JS,
não CSS declarativo. Não afirmo mais do que isso.

### 5.6 O nosso — é um GIF

**[FATO]** `app/javascript/widget/components/AgentTypingBubble.vue`:
```html
<div class="chat-bubble agent typing-bubble bg-white dark:bg-n-solid-3">
  <img src="assets/images/typing.gif" alt="Agent is typing a message" class="!w-full" />
</div>
```
com `.typing-bubble { @apply max-w-[2.4rem] p-2 … }`.

Consequências diretas, todas verificáveis por leitura: o indicador **não herda a cor da marca**, **não
tem versão para tema escuro** (o GIF é o mesmo nos dois), **não respeita `prefers-reduced-motion`**
(imagem animada não é alcançada por CSS), **não escala** com o tamanho da fonte, e custa uma requisição
de imagem. É a única implementação em raster de todo o corpus medido.

---

## 6. Entrada de mensagem nova e o *fake typing*

### 6.1 Como a bolha entra

| Fornecedor | Animação | Duração / easing |
|---|---|---|
| **Intercom** | `scale(0.6) + opacity 0` → `scale(1) + opacity 1`, com **50% do keyframe parado no estado inicial** | 300 ms `ease-in` [FATO] |
| **Intercom** (saída) | a mesma animação em `reverse`, mais colapso de altura `53px → 0` | 300 ms `ease-in` com `delay 300ms` [FATO] |
| **Octadesk** | `octaWaMsgIn` | 250 ms [MEDIDO] |
| **Leadster** | `nld-pop-in` (`scale(0,0)` → `scale(1,1)` + opacity) | 300 ms `forwards` [FATO] |
| **tawk.to** | `TransitionGroup` do Vue: `.list-enter-active/.list-leave-active` | `all .5s cubic-bezier(1,.5,.8,1)` [FATO] |
| **Chatwoot/ChatSPX** | **nenhuma** — a bolha simplesmente aparece | — [FATO] |

Sobre a última linha: varri `ChatMessage.vue`, `AgentMessage.vue`, `UserMessage.vue`,
`UserMessageBubble.vue`, `AgentMessageBubble.vue` e `ConversationWrap.vue` procurando `transition`,
`animate-` ou `keyframes`. As **duas únicas** ocorrências em toda a superfície de mensagens são
`class="transition-opacity delay-75 opacity-0 group-hover:opacity-100"` — e são do **botão de responder
que aparece no hover**, não da bolha. A mensagem entra sem nenhuma animação. [FATO]

O truque do Intercom merece destaque: `0% {opacity:0; scale:.6} 50% {opacity:0; scale:.6} 100% {opacity:1; scale:1}`
— metade da duração é **espera embutida no keyframe**. Efeito prático: um `delay` de 150 ms sem precisar
declarar `animation-delay`, o que mantém a animação sincronizada quando várias bolhas entram juntas.

### 6.2 O atraso artificial da Leadster — medido

**[MEDIDO]** Duas sessões independentes (`timeline-leadster.json` e o run de interação), cronometradas
do `domcontentloaded`:

| Marco | Tempo | Delta |
|---|---|---|
| script `neurolead` injetado | 5 118 ms | — |
| `.nld-chatbot` criado no DOM | 6 949 ms | +1 831 ms |
| avatar começa a entrar (`opacity 0`, `translateY(100px)`) | 7 342 ms | +393 ms |
| `.nld-typing-indicator` existe no DOM (oculto) | 9 919 ms | +2 577 ms |
| **teaser visível** (269×48) | 9 986 ms | +67 ms |
| **painel auto-abre** (420×370, `nld-slide-in` 500 ms) | 18 632 ms | +8 646 ms |
| **1ª bolha renderizada** (200×54) | 20 593 ms | **+1 961 ms** |
| 2ª bolha entra (`nld-hidden` → `nld-shown`) | 21 439 ms | +846 ms |
| botão de opção "Sim, começar agora" | 21 907 ms | +468 ms |
| 2ª bolha completa (291×196) | 22 429 ms | **+1 836 ms após a 1ª** |

**Sim, a Leadster faz atraso artificial, e ele é longo:** aproximadamente **1,96 s** entre o painel abrir
e a primeira frase aparecer, e **1,84 s** entre a primeira e a segunda. Com o indicador de digitando
ocupando esse intervalo, a impressão é de alguém escrevendo. Sem ele, seriam dois segundos de tela
vazia. [MEDIDO]

Observe também o total: **da chegada do visitante até a primeira palavra do bot passam ~20,6 segundos**,
sendo ~18,6 s até o painel abrir sozinho. É uma aposta explícita: quem sai antes disso nunca vê o chat.

### 6.3 Octadesk — mesmo recurso, um terço do tempo

**[MEDIDO]** painel abre em `t=2145 ms` já com `octaWaTyping` rodando; a segunda mensagem entra em
`t=3488 ms` — **1 343 ms de digitação simulada**. Metade do tempo da Leadster para o mesmo efeito.

### 6.4 O scroll acompanha?

**[FATO]** No nosso widget, `ConversationWrap.vue`:
```js
scrollToBottom() {
  const container = this.$el;
  container.scrollTop = container.scrollHeight - this.previousScrollHeight;
  this.previousScrollHeight = 0;
}
updated() {
  if (this.previousConversationSize !== this.conversationSize) {
    this.previousConversationSize = this.conversationSize;
    this.scrollToBottom();   // <- sempre, sem checar se o usuário está lendo acima
  }
}
```
Salto **instantâneo** (atribuição direta de `scrollTop`, sem `behavior: 'smooth'`), disparado a **toda**
mudança de tamanho da conversa. Ver §10.

---

## 7. Estados de envio: enviando / enviado / entregue / lido / falhou

Esta é a área mais pobre do mercado medido — e é um dado, não uma lacuna do estudo.

**[MEDIDO/FATO]** Varri o CSS servido de sete widgets procurando `sending`, `sent`, `delivered`,
`read`, `failed`, `retry`. Resultado:

| Fornecedor | O que existe no CSS servido |
|---|---|
| **tawk.to** | `.tawk-button-retry { width: 100% }` — existe reenvio; nenhuma classe de "entregue"/"lido" |
| **Crisp** | `.cc-3mnem--reconnect-inactive` / `--reconnect-failed` — estados de **conexão**, não de mensagem |
| **Chatwoot/ChatSPX** | `.user-message .is-failed { … }` + `.in-progress { opacity: .6 }` + botão de reenvio |
| **Intercom, LiveChat, HubSpot, Octadesk, JivoChat, Leadster** | nada encontrado |

**[INFERÊNCIA]** Os widgets de site herdaram o modelo de *e-mail* (mandou, sumiu), não o modelo de
*mensageiro* (✓, ✓✓, ✓✓ azul). Isso não é descuido: no chat de site o agente costuma estar em uma
janela só, e "entregue" tem pouco significado. Mas para um produto brasileiro, cuja referência mental
de conversa **é o WhatsApp**, a ausência dos ticks é sentida como falta de qualidade — e nenhum
concorrente medido ocupa esse espaço.

### O nosso lado, lido do repositório

**[FATO]** `app/javascript/widget/`:
- **Optimistic UI: sim.** `store/modules/conversation/helpers.js` cria a mensagem com
  `status: 'in_progress'` antes da resposta do servidor, e `mutations.js` a substitui quando o id real chega.
- **"Enviando":** `.in-progress { opacity: 0.6 }` (`assets/scss/views/_conversation.scss:83`) — a bolha
  fica 40% translúcida. Sem `transition` declarada, então a volta a 100% é um corte seco.
- **"Falhou":** `UserMessage.vue` renderiza um botão com `FluentIcon icon="arrow-clockwise" size="14"`
  e `@click="retrySendMessage"`, em `text-n-ruby-9`. **Nós temos reenvio — o mercado medido quase não tem.**
- **"Entregue"/"lido":** não existem no widget.

---

## 8. Quick replies e botões

| Fornecedor | Como entram | Como saem depois do clique |
|---|---|---|
| **Octadesk** | `.octa-wa-choices { animation: octaWaMsgIn 250ms ease }` — entram como se fossem mensagem [FATO] | não isolado |
| **Leadster** | `button.nld-opt` dentro de `.nld-sel.nld-messages`, injetado 468 ms depois da bolha [MEDIDO] | ao clicar, a bolha vira `nld-hidden` (`nld-pop-out` 300 ms) [FATO] |
| **Crisp** | 4 chips ("How can Crisp help me?", …) presentes no painel aberto [MEDIDO — screenshot] | não isolado |
| **tawk.to** | 4 botões outline verde abaixo da mensagem do Apollo [MEDIDO — screenshot] | não isolado |
| **Chatwoot/ChatSPX** | sem animação de entrada [FATO] | — |

**[INFERÊNCIA]** O padrão convergente é: **os quick replies entram com a mesma animação da mensagem**
(não com uma animação própria) e ficam **alinhados ao lado oposto do autor** — no tawk e no Crisp, à
direita, como se fossem a fala que o usuário *vai* dizer. Esse alinhamento é o que faz o chip ser lido
como "minha resposta possível" em vez de "botão do sistema".

---

## 9. Skeleton, shimmer e carregamento

**[FATO]** Só o **tawk.to** tem shimmer declarado:
```css
@keyframes shimmerLeftToRight { 0% { background-position: -29.25rem 0 } to { background-position: 29.25rem 0 } }
@keyframes shimmerRightToLeft { 0% { background-position:  29.25rem 0 } to { background-position: -29.25rem 0 } }
```
Duas direções — provavelmente para respeitar RTL. [INFERÊNCIA]
Também tem `lds-spinner` (opacidade 1→0), `load8`/`spinner`/`rotateCircleLoader` (rotação 360°) e
`iconAnimation` (`opacity 0→1` + `scale .5→1`).

**Intercom:** spinner de **28×28 px**, `600 ms linear infinite`, rotação 360°. Sem skeleton. [FATO]

**Chatwoot/ChatSPX:** `<Spinner />` centralizado quando `isFetchingList`, sem skeleton e sem shimmer.
[FATO — `ConversationWrap.vue:112`]

**[INFERÊNCIA]** Skeleton não é padrão nesse mercado. Faz sentido: o histórico de um chat de site
costuma ter 3–10 mensagens e carrega em poucos milissegundos; um skeleton apareceria e sumiria antes de
ser lido, o que é pior que nada.

---

## 10. Scroll

**[MEDIDO]** Estado do container rolável logo após abrir o painel:

| Fornecedor | `scrollTop` / `scrollHeight` (viewport) | Está no fim? | `scroll-behavior` | `overscroll-behavior` |
|---|---|---|---|---|
| **JivoChat** | 13 / 329 (316) | **sim** | `auto` | `auto` |
| **Chatwoot** | 0 / 767 (640) | **não** | `auto` | `auto` |

Ressalva de rigor: no Chatwoot o container que satisfez o critério de "rolável" foi
`div.w-full h-full bg-n-slate-2 …` dentro do iframe do widget — **é o wrapper do widget, não
necessariamente a lista de mensagens**, e a conversa estava no estado inicial (mensagem de ausência +
artigos populares). Não afirmo a partir disso que a lista de mensagens não vai ao fim; afirmo que **o
container rolável medido não estava no fim**.

**[MEDIDO]** Nenhum dos widgets medidos usa `scroll-behavior: smooth` nem `overscroll-behavior: contain`
no container de mensagens. Todos em `auto`. Isso significa que **o mercado rola instantaneamente** e
que **o scroll do chat vaza para a página por baixo** quando chega ao fim (comportamento padrão do
navegador) — nenhum deles blindou isso.

### O nosso, por leitura de código [FATO]

`ConversationWrap.vue`:
- `mounted()` → `scrollToBottom()`: vai ao fim ao abrir. ✔
- `updated()` → **`scrollToBottom()` sempre que `conversationSize` muda**, sem checar se o usuário
  rolou para cima. Efeito: chegando mensagem enquanto você lê histórico, **você é arrancado para o fim**.
- `handleScroll()` → quando `scrollTop < 100`, chama `fetchOldConversations({ before: earliestMessage.id })`
  e guarda `previousScrollHeight = scrollHeight`.
- `scrollToBottom()` → `scrollTop = scrollHeight - previousScrollHeight`. **Preservação de posição no
  carregamento de histórico: implementada e correta** — depois de carregar páginas antigas, a posição
  visual é mantida. Esse é um detalhe que muita gente erra, e nós acertamos.
- **Não há botão "descer"** em nenhum lugar do widget. [FATO — nenhuma ocorrência de
  `scroll-to-bottom`/`jump-to` nos componentes]

**[NÃO VERIFICADO]** Momentum/inércia em mobile real (`-webkit-overflow-scrolling`) — Chromium headless
com emulação de toque não reproduz o comportamento de rolagem do iOS/Android de forma confiável.

---

## 11. Foco e teclado

**[MEDIDO]** Após abrir o painel, li `document.activeElement` em todos os frames (filhos primeiro):

| Fornecedor | Foco vai para | Detalhes do campo |
|---|---|---|
| **Intercom** | `<textarea>` — **foco automático** | `aria-label="Ask a question…"`, `rows=1`, `font-size 14px`, `line-height 21px`, altura **23 px** |
| **LiveChat** | `<textarea>` — **foco automático** | `aria-label="Write a message…"`, `rows=2`, `border-radius 32px`, altura **46 px** |
| **Crisp** | `<textarea>` — **foco automático** | `placeholder="Escreva sua mensagem..."` (pt-BR automático), `tabindex="0"`, `font-size 13,6px`, altura **18 px** |
| **Chatwoot/ChatSPX** | não observado na sessão medida | — |

Três de três dos que abriram com composer visível **focam o campo sozinhos ao abrir**. Isso é
convergência de mercado, não estilo.

### Shift+Enter e crescimento do campo

**[MEDIDO]** Digitei `teste`, pressionei `Shift+Enter` e medi a altura antes/depois:

| Fornecedor | Antes | Depois | Cresceu | Valor após |
|---|---|---|---|---|
| **Intercom** | 23 px | 44 px | +21 px (= exatamente 1 `line-height`) | `"teste\n"` |
| **Crisp** | 18 px | 36 px | +18 px (= 1 `line-height`) | `"teste\n"` |
| **LiveChat** | 46 px | 110 px | **+64 px** | `"teste\n"` |

Todos: `Shift+Enter` quebra linha e **não envia**; o campo cresce (auto-grow) e `resize: none` em todos.
O crescimento do LiveChat (+64 px para uma linha de 21 px) é desproporcional. [MEDIDO]

**[NÃO VERIFICADO]** `Enter` sozinho envia nos três concorrentes. Não testei porque testar significa
**mandar uma mensagem para o atendimento real** de empresas terceiras. **[INFERÊNCIA]** Como
`Shift+Enter` está implementado explicitamente como quebra de linha nos três, o par convencional
(`Enter` envia) é a leitura natural.

**No nosso, dá para afirmar por código.** [FATO — `app/javascript/widget/components/ChatInputWrap.vue:94`]
```js
handleEnterKeyPress(e) {
  if (e.keyCode === 13 && !e.shiftKey) { … }   // Enter envia; Shift+Enter quebra linha
}
```
Dois detalhes que aparecem na leitura: o listener é registrado em **`document`** (`addEventListener('keypress', …)`,
linha 74) e não no campo, e usa **`keypress`**, evento marcado como obsoleto e com comportamento
inconsistente para teclas não imprimíveis e para IME (relevante para teclado de celular e para quem
digita com composição de acentos). E o único `Esc` tratado no widget é
`@keydown.esc="hideEmojiPicker"` — **`Esc` fecha o seletor de emoji, nunca o painel**, o que é
exatamente o que a medição em `www.chatwoot.com` mostrou.

### Esc fecha o painel?

**[MEDIDO]** Painel aberto, `Escape` pressionado, estado do painel comparado antes/depois:

| Fornecedor | `Esc` fecha? |
|---|---|
| **Octadesk** | **sim** (opacidade 1 → 0) |
| **Intercom** | não |
| **Crisp** | não |
| **Chatwoot/ChatSPX** | não |
| **LiveChat** | não |
| **tawk.to** | não |
| **JivoChat** | não |

**Um em sete.** É um buraco de acessibilidade generalizado: um painel modal-ish sobreposto ao conteúdo,
sem saída pelo teclado. Ninguém está fazendo isso bem, o que significa que fazer certo custa pouco e
diferencia.

### Ordem de tabulação

**[MEDIDO]** No Intercom, o `Tab` a partir do documento principal entra no `<iframe>` do messenger e
o percurso interno não é observável de fora — o que é, na prática, o comportamento correto (o foco
entra no widget). Na Leadster (que vive no DOM da página, sem iframe), a ordem observada foi:
`button.nld-opt` ("Sim, começar agora") → `a` ("Políticas de privacidade") → depois **volta para a
página** (`a.link` "acessar material", `button.close-btn` "Fechar headline", menu do site…). **Não há
armadilha de foco (focus trap):** com o painel aberto, o `Tab` sai do chat e passeia pelo site atrás
dele. [MEDIDO]

### Teclado virtual no mobile

**[NÃO VERIFICADO]** Chromium headless com emulação de dispositivo não instancia teclado virtual, e
`visualViewport` não muda. Não é mensurável com o instrumento que usei. O que dá para afirmar por
leitura: o Intercom dimensiona o painel com `100dvw`/`min()` [FATO], unidade dinâmica que existe
precisamente para lidar com barras de UI que aparecem e somem — indício de que trataram o caso.
O nosso SDK usa `height: 100%` e `width: 100%` em `max-width: 667px` [FATO — `sdk.js:242-248`], sem `dvh`.

---

## 12. Som, notificação e o título da aba

### 12.1 Som — quem toca, e o quê

**[MEDIDO]** Com `HTMLMediaElement.play`, `new Audio` e `AudioContext` instrumentados com timestamp e
*stack trace*:

| Fornecedor | Toca som? | Evidência |
|---|---|---|
| **Intercom** | **sim** | `new Audio("https://js.intercomcdn.com/audio/operator.1b2a758a7eb92c631251.mp3")` em `t=13 572,3 ms`, seguido de `.play()` em `t=13 572,7 ms` (`volume: 1`, `loop: false`) — exatamente quando a mensagem do Fin chegou |
| **HubSpot** | **sim** (pré-carrega) | `new Audio("//static.hsappstatic.net/conversations-visitor-ui/static-1.9449/audio/notification.mp3")` em `t=1 271,2 ms`, dentro do iframe, antes de qualquer mensagem |
| **LiveChat** | provável | `new Audio` (src vazio na criação) em `t=360,1 ms` dentro do frame `chat-widget` |
| **Leadster** | **NÃO** | zero ocorrências de `new Audio`/`Audio(` nos 447 946 bytes de `neurolead.min.js` |
| **Crisp, tawk, Octadesk, JivoChat, Chatwoot** | não observado na sessão medida | — |

**Correção que precisa ser dita explicitamente:** na página da Leadster **eu capturei três
`new Audio()`** (em `t≈12 583`, `17 525` e `18 245 ms`). Se eu tivesse parado aí, teria escrito "a
Leadster toca som ao abrir". O *stack trace* mostra a origem real:

```
at new window.Audio  |  at q (https://js.hs-analytics.net/analytics/1786486200000/24435410.js:21:81614)
                     |  at ie (…:21:97940)  |  at ne (…:21:97719)
```

É o **HubSpot Analytics carregado no site da Leadster**, não o widget. A Leadster não emite som.
[MEDIDO — `timeline-leadster3.json`]

### 12.2 O piscar do título — confirmado no código, com os números exatos

**[FATO]** Trecho literal de `cdn.leadster.com.br/neurolead/neurolead.min.js`:

```js
class ls {
  constructor() {
    return ls.instance || (
      this._intervalRef = null,
      this._originalTitle = document.title,
      ls.instance = this,
      document.addEventListener("visibilitychange", () => this._handleVisibilityChange(), !1)
    ), ls.instance
  }
  blink() {
    let t = arguments[0] ?? v.e[neuroleadLanguage].new_message,   // "(1) Nova Mensagem!"
        e = arguments[1] ?? 650,                                   // intervalo, ms
        n = arguments[2] ?? 6e4;                                   // duração total, ms
    if (!document.hidden) return;
    if (this._intervalRef) return;
    const i = this;
    this._intervalRef = setInterval(() => this._changeTitle(t), e);
    setTimeout(() => i._stopBlink(), n)
  }
  _stopBlink()      { clearInterval(this._intervalRef); this._intervalRef = null; document.title = this._originalTitle }
  _changeTitle(t)   { document.title = document.title === this._originalTitle ? t : this._originalTitle }
  _handleVisibilityChange() { document.hidden || this._stopBlink() }
}
```
e o dicionário pt-BR do mesmo arquivo: `new_message: "(1) Nova Mensagem!"`.

**Os números da hipótese estão certos: 650 ms de intervalo, 60 000 ms (60 s) de duração, texto
"(1) Nova Mensagem!".** E três detalhes que só o código revela:

1. **`if (!document.hidden) return`** — só pisca com a aba oculta. Nunca pisca na sua cara.
2. **`if (this._intervalRef) return`** — não reentra; várias mensagens não empilham intervalos.
3. **`visibilitychange` → `_stopBlink()`** — **volta ao título original no instante em que você
   retorna à aba**. Não fica piscando depois de você olhar.

**Ressalva honesta:** o disparo é `cs.blink()` dentro de `updateTooltipMessage()` — ou seja, é acionado
quando o **texto do convite/teaser é atualizado**, não a cada mensagem. Em duas sessões minhas com a
aba em segundo plano (uma mandando a aba para trás em `t=2,68 s` e outra em `t=30,06 s`), **eu não
observei o disparo** [MEDIDO], porque a atualização de tooltip não ocorreu nessas sessões. O
instrumento estava funcionando: validei o `MutationObserver` de `<title>` num teste controlado
(`document.title = '(1) Nova Mensagem!'` → evento registrado em `t=53,2 ms`). Então: **mecanismo
confirmado no código com os parâmetros exatos; disparo não observado em campo nas minhas sessões.**

### 12.3 Notificação do navegador e vibração

**[MEDIDO]** Zero chamadas a `new Notification(...)` e zero a `navigator.vibrate(...)` em **todos** os
alvos, em todas as sessões. Nenhum widget de chat de site pede permissão de notificação nativa.
[INFERÊNCIA] Faz sentido — pedir permissão de notificação em cima do primeiro contato é caro em
confiança, e o piscar do título resolve 90% do problema com 0% de atrito.

---

## 13. `prefers-reduced-motion`

**[FATO]** Varredura em todo o CSS servido:

| Fornecedor | Respeita? | Evidência |
|---|---|---|
| **Intercom** | **sim, no launcher** | `@media (prefers-reduced-motion: reduce) { .intercom-namespace .intercom-with-namespace-4wz414 { transition: none !important; transform: none !important; animation: … none !important; opacity: 1 !important; scale: 1 !important } }` — e **[MEDIDO]** com `reduced_motion: 'reduce'` o `transition` computado do launcher vira literalmente `none` |
| **Intercom** | **não, no painel** | **[MEDIDO]** no mesmo contexto reduzido, o painel manteve `transition: width .2s, height .2s, max-height .2s, transform .3s cubic-bezier(0,1.2,1,…)` |
| **Crisp** | não observado | **[MEDIDO]** launcher e painel com transitions idênticas nos dois modos |
| **Chatwoot/ChatSPX** | **não** | **[FATO]** zero ocorrências de `prefers-reduced-motion` em `app/javascript/widget/` e `app/javascript/sdk/` |
| **Demais** | não observado | — |

**[INFERÊNCIA]** O padrão real do mercado é ignorar. O Intercom é o único que tratou, e tratou pela
metade — o que sugere que foi consertado pontualmente (o launcher, que animava toda hora e incomodava)
em vez de por sistema.

Um detalhe relevante para nós: **a preferência é gratuita de respeitar quando o motion é CSS, e
impossível quando é GIF.** Nosso indicador de digitando é GIF (§5.6); nenhuma media query alcança.

---

## 14. Mobile

**[MEDIDO]** Contexto iPhone (390×844, `is_mobile`, `has_touch`, DPR 2/3, UA iOS 17.5):

| Fornecedor | Launcher em mobile | Painel em mobile |
|---|---|---|
| **Crisp** | 54×54 em (322, 776) — **idêntico ao desktop** | **390×844, tela cheia**, `border-radius: 0`, **sem sombra**, `transition: none` |
| **Intercom** | 48×48 em (322, 776) — **idêntico ao desktop** | não observei o messenger em tela cheia nessa sessão; o que apareceu foi um **cartão de notificação de 390×222 ancorado na base** ("Hi there 👋 You are now speaking with Fin") |
| **Chatwoot/ChatSPX** | não localizado na sessão | por código: `height:100%; width:100%; right:0; top:0` abaixo de 667 px |

**[FATO]** O Crisp declara o comportamento explicitamente:
```css
.cc-165wh[data-full-view="true"] .cc-lk42u .cc-w7v18 {
  height: 100%; width: 100% !important; box-shadow: none !important;
  border-radius: 0 !important; inset: 0 !important; transition: none !important;
}
```
Note o `transition: none !important` no modo tela cheia: **em mobile o Crisp desliga a animação de
tamanho**. [INFERÊNCIA] Faz sentido — animar um retângulo do tamanho da tela inteira é caro e lê como
travamento; em tela cheia o que vale é aparecer.

**Convergência medida:** o launcher **não muda de tamanho** entre desktop e mobile (54→54 no Crisp,
48→48 no Intercom). Ninguém aumenta o alvo de toque no celular, embora 48 px seja o mínimo recomendado
e 54 px seja confortável.

---

## 15. O que é convergente e o que é assinatura de um só

### Convergente (o mercado inteiro faz igual)

1. **Duração entre 100 e 300 ms** para abrir/fechar painel. [MEDIDO em 8 fornecedores]
2. **Canto inferior direito, 20–24 px de margem**, `z-index` no teto (2 147 483 000+ em Intercom,
   Chatwoot; 2 147 483 646/7 em JivoChat). [MEDIDO]
3. **Painel de ~400 px de largura** — Intercom 400, Crisp 400, Chatwoot 400, LiveChat 420,
   Leadster 420, Octadesk 349, JivoChat 300–336. [MEDIDO]
4. **Foco automático no campo de texto ao abrir.** 3 de 3 medidos. [MEDIDO]
5. **`Shift+Enter` quebra linha, campo cresce, `resize: none`.** 3 de 3. [MEDIDO]
6. **Indicador de digitando = 3 pontos, ciclo 1–1,3 s, stagger 150–200 ms, 40–50% do ciclo parado.** [FATO]
7. **Sem `scroll-behavior: smooth`, sem `overscroll-behavior: contain`.** Todos em `auto`. [MEDIDO]
8. **Sem `Esc` para fechar** (6 de 7). [MEDIDO]
9. **Sem estados de entrega/leitura.** [MEDIDO/FATO]
10. **Sem `Notification` nativa, sem vibração.** [MEDIDO]

### Assinatura de um fornecedor só

| Assinatura | De quem | Por que é dele |
|---|---|---|
| Overshoot no painel (`cubic-bezier(0, 1.2, 1, 1)`) + `opacity 83ms` desacoplada do `transform 300ms` | **Intercom** | único que separa "aparecer" de "mover" |
| `scale(1.1)` no hover e `scale(0.85)` no press, com curvas distintas (250 ms vs 134 ms) | **Intercom** | único com estado `:active` real |
| Pontos que **encolhem** (`scale(0.5)`) em vez de saltar | **Leadster** | ninguém mais faz |
| Selo "online" que estoura a 150% e pisca branco, 1 s depois da entrada | **Leadster** | encenação de presença em 15 px |
| Piscar do título com parâmetros e desligamento no `visibilitychange` | **Leadster** | único do corpus |
| `octaWaRadar` — pulso infinito de 2,4 s no launcher | **Octadesk** | único "chamar atenção" contínuo |
| Painel no **DOM da página** em vez de iframe | **Crisp** | escolha arquitetural rara |
| `transition: none !important` no modo tela cheia | **Crisp** | único que desliga motion em mobile de propósito |
| Fechar **mais lento** que abrir (100 → 150 ms) | **Crisp** | contraria a intuição do mercado |
| Delays negativos no typing (−1,1 s / −0,9 s) | **tawk.to** | truque para não esperar o 1º ciclo |
| Painel pré-renderizado **fora da viewport** (y = 900) e trazido para dentro | **JivoChat** | evita custo de montagem |
| Rotação no launcher ao esconder (`rotate(-30deg)` / `rotate(45deg)`) | **Chatwoot** | ninguém mais gira o botão |

---

## 16. Onde o ChatSPX está hoje — comparação direta

Tudo abaixo é **[FATO]**, lido de `app/javascript/sdk/sdk.js` e `app/javascript/widget/`, e cruzado com
a medição de `www.chatwoot.com` (mesma base).

| Item | ChatSPX/Chatwoot | Melhor do corpus |
|---|---|---|
| Abertura do painel | `opacity 200ms linear` + `transform 250ms linear` | Intercom: `opacity 83ms ease-out` + `transform 300ms cubic-bezier(0,1.2,1,1)` |
| Easing | **`linear` e `ease` apenas** — nenhum `cubic-bezier` no widget | Intercom usa 4 curvas distintas por gesto |
| Hover do launcher | só `box-shadow` (0,16 → **0,40** de opacidade) | Intercom `scale(1.1)` em 250 ms |
| Press do launcher | **nenhum estado `:active`** | Intercom `scale(0.85)` em 134 ms |
| Esconder o launcher | `translateX(8px) scale(.75) rotate(-30deg)` em 300 ms | — (só nós giramos) |
| Entrada de mensagem | **nenhuma animação** | Intercom 300 ms com espera embutida |
| Indicador de digitando | **GIF** (`typing.gif`), largura máx. 2,4 rem | Octadesk: 7 px, 1,2 s `ease-in-out`, stagger 150 ms, em CSS |
| Estado "enviando" | `opacity: 0.6`, sem transição | ninguém faz melhor |
| Reenvio em falha | **sim**, com ícone `arrow-clockwise` | só o tawk tem algo parecido |
| Entregue / lido | não existe | ninguém tem |
| Scroll ao abrir | vai ao fim (instantâneo) | igual ao mercado |
| Scroll em mensagem nova | **força o fim sempre**, mesmo lendo histórico | — |
| Preservar posição ao carregar histórico | **sim, implementado corretamente** | acima da média |
| Botão "descer" | não existe | não localizado no CSS servido de nenhum dos medidos |
| `Esc` fecha | não | só Octadesk |
| `prefers-reduced-motion` | **não** (zero ocorrências) | Intercom, parcialmente |
| Mobile | `height:100%; width:100%` abaixo de 667 px, sem `dvh` | Crisp: tela cheia + `transition:none`; Intercom: `100dvw` + `min()` |
| Som | não observado | Intercom (`operator.mp3` ao receber) |
| Piscar do título | não existe | Leadster (650 ms / 60 s) |
| Teaser proativo | não observado no widget | Leadster aos 10 s, tawk aos 6,4 s |

**Onde já estamos bem:** optimistic UI com reenvio em falha, preservação de posição de scroll ao
paginar histórico, e um painel de 400 px alinhado com o padrão do mercado. Nada disso precisa mudar.

**Onde estamos claramente atrás:** ausência total de curvas de easing (tudo `linear`/`ease`), ausência
de feedback de toque no launcher, ausência de animação na entrada de mensagem, indicador de digitando
em raster, e nenhum tratamento de `prefers-reduced-motion`.

---

## O QUE ISSO SIGNIFICA PARA O REDESENHO DO CHATSPX

Recomendações, sem código de implementação. Ordenadas por relação entre impacto percebido e esforço.

### A. Adotar — é consenso de mercado e nós não temos

1. **Uma curva única da casa, e usá-la em tudo.** Hoje o widget mistura `linear` e `ease` sem critério.
   O mercado que parece caro (Intercom) escolheu curvas por gesto: entrada rápida com desaceleração,
   saída seca. Definir *uma* curva de entrada e *uma* de saída, e proibir `linear` para movimento, é a
   mudança de maior efeito por menor custo do documento inteiro. `linear` só se justifica para
   opacidade pura e rotação contínua.

2. **Desacoplar opacidade de movimento na abertura do painel.** O padrão do Intercom (opacidade em
   ~80 ms, transform em ~300 ms) faz o painel parecer instantâneo *e* fluido ao mesmo tempo. Hoje
   fazemos 200 ms de opacidade contra 250 ms de transform — praticamente juntos, o que produz meio
   painel fantasma durante toda a animação.

3. **`transform-origin` no canto do launcher.** O painel deve crescer de onde o usuário clicou. É uma
   linha de CSS e muda a leitura de causa e efeito.

4. **Estado de toque no launcher (`:active`).** Um `scale` para baixo entre 0,85 e 0,95, em ~120 ms.
   Somos hoje o único caso do corpus em que apertar o botão não produz nenhuma resposta visual.

5. **Trocar o `typing.gif` por CSS.** Isso destrava quatro coisas de uma vez: cor da marca, tema
   escuro, `prefers-reduced-motion` e nitidez em qualquer DPR. O desenho de referência é o da Octadesk
   (que é o do WhatsApp): 3 pontos de ~7 px, `gap` ~4 px, ciclo ~1,2 s `ease-in-out`, stagger 150 ms,
   salto curto (~0,5× o diâmetro) somado a opacidade 0,5 → 1. Evitar o salto de 2× o diâmetro do tawk.

6. **Animar a entrada da mensagem.** ~250 ms, deslocamento pequeno (8–15 px) mais opacidade. O truque
   do Intercom — metade do keyframe parada no estado inicial — dá um atraso natural sem precisar
   coordenar `animation-delay` entre bolhas.

7. **`prefers-reduced-motion`.** Nenhum concorrente medido faz isso direito. É barato, é correto, e
   num mercado onde 6 de 7 ignoram, é diferenciação real além de acessibilidade.

### B. Fazer diferente — onde o mercado inteiro é fraco e dá para ganhar

8. **`Esc` fecha o painel, e o foco volta para o launcher.** Seis de sete concorrentes não fecham com
   `Esc`. Junto disso vale considerar o *focus trap* enquanto o painel está aberto: hoje (na Leadster,
   que também vive no DOM) o `Tab` sai do chat e passeia pelo site. Como nosso painel é iframe, metade
   do problema já está resolvida — falta a saída pelo teclado.

9. **Estados de entrega no estilo mensageiro.** Nenhum concorrente medido tem ✓/✓✓. No Brasil, a
   referência mental de conversa é o WhatsApp, e o tick é o sinal de que a mensagem *saiu*. Já temos a
   metade difícil (optimistic UI + reenvio); falta a leitura visual. Sugestão de direção: substituir o
   `opacity: 0.6` do estado "enviando" por um indicador discreto que não apague o texto — texto
   translúcido é lido como "erro", não como "em trânsito".

10. **Botão "descer" com contador.** Não localizei nada equivalente no CSS servido de nenhum dos sete fornecedores medidos (busquei por `scroll-to-bottom`, `jump-to`, `unread` em cada folha) — **[INFERÊNCIA]**, já que um botão renderizado condicionalmente pode existir em JS sem classe estática. Combina com o conserto do item 11 e resolve o caso
    "cheguei mensagem enquanto eu lia".

11. **Corrigir o scroll forçado.** Hoje `updated()` chama `scrollToBottom()` a toda mudança de tamanho
    da conversa, sem checar a posição do usuário. A convenção correta: só rolar automaticamente se o
    usuário já estava no fim (com uma margem de tolerância); caso contrário, mostrar o botão "descer".

12. **Considerar `overscroll-behavior: contain` na lista.** Ninguém do corpus faz, e o efeito de
    "rolei o chat e a página atrás rolou junto" é um incômodo real, especialmente em mobile.

### C. Evitar — motion que irrita

13. **Loop infinito de "chamar atenção" no launcher** (o `octaWaRadar` de 2,4 s da Octadesk). Um pulso
    que nunca para vira ruído periférico em segundos e não pode ser desligado pelo usuário. Se for
    preciso chamar atenção, o modelo é a Leadster: **uma** encenação de 500 ms, uma vez, e silêncio.

14. **Saída lenta.** O `all .8s cubic-bezier(1,.5,.8,1)` do tawk deixa o painel meio segundo a mais na
    tela depois de o usuário ter decidido sair. Saída no mesmo intervalo da entrada, ou levemente maior;
    nunca 3×.

15. **Salto grande no indicador de digitando.** Subir 2× o diâmetro do ponto (tawk) transforma um
    estado de espera em animação chamativa dentro de uma conversa.

16. **Auto-abrir o painel aos 18,6 s.** É a aposta da Leadster e é agressiva: ocupa 420×370 px da tela
    sem pedir licença. Se formos por caminho proativo, o teaser (que é pequeno, dispensável e reversível)
    é o instrumento certo — e o tempo do mercado para ele é **6–10 s**, não 18.

17. **Animar o painel em tela cheia no mobile.** O Crisp desliga a transição explicitamente nesse modo.
    Animar tamanho num retângulo de tela cheia é caro e lê como travamento.

### D. Decisões que ficam em aberto para o Walisson

- **Som ao receber mensagem.** Intercom e HubSpot tocam; Leadster não. É reversível e barato, mas é
  decisão de produto (e precisa de controle do usuário).
- **Piscar o título da aba.** O mecanismo da Leadster (650 ms, 60 s, para no `visibilitychange`) é
  bem construído e verificado; a pergunta é se queremos esse nível de insistência.
- **Teaser proativo no widget.** Hoje não temos. Se entrar, o parâmetro de mercado medido é 6–10 s
  após o carregamento, com saída em `pop-out` de ~300 ms.

---

## Apêndice A — Como reproduzir

Instrumentação e dados brutos ficaram fora do repositório, em
`/tmp/claude-1001/-home-chatwoot-chatwoot/baa55442-4781-4484-93c1-40a2baff555a/scratchpad/motion/`:

| Arquivo | O que faz |
|---|---|
| `probe_js.py` | script injetado em todos os frames: recorder rAF, `getAnimations()`, dump de CSS, patches de áudio/título/notificação com stack |
| `recon.py` | varredura inicial de 30 URLs — quem serve widget e onde ele vive |
| `deep.py` | medição completa: CSS antes/depois, launcher, hover, press, abertura, animações por frame |
| `inter.py` | interação: abrir → medir painel → foco → Tab → Shift+Enter → `Esc` → fechar |
| `timeline.py` | linha do tempo desde a navegação, com aba mandada para segundo plano (título/som) |
| `csstext.py`, `kfhunt.py` | extração de CSS e `@keyframes` de todos os frames e shadow roots |
| `serie.py`, `resumo.py`, `cssan.py` | análise das séries e das folhas coletadas |

Exemplo de execução (Chromium headless, sem login):
```
python3 inter.py '{"name":"intercom","url":"https://www.intercom.com/","rootSel":"div[class*=intercom-with-namespace]","settle":10000}'
python3 timeline.py '{"name":"leadster","url":"https://www.leadster.com.br/","dur":75000,"bgAt":2500}'
curl -A "Mozilla/5.0" https://embed.tawk.to/_s/v4/app/6a79567aaa5/css/max-widget.css
```

## Apêndice B — Screenshots

Em `plano/estudo-chat-web/frontend/shots/`:

| Arquivo | Conteúdo |
|---|---|
| `intercom-desktop-open.png` | painel do Fin aberto, 400×704, com composer focado |
| `intercom-desktop-i-hover.png` e `intercom-desktop-i-press.png` | launcher em `scale(1.1)` e `scale(0.85)` |
| `intercom-mobile-i-open.png` | cartão de notificação de 390×222 na base, em mobile |
| `leadster-desktop-closed.png` | painel auto-aberto com "Ana - Leadster / Online agora" |
| `leadster-timeline-t*ms.png` | sequência cronometrada: avatar → teaser → auto-abertura |
| `crisp-desktop-i-open.png` | painel 400×730 com 4 quick replies e "Respostas por hugo" |
| `crisp-mobile-i-open.png` | painel em tela cheia, sem raio e sem sombra |
| `tawk-desktop-open.png` | launcher com selo "We Are Here!" e teaser "Psst, this is clickable…" |
| `tawk-desktop-i-open.png` | painel do Apollo (IA) com 4 quick replies |
| `chatwoot-desktop-open.png` | nosso upstream: painel 400×640 e o X girado |
| `chatwoot-desktop-launcher-hover.png` | o hover que só muda a sombra |
| `zendesk-desktop-i-open.png` | launcher preto 64×64; painel não abriu na sessão |

---

*Levantamento por medição direta em 11/08/2026. Onde não consegui medir, está escrito "não verificado".*
