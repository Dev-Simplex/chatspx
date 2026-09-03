# Onda 5 — trilha COMPOSER, HEADER E ESTADOS

Worktree: `/home/chatwoot/chatwoot-o5-composer` · branch `o5-composer` · base `e0ae8e5759`
(`redesenho-integra`) · 18/08/2026

Blocos: **2.06** (header), **2.05** (composer), **2.07** (estados), **2.09** (mobile), **2.11**
(Esc/inert), **2.15** (idempotência), **2.16** (fila offline).

Escrito conforme avanço. Cada bloco traz: o que a base tinha (medido), o que foi feito, o mecanismo
que executa o aceite, e o **resultado real** — inclusive quando ele é vermelho.

---

## 0. O terreno, medido antes da primeira linha

| O que | Estado medido |
|---|---|
| O worktree | **não existia**. Criado com `git worktree add … -b o5-composer redesenho-integra`, e sem `node_modules` — `pnpm install --frozen-lockfile` (lockfile idêntico ao das outras trilhas, conferido por `md5sum`) |
| `widget/ui/` (bloco **2.01**) | **não existe na base**. Confirma o que o coordenador disse: os 13 primitivos estão sendo escritos agora, por outra trilha |
| `--w-*` (bloco 1.01) | presentes; `text-w-on-brand` já existe como utilitária e já é usada em `UserMessageBubble.vue:24` |
| `tailwind.widget.config.js` | `content` restrito, mas `./app/javascript/widget/**/*.vue` **cobre** `widget/ui/` — diretório novo ali não precisa de entrada nova |
| `ChatHeader.vue` | 63 linhas · `<header>` sem `h1` (título era `<span>`) · 4 usos de branco cravado · avatar `rounded-full` · botão de voltar `px-2`, sem piso de toque |
| `ChatHeaderExpanded.vue` | 57 linhas · `<h2>` para o título da tela inicial · `text-white` e `text-white/80` |
| `HeaderActions.vue` | 134 linhas · 3 botões com `aria-label` (bom, veio do 1.06) e ícones `text-white` |
| `ViewWithHeader.vue` | 144 linhas · **sem `<main>`** |
| Snapshots | nenhum cobre o cabeçalho (só `Spinner` e `DateSeparator`) — não há régua visual a reler aqui |

---

## 1. Bloco 2.06 — o cabeçalho ✅

**Aceite (§2.2):** *"Exatamente 1 `h1`; nenhum `text-white`; alvos ≥ 44×44 em 375 px"*, mais o que a
linha do bloco pede: 56/96, avatar 32 raio 6, ações 40/44, `<main>`, status com rótulo textual.

### 1.1 O que foi feito

| Arquivo | O quê |
|---|---|
| `ChatHeader.vue` | `<span>` do título vira **`<h1>`** (com `tabindex="-1"`, que o 2.05 vai usar para levar o foco); branco cravado → `text-w-on-brand`; avatar `rounded-md`; voltar 44×44 (40 acima de 768) com `aria-label`; `min-h-14` |
| `ChatHeaderExpanded.vue` | `<h2>` → **`<h1>`**; branco cravado → `text-w-on-brand` (+ `opacity-80` no corpo); avatar `rounded-md`; `min-h-24` |
| `HeaderActions.vue` | 3 ícones → `text-w-on-brand`; os 3 botões ganham 44×44 no toque e 40×40 acima de 768 |
| `ViewWithHeader.vue` | `<router-view>` passa a viver dentro de **`<main>`** |
| `i18n/{pt_BR,en}.json` | `A11Y.BACK` — o botão de voltar era só-ícone e não tinha nome acessível |

**Um `h1` por tela, e não um `h1` no app inteiro.** Os dois cabeçalhos são `v-if` mutuamente
exclusivos em `ViewWithHeader.vue`, então cada um ter o seu mantém a promessa "exatamente 1" em
qualquer tela — e é o que faz o aceite 6 do bloco 2.05 (foco no `h1` ao abrir na tela inicial) ser
possível.

**O status deixou de ser só cor.** O ponto era `bg-white/80` quando online e `hidden` quando offline
— informação por cor e por ausência, as duas invisíveis para leitor de tela (SC 1.4.1). Agora ele
existe nos dois estados, com `role="img"` e `aria-label` vindo das strings que já existiam
(`TEAM_AVAILABILITY.ONLINE` / `.OFFLINE`), em pt-BR e en.

**A cor sobre a marca é derivada, nunca cravada.** `--w-on-brand` é calculado por luminância no
servidor (bloco 1.02). Cravar branco quebra toda inbox de marca clara — e é justamente o caso que a
medição usa (§1.3).

### 1.2 Mecanismo

Dois arquivos, e a divisão entre eles é a lição da trilha anterior:

