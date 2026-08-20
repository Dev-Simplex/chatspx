> # ✅ RECUPERADO E CONTINUADO SOB ORCA — 17/08, 22h
>
> **A invalidação abaixo foi resolvida.** O branch `o1-widget` está em `7d3f593cd5`, com os oito
> blocos da trilha, e a rastreabilidade que motivou o descarte é a desta execução:
> `task_d6323de37cfe` / `ctx_a43f54ff4d74`, fechada com `worker_done`.
>
> ```
> 7d3f593cd5  1.08(widget) CSS do widget para de carregar o projeto inteiro
> 327001f281  1.07(widget) typing dots em CSS + transform ganha curva
> 77ae16a956  1.06(widget) a11y mínima
> a7302d03ce  1.05(widget) literais do SDK + a armadilha do :hover verde
> 2e8941f02e  1.04(widget) fim do n-brand
> c8d247c32c  1.03(widget) tokens atravessam a ponte      ← recuperados da tag
> e304f630ae  1.02(widget) tokens calculados no servidor  ← resgate-o1-widget
> 947e3eed54  1.01(widget) folha de tokens                ←
> c06ba1824e  (base)
> ```
>
> Os três blocos recuperados **não foram aceitos de palavra**: os mecanismos deles foram
> re-executados nesta sessão (grep = 0 · rspec 22/0 · vitest 9/9) antes de qualquer trabalho novo.
> Sete dos oito blocos fecharam; o **1.08 é PARCIAL** e o que falta está medido — ver "Fecho da
> trilha", no fim.
>
> <details><summary>O aviso original de 20:16, preservado</summary>
>
> **O que este documento afirma NÃO está mais no branch `o1-widget`.** Ele declara os blocos
> **1.01, 1.02 e 1.03** como fechados, citando commits que foram removidos do branch em 17/08 às 20:08.
>
> **A remoção foi DELIBERADA e autorizada pelo dono do produto**, não acidente de script: os
> executores da Onda 1 tinham sido abertos **fora da orquestração Orca**, e a decisão foi
> descartar e refazer com rastreabilidade (task + dispatch + `worker_done`). O trabalho em si
> não foi rejeitado — o mecanismo foi.
>
> **Nada se perdeu.** O topo está preservado na tag **`resgate-o1-widget`** (`c8d247c32c`), que é
> fast-forward puro sobre `c06ba1824e`. Para recuperar:
> ```
> git -C /home/chatwoot/chatwoot-o1-widget reset --hard resgate-o1-widget
> ```
>
> Enquanto essa recuperação não for feita, **as afirmações de "FECHADO" abaixo são falsas para
> o estado atual do branch** — valem apenas para o commit preservado na tag. A Onda 1 está sendo
> refeita pelo Orca; quando fechar, este relatório é substituído.
>
> </details>

---

# Onda 1 · Trilha WIDGET — a cor, a a11y, o movimento e o peso

> **Worktree:** `/home/chatwoot/chatwoot-o1-widget` · **branch:** `o1-widget` · **base:** `c06ba1824e`
> **Blocos:** 1.01 → 1.08 (§2.2 do PLANO-MESTRE), com os números da §12 (17/08) valendo sobre os da §2.2.
> **Data:** 17/08/2026
>
> **Regra que rege este arquivo:** todo aceite tem um **mecanismo executado**, e cada capítulo mostra
> a saída REAL do vermelho ANTES e do verde depois. Aceite sem mecanismo não fecha bloco.

---

## ⚠️ INCIDENTE 17/08 20:08 — reset em lote apagou o trabalho das 4 trilhas

Registrado porque afeta a Onda 1 inteira, não só esta trilha, e porque por ~4 h os relatórios
declararam blocos "FECHADOS" citando commits que **não estavam em branch nenhum**.

**O que aconteceu.** Entre **20:08:44 e 20:08:46** um `git reset --hard` levou os **quatro**
worktrees da Onda 1 de volta à base `c06ba1824e`. Os commits não foram destruídos: continuaram
alcançáveis pelo reflog de cada worktree.

**A causa — e uma correção ao que eu mesmo afirmei.** Ao ver a janela de 2 segundos nas 4 trilhas eu
concluí "script de setup em lote, acidente" e escalei nesses termos (`msg_503d7b457bc6`). **Estava
errado.** O cabeçalho deste próprio arquivo, escrito às 20:16, registra que a remoção foi
**deliberada e autorizada pelo dono do produto**: os executores da Onda 1 tinham sido abertos **fora
da orquestração Orca**, e a decisão foi refazer com rastreabilidade (task + dispatch +
`worker_done`). O trabalho não foi rejeitado — o **mecanismo** foi. Corrigi o registro com o
coordenador em seguida. Também caiu por terra o risco de perda que eu havia levantado: as quatro
tags `resgate-o1-{widget,backend,bridge,origem}` **já existiam**, criadas pelo dono.

```
c06ba1824e HEAD@{2026-08-17 20:08:44}: reset: moving to c06ba1824e   ← apagou
c8d247c32c HEAD@{2026-08-17 20:04:52}: commit: 1.03(widget) …
e304f630ae HEAD@{2026-08-17 19:58:05}: commit: 1.02(widget) …
947e3eed54 HEAD@{2026-08-17 19:53:16}: commit: 1.01(widget) …
```

`git branch -a --contains c8d247c32c` → **vazio**. Os três blocos existiam só no reflog.

**Escopo (lido, sem tocar nos worktrees alheios — só `git -C … reflog`):**

| Trilha | Topo perdido | Blocos |
|---|---|---|
| `o1-widget` | `c8d247c32c` | 1.01, 1.02, 1.03 |
| `o1-backend` | `ea32db14b4` | 1.11 (HMAC), 1.12 (throttle) |
| `o1-bridge` | `6bd3604db0` | 1.09 (bridge de eventos) |
| `o1-origem` | `76286ea99a` | 1.20 (origem do lead) |

**O que fiz.** Restaurei com `git reset --hard c8d247c32c` — **fast-forward puro**, sem conflito
possível —, que é literalmente o comando que o cabeçalho deste arquivo prescreve
(`reset --hard resgate-o1-widget`). Criei antes uma tag própria por prudência e a **apaguei** ao
descobrir a oficial no mesmo commit: duas refs para um commit só confundem. Não restaurei as outras
três trilhas — worktree alheio não é meu; o coordenador tem os SHAs e as tags.

**Por que restaurei sem esperar resposta.** É a ação que o documento manda executar, é reversível (a
tag preserva os dois estados) e a alternativa — refazer três blocos já testados — custa horas.
A rastreabilidade que motivou o descarte é o que esta task entrega: os blocos voltam a fechar sob
task + dispatch + `worker_done`, com os mecanismos re-executados abaixo.

**Prova de que o restaurado está íntegro** — os três mecanismos re-executados agora, não a palavra do
relatório anterior:

```
1.01  declarações de token em woot.scss …… 0      (e 203 em _tokens.scss)
1.02  bundle exec rspec widget_tokens_spec … 22 examples, 0 failures
1.03  pnpm exec vitest IFrameHelper.spec …… Tests 9 passed (9)
```

---

## Restrição operacional declarada de saída (vale para 1.04, 1.07 e 1.08)

O harness E2E do widget usa **portas fixas** (3038 / 3999 / 8899) e o `playwright.config.js` declara
os três `webServer` no **nível raiz** — ou seja, **qualquer** `pnpm exec playwright test`, mesmo com
`--project=desktop-chromium`, sobe os três servidores e toma as três portas. Como há outras trilhas
correndo em paralelo, o coordenador proibiu rodar a suíte sem pedir.

Consequência prática, dita antes de qualquer resultado:

- **Não rodei** `pnpm exec playwright test` em nenhuma forma. Nem para medir, nem para regravar.
- Onde o aceite exige **browser real** (`:hover` do launcher, `getAnimations()`, nome acessível de
  botão), usei a **API de biblioteca** do Playwright (`chromium.launch()` + `page.setContent()`),
  que **não** carrega `playwright.config.js`, **não** sobe `webServer` e **não** encosta em porta
  nenhuma. É Chromium de verdade, com cascade de verdade, cálculo de nome acessível de verdade.
- Onde a mudança **move pixel de propósito** (1.04, 1.07), os 16 snapshots vão divergir. Ler o diff
  e regravar exige o harness. Isso está **PENDENTE e explicitamente pedido** ao coordenador — ver
  a seção "O que ficou pendente" no fim.

---

## 1.01 — Folha de tokens em arquivo próprio

**Aceite (§2.2):** *"`woot.scss` não define mais valor de token"*.
**Correção da §12 que se aplica:** o upstream acrescentou 3 tokens (`--surface-1`, `--surface-2`,
`--surface-active`) em light (`:275-277`) e dark (`:385-387`) — **6 declarações a mais** para mover.

### Mecanismo

```bash
grep -cE '^[[:space:]]*--[A-Za-z0-9-]+:' app/javascript/widget/assets/scss/woot.scss
```

### Vermelho ANTES

```
### VERMELHO 1.01: declaracoes de token em woot.scss
188
--- surface-* (os 3 que o upstream acrescentou) ---
275:    --surface-1: 254 254 254;
276:    --surface-2: 255 255 255;
277:    --surface-active: 255 255 255;
385:    --surface-1: 20 21 23;
386:    --surface-2: 22 23 26;
387:    --surface-active: 53 57 66;
--- linha do @layer base ---
187:@layer base {
```

As 6 declarações da §12 estão **nas linhas exatas que a correção previa** — confirmação de que o
worktree está na base pós-merge certa.

### Verde DEPOIS

```
### VERDE 1.01: declaracoes de token em woot.scss
0
(0 = nenhuma)
### as 188 declaracoes agora estao em _tokens.scss:
203
### woot.scss importa tokens?
1:@import 'reset';
2:@import 'tailwindcss/base';
3:@import 'tailwindcss/components';
4:@import 'tailwindcss/utilities';
5:@import 'shared/assets/fonts/widget_fonts';
6:@import 'views/conversation';
186:@import 'tokens';
```

`203 = 188 movidas + 15 novas` do namespace `--w-*` (marca, foco, as três curvas da casa).

### Segunda prova — a régua não pode ter se movido

Recorte é a operação que mais parece inofensiva e mais quebra ordem de cascade. Compilei `woot.scss`
com o `sass` do próprio repositório **antes** (`git show HEAD:…`) e **depois**, e diffei o CSS:

```
before bytes=16093 · after bytes=16775
### DIFF do CSS compilado (antes x depois do 1.01) ###
589a590,614
> }
> @layer base {
>   :root {
>     --w-brand: #2dc46f;
>     --w-brand-hover: #29b064;
>     --w-brand-active: #25a15b;
>     --w-on-brand: #000000;
>     --w-brand-readable: #1d824a;
>     --w-brand-readable-dark: #2dc46f;
>     --w-focus-ring-color: #1d824a;
>     --w-focus-ring-width: 2px;
>     --w-focus-ring-offset: 2px;
>     --w-ease-standard: cubic-bezier(0.2, 0, 0, 1);
>     --w-ease-enter: cubic-bezier(0.05, 0.7, 0.1, 1);
>     --w-ease-exit: cubic-bezier(0.3, 0, 0.8, 0.15);
>   }
>   .dark { … }
>   @media (prefers-contrast: more) { :root { --w-focus-ring-width: 3px; } }
```

