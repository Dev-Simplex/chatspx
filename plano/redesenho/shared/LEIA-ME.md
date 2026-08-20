# Fundação visual do redesenho — como usar

**Task 21.** Estes arquivos são a base dos demais mockups. Se dois mockups discordarem de uma
medida, de uma cor ou de uma duração, a resposta está aqui.

Origem de tudo: `plano/estudo-chat-web/frontend/16-spec-redesenho.md` §2 (sistema visual) e §4
(movimento), complementado por 13 (WCAG e escalas), 12 (durações medidas) e 11 (medidas dos
concorrentes). Onde esta fundação **diverge** do estudo, a divergência está declarada com a
medição que a sustenta — são cinco, listadas na §7.

---

## 1. Arquivos

| Arquivo | O que é |
|---|---|
| `shared/tokens.css` | O sistema: cor, tipografia, espaço, raio, elevação, movimento, dimensões |
| `shared/primitivos.css` | Os componentes mínimos, montados só com tokens |
| `shared/on-brand.js` | A cor do texto sobre a marca, calculada pela WCAG |
| `mockups/00-sistema-visual.html` | Página de referência: tudo renderizado, com as provas de contraste ao vivo |

A página `00-sistema-visual.html` é **standalone** — traz os três arquivos embutidos em `<style>` e
`<script>` e abre sem servidor. Os arquivos soltos existem para os outros mockups importarem.
Ela é gerada, não editada à mão: para atualizá-la, edite os `.css`/`.js` e rode o gerador
(`build.py`, no diretório de scratchpad da sessão).

---

## 2. Como importar

```html
<link rel="stylesheet" href="../shared/tokens.css">
<link rel="stylesheet" href="../shared/primitivos.css">
<script src="../shared/on-brand.js"></script>
```

Nesta ordem. `primitivos.css` só usa tokens — carregado sozinho, não pinta nada.

O `<body>` (ou o container do mockup) leva a classe `wui`, que aplica a família, o corpo de texto,
a cor e a superfície:

```html
<body class="wui"> … </body>
```

### 2.1 O tema da página, e o tema de um pedaço da página

**Página inteira:** `data-theme` no `<html>`, como sempre.

```html
<html data-theme="dark">   <!-- ou "light"; sem o atributo, vale prefers-color-scheme -->
```

**Um pedaço só** — um preview que mostra o tema *oposto* ao da página, uma amostra lado a lado,
um cartão de exemplo: as classes `wui-theme-light` e `wui-theme-dark`.

```html
<!-- preview escuro dentro de uma página clara -->
<div class="wui wui-theme-dark"> … </div>
```

A classe `wui` ao lado é o que pinta (ela aplica `background: var(--w-surface)` e
`color: var(--w-text)`); a classe de tema só troca os tokens, de propósito, para poder ser usada
num wrapper que não deve ter fundo próprio.

> ⚠️ **Não copie o bloco de tema para dentro de uma classe sua.** Foi o que aconteceu antes destas
> classes existirem: os mockups 20 e 21 criaram `.pv-claro` / `.pv-escuro` com o bloco de tema
> copiado dentro. Resultado medido pela auditoria 32 §3: **50 das 83 cores literais** de todo o
> conjunto estão nessas duas cópias — e as duas **já divergiram entre si**. Uma cópia de tema é uma
> dessincronização com data marcada.

As classes não são um segundo bloco: `wui-theme-light` entra no **mesmo seletor** do `:root` e
`wui-theme-dark` no mesmo seletor do `[data-theme="dark"]` (`tokens.css` §1, §2 e §2.8). Não há
onde dessincronizar.

**O que o escopo de tema refaz sozinho, e por quê você não precisa saber disso:** quatro tokens de
marca são calculados a partir de tokens que mudam com o tema — `--w-brand-subtle`,
`--w-on-brand-subtle`, `--w-brand-readable` e `--w-brand-border` — e custom property herda o valor
**computado**, não a fórmula (a mesma armadilha da §3.3). O `tokens.css` §2.8.1 redeclara os quatro
dentro das classes. [CALIBRADO] Sem esse bloco, um preview escuro dentro de página clara escreveria
a marca a **3,52:1** — reprova o SC 1.4.3. Com ele: **7,87:1**.

---

## 3. A cor da marca — leia esta seção inteira antes de escrever qualquer tela

### 3.1 A entrada é uma só

```css
:root { --brand: #2dc46f; }
```

Dessa cor derivam **todos** os tokens de marca. Nenhum deles se digita.

### 3.2 ⚠️ O texto sobre a marca é escrito por JS/servidor. Não dependa do fallback CSS

```html
<script>
  ChatSPXOnBrand.apply(document.documentElement, '#2dc46f');
</script>
```

`tokens.css` §3 traz a mesma fórmula em CSS puro, e ela **funciona** — medida por pixel
renderizado, com o JS desligado, acerta 8 de 8 cores incluindo as escuras. Mas ela depende de
duas capacidades do navegador (*relative color syntax* e `pow()` dentro de `calc()`). Faltando uma
delas, `--w-on-brand` fica no default `#000000`, e **para uma marca escura isso é ilegível**
(`#0b2545` com texto preto = 1,36:1). Por isso: escreva o token.

Em produção quem escreve é o **servidor** (16 §2.5.2), calculando em Ruby e entregando pronto no
HTML — o que também elimina o flash de cor errada no primeiro paint. `on-brand.js` é a
implementação de referência a ser portada.

### 3.3 ⚠️ `--brand` só funciona no `:root`

Custom property herda o **valor computado**, não a fórmula. `--w-on-brand` é declarado no `:root` e
derivado **uma vez**, do `--brand` do `:root`. Um descendente que redefina só `--brand` herda o
resultado de cima e sai errado.

[CALIBRADO] Medido por pixel, 10 cores, nos dois temas: **6 de 10 saem erradas** nesse caso — todas
as escuras viram texto preto. E ninguém percebe, porque cor de demonstração costuma ser clara e o
preto acerta por acaso.

**Para pintar mais de uma marca na mesma página**, escolha uma das duas — as duas foram medidas em
0 de 10 erradas:

```html
<!-- 1. só CSS -->
<div class="wui-brand-scope" style="--brand:#0b2545"> … </div>

<!-- 2. quando a cor vem de JS -->
<script>ChatSPXOnBrand.setOnBrand(document.querySelector('.inbox-b'), '#0b2545');</script>
```

### 3.4 A regra, em uma linha

A cor do texto sai da **luminância relativa da WCAG**, limiar `L = 0,17913` — não da heurística YIQ
que o widget usa hoje e que diverge da WCAG em 11 de 16 cores testadas, sempre escolhendo branco
onde o preto teria muito mais contraste [MEDIDO — 13 §3.2].

E o escuro é **preto puro**: com `#000000` a zona morta (cores em que nenhuma das duas escolhas
atinge 4,5:1) é 0,00%; com `#111111` são 3,42% e com `#18181b`, 6,75% das cores RGB
[MEDIDO — 13 §3.2.1, 200.000 cores].

---

## 4. Regras de uso

1. **Nunca escreva cor literal.** Toda cor sai de token. Se falta um token, peça — não invente um
   hex no mockup.
2. **Nunca escreva medida literal.** Espaço, raio, duração, tamanho e alvo de toque saem de token.
3. **Nunca use `opacity` sobre a cor da marca para gerar estado.** Opacidade muda a luminância e
   invalida o cálculo de contraste feito para a cor cheia (regra C10, 16 §2.5.1). Use
   `--w-brand-hover` / `--w-brand-pressed` / `--w-brand-subtle`.
4. **Nunca escreva `outline: none`.** Se precisar tirar o anel padrão, troque por
   `outline: 2px solid transparent` — em `forced-colors` o `transparent` é substituído por cor real
   do sistema; o `none` continua nada [FATO — 13 §1.1, padrão do GOV.UK].
5. **Não repita `@media (prefers-reduced-motion)`.** As durações já são zeradas no token
   (`tokens.css` §4.1). Basta usar `var(--w-dur-*)`.
6. **Marca como preenchimento e marca como texto são tokens diferentes** (regra C4): `--w-brand`
   pinta superfície, `--w-brand-readable` escreve texto, `--w-brand-border` desenha contorno. Cada
   um atende um critério distinto — 1.4.3 e 1.4.11 não são o mesmo requisito.
7. **Nenhuma informação só por cor** (SC 1.4.1). O par verde/vermelho colapsa de ΔE 72,5 para
   **7,9** em deuteranopia [MEDIDO — 13 §3.4]: todo status precisa de rótulo ou ícone.
8. **Nenhuma altura fixa em px em elemento que contenha texto.** Em AX1 — o primeiro dos cinco
   tamanhos de acessibilidade do iOS — o corpo vai de 17 pt para 28 pt, 1,65× [FATO — 13 §2.1].
9. **Todo `<button>` que não envia formulário leva `type="button"`.** Sem o atributo, o valor
   padrão é `submit`: dentro de um `<form>` — e as telas de configuração são formulários — um
   clique num botão de "Adicionar gatilho" recarrega a página e joga fora o que estava preenchido.
   A auditoria 32 §4 mediu **0 de 43** botões com `type` no catálogo `00-sistema-visual.html`. É
   uma palavra por botão e não tem contrapartida. Vale também para `<button>` de ícone, de fechar,
   de aba e de demonstração.
10. **Anel e elevação nunca vivem só de `box-shadow`.** Quem precisa ser uma caixa declara `border`
    real — transparente no modo normal, se o desenho não pede contorno. Em `forced-colors: active`
    o navegador **descarta `box-shadow` por inteiro**, e um componente que dependia só da sombra
    deixa de existir. Os primitivos já fazem isso; telas que criem componentes próprios precisam
    fazer também. Ver §5.3 e §8.6.

---

## 5. Os tokens

### 5.1 Marca — derivados de `--brand`

| Token | Para quê | Garantia |
|---|---|---|
| `--w-brand` | A cor crua. Superfície de marca | — |
| `--w-on-brand` | Texto e ícone **sobre** `--w-brand` | ≥ 4,5:1 pela regra da §3.4 |
| `--w-brand-hover` | Superfície de marca sob o ponteiro | ≥ 4,5:1 contra `--w-on-brand` |
| `--w-brand-pressed` | Superfície de marca pressionada (alias: `--w-brand-active`) | ≥ 4,5:1 contra `--w-on-brand` |
| `--w-brand-subtle` | Fundo tênue: chip selecionado, badge, hover de secundário | mistura, nunca `opacity` |
| `--w-brand-readable` | A marca **como texto** sobre a superfície | **≥ 4,5:1** (SC 1.4.3) |
| `--w-brand-border` | Borda, ícone sem rótulo, anel de foco | **≥ 3:1** (SC 1.4.11) |
| `--w-focus-ring` | Anel de foco (= `--w-brand-border`) | ≥ 3:1 |

Aliases curtos, iguais em conteúdo: `--on-brand`, `--brand-hover`, `--brand-pressed`,
`--brand-subtle`.

### 5.2 Superfícies e texto

| Token | Para quê |
|---|---|
| `--w-surface` | Painel, header, composer |
| `--w-surface-sunken` | Fundo da lista de mensagens |
| `--w-surface-raised` | Cartão, teaser, balão do agente |
| `--w-surface-overlay` | Popover, menu |
| `--w-surface-hover` / `--w-surface-active` | Linha de tabela e item de lista, sob o ponteiro e pressionado |
| `--w-surface-inverse` / `--w-on-inverse` | Tooltip |
| `--w-text` | Texto primário |
| `--w-text-muted` | Autor, horário, sistema, **placeholder**, branding |
| `--w-text-subtle` | **Só componente inativo** (botão e campo desabilitados) |
| `--w-border` | Divisor decorativo |
| `--w-border-strong` | Contorno de **controle** — ≥ 3:1 |
| `--w-danger` · `--w-warning` · `--w-success` · `--w-info` | Cor semântica: texto, ícone, ponto, borda |
| `--w-on-danger` | Texto **sobre** `--w-danger` (botão destrutivo) — convenção X / on-X |
| `--w-danger-subtle` · `-warning-` · `-success-` · `-info-` | Fundo da faixa correspondente |
| `--w-skeleton-base` / `--w-skeleton-sheen` | Skeleton |