* `components/specs/header.spec.js` — **10 exemplos** de marcação e tradução: quantos `h1`, o texto
  deles, o rótulo do ponto nos dois estados, `<main>` uma vez só envolvendo o `router-view`, e a
  varredura textual por `text-white`/`bg-white` nos quatro arquivos.
* `components/specs/browser/header-geometry.check.mjs` — **10 asserções** de geometria e cor
  computada, em Chromium (`chromium.launch()`, sem porta, sem servidor).

### 1.3 Resultado real

**Vermelho antes:** 9 dos 10 exemplos de jsdom falhavam (o único verde já era o `ViewWithHeader`,
que não tinha branco cravado). **Verde depois:**

```
$ npx vitest run …/specs/header.spec.js            10 passed (10)
$ node …/specs/browser/header-geometry.check.mjs   10/10 asserções passaram
  colapsado 60 px (≥56) · expandido 151 px (≥96) · avatar 32x32 raio 6px
  voltar e ação ≥44x44 em 375 px · ação 40x40 em 1024 px
  título rgb(0,0,0) sobre marca #ffe600 · cabeçalho rgb(255,230,0)
$ npx vitest run app/javascript/widget app/javascript/shared
  88 arquivos, 929 exemplos, 0 falhas
$ npx eslint <os 6 arquivos>                       0 problemas
```

**A medição de cor usa uma marca CLARA (`#ffe600`) de propósito.** Com o verde padrão,
`--w-on-brand` é preto e um `text-white` cravado saltaria à vista; com marca clara, o servidor manda
preto e o branco cravado ficaria **invisível sobre o amarelo** — é o caso que quebra a inbox do
cliente, e é o que o teste cobra.

### 1.4 O ponto cego do meu próprio harness, achado por sabotagem

O preâmbulo exige medir o vermelho **restaurando o código antigo no lugar**, não imaginando que o
teste cobre. Fiz isso, e a primeira rodada da sabotagem revelou um defeito **no mecanismo**:

```
SABOTADO: cor cravada (text-white) + alvo sem piso (px-2)
 FAIL  em 375 px, voltar mede ao menos 44x44
9/10 asserções passaram          ← a cor passou! 
```

A cor **não doeu** porque o HTML do harness trazia a classe da linha do título **cravada como
fixture** (`text-w-on-brand` escrito à mão), em vez de extraída do componente. O check media a si
mesmo naquele ponto — exatamente o defeito que ele existe para pegar.

Corrigido: a linha do título ganhou `data-testid="header-title-row"` e o harness passou a extrair a
classe dela do arquivo. Sabotando de novo, agora dói nos dois mecanismos:

```
 FAIL  em 375 px, voltar mede ao menos 44x44
 FAIL  o título usa a cor que o servidor calculou sobre a marca, não branco
        esperado=rgb(0, 0, 0)  recebido=rgb(255, 255, 255)
8/10 asserções passaram
# e o jsdom, com a mesma sabotagem:  1 failed | 9 passed (10)
```

Revertida a sabotagem: 10/10 e 10/10.

---

## 2. Bloco 2.11 — `Esc`, foco e `inert` ✅

**Aceite (§2.2):** *"`Esc` fecha; `document.activeElement` volta ao launcher; nenhum `tabindex`
positivo"* + `inert` no fundo em mobile.

### 2.1 Duas das quatro coisas já existiam — e uma delas não funcionava

| Item | Estado medido na base | O que foi feito |
|---|---|---|
| `Esc` fecha | **existia e falhava no caso mais comum** | listener passou a ser do documento |
| foco volta ao launcher | **existia e funciona** (`bubbleHelpers.js:264`) | **verificado**, não reimplementado |
| `tabindex` positivo | **nenhum** em `widget/`, `sdk/`, `shared/` | travado por varredura |
| `inert` no fundo | **não existia** | novo |

**Por que o `Esc` falhava.** `ViewWithHeader.vue:108` traz `@keydown.esc="closeWindow"` — num
`<div>`. `keydown` só chega ali se o foco já estiver **dentro** dele; logo depois de abrir, o foco
está no `<body>` do iframe, que não é descendente daquele `div`. A tecla não encontrava handler
nenhum. O listener passou a ser do documento (`widget/bridge/closeOnEscape.js`).

**Por que o foco não foi reimplementado.** `handleBubbleToggle` já fazia `chatBubble.focus()` ao
fechar, e funciona porque `toggleClass` roda **antes**: o botão já perdeu `woot--hide` e é focável
quando o `focus()` acontece. Reescrever teria duplicado a lógica — o mesmo erro que a §C.9 do plano
22 alerta sobre o foco do composer. O bloco **verifica**.

