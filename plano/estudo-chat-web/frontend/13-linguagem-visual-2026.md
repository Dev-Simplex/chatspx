# 13 — Linguagem visual e boas práticas de UI para 2026

**Constituição visual do redesenho do widget ChatSPX**

| | |
|---|---|
| **Data da apuração** | 11/08/2026 |
| **Fase** | Estudo. Nenhuma implementação, nenhum arquivo de código tocado. |
| **Escopo** | O que é boa prática de interface de chat em 2026, com fonte — não "como o fulano faz". |
| **Ferramentas** | Playwright + Chromium 145.0.7632.6 (headless, `--no-sandbox --disable-dev-shm-usage`), `curl`, scripts próprios em Python, WebSearch/WebFetch |
| **Saída** | Este documento + 12 pranchas em `shots/t13-*.png` |

---

## Atalho: se você só vai ler três coisas

1. **§12 — As 15 regras inegociáveis.** É a decisão condensada, cada regra com âncora e teste.
2. **§10 — A constituição visual.** São os tokens: tipografia, espaço, raio, elevação, movimento, cor, alvos, layout.
3. **§13.2 — O bug que a apuração encontrou.** O cálculo de contraste do balão colorido está errado hoje, em produção, e o número para corrigir está na §3.2.1.

Se for ler uma quarta: **§2.2**, a medição de caracteres por linha, porque ela é o que determina a largura do painel — e essa é a decisão de layout mais consequente do redesenho.

---

## Sumário

| § | Seção | O que responde |
|---|---|---|
| 1 | Sistemas de design de referência | O que Material 3, Apple HIG, Polaris, Atlassian, Carbon e GOV.UK prescrevem — token servido, não página de marketing |
| 2 | Tipografia em conversa | Tamanho, entrelinha, medida, hierarquia, números tabulares, webfont × stack do sistema, fonte variável |
| 3 | Cor e contraste | WCAG aplicado a chat, o balão de marca, daltonismo, dark mode, cor semântica, APCA |
| 4 | Acessibilidade além da cor | WCAG 2.2 novos critérios, `role="log"`, live regions, foco, i18n, media queries de preferência |
| 5 | Densidade e layout | Quanto cabe, quanto de tela ocupa, bottom sheet, safe areas, `dvh`, anatomia da bolha, catálogo de estados |
| 6 | Tendências 2025/2026 | Liquid Glass, M3 Expressive, blur, cantos, dark, ilustração × foto — só com data e fonte |
| 7 | O que irrita o usuário | Better Ads (66.000 consumidores), regra do Google, NN/g popups, NN/g chatbots |
| 8 | Performance percebida | Os três limites, Core Web Vitals, skeleton × spinner, orçamento de tempo |
| 9 | Padrões de UI de IA | Streaming, transparência, 18 diretrizes HAX, citação, feedback, handoff |
| 10 | **A constituição visual** | Os tokens propostos |
| 11 | Checklist de a11y | Passa/falha, verificável |
| 12 | **As 15 regras inegociáveis** | |
| 13 | O que isso significa para o ChatSPX | Recomendação, lacunas e ordem de ataque |

---

## Como ler este documento

Toda afirmação numérica traz uma marca de procedência. Elas não são decorativas — elas dizem quanto peso a afirmação aguenta.

| Marca | Significa |
|---|---|
| **[MEDIDO]** | Número que **eu** produzi nesta apuração, com o comando/script indicado. Reprodutível. |
| **[FATO]** | Número ou texto lido em fonte primária (spec, documentação oficial, CSS servido, release oficial), com URL. |
| **[FATO·2ª]** | Fonte secundária respeitada, sem confirmação em fonte primária. Vale menos. |
| **[INFERÊNCIA]** | Conclusão minha a partir de fatos declarados. O fato está acima; a conclusão é minha e pode ser contestada. |
| **[NÃO VERIFICADO]** | Não consegui verificar. Está aqui porque a lacuna importa, não porque a afirmação vale. |

**Duas advertências de método que valem para o documento inteiro:**

1. **Não generalizo de uma superfície para outra.** Onde eu medi Inter, digo Inter — não digo "as fontes de UI". Onde medi no Chromium desktop, não afirmo nada sobre Safari iOS sem dizer que não testei.
2. **Rejeitei fontes de "tendências" sem lastro.** Durante a apuração, buscas por "chat UI trends 2026" devolveram artigos afirmando coisas como "balões bem desenhados aumentam o engajamento em até 72%" e "usuários passam 200% mais tempo com mensagens que têm emoji". Não encontrei estudo primário para nenhum desses números. Eles **não** entram neste documento como evidência — entram na §6.9 como exemplo do que não usar para decidir.

---

# 1. Sistemas de design de referência

Seis sistemas, lidos no que prescrevem para densidade, tipografia, espaço, raio, elevação, cor, alvo de toque e foco. Onde havia pacote npm publicado, li o **token servido**, não a página de marketing.

## 1.1 O que cada um prescreve — tabela comparativa

### Escala tipográfica: corpo de texto

| Sistema | Token do corpo | Tamanho | Entrelinha | Peso | Fonte do dado |
|---|---|---|---|---|---|
| **Material 3** | `body-large` | 1rem (16px) | 1.5rem (24px) | 400 | [FATO] `unpkg.com/@material/web/tokens/versions/v0_192/_md-sys-typescale.scss` |
| **Material 3** | `body-medium` | 0.875rem (14px) | 1.25rem (20px) | 400 | idem |
| **Material 3** | `body-small` | 0.75rem (12px) | 1rem (16px) | 400 | idem |
| **Apple HIG (iOS)** | `Body` @ Large (default) | 17 pt | 22 pt | Regular | [FATO] HIG › Typography › Specifications |
| **Apple HIG (iOS)** | `Footnote` | 13 pt | 18 pt | Regular | idem |
| **Apple HIG (iOS)** | `Caption 2` | 11 pt | 13 pt | Regular | idem |
| **Polaris (Shopify)** | `text-body-md` | 0.8125rem (13px)¹ | 1.25rem (20px) | 450 | [FATO] `unpkg.com/@shopify/polaris-tokens/dist/css/styles.css` |
| **Polaris** | `text-body-lg` | 0.875rem (14px)¹ | 1.25rem (20px) | 450 | idem |
| **Atlassian** | `font.body` | 0.875rem (14px) | 1.25rem (20px) | Regular | [FATO] atlassian.design/foundations/typography |
| **Atlassian** | `font.body.large` | 1rem (16px) | 1.5rem (24px) | Regular | idem |
| **IBM Carbon** | `body-01` (step 2) | 0.875rem (14px) | 1.28572 (18px) | 400 | [FATO] `unpkg.com/@carbon/type/scss/_styles.scss` + `_scale.scss` |
| **GOV.UK** | `.govuk-body` / `body-m` | 1.1875rem (19px) | 1.3158 (25px) | 400 | [FATO] `unpkg.com/govuk-frontend/dist/govuk/govuk-frontend.min.css` |
| **GOV.UK** | `.govuk-body-s` | 1rem (16px) | 1.25 (20px) | 400 | idem |

¹ Polaris publica dois conjuntos no mesmo CSS (breakpoint responsivo). Registrei o valor da primeira declaração e o da segunda: `body-md` = `font-size-325` (13px) e `font-size-400` (16px); `body-lg` = `font-size-350` (14px) e `font-size-450` (18px).

**Leitura do conjunto** [INFERÊNCIA]: há dois campos distintos, e eles não estão em desacordo — estão respondendo a perguntas diferentes.

- **Ferramenta densa de trabalho** (Atlassian, Polaris, Carbon): corpo em **14 px**. O usuário fica horas na tela, quer ver muito de uma vez, está sentado.
- **Consumidor / mobile-first** (Material, Apple, GOV.UK): corpo em **16–19 px**. Uso esporádico, ambiente ruim, telefone na mão, público não treinado.

O GOV.UK é o extremo deliberado: 19 px de corpo, porque o público é "toda a população do Reino Unido", inclusive quem tem baixa visão e nenhuma familiaridade com a interface.

**Um widget de chat de site é do segundo campo, não do primeiro.** Quem digita nele é um visitante anônimo, muitas vezes no celular, muitas vezes na rua. A régua do Atlassian (14 px) é a régua errada para essa superfície — ela é a régua certa para o **painel do atendente**, que é outra tela.

### Escala de espaçamento

| Sistema | Base | Degraus (px) | Fonte |
|---|---|---|---|
| **Material 3** | 4 px | grade de 4 e 8 | [FATO] tokens de shape/space M3 |
| **Atlassian** | **8 px** | 0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80 | [FATO] atlassian.design/foundations/spacing |
| **Polaris** | 4 px | 0, 1, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96, 112, 128 | [FATO] `--p-space-*` no CSS servido |
| **IBM Carbon** | 2 px | 2, 4, 8, 12, 16, 24, 32, 40, 48, 64, 80, 96, 160 | [FATO] `@carbon/layout/scss/generated/_spacing.scss` |

**Nota importante sobre o Atlassian** [FATO]: eles declaram base 8 px, mas a escala publicada inclui `space.025` = 2 px e `space.075` = 6 px, que **não** são múltiplos de 8. Na prática, todos os quatro sistemas convergem para uma **escala de 4 px com degraus finos de 2 px na faixa baixa**. Quem diz "base 8" está descrevendo o ritmo dominante, não a régua real.

### Raios

| Sistema | Escala publicada | Fonte |
|---|---|---|
| **Material 3** | none 0 · extra-small 4 · small 8 · medium 12 · large 16 · extra-large 28 · full 9999 | [FATO] `_md-sys-shape.scss` v0.192 |
| **Polaris** | 0 · 2 · 4 · 6 · 8 · 12 · 16 · 20 · 30 · full (624.9375rem) | [FATO] `--p-border-radius-*` |
| **GOV.UK** | `border-radius: 0` em botão | [FATO] `.govuk-button{...border-radius:0...}` |

Note o salto do M3: **16 → 28**, sem 20 nem 24. Isso é intencional — o `extra-large` (28 px) é o raio de bottom sheets e diálogos, e o vão entre 16 e 28 evita que o time invente meio-termos.

Note também que **o GOV.UK não tem raio nenhum no botão**. Um sistema desenhado exclusivamente para clareza funcional decidiu que canto arredondado não paga o próprio custo. Não é uma recomendação para nós — é a prova de que "cantos arredondados" é escolha estética, não requisito de usabilidade.

### Elevação

| Sistema | Modelo | Valores | Fonte |
|---|---|---|---|
| **Material 3** | 6 níveis em dp: 0, 1, 3, 6, 8, 12 | Renderizados como **duas** sombras (key + ambient); `level1` = `0 1px 2px 0` com opacidade 0.3 na key | [FATO] `_md-sys-elevation.scss` + `@material/web/elevation/internal/_elevation.scss` |
| **Polaris** | 7 níveis | `shadow-100` = `0 1px 0 0 rgba(26,26,26,.07)` … `shadow-600` = `0 20px 20px -8px rgba(26,26,26,.28)` | [FATO] CSS servido |

Ponto técnico que vale registrar [FATO]: no tema escuro do Polaris, `--p-shadow-100` é redefinido como **`none`**. O sistema não escurece a sombra no dark mode — ele **desliga** a sombra e passa a separar as superfícies de outro jeito. Isso não é detalhe: é a resposta deles para o problema descrito na §3.5.

### Estados de interação (state layers)

| Estado | Opacidade da camada | Fonte |
|---|---|---|
| hover | 0.08 | [FATO] `_md-sys-state.scss` v0.192 |
| focus | 0.12 | idem |
| pressed | 0.12 | idem |
| dragged | 0.16 | idem |

### Movimento

| Token M3 | Duração | Token M3 | Curva |
|---|---|---|---|
| `short1`…`short4` | 50 / 100 / 150 / 200 ms | `easing-standard` | `cubic-bezier(0.2, 0, 0, 1)` |
| `medium1`…`medium4` | 250 / 300 / 350 / 400 ms | `easing-emphasized` | `cubic-bezier(0.2, 0, 0, 1)` |
| `long1`…`long4` | 450 / 500 / 550 / 600 ms | `easing-emphasized-decelerate` | `cubic-bezier(0.05, 0.7, 0.1, 1)` |
| `extra-long1`…`4` | 700 / 800 / 900 / 1000 ms | `easing-emphasized-accelerate` | `cubic-bezier(0.3, 0, 0.8, 0.15)` |

[FATO] `unpkg.com/@material/web/tokens/versions/v0_192/_md-sys-motion.scss`

### Alvo de toque

| Sistema | Valor | Natureza | Fonte |
|---|---|---|---|
| **WCAG 2.2 SC 2.5.8** | **24 × 24 CSS px** | Nível **AA** — obrigatório para conformidade AA | [FATO] w3.org/TR/WCAG22/#target-size-minimum |
| **WCAG 2.2 SC 2.5.5** | **44 × 44 CSS px** | Nível **AAA** | [FATO] w3.org/TR/WCAG22/#target-size-enhanced |
| **Apple HIG iOS** | **44 × 44 pt** = *default control size* | Recomendação, não mínimo | [FATO] HIG › Accessibility |
| **Apple HIG iOS** | **28 × 28 pt** = *minimum control size* | Mínimo declarado pela Apple | [FATO] idem |
| **Apple HIG macOS** | 28 × 28 pt default / 20 × 20 pt mínimo | | [FATO] idem |
| **Material 3 (toque)** | **48 × 48 dp** | Recomendação | [FATO] m3.material.io/foundations/designing/structure |
| **Material 3 (ponteiro)** | **44 × 44 dp** | Mínimo para mouse/stylus | [FATO] idem |
| **Material 3 (espaçamento)** | **≥ 8 dp** entre alvos | Recomendação | [FATO] idem |
| **GOV.UK** | `input` de checkbox/radio com **44 × 44 px** literais | Implementação, não recomendação | [FATO] `.govuk-checkboxes__input{width:44px;height:44px}` |

O Material 3 é o único que justifica o número em unidade física [FATO]:

> *"Para a maioria das plataformas, considere fazer alvos de toque de pelo menos **48 × 48dp**. Um alvo desse tamanho resulta num tamanho físico de cerca de **9 mm**, independentemente do tamanho da tela. O tamanho de alvo recomendado para elementos de tela sensível ao toque é **7–10 mm**."*

E ele separa explicitamente alvo de **toque** (48 dp) de alvo de **ponteiro** (44 dp), o que nenhum dos outros faz. Também registra que *"o alvo de toque se estende além dos limites visuais do elemento: um ícone pode parecer ter 24 × 24 dp, mas o padding ao redor compõe o alvo completo de 48 × 48 dp."* [FATO] — ou seja, o alvo é a **área de acerto**, não o desenho. Isso resolve o falso dilema entre "ícone pequeno e bonito" e "alvo grande".

**Correção de um mito difundido** [FATO]: a Apple **não** exige 44×44 pt. Ela publica duas colunas na mesma tabela — *default control size* 44×44 pt e *minimum control size* 28×28 pt. Quem cita "a Apple exige 44" está lendo metade da tabela. O número obrigatório em ambiente web é o da WCAG: **24 px**, nível AA.

A HIG acrescenta uma regra de espaçamento que quase ninguém cita [FATO]: *"em geral funciona bem adicionar cerca de 12 pontos de padding em torno de elementos que têm bezel. Para elementos sem bezel, cerca de 24 pontos funciona bem."*

### Estados de foco

O GOV.UK é o único dos seis com uma solução visual **medida e opinada** para foco. Li o CSS servido:

```
.govuk-link:focus   { outline:3px solid transparent; background-color:#fd0;
                      box-shadow:0 -2px #fd0, 0 4px #0b0c0c; text-decoration:none }
.govuk-button:focus { border-color:#fd0; outline:3px solid transparent;
                      box-shadow:inset 0 0 0 1px #fd0 }
.govuk-input:focus  { outline:3px solid; outline-color:#fd0; outline-offset:0;
                      box-shadow:inset 0 0 0 2px #0b0c0c }
```
[FATO] `unpkg.com/govuk-frontend/dist/govuk/govuk-frontend.min.css`

Três decisões embutidas aí, que valem para qualquer produto:

1. **`outline: 3px solid transparent`** — outline transparente em vez de `outline:none`. Isso preserva o indicador de foco no **modo de alto contraste forçado** do Windows, onde o `transparent` é substituído pelo sistema. `outline:none` apagaria o foco lá.
2. **Amarelo `#fd0`** — escolhido para ter contraste tanto contra fundo claro quanto escuro.
3. **A barra preta inferior (`0 4px #0b0c0c`)** — resolve o caso em que o amarelo cai sobre um fundo amarelado e sumiria.

Ver prancha: `shots/t13-foco-espacamento-raios.png`.

## 1.2 O que os sistemas de referência **não** resolvem para chat

Nenhum dos seis prescreve:

- medida (caracteres por linha) em painel estreito;
- hierarquia entre mensagem / autor / horário / mensagem de sistema;
- comportamento do `role="log"` durante streaming de IA;
- escolha automática de cor de texto sobre cor de marca arbitrária.

Essas quatro lacunas são exatamente o que as seções 2, 3, 4 e 9 deste documento preenchem — com medição própria, já que não há prescrição a citar.

---

# 2. Tipografia em interface de conversa

## 2.1 O tamanho mínimo legível — o que dá para afirmar

Não existe piso de tamanho de fonte na WCAG. O que existe é [FATO]:

- **SC 1.4.4 Resize Text (AA)**: *"o texto pode ser redimensionado sem tecnologia assistiva até 200 por cento sem perda de conteúdo ou funcionalidade"*.
- **SC 1.4.12 Text Spacing (AA)**: nenhuma perda de conteúdo ao forçar entrelinha ≥ 1,5× o tamanho da fonte, espaço entre parágrafos ≥ 2×, letter-spacing ≥ 0,12× e word-spacing ≥ 0,16×.

O piso concreto que existe vem da Apple [FATO — HIG › Typography › Specifications]:

| Plataforma | Tamanho padrão | Tamanho mínimo |
|---|---|---|
| iOS, iPadOS | 17 pt | **11 pt** |
| macOS | 13 pt | 10 pt |
| visionOS | 17 pt | 12 pt |
| watchOS | 16 pt | 12 pt |

Ver prancha: `shots/t13-apple-hig-dynamic-type-large-default.png`.

E a escala Dynamic Type do iOS em Large (default), que é a régua real de milhões de usuários [FATO]:

| Estilo | Tamanho | Entrelinha |
|---|---|---|
| Headline | 17 pt (Semibold) | 22 pt |
| **Body** | **17 pt** | **22 pt** |
| Callout | 16 pt | 21 pt |
| Subhead | 15 pt | 20 pt |
| Footnote | 13 pt | 18 pt |
| Caption 1 | 12 pt | 16 pt |
| Caption 2 | 11 pt | 13 pt |

E o teto. Além dos sete tamanhos padrão (xSmall → xxxLarge), o iOS publica **mais cinco tamanhos de acessibilidade: AX1 a AX5** [FATO]. Já em **AX1** — o primeiro dos cinco — o **Body vai a 28 pt com 34 pt de entrelinha** [FATO], contra 17/22 do padrão: **1,65× maior**. Os valores de AX2 a AX5 não capturei nesta apuração [NÃO VERIFICADO], mas são progressivamente maiores.

Esse é o número que quebra layouts. Um balão desenhado para 15 px precisa continuar funcionando quando o corpo passar de 1,6× — o que significa: **nenhuma altura fixa em px**, em lugar nenhum do widget.

**Regra derivada** [INFERÊNCIA]: nada abaixo de **12 px** no widget, para nenhum papel — nem timestamp, nem rótulo de sistema. O Caption 2 do iOS é 11 pt, mas 11 pt no iOS renderiza com o `-apple-system` otimizado para telas Retina; 11 px de CSS em um monitor de 1080p não é a mesma coisa. 12 px é o piso seguro.

## 2.2 A medida (caracteres por linha) — o achado central

A regra clássica de tipografia (Bringhurst, e replicada por praticamente todo manual de tipografia editorial) é **45 a 75 caracteres por linha** para leitura confortável de texto contínuo.

**Medi o que realmente cabe num painel de chat.** [MEDIDO]

Método: HTML local, fonte Inter 400 embutida como `data:` URI (`document.fonts.load()` antes de medir, para não medir fallback), texto de teste = mensagem real de atendimento em pt-BR com 293 caracteres, contagem de caracteres por linha via `Range.getBoundingClientRect()` caractere a caractere no Chromium 145 headless. Padding lateral do painel 12 px, padding da bolha 12 px.

| Painel | Bolha | Corpo | Largura da bolha | Largura do texto | **Caracteres/linha** | Linhas |
|---|---|---|---|---|---|---|
| 320 px | 85% | 15/22 | 252 px | 228 px | **27,9** | 12 |
| 360 px | 85% | 15/22 | 286 px | 262 px | **32,6** | 11 |
| 380 px | 85% | 14/21 | 303 px | 279 px | **38,4** | 9 |
| 380 px | 85% | 15/22 | 303 px | 279 px | **34,1** | 10 |
| 380 px | 85% | 16/24 | 303 px | 279 px | **32,6** | 11 |
| 380 px | 88% | 15/22 | 313 px | 289 px | **37,0** | 9 |
| **400 px** | **88%** | **15/22** | **331 px** | **307 px** | **39,4** | **9** |
| 400 px | 88% | 16/24 | 331 px | 307 px | **36,2** | 10 |
| 420 px | 88% | 14/21 | 348 px | 324 px | **45,0** | 8 |
| 420 px | 88% | 15/22 | 348 px | 324 px | **42,3** | 8 |
| 440 px | 88% | 15/22 | 366 px | 342 px | **45,0** | 8 |
| 440 px | 88% | 16/24 | 366 px | 342 px | **42,3** | 8 |

Tabela completa (36 combinações) na prancha `shots/t13-medida-caracteres-por-linha.png`.

**Conclusão medida, e ela é dura:**

> **Num painel de chat de 380–400 px, a medida fica entre 32 e 39 caracteres por linha. A faixa clássica de 45–75 é estruturalmente inatingível. Com corpo de 16 px, nem um painel de 440 px chega a 45.**

Isso muda o que se pode prescrever. Não adianta "respeitar a medida ideal" — ela não cabe. O que resta são três alavancas, e elas são as decisões reais:

1. **Aumentar a largura do painel.** 420 px @ 88% com corpo 14 px atinge exatamente 45,0 caracteres. O custo é ocupar mais tela.
2. **Compensar com entrelinha.** Linha curta com entrelinha generosa lê melhor do que linha curta apertada, porque o olho precisa de menos precisão para achar a linha seguinte. Por isso 1,45–1,5 e não 1,3.
3. **Controlar o comprimento da mensagem na origem.** Uma mensagem de 293 caracteres vira **9 a 12 linhas** de balão. Isso é um parágrafo de blog dentro de um balão. O limite não é de CSS, é de redação: a mensagem do bot e do atendente precisa ser curta.

Largura média por caractere que medi, em texto pt-BR real [MEDIDO]:

| Fonte | px/caractere @15px | em/caractere |
|---|---|---|
| Inter 400 | 7,29 | 0,486 |
| Roboto 400 | 6,93 | 0,462 |
| Nimbus Sans (≈ Arial/Helvetica) | 6,90 | 0,460 |
| Lato 400 | 6,68 | 0,445 |
| DejaVu Sans | 7,82 | 0,521 |

Regra de bolso derivada [INFERÊNCIA]: **≈ 0,47 em por caractere** para pt-BR em sans-serif de UI. Para *n* caracteres por linha, a largura de texto necessária é `n × 0,47 × tamanho_da_fonte`.

## 2.3 Entrelinha

| Fonte | Prescrição | Referência |
|---|---|---|
| WCAG SC 1.4.12 | Deve **suportar** 1,5× sem quebrar (não é obrigação de usar) | [FATO] w3.org/TR/WCAG22/ |
| Material 3 `body-large` | 24/16 = **1,5** | [FATO] token |
| Material 3 `body-medium` | 20/14 = **1,43** | [FATO] token |
| Apple iOS Body | 22/17 = **1,29** | [FATO] HIG |
| Atlassian `font.body` | 20/14 = **1,43** | [FATO] doc |
| Carbon `body-01` | **1,28572** | [FATO] `_styles.scss` |
| GOV.UK `body-m` | 25/19 = **1,32** | [FATO] CSS servido |

[INFERÊNCIA] Os sistemas de produto ficam em 1,28–1,43; o Material, que é o mais mobile/consumidor da lista, vai a 1,5. Dado que a medida do nosso painel é curta (§2.2) e linha curta se beneficia de entrelinha maior, **1,45–1,5 é a escolha certa para a bolha de mensagem** — mais alta que a média dos sistemas de produto, e de propósito.

## 2.4 Hierarquia: mensagem / autor / horário / sistema

Quatro papéis de texto convivem numa conversa, e eles precisam ser distinguíveis **sem** depender de cor (§4).

| Papel | Proposta | Justificativa |
|---|---|---|
| **Mensagem** | 15 px / 22 px, peso 400 | O único texto que o usuário lê palavra por palavra |
| **Nome do autor** | 12 px / 16 px, peso 500 | Metadado; o peso, não o tamanho, faz a distinção |
| **Horário / recibo** | 12 px / 16 px, peso 400, **`tabular-nums`**, cor secundária | Nunca compete com a mensagem |
| **Mensagem de sistema** | 12 px / 16 px, peso 400, centralizado, cor secundária | "Hoje", "Você entrou na conversa", "Transferido para um atendente" |

Ver prancha: `shots/t13-escala-tipografica-mensagem-light.png` e `shots/t13-escala-tipografica-mensagem-dark.png`, com as três variantes de corpo (14/15/16) lado a lado no mesmo painel de 400 px.

**Regra estrutural** [INFERÊNCIA]: a hierarquia entre mensagem e metadado deve ser feita por **peso e cor**, não por tamanho, porque a diferença de tamanho disponível é pequena demais (15 → 12 são três pixels). Se ela fosse feita só por tamanho, o metadado teria que ir para 10–11 px e cruzaria o piso de legibilidade da §2.1.

## 2.5 Números tabulares — medição própria, resultado contraintuitivo

Medi a largura de sete horários (`00:00`, `11:11`, `10:38`, `22:47`, `09:05`, `23:59`, `18:00`) renderizados a 12 px, com e sem `font-variant-numeric: tabular-nums`. [MEDIDO]

| Fonte | Sem `tabular-nums` | Com `tabular-nums` |
|---|---|---|
| **Inter 400** | amplitude **12,00 px** (de 23 px em "11:11" a 35 px em "00:00") | amplitude **0,00 px** |
| Roboto 400 | amplitude 0,00 px | 0,00 px |
| Nimbus Sans (≈ Arial/Helvetica) | amplitude 0,00 px | 0,00 px |
| DejaVu Sans | amplitude 0,00 px | 0,00 px |

Ver prancha: `shots/t13-tabular-nums.png`.

**Isso é o oposto do que quase todo mundo assume.** A crença corrente é "hoje toda fonte de UI já é tabular por padrão". Não é: **Inter usa algarismos proporcionais por padrão**, e a variação chega a 52% na largura do mesmo horário. Roboto, Arial e Helvetica não têm o problema.

**Regra** [INFERÊNCIA]: se a stack tipográfica incluir Inter — e ela é a escolha default de metade do mercado de UI, inclusive do Polaris [FATO: `--p-font-family-sans: 'Inter', -apple-system, ...`] — então `font-variant-numeric: tabular-nums` em horários, contadores e recibos **não é refinamento, é requisito**. Sem ele, a coluna de horários de uma conversa longa fica visivelmente desalinhada.

Escopo do que medi: quatro fontes, no Chromium 145, em Linux. **Não testei SF Pro nem Segoe UI Variable** (não estão disponíveis nesta máquina), portanto não afirmo nada sobre elas. [NÃO VERIFICADO]

## 2.6 Stack do sistema × webfont — por que quase todo widget usa a do sistema

Quatro razões, em ordem de peso:

1. **Peso e tempo até renderizar.** O widget é código de terceiro injetado no site do cliente. Uma webfont é mais um recurso na rede antes de o texto aparecer. Os arquivos que baixei para medir: Inter latin 400 = **23.664 bytes**, Inter latin 500 = **24.272 bytes**, Roboto latin 400 = **21.884 bytes** [MEDIDO — `curl -w %{size_download}` em `unpkg.com/@fontsource/*`]. Dois pesos de Inter = ~48 KB só de fonte, antes de qualquer CSS ou JS.
2. **FOUT / FOIT.** Com `font-display: swap` o texto pisca e reflui; com `block` ele fica invisível até a fonte chegar. Num widget que precisa parecer instantâneo, ambos são ruins.
3. **CSP.** O site do cliente pode ter `Content-Security-Policy` restritiva. Se a `font-src` não permitir nosso domínio nem `data:`, a webfont simplesmente não carrega — e o widget cai num fallback que ninguém desenhou. Esse é um risco de terceiro que não temos como testar em todos os clientes.
4. **Coerência.** O texto do widget parece pertencer ao sistema operacional do visitante, não a um site de terceiro.

O Carbon resolve isso declarando fallbacks explícitos [FATO]: `'IBM Plex Sans', system-ui, -apple-system, BlinkMacSystemFont, '.SFNSText-Regular', sans-serif`. O Polaris faz igual com Inter na frente.

**Recomendação** [INFERÊNCIA]: stack do sistema, sem webfont, no widget. Se houver decisão de marca por uma webfont, ela precisa vir com: subset latin apenas, `data:` URI ou `font-src` documentado para o cliente, `size-adjust`/`ascent-override` calibrados contra o fallback para não haver salto de layout, e um pixel de teste de que a CSP do cliente permite. O custo dessa decisão é operacional, não estético.

## 2.7 Fontes variáveis — medição, não folclore

A crença corrente é "fonte variável é sempre mais leve". Medi. [MEDIDO — `curl -w '%{size_download}'` em `unpkg.com/@fontsource*`, subset latin, woff2]

| Arquivo | Bytes |
|---|---|
| Inter **variável** (`inter-latin-wght-normal.woff2`, eixo de peso completo) | **48.256** |
| Inter estática 400 | 23.664 |
| Inter estática 500 | 24.272 |
| Inter estática 600 | 24.452 |

| Cenário | Estáticas | Variável | Vencedor |
|---|---|---|---|
| 1 peso (400) | 23.664 | 48.256 | **estática**, por 24.592 bytes (a variável é 2,04× maior) |
| 2 pesos (400+500) | 47.936 | 48.256 | **estáticas**, por 320 bytes — empate técnico |
| 3 pesos (400+500+600) | 72.388 | 48.256 | **variável**, economiza 24.132 bytes (−33%) |
| 4 pesos | ~96.800 | 48.256 | **variável**, −50% |

**O ponto de virada é 3 pesos.** [MEDIDO]

[INFERÊNCIA] A escala tipográfica proposta na §10.1 usa **dois** pesos (400 e 500). Nesse cenário a fonte variável não traz ganho de peso nenhum — traz 320 bytes a mais. Ela só passaria a valer se o design decidisse usar 600 ou 700 além dos dois, ou se fosse usar interpolação de peso em animação (o que um widget de chat não precisa).

Nota de suporte [FATO — webstatus.dev]: `font-variation-settings` é Baseline widely available desde 05/09/2018. Suporte não é o problema; peso é.

---

# 3. Cor e contraste

## 3.1 Os critérios, com o texto

[FATO] Todos transcritos de `w3.org/TR/WCAG22/`:

- **SC 1.4.3 Contraste (Mínimo) — AA**: *"A apresentação visual de texto e imagens de texto tem uma razão de contraste de pelo menos **4,5:1**"*, exceto texto grande (**3:1**), texto incidental e logotipos.
- **SC 1.4.6 Contraste (Aprimorado) — AAA**: *"pelo menos **7:1**"*; texto grande **4,5:1**.
- **SC 1.4.11 Contraste Não-Textual — AA**: *"pelo menos **3:1** contra as cores adjacentes"* para (a) informação visual necessária para **identificar componentes de interface e seus estados** e (b) partes de gráficos necessárias para entender o conteúdo.
- **SC 1.4.1 Uso da Cor — A**: *"A cor não é usada como o único meio visual de transmitir informação, indicar uma ação, solicitar uma resposta ou distinguir um elemento visual."*
- **SC 2.4.13 Aparência do Foco — AAA**: a área do indicador de foco é *"pelo menos tão grande quanto a área de um perímetro de 2 CSS px de espessura do componente não focado"* e tem *"razão de contraste de pelo menos 3:1 entre os mesmos pixels nos estados focado e não focado"*.