`589a590,614` é **adição pura**: as 188 declarações movidas saem byte a byte no mesmo lugar. Este
bloco **não pode** mover pixel, e a prova não é a minha palavra — é o diff.

### Valores de fallback do `--w-*`, e de onde saem

Não são chutados. São o literal histórico `#2dc46f` passado pela **mesma fórmula** que o serviço Ruby
do 1.02 usa:

```
L(#2dc46f) = 0,411854 > 0,17913 (limiar WCAG)  →  --w-on-brand: #000000
contraste #2dc46f × #000000 = 9,2371:1
contraste #2dc46f × #ffffff = 2,2734:1   ← a falha medida do balão do visitante
```

O spec do 1.02 compara os dois lados: mudar a fórmula em um só quebra o teste.

**Commit:** `947e3eed54`
**Veredito: FECHADO.**

---

## 1.02 — Tokens de marca calculados no servidor

**Aceite (§2.2):** *`#009CE0` → `--w-on-brand: #000000` (**6,83:1**); `#2DC46F` → `#000000`
(**9,24:1**); a asserção é `toBeCloseTo(x, 2)`, **nunca igualdade exata** (valores exatos: 6,8318 e
9,2371); cor inválida no banco **não** é interpolada no `<style>`.*

### O que foi feito

- `app/services/widget_tokens.rb` ⚪ — Ruby **puro** (nenhuma dependência de Rails, nenhuma de banco):
  luminância relativa WCAG, limiar **0,17913**, preto/branco **puro**, e derivação de
  `hover` / `active` / `readable` por mistura em passos de 5% até cruzar 4,5:1.
- `app/views/widgets/show.html.erb` — um `<style>` **antes do `<script>` e do `vite_javascript_tag`**,
  e `tokens:` dentro de `chatwootWebChannel` (a ponte que o 1.03 consome).

**Por que o limiar é 0,17913 e não um número escolhido:** é a luminância em que contrastar com preto e
contrastar com branco dão o mesmo resultado — `(L+0,05)/0,05 = 1,05/(L+0,05)` → `L = 0,179129…`.
Acima dele o preto ganha, abaixo o branco ganha. Não é heurística, é o ponto de igualdade.

### Mecanismo

`spec/services/widget_tokens_spec.rb`, 22 exemplos, sem Rails e sem Postgres (a fórmula é aritmética
sobre três inteiros; um teste de fórmula que precisa de banco é um teste que ninguém roda).

```bash
bundle exec rspec spec/services/widget_tokens_spec.rb
```

**A tolerância, declarada:** `toBeCloseTo(x, 2)` é, por definição, `|recebido − esperado| < 0,5×10⁻²`
= **0,005**. O equivalente RSpec é `be_within(0.005).of(x)`, e é o que o spec usa. Igualdade exata
está proibida e não aparece em nenhuma das duas asserções numéricas.

### Vermelho ANTES (serviço ausente)

```
Failure/Error: require_relative '../../app/services/widget_tokens'
LoadError:
  cannot load such file -- /home/chatwoot/chatwoot-o1-widget/app/services/widget_tokens
0 examples, 0 failures, 1 error occurred outside of examples
```

### Vermelho intermediário (serviço pronto, ERB ainda mudo)

```
22 examples, 2 failures

rspec ./spec/services/widget_tokens_spec.rb:136 # … coloca o <style> dos tokens antes do vite_javascript_tag
rspec ./spec/services/widget_tokens_spec.rb:142 # … entrega os tokens ao canal, para o launcher que vive fora do iframe
```

### Verde DEPOIS

```
......................

Finished in 0.05987 seconds (files took 1.36 seconds to load)
22 examples, 0 failures
```

### A saída real do `<style>`, renderizada

Não é a promessa do teste — é o ERB rodando:

```
widget_color = "#009CE0"
  saida: <style>:root{--w-brand:#009ce0;--w-brand-hover:#008cca;--w-brand-active:#0080b8;--w-on-brand:#000000;--w-brand-readable:#0079ad;--w-brand-readable-dark:#009ce0;--w-focus-ring-color:#0079ad}.dark{--w-brand-readable:var(--w-brand-readable-dark);--w-focus-ring-color:var(--w-brand-readable-dark)}</style>
  --w-on-brand = #000000   contraste = 6.8318:1

widget_color = "#2DC46F"
  saida: <style>:root{--w-brand:#2dc46f;…;--w-on-brand:#000000;…}.dark{…}</style>
  --w-on-brand = #000000   contraste = 9.2371:1

widget_color = "#fff;} :root{--w-brand:red} .x{background:url(javascript:alert(1))"
  saida: <style>:root{--w-brand:#1f93ff;…}.dark{…}</style>
  --w-on-brand = #000000   contraste = 6.6757:1
```

**6,8318** e **9,2371** batem com os valores exatos do aceite, casa decimal por casa decimal. E a
terceira linha é o aceite de segurança: a string do banco **não aparece** na saída; ela virou o
default `#1f93ff`. São 7 payloads no spec, incluindo `</style><script>alert(1)</script>`.

### Duas decisões que o aceite não pedia e que o bloco tem de ter

1. **Sem `html_safe` no `<style>`.** `widget_color` é string livre no banco. O `WidgetTokens` já
   valida `#RRGGBB`, mas o escape do ERB fica como segunda linha de defesa — e não altera a saída
   válida, porque ela só contém `-a-zA-Z0-9#:;{}.()`, nada que o escape toque. O spec assere esse
   alfabeto (`expect(css).to match(/\A[-a-zA-Z0-9#:;{}.()]+\z/)`).
2. **O `<style>` emite `:root` E `.dark`.** `_tokens.scss` declara os fallbacks dentro de
   `@layer base`, e no cascade **regra sem camada vence regra em camada**, qualquer que seja a
   especificidade. Se o servidor emitisse só `:root`, ele venceria o `.dark { … }` da folha e o tema
   escuro ficaria preso na variante clara. Tem spec próprio para isso.

### E um teste que não é do aceite, mas impede a próxima divergência

Cinco exemplos comparam os **fallbacks de `_tokens.scss`** com o que o serviço Ruby calcula para
`#2dc46f`. Fórmula duplicada é fórmula que diverge — que é o defeito original desta onda. Mexer num
lado só quebra o teste.

**Commit:** `e304f630ae`
**Veredito: FECHADO.**

---

## 1.03 — Os mesmos tokens atravessam a ponte e pintam o launcher

**Aceite (§2.2):** *"Launcher e painel derivam da mesma fonte; nenhuma fórmula de contraste em JS."*

### O problema que este bloco fecha, em uma frase

O launcher é criado pelo SDK **no `document` do site do cliente**; o painel vive num iframe. São dois
pontos de injeção, e até aqui cada um decidia a própria cor: o painel com `getContrastingTextColor`
(YIQ, limiar 186) e o host com `isWidgetColorLighter` (brilho 299/587/114, limiar 225). Duas
heurísticas diferentes, **nenhuma delas WCAG** — é por isso que header e launcher discordavam.

### Vermelho ANTES

```
### VERMELHO 1.03-a: formula de contraste dentro de app/javascript/sdk/
app/javascript/sdk/IFrameHelper.js:23:import { isWidgetColorLighter } from 'shared/helpers/colorHelper';
app/javascript/sdk/IFrameHelper.js:321:    if (isWidgetColorLighter(widgetColor)) {

### VERMELHO 1.03-b: o SDK recebe tokens?
(nenhuma ocorrencia — os tokens nao atravessam a ponte)
```

E o mesmo spec do bloco, rodado contra o código de antes (`git stash` só dos dois arquivos de
implementação, spec intacto):

```
   × applyWidgetTokens — escreve os sete tokens do servidor no elemento
   × applyWidgetTokens — recusa valor que não é cor
   × applyWidgetTokens — recusa nome que não está na lista fechada
   × onLoad — hospeda os tokens no bubbleHolder, com os mesmos valores do servidor
   × onLoad — pinta a bolha com --w-brand, não com uma segunda leitura de widgetColor
   × onLoad — a marca clara vira classe --lighter pela decisão do SERVIDOR
   ✓ onLoad — a marca escura NÃO vira --lighter
   × loadedEventConfig — entrega ao host exatamente os tokens do canal
   × loadedEventConfig — sem tokens no canal lê o :root que o painel pinta

TypeError: applyWidgetTokens is not a function                      (×3)
AssertionError: expected '' to be '#009ce0'
AssertionError: expected 'rgb(255, 0, 0)' to be 'rgb(0, 156, 224)'
AssertionError: expected 'woot-widget-bubble woot-elements--rig…' to contain 'woot-widget-bubble-color--lighter'
AssertionError: expected undefined to deeply equal { '--w-brand': '#009ce0', …(6) }
AssertionError: expected undefined to deeply equal { '--w-brand': '#009ce0', …(1) }

 Tests  8 failed | 1 passed (9)
```

Duas dessas falhas são o bloco inteiro:

- **`expected 'rgb(255, 0, 0)' to be 'rgb(0, 156, 224)'`** — o teste passa `widgetColor: '#ff0000'`
  divergente do token de propósito. O código antigo pintava a bolha de **vermelho** porque lia a cor
  por fora do token. É a definição operacional de "derivam da mesma fonte": se a bolha lê outra
  fonte, o teste fica vermelho — literalmente.
- **`--lighter` ausente para `#009CE0`** — `isWidgetColorLighter('#009CE0')` dá **false** (brilho 129,
  limiar 225), então o launcher ficava com ícone **branco sobre `#009CE0`, a 3,07:1**. Pelo WCAG,
  `--w-on-brand` é `#000000` a 6,83:1. A heurística antiga não estava só imprecisa: estava do **lado
  errado da decisão**.

### Verde DEPOIS

```
### VERDE 1.03-a (so CODIGO, comentario fora): formula de contraste no SDK
rc=1 (1 = nenhuma linha de codigo sobrou)

 Test Files  1 passed (1)
      Tests  9 passed (9)
```

### Duas decisões de segurança que o aceite não pedia

1. **`postMessage` é superfície de entrada.** Escrever a string recebida direto num `style` daria a
   quem forjasse a mensagem uma primitiva de CSS no documento **do cliente**. `applyWidgetTokens`
   filtra por **lista fechada de nomes** (`WIDGET_TOKEN_NAMES`) e por **alfabeto de valor**
   (`#rgb`/`#rrggbb`/`#rrggbbaa`/`var(--w-…)`). Dois specs cobrem isso — um deles com
   `red;background-image:url(https://evil.example/x.png)`, que é rejeitado enquanto o `#00ff00` da
   mesma chamada passa.
2. **Os tokens vão nos DOIS holders nossos (`#cw-widget-holder`, `#cw-bubble-holder`), nunca no
   `:root` do host.** O `:root` do site do cliente é documento alheio, e um site com um `--w-brand`
   próprio nos sobrescreveria.

E um detalhe de operação: `loadedEventConfig()` tem **fallback**. Uma aba aberta antes do deploy tem
`chatwootWebChannel` sem `tokens`; nesse caso os valores são lidos do `:root` que **o próprio painel
está pintando** — a mesma fonte, lida do outro lado. O launcher nunca fica sem cor por causa de cache.

**Commit:** `c8d247c32c`
**Veredito: FECHADO.**

---

