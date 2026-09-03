# 16 — Especificação de redesenho do widget ChatSPX

> **O que é este documento.** A especificação que um designer e um dev executam para repaginar o
> widget de site do ChatSPX. Não é ensaio, não é levantamento: é documento de execução.
> Toda medida aqui tem âncora num relatório desta onda ou da anterior.
>
> **Fase:** estudo. **Nenhum arquivo de código foi alterado.** Nenhum build, deploy, restart ou
> migration. O único artefato produzido por esta task é este markdown.
>
> **Data:** 12/08/2026. **Branch:** `homologacao`. **Base:** fork ChatSPX sobre Chatwoot v4.12.1.

---

## 0. Antes de ler

### 0.1 Estado das entradas

Todos os relatórios pedidos existem e foram lidos na íntegra. Nada faltou.

| Relatório | Linhas | O que traz para esta spec |
|---|---:|---|
| `frontend/11-teardown-visual.md` | 1.266 | Medidas visuais de 16 concorrentes: launcher, painel, balão, tipografia, paleta, mobile, dark |
| `frontend/12-motion-estados.md` | 1.033 | Durações, curvas, estados, typing, scroll, foco, teclado, som, `prefers-reduced-motion` |
| `frontend/13-linguagem-visual-2026.md` | 1.542 | Tokens de 6 design systems, WCAG 2.2, medida de caracteres/linha, contraste, daltonismo, IA |
| `frontend/14-logica-concorrentes.md` | 2.005 | Transporte, reconexão, offline, storage, segmentação, gatilhos, handoff, API pública |
| `frontend/15-arquitetura-front-chatspx.md` | 1.674 | Raio-X do nosso front: componentes, tokens, bundle, a11y medida, risco de merge |
| `06-ux-conversao.md` | 2.270 | Anatomia, proatividade, formulário conversacional, sinais de vida, handoff, anti-padrões |
| `09-nosso-widget-auditoria.md` | 1.618 | Inventário de features, configuração por inbox, dívidas, pontos de extensão |
| `10-gap-analysis.md` | 839 | Matriz de 68 capacidades, baldes de gap, ondas, perguntas em aberto |

### 0.2 Marcação de procedência

| Marca | Significa |
|---|---|
| **[MEDIDO]** | Número lido no navegador/CSS/bundle por um dos relatórios desta onda. A âncora diz qual. |
| **[FATO]** | Especificação, documentação oficial ou `arquivo:linha` deste repositório. |
| **[CALCULADO]** | Aritmética minha sobre valores medidos, com a conta à vista. |
| **[DECISÃO]** | Escolha desta spec. É prescrição, não observação. Sempre traz o porquê. |
| **[DIVERGÊNCIA]** | Os relatórios de entrada discordam. Os dois lados estão declarados na §0.3. |
| **[NÃO VERIFICADO]** | Ninguém verificou. Fica como lacuna, nunca preenchido com chute. |

**Regra de rigor herdada da onda:** onde um relatório mediu o launcher, nada é afirmado sobre o
painel; onde mediu desktop, nada é afirmado sobre mobile. Esta spec preserva essa separação e a
repete em cada componente.

### 0.3 Divergências entre os relatórios de entrada

Nove pontos em que 11, 12, 13, 15, 06 e 09 não dizem a mesma coisa. Nenhum foi resolvido em
silêncio. Onde há decisão, ela está marcada e justificada; onde é direção de marca, virou pergunta
na §10.

| # | Tema | Lado A | Lado B | Resolução desta spec |
|---|---|---|---|---|
| **DV-1** | **Corpo da mensagem** | **13 §10.1/§12 regra 2:** 15px/22px, porque widget é superfície de consumidor (M3 16, Apple 17, GOV.UK 19), não de produtividade | **11 §C10 + rec.1:** 14px é a moda do mercado (6 de 11) e nossos 14/21 estão na mediana — "não há motivo métrico para mexer" | **[DECISÃO] 15/22**, com `--w-text-message-sm: 14/21` disponível como variante de densidade. O 11 descreve o mercado; o 13 prescreve qualidade. Divergência real, custo real (todas as bolhas crescem). **Vira a pergunta Q1 da §10.** |
| **DV-2** | **`max-width` do balão** | **13 §10.8:** 88% da largura útil (foi a combinação medida que deu 39,4 caracteres/linha) | **11 rec.5:** 88% é o 2º mais largo da amostra; 6 de 8 concorrentes ficam entre 70% e 85%; recomenda 78–82% | **[DECISÃO] 82%.** Fica dentro da faixa do mercado e mantém a medida em ~35–36 caracteres/linha (cálculo na §2.7.4), dentro da faixa 32–39 medida pelo 13. |
| **DV-3** | **Padding do balão** | **13 §10.2:** 8px 12px | **11 §C9:** mediana do mercado é 12/16 — exatamente o nosso valor atual | **[DECISÃO] 12px 16px.** É a mediana medida e é o que já temos: zero custo, zero risco. |
| **DV-4** | **Raio do balão** | **13 §10.3/§5.6:** 16px nos cantos livres, 6px no canto de origem | **11 §C9:** a distribuição é **bimodal** (7–12 "documento" ou 20–24 "conversa"); 16 é justamente o meio-termo que não existe no mercado; estamos em 20 | **[DECISÃO] 20px** nos cantos livres, **6px** no canto de origem **só na última bolha do grupo**. Fica no grupo "conversa" (Intercom 20, Leadster 24, LiveChat 22) e adota a regra de agrupamento do 13. |
| **DV-5** | **Achatamento do canto** | **13 §5.6:** canto reduzido é a técnica certa (não quebra em `forced-colors`, não exige pseudo-elemento) | **11 §C9:** 7 de 9 usam raio uniforme; só LiveChat e nós achatamos — estamos em minoria | Mantido o achatamento, **restrito à última bolha do grupo**. É sinal de agrupamento, não decoração. A minoria aqui é assumida, não acidental. |
| **DV-6** | **Tamanho do launcher** | **13 §10.7:** 56×56 px | **11 §C1:** 8 de 9 entre 54 e 65; mediana 60; nossos **64** estão dentro, "não há motivo métrico para mexer" | **[DECISÃO] 64×64.** Mudar custa e não compra nada. O que muda é o **ícone** (§3.1). |
| **DV-7** | **Skeleton no carregamento de histórico** | **13 §8.3:** skeleton com forma de 2–3 balões para esperas de 2–10 s (NN/g) | **12 §9:** skeleton **não é padrão** neste mercado; o histórico carrega em milissegundos e o skeleton "apareceria e sumiria antes de ser lido" | **[DECISÃO] skeleton com atraso**: nada até 600 ms; skeleton de balões a partir daí. Os dois têm razão em faixas diferentes de latência. |
| **DV-8** | **Entrada da bolha de mensagem** | **12 §A6:** ~250 ms, deslocamento de 8–15 px | **13 §10.5:** 150 ms (`short3` do M3) | **[DECISÃO] 200 ms**, `translateY(8px)` + opacidade. Meio-termo dentro das duas faixas. |
| **DV-9** | **Dark mode do ChatSPX** | **09 §9 e 03:** ✅ existe (`composables/useDarkMode.js`, `light`/`dark`/`auto`) | **06 §7.2:** ❌ ChatSPX não tem | O **10 §0.2 (DIV-1)** já arbitrou: **temos**. O 15 completa o quadro: existe, mas o default é `light`, a classe `dark` é aplicada no `<div>` e não no `<html>`, a cor de marca não tem variante escura e o `computed` de preferência do sistema não é reativo. É "existe e está pela metade". |

**Duas divergências menores, registradas para não virarem mito:**

- **Nº de métodos da API pública.** O 10 §2 usa "14 métodos"; o **14 §11.1** contou **13** em
  `window.$chatwoot` (o 14º é `chatwootSDK.run`, de outro objeto). Vale 13 + 1.
- **Nº de ramos do `postMessage` em `App.vue`.** O 09 §15.4 fala em 17 `else if`; o **15 §A2.4**
  mediu **16 ramos no total**. Vale 16. Não muda o diagnóstico.

### 0.4 O que esta spec assume como já decidido

Três coisas vêm de fora desta onda e não são reabertas aqui:

1. **O widget continua em iframe.** Convergência de 11 §C18 (8 de 13 concorrentes), 15 §B10.1 e
   10 §3.4 V2. O híbrido iframe+Shadow DOM proposto no 10 §Q2 é uma decisão de arquitetura
   posterior — esta spec é compatível com ele, mas não depende dele.
2. **A direção visual do fork é "WhatsApp-fiel"** (fundo texturizado na conversa, balão do
   visitante na cor da marca). O que esta spec faz é dar **números** a essa direção e corrigir o que
   ela quebrou. A pergunta sobre manter a textura está na §10 (Q3).
3. **pt-BR é a língua de primeira classe** do produto. Todo rótulo acessível, estado e mensagem de
   erro desta spec nasce em pt-BR.

---

## 1. Princípios do redesenho

Seis. Cada um justificado por achado medido, e cada um serve como critério de desempate quando duas
decisões de design colidirem.

### P1 — Uma cor de marca só, e ela é do cliente

Hoje o widget mostra **duas cores de marca na mesma tela**: numa inbox com `widget_color = #009CE0`,
o launcher e o balão do visitante saem `#009CE0`, e o header, o botão de enviar, os links das
mensagens e os estados de foco saem `#2DC46F` [MEDIDO — 15 §A3.3, em light e dark, desktop e
mobile]. A causa é rastreável: `brand: '#2dc46f'` é um **literal** em `theme/colors.js:123`, e a
variável `--widget-color` que `App.vue:118-125` escreve **não tem um único consumidor em CSS**
[MEDIDO — 15 §A3.3: `grep` retorna 1 ocorrência, a escrita].

Nenhum dos 16 concorrentes medidos exibe duas cores de marca simultâneas [MEDIDO — 11 §B5].

**Consequência operacional:** nenhum componente do redesenho pode conter cor literal. A cor entra
por token, o token deriva do `widget_color`, e a derivação é calculada — nunca digitada.

### P2 — Contraste é calculado, não escolhido

O widget usa hoje a heurística YIQ para decidir a cor do texto sobre a marca
(`@chatwoot/utils`, limiar 186; e `colorHelper.js`, limiar 225). Ela diverge da regra WCAG em
**11 de 16 cores de marca testadas**, sempre no mesmo sentido: escolhe branco onde o preto teria
muito mais contraste [MEDIDO — 13 §3.2].

O resultado está em produção e foi medido: **texto da bolha do visitante em 3,07:1**, nos dois
temas, e **link na bolha do agente em 2,27:1** no tema claro [MEDIDO — 15 §A5.4]. Os dois reprovam
o mínimo AA de 4,5:1 [FATO — WCAG 2.2 SC 1.4.3].

