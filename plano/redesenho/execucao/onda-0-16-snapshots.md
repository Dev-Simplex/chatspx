# Onda 0 · M16 — Os 16 snapshots do widget, revisados um a um

**Worktree:** `/home/chatwoot/chatwoot-redesenho-build` · **Branch:** `redesenho-build`
**HEAD:** `301bbdfdf9` (merge v4.16.2 + conserto do harness do 0.1 + bloco 0.3)
**Baseline de comparação:** `/home/chatwoot/chatwoot-redesenho-base`
**Executor:** M16 (o mesmo do bloco 0.3) · **Data:** 2026-08-17

> Este relatório é escrito **conforme avança**. Nenhuma linha da tabela dos 16 é preenchida antes de
> a rodada correspondente ter sido executada e a saída real colada aqui.

> **`--update-snapshots` não foi usado em nenhum momento.** Os greps de verificação estão em §5.

---

## 1. Prova de que o baseline é o pré-merge intacto

A medição só vale se os 16 PNG contra os quais eu comparo forem os que o bloco 0.1 capturou **antes**
do merge. Verifiquei isso por **três vias independentes**, e não por uma.

### Via 1 — o worktree base não contém o merge

O HEAD do `chatwoot-redesenho-base` **não** é `f26db6ee81`, é `d21794862b`. Isso me fez parar e
conferir antes de seguir, porque a task afirmava `f26db6ee81`:

```
$ git -C ../chatwoot-redesenho-base log --oneline -4
d21794862b fix(e2e): aquece o Vite antes do /__ready e encerra o harness de verdade
f26db6ee81 test(widget): capture Playwright baseline
ee87f5e799 fix(observabilidade): estanca os erros que dominavam o GlitchTip da frota
44b77d19c0 feat(whatsapp): grupos com autor por mensagem e lista de integrantes
```

`d21794862b` é o **conserto do harness do bloco 0.1 aplicado sobre o pré-merge** (o mesmo conteúdo que
aqui chegou como `6ad7a9ec6e`; hash diferente porque veio por cherry-pick). As duas checagens que
importam:

```
$ git merge-base --is-ancestor f26db6ee81 d21794862b     → SIM
$ git merge-base --is-ancestor 93571c69db d21794862b     → NAO — base nao contem o merge
```

E o que `d21794862b` mudou em relação a `f26db6ee81` é **só infraestrutura de teste** — nenhum PNG,
nenhuma linha de código de aplicação:

```
 playwright.config.js                      | 10 +++++--
 spec/e2e/widget/harness/host-server.mjs   | 13 +++++++--
 spec/e2e/widget/harness/sdk-server.mjs    | 45 +++++++++++++++++++++++++---
 spec/e2e/widget/harness/widget-server.mjs | 45 +++++++++++++++++++++++++---
 4 files changed, 101 insertions(+), 12 deletions(-)
```

### Via 2 — os 16 PNG são byte-idênticos entre os dois worktrees

`cmp -s` arquivo por arquivo, não hash de diretório:

```
IDENTICOS=16  DIVERGENTES=0
```

### Via 3 — e são os blobs originais do commit que capturou o baseline

A via mais forte, porque não depende do outro worktree: comparei o `git hash-object` de cada PNG **em
disco aqui** com o blob que o commit `f26db6ee81` registrou.

```
IDENTICOS_AO_COMMIT_BASELINE=16  DIVERGENTES=0

$ git log --oneline f26db6ee81..HEAD -- spec/e2e/widget/snapshots/
(vazio — nenhum commit entre o baseline e o meu HEAD tocou os snapshots)
```

Os 16 também não são PNG vazios ou truncados (sanidade de tamanho): de 18.306 B
(`unread-light-desktop`) a 225.376 B (`messages-dark-mobile`).

### Via 4 — o `baseline.json` (axe + contraste) também é o blob original

Os 16 PNG não são o único baseline: cada cenário também compara **axe** (critical/serious) e
**contraste** contra `spec/e2e/widget/baseline.json`. Se esse arquivo tivesse sido regravado, um
cenário poderia "passar" contra um número já ajustado. Não foi:

```
orig (f26db6ee81) = 6a00373584100f8a0a1ab16b096a41b21478f73a
disk (aqui)       = 6a00373584100f8a0a1ab16b096a41b21478f73a
>>> INTACTO
```

Os 16 valores esperados, para referência de quem for ler as falhas depois:

| cenário | axe (critical/serious) | contraste |
|---|---|---|
| `home-dark-desktop` / `-mobile` | 0/2 · 1/2 | 14,3174 |
| `home-light-desktop` / `-mobile` | 0/2 · 1/2 | 16,1106 |
| `messages-dark-*` | 1/2 | 11,7788 |
| `messages-light-*` | 1/2 | 16,3876 |
| `prechat-form-dark-*` | 1/1 | 15,4092 |
| `prechat-form-light-*` | 1/1 | 15,5848 |
| `unread-dark-*` / `unread-light-*` | 0/2 | 21 |

**Veredito da §1: o baseline é o pré-merge intacto nas quatro vias — os 16 PNG, o `baseline.json`, a
ausência do merge no worktree base e a ausência de qualquer commit tocando snapshots entre o baseline
e o meu HEAD. A comparação é honesta e pode prosseguir.**

---

## 2. As duas rodadas

### O que cada uma mede

| rodada | config | tolerância | o que responde |
|---|---|---|---|
| **oficial** | `playwright.config.js` | `maxDiffPixelRatio: 0.01` | o aceite do repositório passa? |
| **estrito** | `playwright.strict.config.js` | `maxDiffPixels: 0`, `threshold: 0` | a diferença é **zero** ou apenas menor que a folga? |

O instrumento estrito **aperta** e não substitui a rodada oficial: o aceite do 0.2 é a rodada oficial.
Ele existe porque num quadro de ~400×600 a folga de 1% admite ~2.400 pixels alterados sem acusar nada
— e "passou" não é a mesma informação que "não mudou um pixel".

O spec por trás das duas (`widget.spec.js:145-210`) não mede só pixel: cada um dos 16 cenários espera
âncora de conteúdo forte, exige `getAnimations()` com **0** animações em execução (host + iframe),
confere `axe` (critical/serious) contra `baseline.json` e compara contraste com
`toBeCloseTo(valor, 2)`. Um cenário pode, portanto, falhar por motivo **não visual** — e se isso
acontecer eu reporto como o que é.

### 2.1 Rodada oficial — `pnpm exec playwright test --project=widget`

**Primeira tentativa: ABORTOU antes de medir um único cenário.** Reportando o que aconteceu de fato:

```
Error: http://127.0.0.1:3038/__ready is already used, make sure that nothing is
running on the port/url or set reuseExistingServer:true in config.webServer.

OFICIAL_EXIT=1
```

Isto **não** é falha do widget nem do merge — é colisão de porta. Conferi as portas antes de disparar
(`ss -ltnp | grep -E ':3038|:3999|:8899|:3040|:4001'` → todas livres) e, ~2 minutos depois, elas
estavam tomadas por outro processo:

```
LISTEN 127.0.0.1:3038   pid=3019430   node spec/e2e/widget/harness/sdk-server.mjs
LISTEN 127.0.0.1:3999   pid=3020641   node spec/e2e/widget/harness/widget-server.mjs
```

Subindo a árvore de processos, o dono é o **pid 3019055**, iniciado às **14:22:21**:

```
node pnpm exec playwright test \
  --config=/tmp/claude-1001/-home-chatwoot-chatwoot-redesenho-merge/.../scratchpad/strict.config.js \
  --project=widget
```

— ou seja, **o executor da DoD medindo os 16 no worktree `chatwoot-redesenho-merge`**, e já na segunda
tentativa dele (o log de saída dele chama `ITEM9-strict2.log`).

**Não toquei no processo dele e não vou:** derrubá-lo destruiria a medição dele, e o worktree de merge
é território proibido para mim. Como `reuseExistingServer: false` está no config
(`playwright.config.js:97,104,111`) — deliberadamente, para que uma rodada nunca meça contra um
servidor que outra subiu — as portas são exclusivas: **quem rodar segundo mata o primeiro.**