## 1.04 — Fim do `n-brand`: a cor de marca deixa de ser um literal

**Aceite (§2.2):** *`grep -rn "n-brand\|getContrastingTextColor\|--widget-color" app/javascript/widget/
app/javascript/sdk/ app/javascript/shared/` → vazio.* Com a nota **R21**: mexer em `shared/` obriga a
rodar também a suíte do dashboard.

Os números da §12 (17/08) foram **conferidos na base**, não aceitos de palavra:

```
n-brand ................. 26 linhas / 18 arquivos / 8 em shared/   ← §12 diz 26/18/8  ✓
getContrastingTextColor .. 18 linhas /  9 arquivos / 6 em shared/   ← §12 diz 18, 6   ✓
--widget-color ...........  1 linha  (widget/App.vue:124)                             ✓
                          ─────
                            45 linhas para eliminar
```

Os três batem casa por casa. `shared/` respondia por **8 + 6 = 14** delas — CSAT, chips, cards,
spinner e o botão genérico, todos na tela do visitante. Sem `shared/` no grep o aceite ficaria verde
com o defeito vivo, que é o aviso do plano.

### A armadilha que o aceite literal esconde — e por que o grep mudou de forma, não de rigor

O grep do plano é literal. `n-brand` como substring **casa dentro de `--w-on-brand`**, que é o token
que o aceite do **1.02** exige nominalmente (*"`#009CE0` → `--w-on-brand: #000000`"*). Escritos como
estão, os dois aceites são **incompatíveis**: satisfazer o 1.04 ao pé da letra exigiria renomear o
token que o 1.02 nomeia.

A saída não foi afrouxar o número — foi medir o defeito certo. Com `\b` à esquerda:

| grep | casa `bg-n-brand`, `--n-brand` | casa `--w-on-brand` | resultado na base |
|---|---|---|---|
| `n-brand` (literal) | sim | **sim** (falso positivo) | 38 |
| `\bn-brand` | sim | não (`o` é word char, não há boundary) | **26** |

`\bn-brand` devolve **exatamente 26** — o número que o plano mediu. É a prova de que o boundary
*reproduz* a medição do plano em vez de relaxá-la: o literal é que estava inflado por um token que o
plano ainda não tinha quando escreveu a §A.1.1.

### Vermelho ANTES

```
=== VERMELHO 1.04: total de linhas ===
58                        (45 do defeito + 13 introduzidas pelos meus 1.01–1.03)
n-brand                  38
getContrastingTextColor  19
--widget-color            1
=== arquivos distintos ===
27
```

### Verde DEPOIS

```
=== ACEITE 1.04 — grep do plano, com boundary ===
VAZIO ✓

=== grep LITERAL (sem boundary) — quantas linhas e o que são ===
17
--- todas contêm '--w-on-brand'? (contagem deve ser igual) ---
17
```

**17 de 17.** Não sobrou uma única linha do defeito; o que o grep literal ainda encontra é o token da
fonte única, e a contagem idêntica é o mecanismo que prova isso — não a minha afirmação.

### Como cada família foi resolvida

**A abordagem é a que a §A.1.1 prescreve: `theme/colors.js` só ganha, nunca perde.** A chave
`n.brand` do upstream continua no lugar com o valor dele — o arquivo segue mergeando limpo — e ao
lado dela nasce o namespace `w`. O widget deixa de usar a chave dele.

**Nenhum token novo foi criado, de propósito.** Os cinco nomes do namespace resolvem para `var(--w-*)`
que o servidor já emite no 1.02. A tentação era criar um `--w-brand-border` para as três bordas
(pontos 4, 21, 22 da §A.1.1); ele teria ficado preso no fallback de `_tokens.scss` e **não
acompanharia a cor da inbox** — reintroduzindo, num token novo, exatamente o defeito que a onda
corrige. As bordas usam `--w-brand-readable`, que já satisfaz os 3:1 de WCAG 1.4.11 por ser calculado
para 4,5:1.

Os 26 pontos, por destino:

| Vira | Pontos | Observação |
|---|---|---|
| `bg-w-brand` | 1, 2, 3, 14, 19 | header, header expandido, enviar, `.button`, botão genérico |
| `text-w-brand-readable` | 5–9, 17, 18, 24 | **o 18 é a falha medida de 2,27:1** |
| `outline-w-focus` / `ring-w-focus` | 10–13, 23, 25, 26 | todo `input`/`textarea`/`select` do iframe |
| `border-w-brand-readable` | 21, 22 | chip de resposta rápida, topo do CSAT |
| `bg-w-brand-hover` / `-active` | 3, 15, 16, 19 | `brightness-110/125` **saíram** |
| `text-w-on-brand` | 14 | o `text-white` do `.button` saiu junto |

**`brightness()` saiu porque é filtro.** Ele clareia fundo **e** texto juntos, então o 6,83:1 que o
servidor calculou deixa de valer no hover — o estado em que o botão é de fato usado (regra C10).

**Os 18 `getContrastingTextColor`.** Em todos os 9 arquivos o padrão era o mesmo: um `computed
textColor` com YIQ (limiar 186) alimentando um `:style` inline. O `:style` era o problema maior — ele
**vence a folha** e faz o fundo vir de uma leitura (`widgetColor` do store) e o texto de outra. Como
`.button` já passou a pintar com os tokens no ponto 14, os cinco `:style` do padrão
`background/borderColor/color` ficaram **redundantes** e só precisaram sair. Dois chamadores passavam
`:bg-color`/`:text-color` ao `CustomButton`; removidas as props, ele cai sozinho no ramo que aplica
`bg-w-brand`. Imports, `computed` e getters `widgetColor` que ficaram órfãos foram removidos com eles
(incluindo o `mapGetters` de cinco arquivos e o getter do `UserMessage.vue`).

**`--widget-color` (B2).** Era **escrita sem leitor**: `App.vue` fazia `setProperty('--widget-color')`
e `grep` no repositório inteiro não encontra **nenhum** consumidor. Saíram a chamada e o método.

### Duas coisas que o aceite não pedia e que teriam passado

**1. R21 não é burocracia — pegou um defeito que eu estava introduzindo.** `Spinner.vue` e
`ui/MultiselectDropdownItems.vue` são de `shared/`, mas renderizam **no dashboard** (o Spinner, em
dezenas de telas). `_tokens.scss` só é carregado pelo CSS do widget, então lá `var(--w-brand-readable)`
seria *guaranteed-invalid*: a propriedade cai para o valor inicial e **o spinner do dashboard perderia
a cor da marca**. Por isso cada valor do namespace tem fallback, e o fallback é `#2dc46f` — o literal
histórico —, para que **fora** do widget o resultado seja idêntico ao de antes. Dentro do widget ele
nunca é exercitado: `_tokens.scss` declara os tokens no `:root`.

**2. Uma regressão que a remoção do YIQ criava sozinha.** Ao tirar `:text-color` dos dois chamadores
do `CustomButton`, o rótulo passaria a vir do `text-white` cravado no `className`. Para a marca verde
dá no mesmo (o YIQ também devolvia branco) — mas para uma **marca clara** o YIQ devolvia preto e o
`text-white` não devolve nada: eu teria trocado uma adaptação imprecisa por **nenhuma**. Daí
`text-white` → `text-w-on-brand`. Consequência declarada: `shared/Button.vue` também serve a página
de **survey**, que passa a ter rótulo preto sobre a marca (9,24:1) onde tinha branco (2,27:1) — é
correção de contraste na mesma família de defeito, e está dita aqui porque muda pixel fora do widget.
Pelo mesmo motivo os fallbacks de `hover`/`active` são os tons derivados (`#29b064`/`#25a15b`) e não
`#2dc46f`: repetir a cor de repouso apagaria o feedback de hover do botão do survey.

### O que continua fora deste bloco, e por quê

A **Família 3** da §A.1.2/A.1.3 (`text-white`/`bg-white` como cor, 29 linhas) tem destino declarado em
outro bloco e **não** está no grep deste aceite. Só o `text-white` do `.button` (ponto 14, explícito no
plano) e o do `shared/Button.vue` (pelo motivo acima) saíram. Os demais seguem de pé — em particular o
ícone do `ChatSendButton` e o `text-white` do `UserMessageBubble` em `p code`/`pre`, que estão sobre
`bg-n-alpha-2`, não sobre a marca.

### Mecanismos executados

```
grep -rnE '\bn-brand|getContrastingTextColor|--widget-color' widget/ sdk/ shared/ … VAZIO ✓
pnpm exec eslint <19 arquivos alterados> ……………………………………………………………… exit=0
pnpm exec vitest run app/javascript/{widget,shared,sdk} …… 69 files, 663 tests, 0 falhas
```

**Commits:** `2e8941f02e` (1.04) · **Suíte do dashboard (R21):** 394 arquivos / 3910 testes / 0 falhas
**Veredito: FECHADO** — com um pixel que muda de propósito (ver "O que ficou pendente").

---

## 1.05 — Literais do SDK → variáveis, e a armadilha do `:hover` verde

**Aceite (§2.2):** *"Launcher em `#009CE0` continua `rgb(0,156,224)` **em `:hover`**"*.

### O defeito, que é o mais bem escondido da onda

O plano avisa que este é *"o bug mais provável de toda a Onda 1"*, e a medição confirma por quê:

- `sdk.js:132` reaplicava **`#2dc46f` cravado** em `.woot-widget-bubble:hover`;
- isso **não aparecia na tela**, porque `IFrameHelper` escrevia `chatIcon.style.background` **inline**,
  e estilo inline vence regra de folha sem `!important`;
- ou seja: **o literal estava morto** — e ressuscitaria **no instante exato** em que alguém removesse
  o inline em favor da variável. Que é precisamente o que este bloco faz.

Um bloco executado pela metade (var no holder, inline removido, `sdk.js:132` esquecido) entregaria um
lançador na cor da inbox que **fica verde ao passar o mouse**, em produção, no mouse do visitante.

### O mecanismo, e por que ele não é um `.spec.js`

O defeito é de **cascade**. jsdom não resolve `:hover` nem calcula cascade de folha injetada — um
teste em jsdom daria **verde com o defeito vivo**, que é exatamente a falha que esta onda existe para
não repetir. O mecanismo é Chromium real:

```
node app/javascript/sdk/specs/browser/launcher-hover.check.mjs
```

Extensão `.check.mjs` de propósito: o `include` do vitest é `app/**/*.{test,spec}.?(c|m)[jt]s?(x)`,
então ele não é coletado. E **não** carrega `playwright.config.js` — logo não sobe `webServer` nenhum
e **não toca nas portas fixas** 3038/3999/8899, compartilhadas com as outras trilhas.

### Vermelho ANTES — o mesmo check, contra o `sdk.js` de antes do bloco

```
 FAIL  lançador em repouso usa a cor da inbox
        esperado=rgb(0, 156, 224)  recebido=rgb(45, 196, 111)
 FAIL  lançador EM :hover continua na cor da inbox
        esperado=rgb(0, 156, 224)  recebido=rgb(45, 196, 111)
 FAIL  nenhum #2dc46f em declaração do SDK_CSS
 FAIL  a regra :hover usa var(--w-brand)
1/5 asserções ok
```

**`rgb(45, 196, 111)` é `#2dc46f`.** Com a inbox configurada em `#009CE0`, o lançador media **verde** —
em repouso *e* em hover. Não é dedução de leitura de código: é o Chromium reportando.

