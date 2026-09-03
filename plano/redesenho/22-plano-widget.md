# 22 — Plano de execução: o widget (iframe)

> **O que é este documento.** O plano tarefa a tarefa para executar o redesenho do widget de site
> do ChatSPX — `app/javascript/widget/` e `app/javascript/sdk/`. É o documento que um dev abre e
> executa: cada tarefa tem id, arquivos, o que fazer, critério de aceite verificável, esforço
> relativo, dependência e risco de merge.
>
> **O que este documento não é.** Não é estudo (isso são os 22 relatórios de
> `plano/estudo-chat-web/`), não é spec visual (isso é o relatório 16) e não é levantamento
> (isso é o 15). Tudo aqui pressupõe os dois lidos.
>
> **Fase:** planejamento. **Nenhum arquivo de código foi alterado por esta task.** Nenhum build,
> deploy, restart, migration ou `.env`. O único artefato produzido é este markdown.
>
> ---
>
> ## ⚠ DECISÕES DO PRODUTO — 13/08/2026: leia antes de executar qualquer tarefa deste plano
>
> O dono do produto decidiu quinze pontos que estavam abertos. **O `PLANO-MESTRE.md` é a fonte única
> da ordem e do escopo; este plano continua sendo a fonte do detalhe** — mas em seis pontos o
> detalhe daqui foi superado. Onde este arquivo e o mestre divergirem, **o mestre manda**.
>
> | Decisão | O que muda **neste** plano | Onde está o novo detalhe |
> |---|---|---|
> | **D1** — abordagem em três níveis com degradação por familiaridade | A §C.2 descreve **um** teaser; agora são **três níveis** (`discreet` / `bold` / `aggressive`), um componente com duas formas, mais o estado de familiaridade em cookie. **A frase "nunca auto-open" deixou de ser absoluta** | Mestre §2.2 blocos **3.20**, **4.06**, **4.19**, **4.20**, **4.21**; arbitragem **A15**; bloco `> DECISÃO` no topo da §C.2 |
> | **D5** — ícone do lançador | O lançador ganha `launcher_icon` com três modos; **toda inbox nova nasce com o balão**, em qualquer perfil (o padrão por perfil caiu); a tela sugere foto do time e **nunca** oferece banco de imagem | Mestre bloco **3.19**; bloco `> DECISÃO` no topo da §C.1 |
> | **D4** — facade volta ao plano | O carregamento sob demanda do app do widget (iframe só no primeiro clique) **entra**, na última onda, **depois** de W1.14/W1.16 e W4.10 (o emagrecimento) — facade sobre bundle gordo troca "pesado sempre" por "lento quando abre" | Mestre bloco **6.04** |
> | **D7** — reordenação das ondas | **As ondas W1–W4 deste plano não são mais a ordem de execução.** O acabamento visual (a maior parte de W2) passou a ser a **penúltima** onda do mestre; captura e atribuição vêm antes. Os ids das tarefas (`W1.1`, `W2.3`…) continuam válidos e continuam sendo citados pelo mestre | Mestre §2.1, §2.2 e **§2.6** (a curva de valor, com a conta aberta) |
> | **D14** — kit de qualidade adaptado ao fork | Todo E2E deste plano usa o **fixture anti-erro** (falha com `console.error`, `pageerror` ou HTTP 4xx/5xx). **Não** adotamos TypeScript strict, Biome, Zod nem Stryker — somos um fork, e Zod estoura o teto de 15 KB gzip do SDK sozinho | Mestre **§10**, bloco **0.11** |
> | **D11–D13, D15** — como este plano é executado | Worktree por frente, autonomia até **commit local** (nunca push, PR ou deploy), falha = 2 tentativas → revert → escalação | Mestre **§11** |
>
> **Data:** 12/08/2026 · **Branch:** `homologacao` (HEAD `ee87f5e799`) · **Base:** fork ChatSPX
> sobre Chatwoot v4.12.1.

---

## Como ler

| Marca | Significa |
|---|---|
| **[FATO]** | Trecho de código deste repositório, com `arquivo:linha` verificável hoje. |
| **[MEDIDO]** | Número obtido por execução (git, grep, manifest, navegador). Onde a medição é **minha, feita nesta task em 12/08/2026**, está escrito "medido nesta task". Onde vem de outro relatório, a âncora diz qual. |
| **[INFERÊNCIA]** | Conclusão derivada de dois ou mais fatos. É dedução declarada, não observação. |
| **[NÃO VERIFICADO]** | Ninguém verificou. Fica como lacuna, nunca preenchido com chute. |
| **DIVERGÊNCIA** | Este plano discorda de um relatório de entrada. Os dois lados estão declarados, com a medição nova. |

**Esforço** é sempre relativo — **P** (pequeno), **M** (médio), **G** (grande). Nunca em horas.

**Risco de merge** usa a legenda do 16 §6.3, recalibrada pela medição desta task (§0.3):
🟢 upstream não mexeu desde a v4.12.1 · 🟡 upstream mexe às vezes · 🔴 campo minado ·
⚪ arquivo novo, risco zero por construção.

---

## 0. Antes da primeira linha de código

### 0.1 O que já está decidido e não se reabre aqui

Do Walisson, e este plano executa como está:

1. **Dois perfis por inbox** — *marketing* (captura) e *suporte* (atendimento). Alternável na
   configuração da caixa de entrada; muda comportamento padrão **e** o conjunto de campos visíveis.
   Detalhado na §B.
2. **A geometria fica.** Launcher 64, painel 400×640, raio 16, padding do balão 12/16, offsets
   20/20, mobile fullscreen, iframe. O que muda é cor, movimento, acabamento, acessibilidade e peso
   [MEDIDO — 11 rec.1: doze medidas nossas coincidem com a mediana ou a moda do mercado].
3. **Onde o mercado inteiro faz errado, não copiamos.** Os três casos concretos, todos medidos:
   6 de 7 concorrentes ignoram `prefers-reduced-motion` [MEDIDO — 12 §13]; 6 de 7 não fecham com
   `Esc` [MEDIDO — 12 §11]; só 1 de 4 suporta dark mode [MEDIDO — 11 §G]. Os três entram no plano
   (W2.12, W4.5, W4.3) e são baratos justamente porque ninguém fez.
4. **Escopo é o widget inteiro, em todas as ondas** — não só a primeira.

Do estudo, e este plano assume sem reabrir [16 §0.4]: o widget continua em **iframe**; a direção
visual do fork é **WhatsApp-fiel**; **pt-BR é a língua de primeira classe**.

### 0.2 As oito perguntas do 16 §10 — como este plano as trata

O plano não trava esperando resposta. Cada pergunta tem um **default executável** e um ponto único
onde a resposta contrária é aplicada. Se a resposta vier depois, muda um token ou uma linha.

| # | Pergunta | Default deste plano | Onde muda se a resposta for outra |
|---|---|---|---|
| Q1 | Corpo 15 px ou 14 px | **15/22** | `--w-text-message` em `_tokens.scss` (W1.1). A variante 14/21 já nasce como `--w-text-message-sm` |
| Q2 | Header colorido ou neutro | **Colorido**, com `--w-on-brand` calculado (DECISOES.md F2) | `ChatHeader.vue:28` troca `bg-w-brand`→`bg-w-surface` (W2.10) |
| Q3 | Textura de fundo | **Manter, trocar o asset** | `ConversationWrap.vue:140-167` (W2.7) |
| Q4 | Launcher que fala | **Bolha silenciosa como default**, variante expandida como experimento | `sdk.js:93-121` já tem a variante; é config, não código (W3.8) |
| Q5 | Teaser nesta onda | **Sim**, Onda 3 | W3.8 |
| Q6 | Dark default `auto` | **Sim** | `sdk/sdk.js:74` (W4.3) |
| Q7 | Som e piscar do título | **Som desligado por inbox; piscar ligado** | W4.6 |
| Q8 | Rótulo de IA persistente | **Sim** | W3.9 |

### 0.3 Medições próprias desta task — e três divergências com o estudo

Rodei o levantamento de novo antes de planejar, porque um plano de execução não pode se apoiar em
número de terceiro sem reconferir. Três resultados mudam o plano.