> `--w-text-subtle` **não** serve para placeholder. Placeholder é texto ativo e não tem isenção no
> SC 1.4.3; usa `--w-text-muted`. `--w-text-subtle` só vale onde a WCAG isenta — "texto que faz
> parte de um componente de interface inativo".

### 5.3 Elevação — dois tokens por nível, e uma armadilha

```css
box-shadow: var(--w-elev-1), var(--w-elev-1-ring);
```

Sempre os dois. No tema claro o anel é transparente e a sombra trabalha; no escuro a sombra é
desligada e o anel de 1px assume. Sombra preta sobre fundo escuro não separa nada — o Polaris
redefine `--p-shadow-100` como `none` no dark [FATO — 13 §1.1]. Níveis: `0` (balão, chip),
`1` (cartão, teaser), `2` (launcher), `3` (painel).

> ⚠️ **"Desligada" se escreve como sombra transparente, nunca como `none`.** `box-shadow` não
> aceita `none` como item de lista: um `none` invalida a declaração inteira em tempo de valor
> computado, e os **dois** lados somem — inclusive o anel. Até 12/08/2026 o tema escuro declarava
> `--w-elev-1: none`, e o resultado medido era `box-shadow: none` em `.wui-card`,
> `.wui-btn--primary` e `.wui-tip__bubble`: a promessa "no escuro o anel assume" **não estava
> valendo** em nenhum primitivo dos níveis 1, 2 e 3. `.wui-typing` era o único de pé, porque usa
> `--w-elev-0`, que é sombra transparente. Corrigido; ver `tokens.css` §1.4.1.

**E a elevação sozinha nunca basta.** Em `forced-colors: active` o `box-shadow` é descartado
inteiro. Todo componente que precisa ser uma caixa declara `border` real — transparente no modo
normal, colorida pela §19 do `primitivos.css`. Regra 10 da §4.

### 5.4 Tipografia

Cada papel tem quatro formas: `--w-font-size-*`, `--w-line-height-*`, `--w-font-weight-*` e o
atalho `--w-text-*` para a shorthand `font:`.

```css
font: var(--w-text-message);          /* 400 15px/22px + a stack do sistema */
letter-spacing: var(--w-tracking);    /* normal em todos os papéis */
```

| Papel | px / lh / peso | Uso |
|---|---|---|
| `--w-text-message` | 15 / 22 / 400 | Corpo da mensagem (decisão F1) |
| `--w-text-message-sm` | 14 / 21 / 400 | Variante de densidade |
| `--w-text-title` | 16 / 24 / 600 | Nome no header, título de cartão |
| `--w-text-subtitle` | 13 / 18 / 400 | Linha de status |
| `--w-text-input` | **16** / 24 / 400 | Campo — abaixo de 16 o Safari iOS dá zoom |
| `--w-text-button` | 14 / 20 / 500 | Botão e chip |
| `--w-text-author` | 12 / 16 / 500 | Autor acima do grupo, rótulo de campo |
| `--w-text-meta` | 12 / 16 / 400 | Horário, recibo, contador |
| `--w-text-system` | 12 / 16 / 400 | "Hoje", mensagem de sistema |
| `--w-text-branding` | 12 / 16 / 400 | Rodapé |

Piso absoluto: 12 px. Em horário, contador e recibo, some `.wui-tabular` — sem
`tabular-nums` a largura do mesmo horário varia **52%** na Inter [MEDIDO — 13 §2.5].

#### Os três títulos das telas de configuração — trio canônico

Estes três são **novos** (12/08/2026) e existem porque a fundação só tinha título de *cartão*
(`--w-text-title`, 16/24/600). Sem um degrau acima dele, cada tela digitou o seu: a auditoria 32 §4
mediu **cinco** tamanhos de `<h1>` nos nove mockups (16, 18, 20, 22 e 34 px), e nas telas 20 e 21 o
`<h1>` saiu com **16 px** — o mesmo tamanho do `<h2>` da própria página.

| Papel | px / entrelinha / peso | Uso | Token de tamanho |
|---|---|---|---|
| `--w-text-page-title` | 20 / 1,25 (25px) / **700** | Título da página. **Um por tela.** | `--w-fs-page-title` |
| `--w-text-section` | 15 / 1,4 (21px) / **650** | Título de cartão de seção | `--w-fs-section` |
| `--w-text-label` | 13 / 1,4 (18,2px) / **600** | Rótulo de campo | `--w-fs-label` |

```css
h1  { font: var(--w-text-page-title); letter-spacing: var(--w-tracking); }
h2  { font: var(--w-text-section); }
.rotulo { font: var(--w-text-label); }
```

Cada papel também tem as três partes soltas, no padrão do contrato: `--w-fs-*` (tamanho),
`--w-lh-*` (entrelinha) e `--w-fw-*` (peso).

> **Duas divergências declaradas, e não corrigidas.** (1) Os nomes `--w-fs-*` fogem do
> `--w-font-size-*` do resto do arquivo; vieram fixados no contrato e ficam. (2) O peso **650** não
> está no conjunto {400, 500, 600, 700} que a auditoria cobra e só rende traço próprio em fonte
> variável — medido nesta task, `system-ui` nesta máquina computa 650 e rasteriza como 700. O que
> separa seção de título de página é o **tamanho** (15 contra 20 px), não o peso.

### 5.5 Espaço, raio e dimensão

`--w-space-0 / 05 / 1 / 2 / 3 / 4 / 5 / 6 / 8 / 10 / 12` → `0, 2, 4, 8, 12, 16, 20, 24, 32, 40, 48px`

`--w-radius-0 / 1 / 15 / 2 / 3 / 4 / 5 / full` → `0, 4, 6, 8, 12, 16, 20, 9999px`
(6 = avatar · 12 = campo e cartão · 16 = painel · 20 = balão · full = launcher e chip)