### Verde DEPOIS

```
  ok   lançador em repouso usa a cor da inbox            rgb(0, 156, 224)
  ok   lançador EM :hover continua na cor da inbox       rgb(0, 156, 224)
  ok   ícone herda --w-on-brand por currentColor         rgb(0, 0, 0)
  ok   bubbleHelpers pinta o path com currentColor, não com branco cravado
  ok   nenhum #2dc46f em declaração do SDK_CSS
  ok   os únicos hex em declaração são os 3 tokens fixos  #F2F3F7,#ff4040,#ffffff
  ok   a regra :hover usa var(--w-brand)
7/7 asserções ok · EXIT=0
```

### Duas asserções que precisaram ser corrigidas — e o que isso ensinou

**A do ícone estava frouxa.** Ela media `getComputedStyle(path).fill` num HTML que **este próprio
arquivo escreve** com `fill="currentColor"` — passaria mesmo se `bubbleHelpers.js` seguisse cravando
`#FFFFFF`. Foi somada uma segunda que lê o arquivo real. Teste que valida a própria fixture é
tautológico, e o §10.3 proíbe.

**A do literal acusou o meu comentário.** O `SDK_CSS` explica em prosa o defeito que o bloco matou, e
a explicação cita o hex. A asserção passou a remover comentários antes de medir — e ganhou uma
segunda, mais forte, que exige que os **únicos** hex em declaração sejam os três tokens fixos
(`#F2F3F7`, `#ff4040`, `#ffffff`). Medir prosa não é medir pixel; medir *toda* declaração é.

### A divergência com o plano, declarada

A §A.1.2 ponto 32 manda `sdk.js:132` virar **`var(--w-brand-hover)`**. O aceite da §2.2 exige
`rgb(0,156,224)` **em `:hover`** — a cor da inbox, **sem** mudança de matiz. São incompatíveis: com
`--w-brand-hover` o valor medido seria `rgb(0,140,202)`.

Segui o **aceite**, por três razões: ele é o contrato do bloco; preserva o comportamento observável de
hoje (o feedback de hover vem do `box-shadow`, que continua lá); e mudar o matiz no hover é mudança de
comportamento que ninguém pediu. A §A.1.2 foi escrita **antes** de medir que o inline mascarava o
literal — quando o destino "vira `--w-brand-hover`" foi anotado, ninguém sabia que a regra estava
morta.

### Três decisões que o aceite não pedia

1. **Os tokens fixos não vão para o `:root` do host.** `--w-border`, `--w-danger` e `--w-surface` são
   declarados em `#cw-widget-holder, #cw-bubble-holder` — mesma decisão do 1.03: o documento é do
   cliente, e um site com `--w-*` próprio nos sobrescreveria.
2. **Degradação para aba antiga.** Uma aba aberta antes do deploy do 1.02 chega **sem `tokens`**. Como
   o inline que pintava a bolha saiu, sem tratamento o lançador ficaria **sem cor de fundo** até o
   próximo reload. `--w-brand` recebe `widgetColor` cru — repassar a cor da inbox **não** é calcular
   contraste — e o ícone cai no fallback `--w-surface`, que é o branco que ele já tinha.
3. **As três regras `--lighter` de cor saíram.** Existiam para pintar de escuro (`--s-700: #37546D`)
   quando a marca era clara, decisão de `isWidgetColorLighter` (brilho 299/587/114, limiar 225,
   não-WCAG). Com `--w-on-brand` decidindo por luminância, viraram **duplicatas exatas** da regra
   base. A classe continua aplicada pelo 1.03 (tem spec) como sinal semântico, mas não pinta mais
   nada — a remoção dela pertence ao bloco que refatorar o lançador.

### O spec do 1.03 mudou de forma, e isso é parte do bloco

Ele assertava o **valor do inline** (`bubble.style.background === 'rgb(0, 156, 224)'`) — que este
bloco faz deixar de existir. Passou a assertar `getAttribute('style') === null`: a forma mais forte de
dizer que o inline saiu, e o que permite ao `:hover` da folha finalmente valer. O valor efetivo migrou
para o mecanismo em browser real, onde pode ser medido de verdade.

**Commit:** `a7302d03ce` · **Vitest sdk:** 3 arquivos / 21 testes / 0 falhas
**Veredito: FECHADO.**

---

## 1.06 — A11y mínima: `lang`, `role="log"`, rótulos em pt-BR e um anel de foco que existe

**Aceite (§2.2):** *1 `[role="log"]`; todo `<button>` com nome acessível **em pt-BR**;
`outline-color` não transparente.*

### Os quatro defeitos, medidos

| # | Defeito | Medição do vermelho |
|---|---|---|
| 1 | `<html>` **sem `lang`** (WCAG 3.1.1) | `sed -n 1,6p show.html.erb` → `<html>` puro |
| 2 | **Nenhum** `role="log"` | `grep -rn 'role="log"' widget/` → vazio |
| 3 | 2 dos 3 botões só-ícone do cabeçalho **sem nome acessível**; rótulo do lançador cravado em **inglês** | `HeaderActions.vue`: só o de encerrar tinha `:title`; `bubbleHelpers.js`: `target.title = 'Open chat window'` |
| 4 | **Anel de foco do composer inexistente**, de duas formas somadas | ver abaixo |

### O defeito 4 é dois, e nenhum dos dois aparece lendo o código com atenção

**`shadow-focus` era usada e não existia.** `ChatInputWrap.vue` aplicava
`'border-w-focus shadow-focus': isFocused`, e `shadow-focus` **não estava definida em config
nenhum**. Tailwind descarta classe desconhecida em silêncio — nada quebra, o anel simplesmente não é
pintado. Medido no CSS compilado:

```
.shadow-focus   → 0 ocorrências
.shadow-overlay → 1 ocorrência     ← controle, para provar que a medição funciona
```

**`outline-none` pinta um anel transparente.** O utilitário do Tailwind gera
`outline: 2px solid transparent`. O Chromium, com o composer focado:

```
[{"id":"composer","style":"solid","width":"2px","color":"rgba(0, 0, 0, 0)"}]
```

Um anel **sólido de 2px totalmente transparente** — invisível para quem navega por teclado, e que
passa em qualquer teste de marcação. É o A5 do 22 §D.5, agora com número. Trocado por `outline-0`,
que zera a largura em vez de pintar um fantasma. No `PhoneInput` o `outline-none` ainda **contradizia
um `outline outline-1` da mesma classe**.

### Verde DEPOIS

```
### a11y.spec.js (jsdom, i18n REAL de pt_BR.json)
  ✓ existe EXATAMENTE um [role="log"], e ele tem nome acessível em pt-BR
  ✓ não declara aria-live junto de role="log" (o papel já implica polite)
  ✓ todo <button> tem nome acessível não vazio
  ✓ os nomes são as strings de pt-BR, não inglês cravado
  ✓ title e aria-label não divergem
  ✓ pt_BR e en têm as 4 chaves de A11Y, e nenhuma está vazia
  Tests  6 passed (6)

### show_lang_spec.rb          VERMELHO antes: 4 examples, 4 failures  (`+<html>`)
  4 examples, 0 failures

### focus-ring.check.mjs       VERMELHO antes: 0/5
  ok  ChatInputWrap não aplica outline-none em classe nenhuma
  ok  .shadow-focus existe no CSS compilado
  ok  o anel de foco desenha (box-shadow não é "none")
  ok  o anel usa a cor do token, não uma cor própria
  ok  nenhum anel com largura > 0 e cor transparente
  5/5 asserções ok · EXIT=0
```

### Três decisões de método que valem registrar

1. **O spec do `lang` não grepa `lang=`, ele AVALIA o ERB.** O defeito interessante não é a ausência
   do atributo — é `lang="pt_BR"`, que é tão inútil para o leitor de tela quanto nenhum e **passaria
   por qualquer grep**. O spec renderiza a linha `<html …>` com um duplo de `@web_widget` e assere
   `lang="pt-BR"` **e** que o underscore não sobreviveu. Também cobre locale de uma parte (`en`) e
   locale que chega como símbolo, porque `account.locale` é enum.
2. **O anel de foco é medido com as classes EXTRAÍDAS do componente**, não escritas no teste. Um
   teste que escreve a própria fixture mede a si mesmo — o §10.3 chama isso de tautológico e proíbe.
3. **`toHaveLength(3)`, não `>= 2`.** A primeira versão do spec usava piso, e o piso deixaria passar
   um botão que parasse de renderizar — quando era justamente **um botão não observado** que estava
   sem nome. O aceite virou o número exato.

### O rótulo do lançador: por que ele atravessa a ponte

O lançador vive no documento do **host**, fora do bundle do widget, e não alcança o i18n do Vue. A
tradução vem do painel pela ponte que **já existia** para o texto do modo expandido (`setBubbleLabel`)
— o painel é quem tem os 40 locales. Limitação declarada: nos milissegundos até o painel montar, o
`title` é o texto do upstream, salvo quando o cliente define `launcherTitle`. Deixar o botão **sem**
nome nesse intervalo seria pior para o leitor de tela do que um nome no idioma errado.

**Commit:** `77ae16a956` · **Suítes:** vitest 70 arq./669 testes · rspec 26 exemplos · dashboard 394 arq./3910 testes
**Veredito: FECHADO.**

---

## 1.07 — Typing dots em CSS, e o `transform` ganha curva

**Aceite (§2.2):** *Nenhuma requisição a `typing.gif`; `getAnimations()` na abertura não devolve
`linear` em `transform`.*

### Vermelho ANTES

```
./public/assets/images/typing.gif                                  19296 bytes
./app/javascript/widget/assets/images/typing.gif                   19296 bytes
AgentTypingBubble.vue:14:  src="assets/images/typing.gif"

getAnimations() na abertura:
[{"prop":"opacity","easing":"linear"},{"prop":"transform","easing":"linear"}]
                                                            ^^^^^^^^^^^^^^^^
```

**19.296 B exatos** — o número da §12, confirmado. E o `transform` da abertura em `linear`: o painel
subia a velocidade constante, que é o que faz uma superfície parecer **empurrada** em vez de aberta.

### Verde DEPOIS

```
getAnimations() na abertura:
[{"prop":"opacity","easing":"linear"},{"prop":"transform","easing":"cubic-bezier(0.05, 0.7, 0.1, 1)"}]

  ok   as três curvas da casa estão declaradas no host
  ok   a abertura monta transição de transform
  ok   nenhuma transição de transform com easing linear
  ok   o transform da abertura usa a curva de ENTRADA
  ok   o transform de saída do lançador usa a curva de SAÍDA
  5/5 asserções ok        (VERMELHO antes: 1/5)

  Tests  5 passed (5)     typingDots.spec.js
  typing.gif do widget: Bin 19296 -> 0 bytes
```

A `opacity` **continua `linear`, de propósito**: em opacidade pura `linear` é o correto, e o aceite
fala de `transform`. As 10 transições de `transform 300ms ease` do lançador também passaram às curvas
da casa — **5 de entrada e 5 de saída**, decididas pelo seletor (`woot--hide` = saindo). Os `linear`
que sobraram estão em `visibility` e `bottom` com duração **0ms**, que é truque de delay e não
movimento.

### Por que o aceite manda medir com `getAnimations()`, e não ler o CSS