**DIVERGÊNCIA 1 — o SDK não é campo minado.**
O 15 §B12.3 classifica `sdk/IFrameHelper.js` como 🔴 **campo minado** ("10 commits; é a ponte,
mexer aqui quebra o contrato dos dois lados"). Os 10 commits são a história de 36 meses. Medindo o
que interessa — o que o upstream mexeu **desde a nossa base** — o resultado é outro
[MEDIDO nesta task, `git diff --numstat v4.12.1 v4.16.2 -- <arquivo>` e
`git log --oneline v4.12.1..v4.16.2 -- <arquivo>`]:

| Arquivo | v4.12.1 → v4.16.2 | Commits no intervalo |
|---|---|---:|
| `app/javascript/sdk/sdk.js` | **0 / 0** | 0 |
| `app/javascript/sdk/IFrameHelper.js` | **0 / 0** | 0 |
| `app/javascript/sdk/bubbleHelpers.js` | **0 / 0** | 0 |
| `app/views/widgets/show.html.erb` | **0 / 0** | 0 |
| `app/models/channel/web_widget.rb` | **0 / 0** | 0 |
| `app/javascript/widget/assets/scss/views/_conversation.scss` | **0 / 0** | 0 |
| `app/javascript/widget/components/ChatHeader.vue` | **0 / 0** | 0 |
| `app/javascript/widget/components/ChatHeaderExpanded.vue` | **0 / 0** | 0 |
| `app/javascript/widget/components/ChatSendButton.vue` | **0 / 0** | 0 |
| `app/javascript/widget/components/HeaderActions.vue` | **0 / 0** | 0 |
| `app/javascript/widget/components/ConversationWrap.vue` | **0 / 0** | 0 |
| `app/javascript/widget/components/AgentMessageBubble.vue` | **0 / 0** | 0 |
| `app/javascript/widget/components/AgentTypingBubble.vue` | **0 / 0** | 0 |
| `app/javascript/widget/components/AgentMessage.vue` | **0 / 0** | 0 |
| `app/javascript/widget/views/Messages.vue` · `views/Home.vue` | **0 / 0** | 0 |
| `app/javascript/widget/components/layouts/ViewWithHeader.vue` | **0 / 0** | 0 |
| `app/javascript/widget/store/modules/appConfig.js` | **0 / 0** | 0 |
| `app/javascript/widget/helpers/utils.js` | **0 / 0** | 0 |
| `app/javascript/widget/components/ChatInputWrap.vue` | +12 −9 | 2 |
| `app/javascript/widget/components/ChatFooter.vue` | +37 −12 | 1 |
| `app/javascript/widget/components/PreChat/Form.vue` | +39 −33 | 1 |
| `app/javascript/widget/assets/scss/woot.scss` | +30 −4 | 5 |
| `app/javascript/widget/components/UserMessage.vue` | +3 −4 | 1 |
| `app/javascript/widget/components/UserMessageBubble.vue` | +4 −4 | 1 |
| `app/javascript/widget/App.vue` | +4 −0 | 1 |
| `theme/colors.js` | +8 −0 | 2 |
| `tailwind.config.js` | +21 −14 | 2 |
| `vite.config.ts` | +8 −108 | 3 |

**Consequência para o plano:** o SDK inteiro (`sdk.js`, `IFrameHelper.js`, `bubbleHelpers.js`) é
**zona segura 🟢**, não campo minado. Isso libera três coisas que o 16 tratava com pinça: injetar
tokens no launcher (W1.9), implementar o teaser no host (W3.8) e corrigir o breakpoint duplicado
(W2.13). Não é permissão para reescrever o SDK — é permissão para mexer nele sem pagar pedágio em
todo merge.

**Consequência ainda maior:** `app/views/widgets/show.html.erb` e `app/models/channel/web_widget.rb`
— os **dois** pontos onde o perfil por inbox e os tokens calculados no servidor entram — também são
🟢 com zero churn. O caminho crítico do plano inteiro passa pelos arquivos mais seguros do
repositório. Isso não é sorte de planejamento; é o que torna a Onda 1 e a Onda 3 baratas.

**DIVERGÊNCIA 2 — o Leaflet já não existe no upstream; o merge resolve de graça.**
O 15 §A4.5 e o 16 A3 tratam `manualChunks: { leaflet: ['leaflet'] }` como dívida a corrigir.
Medido nesta task: a linha está em `vite.config.ts:84-90` do **nosso fork**, e
`git show v4.16.2:vite.config.ts` **não tem `manualChunks`, não tem `leaflet` e não tem
`rollupOptions`** — o upstream reestruturou o build inteiro. A v4.12.1 (nossa base) também não
tinha a linha [MEDIDO: `git show v4.12.1:vite.config.ts | grep -n leaflet` → vazio]. **A linha é
nossa.** Depois do merge da v4.16.2 ela some junto com o arquivo que a hospeda.
Efeito no plano: o item "tirar o Leaflet" deixa de ser uma tarefa de conserto e vira uma tarefa de
**verificação + trava** (W1.15). Ganho medido continua o mesmo: −150.679 B crus / −43.491 gzip
[MEDIDO — 15 §A4.2].

**DIVERGÊNCIA 3 — o build foi reestruturado pelo upstream, e isso reordena a Onda 0.**
[MEDIDO nesta task] O upstream v4.16.2 quebrou `vite.config.ts` em quatro arquivos:

```
vite.config.ts        17 linhas  — app build, importa de vite.shared
vite.lib.config.ts               — build do SDK em IIFE (era BUILD_MODE=library no nosso)
vite.shared.ts                   — aliases + vueOptions (o alias vue.esm-bundler continua lá)
vitest.config.ts                 — config de teste (no nosso fork está DENTRO do vite.config.ts:116-142)
```

Nosso fork tem tudo num `vite.config.ts` de 140+ linhas, com o `test:` embutido. O merge da v4.16.2
nessa área é **substituição estrutural, não merge de linhas**. Portanto: **nenhuma tarefa de build
(Tailwind `content` próprio, gate de peso, chunk de vendor) começa antes do merge.** Fazer antes é
escrever duas vezes.

**Medição 4 — o inventário de `n-brand` é maior do que o relatado.**
O 15 §A3.4 diz "23 ocorrências". Medido nesta task:
`grep -rn "n-brand" app/javascript/widget/ app/javascript/shared/ | wc -l` → **25 linhas**;
`grep -rho "n-brand" ... | wc -l` → **29 ocorrências**. A diferença não muda o diagnóstico, mas
muda a estimativa de trabalho de W1.5 — e a lista completa está na §A.1, porque um plano precisa da
lista, não do total.

**Uma quarta divergência aparece na §C.9** e vale ser anunciada aqui, porque muda uma tarefa de
"implementar" para "verificar": o **foco automático no campo ao abrir já está implementado**
(`ChatInputWrap.vue:63-68,73-78`). O 12 §11 mediu "não observado" — e mediu certo, porque o composer
nem existe no DOM na tela inicial. Detalhe completo na §C.9.

**Medição 5 — o grafo eager continua o mesmo.**
`public/vite/.vite/manifest.json`, entrada `entrypoints/widget.js`, soma de entry + 13 imports
estáticos + 1 CSS = **2.578.444 bytes crus** [MEDIDO nesta task]. O 15 §A4.2 reportou 2.579.866 —
a diferença de 1.422 B é o CSS de `useBranding`, que ele contou e eu não. **Os hashes dos arquivos
são os mesmos** (`widget-D0AtGYyS.js`, `widget-EcEcykJV.css`, `leaflet-58r2EQLt.js`): o build de
`public/vite/` não mudou desde a medição do estudo, então todos os números de peso do 15 §A4
continuam válidos.

### 0.4 A regra estrutural que atravessa o plano inteiro

Quatro linhas, herdadas do 16 §6.1 e do 15 §B12.4, e nenhuma tarefa deste plano as viola:

1. **Componente novo mora em pasta nova.** `widget/ui/`, `widget/message-types/`, `widget/bridge/`
   não existem no upstream → conflito zero, para sempre.
2. **No campo minado, delegar, não reescrever.** `ChatInputWrap.vue` (+12 −9), `ChatFooter.vue`
   (+37 −12) e `PreChat/Form.vue` (+39 −33) viram cascas finas que renderizam componentes de
   `widget/ui/`.
3. **Tokens em arquivo próprio.** `widget/assets/scss/_tokens.scss` (novo). `woot.scss` fica só com
   o `@import` — é o pior arquivo possível para tokens: o upstream mexeu +30 −4 em 5 commits **e**
   o fork já reescreveu 32 linhas [MEDIDO — 15 §B12.1].
4. **`store/modules/conversation/` não se toca por motivo visual.** É o módulo que o upstream mais
   mexeu (+51 −8 em `actions.js`, +29 em `mutations.js`). Agrupamento de mensagens vai em getter
   novo, arquivo separado (W2.5).

---

# A. FUNDAÇÃO

O que precisa existir antes de qualquer pixel novo. Três frentes: cor→token, ponto de injeção,
refatorações que evitam conflito.

## A.1 Inventário completo de cor literal — varredura própria

Varri `app/javascript/widget/`, `app/javascript/sdk/` e `app/javascript/shared/` em 12/08/2026.
Cinco famílias. **Cada linha tem destino declarado.** Nenhuma delas sobrevive à Onda 1 sem virar
token — e é essa lista, não o total, que faz W1.5/W1.6/W1.9 serem executáveis.

### A.1.1 Família 1 — `*-n-brand`, que resolve para o literal `#2dc46f`

`bg-n-brand` resolve por `theme/colors.js:227` → `brand: '#2dc46f'`, **um literal**: não passa por
`var()`, não muda com tema, não muda com inbox [FATO]. **25 linhas / 29 ocorrências**
[MEDIDO nesta task]. O arquivo fica na **raiz do repositório** (`theme/colors.js`), não em
`app/javascript/` — conferido em 12/08/2026 no HEAD `ee87f5e799`.

| # | `arquivo:linha` | Uso hoje | Vira |
|---|---|---|---|
| 1 | `widget/components/ChatHeader.vue:28` | `bg-n-brand` no `<header>` | `bg-w-brand` (ou `bg-w-surface` se Q2=neutro) |
| 2 | `widget/components/ChatHeaderExpanded.vue:34` | `bg-n-brand` | idem |
| 3 | `widget/components/ChatSendButton.vue:27` | `bg-n-brand hover:bg-[#1FB85A]` | `bg-w-brand hover:bg-w-brand-hover` — **dois** literais numa linha |
| 4 | `widget/components/ChatInputWrap.vue:132` | `border-n-brand shadow-focus` no foco | `border-w-brand-border` + anel `--w-focus-ring` |
| 5 | `widget/components/ChatInputWrap.vue:167` | `text-n-brand` (ícone de emoji ativo) | `text-w-brand-readable` |
| 6 | `widget/components/FileBubble.vue:85` | `text-n-brand` (ícone de arquivo, 2,5rem) | `text-w-brand-readable` |
| 7 | `widget/components/FileBubble.vue:89` | `text-n-brand` (link de download) | `text-w-brand-readable` |
| 8 | `widget/components/UnreadMessageList.vue:122` | `text-n-brand` (botão de ler) | `text-w-brand-readable` |
| 9 | `widget/components/PreChat/Form.vue:266` | `[&>p>.link]:text-n-brand` | `text-w-brand-readable` |
| 10 | `widget/components/Form/PhoneInput.vue:169` | `focus-within:outline-n-brand focus-within:ring-n-brand` | `--w-focus-ring` |
| 11 | `widget/components/template/EmailInput.vue:109` | `focus:outline-n-brand` | `--w-focus-ring` |
| 12 | `widget/assets/scss/woot.scss:78` | `focus:outline-n-brand focus:ring-1 focus:ring-n-brand` — **todo `input`/`textarea` do iframe** | `--w-focus-ring` |
| 13 | `widget/assets/scss/woot.scss:94` | idem para `select` | `--w-focus-ring` |
| 14 | `widget/assets/scss/woot.scss:123` | `.button` = `bg-n-brand border-n-brand text-white` | `bg-w-brand border-w-brand text-w-on-brand` — **e o `text-white` sai junto** |
| 15 | `widget/assets/scss/woot.scss:127` | `.button:hover` = `border-n-brand brightness-110` | `--w-brand-hover` — `brightness()` é filtro, invalida o contraste calculado (regra C10) |
| 16 | `widget/assets/scss/woot.scss:132` | `.button:active` = `border-n-brand brightness-125` | `--w-brand-active` |
| 17 | `widget/assets/scss/views/_conversation.scss:185` | `.chat-bubble > a { text-n-brand }` | `text-w-brand-readable` |
| 18 | `widget/assets/scss/views/_conversation.scss:205` | `.chat-bubble.agent .link { text-n-brand }` | `text-w-brand-readable` — **é a falha medida de 2,27:1** [MEDIDO — 15 §A5.4] |
| 19 | `shared/components/Button.vue:34` | `bg-n-brand hover:brightness-110` | `bg-w-brand hover:bg-w-brand-hover` |
| 20 | `shared/components/Spinner.vue:16` | `before:!border-t-n-brand` | `--w-brand-readable` |
| 21 | `shared/components/ChatOption.vue:44` | `border-n-brand` (chip de resposta rápida) | `border-w-brand-border` |
| 22 | `shared/components/CustomerSatisfaction.vue:122` | `border-t-n-brand` | `border-w-brand-border` |
| 23 | `shared/components/CustomerSatisfaction.vue:191` | `focus:outline-n-brand` | `--w-focus-ring` |
| 24 | `shared/components/CardButton.vue:60` | `text-n-brand` | `text-w-brand-readable` |
| 25 | `shared/components/ui/MultiselectDropdownItems.vue:167` | `focus:border-n-brand` | `--w-focus-ring` — **[INFERÊNCIA]** nenhum arquivo de `widget/` importa `MultiselectDropdown`; o componente entra no CSS do widget pelo glob `shared/**/*.vue` do Tailwind, não por render. Migrar por higiene, não por bug |

**Nota sobre a fonte do literal.** `brand: '#2dc46f'` não é erro nosso: o upstream tem
`brand: '#2781F6'` — também literal — em `theme/colors.js:229` da v4.16.2 [MEDIDO nesta task]. O
fork só trocou o valor, no commit `c42a446322` [MEDIDO — 15 §A3.3]. **Herdamos o erro e pintamos de
verde.** Consequência prática: substituir `n-brand` por `w-brand` é divergir do upstream num arquivo
que ele mexe (`theme/colors.js`, +8 −0 em 2 commits). Mitigação em W1.4: **não remover** a chave
`brand` do `theme/colors.js`; **acrescentar** o namespace `w-*` ao lado. O upstream continua
mergeando limpo e o widget deixa de usar a chave dele.

### A.1.2 Família 2 — hex literal fora do Tailwind

| # | `arquivo:linha` | Literal | Vira |
|---|---|---|---|
| 26 | `sdk/sdk.js:3` | `--b-100: #F2F3F7` | `--w-border` do host (W1.9) |
| 27 | `sdk/sdk.js:4` | `--s-700: #37546D` | `--w-on-brand` — hoje é o "texto escuro quando a marca é clara", decidido por `isWidgetColorLighter` |
| 28 | `sdk/sdk.js:42` | `.woot-widget-bubble { background: #2dc46f }` | `var(--w-brand)` |
| 29 | `sdk/sdk.js:85` | badge `background: #ff4040` | `var(--w-danger)` |
| 30 | `sdk/sdk.js:89` | badge `border: 2px solid #ffffff` | `var(--w-surface)` |
| 31 | `sdk/sdk.js:103` | `.woot-widget--expanded div { color: #fff }` | `var(--w-on-brand)` |
| 32 | `sdk/sdk.js:132` | `.woot-widget-bubble:hover { background: #2dc46f }` | `var(--w-brand-hover)` — **ver a armadilha abaixo** |
| 33 | `sdk/sdk.js:161` | `.woot--close::before/::after { background-color: #fff }` | `var(--w-on-brand)` |
| 34 | `sdk/bubbleHelpers.js:46` | `bubblePath.setAttributeNS(null,'fill','#FFFFFF')` — o ícone do launcher | `currentColor`, herdando `--w-on-brand` |
| 35 | `widget/components/ChatSendButton.vue:27` | `hover:bg-[#1FB85A]` | `bg-w-brand-hover` (já contado em #3) |
| 36 | `widget/components/ImageBubble.vue:41` | `linear-gradient(-180deg, transparent 3%, #1f2d3d 130%)` — véu sob o horário da imagem | token `--w-scrim` novo, ou `color-mix` sobre `--w-text` |
| 37 | `widget/assets/scss/woot.scss:99` | seta do `<select>` em data-URI com `fill: rgb(110,111,115)` cravado na string | SVG com `currentColor`, ou `mask-image` + `background-color: var(--w-text-muted)` |
| 38 | `widget/assets/images/logo.svg:8,9` | `#2dc46f` + `#FFFFFF` | asset — trocar no W1.16 |
| 39 | `widget/assets/images/message-send.svg:7` | `#999A9B` | asset — some quando o botão de enviar virar ícone tokenizado (W2.9) |

> **A armadilha do `:hover` do launcher — ler antes de executar W1.9.**
> Hoje `sdk.js:132` reaplica `#2dc46f` no hover, mas isso **não aparece na tela**: `IFrameHelper.js:334`
> escreve `chatIcon.style.background = widgetColor` **inline**, e estilo inline vence regra de folha
> sem `!important` [INFERÊNCIA — leitura de código + o launcher medido em `rgb(0,156,224)` no
> 15 §A3.3, inclusive em hover]. **O literal está morto hoje e ressuscita no momento exato em que a
> tarefa W1.9 remover o `:style` inline em favor da variável CSS.** Se W1.9 for executada pela
> metade — variável no `:root` do host, inline removido, `sdk.js:132` esquecido — o launcher fica
> na cor da inbox e **fica verde ao passar o mouse**. Este é o bug mais provável de toda a Onda 1.
> Aceite de W1.9 tem uma asserção só para ele.

### A.1.3 Família 3 — `white`/`black` como cor (utilitário Tailwind, não token)

**29 linhas** [MEDIDO nesta task]. São o outro lado do mesmo problema: onde a cor de marca é fixa, a
cor **sobre** ela também é.

| Onde | Linhas | Vira |
|---|---|---|
| `widget/components/ChatHeader.vue` | 35 (`text-white` na seta de voltar), 45 (título), 50 (`bg-white/80` no ponto de online), 57 (`text-white/80` no status) | `text-w-on-brand`; o `/80` vira token próprio, **nunca `opacity` sobre a marca** (regra C10 do 16 §2.5.1) |
| `widget/components/ChatHeaderExpanded.vue` | 50, 54 | `text-w-on-brand` |
| `widget/components/HeaderActions.vue` | 94, 101, 110 (os três ícones de ação) | `text-w-on-brand` |
| `widget/components/ChatSendButton.vue` | 29 | `text-w-on-brand` |
| `widget/components/AgentMessageBubble.vue` | 98 (`bg-white dark:bg-n-solid-3`) | `bg-w-surface-raised` |
| `widget/components/AgentTypingBubble.vue` | 12 | `bg-w-surface-raised` |
| `widget/components/ChatInputWrap.vue` | 130 (`bg-white dark:bg-n-solid-2`) | `bg-w-surface` |
| `widget/components/UnreadMessage.vue` | 96 | `bg-w-surface-raised` |
| `widget/views/ArticleViewer.vue` | 13 (`bg-white h-full` — **sem variante dark**) | `bg-w-surface` — é bug de dark mode hoje, não só de token |
| `widget/components/Banner.vue` | 37 | `text-w-on-brand` |
| `widget/components/GroupedAvatars.vue` | 25 | `text-w-on-brand` |
| `widget/components/VideoBubble.vue` · `ImageBubble.vue` | 23 · 58 | sobre-imagem: continua branco, mas por token `--w-on-scrim` |
| `widget/components/UserMessageBubble.vue` | 42, 46, 49 | `text-w-on-brand` |
| `widget/assets/scss/views/_conversation.scss` | 98, 102 (ícone e download de anexo do visitante), 176 (`.chat-bubble` base: `text-white`), 197 (`> a` na bolha do visitante) | `text-w-on-brand` — a linha 176 é a raiz: **todo** balão nasce com texto branco |
| `widget/assets/scss/woot.scss` | 123 | `text-w-on-brand` |
| `shared/components/Button.vue` | 28 | `text-w-on-brand` |
| `shared/components/ui/MultiselectDropdown.vue` | 104 (`dark:bg-[#233138]`) | não consumido pelo widget — higiene |

### A.1.4 Família 4 — `rgba()` literal (sombra, textura, véu)

| `arquivo:linha` | Literal | Vira |
|---|---|---|
| `widget/assets/scss/views/_conversation.scss:176` | `shadow-[0_0.25rem_6px_rgba(50,50,93,0.08),0_1px_3px_rgba(0,0,0,0.05)]` — **idêntico nos dois temas** [MEDIDO — 15 §A3.5] | **removido**: a sombra sai do balão (16 §2.4). Só 2 de 9 concorrentes têm sombra no balão — a Huggy e nós [MEDIDO — 11 §C9] |
| `widget/components/ConversationWrap.vue:140` | `linear-gradient(rgba(0,0,0,.85), rgba(0,0,0,.85))` + `url('/assets/images/chat-spx-background.png')` | `--w-surface-sunken` + textura tokenizada |
| `widget/components/ConversationWrap.vue:158-159` | idem em branco, tema claro | idem |
| `widget/components/ChatFooter.vue:118` | `shadow-[0px_-20px_20px_1px_rgba(0,0,0,0.05)]` + variante dark | `--w-elev-1` |
| `widget/components/layouts/ViewWithHeader.vue:115` | `shadow-[0_10px_15px_-16px_rgba(50,50,93,0.08),…]` | `--w-elev-1` |
| `sdk/sdk.js:8` | `.woot-widget-holder { box-shadow: 0 5px 40px rgba(0,0,0,.16) }` | `--w-elev-3` |
| `sdk/sdk.js:46` | launcher `0 8px 24px rgba(0,0,0,.16)` — **uma camada só**; 5 de 9 usam duas [MEDIDO — 11 §C5] | `--w-elev-2`, duas camadas |
| `sdk/sdk.js:133` | hover `0 8px 32px rgba(0,0,0,.4)` — salto de opacidade de 0,16 → 0,40, **e `box-shadow` nem está na lista de `transition`**, então a mudança é instantânea [MEDIDO — 12 §3.1] | `--w-elev-2-hover` + `scale(1.1)` em 150 ms (W2.12) |

### A.1.5 Família 5 — cor por `:style` inline, calculada pelo YIQ

Este é o mecanismo que **funciona parcialmente hoje** e que precisa ser desligado por inteiro — não
porque não pinta, mas porque pinta com uma heurística errada. `getContrastingTextColor` é YIQ com
limiar 186 [FATO — `node_modules/@chatwoot/utils/src/helpers.ts:9-15`], **não verifica se o
resultado atinge razão alguma**, e diverge da regra WCAG em 11 de 16 cores de marca testadas
[MEDIDO — 13 §3.2].

| Componente | Linhas | O que faz |
|---|---|---|
| `widget/components/UserMessageBubble.vue` | 25 (calcula), 35 (`:style="{ background: widgetColor, color: textColor }"`) | **a falha de 3,07:1** [MEDIDO — 15 §A5.4] |
| `widget/components/UserMessage.vue` | 47, 129, 134 (`:style="{ backgroundColor: widgetColor }"`), 159 | fundo de anexo |
| `widget/components/FileBubble.vue` | 18, 37, 39-40, 56, 63, 72 | ícone/nome/download |
| `widget/components/ChatFooter.vue` | 32, 37-38, 137-138 | botão "Iniciar nova conversa" |
| `widget/components/template/EmailInput.vue` | 36, 38-39, 94-96 | botão do card de e-mail |
| `widget/components/template/IntegrationCard.vue` | 22-24, 59-61 | botão do card de integração |
| `widget/components/PreChat/Form.vue` | 50, 59-60, 318-319 | botão de submit |
| `widget/components/TeamAvailability.vue` | 14, 36 | CTA "Iniciar conversa" |
| `widget/components/pageComponents/Home/Article/ArticleBlock.vue` | 15, 41 | link "ver todos" |
| `widget/components/UnreadMessageList.vue` | 27, 34, 93 | cor do texto na prévia |
| `shared/components/ChatForm.vue` | 29, 31-32, 144-146 | botão |
| `shared/components/CustomerSatisfaction.vue` | 43, 54-55, 123, 158-160 | borda + botão |
| `shared/components/ChatOption.vue` | 19, 34, 37 | chip |
| `shared/components/CardButton.vue` | 16, 18-19, 48-50, 61 | botão de card |
| `shared/components/Button.vue` | 16, 46-47 | props `bgColor`/`textColor` |
| `sdk/IFrameHelper.js` | 321 (`isWidgetColorLighter`), 334, 335 | launcher e botão de fechar, **no host** |

**Total da família 5: 16 arquivos.** Todos passam a ler `var(--w-brand)` / `var(--w-on-brand)` do
CSS. O `getContrastingTextColor` sai do widget inteiro; `isWidgetColorLighter` sai do SDK.

### A.1.6 O caso da variável que ninguém lê

```
inbox.widget_color (banco)
  → app/views/widgets/show.html.erb:16   window.chatwootWebChannel.widgetColor
    → App.vue:82-85                      setWidgetColor() + setWidgetColorVariable()
      → App.vue:118-125                  documentElement.style.setProperty('--widget-color', …)
        → (nada)
```

`grep -rn -- "--widget-color" app/` devolve **uma** ocorrência: a escrita [MEDIDO — 15 §A3.3,
reconferido nesta task]. **Zero consumidores em CSS.** O mecanismo está certo — o iframe nos dá um
`:root` que é só nosso, e a variável chegou corretamente em todas as medições do 15 — mas ninguém
plugou o outro lado. W1.1+W1.2 plugam.

---

## A.2 Onde os tokens são injetados

O widget roda em iframe. Isso dá uma vantagem e cria uma obrigação.

**A vantagem:** o `document` é nosso. `:root` não colide com o site do cliente, o CSS do host não
entra, e a configuração já chega **antes do primeiro paint** — `window.chatwootWebChannel` é escrito
inline em `app/views/widgets/show.html.erb:8-32`, antes de `vite_javascript_tag 'widget'`
(`show.html.erb:35`) [FATO].

**A obrigação:** o launcher vive **fora** do iframe, no `document` do site do cliente, criado por
`sdk/bubbleHelpers.js:28-62` e montado por `sdk/IFrameHelper.js:302-340` [FATO]. Ele não alcança o
`:root` do widget. **São dois pontos de injeção, uma fonte só.**

### Decisão: o servidor calcula, os dois lados recebem pronto

```
                    ┌──────────────────────────────────────────┐
                    │  Ruby: WidgetTokens.for(web_widget)      │  ← fonte única
                    │  luminância relativa WCAG, limiar 0,17913│
                    └───────────────┬──────────────────────────┘
                                    │
              ┌─────────────────────┴────────────────────────┐
              ▼                                              ▼
  show.html.erb  →  <style>:root{--w-brand:…}</style>   channelConfig.tokens
  (dentro do iframe, 1º byte de HTML)                        │
                                                             ▼
                                          widget/App.vue → IframeEventHelper.loadedEventConfig()
                                          (helpers/IframeEventHelper.js:1-9, já manda channelConfig)
                                                             ▼
                                          sdk/IFrameHelper.js:158-198 evento `loaded`
                                          → IFrameHelper.onLoad({ tokens })
                                          → grava as vars no bubbleHolder do host
```

**Por que no servidor, e não em JS dos dois lados** [15 §B7.4]: duplicar a fórmula de contraste em
Ruby e em JS é risco de divergência silenciosa — o dia em que uma das duas mudar, o launcher e o
header discordam de novo, que é exatamente o bug que estamos consertando. O servidor calcula uma vez
e os dois lados consomem.

**Por que no ERB, e não no `mounted()`**: elimina o flash de cor errada entre o primeiro paint e o
`App.vue:81`. Hoje o widget pinta verde e depois corrige — em conexão lenta isso é visível.

**Detalhes de execução que não podem ser esquecidos:**

- O canal já carrega a configuração inteira do widget para o SDK: `IFrameHelper.js:181` lê
  `message.config.channelConfig.widgetColor` [FATO]. Acrescentar `tokens` ao mesmo objeto **não
  muda o contrato do postMessage** — é campo novo num payload existente.
- O launcher hospeda as variáveis em `bubbleHolder` (`sdk/bubbleHelpers.js:16`,
  `id="cw-bubble-holder"`), **não** no `:root` do site do cliente. Escrever no `:root` do host é
  poluição do documento alheio, e um site com um `--w-brand` próprio nos sobrescreveria.
- `sdk/DOMHelpers.js` já injeta a folha (`loadCSS()`, chamado em `IFrameHelper.js:62`); as
  variáveis entram como um segundo `<style>` ou via `style.setProperty` no holder.
- O ERB precisa escapar a cor. `widget_color` é `string` livre no banco
  (`db/schema.rb`, `channel_web_widgets.widget_color`, default `#1f93ff`) e hoje é interpolada em
  `show.html.erb:16` dentro de aspas simples de JS. Emitir num `<style>` cria um vetor novo de
  injeção de CSS. **O helper Ruby valida o formato `#RRGGBB` e cai para o default se não bater** —
  não interpola string do banco em CSS sem validar. Item explícito no aceite de W1.2.

---

## A.3 As duas refatorações que vêm antes

O 15 §15.4/§15.8 explica por quê, e o motivo é o mesmo nas duas: **uma cadeia de `else if` e um
`v-if` composto garantem conflito de merge por construção; um mapa isola o conflito numa linha.**

### A.3.1 `App.vue:258-345` → mapa de handlers (`widget/bridge/`)

Hoje: `window.addEventListener('message', …)` com **16 ramos** — 1 `if` + 15 `else if` [MEDIDO —
15 §A2.4, reconferido nesta task lendo `App.vue:258-345`]:

`config-set` · `widget-visible` · `change-url` · `toggle-close-button` · `push-event` ·
`set-label` · `remove-label` · `set-user` · `set-custom-attributes` · `delete-custom-attribute` ·
`set-conversation-custom-attributes` · `delete-conversation-custom-attribute` · `set-locale` ·
`set-color-scheme` · `toggle-open` · `SDK_SET_BUBBLE_VISIBILITY`

**O padrão certo já existe no repositório, do outro lado da ponte.** `sdk/IFrameHelper.js:104-117`
usa dicionário: `typeof IFrameHelper.events[message.event] === 'function'` [FATO]. Só o lado do
widget ficou com a escada.

Por que **antes** e não depois: toda tarefa da Onda 3 acrescenta evento nessa cadeia (perfil,
teaser, tracking). Acrescentar `else if` num bloco de 87 linhas que o upstream também edita
(`App.vue` +4 −0 desde a base) é onde o merge quebra. Com o mapa, cada evento novo é um arquivo novo
em `widget/bridge/handlers/` — risco ⚪.

**Ganho colateral que não é estético:** `widget/helpers/utils.js:18-21` valida **apenas o prefixo da
string** e **não verifica `e.origin`** [FATO]; e `utils.js:8-13` faz `postMessage(..., '*')` com
`targetOrigin` curinga. O bridge dá o ponto único onde os dois se corrigem — é o defeito **B4** do
`DECISOES.md`, e o lado do SDK já faz certo (`IFrameHelper.js:96-98` calcula o `targetOrigin` a
partir do `src` do iframe).

### A.3.2 `AgentMessageBubble.vue` → `<component :is>` + registry

Hoje: 8 computeds booleanos (`:42-67`), 6 blocos `v-if` (`:92-152`) e uma condição de exclusão que é
literalmente [FATO — 15 §A6.2]:

```html
v-if="!isCards && !isOptions && !isForm && !isArticle && !isCards && !isCSAT"
```

`!isCards` **duplicado**; `!isIntegrations` e `!isTemplateEmail` **ausentes** — esses dois renderizam
*dentro* da bolha de texto, inconsistente com os outros seis. Adicionar um `content_type` hoje exige
três edições em lugares distintos.

Depois: `widget/message-types/index.js` mapeia os oito tipos suportados
(texto, `input_email`, `integrations`, `input_select`, `form`, `cards`, `article`, `input_csat`
[FATO — `AgentMessageBubble.vue:42-67,92-152`]) e a bolha vira
`<component :is="resolve(contentType)" v-bind="…" />`. Tipo novo = um arquivo + uma linha no mapa.

Por que **antes**: a Onda 3 precisa de tipos novos (cartão de handoff, seletor de intenção,
CTA de WhatsApp). Sem o registry, cada um deles reabre o `v-if` composto.

---

## A.4 Estrutura de pastas nova — a defesa de merge

Quatro pastas que **não existem no upstream** [16 §P6]. Conflito zero por construção, e é isso que
transforma "o widget virou nosso" de dívida permanente em custo pago uma vez.

```
app/javascript/widget/
├── assets/scss/
│   └── _tokens.scss              ⚪ NOVO — toda a §2 do relatório 16
├── bridge/                       ⚪ NOVO
│   ├── index.js                     mapa {evento: handler} + validação de e.origin
│   └── handlers/                    um arquivo por evento
├── message-types/                ⚪ NOVO
│   ├── index.js                     registry de content_type
│   └── *.vue                        um componente por tipo
├── ui/                           ⚪ NOVO — primitivos sem regra de negócio
│   ├── WButton.vue  WIconButton.vue  WBubble.vue   WAvatar.vue
│   ├── WSurface.vue WSpinner.vue     WField.vue    WSkeleton.vue
│   ├── WTypingDots.vue  WBanner.vue  WComposer.vue WTeaserCard.vue
│   └── WScrollToBottom.vue
└── composables/
    └── useMessageGrouping.js     ⚪ NOVO — isFirstOfGroup/isLastOfGroup fora do store
```

**Duas regras verificáveis por lint, não por convenção** [15 §B8.3]:

1. Nenhum arquivo de `widget/ui/` importa de `dashboard/`.
2. Nenhum arquivo de `widget/ui/` contém cor literal (hex, `rgb(`, `bg-white`, `text-black`).

A segunda regra é o que impede o problema de voltar. Sem ela, daqui a seis meses tem `#1FB85A` de
novo — o `#1FB85A` de hoje aparece em 15 lugares do repositório, e só 1 dentro do widget
[MEDIDO — 15 §A3.3], o que mostra exatamente como esse tipo de literal se espalha.

**E uma casca fina em cada arquivo do campo minado:**

| Campo minado 🔴 | Churn desde v4.12.1 | Vira |
|---|---|---|
| `widget/components/ChatInputWrap.vue` | +12 −9, 2 commits | casca → `widget/ui/WComposer.vue` |
| `widget/components/ChatFooter.vue` | +37 −12, 1 commit | casca → `WComposer` + `WButton` |
| `widget/components/PreChat/Form.vue` | +39 −33, 1 commit | **só tokens nesta onda**; conversacional em W3.5, em arquivo novo |
| `widget/assets/scss/woot.scss` | +30 −4, 5 commits | reduzido a `@import` de `_tokens.scss` + `_reset.scss` |

---

# B. PERFIL POR INBOX

Decisão do Walisson, já tomada. Esta seção define **como** se executa sem transformar o widget em
dois widgets.

## B.1 A regra que evita o desastre

> **O perfil é um preset de configuração e uma regra de visibilidade de campos. Nunca um segundo
> caminho de código no widget.**

O widget **não lê o nome do perfil** para decidir o que renderizar. Ele lê **flags planas**. O
servidor resolve o perfil em flags e entrega o resultado. Três razões, nesta ordem:

1. **Merge.** `if (profile === 'marketing')` espalhado em 15 componentes é a mesma doença do
   `else if` de 16 ramos (§A.3.1), com o agravante de estar dentro de arquivos que o upstream mexe.
2. **Teste.** A matriz de regressão visual é 4 views × 2 temas × 2 viewports = 16 snapshots
   [15 §B11.2]. Com ramificação por perfil dentro dos componentes, vira 32 — e cada componente
   precisa de dois casos de teste. Com flags planas, o snapshot testa a **combinação de flags**, e
   as combinações que importam são poucas.
3. **Produto.** Cliente sempre quer o híbrido: perfil marketing **com** base de conhecimento, perfil
   suporte **com** teaser. Se o perfil for um caminho de código, o híbrido é impossível sem uma
   terceira branch. Se for preset, o híbrido é o cliente desmarcando uma caixa.

**Corolário duro, e é o que garante deploy sem susto:**

> **O perfil nunca reescreve coluna que já existe em inbox já criada.**

`csat_survey_enabled`, `continuity_via_email`, `pre_chat_form_enabled`, `pre_chat_form_options` e as
5 flags de `feature_flags` já têm valor gravado em cada inbox da frota. O perfil só governa:
(a) o **default proposto na UI ao criar inbox nova**, (b) a **visibilidade dos campos** na tela de
configuração, e (c) os **campos que só nascem agora** (teaser, KB no widget, CTA de WhatsApp, forma
da tela inicial). Para tudo que já existe, o valor gravado vence o perfil, sempre.

> **ARBITRADO — PLANO-MESTRE §5 A3: são três regimes, e este corolário governa o segundo.**
> (1) **Inbox nova** — o perfil semeia os defaults na criação (serviço de seed, plano 24 §9.4);
> (2) **inbox existente** — trocar o perfil **propõe**: abre um diálogo listando nominalmente cada
> mudança, com caixas marcáveis, e grava **só o que o administrador confirmar** (tela do plano 23
> §B.1.4, com a garantia deste corolário); nada é escrito em silêncio e nada é apagado — a
> configuração do perfil anterior fica no banco, inerte, e volta se o perfil voltar;
> (3) **campos que só nascem agora** — resolvidos em runtime pelo perfil (`WidgetProfile.resolve` →
> flags planas da §B.3) até o cliente sobrescrever.

## B.2 Onde o perfil é armazenado

> **ARBITRADO — PLANO-MESTRE §5 A1: `inbox.additional_attributes`, com três chaves de topo —
> `widget_profile`, `widget_triggers`, `widget_tracking` — declaradas numa única edição do strong
> params. Sem coluna nova, sem migration, sem bit de `feature_flags`.** A recomendação original desta
> seção (coluna `widget_profile` em `channel_web_widgets`) **não vale mais**, e com ela cai a
> migration e a entrada em `EDITABLE_ATTRS`.

Estado atual da tabela [FATO — `db/schema.rb`, `create_table "channel_web_widgets"`;
anotação em `app/models/channel/web_widget.rb:1-27`]:

```
website_url · account_id · website_token · widget_color (default "#1f93ff") ·
welcome_title · welcome_tagline · feature_flags (int, default 7) · reply_time (int) ·
hmac_token · pre_chat_form_enabled · pre_chat_form_options (jsonb) · hmac_mandatory ·
continuity_via_email · allowed_domains
```

| Opção | Veredito |
|---|---|
| **(a) `inbox.additional_attributes['widget_profile']`** | **Escolhida (A1).** O ERB já tem a inbox na mão (`show.html.erb` usa `@web_widget.inbox` em doze chaves), `_inbox.json.jbuilder:27` já serializa `additional_attributes` inteiro, e gatilhos e tracking — que são **estrutura**, não escalar — moram no mesmo lugar. Zero migration |
| (b) Coluna `widget_profile` integer + `enum` | **Rejeitada por A1.** Era a recomendação desta seção. Custa migration (risco de colisão de timestamp na frota), `EDITABLE_ATTRS`, jbuilder e ERB — quatro arquivos, três do upstream — e ainda parte a configuração do widget em dois lares com dois formatos |
| (c) Um bit em `feature_flags` | Rejeitada. `has_flags` (`web_widget.rb:50-56`) modela **conjunto de booleanos**, não escolha exclusiva. E o precedente de bitmask estourado na frota desaconselha gastar slot em algo que não é booleano |
| (d) Chave em `pre_chat_form_options` (jsonb) | Rejeitada. Esse jsonb é reescrito por `validate_pre_chat_options` (`web_widget.rb:84-101`) quando `pre_chat_fields` vem vazio — guardar o perfil ali é guardá-lo num campo que o próprio modelo sobrescreve |

**O que se escreve, em vez da migration** (detalhe em `24-plano-backend-dados.md` §9.1 e BK-08):

```ruby
# app/models/inbox.rb — ilustrativo. A linha 50 HOJE é:
#   store_accessor :additional_attributes, :pin_mode, :pinned_conversation_ids
# ela é ESTENDIDA (não substituída), sob pena de quebrar o pin de conversas:
WIDGET_PROFILES = %w[support marketing].freeze
store_accessor :additional_attributes, :pin_mode, :pinned_conversation_ids,
               :widget_profile, :widget_triggers, :widget_tracking
validates :widget_profile, inclusion: { in: WIDGET_PROFILES }, allow_nil: true
```

Valores em inglês (**A2**: `support` | `marketing`), pelo precedente medido do repositório
(`pin_mode` grava `'per_agent'`, `reply_time` é `enum { in_a_few_minutes: 0, … }`); **rótulo em pt-BR
fica no i18n do dashboard**. `nil` é lido como `support` — e a resolução de `support` tem de ser
**byte-idêntica ao comportamento de hoje**, que é o critério de aceite de 3.01 (§B.5).

**Por que três chaves de topo, e não um sub-hash único** (`widget_config`): o update faz
`(@inbox.additional_attributes || {}).merge(…)` — **primeiro nível apenas**
(`inboxes_controller.rb:52-56`). Com uma chave só, um `PATCH` parcial de gatilhos **apagaria** perfil
e tracking. Declarando as três de uma vez na primeira tarefa (3.01), a evolução posterior acontece
**dentro** dos jsonb (hash aberto, `{}`) sem tocar mais no controller — que é o arquivo 🔴 que o
plano 23 (BE-1) queria justamente proteger. *(A ação 2 do `auditoria/35-VEREDITO.md` §7 propõe uma
quarta chave, `widget_appearance`, na mesma edição única; se o mestre a incorporar, ela entra por
esta mesma regra e sem nova edição do controller.)*

**Permitir a edição:** uma linha em `inboxes_controller.rb:217` (o `permit`), declarando as três
chaves de uma vez. **Não** se toca em `Channel::WebWidget::EDITABLE_ATTRS` por causa do perfil — essa
constante só é ampliada pelo pré-chat (bloco 3.12 / `23` T2.1 / `24` BE-6).

**Risco de merge: baixo.** `inbox.rb` já tem o `store_accessor` (`:50`), e `_inbox.json.jbuilder:27`
já devolve `additional_attributes` inteiro — o dashboard recebe de graça. **Custo aceito:**
`additional_attributes` não é tipado nem indexável; mitigação é `store_accessor` + validação de
inclusão + JSON Schema com `json_schemer` (já é dependência, `Gemfile:37`) para gatilhos e tracking,
e um spec de controller cobrindo o `permit`. **Regra dura herdada:** nenhum segredo em
`additional_attributes` — qualquer agente com a inbox atribuída o lê.

## B.3 Como o perfil chega ao widget

O widget lê tudo de `window.chatwootWebChannel`, escrito inline em
`app/views/widgets/show.html.erb:8-32` [FATO]. É onde o perfil resolvido entra — e é o arquivo com
**0 mudanças do upstream** desde a v4.12.1 [MEDIDO nesta task].

```erb
<%# app/views/widgets/show.html.erb — dentro do window.chatwootWebChannel %>
widgetProfile: '<%= @web_widget.inbox.widget_profile || "support" %>',
profileConfig: <%= WidgetProfile.resolve(@web_widget).to_json.html_safe %>,
tokens: <%= WidgetTokens.for(@web_widget).to_json.html_safe %>,
```

O perfil é lido da **inbox** (`additional_attributes['widget_profile']`, A1), não do canal; `nil`
resolve para `support` (A4). O ERB já tem a inbox na mão — `show.html.erb` usa `@web_widget.inbox`
em **12 chaves** [MEDIDO em 12/08/2026, HEAD `ee87f5e799`].

> **LISTA CANÔNICA — `profileConfig`.** Esta tabela é o **único lugar** onde as flags do perfil são
> definidas. Os planos 23 (§B.1.4), 24 (§9.4) e o bloco 3.03 do `PLANO-MESTRE` apontam para cá; quem
> precisar acrescentar, remover ou renomear flag muda **aqui** e em nenhum outro lugar. Regra que a
> sustenta (A3): **o widget lê flags planas, nunca o nome do perfil.**

`profileConfig` é **plano**, sem aninhamento — 11 chaves:

```json
{
  "showKnowledgeBase":    true,
  "showConversationList": true,
  "teaserEnabled":        false,
  "teaserDelayMs":        8000,
  "teaserScrollPercent":  30,
  "captureFlow":          "form",
  "primaryExit":          "none",
  "csatOnResolve":        true,
  "emailContinuity":      true,
  "homeLayout":           "support",
  "aiLabelPersistent":    true
}
```

| Flag | Tipo | Valores | Coluna/campo gravado que ela **reflete** (regime 2 de A3) |
|---|---|---|---|
| `showKnowledgeBase` | booleano | `true`/`false` | — (nasce agora: regime 3) |
| `showConversationList` | booleano | `true`/`false` | — (regime 3) |
| `teaserEnabled` | booleano | `true`/`false` | — (regime 3, vive em `widget_triggers`) |
| `teaserDelayMs` | inteiro | ms | — (regime 3, `widget_triggers`) |
| `teaserScrollPercent` | inteiro | 0–100 | — (regime 3, `widget_triggers`) |
| `captureFlow` | enum | `form` \| `conversational` | deriva de `pre_chat_form_enabled` + `pre_chat_form_options` |
| `primaryExit` | enum | `none` \| `whatsapp` | — (regime 3) |
| `csatOnResolve` | booleano | `true`/`false` | espelha `csat_survey_enabled` gravado |
| `emailContinuity` | booleano | `true`/`false` | espelha `continuity_via_email` gravado |
| `homeLayout` | enum | `support` \| `marketing` | — (regime 3) |
| `aiLabelPersistent` | booleano | `true`/`false` | — (regime 3) |

**Precedência, e é o que impede o bug silencioso:** onde a flag reflete campo já gravado (linhas com
coluna na 4ª coluna), **o valor gravado vence o perfil, sempre** — o perfil só propõe, e só na
criação de inbox nova ou num diálogo de confirmação explícito (A3, regimes 1 e 2). Onde não há valor
gravado (regime 3), o perfil resolve em runtime até o cliente sobrescrever.

O widget consome `profileConfig.showKnowledgeBase`. **Não** consome `widgetProfile` — esse campo
existe só para telemetria e para o rótulo na tela de configuração. Regra verificável por lint:
`grep -rn "widgetProfile" app/javascript/widget/` só pode casar no `configMixin`/store, nunca num
`v-if` de template.

`window.chatwootWebChannel` já atravessa a ponte inteiro: `widget/helpers/IframeEventHelper.js:1-9`
manda `channelConfig: window.chatwootWebChannel` no evento `loaded`, e
`sdk/IFrameHelper.js:181` já lê `message.config.channelConfig.widgetColor` [FATO]. Então o SDK
recebe `profileConfig` **de graça** — o que importa para o teaser, que vive no host.

## B.4 O que muda em cada perfil

Cinco superfícies. Onde a linha diz "igual", é igual de propósito: o perfil muda o mínimo necessário.

| Superfície | **Marketing** (captura) | **Suporte** (atendimento) |
|---|---|---|
| **Tela inicial** (`views/Home.vue`) | Sem lista de artigos. Saudação + **2–4 opções de intenção nomeadas** + CTA único. Nunca "Como posso ajudar?" — NN/g: com 3 exemplos nomeados o usuário decide em 5 s se a ferramenta serve [13 §9.3] | Bloco de artigos no topo (`pageComponents/Home/Article/ArticleContainer.vue`), histórico de conversa, disponibilidade da equipe, CTA "Iniciar conversa" |
| **Abordagem** | **Teaser ligado** por default, gatilho composto **8 s de permanência E 30 % de scroll** [06 §14.2 R8]. Launcher pode usar a variante expandida (`sdk.js:93-121`, já existe no CSS) | **Teaser desligado** por default. Bolha silenciosa. Não se persegue quem já é cliente |
| **Pre-chat** | **Fluxo conversacional**: campos chegam como mensagens, um por vez. Teto de **8 campos no fluxo inteiro** [Baymard, 06 §3.2]. **E-mail OU WhatsApp, nunca os dois** [06 §14.3 R16]. Máscaras BR (celular, CPF, CNPJ, CEP), validando no `blur` | Formulário curto clássico (`components/PreChat/Form.vue`), ou nenhum. E-mail para continuidade |
| **Rodapé / saída** | **CTA de saída para WhatsApp** no rodapé e no fim do fluxo. Justificativa medida: 75,96 % das empresas brasileiras redirecionam para o WhatsApp, e quem redireciona converte **+0,54 p.p. (+20 % relativo)** [FATO — 00-INDICE §3, do 04-players-br] | Continuidade por e-mail ligada; "receber transcrição" (`ChatFooter.vue`, `EMAIL_TRANSCRIPT.BUTTON_TEXT` já traduzido) |
| **Handoff** | Handoff é para **vendas**: a mensagem de sistema nomeia a pessoa e o time. Sem fila visível — em captura, fila afasta | Fila completa: posição a cada 60–90 s, e aos **120 s** o card `[Receber por e-mail] [Receber no WhatsApp] [Continuar esperando]` [06 §6.3] |
| **CSAT** | Desligado por default em inbox nova | Ligado por default em inbox nova, **sempre depois** do encerramento — pedir antes é o padrão problemático nº 4 do NN/g [13 §7.3] |
| **Base de conhecimento** | Oculta no widget | Visível |
| **Tracking** | Camadas de funil ligadas (07, C0–C9) | Só o básico |

**O que é igual nos dois, e não vira opção:** todos os tokens, todo o contraste, todo o movimento,
toda a acessibilidade, todo o comportamento offline, o rótulo de IA e o `Esc` que fecha. Perfil não
é desculpa para ter dois padrões de qualidade.

## B.5 Inbox existente que não tem perfil

> **ARBITRADO — PLANO-MESTRE §5 A1 + A4: não há migration e não há backfill.** Inbox existente fica
> com `widget_profile` **ausente** em `additional_attributes`, e a **leitura derivada** trata `nil`
> como `support` — que é literalmente o comportamento de hoje (widget reativo, sem gatilho, sem
> teaser). Escrever `"support"` em toda inbox da frota seria uma varredura de escrita para produzir
> **zero** diferença de comportamento.

O que precisa ser garantido é que isso não mude nada na tela.

**Critério de aceite, verificável e obrigatório em 3.01** (a tarefa que era W3.1):

1. Rodar os 16 snapshots de regressão visual **antes** do deploy → baseline.
2. Fazer o deploy do código que introduz `WidgetProfile.resolve` (nenhuma escrita no banco).
3. Rodar os 16 snapshots **de novo**, na mesma inbox **sem** `widget_profile` gravado → **zero
   diferença de pixel**.

O aceite vale sobre a **leitura derivada** (`nil` → `support`), não sobre uma migration que deixou de
existir. Se der diferença, `WidgetProfile.resolve` está sobrescrevendo coluna existente e viola a
regra do corolário da §B.1.

E um segundo aceite, para o caminho do cliente que **escolhe** um perfil depois:

4. Numa inbox com `csat_survey_enabled = false` gravado, trocar o perfil para `support` (que propõe
   CSAT ligado) **não liga o CSAT** por conta própria: abre o diálogo do regime 2 (A3), que lista a
   mudança nominalmente e grava **só se o administrador confirmar**. A tela de configuração mostra o
   campo, com o valor gravado, e uma dica de que o perfil sugere outro valor. **A troca é do cliente,
   com um clique consciente — nunca de uma escrita em massa.**

---

# C. COMPONENTE A COMPONENTE

Convenção desta seção: **arquivos** · **o que muda** · **estados a cobrir** · **aceite** (passa ou
falha, verificável) · **esforço** · **risco de merge**. Onde a spec já existe no 16 §3, aqui está a
tradução para execução — não a repetição das medidas.

## C.1 Launcher (bolha)

> **DECISÃO DO PRODUTO — 13/08/2026 (D5). O ícone do lançador ganhou campo, e ganhou um padrão.**
> Ver `PLANO-MESTRE` §2.2 bloco **3.19** (nove asserções) e §4 Onda 2 item 5c. Três pontos:
>
> 1. **`launcher_icon` com três modos** — `default` (o balão de hoje), `image` (upload) e
>    `agent_photo` (reusa o avatar da inbox) —, morando em `widget_appearance` (bloco 3.18). Hoje não
>    existe caminho algum para imagem: `bubbleHelpers.js:10` monta o SVG a partir de um `path` fixo,
>    `:46` crava `fill: '#FFFFFF'` e `:60` traz `title = 'Open chat window'` em inglês.
> 2. **Toda inbox nova nasce com `default`, em qualquer perfil.** O plano anterior previa padrão por
>    perfil (foto no marketing, balão no suporte); **isso caiu**. A única foto que o produto poderia
>    escolher sozinho seria genérica, e foto genérica é pior que balão — a decisão é **nunca** foto
>    de banco de imagem, em nenhum caminho da tela.
> 3. **A tela sugere, em vez de decidir**: enquanto o modo for `default`, a tela de aparência mostra
>    um aviso recomendando subir a foto de alguém do time, com a razão escrita ("rosto converte
>    mais"). Registro da engenharia, sem reabrir a decisão: **o corpus não traz teste comparando
>    foto e balão** — 9 dos 13 lançadores são balão em círculo e só a Leadster usa fotografia, o que
>    é evidência de **desvio**, não de conversão. A frase é [INFERÊNCIA] de mercado; a instrumentação
>    do bloco 4.21 e o A/B do 6.05 são quem podem transformá-la em [MEDIDO], e o texto é uma string
>    de i18n que muda em dez minutos se o dado disser o contrário.

| | |
|---|---|
| **Arquivos** | `sdk/sdk.js:41-145` (CSS), `sdk/bubbleHelpers.js:10-62` (criação do SVG e do `title`), `sdk/IFrameHelper.js:302-340` (montagem, cor, classe `--lighter`) |
| **Risco de merge** | 🟢 — os três com **0 mudanças** do upstream desde a v4.12.1 [MEDIDO nesta task]. Reclassificado do 🔴 do 15 §B12.3 (ver §0.3) |
| **Esforço** | **M** |

**O que muda**

| Item | Hoje | Vira | Âncora |
|---|---|---|---|
| Caixa | 64×64 (`sdk.js:48,52`) | **mantido** | 8 de 9 entre 54 e 65 [11 §C1] |
| Fundo | `#2dc46f` literal (`sdk.js:42`) + inline (`IFrameHelper.js:334`) | `var(--w-brand)` | §A.2 |
| Ícone | SVG 24×24 com `margin: 20px` (`sdk.js:136-141`, `bubbleHelpers.js:35-36`) = **37,5 % do botão** | **32×32**, margem 16 | mercado 43–65 %, mediana ≈52 % — somos o menor da amostra [MEDIDO — 11 §C4] |
| Cor do ícone | `fill: '#FFFFFF'` cravado (`bubbleHelpers.js:46`) | `currentColor` ← `--w-on-brand` | regra C1 |
| Sombra | 1 camada (`sdk.js:46`) | `--w-elev-2`, **2 camadas** | 5 de 9 usam duas [11 §C5] |
| Hover | só sombra 0,16→0,40, **e `box-shadow` não está na lista de `transition`** (`sdk.js:210`) — muda instantaneamente | `scale(1.1)` em **150 ms** `--w-ease-standard` | [MEDIDO — 12 §3.1] |
| Press | **nada** | `scale(0.94)` em **120 ms** `cubic-bezier(.45,0,.2,1)` | somos o único do corpus sem `:active` [MEDIDO — 12 §3.2] |
| Esconder | `translateX(8px) scale(.75) rotate(-30deg)` (`sdk.js:213`) | cross-fade de ícone, **150 ms**, sem rotação | ninguém mais gira o botão [MEDIDO — 12 §15] |
| Badge | `::after` de **12×12 sem número**, `#ff4040`, borda branca (`sdk.js:80-91`) | **20×20** com o número (99+ acima), `--w-danger` | 20×20 é o do tawk.to [11 §A4] |
| Offsets | `bottom: 20px` (`sdk.js:45`), `right: 20px` (`sdk.js:128`) | `bottom: max(20px, env(safe-area-inset-bottom))` | **não há uma única regra `env(safe-area-inset-*)` no `sdk.js`** [FATO, verificado nesta task] |
| Rótulo | `target.title = 'Open chat window'` **hardcoded em inglês** (`bubbleHelpers.js:60`) | `aria-label` traduzido | `BUBBLE.LABEL = "Fale conosco no chat"` **existe** em `widget/i18n/locale/pt_BR.json:57-59` e é enviado por `App.vue:130-135` → `IFrameHelper.js:209-211` `setBubbleLabel`, mas só é aplicado na **variante expandida** (`bubbleHelpers.js:21-26`) [FATO] |

**Estados a cobrir:** default · hover · press · `focus-visible` · com não lidas (com número) ·
aberto (ícone de fechar) · variante flat · variante expandida · **bundle falhou** (degradar para
canal de contato — hoje o site do cliente fica sem canal e ninguém percebe [13 §5.7]).

**Aceite**

1. Com `widget_color = #009CE0`, `getComputedStyle(launcher).backgroundColor === 'rgb(0, 156, 224)'`
   em repouso **e em `:hover`**. (A asserção de hover é a armadilha da §A.1.2.)
2. O `<path>` do SVG tem `fill: currentColor` e o botão tem `color` = `--w-on-brand`.
3. `launcher.getAttribute('aria-label')` não é nulo e é igual a `BUBBLE.LABEL` do locale corrente;
   `title` não contém `'Open chat window'` em nenhum locale.
4. `aria-expanded` reflete o estado do painel.
5. Com 2 não lidas, o nome acessível contém o número — não só o badge colorido (regra C7).
6. Ícone mede 32×32 dentro de um botão de 64×64.
7. `document.getAnimations()` no `mousedown` devolve uma transição de `transform` de ~120 ms.

## C.2 Teaser — **NOVO**

> **DECISÃO DO PRODUTO — 13/08/2026 (D1). Esta seção descreve UM teaser; agora ela descreve a
> superfície de TRÊS níveis de abordagem.** Ver `PLANO-MESTRE` §2.2 blocos **3.20**, **4.06**,
> **4.19**, **4.20** e **4.21**, arbitragem **A15** e §4 Onda 3 itens 2 e 3. O que muda aqui:
>
> 1. **Três níveis, não um.** `discreet` (teaser pequeno, só texto), `bold` (teaser grande com foto e
>    chips — **o padrão de fábrica**) e `aggressive` (**abre o painel sozinho**). Os dois primeiros
>    são esta seção; o terceiro é o bloco 4.20.
> 2. **Um componente, duas formas.** Discreto é o Chamativo com foto e chips ocultos por CSS —
>    **nunca um segundo componente**. Dois componentes de teaser dobram o peso do arquivo que 100%
>    dos visitantes baixam para entregar a mesma coisa menor (teto de 15 KB gzip, **A13**).
> 3. **Degradação por familiaridade** (bloco 4.19): visitante novo recebe o nível configurado;
>    visitante que já foi abordado **e não converteu** recebe o nível abaixo; converter zera o
>    contador. O estado é um cookie de primeira parte com **duas** informações (quantas abordagens,
>    se converteu), gravado pela helper que já existe — `sdk/cookieHelpers.js:26-44`
>    (`setCookieWithDomain`) — com `secure` em HTTPS e 30 dias de validade.
> 4. **A frase "nunca auto-open" desta seção deixou de valer.** Ela vale para os níveis `discreet` e
>    `bold`, que são os padrões; deixou de ser proibição absoluta.
>
> **[INFERÊNCIA] sobre a origem da regra de degradação, declarada porque ela não foi verificada.** O
> dono do produto observou o balão no site da Leadster, e a captura cronometrada do estudo
> (`plano/estudo-chat-web/frontend/shots/leadster-timeline-t8000ms.png`) mostra **o painel aberto** na
> mesma frase, aos 8 s. A hipótese é que a Leadster degrade a abordagem por visita. **A verificação
> de visita repetida falhou — o acesso foi barrado por detecção de bot** — então isto é dedução a
> partir de duas observações que não se encaixam, não observação de comportamento. A regra entra
> porque faz sentido de produto e é barata; a instrumentação do bloco **4.21** é quem vai dizer se
> ela funciona, e ela mede **nesta frota**, que vale mais que qualquer benchmark citável.

| | |
|---|---|
| **Arquivos** | `sdk/bubbleHelpers.js` (criação, ao lado do `bubbleHolder`), `sdk/sdk.js` (CSS), `widget/ui/WTeaserCard.vue` ⚪ (se algum dia migrar para dentro do iframe), `sdk/cookieHelpers.js:1-45` (dispensa persistida **e** o estado de familiaridade da D1) |
| **Risco de merge** | 🟢/⚪ |
| **Esforço** | **G** (o teaser) **+ M** (degradação, bloco 4.19) **+ P** (auto-open, bloco 4.20) |

**Decisão de arquitetura: o teaser vive no host, não no iframe.** Ele fica **ao lado** do launcher,
que já está no host. Colocá-lo dentro do iframe exigiria redimensionar o iframe para caber um cartão
de 280 px fora do painel — que é exatamente a mecânica frágil de `has-unread-view`
(`sdk.js:32-39,255-267`, com `min-height`/`bottom` calculados). O host já tem `bubbleHolder`
(`bubbleHelpers.js:16`) e já sabe posicionar em relação ao launcher.

**Consequência declarada:** o teaser fica **fora** do isolamento do iframe, sujeito ao CSS do site do
cliente. Mitigação: nomes de classe com prefixo `woot-`, todas as propriedades declaradas
explicitamente (nada herdado), e `all: revert` no contêiner — o mesmo padrão que `sdk.js:137` já usa
para o SVG do launcher. **[NÃO VERIFICADO]** o quanto isso basta em sites reais com CSS agressivo;
testar em 3 sites de clientes antes de liberar para a frota.

**Comportamento** (16 §3.2, sem alteração): 280 px desktop / `min(320px, 100vw − 32px)` mobile;
entrada `translateY(8px)` + opacidade em 250 ms `ease-out`, **sem bounce, sem som**; saída
`scale(0.96)` em 200 ms; **gatilho composto** — 8 s **E** 30 % de scroll; dispensa **permanente na
sessão e persistida por cookie**; nunca com banner de cookies visível; **nunca vira auto-open**.

**Aceite**

1. Aparece **uma vez**, e só com as duas condições satisfeitas — 8 s sozinho não dispara.
2. Dispensado, não volta em 3 navegações seguidas no mesmo contexto (cookie).
3. Com banner de cookie visível na página, não dispara.
4. O painel **não** abre sozinho em nenhum caminho.
5. Alvo de dispensa ≥ 32×32 (o do Olark tem 9,8×9,8 — abaixo do mínimo [MEDIDO — 11 §A12]).
6. `role="status"`; o foco **não** vai para o teaser.
7. Sob `prefers-reduced-motion`, aparece sem animação.
8. `profileConfig.teaserEnabled === false` (perfil suporte) → o código do teaser **não é montado**,
   não só escondido.

## C.3 Header

| | |
|---|---|
| **Arquivos** | `widget/components/ChatHeader.vue` (63 l.), `ChatHeaderExpanded.vue` (57 l.), `HeaderActions.vue`, `layouts/ViewWithHeader.vue:35-45,104-144` |
| **Risco de merge** | 🟢 — os quatro com **0 mudanças** do upstream [MEDIDO nesta task] |
| **Esforço** | **M** |

**O que muda**

| Item | Hoje | Vira |
|---|---|---|
| Fundo | `bg-n-brand` (`ChatHeader.vue:28`, `ChatHeaderExpanded.vue:34`) | `bg-w-brand` com `--w-on-brand` calculado — **ou** `bg-w-surface` se Q2 = neutro |
| Altura | **72 px** medidos, `p-5` (`ChatHeader.vue:28`) | **56 px** compacto / 96 expandido; padding `8px 12px` |
| Texto | `text-white` em 4 pontos (`:35,:45,:50,:57`) | `text-w-on-brand` |
| Avatar | `w-8 h-8 rounded-full` (`:39`) | 32×32, **raio 6 px** — 3 de 7 já abandonaram o círculo [11 §C11] |
| Heading | o título é um `<span>` (`ChatHeader.vue:47`); o único `<h2>` está em `ChatHeaderExpanded.vue:48` e **só aparece na Home com texto de boas-vindas** (`ViewWithHeader.vue:35-45`) | **`<h1>` do documento do widget**, sempre presente |
| Status online | bolinha `bg-white/80` (`ChatHeader.vue:50`) | bolinha **+ rótulo textual** — verde×vermelho colapsa para ΔE 7,9 em deuteranopia [MEDIDO — 13 §3.4] |
| Ações | 3 `<button>` com `:title` e **sem `aria-label`** (`HeaderActions.vue:83-111`); o botão de voltar (`ChatHeader.vue:30-36`) não tem nem `title` nem `aria-label` | `WIconButton` com `aria-label` **obrigatório via prop**; caixa 40×40 desktop / **44×44 mobile** |
| Identidade de IA | não existe | rótulo textual persistente "IA" ao lado do nome, e some no handoff |

**Aceite**

1. Existe exatamente um `h1` na view de mensagens, e seu texto é o nome da inbox/agente.
2. Todos os `<button>` do header têm nome acessível não vazio, **em pt-BR**.
3. Nenhum `text-white` sobra em `ChatHeader.vue`, `ChatHeaderExpanded.vue`, `HeaderActions.vue`.
4. Contraste do título contra o fundo do header ≥ 4,5:1 para `#009CE0` **e** `#2DC46F` — os dois
   casos medidos como falha (3,07:1 e 2,25:1).
5. Em 375 px, os alvos das ações medem ≥ 44×44.
6. Com o bot atendendo, o rótulo "IA" está visível; simulando handoff, some.

## C.4 Lista de mensagens

| | |
|---|---|
| **Arquivos** | `widget/components/ConversationWrap.vue` (fundo, scroll, paginação), `views/Messages.vue`, `assets/scss/views/_conversation.scss` (209 l.), `widget/composables/useMessageGrouping.js` ⚪ |
| **Risco de merge** | 🟢 — todos com 0 mudanças [MEDIDO nesta task]. `ConversationWrap.vue` é o arquivo que o **fork** mais mexeu (+37 −3) — a textura mora nele |
| **Esforço** | **M** |

**O que muda**

1. **Fundo.** `--w-surface-sunken` (`#F3F4F6`) + textura. Hoje: `bg-n-chat-bg` em `Messages.vue:22`
   é **classe morta** — `chat-bg` não existe no namespace `n:` de `theme/colors.js` [MEDIDO —
   15 §A3.5], então não gera CSS; o fundo real vem do `background-image` de
   `ConversationWrap.vue:140-167`. Remover a classe morta e tokenizar a textura (`0.85` e `400px`
   hardcoded hoje).
2. **Padding.** `32px 8px 8px` medido → `16px 12px 8px`.
3. **Agrupamento por dados, não por seletor de irmão.** Hoje o agrupamento vive em
   `_conversation.scss:50-74,106-118` com `.agent-message-wrap + .agent-message-wrap` e
   `.has-response + .user-message-wrap` [FATO]. Vira `isFirstOfGroup`/`isLastOfGroup` num composable
   novo — **fora do store**, porque `store/modules/conversation/` é o módulo que o upstream mais
   mexe (+51 −8 / +29).
4. **Separador de data.** Hoje 14 px, altura 50 px medidos. Vira pill de `--w-surface-raised`,
   altura 24, `margin: 20px 0`, `--w-text-system`.
5. **Scroll — quatro correções.** Hoje `updated()` chama `scrollToBottom()` a **toda** mudança de
   tamanho da conversa, sem checar onde o usuário está (`ConversationWrap.vue:67-72`) [FATO]: chega
   mensagem enquanto você lê histórico, **você é arrancado para o fim**. Vira: rolar só se já estava
   no fim (tolerância ~80 px); botão "descer" com contador (`WScrollToBottom.vue` ⚪) quando não
   estava; `updated()` → `watch`; throttle no `handleScroll` (hoje ligado direto em
   `ConversationWrap.vue:64`, sem throttle).
6. **O que não muda:** a preservação de posição ao paginar
   (`ConversationWrap.vue:78-82,92-95`, via `previousScrollHeight`) está **correta e acima da média
   do mercado** [12 §10]. Não mexer.

**A11y — o buraco mais sério do widget hoje.** `role="log"` no contêiner. A spec WAI-ARIA cita "chat
logs" literalmente como exemplo canônico do role, e ele já implica `aria-live="polite"`
[FATO — 13 §4.3]. Hoje há **zero elementos com `aria-live`** em todas as views
[MEDIDO — 15 §A5.3]: **mensagem que chega não é anunciada. Num chat.** Nunca `assertive` para
mensagem normal; `aria-busy="true"` durante streaming de IA; typing e recibos **não** anunciados.

**Aceite**

1. `document.querySelectorAll('[role="log"]').length === 1` na view de mensagens.
2. Chegando mensagem com o visitante rolado 300 px para cima: `scrollTop` **não muda**, e o botão
   "descer" aparece com contador.
3. Chegando mensagem com o visitante no fim: rola.
4. Paginando para trás, a posição visual é preservada (não regredir).
5. `handleScroll` não executa mais de ~10×/s durante um scroll contínuo.
6. Nenhum seletor de irmão adjacente sobra em `_conversation.scss` para fins de agrupamento.

## C.5 Balão — agente, visitante, sistema

| | |
|---|---|
| **Arquivos** | `AgentMessageBubble.vue`, `UserMessageBubble.vue`, `AgentMessage.vue` (266 l.), `UserMessage.vue` (182 l.), `ChatMessage.vue`, `_conversation.scss:88-122,170-209`, `widget/ui/WBubble.vue` ⚪, `widget/components/MessageRow.vue` ⚪ |
| **Risco de merge** | 🟢 nos quatro primeiros; `UserMessage.vue` (+3 −4) e `UserMessageBubble.vue` (+4 −4) são 🟡 [MEDIDO nesta task] |
| **Esforço** | **M** (+ **M** para o `MessageRow`) |

**O que muda**

| Item | Hoje [MEDIDO — 15 §A6.3] | Vira |
|---|---|---|
| Raio | `20px 20px 20px 4px` (agente) / `20px 20px 4px 20px` (visitante) | 20 px livres, **6 px** no canto de origem, **só na última do grupo** |
| Padding | `12px 16px` | **mantido** — é a mediana do mercado [11 §C9] |
| Corpo | 14/21 | **15/22** (Q1) |
| `max-width` | 88 % (agente, `_conversation.scss:7`) / 85 % (visitante, `:53`) | **82 %** nos dois — dentro da faixa de 6 de 8 concorrentes [11 rec.5] |
| Sombra | `rgba(50,50,93,.08) 0 4px 6px, rgba(0,0,0,.05) 0 1px 3px`, **idêntica nos dois temas** | **removida**; a separação vem do par superfície (§C.4) e, no escuro e sob `forced-colors`, de borda 1 px |
| Fundo agente | `bg-white dark:bg-n-solid-3` (`AgentMessageBubble.vue:98`) | `bg-w-surface-raised` |
| Fundo visitante | `:style` inline com `widgetColor` (`UserMessageBubble.vue:35`) | `bg-w-brand` |
| Texto visitante | branco por YIQ → **3,07:1** [MEDIDO — 15 §A5.4] | `--w-on-brand` calculado → **6,85:1** para a mesma cor |
| Link na bolha do agente | `text-n-brand` (`_conversation.scss:205`) → **2,27:1** no claro | `--w-brand-readable` (marca como texto ≠ marca como fundo) |
| Texto base do balão | `.chat-bubble { … text-white }` (`_conversation.scss:176`) | `--w-on-brand` só no visitante; agente recebe `--w-text` |
| Horário | dentro do balão | **fora** — um balão com "Ok" precisaria de largura mínima artificial [13 §5.6] |

**Estados de envio.** Hoje: `.in-progress { opacity: 0.6 }` (`_conversation.scss:83`) sem transição —
texto translúcido lê como "erro", não como "em trânsito". Vira ícone de relógio 12 px **fora** do
balão. "Enviado" ✓ é **NOVO**. "Falhou" já existe e está bom — temos reenvio e **o mercado quase não
tem** [MEDIDO — 12 §7]. "Entregue"/"lido" **não entram** (§ *O que não vamos fazer*).

**Optimistic UI já está correto** (`store/modules/conversation/helpers.js` cria com
`status: 'in_progress'` e `mutations.js` substitui quando o id real chega) [FATO — 12 §7]. Não mexer.

**`MessageRow.vue` — a junção.** `AgentMessage.vue` e `UserMessage.vue` repetem
`hasImageError`/`hasVideoError` com `watch` + `mounted` idênticos, o mesmo bloco de anexos, o mesmo
`ReplyToChip` e o mesmo `MessageReplyButton` [FATO — 15 §B8.2]. Vira um componente com
`direction: 'in' | 'out'` e slots para o que difere de verdade.

**Aceite**

1. Para `#009CE0` **e** `#2DC46F`: contraste do texto sobre o balão do visitante ≥ 4,5:1, medido por
   `getComputedStyle`, nos dois temas.
2. Link na bolha do agente ≥ 4,5:1 nos dois temas (hoje 2,27:1 no claro).
3. `getComputedStyle(bubble).boxShadow === 'none'`.
4. Três mensagens seguidas do mesmo autor: só a última tem o canto de 6 px e o avatar; só a primeira
   tem o nome.
5. Nenhuma altura fixa em px em elemento com texto (auditável por busca).
6. `AgentMessage.vue` + `UserMessage.vue` somam < 150 linhas depois do `MessageRow`.

## C.6 Indicador de digitando

| | |
|---|---|
| **Arquivos** | `widget/components/AgentTypingBubble.vue` (28 l. inteiras), `widget/ui/WTypingDots.vue` ⚪ |
| **Risco de merge** | 🟢 — 0 mudanças do upstream [MEDIDO nesta task] |
| **Esforço** | **P** |

É a tarefa de melhor razão esforço/ganho do plano inteiro. Hoje:
`<img src="assets/images/typing.gif">` (`AgentTypingBubble.vue:13-17`), **19.296 bytes**, a única
implementação em raster de todo o corpus medido [FATO — 12 §5.6]. **Nenhuma media query alcança um
GIF**: não herda a cor da marca, não tem versão escura, não respeita `prefers-reduced-motion`, não
escala com a fonte.

**Especificação** (o desenho do Octadesk/WhatsApp, o único que "lê como digitação" [12 §5.4]):
3 pontos de **7 px**, gap **4 px**, `--w-text-muted`, ciclo **1200 ms** `ease-in-out` infinito,
stagger **150 ms**, `translateY(-4px)` no pico (0,57× o diâmetro) **combinado com** opacidade
0,5 → 1, keyframe `0%,60%,100%` em repouso e `30%` no pico.

**Evitar** o salto de 2× o diâmetro do tawk.to (`translateY(-10px)` em pontos de 5 px) — vira
animação chamativa num estado de espera [12 §C15].

**Detalhe barato:** `tailwind.config.js:288-291,335` **já define** o keyframe `typing-bounce` e a
animação `animate-typing-bounce`, e o widget não usa [FATO — 15 §A6.3].

**Aceite**

1. Nenhuma requisição a `typing.gif` na aba de rede.
2. Os pontos herdam `--w-text-muted` e mudam de cor entre os temas.
3. Sob `prefers-reduced-motion: reduce`, os pontos ficam **estáticos** e aparece o rótulo textual
   "digitando…" — isso também resolve o **SC 2.2.2 (nível A)**, que exige mecanismo de parar
   qualquer movimento acima de 5 s [13 §4.2].
4. `role="status"`, anunciado **uma vez por turno**, nunca em loop.

## C.7 Quick replies (chips)

| | |
|---|---|
| **Arquivos** | `shared/components/ChatOptions.vue`, `shared/components/ChatOption.vue:19,34,37,44`, `widget/message-types/input_select.vue` ⚪ |
| **Risco de merge** | 🟡 — `shared/` é compartilhado com dashboard e portal |
| **Esforço** | **P** |

Altura **40 px** (alvo de toque; o mercado usa 34–36), raio `full`, fundo `--w-surface-raised`,
borda `--w-brand-border`, texto `--w-brand-readable`, gap **8 px**, alinhados **à direita** — é o
alinhamento que faz o chip ser lido como "minha resposta possível" e não como "botão do sistema"
[12 §8]. Entram com **a mesma animação da mensagem** (200 ms), não uma própria.

**Quantidade: 2 a 4.** Mais de 4 de uma vez = +22 % de abandono em mobile [06 §4.3 — fornecedor,
mecanismo plausível]. E o limite de canal manda: se o mesmo fluxo roda em WhatsApp, o teto é
**3 botões de 20 caracteres** [FATO — 06 §4.2].

**Regra dura: o campo de digitação nunca é desabilitado enquanto há chips.** Botões aumentam a
conclusão do fluxo guiado; texto livre aumenta a cobertura de casos fora do script — os dois achados
não se contradizem [06 §1.5, §14.4 R23].

**Aceite:** `<button type="button">` reais (não `<div role="button">`); grupo com `role="group"` e
`aria-label`; alvo ≥ 24×24 com 8 px de separação; ao clicar, o chip vira balão do visitante e os
outros somem; em mensagem antiga, opacidade reduzida e **não clicáveis**.

## C.8 Cards e conteúdo rico

| | |
|---|---|
| **Arquivos** | `shared/components/ChatCard.vue`, `CardButton.vue`, `ChatForm.vue`, `widget/components/template/Article.vue`, `EmailInput.vue`, `IntegrationCard.vue`, `widget/message-types/*` ⚪ |
| **Risco de merge** | 🟡 (`shared/`) + ⚪ (registry) |
| **Esforço** | **M** |

Os oito `content_type` suportados hoje [FATO — `AgentMessageBubble.vue:42-67,92-152`]: texto,
`input_email`, `integrations`, `input_select`, `form`, `cards`, `article`, `input_csat`.

**O pipeline de markdown não muda e está adequado**: `markdown-it` com `html: false` na entrada
**mais** DOMPurify na saída — duas camadas [FATO — 15 §A6.1]. **O que muda é performance:**
`MessageFormatter.js:109` chama `createMarkdownInstance()` **dentro do construtor**, e
`useMessageFormatter.js:19` faz `new MessageFormatter(...)` a cada `formatMessage`, que o template
chama **a cada render de cada bolha** (`AgentMessageBubble.vue:101`) [FATO]. Uma instância de
MarkdownIt com 3 plugins por mensagem, por render. Memoizar — a instância é pura e depende só de
`linkify`.

**Estilos de markdown no balão:** `strong` 600, `em` itálico, `ul/ol` com `padding-left: 20px`,
`code` inline em `--w-surface-sunken`, `pre` com scroll horizontal próprio, e
**link em `--w-brand-readable`** — o token que corrige a falha de 2,27:1.

**Aceite:** contêiner com raio 12, borda 1 px `--w-border`, `--w-elev-0`; máximo 3 botões por card;
`max-width` 82 %; uma única instância de MarkdownIt por valor de `linkify` (verificável com spy no
construtor).

## C.9 Composer

| | |
|---|---|
| **Arquivos** | `widget/components/ChatInputWrap.vue` (🔴 +12 −9), `ChatFooter.vue` (🔴 +37 −12), `ChatSendButton.vue` (🟢), `ChatAttachment.vue`, `FooterReplyTo.vue`, `shared/components/ResizableTextArea.vue`, `shared/components/emoji/EmojiInput.vue`, `widget/ui/WComposer.vue` ⚪ |
| **Risco de merge** | 🔴 nos dois primeiros → **tática de casca fina, nunca reescrita** |
| **Esforço** | **M** |

**A lacuna mais objetiva: não temos botão de enviar visível.** 7 de 7 concorrentes com composer
medido têm; **nós somos a única exceção** [MEDIDO — 11 §C12].

**Precisão que a varredura desta task acrescenta:** o componente **existe** e é 🟢. O que não existe
é a permanência. `ChatInputWrap.vue:177` renderiza `<ChatSendButton v-if="showSendButton" />`, e
`ChatInputWrap.vue:59-61` define `showSendButton() { return this.userInput.length > 0 }` — o botão
**só aparece depois que o visitante digita** [FATO]. E ele é **mutuamente exclusivo com o botão de
anexo**: `showAttachment()` (`:56-58`) exige `userInput.length === 0` [FATO]. Ou seja, o composer
vazio mostra anexo e nenhum enviar; o composer com texto mostra enviar e nenhum anexo. A correção
não é criar o componente — é **manter os dois sempre visíveis**, com o enviar desabilitado em fundo
neutro quando o campo está vazio, que é o padrão de mercado medido [11 §C12].

| Item | Hoje | Vira |
|---|---|---|
| Botão de enviar | ausente/condicional; `bg-n-brand hover:bg-[#1FB85A]` (`ChatSendButton.vue:27`), ícone `text-white` (`:29`) | **sempre visível**, 40×40, `full`, `bg-w-brand`, ícone `--w-on-brand` |
| Caixa | 48 px de altura medidos, `bg-white dark:bg-n-solid-2` (`ChatInputWrap.vue:130`) | `--w-surface`, borda `--w-border`, raio 12; cresce até 120 px |
| Foco | `outline` computado do textarea é `rgba(0,0,0,0) solid 2px` — **transparente**, vindo de `outline-none` em `ChatInputWrap.vue:188` [MEDIDO — 15 §A5.3] | borda `--w-brand-border` + anel de 3 px `--w-brand-subtle`, 100 ms |
| Botões anexo/emoji | 32×32 com ícone 20 | 40×40 desktop / **44×44 mobile** |
| Textarea | 16 px — **correto**, evita o zoom do Safari iOS | mantido |
| Teclado | `document.addEventListener('keypress', …)` (`ChatInputWrap.vue:74`) — listener no **documento**, e `keypress` é **obsoleto e inconsistente para IME**, o que importa para teclado de celular e para acentuação em pt-BR [FATO — 12 §11] | `keydown` **no campo** |
| Foco ao abrir | **existe em código** e não foi observado — ver a nota abaixo | manter, e tratar a exceção explicitamente |

> **DIVERGÊNCIA — o foco automático no campo já está implementado.**
> O 12 §11 registra "Chatwoot/ChatSPX: não observado na sessão medida", e o 16 §3.9 lista foco ao
> abrir como algo a fazer. Medido nesta task por leitura de código: `ChatInputWrap.vue:63-68` tem
> `watch: { isWidgetOpen(v) { if (v) this.focusInput() } }` e `:73-78` repete no `mounted()` [FATO].
> **A lógica existe.** [INFERÊNCIA] da razão de não ter sido observada: o composer só é montado na
> view de mensagens (`Messages.vue` → `ChatFooter` → `ChatInputWrap`), e a sessão do 12 abriu na
> tela inicial (mensagem de ausência + artigos populares), onde `ChatInputWrap` **nem existe no
> DOM** — não há campo para focar.
> **Consequência prática, e é boa:** o comportamento medido como ausente é exatamente a **exceção**
> que a spec prescreve — "se a primeira tela tem conteúdo a ler, o foco vai para o cabeçalho; em
> mobile, focar o campo abre o teclado e come metade da tela" [16 §3.9]. Então W2.9 **não
> implementa** foco ao abrir: verifica que ele dispara na view de mensagens, que **não** dispara na
> tela inicial, e move o foco para o `<h1>` do header nesse caso. Se alguém tratar isso como
> "implementar do zero", vai duplicar lógica e provavelmente abrir o teclado do celular na cara do
> visitante.

**Estados:** default · focus · enviar desabilitado (campo vazio: fundo `--w-surface-sunken`, ícone
`--w-text-muted`) · enviando (spinner de 16 px, campo continua editável) · erro de anexo (faixa em
`--w-danger-subtle` com o limite em MB — a string já existe com interpolação) · bloqueado (conversa
encerrada → botão "Iniciar nova conversa", que já é o caminho de `ChatFooter.vue:133-142`).

**Aceite**

1. Botão de enviar **e** botão de anexo visíveis **simultaneamente**, com o campo vazio e com texto.
2. Com o campo vazio, o enviar está desabilitado em fundo neutro — não ausente.
3. `outline-width > 0` **e** `outline-color` não transparente no textarea focado.
4. Nenhum `addEventListener` de `keypress` sobra em `widget/`.
5. Digitar "café" com IME/acentuação não dispara envio prematuro.
6. Abrindo direto na view de mensagens, `document.activeElement` é o textarea; abrindo na tela
   inicial, é o `<h1>` do header — **e o teclado virtual não abre**.
7. `ChatInputWrap.vue` e `ChatFooter.vue` ficam abaixo de 60 linhas cada (são cascas).
8. Em 375 px, anexo, emoji e enviar medem ≥ 44×44.

## C.10 Anexos

| | |
|---|---|
| **Arquivos** | `widget/components/ImageBubble.vue`, `VideoBubble.vue`, `FileBubble.vue`, `ChatAttachment.vue`, `DragWrapper.vue`, `AgentMessage.vue:207-240` |
| **Risco de merge** | 🟢 |
| **Esforço** | **M** |

Imagem: `max-height: 240px`, raio 12, `aspect-ratio` preservado. Vídeo: player nativo.
**Áudio: hoje é `<audio controls class="h-10 dark:invert">` (`AgentMessage.vue:231-237`) — `invert`
é remendo** [FATO — 15 §A6.2]; a correção real é `color-scheme` no `:root` (W4.3), e aí o controle
nativo acompanha o tema sozinho. Arquivo: linha com ícone 32, nome truncado, tamanho em
`--w-text-meta`, download 40×40. Progresso: barra de 2 px em `--w-brand`. Falha: ícone + "Tentar de
novo". Arrastar: overlay `--w-brand-subtle` com borda tracejada.

**A11y:** todo `<img>` com `alt` (hoje já está correto — 0 imagens sem alt [MEDIDO — 15 §A5.3]); e o
overlay de arrastar **não pode ser a única forma de anexar** — **SC 2.5.7 Dragging Movements (AA)**
exige alternativa por ponteiro simples [13 §4.1]; o botão de anexo já cumpre.

**Aceite:** `dark:invert` some do `<audio>`; o véu de `ImageBubble.vue:41` (`#1f2d3d`) vira token;
nenhum literal sobra nos cinco arquivos.

## C.11 CSAT

| | |
|---|---|
| **Arquivos** | `shared/components/CustomerSatisfaction.vue:43,54-55,122-123,158-160,191`, `shared/components/StarRating.vue`, `widget/message-types/input_csat.vue` ⚪ |
| **Risco de merge** | 🟡 (`shared/`) |
| **Esforço** | **M** |

Card centralizado, `--w-surface-raised`, raio 12, padding 16. **5 alvos de 44×44**, gap 8, ícone 28.
Selecionado: escala 1,1 em 150 ms + `--w-brand-subtle` + **marca de seleção** (não só cor).
Comentário aparece **depois** da escolha. Enviado, colapsa para linha de sistema.

**Duas regras de produto que valem mais que o CSS:** nunca pedir CSAT **antes** do fim da conversa
(padrão problemático nº 4 do NN/g [13 §7.3]); e para feedback de resposta de **IA** o instrumento é
**polegar cima/baixo**, não escala de 5 — mutuamente exclusivo, coletivamente exaustivo e acionável;
o polegar para baixo abre um campo opcional de texto, que é onde está a informação útil
[FATO — 13 §9.5].

**Aceite:** `role="radiogroup"` com `aria-label`; cada opção com rótulo textual acessível
("Muito insatisfeito"…"Muito satisfeito"), **nunca só o emoji**; alvos ≥ 44×44 no mobile; o card não
aparece antes do encerramento.

## C.12 Pre-chat

| | |
|---|---|
| **Arquivos** | `widget/components/PreChat/Form.vue` (🔴 +39 −33), `views/PreChatForm.vue` (🟡 +6 −7), `components/Form/PhoneInput.vue`, `widget/ui/WField.vue` ⚪, `widget/capture/` ⚪ (Onda 3) |
| **Risco de merge** | 🔴 |
| **Esforço** | **M** (tokens) + **G** (fluxo conversacional, Onda 3) |

**Nesta onda `PreChat/Form.vue` recebe apenas tokens.** É o segundo arquivo mais mexido pelo upstream
(+39 −33 desde a nossa base, 16 commits em 36 meses). Redesenhar por dentro é comprar conflito em
todo merge.

O fluxo conversacional do perfil **marketing** (§B.4) **não** reescreve esse arquivo: nasce em
`widget/capture/` ⚪ e é escolhido pelo `profileConfig.captureFlow`. Os dois convivem.

**Regras de conteúdo, não de CSS** [06 §14]: teto de **8 campos no fluxo inteiro** (o que conta é o
número de campos, não de etapas); **e-mail OU WhatsApp**; máscaras brasileiras validando **no blur**
e aceitando entrada suja; **erro específico por campo** — hoje `REGEX_ERROR` é
`"Forneça uma entrada válida"` [FATO — `widget/i18n/locale/pt_BR.json:96`], que diz que errou sem
dizer como acertar; aviso de privacidade **não modal**; checkbox de marketing **desmarcado** e
separado do atendimento; link da política em **nova aba**.

**E uma correção de tradução que é constrangedora e barata:** `pt_BR.json:70` diz
`"Nome Completo é mandatório"` — tradução mecânica de *mandatory*. É "obrigatório" [FATO,
verificado nesta task].

**Aceite:** `<label>` real associado a cada campo (não placeholder como rótulo); `aria-invalid` e
`aria-describedby` apontando para a mensagem de erro; foco no primeiro campo inválido ao submeter;
`grep -rn "mandatório" app/javascript/widget/i18n/` → vazio.

## C.13 Base de conhecimento no widget

| | |
|---|---|
| **Arquivos** | `views/Home.vue`, `components/pageComponents/Home/Article/ArticleContainer.vue`, `ArticleBlock.vue:15,41`, `ArticleListItem.vue`, `SkeletonLoader.vue`, `views/ArticleViewer.vue:13` |
| **Risco de merge** | 🟢 (`Home.vue` 0 mudanças) / 🟡 (`ArticleBlock`, `ArticleListItem`: ±1 linha) |
| **Esforço** | **P** |

Governada por `profileConfig.showKnowledgeBase` (§B.3). Visível no perfil **suporte**, oculta no
**marketing**.

**Um bug de tema para corrigir junto:** `views/ArticleViewer.vue:13` é `class="bg-white h-full"`,
**sem variante `dark:`** [FATO, verificado nesta task] — o leitor de artigo fica branco no tema
escuro. Vira `bg-w-surface`.

**Estado vazio:** sem artigos, **esconder o bloco inteiro** — nunca título com lista vazia.

**Aceite:** com `showKnowledgeBase: false`, nenhum request a `/api/v1/.../articles` sai (não é só
esconder na tela); `ArticleViewer` respeita o tema escuro.

## C.14 Estados vazios

| | |
|---|---|
| **Arquivos** | `views/Home.vue`, `components/TeamAvailability.vue`, `GroupedAvatars.vue`, `widget/ui/WEmptyState.vue` ⚪ |
| **Risco de merge** | 🟢 |
| **Esforço** | **M** |

| Estado | Conteúdo |
|---|---|
| Home sem conversa | avatar(es) · saudação · linha de disponibilidade · **2–4 opções nomeadas** · CTA |
| Conversa nova | primeira mensagem do bot dizendo **o que ele resolve** + opções. **Nunca "Como posso ajudar?"** |
| Sem artigos | esconder o bloco inteiro |
| Carregando histórico | **nada até 600 ms**; depois skeleton de 2–3 balões [DV-7 do 16 §0.3] |

**Sobre avatar** [06 §5.2]: ou foto real de pessoa real, ou ilustração assumidamente ilustração — o
meio-termo (avatar 3D quase-humano, foto de banco com nome inventado) é onde mora a desconfiança
medida. E a imagem tem de corresponder a quem está falando: bot → avatar de bot; humano → foto do
humano; **no handoff, a imagem muda** [13 §6.7].

**Sobre a promessa de retorno:** as chaves já existem em pt-BR (`TEAM_AVAILABILITY.ONLINE`,
`REPLY_TIME.*`) e suportam retorno calculado [FATO — 06 §1.3]. A regra: **nunca prometer mais rápido
que o p75 real**, e derivar a string da métrica da inbox em vez de um campo digitado.

## C.15 Erro, offline e reconexão

| | |
|---|---|
| **Arquivos** | `widget/components/Banner.vue:37`, `widget/ui/WBanner.vue` ⚪, `widget/helpers/actionCable.js`, `shared/helpers/BaseActionCableConnector.js`, `widget/bridge/` ⚪ |
| **Risco de merge** | 🟢/⚪ |
| **Esforço** | **M** |

**Três estados distintos, hoje inexistentes como desenho:**

| Estado | Faixa | Comportamento |
|---|---|---|
| Reconectando | `--w-surface-sunken`, altura 32, no topo da lista | "Reconectando…", **não bloqueante**, composer continua utilizável |
| Offline | `--w-warning` a 12 % | "Sem conexão. Suas mensagens serão enviadas quando voltar." |
| Erro de envio | dentro do balão | ícone + texto + "Tentar de novo", `role="alert"` |

**Regra de tempo: nenhuma faixa aparece antes de 3 s de degradação.** Piscar "reconectando" a cada
micro-queda é pior que não avisar — foi exatamente o que motivou o F0 "sempre conectado" no
dashboard, e não vamos repetir o erro no widget.

**O que já é nosso e é vantagem real — não mexer** [14 §15.1]: backoff exponencial 1 s→30 s com
jitter e tentativas ilimitadas (o Crisp desiste em 5 tentativas; a Leadster em 5 de 1 s fixo);
reabertura em `visibilitychange` + `focus` + `pageshow(persisted)` — **somos os únicos que cobrem os
três caminhos** [MEDIDO — 14 §9.3]; e gap-fill via `onReconnect → syncLatestMessages()`, sem
equivalente em nenhum concorrente medido.

**O que precisa mudar, e destrava a faixa:** `STALE_CHECK_INTERVAL=15000` /
`STALE_EVENT_THRESHOLD=25000` existem em `BaseActionCableConnector.js`, mas a ação depende de
`window.reconnectService`, **que existe no dashboard e não existe no widget** — o timer roda a cada
15 s dentro do widget e **não faz nada** [MEDIDO — 14 §15.1 D3]. Sem o watchdog, a faixa
"reconectando" não tem o que reportar.

**Fila offline** (Onda 4): **somente intenções** — mensagem enviada, anexo. **Nunca estados
transitórios** como "digitando". A regra vem de um erro medido no Crisp, onde três eventos
`message:compose:send` foram bufferizados e despachados **todos de uma vez, em 1 ms, 20 segundos
depois do fato** [MEDIDO — 14 §7.2].

**Aceite**

1. Cortando a rede por 10 s: nada aparece nos primeiros 3 s; a faixa aparece depois; o composer
   continua utilizável; a mensagem digitada entra na fila e é enviada na volta, **em ordem**.
2. Micro-queda de 1,5 s: **nenhuma faixa aparece**.
3. `role="alert"` em "offline" e em falha de envio; `role="status"` em "reconectando".
4. `Banner.vue:37` não usa `text-white` literal.

---

# D. MOVIMENTO E ACESSIBILIDADE

## D.1 O diagnóstico em uma linha

O widget hoje usa **`linear` e `ease`, e nenhum `cubic-bezier`** [MEDIDO — 12 §16]. Somos o **único**
widget do corpus cujo painel se move em `linear` (`sdk.js:14`), o **único** cujo launcher não
responde ao toque, o **único** com indicador de digitando em raster, e um dos que ignoram
`prefers-reduced-motion` — nesse último caso, em boa companhia: 6 de 7 também ignoram.

**Movimento é onde o mercado inteiro é fraco e onde o ganho por linha de CSS é maior.**

## D.2 As três curvas da casa

| Token | Valor | Uso |
|---|---|---|
| `--w-ease-standard` | `cubic-bezier(0.2, 0, 0, 1)` | hover, press, cor, foco — M3 `easing-standard` |
| `--w-ease-enter` | `cubic-bezier(0.05, 0.7, 0.1, 1)` | entrada de superfície — M3 `emphasized-decelerate` |
| `--w-ease-exit` | `cubic-bezier(0.3, 0, 0.8, 0.15)` | saída de superfície — M3 `emphasized-accelerate` |

`linear` fica permitido **apenas** para opacidade pura e rotação contínua (spinner) [12 §A1].

**O que não adotamos: overshoot.** Só o Intercom usa (`cubic-bezier(0, 1.2, 1, 1)`, ordenada 1,2
acima de 1); **todas** as outras curvas customizadas do corpus desaceleram sem passar do ponto
[MEDIDO — 12 §1.3]. Overshoot num painel de 400×640 chama atenção para o contêiner em vez do
conteúdo.

## D.3 Tabela de duração por interação — e o que fazemos diferente do mercado

| Interação | Duração | Curva | Hoje | Adotamos de / divergimos de |
|---|---|---|---|---|
| **Painel — abrir (transform)** | **300 ms** | `--w-ease-enter`, `transform-origin: right bottom` | `transform 250ms linear` (`sdk.js:14`) | **Adotado do Intercom.** A origem no launcher é o que faz o gesto parecer causado pelo clique |
| **Painel — abrir (opacity)** | **80 ms** `ease-out` | — | `opacity 200ms linear` (`sdk.js:14`) | **Desacoplado do transform**, como o Intercom (83 ms contra 300 ms). Hoje fazemos 200 contra 250 — praticamente juntos, o que deixa **meio painel fantasma durante toda a animação** [12 §A2] |
| **Painel — fechar** | 200 ms transform + 120 ms opacity | `--w-ease-exit` | idem abertura | Saída no mesmo intervalo ou levemente menor; **nunca 3× maior** (o `all .8s` do tawk.to) |
| **Painel — mobile fullscreen** | **sem transição de tamanho** | — | anima igual ao desktop | **Adotado do Crisp**, o único que desliga motion em tela cheia de propósito. Animar um retângulo de tela inteira é caro e lê como travamento [12 §14] |
| **Launcher — hover** | **150 ms** | `--w-ease-standard`, `scale(1.1)` | só sombra, **sem transição** (`box-shadow` não está na lista de `sdk.js:210`) | 3 de 6 concorrentes escalam 1,1× em 100–250 ms |
| **Launcher — press** | **120 ms** | `cubic-bezier(.45,0,.2,1)`, `scale(0.94)` | **nada** | Intercom usa 0,85 em 134 ms; adotamos mais discreto |
| **Launcher — troca de ícone** | **150 ms** cross-fade | `--w-ease-standard` | `rotate(-30deg)` (`sdk.js:213`) | **Divergimos de nós mesmos:** ninguém no corpus gira o botão [12 §15] |
| **Mensagem — entrada** | **200 ms** | `--w-ease-standard`, `translateY(8px)` + opacidade, **40 % do keyframe parado no estado inicial** | **nenhuma animação** [FATO — 12 §6.1] | O truque do Intercom: atraso natural sem coordenar `animation-delay` entre bolhas |
| **Mensagem — remoção** | 150 ms | `--w-ease-exit` | — | |
| **Typing dots** | **1200 ms** infinito | `ease-in-out`, stagger 150 ms | GIF | Octadesk/WhatsApp (§C.6) |
| **Teaser — entrada / saída** | 250 ms `ease-out` / 200 ms | `--w-ease-exit` | não existe | Sem bounce, sem som [06 §2.5] |
| **Chip — hover/seleção** | 100 ms | `--w-ease-standard` | — | M3 `short2` |
| **Composer — foco** | 100 ms | `--w-ease-standard` | `0.2s cubic-bezier(.4,0,.2,1)` medido | Intercom anima `outline-width` em 100 ms |
| **Faixa de status** | 200 ms | `--w-ease-standard` | não existe | slide + fade |
| **Botão "descer"** | 150 ms | `--w-ease-standard` | não existe | escala + opacidade |
| **Skeleton** | 1200 ms | `linear` | não existe | shimmer, **só depois de 600 ms de espera** |
| **Spinner** | 600 ms | `linear` | existe | rotação contínua |

**Faixa de trabalho: 80–300 ms.** É onde o mercado inteiro está, com duas exceções (Leadster 500 ms,
LiveChat 430 ms) [MEDIDO — 12 §1.3].

**Sem stagger na abertura do painel.** Nos oito painéis que o 12 conseguiu abrir, **nenhum** escalona
a entrada dos elementos internos — o painel entra como bloco só [MEDIDO — 12 §2.4]. O stagger, quando
existe, está na entrada de *mensagens*. Não inventar aqui.

## D.4 `prefers-reduced-motion` — onde não copiamos o mercado

**6 de 7 concorrentes ignoram.** O Intercom é o único que trata, e trata pela metade: o launcher
respeita, o painel não [MEDIDO — 12 §13]. Do nosso lado: **zero ocorrências** de
`prefers-reduced-motion` em `app/javascript/widget/` e `app/javascript/sdk/` [FATO — 12 §13,
reconferido nesta task].

```
@media (prefers-reduced-motion: reduce) {
  transição de transform      → nenhuma (o elemento aparece na posição final)
  transição de opacidade      → mantida, no máximo 100 ms
  typing dots                 → estáticos + rótulo textual "digitando…"
  skeleton shimmer            → estático
  entrada da bolha            → nenhuma
  hover/press do launcher     → só mudança de sombra/cor
}
```

**O que a preferência não alcança: o GIF.** É por isso que C.6 é pré-requisito desta seção, não item
independente. Um GIF não herda a cor da marca, não tem versão escura, não respeita a preferência e
não escala com a fonte — **errar o meio custa quatro coisas de uma vez**.

Duas media queries acompanham, ambas Baseline widely available — não há desculpa de
compatibilidade [13 §4.7]:

- **`prefers-contrast: more`** → bordas 1 px viram 2 px (`--w-border-strong`); texto secundário sobe
  para `--w-text`; anel de foco engrossa para 3 px.
- **`forced-colors: active`** → some a textura e todo fundo decorativo; cores do sistema;
  **os dois balões ganham borda de 1 px** (o alinhamento sozinho não basta quando as duas
  superfícies colapsam); e `outline: 2px solid transparent` — **nunca `none`**, porque em
  `forced-colors` o `transparent` é substituído por cor real do sistema e o `none` continua nada.

## D.5 Acessibilidade — o inventário do que falta, com o ponto de correção

Tudo medido em 15 §A5.3, com o arquivo onde se corrige adicionado nesta task.

| # | Falta | Estado hoje [MEDIDO] | Onde se corrige | Tarefa |
|---|---|---|---|---|
| **A1** | `aria-live` na lista | **0 elementos** em todas as views. **Mensagem que chega não é anunciada. Num chat.** | `role="log"` em `ConversationWrap.vue:102-110` | W1.11 |
| **A2** | `lang` no documento | `document.documentElement.lang === ""` em todas as views e temas | `app/views/widgets/show.html.erb:2` — hoje é `<html>` puro. **Uma linha, num arquivo com 0 mudanças do upstream** [MEDIDO nesta task] | W1.10 |
| **A3** | Heading real | **0 headings** nas views medidas. O título do header é `<span>` (`ChatHeader.vue:47`); o único `<h2>` (`ChatHeaderExpanded.vue:48`) só aparece na Home e só com texto de boas-vindas | `ChatHeader.vue` | W2.10 |
| **A4** | Rótulos traduzidos | 2 `aria-label` no widget inteiro; launcher com `aria-label: null` e `title = 'Open chat window'` **hardcoded em inglês** (`bubbleHelpers.js:60`) enquanto `BUBBLE.LABEL = "Fale conosco no chat"` existe e não é usado (`pt_BR.json:57-59`) | `bubbleHelpers.js:60`, `HeaderActions.vue:83-111`, `ChatHeader.vue:30-36` | W1.11 |
| **A5** | Foco visível | textarea com `outline: rgba(0,0,0,0) solid 2px` (transparente), de `ChatInputWrap.vue:188`; botões com o foco **padrão do navegador** (`rgb(16,16,16) auto 1px`), inclusive o launcher | `_tokens.scss` + `WButton`/`WIconButton` | W1.11 / W2.3 |
| **A6** | Alvos 44×44 no mobile | medidos: **40×24, 24×24, 32×32, 32×32, 180×24** — **nenhum passa** | primitivos + `sdk.js` | W2.13 |
| **A7** | `Esc` fecha o painel | `Esc` só fecha o seletor de emoji (`ChatInputWrap.vue:135,175`). 6 de 7 concorrentes também não fecham | `widget/bridge/` + `sdk/IFrameHelper.js` | W4.5 |
| **A8** | `<main>` e landmarks | só `<header>` e `<footer>` | `layouts/ViewWithHeader.vue` | W2.10 |
| **A9** | Focus trap / devolução de foco | ordem de Tab medida sai do widget e volta, sem ciclo. `bubbleHelpers.js:81` **já** faz `chatBubble.focus()` ao fechar — metade do caminho existe | `sdk/bubbleHelpers.js`, `WPanel` | W4.5 |

**As regras de anúncio, que são tão importantes quanto ter `aria-live`** [13 §4.3/§4.4]:

- **Nunca `aria-live="assertive"`** para mensagem normal — interromperia a leitura da mensagem
  anterior no meio.
- **Não anunciar** o indicador de digitando repetidamente, nem os recibos.
- `aria-busy="true"` durante streaming de IA, `false` ao concluir: **uma resposta = um anúncio**.
- O estado "falhou" recebe `role="alert"`; os demais estados de envio, não.

**E um critério que não é de código, é de produto:** **SC 3.2.6 Consistent Help é nível A**, e um
chat é literalmente um "mecanismo de contato humano" [FATO — 13 §4.1]. A feature "ocultar o widget em
páginas X" conflita com isso. Não é motivo para não ter a feature — é motivo para a decisão ser
tomada com o critério na mesa.

---

# E. PESO

## E.1 O tamanho do problema, medido

Grafo eager do widget hoje [MEDIDO — 15 §A4.2; hashes e soma reconferidos nesta task]:

| Papel | Arquivo | Cru (B) | Gzip (B) |
|---|---|---:|---:|
| entry | `widget-D0AtGYyS.js` | 61.841 | 19.071 |
| **css** | **`widget-EcEcykJV.css`** | **1.103.132** | **106.127** |
| import | `index-DqTgoDi8.js` (FormKit + date-fns) | 350.867 | 104.774 |
| import | `useBranding-Cod3jKwR.js` (**Amplitude** + vue-i18n + vuex) | 287.030 | 85.022 |
| import | `_plugin-vue_export-helper` (Vue + **compilador**) | 223.922 | 84.950 |
| import | `Validators-B8yFtBg4.js` (**Sentry** + vue-router) | 164.809 | 53.436 |
| **import** | **`leaflet-58r2EQLt.js`** | **150.679** | **43.491** |
| import | `vue-dompurify-html` (markdown-it + DOMPurify) | 131.392 | 56.255 |
| import | `utils.esm` (axios + @chatwoot/utils) | 83.343 | 25.747 |
| import | outros 5 | 15.424 | 7.416 |
| | **TOTAL EAGER** | **~2,58 MB** | **~575 KB** |

**E o nginx serve tudo cru:** nenhum asset do widget vem com `content-encoding`
[MEDIDO — 15 §A4.6, contra `hmlchat.simplexsolucoes.com.br`]. A primeira visita baixa **2,58 MB**,
não 575 KB. O `cache-control` está certo (`public, max-age=31556952`); a compressão simplesmente não
existe.

**[NÃO VERIFICADO]** se a frota de produção (.229, Tozi, fábrica) tem a mesma configuração de nginx.
Só homologação foi medida. **Verificar antes de qualquer conclusão sobre produção** — e antes de
comemorar o ganho.

## E.2 Ordem de ataque

Ordenado por ganho ÷ esforço, com a coluna que mais importa para o planejamento: **toca componente?**

| # | Ação | Ganho | Toca componente? | Esforço | Tarefa |
|---|---|---|---|---|---|
| 1 | **gzip/brotli no nginx** (frota inteira) | **2,58 MB → ~575 KB** na primeira visita | não | P | W0.3 |
| 2 | **`content` próprio do Tailwind** | **−1.047.130 B crus (−94,9 %) / −96.626 B gzip** [MEDIDO — 15 §A4.3] | não | M | W1.14 |
| 3 | **Leaflet fora do grafo eager** | −150.679 B crus / −43.491 gzip, e `window.L` some de dentro do iframe | não | **P — o merge já faz** | W1.15 |
| 4 | **Gate de peso medindo o grafo** | 0 B, mas sem ele **nenhum número acima significa nada** | não | P | W0.4 |
| 5 | **Logo do branding** — `logo_thumbnail.svg` = **90.492 B para renderizar a 24 px** (elemento medido: 179,6×24) | −~88 KB | não | P | W1.16 |
| 6 | **7 `@font-face` da Inter órfãos** — 773.684 B publicados, `theme.fontFamily.sans` não inclui Inter, **nenhum arquivo é baixado** | 0 B de rede (já era zero); limpa o CSS | não | P | W1.16 |
| 7 | **`typing.gif`** | −19.296 B + tema/marca/`reduced-motion` corretos | sim | P | W1.12 |
| 8 | **Chunk de vendor próprio do widget** — hoje `useBranding-*.js` é importado por 4 entradas (`dashboard`, `survey`, `v3app`, `widget`) e o Rollup hospedou nele o **Amplitude** (428.435 B de fonte) que só o dashboard usa | tira Amplitude + Sentry (156.721 B de fonte) do grafo | não | M | W4.10 |
| 9 | **FormKit só na rota do pre-chat** — `entrypoints/widget.js:32-40` registra `defaultConfig()` no `createApp`, então o FormKit inteiro **com todas as traduções** (510.413 B de fonte só de `@formkit/i18n`) vem eager, embora só seja usado em rotas **lazy** | parte relevante dos 350.867 B de `index-*` | sim (1 arquivo) | M | W4.10 |
| 10 | **i18n sob demanda** — `widget/i18n/index.js` faz **40 `import` estáticos**; um cliente brasileiro baixa **200.591 B** de traduções que jamais usará | −200.591 B | sim (1 arquivo) | M | W4.10 |
| 11 | **`vue.runtime.esm-bundler`** — o alias `vue: 'vue/dist/vue.esm-bundler.js'` traz ~192 KB de fonte de compilador de template | ~192 KB de fonte | não | M | W4.10 — **e cuidado: o alias é do upstream** (`vite.shared.ts` da v4.16.2), então divergir custa |
| 12 | **Texturas de fundo** — `chat-spx-background.png` 88.534 B + `chat-spx-background-light.png` 96.098 B, tileados a 400 px, sem WebP e sem preload | −~150 KB se virar SVG/WebP | sim | P | W2.7 |
| 13 | **Memoizar MarkdownIt** | render de bolha, não bytes | sim | P | W2.15 |

**Os itens 1, 2 e 3 sozinhos são o grosso do problema, e nenhum toca num componente Vue.** É por isso
que eles ficam na Onda 0/1: dá para colher a maior parte do ganho **antes** do redesenho aparecer, e
os ganhos não se confundem com os efeitos dele.

## E.3 Por que o CSS tem 1,1 MB — e por que a correção é de configuração

Anatomia do arquivo [MEDIDO — 15 §A4.3]: 1 linha, ~5.095 blocos, **1.291 data-URIs** (549.852 B,
49,8 % do arquivo) e **436 regras `.i-*`** de ícone (700.673 B, **63,5 % do arquivo**).

Quantos desses ícones o widget usa? **Dez.** As 11 regras correspondentes ocupam 11.813 B. As outras
425 regras — **688.860 B** — são ícones que o widget nunca renderiza. Prova direta: `i-lucide-bot`,
`i-lucide-shield` e `animate-copilot-menu-in` **estão** no CSS servido ao widget e **não aparecem** em
nenhum arquivo de `widget/` ou `shared/`.

A causa é uma linha de configuração: `tailwind.config.js:24-38` tem um `content` único que inclui
`./app/javascript/dashboard/**/*.vue` e mais 4 globs de `.js` do dashboard [FATO, reconferido nesta
task]. **O widget recebe o CSS do dashboard inteiro por construção do build**, não por herança de DOM
— o iframe não protege contra o CSS que nós mesmos colocamos dentro dele.

Contrafactual medido: mesmo `tailwind.config.js`, trocando só o `content` para `widget/**` +
`shared/**` → **56.002 B crus / 9.501 B gzip** [MEDIDO — 15 §A4.3].

**Cuidado de execução (novo nesta task):** o `content` do upstream v4.16.2 é praticamente o mesmo,
com `.erb` no lugar de `.html.erb`, e `tailwind.config.js` teve +21 −14 em 2 commits desde a base
[MEDIDO nesta task]. A implementação certa é um **segundo arquivo de config** que importa o base e
sobrescreve só o `content` — não editar o `content` compartilhado. Assim o merge do upstream continua
caindo no arquivo dele.

## E.4 O gate que hoje dá falso verde

`package.json` tem `size-limit` configurado e roda no CI
(`.github/workflows/size-limit.yml:52` → `pnpm run size`, em PRs para `develop`) [FATO]:

```json
"size-limit": [
  { "path": "public/vite/assets/widget-*.js", "limit": "300 KB" },
  { "path": "public/packs/js/sdk.js",         "limit": "40 KB"  }
]
```

Executado: **76,53 kB gzipped — verde** [MEDIDO — 15 §A4.8]. O widget real custa 575 KiB.
**Falso verde por um fator de ~7,5×**, por dois motivos: o glob `widget-*.js` pega **só o chunk de
entrada** (ignora os 13 imports estáticos e o CSS), e casa com **arquivos antigos acumulados** no
diretório (quatro hashes na saída), o que torna a medição não determinística entre builds.

**Descoberta desta task:** o upstream v4.16.2 tem **exatamente o mesmo `size-limit`, com o mesmo
glob** [MEDIDO nesta task]. Então o falso verde é upstream, e corrigi-lo é divergência nossa num
arquivo que o upstream mexe muito (`package.json`). Mitigação: o cálculo vai para
`scripts/widget-size.mjs` ⚪ (arquivo novo, risco zero) e o `package.json` recebe **uma** entrada
apontando para ele — a superfície de conflito fica em uma linha.

**Orçamentos** [15 §B11.4]:

| Métrica | Hoje | Teto | Por quê |
|---|---:|---:|---|
| JS eager (gzip) | 482.322 B | **150 KB** | após tirar Leaflet, Amplitude, Sentry e FormKit eager |
| CSS (gzip) | 106.127 B | **20 KB** | o `content` restrito já mede 9.501 B |
| CSS (cru) | 1.103.132 B | **80 KB** | idem |
| Total eager (gzip) | 588.943 B | **170 KB** | soma |
| SDK (gzip) | 9.570 B | **15 KB** | já está bom; trava para não regredir |

E **uma asserção que não é de tamanho**: falhar o build se `leaflet-*.js` voltar a aparecer nos
imports estáticos de `entrypoints/widget.js` no manifest. Uma linha contra um bug de 150 KB.

---

# F. FASEAMENTO

Cinco ondas, ordenadas por **dependência real**. Nenhuma tarefa depende de algo que venha depois
dela. Esforço relativo. Risco de merge pela legenda da §0.

**Legenda de dependência:** `—` = nenhuma; `Wx.y` = precisa daquela tarefa concluída.

## Onda 0 — Terreno (não é redesenho; é o que torna o redesenho mensurável)

| Id | Título | Arquivos | O que fazer | Aceite | Esf. | Dep. | Risco |
|---|---|---|---|---|---|---|---|
| **W0.1** | **Merge da v4.16.2, sozinho** | 113 arquivos do widget (+4.332 −7.635) [MEDIDO — 15 §B12.4] | Merge isolado, nada mais no mesmo PR | `pnpm test` verde; widget abre; os 16 snapshots de W0.6 revisados um a um (vão mudar, e tudo bem — o que não pode é mudar sem alguém olhar) | **G** | — | 🔴 |
| **W0.2** | Reconciliar o build pós-merge | `vite.config.ts`, `vite.lib.config.ts`, `vite.shared.ts`, `vitest.config.ts` | O upstream quebrou o build em 4 arquivos (§0.3, DIVERGÊNCIA 3). Portar nossas 2 divergências (SDK em library mode → já existe upstream como `vite.lib.config.ts`; `manualChunks` → **deletar**, não portar) | `bin/vite build` gera o mesmo conjunto de entradas; `public/packs/js/sdk.js` sai IIFE; `pnpm test` acha a config | **M** | W0.1 | 🔴 |
| **W0.3** | Compressão no nginx | fora do repo (Ansible/nginx da frota) | `gzip_types`/`brotli_types` com `text/css` e `application/javascript`. **Verificar as 4 VMs, não só homologação** | `curl -skI -H "Accept-Encoding: gzip, br" <asset>` devolve `content-encoding` em **todas** as VMs | **P** | — | — |
| **W0.4** | Gate de peso medindo o grafo | `scripts/widget-size.mjs` ⚪, `package.json`, `.github/workflows/size-limit.yml` | Ler `public/vite/.vite/manifest.json`, resolver o fecho transitivo de `imports` + `css` da entrada e somar. Limpar o diretório antes de medir | Roda hoje e reporta ~575 KiB (não 76,53 kB); falha se passar do teto; falha se `leaflet-*.js` aparecer nos imports estáticos | **P** | W0.2 | ⚪/🟡 |
| **W0.5** | Harness de teste do widget | `playwright.config.js`, `spec/e2e/widget/` ⚪, página host fixa ⚪ | Segundo projeto Playwright com `testDir: 'spec/e2e/widget'`. Fixtures injetadas via `store.commit('conversation/pushMessageToConversation', …)`. Tempo congelado | `pnpm exec playwright test --project=widget` roda e passa vazio | **M** | — | ⚪ |
| **W0.6** | Baseline: 16 snapshots + axe + contraste | `spec/e2e/widget/` ⚪ | Gerar a matriz 4 views × 2 temas × 2 viewports **antes** de qualquer mudança, e o relatório axe/contraste de referência | Os 16 PNG e o JSON de baseline commitados | **P** | W0.5 | ⚪ |

> **W0.1 é bloqueante para tudo.** Hoje o merge mexe em 113 arquivos do widget. Fazer o redesenho
> antes é resolver dois problemas embaralhados — e, pior, é resolver o segundo por cima de um
> primeiro que ainda vai chegar.

## Onda 1 — Fundação: uma cor só, e ela é do cliente

| Id | Título | Arquivos | O que fazer | Aceite | Esf. | Dep. | Risco |
|---|---|---|---|---|---|---|---|
| **W1.1** | Folha de tokens | `widget/assets/scss/_tokens.scss` ⚪; `woot.scss` só o `@import` | Toda a §2 do relatório 16: tipografia, espaçamento, raio, elevação, cor, motion | `_tokens.scss` existe; `woot.scss` não define mais valor de token | **M** | W0.1 | ⚪ |
| **W1.2** | Tokens de marca calculados no servidor | `app/helpers/widget_tokens_helper.rb` ⚪ (ou `app/services/widget_tokens.rb`), `app/views/widgets/show.html.erb` | Luminância relativa WCAG, limiar **0,17913**, escolha entre `#FFFFFF` e **`#000000` puro**; se nenhum atinge 4,5:1, ajustar a luminância do fundo preservando o matiz. Emitir `<style>:root{…}</style>` | Para `#009CE0` → `--w-on-brand: #000000` (6,85:1); para `#2DC46F` → `#000000` (9,35:1). **E `widget_color` inválido no banco não é interpolado no CSS** (valida `#RRGGBB`, senão default) | **M** | W1.1 | 🟢 |
| **W1.3** | Tokens ao SDK | `widget/helpers/IframeEventHelper.js:1-9`, `sdk/IFrameHelper.js:158-198,302-340` | `channelConfig.tokens` já atravessa a ponte; o SDK grava as vars em `bubbleHolder` | Launcher e painel derivam a cor da **mesma** fonte; nenhuma fórmula de contraste em JS | **P** | W1.2 | 🟢 |
| **W1.4** | Tokens no Tailwind | `theme/colors.js` | **Acrescentar** o namespace `w-*` (`bg-w-brand`, `text-w-on-brand`, …). **Não remover** a chave `brand` do upstream | `bg-w-brand` gera `background-color: var(--w-brand)`; `git diff` em `theme/colors.js` é só adição | **P** | W1.1 | 🟡 |
| **W1.5** | Substituir os 25 pontos de `n-brand` | os 25 da §A.1.1 | Um a um, conforme a coluna "vira" | `grep -rn "n-brand" app/javascript/widget/ app/javascript/shared/` → **0** | **M** | W1.4 | 🟢/🟡 |
| **W1.6** | Matar `--widget-color` e os `:style` inline | os 16 arquivos da §A.1.5, `App.vue:118-125` | Remover a variável órfã e todos os `:style` de cor; os componentes passam a ler CSS | `grep -rn -- "--widget-color" app/` → 0; `grep -rn "getContrastingTextColor" app/javascript/widget/ app/javascript/shared/` → 0 | **M** | W1.5 | 🟢/🟡 |
| **W1.7** | Despintar a rampa `--iris-*` | `woot.scss:193,255,272` | Devolver o primitivo (no upstream `iris` é roxo). A marca sai da rampa | `--iris-9` volta ao valor do upstream; nada visual muda, porque ninguém mais lê `iris` como marca | **P** | W1.5 | 🔴 (`woot.scss`) |
| **W1.8** | Alvo de contraste parametrizável | `shared/helpers/colorHelper.js:12-29` | `adjustColorForContrast(color, bg, target)` — hoje o alvo é fixo em 3,1, correto para componente (SC 1.4.11) e insuficiente para texto (SC 1.4.3) | Chamada com `target: 4.5` produz cor que passa; a chamada existente do launcher não regride | **P** | — | 🟡 |
| **W1.9** | Literais do SDK → variáveis | `sdk/sdk.js:3,4,42,85,89,103,132,161`, `sdk/bubbleHelpers.js:46`, `sdk/IFrameHelper.js:321,334,335` | Trocar os 11 pontos por `var(--w-*)`; remover o `:style` inline e o `isWidgetColorLighter` | **Inclui a asserção da armadilha:** launcher em `#009CE0` continua `rgb(0,156,224)` **em `:hover`** | **P** | W1.3 | 🟢 |
| **W1.10** | `lang` no documento do widget | `app/views/widgets/show.html.erb:2` | `<html lang="<%= … %>">` — o locale da **conversa**, não o do site do cliente | `document.documentElement.lang` não vazio e igual ao locale corrente | **P** | — | 🟢 |
| **W1.11** | A11y mínima: log, rótulos, foco | `ConversationWrap.vue`, `bubbleHelpers.js:60`, `HeaderActions.vue:83-111`, `ChatHeader.vue:30-36`, `ChatInputWrap.vue:188`, `_tokens.scss` | `role="log"`; `aria-label` traduzido no launcher/fechar/voltar/enviar; anel de foco visível | 1 `[role="log"]`; todo `<button>` com nome acessível em pt-BR; `outline-color` não transparente | **M** | W1.1 | 🟢/🟡 |
| **W1.12** | Typing dots em CSS | `AgentTypingBubble.vue`, `widget/ui/WTypingDots.vue` ⚪ | §C.6 | Nenhuma requisição a `typing.gif`; pontos herdam token; estáticos sob `reduced-motion` | **P** | W1.1 | 🟢 |
| **W1.13** | Curvas da casa + painel | `_tokens.scss`, `sdk/sdk.js:14,197-240` | As 3 curvas; abrir 300 ms transform + 80 ms opacity; fechar 200/120; `transform-origin: right bottom` | `document.getAnimations()` na abertura não devolve nenhum `linear` em transform | **P** | W1.1 | 🟢 |
| **W1.14** | `content` próprio do Tailwind | `tailwind.widget.config.js` ⚪, pipeline PostCSS | Segundo config que herda o base e restringe o `content` a `widget/**` + `shared/**` | CSS do widget ≤ **80 KB crus** (hoje 1.103.132) | **M** | W0.2 | 🟡 |
| **W1.15** | Leaflet: confirmar e travar | `vite.config.ts` (verificar), `scripts/widget-size.mjs` | Após W0.2, confirmar que o `manualChunks` sumiu; adicionar a asserção permanente | `typeof window.L === 'undefined'` dentro do iframe; `leaflet-*.js` fora dos imports estáticos; teste falha se voltar | **P** | W0.2, W0.4 | ⚪ |
| **W1.16** | Assets órfãos | `public/brand-assets/logo_thumbnail.svg`, `shared/assets/fonts/widget_fonts` | Trocar o logo de 90.492 B (renderiza a 24 px); remover os 7 `@font-face` da Inter que ninguém baixa | Logo < 5 KB; nenhum `@font-face` no CSS do widget | **P** | — | ⚪/🟡 |

**Critério de pronto da Onda 1** — todos verificáveis, e o primeiro é o que falharia hoje:

1. Uma inbox com `widget_color = #009CE0` e outra com `#2DC46F` renderizam **header, botão de enviar,
   balão do visitante e launcher com o mesmo `background-color` da respectiva inbox**, medido por
   `getComputedStyle`, em light e dark, desktop e mobile — **e em `:hover` no launcher**.
2. Contraste do texto sobre o balão do visitante ≥ 4,5:1 para as duas cores.
3. `curl -I` nos assets devolve `content-encoding` em **todas** as VMs da frota.
4. CSS do widget ≤ 80 KB crus.
5. `typeof window.L === 'undefined'` dentro do iframe.
6. `document.documentElement.lang` não vazio.
7. Um `[role="log"]` na view de mensagens.
8. Nenhuma requisição a `typing.gif`.
9. `size-limit` falha se o grafo eager passar do teto.
10. `grep -rn "n-brand\|getContrastingTextColor\|--widget-color" app/javascript/widget/ app/javascript/sdk/` → vazio.

## Onda 2 — A conversa (a superfície que o visitante lê)

| Id | Título | Arquivos | O que fazer | Aceite | Esf. | Dep. | Risco |
|---|---|---|---|---|---|---|---|
| **W2.1** | Bridge de eventos | `widget/bridge/` ⚪, `App.vue:258-345`, `widget/helpers/utils.js:8-21` | 16 ramos → mapa; **validar `e.origin`** e trocar o `targetOrigin: '*'` pela origem real | `App.vue` abaixo de 250 linhas; um teste por handler, sem montar o App; `postMessage` de origem estranha é ignorado | **M** | W0.1 | ⚪ + 🟡 |
| **W2.2** | Registry de `content_type` | `widget/message-types/` ⚪, `AgentMessageBubble.vue:42-67,92-152` | 8 computeds + 6 `v-if` → `<component :is>`; corrigir o `!isCards` duplicado e os dois ausentes | Os 8 tipos renderizam; adicionar um 9º é 1 arquivo + 1 linha | **M** | W0.1 | ⚪ + 🟢 |
| **W2.3** | Primitivos `widget/ui/` | 13 arquivos ⚪ | `WButton`, `WIconButton` (`aria-label` obrigatório via prop), `WBubble`, `WAvatar`, `WSurface`, `WSpinner`, `WField`, `WSkeleton`, `WTypingDots`, `WBanner`, `WComposer`, `WScrollToBottom` | Regra de lint: nenhum importa de `dashboard/`, nenhum tem cor literal | **G** | W1.1 | ⚪ |
| **W2.4** | `MessageRow.vue` | `AgentMessage.vue`, `UserMessage.vue`, `MessageRow.vue` ⚪ | Unificar por `direction`, slots para o que difere | Os dois somam < 150 linhas; snapshots idênticos | **M** | W2.3 | ⚪ + 🟡 |
| **W2.5** | Agrupamento por dados | `useMessageGrouping.js` ⚪, `_conversation.scss:50-74,106-118` | `isFirstOfGroup`/`isLastOfGroup` **fora do store**; remover os seletores de irmão adjacente | Nenhum `+ .agent-message-wrap` sobra; agrupamento visual idêntico | **M** | W2.4 | ⚪ + 🟢 |
| **W2.6** | Balões | `AgentMessageBubble.vue`, `UserMessageBubble.vue`, `_conversation.scss:88-122,170-209` | Raio 20/6, padding 12/16, `max-width` 82 %, **sem sombra**, corpo 15/22, horário fora | `boxShadow === 'none'`; contraste ≥ 4,5:1 nos dois temas | **M** | W2.5 | 🟢/🟡 |
| **W2.7** | Lista | `ConversationWrap.vue:101-173`, `Messages.vue:22` | Fundo `--w-surface-sunken` + textura tokenizada (e trocar os 2 PNG por WebP/SVG); padding 16/12/8; separador em pill; remover a classe morta `bg-n-chat-bg` | Textura < 30 KB; `grep "chat-bg"` → 0 | **M** | W2.6 | 🟢 |
| **W2.8** | Scroll | `ConversationWrap.vue:63-96`, `WScrollToBottom.vue` ⚪ | Auto-scroll condicional (tolerância 80 px); botão "descer" com contador; `updated()` → `watch`; throttle | Mensagem chegando com o visitante rolado para cima **não** salta; o botão aparece | **M** | W2.3 | 🟢 + ⚪ |
| **W2.9** | Composer | `ChatInputWrap.vue:56-61,63-78,177,188` (casca), `ChatFooter.vue` (casca), `ChatSendButton.vue`, `WComposer.vue` ⚪ | Enviar **e** anexo simultâneos (hoje são mutuamente exclusivos); enviar desabilitado com campo vazio; foco visível; `keydown` no campo. **Foco ao abrir já existe — verificar, não reimplementar** (§C.9) | Os 8 aceites da §C.9; nenhum `keypress` sobra; as duas cascas < 60 linhas cada | **M** | W2.3 | 🔴 → casca |
| **W2.10** | Header | `ChatHeader.vue`, `ChatHeaderExpanded.vue`, `HeaderActions.vue`, `ViewWithHeader.vue` | Altura 56/96, avatar 32 raio 6, ações 40/44, **`<h1>` real**, `<main>`, status com rótulo textual | 1 `h1`; todos os botões com nome acessível; nenhum `text-white` | **M** | W2.3 | 🟢 |
| **W2.11** | Estados: vazio, carregando, erro, offline | `WBanner.vue` ⚪, `WSkeleton.vue` ⚪, `Banner.vue`, `views/Home.vue` | Skeleton **só acima de 600 ms**; as três faixas da §C.15; estado inicial com 2–4 opções nomeadas | Rede cortada 10 s: faixa aos ~3 s, composer utilizável; micro-queda de 1,5 s não mostra nada | **M** | W2.3 | ⚪ + 🟢 |
| **W2.12** | Motion completo + `reduced-motion` | `_tokens.scss`, `sdk/sdk.js`, componentes | A tabela da §D.3 inteira; o bloco `@media` da §D.4 | Com `reduced-motion: reduce`, `transition` do painel e do launcher é `none` ou ≤ 1 ms; typing sem `animation` | **P** | W1.13, W2.6 | 🟢 |
| **W2.13** | Mobile | `sdk/sdk.js:147,242-290`, `IFrameHelper.js:341-347` | **Breakpoint único 768** (`max-width: 767.98px` / `min-width: 768px`); hoje `max-width:667` e `min-width:667` **coexistem** (`sdk.js:242,281`) e o JS usa **668** (`IFrameHelper.js:343`); `100dvw`/`100dvh` com fallback declarado antes; `env(safe-area-inset-*)`; alvos 44×44 | Em 767 px é fullscreen, em 768 é flutuante, sem ambiguidade; todo clicável em 375 px mede ≥ 44×44 (hoje **0 de 5** passam) | **M** | W2.3 | 🟢 |
| **W2.14** | Watchdog do widget | `shared/helpers/BaseActionCableConnector.js`, `widget/helpers/actionCable.js` | Dar ação ao `STALE_CHECK_INTERVAL`, que hoje roda a cada 15 s e **não faz nada** no widget porque depende de `window.reconnectService`, que só existe no dashboard | Socket morto silenciosamente é detectado em ≤ 25 s e reconecta | **M** | W2.11 | 🟡 |
| **W2.15** | Render: memoizar e `v-memo` | `shared/composables/useMessageFormatter.js:19`, `shared/helpers/MessageFormatter.js:109`, `MessageRow.vue` | Uma instância de MarkdownIt por valor de `linkify`; `v-memo` na linha | Spy no construtor: 1 chamada, não 1 por bolha por render | **P** | W2.4 | 🟡 |

**Critério de pronto da Onda 2:**

1. Os 16 snapshots passam (revisados, não só verdes).
2. `axe-core` sem violação **crítica ou séria** nas 4 views, nos 2 temas.
3. Todo clicável em 375×667 mede ≥ 44×44.
4. `prefers-reduced-motion` respeitado no painel, no launcher e no typing.
5. Rede cortada 10 s: faixa aos ~3 s, composer utilizável, fila drena em ordem.
6. Mensagem chegando com scroll para cima não arranca o visitante.
7. Painel funciona em **320 px** e em **200 % de zoom** sem perda de conteúdo.
8. Nenhuma altura fixa em px em elemento com texto.

## Onda 3 — Perfil por inbox, captura e proatividade

| Id | Título | Arquivos | O que fazer | Aceite | Esf. | Dep. | Risco |
|---|---|---|---|---|---|---|---|
| **W3.1** (= bloco **3.01**) | Perfil em `additional_attributes` — **sem migration** (A1/A4) | `app/models/inbox.rb:50` (`store_accessor` + `validates :inclusion`), `app/controllers/api/v1/accounts/inboxes_controller.rb:217` (`permit`) | Declarar **numa única edição** as três chaves de topo `widget_profile`, `widget_triggers`, `widget_tracking`; valores `support`/`marketing` (A2); `nil` lido como `support` (A4). **Nada de `add_column`, nada de `EDITABLE_ATTRS`** | **Os 16 snapshots são idênticos antes e depois do deploy**, com a inbox **sem** `widget_profile` gravado (§B.5). `PATCH inbox` com `widget_profile: "marketing"` persiste e volta no `GET`; valor inválido devolve 422 | **P** | W2.* | 🔴 (`inboxes_controller.rb`, **uma edição só**) |
| **W3.2** | Resolver o perfil no servidor | `app/services/widget_profile.rb` ⚪, `show.html.erb` | `WidgetProfile.resolve(web_widget)` → **as 11 flags planas da §B.3 (lista canônica)**. **Nunca sobrescreve coluna gravada** | Inbox com `csat_survey_enabled: false` + perfil `support` continua com CSAT desligado | **M** | W3.1 | ⚪ + 🟢 |
| **W3.3** | Widget consome flags, não o perfil | `widget/mixins/configMixin.js`, `store/modules/appConfig.js`, componentes | O widget lê `profileConfig.*`; `widgetProfile` só para telemetria | `grep -rn "widgetProfile" app/javascript/widget/` não casa em nenhum `v-if` de template | **M** | W3.2 | 🟡 |
| **W3.4** | Tela inicial por perfil | `views/Home.vue`, `TeamAvailability.vue`, `pageComponents/Home/Article/*`, `views/ArticleViewer.vue:13` | Layout `support` × `marketing` (§B.4); corrigir o `bg-white` sem `dark:` do ArticleViewer | Com `showKnowledgeBase: false`, **nenhum request a articles sai** | **M** | W3.3 | 🟢/🟡 |
| **W3.5** | Fluxo de captura conversacional | `widget/capture/` ⚪, `message-types/` ⚪ | Campos como mensagens; teto de 8 campos; e-mail **ou** WhatsApp; máscaras BR validando no blur. **`PreChat/Form.vue` não é reescrito** | Fluxo de 4 campos conclui em mobile 375 px sem scroll horizontal; erro específico por campo | **G** | W2.2, W3.3 | ⚪ |
| **W3.6** | Saída para WhatsApp (marketing) | `message-types/` ⚪, `ChatFooter.vue` (casca) | CTA de saída no rodapé e no fim do fluxo, com o contexto da conversa | O link carrega o contexto; `profileConfig.primaryExit === 'none'` esconde | **M** | W3.5 | ⚪ |
| **W3.7** | Base de conhecimento (suporte) | `pageComponents/Home/Article/*` | Governada por flag; estado vazio esconde o bloco inteiro | §C.13 | **P** | W3.4 | 🟡 |
| **W3.8** | Teaser | `sdk/bubbleHelpers.js`, `sdk/sdk.js`, `sdk/cookieHelpers.js` | §C.2 | Os 8 aceites da §C.2 | **G** | W1.9, W3.2 | 🟢 |
| **W3.9** | Identidade de IA | `ChatHeader.vue`, `message-types/`, `ConversationWrap.vue` | Rótulo persistente no header **e** atrelado à bolha; `aria-busy` no streaming; **as três marcações no handoff** (sistema, header, bolha) e as três de volta | Simulando handoff, as 3 aparecem; simulando volta à IA, as 3 também. **Nunca roxo como marcador** — contra o azul, colapsa para ΔE 1,8 em deuteranopia | **M** | W2.10, W2.2 | 🟢/⚪ |
| **W3.10** | CSAT redesenhado | `shared/components/CustomerSatisfaction.vue`, `StarRating.vue` | §C.11 | `role="radiogroup"`; rótulos textuais; alvos 44×44; nunca antes do encerramento | **M** | W2.3 | 🟡 |
| **W3.11** | Cards e conteúdo rico | `shared/components/ChatCard.vue`, `CardButton.vue`, `ChatForm.vue`, `template/*` | §C.8 | Máximo 3 botões; `max-width` 82 %; markdown memoizado | **M** | W2.2, W2.15 | 🟡 |

**Critério de pronto da Onda 3:**

1. Trocar o perfil de uma inbox muda a tela inicial, o teaser e o rodapé — **e não muda nenhum valor
   já gravado**.
2. O teaser aparece uma vez, com as duas condições, e não volta após dispensa.
3. O widget não abre sozinho em nenhum caminho.
4. Simulando handoff, as três marcações aparecem.
5. Um fluxo de captura de 4 campos conclui em 375 px sem scroll horizontal.

## Onda 4 — Acabamento, e o que o mercado não faz

| Id | Título | Arquivos | O que fazer | Aceite | Esf. | Dep. | Risco |
|---|---|---|---|---|---|---|---|
| **W4.1** | Fila offline de intenções | `widget/bridge/` ⚪, `store/modules/conversation/` (**só leitura**), `widget/offline/` ⚪ | Enfileirar **somente intenções** (mensagem, anexo); nunca estados transitórios | Rede cortada: 3 mensagens digitadas chegam **em ordem** na volta; nenhum evento de "digitando" é despachado em lote | **M** | W2.14 | ⚪ |
| **W4.2** | Telemetria de erro do widget | `widget/bridge/` ⚪, config do GlitchTip | Hoje há ~20 `catch { // Ignore error }` e **zero telemetria** — o widget é o único componente da frota sem observabilidade [FATO — 09 §9, 14 §7.3] | Erro forçado aparece no GlitchTip **com PII removida**; nenhuma exceção vaza para o `window.onerror` do site do cliente | **M** | W2.1 | ⚪ |
| **W4.3** | Dark mode completo | `sdk/sdk.js:74`, `App.vue:369-381`, `composables/useDarkMode.js:20`, `_tokens.scss` | Default `auto`; classe `dark` no **`<html>`** (hoje no `<div>`, `App.vue:377`); `color-scheme` no `:root` (hoje só em `ConversationWrap.vue:138`); tornar `prefers-color-scheme` **reativo** (o `computed` atual lê `matchMedia().matches`, que não é fonte reativa do Vue) | Sem `darkMode` configurado e SO no escuro, o widget abre escuro; trocar o tema do SO com o painel aberto reflete **sem remount** | **P** | W1.1 | 🟢/🟡 |
| **W4.4** | `prefers-contrast` e `forced-colors` | `_tokens.scss` | §D.4 | `prefers-contrast: more` engrossa bordas e foco; em `forced-colors: active` a textura some e os dois balões continuam distinguíveis por borda | **P** | W2.6 | ⚪ |
| **W4.5** | `Esc` fecha e devolve o foco | `widget/bridge/` ⚪, `sdk/IFrameHelper.js`, `sdk/bubbleHelpers.js:74-83` | `Esc` fecha o painel e devolve o foco ao launcher (`chatBubble.focus()` **já existe** em `bubbleHelpers.js:81`); no mobile, conteúdo de fundo `inert`; no desktop, **sem** armadilha de foco | `Esc` fecha; `document.activeElement` volta a ser o launcher; ordem de Tab = ordem visual; nenhum `tabindex` positivo | **P** | W2.1 | 🟢/⚪ |
| **W4.6** | Piscar do título + som por inbox | `sdk/` ⚪, `IFrameHelper.js:145-156,294-296` | Piscar: 650 ms de intervalo, 60 s de duração, só com a aba oculta, para no `visibilitychange`, não reentra. Som **desligado por default**, opção por inbox | Aba em segundo plano: o título alterna e para ao voltar. Som não toca sem opt-in | **P** | W3.2 | ⚪/🟢 |
| **W4.7** | Idempotência de envio | `widget/api/conversation.js` (🔴 +17 −4), backend | Chave de idempotência em todo POST de mensagem. O Intercom manda `Idempotency-Key` em todo request; nós não temos nada equivalente [MEDIDO — 14 §4.3] | Retry de rede com a mesma chave não duplica mensagem | **M** | W4.1 | 🔴 |
| **W4.8** | Degradação do launcher | `sdk/sdk.js`, snippet de instalação | Se o bundle falhar, o launcher degrada para canal de contato (mailto/WhatsApp) servido no snippet — hoje o site fica **sem canal de contato e ninguém percebe** [13 §5.7] | Bloqueando o bundle no devtools, o link alternativo aparece | **P** | W1.9 | 🟢 |
| **W4.9** | i18n: as correções pendentes | `widget/i18n/locale/pt_BR.json:70,96` e demais | `"mandatório"` → **"obrigatório"**; `REGEX_ERROR` genérico → erro específico por campo; revisão de traduções mecânicas | `grep -rn "mandatório" app/javascript/widget/i18n/` → vazio; nenhum rótulo acessível em inglês com interface em pt-BR | **P** | W3.5 | 🟡 |
| **W4.10** | Peso: vendor, FormKit, i18n, compilador | `vite.config.ts`/`vite.shared.ts`, `entrypoints/widget.js:32-40`, `widget/i18n/index.js` | Chunk de vendor próprio do widget (tira Amplitude + Sentry); FormKit só na rota do pre-chat; i18n sob demanda; avaliar `vue.runtime.esm-bundler` | JS eager (gzip) ≤ **150 KB**; total eager ≤ **170 KB**; `typeof window.__SENTRY__ === 'undefined'` e `typeof window.amplitude === 'undefined'` dentro do iframe | **G** | W0.4, W2.* | 🟡/🔴 |

**Critério de pronto da Onda 4:**

1. Um erro forçado no widget aparece no GlitchTip, com PII removida.
2. Com `chatwootSettings.darkMode` ausente e o SO em escuro, o widget abre escuro; trocar o tema do
   SO com o painel aberto reflete sem remount.
3. `Esc` fecha o painel e devolve o foco ao launcher.
4. `forced-colors: active` mantém os dois balões distinguíveis.
5. Os cinco tetos de peso da §E.4 passam no CI.
6. Rede cortada com 3 mensagens na fila: chegam em ordem, sem duplicata.

---

# G. COMO TESTAR

## G.1 O que já existe, medido

| Ferramenta | Versão | Estado hoje |
|---|---|---|
| **Vitest** | 3.0.5 | Ativo — `pnpm test` (`TZ=UTC vitest --no-watch --no-cache --no-coverage`); config **dentro** de `vite.config.ts:116-142`, `environment: 'jsdom'`, `include: ['app/**/*.{test,spec}…']`, `setupFiles: ['fake-indexeddb/auto', 'vitest.setup.js']` [FATO, verificado nesta task]. **33 specs no widget** |
| **Playwright** | ^1.59.1 | Instalado. `playwright.config.js` existe, `testDir: 'spec/e2e'`, `locale: 'pt-BR'`, `timezoneId: 'America/Cuiaba'`, `baseURL` por `E2E_BASE_URL` — mas **o único suite é o Copilot (dashboard)** [FATO] |
| **Histoire** | 0.17.15 | Configurado; **1 única story no widget** — `Availability/AvailabilityText.story.vue` |
| **size-limit** | ^8.2.4 | Ativo no CI, **medindo o arquivo errado** (§E.4) |

**A lacuna que define o risco desta empreitada:** dos 33 specs do widget, **apenas 2 montam
componente** (`messageMixin.spec.js` e `configMixin.spec.js` — e mesmo esses testam mixin, não
render) [MEDIDO — 15 §B11.1, reconferido nesta task pela listagem: os 33 arquivos são
`api/specs`, `composables/specs`, `mixins/specs`, `helpers/specs` e `store/modules/specs`].
**Não há um único teste de render de componente do widget.** Um redesenho total sobre essa base é
redesenho sem rede — e é por isso que W0.5/W0.6 vêm antes de tudo, não depois.

**Nota de execução (nova nesta task):** o upstream v4.16.2 extraiu a config de teste para
`vitest.config.ts` próprio. Depois de W0.1/W0.2, `pnpm test` passa a ler de lá. Qualquer setup novo
de teste do widget deve pousar no arquivo do upstream, não recriar o nosso.

## G.2 O que cobrir com Vitest (jsdom, barato, roda em todo PR)

| Alvo | Por que Vitest basta |
|---|---|
| `WidgetTokens` / a fórmula de contraste (Ruby: RSpec) | É aritmética pura. Tabela de entrada→saída para as 12 cores do `t13-contraste-balao-marca.png` + `#009CE0` e `#2DC46F` |
| `WidgetProfile.resolve` (RSpec) | Função pura de config. **O teste que importa:** perfil `support` numa inbox existente devolve exatamente os valores gravados |
| Handlers do `widget/bridge/` | Cada um é `(payload, ctx) => void`, testável sem montar o App — **é metade do motivo de W2.1 existir** |
| Registry de `message-types` | `resolve('input_csat')` devolve o componente certo; tipo desconhecido cai no texto |
| `useMessageGrouping` | Entra array de mensagens, sai `isFirstOfGroup`/`isLastOfGroup` |
| Fila offline | Enfileirar 3, drenar, verificar **ordem**; e verificar que "digitando" **não** entra |
| Primitivos de `widget/ui/` | Render + props + `aria-label` obrigatório. **É aqui que os 0 testes de componente viram N** |
| Memoização do MarkdownIt | Spy no construtor: 1 chamada para 10 renders |
| Validação de origem no `postMessage` | Evento de origem estranha é ignorado |

## G.3 O que exige Playwright (browser real, roda no merge)

Playwright é obrigatório para tudo que depende de layout computado, de cross-origin real ou de
`prefers-*`. Três coisas **não** são simuláveis em jsdom e são exatamente as que estamos consertando:
contraste computado, tamanho de alvo de toque e media query de preferência.

**Setup (W0.5).** Segundo projeto no `playwright.config.js` com `testDir: 'spec/e2e/widget'` e uma
página host fixa servida do próprio repositório, embutindo o SDK — cenário cross-origin idêntico ao
real, que é como o 15 mediu (`http://localhost:8899/host.html` → SDK de `http://localhost:3000`).

**Duas travas obrigatórias, senão o suite vira flaky:**

1. **Fixtures determinísticas.** Mensagens injetadas no store
   (`store.commit('conversation/pushMessageToConversation', msg)`), **nunca** vindas do backend.
   A técnica é a mesma que o 15 usou e funcionou — e **nenhuma mensagem foi enviada ao backend**
   naquela sessão, o que é a propriedade que queremos preservar.
2. **Tempo congelado.** `shared/components/DateSeparator.vue` renderiza "Hoje".

**O suite:**

| Suite | O que verifica | Onda |
|---|---|---|
| **`color.spec.js` — a trava que define o projeto** | Mesma inbox, **duas `widget_color` diferentes**: header, botão de enviar, balão do visitante e launcher têm o **mesmo** `background-color`. **Este teste falha hoje** e é a garantia de que o bug não volta | W1 |
| `contrast.spec.js` | Razão WCAG calculada a partir das cores computadas reais, nos 2 temas. Alvos: corpo ≥ 4,5:1, link na bolha ≥ 4,5:1 (hoje 2,27:1), texto sobre a marca ≥ 4,5:1 (hoje 3,07:1), borda de input ≥ 3:1, anel de foco ≥ 3:1 | W1 |
| `a11y.spec.js` (`@axe-core/playwright`) | Sem violação crítica/séria nas 4 views × 2 temas. Mais as asserções que o axe não faz: `lang` não vazio (hoje `""`), ≥ 1 `[aria-live]` (hoje 0), todo `<button>` com nome acessível (hoje 0 de 2 na Home), `outline-width > 0` **e** cor não transparente | W1/W2 |
| `touch-targets.spec.js` | Todo `button`/`a` em 375×667 mede ≥ 44×44. **Hoje 0 de 5 passam** (40×24, 24×24, 32×32, 32×32, 180×24) | W2 |
| `motion.spec.js` | `document.getAnimations()` na abertura: nenhum `linear` em `transform`. Com `reducedMotion: 'reduce'` no contexto: `transition` do painel e do launcher `none` ou ≤ 1 ms; typing sem `animation`. **É a mesma instrumentação do 12 §Método**, então é comparável com a medição dos concorrentes | W2 |
| `scroll.spec.js` | Rolar 300 px para cima → injetar mensagem → `scrollTop` não muda e o botão "descer" aparece. No fim → rola | W2 |
| `offline.spec.js` | `context.setOffline(true)` por 10 s: nada nos primeiros 3 s, faixa depois, composer utilizável, fila drena **em ordem**. E micro-queda de 1,5 s **não** mostra faixa | W2/W4 |
| `teaser.spec.js` | 8 s sem scroll → não dispara. 8 s + 30 % → dispara uma vez. Dispensar → não volta em 3 navegações. Banner de cookie visível → não dispara | W3 |
| `profile.spec.js` | Perfil `marketing` esconde a KB e liga o teaser; `support` faz o inverso; **trocar o perfil não altera valor gravado** | W3 |
| `reflow.spec.js` | 320 px de largura e 200 % de zoom sem perda de conteúdo (SC 1.4.10 e 1.4.4) | W2 |

## G.4 Regressão visual

`toHaveScreenshot()` é nativo do Playwright — **zero dependência nova**. Matriz mínima
[15 §B11.2]: **4 views** (`home`, `messages`, `prechat-form`, `unread`) × **2 temas** ×
**2 viewports** (1280×900 e 375×667) = **16 snapshots**.

Três usos específicos, além do óbvio:

1. **Baseline pré-merge (W0.6).** Os 16 snapshots antes de W0.1 são o que torna o merge da v4.16.2
   revisável. Eles **vão** mudar; o que não pode é mudar sem alguém olhar.
2. **Baseline do perfil (W3.1 / bloco 3.01).** Os mesmos 16, antes e depois do deploy que introduz
   `WidgetProfile.resolve`, numa inbox **sem** `widget_profile` gravado, com diferença **zero**. É a
   prova de que a frota não sente o deploy. **Não há migration** (A1) e **não há backfill** (A4): o
   que se prova é a leitura derivada `nil` → `support`.
3. **Matriz de perfil (W3).** Não dobra para 32: só as views que o perfil muda (`home` e o rodapé)
   ganham um segundo snapshot. É a economia que a regra "flags planas, não branch" (§B.1) compra.

**Threshold:** comparação estrita nas views de layout; tolerância só onde houver antialiasing de
texto. Snapshot flaky é pior que snapshot ausente, porque ensina o time a ignorar o vermelho.

## G.5 Gate de peso no CI

Já detalhado na §E.4. O que importa para a execução:

- O cálculo mora em `scripts/widget-size.mjs` ⚪ (fecho transitivo do manifest), **não** em
  `package.json`, para minimizar a superfície de conflito com o upstream — que tem o mesmo
  `size-limit` errado que nós [MEDIDO nesta task].
- **Limpar `public/vite/assets/` antes de medir**; hoje o glob casa com 4 hashes antigos e a medição
  não é determinística.
- Asserção nominal: falhar se `leaflet-*.js` aparecer nos imports estáticos da entrada.
- Os 5 tetos da §E.4 entram um a um, conforme as tarefas que os viabilizam ficam prontas — teto que
  falha desde o primeiro dia é teto que o time desliga.

## G.6 O que não dá para testar no CI, e como cobrir

Três lacunas do 13 §13.5 que **nenhuma delas é resolvível em headless**, e 72 % dos minutos digitais
no Brasil são mobile [FATO — 06 §8.3]:

| Lacuna | Por que não dá | Como cobrir |
|---|---|---|
| `dvh` com a barra de endereço real | Chromium headless não instancia a barra dinâmica | Teste manual em iOS Safari e Android Chrome reais, **antes de congelar o layout mobile** |
| `visualViewport` com teclado virtual | Emulação de dispositivo não instancia teclado; `visualViewport` não muda | Idem. **O composer não pode ficar atrás do teclado** |
| `overscroll-behavior` no Safari | Baseline **limited**, sem implementação listada no Safari | Declarar como enriquecimento progressivo **e** bloquear o scroll do `body` por JS em mobile fullscreen — não depender só do CSS |

E uma quarta, que é de produto e não de browser: **a frequência de reaparição do teaser não foi
medida em nenhum fornecedor** [NÃO VERIFICADO — 12 §4]. É parâmetro nosso, sem referência externa.
Temos frota para medir internamente, e essa medição vale mais que qualquer benchmark citável.

---

# RISCOS E ARMADILHAS

Ordenados por probabilidade × custo. Cada um tem o sinal que o denuncia e a mitigação.

| # | Risco | Sinal de que aconteceu | Mitigação |
|---|---|---|---|
| **R1** | **O `:hover` verde do launcher ressuscita.** `sdk.js:132` reaplica `#2dc46f`; hoje o `:style` inline de `IFrameHelper.js:334` vence. W1.9 remove o inline. Se `sdk.js:132` for esquecido, o launcher fica na cor da inbox e **fica verde ao passar o mouse** | Ninguém percebe: screenshot de launcher não captura hover | Asserção de hover explícita no aceite de W1.9 e em `color.spec.js`. **É o bug mais provável da Onda 1** |
| **R2** | **Fazer o redesenho antes do merge da v4.16.2.** O merge mexe em 113 arquivos do widget | Conflitos gigantes num PR que já é grande; ninguém consegue revisar | W0.1 é bloqueante. Sem exceção |
| **R3** | **Reescrever a config de build antes do merge.** O upstream quebrou `vite.config.ts` em 4 arquivos (§0.3) | O trabalho de W1.14/W0.4 é jogado fora no merge | Nenhuma tarefa de build antes de W0.2 |
| **R4** | **Perfil vira `if` espalhado.** Começa com um `v-if="isMarketing"` "só nesse componente" | `grep -rn "widgetProfile" app/javascript/widget/` casa em template | Regra da §B.1 + lint. O widget lê flags, nunca o nome do perfil |
| **R5** | **A leitura derivada do perfil muda comportamento de inbox existente** (`nil` → `support` resolvendo diferente do que a inbox já tem gravado) | Cliente reclama que "o chat mudou sozinho" | Aceite de W3.1 / 3.01: 16 snapshots idênticos antes e depois do deploy, na inbox sem `widget_profile`. E o corolário: perfil nunca reescreve coluna gravada |
| ~~R6~~ | ~~**Colisão de timestamp de migration** com o upstream num merge futuro~~ | — | **ELIMINADO por A1**: não há migration no perfil. O risco continua real para *outras* migrations do plano; a mitigação (`ls db/migrate \| cut -d_ -f1 \| sort \| uniq -d`, fix por `git mv`) fica registrada para quando alguma aparecer |
| **R7** | **Comemorar a compressão medindo só homologação.** [NÃO VERIFICADO] se .229/Tozi/fábrica têm o mesmo nginx | O ganho de 2,58 MB→575 KB não aparece para o cliente | W0.3 exige `curl -I` nas 4 VMs, não em uma |
| **R8** | **`widget_color` do banco interpolado em CSS.** Hoje é interpolado em JS (`show.html.erb:16`); o `<style>` de W1.2 é vetor novo | Injeção de CSS via cor de inbox | Validar `#RRGGBB` no helper Ruby, cair para o default. Item explícito no aceite de W1.2 |
| **R9** | **O teaser fora do iframe quebra em site do cliente com CSS agressivo** | Funciona no nosso host de teste, quebra no site real | `all: revert` no contêiner, tudo declarado explicitamente, prefixo `woot-`. **E testar em 3 sites reais antes da frota** |
| **R10** | **Snapshots viram ruído.** 16 snapshots que falham por antialiasing ensinam o time a ignorar o vermelho | PRs mergeados com snapshot vermelho | Fixtures determinísticas + tempo congelado (W0.5), threshold estrito só onde faz sentido |
| **R11** | **`woot.scss` é tocado além do `@import`.** É o pior arquivo do repositório: upstream +30 −4 em 5 commits **e** o fork já reescreveu 32 linhas | Conflito em todo merge, para sempre | W1.1 reduz a um `@import`. W1.7 é a **única** tarefa que edita valor lá dentro, e é remoção |
| **R12** | **`ChatInputWrap`/`ChatFooter`/`PreChat/Form` reescritos por dentro** em vez de virarem cascas | +12 −9, +37 −12 e +39 −33 de conflito em cada minor do upstream | Regra §0.4 item 2. O aceite de W2.9 mede: cascas < 60 linhas |
| **R13** | **`store/modules/conversation/` tocado por motivo visual** (agrupamento) | +51 −8 / +29 de conflito no módulo que o upstream mais mexe | W2.5 põe o agrupamento em composable novo |
| **R14** | **Divergir do upstream em `theme/colors.js` removendo a chave `brand`** | Conflito em `theme/colors.js` (+8 −0 em 2 commits) | W1.4 **acrescenta** `w-*`, não remove `brand` |
| **R15** | **O gate de peso é ligado com tetos inalcançáveis** antes das tarefas que os viabilizam | Time desliga o gate | Os 5 tetos entram um a um, cada um com a tarefa que o torna alcançável |
| **R16** | **Congelar o layout mobile sem dispositivo real.** `dvh`, `visualViewport` e `overscroll-behavior` são [NÃO VERIFICADO] em headless | Composer atrás do teclado em iPhone; painel cortado pela barra de endereço | §G.6. Teste manual obrigatório antes de fechar W2.13 |
| **R17** | **Regressão de RTL.** `App.vue:74-79` já trata `dir`; `_conversation.scss` tem ~30 pares `ltr:`/`rtl:` | Layout árabe/hebraico quebrado, sem ninguém para reclamar | Cada tarefa que toca `_conversation.scss` preserva os pares. Um snapshot em `dir="rtl"` na Onda 2 |
| **R18** | **`shared/` mexido para o widget quebra dashboard/portal/survey.** `shared/components/` é consumido pelos quatro | Regressão em tela que ninguém estava olhando | Toda tarefa 🟡 em `shared/` roda a suíte do dashboard também. Alternativa: primitivo próprio em `widget/ui/` (é o caso de `WAvatar` vs `components-next/avatar/Avatar.vue`) |
| **R19** | **Rate limit do Rack::Attack durante o suite.** Na medição do 11 §A16, `/widget` devolveu **429** pelo domínio público, por reaberturas do próprio teste | CI vermelho intermitente e inexplicável | Suite roda contra `localhost:3000`, nunca contra o domínio público |
| **R20** | **O plano trava esperando as respostas Q1–Q8** | Nenhuma linha escrita enquanto se discute 14 px vs 15 px | §0.2: cada pergunta tem default executável e ponto único de troca |

---

# O QUE NÃO VAMOS FAZER

Lista explícita. Cada linha existe para impedir que o escopo cresça em reunião — e cada uma tem o
número que sustenta a recusa.

| # | Não faremos | Por quê |
|---|---|---|
| 1 | **Migrar para Shadow DOM ou DOM direto** | O isolamento por iframe é vantagem real e medida (a Leadster precisa de **239 `!important`** para provar o contrário). O híbrido é decisão de arquitetura posterior, e este plano é compatível com ele |
| 2 | **Virtualizar a lista de mensagens** | O DOM inteiro do widget tem **74 nós** [MEDIDO — 15 §B9.3]; 50 mensagens ficam em 500–700 — irrelevante. O limiar é ~200 mensagens simultâneas, raro num chat de site. E o pré-requisito (agrupamento por dados) só vale por si, não pela virtualização |
| 3 | **Adotar webfont** | Com dois pesos, a fonte variável é **320 bytes mais pesada** que as estáticas; o ponto de virada é 3 pesos. Hoje o custo de rede já é **zero** — os 7 `.woff2` publicados nunca são baixados |
| 4 | **Liquid Glass / `backdrop-filter` atrás de texto de conversa** | A própria Apple escreve "não use Liquid Glass na camada de conteúdo". E `backdrop-filter` só entrou em Baseline "newly available" em 16/09/2024 — cedo demais para código de terceiro. Se entrar, entra atrás de `@supports`, no header ou no launcher |
| 5 | **Roxo como marcador exclusivo de IA** | Contra o azul de informação, o par colapsa para **ΔE 1,8** em deuteranopia — a mesma cor. Roxo pode ser sotaque; marcador é rótulo ou ícone |
| 6 | **Densidade compacta (14 px como default)** | É a régua de ferramenta de produtividade, para usuário treinado e sentado. O visitante é o oposto nas três dimensões. Fica como variante (`--w-text-message-sm`) |
| 7 | **Recibos "entregue" e "lido"** | Nenhum concorrente do corpus tem, e "lido e não respondido" transforma cada segundo de silêncio em irritação. Faremos `enviando`/`enviado`/`falhou` |
| 8 | **Auto-open do painel** | Toda a reclamação documentada de usuário final é contra ele; nenhuma é contra o teaser. E abrir sozinho cobrindo a tela em mobile é a descrição literal do que o Google penaliza desde 10/01/2017 |
| 9 | **Loop infinito de "chamar atenção" no launcher** | O `octaWaRadar` de 2,4 s da Octadesk vira ruído periférico em segundos e não pode ser desligado pelo visitante. O modelo certo é o da Leadster: **uma** encenação de 500 ms, uma vez, e silêncio |
| 10 | **Bloquear Lighthouse/GTmetrix por User-Agent** | O Crisp faz. Esconder o custo do widget da auditoria do cliente é enganoso, e quebraria nossos próprios testes Playwright |
| 11 | **Redesenhar `PreChat/Form.vue` por dentro** | +39 −33 só desde a nossa base, 16 commits em 36 meses. Recebe **apenas tokens**. O fluxo conversacional nasce em `widget/capture/` ⚪ |
| 12 | **Mexer em `store/modules/conversation/` por motivo visual** | +51 −8 em `actions.js`, +29 em `mutations.js` desde a base |
| 13 | **Notificação nativa do navegador e vibração** | **Zero** widgets do corpus fazem — zero `new Notification` e zero `navigator.vibrate` em todos os alvos. Pedir permissão em cima do primeiro contato é caro em confiança; o piscar do título resolve 90 % com 0 % de atrito |
| 14 | **Skeleton em toda espera** | Só acima de **600 ms**. Um skeleton que aparece e some antes de ser lido é pior que nada |
| 15 | **Gravação de áudio no composer** | O `iframe.allow` já concede `microphone` (`IFrameHelper.js:70-71`), mas é feature de produto, não de redesenho |
| 16 | **Busca no Help Center dentro do widget** | Mesma razão: é feature, não acabamento |
| 17 | **Múltiplas conversas simultâneas / inbox do visitante** | O widget hoje só conhece a última conversa. Mudar isso é produto |
| 18 | **Perfil como segundo caminho de código** | §B.1. Dobra a matriz de teste, espalha `if` pelos arquivos do campo minado e torna o híbrido impossível |
| 19 | **Migrar `MultiselectDropdown`/`MultiselectDropdownItems` por causa do widget** | Nenhum arquivo de `widget/` importa esses componentes; eles entram no CSS pelo glob do Tailwind, não por render. W1.14 resolve por build |
| 20 | **Overshoot nas curvas** | Só o Intercom usa; **todas** as outras curvas customizadas do corpus desaceleram sem passar do ponto. Overshoot num painel de 400×640 chama atenção para o contêiner em vez do conteúdo |

---

## Fecho — as sete frases que resumem o plano

**1. O caminho crítico passa pelos arquivos mais seguros do repositório.** Medi nesta task:
`show.html.erb`, `web_widget.rb`, `sdk.js`, `IFrameHelper.js`, `bubbleHelpers.js`, `ChatHeader.vue`,
`ChatSendButton.vue`, `ConversationWrap.vue`, `_conversation.scss` — **todos com zero mudanças do
upstream** entre v4.12.1 e v4.16.2. Os tokens, a cor, o perfil por inbox e o teaser cabem inteiros
nessa zona. Isso reclassifica o SDK do 🔴 que o relatório 15 lhe deu (DIVERGÊNCIA 1) e é o que torna
as Ondas 1 e 3 baratas.

**2. Duas das dívidas de peso morrem no merge, não no redesenho.** O `manualChunks` do Leaflet é do
nosso fork e não existe na v4.16.2, que reestruturou o build inteiro em quatro arquivos. Quem tentar
consertar o build antes do merge escreve duas vezes (DIVERGÊNCIAS 2 e 3).

**3. A cor não tem três pontos de correção — tem cinco famílias.** A varredura desta task achou
**25 linhas** de `n-brand`, **14** hex literais no widget e no SDK, **29 linhas** de `white`/`black`
como cor, nove pontos de `rgba()` literal e **16 arquivos** pintando por `:style` inline com uma
heurística YIQ dos anos 90 que não verifica se o resultado atinge razão alguma. O plano lista cada
um com destino declarado (§A.1), porque é a lista — não o total — que se executa.

**4. O perfil por inbox é preset, não branch.** O widget lê flags planas; o servidor resolve o
perfil. É o que impede a matriz de teste de dobrar, o `if` de se espalhar pelo campo minado e o
híbrido de virar impossível. E o corolário — perfil nunca reescreve coluna gravada — é o que garante
que a frota não sinta o deploy.

**5. Onde o mercado inteiro é fraco, é barato ganhar.** `Esc` que fecha (6 de 7 não fecham),
`prefers-reduced-motion` (6 de 7 ignoram), dark mode (1 de 4 suporta), estado de toque no launcher
(1 de 7 tem), botão "descer" com contador (não localizado em nenhum), telemetria de erro no widget
(todos os cinco medidos têm; nós não temos). Nenhum é caro. Todos são visíveis.

**6. Sem harness, não é redesenho — é aposta.** Não existe **um** teste de render de componente do
widget hoje. W0.5 e W0.6 vêm antes de tudo porque o baseline pré-merge é o que torna o merge de 113
arquivos revisável, e o baseline do perfil (antes/depois do deploy de 3.01) é o que prova que a frota
não sente o perfil.

**7. Três coisas continuam sem verificação e nenhuma é resolvível em headless:** `dvh` com barra de
endereço real, `visualViewport` com teclado virtual, e `overscroll-behavior` no Safari. Não congelar
o layout mobile antes de fechar as três em dispositivo real — 72 % dos minutos digitais no Brasil
são mobile.

---

*Documento produzido em 12/08/2026 a partir da leitura integral dos relatórios 16, 15, 12, 11 e 13
(frontend), do `DECISOES.md` e das decisões do Walisson, mais varredura própria de
`app/javascript/widget/`, `app/javascript/sdk/`, `app/javascript/shared/`, `app/views/widgets/`,
`app/models/channel/`, `theme/`, `tailwind.config.js`, `vite.config.ts`, `package.json` e do
histórico do upstream entre `v4.12.1` e `v4.16.2`. **Nenhum arquivo de código foi alterado.** Onde
nada foi verificado, está escrito "não verificado".*

---

## Correções aplicadas em 12/08/2026 (pós-auditoria)

Edição cirúrgica para propagar as arbitragens do `PLANO-MESTRE.md` §5 (bloqueador **B1** do
`auditoria/35-VEREDITO.md`). **Nada foi reescrito além dos pontos contraditos**, e onde o texto
antigo mandava fazer o contrário da decisão, ele **saiu** — não ficou como alternativa.

| Onde (linha atual) | O que mudou | Origem |
|---|---|---|
| `:206` | `theme/colors.js:123` → **`:227`**, e registrado que o arquivo fica na **raiz** do repositório. Conferido no HEAD `ee87f5e799`: `:227` é `brand: '#2dc46f'`; `:123` é `2: 'rgb(var(--iris-2) / <alpha-value>)'` | `auditoria/31-planos.md` A-16 (a única referência errada em 46) |
| `:551` | Corolário da §B.1 ganha os **três regimes** (inbox nova semeia · inbox existente **propõe** com diálogo de confirmação · campos novos resolvem em runtime) | §5 **A3** |
| `:562` — §B.2 inteira | **A recomendação virou `inbox.additional_attributes` com três chaves de topo.** Caíram: `add_column`, o `enum` no canal, a entrada em `EDITABLE_ATTRS` e o risco de colisão de timestamp. A coluna passou a linha **rejeitada** da tabela de opções, com o motivo | §5 **A1**, **A2** |
| `:636` — §B.3 | A lista de 11 flags de `profileConfig` foi declarada **LISTA CANÔNICA** (é o único lugar onde as flags são definidas; 23, 24 e o bloco 3.03 do mestre apontam para cá), com tabela de tipo/valores e a regra de precedência (valor gravado vence o perfil) | `auditoria/31-planos.md` §6 itens 1 e 2 · §5 **A3** |
| `:709` — §B.5 | "Toda inbox vira `support` no instante da migration" → **`nil` é lido como `support`, sem migration e sem backfill**; o aceite dos 16 snapshots passa a valer sobre a **leitura derivada**, e o aceite 4 passa pelo diálogo do regime 2 | §5 **A1**, **A4** |
| `:1589` — tarefa **W3.1** | Vira o bloco **3.01**: `inbox.rb:50` + `inboxes_controller.rb:217` numa **edição única**, valores em inglês, sem `add_column`; aceite reescrito | §5 **A1**, **A2**, **A4** |
| `:1590` — tarefa **W3.2** | `WidgetProfile.resolve` devolve **as 11 flags da lista canônica** | §5 **A3** |
| `:1718` | "Baseline pré-migration" → **baseline do perfil** (antes/depois do deploy de 3.01) | §5 **A1** |
| `:1765` — riscos | **R5** reescrito (é a leitura derivada que precisa ser inócua, não a migration); **R6** (colisão de timestamp) **eliminado por A1**, com a mitigação preservada para outras migrations | §5 **A1** |
| `:1846` | "baseline pré-migration" → baseline do perfil | §5 **A1** |

**Verificações próprias feitas nesta correção** (leitura, sem escrita, HEAD `ee87f5e799`):
`theme/colors.js:227` = `brand: '#2dc46f'`; `app/models/inbox.rb:50` tem o `store_accessor`;
`app/controllers/api/v1/accounts/inboxes_controller.rb:217` é a linha do `permit` de
`additional_attributes` e `:52-56` é o merge **raso**; `_inbox.json.jbuilder:27` devolve
`additional_attributes` inteiro; `Gemfile:37` tem `json_schemer`; `show.html.erb` usa
`@web_widget.inbox` em **12** ocorrências.

