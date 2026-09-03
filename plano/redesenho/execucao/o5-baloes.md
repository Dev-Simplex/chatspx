# Onda 5 — trilha BALÕES E RENDER DE MENSAGEM

Worktree: `/home/chatwoot/chatwoot-o1-bridge` · branch `o1-bridge` · base `c32c1a738d` · 19/08/2026

Blocos: **2.03** (balões), **2.12** (render/MarkdownIt), **2.04** (lista e scroll), **2.08**
(movimento e as três media queries de acessibilidade).

Escrito conforme avanço. Cada bloco traz o que a base tinha (medido), o que foi feito, o mecanismo
que executa o aceite, e o resultado real — inclusive quando ele é vermelho.

---

## 0. O terreno, medido antes da primeira linha

| O que | Estado medido |
|---|---|
| Matriz de 20 (`--project=widget`) | **32 passed (5,4 min)** antes de qualquer alteração. É a linha de base contra a qual todo pixel deste relatório é comparado |
| `_conversation.scss` | 209 linhas · **oito** declarações de raio com `0.25rem`/`1.25rem` cravados · sombra dupla no `.chat-bubble` · corpo `text-sm leading-[1.5]` (14/21) · `max-w-[88%]` no agente e `[85%]` no visitante |
| Os **seis** seletores de irmão adjacente | **vivos**, em `:50-74` e `:106-118`, exatamente onde o plano os mapeou |
| `useMessageGrouping.js` (bloco 2.02) | existe, com 18 testes verdes — e **nenhum consumidor**: `grep -rn useMessageGrouping app/javascript` só encontrava a própria definição |
| `widget/ui/WBubble.vue` (bloco 2.01) | existe, com a geometria do 2.03 **cravada em literais** e `@apply … shadow-none` |
| Horário da mensagem | só existe em anexo, **dentro** do balão: `<span class="time">` em absoluto sobre a imagem, e um `<span>` sobre a barra de controles do vídeo |
| `spec/services/widget_tokens_spec.rb` | **6 exemplos vermelhos** na base (ver §1.6) |

### 0.1 O 2.02 não estava fechado — e é dele que o 2.03 depende

O enunciado desta trilha diz que o 2.02 está fechado. **Metade dele está.** O commit `c32c1a738d`
diz isso na primeira linha do corpo ("Primeira metade do 2.02") e a medição confirma: o composable
existe e é testado, mas ninguém o chama, e os seis seletores continuavam decidindo o agrupamento.

Isso não é observação de arquivista: o 2.03 pede **"raio 20/6"**, e o 6 é o canto que só existe *na
continuação de um grupo*. Sem o dado do agrupamento não há como colocá-lo. Então a ligação — o
composable sendo consumido, e os seis seletores saindo do CSS — foi feita **dentro do 2.03**, que é
onde ela é pré-requisito, e está documentada aqui.