Porque as três curvas moram em `_tokens.scss`, que **só é carregado dentro do iframe** — e o holder e
o lançador vivem no documento do host. Uma `var()` não declarada ali cai para o valor inicial e o
easing volta ao padrão **sem que uma linha do CSS mude**. Foi exatamente esse o risco: as curvas
tiveram de ser declaradas também em `#cw-widget-holder, #cw-bubble-holder`, e o check assere os três
valores lidos por `getComputedStyle` no host antes de medir a animação.

### O que os pontos em CSS ganharam além do peso

- **0 requisição, 0 byte de rede** contra 19.296 B baixados na primeira vez que um agente digitava.
- Acompanham o tema. O GIF tinha **fundo branco cravado** — em tema escuro era um retângulo claro.
- `prefers-reduced-motion: reduce` para de saltar e passa a **pulsar em opacidade**. `animation: none`
  apagaria a informação de que o agente está digitando, que é o oposto do que a preferência pede.
- `role="status"` com nome em pt-BR em vez de `alt` de imagem: um estado que muda deve ser anunciado
  como estado.

**Commit:** `327001f281` · **Suítes:** vitest 71 arq./674 testes · dashboard 394 arq./3910 testes
**Veredito: FECHADO.**

---

## 1.08 — Peso: o CSS do widget deixa de carregar o projeto inteiro

**Aceite (§2.2):** *CSS do widget ≤ **80 KB crus** (hoje **1.692.256** no artefato pós-merge);
logo < 5 KB; `grep -o "@font-face" <css do widget>` → 0 (hoje são 7).*

### Vermelho ANTES — medido no artefato de um `bin/vite build` real

```
CSS do widget ....... 1.692.204 B crus   (teto 81.920 B = 80 KiB)   → 20,6× o teto
@font-face .......... 7                  (aceite: 0)
fontes .woff2 ....... 773.684 B no grafo do widget
logo (brand-assets) . 98.279 B           (aceite: < 5.120 B)
```

Os **1.692.204 B** confirmam a correção da §12 (1.692.256, diferença de 52 B são os comentários que
os blocos 1.04–1.07 acrescentaram) e enterram o número da §2.2 (1.103.132). Os **7 `@font-face`**
também batem.

### A causa, em uma frase

`tailwind.config.js` declara um `content` que varre `dashboard/**`, `portal/**`, `survey/**`,
`v3/**`, os `.erb` do enterprise e os helpers do dashboard. O CSS do widget é gerado por esse mesmo
config — então o visitante do site do cliente baixava, em rede móvel, toda utilitária que **qualquer**
superfície do produto usa.

### Verde DEPOIS — com um aceite que NÃO fechou, e o número que prova por quê

```
CSS do widget ....... 100.717 B crus   ✗ +18.797 B ACIMA do teto de 81.920 B
redução ............. 94,0%            (o plano exigia −95,3%)
@font-face .......... 0                ✓
fontes .woff2 ....... 0 B no grafo     ✓  (eram 773.684 B)
CSS gzip no gate .... 12.928 B              (era 156.363 B)
```

### Como se chega de 1.692.204 a 100.717, em quatro passos medidos

| Passo | O que muda | Efeito |
|---|---|---|
| `content` próprio (`tailwind.widget.config.js` + `@config`) | saem as utilitárias de dashboard/portal/survey/v3 | 1.692.204 → **101.741 B** |
| `shared/components/ui/**` fora do `content` | saem 8 ícones que o widget nunca renderiza | **−8.529 B** |
| `@tailwindcss/typography` fora do config do widget | saem 16.536 B de `prose` para **um** título | **−16.536 B** |
| **componentes do dashboard que o widget renderiza** | **entram** — sem eles a tela `unread` quebra | **+27.619 B** |
| | | **= 100.717 B** |

### O teto de 80 KB não fechou, e a razão foi descoberta pelo mecanismo deste bloco

O `content` restrito tem uma falha de modo silenciosa: arquivo fora do `content`
não tem classe gerada, e nada avisa. Escrevi `specs/tailwindWidgetContent.spec.js`
para cobrir isso — e **na primeira execução ele reprovou o meu próprio trabalho**,
listando 23 arquivos descobertos. A cadeia, medida a partir de
`entrypoints/widget.js`:

```
router.js → views/UnreadMessages.vue → UnreadMessageList.vue → UnreadMessage.vue
  → dashboard/components-next/avatar/Avatar.vue
      → icon/Icon.vue, GalleryView.vue → button/Button.vue, spinner/Spinner.vue
```

**O widget renderiza componentes do dashboard.** A tela de mensagens não lidas é
uma das **quatro** que os 16 snapshots cobrem. A escolha ficou explícita:

| | CSS | teto | tela `unread` |
|---|---|---|---|
| sem os componentes do dashboard | **73.098 B** | ✓ fecha, margem 8.822 B | **sem estilo** |
| com eles (caminhos exatos) | **100.717 B** | ✗ +18.797 B | **correta** |

Escolhi a tela correta e **não afrouxei o teto**. O caminho para 80 KB é
desacoplar a tela de não lidas do `Avatar` do dashboard — refatoração de
componente, e este bloco é explicitamente *"peso sem tocar componente"*. Fica
escalado, com o número que o torna decidível: **27.619 B**, ou 34% do teto.

**Caminhos exatos, não globs.** `components-next/icon/**` traz sete arquivos —
dois deles `*.story.vue`, que nunca renderizam em produção — e custa **30.625 B
só ele**. Nomeando `Icon.vue`, os seis caem de 103.903 para 71.560 B de
utilitárias. Glob aqui é imprecisão paga em bytes.

**A diretiva `@config` tem uma pegadinha de caminho, e ela custou um build.** O caminho é relativo ao
arquivo que o **PostCSS** recebe — que é o bloco `<style lang="scss">` de `widget/App.vue`, porque o
Sass já concatenou o `@import` antes. A base é `app/javascript/widget/` (três níveis até a raiz), não
`…/assets/scss/` (cinco). Com cinco, o build falha em 1 min com
`The config file at "…" does not exist` — erro alto, não silencioso, o que é a virtude aqui.

### O que o plano inferia e agora está medido

A §A.1.1 ponto 25 dizia, marcado **[INFERÊNCIA]**: *"nenhum arquivo de `widget/` importa
`MultiselectDropdown`; o componente entra no CSS do widget pelo glob `shared/**/*.vue` do Tailwind,
não por render."* Confirmado por medição: percorrendo o **fecho de imports estáticos** a partir de
`entrypoints/widget.js`, o widget alcança **206 arquivos**, **47** deles em `shared/` — e **nenhum**
em `shared/components/ui/`. Os ícones que vinham de lá (`i-lucide-sparkles`, `i-lucide-bot`,
`i-lucide-plus`, …) eram 8.529 B que o visitante baixava sem nunca ver. `StarRating` e `EmojiPicker`,
que o widget **de fato** renderiza, ficaram — e os ícones deles continuam no CSS.

### O `prose` de 16 KB para um título

`grep -rn prose` em tudo que o widget renderiza devolve **uma** linha: o título do CSAT, com
`prose prose-bubble`. O `@tailwindcss/typography` cobrava por ela 16.536 B — estilos para h1–h6,
listas, tabelas, `pre`, `blockquote` e imagens, num título de uma linha. O título recebeu, no
`<style scoped>` que já tinha, o estilo mínimo do markdown que de fato aparece nele (ênfase, link,
código inline). É a única vez que este bloco "toca componente", e está dita aqui por isso.

### O mecanismo que reprovou o próprio bloco

`specs/tailwindWidgetContent.spec.js` ataca pelo caminho oposto ao do glob: parte da entrada,
percorre os `import` e exige que todo arquivo **com classe** esteja coberto pelo `content`. As duas
fontes são independentes — código e config —, então não é tautológico. Ele tem quatro asserções, com
pisos altos (`> 150` arquivos no fecho) para não passar por vacuidade, e foi ele que achou os
componentes do dashboard. Se alguém importar um componente de `shared/components/ui/` no widget, ele
vermelhece **nomeando o arquivo**.

```
  ✓ o fecho de imports foi calculado de verdade
  ✓ todo arquivo com classe que o widget carrega está coberto pelo content
  ✓ nada de shared/components/ui/ entrou no fecho — é a exclusão do bloco
  ✓ não varre superfície alheia por glob amplo
  Tests  4 passed (4)
```

### O gate de peso do 0.5: o que este bloco derruba, e o que não

A task dizia que o 1.08 derruba o gate. **Não derruba, e o próprio gate explica por quê:** o teto de
300 kB é cobrado do **JS eager**, e este bloco mexe em **CSS**. Medido com dois `bin/vite build
--force`, um na base `c06ba1824e` e um aqui:

| | base `c06ba1824e` | depois (1.04–1.08) | delta |
|---|---|---|---|
| **JS eager** gzip | 422.933 B | 423.541 B | **+608 B** |
| CSS cru | 1.693.591 B | 74.520 B | **−1.619.071 B (−95,6%)** |
| CSS gzip | 156.363 B | 12.928 B | −143.435 B |
| fontes `.woff2` | 773.684 B | **0 B** | −773.684 B |
| **grafo total** gzip | 579.296 B | 436.469 B | **−142.827 B (−24,7%)** |

O gate segue vermelho no teto de JS eager — dono declarado: bloco **2.18**, que o próprio gate cita
(*"fecha o JS eager em ≤ 150 KB gzip"*).

**E sobre a "regressão nova" que o gate me atribui:** ele acusa +942 B contra a linha de base de
422.599 B. Medindo a **minha** base real, os números se separam: **+608 B são meus** (o código de
a11y, os typing dots, os tokens e o i18n dos blocos 1.04–1.07) e **+334 B já existiam em
`c06ba1824e`** — a linha de base do gate foi tirada em `redesenho-build @ 301bbdfdf9`, que é outro
commit. Não nego a regressão: 608 B é o custo real do que este trilho acrescentou, contra 142.827 B
de gzip que ele devolveu no grafo.

**Um aviso sobre medir peso nesta máquina:** a primeira medição da base saiu **inválida** e parecia
boa. `bin/vite build` respondeu `exit 0` com *"Skipping vite build. Watched files have not changed"* —
o cache pulou o build e o gate mediu o manifest do branch errado, dando dois JSONs idênticos. É o
mesmo padrão de falso verde que a lição do `assets:precompile` registra. **Para medir peso, `--force`
não é opcional**, e a prova de que rodou é `grep -c "Skipping vite build" = 0`.

### O item `logo < 5 KB` — **MOVIDO** para o bloco de branding/assets (decisão do coordenador, 18/08)

> **MOVIDO ≠ DISPENSADO.** O peso do aceite fica **intacto**: continua `< 5 KB`, continua
> **obrigatório**, e só muda de dono. Nada foi afrouxado e nada foi waived. Está escrito com estas
> palavras de propósito, porque "movido" e "dispensado" viram a mesma coisa na leitura de daqui a um
> mês se o documento não separar os dois.

**O critério da decisão:** o 1.08 mede *o que o visitante baixa*, e este arquivo **não está no que o
visitante baixa** — logo o item não é mensurável pela régua deste bloco. Um aceite que o instrumento
do bloco não alcança está no bloco errado, não no bloco frouxo.

O diagnóstico que sustenta a decisão, medido:

Este é o único aceite da trilha que não fechei. O diagnóstico, medido:

1. **O widget não consome logo nenhum de `public/brand-assets/`.** `grep` em
   `app/javascript/widget/` e `app/views/widgets/` → vazio. Quem usa são `dashboard`, `super_admin`,
   `portal` e o favicon de `vueapp.html.erb`/`_portal_head.html.erb`. Reduzir esse arquivo **não tira
   um byte** do que o visitante do widget baixa.
2. **Por que pesam.** `logo.svg` (98.279 B) e `logo_thumbnail.svg` (90.492 B) são SVGs com **imagem
   raster base64 embutida** — PNGs embrulhados em SVG, não vetores gordos.
3. **A armadilha.** Existem `logo1.svg` (5.435 B) e `logo_thumbnail1.svg` (1.386 B), que à primeira
   vista parecem "a versão otimizada que alguém já fez". **Não são.** Rasterizei os dois em Chromium e
   comparei: `logo.svg` é **"ChatSPX" com balão verde** — a marca em uso; `logo1.svg` é
   **"SPX CHAT" em azul**, identidade anterior. Trocar um pelo outro não otimizaria nada: trocaria a
   **identidade visual do produto** em quatro superfícies, três delas de outras trilhas.
4. **Os caminhos, todos precisando de decisão de quem manda:** (a) re-exportar o vetor da marca atual
   do arquivo-fonte de design — chega bem abaixo de 5 KB sem perda, mas exige o `.ai`/`.fig` que eu
   não tenho; (b) recomprimir o raster embutido — reduz muito, com perda de nitidez em retina e no
   favicon, e é mudança visual em superfícies alheias; (c) mover o item para um bloco de
   assets/branding, já que o widget não consome o arquivo.

**A prova visual, registrada aqui porque é ela que impede o próximo de "otimizar" isso.** Os dois
arquivos foram rasterizados em Chromium e comparados lado a lado:

| arquivo | bytes | o que o pixel mostra |
|---|---|---|
| `logo.svg` | 98.279 B | **"ChatSPX"**, balão **verde** — a marca em uso |
| `logo1.svg` | 5.435 B | **"SPX CHAT"**, **azul** — identidade anterior |

Comparar **tamanho de arquivo** faz `logo1.svg` parecer "a versão otimizada que alguém já fez".
Comparar **pixel** mostra que é outra marca. Trocar teria mudado a identidade do produto em quatro
superfícies — dashboard, super_admin, portal e o favicon —, três delas de outras trilhas: um bug de
marca disfarçado de otimização. Screenshots em
`$SCRATCH/logo-logo.svg-A.png` e `$SCRATCH/logo-logo1.svg-B.png`.

Não troquei o asset e **não afrouxei o aceite** para fazer passar.


**Commit:** `7d3f593cd5` · **Suítes:** vitest 72 arq./678 testes · dashboard 394 arq./3910 testes (R21)

---

### 1.08 (continuação, 18/08) — o desacoplamento autorizado, e o teto fecha

O coordenador autorizou o que o bloco não podia fazer sozinho, com uma frase que vale registrar:
**"o título cede, o número não"**. O 1.08 se chamava *"peso sem tocar componente"*; o teto de
**81.920 B permaneceu intacto**, e o que cedeu foi a restrição de não tocar componente.

**A cadeia que foi cortada.** O widget importava `dashboard/components-next/avatar/Avatar.vue` em
**três** pontos — não um, como o primeiro diagnóstico sugeria:

| Onde | Tela | Coberta por snapshot? |
|---|---|---|
| `UnreadMessage.vue` | `unread` | **sim** |
| `AgentMessage.vue` | `messages` | **sim** |
| `GroupedAvatars.vue` | cabeçalho | — |

E aquele componente, de 364 linhas, arrasta por import estático `icon/Icon.vue`, `GalleryView.vue`,
`button/Button.vue` e `spinner/Spinner.vue`. **27.619 B de utilitárias** — para um uso que soma
**cinco props**: `src`, `size`, `name`, `status`, `rounded-full`. Upload, preview em galeria, slots de
badge e overlay, tooltip e ícones lucide nunca são exercitados no widget.

**Os quatro números:**

```
CSS do widget ........ 100.717 B  →  75.500 B crus
teto ................. 81.920 B
margem ............... 6.420 B abaixo do teto           ✓ FECHA
contra a base ........ 1.692.204 B  →  −95,5%
@font-face ........... 0
fecho de imports ..... 158 → 148 arquivos
```

**`WAvatar.vue` é réplica, não redesenho.** As doze cores de iniciais, o `outline` de 1px com alfa
0,03/0,04, o badge a 35% do tamanho com mínimo de 8px e o `top`/`left` em `size − badge/1.1` são os
valores do original **copiados**, não recalculados. Duas das telas afetadas estão sob snapshot, e a
régua não se move para acomodar refatoração.

A **única** divergência é deliberada e declarada: o badge `online` era `bg-n-brand` — o literal
`#2dc46f` que o bloco 1.04 baniu de `widget/`, `sdk/` e `shared/`. Agora é `bg-w-brand`, pelo token da
inbox. **Não muda o pixel do snapshot**, porque o harness usa `widgetColor: '#2DC46F'` e não emite
tokens, então o fallback de `_tokens.scss` dá exatamente a mesma cor — verificado em
`spec/e2e/widget/harness/widget-server.mjs:83`. Com uma inbox de outra cor, o ponto de presença passa
a acompanhá-la, que é o que a onda inteira corrige.

**A guarda que impede a volta.** `tailwindWidgetContent.spec.js` ganhou a asserção de que **nenhum
`.vue` de `dashboard/`** está no fecho de imports do widget. É `.vue` de propósito: o widget ainda usa
**nove helpers `.js`** de lá (`editorHelper`, `businessHour`, `languages`, …) e helper sem classe não
gera uma linha de CSS — quem custa byte é componente. O piso do fecho caiu de 150 para 140
acompanhando o encolhimento, que é o efeito desejado, não uma tolerância afrouxada.

**Commit:** `776ea5a883` · **Suítes:** vitest 72 arq./679 testes · eslint exit 0

### A corrida dos 16 snapshots — 18/08, janela liberada pelo coordenador

```
✓  home-light-desktop      ✓  messages-light-desktop   ✓  prechat-form-light-desktop  ✓  unread-light-desktop
✘  home-light-mobile       ✓  messages-light-mobile    ✓  prechat-form-light-mobile   ✓  unread-light-mobile
✓  home-dark-desktop       ✓  messages-dark-desktop    ✓  prechat-form-dark-desktop   ✓  unread-dark-desktop
✘  home-dark-mobile        ✓  messages-dark-mobile     ✓  prechat-form-dark-mobile    ✓  unread-dark-mobile
                                                                            18 passed · 2 failed (6.0m)
```

**Os DEZESSEIS snapshots de pixel foram comparados, e os dezesseis passaram.**