Observação de escopo que costuma ser esquecida: **SC 1.4.11 se aplica à bolha**. Se a bolha do agente é um cinza claro sobre fundo branco e a distinção entre "bolha" e "fundo" é necessária para entender a conversa, esse par precisa de 3:1 — ou a distinção precisa vir de outra coisa (borda, alinhamento).

## 3.2 O problema do balão colorido — medição própria

Este é o problema clássico: o cliente escolhe a cor da marca, o widget pinta o balão do visitante com ela, e o texto por cima precisa ser legível. Praticamente todo fornecedor resolve escolhendo automaticamente entre texto branco e texto escuro.

**Medi as duas regras concorrentes.** [MEDIDO — script Python próprio, fórmula de luminância relativa da WCAG]

O ChatSPX hoje usa uma heurística YIQ em `app/javascript/shared/helpers/colorHelper.js` (leitura, não alteração):

```js
const brightness = (c_r * 299 + c_g * 587 + c_b * 114) / 1000;
return brightness > 225;
```

Comparei essa heurística com a regra correta (luminância relativa da WCAG) em 16 cores de marca:

| Cor | Luminância | Texto #fff | Texto #000 | WCAG escolhe | YIQ>225 escolhe | Conflito |
|---|---|---|---|---|---|---|
| `#1f93ff` azul Chatwoot | 0,2838 | **3,15** | 6,68 | preto | branco | **SIM** |
| `#25d366` verde WhatsApp | 0,4794 | **1,98** | 10,59 | preto | branco | **SIM** |
| `#007aff` azul iOS | 0,2114 | **4,02** | 5,23 | preto | branco | **SIM** |
| `#ffcc00` amarelo | 0,6445 | **1,51** | 13,89 | preto | branco | **SIM** |
| `#ff7a00` laranja | 0,3518 | **2,61** | 8,04 | preto | branco | **SIM** |
| `#00bcd4` ciano | 0,4072 | **2,30** | 9,14 | preto | branco | **SIM** |
| `#14b8a6` teal | 0,3718 | **2,49** | 8,44 | preto | branco | **SIM** |
| `#a3e635` lima | 0,6464 | **1,51** | 13,93 | preto | branco | **SIM** |
| `#f9a8d4` rosa | 0,5290 | **1,81** | 11,58 | preto | branco | **SIM** |
| `#6c2bd9` roxo | 0,0993 | 7,03 | 2,99 | branco | branco | — |
| `#e11d48` vermelho | 0,1735 | 4,70 | 4,47 | branco | branco | — |
| `#0b2545` azul-marinho | 0,0182 | 15,39 | 1,36 | branco | branco | — |

**11 conflitos em 16 cores testadas** (a tabela acima mostra 12 das 16; a lista completa incluiu ainda `#1f8ded`, `#005c4b`, `#0f7a52` e `#808080`). E o conflito é **sempre no mesmo sentido**: a heurística YIQ com limiar 225 escolhe branco onde o preto tem muito mais contraste.

Ver prancha: `shots/t13-contraste-balao-marca.png`.

O caso mais grave da amostra: **`#25d366`, o verde do WhatsApp, com texto branco, dá 1,98:1** — menos da metade do mínimo AA — quando o texto preto no mesmo fundo daria 10,59:1.

### 3.2.1 Os números que resolvem

[MEDIDO] Ponto de cruzamento: uma cor de fundo com **luminância relativa 0,17913** tem exatamente o mesmo contraste contra branco e contra preto puro. Acima disso, preto ganha; abaixo, branco.

Mas escolher entre branco e preto não basta sozinho. Existe uma **zona morta**: cores onde nenhuma das duas atinge 4,5:1. E o tamanho dela depende de quão escuro é o "preto" escolhido:

| Cor de texto escura | Fundo precisa de L ≥ | Zona morta | % de cores RGB sem saída em 4,5:1 |
|---|---|---|---|
| **`#000000`** | 0,17500 | **não existe** (−0,00833, há sobreposição) | **0,00%** |
| `#0b0b0c` | 0,19017 | +0,00683 | 1,46% |
| `#111111` | 0,20022 | +0,01689 | **3,42%** |
| `#18181b` (zinc-900) | 0,21670 | +0,03336 | **6,75%** |

(Texto branco `#fff` exige fundo com L ≤ 0,18333. Amostra de 200.000 cores RGB uniformes, seed fixa.) [MEDIDO]

**Regra derivada, e ela é precisa** [INFERÊNCIA]:

> A cor de texto escura sobre balão de marca tem que ser **`#000000` puro**, ou algo com luminância ≤ 0,0034. Com o cinza-quase-preto que todo design system moderno usa (`#18181b`, `#111111`), entre 3,4% e 6,8% das cores de marca possíveis ficam **sem nenhuma escolha válida** — nem branco nem escuro atinge 4,5:1.

E, mesmo com preto puro, [MEDIDO] **63,9% das cores RGB não atingem 4,5:1 com texto branco**. Ou seja: o default "texto branco sobre a cor da marca" está errado para dois terços das cores possíveis.

### 3.2.2 O que fazer quando nem assim dá

Para as cores que ficam na fronteira, ou quando a marca exige texto branco, a saída é **ajustar o fundo, não o texto**. O ChatSPX já tem o esqueleto disso em `adjustColorForContrast()` (mesmo arquivo), que itera misturando a cor com branco ou `#151718` até atingir a razão-alvo — mas com alvo **3.1**, não 4.5. [FATO — leitura do código]

[INFERÊNCIA] Alvo 3,1 é correto para **componente** (SC 1.4.11) e insuficiente para **texto** (SC 1.4.3). São dois usos diferentes que precisam de dois alvos diferentes.

Nota sobre `contrast-color()`: a função CSS que resolveria isso nativamente entrou em Baseline "newly available" em **10/04/2026** [FATO — `api.webstatus.dev/v1/features?q=contrast-color`]. É recente demais para ser a única estratégia num widget que roda em navegador de terceiro, mas é o caminho de médio prazo.

## 3.3 Contraste de componente (3:1) na prática do chat

Elementos do widget em que o **SC 1.4.11** se aplica e que costumam falhar:

| Elemento | Contra o quê | Mínimo |
|---|---|---|
| Borda do campo de digitação | fundo do painel | 3:1 |
| Ícone de enviar (sem rótulo) | fundo do botão | 3:1 |
| Bolha do agente vs. fundo do painel | entre si | 3:1 (se a distinção for informativa) |
| Indicador de "digitando" | fundo | 3:1 |
| Estado ativo/selecionado de um chip de resposta rápida | estado normal | 3:1 |
| Contorno do launcher fechado | página do cliente (que não controlamos) | 3:1 |

O último é o mais traiçoeiro: **o launcher fica sobre o site do cliente**, cujo fundo é desconhecido. Um launcher azul-claro sobre um hero azul-claro some. [INFERÊNCIA] A defesa é uma sombra ou um anel de contraste que não dependa da cor de fundo — o mesmo raciocínio do anel duplo de foco da §1.1.

## 3.4 Daltonismo — medição própria

Simulei protanopia, deuteranopia e tritanopia (matrizes de Viénot/Brettel aplicadas em RGB linear) e calculei a distância perceptual **ΔE2000** entre pares de cores semânticas. [MEDIDO — script Python próprio]

| Par | ΔE00 normal | Protanopia | **Deuteranopia** | Tritanopia |
|---|---|---|---|---|
| verde `#16A34A` vs vermelho `#DC2626` | 72,5 | 23,9 | **7,9** | 65,5 |
| verde `#22C55E` vs vermelho `#EF4444` | 76,2 | 25,9 | **7,8** | 72,3 |
| azul info `#3B82F6` vs roxo IA `#8B5CF6` | 18,4 | **5,6** | **1,8** | 20,0 |
| âmbar `#F59E0B` vs vermelho `#DC2626` | 36,2 | 31,4 | 18,8 | 20,0 |
| cinza balão `#E5E7EB` vs azul balão `#1F93FF` | 32,9 | 30,5 | 34,6 | 28,5 |

Ver prancha: `shots/t13-daltonismo-status.png`.

Três leituras:

1. **O par verde/vermelho — base de todo indicador de presença — colapsa de ΔE 72,5 para 7,9 em deuteranopia.** Praticamente a mesma cor.
2. **Azul-informação vs. roxo-IA colapsa para ΔE 1,8.** Se o plano é distinguir "mensagem do sistema" de "mensagem da IA" por azul vs. roxo, essa distinção **não existe** para quem tem deuteranopia. E roxo é justamente a cor que virou convenção de IA no mercado.
3. **O par que sobrevive é o dos balões** (cinza vs. azul de marca): ΔE ≥ 28 em todos os três tipos. Ele sobrevive porque a diferença principal é de **luminância**, não de matiz — e daltonismo afeta matiz, não luminância.

**Regra** [INFERÊNCIA, ancorada em SC 1.4.1]: qualquer distinção informativa no widget precisa ter um segundo canal além da cor — **forma, ícone, rótulo textual ou posição**. E, quando a distinção tiver que ser feita por cor, que a diferença seja de **luminância**, não de matiz.

## 3.5 Dark mode não é inversão

Três razões concretas, cada uma com evidência:

**1. A sombra some.** [FATO] No tema escuro do Polaris, `--p-shadow-100` é redefinido como `none`. Uma sombra preta sobre fundo escuro não produz separação. Ver pranchas `shots/t13-elevacao-vs-borda-light.png` e `shots/t13-elevacao-vs-borda-dark.png`, lado a lado: as mesmas cinco sombras, o mesmo card, em claro e escuro.

**2. A hierarquia de superfície inverte.** No tema claro, "mais elevado" = mais branco + sombra. No escuro, "mais elevado" = **mais claro**, porque a luz vem de cima. Isso é o oposto de inverter: inverter deixaria o elemento elevado mais escuro que o fundo.

**3. Cor saturada sobre fundo escuro cansa.** Uma cor de marca calibrada para 4,5:1 contra branco pode ficar com contraste altíssimo (e vibração cromática) contra preto. A regra prática é reduzir a saturação e subir a luminosidade no tema escuro — o que significa **duas cores de marca**, não uma cor invertida.