`--w-radius-lg` é apelido de `--w-radius-3` (12 px) com um papel declarado: **cartão de seção das
telas de configuração**. Existe porque a auditoria 32 §4 mediu dois raios de cartão de seção no
mesmo conjunto — 16 px nos mockups 20/21 e 12 px nos 22/23 — e 16 é raio de *painel* pela semântica
que esta seção já declarava. Cartão grande com raio de painel lê como janela (32 §9, item 3).
**Escolha o papel, não o número.**

| Token | Valor | Origem |
|---|---|---|
| `--w-content-max` | 1200px | Largura útil das telas de configuração. Havia **três** (1120, 1200, 1280) no mesmo conjunto [auditoria 32 §4] |
| `--w-launcher-size` | 64px | faixa medida 54–65 [11 §C1] |
| `--w-panel-width` | 400px | a moda exata do mercado [11 §C7] |
| `--w-panel-height` | `min(640px, calc(100dvh - 104px))` | mediana 632 [11 §C7] |
| `--w-panel-min-height` | 320px | hoje é 250, que não cabe header + balão + composer |
| `--w-offset-x` / `--w-offset-y` | 20px / 104px | valor mais repetido, 5 de 9 [11 §C2] |
| `--w-header-height` | 56px | — |
| `--w-touch-min` | 24px | SC 2.5.8, AA |
| `--w-touch-mobile` | 44px | SC 2.5.5 / exigência da §8.3 do 16 |
| `--w-touch-gap` | 8px | exceção "Spacing" do SC 2.5.8 |
| `--w-bp-mobile-max` / `--w-bp-desktop` | 767.98px / 768px | ponto de corte único (16 §2.7.1) |
| `--w-z-panel` / `--w-z-launcher` | 2147483000 | empatado com o Intercom [11 §C17] |

### 5.6 Movimento

Curvas: `--w-ease-standard`, `--w-ease-enter`, `--w-ease-exit`, `--w-ease-press`.
**`linear` só para opacidade pura e rotação contínua** (spinner) [12 §A1].

Durações por interação: `--w-dur-panel-in` (300ms), `--w-dur-panel-in-opacity` (80ms, desacoplado),
`--w-dur-panel-out` (200ms), `--w-dur-launcher-hover` (150ms), `--w-dur-launcher-press` (120ms),
`--w-dur-icon-swap` (150ms), `--w-dur-message-in` (200ms), `--w-dur-typing` (1200ms) +
`--w-dur-typing-stagger` (150ms), `--w-dur-teaser-in` (250ms), `--w-dur-chip` (100ms),
`--w-dur-focus` (100ms), `--w-dur-status` (200ms), `--w-dur-skeleton` (1200ms),
`--w-dur-spinner` (600ms). Genéricos: `--w-dur-1..4` (50/100/150/200ms).

---

## 6. Os primitivos

Prefixo `wui-`, escolhido para não colidir com o Tailwind do dashboard nem com o `woot-` do widget.

`wui-btn` (`--primary` `--secondary` `--ghost` `--danger` × `--sm` `--md` `--lg` × `--icon`) ·
`wui-field` + `wui-label` + `wui-input` + `wui-textarea` + `wui-hint` + `wui-error` ·
`wui-select` · `wui-switch` · `wui-check` (checkbox e radio) · `wui-chip` + `wui-chip-group` ·
`wui-badge` · `wui-card` · `wui-table` + `wui-table-wrap` · `wui-tabs` + `wui-tab` ·
`wui-tip` + `wui-tip__bubble` (`--start` / `--end`) · `wui-banner` (`--info` `--success`
`--warning` `--danger`) · `wui-skeleton` · `wui-spinner` · `wui-avatar` · `wui-divider` ·
`wui-typing`. Utilitários: `wui-tabular`, `wui-sr-only`, `wui-brand-scope`.

Todos os estados estão renderizados em `mockups/00-sistema-visual.html` §8.

**O alvo de toque mora no primitivo.** Use `.wui-btn`, `.wui-chip`, `.wui-input`, `.wui-select`,
`.wui-textarea`, `.wui-tab`, `.wui-check` ou `.wui-switch` e o alvo vem junto: **≥ 24×24 em
qualquer largura** e **≥ 44×44 abaixo de 768 px**. Não é preciso repetir a media query, e o
modificador de tamanho (`--sm` / `--md` / `--lg`) só sobe do piso — nunca desce.
[CALIBRADO 12/08/2026] Os doze primitivos medidos em 390×844 dão 44 px de altura, e o botão de
ícone dá 44×44.

> É exatamente aqui que o widget se machucou. Ele reimplementou botão, chip e campo com prefixo
> `wchat-` em vez de usar os primitivos, e ao reimplementar **perdeu a regra**: seis alvos abaixo de
> 44 px no mobile, incluindo o botão de enviar e o CTA de handoff [MEDIDO — auditoria 32 G2]. A
> conta da aderência, na mesma medição: 3 elementos com classe `wui-` contra 66 com `wchat-`, e
> **0 de 14 botões** usando `wui-btn`. Quem escreve tela nova: use o primitivo.

**Todo componente que é uma caixa tem `border` real** — transparente quando o desenho não pede
contorno. Isso não é estética: é o que faz o componente sobreviver a `forced-colors: active`, onde
o `box-shadow` é descartado inteiro. Ver §8.7.

**O indicador de digitando é CSS puro** e substitui `assets/images/typing.gif` (19.296 B) — a única
implementação em raster de todo o corpus medido [MEDIDO — 12 §5.6, 15 §A6.3]. Um GIF não é
alcançado por media query nenhuma: não herda a cor da marca, não tem versão escura e ignora
`prefers-reduced-motion`. Desenho de referência (Octadesk/WhatsApp, o único que "lê como digitação"
[12 §5.4]): 3 pontos de **7px**, gap **4px**, ciclo **1200ms** `ease-in-out`, stagger **150ms**,
`translateY(-4px)` no pico com opacidade 0,5 → 1, e 40% do ciclo parado.

---

## 7. As cinco divergências em relação ao estudo

Todas com a medição que as sustenta. Nenhuma delas muda uma conclusão do estudo — três corrigem
contradições internas dele, uma corrige aritmética e uma troca uma convenção de mercado que não
se aplica ao nosso caso.