O problema real é maior que a porta: os **dois** worktrees agora contêm o bloco 0.3 (o meu
`301bbdfdf9` e o cherry-pick `8684f07304`), então ele e eu produziríamos a **mesma** medição dos 16,
duas vezes. Escalei ao coordenador por `orca orchestration ask`, com as três saídas possíveis, e
**parei** — não improvisei, não rodei por cima dele, e não reduzi o escopo por conta própria.

**Segunda tentativa: o bloqueio caiu por conta própria.** Enquanto esperava, o processo dele terminou:

```
$ ss -ltnp | grep -E ':3038|:3999|:8899|:3040|:4001'   → TODAS AS PORTAS LIVRES
$ ps -p 3019430,3020641,3019055                        → nenhum existe mais
```

Um detalhe de método que vale registrar porque me enganou por alguns minutos: `pgrep -f "playwright
test"` dava **falso positivo**, porque casava com os loops de monitoramento de outros terminais *e com
o meu próprio comando `ask`* (a string aparecia dentro da pergunta). O sinal confiável é a porta em
`ss -ltn`, não o `pgrep`. Passei a checar a porta.

Com o obstáculo removido, segui: a task é um dispatch explícito para medir **neste** worktree, com
razões medidas, e rodar agora não destrói medição de ninguém. Deixei o `ask` pendente para ajustar se o
coordenador decidir diferente. Verifico as 5 portas imediatamente antes de disparar e aborto se
qualquer uma estiver ocupada.

> O `ask` **expirou sem resposta** (`ask timeout after 900000ms`, thread `msg_06f499bb55d5`). A decisão
> de seguir foi minha e está justificada acima; registro isso explicitamente para que ninguém leia esta
> medição como tendo sido autorizada caso a caso.

### RESULTADO DA RODADA OFICIAL

```
$ pnpm exec playwright test --project=widget
  ✓   1 … home-light-desktop (8.7s)         ✓   9 … prechat-form-light-desktop (6.4s)
  ✓   2 … home-light-mobile (5.6s)          ✓  10 … prechat-form-light-mobile (5.5s)
  ✓   3 … home-dark-desktop (5.6s)          ✓  11 … prechat-form-dark-desktop (5.6s)
  ✓   4 … home-dark-mobile (5.6s)           ✓  12 … prechat-form-dark-mobile (5.7s)
  ✓   5 … messages-light-desktop (6.1s)     ✓  13 … unread-light-desktop (5.6s)
  ✓   6 … messages-light-mobile (6.4s)      ✓  14 … unread-light-mobile (4.6s)
  ✓   7 … messages-dark-desktop (6.3s)      ✓  15 … unread-dark-desktop (5.2s)
  ✓   8 … messages-dark-mobile (6.2s)       ✓  16 … unread-dark-mobile (5.2s)
  ✓  17 … carrega SDK, entrypoint e host reais nas portas contratadas (2.8s)
  ✓  18 … congela o relógio e alimenta o store determinístico (3.6s)
  ✓  19 … preserva a geometria original do unread no resize real (2.7s)
  ✓  20 … baseline descreve exatamente a matriz de 16 cenários (48ms)

  20 passed (5.6m)
OFICIAL_EXIT=0
```

**16/16 cenários passaram na tolerância do repositório, mais os 4 testes de infraestrutura da suíte.**
Zero falhas — e isso inclui as dimensões não-visuais: cada cenário também validou os contadores `axe`
e o contraste contra o `baseline.json` intacto, e o teste 19 confirmou a geometria do `unread` sob
resize real.

Como nada falhou, o Playwright **não gerou nenhum artefato de comparação**
(`find test-results -name "*-actual.png" -o -name "*-diff.png"` → **0**). É por isso que a rodada
estrita é necessária: até aqui eu sei que "passou", mas ainda não sei se a diferença é **zero**.

### 2.2 Rodada estrita — `--config=playwright.strict.config.js --project=widget`

**Resultado: 15 passed / 5 failed** (`ESTRITA_EXIT=1`), e a leitura correta desse número exigiu três
execuções — porque o instrumento estrito se revelou **instável**, e isso é o achado central desta task.