### 2.2 O `inert`, e a regra dura que ele carrega

Em celular o painel é tela cheia e a página do cliente continua atrás dele: sem `inert`, Tab e
leitor de tela caminham por links que o visitante não vê. Em **desktop não se aplica** — o widget é
flutuante ali, e congelar a página roubaria de quem só quer ler.

`[DECISÃO]` — **só sai o que este código marcou** (`data-woot-inert`). Se o site já mantinha um
elemento `inert` por conta própria (um menu fechado, um modal dele), fechar o widget **não** pode
desmarcá-lo: seria o widget quebrando a acessibilidade da página que ele visita. Há teste para isso.

### 2.3 Um número novo que não vira o quarto número

`sdk/viewport.js` nasce com `MOBILE_BREAKPOINT = 768`. A base tem **três** valores para a mesma
pergunta — `max-width: 668px` em `IFrameHelper.js:480` e `667px` em três media queries de `sdk.js` —
e um visitante com a janela em 668 px cai num estado que ninguém desenhou. O 2.11 consome do módulo
novo em vez de acrescentar um quarto; **o 2.09 unifica os outros três**, e até lá o estado
intermediário está declarado aqui.

### 2.4 A fiação entra pela mesma porta que a ponte

`registerWidgetListeners` (em `widget/bridge/index.js`) liga a ponte **e** o `Esc`, e o `App.vue`
chama só ela. A razão é testabilidade: registrar o `Esc` direto no `App.vue` funcionaria, mas
deixaria a ligação verificável apenas montando o app inteiro — e **ligação não testada é como
recurso desligado, ninguém percebe**.

### 2.5 Resultado real

```
$ npx vitest run widget/bridge/specs sdk/specs/inertBackground.spec.js   41 passed
$ npx vitest run sdk/specs/toggleAccessibility.spec.js                    7 passed
$ npx vitest run app/javascript/{widget,sdk,shared}   96 arquivos, 1015 exemplos, 0 falhas
$ npx eslint <os 9 arquivos>                          0 problemas
```

**Vermelho medido com o código antigo no lugar**, nos dois níveis: os módulos nasceram com
`Failed to resolve import` (não existiam), e a ligação foi sabotada depois de verde — desligando
`applyInertBackground`, `releaseInertBackground` e `chatBubble.focus()` dentro de
`handleBubbleToggle`, **3 dos 7** exemplos da ligação falharam; revertido, 7/7.

---

## 3. BLOQUEIO REGISTRADO — `WBanner`, `WSkeleton` e `WComposer` são do bloco 2.01

Medido no `22-plano-widget.md:1626` (tarefa **W2.3**, que é o bloco **2.01**), a lista dos 13
primitivos:

> `WButton`, `WIconButton`, `WBubble`, `WAvatar`, `WSurface`, `WSpinner`, `WField`, **`WSkeleton`**,
> `WTypingDots`, **`WBanner`**, **`WComposer`**, `WScrollToBottom`

E a mesma árvore aparece no `:508-509`, dentro de `widget/ui/`.

**Os três estão também nas linhas dos meus blocos** — `WComposer.vue` no 2.05, `WBanner.vue` e
`WSkeleton.vue` no 2.07. O coordenador **já autorizou** que eu escreva o `WComposer.vue`
(contract-first). Para os outros dois **não há autorização**, e escrevê-los seria colocar dois
autores no mesmo arquivo — exatamente o que a regra de um-autor-por-worktree existe para impedir.

**Escalado.** Enquanto não há resposta, sigo pelos blocos que não tocam `widget/ui/`.

---

## 4. Bloco 2.09 — mobile ✅ (parcial, e o que falta está nomeado)

**Aceite (§2.2):** *"767 px fullscreen, 768 flutuante, sem ambiguidade; 0 de 5 alvos passam hoje,
todos passam depois; o `meta viewport` não contém `user-scalable=0` nem `maximum-scale`, e nenhum
input do composer tem `font-size` < 16 px"*.

### 4.1 A ambiguidade era literal

| Onde | Valor | Consequência |
|---|---|---|
| `sdk.js` ×2 | `min-width: 667px` | flutuante |
| `sdk.js` ×1 | `max-width: 667px` | tela cheia |
| `IFrameHelper.js:480` | `max-width: 668px` | `isMobile` para o widget |

Em **667 px exatos as duas media queries casavam** — o pixel tinha as duas geometrias e vencia a
ordem no arquivo. Em **668 px** o CSS já dizia desktop enquanto o JS dizia celular. Agora é um
número só (`sdk/viewport.js`), com faixas **disjuntas**: até 767 tela cheia, de 768 flutuante.

### 4.2 O que mais entrou