| # | O que o estudo diz | O que foi medido | O que esta fundação faz |
|---|---|---|---|
| **D1** | 16 §2.5.2: estado de marca "escurece se clara, clareia se escura" (direção do *state layer* do M3) | Essa direção derruba **16,3%** das cores abaixo de 4,5:1 no hover e **30,9%** no pressed. `#007aff` cai de 5,23:1 para 4,31:1 e 3,71:1; `#e11d48` para 4,06:1 e 3,65:1. [CALIBRADO — 2.018 cores] | Desloca na direção **oposta** ao texto: 0 reprovações na mesma amostra de 2.018 cores, mínimo 5,30:1 no hover e 5,88:1 no pressed. A sensação de afundar vem do movimento e da sombra interna. O M3 escapa disso porque a paleta dele é gerada e `primary` tem tom fixo; aqui a cor é arbitrária |
| **D2** | 16 §2.5.3: `--w-border: #E4E5E8` para "borda de input"; `--w-border-strong: #C9CBCF` | 1,28:1 e 1,62:1 contra `#FFFFFF`. Os dois reprovam o SC 1.4.11 (3:1) que a **própria §8.1 do 16 exige** para a borda do campo de digitação | Separa os papéis: `--w-border` é divisor decorativo; `--w-border-strong` (`#898C93`) é contorno de controle, medido em **3,37:1** |
| **D3** | 16 §2.5.4: `--w-border-strong: rgba(255,255,255,.22)` no escuro | Composto sobre `#17171A` dá **2,02:1** — reprova o SC 1.4.11 | `rgba(255,255,255,.40)`, medido em **3,78:1** |
| **D4** | Desenho convencional: texto na cor semântica sobre o fundo `-subtle` da mesma família | `--w-danger` sobre `--w-danger-subtle` = 4,36:1; `--w-warning` 4,26:1; `--w-info` 4,32:1. Para chegar a 4,5:1 o fundo teria de virar 94–98% branco, apagando o tingimento | Inverte os papéis no badge e no banner: **texto neutro** (`--w-text`, 14,4:1) e a cor semântica no **ponto/borda**, onde o requisito é 3:1 |
| **D5** | 16 §1 P2: L(`#2DC46F`) = 0,4176 · 2,25:1 com branco · 9,35:1 com preto | **L = 0,4119 · 2,27:1 · 9,24:1** [CALIBRADO]. Bate com a medição em browser do 15 §A5.4, que deu 2,27:1 | Usa os valores recalculados. A conclusão não muda: branco reprova, preto passa com folga |

---

## 8. Validação — o que foi medido, e como

**Método.** Playwright + Chromium 145, `--no-sandbox --disable-dev-shm-usage`. Contraste pela
fórmula da WCAG 2.2, com a cor lida do **pixel efetivamente pintado** (canvas), não da string CSS —
assim o número inclui o clipping de gamut que o navegador aplica em `oklch()` fora do sRGB, e a
**composição alfa** dos tokens translúcidos do tema escuro. Sem isso, `--w-border-strong` no escuro
aparece como branco puro e "passaria" com 17,89:1, quando composto ele dá 3,78:1.

Viewports: **1200×900** (desktop), **390×844** (mobile) e **320×640** (reflow, SC 1.4.10), cada um
em tema **claro** e **escuro** — seis combinações.

### 8.1 Resultado geral

| Verificação | Resultado |
|---|---|
| Erro de console | **nenhum**, nas 6 combinações |
| Exceção de página | **nenhuma** |
| Requisição externa | **nenhuma** — zero CDN, zero webfont, zero imagem remota |
| Requisição falha | **nenhuma** |
| Overflow horizontal | **nenhum**: `scrollWidth` = `clientWidth` em 1200, 390 e 320 |

### 8.2 Contraste dos pares principais

Requisito por par: 4,5:1 onde é texto (SC 1.4.3); 3:1 onde é componente, borda ou ícone (SC 1.4.11).

| Par (frente sobre fundo) | Requisito | Claro | Escuro |
|---|---:|---:|---:|
| `--w-text` sobre `--w-surface` | 4,5:1 | 16,39:1 | 15,41:1 |
| `--w-text` sobre `--w-surface-sunken` | 4,5:1 | 14,89:1 | 16,13:1 |
| `--w-text` sobre `--w-surface-raised` | 4,5:1 | 16,39:1 | 11,78:1 |
| `--w-text-muted` sobre `--w-surface` | 4,5:1 | 5,94:1 | 8,59:1 |
| `--w-text-muted` sobre `--w-surface-sunken` | 4,5:1 | 5,40:1 | 8,99:1 |
| `--w-text-muted` sobre `--w-surface-hover` | 4,5:1 | 5,40:1 | 7,62:1 |
| `--w-on-inverse` sobre `--w-surface-inverse` | 4,5:1 | 16,39:1 | 15,41:1 |
| `--w-brand-readable` sobre `--w-surface` | 4,5:1 | 5,09:1 | 7,87:1 |
| `--w-brand-readable` sobre `--w-brand-subtle` | 4,5:1 | 4,74:1 | 6,83:1 |
| `--w-danger` sobre `--w-surface` | 4,5:1 | 4,98:1 | 6,47:1 |
| `--w-on-danger` sobre `--w-danger` | 4,5:1 | 4,98:1 | 6,47:1 |
| `--w-warning` sobre `--w-surface` | 4,5:1 | 4,67:1 | 10,72:1 |
| `--w-success` sobre `--w-surface` | 4,5:1 | 5,35:1 | 10,27:1 |
| `--w-info` sobre `--w-surface` | 4,5:1 | 4,92:1 | 9,25:1 |
| `--w-text` sobre `--w-danger-subtle` | 4,5:1 | 14,35:1 | 13,17:1 |
| `--w-text` sobre `--w-warning-subtle` | 4,5:1 | 14,94:1 | 11,44:1 |
| `--w-text` sobre `--w-success-subtle` | 4,5:1 | 14,69:1 | 12,11:1 |
| `--w-text` sobre `--w-info-subtle` | 4,5:1 | 14,38:1 | 12,89:1 |
| `--w-border-strong` sobre `--w-surface` | 3:1 | 3,37:1 | 3,78:1 |
| `--w-border-strong` sobre `--w-surface-sunken` | 3:1 | 3,06:1 | 3,78:1 |
| `--w-brand-border` sobre `--w-surface` | 3:1 | 3,34:1 | 7,87:1 |
| `--w-danger` sobre `--w-danger-subtle` | 3:1 | 4,36:1 | 5,53:1 |
| `--w-warning` sobre `--w-warning-subtle` | 3:1 | 4,26:1 | 7,96:1 |
| `--w-success` sobre `--w-success-subtle` | 3:1 | 4,80:1 | 8,07:1 |
| `--w-info` sobre `--w-info-subtle` | 3:1 | 4,32:1 | 7,74:1 |
| `--w-text-subtle` sobre `--w-surface` | 3:1 † | 4,13:1 | 5,57:1 |
| `--w-text-subtle` sobre `--w-surface-hover` | 3:1 † | 3,75:1 | 4,94:1 |