| # | cenário | run 1 | run 2 | run 3 |
|---|---|---|---|---|
| 1 | `home-light-desktop` | ✓ | ✓ | _(a seguir)_ |
| 2 | `home-light-mobile` | ✘ | ✓ | |
| 3 | `home-dark-desktop` | ✓ | ✓ | |
| 4 | `home-dark-mobile` | ✓ | ✓ | |
| 5 | `messages-light-desktop` | ✓ | ✘ | |
| 6 | `messages-light-mobile` | ✓ | ✓ | |
| 7 | `messages-dark-desktop` | ✓ | ✘ | |
| 8 | `messages-dark-mobile` | ✓ | ✓ | |
| 9 | `prechat-form-light-desktop` | ✘ | ✓ | |
| 10 | `prechat-form-light-mobile` | ✘ | ✘ | |
| 11 | `prechat-form-dark-desktop` | ✘ | ✘ | |
| 12 | `prechat-form-dark-mobile` | ✘ | ✘ | |
| 13-16 | `unread-*` (4) | ✓ | ✓ | |

**As duas execuções deram 5 falhas cada, mas com conjuntos diferentes** — `home-light-mobile` e
`prechat-form-light-desktop` falharam só na run 1; `messages-light-desktop` e `messages-dark-desktop`
falharam só na run 2. Mesmo commit, mesmo baseline, mesma máquina, nada alterado entre as rodadas.
Isso, por si só, prova que parte do sinal é **ruído**, não diferença de conteúdo.

### O diagnóstico: mesma fonte, mesmo texto, deslocamento sub-pixel

Não parei em "é flaky". Fui medir o que os pixels dizem, e o caminho corrigiu duas leituras minhas:

**Leitura 1 (errada):** classifiquei ~50% dos pixels alterados como "mudança visível real" porque
tinham delta > 8, com ~4.000 px de delta > 32. **Estava apressado** — um deslocamento sub-pixel de
*texto* produz deltas enormes justamente nas bordas dos glifos (pixel de texto escuro contra fundo
claro), então "delta grande" não distingue mudança real de reposicionamento.

**Leitura 2 (errada):** ao ver o primeiro recorte ampliado 3× do header do `prechat-form`, concluí que
**a fonte havia mudado**. Ampliando a 7× ficou claro que não: é o mesmo desenho de letra, com o
anti-aliasing recalculado.

**A medição que decide** — extremos do texto renderizado, por faixa:

| cenário / faixa | largura do texto (expected → actual) | topo (expected → actual) |
|---|---|---|
| `prechat-form-light-desktop` y=20..52 (header "Equipe Simplex") | 355 → **355 px** (Δ 0) | 21 → 20 (**−1 px**) |
| `prechat-form-light-desktop` y=97..110 (label do form) | 227 → **227 px** (Δ 0) | 98 → 97 (**−1 px**) |
| `home-light-mobile` y=68..92 ("Como podemos ajudar?") | 282 → **282 px** (Δ 0) | 69 → 68 (**−1 px**) |

**Largura idêntica ao pixel nos três casos** = mesma fonte, mesma métrica, mesmo texto. **Topo −1 px** =
o conteúdo está deslocado verticalmente. E o deslocamento é **fracionário**, não inteiro: testei todos
os shifts de −4 a +4 e nenhum faz as linhas casarem (com shift −1, só 1 de 33 linhas casa
exatamente), o que só acontece quando o glifo é rasterizado em posição sub-pixel diferente.

Confirmação por código de que a fonte não mudou: o merge **não tocou** nenhuma declaração de fonte no
widget (`git diff … | grep -iE "font-family|@font-face|Inter|woff"` → só falsos positivos de
"cursor"/"printer"), e `woot.scss:88,114` usa `font-family: inherit`.

**Conclusão do diagnóstico:** o que a rodada estrita acusa nesses cenários é **rasterização sub-pixel
instável do harness**, não diferença de conteúdo. O `threshold: 0` é sensível demais para um harness que
renderiza num iframe dentro de um host, e por isso ele **não consegue** responder "a diferença é zero?"
de forma confiável — o instrumento que eu mesmo escrevi tem esse limite, e reporto isso em vez de
apresentar seus 5 números como se fossem achados.

---

## 2.3 A mudança esperada, conferida no código antes de medir

Isto **não** substitui a medição — é para eu saber o que procurar no `-diff.png` e para distinguir
"mudança do upstream" de "regressão nossa" com base em código, não em impressão.