* `100dvh`/`100dvw` **com a declaração antiga logo acima** como fallback — `100vh` em celular mede a
  viewport com a barra do navegador recolhida, e o botão de enviar some atrás dela.
* `env(safe-area-inset-*)` — sem isso o composer fica debaixo da barra de gestos do iPhone.
* **O zoom de volta**: `maximum-scale=1, user-scalable=0` saiu do `show.html.erb`. É violação direta
  de **SC 1.4.4 (AA)**, e dentro de um iframe o visitante não tem outra saída.

### 4.3 O que FALTA, e por quê

Duas asserções do aceite dependem do **composer** (bloco 2.05), que depende dos **primitivos**
(bloco 2.01, de outra trilha): *"nenhum input do composer tem `font-size` < 16 px"* e *"0 de 5 alvos
passam hoje, todos passam depois"*. **Não há mecanismo delas aqui porque não há código delas aqui** —
e um teste que fingisse cobri-las seria pior que a ausência.

> A razão histórica do trava-zoom é exatamente o auto-zoom do iOS ao focar campo com fonte < 16 px.
> A correção certa é o tamanho da fonte (2.05) — desligar o zoom de todo mundo era tratar o sintoma
> na pessoa errada.

### 4.4 Mecanismo, em três camadas

```
$ npx vitest run sdk/specs/mobileBreakpoint.spec.js        7 passed
$ rspec spec/views/widgets/show_viewport_spec.rb           4 examples, 0 failures
$ node sdk/specs/browser/mobile-breakpoint.check.mjs       6/6 asserções
     767 → largura 767, raio 0px      768 → largura 400, raio 16px, bottom 104px
$ npx vitest run app/javascript/{widget,sdk,shared}   97 arquivos, 1022 exemplos, 0 falhas
```

Sabotando com os breakpoints antigos: **3 das 6** asserções de geometria falham.

### 4.5 O defeito que os meus dois mecanismos NÃO pegaram

Escrevi um comentário CSS com **crases** dentro da template string `SDK_CSS`. As duas crases
**fecharam a string no meio** e `sdk.js` deixou de ser JavaScript válido.

**Nenhum dos dois mecanismos percebeu** — o spec e o check leem `sdk.js` como **texto**, e texto
quebrado continua sendo texto. Quem pegou foi o `eslint`, por acaso de eu tê-lo rodado.

O spec ganhou um exemplo que **importa o módulo**: com a crase de volta, ele falha com
`Parse failure: Identifier cannot follow number`. É a mesma família da armadilha de canal que o
coordenador descreveu — crase não é decoração em lugar nenhum deste projeto.

---

## 5. O canal de coordenação estava sem coordenador

`orca orchestration ask` respondeu **"ask requires an active supervised Dispatch"**. O preâmbulo
prevê o caso: *"se o relay estiver sem coordenador, escreva tudo no relatório assim mesmo, inclusive
o que você diria por mensagem"*. A pergunta é a da §3 (quem escreve `WBanner`/`WSkeleton`), com as
três saídas que ofereci:

* **(A)** eu escrevo os três em `widget/ui/` pelo contrato, e a trilha 2.01 não os escreve;
* **(B)** a trilha 2.01 escreve, eu consumo, e o 2.07 fica bloqueado até landarem;
* **(C)** eu escrevo **o comportamento** do 2.07 em módulos próprios **fora de `widget/ui/`**, e só
  a casca visual espera os primitivos.