**27 pares × 2 temas = 54 medições, 54 aprovações.** Pior caso: 3,06:1 no claro (requisito 3:1) e
3,78:1 no escuro.

† `--w-text-subtle` é texto de **componente inativo**, que a WCAG isenta do SC 1.4.3. Medimos
contra 3:1 mesmo assim, por disciplina.

### 8.3 A cor do texto sobre a marca — as duas vias, 23 cores

Cada cor foi passada pela via JS (`on-brand.js`, a fonte de verdade) e pela via CSS pura (o
fallback, com o token removido para o `calc` responder sozinho), e as duas comparadas com a
escolha correta da WCAG. **23 cores · 0 divergências · mínimo de contraste 4,70:1.**

Inclui as quatro exigidas — duas escuras (`#0b2545`, `#7c2d12`) e duas claras (`#f5d90a`,
`#a7f3d0`) — e a bateria do 13 §3.2.

| `--brand` | L | WCAG escolhe | via CSS | via JS | contraste |
|---|---:|---|---|---|---:|
| `#0b2545` azul-marinho **(escura)** | 0,0182 | `#ffffff` | `#ffffff` | `#ffffff` | **15,39:1** |
| `#7c2d12` marrom **(escura)** | 0,0621 | `#ffffff` | `#ffffff` | `#ffffff` | **9,37:1** |
| `#f5d90a` amarelo **(clara)** | 0,6906 | `#000000` | `#000000` | `#000000` | **14,81:1** |
| `#a7f3d0` verde-água **(clara)** | 0,7687 | `#000000` | `#000000` | `#000000` | **16,37:1** |
| `#2dc46f` o verde do fork | 0,4119 | `#000000` | `#000000` | `#000000` | **9,24:1** |
| `#009ce0` a inbox de teste | 0,2916 | `#000000` | `#000000` | `#000000` | **6,83:1** |
| `#25d366` verde WhatsApp | 0,4794 | `#000000` | `#000000` | `#000000` | **10,59:1** |
| `#1f93ff` azul Chatwoot | 0,2838 | `#000000` | `#000000` | `#000000` | **6,68:1** |
| `#007aff` azul iOS | 0,2114 | `#000000` | `#000000` | `#000000` | **5,23:1** |
| `#ffcc00` amarelo | 0,6445 | `#000000` | `#000000` | `#000000` | **13,89:1** |
| `#ff7a00` laranja | 0,3518 | `#000000` | `#000000` | `#000000` | **8,04:1** |
| `#00bcd4` ciano | 0,4072 | `#000000` | `#000000` | `#000000` | **9,14:1** |
| `#14b8a6` teal | 0,3718 | `#000000` | `#000000` | `#000000` | **8,44:1** |
| `#a3e635` lima | 0,6464 | `#000000` | `#000000` | `#000000` | **13,93:1** |
| `#f9a8d4` rosa | 0,5290 | `#000000` | `#000000` | `#000000` | **11,58:1** |
| `#6c2bd9` roxo | 0,0993 | `#ffffff` | `#ffffff` | `#ffffff` | **7,03:1** |
| `#e11d48` vermelho | 0,1735 | `#ffffff` | `#ffffff` | `#ffffff` | **4,70:1** |
| `#005c4b` verde escuro | 0,0816 | `#ffffff` | `#ffffff` | `#ffffff` | **7,98:1** |
| `#0f7a52` verde | 0,1463 | `#ffffff` | `#ffffff` | `#ffffff` | **5,35:1** |
| `#808080` cinza médio | 0,2159 | `#000000` | `#000000` | `#000000` | **5,32:1** |
| `#1f8ded` azul | 0,2546 | `#000000` | `#000000` | `#000000` | **6,09:1** |
| `#000000` preto | 0,0000 | `#ffffff` | `#ffffff` | `#ffffff` | **21,00:1** |
| `#ffffff` branco | 1,0000 | `#000000` | `#000000` | `#000000` | **21,00:1** |

**O problema do header verde está resolvido na raiz:** `#2DC46F` saía com texto branco a 2,27:1 e
agora sai com texto preto a **9,24:1**, sem ninguém decidir nada.

### 8.4 Os demais tokens de marca

Amostra de 20 cores (as da §8.3 menos as três que só existem lá). Os mínimos de `hover` e `pressed`
na varredura maior de 2.018 cores são mais apertados — 5,30:1 e 5,88:1 — e são os que valem como
piso do sistema.

| Token | Requisito | Mínimo no claro | Mínimo no escuro |
|---|---:|---:|---:|
| `--w-on-brand` vs `--w-brand` | 4,5:1 | **4,70:1** | 4,70:1 |
| `--w-brand-readable` vs `--w-surface` | 4,5:1 | **5,00:1** | **5,50:1** |
| `--w-brand-border` vs `--w-surface` | 3:1 | **3,26:1** | **3,75:1** |
| `--w-brand-hover` vs `--w-on-brand` | 4,5:1 | **5,68:1** | 5,68:1 |
| `--w-brand-pressed` vs `--w-on-brand` | 4,5:1 | **6,54:1** | 6,54:1 |