Isso precisa ser dito com precisão, porque eu mesmo relatei errado na primeira leitura ("14 de 16
comparados"). No `widget.spec.js`, o `toHaveScreenshot` está na **linha 179** e a asserção de `axe`
na **193**: o pixel é comparado **antes**. Nos dois testes que falharam, o snapshot **já havia
passado** — a falha veio depois, na medição de acessibilidade. Nenhuma tela divergiu.

E os `unread-*` e `messages-*` — as duas telas onde o `WAvatar` substituiu o `Avatar` do dashboard —
passaram nos dois temas e nos dois viewports. É a prova de que a réplica é pixel a pixel: o motor foi
trocado sem mexer na carroceria.

**As duas falhas não são de pixel.** Elas quebram na asserção do `axe`, na linha 193, **antes** da
comparação de imagem — e quebram porque **melhoraram**:

```
Object {
-   "critical": 1,     ← o que a baseline exige
+   "critical": 0,     ← o que há agora
    "serious": 2,
}
```

A causa está no `page snapshot` que o próprio Playwright anexou ao erro:

```yaml
- button "Fechar o chat" [ref=f1e10]:
    - img [ref=f1e11]
```

**"Fechar o chat" é a string pt-BR que o bloco 1.06 acrescentou** (`A11Y.CLOSE_WIDGET`). O botão de
fechar só é **visível em mobile** (`.is-mobile .actions .close-button { display: block !important }`)
e estava sem nome acessível — violação crítica de `button-name`. A tabela do `baseline.json` fecha o
argumento sozinha:

| cenário | critical (baseline) |
|---|---|
| `home-*-**desktop**` | **0** — o botão não é visível |
| `home-*-**mobile**` | **1** — o botão aparece, sem nome |
| `messages-*`, `prechat-form-*` | 1 em desktop **e** mobile — violação **outra**, que persiste |
| `unread-*` | 0 |

As telas `messages` e `prechat-form` têm crítica em ambos os viewports e **continuam passando**: a
violação delas é outra, não é minha e não foi tocada.

### AUTORIZADO em 18/08 — e a régua ganhou uma correção maior que o número

O coordenador conferiu contra o disco antes de autorizar (o padrão desktop-0/mobile-1 só existe no
`home`; o rótulo está em `HeaderActions.vue:115-116`; `git log -S` aponta o commit `77ae16a956` do
1.06 como quem o introduziu) e concluiu: *"você não está apagando um vermelho — está parando de
exigir um defeito"*.

**Duas mudanças entraram, e a segunda é a que importa:**

**1. `baseline.json`, duas linhas, `critical: 1 → 0`.** O diff é de **exatamente 2 linhas**. A
primeira tentativa usou `json.dump` e **reformatou o arquivo inteiro** — 82 inserções, quebrando
todos os objetos compactos de uma linha. Revertido e refeito com edição cirúrgica sobre o texto:
reformatação em massa é proibida no fork, e aqui teria escondido a mudança real de dois números
dentro de um diff de 102 linhas. `serious` intacto, demais cenários intactos, formato preservado.

**2. A asserção deixou de ser igualdade e virou TETO.** Esta é a correção de fundo:

```js
// antes
expect(axeCounts).toEqual(baseline.measurements[scenario].axe);
// depois
expect(medido, `violações ${nivel} … ${medido} contra o teto de ${teto}`)
  .toBeLessThanOrEqual(axeEsperado[nivel]);
```

O aceite é *"nenhuma **regressão** crítica"*. `toEqual` também proibia **melhorar** — foi por isso
que o conserto do 1.06 **reprovou o próprio teste**: a régua exigia que a violação continuasse
existindo. Com teto, regressão continua reprovando exatamente como antes; o que deixa de reprovar é
o conserto. E o número só desce por **ato deliberado**: quando o medido é menor, o teste passa **e
imprime**

```
[axe] home-light-mobile MELHOROU — critical: 1 → 0.
      Baixe a linha em spec/e2e/widget/baseline.json para travar o ganho.
```

para quem viu decidir baixar a linha, em vez de o arquivo se ajustar sozinho e o ganho passar
despercebido.

**Veredito: `@font-face → 0` ✓ · CSS −95,5% ✓ · teto de 80 KB ✓ (margem 6.420 B) · 16/16 snapshots
sem regressão de pixel ✓ · `logo < 5 KB` MOVIDO para branding/assets, com o peso intacto.**

---

## Achado roteado — o `bg-white` da bolha de não lidas: **(a) INTENCIONAL**

A varredura da Onda 2 marcou `UnreadMessage.vue:96` por ter `bg-white` sem variante `dark:`, e a
pergunta era se é escolha ou defeito que alguém baselinou. **É escolha**, e a evidência que decide
está na **mesma declaração** do `_conversation.scss`:

```scss
.unread-messages .chat-bubble-wrap .chat-bubble {
  @apply border border-solid border-n-slate-5 dark:border-n-slate-11/50 text-n-black;
}
```

Ela dá variante escura **à borda** e, no mesmo gesto, mantém `text-n-black` — `#000000` fixo
(`theme/colors.js:226`). **Esquecimento não ajusta a borda para dark e deixa o resto.** Quem escreveu
pensou no modo escuro naquele nó e resolveu-o pela borda.

As outras duas evidências: o holder é despido no `SDK_CSS` (`.woot-widget-holder.has-unread-view`
zera `box-shadow`, `border` e `border-radius`), então as bolhas flutuam sobre o **site do cliente**,
cujo tema o widget não conhece; e branco com preto puro dá **21:1**, o contraste máximo possível,
legível sobre qualquer página — com a borda escura separando a bolha branca de um site escuro.

**A hipótese (b) foi descartada pelo pixel, não por raciocínio.** Comparando
`unread-light-mobile.png` e `unread-dark-mobile.png` lado a lado, o **avatar muda de cor** entre os
temas (`#E1E9FF` → `#1D2E62`) e o botão "Ver novas mensagens" também. Logo **o tema alcança aquele
nó** — a bolha não é branca por estar fora do alcance. E se fosse defeito baselinado, o texto seria
`n-slate-12` e ficaria claro sobre branco no escuro; ele é preto fixo nos dois.

**A trava**, porque determinação sem mecanismo é opinião:
`specs/browser/unread-bubble-contrast.check.mjs` monta a árvore real com o CSS compilado e mede nos
dois temas — **7/7**. Ele trava a *intenção*, não a implementação: não exige que a bolha seja branca
por ser branca, exige que o par fundo/texto mantenha **contraste máximo** em light e dark. Um
`dark:bg-n-solid-3` bem-intencionado passa no lint e na revisão; aqui ele derruba o teste com o
número na mão. A última asserção confirma que **a borda muda** entre os temas — a evidência 1 virando
teste.

O porquê ficou escrito ao lado da classe, com o caminho da evidência, para o próximo não "consertar".
**Nenhum snapshot foi tocado.** · **Commit:** `5b2151f00f`

---

## 1.23 — O contrato do SDK deixa de ser mudo

**Aceite (§2.2):** *Os 7 métodos chamados antes do boot são aplicados depois com o mesmo efeito;
chamada malformada dentro de tag do GTM não derruba as tags seguintes.*

**Escopo, conforme a §12.1:** o upstream fez metade. A fila **pré-conversa** já existe e vive no
store do painel — **não foi reimplementada**, porque uma segunda fila por cima enviaria o atributo
duas vezes. Este bloco cobre o degrau **anterior**: widget ainda não carregado.

### Vermelho ANTES

```
× nenhum dos 7 é despachado para o vazio antes do boot
  → expected [ 'set-user', …(6) ] to deeply equal []
× os 7 são aplicados depois do boot, com o mesmo efeito
× chamada malformada não derruba as tags seguintes do GTM
  → expected [Function] to not throw an error but 'Error: Identifier should be a string …'
                                                                        3 failed (3)
```

`run()` cria o iframe e retorna na mesma linha; o app leva centenas de milissegundos para montar e
escutar. Tudo que fosse chamado nesse intervalo virava `postMessage` para um documento **sem
ouvinte** — e sumia. Sem erro, sem log, sem nova tentativa. Num container do GTM, a tag que chama
`setUser` dispara junto com a que chama `run()`: é o caso **comum**, não o raro.

### Verde DEPOIS

```
✓ nenhum dos 7 é despachado para o vazio antes do boot
✓ os 7 são aplicados depois do boot, com o mesmo efeito
✓ chamada malformada não derruba as tags seguintes do GTM
✓ a Promise resolve quando a mensagem SAI, não quando é chamada
✓ o set-user NÃO sai duas vezes — a re-hidratação não duplica a fila
✓ open() duas vezes abre uma vez só
✓ close() com o painel já fechado não faz nada
✓ close() fecha quando está aberto
                                                                        8 passed (8)
```

### O achado: a segunda fila estava escondida no `IFrameHelper`

`IFrameHelper.js:220` reenviava `set-user` no `loaded` por conta própria. Duas coisas erradas:

1. **Duplicação.** Com a fila nova, um `setUser` pré-boot sairia **duas vezes** — exatamente a
   armadilha que a §12.1 descreve para a fila pré-conversa, escondida noutro lugar. `drenar()` passou
   a devolver os **rótulos** drenados, e a re-hidratação só acontece se a fila não cobriu.
2. **Formato divergente.** Mandava `window.$chatwoot.user` **cru, sem `identifier`**, enquanto
   `setUser` manda `{ identifier, user }`. O mesmo evento chegava ao painel em dois formatos,
   dependendo de quem o emitiu.

### Uma decisão de design que o próprio aceite forçou a rever — e de quem é a conta

A primeira versão deste bloco devolvia `Promise.reject` nos erros de validação, e a suíte acusou
**3 unhandled errors**. O aceite pede *"nenhuma exceção não capturada"*, e **uma `Promise` rejeitada
que ninguém observa é uma**.

**O raciocínio inteiro, porque ele é sobre quem paga a conta do defeito, não sobre o teste.** O
`sdk.js` não roda na nossa página: roda na página de terceiros. Um erro nosso não aparece no nosso
painel — aparece no **Sentry/GlitchTip do cliente**, carimbado com o domínio dele, e alguém lá vai
gastar uma tarde caçando um bug que não é dele. Nós operamos GlitchTip para a frota inteira e
sabemos exatamente o que ruído em rastreador de erro custa: ele não só desperdiça o tempo de quem
investiga, ele **treina a equipe a ignorar o rastreador**, que é onde o próximo defeito de verdade
vai aparecer. E quem integra por GTM chama `setUser(...)` e não encadeia nada — é o caso comum, não
o descuidado.

**A correção separa duas coisas que estavam coladas:** *observado internamente* e *devolvido ao
chamador*. Um handler é anexado **internamente** — que reporta no console, onde o integrador vê — e
a promessa **original** é devolvida, não a derivada do `catch`. Quem quiser tratar, trata: o
`.catch` do integrador continua funcionando. Quem não quiser, não polui o rastreador de ninguém.

O que **não** foi feito, e é a tentação óbvia: mudar o comportamento público para calar o teste —
trocar rejeição por resolução silenciosa, ou por um `{ ok: false }`. Isso teria deixado a suíte verde
apagando a informação de erro, que é justamente o que o bloco existe para acrescentar. Suíte com
**0 unhandled errors**, e o contrato público intacto.

### Regra A13 — o peso *eager* declarado, como o plano exige

Medido com `pnpm build:sdk` nos dois estados, com o trabalho guardado no stash para o "antes":

| | crus | gzip |
|---|---|---|
| antes | 32.696 B | 11.429 B |
| depois | 33.607 B | 11.710 B |
| **delta** | **+911 B** | **+281 B (+2,46%)** |

É o arquivo que **100% dos visitantes de todos os sites de todos os clientes** baixa — por isso a
§A13 exige o número no próprio aceite, e por isso ele está aqui e não numa nota.

**A folga que sobra, para quem vem depois.** O teto do `sdk.js` é **15.360 B gzip**:

```
teto ..... 15.360 B
atual .... 11.710 B
folga .....  3.650 B   (23,8% do teto)
o 1.23 custou 281 B = 1,8% do teto
```

Isso interessa em particular ao bloco **4.06** (o teaser), que o plano descreve como *"o maior
consumidor de bytes do host em todo o plano"* — DOM próprio, gatilho composto, cookie de dispensa,
avatar, chips e i18n. Ele **não herda um teto virgem: herda 3.650 B gzip**. Descobrir isso no fim,
com o código escrito, é o tipo de surpresa que faz um bloco pronto voltar para a mesa.

### O que não foi feito, e por quê

`widget/bridge/` **não existe neste branch** — é o bloco **1.09**, da trilha `o1-bridge`. O aceite
deste bloco se verifica inteiro no SDK, que é o lado que enfileira; a parte do bridge fica para
quando os dois branches se encontrarem. Fica dito para não parecer esquecimento.

**Commit:** `660eb79f62` · **Suítes:** vitest 73 arq./687 testes/0 unhandled · eslint exit 0
**Veredito: FECHADO.**

---

# Triagem de acessibilidade — as 8 violações críticas gravadas como esperadas

> Roteado pelo coordenador em 18/08. **Escopo: determinar e rotear**, consertando só o que fosse
> barato e obviamente meu. O instrumento (`axeTriagem.spec.js`) rodou uma vez no harness e **foi
> removido do repo** — ele vivia em `spec/e2e/widget/` e o `testDir` do projeto o pegaria em *toda*
> corrida das outras trilhas, consumindo a janela de um recurso que está sob tranca.

## A resposta curta: **uma regra**, e **um nó comum aos dois**

`messages-*` e `prechat-form-*` carregam a **mesma** violação crítica — `button-name`
(*"Buttons must have discernible text"*) — e o axe conta **violações, não nós**, que é por que os
dois marcam `critical: 1`.

| Cenário | nós | quem |
|---|---|---|
| `messages` | 6 | `ChatHeader.vue:32` (voltar) · 4× `MessageReplyButton.vue` · `ChatAttachment.vue:162` |
| `prechat-form` | 1 | `ChatHeader.vue:32` (voltar) |

**O botão de voltar do cabeçalho é o nó comum aos dois** — `<button class="px-2 ltr:-ml-3 rtl:-mr-3">`,
só ícone, sem `aria-label` e sem `title`. Ele sozinho explica o `critical: 1` do `prechat-form` e
entra na conta do `messages`.

## Os donos — e um aceite que regrediu na consolidação

| Botão | Arquivo | Bloco | O aceite cobre? |
|---|---|---|---|
| voltar | `ChatHeader.vue:32` | **2.06** | **Sim na tarefa original, não no bloco** — ver abaixo |
| anexo | `ChatAttachment.vue:162` | **2.05** (arquivo listado na §C.9) | **Não** — a §C.9 trata do *tamanho* do alvo (40/44), não do nome |
| responder (×4) | `MessageReplyButton.vue` | **sem dono** | — |

**O achado que vale mais que o roteamento.** A tarefa **W2.10**, que virou o bloco 2.06, tinha no
aceite (22 §linha 1633):

> `1 h1; **todos os botões com nome acessível**; nenhum text-white`

E o bloco **2.06**, na §2.2 do PLANO-MESTRE, ficou:

> `Exatamente 1 h1; nenhum text-white; alvos ≥ 44×44 em 375 px`

**A cláusula "todos os botões com nome acessível" desapareceu na consolidação**, trocada por
"alvos ≥ 44×44". As duas coisas são de acessibilidade e é fácil ler uma como a outra — mas tamanho de
alvo e nome acessível são defeitos diferentes, e o axe só reprova o segundo. **Executado pelo aceite
da §2.2, o 2.06 pode fechar com o botão de voltar ainda mudo, e os 16 continuam verdes.**

## Proposta de roteamento

1. **2.06 — restaurar a cláusula perdida.** Custo marginal **zero**: mesmo arquivo, mesmo bloco, e o
   aceite volta a ser o que a tarefa original já pedia. Fecha o nó **comum aos dois cenários**, ou
   seja, derruba `critical` de `prechat-form-*` (4 cenários) e reduz o de `messages-*`.
2. **2.05 — acrescentar nome acessível ao aceite.** `ChatAttachment.vue` já é arquivo dele pela §C.9;
   o aceite só precisa dizer que os botões de anexo/emoji, além de medir 40/44, **têm nome**.
3. **`MessageReplyButton.vue` — sem dono.** Não é composer nem cabeçalho: é o botão de responder que
   aparece no hover de **cada** mensagem (4 nós no cenário). Proposta de aceite, se virar bloco:
   *"todo botão de ação de mensagem tem nome acessível em pt-BR; `axe --rules button-name` em
   `messages-*` → 0 violações; o nome distingue a ação do conteúdo da mensagem a que se refere"*.
   Fica **de fora** deste bloco a decisão de o botão ser ou não visível só no hover, que é desenho.

## O que consertei, e por que só isso

Apenas o que era **barato e comprovadamente meu**: o `role="img"` sem nome no **`WAvatar`** — o
componente que **eu** criei no 1.08. `role="img"` **remove os filhos da árvore de acessibilidade**:
as iniciais "ML" que aparecem na tela não são lidas, e o nó é uma imagem sem nome. **O defeito veio
do `Avatar` do dashboard e eu o repliquei fielmente** — é o preço de replicar pixel a pixel, e é
justamente o tipo de coisa que só uma triagem encontra depois.

`:aria-label="name"`, **zero pixel alterado**, provado por
`specs/browser/avatar-aria.check.mjs` — que **não usa o harness trancado**: `chromium.launch()`
direto, com axe-core, mostrando a violação existir sem o label e desaparecer com ele (**4/4**).

Não encostei em `ChatHeader.vue`, `ChatAttachment.vue` nem `MessageReplyButton.vue`: são de outras
trilhas, e o combinado era rotear.

## O que fica registrado e não foi roteado

As violações **`serious`** não entraram no pedido, mas duas merecem nota porque **já têm dono**:

- `color-contrast` em `<span class="text-xs … text-white/80 …">` e no `<h2 … text-white>` do
  cabeçalho — caem no aceite do **2.06**, que já exige *"nenhum `text-white`"*.
- `color-contrast` no balão do visitante (`p` dentro de `.user.text-w-on-brand`) — vale conferir
  depois do 1.04 estar em produção: o token mudou o texto para `--w-on-brand`, e a medição do axe é
  sobre o par renderizado.

**Achado incidental, fora de escopo:** `test-results/` **é rastreado pelo git** e não está no
`.gitignore` — toda corrida de Playwright suja a árvore com screenshots e `error-context` de quem
rodou. Revertí os meus; não mexi no `.gitignore`, que é arquivo de todos.

**Commit:** `3fdbbbe54a`

---

# Fecho da trilha

## Situação por bloco

| Bloco | Aceite | Commit | Veredito |
|---|---|---|---|
| **1.01** | `woot.scss` não declara valor de token | `947e3eed54` | ✅ FECHADO |
| **1.02** | `#009CE0` → `#000000` a 6,8318:1; `#2DC46F` a 9,2371:1; cor inválida não interpolada | `e304f630ae` | ✅ FECHADO |
| **1.03** | Launcher e painel da mesma fonte; zero fórmula de contraste em JS | `c8d247c32c` | ✅ FECHADO |
| **1.04** | `grep n-brand\|getContrastingTextColor\|--widget-color` → vazio | `2e8941f02e` | ✅ FECHADO |
| **1.05** | Launcher `#009CE0` segue `rgb(0,156,224)` **em `:hover`** | `a7302d03ce` | ✅ FECHADO |
| **1.06** | 1 `[role="log"]`; todo botão com nome em pt-BR; `outline-color` não transparente | `77ae16a956` | ✅ FECHADO |
| **1.07** | Nenhuma requisição a `typing.gif`; `getAnimations()` sem `linear` em `transform` | `327001f281` | ✅ FECHADO |
| **1.08** | CSS ≤ 80 KB; `@font-face` → 0; ~~logo < 5 KB~~ (movido) | `7d3f593cd5` + `776ea5a883` | ✅ **FECHADO** — 75.500 B, 16/16 sem regressão de pixel |
| **1.23** | 7 métodos pré-boot aplicados depois; GTM não cai | `660eb79f62` | ✅ FECHADO |
| *achado* | `bg-white` do unread: intencional, travado | `5b2151f00f` | ✅ determinado |

**Nove blocos fechados com mecanismo executado**, mais o achado do `bg-white` determinado e travado.
O 1.08 fechou as duas metades: o número (**75.500 B ≤ 81.920**, margem 6.420 B) **e** a tela — 16/16
snapshots sem regressão de pixel, com os `unread-*` e `messages-*` verdes justamente onde o `WAvatar`
substituiu o `Avatar` do dashboard.

**A janela do harness foi usada e devolvida (18/08).** A corrida rodou com o coordenador tendo
conferido as portas por `ss`, e ao terminar elas foram liberadas processo a processo — nenhum
`pkill` amplo, e o Puma 3000 (ChatSPX de homologação) intocado o tempo todo. **Nenhum snapshot foi
regravado**; `--update-snapshots` não foi usado em nenhum momento.

**Uma pendência administrativa, não técnica:** aguardo autorização para mudar `baseline.json` de
`critical: 1` → `0` nas duas linhas de `home-*-mobile`. Nenhum `.png` seria tocado — é o registro de
*medição* de a11y, que hoje grava o defeito que o 1.06 corrigiu; enquanto disser `1`, a régua exige
que a violação crítica **volte**.

> **A regra que rege esta corrida, registrada porque decide o bloco.** Se `unread-*` ou `messages-*`
> divergirem, **isso é o aceite falando, não o teste falhando**. O caminho é ler o diff do PNG,
> descobrir o que o `WAvatar` faz diferente — raio, tamanho, fonte da inicial, cor de fundo, borda — e
> **corrigir o componente**. `--update-snapshots` está proibido, nem "só para ver": regravar
> converteria uma regressão visual real em baseline nova, em silêncio, e os 16 deixariam de ser régua
> para virar registro do que quer que esteja na tela.

## O que ficou pendente, e o que cada pendência exige

**1. Os 16 snapshots não foram regravados.** Os blocos 1.04, 1.07 e 1.08 mudam pixel **de propósito**:
a cor de texto da marca passa de `#2dc46f` a `#1d824a` (correção de 2,27:1), a cor sobre a marca vira
`#000000`, o anel de foco passa a existir e o GIF virou três pontos em CSS. Regravar exige o harness,
que usa **portas fixas 3038/3999/8899** compartilhadas com as outras três trilhas — e a regra desta
onda é pedir antes. **O coordenador está desconectado do relay** (`No owning Orca client is connected`),
então nem o pedido saiu. Nenhum snapshot foi tocado: a régua está intacta e divergirá na próxima
execução, como deve.

Onde o aceite exigia browser real, usei a **API de biblioteca** do Playwright (`chromium.launch()` +
`page.setContent()`), que não carrega `playwright.config.js`, não sobe `webServer` e **não toca em
porta nenhuma** — são os três `*.check.mjs`, com 17 asserções somadas, todas verdes, e cada um com o
vermelho de antes registrado.

**2. `logo < 5 KB` (1.08).** Não é trabalho de código: é decisão de marca. Ver o diagnóstico acima —
os dois SVGs são **identidades diferentes**, com prova visual rasterizada.

**3. Teto de 80 KB do CSS (1.08).** Falta desacoplar a tela de não lidas do `Avatar` do dashboard:
**27.619 B**, ou 34% do teto. É refatoração de componente, fora de um bloco cujo título é "peso sem
tocar componente".

**4. `sdk.js` fora da régua do gate.** O gate reporta `public/packs/js/sdk.js não existe; rode
pnpm build:sdk`. Não rodei: gerar artefato de SDK não está em nenhum aceite meu, e um `pnpm build:sdk`
sem necessidade mexeria em `public/packs/`, que não é meu. Fica anotado porque o gate conta isso como
falha nova e não é.

## Achado incidental, fora de escopo — `scripts/widget-size.mjs` é binário para o git

O arquivo do bloco 0.5 tem **um byte NUL literal** na linha 516: `const k = \`${h.file}<NUL>${h.entry}\``,
separador de chave composta escrito como byte em vez de `\x00` escapado. Consequência: `git` e `grep`
tratam o arquivo como **binário** — `git diff` não mostra o conteúdo e `grep` não imprime linha
(descobri porque meus greps nele saíam vazios, sem erro). Um `\x00` escapado resolve, com
comportamento idêntico. **Não toquei:** é arquivo de bloco já fechado e revalidá-lo não é meu escopo.
Fica registrado porque a Onda 1 inteira usa esse gate e a próxima pessoa vai tropeçar no mesmo silêncio.

## Uma nota de método, porque ela se repetiu quatro vezes

Quatro asserções minhas nasceram **erradas por medir prosa em vez de código**: o comentário que
explica por que `#2dc46f` saiu do `SDK_CSS` fazia a asserção do literal falhar; o que explica
`outline-none` fazia a do foco falhar; os que explicam a saída do `typing.gif` faziam duas do 1.07
falharem. Em todos os casos a correção foi a mesma — **remover comentários antes de medir** — e em
todos ela veio acompanhada de uma asserção **mais forte**, não mais fraca: no SDK, a lista exaustiva
dos hex que podem existir em declaração; no typing, o conjunto de atributos `src` de qualquer tag.

E uma quinta que era pior: a do ícone do launcher media `fill` num HTML que **o próprio teste
escrevia**. Passaria com `bubbleHelpers.js` cravando `#FFFFFF`. Ganhou uma segunda asserção que lê o
arquivo real. Teste que valida a própria fixture é o que o §10.3 chama de tautológico, e é o mais
fácil de escrever sem perceber.


## ⚠️ O `worker_done` não pôde ser entregue — o relay está sem coordenador

Tentei **20 vezes ao longo de 10 minutos**; toda tentativa devolveu:

```
[relay-connect] Handshake OK at version=0.1.0+a02497db1fab
No owning Orca client is connected to the relay
```

O mesmo vale para as duas escalações que este documento cita — a do item do logo e a correção sobre a
causa do reset. **Nenhuma delas chegou ao coordenador.** O handshake funciona; o que falta é o cliente
Orca do outro lado.

Consequência prática, dita sem rodeio: **este arquivo é a entrega.** O trabalho está em
`o1-widget @ 7d3f593cd5`, oito commits, árvore limpa, nada pushado — e tudo o que eu teria dito por
mensagem está escrito aqui, incluindo as duas decisões que precisam de alguém acima de mim
(`logo < 5 KB` e o teto de 80 KB), o incidente das quatro trilhas e as duas correções ao que eu mesmo
afirmei antes de ter lido o cabeçalho.

Comando para reenviar o fecho quando o coordenador voltar (o corpo está preservado em
`/tmp/done_body.txt`, e o script de retry em `/tmp/send_done.sh`):

```bash
/tmp/send_done.sh
```