**Segui (C)**, que é a única que não toca arquivo de outra trilha e ainda assim não entrega zero — e
o aceite que mais vale do 2.07 (*"rede cortada 10 s: nada nos primeiros 3 s, faixa depois, composer
utilizável; micro-queda de 1,5 s não mostra nada"*) é **comportamento puro**: não precisa de pixel
nenhum para ser medido.

---

## 6. Bloco 2.07 — estados de verdade ✅ (o comportamento; a casca visual espera o 2.01)

**Aceite (§2.2):** *"Rede cortada 10 s: nada nos primeiros 3 s, faixa depois, composer utilizável;
micro-queda de 1,5 s não mostra nada"*.

### 6.1 O aceite é sobre tempo, então o código dele é sobre tempo

`widget/state/connectionMonitor.js` e `widget/state/loadingGate.js` — **fora de `widget/ui/`**, pela
decisão da §5. A carência de 3 s, o corte de 15 s para "offline" e o limiar de 600 ms do esqueleto
vivem ali, medidos com relógio falso em milissegundos, em vez de espalhados por `setTimeout` dentro
de componente.

| Regra | Valor | Razão |
|---|---|---|
| carência antes de avisar | **3 000 ms** | queda de 1,5 s é o caso comum de quem anda com o celular; faixa que pisca e some assusta sem informar, e ensina a ignorar a faixa quando ela importa |
| vira "offline" | **15 000 ms** | "reconectando" para sempre é mentira |
| esqueleto | **600 ms** | abaixo disso é flash: a tela pisca e a impressão é de defeito |
| `canCompose` | **sempre `true`** | campo desabilitado por rede perde o texto que a pessoa acabou de digitar |

### 6.2 O defeito que o teste pegou — e ele era do meu código

O exemplo *"quedas repetidas não empilham temporizador"* falhou na primeira rodada: cada nova queda
**reiniciava** a carência. Numa rede instável — que é exatamente quando a faixa importa — ela nunca
apareceria. `reportDisconnected` passou a ser **idempotente**: a carência conta da **primeira**
queda.

### 6.3 O watchdog que rodava a cada 15 s sem fazer nada

Medido: `BaseActionCableConnector.js:132` chamava `window.reconnectService.handleRouteSpecificFetch?.()`,
e **`reconnectService` não existe em `app/javascript/widget/`** (zero ocorrências). No widget, o
temporizador acordava a cada 15 s, comparava um carimbo e ia dormir.

Agora existe o gancho `onStaleConnection()` — vazio por padrão, então o dashboard não muda —, e o
widget o sobrescreve para refazer o mesmo trabalho da reconexão.

### 6.4 Mecanismo e resultado real

```
$ npx vitest run widget/state/specs/connectionState.spec.js    12 passed (12)
```

12 exemplos: os quatro tempos do aceite, o composer utilizável em todo estado, a sequência de avisos,
a idempotência, o `destroy`, os três casos do esqueleto e **dois do watchdog com o ActionCable
dublado** — um provando que o gancho é chamado aos 15 s com fluxo silencioso, outro que fluxo
recente **não** dispara nada (o watchdog não é cronômetro cego).

**Sabotagem:** removendo `this.onStaleConnection()` do `BaseActionCableConnector`, 1 dos 12 falha;
revertido, 12/12.

> Um teste que eu **descartei**: a primeira versão do exemplo do watchdog só verificava que o gancho
> *existia* — espelho da implementação, exatamente o que o §10.3 proíbe. Foi trocado pelo que
> instancia o connector e avança o relógio.

### 6.5 O que falta do 2.07, e por quê

A **casca visual** (`WBanner.vue`, `WSkeleton.vue`) é do bloco **2.01** — §3. O comportamento está
pronto e testado; ligar a faixa exige os primitivos.

---

## 7. O 2.01 landou — a primeira corrida contra o código real

`git merge redesenho-integra` trouxe os 13 primitivos de `widget/ui/`. **Um conflito**, nos dois
arquivos de i18n do widget (`pt_BR.json` e `en.json`), e ele era **aditivo e disjunto dos dois
lados**: eu havia acrescentado `A11Y.BACK` (bloco 2.06) e a outra trilha acrescentou o bloco
`CAPTURE`. Resolvido **por união**, com asserção no próprio script de resolução — ele falha se
`CAPTURE` sumir ou se `A11Y.IMAGE_ATTACHMENT` se perder. Escolher um lado teria apagado o trabalho
do outro em silêncio.

**Resultado da primeira corrida — tudo passou, e isso é informação:**

```
$ npx vitest run app/javascript/{widget,sdk,shared}    109 arquivos, 1190 exemplos, 0 falhas
$ node …/header-geometry.check.mjs                     10/10 asserções
$ node …/mobile-breakpoint.check.mjs                     6/6 asserções
```

**Zero divergências de contrato a conciliar.** Vale dizer por quê, para o registro não virar
autoelogio: os blocos que eu entreguei antes do merge (2.06, 2.11, 2.09, 2.07) foram desenhados
**deliberadamente sem depender dos primitivos** — o header mexe em componentes que já existiam, o
`Esc`/`inert` vive no SDK e na ponte, e os estados do 2.07 são módulos de comportamento fora de
`widget/ui/`. A superfície de contrato entre as duas trilhas era, até aqui, **pequena de propósito**.

O contrato de verdade se paga agora, no **2.05**, que é o primeiro bloco meu a consumir os
primitivos. E ali o que encontrei foi favorável:

| O que o `WComposer.vue` real entrega | Como isso casa com o aceite da §C.9 |
|---|---|
| `label` **required** | o campo tem nome acessível por construção |
| slot `actions` independente do campo | enviar e anexar **deixam de ser mutuamente exclusivos** (aceite 1) |
| `@keydown` com `Enter`/`Shift+Enter` | aceite 4 — nenhum `keypress` |
| `text-base` no campo | **16 px**, que é a asserção do 2.09 sobre auto-zoom do iOS |
| `:focus-visible` com `--w-focus-ring-*` | aceite 3 — anel não transparente |

---

## 8. Bloco 2.05 — o composer ✅

**Aceite:** os 8 da §C.9 do plano 22.

### 8.1 O defeito central, e ele era de produto

`showAttachment()` exigia campo **vazio**; `showSendButton()` exigia **texto**. Os dois botões eram
**mutuamente exclusivos**: composer vazio mostrava anexo e nenhum enviar; com texto, enviar e nenhum
anexo. Agora os três controles ficam sempre na tela, e enviar fica **desabilitado em fundo neutro**
quando não há o que enviar.

### 8.2 As cascas

| Arquivo | Antes | Depois | Para onde foi |
|---|:---:|:---:|---|
| `ChatInputWrap.vue` | 199 | **36** | `useComposer` + `WComposer` + `ComposerActions` |
| `ChatFooter.vue` | 166 | **48** | `useConversationFooter` |

Nada de comportamento novo escondido na mudança: é o mesmo código, no lugar onde dá para testá-lo
sem montar a árvore inteira.

### 8.3 DIVERGÊNCIA DE CONTRATO com o 2.01 — resolvida sem tocar no primitivo

**`WComposer` emite `submit` no `Enter` sem olhar `isComposing`.** Digitar "café" com IME (teclado de
celular, dead key) passa por um `Enter` que **confirma a composição** — e a mensagem sairia pela
metade. É o aceite 5 do meu bloco, e o primitivo não o satisfaz.

A regra é não alterar o primitivo e não criar alias. Então **o consumidor se defende**: `useComposer`
mantém uma bandeira de composição (`compositionstart`/`compositionend`, que chegam ao `textarea` pelo
`$attrs` do primitivo) e **ignora `submit` enquanto a composição está aberta**.

> **Para o coordenador conciliar:** a correção definitiva é `WComposer` checar `event.isComposing` no
> próprio `aoTeclar`. Enquanto isso não acontece, **todo** consumidor do primitivo precisa repetir
> esta defesa — e o próximo provavelmente não vai saber que precisa.

### 8.4 O aceite 6 — verificar, não reimplementar

A §C.9 alerta: *"o foco ao abrir JÁ EXISTE — verificar, não reimplementar"*. A lógica mudou de lugar
(`ChatInputWrap` → `useComposer`) e **não foi reescrita**. A metade que faltava é a **tela inicial**,
onde o composer nem está montado: ali o foco vai para o **`h1` do cabeçalho**, que ganhou
`tabindex="-1"` no bloco 2.06. Focar campo naquela tela abriria o teclado do celular e comeria metade
da tela antes de o visitante ler qualquer coisa.

### 8.5 Mecanismo e resultado real

```
$ npx vitest run …/specs/composer.spec.js                    12 passed (12)
$ node …/specs/browser/composer-geometry.check.mjs            7/7 asserções
     anexo, emoji e enviar ≥ 44x44 em 375 px
     anel de foco: largura 2px, cor rgb(29,130,74), estilo solid
     fonte do campo: 16px  ← é o que dispensa o trava-zoom removido no 2.09
$ npx vitest run app/javascript/{widget,sdk,shared}   110 arquivos, 1202 exemplos, 0 falhas
```

O anel de foco merece nota: `15 §A5.3` mediu `rgba(0, 0, 0, 0) solid 2px` — um anel de 2 px
**transparente**, que passa em qualquer teste de marcação e é invisível para quem navega por teclado.
Por isso a asserção é sobre a **cor computada**, não sobre a existência da classe.

**Sabotagem:** removendo a proteção de IME, 1 dos 12 exemplos falha; revertido, 12/12.

---

## 9. Estado da trilha

| Bloco | Estado | Mecanismo |
|---|:---:|---|
| **2.06** header | ✅ | 10 jsdom + 10 Chromium |
| **2.11** Esc/inert/foco | ✅ | 8 + 7 exemplos, com sabotagem da fiação |
| **2.09** mobile | ✅ **parcial** | 7 vitest + 4 rspec + 6 Chromium — faltam as 2 asserções que dependiam do composer, agora destravadas |
| **2.07** estados | ✅ **parcial** | 12 exemplos; casca visual espera `WBanner`/`WSkeleton` (2.01) |
| **2.05** composer | ✅ | 12 jsdom + 7 Chromium |
| **2.15** idempotência | ⏳ pendente | — |
| **2.16** fila offline | ⏳ pendente | depende do 2.07, que está pronto no comportamento |

**Commits** (locais, um por bloco, com o id na mensagem):

```
404bcd7680  feat(2.06)   14822b4cd6  feat(2.11)   144d56efb8  feat(2.09, parcial)
862e4f3e8b  feat(2.07)   5d8dc981ec  merge 2.01   97dd827024  feat(2.05)
```

---

## 10. Bloco 2.16 — fila offline ✅

**Aceite (§2.2):** *"3 mensagens digitadas offline chegam em ordem na volta; nenhum evento de
digitando em lote"*.

A fila guarda **intenção**, nunca estado transitório. *"Enviar esta mensagem"* continua verdadeira
dez segundos depois; *"estou digitando"* não — chegar atrasado é pior que não chegar, e num lote o
agente veria três avisos de quem digitou uma vez. `typing_on`, `typing_off` e `presence_update` são
recusados **por nome**, e quem enfileira fica sabendo pelo `onDrop`, em vez de o evento sumir calado.

**A ordem é o aceite**, então a drenagem é **sequencial**: um `Promise.all` entregaria as três ao
mesmo tempo e o servidor as ordenaria por acaso. `no-await-in-loop` está desligado numa linha, com a
razão escrita acima dela — aqui o laço **é** a funcionalidade.

Falha no meio **para** a fila e devolve o restante intacto, começando pela que falhou: entregar a
terceira tendo perdido a segunda seria pior que não entregar nenhuma.

**Mecanismo:** 7 exemplos. O da ordem faz cada envio demorar **menos** que o anterior — com drenagem
paralela a terceira chegaria primeiro e o teste acusaria. Sabotando com `Promise.all`, **3 dos 7**
falham.

---

## 11. Bloco 2.15 — idempotência de envio ✅

**Aceite (§2.2):** *"Retry de rede com a mesma chave não duplica mensagem"*.

### 11.1 O caso real não é clique duplo

É a mensagem **chegar** ao servidor e a **resposta se perder na volta** — túnel, elevador, troca de
antena. O widget não tem como saber que deu certo, então reenvia.

### 11.2 A chave já viajava, e não protegia nada

Medido: `echo_id` já ia do widget ao servidor (`base_controller.rb:94`), mas é `attr_accessor` no
modelo (`message.rb:89`) — **virtual**, some depois do broadcast. Agora ele é gravado em `source_id`
(coluna **e índice que já existiam**, então **sem migration**) e conferido antes de criar.

O escopo da busca é a **conversa**: a mesma chave em outra conversa é outra mensagem, não um retry.
E **sem chave o comportamento de hoje continua** — há teste para isso, porque cliente antigo em
cache não pode mudar de comportamento por causa deste bloco.

### 11.3 O fallback que não é enfeite

`crypto.randomUUID` exige **contexto seguro**, e o widget roda dentro do site do cliente. Sem
fallback, um cliente ainda em `http` mandaria `undefined` em toda mensagem — **todas colidiriam entre
si**, que é o oposto do que o bloco faz. Há teste que remove `randomUUID` e exige chave mesmo assim.

### 11.4 Mecanismo, resultado e uma nota de medição

```
$ rspec spec/controllers/api/v1/widget/messages_idempotency_spec.rb   6 examples, 0 failures
$ npx vitest run widget/api/specs/idempotencia.spec.js                4 passed
$ rubocop <os 3 arquivos ruby>                                        no offenses
```

**Vermelho antes em 3 dos 6** — os três do comportamento novo; os outros três já passavam porque são
o comportamento atual, que o bloco preserva.

> **Nota de medição:** a primeira versão do spec contava `conversation.messages` inteiro e acusou
> *"changed by 3"* — um POST mexe em três linhas, por causa das mensagens automáticas do fluxo. O
> spec passou a contar a mensagem **`incoming` com aquele conteúdo**, que é o que o aceite trata.
> Contar a coisa errada teria dado vermelho eterno num código certo.

**Duas falhas pré-existentes** em `spec/controllers/api/v1/widget/`
(`conversations_controller_spec.rb:272` e `integrations/dyte_controller_spec.rb:37`), medidas **com
este código fora do caminho** (`git checkout HEAD --` nos dois arquivos, rodar, restaurar). Não têm
relação com idempotência.

---

## 12. Fechamento da trilha

### 12.1 Os sete blocos

| Bloco | Estado | Mecanismo | Sabotagem |
|---|:---:|---|---|
| **2.05** composer | ✅ | 12 jsdom + 7 Chromium | IME → 1/12 falha |
| **2.06** header | ✅ | 10 jsdom + 10 Chromium | cor+alvo → 2 falhas |
| **2.07** estados | ✅ comportamento | 12 exemplos | watchdog → 1/12 falha |
| **2.09** mobile | ✅ | 7 vitest + 4 rspec + 6 Chromium | breakpoints → 3/6 falham |
| **2.11** Esc/inert | ✅ | 8 + 7 exemplos | fiação → 3/7 falham |
| **2.15** idempotência | ✅ | 6 rspec + 4 vitest | vermelho antes em 3/6 |
| **2.16** fila offline | ✅ | 7 exemplos | `Promise.all` → 3/7 falham |

**Commits locais, um por bloco, com o id na mensagem** — nenhum `push`, PR ou deploy:

```
404bcd7680 feat(2.06)   14822b4cd6 feat(2.11)   144d56efb8 feat(2.09, parcial)
862e4f3e8b feat(2.07)   5d8dc981ec merge(2.01)  97dd827024 feat(2.05)
7e6920f40b feat(2.16)   3ab2ae88f9 feat(2.15)
```

### 12.2 O que ficou pendente, com o número do bloco que falta

1. **Casca visual do 2.07** — `WBanner.vue` e `WSkeleton.vue` são dois dos 13 primitivos do **2.01**.
   Eles agora **existem** (chegaram no merge), então a ligação é um bloco curto: o comportamento já
   está pronto e testado.
2. **Duas asserções do 2.09** (`font-size` ≥ 16 px no composer e os 5 alvos) — **destravadas** pelo
   2.05: o `composer-geometry.check.mjs` já mede as duas (16 px e ≥ 44×44). Falta consolidá-las no
   arquivo do 2.09, o que é reorganização de teste, não código novo.

### 12.3 A divergência de contrato que preciso que alguém concilie

**`WComposer` não checa `event.isComposing` antes de emitir `submit`.** Está contornado no meu
consumidor (§8.3), e a correção definitiva é no primitivo — enquanto não for, **todo** consumidor
precisa repetir a defesa, e o próximo não vai saber que precisa.

### 12.4 Três coisas que os testes acharam, e que valem além desta trilha

1. **Meu próprio harness tinha ponto cego** (§1.4): o check de cor do header media uma classe
   **cravada como fixture**, e a sabotagem passava verde. Extração por `data-testid` resolveu.
2. **Crase dentro de template string** (§4.5): fechou a `SDK_CSS` no meio e `sdk.js` deixou de ser JS
   válido. **Os dois mecanismos do bloco liam o arquivo como texto** e não viram — quem pegou foi o
   eslint. O spec ganhou um exemplo que **importa** o módulo.
3. **Carência reiniciando** (§6.2): cada nova queda de rede reiniciava os 3 s, então numa rede
   instável a faixa **nunca** apareceria — exatamente quando ela importa.

---

## 13. O que eu diria por mensagem (o canal fechou)

`orca orchestration send --type worker_done` respondeu **"Dispatch capability is revoked"**, depois
de o `ask` já ter respondido **"requires an active supervised Dispatch"** mais cedo. O preâmbulo diz
que, sem coordenador no relay, o conteúdo da mensagem vai para o relatório — é o que segue.

**Estado:** os sete blocos entregues, em commits locais, um por bloco, com o id na mensagem. Nenhum
`push`, PR, deploy ou restart. Nenhuma migration rodada em banco que não fosse o de teste dedicado
(`chatwoot_test_o5_composer`).

**Números finais, medidos depois do último commit:**

```
$ npx vitest run app/javascript/{widget,sdk,shared}    112 arquivos, 1213 exemplos, 0 falhas
$ node …/header-geometry.check.mjs                     10/10
$ node …/composer-geometry.check.mjs                    7/7
$ node …/mobile-breakpoint.check.mjs                     6/6
$ rspec …/messages_idempotency_spec.rb                  6 examples, 0 failures
$ rspec spec/views/widgets/show_viewport_spec.rb        4 examples, 0 failures
$ eslint / rubocop                                      0 problemas
```

**Cada mecanismo foi conferido nos dois sentidos.** Não há aqui um número que eu só tenha visto
verde: em todos os blocos o código antigo foi restaurado no lugar, o teste doeu, e só então o verde
contou.

**As duas coisas que precisam de decisão de quem coordena:**

1. **Divergência de contrato com o 2.01** (§8.3). `WComposer` emite `submit` no `Enter` sem olhar
   `isComposing`. Contornei no meu consumidor **sem tocar no primitivo**, como manda a regra. A
   correção definitiva é no primitivo — e enquanto não for, **todo** consumidor precisa repetir a
   defesa, e o próximo não vai saber que precisa.
2. **Duas pendências curtas e nomeadas** (§12.2): ligar a casca visual do 2.07 aos `WBanner`/
   `WSkeleton` (que agora existem) e consolidar no 2.09 as duas asserções que o 2.05 destravou —
   ambas já medidas no `composer-geometry.check.mjs`.

**E o que eu não escondi:** duas falhas em `spec/controllers/api/v1/widget/`
(`conversations_controller_spec.rb:272`, `integrations/dyte_controller_spec.rb:37`) são
**pré-existentes**, medidas com o meu código fora do caminho.