Os cortes de luminosidade OKLCH que garantem isso foram **calibrados por varredura**, não
escolhidos: 2.023 cores (23 fixas + 2.000 aleatórias, seed 42), buscando o valor mais próximo da
cor original que ainda passa em 100% da amostra.

| Derivação | Corte | Mínimo medido na varredura | Onde já reprova |
|---|---|---:|---|
| `--w-brand-readable`, claro | `min(l, 0.51)` | 4,59:1 | `0.52` reprova 1 de 2.023 |
| `--w-brand-readable`, escuro | `max(l, 0.69)` | 4,58:1 | `0.675` reprova 1 |
| `--w-brand-border`, claro | `min(l, 0.62)` | 3,01:1 | `0.63` reprova 3 |
| `--w-brand-border`, escuro | `max(l, 0.58)` | 3,07:1 | `0.565` reprova 1 |

### 8.5 O escopo de marca

Medido **por pixel renderizado**, 10 cores, nos dois temas, num descendente que redefine `--brand`:

| | claro | escuro |
|---|---:|---:|
| sem `.wui-brand-scope` | **6 de 10 erradas** | **6 de 10 erradas** |
| com `.wui-brand-scope` | **0 de 10** | **0 de 10** |

### 8.6 O que **não** foi verificado

- **Outros navegadores.** Toda medição é Chromium 145. O fallback CSS depende de *relative color
  syntax* e `pow()`; em Safari e Firefox não foi testado — e é justamente por isso que a fonte de
  verdade é o JS/servidor.
- ~~**`forced-colors: active`.**~~ **Verificado em 12/08/2026** — e havia defeito. Ver §8.7.
- **`prefers-contrast: more`.** O bloco existe, o contraste resultante continua não medido.
- **Zoom de 200% e text-spacing forçado** (SC 1.4.4 e 1.4.12): não exercitados nesta fundação. A
  auditoria 32 §8 os exercitou nos **mockups** e achou uma falha real, no `.pv__palco` das telas 20
  e 21 — que é código de mockup, não desta fundação.
- **Leitor de tela.** Os `role` e rótulos estão nos primitivos, mas nenhum leitor foi rodado.
- **Tooltip colado na borda da tela em desktop.** Em telas < 768px o tooltip deixa de flutuar e o
  problema não existe; acima disso, quem escreve a tela escolhe a âncora (`--start` / `--end`).
  Posicionamento dinâmico (anchor positioning ou JS) fica para a implementação.

### 8.7 `forced-colors: active` — verificado em 12/08/2026, e o que estava quebrado

Método: Playwright + Chromium 145, `forced_colors="active"` sobre `00-sistema-visual.html`, em
1280×900 e 390×844, com leitura do **pixel renderizado** (contagem de cores dentro da caixa de cada
componente) além do valor computado.

**A regra do modo, que o bloco anterior não seguia até o fim:** o navegador substitui *toda cor de
autor* pela cor de sistema correspondente. Sobrevive como foi escrito só quem foi escrito como
*system color*. [CALIBRADO] `--w-brand: Highlight` sai pintado `rgba(5,0,73,0.8)`; já
`--w-skeleton-base: #e9eaee` sai `rgb(255,255,255)` — Canvas, o mesmo fundo. **Token não mapeado
não vira outra cor: vira o fundo.** Só 16 dos 34 tokens de cor estavam mapeados.

**E `box-shadow` é descartado inteiro.** A estratégia de "anel de 1px" da §5.3 é, nesse modo,
exatamente nada. Quem sobrevive é quem tem `border` real.

O que isso produzia, medido pelo preenchimento dominante da caixa de cada componente:

| Componente | Antes | Depois |
|---|---|---|
| `.wui-skeleton` | **100% Canvas** — uma barra branca sobre fundo branco | 95% Canvas + 5% CanvasText: a caixa contornada aparece |
| `.wui-tip__bubble` | **85% Canvas**, o texto da página aparecendo por baixo | 56% CanvasText + 37% Canvas: balão cheio, texto vazado |
| `.wui-avatar__dot` | **100% Canvas** — o ponto de presença não existia | 62% Canvas (o anel) + 16% CanvasText (o ponto) |
| `.wui-badge` | sem delimitação, texto solto | cápsula contornada |

Na captura da página inteira, a §8.10 do catálogo ("Skeleton e spinner") era **uma coluna vazia**.

**As três correções:**

1. Os **34** tokens de cor mapeados, não 16 (`tokens.css` §4.3).
2. `border` real, transparente no modo normal, em `.wui-skeleton`, `.wui-tip__bubble`, `.wui-typing`
   e `.wui-badge`. A §19 do `primitivos.css` só acende a cor — assim nenhum componente muda de
   tamanho ao entrar em alto contraste.
3. `--w-text-muted: CanvasText`, não `GrayText`. `GrayText` é a cor que o sistema reserva para
   conteúdo **inativo**, e `--w-text-muted` pinta autor, horário, linha de status, descrição de
   cartão, cabeçalho de tabela, placeholder e rodapé — todos ativos [auditoria 32 M7].
   `--w-text-subtle` fica em `GrayText`, porque ali é o papel certo: a §5.2 já o declara como "só
   componente inativo".

Resultado das seis combinações depois da correção: **0 erro de console, 0 exceção, 0 overflow
horizontal**, e os quatro componentes acima visíveis em 1280 e em 390.

**Continua não verificado aqui:** o modo de alto contraste real do Windows (a emulação do Chromium
usa a paleta padrão, não a do usuário) e as paletas de alto contraste que invertem para fundo
escuro.

---

## 9. Risco de merge com o upstream

Nada aqui toca o repositório: são arquivos novos em `plano/redesenho/`, uma árvore que não existe no
upstream. O risco aparece **na implementação**, não neste plano, e o 16 §6.1 já dá a regra: peça
nova mora em arquivo novo, em pastas que o upstream não tem (`widget/ui/`,
`widget/message-types/`, `widget/bridge/`), com cascas finas nos arquivos que o upstream mais mexe.