`App.vue:375-382` (HEAD), o container raiz:

```html
:class="{
  ...
  'bg-n-slate-2 dark:bg-n-solid-1': !isUnreadOrCampaignView,
  dark: prefersDarkMode,
}"
```

e `App.vue:71-73`:

```js
isUnreadOrCampaignView() {
  return ['unread-messages', 'campaigns'].includes(this.$route.name);
},
```

**Veio do upstream, confirmado:** nenhuma das duas construções existia antes do merge —

```
$ git show f26db6ee81:app/javascript/widget/App.vue | grep -n "bg-n-slate-2\|isUnreadOrCampaignView"
>>> NAO existia no pre-merge: a mudanca veio do UPSTREAM
```

Logo a previsão a testar é: **12 cenários mudam** (home, messages, prechat-form × 2 temas × 2
viewports) e **4 não mudam** (`unread-*`, porque `unread-messages` está na lista de exceção).

### As cores do briefing estão certas — e onde eu me enganei primeiro

Registro o erro porque ele muda a previsão, e porque um relatório que esconde o próprio caminho é
menos útil: primeiro fui ler `app/javascript/dashboard/assets/scss/_next-colors.scss` e conclui que o
dark era `#202C33`, "corrigindo" o briefing. **Estava errado** — o widget não importa esse arquivo
(grep por `next-colors` em `app/javascript/widget/` sai vazio). O widget tem o seu próprio conjunto,
em `app/javascript/widget/assets/scss/woot.scss`:

| token | linha | valor | hex | briefing |
|---|---|---|---|---|
| `--slate-2` (light) | `woot.scss:192` | `249 249 251` | **#F9F9FB** | #F9F9FB ✅ |
| `--solid-1` (dark) | `woot.scss:390` | `23 23 26` | **#17171A** | #17171A ✅ |

O briefing está correto nos dois valores.

### O que a medição das cores do baseline revelou — e por que a previsão de "12 mudam" é frágil

Antes de rodar qualquer coisa, medi a **cor dominante de cada um dos 16 PNG do baseline** (é dado, não
usa porta nenhuma):

| cenário | dim | cor dominante | % do quadro |
|---|---|---|---|
| `home-dark-desktop` | 400×564 | **#17171A** | 53,73% |
| `home-dark-mobile` | 390×844 | **#17171A** | 63,11% |
| `home-light-desktop` | 400×564 | **#F9F9FB** | 53,74% |
| `home-light-mobile` | 390×844 | **#F9F9FB** | 63,11% |
| `prechat-form-dark-desktop` | 400×564 | **#17171A** | 52,94% |
| `prechat-form-dark-mobile` | 390×844 | **#17171A** | 67,23% |
| `prechat-form-light-desktop` | 400×564 | **#F9F9FB** | 54,42% |
| `prechat-form-light-mobile` | 390×844 | **#F9F9FB** | 67,23% |
| `messages-*` | — | #FEFEFE / #2DC46F / #030304 | 17–39% |
| `unread-*` | 400×282 / 316×282 | #FFFFFF | 76–86% |

**O baseline pré-merge JÁ é dominado por `#17171A` / `#F9F9FB`** — exatamente as cores que o `App.vue:380`
do upstream passou a pintar. Ou seja: o fundo não é novidade visual, ele só passou a ser pintado
**também** um nível acima na árvore. Quem já o pintava antes:

```
$ git grep -n "bg-n-slate-2\|bg-n-solid-1" f26db6ee81 -- app/javascript/widget
…/components/layouts/ViewWithHeader.vue:106:  class="w-full h-full bg-n-slate-2 dark:bg-n-solid-1"
…/views/Messages.vue:22:  class="… rounded-b-lg bg-n-chat-bg dark:bg-n-solid-1"
```

`ViewWithHeader.vue:106` — o layout de `home` e `prechat-form` — já aplicava **as mesmas duas classes**,
`w-full h-full`, desde antes do merge. Então a mudança do upstream é, para esses cenários,
**redundante**: pinta a mesma cor atrás de algo que já a pintava.