**O que continua aberto do 2.02, e não foi feito:** o `MessageRow.vue` que unifica
`AgentMessage.vue` + `UserMessage.vue`, com o aceite *"< 150 linhas somados"*. Hoje eles somam
**471** (283 + 188). Não entrou de propósito: fundir os dois é uma refatoração que mexe em anexo,
`ReplyToChip`, `DragWrapper` e estado de erro ao mesmo tempo, e faria a matriz de 20 se mover por
razões que eu não conseguiria separar das do 2.03 — que é justamente a régua desta trilha. Fica
registrado como o resto do 2.02, com a metade dele (o aceite *"nenhum seletor de irmão adjacente
para agrupar"*) fechada aqui.

---

## 1. Bloco 2.03 — os balões ✅

**Aceite (§2.2):** *"`boxShadow === 'none'`; contraste ≥ 4,5:1 nos dois temas, nas duas cores de
teste"*, mais a linha do bloco: raio 20/6, `max-width` 82%, sem sombra, corpo 15/22, horário fora.

### 1.1 O que foi feito

| Arquivo | O quê |
|---|---|
| `_tokens_values.scss` | mixin novo **`widget-shape`**: `--w-bubble-radius: 20px`, `--w-bubble-radius-tail: 6px`, `--w-bubble-max-width: 82%`, `--w-bubble-font-size: 15px`, `--w-bubble-line-height: 22px`, `--w-bubble-shadow: none` |
| `_tokens.scss` | `@include widget-shape` no `:root` (sem par escuro — forma não muda com tema) |
| `_conversation.scss` | sombra removida; corpo 15/22; os oito raios saem do token; `max-width` 82% nos dois lados; os **seis** seletores de irmão viram duas classes; `.message-time` novo |
| `ConversationWrap.vue` | consome `calcularAgrupamento`, **por bloco de data**, e entrega a classe pronta à linha |
| `ChatMessage.vue` · `AgentMessage.vue` · `UserMessage.vue` | recebem e aplicam `classeAgrupamento`; `has-response` some; horário fora do balão |
| `UnreadMessageList.vue` · `UnreadMessage.vue` | mesma classe, calculada por índice (na lista de não lidas toda linha é do agente) |
| `ImageBubble.vue` · `VideoBubble.vue` | o horário sai de dentro da mídia; com ele sai o degradê que existia só para torná-lo legível |
| `widget/ui/WBubble.vue` | `box-shadow: none` literal e geometria pelos tokens (ver §1.5) |
| `app/services/widget_tokens.rb` | `SURFACE_DARK` passa a ser a superfície do BALÃO, não a do painel (ver §1.4) |

**Os cinco números moram num lugar só.** Três superfícies precisam deles — a conversa, a lista de não
lidas e o primitivo `WBubble` — e o preview do widget no dashboard consome os mesmos mixins. Cravá-los
em cada uma é a dívida D4 se reabrindo: cópias livres para divergir sem ninguém ver.

**O agrupamento é POR BLOCO DE DATA, e isso não é detalhe.** Era o que o seletor de irmão fazia sem
dizer: cada dia é uma `<div class="messages-wrap">` própria, então a primeira linha de um dia nunca
teve irmão anterior e nunca continuou o grupo do dia anterior. Rodar `calcularAgrupamento` na
conversa achatada mudaria exatamente essa linha — a que fica logo abaixo do separador, uma das mais
visíveis da lista. Está travado por teste próprio.

### 1.2 Mecanismo

Dois arquivos, com a divisão que esta casa já usa: marcação e estrutura em jsdom, valor computado em
Chromium.

* `components/specs/baloes.spec.js` — **15 exemplos**. As seis regras do CSS antigo, uma a uma,
  medidas pela classe que a linha recebe; o recorte por bloco de data; que nenhum horário more dentro
  de um `.chat-bubble`; e a varredura textual que impede o seletor de irmão, a sombra e o `0.25rem`
  de voltarem ao SCSS.
* `components/specs/browser/bubble-geometry.check.mjs` — **64 asserções** de valor computado em
  Chromium, nas 4 combinações do aceite (2 cores × 2 temas) mais o espelho RTL.

**Por que jsdom não serve para a parte que o aceite mede.** Ele não resolve `var(--w-brand)`, não
aplica cascade e devolve a string que você escreveu. Um teste de classe — *"a bolha tem
`bg-w-brand`"* — passa com o widget preto no branco.

**As duas cores de teste vêm do Ruby de verdade.** `WidgetTokens` não depende de Rails (é aritmética
sobre três inteiros), então o check o executa por `ruby -r./app/services/widget_tokens` e usa o
`<style>` que `show.html.erb` emitiria. Reescrever a fórmula em JS seria reabrir o defeito que o
bloco 1.02 fechou: duas contas de contraste livres para divergir.

### 1.3 Resultado real — as quatro medições do aceite

Chromium, `getComputedStyle`, CSS do build (`bin/vite build --force`):

| Cor | Tema | Texto na bolha do visitante | `boxShadow` |
|---|---|---|---|
| `#009CE0` | claro | **6,8318:1** | `none` |
| `#009CE0` | escuro | **6,8318:1** | `none` |
| `#2DC46F` | claro | **9,2371:1** | `none` |
| `#2DC46F` | escuro | **9,2371:1** | `none` |

E o resto do bloco, medido junto: raio livre **20px**, canto de origem **6px**, canto quebrado da
continuação **6px**, corpo **15px/22px**, largura da linha **0,820** da lista nos dois lados (era
88% × 90% = **79,2%** efetivos do lado do agente — o número declarado nunca tinha sido o medido).

**64/64 asserções ok.**

### 1.4 Achado — o link na bolha do agente reprovava, e o DEFAULT era o pior caso

A primeira execução do check pegou isto, e não é o aceite principal: é o **aceite 2 da §C.5**
(*"link na bolha do agente ≥ 4,5:1 nos dois temas"*).

```
FAIL  [#009CE0 · dark] contraste do LINK na bolha do agente
      mínimo=4.5  medido=4.4486
```

**A causa.** `--w-brand-readable-dark` é calculado por `WidgetTokens.readable_on(brand,
SURFACE_DARK)`, e `SURFACE_DARK` era `#121213` — o fundo do **painel**. Só que esse token pinta o
link **dentro do balão do agente**, e no tema escuro esse balão é `bg-n-solid-3` = `#2c2d36`, que é
mais claro que o painel. Uma cor calibrada contra o painel chega ao balão abaixo do alvo.

Medido, com a cor calibrada contra o painel, sobre o balão:

| Marca | Sobre o balão escuro |
|---|---|
| `#009CE0` | 4,4486:1 ❌ |
| **`#1f93ff`** (o **default** de `channel_web_widgets.widget_color`) | **4,3470:1** ❌ |
| `#2DC46F` | 6,0148:1 ✅ |

Ou seja: **a inbox que ninguém configurou nascia reprovando o aceite.**

**A correção** é uma constante: `SURFACE_DARK` passa a ser `#2c2d36`, a superfície mais clara sobre a
qual esse token pinta texto. Trocar para a superfície mais clara só pode *aumentar* contraste no tema
escuro, então nenhum consumidor de `--w-brand-readable-dark` fica pior. E a marca que já passava volta
intacta: `#2dc46f` continua `#2dc46f`, com 6,0148:1 — o fallback do SCSS não se move.

Depois: `#009CE0` → 4,6970:1, `#1f93ff` → 4,5801:1, `#2DC46F` → 6,0148:1. **64/64.**

### 1.5 Achado — `@apply shadow-none` não computa `none`

`widget/ui/WBubble.vue` nasceu no bloco 2.01 com este comentário:

```scss
// 15/22 e 82% saem da §C; `shadow-none` é explícito porque a regra antiga
// deste balão tinha sombra e o aceite do 2.03 mede `boxShadow === 'none'`.
@apply max-w-[82%] px-3 py-2 text-[15px] leading-[22px] shadow-none …
```

O comentário cita o aceite certo e a linha o reprova. `shadow-none` do Tailwind emite
`box-shadow: var(--tw-ring-offset-shadow,0 0 #0000), var(--tw-ring-shadow,0 0 #0000), 0 0 #0000`,
que o navegador computa como `rgba(0, 0, 0, 0) 0px 0px 0px 0px`. A string do aceite é `'none'`, e
essa não é.

É o modo de falha exato que o enunciado desta trilha descreve: um aceite de valor computado
"cumprido" por uma asserção de classe. Passaria em revisão de código, passaria num teste de jsdom, e
só o `getComputedStyle` mostra. Corrigido com `box-shadow: none` literal, no token
`--w-bubble-shadow`, e travado pelo check.

### 1.6 Achado — a guarda contra divergência SCSS↔Ruby estava vermelha há semanas

`spec/services/widget_tokens_spec.rb` tem um grupo cujo trabalho é comparar os fallbacks do SCSS com
o que o serviço Ruby calcula — *"mexer num só quebra este teste"*. Na base, os **6 exemplos dele
falhavam**, todos com `expected: "#2dc46f" got: nil`.

**Causa:** o bloco 3.10 recortou os valores de `_tokens.scss` para `_tokens_values.scss` (para o
preview do dashboard consumir os mesmos mixins) e não moveu o caminho do spec junto. Desde
`ce5b47aa6e` a regex lia um arquivo que já não declara token nenhum.

Uma guarda contra divergência que está vermelha não guarda nada — vira ruído que se aprende a
ignorar. E foi debaixo dela que o `SURFACE_DARK` do §1.4 pôde ficar calibrado contra a superfície
errada.

Corrigido: caminho certo, mais um exemplo que reprova se a regex voltar a não achar nada (senão a
próxima mudança de arquivo se apresentaria como *"divergiu"* em vez de *"a guarda perdeu o arquivo"*)
e três exemplos novos para a superfície escura do §1.4.

**`26 examples, 0 failures`** (eram 22 exemplos com 6 falhas).

### 1.7 Achado — o `dir` do documento é pré-requisito do canto quebrado

Na primeira execução, o check reprovou os oito cantos de 6px medindo **20px**. Não era o CSS: era a
página do check, que não tinha `dir`.

As variantes `ltr:`/`rtl:` do Tailwind compilam para `:where([dir=ltr], [dir=ltr] *)`. **Num
documento sem `dir`, nenhuma das duas casa** e o balão sai com os quatro cantos livres. No app quem
escreve o atributo é o watcher `isRTL` de `App.vue`, com `immediate: true`, antes do primeiro paint —
então em produção está correto; o que estava errado era a minha reprodução.

Corrigir a reprodução rendeu cobertura que não existia: o check agora mede também o **espelho RTL**
(risco **R23** do plano — `_conversation.scss` carrega ~30 pares `ltr:`/`rtl:` e este bloco reescreve
oito declarações de raio). Não há snapshot em `dir="rtl"` na matriz; estas quatro asserções são a
única coisa que prova que os pares sobreviveram.

### 1.8 Achado — a matriz de 20 dependia de quem estava com o foco

Este é o achado que mais custou, e é sobre a **régua**, não sobre o bloco.

Na primeira rodada pós-2.03, o diff de `messages-light-desktop` marcou os balões (esperado) **e o
campo do composer**, contornado por um retângulo escuro que não existia no PNG gravado. Nada em 2.03
toca o composer.

Três execuções do harness para separar as coisas. A resposta: **é o anel `:focus-visible` que o
Chromium desenha no `textarea`**, que recebe foco sozinho ao abrir a conversa. Provado capturando o
mesmo quadro duas vezes, com foco e depois de `blur()` — com foco, o retângulo; sem foco, ele some.

Duas consequências, e a segunda é a que importa:

1. **Não é regressão do 2.03.** Medido no instante exato do snapshot, o contêiner do composer tem
   `border-width: 0px` e `box-shadow` só do `shadow-sm`: ele não pinta borda nenhuma. O retângulo é
   do agente de usuário.
2. **A matriz tinha um estado não determinístico dentro de uma suíte cujo método é congelar tudo
   antes de fotografar** — o relógio, as animações, as fontes. O anel entrava ou não conforme o
   instante em que o foco caísse. Passava despercebido porque ele custa ~750 px num quadro de
   400×564 e o teto é `maxDiffPixelRatio: 0.01` = **2.256 px**: a variação existia e cabia embaixo da
   tolerância. Até que uma mudança legítima somasse a diferença dela e o quadro inteiro reprovasse —
   com o anel aparecendo no diff como se fosse consequência da mudança.

`prepareScenario` agora tira o foco antes de fotografar, com o porquê escrito ali. O que se perde é
cobertura em pixel do anel de foco — que não era cobertura, era sorteio.

**Efeito colateral útil:** ao medir isso apareceu que `ChatInputWrap.vue:197` aplica `outline-0` ao
`textarea` com o comentário *"zera a largura sem pintar um anel fantasma"*, e **não é o que
acontece**: a folha do agente de usuário aplica `outline-style: auto` no `:focus-visible`, e com
estilo `auto` a largura é decidida pelo navegador — `outline-width: 0` do autor é ignorado. Por isso
o visitante vê o anel padrão do Chromium em vez do `border-w-focus shadow-focus` que o bloco 2.05
desenhou (e que, medido, também não pinta: `shadow-sm` vem depois na folha e sobrescreve o
`--tw-shadow` do `shadow-focus`). **Não corrigi** — é arquivo e aceite do 2.05, e mexer nele daqui
misturaria as duas trilhas. Fica roteado.

### 1.9 A matriz de 20, depois

*(preenchido em §1.10)*

### 1.10 A matriz de 20, depois

**32/32 verdes.** Doze snapshots regravados, oito intactos — e os oito intactos são a conferência,
não sobra:

| Cenário | Mudou? | Por quê |
|---|:---:|---|
| `home-*` (4) | **não** | não tem balão na tela |
| `prechat-form-*` (4) | **não** | idem |
| `messages-*` (4) | sim | balões: sem sombra, 15/22, 82%, cantos 20/6 |
| `rich-types-*` (4) | sim | os mesmos balões **e** o anel de foco (ver abaixo) |
| `unread-*` (4) | sim | mesmos balões; a caixa cresceu 282 → 306 px porque a 1ª das três mensagens passou a ocupar duas linhas com 15/22 |

**Os quatro `rich-types` mudaram por dois motivos somados, e isso é a prova do §1.8.** A linha de
base deles tinha o anel de foco do composer; a de `messages-*` não. Mesma suíte, mesmo comando,
mesmo commit — dois estados diferentes gravados. Era sorteio, e agora não é.

**Os sete tipos ricos foram conferidos um a um** no PNG novo (`input_email`, `input_select`, `cards`,
`form`, `article`, `integrations`, `input_csat`): todos continuam renderizando, nenhum perdeu botão,
campo ou estrela. O que mudou neles é o que o bloco mudou — a bolha que os embrulha.

**O teste de resize do unread** (`gap: 4`, `holder: 316`, `iframe: 300`) continua idêntico nas três
medidas que ele guarda; só `iframeHeight` foi de 278 para 302, que é consequência do corpo 15/22.

---

## 2. Bloco 2.12 — uma instância de MarkdownIt ✅

**Aceite (§2.2):** *"Spy no construtor: 1 chamada para 10 renders"* + `v-memo`.

### 2.1 O que a base fazia

`MessageFormatter`, no construtor: `this.md = createMarkdownInstance(linkify)`. Uma instância **por
bolha, por render** — e `createMarkdownInstance` monta um MarkdownIt do zero (parser, regras de
core/block/inline, renderer) e ainda aplica três plugins (`mentionPlugin`, `imgResizeManager`,
`mila`). Numa conversa de 40 mensagens que rerenderiza porque o agente começou a digitar, são 40
construções para produzir o mesmo HTML de antes.

### 2.2 A armadilha que o cache ingênuo abriria — e que quase abri

Memoizar por `linkify`, que é o que a linha do bloco pede, **quebra `disableImageRendering()` em
silêncio**. O método muta a instância:

```js
disableImageRendering() {
  this.md.disable(['add-image-sizing']);
  this.md.renderer.rules.image = () => '';
}
```

Com uma instância por bolha isso era local e inofensivo. Com uma instância compartilhada, a primeira
chamada apaga imagem de **toda superfície do SPA** até o próximo reload. Quem chama é
`captain/.../DocumentDetails.vue` — então o sintoma apareceria numa conversa, noutra tela, sem nada
apontando para a causa.

E a prova de que o risco é real já estava no repositório: em `MessageFormatter.spec.js` o caso de
`#disableImageRendering` roda **depois** dos casos que esperam `<img>` renderizado. Com cache por
`linkify`, a ordem dos `describe` passaria a decidir o resultado do arquivo.

**A correção:** "sem imagem" é outra configuração, e ganha entrada própria no mapa. `md` deixa de ser
campo e vira derivado (`get md()`), então `disableImageRendering()` só marca uma flag e nenhuma
instância compartilhada é mutada. São no máximo **quatro** instâncias no processo inteiro; na
prática, uma.

### 2.3 `v-memo` — e o disable de lint que foi medido antes de ser escrito

`v-memo` entrou na linha com três chaves: `[message, classeAgrupamento, idiomaAtual]`.

* **`message`** — a identidade é chave legítima porque `getGroupedConversation` reconstrói cada
  mensagem (`{ showAvatar, ...message }`) sempre que recomputa. Objeto igual significa "o store não
  mexeu nesta conversa".
* **`classeAgrupamento`** — a linha de cima pode mudar de autor sem esta mudar.
* **`idiomaAtual`** — a chave que quase ficou de fora. Numa inbox com mais de um idioma o visitante
  troca em tempo de execução, e `RETRY`, `DOWNLOAD` e os rótulos de anexo vêm do i18n, não da
  mensagem. Sem ela ficariam no idioma antigo até a mensagem se mexer — que pode ser nunca.

**O `eslint-disable vue/valid-v-memo`.** A regra existe para o caso real (`v-memo` num *descendente*
de `v-for`, que o Vue ignora), mas ela rastreia só o `v-for` **mais externo**: `vForElement` é
atribuído apenas quando ainda é nulo, e depois a regra exige que o `v-memo` esteja nesse elemento.
Com `v-for` aninhado — blocos de data por fora, linhas por dentro — o de dentro nunca passa, embora
seja o padrão documentado do Vue (`v-memo` no MESMO elemento do `v-for`).

Um disable de lint sem medição é uma opinião. Este tem três exemplos atrás dele.

### 2.4 Mecanismo e resultado real

* `shared/helpers/specs/markdownMemoizacao.spec.js` — **4 exemplos**. O espião envolve o construtor
  REAL (`vi.importActual`), então a contagem não vem de um dublê que parou de formatar: os exemplos
  também conferem o HTML. `vi.resetModules()` por exemplo, senão um cache aquecido pelo anterior faz
  o seguinte passar por motivo errado.
* `widget/components/specs/memoDaLinha.spec.js` — **3 exemplos** com um dublê de linha que conta os
  próprios renders.

| Medição | Resultado |
|---|---|
| 10 renders, mesma configuração | **1 chamada** ao construtor |
| 5 com `linkify: true` + 5 com `false` | **2 chamadas**, e as saídas de fato diferem (`<a>` num, não no outro) |
| 10 renders com `disableImageRendering` | **≤ 2 chamadas**, e quem não desligou continua vendo `<img>` |
| Agente começa a digitar (2 linhas na tela) | linhas rerenderizadas: **0** (sem memo seriam 2) |
| Mensagem editada no store | linhas rerenderizadas: **> 0** — o memo não congela a conversa |
| Visitante troca de idioma | linhas rerenderizadas: **> 0** |

`pnpm test` de `shared/` + `widget/`: **1.138/1.138**.

### 2.5 Roteado, não corrigido — `setImageSizing` quebra com URL relativa

Achado ao escrever o spec: `imgResizeManager` faz `new URL(imgSrc)` **sem base**, e
`new URL('/imagem.png')` levanta `TypeError: Invalid URL`. Ou seja, uma mensagem em markdown com
imagem de caminho relativo **derruba a formatação inteira** — não degrada, levanta.

Reprodução: `new MessageFormatter('![alt](/imagem.png)').formattedMessage`.

Não corrigi de propósito: é `shared/helpers/MessageFormatter.js` em código que o dashboard inteiro
usa, o conserto muda o que se renderiza (imagem relativa passaria a aparecer, sem dimensionamento) e
isso não está em nenhum aceite desta trilha. A correção é um `try/catch` de três linhas em
`setImageSizing`. Fica registrado com a reprodução.