O widget está praticamente virgem — **4 commits** do fork tocaram `widget/` ou `sdk/` em toda a
história, 14 arquivos e 98 inserções contra a v4.12.1 — enquanto o upstream mudou **113 arquivos do
widget** entre a nossa base e a v4.16.2 (+4.332 −7.635) [MEDIDO — 15 §B12.1 e §B12.4]. Uma
repaginada total transformaria uma área "quase idêntica ao upstream" em "totalmente reescrita".

**Consequência direta para estes arquivos:** quando `tokens.css` virar código, ele vai para um
arquivo próprio — **nunca** dentro de `woot.scss`, que é o pior dos dois mundos: o upstream mexe
**e** o fork já reescreveu 32 linhas [MEDIDO — 15 §B12.3]. O prefixo `--w-` foi escolhido pela
mesma razão: não sequestra o `--n-` do design system do dashboard nem nada do upstream.

**Esforço de portar esta fundação para o código:** **P** para os dois CSS (arquivos novos, sem
conflito). **M** para o cálculo no servidor, porque envolve `show.html.erb`, o evento `config-set`
do SDK e a paridade Ruby ↔ JS descrita no 16 §2.5.2 — e é aí que o risco real mora, não no CSS.

---

## Correções aplicadas em 12/08/2026 (pós-auditoria)

Esta rodada respondeu à auditoria adversarial `plano/redesenho/auditoria/32-mockups.md`, itens 6, 7
e 8 da §10, mais a §3. **Só a fundação mudou** — `tokens.css`, `primitivos.css` e este arquivo.
Nenhum mockup foi tocado; os nove trazem a fundação embutida e precisam ser regerados para receber
o que está aqui.

| # | O que mudou | Onde | Achado que fecha |
|---|---|---|---|
| 1 | Três papéis de título: `--w-fs-page-title` (20/700/1,25), `--w-fs-section` (15/650), `--w-fs-label` (13/600), cada um com `--w-lh-*`, `--w-fw-*` e o atalho `--w-text-*` | `tokens.css` §1.5.1 · LEIA-ME §5.4 | 32 §10 item 8 — cinco tamanhos de `<h1>` em nove páginas |
| 2 | `.wui-theme-light` / `.wui-theme-dark`, no **mesmo seletor** do `:root` e do `[data-theme="dark"]`, mais as quatro derivações de marca que o escopo precisa refazer | `tokens.css` §1, §2, §2.8, §2.8.1 · LEIA-ME §2.1 | 32 §10 item 7 — 50 das 83 cores literais estão nas cópias `.pv-*`, que já divergiram |
| 3 | Os **34** tokens de cor mapeados em `forced-colors`, não 16; `--w-text-muted: CanvasText` | `tokens.css` §4.3 · LEIA-ME §8.7 | 32 G3 e M7 |
| 4 | `border` real (transparente no modo normal) em skeleton, tooltip, typing e badge; §19 só acende a cor | `primitivos.css` §11, §13, §7, §17, §19 | 32 G3 — três componentes desapareciam |
| 5 | Piso de alvo 24×24 no próprio `.wui-btn`, e `--icon.--sm` na lista do bloco mobile | `primitivos.css` §1, §18 · LEIA-ME §6 | 32 §5 (SC 2.5.8) e o cabeçalho do próprio arquivo, que prometia o piso e não entregava sem modificador de tamanho |
| 6 | `--w-radius-lg` (12px, cartão de seção) e `--w-content-max` (1200px) | `tokens.css` §1.7, §1.9 · LEIA-ME §5.5 | 32 §4 — dois raios de cartão e três larguras úteis no mesmo conjunto |
| 7 | `type="button"` e "anel nunca só por `box-shadow`" viram regras 9 e 10 | LEIA-ME §4 · cabeçalho do `primitivos.css` | 32 §10 item 9 — 0 de 43 botões com `type` no catálogo |

### Um achado que não estava na auditoria

Ao aplicar a prescrição do G3, medi que **`none` dentro de uma lista de `box-shadow` invalida a
declaração inteira**. Como o tema escuro declarava `--w-elev-1/2/3: none` e os primitivos escrevem
`box-shadow: var(--w-elev-1), var(--w-elev-1-ring)`, o valor computado dava `box-shadow: none` em
`.wui-card`, `.wui-btn--primary` e `.wui-tip__bubble`: **o anel do tema escuro nunca existiu** nos
níveis 1, 2 e 3. `.wui-typing` era o único de pé, por usar `--w-elev-0` (sombra transparente).
Corrigido escrevendo sombra desligada como `0 0 0 0 transparent`. Detalhe e medição em
`tokens.css` §1.4.1 e na §5.3 acima.

### Divergências declaradas nesta rodada

- **Nome dos tokens de título.** `--w-fs-*` foge do `--w-font-size-*` do resto do arquivo. Veio
  fixado no contrato desta rodada e foi mantido; os atalhos `--w-text-*` fazem a ponte.
- **Peso 650.** Fora do conjunto {400, 500, 600, 700} e sem traço próprio fora de fonte variável —
  medido, `system-ui` desta máquina rasteriza como 700. Mantido; o degrau real é o tamanho.
- **Aritmética da auditoria, sem efeito no achado.** O G3 diz "18 dos 34 tokens não são remapeados"
  e a prosa nomeia 16 + "e mais quatro" = 20. Conferido um a um: **18** está certo, e os dois que a
  prosa não nomeou são `--w-brand-active` e `--w-on-brand-subtle`. Este último já caía de pé por
  acidente (é `var(--w-text)`, que já resolvia em `CanvasText`); está mapeado explicitamente agora.

### O que esta rodada não fez

- **Não regerou os nove mockups.** Eles embutem `tokens.css` e `primitivos.css` em `<style>`, e as
  cópias embutidas continuam com a fundação anterior. Toda a validação acima foi feita injetando os
  arquivos de `shared/` em tempo de execução sobre `00-sistema-visual.html` — que é exatamente o
  que a regeração vai produzir.
- **Não apagou as classes `.pv-*`** dos mockups 20 e 21. A ferramenta para isso está pronta
  (§2.1); a troca é dos mockups.
- **Não mexeu nos `<h1>`, nas larguras nem nos raios de cartão** das telas. Os tokens existem; usá-los
  é trabalho de quem edita as telas.