E há um terceiro caso que ninguém tinha fechado. O relatório 09 §16.4 A6 **estimou** ~2,3:1 para o
header verde com texto branco e marcou como não verificado; o 10 §A.1 item 7 registrou a lacuna.
Ela fecha aqui: a razão de contraste da WCAG é **simétrica** — depende só das duas luminâncias —,
então o par medido pelo 15 (`#2DC46F` como texto sobre branco = 2,27:1) é o **mesmo par** do header
(branco sobre `#2DC46F`). [CALCULADO] confirma: L(#2DC46F) = 0,4176 → branco = 1,05/0,4676 =
**2,25:1**; preto = 0,4676/0,05 = **9,35:1**. A conta bate com o 2,27:1 medido (arredondamento) e
com a calibração contra `#009CE0`, onde meu cálculo dá 3,07:1 para branco e 6,85:1 para preto,
exatamente os valores medidos pelo 15.

**Consequência dura: o header verde com texto branco está em 2,25:1 — reprova AA (4,5:1) e reprova
até o mínimo de componente (3:1).** Se o verde ficar, o texto tem de ser preto (9,35:1). Não é
questão de gosto.

### P3 — O esqueleto está certo; o que muda é o acabamento

Doze medidas nossas coincidem com a mediana ou a moda do mercado [MEDIDO — 11 rec.1]: launcher
64×64 dentro da faixa 54–65, offsets 20/20 (o valor mais repetido, 5 de 9), painel 400 px (a moda
exata), altura 640 (mediana 632), raio do painel 16 px (mediana exata), padding do balão 12/16
(mediana exata), secundário 12 px, branding 12 px cinza, mobile fullscreen (4 de 4), iframe (8 de
13), `z-index` 2147483000 (empatado com o Intercom).

**O redesenho não recomeça da geometria.** Ele ataca: cor (P1/P2), movimento (hoje só `linear` e
`ease`, sem uma curva sequer [MEDIDO — 12 §16]), acessibilidade (zero `aria-live`, `lang` vazio,
nenhum alvo de 44×44 no mobile [MEDIDO — 15 §A5.3]) e peso (2,58 MB crus servidos sem compressão
[MEDIDO — 15 §A4.6]).

### P4 — O visitante é consumidor, não operador

O corpo de 14 px é a régua de Atlassian, Polaris e Carbon — sistemas de ferramenta densa, para
usuário treinado, sentado, em sessão longa [FATO — 13 §1.1]. Material (16), Apple (17) e GOV.UK
(19) são a régua da outra ponta.

Quem digita no nosso widget é um visitante anônimo, com pressa, frequentemente no celular: **72% dos
minutos digitais no Brasil são mobile** [FATO — 06 §8.3, Statcounter jan/2026]. A densidade compacta
é a tendência dominante em produtividade e é a régua errada aqui [FATO — 13 §6.8].

### P5 — Movimento com intenção, e desligável

Somos o **único** widget do corpus cujo painel se move com easing `linear` [MEDIDO — 12 §1.3], o
único cujo launcher não responde ao toque (sem `:active`) [MEDIDO — 12 §3.2], o único com
indicador de digitando em **raster** (GIF de 19.296 B) [MEDIDO — 12 §5.6 / 15 §A6.3], e um dos que
não tratam `prefers-reduced-motion` — nesse último caso, em boa companhia: 6 de 7 do corpus também
ignoram [MEDIDO — 12 §13].

Movimento é onde o mercado inteiro é fraco e onde o ganho por linha de CSS é maior. E o GIF é o
exemplo perfeito do custo de errar o meio: **nenhuma media query alcança um GIF** — ele não herda a
cor da marca, não tem versão escura, não respeita `prefers-reduced-motion` e não escala com a fonte
[FATO — 12 §5.6].

### P6 — Cada peça nova mora em arquivo novo

O widget está praticamente virgem em relação ao upstream: **4 commits** do fork tocaram
`widget/` ou `sdk/` em toda a história, e o diff contra a v4.12.1 é de 14 arquivos / 98 inserções
[MEDIDO — 15 §B12.1]. Ao mesmo tempo, o upstream continua mexendo: **113 arquivos do widget mudaram
entre a nossa base e a v4.16.2** (+4.332 −7.635) [MEDIDO — 15 §B12.4].

Uma repaginada total transforma uma área "quase idêntica ao upstream" em "totalmente reescrita" — e
é aí que todo merge futuro passa a doer. A defesa é estrutural: componentes novos em pastas que não
existem no upstream (`widget/ui/`, `widget/message-types/`, `widget/bridge/`), cascas finas nos
arquivos que o upstream mais mexe, e tokens em arquivo próprio — nunca dentro de `woot.scss`, que é
o pior dos dois mundos (o upstream mexe **e** o fork já reescreveu 32 linhas) [MEDIDO — 15 §B12.3].

---

## 2. Sistema visual

Tudo nesta seção é **[DECISÃO]**, derivada das âncoras citadas em cada linha. Os nomes de token
usam o prefixo `--w-` (de *widget*), deliberadamente distinto do `--n-` do design system do
dashboard e do `--spx-*` sugerido pelo 09 §16.6 M4 — o objetivo é o mesmo (não sequestrar variável
existente), e o prefixo curto reduz ruído no CSS.

### 2.1 Tipografia

**Família.** Stack do sistema, sem webfont:

```
system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif,
'Apple Color Emoji', 'Segoe UI Emoji'
```

Âncora: 13 §2.6 (peso, FOUT/FOIT, CSP do site do cliente, coerência com o SO do visitante) e
11 §B4 (6 dos 12 concorrentes usam stack de sistema — empate exato com os que usam fonte própria).

Achado que fecha a questão do lado prático: o repositório publica **7 arquivos `.woff2` da Inter
(773.684 bytes somados) e declara 7 `@font-face`**, mas `theme.fontFamily.sans` não inclui Inter e
a família computada no widget é a stack do sistema — **nenhum arquivo de fonte é baixado hoje**
[MEDIDO — 15 §B9.4]. O custo de rede já é zero; o que sobra é lixo no CSS. Assumir a stack do
sistema formaliza o que já acontece.

**Escala.** Piso absoluto de **12 px** para qualquer papel [13 §2.1].

| Token | px / line-height / weight | `letter-spacing` | Uso |
|---|---|---|---|
| `--w-text-message` | **15 / 22 / 400** | `normal` | Texto da mensagem — o único lido palavra por palavra |
| `--w-text-message-sm` | 14 / 21 / 400 | `normal` | Variante de densidade (ver DV-1 e Q1) |
| `--w-text-author` | **12 / 16 / 500** | `normal` | Nome do agente acima do grupo |
| `--w-text-meta` | **12 / 16 / 400** | `normal` + `font-variant-numeric: tabular-nums` | Horário, recibo, contador |
| `--w-text-system` | **12 / 16 / 400** | `normal` | "Hoje", "Você foi transferido para…" |
| `--w-text-input` | **16 / 24 / 400** | `normal` | Campo de digitação — **sempre 16**, anti-zoom do Safari iOS |
| `--w-text-button` | 14 / 20 / 500 | `normal` | Botões e chips de resposta rápida |
| `--w-text-title` | **16 / 24 / 600** | `normal` | Nome no header |
| `--w-text-subtitle` | 13 / 18 / 400 | `normal` | Linha de status no header |
| `--w-text-branding` | 12 / 16 / 400 | `normal` | Rodapé "Desenvolvido por" |

**Três regras que acompanham a escala:**

1. **`tabular-nums` em todo horário, contador e recibo.** Não é refinamento: medido, a Inter usa
   algarismos proporcionais por padrão e a largura do mesmo horário varia **12,00 px** (de 23 px em
   "11:11" a 35 px em "00:00") — 52% [MEDIDO — 13 §2.5]. Roboto, Arial e Helvetica não têm o
   problema, mas a stack não garante qual será usada.
2. **Hierarquia por peso e cor, nunca por tamanho.** Entre mensagem (15) e metadado (12) há três
   pixels; fazer a distinção só por tamanho empurraria o metadado para 10–11 px e cruzaria o piso
   [13 §2.4].
3. **`letter-spacing: normal` em todos os papéis.** Medido: o mercado praticamente não usa — só
   Crisp (0,15–0,2 px) e Intercom (0,072 px no timestamp) declaram algo diferente [MEDIDO — 11
   §C10].

**Nenhuma altura fixa em px** em elemento que contenha texto. Em AX1 — o primeiro dos cinco tamanhos
de acessibilidade do iOS — o Body vai de 17/22 pt para **28/34 pt**, 1,65× maior [FATO — 13 §2.1].
Um balão desenhado para caber quebra ali.

### 2.2 Espaçamento

Escala de 4 px com dois degraus finos na faixa baixa. Onze degraus — o suficiente para um painel de
400 px [13 §5.8]:

`--w-space-0: 0` · `--w-space-05: 2px` · `--w-space-1: 4px` · `--w-space-2: 8px` ·
`--w-space-3: 12px` · `--w-space-4: 16px` · `--w-space-5: 20px` · `--w-space-6: 24px` ·
`--w-space-8: 32px` · `--w-space-10: 40px` · `--w-space-12: 48px`

Aplicação prescrita:

| Uso | Valor | Âncora |
|---|---|---|
| Padding interno do balão | `12px 16px` | mediana do mercado [11 §C9] — ver DV-3 |
| Entre mensagens do **mesmo** autor | `4px` | 13 §5.6 |
| Entre autores **diferentes** | `12px` | 13 §5.6 |
| Entre grupos separados no tempo | `20px` + marcador de data | 13 §5.6 |
| Padding lateral da lista de mensagens | `12px` | 13 §10.2 |
| Padding vertical da lista | `16px` topo, `8px` base | [DECISÃO] — hoje é `32px 8px 8px` [MEDIDO — 11 §A16] |
| Padding do rodapé (composer) | `12px` + `env(safe-area-inset-bottom)` | 13 §5.3 |
| Gap entre ícones do composer | **≥ 8px** | M3 + exceção "Spacing" do SC 2.5.8 [13 §4.1] |
| Gap entre chips de resposta rápida | `8px` | 11 §A6 (HubSpot) |

**O ganho medido do agrupamento.** A mesma conversa de 6 mensagens curtas ocupa **522 px** sem
agrupamento e **403 px** com — economia de **119 px, 22,8%** [MEDIDO — 13 §5.6]. Numa área útil de
488 px (pior caso mobile, 360×640), isso é mais de uma mensagem inteira a mais visível. Agrupamento
não é refinamento estético.

### 2.3 Raios

`--w-radius-0: 0` · `--w-radius-1: 4px` · `--w-radius-15: 6px` · `--w-radius-2: 8px` ·
`--w-radius-3: 12px` · `--w-radius-4: 16px` · `--w-radius-5: 20px` · `--w-radius-full: 9999px`

| Elemento | Raio | Âncora |
|---|---|---|
| Painel (desktop) | **16px** | mediana exata do mercado [11 §C8] |
| Painel (mobile fullscreen) | **0** | 4 de 4 medidos [11 §C14] |
| Launcher | `full` | 8 de 9 [11 §C3] |
| Balão, cantos livres | **20px** | grupo "conversa" [11 §C9] — ver DV-4 |
| Balão, canto de origem (última do grupo) | **6px** | 13 §5.6 |
| Chip de resposta rápida | `full` | 13 §10.3 |
| Campo de digitação | **12px** | 13 §10.3 |
| Cartão dentro da conversa | 12px | 13 §10.3 |
| Botão de enviar | `full` | 5 de 7 concorrentes usam circular [11 §C12] |
| Avatar (header e mensagem) | **6px** (quadrado arredondado) | 3 de 7 já abandonaram o círculo: Intercom 16,7%, Tidio 4px, tawk.to 15px em 40 [MEDIDO — 11 §C11] |
| Teaser | 16px | [DECISÃO] — coerente com o painel |

O raio é **proporcional ao elemento**, nunca constante: raio grande em elemento pequeno lê como
pill, raio grande em elemento grande lê como cartão [13 §6.5]. É por isso que existe escala e não
um valor.

### 2.4 Elevação e sombras

Valores literais. **No tema escuro a sombra não escurece: ela é substituída por superfície mais
clara + borda de 1px.** Isso não é estética — é consequência física: sombra preta sobre fundo
escuro não separa nada. O Polaris redefine `--p-shadow-100` como `none` no tema escuro [FATO —
13 §1.1, CSS servido].

| Token | Tema claro | Tema escuro | Uso |
|---|---|---|---|
| `--w-elev-0` | `none` | `none` | Balão, chips, lista |
| `--w-elev-1` | `0 1px 2px rgba(0,0,0,.06), 0 1px 3px rgba(0,0,0,.10)` | `none` + `1px solid rgba(255,255,255,.08)` | Cartão, teaser, botão "descer" |
| `--w-elev-2` | `0 4px 8px -2px rgba(0,0,0,.14), 0 2px 4px rgba(0,0,0,.08)` | superfície +1 degrau + borda | Launcher |
| `--w-elev-3` | `0 12px 28px -6px rgba(0,0,0,.20), 0 4px 8px rgba(0,0,0,.08)` | superfície +2 degraus + borda | Painel |

Duas decisões embutidas, ambas contra o que temos hoje:

**A sombra sai do balão.** Só 2 de 9 concorrentes têm sombra no balão — a Huggy e nós [MEDIDO —
11 §C9]. Os outros 7 resolvem por contraste de fundo. Nossa sombra atual
(`0 4px 6px rgba(50,50,93,.08), 0 1px 3px rgba(0,0,0,.05)`) é **idêntica nos dois temas** [MEDIDO —
15 §A3.5]: uma sombra calibrada para fundo claro, aplicada também no escuro. Ela virou muleta para
compensar um balão branco (`#FFFFFF`) sobre um painel quase branco (`#F9F9FB`) — 6 pontos de
diferença nos canais R e G [MEDIDO — 11 rec.4.2].

**A sombra do launcher ganha duas camadas.** 5 de 9 concorrentes usam duas (uma de contato, curta e
opaca; uma ambiente, longa e translúcida); nós usamos uma só [MEDIDO — 11 §C5].

### 2.5 Cor

#### 2.5.1 A regra antes da paleta

A paleta neutra é nossa; a cor de marca é do cliente. O que não pode variar são as **regras**:

| # | Regra | Âncora |
|---|---|---|
| **C1** | Texto sobre a marca: escolher entre `#FFFFFF` e **`#000000` puro** pela **luminância relativa**, limiar **0,17913** — nunca por YIQ, nunca "branco por padrão" | 13 §3.2.1 |
| **C2** | Se nenhuma das duas atingir 4,5:1, ajustar a **luminância do fundo** preservando o matiz — nunca aceitar o texto ilegível | 13 §3.2.2 |
| **C3** | O escuro tem de ser **preto puro**. Com `#111111` ou `#18181b`, entre **3,4% e 6,8%** das cores de marca possíveis ficam sem nenhuma escolha válida | 13 §3.2.1 [MEDIDO — 200.000 cores] |
| **C4** | **Marca como preenchimento e marca como texto são dois tokens diferentes** | 15 §B7.3 |
| **C5** | Texto do corpo ≥ **4,5:1** nos dois temas | SC 1.4.3 |
| **C6** | Borda de input, ícone sem rótulo, estado ativo: ≥ **3:1** | SC 1.4.11 |
| **C7** | Nenhuma informação transmitida só por cor | SC 1.4.1 + 13 §3.4 |
| **C8** | Distinção informativa por cor deve ser de **luminância**, não de matiz | 13 §3.4 [MEDIDO — ΔE 7,9 em deuteranopia para verde×vermelho] |
| **C9** | Tema escuro é **paleta própria**, não inversão; fundo escuro nunca é `#000` puro | 13 §3.5 |
| **C10** | **Nunca `opacity` sobre a cor da marca** para gerar estado. Opacidade muda a luminância e invalida o cálculo de contraste feito para a cor cheia | 13 §3.6 |

**O default "texto branco sobre a cor da marca" está errado para dois terços das cores possíveis:
63,9% das cores RGB não atingem 4,5:1 com texto branco** [MEDIDO — 13 §3.2.1].

#### 2.5.2 Tokens derivados do `widget_color`

Sete tokens, todos **calculados** a partir de uma entrada só. O cliente escolhe a cor; a garantia
fica no token.

| Token | O que é | Como se deriva |
|---|---|---|
| `--w-brand` | A cor da inbox, crua | `inbox.widget_color` |
| `--w-on-brand` | Texto/ícone **sobre** `--w-brand` | Regra C1 → `#FFFFFF` ou `#000000`; se o melhor < 4,5:1, aplica C2 e ajusta `--w-brand` |
| `--w-brand-hover` | Estado hover de superfície de marca | `--w-brand` deslocada ~8% em luminância (escurece se clara, clareia se escura) |
| `--w-brand-active` | Estado pressionado | ~14% |
| `--w-brand-subtle` | Fundo tênue (chip selecionado, badge) | mistura de `--w-brand` com a superfície até 10% de peso — **mistura, não `opacity`** (C10) |
| `--w-brand-border` | Borda e anel de foco | `--w-brand` ajustada até **≥ 3:1** contra `--w-surface` |
| `--w-brand-readable` | A marca **como texto** sobre a superfície | `--w-brand` ajustada até **≥ 4,5:1** contra `--w-surface` do tema corrente |

**Os dois casos concretos, com a conta à vista:**

| `widget_color` | L | Contraste c/ branco | Contraste c/ preto | `--w-on-brand` | Situação hoje |
|---|---:|---:|---:|---|---|
| `#009CE0` (a inbox de teste) | 0,2924 | **3,07:1** ❌ | **6,85:1** ✅ | **`#000000`** | o widget usa branco → 3,07:1, reprova [MEDIDO — 15 §A5.4] |
| `#2DC46F` (o verde do fork) | 0,4176 | **2,25:1** ❌ | **9,35:1** ✅ | **`#000000`** | o header usa branco → 2,25:1, reprova (P2) |

[CALCULADO], calibrado contra as medições do 15 (que deram 3,07 e 6,83 para `#009CE0`) e do
15 §A5.4 (2,27 para `#2DC46F` sobre branco).

A ferramenta certa **já existe no repositório e não é usada no widget**:
`shared/helpers/colorHelper.js` tem `adjustColorForContrast(color, backgroundColor)`, que itera
misturando a cor até bater uma razão-alvo, usando `getContrast`/`getLuminance` do `color2k`
[FATO — 15 §A5.4]. Hoje o alvo está em 3,1 — correto para componente (SC 1.4.11), insuficiente para
texto (SC 1.4.3) [13 §3.2.2]. É parametrizar o alvo, não escrever do zero.

**Onde calcular.** No **servidor**, e entregar os tokens prontos: ao widget via
`app/views/widgets/show.html.erb` (que já escreve `window.chatwootWebChannel.widgetColor` inline,
antes de qualquer bundle carregar [FATO — 15 §B7.2]) e ao SDK via o evento `config-set`, porque o
launcher vive **fora** do iframe, no `document` do host [FATO — 15 §B7.2]. Duplicar a fórmula em
Ruby e em JS é risco de divergência; o servidor calcular e o SDK receber pronto elimina isso
[15 §B7.4].

**Ganho colateral:** os tokens no primeiro byte de HTML eliminam o flash de cor errada entre o
primeiro paint e o `mounted()`.

#### 2.5.3 Neutros e superfícies — tema claro

Ancorados nos valores que o widget **já** computa hoje [MEDIDO — 15 §A6.3 e 11 §A16], para que a
migração seja rastreável em vez de inventada:

| Token | Valor | Uso |
|---|---|---|
| `--w-surface` | `#FFFFFF` | Painel, header, composer |
| `--w-surface-sunken` | `#F3F4F6` | Fundo da lista de mensagens (ver §2.5.5) |
| `--w-surface-raised` | `#FFFFFF` | Cartão, teaser, balão do agente |
| `--w-text` | `#1C2024` | Texto primário (medido hoje) |
| `--w-text-muted` | `#60646C` | Nome do agente, horário, sistema (medido hoje) |
| `--w-border` | `#E4E5E8` | Borda de input, divisor |
| `--w-border-strong` | `#C9CBCF` | Borda em `prefers-contrast: more` |
| `--w-danger` | `#D32F2F` | Erro, falha de envio |
| `--w-danger-subtle` | `#FDECEC` | Fundo de faixa de erro |
| `--w-warning` | `#B25E00` | Offline, degradado |
| `--w-success` | `#0F7A52` | Confirmação, "online" |
| `--w-focus-ring` | `--w-brand-border` | Anel de foco |

Contrastes contra `--w-surface` (`#FFFFFF`) — [CALCULADO]: `--w-text` **14,5:1** ✅ AAA;
`--w-text-muted` **5,3:1** ✅ AA (é a linha que mais se erra em widget: o 06 §8.2 registra que
timestamps e status ficam "quase sempre abaixo de 4,5:1"); `--w-danger` **5,0:1** ✅;
`--w-warning` **4,8:1** ✅; `--w-success` **4,9:1** ✅.

#### 2.5.4 Neutros e superfícies — tema escuro

Paleta própria, não inversão [C9]. Ancorada nos valores já medidos no dark do widget
[MEDIDO — 15 §A5.2 e §A6.3]:

| Token | Valor | Nota |
|---|---|---|
| `--w-surface` | `#17171A` | = `--solid-1` medido hoje. **Não é `#000`** — preto puro produz halação e smearing em OLED [13 §3.5] |
| `--w-surface-sunken` | `#121213` | = `--background-color` medido hoje |
| `--w-surface-raised` | `#2C2D36` | = fundo do balão do agente medido hoje |
| `--w-text` | `#EDEEF0` | medido hoje |
| `--w-text-muted` | `#B0B4BA` | medido hoje |
| `--w-border` | `rgba(255,255,255,.10)` | substitui a sombra (§2.4) |
| `--w-border-strong` | `rgba(255,255,255,.22)` | `prefers-contrast: more` |
| `--w-danger` | `#F87171` | recalibrado: cor de erro clara sobre fundo escuro |
| `--w-warning` | `#FBBF24` | idem |
| `--w-success` | `#4ADE80` | idem |

Contrastes contra `--w-surface` (`#17171A`) — [CALCULADO]: `--w-text` **13,7:1** ✅;
`--w-text-muted` **7,6:1** ✅ AAA.

**A marca também é recalibrada.** Hoje `--iris-9` é `45 196 111` **idêntico nos dois temas**
[MEDIDO — 15 §A5.2] — todas as outras rampas trocam, essa não. No novo sistema isso se resolve por
construção: `--w-brand-readable` e `--w-brand-border` são calculados **contra a superfície do tema
corrente**, então mudam sozinhos.

**Três ajustes de mecânica do tema**, todos medidos como problema hoje [15 §B10.4]:

1. A classe `dark` vai no **`<html>`**, não no `<div>` raiz. Hoje está no div (`App.vue:377`), o que
   deixa `<body>` e `<html>` fora do escopo — medir `getComputedStyle(document.documentElement)`
   devolve valores do tema claro mesmo com a classe presente.
2. `color-scheme: light dark` no `:root`, para scrollbars e controles nativos (`<audio controls>`,
   `<select>` do pre-chat) acompanharem. Hoje está só no container da conversa
   (`ConversationWrap.vue:138`).
3. `prefers-color-scheme` precisa ser **reativo**: o `computed` atual lê `matchMedia().matches`, que
   não é fonte reativa do Vue — o widget não acompanha a troca de tema do sistema até um remount
   [15 §A2.2; o comportamento em si é **[NÃO VERIFICADO]**, é leitura de código].

#### 2.5.5 A separação balão × fundo, e uma interpretação que precisa ficar explícita

O par que temos hoje (balão `#FFFFFF` sobre painel `#F9F9FB`) é praticamente indistinguível, e é por
isso que existe a sombra. O mercado resolve de duas formas [MEDIDO — 11 §B5]:

- **painel branco + balão cinza**: Intercom `#FFFFFF`/`#F5F5F5`, Crisp `#FFFFFF`/`#F0F2F5`,
  HubSpot `#FFFFFF`/`#F5F3F2`, tawk.to `#FFFFFF`/`#E5E5E5`;
- **painel cinza + balão branco**: LiveChat `#F6F6F7`/`#FFFFFF`.

**[DECISÃO]** Adotamos a segunda, com `--w-surface-sunken` (`#F3F4F6`) na lista e balão do agente em
`--w-surface-raised` (`#FFFFFF`). Razão: é a única compatível com a direção WhatsApp-fiel do fork
(fundo texturizado, balão claro por cima), e é o padrão que o visitante brasileiro já lê sem
aprender nada.

**A interpretação que precisa ficar registrada.** O 13 §3.3 lista "bolha do agente vs. fundo do
painel — 3:1 **se a distinção for informativa**". Aplicado ao pé da letra, isso exigiria um cinza
médio (~`#949494`) contra branco, o que **nenhum concorrente faz** — o par do Intercom dá ~1,06:1.
[INFERÊNCIA] A leitura correta é que a distinção in/out **não é transmitida pela cor do balão**: ela
é transmitida pelo **alinhamento** (agente à esquerda, visitante à direita — universal [06 §1.4]) e
reforçada pela cor. Com um segundo canal presente, o SC 1.4.1 está satisfeito e o SC 1.4.11 não se
aplica ao par de superfícies.

**Mas isso cobra um preço em `forced-colors: active`**, onde o sistema substitui as cores do autor e
todos os balões viram iguais [13 §4.7]. Por isso a §3.5 prescreve **borda de 1px** nos dois balões
sob `forced-colors` — o alinhamento sozinho não basta quando as duas superfícies colapsam.

#### 2.5.6 Daltonismo

Duas armadilhas medidas por ΔE2000 [MEDIDO — 13 §3.4]:

1. **Verde × vermelho colapsa de ΔE 72,5 para 7,9 em deuteranopia** — praticamente a mesma cor. É a
   base de todo indicador de presença ("online"/"offline"). Nossa linha de status precisa de
   **rótulo textual**, não só de bolinha colorida.
2. **Azul-informação × roxo-IA colapsa para ΔE 1,8.** Roxo virou convenção de mercado para IA e
   **não funciona como marcador** — a distinção IA/sistema tem de ser rótulo ou ícone [13 §13.4].

O par que sobrevive (ΔE ≥ 28 nos três tipos) é justamente o dos balões — cinza vs. cor de marca —,
porque a diferença principal é de **luminância**, não de matiz.

### 2.6 Preferências do sistema

Três media queries, todas Baseline widely available — não há desculpa de compatibilidade
[FATO — 13 §4.7]:

| Media query | Comportamento obrigatório |
|---|---|
| `prefers-color-scheme` | Respeitado por padrão. Ver Q6 (§10): o default hoje é `light` [MEDIDO — 15 §A5.2] |
| `prefers-reduced-motion: reduce` | Todas as transições ≤ 1 ms ou fade puro de 100 ms. Sem shimmer, sem bounce, sem typewriter cosmético. Detalhe da §4.3 |
| `prefers-contrast: more` | Bordas 1px → 2px (`--w-border-strong`); texto secundário sobe para `--w-text`; anel de foco engrossa para 3px |
| `forced-colors: active` | Remover fundos decorativos e a textura; usar cores de sistema; **balões distinguíveis por borda**; `outline: 2px solid transparent` (nunca `none`) — em `forced-colors` o `transparent` é substituído por cor real do sistema, o `none` continua nada |

### 2.7 Grid e dimensões

#### 2.7.1 Breakpoint — resolver antes de qualquer coisa responsiva

Hoje existem **três** valores conflitantes:

- `@media (max-width: 667px)` **e** `@media (min-width: 667px)` coexistem no `sdk.js` — em
  exatamente 667 px **as duas regras aplicam** e o resultado depende da ordem da cascata
  [FATO — 11 §A16, obs. 2];
- o JS usa **668 px** em `IFrameHelper.js:343`, inconsistente com o CSS [FATO — 09 §13.1 item 18];
- 667 px é a largura do iPhone 6/7/8 em landscape — um breakpoint datado [06 §14.6 R37].

**[DECISÃO] Um único ponto de corte: `768px`.** Fullscreen abaixo, flutuante a partir dele.
Escrito como `max-width: 767.98px` / `min-width: 768px`, sem sobreposição. Consequência declarada:
telas de **668–767 px** (celulares em landscape, tablets pequenos em retrato) passam de flutuante a
fullscreen — que é o comportamento desejado, mas é mudança de comportamento e precisa de teste.

#### 2.7.2 Desktop (≥ 1024 px)

| Propriedade | Valor | Âncora |
|---|---|---|
| Largura do painel | **400px** | a moda exata do mercado, 3 concorrentes + nós [11 §C7] |
| Altura | `min(640px, calc(100dvh - 104px))` | 640 é a mediana (632) [11 §C7]; `dvh` por 13 §5.4 |
| Altura mínima | `320px` | [DECISÃO] — hoje é 250, que não cabe header + 1 balão + composer |
| Offsets | `right: 20px`, `bottom: 104px` | 20 é o valor mais repetido, 5 de 9 [11 §C2] |
| Raio | 16px | mediana exata [11 §C8] |
| Sombra | `--w-elev-3` | §2.4 |
| `transform-origin` | `right bottom` (ou `left bottom` se `position: left`) | o painel cresce de onde o clique aconteceu [12 §2.1] |
| `z-index` | `2147483000` | empatado com o Intercom; teto prático sem entrar na guerra do int32 [11 §C17] |

Ocupação de tela: **19,8%** em 1440×900, 25,0% em 1280×800, 12,4% em 1920×1080 [MEDIDO — 13 §5.1.1].
Em desktop o site continua utilizável — é o que separa "painel flutuante" de "intersticial".

#### 2.7.3 Tablet (768–1023 px)

Painel flutuante, `width: min(400px, calc(100vw - 40px))`, mesma altura e mesmos offsets do desktop.
**[NÃO VERIFICADO]** — nenhum relatório desta onda mediu concorrente em viewport de tablet. É
extrapolação declarada do comportamento desktop, não observação.

#### 2.7.4 Mobile (< 768 px)

| Propriedade | Valor | Âncora |
|---|---|---|
| Dimensão | `100dvw × 100dvh`, `inset: 0` | fullscreen é unânime: 4 de 4 medidos [11 §C14]; `dvh` por 13 §5.4 |
| Fallback | `100vw`/`100vh` declarado **antes** | 13 §5.4 |
| Raio | 0 | [11 §C14] |
| Sombra | `none` | idem |
| Transição de tamanho | **nenhuma** | o Crisp desliga explicitamente (`transition: none !important`) no modo tela cheia; animar um retângulo de tela inteira é caro e lê como travamento [FATO — 12 §14] |
| Launcher | some ao abrir | já fazemos, e é correto [FATO — 11 §A16] |
| Topo | `padding-top: env(safe-area-inset-top)` no header | hoje **não existe nenhuma regra `env(safe-area-inset-*)`** no `sdk.js` [FATO — 11 §C14] |
| Base | `padding-bottom: max(12px, env(safe-area-inset-bottom))` no composer | 13 §5.3 |
| Camada por trás | opcional, `rgba(0,0,0,.4)` | só o JivoChat faz [MEDIDO — 11 §B6] |

Altura útil de conversa descontando header (56) e rodapé (96): **488 px em 360×640** (76% da tela),
692 px em 390×844, 763 px em 412×915 [MEDIDO — 13 §5.1.1]. **No pior caso cabem duas mensagens
longas e nada mais.**

#### 2.7.5 Reflow em 320 px

Obrigatório funcionar [FATO — SC 1.4.10]. Ali a medida cai para **27,9 caracteres por linha**
[MEDIDO — 13 §2.2] — é o piso tolerável, não o alvo.

#### 2.7.6 A medida (caracteres por linha) — o número que sustenta a largura

Medição direta: num painel de 380–400 px, a medida fica entre **32 e 39 caracteres por linha**. A
faixa clássica de 45–75 é **estruturalmente inatingível**; com corpo de 16 px, nem um painel de
440 px chega a 45 [MEDIDO — 13 §2.2].

Com os tokens desta spec [CALCULADO, a partir da medição de 13 §2.2]:

```
painel 400px − padding lateral 12px × 2         = 376px úteis
balão max-width 82%                             = 308px
− padding horizontal do balão 16px × 2          = 276px de texto
```

A combinação medida pelo 13 (400px / 88% / 15px) entregou 307 px de texto e **39,4 c/l**.
Proporcionalmente, 276/307 = 0,90 → **≈ 35,5 caracteres/linha**. Dentro da faixa medida.
**Verificar por medição na implementação** — a regra de bolso (≈ 0,47 em por caractere em pt-BR)
tem erro de alguns por cento entre famílias.

**Três consequências que não são de CSS:**

1. Uma mensagem de **293 caracteres ocupa 9 linhas e 214 px de altura de balão** (15/22)
   [MEDIDO — 13 §5.1]. Duas dessas enchem o painel.
2. Isso é **restrição de redação**, não de layout: vale para o prompt do bot e para o treinamento do
   atendente. Não tem solução em CSS [13 §13.1].
3. Texto longo (uma política, uma tabela de planos) pede **card ou link**, não balão de 12 linhas.

---

## 3. Especificação componente a componente

Convenção desta seção: **Anatomia** (o que compõe) · **Medidas** · **Estados** (default / hover /
focus / active / disabled / loading / erro, quando aplicável) · **Responsivo** · **A11y**.

Onde a spec prescreve algo que hoje não existe, está marcado como **NOVO**. Onde corrige algo
medido, está marcado como **CORRIGE** com a âncora.

### 3.1 Launcher (bolha)

Vive **fora do iframe**, no `document` do site do cliente, criado por
`sdk/bubbleHelpers.js` [FATO — 15 §B7.2]. Isso muda tudo em a11y e tokens: ele não alcança o
`:root` do widget.

**Anatomia.** `<button>` circular · ícone SVG centralizado · badge de não lidas (canto superior
direito) · (opcional) rótulo de texto na variante expandida.

**Medidas**

| Propriedade | Valor | Nota |
|---|---|---|
| Caixa | **64 × 64 px** | mantido — dentro de 54–65 (8 de 9) [11 §C1]; ver DV-6 |
| Raio | `full` | 8 de 9 [11 §C3] |
| Offsets | `right: 20px`, `bottom: max(20px, env(safe-area-inset-bottom))` | 5 de 9 usam 20 [11 §C2] · safe-area **NOVO** |
| Fundo | `--w-brand` | **CORRIGE** — hoje o launcher já respeita, mas por `:style` inline em `IFrameHelper.js:334` |
| Ícone | **32 × 32 px** | **CORRIGE**: hoje 24 px em botão de 64 = **37,5%**, o menor da amostra (mercado 43–65%, mediana ≈52%) [MEDIDO — 11 §C4] |
| Cor do ícone | `--w-on-brand` | **CORRIGE** — hoje é branco fixo |
| Sombra | `--w-elev-2` (duas camadas) | **CORRIGE**: hoje uma camada só [11 §C5] |
| Badge | 20 × 20 px, `full`, fundo `--w-danger`, texto 12/500 em branco, ancorado no canto superior direito, transbordando | **CORRIGE**: hoje é pseudo-elemento `::after` de **12×12 sem número** [FATO — 11 §A16]; 20×20 é o do tawk.to [MEDIDO — 11 §A4] |
| Variante *flat* | 56 × 56, raio 0 | mantida |
| Variante *expandida* | altura 48, largura automática, texto 16/500, ícone 20 | mantida — já existe no CSS e está possivelmente ociosa [11 rec.8.1]; ver Q4 |

**Estados**

| Estado | Comportamento | Âncora |
|---|---|---|
| default | conforme acima | |
| **hover** | `transform: scale(1.1)`, **150 ms**, `cubic-bezier(0.2, 0, 0, 1)` | **CORRIGE**: hoje muda **só a sombra**, saltando a opacidade de 0,16 para 0,40 — e `box-shadow` **não está** na lista de `transition`, então a mudança é instantânea, sem interpolação [MEDIDO — 11 §C6, 12 §3.1]. 3 de 6 concorrentes escalam 1,1× em 100–250 ms |
| **active (press)** | `transform: scale(0.94)`, **120 ms**, `cubic-bezier(0.45, 0, 0.2, 1)` | **NOVO** — somos hoje o único do corpus em que apertar o botão não produz nenhuma resposta visual [MEDIDO — 12 §3.2] |
| **focus-visible** | anel de 2px `--w-focus-ring` + offset 2px, sobre `outline: 2px solid transparent` | **CORRIGE**: hoje é o foco padrão do navegador (`rgb(16,16,16) auto 1px`) [MEDIDO — 15 §A5.3] |
| com não lidas | badge visível com o número (99+ acima disso) | |
| aberto | ícone troca para "fechar" com cross-fade de 150 ms | **CORRIGE**: hoje o launcher some com `translateX(8px) scale(.75) rotate(-30deg)` — somos os únicos do corpus que **giram** o botão [MEDIDO — 12 §15] |
| indisponível (bundle falhou) | degradar para link de contato | **NOVO** — 13 §5.7: se o bundle falhar, o site do cliente fica **sem canal de contato** e ninguém percebe |

**A11y**

- `type="button"` explícito — evita submit acidental se o widget cair dentro de um `<form>` do
  cliente [09 §16.4 A4].
- `aria-label` **traduzido**, vindo do i18n. **CORRIGE**: hoje o launcher tem `aria-label: null` e um
  `title = 'Open chat window'` **hardcoded em inglês** em `bubbleHelpers.js:60` — o único texto do
  widget fora do i18n, enquanto `BUBBLE.LABEL = "Fale conosco no chat"` existe traduzido e não é
  usado [MEDIDO — 15 §A5.3, 09 §13.2, 06 §14.1 R3].
- `aria-expanded` refletindo o estado do painel. **NOVO**.
- Contador de não lidas anunciado via `aria-label` ("Fale conosco no chat, 2 mensagens não lidas"),
  não só pelo badge colorido [C7].
- Alvo: 64×64, folgado sobre os 24×24 do SC 2.5.8 e os 44×44 do 2.5.5.
- **Posição idêntica em todas as páginas do site.** Não é preferência: **SC 3.2.6 Consistent Help é
  nível A** e um chat é literalmente um "mecanismo de contato humano" [FATO — 13 §4.1]. A feature
  "ocultar o widget em páginas X" conflita com isso e precisa ser decidida com o critério na mesa
  [13 §13.3].

**Contraste sobre fundo desconhecido.** O launcher fica sobre o site do cliente, cuja cor não
controlamos — um launcher azul-claro sobre um hero azul-claro some [13 §3.3]. A defesa é a sombra de
duas camadas de `--w-elev-2`, que não depende da cor de fundo.

### 3.2 Teaser (mensagem proativa) — **NOVO**

Hoje **não temos**. O mais próximo é a `has-unread-view`, que é prévia de mensagem não lida, não
convite [FATO — 11 §A17]. Nove dos concorrentes medidos têm.

**Anatomia.** Cartão ao lado/acima do launcher: avatar 32 · nome + papel · 1–2 linhas de texto ·
botão de dispensar próprio · (opcional) 2 chips de intenção ou campo de resposta embutido.

**Medidas**

| Propriedade | Valor | Âncora |
|---|---|---|
| Largura | 280 px desktop; `min(320px, calc(100vw - 32px))` mobile | 06 §2.5; a amostra vai de 260 (Huggy) a 400 (Intercom) [11 §A17] |
| Posição | alinhado à direita, base = topo do launcher + 12 px | 06 §2.5 |
| Raio | 16 px · Sombra `--w-elev-1` · Fundo `--w-surface-raised` | |
| Padding | 12px 16px · gap 12px | |
| Nome + papel | `--w-text-author` | |
| Texto | `--w-text-message`, **máximo 90 caracteres** | 06 §2.5 |
| Botão dispensar | **32 × 32 px** de alvo, ícone 16 | **CORRIGE por antecipação**: o dismiss do teaser do Olark tem **9,8 × 9,8 px**, muito abaixo do mínimo [MEDIDO — 11 §A12] |

**Comportamento**

- **Entrada:** `translateY(8px)` + opacidade, 250 ms `ease-out`. **Sem bounce. Sem som.** [06 §2.5]
- **Gatilho composto**, nunca só tempo: mínimo **8 s de permanência E 30% de scroll**, ou entrada em
  página de alta intenção [06 §14.2 R8]. A referência de tempo do mercado medido é **6–10 s**
  (tawk.to 6,4 s; Leadster 10,0 s) [MEDIDO — 12 §4].
- **Saída:** `pop-out` de ~200 ms (`scale(0.96)` + opacidade) [12 §4].
- **Dispensa é permanente na sessão** e persistida por cookie por N dias. O item A3 do catálogo de
  anti-padrões é exatamente "não persistir a dispensa" [06 §9.1].
- **Clique no corpo** abre o painel já com a mensagem no histórico.
- **Nunca dispara** enquanto houver banner de cookies visível [06 §14.6 R38].
- **Nunca vira auto-open.** Toda reclamação documentada de usuário final é contra o auto-open;
  nenhuma é contra o teaser [06 §2.4, §14.2 R7]. E há consequência de SEO: painel que abre sozinho e
  cobre o conteúdo em mobile é a descrição literal do que o Google penaliza desde 10/01/2017
  [FATO — 13 §7.2].

**Três padrões do mercado que valem ser considerados** [MEDIDO — 11 §A17]: teaser com **campo de
resposta embutido** (Huggy, LiveChat — o visitante digita sem abrir o painel, corta um clique do
funil); teaser com **2–4 chips de intenção** (Crisp, tawk.to, HubSpot); e `right: -10px` (Intercom),
que transborda a viewport de propósito para a sombra não parecer cortada.

**A11y.** `role="status"` (não `alert` — não é crítico). Foco **não** vai para o teaser. Alvo de
dispensa ≥ 32×32. Sem animação sob `prefers-reduced-motion` — aparece direto.

**Frequência.** Uma vez por sessão; no máximo um re-ping para visitante silencioso; nunca antes de o
visitante conseguir ler o título da página [06 §2.3]. **[NÃO VERIFICADO]** — a frequência de
reaparição do teaser não foi medida em **nenhum** fornecedor (a tentativa na Leadster esbarrou no
anti-bot da Vercel) [12 §4]. É parâmetro nosso, sem referência externa.

### 3.3 Header

**Anatomia.** Botão voltar (quando há navegação) · avatar · nome · linha de status · ações
(encerrar, popout, fechar).

**Medidas**

| Propriedade | Valor | Âncora |
|---|---|---|
| Altura | **56 px** (compacto) / 96 px (expandido, com saudação) | **CORRIGE**: hoje 72 px, no topo da faixa 49–72 de 8 de 11 concorrentes [MEDIDO — 11 §C11] |
| Padding | `8px 12px` | Intercom usa `8px 13px` [11 §A1] |
| Fundo | ver Q2 (§10) — `--w-surface` (neutro) ou `--w-brand` | **CORRIGE**: hoje `bg-n-brand` literal `#2DC46F`, que ignora o `widget_color` [MEDIDO — 15 §A3.3] |
| Avatar | **32 × 32**, raio 6px | 32 é o valor de Intercom e Tidio; 3 de 7 já não usam círculo [11 §C11] |
| Nome | `--w-text-title` | |
| Status | `--w-text-subtitle` em `--w-text-muted` | |
| Botões de ação | caixa **40 × 40**, ícone 20 | **CORRIGE**: mediana do mercado ≈36 [11 §C11]; 40 dá folga sobre o SC 2.5.5 (44 é o alvo em contexto de toque — ver §3.3 nota) |
| Divisor | 1px `--w-border` na base | separa do fundo texturizado |

> **Nota sobre 40 vs 44.** O SC 2.5.8 (AA, obrigatório) pede **24×24**; o 2.5.5 (AAA) e a HIG pedem
> 44×44 [FATO — 13 §1.1]. Botões de 40×40 encostados no topo da tela em mobile são desconfortáveis.
> **[DECISÃO]** 40×40 em desktop, **44×44 em mobile** (< 768 px), onde o alvo é o dedo.

**Estados**

| Estado | Comportamento |
|---|---|
| default | avatar + nome da inbox + status |
| **atendido por humano** | avatar e nome **do agente**, status "Online" |
| **atendido por IA** | avatar do bot + rótulo textual persistente "IA" ao lado do nome — **NOVO**, e não é decoração: a identidade tem de estar visível **naquele momento**, não só na primeira mensagem [13 §9.2] |
| **fora do horário** | status com a promessa de retorno calculada |
| **offline / reconectando** | ver §3.14 |
| hover/focus dos botões | fundo `--w-brand-subtle`, 100 ms; anel de foco visível |

**A11y**

- O nome do header é o **`<h1>` do documento do widget**. **CORRIGE**: hoje não há **nenhum**
  heading nas views medidas — o título do header colapsado é um `<span>`, e o único `<h2>` existente
  (em `ChatHeaderExpanded.vue:48`) só aparece na Home e só quando a inbox tem texto de boas-vindas
  [MEDIDO — 15 §A5.3].
- Os três botões precisam de `aria-label` traduzido. **CORRIGE**: hoje têm `:title` mas **não** têm
  `aria-label`, e o botão de voltar não tem nem um nem outro [MEDIDO — 15 §A5.3].
- Status nunca só por cor (C7 + o colapso verde/vermelho em deuteranopia, §2.5.6).
- `<header>` como landmark — já existe.

**Sobre a promessa do status.** As chaves já existem em pt-BR (`TEAM_AVAILABILITY.ONLINE`,
`REPLY_TIME.{IN_A_FEW_MINUTES, BACK_AT_TIME, BACK_TOMORROW, …}`) e suportam retorno calculado
[FATO — 06 §1.3]. A regra: **nunca prometa mais rápido que o seu p75 real**, e derive a string da
métrica da inbox em vez de um campo digitado [06 §5.4, §14.1 R6].

### 3.4 Lista de mensagens

**Anatomia.** Contêiner rolável · separadores de data · grupos por autor · balões · indicador de
digitando · botão "descer" flutuante.

**Medidas**

| Propriedade | Valor |
|---|---|
| Fundo | `--w-surface-sunken` + textura opcional (Q3) |
| Padding | `16px 12px 8px` |
| Separador de data | `--w-text-system`, centralizado, pill de `--w-surface-raised`, altura 24, `margin: 20px 0` |
| Espaçamento | 4px mesmo autor · 12px autores diferentes · 20px entre grupos temporais |
| Avatar por mensagem | **28 × 28**, raio 6px, só na **última** do grupo, alinhado à base |
| Nome do autor | só na **primeira** do grupo, `--w-text-author`, `margin-bottom: 4px` |
| Horário | só na **última** do grupo, `--w-text-meta`, **fora do balão** |

**Regras de agrupamento** [13 §5.6]: avatar na última, nome na primeira, horário na última, canto
reduzido só na última. Intervalo de tempo relevante quebra o grupo — o valor exato é decisão de
produto.

**Por que o horário fica fora do balão:** um balão com "Ok" precisaria de largura mínima artificial
para o horário não estrangular o texto. Com o recibo externo, o balão encolhe até o conteúdo
[13 §5.6].

**Estados**

| Estado | Comportamento | Âncora |
|---|---|---|
| vazia (conversa nova) | estado inicial que **diz o que o bot resolve** + 2–4 opções nomeadas — nunca "Como posso ajudar?" | HAX G1; NN/g: com 3 exemplos nomeados o usuário decide em 5 s se a ferramenta serve [13 §9.3, 06 §14.4 R24] |
| carregando histórico | **nada até 600 ms**; depois skeleton com forma de 2–3 balões alternados | ver DV-7 |
| paginando (scroll ao topo) | spinner discreto no topo, **preservando a posição** | já implementado e correto [FATO — 12 §10] |
| digitando | ver §3.6 |
| erro de carga | faixa com ação de tentar de novo |

**Scroll — quatro correções**

1. **Auto-scroll condicional.** Hoje `updated()` chama `scrollToBottom()` a **toda** mudança de
   tamanho da conversa, sem checar onde o usuário está: chegando mensagem enquanto você lê
   histórico, **você é arrancado para o fim** [FATO — 12 §10, 15 §A6.4]. A regra: rolar
   automaticamente **só se o usuário já estava no fim** (tolerância ~80 px); caso contrário, mostrar
   o botão "descer".
2. **Botão "descer" com contador — NOVO.** Não existe no widget, e não foi localizado no CSS servido
   de nenhum dos 7 concorrentes medidos [12 §10 — marcado como INFERÊNCIA, porque um botão
   renderizado condicionalmente pode existir só em JS]. Especificação: 36 × 36, `full`,
   `--w-surface-raised`, `--w-elev-1`, ancorado a 16 px da base e 12 px da direita da lista, com
   badge de não lidas quando aplicável.
3. **`updated()` → `watch`.** O hook atual dispara a cada re-render e força leitura de
   `scrollHeight` (reflow) em situações que não são chegada de mensagem [15 §B9.3].
4. **Throttle no `handleScroll`.** O listener é ligado direto, sem throttle/debounce
   [FATO — 15 §A6.4].

Sobre `overscroll-behavior: contain` (o scroll do chat vazar para a página): **nenhum** dos widgets
medidos usa — todos em `auto` [MEDIDO — 12 §10]. Mas a propriedade está em Baseline **limited**, sem
implementação listada no Safari [FATO — 13 §5.4]. **[DECISÃO]** declarar `overscroll-behavior:
contain` como enriquecimento progressivo e, em mobile fullscreen, bloquear o scroll do `body` por
JS — não dá para depender só do CSS.

**A11y — o buraco mais sério do widget hoje**

- `role="log"` no contêiner da lista. A spec WAI-ARIA cita "chat logs" **literalmente** como o
  exemplo canônico do role, e ele já implica `aria-live="polite"` [FATO — 13 §4.3]. Hoje temos
  **zero elementos com `aria-live`** em todas as views [MEDIDO — 15 §A5.3]: mensagem que chega
  **não é anunciada**. Num chat.
- **Nunca `aria-live="assertive"`** para mensagem normal — interromperia a leitura da mensagem
  anterior no meio [13 §4.3].
- `aria-busy="true"` durante streaming de IA, `false` ao concluir: uma resposta = um anúncio
  [13 §4.3].
- **Não anunciar** o indicador de digitando repetidamente nem os recibos [13 §4.4].
- `aria-atomic="false"` (já é o default do role).
- A lista precisa ser navegável e rolável por teclado [SC 2.1.1].

### 3.5 Balão de mensagem

Três variantes: **agente** (in), **visitante** (out) e **sistema**.

#### 3.5.1 Balão do agente

| Propriedade | Valor | Âncora |
|---|---|---|
| Fundo | `--w-surface-raised` | §2.5.5 |
| Texto | `--w-text` · `--w-text-message` | |
| Raio | **20px**, canto inferior esquerdo **6px** na última do grupo | DV-4 / DV-5 |
| Padding | **12px 16px** | mediana [11 §C9] — DV-3 |
| `max-width` | **82%** da largura útil | DV-2 |
| Sombra | **nenhuma** | **CORRIGE** — §2.4 |
| Borda | nenhuma no tema claro; `1px --w-border` no escuro e sob `forced-colors` | §2.5.5 |
| `word-break` | `break-word` | mantido |

#### 3.5.2 Balão do visitante

Idêntico, exceto: fundo `--w-brand` (ou a versão ajustada por C2), texto `--w-on-brand`, alinhado à
direita, canto inferior **direito** em 6px.

**CORRIGE a falha medida**: hoje o texto sai branco sobre `#009CE0` = **3,07:1**, porque
`getContrastingTextColor()` é YIQ com limiar 186 e **não verifica se o resultado atinge razão
alguma** [FATO — 15 §A5.4, `@chatwoot/utils/src/helpers.ts:9-15`]. Com a regra C1, a mesma cor
recebe texto preto e vai a **6,85:1**.

#### 3.5.3 Mensagem de sistema

Centralizada, **sem balão**, `--w-text-system` em `--w-text-muted`, `margin: 20px 0`. Usada para
"Hoje", "Você foi transferido para Maria", "Conversa encerrada". Nunca compete com a conversa.

#### 3.5.4 Estados de envio (balão do visitante)

Esta é a área mais pobre do mercado medido — e isso é um dado, não uma lacuna do estudo. Varrendo o
CSS servido de sete widgets por `sending|sent|delivered|read|failed|retry`: só o tawk.to tem reenvio;
**nenhum** tem entregue/lido [MEDIDO — 12 §7].

| Estado | Tratamento | Situação hoje |
|---|---|---|
| enviando | ícone de relógio 12px em `--w-text-muted`, **fora** do balão, ao lado do horário | **CORRIGE**: hoje é `opacity: 0.6` no balão inteiro, sem transição — texto translúcido é lido como "erro", não como "em trânsito" [12 §A9] |
| enviado | ✓ 12px em `--w-text-muted` | **NOVO** |
| falhou | ícone de alerta + texto "Não foi possível enviar" + botão "Tentar de novo", em `--w-danger` | já temos reenvio, e o mercado quase não tem [FATO — 12 §7] |
| entregue / lido | **não implementar agora** | ver §9 |

**Optimistic UI:** já temos e está correto (`status: 'in_progress'` antes da resposta do servidor,
substituição quando o id real chega) [FATO — 12 §7].

**A11y:** o estado "falhou" recebe `role="alert"`; os demais **não** são anunciados [13 §4.4].

### 3.6 Indicador de digitando

**CORRIGE** a única implementação em raster de todo o corpus medido: hoje é
`assets/images/typing.gif`, 19.296 bytes [FATO — 12 §5.6, 15 §A6.3]. Trocar por CSS destrava quatro
coisas de uma vez: cor da marca, tema escuro, `prefers-reduced-motion` e nitidez em qualquer DPR.

**Especificação** — o desenho de referência é o do Octadesk/WhatsApp, que o 12 §5.4 identifica como
o único que "lê como digitação" e não como carregamento:

| Propriedade | Valor |
|---|---|
| Pontos | 3 × **7 px**, `full`, `--w-text-muted` |
| Gap | **4 px** |
| Ciclo | **1200 ms**, `ease-in-out`, infinito |
| Stagger | **150 ms** entre pontos |
| Movimento | `translateY(-4px)` (0,57× o diâmetro) no pico + opacidade **0,5 → 1** |
| Keyframe | `0%, 60%, 100%` em repouso; `30%` no pico (40% do ciclo parado) |
| Contêiner | balão do agente com `padding: 12px 16px`, largura automática |

**Evitar** o salto de 2× o diâmetro do tawk.to (`translateY(-10px)` com pontos de 5 px): transforma
um estado de espera em animação chamativa [12 §C15].

**Regras de tempo** [06 §5.1]: 600 ms–1,5 s antes de mensagens curtas, escalando com o tamanho da
resposta, **teto de 3 s**; acima de **4 s** trocar por estado explícito ("Estou consultando isso…"),
porque acima de ~4 s a latência degrada a experiência mesmo com indicador.

**Sob `prefers-reduced-motion`:** pontos estáticos com opacidade fixa **mais** o rótulo textual
"digitando…". Isso também resolve o **SC 2.2.2 (nível A)**, que exige mecanismo de pausar/parar para
qualquer conteúdo em movimento que dure mais de 5 s [FATO — 13 §4.2].

**A11y:** `role="status"`, anunciado **uma vez por turno**, nunca em loop [13 §4.4].

**Simular digitação do bot é legítimo e recomendado; simular a de humano é mentira** [06 §14.5 R27].
Para referência, a Leadster insere ~1,96 s entre o painel abrir e a primeira frase, e ~1,84 s entre a
primeira e a segunda [MEDIDO — 12 §6.2]; a Octadesk faz o mesmo efeito em 1,34 s [MEDIDO — 12 §6.3].

### 3.7 Quick replies (chips)

| Propriedade | Valor | Âncora |
|---|---|---|
| Altura | **40 px** (alvo de toque) | 06 §4.4; o mercado usa 34–36 [11 §A2, §A6] |
| Raio | `full` | 13 §10.3 |
| Fundo | `--w-surface-raised` · Borda `1px --w-brand-border` · Texto `--w-brand-readable` | C4 + C6 |
| Padding | `0 16px` · Gap **8px** | SC 2.5.8 "Spacing" |
| Tipografia | `--w-text-button` | |
| Alinhamento | **à direita**, do lado do visitante | é o que faz o chip ser lido como "minha resposta possível" e não como "botão do sistema" [12 §8] |
| Layout | em linha com wrap; empilhados quando o texto é longo | 06 §4.4 |
| Entrada | **a mesma animação da mensagem** (200 ms), não uma própria | padrão convergente [12 §8] |
| Ao clicar | o chip vira balão do visitante; os outros **somem** | 06 §4.4 |
| Em mensagem antiga | opacidade reduzida e **não clicáveis** | 06 §4.4 |

**Quantidade: 2 a 4.** Mais de 4 de uma vez = **+22% de abandono em mobile** [06 §4.3 — fornecedor,
mecanismo plausível]. E o limite de canal manda: se o mesmo fluxo roda em WhatsApp, o teto é **3
botões de 20 caracteres** [FATO — 06 §4.2]. Já existe issue aberta no upstream (#8288) sobre estourar
esse limite e tratar errado.

**Regra dura: o campo de digitação nunca é desabilitado enquanto há chips.** Botões aumentam a
conclusão do fluxo guiado; texto livre aumenta a cobertura de casos fora do script. Os dois achados
não se contradizem — o desenho correto tem os dois simultaneamente [06 §1.5, §14.4 R23].

**A11y:** `<button type="button">` reais, não `<div role="button">`. Grupo com `role="group"` e
`aria-label` ("Respostas sugeridas"). Alvo ≥ 24×24 com 8 px de separação.

### 3.8 Cards e conteúdo rico

Os oito `content_type` já suportados [FATO — 15 §A6.2]: texto, `input_email`, `integrations`,
`input_select`, `form`, `cards`, `article`, `input_csat`.

| Propriedade | Valor |
|---|---|
| Contêiner | `--w-surface-raised`, raio 12px, borda `1px --w-border`, `--w-elev-0` |
| Padding | 12px · Gap interno 8px |
| Título | `--w-text-message` peso 500 · Descrição `--w-text-meta` |
| Imagem | topo, `border-radius: 12px 12px 0 0`, `aspect-ratio` fixo, `object-fit: cover` |
| Botões | máximo **3** por card, largura total, altura 40, separados por 1px `--w-border` |
| `max-width` | 82% (igual ao balão) |

**Renderização de markdown.** O pipeline atual é adequado e não muda: `markdown-it` com
`html: false` na entrada **mais** DOMPurify na saída — duas camadas [FATO — 15 §A6.1]. O que muda é
performance: hoje uma instância nova de MarkdownIt com 3 plugins é construída **por mensagem, por
render**, porque `useMessageFormatter` chama `new MessageFormatter(...)` a cada `formatMessage` e o
template chama isso em toda renderização de bolha [FATO — 15 §A6.1]. Memoizar.

**Estilos de markdown dentro do balão:** `strong` 600; `em` itálico; `ul/ol` com `padding-left:
20px` e `margin: 8px 0`; `code` inline em `--w-surface-sunken` com raio 4 e 13px; `pre` com scroll
horizontal próprio; **link em `--w-brand-readable`** — que é exatamente o token que corrige a falha
medida de **2,27:1** [MEDIDO — 15 §A5.4].

### 3.9 Composer

**Anatomia.** Caixa · textarea auto-grow · botão de anexo · botão de emoji · **botão de enviar** ·
(condicional) chip de "respondendo a".

**Medidas**

| Propriedade | Valor | Âncora |
|---|---|---|
| Altura da caixa | mínimo **48 px**, cresce até 120 px, depois rola | hoje 48, a 2ª menor da amostra (42–110) [11 §C12] |
| Raio | 12 px | |
| Fundo | `--w-surface` · Borda `1px --w-border` | |
| Padding | `8px 8px 8px 12px` | |
| Textarea | `--w-text-input` (**16 px**), `resize: none`, `rows=1` | 16 px evita o zoom automático do Safari iOS; já está correto hoje [MEDIDO — 15 §A6.3] |
| Botões anexo/emoji | caixa **40 × 40** (44 em mobile), ícone 20 | hoje 32×32 com ícone 20 — acima do mínimo, mas abaixo do confortável [11 §C10] |
| **Botão de enviar** | **40 × 40**, `full`, fundo `--w-brand`, ícone 20 em `--w-on-brand` | **NOVO — a lacuna mais objetiva do composer**: 7 de 7 concorrentes com composer medido têm botão de enviar visível; **nós somos a única exceção** [MEDIDO — 11 §C12] |
| Rodapé de branding | 12 px, `--w-text-muted`, altura 32 | 10–13 px em todos que têm [11 §C13] |

**Estados**

| Estado | Comportamento |
|---|---|
| default | placeholder "Digite sua mensagem" (já traduzido) |
| **focus** | borda `--w-brand-border` + anel de 3 px `--w-brand-subtle`, 100 ms — o padrão do Crisp, um dos únicos dois com foco visível no contêiner [11 §C12] |
| **enviar desabilitado** (campo vazio) | fundo `--w-surface-sunken`, ícone `--w-text-muted`. Padrão de mercado: fundo neutro + ícone cinza [11 §C12] |
| enviando | botão vira spinner de 16 px, campo continua editável |
| **erro de anexo** | faixa em `--w-danger-subtle` acima da caixa, com o limite de tamanho |
| bloqueado (conversa encerrada) | caixa substituída por botão "Iniciar nova conversa" |
| gravando áudio | **fora de escopo** — ver §9 |

**Teclado**

- `Enter` envia, `Shift+Enter` quebra linha, campo cresce, `resize: none` — convergência de 3 de 3
  medidos [MEDIDO — 12 §11], e já é o nosso comportamento.
- **CORRIGE dois detalhes do código atual** [FATO — 12 §11]: o listener está registrado em
  `document` (não no campo) e usa **`keypress`**, evento obsoleto e inconsistente para teclas não
  imprimíveis e para **IME** — o que importa para teclado de celular e para composição de acentos em
  pt-BR.
- **Foco automático no campo ao abrir o painel.** 3 de 3 concorrentes medidos fazem; é convergência
  de mercado, não estilo [MEDIDO — 12 §11]. **Exceção:** se a primeira tela tem conteúdo a ler
  (estado vazio com opções), o foco vai para o cabeçalho — em mobile, focar o campo abre o teclado e
  come metade da tela.

**A11y.** `aria-label` traduzido no textarea (já existe) e em cada botão. Ordem de tabulação =
ordem visual. **CORRIGE**: hoje o `outline` computado do textarea focado é
`rgba(0,0,0,0) solid 2px` — **transparente**, vindo do `outline-none` em `ChatInputWrap.vue:188`
[MEDIDO — 15 §A5.3].

### 3.10 Anexos

| Tipo | Tratamento |
|---|---|
| Imagem | thumbnail com `aspect-ratio` preservado, `max-height: 240px`, raio 12, clique abre em nova aba |
| Vídeo | player nativo, raio 12, `max-height: 240px` |
| Áudio | player nativo com `color-scheme` correto — hoje resolvido com `dark:invert`, que é remendo [FATO — 15 §A6.2] |
| Arquivo | linha com ícone 32, nome (truncado com `text-overflow`), tamanho em `--w-text-meta`, botão de download 40×40 |
| Upload em progresso | barra de progresso 2 px em `--w-brand` na base do card + "Enviando…" |
| Falha | ícone de alerta + "Tentar de novo" |
| Arrastar-e-soltar | overlay `--w-brand-subtle` com borda tracejada 2px `--w-brand-border` e rótulo "Solte para anexar" |

**A11y.** Toda imagem com `alt` derivado do nome do arquivo; nenhum `<img>` sem `alt` (hoje já está
correto [MEDIDO — 15 §A5.3]). O overlay de arrastar não pode ser a **única** forma de anexar
— **SC 2.5.7 Dragging Movements (AA)** exige alternativa por ponteiro simples [FATO — 13 §4.1]; o
botão de anexo já cumpre.

### 3.11 CSAT

Já existe (`shared/components/CustomerSatisfaction.vue`, emoji ou estrelas + campo de feedback)
[FATO — 09 §9].

| Propriedade | Valor |
|---|---|
| Contêiner | card centralizado, `--w-surface-raised`, raio 12, padding 16, `max-width` 82% |
| Título | `--w-text-message` peso 500 — "Avalie sua conversa" (já traduzido) |
| Opções | 5 alvos de **44 × 44**, gap 8, ícone 28 |
| Selecionado | escala 1,1 em 150 ms + `--w-brand-subtle` de fundo + **marca de seleção** (não só cor) |
| Campo de comentário | aparece após a escolha, `--w-text-input`, 3 linhas |
| Enviado | card colapsa para linha de sistema "Obrigado pela avaliação" |

**Regras.** Nunca pedir CSAT **antes** do fim da conversa (é o padrão problemático nº 4 do NN/g)
[13 §7.3]. Para feedback de resposta de IA, o instrumento é **polegar cima/baixo** — mutuamente
exclusivo, coletivamente exaustivo e acionável —, **não** escala de 5 estrelas; e o polegar para
baixo abre um campo opcional de texto, que é onde está a informação útil [FATO — 13 §9.5].

**A11y.** `role="radiogroup"` com `aria-label`; cada opção com rótulo textual acessível ("Muito
insatisfeito"… "Muito satisfeito"), nunca só o emoji.

### 3.12 Pre-chat

| Propriedade | Valor |
|---|---|
| Layout | card único, `--w-surface`, padding 16, gap 12 |
| Campo | altura 48, raio 12, borda `1px --w-border`, `--w-text-input` |
| Rótulo | `--w-text-author`, acima do campo |
| Erro | texto `--w-danger` **abaixo** do campo + borda `--w-danger` + ícone |
| Botão primário | altura 48, `full`? não — raio 12, fundo `--w-brand`, texto `--w-on-brand` |
| Aviso de privacidade | `--w-text-meta`, **uma linha**, na altura do primeiro campo pessoal |

**Regras herdadas do 06, que são de conteúdo e não de CSS:**

- **Teto de 8 campos** no fluxo inteiro; o que conta é o número de campos, não de etapas
  [FATO — Baymard, 06 §3.2].
- Pedir **e-mail OU WhatsApp**, nunca os dois [06 §14.3 R16].
- Máscaras e validação brasileiras (celular, CPF, CNPJ, CEP), validando **no blur** e aceitando
  entrada suja [06 §14.3 R17]. Hoje não temos nada disso.
- **Erro específico por campo.** Hoje o widget tem `REGEX_ERROR = "Forneça uma entrada válida"`, que
  diz que errou sem dizer como acertar (anti-padrão A14), e `"Nome Completo é mandatório"` —
  tradução mecânica de *mandatory* [06 §14.1 R1/R2].
- Aviso de privacidade **não modal**, e checkbox de marketing **desmarcado** e separado do
  atendimento [06 §14.9].
- Link da política abre em **nova aba** — perder a conversa por clicar na política é anti-padrão
  silencioso [06 §14.9 R50].

**A11y.** `<label>` real associado a cada campo (não placeholder como rótulo); `aria-invalid` e
`aria-describedby` apontando para a mensagem de erro; foco no primeiro campo inválido ao submeter.

### 3.13 Estados vazios

| Estado | Conteúdo |
|---|---|
| **Home sem conversa** | avatar(es) da equipe · saudação · linha de disponibilidade · **2–4 opções nomeadas** · botão "Iniciar conversa" |
| **Conversa nova** | primeira mensagem do bot dizendo **o que ele resolve** + opções. Nunca "Como posso ajudar?" |
| **Sem artigos** | esconder o bloco inteiro, não mostrar título com lista vazia |
| **Histórico vazio após filtro** | não aplicável hoje (não há busca) |

Medidas: ilustração ou avatar 64, título `--w-text-title`, texto `--w-text-message` em
`--w-text-muted`, `max-width` 280 px, centralizado, gap 12.

**Sobre avatar.** Regra que sai da literatura: **ou foto real de pessoa real, ou ilustração
assumidamente ilustração** — o meio-termo (avatar 3D quase-humano, foto de banco de imagem com nome
inventado) é onde mora o vale da estranheza e a desconfiança medida [06 §5.2]. E a imagem tem de
corresponder a quem está falando: bot → avatar de bot; humano → foto do humano; no handoff, a imagem
muda [13 §6.7].

### 3.14 Erro, offline e reconexão

Três estados **distintos**, hoje inexistentes como desenho.

| Estado | Faixa | Comportamento |
|---|---|---|
| **Reconectando** | fundo `--w-surface-sunken`, texto `--w-text-muted`, ícone de spinner 14, altura 32, **não bloqueante**, no topo da lista | "Reconectando…" · o composer **continua utilizável** · mensagens digitadas entram na fila |
| **Offline** (rede caiu) | fundo `--w-warning` a 12% + texto `--w-warning`, altura 32 | "Sem conexão. Suas mensagens serão enviadas quando voltar." |
| **Erro de envio** | dentro do balão (§3.5.4) | ícone + texto + "Tentar de novo", `role="alert"` |
| **Erro de carregamento do widget** | fora do iframe | launcher degrada para canal de contato alternativo (§3.1) |
| **Fora do horário** | linha de sistema no topo da conversa + status no header | promessa **específica** ("respondemos em até 12 horas"), não "em breve" [06 §6.4] |
| **Conversa encerrada** | linha de sistema + composer substituído | sem ambiguidade sobre poder ou não responder |

**Regras de comportamento** (detalhamento na §5):

- A faixa **nunca** bloqueia a interface. O visitante pode continuar digitando.
- Nenhuma faixa aparece antes de **3 s** de degradação — piscar "reconectando" a cada micro-queda é
  pior que não avisar. Foi exatamente o que motivou o F0 "sempre conectado" no dashboard.
- Ao reconectar: a faixa some com fade de 200 ms e o gap de mensagens é preenchido (§5.4).
- `role="alert"` em "offline" e em falha de envio; `role="status"` em "reconectando" [13 §4.3].

---

## 4. Movimento

### 4.1 Curvas da casa

Duas curvas, e a proibição do `linear` para movimento. Hoje o widget mistura `linear` e `ease` sem
critério, e é o **único** do corpus cujo painel se move em `linear` — um retângulo de 400×640
atravessando 40 px em velocidade constante é o que o olho lê como "animação de software", não como
objeto [MEDIDO — 12 §2.2].

| Token | Valor | Uso |
|---|---|---|
| `--w-ease-standard` | `cubic-bezier(0.2, 0, 0, 1)` | Hover, press, cor, foco — M3 `easing-standard` [FATO — 13 §1.1] |
| `--w-ease-enter` | `cubic-bezier(0.05, 0.7, 0.1, 1)` | Entrada de superfície — M3 `emphasized-decelerate` |
| `--w-ease-exit` | `cubic-bezier(0.3, 0, 0.8, 0.15)` | Saída de superfície — M3 `emphasized-accelerate` |

`linear` fica permitido **apenas** para opacidade pura e rotação contínua (spinner) [12 §A1].

**O que não adotamos:** overshoot. Só o Intercom usa (`cubic-bezier(0, 1.2, 1, 1)`, com ordenada
1,2 acima de 1); todas as outras curvas customizadas do corpus desaceleram sem passar do ponto
[MEDIDO — 12 §1.3]. Overshoot num painel de 400×640 chama atenção para o container em vez do
conteúdo.

### 4.2 Tabela de durações por interação

| Interação | Duração | Curva | Adotamos de / diferente de |
|---|---|---|---|
| **Painel — abrir (transform)** | **300 ms** | `--w-ease-enter`, `transform-origin: right bottom` | Adotado do Intercom (300 ms + origem no launcher) [12 §2.1] |
| **Painel — abrir (opacity)** | **80 ms** `ease-out` | — | **Desacoplado do transform**, como o Intercom (83 ms contra 300 ms). Hoje fazemos 200 ms contra 250 ms — praticamente juntos, o que deixa meio painel fantasma durante toda a animação [12 §A2] |
| **Painel — fechar** | **200 ms** transform + 120 ms opacity | `--w-ease-exit` | Saída no mesmo intervalo da entrada ou levemente menor; **nunca 3× maior** (o `all .8s` do tawk.to) [12 §C14] |
| **Painel — mobile fullscreen** | **sem transição de tamanho** | — | Adotado do Crisp, único que desliga motion em tela cheia de propósito [12 §14] |
| **Launcher — hover** | **150 ms** | `--w-ease-standard` | `scale(1.1)`; 3 de 6 concorrentes fazem em 100–250 ms [11 §C6] |
| **Launcher — press** | **120 ms** | `cubic-bezier(0.45, 0, 0.2, 1)` | `scale(0.94)`; o Intercom usa 0,85 em 134 ms — adotamos mais discreto [12 §3.2] |
| **Launcher — troca de ícone** | **150 ms** cross-fade | `--w-ease-standard` | **Diferente de nós hoje**, que giramos o botão (`rotate(-30deg)`) — ninguém mais gira [12 §15] |
| **Mensagem — entrada** | **200 ms** | `--w-ease-standard` | `translateY(8px)` + opacidade, com **40% do keyframe parado no estado inicial** — o truque do Intercom, que dá atraso natural sem coordenar `animation-delay` entre bolhas [12 §6.1]. Ver DV-8 |
| **Mensagem — remoção** | 150 ms | `--w-ease-exit` | |
| **Typing dots** | **1200 ms** infinito | `ease-in-out` | Stagger 150 ms (§3.6) |
| **Teaser — entrada** | 250 ms | `ease-out` | `translateY(8px)` + opacidade, sem bounce [06 §2.5] |
| **Teaser — saída** | 200 ms | `--w-ease-exit` | `scale(0.96)` + opacidade [12 §4] |
| **Chip — hover / seleção** | 100 ms | `--w-ease-standard` | M3 `short2` |
| **Composer — foco** | 100 ms | `--w-ease-standard` | Intercom anima `outline-width` em 100 ms [11 §A1] |
| **Faixa de status (offline/reconectando)** | 200 ms | `--w-ease-standard` | slide + fade |
| **Botão "descer"** | 150 ms | `--w-ease-standard` | escala + opacidade |
| **Skeleton** | 1200 ms | `linear` | shimmer, só depois de 600 ms de espera |
| **Spinner** | 600 ms | `linear` | rotação contínua — o Intercom usa exatamente isso [12 §9] |

**Faixa de trabalho:** 80–300 ms para tudo que é interação. É onde o mercado inteiro está, com duas
exceções (Leadster 500 ms, LiveChat 430 ms) [MEDIDO — 12 §1.3].

### 4.3 `prefers-reduced-motion`

**Regra dura, sem exceção estética:**

```
@media (prefers-reduced-motion: reduce) {
  toda transição de transform → nenhuma (o elemento aparece na posição final)
  toda transição de opacidade  → mantida, no máximo 100 ms
  typing dots                  → estáticos + rótulo textual "digitando…"
  skeleton shimmer             → estático
  animação de entrada da bolha → nenhuma
  hover/press do launcher      → só mudança de sombra/cor
}
```

O padrão real do mercado é ignorar: só o Intercom trata, e trata **pela metade** — o launcher
respeita, o painel não [MEDIDO — 12 §13]. Num mercado onde 6 de 7 ignoram, fazer certo é barato e
diferencia.

**O que a preferência não alcança:** o GIF. É por isso que o §3.6 é pré-requisito desta seção, não
um item independente.

### 4.4 Sem stagger na abertura do painel

Nos oito painéis que o 12 conseguiu abrir, **nenhum escalona a entrada dos elementos internos** — o
painel entra como bloco só [MEDIDO — 12 §2.4]. O stagger, quando existe, está na entrada de
*mensagens*. Não inventar aqui.

---

## 5. Comportamento

As decisões de lógica do relatório 14 que têm consequência visível na interface. Esta seção não
especifica transporte nem protocolo — especifica **o que o visitante vê** em cada situação.

### 5.1 Máquina de estados do widget

```
                        ┌───────────────┐
    (a) carga da página │   AUSENTE     │
              │         └───────┬───────┘
              ▼                 │ SDK executa; degrada em silêncio se faltar suporte
       ┌──────────────┐         │
       │  DEGRADADO   │◄────────┤ storage bloqueado / bundle falhou
       │ link contato │         │   → nunca vazar exceção para o window.onerror do site
       └──────────────┘         ▼
                        ┌───────────────┐
                        │ FECHADO       │  launcher visível
                        │ (idle)        │  badge se houver não lidas
                        └───┬───────┬───┘
              teaser (§3.2) │       │ (b) clique / $chatwoot.toggle()
                            ▼       ▼
                    ┌───────────┐  ┌──────────────────────────┐
                    │ TEASER    │─►│ ABERTO                    │
                    │ visível   │  │  Home | Pre-chat | Conversa│
                    └───────────┘  └────┬─────────────────────┘
                       dispensa →       │ (c) primeira mensagem
                       FECHADO          ▼
                                 ┌──────────────────┐
                                 │ CONVERSA ATIVA   │
                                 │  bot | humano    │
                                 └────┬─────────────┘
                                      │ (d) handoff → §5.5
                                      │ encerrada  → composer vira "Nova conversa"
                                      ▼
                                 ┌──────────────────┐
                                 │ ENCERRADA        │ + CSAT
                                 └──────────────────┘

  Eixo ortogonal — CONEXÃO (vale em qualquer estado acima):
     CONECTADO ──perda──► RECONECTANDO ──3s──► faixa visível ──volta──► gap-fill + faixa some
                          RECONECTANDO ──rede offline──► OFFLINE (fila local)
```

**Os quatro momentos** (a=carga, b=abrir, c=primeira mensagem, d=handoff) são a convenção do
relatório 14 e valem aqui: nada nesta spec afirma que algo acontece em (a) sem que a âncora diga
(a).

### 5.2 O que acontece em cada erro

| Situação | O que o visitante vê | Âncora |
|---|---|---|
| **Storage bloqueado** (Safari ITP, aba anônima agressiva, extensão) | Nada quebra. O widget carrega ou não carrega, **em silêncio**. Nunca uma exceção no console do site do cliente | O Crisp escreve e relê uma chave de teste antes de decidir; o JivoChat só testa existência e **estoura `pageerror` no site do cliente** [MEDIDO — 14 §7.1] |
| **Bundle não carrega** | Launcher degrada para canal de contato (mailto/WhatsApp) servido no snippet | 13 §5.7 |
| **Falha ao enviar mensagem** | Balão permanece, com ícone + "Tentar de novo" | já temos, e o mercado quase não tem [12 §7] |
| **Mensagem duplicada por retry de rede** | **Não deve acontecer.** Todo POST de mensagem carrega chave de idempotência | O Intercom manda `Idempotency-Key` em todo request; nós não temos nada equivalente [MEDIDO — 14 §4.3] |
| **Anexo excede o limite** | Faixa no composer com o limite em MB (string já existe com interpolação) | 09 §9 |
| **Domínio não autorizado** | O widget **não cria sessão**, mas também não "quebra feio" | Modelo do Intercom: libera a config visual, bloqueia a criação de sessão [MEDIDO — 14 §10.1] |
| **Erro interno do widget** | Nada visível; o erro **é reportado** | Hoje há ~20 `catch { // Ignore error }` e **zero telemetria** — o widget é o único componente da frota sem observabilidade [FATO — 09 §9, 14 §7.3] |

### 5.3 Offline

| Momento | Comportamento |
|---|---|
| Detecção | O socket fecha rápido — no Crisp, **223 ms** após a rede cair [MEDIDO — 14 §7.2] |
| 0–3 s | **Nada na tela.** Não avisar micro-queda |
| > 3 s | Faixa "Sem conexão" (§3.14), não bloqueante |
| Digitação durante o offline | Permitida. A mensagem entra em **fila local** com estado "enviando" |
| **O que entra na fila** | **Somente intenções** — mensagem enviada, anexo. **Nunca estados transitórios** como "digitando" |
| Volta da rede | Fila drenada em ordem; faixa some com fade de 200 ms; gap-fill (§5.4) |

A regra sobre o que entra na fila vem de um erro medido no Crisp: os três eventos
`message:compose:send` (começou a digitar / parou / começou) foram bufferizados e despachados **todos
de uma vez, em 1 ms, 20 segundos depois do fato** — o operador do outro lado recebe uma sequência
temporal sem sentido [MEDIDO — 14 §7.2, e o próprio 14 §15.6 lista isso como "não copiar"].

**Não temos fila offline hoje** [FATO — 14 §13]. É item novo.

### 5.4 Reconexão

O que já é nosso e é vantagem real, **não mexer** [14 §15.1]:

- Backoff exponencial de 1 s → 30 s com jitter de 500 ms e tentativas ilimitadas — **melhor para o
  visitante** que o do Crisp (15 s → 60 s, desiste em 5 tentativas) e muito melhor que o da Leadster
  (5 tentativas de 1 s fixo, sem backoff).
- Reabertura em `visibilitychange` + `focus` + `pageshow(persisted)`: **somos os únicos que cobrem
  os três caminhos** [MEDIDO — 14 §9.3].
- **Gap-fill:** `onReconnect → syncLatestMessages()`. Não há equivalente explícito em nenhum
  concorrente medido [14 §15.1 D5].

O que muda, e tem consequência visível:

1. **O watchdog precisa fazer alguma coisa.** `STALE_CHECK_INTERVAL=15000` /
   `STALE_EVENT_THRESHOLD=25000` existem em `BaseActionCableConnector.js`, mas a ação depende de
   `window.reconnectService`, que **existe no dashboard e não existe no widget** — o timer roda a
   cada 15 s dentro do widget e **não faz nada** [MEDIDO — 14 §15.1 D3]. Efeito visível: um socket
   silenciosamente morto no widget do visitante hoje só se resolve se o `disconnected` do
   ActionCable disparar; se não disparar, não se resolve. **É a recomendação mais concreta do
   relatório 14 e o pré-requisito para a faixa "reconectando" significar alguma coisa.**
2. **O servidor deve poder ditar o tempo de espera.** Numa incidência, hoje a frota inteira martela
   em 1 s. A tabela por motivo de fechamento do JivoChat (de 0 s a 24 h conforme o `close reason`) é
   a peça que falta [MEDIDO — 14 §4.4]. Consequência de interface: durante uma janela dessas, a
   faixa muda de "Reconectando…" para "Voltamos em instantes" — texto diferente, sem spinner.

### 5.5 Handoff bot → humano

**Três marcações simultâneas**, e isso não é redundância — é o requisito [13 §9.6]:

1. **Mensagem de sistema no fluxo**: "Você foi transferido para Maria, do time de vendas."
2. **Header muda de forma persistente**: avatar, nome e status de quem atende **agora**. O rótulo
   "IA" some.
3. **Identidade da bolha muda**: as mensagens do humano não carregam a marcação de IA.

E o inverso vale igual: quando o humano sai e a IA volta, as mesmas três marcações. **O visitante
nunca deve precisar perguntar "você é robô?"** [13 §9.6].

**Durante a espera** [06 §6.3]:

| Momento | O que aparece |
|---|---|
| Imediato | Linha de sistema "Transferindo para um atendente" |
| A cada 60–90 s | Posição na fila e/ou tempo estimado — posição é mais real e menos volátil que ETA |
| Aos **120 s** | Card com `[Receber por e-mail]` `[Receber no WhatsApp]` `[Continuar esperando]` |

**A primeira frase do humano deve referenciar algo que o bot já coletou.** É o sinal mais barato e
mais eficaz de que o contexto passou [06 §6.3].

**Um dado que muda o desenho da saída:** esconder o botão "falar com humano" **reduz** a tolerância
ao bot; deixar a saída visível **aumenta** o tempo que a pessoa dá ao bot [FATO — 06 §6.1]. A saída
visível é pró-deflexão, não contra ela.

**Nota de honestidade:** fila de espera, mensagem de fora de horário e tempo de espera exibido
**não foram medidos em nenhum concorrente** — mediria exigir conta de teste em cada produto
[NÃO VERIFICADO — 14 §14]. As prescrições acima vêm da literatura de handoff do 06, não de medição.

### 5.6 Identidade de IA

- Rótulo persistente no header **e** atrelado à bolha, não só na primeira mensagem [13 §9.2].
- **Não usar roxo como marcador** — contra o azul de informação, o par colapsa para ΔE 1,8 em
  deuteranopia [MEDIDO — 13 §3.4]. Roxo pode ser o sotaque; o marcador é rótulo ou ícone.
- Streaming: `aria-busy="true"` durante, `false` ao concluir (§3.4).
- Autoscroll durante o streaming segue a regra da §3.4 — se o visitante rolou para cima, o texto
  crescendo embaixo **não** pode arrastá-lo de volta [13 §9.1].
- Disclaimer de IA: uma linha discreta, `--w-text-meta`, como o HubSpot faz (faixa de 24 px, "AI
  generated content may be inaccurate") [MEDIDO — 11 §A6].

### 5.7 Som, notificação e título da aba

- **Nenhum widget do corpus pede permissão de notificação nativa nem vibra** — zero chamadas a
  `new Notification` e `navigator.vibrate` em todos os alvos [MEDIDO — 12 §12.3]. Não inventar.
- **Som:** Intercom e HubSpot tocam; a Leadster **não** (o 12 §12.1 registra explicitamente a
  correção: os três `new Audio()` capturados na página da Leadster vinham do HubSpot Analytics, não
  do widget). Nós temos `ding.mp3` hoje. É decisão de produto — Q7 (§10). O argumento contra:
  Nielsen mede que **92%** acham autoplay irritante e **mais de um terço abandona o site**
  [FATO — 06 §9.1 A6].
- **Piscar o título da aba:** o mecanismo da Leadster é bem construído (650 ms de intervalo, 60 s de
  duração, para no `visibilitychange`, não reentra) e está confirmado no código deles
  [FATO — 12 §12.2]. É a alternativa de 0% de atrito à notificação nativa. Também é Q7.

---

## 6. Mapa de implementação

### 6.1 Regra estrutural

Quatro regras, derivadas do mapa de risco de merge do 15 §B12:

1. **Todo componente novo em pasta nova.** `widget/ui/`, `widget/message-types/`, `widget/bridge/`
   não existem no upstream → conflito zero, para sempre.
2. **No campo minado, substituir por delegação, não reescrever.** `ChatInputWrap.vue` (17 commits em
   36 meses, +12 −9 desde a nossa base) vira casca fina que renderiza `widget/ui/WComposer.vue`.
   Quando o upstream mudar a lógica de anexo, o merge acontece num arquivo de 30 linhas.
3. **Tokens em arquivo próprio.** `widget/assets/scss/_tokens.scss` (novo); `woot.scss` fica só com
   o `@import`. `woot.scss` é o pior arquivo possível para tokens: o upstream mexeu +30 −4 desde a
   nossa base **e** o fork já reescreveu 32 linhas.
4. **Nunca tocar em `store/modules/conversation/` para fins visuais.** É o módulo que o upstream mais
   mexeu (+51 −8 em `actions.js`, +29 em `mutations.js`). Se o redesenho precisar de
   `isFirstOfGroup`/`isLastOfGroup`, calcular em getter **novo**, arquivo separado.

### 6.2 Pré-requisito absoluto: rodar o merge da v4.16.2 antes

Hoje esse merge mexe em **113 arquivos do widget (+4.332 −7.635)** [MEDIDO — 15 §B12.4]. Fazer isso
*depois* do redesenho é resolver dois problemas embaralhados. É a única linha desta seção que é
bloqueante para todas as outras.

### 6.3 Frentes, arquivos e risco

**Legenda de risco:** 🟢 upstream não mexeu desde a v4.12.1 · 🟡 upstream mexe às vezes ·
🔴 campo minado (upstream mexe muito e é lógica) · ⚪ arquivo novo, risco zero por construção.

#### Frente A — Build e peso (não toca em nenhum componente Vue)

| # | Ação | Arquivo | Ganho medido | Risco | Esforço |
|---|---|---|---|---|---|
| A1 | Ligar gzip/brotli no nginx | fora do repo | **2,58 MB → ~575 KB** na primeira visita | — | P |
| A2 | `content` próprio do Tailwind para o widget | `tailwind.config.js` + pipeline | **−1.047.130 B crus (−94,9%)** / −96.626 B gzip | 🟡 | M |
| A3 | Tirar o Leaflet do grafo eager | `vite.config.ts:86-88` | **−150.679 B** cru / −43.491 gzip, e `window.L` some de dentro do iframe | 🟡 | P |
| A4 | Corrigir o gate de `size-limit` (medir o grafo, não o glob) | `package.json` + script novo | Hoje reporta 76,53 kB para um widget de 575 KiB — **falso verde por 7,5×** | ⚪ | P |
| A5 | Trocar `logo_thumbnail.svg` (90.492 B para renderizar a 24 px) | `public/brand-assets/` | −~88 KB | ⚪ | P |
| A6 | Remover os 7 `@font-face` da Inter que ninguém usa | `shared/assets/fonts/widget_fonts` | limpeza de CSS; rede já era zero | 🟡 | P |

**Os itens A1, A2 e A3 sozinhos são o grosso do problema, e nenhum toca num componente.** Isso
importa para o planejamento: dá para colher a maior parte do ganho de performance **antes** do
redesenho começar, sem conflitar com ele.

**[NÃO VERIFICADO]** se a frota de produção (.229, Tozi, fábrica) tem a mesma configuração de nginx.
Só homologação foi medida [15 §A4.6]. Verificar antes de qualquer conclusão sobre produção.

#### Frente B — Tokens (pré-requisito de todo o resto do visual)

| # | Ação | Arquivo | Risco |
|---|---|---|---|
| B1 | Criar a folha de tokens (§2) | `widget/assets/scss/_tokens.scss` | ⚪ |
| B2 | Calcular os tokens de marca no servidor e emitir `<style>` inline | `app/views/widgets/show.html.erb` | 🟡 |
| B3 | Entregar os mesmos tokens ao SDK via `config-set` (launcher vive fora do iframe) | `sdk/IFrameHelper.js` | 🔴 |
| B4 | Parametrizar o alvo de contraste de `adjustColorForContrast` (3,1 → 4,5 para texto) | `shared/helpers/colorHelper.js` | 🟡 |
| B5 | Mapear os tokens no Tailwind (`bg-w-brand`, `text-w-on-brand`, …) | `theme/colors.js` | 🟡 |
| B6 | Despintar a rampa `--iris-*` (hoje verde) e devolver o primitivo | `widget/assets/scss/woot.scss:193,255,272` | 🔴 |

**O que isso apaga** [15 §B7.5]: `--widget-color` escrita e nunca lida; os `:style` inline
espalhados em 7 componentes; `bg-n-brand`/`text-n-brand`/`border-n-brand` nos 23 pontos do widget e
do shared; o literal `hover:bg-[#1FB85A]`; a dependência do YIQ de `@chatwoot/utils`.

#### Frente C — Primitivos novos

| Arquivo (todos ⚪) | Conteúdo |
|---|---|
| `widget/ui/WButton.vue` | variantes brand/ghost/danger, com **foco visível** (hoje inexistente) |
| `widget/ui/WIconButton.vue` | `aria-label` **obrigatório via prop** — faz o linter pegar as omissões de `HeaderActions.vue` |
| `widget/ui/WBubble.vue` | fundo/raio/borda por token, sem saber o que renderiza dentro |
| `widget/ui/WAvatar.vue` | corta o import de `dashboard/components-next/avatar/Avatar.vue` |
| `widget/ui/WSurface.vue`, `WSpinner.vue`, `WField.vue`, `WSkeleton.vue`, `WTypingDots.vue`, `WBanner.vue` | |

**Regra verificável por lint, não por convenção:** nenhum componente de `widget/ui/` importa de
`dashboard/` nem contém cor literal [15 §B8.3].

#### Frente D — Componentes na zona segura 🟢

Todos com **zero mudanças do upstream** desde a v4.12.1 [MEDIDO — 15 §B12.3]. É onde o redesenho
começa:

`ChatHeader.vue` · `ChatHeaderExpanded.vue` · `ChatSendButton.vue` · `HeaderActions.vue` ·
`ConversationWrap.vue` · `AgentMessageBubble.vue` · `AgentTypingBubble.vue` ·
`layouts/ViewWithHeader.vue` · `views/Messages.vue` · `views/Home.vue` ·
`assets/scss/views/_conversation.scss`

**Coincidência muito favorável:** os três arquivos do bug de cor — `ChatHeader`,
`ChatHeaderExpanded`, `ChatSendButton` — estão **todos** na zona segura. Corrigir o `widget_color` é
barato em risco de merge.

#### Frente E — Campo minado 🔴 (delegação, nunca reescrita)

| Arquivo | Commits (36 m) | Desde v4.12.1 | Tática |
|---|---:|---|---|
| `components/ChatInputWrap.vue` | 17 | +12 −9 | casca fina → `widget/ui/WComposer.vue` |
| `components/ChatFooter.vue` | 15 | +37 −12 | casca fina |
| `components/PreChat/Form.vue` | 16 | +39 −33 | **não redesenhar por dentro nesta onda** — só tokens |
| `store/modules/conversation/*` | 5 | +51 −8 / +29 | **não tocar**; getters novos em arquivo separado |
| `assets/scss/woot.scss` | 9 | +30 −4 (e o fork já reescreveu 32 linhas) | reduzir a um `@import` |
| `api/endPoints.js`, `api/conversation.js` | — | +29 −11, +17 −4 | não tocar |
| `sdk/IFrameHelper.js` | 10 | — | mexer só no mínimo (tokens + eventos) |

#### Frente F — Refatorações que reduzem conflito (fazer antes de estender)

| # | Ação | Por quê |
|---|---|---|
| F1 | `App.vue:258-345`: cadeia de **16 ramos** → mapa `{evento: handler}` em `widget/bridge/` | Um mapa isola conflito por linha; a cadeia garante conflito. **O padrão bom já existe no repositório**, do lado do SDK (`IFrameHelper.js:104-117` usa dicionário) [15 §A2.4] |
| F2 | `AgentMessageBubble.vue`: 8 computeds + 6 `v-if` → `<component :is>` com registry | O `v-if` composto atual tem `!isCards` **duplicado** e `!isIntegrations`/`!isTemplateEmail` **ausentes** [FATO — 15 §A6.2] |
| F3 | `_conversation.scss` (209 linhas): mover o layout da conversa para junto dos componentes | Hoje o agrupamento e os raios moram num SCSS global que ninguém encontra a partir do componente |
| F4 | `AgentMessage.vue` (266 l.) + `UserMessage.vue` (182 l.) → `MessageRow.vue` com `direction` | Repetem `hasImageError`/`hasVideoError`, anexos, `ReplyToChip` e `MessageReplyButton` |
| F5 | Cortar os imports de `dashboard/` que arrastam peso: `useTransformKeys` (→ `@sentry/core`, 156 KB de fonte) e `editorHelper` (→ `@sentry/vue`) | 15 §B8.4 |

#### Frente G — Acessibilidade

| # | Ação | Estado hoje |
|---|---|---|
| G1 | `role="log"` na lista | **0** elementos com `aria-live` |
| G2 | `lang` no `<html>` do widget | `document.documentElement.lang` = `""` |
| G3 | Heading real no header | **0** headings nas views medidas |
| G4 | `aria-label` traduzido no launcher, fechar, voltar, enviar | 2 `aria-label` no widget inteiro; launcher com `aria-label: null` |
| G5 | Foco visível em tudo | textarea com `outline: rgba(0,0,0,0) solid 2px` |
| G6 | Alvos ≥ 44×44 em mobile | medidos: 40×24, 24×24, 32×32, 32×32, 180×24 — **nenhum passa** |
| G7 | `Esc` fecha o painel e devolve o foco ao launcher | hoje `Esc` só fecha o seletor de emoji; **6 de 7 concorrentes também não fecham** — fazer certo custa pouco e diferencia |
| G8 | `<main>` e landmarks | só `<header>` e `<footer>` |

Todos [MEDIDO — 15 §A5.3], exceto G7 [MEDIDO — 12 §11].

### 6.4 O que dá para fazer isolado e o que exige refatoração antes

| Pode ser feito isolado, agora | Exige refatoração antes |
|---|---|
| Frente A inteira (build) | Qualquer componente novo → depende da Frente B (tokens) |
| Tokens (B1–B6) | Novo `content_type` → depende de F2 |
| Primitivos em `widget/ui/` (C) | Novo método de API / evento → depende de F1 |
| Componentes da zona segura (D) | Composer redesenhado → depende de F1 (casca) |
| Typing dots em CSS (§3.6) | Virtualização (se um dia) → depende de mover o agrupamento de CSS para dados |
| Motion (§4) | Fila offline (§5.3) → depende do watchdog (§5.4 item 1) |
| a11y G1–G5, G8 | G6 (alvos) → depende dos primitivos |

---

## 7. Faseamento

Três fases. Esforço **relativo** (P/M/G), nunca em horas. Cada fase tem critério de pronto
**verificável** — não "está bonito", mas um comando ou uma medição que passa ou falha.

### Fase 1 — Terreno limpo e uma cor só

**Objetivo:** o widget deixa de mentir sobre a cor do cliente, deixa de trafegar 2,58 MB e passa a
ter um sistema de tokens. Nenhuma tela é redesenhada ainda.

| Item | Frente | Esforço |
|---|---|---|
| Merge da v4.16.2 sozinho, antes de tudo | §6.2 | **G** |
| gzip/brotli no nginx (verificar a frota inteira) | A1 | P |
| `content` próprio do Tailwind para o widget | A2 | M |
| Tirar o Leaflet do grafo eager | A3 | P |
| `size-limit` medindo o grafo + asserção "leaflet não pode voltar" | A4 | P |
| Folha de tokens + cálculo no servidor + entrega ao SDK | B1–B6 | **G** |
| Substituir `bg-n-brand`/literais nos 3 arquivos da zona segura | D | P |
| `lang`, `role="log"`, `aria-label` traduzidos, foco visível | G1–G5 | M |
| Typing dots em CSS (mata o GIF) | §3.6 | P |
| Curvas da casa + abertura/fechamento do painel | §4.2 | P |

**Critério de pronto — tudo verificável:**

1. Uma inbox com `widget_color = #009CE0` e outra com `#2DC46F` renderizam **header, botão de enviar
   e balão do visitante com o mesmo `background-color` da respectiva inbox** — medido por
   `getComputedStyle`, em light e dark, desktop e mobile. (É o teste que falharia hoje [15 §B11.2].)
2. `getContrast` do texto sobre o balão do visitante ≥ **4,5:1** para as duas cores acima.
3. `curl -I` nos assets do widget devolve `content-encoding: gzip` ou `br`.
4. `leaflet-*.js` **não** aparece nos imports estáticos de `entrypoints/widget.js` no manifest, e
   `typeof window.L === 'undefined'` dentro do iframe.
5. CSS do widget ≤ **80 KB crus** (hoje 1.103.132 [MEDIDO]).
6. `document.documentElement.lang` não vazio e igual ao locale da conversa.
7. Um `[role="log"]` existe na view de mensagens.
8. Nenhuma requisição a `typing.gif`.
9. `size-limit` falha se o grafo eager passar do teto (§8).

### Fase 2 — A conversa

**Objetivo:** a superfície que o visitante realmente lê. É aqui que o redesenho aparece.

| Item | Frente | Esforço |
|---|---|---|
| Primitivos `widget/ui/` | C | **G** |
| F1 (bridge), F2 (registry de tipos), F3 (SCSS), F4 (MessageRow) | F | **G** |
| Balões: raio, padding, `max-width`, sem sombra, agrupamento por dados | D | M |
| Lista: fundo, separadores, avatar/nome/horário por grupo | D | M |
| Scroll condicional + botão "descer" + throttle + `watch` | §3.4 | M |
| Composer: botão de enviar, foco visível, `keydown` no campo | E (casca) + C | M |
| Header: altura, avatar, ações, heading, identidade de IA | D | M |
| Estados: vazio, carregando (skeleton > 600 ms), erro, offline, reconectando | §3.13, §3.14 | M |
| Animação de entrada de mensagem + `prefers-reduced-motion` completo | §4 | P |
| Mobile: `dvh`, safe-area, breakpoint único 768, alvos 44×44 | §2.7 | M |
| Watchdog do widget (destrava a faixa "reconectando") | §5.4 | M |

**Critério de pronto:**

1. Os **16 snapshots** de regressão visual passam: 4 views (home, messages, prechat, unread) × 2
   temas × 2 viewports (1280×900 e 375×667), com fixtures determinísticas injetadas no store e tempo
   congelado [15 §B11.2].
2. `axe-core` sem violação **crítica ou séria** nas 4 views, nos 2 temas.
3. Todo elemento clicável no viewport 375×667 mede **≥ 44×44** — hoje 0 de 5 passam [MEDIDO].
4. Com `prefers-reduced-motion: reduce`, o `transition` computado do painel e do launcher é `none`
   ou ≤ 1 ms; os typing dots não têm `animation`.
5. Com a rede cortada por 10 s: a faixa aparece depois de ~3 s, o composer continua utilizável, a
   mensagem digitada entra na fila e é enviada na volta, **em ordem**.
6. Chegando mensagem com o visitante rolado para cima: a lista **não** salta; o botão "descer"
   aparece com contador.
7. Painel funciona em **320 px** de largura e em **200%** de zoom sem perda de conteúdo.
8. Nenhuma altura fixa em px em elemento com texto (auditável por busca).

### Fase 3 — Proatividade e acabamento

**Objetivo:** o widget passa de reativo a convidativo, e fecha os itens que dependem de decisão do
Walisson.

| Item | Frente | Esforço |
|---|---|---|
| Teaser (§3.2) com gatilho composto, dispensa persistida, cooldown | C + SDK | **G** |
| CSAT e cards redesenhados | D | M |
| Pre-chat: tokens, erros específicos, aviso de privacidade em linha | E | M |
| Handoff: as três marcações + fila + card de 120 s | D + backend | **G** |
| Rótulo de IA persistente + `aria-busy` no streaming | D | M |
| Telemetria de erro do widget (GlitchTip) | ⚪ | M |
| Fila offline de intenções | ⚪ | M |
| Dark mode: default, `<html>`, `color-scheme`, reatividade | B + D | P |
| Decisões Q1–Q8 aplicadas | — | varia |

**Critério de pronto:**

1. O teaser aparece **uma vez**, com 8 s + 30% de scroll, some ao ser dispensado e **não volta** em
   3 navegações seguidas no mesmo contexto.
2. O teaser **não** dispara com banner de cookies visível.
3. Simulando handoff, as **três** marcações aparecem (mensagem de sistema, header, identidade da
   bolha); simulando a volta para a IA, as três também.
4. Um erro forçado no widget aparece no GlitchTip com PII removida.
5. Com `chatwootSettings.darkMode` ausente e o SO em escuro, o widget abre escuro.
6. Trocar o tema do SO com o painel aberto muda o tema **sem remount**.
7. `prefers-contrast: more` engrossa bordas e foco; `forced-colors: active` mantém os dois balões
   distinguíveis por borda.

---

## 8. Checklist de aceite

Cada item é passa/falha. Nada aqui é princípio.

### 8.1 Contraste

- [ ] Texto do corpo ≥ **4,5:1** no tema claro
- [ ] Texto do corpo ≥ **4,5:1** no tema escuro
- [ ] Texto sobre o balão de marca ≥ 4,5:1 para as **5 cores de marca mais usadas na frota**
- [ ] Texto sobre o balão de marca ≥ 4,5:1 para `#009CE0` e `#2DC46F` especificamente (os dois casos
      medidos como falha)
- [ ] Link dentro da bolha do agente ≥ 4,5:1 nos dois temas (hoje: **2,27:1** no claro)
- [ ] Texto secundário (horário, sistema, branding) ≥ 4,5:1 — **não** é "texto grande", tem 12 px
- [ ] Borda do campo de digitação ≥ **3:1** contra o fundo do painel
- [ ] Ícone de enviar ≥ 3:1 contra o fundo do botão
- [ ] Anel de foco ≥ 3:1 contra o elemento **e** contra o fundo, nos dois temas
- [ ] Nenhum token de cor usa `opacity` sobre a marca para gerar estado

### 8.2 Cor e daltonismo

- [ ] Nenhum status (online/ausente/fora do horário) distinguível **apenas** por cor
- [ ] Distinção IA / humano / sistema feita por rótulo ou ícone, nunca só por matiz
- [ ] Falha de envio sinalizada por ícone **e** texto
- [ ] Screenshot em simulação de deuteranopia revisado nas 4 views

### 8.3 Acessibilidade — WCAG 2.2

| Critério | Nível | Verificação |
|---|---|---|
| **1.4.3** Contraste mínimo | AA | §8.1 |
| **1.4.11** Contraste não-textual | AA | borda de input, ícone sem rótulo, estado ativo |
| **1.4.1** Uso da cor | A | §8.2 |
| **1.4.4** Resize text | AA | 200% de zoom sem perda |
| **1.4.10** Reflow | AA | funciona em 320 px |
| **1.4.12** Text spacing | AA | entrelinha 1,5 / `letter-spacing` 0,12em / `word-spacing` 0,16em forçados |
| **2.1.1** Teclado | A | toda ação alcançável sem mouse |
| **2.2.2** Pause, stop, hide | **A** | nenhuma animação em loop passa de 5 s sem controle (typing dots sob `reduced-motion`) |
| **2.4.7** Foco visível | AA | todo controle |
| **2.4.11** Focus not obscured | AA | o foco nunca fica inteiramente escondido atrás do painel |
| **2.5.7** Dragging movements | AA | anexar por arrastar tem alternativa por clique |
| **2.5.8** Target size (minimum) | AA | ≥ 24×24, com regra de espaçamento onde menor |
| **3.2.6** Consistent help | **A** | launcher na mesma posição relativa em todas as páginas |
| **4.1.3** Status messages | AA | `role="log"` na lista; `role="alert"` em erro |

Checklist operacional:

- [ ] Launcher alcançável por Tab, com nome acessível **traduzido**
- [ ] `Enter`/`Espaço` abrem o painel
- [ ] Foco entra no painel ao abrir (campo ou cabeçalho, conforme §3.9)
- [ ] **`Esc` fecha o painel** e o foco volta ao launcher
- [ ] Nenhum `tabindex` positivo; ordem de Tab = ordem visual
- [ ] Em modal (mobile), o conteúdo de fundo é `inert`; em desktop **não** há armadilha de foco
- [ ] `aria-busy="true"` durante streaming de IA, `false` ao concluir
- [ ] Typing indicator **não** anunciado repetidamente; recibos **não** anunciados
- [ ] Nenhum `aria-live="assertive"` na chegada de mensagem normal
- [ ] Alvos ≥ **44×44** no viewport mobile

### 8.4 Peso de bundle

| Métrica | Hoje [MEDIDO] | Teto |
|---|---:|---:|
| JS eager do widget (gzip) | 482.322 B | **150 KB** |
| CSS do widget (gzip) | 106.127 B | **20 KB** |
| CSS do widget (cru) | 1.103.132 B | **80 KB** |
| Total eager (gzip) | 588.943 B | **170 KB** |
| SDK (gzip) | 9.570 B | **15 KB** |

- [ ] O gate mede o **fecho transitivo** de imports + CSS da entrada, não um glob de arquivo
- [ ] O diretório é limpo antes de medir (hoje o glob casa com 4 hashes antigos)
- [ ] Asserção específica: **falhar se `leaflet-*.js` aparecer nos imports estáticos** da entrada
- [ ] Assets servidos com `content-encoding`
- [ ] Contribuição do widget para o CLS do site do cliente = **0**

### 8.5 Mobile

- [ ] Painel em `100dvh`, com `100vh` declarado antes como fallback
- [ ] Composer respeita `env(safe-area-inset-bottom)`; header respeita `safe-area-inset-top`
- [ ] Launcher some ao abrir
- [ ] Sem transição de tamanho no fullscreen
- [ ] Breakpoint único em 768 px, sem sobreposição
- [ ] Campo de digitação em **16 px** (anti-zoom iOS)
- [ ] **[NÃO VERIFICADO — testar em dispositivo real]** o composer não fica atrás do teclado virtual.
      Três lacunas do 13 §13.5 se aplicam aqui: comportamento de `dvh` com barra de endereço real,
      `visualViewport` com teclado, e `overscroll-behavior` no Safari. Nenhuma é resolvível em
      headless.

### 8.6 Dark mode

- [ ] Classe `dark` no `<html>`, não no `<div>`
- [ ] `color-scheme` no `:root`
- [ ] Contraste auditado **independentemente** no tema escuro (não herdado do claro)
- [ ] Sombras substituídas por superfície + borda
- [ ] Cor de marca recalibrada contra a superfície escura
- [ ] Troca de tema do SO com o painel aberto reflete sem remount
- [ ] Default respeita `prefers-color-scheme` (ver Q6)

### 8.7 i18n pt-BR

- [ ] Nenhum texto visível fora do i18n — em especial o `title`/`aria-label` do launcher, hoje
      `'Open chat window'` **hardcoded em inglês** [FATO — 15 §A5.3]
- [ ] "mandatório" → **"obrigatório"** e revisão de toda tradução mecânica [06 §14.1 R1]
- [ ] `REGEX_ERROR` genérico → erro **específico por campo** [06 §14.1 R2]
- [ ] `lang` do contêiner acompanha o idioma da **conversa**, não o do site do cliente
- [ ] Nenhum rótulo acessível em inglês com interface em pt-BR
- [ ] Textos longos testados em pt-BR (que é ~15–20% mais longo que en) sem quebrar layout

---

## 9. O que não vamos fazer

Lista explícita. Cada linha existe para impedir que o escopo cresça em reunião.

| # | Não faremos | Por quê |
|---|---|---|
| 1 | **Virtualizar a lista de mensagens** | O DOM inteiro do widget tem **74 nós**; 50 mensagens ficam em 500–700 — irrelevante para qualquer navegador atual. O limiar é ~200 mensagens simultâneas, cenário raro num chat de site. E o pré-requisito (mover o agrupamento de seletores de irmão adjacente para dados) custa mais que o ganho hoje [15 §B9.3] |
| 2 | **Adotar webfont (Inter ou outra)** | Com dois pesos, a fonte variável é 320 bytes **mais** pesada que as estáticas; o ponto de virada é 3 pesos [MEDIDO — 13 §2.7]. Mais FOUT/FOIT e risco de CSP no site do cliente. O custo de rede hoje já é zero |
| 3 | **Liquid Glass / `backdrop-filter` atrás de texto de conversa** | A própria Apple escreve "não use Liquid Glass na camada de conteúdo" e manda usar a variante *regular* quando há "quantidade significativa de texto". E `backdrop-filter` só entrou em Baseline "newly available" em 16/09/2024 — cedo demais para código de terceiro [13 §13.4]. Se entrar, entra atrás de `@supports`, no header ou no launcher |
| 4 | **Roxo como marcador exclusivo de IA** | Contra o azul de informação, o par colapsa para **ΔE 1,8** em deuteranopia — a mesma cor [MEDIDO — 13 §3.4] |
| 5 | **Densidade compacta (14 px como default)** | É a régua de ferramenta de produtividade, para usuário treinado e sentado. O visitante é o oposto nas três dimensões [13 §6.8]. Fica como variante opcional (`--w-text-message-sm`), não como padrão |
| 6 | **Recibos "entregue" e "lido"** | Nenhum concorrente do corpus tem [MEDIDO — 12 §7], e "lido e não respondido" cria dívida visível e transforma cada segundo de silêncio em irritação [06 §5.3]. Faremos `enviando`/`enviado`/`falhou`, que é o que resolve |
| 7 | **Auto-open do painel** | Toda a reclamação documentada de usuário é contra ele; nenhuma é contra o teaser [06 §2.4]. E abrir sozinho cobrindo a tela em mobile é a descrição literal do que o Google penaliza [13 §7.2] |
| 8 | **Loop infinito de "chamar atenção" no launcher** | O `octaWaRadar` de 2,4 s da Octadesk vira ruído periférico em segundos e não pode ser desligado pelo visitante. O modelo certo é a Leadster: **uma** encenação de 500 ms, uma vez, e silêncio [12 §C13] |
| 9 | **Bloquear Lighthouse/GTmetrix por User-Agent** | O Crisp faz (o loader lista `Lighthouse`, `GTmetrix`, `HeadlessChrome`). Esconder o custo do widget da auditoria do cliente é enganoso, e quebraria nossos próprios testes Playwright [14 §15.6, 06 §14.7 R40] |
| 10 | **Migrar para Shadow DOM ou DOM direto nesta onda** | O isolamento por iframe é vantagem real e medida (a Leadster tem 239 `!important` para provar o contrário). O híbrido do 10 §Q2 é decisão de arquitetura posterior, e esta spec é compatível com ele |
| 11 | **Redesenhar `PreChat/Form.vue` por dentro** | 16 commits em 36 meses e **+39 −33** só desde a nossa base. Nesta onda ele recebe **apenas tokens** |
| 12 | **Mexer em `store/modules/conversation/`** | O módulo que o upstream mais mexeu. Getters novos vão em arquivo separado |
| 13 | **Gravação de áudio no composer** | O `iframe.allow` já concede `microphone`, mas é feature de produto, não de redesenho. Fica para o roadmap [09 §16.3 G10] |
| 14 | **Busca no Help Center dentro do widget** | Mesma razão: é feature, não acabamento [09 §16.3 G9] |
| 15 | **Notificação nativa do navegador e vibração** | Zero widgets do corpus fazem. Pedir permissão de notificação em cima do primeiro contato é caro em confiança [12 §12.3] |
| 16 | **Skeleton em toda espera** | Só acima de 600 ms. Um skeleton que aparece e some antes de ser lido é pior que nada [DV-7] |
| 17 | **Múltiplas conversas simultâneas / inbox do visitante** | O widget hoje só conhece a última conversa (`conversations.last`). Mudar isso é produto, não redesenho [09 §9] |

---

## 10. Perguntas para o Walisson

Oito decisões que dependem dele. Cada uma com opções reais, o que muda, e minha recomendação.

### Q1 — Corpo da mensagem: 15 px ou 14 px?

| Opção | O que muda |
|---|---|
| **(a) 15px / 22px** — recomendado | Alinha com a régua de superfície de consumidor (M3 16, Apple 17, GOV.UK 19). Balões ficam ~7% mais altos; cabe menos conversa na tela. Medida de ~35–36 caracteres/linha |
| (b) Manter 14px / 21px | É a moda do mercado (6 de 11 concorrentes) e o que já temos: custo zero, risco zero. Cabe mais conversa |

**Recomendo (a).** O 11 descreve o que o mercado faz; o 13 prescreve para quem o widget serve — e
quem digita nele é um visitante com pressa, no celular. Mas é a divergência mais cara desta spec
(muda a altura de tudo), e a decisão é sua. Se a preferência for por densidade, (b) é defensável e a
spec já traz o token de variante.

### Q2 — Header: colorido com a marca, ou neutro?

| Opção | O que muda |
|---|---|
| **(a) Neutro** (`--w-surface`), com a marca no launcher, no balão do visitante, no botão de enviar e no foco — recomendado | Resolve o problema de contraste de uma vez (nada de texto sobre cor arbitrária no header). É a escola do Intercom e do LiveChat, que são também os dois com maior raio de painel e os que resolvem o balão por contraste. 3 de 11 hoje |
| (b) Colorido com `--w-brand` | É maioria (7 de 11) e é o que temos. **Mas exige `--w-on-brand` preto** em cores claras: com o verde atual, texto branco dá **2,25:1** e preto dá 9,35:1 |

**Recomendo (a).** Com (b) o widget fica refém da cor que o cliente escolher, e um header com texto
preto sobre verde-claro é visualmente estranho — vamos acabar querendo escurecer o verde, o que
muda a marca dele sem pedir. O neutro dá liberdade total de cor **sem** risco de contraste.

### Q3 — Textura de fundo da conversa: manter, trocar ou remover?

| Opção | O que muda |
|---|---|
| **(a) Manter a assinatura, trocar o asset** — recomendado | Padrão em SVG/CSS em vez de PNG. Hoje são **88.534 B + 96.098 B** de PNG, sem WebP e sem preload |
| (b) Manter como está | Custo de rede em cada abertura, e um dos dois é sempre baixado à toa |
| (c) Remover, fundo sólido `--w-surface-sunken` | Mais leve e mais próximo do Intercom/Crisp — mas abre mão da leitura "WhatsApp" que é a direção do fork |

**Recomendo (a).** A textura é assinatura de produto e a direção do fork já foi aprovada; o problema
é o formato do arquivo, não a decisão de design. Sob `forced-colors: active` a textura sai de
qualquer forma (§2.6).

### Q4 — Launcher: bolha silenciosa ou launcher que fala?

| Opção | O que muda |
|---|---|
| (a) Bolha silenciosa (atual) | É o padrão: 9 de 13 |
| **(b) Testar a variante expandida em algumas contas** — recomendado | **Ela já existe no CSS do SDK** (altura 48, largura automática, texto 16/500) e é possivelmente ociosa. Três concorrentes abandonaram o círculo para caber texto: Olark (pill 183,7×52), JivoChat (etiqueta 301×40), LiveChat (cartão 296×237) |
| (c) Rosto humano no launcher | É o que a Leadster faz — e é o único do corpus. Para quem vende atendimento humano + IA é diferenciação forte, e o custo é uma configuração de imagem |

**Recomendo (b) como experimento**, não como default: ativar em 2–3 contas e comparar. É a mudança
de maior efeito potencial sem escrever componente novo. **[NÃO VERIFICADO]** quantas contas da frota
já usam a variante hoje — vale checar antes.

### Q5 — Teaser proativo entra nesta onda?

| Opção | O que muda |
|---|---|
| **(a) Sim, na Fase 3** — recomendado | Nove concorrentes têm; nós não temos nada. Com gatilho composto (8 s + 30% de scroll), dispensa persistida e cooldown |
| (b) Não, fica para depois | A Fase 3 encolhe bastante |

**Recomendo (a)**, com uma ressalva de honestidade: **não existe teste A/B público comparando teaser
vs. auto-open**, e a frequência de reaparição não foi medida em nenhum fornecedor
[NÃO VERIFICADO — 06 §15 L1, 12 §4]. Temos frota para medir isso internamente, e essa medição vale
mais que qualquer benchmark que eu pudesse citar.

### Q6 — Dark mode: default `auto` em vez de `light`?

| Opção | O que muda |
|---|---|
| **(a) `auto` como default** — recomendado | Quem embute o widget sem configurar nada passa a respeitar o SO do visitante. Hoje o default é `light`, então quem usa o SO no escuro recebe tema claro |
| (b) Manter `light` | Previsível para o cliente, mas ignora uma preferência que o SO já respondeu |

**Recomendo (a).** É uma linha (`sdk.js:74`), e **apenas 1 de 4 concorrentes testados suporta dark
mode** — é a diferenciação com melhor razão esforço/percepção de todo o levantamento visual.
Ressalva: com (a), contas que hoje veem claro podem ver escuro depois do deploy. É mudança visível
para cliente existente e precisa de aviso.

### Q7 — Som e piscar do título da aba

| Opção | O que muda |
|---|---|
| **(a) Som desligado por padrão, com opção por inbox; piscar do título ligado** — recomendado | Nielsen mede 92% de irritação com autoplay e >1/3 de abandono. O piscar do título tem 0% de atrito e só age com a aba oculta |
| (b) Manter o som ligado (hoje temos `ding.mp3`) | Intercom e HubSpot tocam; a Leadster não |
| (c) Nem som nem piscar | |

**Recomendo (a).** O mecanismo do piscar já está documentado com parâmetros exatos (650 ms de
intervalo, 60 s de duração, para no `visibilitychange`, não reentra) e é copiável direto
[FATO — 12 §12.2].

### Q8 — Identidade de IA visível: rótulo persistente?

| Opção | O que muda |
|---|---|
| **(a) Sim — rótulo "IA" no header e atrelado à bolha do bot** — recomendado | Três fontes independentes convergem (NN/g, Carbon for AI, HAX G1/G2/G18), e o **EU AI Act art. 50 está em vigor desde 02/08/2026** com alcance extraterritorial |
| (b) Só na primeira mensagem | Quem entra numa conversa longa ou volta depois não sabe com quem fala **naquele momento** |
| (c) Não rotular | A FTC alerta contra chatbot humanizado não rotulado; e o ganho de curto prazo é apagado no instante em que o visitante descobre |

**Recomendo (a).** O custo é um rótulo textual; o risco de (c) é regulatório e reputacional. E o
rótulo precisa ser **texto ou ícone**, nunca só a cor (§5.6).

---

## Anexo — pranchas e capturas de apoio

Esta task não produziu imagens novas (é síntese). As referências visuais para executar a spec já
existem em `plano/estudo-chat-web/frontend/shots/` — 360 arquivos. As que importam para cada seção:

| Seção desta spec | Arquivo | O que mostra |
|---|---|---|
| §1 P1, §2.5.2, §3.3 | `t15-panel-messages-desktop-light.png` · `-dark.png` | **O bug de cor**: header verde com `widget_color` azul, nos dois temas |
| §2.5.2, §8.1 | `t13-contraste-balao-marca.png` | 12 cores de marca: luminância, contraste com branco e preto, escolha WCAG × escolha YIQ |
| §2.1 | `t13-escala-tipografica-mensagem-light.png` · `-dark.png` | Corpo 14/15/16 lado a lado no mesmo painel de 400 px |
| §2.7.6 | `t13-medida-caracteres-por-linha.png` | Matriz de 36 medições: painel × largura de bolha × corpo → caracteres/linha |
| §2.1 | `t13-tabular-nums.png` | Sete horários em Inter/Roboto/Arial, com e sem `tabular-nums` |
| §2.2, §3.4 | `t13-agrupamento-mensagens.png` | A mesma conversa com e sem agrupamento (−22,8% de altura) |
| §2.4 | `t13-elevacao-vs-borda-light.png` · `-dark.png` | Cinco sombras + uma borda, no mesmo card, nos dois temas |
| §2.5.6, §8.2 | `t13-daltonismo-status.png` | Indicadores de status em protanopia, deuteranopia e tritanopia + ΔE2000 |
| §3.1, §3.3, §3.9 | `t13-alvos-de-toque.png` | Alvos de 20/24/28/44/48 px + regra dos círculos de 24 px |
| §3.9, §8.3 | `t13-foco-espacamento-raios.png` | Quatro estratégias de indicador de foco (incluindo a do GOV.UK) |
| §3.1, Q4 | `COMPARATIVO-launchers-desktop.png` | Os 13 cantos inferiores direitos lado a lado — bolha silenciosa × pill com rótulo × etiqueta × cartão × rosto humano |
| §3.5 | `t15-panel-bolhas-desktop-light.png` · `-dark.png` · `t15-bolhas-markdown-light.png` | Nossos balões hoje, e o link com 2,27:1 no claro |
| §2.7.4, §8.5 | `t15-panel-mobile-375.png` · `t15-messages-mobile-375.png` | Painel em tela cheia e os alvos de toque no mobile |
| §3.1 | `t15-launcher-desktop-light.png` · `-dark.png` · `t15-launcher-mobile-375.png` | Nosso launcher hoje |
| §4.2 | `intercom-desktop-i-hover.png` · `intercom-desktop-i-press.png` | `scale(1.1)` e `scale(0.85)` do Intercom |
| §4.2 | `chatwoot-desktop-launcher-hover.png` | O nosso hover, que só muda a sombra |
| §3.2 | `crisp-desktop-i-open.png` · `tawk-desktop-i-open.png` · `leadster-timeline-t*ms.png` | Teasers e quick replies do mercado; a sequência cronometrada da Leadster |
| §5.3 | `crisp-offline-11s-desktop.png` · `crisp-reconectado-desktop.png` | Comportamento offline e drenagem da fila no Crisp |

---

## O QUE ISSO SIGNIFICA PARA O REDESENHO DO CHATSPX

**1. O redesenho tem um pré-requisito que não é de design.** A cor da conta não chega no produto —
está medido, em light e dark, desktop e mobile, com a causa rastreada até um literal em
`theme/colors.js:123` e uma variável CSS que é escrita e nunca lida. Enquanto isso não for
resolvido, qualquer paleta nova apenas amplifica o problema: o widget continuará contando duas
histórias na mesma tela. E os três arquivos envolvidos estão na zona segura de merge, o que torna a
correção barata em risco.

**2. Contraste deixou de ser opinião.** Três falhas estão medidas e uma foi fechada aqui: balão do
visitante em 3,07:1, link do agente em 2,27:1, e — pela simetria da fórmula WCAG — o **header verde
com texto branco em 2,25:1**, que reprova até o mínimo de componente. A causa é a mesma nas três: uma
heurística YIQ dos anos 90 que escolhe entre dois extremos e não verifica se o resultado atinge razão
alguma. A regra correta (luminância relativa, limiar 0,17913, preto puro) e a ferramenta
(`colorHelper.js`) já existem no repositório. É parametrizar, não escrever.

**3. O esqueleto não muda; o acabamento muda inteiro.** Doze das nossas medidas coincidem com a
mediana ou a moda do mercado. O redesenho não recomeça da geometria — ele ataca cor, movimento
(somos o único do corpus com painel em `linear`, sem `:active` no launcher e com typing em GIF),
acessibilidade (zero `aria-live` num chat) e peso (2,58 MB servidos crus).

**4. A maior parte do ganho de performance não toca em um componente Vue.** Ligar compressão,
restringir o `content` do Tailwind e tirar o Leaflet do grafo devolvem quase tudo — e podem ser
feitos **antes** do redesenho, num terreno limpo, sem que os ganhos se confundam com os efeitos do
redesenho. O gate de tamanho no CI precisa ser corrigido junto, senão nenhuma meta significa nada:
hoje ele reporta 76,53 kB para um widget que custa 575 KiB.

**5. Onde o mercado inteiro é fraco, é barato ganhar.** `Esc` que fecha (6 de 7 não fecham),
`prefers-reduced-motion` (6 de 7 ignoram), dark mode (1 de 4 suporta), estado de toque no launcher
(1 de 7 tem), botão "descer" com contador (não localizado em nenhum), telemetria de erro no widget
(todos os cinco medidos têm; nós não temos). Nenhum desses é caro. Todos são visíveis.

**6. Três coisas ficam em aberto e precisam de dispositivo real antes de congelar o mobile:**
comportamento de `dvh` com barra de endereço, `visualViewport` com teclado virtual, e
`overscroll-behavior` no Safari. Nenhuma é mensurável em headless, e 72% dos minutos digitais no
Brasil são mobile. Não congelar o layout mobile antes de fechar essas três.

**7. A defesa contra o custo de merge é estrutural, não disciplinar.** O widget está praticamente
virgem (4 commits do fork) e o upstream continua mexendo (113 arquivos entre a nossa base e a
v4.16.2). Pastas novas, cascas finas no campo minado, tokens em arquivo próprio e o merge da v4.16.2
rodado **antes** — nessa ordem. Fazer o redesenho primeiro é escolher pagar esse custo em todo merge
futuro.

---

*Documento produzido em 12/08/2026 a partir da leitura integral dos relatórios 11, 12, 13, 14 e 15
(frontend) e 06, 09 e 10 (onda anterior). Nenhum arquivo de código foi alterado; os relatórios de
entrada não foram modificados. Onde nada foi verificado, está escrito "não verificado".*