**Previsão revisada, e é diferente da do briefing:** em vez de "12 mudam", o esperado agora é
**pouca ou nenhuma mudança** — e, se houver, concentrada em bordas, cantos arredondados ou faixas que o
layout interno não cobria (`rounded-b-lg` no `Messages.vue` deixa cantos; o container raiz agora pinta
atrás deles). É isso que a medição vai decidir. Anoto a previsão **antes** de medir justamente para
não ajustá-la ao resultado depois.

## 2.4 O inventário completo do que o merge mudou no widget — para eu poder atribuir qualquer diff

O `App.vue:380` não é a única mudança. Levantei tudo entre `f26db6ee81..HEAD` em
`app/javascript/widget/` + `app/javascript/shared/`: **112 arquivos**, mas a esmagadora maioria é
`i18n/locale/*.json` e `*.spec.js`. Fora disso, os que podem mover pixel:

| arquivo | natureza da mudança | alcança os 16? |
|---|---|---|
| `widget/App.vue` | `bg-n-slate-2 dark:bg-n-solid-1` no container raiz | **sim** (12 cenários) |
| `widget/assets/scss/woot.scss` | `.message-content ul/ol/li` reescrito + 6 vars `--surface-*` novas | **ver abaixo** |
| `widget/views/PreChatForm.vue` | **só lógica** (`custom_attributes` no mesmo request) | não |
| `widget/views/ArticleViewer.vue` | 1 linha, `bg-n-solid-1 h-full` | não (view fora da matriz) |
| `shared/components/emoji/*` | `EmojiInput.vue` → `EmojiPicker.vue` (§R1 da auditoria) | só se o picker abrir |
| `widget/components/{ChatFooter,ChatInputWrap,UserMessage,UserMessageBubble}.vue` | markup/classes | possivelmente `messages-*` |

### A mudança do `woot.scss` é visual — mas está fora do alcance dos 16

O merge trocou o CSS de listas dentro das mensagens:

```diff
 .message-content {
   ul {
-    list-style: disc;
-    @apply ltr:pl-3 rtl:pr-3;
+    @apply list-disc list-inside;
   }
+  li {
+    padding-inline-start: 1.5em;
+    text-indent: -1.5em;
+  …
```

Isso muda a indentação de listas em mensagens. Mas as 4 mensagens que o harness serve
(`widget-server.mjs:12-110`) são **texto puro** — `'Olá, preciso de ajuda.'`,
`'Mensagem determinística para o cenário.'`, `'Vou conferir agora.'`,
`'Resposta pendente número três.'` — **nenhuma contém lista markdown**. Logo esse CSS não é exercitado
por nenhum dos 16 cenários.

**Consequência honesta: é uma mudança visual do upstream que os 16 snapshots NÃO cobrem.** Não é
regressão e não é falha da medição — é um limite da matriz, e fica registrado como débito de cobertura
(§5), não como resultado.

O merge também **adicionou** `--surface-1`, `--surface-2` e `--surface-active` (light e dark). São
tokens novos; nenhuma variável de cor **pré-existente** do widget foi alterada — o que sustenta a
previsão de que `#F9F9FB` / `#17171A` continuam sendo as cores do quadro.

---

## 3. A tabela dos 16

_(preenchida cenário por cenário depois das duas rodadas)_

### Instrumento de leitura dos diffs

"Revisado um a um" exige que eu diga **o que** mudou, não só "mudou". Para isso escrevi
`analisa-diffs.py`: ele lê os pares `-expected.png` / `-actual.png` que o Playwright deixa quando um
`toHaveScreenshot` falha e, por cenário, extrai **contagem exata** de pixels diferentes (não
estimativa), o % do quadro, o *bounding box* da região alterada e as **transições de cor dominantes**
("de `#XXXXXX` para `#YYYYYY`, N pixels"). É isso que transforma cada frase da tabela em afirmação com
número em vez de impressão.

Uma propriedade do Playwright que condiciona a leitura: ele só grava `-actual`/`-diff`/`-expected`
quando o cenário **falha**. Portanto, cenário que passa na rodada estrita (`maxDiffPixels: 0`) não gera
artefato — e a ausência do artefato **é** a prova de zero pixels de diferença.

---

## 4. Veredito final do aceite do 0.2

_(a preencher — sem meio-termo)_