**4. Preto puro (#000) tem custo.** Contraste de 21:1 com texto branco produz halação (o texto "vibra") para muita gente, e em telas OLED o *smearing* no scroll é visível. Os sistemas usam cinzas muito escuros, não preto: o Polaris usa `#1a1a1a` como `bg-inverse` [FATO — CSS servido].

Ponto de método [FATO]: a HIG orienta explicitamente *"se o seu app suporta Dark Mode, verifique o contraste mínimo em ambas as aparências, clara e escura"*. Não é a mesma verificação.

## 3.6 Cor semântica: papéis, não cores soltas

O Material 3 é o mais explícito dos seis sobre isso [FATO — m3.material.io/styles/color/roles]:

> *"Existem **26 papéis de cor padrão** organizados em seis grupos: primary, secondary, tertiary, error, surface e outline."*
> *"O sistema de cor é construído sobre pares de cor acessíveis. Esses pares fornecem um contraste mínimo acessível de **3:1**."*
> *"**Combinar cores de forma imprópria pode quebrar o contraste** necessário para acessibilidade visual, particularmente quando as cores são ajustadas por recursos de cor dinâmica, como contraste controlado pelo usuário."*
> *"Papéis começando com **'On'** indicam uma cor para texto ou ícones sobre a cor-pai correspondente. Por exemplo, *on primary* é usado para texto e ícones contra a cor de preenchimento *primary*."*

A convenção `X` / `on-X` é a ideia central: **cada cor de fundo tem, no sistema, a cor de texto que combina com ela** e o par já foi validado. Não existe "escolher a cor do texto" em tempo de design — existe usar o par.

O Polaris chega ao mesmo lugar por outro caminho, com nomes semânticos por função em vez de hierarquia de ênfase [FATO — CSS servido]: `--p-color-bg-surface`, `--p-color-bg-surface-hover`, `--p-color-bg-surface-active`, `--p-color-bg-surface-selected`, `--p-color-bg-surface-disabled`, `--p-color-bg-surface-secondary`, `--p-color-bg-surface-tertiary`, `--p-color-bg-inverse`. O estado (`hover`, `active`, `selected`, `disabled`) faz parte do nome do token — não é uma opacidade aplicada por cima.

[INFERÊNCIA] Para o widget, isso significa: a cor da marca do cliente entra no sistema como **um papel** (`brand` / `on-brand`), com a cor de texto derivada pela regra da §3.2 no momento em que a cor é configurada — não em tempo de renderização de cada bolha. E os estados (hover, pressed, disabled) são tokens próprios, derivados dela, não `opacity: .8` aplicado em cima. `opacity` sobre a cor de marca muda a luminância e, portanto, invalida o cálculo de contraste que foi feito para a cor cheia.

## 3.7 Nota sobre APCA

[FATO — Apple HIG › Accessibility] A Apple cita duas metodologias: *"Dois padrões populares de medida para contraste de cor são as Web Content Accessibility Guidelines (WCAG) e o **Accessible Perceptual Contrast Algorithm (APCA)**."*

[INFERÊNCIA] O APCA foi desenvolvido como candidato para a WCAG 3 e modela melhor a percepção real, especialmente em texto claro sobre fundo escuro — onde a fórmula da WCAG 2.x é conhecidamente otimista. Mas **a conformidade legal e contratual hoje é medida pela WCAG 2.x**, e é ela que as ferramentas de auditoria usam.

Recomendação: **calcular pela WCAG 2.x** (é o que vale) e, se houver dúvida sobre um par específico no tema escuro, conferir com APCA como segunda opinião. Nunca o contrário.

---

# 4. Acessibilidade além da cor

## 4.1 Os critérios novos da WCAG 2.2 que atingem um widget de chat

A WCAG 2.2 é de outubro/2023. Estes quatro são **novos** nela e batem em cheio num widget de chat. Transcrevo o texto porque o número sozinho não ajuda ninguém.

### SC 2.5.8 Target Size (Minimum) — AA, novo

> *"O tamanho do alvo para entradas de ponteiro é de pelo menos **24 por 24 CSS pixels**, exceto quando: **Espaçamento** — alvos subdimensionados (menores que 24×24) são posicionados de modo que, se um círculo de 24 CSS pixels de diâmetro for centrado na caixa delimitadora de cada um, os círculos não se cruzem com outro alvo nem com o círculo de outro alvo subdimensionado; **Equivalente** — a função pode ser alcançada por outro controle na mesma página que atenda ao critério; **Inline** — o alvo está em uma frase ou seu tamanho é limitado pela altura de linha do texto que não é alvo; **Controle do agente de usuário**; **Essencial**."* [FATO]

Ver prancha `shots/t13-alvos-de-toque.png`, que ilustra os alvos de 20/24/28/44/48 px e a regra de espaçamento com os círculos de 24 px.

Onde isso costuma falhar num widget: o **X de fechar** (frequentemente 16–20 px), os ícones de anexo/emoji no rodapé, e o botão de "curtir/não curtir" numa resposta de IA.

### SC 2.4.11 Focus Not Obscured (Minimum) — AA, novo

> *"Quando um componente de interface recebe foco de teclado, o componente não fica inteiramente escondido por conteúdo criado pelo autor."* [FATO]

Um painel de chat flutuante **é** conteúdo criado pelo autor que cobre a página. Se o visitante navega por Tab pela página do cliente com o painel aberto e o foco vai parar atrás do painel, o critério falha. [INFERÊNCIA] Duas defesas: `inert` no conteúdo de fundo enquanto o painel está aberto em modo modal (`inert` é Baseline widely desde 11/04/2023 [FATO — webstatus.dev]), ou não abrir modal em desktop.

### SC 2.5.7 Dragging Movements — AA, novo

> *"Toda funcionalidade que usa um movimento de arrastar para operação pode ser realizada por um único ponteiro sem arrastar, a menos que arrastar seja essencial."* [FATO]

Atinge diretamente o **bottom sheet arrastável** em mobile e qualquer "puxe para expandir". Se a única forma de fechar o painel é arrastar para baixo, o critério falha. Precisa haver um botão.

### SC 3.2.6 Consistent Help — A (nível A!), novo

> *"Se uma página web contém qualquer dos seguintes mecanismos de ajuda, e esses mecanismos se repetem em múltiplas páginas dentro de um conjunto de páginas web, eles ocorrem na mesma ordem relativa ao restante do conteúdo da página, a menos que uma mudança seja iniciada pelo usuário: detalhes de contato humano; **mecanismo de contato humano**; opção de autoatendimento; **mecanismo de contato totalmente automatizado**."* [FATO]

Este é o critério que quase ninguém conecta ao widget, e ele é **nível A** — o mais básico. Um chat de site é literalmente um "mecanismo de contato humano" e/ou um "mecanismo de contato totalmente automatizado". [INFERÊNCIA] Consequência: **o launcher tem que estar na mesma posição relativa em todas as páginas do site**. Esconder o widget em algumas páginas, ou movê-lo de canto conforme a página, é violação de nível A. Isso tem implicação de produto: a feature "ocultar o widget em páginas X" precisa ser desenhada com essa restrição em mente.

## 4.2 Os critérios antigos que continuam pegando

| Critério | Nível | Aplicação no chat |
|---|---|---|
| **2.2.2 Pause, Stop, Hide** | **A** | *"Para qualquer informação em movimento, piscando ou rolando que (1) inicia automaticamente, (2) dura mais de cinco segundos e (3) é apresentada em paralelo com outro conteúdo, existe um mecanismo para pausar, parar ou ocultar"* [FATO]. Atinge o indicador de "digitando…" animado que dura mais de 5 s, e o autoscroll de mensagens chegando. |
| **1.4.10 Reflow** | AA | *"sem rolagem em duas dimensões para conteúdo com rolagem vertical em largura equivalente a **320 CSS pixels**"* [FATO]. O painel precisa funcionar em 320 px de largura — a §2.2 mostra que ali a medida cai para 27,9 caracteres. |
| **1.4.4 Resize Text** | AA | 200% de zoom sem perda. Um painel com altura fixa em px quebra aqui. |
| **1.4.12 Text Spacing** | AA | Balão com altura fixa quebra quando o usuário força entrelinha 1,5 e letter-spacing 0,12em. |
| **2.4.7 Focus Visible** | AA | Todo controle do widget precisa de indicador visível. |
| **4.1.3 Status Messages** | AA | *"mensagens de status podem ser determinadas programaticamente através de role ou propriedades, de modo que possam ser apresentadas ao usuário por tecnologias assistivas **sem receber foco**"* [FATO]. É este critério que obriga o `role="log"` / `aria-live`. |
| **2.5.1 Pointer Gestures** | A | Nada no widget pode depender de gesto multiponto ou baseado em trajetória. |

## 4.3 Roles e live regions para o log de conversa — a parte que quase todo mundo erra

Transcrevo da spec WAI-ARIA 1.2, porque a redação importa. [FATO — `w3.org/TR/wai-aria-1.2/`]

### `role="log"`

> *"Um tipo de região viva onde nova informação é adicionada em ordem significativa e informação antiga pode desaparecer. (…) **Exemplos incluem logs de chat**, histórico de mensagens, log de jogo ou log de erros. Em contraste com outras regiões vivas, neste role há uma relação entre a chegada de novos itens no log e a ordem de leitura. O log contém uma sequência significativa e nova informação é adicionada apenas ao fim do log, não em pontos arbitrários. Elementos com o role log têm um valor implícito de aria-live **polite**."*

A spec cita "chat logs" **literalmente** como o exemplo canônico. Não há ambiguidade sobre qual role usar na lista de mensagens.

### `role="status"` × `role="alert"`

> **status**: *"Um tipo de região viva cujo conteúdo é informação de aviso para o usuário mas não é importante o suficiente para justificar um alert. (…) Autores DEVEM garantir que um elemento com role status não receba foco como resultado de mudança no status. (…) valor implícito de aria-live **polite** e aria-atomic **true**."*
>
> **alert**: *"Um tipo de região viva com informação importante e geralmente sensível ao tempo. (…) Alerts são regiões vivas **assertivas**, o que significa que causam notificação imediata para usuários de tecnologia assistiva."*

[INFERÊNCIA] Mapeamento para o widget:

| Conteúdo | Role | Por quê |
|---|---|---|
| Lista de mensagens | `role="log"` | É exatamente o caso de uso da spec |
| "Sofia está digitando…" | `role="status"` ou nada | Não é crítico; e ver §4.4 sobre não anunciar |
| "Falha ao enviar. Tentar de novo?" | `role="alert"` | Time-sensitive, o usuário precisa saber já |
| "Conexão perdida" | `role="alert"` | idem |
| "Mensagem enviada" | nada | Ruído; o recibo visual basta |

**`assertive` interrompe a fala em curso.** Usar `assertive` para cada mensagem que chega torna o widget inutilizável com leitor de tela: a chegada de uma mensagem cortaria a leitura da mensagem anterior no meio.

### `aria-busy` — a solução para o streaming de IA

> *"Indica que um elemento está sendo modificado e que tecnologias assistivas PODEM querer esperar até que as modificações estejam completas antes de expô-las ao usuário. (…) Quando aria-busy é true para um elemento, tecnologias assistivas PODEM ignorar mudanças no conteúdo pertencente àquele elemento e então processar todas as mudanças feitas durante o período ocupado como **uma única atualização atômica** quando aria-busy voltar a false. (…) Por exemplo, se múltiplas mudanças em uma região viva devem ser faladas como uma única unidade de fala, autores PODEM definir aria-busy como true enquanto as mudanças são feitas e então false quando as mudanças estiverem completas."* [FATO]

Isto é a resposta direta para o problema descrito na §9.1: uma resposta de IA transmitida token a token dispara uma mutação de DOM a cada poucos milissegundos. Sem `aria-busy`, o leitor de tela tenta anunciar cada fragmento. **Com `aria-busy="true"` durante o streaming e `false` ao terminar, a resposta é lida uma vez, inteira.**

### `aria-relevant`

> *"Quando o atributo aria-relevant não é fornecido, o valor padrão, **additions text**, indica que modificações de texto e adições de nós são relevantes, mas que remoções de nós são irrelevantes. (…) valores de aria-relevant como removals ou all devem ser usados com parcimônia."* [FATO]

[INFERÊNCIA] Ou seja: o default já está certo para chat. Não declarar `aria-relevant="all"` num log de mensagens — isso faria o leitor anunciar mensagens **removidas** (por virtualização de lista, por exemplo), o que é puro ruído.

## 4.4 Anúncio de mensagem nova sem inundar o leitor de tela

O problema: numa conversa ativa, com typing indicator, recibos de leitura e streaming, um `aria-live` mal configurado transforma o widget num rádio ligado.

Regras derivadas [INFERÊNCIA, ancoradas nos fatos da §4.3]:

1. **Um único live region**, no contêiner da lista, com `role="log"` (polite implícito). Não colocar `aria-live` em cada bolha.
2. **`aria-busy="true"` durante streaming**, `false` ao concluir. Uma resposta = um anúncio.
3. **Não anunciar o typing indicator.** Ele é informação visual efêmera; anunciá-lo a cada 2 s é hostil. Se for anunciado, `role="status"` e só uma vez por turno.
4. **Não anunciar recibos** ("entregue", "lido"). São metadados; ficam disponíveis na leitura da mensagem, não como evento.
5. **A mensagem própria do usuário não precisa de anúncio** — ele acabou de digitá-la.
6. **`aria-atomic="false"`** no log (é o default do role `log`, mas explicitar não custa): anunciar só o que foi adicionado, não a conversa inteira a cada mensagem.

## 4.5 Foco: abrir, fechar, e o resto

| Momento | Comportamento correto | Ancoragem |
|---|---|---|
| Abrir o painel | Mover o foco para dentro. Alvo: o campo de digitação se o objetivo é digitar; o cabeçalho se há conteúdo a ler primeiro. | Prática de diálogo |
| Painel aberto em modo modal (mobile) | `inert` no resto da página, foco preso dentro | SC 2.4.11 + `inert` Baseline widely 11/04/2023 [FATO] |
| Painel aberto em modo não-modal (desktop) | **Não** prender o foco. O visitante ainda está usando o site. | [INFERÊNCIA] |
| Fechar o painel | Foco volta **para o launcher** | Prática de diálogo |
| Esc | Fecha o painel (ou o nível mais interno aberto) | Prática de diálogo |
| Tab dentro do painel | Ordem = ordem visual. Sem `tabindex` positivo. | |
| Mensagens antigas | Devem ser alcançáveis por teclado (o log é rolável e navegável) | SC 2.1.1 |

## 4.6 Rótulos traduzidos

[INFERÊNCIA, mas o risco é concreto e comum] Todo `aria-label`, `title` e texto alternativo do widget precisa passar pelo i18n. O caso clássico: o botão de fechar tem `aria-label="Close"` fixo no código enquanto toda a interface está em pt-BR. Para o usuário de leitor de tela em português, o widget passa a falar duas línguas.

Itens que costumam escapar: `aria-label` do launcher, do botão fechar, do botão enviar, do input de anexo; o `title` do iframe (se houver); os textos de estado ("Digitando", "Enviando", "Falha ao enviar"); e o `lang` do contêiner do widget, que precisa acompanhar o idioma da conversa e não o do site do cliente.

## 4.7 As três media queries de preferência do usuário

Todas com suporte consolidado — não há desculpa de compatibilidade para ignorá-las. [FATO — `api.webstatus.dev`]

| Media query | Baseline | Desde | O que o widget precisa fazer |
|---|---|---|---|
| `prefers-reduced-motion` | **widely** | low 15/01/2020, high 15/07/2022 | Desligar transições de abertura, o "efeito máquina de escrever" cosmético, o shimmer do skeleton e a animação do typing indicator |
| `prefers-contrast` | **widely** | low 31/05/2022, high 30/11/2024 | Em `more`: aumentar a espessura das bordas, reforçar o indicador de foco, subir o contraste do texto secundário |
| `forced-colors` | **widely** | low 12/09/2022, high 12/03/2025 | Em `active`: **não** brigar com o sistema. Remover fundos decorativos, usar `ButtonText`/`Canvas`/`Highlight` do sistema, e garantir que o balão continue distinguível por **borda** |

O `forced-colors` é o mais esquecido dos três e o que mais quebra um widget de chat [INFERÊNCIA]: no modo de alto contraste do Windows, o sistema substitui as cores do autor. Um design em que a única diferença entre a bolha do visitante e a do agente é a **cor de fundo** vira uma tela em que todas as bolhas são idênticas. A defesa é ter uma **borda** ou um **alinhamento** distinguindo os dois lados, e não só a cor.

É também o motivo técnico da regra `outline: 2px solid transparent` da §1.1: em `forced-colors`, o `transparent` é trocado por uma cor real do sistema; `outline: none` continua sendo nada.

Nota adicional [FATO — webstatus.dev]: `text-size-adjust` está em Baseline **limited**. Não dá para depender dele para controlar o ajuste automático de tamanho de texto em mobile.

---

# 5. Densidade e layout

## 5.1 Quanto conteúdo cabe

[MEDIDO] Com corpo 15/22 num painel de 400 px @ 88%, uma mensagem de 293 caracteres ocupa **9 linhas** e **214 px de altura de bolha**. Com 16/24, sobe para **10 linhas / 256 px**.

[INFERÊNCIA] Consequência de layout: num painel cuja área de conversa tem ~440 px de altura útil (painel de 600 px menos cabeçalho ~56 px e rodapé ~96 px), **duas mensagens longas enchem a tela**. O design tem que assumir que a conversa é uma sequência de mensagens **curtas**, não um documento. Se o produto precisa entregar texto longo (uma política, uma lista de planos), o formato certo é um card ou um link, não um balão de 12 linhas.

## 5.1.1 Quanto de tela o widget ocupa — o número que sustenta a regra do Google

A regra do Google (§7.2) fala em *"quantidade razoável de espaço de tela"*. Calculei quanto é, em cada estado. [MEDIDO — cálculo de área sobre viewports de referência]

| Viewport | Launcher 56 px | Bloco reservado 88 × 88¹ | Painel 400 × 640 | Painel fullscreen |
|---|---|---|---|---|
| 360 × 640 | 1,36% | 3,36% | — | **100%** |
| 390 × 844 | 0,95% | 2,35% | — | **100%** |
| 412 × 915 | 0,83% | 2,05% | — | **100%** |
| 768 × 1024 | 0,40% | 0,98% | 32,6% | 100% |
| 1280 × 800 | 0,31% | 0,76% | 25,0% | 100% |
| 1440 × 900 | 0,24% | 0,60% | **19,8%** | 100% |
| 1920 × 1080 | 0,15% | 0,37% | 12,4% | 100% |

¹ Launcher de 56 px mais a margem de 16 px em dois lados — a área que na prática fica indisponível para o site do cliente.

[INFERÊNCIA] O contraste é a coisa toda: **o launcher fechado ocupa entre 0,15% e 3,4% da tela; o painel aberto em mobile ocupa 100%.** São dois regimes completamente diferentes de intrusão, e é por isso que "abrir sozinho" em desktop e "abrir sozinho" em mobile não são a mesma decisão. Em desktop, o painel toma 12–25% e o site continua utilizável. Em mobile, ele **é** a tela — que é exatamente a descrição do que o Google penaliza.

Altura útil de conversa no modo fullscreen, descontando cabeçalho (56 px) e rodapé (96 px) [MEDIDO]: 488 px em 360 × 640 (76% da tela), 692 px em 390 × 844, 763 px em 412 × 915. No pior caso — 488 px — cabem **duas mensagens longas** e nada mais (§5.1).

## 5.2 Painel flutuante × bottom sheet × fullscreen

| Contexto | Padrão | Justificativa |
|---|---|---|
| Desktop ≥ 1024 px | **Painel flutuante** ancorado ao canto, não-modal | O visitante continua usando o site; travar a página é hostil |
| Tablet / desktop pequeno | Painel flutuante, largura reduzida | |
| Mobile < 768 px | **Fullscreen** ou bottom sheet alto | Não há espaço para "flutuar" sobre nada |

Do Material 3, sobre bottom sheets [FATO — m3.material.io/components/bottom-sheets/guidelines]:

- *"Para dar acesso às suas ações principais, a posição vertical inicial de modal bottom sheets é limitada a **50% da altura da tela**."*
- *"Bottom sheets modais são usados apenas em apps mobile."*
- *"Em breakpoints compactos, como dispositivos móveis, bottom sheets se estendem por toda a largura da tela."*
- *"Em breakpoints expandidos, como desktop, um bottom sheet pode ser trocado por um **side sheet** que mostra conteúdo similar."*
- Dispensa: *"tocando um item ou ação dentro do bottom sheet; tocando o scrim; **arrastando a folha para baixo**; usando uma affordance de fechar na app bar."* — Note que a lista inclui uma alternativa não-arrastável, o que satisfaz o SC 2.5.7.

[INFERÊNCIA] Para um widget de chat, o bottom sheet a 50% é o **estado intermediário**, não o estado de conversa: serve para o "cartão de boas-vindas" ou o menu de opções. A conversa em si quer altura máxima.

## 5.3 Safe areas

[FATO] `env(safe-area-inset-*)` é Baseline **widely available** desde 15/01/2020 (`api.webstatus.dev/v1/features?q=safe-area-inset`).

[INFERÊNCIA] O rodapé do painel (campo de digitação + botão enviar) precisa de `padding-bottom: max(12px, env(safe-area-inset-bottom))`. Sem isso, em iPhone com barra de gestos, o botão enviar fica embaixo da barra do sistema. O launcher fechado tem o mesmo problema: precisa de offset inferior que respeite a safe area.

## 5.4 `dvh` / `svh` / `lvh` e o problema da barra de endereço

**O que consegui verificar** [MEDIDO]:

- Chromium 145.0.7632.6 suporta `100dvh`, `100svh` e `100lvh` (`CSS.supports()` = true nos três).
- `window.visualViewport` existe.
- Em três viewports emuladas (1440×900, 390×844, 360×640), **`vh`, `dvh`, `svh` e `lvh` retornaram o mesmo valor**.

**O que isso NÃO prova** [NÃO VERIFICADO]: nada sobre o comportamento com barra de endereço real. Em headless não há chrome de navegador, então `svh` e `lvh` coincidem por construção. **Não testei em Safari iOS nem Chrome Android reais.** Qualquer afirmação sobre o quanto a barra de endereço encolhe o viewport nesses navegadores estaria inventada.

**O que é fato de suporte** [FATO — `api.webstatus.dev/v1/features?q=viewport`]:

| Feature | Baseline | Desde |
|---|---|---|
| `viewport-unit-variants` (small, large, dynamic) | **widely available** | low 05/12/2022, high 05/06/2025 |
| Visual Viewport API | **widely available** | low 10/08/2021, high 10/02/2024 |
| `viewport-units` (vh/vw clássicos) | widely | 2017 |
| **`overscroll-behavior`** | **limited** | Chrome/Edge 144 (13/01/2026), Firefox 150 (21/04/2026) — **sem implementação de Safari listada** |

O último merece atenção: **`overscroll-behavior: contain` não tem suporte listado no Safari**. É a propriedade que impede o scroll do painel de "vazar" para a página quando se chega ao fim da lista. [INFERÊNCIA] Num widget que roda muito em iOS, isso significa que o *scroll chaining* precisa ser tratado por outro caminho (bloquear o scroll do body enquanto o painel está aberto em modo fullscreen, por exemplo) — não dá para depender só da propriedade CSS.

**Regra derivada** [INFERÊNCIA]: usar `100dvh` como altura do painel fullscreen em mobile, com `100vh` como fallback declarado antes. `dvh` acompanha a barra de endereço, que é o comportamento desejado num painel que ocupa a tela toda.

## 5.5 `visualViewport` e o teclado virtual

[FATO] A Visual Viewport API é Baseline widely available. Ela expõe `height`, `offsetTop` e o evento `resize`, que é o que muda quando o teclado virtual sobe.

[INFERÊNCIA] O problema clássico: o teclado sobe, o campo de digitação fica escondido atrás dele. Duas abordagens: (a) `interactive-widget=resizes-content` no meta viewport, que faz o layout viewport encolher; (b) ouvir `visualViewport.resize` e reposicionar o rodapé. **Não testei nenhuma das duas** nesta apuração [NÃO VERIFICADO] — exigem dispositivo real com teclado virtual, e o headless não tem.

Registro isso como lacuna a fechar antes da implementação, não como recomendação verificada.

## 5.6 Anatomia da bolha e agrupamento

Nenhum dos seis sistemas de referência prescreve isto (§1.2), então aqui é medição própria mais convenção estabelecida, marcada como tal.

### Agrupamento — o ganho medido

Renderizei a mesma conversa de 6 mensagens curtas de duas formas: repetindo avatar, nome e horário em cada mensagem, e agrupando as consecutivas do mesmo autor. [MEDIDO]

| Tratamento | Altura total |
|---|---|
| Sem agrupamento | **522 px** |
| Com agrupamento (4 px entre mensagens do mesmo autor, avatar e nome só na primeira, horário só na última) | **403 px** |
| **Economia** | **119 px — 22,8%** |

Ver prancha `shots/t13-agrupamento-mensagens.png`, com os dois tratamentos lado a lado.

[INFERÊNCIA] 22,8% de altura numa área útil de 488 px (§5.1.1, pior caso mobile) equivale a **mais de uma mensagem inteira a mais visível na tela**. O agrupamento não é refinamento estético — é a diferença entre ver o contexto da conversa e ver só a última troca.

### As regras de agrupamento

| Regra | Valor |
|---|---|
| Espaço entre mensagens **do mesmo autor** | 4 px |
| Espaço entre autores **diferentes** | 12 px |
| Espaço entre grupos separados no tempo | 20 px + marcador de tempo |
| Avatar | Só na **última** mensagem do grupo, alinhado à base |
| Nome do autor | Só na **primeira** mensagem do grupo |
| Horário | Só na **última** mensagem do grupo |
| Quebra do agrupamento por tempo | Convenção estabelecida: intervalo relevante entre mensagens quebra o grupo — o valor exato é decisão de produto |

### A cauda ("rabinho") do balão

[INFERÊNCIA] Duas escolas: cauda desenhada (triângulo/curva saindo do balão, ao estilo iMessage e WhatsApp) e **canto reduzido** (o canto voltado para o autor tem raio pequeno, os outros três têm raio grande).

Recomendo o **canto reduzido**: `border-radius: 16px 16px 16px 6px` para o agente e `16px 16px 6px 16px` para o visitante. Motivos: não exige pseudo-elemento nem SVG, não quebra em `forced-colors` (§4.7), não precisa de ajuste por tema, e continua funcionando com fundo translúcido. A cauda desenhada é mais expressiva e custa todos esses casos.

Detalhe de agrupamento [INFERÊNCIA]: dentro de um grupo, só a **última** bolha recebe o canto reduzido. As anteriores ficam com raio grande nos quatro cantos. Isso é o que faz o grupo ler como um bloco só.

### Largura mínima da bolha

[INFERÊNCIA] Uma bolha com "Ok" precisa de largura mínima suficiente para o horário e o recibo não estrangularem o texto, se o recibo for interno à bolha. Se o recibo for **externo** (abaixo da bolha, que é o que proponho na §2.4), o problema desaparece e a bolha pode encolher até o conteúdo. Esta é uma razão concreta para não colocar o horário dentro da bolha.

## 5.7 Catálogo de estados que precisam ser desenhados

[INFERÊNCIA] Lista de estados que um widget de chat precisa ter desenhados. A ausência de qualquer um deles não é "detalhe" — é uma tela que o usuário vai ver e que ninguém desenhou.

| Estado | O que precisa existir | Âncora |
|---|---|---|
| **Launcher fechado, sem histórico** | Ícone + rótulo acessível | §10.7 |
| **Launcher com mensagem não lida** | Contador; distinguível sem depender só de cor | SC 1.4.1 §3.4 |
| **Painel abrindo** | Transição de 250–300 ms; sob `prefers-reduced-motion`, sem transição | §10.5 |
| **Conversa vazia** | Estado inicial que diz o que o bot resolve | HAX G1 §9.3 |
| **Carregando histórico** | Skeleton com forma de balões, não spinner, não frame vazio | §8.3 |
| **Digitando (agente/IA)** | Animação com duração limitada, não anunciada em loop | SC 2.2.2 §4.2 |
| **Streaming de IA** | Texto crescendo + `aria-busy` | §4.3, §9.1 |
| **Mensagem enviando** | Optimistic UI, bolha em estado intermediário | §8.3 |
| **Mensagem falhou** | Ícone + texto + ação de reenviar; `role="alert"` | §4.3, SC 1.4.1 |
| **Offline / desconectado** | Faixa não bloqueante | §8.3 |
| **Reconectando** | Estado distinto de "offline" | |
| **Fora do horário de atendimento** | Expectativa explícita de retorno | HAX G2 §9.3 |
| **Handoff para humano** | Três marcações simultâneas | §9.6 |
| **Conversa encerrada** | Sem ambiguidade sobre poder ou não responder | |
| **Erro de carregamento do widget** | Degradar para link de contato, não para tela em branco | [INFERÊNCIA] |

O último merece ênfase: se o bundle do widget falhar em carregar, o site do cliente fica **sem canal de contato** e ninguém percebe. O launcher deveria ser capaz de degradar para um `mailto:` ou link de WhatsApp, servido no snippet inicial.

## 5.8 Grade e ritmo

[INFERÊNCIA a partir dos tokens da §1.1] Escala de espaçamento proposta, base 4 px, 11 degraus:

`0 · 2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48`

Onze degraus é o suficiente: o Carbon usa 13, o Polaris 18, o Atlassian 14 — e nenhum deles é um widget de 400 px de largura. Menos degraus = menos decisão arbitrária.

Ver prancha `shots/t13-foco-espacamento-raios.png`.

---

# 6. Tendências reais de 2025/2026 — com data e fonte

Critério aplicado: **só entra tendência com exemplo real, datado e verificável em fonte primária.** O que não passou nesse filtro está na §6.9.

## 6.1 Liquid Glass (Apple) — 09/06/2025

[FATO — apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/, datado "June 9, 2025"]

> *"É construído com um novo material chamado Liquid Glass. Este material translúcido reflete e refrata seu entorno, enquanto se transforma dinamicamente para ajudar a trazer maior foco ao conteúdo."* — Alan Dye, VP de Human Interface Design

Aplica-se a iOS 26, iPadOS 26, macOS Tahoe 26, watchOS 26 e tvOS 26.

**A parte que interessa para nós são as restrições que a própria Apple publicou** [FATO — HIG › Materials]:

- *"**Não use Liquid Glass na camada de conteúdo.** (…) incluí-lo na camada de conteúdo pode resultar em complexidade desnecessária e hierarquia visual confusa."*
- *"**Use efeitos de Liquid Glass com parcimônia.** (…) usar demais este material em múltiplos controles customizados pode dar uma experiência inferior ao distrair do conteúdo. Limite esses efeitos aos elementos funcionais mais importantes."*
- *"**Use apenas o Liquid Glass 'clear' para componentes que aparecem sobre fundos visualmente ricos.**"*
- *"A variante **regular** desfoca e ajusta a luminosidade do conteúdo de fundo para manter a legibilidade (…) Use a variante regular quando o conteúdo de fundo puder criar problemas de legibilidade, ou quando componentes tiverem quantidade significativa de texto, como alertas, sidebars ou popovers."*

**Leitura honesta** [INFERÊNCIA]: a Apple lançou um material translúcido e, no mesmo documento, escreveu quatro parágrafos dizendo onde **não** usá-lo. E ela mesma reconhece que o resultado depende de configurações de acessibilidade do usuário (*"reduce transparency"*, *"increase contrast"*) — ou seja, o efeito **não é garantido**.

[FATO·2ª] Houve reação pública sobre legibilidade, e a Apple adicionou controles para reduzir o efeito em versões subsequentes do iOS 26. Não consegui confirmar isso em release notes primárias da Apple nesta apuração — a afirmação vem de cobertura de imprensa (MacRumors, GSMArena, fórum de desenvolvedores da Apple). Registro como fonte secundária.

**Um painel de chat é "quantidade significativa de texto"**, categoria que a própria HIG manda tratar com a variante *regular* (opaca o suficiente para garantir legibilidade), não com a *clear*.

## 6.2 Material 3 Expressive (Google) — 13/05/2025

[FATO — blog.google, datado "May 13, 2025"]

> *"Material 3 Expressive parece ainda mais fluido e introduz um sistema de animações mais naturais e elásticas (springy) (…) Android também está recebendo temas de cor dinâmica atualizados, componentes responsivos e **tipografia enfatizada**."*

Números que o Google publica sobre a pesquisa por trás [FATO — design.google/library/expressive-material-design-google-research]:

- *"46 estudos de pesquisa separados com centenas de designs, e **mais de 18.000 participantes** de todo o mundo"*
- *"preferência (…) particularmente forte — **até 87%** — entre pessoas de 18 a 24 anos"*
- *"Participantes conseguiram localizar elementos-chave da UI **até quatro vezes mais rápido** nos designs M3 Expressive"* (eye tracking)
- *"uma **eliminação dramática do efeito de idade** nos tempos de fixação, ajudando usuários de 45+ a performar no mesmo nível dos mais jovens"*
- *"Em muitos casos, escolhemos **exceder** os padrões existentes de tamanho de alvo de toque, contraste de cor"*
- Ressalva do próprio Google: *"embora houvesse apelo amplo para design vibrante e expressivo, **uma minoria forte de usuários preferiu versões mais calmas, menos intensas**"*

**Leitura honesta** [INFERÊNCIA]: é pesquisa do fornecedor sobre o próprio produto, sem revisão por pares e sem dados brutos publicados. Trato como **afirmação datada e atribuível**, não como evidência independente. O que é aproveitável do achado, independentemente do número: **contraste de tamanho e de cor entre o elemento principal e o resto acelera a localização visual**. Isso é consistente com décadas de pesquisa de atenção visual, e o exemplo que eles dão (botão Enviar maior, em cor secundária, perto do teclado) é diretamente transportável para o rodapé de um chat.

## 6.3 Glassmorphism / blur — ainda?

**O fato de plataforma** [FATO — `api.webstatus.dev/v1/features?q=backdrop-filter`]: `backdrop-filter` entrou em Baseline **"newly available" em 16/09/2024**. Ainda **não** é "widely available".

[INFERÊNCIA] Para código de terceiro injetado em site alheio — que é o nosso caso —, "newly available" significa que ainda há navegadores em uso sem suporte. O blur precisa ser tratado como **enriquecimento progressivo**, atrás de `@supports (backdrop-filter: blur(1px))`, com um fundo sólido de fallback que sozinho já atenda ao contraste.

**Resposta direta à pergunta "ainda?":** sim, o blur ainda está em uso e ganhou legitimidade em 2025 pelas duas maiores plataformas (Liquid Glass e a "sombra desfocada" do M3E). Mas as duas o usam em **camada de navegação/controle sobre conteúdo**, e ambas publicam restrições explícitas de legibilidade. O que morreu não foi o blur — foi o blur **como fundo de texto**.

## 6.4 Bordas × sombras

[FATO] Polaris redefine `--p-shadow-100` como `none` no tema escuro. [FATO] Material 3 mantém sombras nos dois temas, mas o token de elevação é um **número em dp**, não uma sombra — a tradução para `box-shadow` é responsabilidade do componente, o que permite trocar a estratégia por tema.

[INFERÊNCIA] A prática convergente é: **sombra no tema claro, borda (ou superfície mais clara) no tema escuro**. Não é uma tendência estética, é uma consequência física de como sombra funciona. Ver as pranchas `shots/t13-elevacao-vs-borda-light.png` e `shots/t13-elevacao-vs-borda-dark.png`.

## 6.5 Cantos

[FATO] Os raios publicados vão de 0 (GOV.UK button) a 28 px (M3 `corner-extra-large`) e "full" (pill). Não há convergência.

[INFERÊNCIA] O que se pode afirmar: raio grande em elemento pequeno (um chip de 28 px de altura com raio 16) lê como pill; raio grande em elemento grande (um painel de 600 px com raio 16) lê como "cartão". O raio precisa ser **proporcional ao elemento**, não constante — que é exatamente por que os sistemas publicam uma escala e não um valor.

## 6.6 Modo escuro por padrão?

[NÃO VERIFICADO] Não encontrei dado primário confiável sobre a proporção de usuários com preferência de sistema em escuro que sirva como base de decisão. Não vou inventar um número.

[INFERÊNCIA] O que dá para prescrever sem número: o widget deve **respeitar `prefers-color-scheme`** por padrão e permitir que o cliente force um tema. `prefers-color-scheme` é Baseline widely há anos, e `light-dark()` entrou em Baseline newly em 13/05/2024 [FATO — webstatus.dev]. Escolher "escuro por padrão" como decisão estética, ignorando a preferência do sistema, é impor ao visitante uma escolha que o sistema operacional dele já respondeu.

## 6.7 Ilustração × foto de agente real

[NÃO VERIFICADO] Procurei estudo primário comparando avatar ilustrado, avatar gerado e foto de pessoa real em widget de chat, com métrica de confiança ou conversão. **Não encontrei nenhum.** Os números que circulam sobre "foto de agente real aumenta conversão em X%" vêm de blogs de fornecedores de chat, sobre os próprios clientes, sem metodologia publicada.

O que se pode afirmar com âncora [FATO — NN/g, §7.4]: o problema não é o tipo de imagem, é a **coerência entre o que a imagem promete e o que o sistema entrega**. O relato do participante sobre a Flo da Progressive — bot com personalidade que some quando começa o formulário — é sobre isso. Uma foto de pessoa real ao lado de mensagens obviamente automatizadas cria exatamente essa dissonância, e ela é medida como perda de confiança.

[INFERÊNCIA] Regra defensável sem número inventado: **a imagem tem que corresponder a quem está falando**. Bot → avatar de bot ou marca. Humano → foto do humano. No handoff, a imagem muda (§9.6). Foto de estoque de "atendente sorridente" para representar uma IA é a versão visual de fingir ser humano, e cai sob o achado do NN/g de que não revelar o bot é um erro.

## 6.8 Densidade compacta

[FATO, §1.1] A tendência para densidade compacta é real e mensurável nos sistemas de **produtividade**: Atlassian, Polaris e Carbon convergem em corpo de 14 px. O Atlassian declara inclusive que o sistema de espaçamento *"lança a base para densidade de UI customizável no futuro"*.

[INFERÊNCIA] E ela é a régua errada aqui. Esses três sistemas são para usuário treinado, sentado, em sessão longa. O visitante de um site é o oposto disso em todas as três dimensões. Adotar a densidade de uma ferramenta de trabalho num widget de consumidor é copiar a estética sem copiar o contexto que a justifica.

Onde a densidade compacta **cabe** no nosso caso: no painel do atendente (que é outro produto), e possivelmente numa preferência de densidade oferecida ao cliente — nunca como default do widget.

## 6.9 O que **não** entrou — e por quê

Durante a apuração, buscas por tendências de UI de chat para 2026 devolveram, em blogs de agências e plataformas de design:

- *"balões bem desenhados aumentam o engajamento em até 72%"*
- *"usuários passam 200% mais tempo com mensagens que têm elementos visuais como emoji ou anexo"*
- *"bento grids se tornaram o padrão da indústria em 2024"*

**Não encontrei fonte primária para nenhuma dessas afirmações.** Nenhum estudo, nenhuma amostra, nenhum método. São números que circulam entre artigos que citam uns aos outros.

Registro isso explicitamente porque é o tipo de "dado" que costuma entrar num documento de redesign e virar justificativa de decisão. **Não é evidência. Não use.** [NÃO VERIFICADO]

---

# 7. O que irrita o usuário final — com fonte

## 7.1 Pop-ups e sobreposições: a evidência com escala

[FATO — betterads.org/research/] A Coalition for Better Ads (associações e empresas do setor, incluindo Google e Facebook) pesquisou preferências de consumidores com metodologia declarada:

> *"Na primeira fase da pesquisa da Coalition, **mais de 25.000 usuários de internet** na América do Norte e Europa foram pesquisados (…) A metodologia foi então usada para medir preferências na Ásia, América Latina e África. (…) Até hoje, **mais de 66.000 consumidores** em países que representam **70% do investimento global em publicidade online** participaram."*

Experiências **abaixo** do limiar de aceitabilidade em **mobile web** [FATO]:

- **Pop-up ads**
- Prestitial ads
- Páginas mobile com mais de 30% de densidade de anúncio
- **Flashing animations**
- Poststitial ads que exigem contagem regressiva para dispensar
- **Fullscreen scrollover ads**
- **Large sticky ads**
- **Auto-playing videos with sound**

Em **desktop web**: pop-up ads, auto-playing videos with sound, prestitial com contagem regressiva, **large sticky ads**, densidade acima de 50%.

**Cuidado de método** [INFERÊNCIA, marcada como tal]: isto é pesquisa sobre **anúncios**, não sobre widgets de chat. O que se pode transportar não é a conclusão, é o **mecanismo**: as experiências reprovadas têm três características em comum — aparecem sem serem chamadas, cobrem o conteúdo, e custam esforço para dispensar. Um widget de chat que abre sozinho e cobre a tela em mobile tem exatamente essas três características. A analogia é minha; a evidência de que essas três características irritam é da Coalition.

## 7.2 A regra do Google sobre intersticiais intrusivos

[FATO — developers.google.com/search/blog/2016/08/helping-users-easily-access-content-on]

> *"Páginas que mostram intersticiais intrusivos oferecem uma experiência pior aos usuários (…) Para melhorar a experiência de busca mobile, **após 10 de janeiro de 2017, páginas onde o conteúdo não é facilmente acessível ao usuário na transição a partir dos resultados de busca mobile podem não ranquear tão bem**."*

Técnicas listadas como problemáticas [FATO]:
- *"Mostrar um pop-up que cobre o conteúdo principal, seja imediatamente após o usuário navegar para a página a partir dos resultados de busca, seja enquanto ele está percorrendo a página."*
- *"Exibir um intersticial autônomo que o usuário tem que dispensar antes de acessar o conteúdo principal."*

E o que **não** é penalizado [FATO]:
- *"Banners que usam uma quantidade razoável de espaço de tela e são facilmente dispensáveis."*

[INFERÊNCIA] Um launcher no canto = "banner que usa quantidade razoável de espaço e é facilmente dispensável". Um painel que abre sozinho e cobre o conteúdo em mobile = a descrição literal do que é penalizado. Isso transforma "auto-open agressivo em mobile" de uma questão de gosto em uma questão de **risco de SEO para o cliente**, o que é um argumento que o comercial entende.

## 7.3 NN/g sobre pop-ups — 10 padrões, todos aplicáveis

[FATO — nngroup.com/articles/popups/]

> *"Resumo: sejam modais ou não, a maioria das sobreposições aparece no momento errado, interrompe usuários durante tarefas críticas, usa linguagem ruim e contribui para a desorientação do usuário."*

Relato de campo do próprio artigo: *"Enquanto tentava completar uma tarefa, um participante atirou o telefone do outro lado da mesa depois de encontrar múltiplos pop-ups consecutivos. Frustrado, ele abandonou a tarefa e saiu do site com uma péssima impressão da organização."* E: *"em média, **25 pop-ups por semana**"* durante o levantamento da autora.

Os padrões da lista que atingem diretamente um widget de chat:

| # | Padrão problemático | Tradução para chat |
|---|---|---|
| 1 | *"Mostrar um pop-up antes de o conteúdo principal carregar"* | Auto-open no `load` |
| 3 | *"Pedir e-mail antes da interação"* | Pre-chat form como primeira tela |
| 4 | *"Pedir feedback antes de a pessoa ter feito algo significativo"* | CSAT antes do fim da conversa |
| 5 | *"Interromper usuários para pedir feedback durante tarefas críticas"* | Convite proativo no meio do checkout |
| 6 | *"Mostrar múltiplos pop-ups em sequência"* | Chat + cookie banner + newsletter juntos |
| 8 | *"Interromper acesso ao conteúdo com sobreposições modais"* | Painel modal em desktop |

Contraponto útil do mesmo artigo [FATO]: *"o que fazer em vez disso: espere para apresentar o conteúdo do pop-up até que seja contextualmente relevante para o usuário. Use o princípio da reciprocidade: dê valor aos visitantes antes de pedir qualquer coisa."*

## 7.4 NN/g sobre chatbots

[FATO — nngroup.com/articles/chatbots/, estudo com 8 participantes, mobile e desktop]

> *"Resumo: longe de serem 'inteligentes', os chatbots de hoje guiam usuários por fluxos lineares simples, e nossa pesquisa mostra que eles têm dificuldade sempre que os usuários se desviam desses fluxos."*

Achados diretamente aplicáveis:

1. **Transparência sobre ser bot** — *"Nossos participantes ficaram satisfeitos quando o negócio foi transparente sobre usar um bot, porque puderam calibrar tanto suas expectativas quanto sua linguagem. (…) Algumas empresas nem sempre revelam antecipadamente aos clientes que eles estão interagindo com um bot. **Acreditamos que isso é um erro.**"*
2. **Botão E texto, não um ou outro** — *"Ambos os mecanismos de entrada eram importantes e os dois devem estar presentes."* E: *"Usuários reclamaram quando um bot não permitia escolher uma opção e em vez disso exigia digitação."*
3. **Assumir a falha e oferecer saída** — *"Assumir a falha e oferecer uma escotilha de escape (número de telefone ou atendente ao vivo) foi geralmente percebido de forma favorável. Reconhecer que uma pergunta não foi entendida era decepcionante, mas melhor do que uma resposta descaradamente errada."*
4. **Repetição irrita** — *"Usuários ficavam geralmente irritados quando o bot repetia as mesmas respostas várias vezes."*
5. **Personalidade inconsistente é pior que nenhuma** — o relato do participante sobre o bot da Progressive que começa brincalhão e vira formulário: *"me tirou daquele conceito de 'ah, estou falando com a Flo da Progressive' versus estou apenas falando com um chatbot."*
6. **Contexto não se perde** — bots que pediam o mesmo endereço duas vezes na mesma sessão.
7. **Preocupação com dado pessoal** — *"Alguns dos nossos usuários estavam preocupados em compartilhar dados pessoais como data de nascimento, endereço, números de cartão de crédito."*

Nota de datação [INFERÊNCIA]: o estudo é anterior aos LLMs. Os achados 1, 3, 4, 5, 6 e 7 são sobre **expectativa e confiança do usuário** e envelhecem bem. O achado central ("bots não entendem desvio do script") mudou com LLMs — mas mudou o **quanto**, não o **se**: um LLM ainda alucina, ainda perde contexto, e o usuário ainda precisa da escotilha de escape.

## 7.5 Consolidado: a lista do que não fazer

| Prática | Evidência |
|---|---|
| Abrir sozinho no carregamento | NN/g padrão #1 [FATO]; risco de ranqueamento Google [FATO] |
| Abrir sozinho cobrindo a tela em mobile | Google intersticiais [FATO]; Better Ads "fullscreen scrollover" [FATO] |
| Tocar som na chegada de mensagem sem o usuário ter iniciado | Better Ads: "auto-playing videos with sound" reprovado nas duas plataformas [FATO] — a analogia é minha [INFERÊNCIA] |
| Launcher cobrindo botão do site | Better Ads: "large sticky ads" reprovado [FATO] + é conflito funcional direto [INFERÊNCIA] |
| Reabrir sozinho depois de fechado | NN/g padrão #6 (múltiplos pop-ups) [FATO]; e viola a expectativa mais básica de controle [INFERÊNCIA] |
| Bot que finge ser humano | NN/g: *"acreditamos que isso é um erro"* [FATO] |
| Formulário disfarçado de conversa | NN/g padrão #3 [FATO] + NN/g chatbots achado 2 [FATO] |
| Animação/piscar por mais de 5 s sem controle | WCAG SC 2.2.2, **nível A** [FATO] |
| Mover o launcher de lugar entre páginas | WCAG SC 3.2.6 Consistent Help, **nível A** [FATO] |

---

# 8. Performance percebida como decisão de design

## 8.1 Os três limites, que não mudaram em 30 anos

[FATO — nngroup.com/articles/response-times-3-important-limits/]

> *"**0,1 segundo** é aproximadamente o limite para o usuário sentir que o sistema está reagindo instantaneamente, o que significa que nenhum feedback especial é necessário além de exibir o resultado."*
>
> *"**1,0 segundo** é aproximadamente o limite para o fluxo de pensamento do usuário permanecer ininterrupto, ainda que ele note o atraso."*
>
> *"**10 segundos** é aproximadamente o limite para manter a atenção do usuário focada no diálogo. Para atrasos maiores, usuários vão querer realizar outras tarefas enquanto esperam."*

## 8.2 Os limites do Core Web Vitals

[FATO — web.dev/articles/vitals e /articles/inp]

| Métrica | Bom | Precisa melhorar | Ruim |
|---|---|---|---|
| **LCP** | ≤ 2,5 s | | |
| **INP** | **≤ 200 ms** | 200–500 ms | **> 500 ms** |
| **CLS** | ≤ 0,1 | | |

*"Um bom limiar para medir é o **percentil 75** dos carregamentos de página registrados em campo, segmentado entre mobile e desktop."* [FATO]

[INFERÊNCIA] O INP é o número que mais importa para um widget de chat: cada toque no launcher, cada envio de mensagem, cada abertura de painel é uma interação medida. **200 ms** é o orçamento por interação — e ele é do **site do cliente**, não nosso. Um widget que bloqueia a thread principal degrada a métrica de quem nos contratou.

## 8.3 Skeleton × spinner × nada

[FATO — nngroup.com/articles/skeleton-screens/]

> *"Spinners ou animações de espera dão feedback de que o sistema está trabalhando mas não dão nenhuma indicação de quanto tempo o usuário vai ter que esperar; portanto, são melhor usados quando a página leva **2 a 10 segundos** para carregar. Da mesma forma, skeleton screens devem ser usados com tempo de espera **abaixo de 10 segundos**. Por outro lado, barras de progresso são fortemente recomendadas para qualquer página que leve mais de 10 segundos."*
>
> *"Spinners são tipicamente melhor usados em um módulo único, como um vídeo ou um card num dashboard. **Skeleton screens (com exceção dos de frame-display) são melhores quando a tela inteira está carregando**, porque o wireframe dá aos usuários uma noção de como a página vai ficar e assim minimiza a carga cognitiva."*

E o que **não** fazer [FATO]:

> *"Uma variação que **não** recomendamos é um skeleton screen que exibe apenas o frame da aplicação sem um wireframe de conteúdo. (…) não dá aos usuários uma noção da estrutura geral. Um frame display não é recomendado porque, se os usuários forem forçados a esperar demais, eles vão assumir que a página não está funcionando."*

[INFERÊNCIA] Mapeamento para o widget:

| Espera | Tratamento |
|---|---|
| Abrir o painel (< 100 ms se o painel já está montado) | **Nada.** Renderizar direto. |
| Carregar histórico de conversa (2–10 s) | **Skeleton** com a forma de 2–3 balões alternados — não um frame vazio, não um spinner |
| Enviar mensagem | **Optimistic UI**: a bolha aparece na hora, com estado "enviando", e muda para "enviado" no ACK |
| Aguardar resposta da IA | Indicador de atividade + **streaming** assim que o primeiro token chegar (§9.1) |
| Reconectar | Faixa discreta, não bloqueante |

## 8.4 Orçamento de tempo até o widget ser interativo

[INFERÊNCIA — a partir dos limites acima] Proposta de orçamento, a ser validada por medição na implementação:

| Marco | Alvo |
|---|---|
| Launcher visível e clicável | ≤ 1,0 s após o script carregar (limite do "fluxo de pensamento") |
| Abertura do painel após clique | ≤ 200 ms (limite do INP "bom") |
| Primeira mensagem visível no painel | ≤ 1,0 s |
| Contribuição do widget para o CLS do cliente | **0** — o launcher é `position:fixed` e não deve empurrar nada |

O CLS zero não é meta ambiciosa, é obrigação: um elemento fixo sobreposto não participa do fluxo, então qualquer contribuição nossa para o CLS do cliente é bug.

## 8.5 A decisão de design que compra mais performance percebida

[INFERÊNCIA, ancorada nos limites da §8.1] Renderizar o **launcher** antes de qualquer outra coisa, com CSS crítico inline e sem depender do bundle da conversa. O visitante que não clica — a maioria — nunca paga o custo do painel. O que precisa estar pronto em 1 segundo é o launcher, não o chat.

---

# 9. Padrões de UI de IA em chat

## 9.1 Streaming token a token

[INFERÊNCIA a partir dos limites da §8.1] O streaming existe porque o limite de 10 segundos de atenção é excedido por qualquer resposta de LLM minimamente longa. Mostrar o primeiro token em ~1 s mantém o usuário dentro do limite de "fluxo ininterrupto", mesmo que a resposta completa leve 8 s.

**O custo de acessibilidade, e a solução, são os da §4.3**: `aria-busy="true"` durante o streaming, `false` ao concluir. Sem isso, o leitor de tela tenta anunciar cada fragmento.

[INFERÊNCIA] Dois requisitos adicionais que costumam ser esquecidos:
- **Não fazer autoscroll agressivo durante o streaming.** Se o usuário rolou para cima para reler algo, o texto crescendo embaixo não pode arrastá-lo de volta. A regra: autoscroll só se o usuário já estava no fim da lista.
- **`prefers-reduced-motion`**: se o "efeito máquina de escrever" for cosmético (texto já recebido sendo revelado gradualmente), ele precisa ser desligado sob `prefers-reduced-motion` — é animação disparada por interação (SC 2.3.3, AAA) e informação em movimento (SC 2.2.2, **A**, se durar mais de 5 s). Se o texto está genuinamente chegando pela rede, não é animação; é conteúdo.

## 9.2 Transparência: "sou uma IA"

Três fontes independentes convergem, e isso é raro:

[FATO — NN/g] *"Nossos participantes ficaram satisfeitos quando o negócio foi transparente sobre usar um bot (…) Acreditamos que isso é um erro [não revelar]."*

[FATO — IBM Carbon for AI, carbondesignsystem.com/guidelines/carbon-for-ai/, página atualizada em 11/08/2026]
> *"**Use o AI label e a estilização para marcar qualquer instância de uso de IA.** Transparência da presença de IA é chave para a confiança do usuário."*
> *"**Não use a estilização Carbon for AI como decoração.** Embora esses novos elementos de estilo sejam sedutores, eles são estritamente destinados a identificar quaisquer instâncias de IA sendo usada em uma experiência."*
> *"Ao projetar uma experiência de IA, pergunte se o usuário sabe que IA está sendo usada."*

[FATO — Microsoft HAX Toolkit, 18 Guidelines for Human-AI Interaction, síntese de 20+ anos de pesquisa, paper CHI 2019]
> **G1**: *"Make clear what the system can do."* — **G2**: *"Make clear how well the system can do what it can do."*

[INFERÊNCIA] Prescrição: a identidade de IA aparece (a) no cabeçalho do painel, de forma persistente, e (b) atrelada à bolha, não só na primeira mensagem. O usuário que entra numa conversa longa, ou que volta depois, precisa saber com quem está falando **naquele momento** — e o handoff para humano (§9.6) muda essa resposta no meio da conversa.

## 9.3 As 18 diretrizes HAX — a lista completa

[FATO — microsoft.com/en-us/haxtoolkit/, lista extraída da HAX Design Library]

| # | Diretriz | Aplicação num chat de site |
|---|---|---|
| G1 | Make clear what the system can do | Tela inicial diz o que o bot resolve |
| G2 | Make clear how well the system can do what it can do | Não prometer o que não entrega |
| G3 | Time services based on context | Convite proativo no momento certo (§7) |
| G4 | Show contextually relevant information | Usar a página em que o visitante está |
| G5 | Match relevant social norms | Tom compatível com o público brasileiro |
| G6 | Mitigate social biases | |
| G7 | Support efficient invocation | Launcher sempre acessível |
| G8 | **Support efficient dismissal** | **Fechar em um toque, sem confirmação, sem reabrir** |
| G9 | **Support efficient correction** | **Editar/reenviar, regenerar resposta** |
| G10 | Scope services when in doubt | Na dúvida, oferecer o humano |
| G11 | Make clear why the system did what it did | Citação de fonte (§9.4) |
| G12 | **Remember recent interactions** | Não repetir pergunta já respondida (§7.4 achado 6) |
| G13 | Learn from user behavior | |
| G14 | Update and adapt cautiously | |
| G15 | **Encourage granular feedback** | Polegar por resposta, não só CSAT no fim |
| G16 | Convey the consequences of user actions | Deixar claro o que acontece ao enviar dado pessoal |
| G17 | Provide global controls | Silenciar som, encerrar conversa, apagar histórico |
| G18 | Notify users about changes | Handoff visível (§9.6) |

## 9.4 Citação de fonte

[FATO — IBM Carbon for AI]
> *"O AI label é também o gatilho para o **popover de explicabilidade**, que serve como a primeira camada de explicabilidade. Ele oferece uma forma consistente e antecipada de acessar explicabilidade, com a opção de aprofundar em mais detalhes se necessário."*
> *"**Integre explicabilidade ao fluxo de trabalho e à experiência geral.** Essa integração exige que você minimize distrações e mostre explicações apenas quando necessário ou solicitado pelo usuário."*

[INFERÊNCIA] Duas regras que saem daí: a citação é uma **camada**, acessível sob demanda, não um bloco de texto empurrado dentro de cada resposta; e ela precisa de um ponto de entrada **consistente** — o mesmo affordance, no mesmo lugar, em toda resposta de IA.

## 9.5 Feedback do usuário sobre a resposta

[FATO — Google PAIR Guidebook, "Feedback + Control"]
> *"Na maioria dos casos, as opções de resposta de feedback devem ser **mutuamente exclusivas e coletivamente exaustivas**. Por exemplo, polegar para cima versus polegar para baixo é inequívoco ('sim' ou 'não'), mutuamente exclusivo (não 'sim e não'), e cobre a faixa completa de opiniões úteis ('mais ou menos' não é muito acionável)."*
> *"Deixe o usuário saber onde ele pode ver seus dados e onde pode mudar as configurações de coleta de dados. Idealmente, faça isso no contexto."*
> *"Não colete dados implicitamente sem contar às pessoas."*

[FATO — HAX G15] *"Encourage granular feedback."*

[INFERÊNCIA] Polegar cima/baixo por resposta, **não** uma escala de 5 estrelas (não é mutuamente exclusiva nem acionável), e o polegar para baixo abre um campo opcional de texto — que é onde está a informação útil.

## 9.6 Handoff visível para humano

[FATO — NN/g] *"Assumir a falha e oferecer uma escotilha de escape (número de telefone ou atendente ao vivo) foi geralmente percebido de forma favorável."*
[FATO — HAX G10] *"Scope services when in doubt."* [FATO — HAX G18] *"Notify users about changes."*

[INFERÊNCIA] O handoff precisa de **três marcações visuais distintas**:
1. **Uma mensagem de sistema** no fluxo, marcando o momento ("Você foi transferido para Maria, do time de vendas").
2. **Mudança persistente no cabeçalho** — nome, foto e status de quem está atendendo agora.
3. **Mudança na identidade da bolha** — as mensagens do humano não podem carregar a marcação de IA.

E o inverso também vale: quando o humano sai e a IA volta, a mesma sinalização em três lugares. O usuário nunca deve precisar perguntar "você é robô?".

## 9.7 Indicador de raciocínio ("pensando…")

[INFERÊNCIA] Um indicador de raciocínio é honesto quando o modelo está de fato num passo intermediário (busca, chamada de ferramenta) e desonesto quando é só uma animação para preencher latência de rede.

Regras: o indicador precisa dizer **o que** está acontecendo quando isso é conhecido ("consultando seus pedidos") e ser genérico quando não é; não pode durar mais de 5 s sem controle do usuário (SC 2.2.2, nível A [FATO]); e não deve ser anunciado repetidamente pelo leitor de tela (§4.4).

## 9.8 Correção e regeneração

[FATO — HAX G9] *"Support efficient correction."*

[INFERÊNCIA] Mínimo viável: reenviar a última mensagem, regenerar a última resposta da IA, e copiar a resposta. Cada um desses é um alvo de toque que precisa dos 24 px do SC 2.5.8 — e eles ficam agrupados, o que ativa a regra de espaçamento (círculos de 24 px que não se cruzam).

---

# 10. A constituição visual proposta

Tudo abaixo é **[INFERÊNCIA]** — é a minha proposta, derivada dos fatos e das medições das seções 1 a 9. Cada linha traz a âncora.

## 10.1 Tipografia

| Token | Valor | Âncora |
|---|---|---|
| `--chat-font-family` | `system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif` | §2.6 (peso, FOUT, CSP) |
| `--chat-text-message` | **15px / 22px / 400** | §2.2 (medida), §2.3 (entrelinha 1,47) |
| `--chat-text-message-lg` | 16px / 24px / 400 | Variante de densidade confortável |
| `--chat-text-author` | 12px / 16px / **500** | §2.4 |
| `--chat-text-meta` | 12px / 16px / 400 + `tabular-nums` | §2.4, §2.5 |
| `--chat-text-system` | 12px / 16px / 400 | §2.4 |
| `--chat-text-input` | **16px** / 24px / 400 | §10.6 — regra anti-zoom iOS |
| `--chat-text-button` | 14px / 20px / 500 | |
| `--chat-text-title` | 16px / 24px / 600 | Cabeçalho do painel |
| **Piso absoluto** | **12px** | §2.1 |

## 10.2 Espaçamento

`--space-0: 0` · `--space-05: 2px` · `--space-1: 4px` · `--space-2: 8px` · `--space-3: 12px` · `--space-4: 16px` · `--space-5: 20px` · `--space-6: 24px` · `--space-8: 32px` · `--space-10: 40px` · `--space-12: 48px`

Âncora: §1.1 (convergência de 4 sistemas), §5.8.

Aplicação prescrita:

| Uso | Valor |
|---|---|
| Padding interno da bolha | 8px 12px |
| Espaço entre mensagens do mesmo autor | 4px |
| Espaço entre autores diferentes | 12px |
| Espaço entre grupos temporais | 20px |
| Padding lateral do painel | 12px |
| Padding do rodapé | 12px + `env(safe-area-inset-bottom)` |
| Gap entre ícones do rodapé | 8px mínimo (§4.1, regra de espaçamento do SC 2.5.8) |

## 10.3 Raios

`--radius-0: 0` · `--radius-1: 4px` · `--radius-2: 8px` · `--radius-3: 12px` · `--radius-4: 16px` · `--radius-5: 20px` · `--radius-full: 9999px`

| Elemento | Raio |
|---|---|
| Bolha (cantos livres) | 16px |
| Bolha (canto de "rabinho") | 4px |
| Chip de resposta rápida | `full` |
| Campo de digitação | 12px (ou `full` se for pill) |
| Cartão dentro da conversa | 12px |
| Painel | 16px |
| Launcher | `full` |

Âncora: §1.1, §6.5 (raio proporcional ao elemento).

## 10.4 Elevação

| Nível | Tema claro | Tema escuro |
|---|---|---|
| `--elev-0` | `none` | `none` |
| `--elev-1` (chip, cartão) | `0 1px 2px rgba(0,0,0,.06), 0 1px 3px rgba(0,0,0,.10)` | `none` + borda 1px `rgba(255,255,255,.08)` |
| `--elev-2` (launcher) | `0 4px 8px -2px rgba(0,0,0,.14), 0 2px 4px rgba(0,0,0,.08)` | superfície +1 degrau de claridade + borda |
| `--elev-3` (painel) | `0 12px 28px -6px rgba(0,0,0,.20), 0 4px 8px rgba(0,0,0,.08)` | superfície +2 degraus + borda |

Âncora: §1.1 (Polaris zera a sombra no dark), §3.5, §6.4.

## 10.5 Movimento

| Uso | Duração | Curva | Âncora |
|---|---|---|---|
| Hover / press | 100 ms | `cubic-bezier(0.2, 0, 0, 1)` | M3 `short2` + `easing-standard` [FATO] |
| Abrir/fechar painel | 250–300 ms | `cubic-bezier(0.05, 0.7, 0.1, 1)` (entrada) / `cubic-bezier(0.3, 0, 0.8, 0.15)` (saída) | M3 `medium1/2` + emphasized decelerate/accelerate [FATO] |
| Bolha entrando na lista | 150 ms | standard | M3 `short3` |
| Bottom sheet | 300–400 ms | emphasized | M3 `medium2/4` |

**Regra dura**: sob `prefers-reduced-motion: reduce`, toda transição de movimento cai para ≤ 1 ms ou vira fade. Sem exceção estética.

## 10.6 Cor — as regras, não a paleta

A paleta depende da marca do cliente. As **regras** não:

| # | Regra | Âncora |
|---|---|---|
| C1 | Texto sobre balão de marca: escolher entre `#ffffff` e **`#000000` puro** pela **luminância relativa** (limiar 0,17913), nunca por YIQ | §3.2 |
| C2 | Se nenhuma das duas atingir 4,5:1, ajustar a **luminância do fundo** até atingir, preservando o matiz | §3.2.2 |
| C3 | Texto do corpo: ≥ 4,5:1 em ambos os temas | SC 1.4.3 [FATO] |
| C4 | Borda de input, ícone sem rótulo, estado ativo: ≥ 3:1 | SC 1.4.11 [FATO] |
| C5 | Nenhuma informação transmitida só por cor | SC 1.4.1 [FATO] + §3.4 |
| C6 | Distinção informativa por cor deve ser de **luminância**, não de matiz | §3.4 (ΔE em deuteranopia) |
| C7 | Tema escuro é uma paleta separada, não uma inversão | §3.5 |
| C8 | Fundo do tema escuro não é `#000` puro | §3.5 |
| C9 | Respeitar `prefers-color-scheme` por padrão | §6.6 |
| C10 | Sob `backdrop-filter`, o fallback sólido sozinho já atende ao contraste | §6.3 |

## 10.7 Alvos e foco

| Regra | Valor | Âncora |
|---|---|---|
| Alvo mínimo (absoluto) | **24 × 24 px** | SC 2.5.8 AA [FATO] |
| Alvo em contexto de toque | **44 × 44 px** (ideal 48) | SC 2.5.5 AAA + HIG default + M3 48 dp [FATO] |
| Alvo em contexto de ponteiro | **44 × 44 px** | M3 pointer target [FATO] |
| Launcher | **56 × 56 px** | Alvo primário; folga sobre o AAA |
| Espaçamento entre alvos | **≥ 8 px**; se o alvo tiver < 24 px, círculos de 24 px sem interseção | M3 [FATO] + SC 2.5.8 exceção "Spacing" [FATO] |
| Ícone dentro do alvo | 20–24 px de desenho, com padding até o alvo completo | M3: *"o alvo se estende além dos limites visuais"* [FATO] |
| Indicador de foco | Anel de 2 px + offset 2 px, com contraste ≥ 3:1 contra fundo **claro e escuro** | SC 2.4.7 + 2.4.13 [FATO] |
| `outline` | Nunca `none`. Use `outline: 2px solid transparent` + `box-shadow` para preservar alto contraste forçado | Técnica do GOV.UK [FATO] + `forced-colors` §4.7 |

## 10.8 Layout

| Regra | Valor | Âncora |
|---|---|---|
| Largura do painel em desktop | **400 px** (aceitável 380–420) | §2.2 |
| Largura máxima da bolha | **88%** da largura útil | §2.2 |
| Altura do painel em desktop | `min(640px, calc(100dvh - 96px))` | §5.4 |
| Mobile < 768 px | Fullscreen com `100dvh` | §5.2, §5.4 |
| Reflow | Funcionar em 320 px de largura | SC 1.4.10 [FATO] |
| Rodapé | `padding-bottom: max(12px, env(safe-area-inset-bottom))` | §5.3 |
| Contribuição para o CLS do cliente | **0** | §8.4 |

## 10.9 Preferências do usuário

| Media query | Comportamento obrigatório |
|---|---|
| `prefers-reduced-motion: reduce` | Todas as transições ≤ 1 ms ou fade. Sem shimmer, sem typewriter cosmético, sem bounce. |
| `prefers-contrast: more` | Bordas 1 px → 2 px; texto secundário sobe para o contraste do texto primário; indicador de foco engrossa. |
| `forced-colors: active` | Remover fundos decorativos; usar cores de sistema; **garantir que as bolhas continuem distinguíveis por borda, não por cor**. |
| `prefers-color-scheme` | Respeitado por padrão; o cliente pode forçar um tema. |

Âncora: §4.7 — todas as três são Baseline widely available.

---

# 11. Checklist de acessibilidade verificável

Cada item é **testável** — não é princípio, é passa/falha. Os números vieram das seções anteriores.

## Contraste

- [ ] Texto do corpo ≥ 4,5:1 no tema claro *(medir com calculadora de contraste)*
- [ ] Texto do corpo ≥ 4,5:1 no tema escuro
- [ ] Texto sobre balão de marca ≥ 4,5:1 para as 5 cores de marca mais usadas pelos clientes
- [ ] Texto secundário (horário, sistema) ≥ 4,5:1 — **não** é "texto grande", tem 12 px
- [ ] Borda do campo de digitação ≥ 3:1 contra o fundo do painel
- [ ] Ícone de enviar ≥ 3:1 contra o fundo do botão
- [ ] Estado desabilitado: se transmite informação, ≥ 3:1
- [ ] Indicador de foco ≥ 3:1 contra o elemento e contra o fundo, nos dois temas

## Cor

- [ ] Nenhum status (online/ausente/ocupado) distinguível apenas por cor
- [ ] Nenhuma distinção IA/humano/sistema feita apenas por matiz
- [ ] Erro de envio sinalizado por ícone + texto, não só por cor
- [ ] Testado em simulação de deuteranopia

## Alvos

- [ ] Botão fechar ≥ 24 × 24 px
- [ ] Todos os ícones do rodapé ≥ 24 × 24 px
- [ ] Launcher ≥ 44 × 44 px
- [ ] Chips de resposta rápida ≥ 24 px de altura
- [ ] Alvos adjacentes menores que 24 px passam na regra dos círculos
- [ ] Botões de feedback (polegar) ≥ 24 × 24 px e separados entre si

## Teclado

- [ ] Launcher alcançável por Tab
- [ ] Enter/Espaço abrem o painel
- [ ] Foco vai para dentro do painel ao abrir
- [ ] Esc fecha o painel
- [ ] Foco volta ao launcher ao fechar
- [ ] Toda ação alcançável sem mouse
- [ ] Nenhum `tabindex` positivo
- [ ] Ordem de Tab = ordem visual
- [ ] Com o painel aberto em modal, o fundo é `inert`
- [ ] Nenhuma armadilha de foco em modo não-modal

## Leitor de tela

- [ ] Lista de mensagens com `role="log"`
- [ ] `aria-busy="true"` durante streaming, `false` ao concluir
- [ ] Typing indicator **não** anunciado repetidamente
- [ ] Recibos de leitura **não** anunciados
- [ ] Erros com `role="alert"`
- [ ] Nenhum `aria-live="assertive"` na chegada de mensagem normal
- [ ] Todo `aria-label` traduzido (nenhum "Close" em interface pt-BR)
- [ ] `lang` correto no contêiner do widget
- [ ] Launcher com nome acessível descritivo (não "botão")

## Movimento

- [ ] `prefers-reduced-motion: reduce` desliga todas as transições
- [ ] Nenhuma animação em loop dura mais de 5 s sem controle *(SC 2.2.2, nível A)*
- [ ] Typing indicator pausável ou de duração limitada
- [ ] Autoscroll não arrasta o usuário que rolou para cima

## Preferências do sistema

- [ ] `prefers-contrast: more` reforça bordas e foco
- [ ] `forced-colors: active` — as bolhas do visitante e do agente continuam distinguíveis (por borda ou alinhamento, não por cor)
- [ ] `forced-colors: active` — o indicador de foco continua visível (`outline: transparent`, não `none`)
- [ ] `prefers-color-scheme` respeitado quando o cliente não força tema

## Layout e zoom

- [ ] Funciona a 320 px de largura *(SC 1.4.10)*
- [ ] Funciona a 200% de zoom *(SC 1.4.4)*
- [ ] Funciona com entrelinha 1,5 / letter-spacing 0,12em / word-spacing 0,16em forçados *(SC 1.4.12)*
- [ ] Nada quebra no maior tamanho de Dynamic Type
- [ ] Rodapé respeita `safe-area-inset-bottom`
- [ ] Painel não fica atrás do teclado virtual **(pendente: testar em dispositivo real)**

## Comportamento

- [ ] Launcher na mesma posição relativa em todas as páginas *(SC 3.2.6, nível A)*
- [ ] Nenhum gesto de arrastar é a única forma de executar uma ação *(SC 2.5.7)*
- [ ] Foco nunca fica inteiramente escondido atrás do painel *(SC 2.4.11)*
- [ ] Fechar exige um único toque, sem confirmação
- [ ] Não reabre sozinho depois de fechado na mesma sessão
- [ ] Os 15 estados da §5.7 estão todos desenhados (nenhum "a gente vê depois")
- [ ] Se o bundle do widget falhar, o launcher degrada para um canal de contato — não some nem vira tela em branco
- [ ] Mensagens consecutivas do mesmo autor são agrupadas *(§5.6 — 22,8% de altura medida)*

---

# 12. As 15 regras inegociáveis do redesenho

Cada uma tem número, âncora e teste. Se uma decisão de design conflitar com uma destas, a decisão muda — não a regra.

| # | Regra | Âncora | Como se testa |
|---|---|---|---|
| **1** | **Nada de texto abaixo de 12 px** em nenhum papel do widget. | §2.1 · Apple HIG mínimos [FATO] | Inspecionar `font-size` computado de todos os nós de texto |
| **2** | **Mensagem em 15px/22px**, entrelinha 1,45–1,5. Nunca abaixo de 1,4. | §2.2, §2.3 [MEDIDO] | `getComputedStyle` na bolha |
| **3** | **Campo de digitação em 16 px**, sempre. | §10.1 · zoom automático do Safari iOS abaixo de 16px [FATO·2ª] | `getComputedStyle` no `input`/`textarea` |
| **4** | **Painel de 400 px** em desktop, bolha a 88% — entrega 39,4 caracteres/linha. Em 320 px (o mínimo do SC 1.4.10) a medida cai para 27,9, o que é o piso tolerável, não o alvo. | §2.2 [MEDIDO] | Medir `getBoundingClientRect()` e contar caracteres por linha |
| **5** | **`tabular-nums` em todo horário, contador e recibo.** | §2.5 [MEDIDO: 12 px de variação em Inter] | Renderizar `00:00` e `11:11` e comparar larguras |
| **6** | **Cor do texto no balão de marca decidida por luminância relativa (limiar 0,17913), com preto puro** — nunca por YIQ, nunca "branco por padrão". | §3.2 [MEDIDO: 11 conflitos em 16 cores; 63,9% das cores falham com branco] | Rodar a calculadora sobre as cores de marca dos clientes |
| **7** | **Nenhuma informação apenas por cor.** Status, erro, identidade de IA: sempre cor + forma/ícone/rótulo. | SC 1.4.1 [FATO] · §3.4 [MEDIDO: ΔE 7,9 em deuteranopia] | Screenshot em simulação de deuteranopia |
| **8** | **Tema escuro é paleta própria.** Sombra vira borda, marca é recalibrada, fundo não é `#000`. | §3.5 · Polaris zera sombra no dark [FATO] | Auditar contraste independentemente nos dois temas |
| **9** | **24 px é o piso de alvo; 44 px é o padrão para tudo que é primário.** | SC 2.5.8 AA e 2.5.5 AAA [FATO] | Medir todo elemento clicável |
| **10** | **Foco sempre visível, com anel de contraste ≥ 3:1 nos dois temas.** `outline: none` é proibido; use `outline: transparent` + `box-shadow`. | SC 2.4.7, 2.4.13 [FATO] · técnica GOV.UK [FATO] | Navegar todo o widget por Tab e fotografar cada estado |
| **11** | **A lista de mensagens é `role="log"`, com `aria-busy` durante streaming.** Typing indicator e recibos não são anunciados. | WAI-ARIA 1.2 [FATO] · SC 4.1.3 [FATO] | Testar com leitor de tela; contar anúncios por mensagem |
| **12** | **O widget nunca abre sozinho cobrindo o conteúdo em mobile**, e nunca reabre depois de fechado na mesma sessão. | Google intersticiais [FATO] · Better Ads / 66.000 consumidores [FATO] · NN/g [FATO] | Carregar em mobile e cronometrar; fechar e navegar 3 páginas |
| **13** | **O launcher ocupa a mesma posição relativa em todas as páginas** do site do cliente. | **SC 3.2.6 Consistent Help, nível A** [FATO] | Verificar 5 páginas distintas do mesmo site |
| **14** | **O launcher fica visível e clicável em ≤ 1 s; abrir o painel responde em ≤ 200 ms; a contribuição para o CLS do cliente é 0.** | NN/g limites de resposta [FATO] · INP "bom" ≤ 200 ms [FATO] | Medir com Performance API no site de um cliente real |
| **15** | **A IA se identifica como IA, de forma persistente, e o handoff para humano é sinalizado em três lugares** (mensagem de sistema, cabeçalho, identidade da bolha). | NN/g [FATO] · Carbon for AI [FATO] · HAX G1/G2/G18 [FATO] | Simular handoff e verificar as três marcações |

---

# 13. O que isso significa para o redesenho do ChatSPX

## 13.1 O que este documento decide

Ele fecha a discussão sobre **como deve parecer e por quê**, com números que sobrevivem a "eu acho". Especificamente:

1. **A régua tipográfica está definida** e não é a do painel do atendente. O widget é superfície de consumidor: 15px/22px de mensagem, 16px de input, 12px de piso. O dashboard interno pode continuar em 14px — são telas diferentes com públicos diferentes, e copiar a densidade de uma para a outra seria o erro.

2. **A largura do painel virou uma decisão medida, não estética.** 400 px entrega 39,4 caracteres por linha; 380 px entrega 37; 320 px entrega 27,9. A escolha de largura **é** a escolha de legibilidade, e agora dá para argumentar com número em vez de gosto.

3. **A escrita das mensagens virou requisito de design.** Uma mensagem de 293 caracteres ocupa 9 linhas e 214 px de altura. Duas dessas enchem o painel. Isso é uma restrição para quem escreve o prompt do bot e para quem treina o atendente — não é um problema de CSS, e não tem solução em CSS.

## 13.2 O bug real que a apuração encontrou

Não estava no escopo procurar, mas a medição de contraste esbarrou nele: **`isWidgetColorLighter()` em `app/javascript/shared/helpers/colorHelper.js` usa a fórmula errada.**

A heurística YIQ com limiar 225 diverge da regra WCAG em **11 das 16 cores de marca que testei**, sempre escolhendo branco onde o preto teria muito mais contraste. Com a cor padrão do próprio produto (`#1f93ff`), o texto branco dá **3,15:1** — abaixo do mínimo AA — quando o preto daria 6,68:1. Com o verde do WhatsApp, que é uma cor de marca plausível para um cliente brasileiro, o branco dá **1,98:1**.

Não toquei no arquivo. Mas isso não é refinamento estético do redesenho: é uma falha de acessibilidade que já está em produção, e o redesenho é a oportunidade natural de corrigi-la. O número exato para a correção está na §3.2.1: limiar de luminância **0,17913**, cor escura **`#000000` puro** (com `#111111` ou `#18181b`, entre 3,4% e 6,8% das cores de marca ficam sem saída possível).

## 13.3 O critério de acessibilidade que muda a roadmap

**SC 3.2.6 Consistent Help é nível A** — o patamar mais básico da WCAG — e diz que um mecanismo de contato humano repetido em várias páginas tem que aparecer na mesma ordem relativa. Um widget de chat é literalmente isso.

[INFERÊNCIA] Consequência de produto: a funcionalidade "ocultar o widget em determinadas páginas" e qualquer ideia de "mover o launcher conforme o contexto da página" entram em conflito com um critério de nível A. Não é impeditivo absoluto — há leituras possíveis — mas é uma decisão que precisa ser tomada com o critério na mesa, e não descoberta numa auditoria depois.

## 13.4 Onde eu recomendo não seguir a moda

**Liquid Glass no painel: não.** A própria Apple escreve *"não use Liquid Glass na camada de conteúdo"* e *"use a variante regular quando componentes tiverem quantidade significativa de texto"*. Um painel de chat é quantidade significativa de texto. Além disso, `backdrop-filter` só entrou em Baseline "newly available" em 16/09/2024 — cedo demais para código de terceiro em navegador alheio. Blur, se entrar, entra atrás de `@supports`, no cabeçalho ou no launcher, nunca atrás de texto de conversa.

**Roxo como marcador exclusivo de IA: não.** Roxo virou convenção de mercado, mas medi: contra o azul de informação, o par colapsa para **ΔE 1,8 em deuteranopia** — a mesma cor. Roxo pode ser o sotaque; o marcador tem que ser rótulo ou ícone.

**Densidade compacta: não.** É a tendência dominante em ferramentas de produtividade e é a régua errada aqui. O visitante do site do cliente não é usuário treinado; é alguém no celular, provavelmente com pressa.

## 13.5 As três lacunas que este documento não fecha

Registro explicitamente, para que ninguém assuma cobertura que não existe:

1. **Comportamento de `dvh`/`svh`/`lvh` com barra de endereço real.** Medi que o Chromium 145 suporta os três, e medi que em headless eles retornam o mesmo valor — porque não há barra de endereço. Nada aqui afirma como Safari iOS ou Chrome Android se comportam de fato. Precisa de dispositivo real.

2. **Teclado virtual e `visualViewport`.** A API é Baseline widely available, mas não testei nenhuma das duas estratégias de reposicionamento do rodapé. Precisa de dispositivo real, antes de escolher a abordagem.

3. **`overscroll-behavior` no Safari.** O webstatus.dev lista Chrome/Edge 144 e Firefox 150, **sem entrada para Safari**. Se isso se confirmar em teste, o scroll do painel vai vazar para a página em iOS e o tratamento terá que ser em JavaScript. Precisa de verificação direta.

## 13.6 A ordem em que eu atacaria

1. **Fixar os tokens da §10** antes de desenhar qualquer tela. Sem isso, cada tela inventa a própria escala e a reconciliação depois custa mais que a decisão agora.
2. **Corrigir o cálculo de contraste do balão** (§13.2) — é a única coisa aqui que já está errada em produção.
3. **Desenhar em 400 px e validar em 320 px**, nessa ordem. O reflow em 320 px é critério AA, não caso de borda.
4. **Rodar o checklist da §11 como gate**, não como revisão final. Um item falhando é bloqueio, do mesmo jeito que um teste vermelho.
5. **Fechar as três lacunas da §13.5 em dispositivo real** antes de congelar o layout mobile.

---

## Anexo A — Pranchas geradas nesta apuração

Todas em `plano/estudo-chat-web/frontend/shots/`, prefixo `t13-`:

| Arquivo | Conteúdo |
|---|---|
| `t13-escala-tipografica-mensagem-light.png` / `-dark.png` | Três variantes de corpo (14/15/16) no mesmo painel de 400 px, com autor, horário e recibo |
| `t13-medida-caracteres-por-linha.png` | Matriz completa de 36 medições: painel × largura de bolha × corpo → caracteres/linha |
| `t13-contraste-balao-marca.png` | 12 cores de marca: luminância, contraste com branco e preto, escolha WCAG × escolha YIQ, e os balões renderizados |
| `t13-daltonismo-status.png` | Indicadores de status em visão tricromática, protanopia, deuteranopia e tritanopia + tabela de ΔE2000 |
| `t13-alvos-de-toque.png` | Alvos de 20/24/28/44/48 px comparados + demonstração da regra dos círculos de 24 px |
| `t13-foco-espacamento-raios.png` | Quatro estratégias de indicador de foco (incluindo a do GOV.UK) + escala de espaçamento + escala de raios |
| `t13-tabular-nums.png` | Sete horários em Inter/Roboto/Arial, com e sem `tabular-nums` |
| `t13-agrupamento-mensagens.png` | A mesma conversa de 6 mensagens com e sem agrupamento (economia medida de 22,8% de altura) |
| `t13-elevacao-vs-borda-light.png` / `-dark.png` | Cinco sombras + uma borda, no mesmo card, nos dois temas |
| `t13-apple-hig-dynamic-type-large-default.png` | Captura da tabela de especificações do Apple HIG |

## Anexo B — Fontes primárias consultadas

**Especificações**
- WCAG 2.2 — `https://www.w3.org/TR/WCAG22/` (baixada íntegra, 512.457 bytes, 11/08/2026)
- WAI-ARIA 1.2 — `https://www.w3.org/TR/wai-aria-1.2/` (baixada íntegra, 1.410.696 bytes)
- Baseline / Web Platform Dashboard — `https://api.webstatus.dev/v1/features?q=...`

**Design systems (token servido, não página de marketing)**
- Material 3 — `unpkg.com/@material/web/tokens/versions/v0_192/_md-sys-{typescale,shape,elevation,state,motion}.scss`, `@material/web/elevation/internal/_elevation.scss`
- Polaris — `unpkg.com/@shopify/polaris-tokens/dist/css/styles.css` (28.240 bytes)
- Carbon — `unpkg.com/@carbon/type/scss/{_styles,_scale,_font-family}.scss`, `unpkg.com/@carbon/layout/scss/generated/_spacing.scss`
- GOV.UK — `unpkg.com/govuk-frontend/dist/govuk/govuk-frontend.min.css` (125.827 bytes)
- Atlassian — `atlassian.design/foundations/typography`, `/foundations/spacing`

**Documentação de plataforma**
- Apple HIG — Typography, Layout, Accessibility, Materials, Sheets, Color
- Material 3 — Bottom sheets, Color roles, Motion specs
- web.dev — Web Vitals, INP, LCP

**Pesquisa e diretrizes**
- Nielsen Norman Group — Chatbots, Popups, Response Time Limits, Skeleton Screens
- Coalition for Better Ads — The Research (66.000+ consumidores)
- Google Search Central — Helping users easily access content on mobile (2016)
- Microsoft HAX Toolkit — 18 Guidelines for Human-AI Interaction (CHI 2019)
- Google PAIR Guidebook — Feedback + Control
- IBM Carbon for AI (página atualizada em 11/08/2026)
- Google Design — Expressive Material Design research (46 estudos, 18.000+ participantes)

**Anúncios datados**
- Apple Newsroom, 09/06/2025 — Liquid Glass
- blog.google, 13/05/2025 — Material 3 Expressive

**Código do próprio repositório (leitura, sem alteração)**
- `app/javascript/shared/helpers/colorHelper.js`

**Ambiente de medição**
- Chromium 145.0.7632.6 via Playwright (headless, `--no-sandbox --disable-dev-shm-usage`)
- Fontes de teste: Inter 400/500 e Roboto 400 de `@fontsource` (embutidas como `data:` URI), Nimbus Sans, Lato e DejaVu Sans do sistema
- Scripts próprios em Python para contraste WCAG, simulação de daltonismo (Viénot/Brettel) e ΔE2000
